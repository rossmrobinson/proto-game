class_name FluidSurface
extends Node
## Manages fluid patches on external body surfaces (face, chest, thighs, etc.).
##
## Each patch is a Decal3D that moves with the body part it landed on,
## flows downward under gravity, fades/dries over time, and can merge with
## neighbouring patches when they overlap.

signal patch_created(body_part: String, fluid_name: String)
signal patch_dried(body_part: String, fluid_name: String)

# ── Tuning ───────────────────────────────────────────────────────────────────

@export_group("Patches")
## Maximum simultaneous patches per NPC.
@export var max_patches: int = 32
## Base decal size (metres) per mL of fluid.
@export var size_per_ml: float = 0.015
## Minimum decal size.
@export var min_patch_size: float = 0.01
## Maximum decal size (prevents absurdly large splatters).
@export var max_patch_size: float = 0.12

@export_group("Flow")
## How fast fluid flows down the body surface (m/s at gravity_factor = 1).
@export var flow_speed: float = 0.02
## Minimum gravity alignment to flow (0 = any tilt, 1 = only straight down).
@export_range(0.0, 1.0) var flow_threshold: float = 0.15
## Viscous fluids flow slower. This multiplies (1 - viscosity) into flow speed.
@export var viscosity_flow_damping: float = 0.8

@export_group("Drying")
## Global multiplier on FluidType.dry_rate.
@export var dry_rate_multiplier: float = 1.0
## Once opacity falls below this, the patch is removed.
@export_range(0.0, 0.2) var remove_opacity: float = 0.05

# ── Runtime ──────────────────────────────────────────────────────────────────

## All active patches.
var _patches: Array[FluidPatch] = []

## Pool of recycled Decal3D nodes.
var _decal_pool: Array[Decal] = []


## Inner data class for a single fluid patch on the body.
class FluidPatch:
	var decal: Decal
	var body_part: RigidBody3D
	var body_part_name: String
	var fluid_type: FluidType
	var volume: float  ## mL
	var opacity: float
	var local_offset: Vector3  ## offset in body-part-local space
	var age: float


func _ready() -> void:
	set_physics_process(false)


## Call after NPC is built to enable processing.
func activate() -> void:
	set_physics_process(true)


## Place a new fluid patch on a body part surface.
func add_patch(body_part: RigidBody3D, part_name: String,
		world_hit: Vector3, fluid: FluidType, volume: float) -> void:
	if _patches.size() >= max_patches:
		_recycle_oldest()

	var decal: Decal = _acquire_decal()
	var patch_size: float = clampf(size_per_ml * volume, min_patch_size, max_patch_size)

	decal.size = Vector3(patch_size, 0.1, patch_size)
	decal.modulate = Color(fluid.color.r, fluid.color.g, fluid.color.b, fluid.opacity)
	# Project onto body part surface
	decal.global_position = world_hit
	decal.global_transform = _orient_to_surface(body_part, world_hit)

	var local_pos: Vector3 = body_part.global_transform.affine_inverse() * world_hit

	var patch: FluidPatch = FluidPatch.new()
	patch.decal = decal
	patch.body_part = body_part
	patch.body_part_name = part_name
	patch.fluid_type = fluid
	patch.volume = volume
	patch.opacity = fluid.opacity
	patch.local_offset = local_pos
	patch.age = 0.0
	_patches.append(patch)

	patch_created.emit(part_name, fluid.fluid_name)


