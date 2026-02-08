class_name TargetingSystem
extends Node3D
## Screen-center body-part targeting with optional crosshair and highlight.
## Supersedes InteractionSystem with smarter proximity-based aim-assist.
## Attach as a child of PlayerController.

signal target_changed(new_target: BodyPart, old_target: BodyPart)
signal target_lost()

@export_group("Targeting")
@export var max_distance: float = 4.0
## Cone half-angle (degrees) for soft aim-assist when raycast misses.
@export_range(1.0, 30.0) var aim_assist_cone_deg: float = 15.0

@export_group("Crosshair")
@export var show_crosshair: bool = false
@export var crosshair_color: Color = Color(1.0, 1.0, 1.0, 0.5)
@export_range(4.0, 30.0) var crosshair_size: float = 12.0
@export_range(1.0, 10.0) var crosshair_gap: float = 4.0
@export_range(0.5, 4.0) var crosshair_thickness: float = 1.5

@export_group("Highlight")
@export var show_highlight: bool = false
@export var highlight_color: Color = Color(1.0, 1.0, 1.0, 0.15)

# ── State ────────────────────────────────────────────────────────────────────
var current_target: BodyPart = null
## World-space hit point of the last successful target acquisition.
var target_hit_point: Vector3 = Vector3.ZERO

@onready var _player: PlayerController = get_parent() as PlayerController
var _crosshair_layer: CanvasLayer = null
var _crosshair_draw: Control = null
var _highlighted_part: BodyPart = null
var _original_material: Material = null


func _ready() -> void:
	if show_crosshair:
		_create_crosshair()


func _physics_process(_delta: float) -> void:
	_update_target()
	_update_highlight()


## Toggle crosshair on/off.
func toggle_crosshair() -> void:
	show_crosshair = not show_crosshair
	if show_crosshair and _crosshair_layer == null:
		_create_crosshair()
	elif not show_crosshair and _crosshair_layer != null:
		_destroy_crosshair()


## Toggle body-part highlight on/off.
func toggle_highlight() -> void:
	show_highlight = not show_highlight
	if not show_highlight:
		_clear_highlight()


# ── Targeting Logic ──────────────────────────────────────────────────────────

func _update_target() -> void:
	var camera: Camera3D = _player.get_active_camera()
	if camera == null:
		return

	var origin: Vector3 = camera.global_position
	var direction: Vector3 = -camera.global_basis.z
	var best: BodyPart = null
	var best_point: Vector3 = Vector3.ZERO

	# Primary: direct physics raycast from screen center
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var ray_end: Vector3 = origin + direction * max_distance
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		origin, ray_end)
	query.collision_mask = 4 | 8  # layer 3 (NPC) + layer 4 (Interactable)
	query.collide_with_bodies = true

	var result: Dictionary = space.intersect_ray(query)
	if not result.is_empty():
		var collider: Object = result["collider"]
		if collider is BodyPart:
			best = collider as BodyPart
			best_point = result["position"] as Vector3

	# Fallback: soft aim-assist — find nearest body part inside aim cone
	if best == null:
		var cone_result: Array = _find_nearest_in_cone(origin, direction)
		if cone_result.size() == 2:
			best = cone_result[0] as BodyPart
			best_point = cone_result[1] as Vector3

	# Update state
	if best != current_target:
		var old: BodyPart = current_target
		current_target = best
		target_hit_point = best_point
		if best != null:
			target_changed.emit(best, old)
		else:
			target_lost.emit()
	elif best != null:
		target_hit_point = best_point


func _find_nearest_in_cone(origin: Vector3, direction: Vector3) -> Array:
	var parts: Array[Node] = get_tree().get_nodes_in_group(&"body_part")
	var best_dot: float = -1.0
	var best_part: BodyPart = null
	var cone_cos: float = cos(deg_to_rad(aim_assist_cone_deg))

	for node: Node in parts:
		if node is not BodyPart:
			continue
		var part: BodyPart = node as BodyPart
		var to_part: Vector3 = part.global_position - origin
		var dist: float = to_part.length()
		if dist > max_distance or dist < 0.1:
			continue
		var dot: float = to_part.normalized().dot(direction)
		if dot < cone_cos:
			continue
		if dot > best_dot:
			best_dot = dot
			best_part = part

	if best_part != null:
		return [best_part, best_part.global_position]
	return []


# ── Highlight ────────────────────────────────────────────────────────────────

func _update_highlight() -> void:
	if not show_highlight:
		return

	if current_target != _highlighted_part:
		_clear_highlight()
		if current_target != null:
			_apply_highlight(current_target)


func _apply_highlight(part: BodyPart) -> void:
	# Find a MeshInstance3D child to tint
	for child: Node in part.get_children():
		if child is MeshInstance3D:
			var mesh_inst: MeshInstance3D = child as MeshInstance3D
			_original_material = mesh_inst.material_override
			var tint: StandardMaterial3D = StandardMaterial3D.new()
			tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			tint.albedo_color = highlight_color
			tint.emission_enabled = true
			tint.emission = highlight_color
			tint.emission_energy_multiplier = 0.4
			# Apply as overlay (next_pass) so it layers on existing material
			if mesh_inst.material_override != null:
				tint.next_pass = null
			mesh_inst.material_overlay = tint
			_highlighted_part = part
			return
	_highlighted_part = part  # Track even without mesh for state consistency


func _clear_highlight() -> void:
	if _highlighted_part != null and is_instance_valid(_highlighted_part):
		for child: Node in _highlighted_part.get_children():
			if child is MeshInstance3D:
				var mesh_inst: MeshInstance3D = child as MeshInstance3D
				mesh_inst.material_overlay = null
	_highlighted_part = null
	_original_material = null


# ── Crosshair ────────────────────────────────────────────────────────────────

func _create_crosshair() -> void:
	_crosshair_layer = CanvasLayer.new()
	_crosshair_layer.name = "CrosshairLayer"
	_crosshair_layer.layer = 10
	add_child(_crosshair_layer)

	_crosshair_draw = _CrosshairDraw.new()
	_crosshair_draw.name = "CrosshairDraw"
	_crosshair_draw.targeting = self
	_crosshair_layer.add_child(_crosshair_draw)


func _destroy_crosshair() -> void:
	if _crosshair_layer != null:
		_crosshair_layer.queue_free()
		_crosshair_layer = null
		_crosshair_draw = null


# ── Inner Crosshair Drawer ──────────────────────────────────────────────────

class _CrosshairDraw extends Control:
	var targeting: TargetingSystem = null

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if targeting == null or not targeting.show_crosshair:
			return
		var center: Vector2 = size / 2.0
		var gap: float = targeting.crosshair_gap
		var arm: float = targeting.crosshair_size
		var thick: float = targeting.crosshair_thickness
		var col: Color = targeting.crosshair_color

		# Tint crosshair when a target is acquired
		if targeting.current_target != null:
			col = Color(0.3, 1.0, 0.3, col.a)

		# Four lines forming a gapped cross
		draw_line(center + Vector2(-arm, 0), center + Vector2(-gap, 0), col, thick)
		draw_line(center + Vector2(gap, 0), center + Vector2(arm, 0), col, thick)
		draw_line(center + Vector2(0, -arm), center + Vector2(0, -gap), col, thick)
		draw_line(center + Vector2(0, gap), center + Vector2(0, arm), col, thick)
