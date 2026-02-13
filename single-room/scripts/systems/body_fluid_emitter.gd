class_name BodyFluidEmitter
extends Node3D
## Emits bodily fluids as GPU particles attached to a BodyPart or world point.
## Handles stream, drip, splatter, and pooling behaviors.
##
## Attach to a BodyPart or place in the scene. Set the fluid_type and call
## start_emitting() / stop_emitting(), or use one-shot methods for splatters.

signal emission_started(fluid_name: String)
signal emission_stopped(fluid_name: String)
signal fluid_hit_surface(fluid_name: String, hit_point: Vector3, hit_normal: Vector3)

@export var fluid_type: FluidType
@export var auto_start: bool = false

@export_group("Emission")
## Particles per second during continuous emission.
@export var emission_rate: float = 30.0
## Direction of emission in local space (normalized automatically).
@export var emission_direction: Vector3 = Vector3.DOWN
## Override emission speed from fluid_type. 0 = use fluid default.
@export_range(0.0, 10.0) var speed_override: float = 0.0

@export_group("Interior Origin")
## When true, particles spawn inside the body and travel outward so
## they appear to emerge from the surface rather than popping into existence.
@export var interior_origin: bool = false
## The body part whose centre is used as the origin for interior emission.
## Emission direction is computed from this body toward the emitter position.
@export var origin_body: RigidBody3D = null
## How far inside the body part the spawn point sits (metres).
@export_range(0.0, 0.15) var interior_depth: float = 0.04

# ── Runtime ──────────────────────────────────────────────────────────────────
var _particles: GPUParticles3D = null
var _process_mat: ParticleProcessMaterial = null
var _draw_pass: QuadMesh = null
var _material: StandardMaterial3D = null
var _color_ramp: GradientTexture1D = null
var _gradient: Gradient = null
var _is_emitting: bool = false
var _is_burst: bool = false


func _ready() -> void:
	if fluid_type == null and auto_start:
		push_error("[BodyFluidEmitter] No fluid_type assigned.")
		return
	_build_particle_system()
	if auto_start and fluid_type != null:
		start_emitting()
	set_physics_process(false)


## Begin continuous emission.
func start_emitting() -> void:
	if fluid_type == null or _particles == null:
		return
	_configure_from_fluid()
	_particles.emitting = true
	_is_emitting = true
	set_physics_process(interior_origin and origin_body != null)
	emission_started.emit(fluid_type.fluid_name)


## Stop continuous emission (existing particles finish their lifetime).
func stop_emitting() -> void:
	if _particles == null:
		return
	_particles.emitting = false
	_is_emitting = false
	set_physics_process(false)
	if fluid_type != null:
		emission_stopped.emit(fluid_type.fluid_name)


## Emit a one-shot burst (e.g., sneeze, splash, splatter).
func emit_burst(count: int = 20) -> void:
	if fluid_type == null or _particles == null:
		return
	_configure_from_fluid()
	_particles.amount = count
	_particles.one_shot = true
	_particles.emitting = true
	_is_emitting = true
	_is_burst = true
	set_physics_process(interior_origin and origin_body != null)
	emission_started.emit(fluid_type.fluid_name)
	# Auto-stop after burst lifetime
	var lifetime: float = _particles.lifetime
	get_tree().create_timer(lifetime).timeout.connect(_on_burst_finished)


## Change the fluid type at runtime.
func set_fluid(new_fluid: FluidType) -> void:
	fluid_type = new_fluid
	if _is_emitting:
		_configure_from_fluid()


func is_emitting() -> bool:
	return _is_emitting


func report_surface_hit(hit_point: Vector3, hit_normal: Vector3) -> void:
	if fluid_type == null:
		return
	fluid_hit_surface.emit(fluid_type.fluid_name, hit_point, hit_normal)


## Called when a one-shot burst finishes its particle lifetime.
func _on_burst_finished() -> void:
	if _is_burst:
		_is_burst = false
		_is_emitting = false
		set_physics_process(false)
		if fluid_type != null:
			emission_stopped.emit(fluid_type.fluid_name)


