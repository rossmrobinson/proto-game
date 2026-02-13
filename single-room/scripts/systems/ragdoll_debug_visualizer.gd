class_name RagdollDebugVisualizer
extends RefCounted
## Owns the debug-line mesh, 3-D labels, and collision-mesh visibility
## toggling for the ragdoll diagnostics system.
##
## Constructed once by RagdollDiagnostics, receives snapshots/config per frame.

var _parent: Node = null
var _line_mesh: ImmediateMesh = null
var _line_instance: MeshInstance3D = null
var _line_material: StandardMaterial3D = null
var _labels: Dictionary = {}


func _init(parent: Node) -> void:
	_parent = parent


## ── Setup ───────────────────────────────────────────────────────────────────

func setup() -> void:
	_line_mesh = ImmediateMesh.new()
	_line_instance = MeshInstance3D.new()
	_line_instance.name = "RagdollDebugLines"
	_line_instance.mesh = _line_mesh
	_line_material = StandardMaterial3D.new()
	_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_material.vertex_color_use_as_albedo = true
	_line_instance.material_override = _line_material
	_parent.add_child(_line_instance)


## ── Line drawing ────────────────────────────────────────────────────────────

func clear_lines() -> void:
	if _line_mesh != null:
		_line_mesh.clear_surfaces()


func update_lines(snapshots: Dictionary, config: RagdollDebugConfig) -> void:
	if _line_mesh == null:
		return

	_line_mesh.clear_surfaces()
	_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	if config.show_offset_lines:
		var color_ok: Color = Color(0.2, 0.8, 1.0, 0.9)
		var color_bad: Color = Color(1.0, 0.3, 0.2, 0.9)
		for npc_name: String in snapshots:
			var snap: Dictionary = snapshots[npc_name] as Dictionary
			var parts: Array = snap.get("parts", []) as Array
			for entry: Dictionary in parts:
				var part_ref: Variant = entry.get("part", null)
				if part_ref == null or not is_instance_valid(part_ref):
					continue
				var part: BodyPart = part_ref as BodyPart
				if part == null:
					continue
				var target_pos: Vector3 = entry["target_pos"] as Vector3
				var offset: float = float(entry["offset"])
				var color: Color = color_bad if offset > config.max_offset else color_ok
				_line_mesh.surface_set_color(color)
				_line_mesh.surface_add_vertex(target_pos)
				_line_mesh.surface_set_color(color)
				_line_mesh.surface_add_vertex(part.global_position)

	if config.show_joint_axes:
		var axis_len: float = config.axis_length
		var axes_drawn: int = 0
		var joints: Array = _parent.get_tree().get_nodes_in_group(&"ragdoll_joint")
		for node: Node in joints:
			if axes_drawn >= config.max_joint_axes:
				break
			var joint: Generic6DOFJoint3D = node as Generic6DOFJoint3D
			if joint == null:
				continue
			var origin: Vector3 = joint.global_transform.origin
			var basis: Basis = joint.global_transform.basis
			_line_mesh.surface_set_color(Color(1.0, 0.2, 0.2, 0.9))
			_line_mesh.surface_add_vertex(origin)
			_line_mesh.surface_set_color(Color(1.0, 0.2, 0.2, 0.9))
			_line_mesh.surface_add_vertex(origin + basis.x * axis_len)

			_line_mesh.surface_set_color(Color(0.2, 1.0, 0.2, 0.9))
			_line_mesh.surface_add_vertex(origin)
			_line_mesh.surface_set_color(Color(0.2, 1.0, 0.2, 0.9))
			_line_mesh.surface_add_vertex(origin + basis.y * axis_len)

			_line_mesh.surface_set_color(Color(0.2, 0.4, 1.0, 0.9))
			_line_mesh.surface_add_vertex(origin)
			_line_mesh.surface_set_color(Color(0.2, 0.4, 1.0, 0.9))
			_line_mesh.surface_add_vertex(origin + basis.z * axis_len)

			axes_drawn += 1

	_line_mesh.surface_end()


## ── Labels ──────────────────────────────────────────────────────────────────

func update_labels(snapshots: Dictionary, config: RagdollDebugConfig) -> void:
	if config == null:
		return
	if not config.show_part_labels:
		for label_key: int in _labels:
			var label: Label3D = _labels[label_key] as Label3D
			if label != null:
				label.visible = false
		return

	for npc_name: String in snapshots:
		var snap: Dictionary = snapshots[npc_name] as Dictionary
		var parts: Array = snap.get("parts", []) as Array
		for entry: Dictionary in parts:
			var part_ref: Variant = entry.get("part", null)
			if part_ref == null or not is_instance_valid(part_ref):
				continue
			var part: BodyPart = part_ref as BodyPart
			if part == null:
				continue
			var offset: float = float(entry["offset"])
			var lin_vel: float = float(entry["lin_vel"])
			var ang_vel: float = float(entry["ang_vel"])
			var half_height: float = float(entry["half_height"])
			var label: Label3D = _get_or_create_label(part)
			label.text = "%s off=%.3f v=%.2f w=%.2f" % [
				part.part_name, offset, lin_vel, ang_vel]
			label.position = Vector3(0.0, half_height + 0.05, 0.0)
			label.visible = true


func _get_or_create_label(part: BodyPart) -> Label3D:
	var key: int = part.get_instance_id()
	if _labels.has(key):
		return _labels[key] as Label3D

	var label: Label3D = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	part.add_child(label)
	_labels[key] = label
	return label


## ── Collision-mesh visibility ───────────────────────────────────────────────

func apply_mesh_visibility(config: RagdollDebugConfig) -> void:
	if config == null:
		return
	var parts: Array = _parent.get_tree().get_nodes_in_group(&"body_part")
	for node: Node in parts:
		var part: BodyPart = node as BodyPart
		if part == null:
			continue
		part.set_debug_mesh_visible(config.show_debug_meshes)


func set_mesh_visibility(visible: bool) -> void:
	var parts: Array = _parent.get_tree().get_nodes_in_group(&"body_part")
	for node: Node in parts:
		var part: BodyPart = node as BodyPart
		if part == null:
			continue
		part.set_debug_mesh_visible(visible)