func _physics_process(delta: float) -> void:
	var removal_set: Dictionary = {}  # int → bool — dedup indices

	for i: int in range(_patches.size()):
		var patch: FluidPatch = _patches[i]
		if not is_instance_valid(patch.body_part):
			removal_set[i] = true
			continue

		patch.age += delta

		# Move decal with body part
		var world_pos: Vector3 = patch.body_part.global_transform * patch.local_offset
		patch.decal.global_position = world_pos

		# Gravity flow — slide downward along body surface
		_apply_flow(patch, delta)

		# Drying
		var dry_amount: float = patch.fluid_type.dry_rate * dry_rate_multiplier * delta
		patch.opacity = maxf(patch.opacity - dry_amount, 0.0)
		patch.decal.modulate.a = patch.opacity

		# Shrink as it dries
		var size_factor: float = patch.opacity / maxf(patch.fluid_type.opacity, 0.01)
		var base_size: float = clampf(size_per_ml * patch.volume, min_patch_size, max_patch_size)
		var current_size: float = base_size * clampf(size_factor, 0.3, 1.0)
		patch.decal.size = Vector3(current_size, 0.1, current_size)

		if patch.opacity <= remove_opacity:
			removal_set[i] = true

	# Remove dried / invalid patches (reverse order to preserve indices)
	var to_remove: Array[int] = []
	for idx: int in removal_set:
		to_remove.append(idx)
	to_remove.sort()
	to_remove.reverse()
	for idx: int in to_remove:
		_remove_patch(idx)


## Slide the patch downward along the body surface under gravity.
func _apply_flow(patch: FluidPatch, delta: float) -> void:
	if patch.fluid_type.viscosity >= 0.95:
		return  # Too thick to flow

	# World-space down projected onto body-part surface
	var body_up: Vector3 = patch.body_part.global_transform.basis.y.normalized()
	var gravity_on_surface: Vector3 = Vector3.DOWN - body_up * Vector3.DOWN.dot(body_up)

	if gravity_on_surface.length_squared() < flow_threshold * flow_threshold:
		return

	var speed: float = flow_speed * (1.0 - patch.fluid_type.viscosity * viscosity_flow_damping)
	var world_delta: Vector3 = gravity_on_surface.normalized() * speed * delta

	# Update local offset
	var new_world: Vector3 = (patch.body_part.global_transform * patch.local_offset) + world_delta
	patch.local_offset = patch.body_part.global_transform.affine_inverse() * new_world


## Orient decal to project onto the body part surface from the outside.
func _orient_to_surface(body_part: RigidBody3D, world_pos: Vector3) -> Transform3D:
	var body_centre: Vector3 = body_part.global_position
	var outward_raw: Vector3 = world_pos - body_centre
	var outward: Vector3
	if outward_raw.length_squared() < 0.0001:
		outward = Vector3.UP
	else:
		outward = outward_raw.normalized()
	# Build a transform where Y points outward from body
	var up: Vector3 = outward
	var forward: Vector3 = up.cross(Vector3.RIGHT).normalized()
	if forward.length_squared() < 0.001:
		forward = up.cross(Vector3.FORWARD).normalized()
	var right: Vector3 = forward.cross(up).normalized()
	var xform: Transform3D = Transform3D(Basis(right, up, forward), world_pos)
	return xform


## Get or create a Decal3D from the pool.
func _acquire_decal() -> Decal:
	if not _decal_pool.is_empty():
		var pooled_decal: Decal = _decal_pool.pop_back()
		pooled_decal.visible = true
		return pooled_decal

	var new_decal: Decal = Decal.new()
	new_decal.name = "FluidPatch_%d" % _patches.size()
	# Decals project on all cull mask layers that include NPC_External (layer 3)
	new_decal.cull_mask = 1 << 2  # Layer 3 (0-indexed bit 2)
	add_child(new_decal)
	return new_decal


## Return a decal to the pool instead of freeing it.
func _release_decal(decal: Decal) -> void:
	decal.visible = false
	_decal_pool.append(decal)


## Remove a patch by index and release its decal.
func _remove_patch(index: int) -> void:
	var patch: FluidPatch = _patches[index]
	patch_dried.emit(patch.body_part_name, patch.fluid_type.fluid_name)
	_release_decal(patch.decal)
	_patches.remove_at(index)


## Recycle the oldest patch when at capacity.
func _recycle_oldest() -> void:
	if _patches.is_empty():
		return
	_remove_patch(0)


## Remove all patches (cleanup).
func clear_all() -> void:
	for i: int in range(_patches.size() - 1, -1, -1):
		_remove_patch(i)


## Diagnostic: how many patches are active.
func get_patch_count() -> int:
	return _patches.size()
