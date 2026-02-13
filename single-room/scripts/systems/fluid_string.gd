class_name FluidString
extends Node3D
## Renders a viscous string (saliva thread, semen strand) between two
## separating points. The string thins as it stretches and breaks when
## it exceeds the fluid's string_max_length.
##
## Uses ImmediateMesh with a translucent material for a thin cylindrical
## thread that updates each physics frame.

signal string_broke(fluid_name: String)

# ── Tuning ───────────────────────────────────────────────────────────────────

@export_group("Appearance")
## Base radius of the string at zero stretch.
@export_range(0.0005, 0.01) var base_radius: float = 0.002
## Minimum radius before visual cutoff.
@export_range(0.0001, 0.005) var min_radius: float = 0.0004
## How many segments along the string length (more = smoother curve).
@export_range(2, 12) var segments: int = 6
## Sag amount — how much the string droops in the middle under gravity.
@export_range(0.0, 0.1) var sag_strength: float = 0.03

# ── Runtime ──────────────────────────────────────────────────────────────────

var _fluid_type: FluidType = null
var _point_a: Node3D = null
var _point_b: Node3D = null
var _mesh_instance: MeshInstance3D = null
var _immediate_mesh: ImmediateMesh = null
var _material: StandardMaterial3D = null
var _active: bool = false
var _max_length: float = 0.15


func _ready() -> void:
	_build_mesh()
	set_physics_process(false)


## Start rendering a string between two points.
func start_string(point_a: Node3D, point_b: Node3D, fluid: FluidType) -> void:
	_point_a = point_a
	_point_b = point_b
	_fluid_type = fluid
	_max_length = fluid.string_max_length if fluid.string_max_length > 0.0 else 0.15
	_active = true

	# Material from fluid
	_material.albedo_color = Color(
		fluid.color.r, fluid.color.g, fluid.color.b, fluid.opacity * 0.8)
	_material.metallic = fluid.metallic
	_material.roughness = fluid.roughness

	_mesh_instance.visible = true
	set_physics_process(true)


## Immediately break and hide the string.
func break_string() -> void:
	if not _active:
		return
	_active = false
	_mesh_instance.visible = false
	set_physics_process(false)
	if _fluid_type != null:
		string_broke.emit(_fluid_type.fluid_name)
	_point_a = null
	_point_b = null
	_fluid_type = null


func is_active() -> bool:
	return _active


func _physics_process(_delta: float) -> void:
	if not _active:
		return

	if not is_instance_valid(_point_a) or not is_instance_valid(_point_b):
		break_string()
		return

	var pos_a: Vector3 = _point_a.global_position
	var pos_b: Vector3 = _point_b.global_position
	var dist: float = pos_a.distance_to(pos_b)

	# Break check
	if dist > _max_length:
		break_string()
		return

	# Stretch factor (0 = touching, 1 = at max length)
	var stretch: float = dist / _max_length

	# Radius thins with stretch
	var radius: float = lerpf(base_radius, min_radius, stretch * stretch)

	# Rebuild the tube mesh each frame
	_rebuild_tube(pos_a, pos_b, radius, stretch)


## Build the MeshInstance3D + ImmediateMesh + Material once.
func _build_mesh() -> void:
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "StringMesh"
	_immediate_mesh = ImmediateMesh.new()
	_mesh_instance.mesh = _immediate_mesh

	_material = StandardMaterial3D.new()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	_material.albedo_color = Color(1.0, 1.0, 1.0, 0.6)
	_mesh_instance.material_override = _material

	_mesh_instance.visible = false
	add_child(_mesh_instance)


## Rebuild the tube geometry between two world-space points.
## Uses TRIANGLE_STRIP with interleaved ring vertices for correct winding.
func _rebuild_tube(pos_a: Vector3, pos_b: Vector3,
		radius: float, stretch: float) -> void:
	_immediate_mesh.clear_surfaces()

	var direction: Vector3 = pos_b - pos_a
	var length: float = direction.length()
	if length < 0.001:
		return

	var forward: Vector3 = direction / length
	# Find a perpendicular axis
	var up: Vector3 = Vector3.UP
	if absf(forward.dot(up)) > 0.99:
		up = Vector3.RIGHT
	var right_axis: Vector3 = forward.cross(up).normalized()
	var up_axis: Vector3 = right_axis.cross(forward).normalized()

	var ring_verts: int = 4  # Quad cross-section (cheap)

	# Pre-compute ring centres and radii for each segment
	var centres: Array[Vector3] = []
	var radii: Array[float] = []
	for seg_i: int in range(segments + 1):
		var t: float = float(seg_i) / float(segments)
		var along: Vector3 = pos_a.lerp(pos_b, t)
		var sag_t: float = 4.0 * t * (1.0 - t)
		along.y -= sag_strength * sag_t * (1.0 + stretch)
		var taper: float = 1.0 - 0.3 * sag_t * stretch
		centres.append(along)
		radii.append(radius * taper)

	# Emit one triangle strip per pair of adjacent rings.
	# Vertices alternate: ring_A[i], ring_B[i], ring_A[i+1], ring_B[i+1], ...
	for seg_i: int in range(segments):
		_immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		var c_a: Vector3 = centres[seg_i]
		var c_b: Vector3 = centres[seg_i + 1]
		var r_a: float = radii[seg_i]
		var r_b: float = radii[seg_i + 1]

		for ring_i: int in range(ring_verts + 1):
			var angle: float = float(ring_i % ring_verts) / float(ring_verts) * TAU
			var dir_offset: Vector3 = right_axis * cos(angle) + up_axis * sin(angle)
			var normal: Vector3 = dir_offset.normalized()

			# Vertex on ring A
			var vert_a: Vector3 = c_a + dir_offset * r_a
			_immediate_mesh.surface_set_normal(normal)
			_immediate_mesh.surface_add_vertex(vert_a)

			# Vertex on ring B
			var vert_b: Vector3 = c_b + dir_offset * r_b
			_immediate_mesh.surface_set_normal(normal)
			_immediate_mesh.surface_add_vertex(vert_b)

		_immediate_mesh.surface_end()
