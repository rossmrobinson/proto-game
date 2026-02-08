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

# ── Runtime ──────────────────────────────────────────────────────────────────
var _particles: GPUParticles3D = null
var _process_mat: ParticleProcessMaterial = null
var _draw_pass: QuadMesh = null
var _is_emitting: bool = false


func _ready() -> void:
	if fluid_type == null and auto_start:
		push_error("[BodyFluidEmitter] No fluid_type assigned.")
		return
	_build_particle_system()
	if auto_start and fluid_type != null:
		start_emitting()


## Begin continuous emission.
func start_emitting() -> void:
	if fluid_type == null or _particles == null:
		return
	_configure_from_fluid()
	_particles.emitting = true
	_is_emitting = true
	emission_started.emit(fluid_type.fluid_name)


## Stop continuous emission (existing particles finish their lifetime).
func stop_emitting() -> void:
	if _particles == null:
		return
	_particles.emitting = false
	_is_emitting = false
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
	if fluid_type != null:
		emission_started.emit(fluid_type.fluid_name)


## Change the fluid type at runtime.
func set_fluid(new_fluid: FluidType) -> void:
	fluid_type = new_fluid
	if _is_emitting:
		_configure_from_fluid()


func is_emitting() -> bool:
	return _is_emitting


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

	# Material appearance
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = ft.color
	mat.metallic = ft.metallic
	mat.roughness = ft.roughness
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	if ft.emission_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = ft.color
		mat.emission_energy_multiplier = ft.emission_energy
	_particles.material_override = mat

	# Direction
	var dir: Vector3 = emission_direction.normalized()
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
	# Fade out toward end of life
	var color_ramp: GradientTexture1D = GradientTexture1D.new()
	var grad: Gradient = Gradient.new()
	grad.set_color(0, ft.color)
	grad.add_point(0.7, ft.color)
	grad.add_point(1.0, Color(ft.color_secondary.r, ft.color_secondary.g,
		ft.color_secondary.b, 0.0))
	color_ramp.gradient = grad
	_process_mat.color_ramp = color_ramp