## When interior_origin is active, update spawn point to stay inside the
## tracked body part so particles always appear to emerge from within.
func _physics_process(_delta: float) -> void:
	if origin_body == null or _particles == null:
		return
	# Point from body centre toward emitter → that is the outward direction
	var body_pos: Vector3 = origin_body.global_position
	var emitter_pos: Vector3 = global_position
	var outward: Vector3 = (emitter_pos - body_pos).normalized()
	# Place particle system inside the body, offset inward from emitter pos
	_particles.global_position = emitter_pos - outward * interior_depth
	# Update emission direction to point outward
	_process_mat.direction = global_transform.basis.inverse() * outward


func _build_particle_system() -> void:
	_particles = GPUParticles3D.new()
	_particles.name = "FluidParticles"

	# Process material (physics/movement)
	_process_mat = ParticleProcessMaterial.new()
	_particles.process_material = _process_mat

	# Draw pass — small sphere for each droplet
	_draw_pass = QuadMesh.new()
	_draw_pass.size = Vector2(0.01, 0.01)
	_particles.draw_pass_1 = _draw_pass

	_particles.emitting = false
	_particles.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))
	add_child(_particles)

	# Pre-create reusable material and gradient
	_material = StandardMaterial3D.new()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_particles.material_override = _material

	_gradient = Gradient.new()
	_color_ramp = GradientTexture1D.new()
	_color_ramp.gradient = _gradient


func _configure_from_fluid() -> void:
	if fluid_type == null or _process_mat == null:
		return

	var ft: FluidType = fluid_type

	# Particle count & lifetime
	_particles.amount = ceili(emission_rate * ft.lifetime)
	_particles.lifetime = ft.lifetime
	_particles.one_shot = false

	# Visual size
	var radius: float = ft.particle_radius
	_draw_pass.size = Vector2(radius * 2.0, radius * 2.0)

	# Material appearance (reuse cached material)
	_material.albedo_color = ft.color
	_material.metallic = ft.metallic
	_material.roughness = ft.roughness
	if ft.emission_energy > 0.0:
		_material.emission_enabled = true
		_material.emission = ft.color
		_material.emission_energy_multiplier = ft.emission_energy
	else:
		_material.emission_enabled = false

	# Direction
	var dir: Vector3 = emission_direction.normalized()
	if interior_origin and origin_body != null:
		var outward: Vector3 = (global_position - origin_body.global_position).normalized()
		dir = global_transform.basis.inverse() * outward
		# Move particle system inside body
		_particles.global_position = global_position - outward * interior_depth
	_process_mat.direction = dir
	_process_mat.spread = ft.spread_angle

	# Speed
	var spd: float = speed_override if speed_override > 0.0 else ft.emission_speed
	_process_mat.initial_velocity_min = spd * 0.7
	_process_mat.initial_velocity_max = spd * 1.3

	# Gravity — use viscosity to slow fall for thick fluids
	var grav_y: float = -9.8 * ft.gravity_scale * (1.0 - ft.viscosity * 0.5)
	_process_mat.gravity = Vector3(0.0, grav_y, 0.0)

	# Damping (viscosity -> drag)
	_process_mat.damping_min = ft.viscosity * 8.0
	_process_mat.damping_max = ft.viscosity * 12.0

	# Scale fade for drying effect
	_process_mat.scale_min = 0.8
	_process_mat.scale_max = 1.2
	# Fade out toward end of life (reuse cached gradient)
	_gradient.remove_point(0)
	while _gradient.get_point_count() > 0:
		_gradient.remove_point(0)
	_gradient.add_point(0.0, ft.color)
	_gradient.add_point(0.7, ft.color)
	_gradient.add_point(1.0, Color(ft.color_secondary.r, ft.color_secondary.g,
		ft.color_secondary.b, 0.0))
	_process_mat.color_ramp = _color_ramp
