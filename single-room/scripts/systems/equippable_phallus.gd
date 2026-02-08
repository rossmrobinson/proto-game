class_name EquippablePhallus
extends Node3D
## A strap-on phallic object that can be equipped on any NPC — regardless
## of their body_type.  Creates physics bodies matching the male anatomy
## pattern (shaft + optional scrotum placeholder) and optionally registers
## them with the host NPC's NerveSystem so the *wearer* can feel stimulation
## through the toy.
##
## Usage:
##   var toy := EquippablePhallus.new()
##   toy.equip(npc)         # attaches to pelvis, creates physics
##   toy.unequip()          # removes cleanly
##
## The shaft is a BodyPart, so it is grabbable, targetable, and responds
## to the same interaction pipeline as native anatomy.

signal equipped(npc: NPCPlaceholder)
signal unequipped()

@export_group("Dimensions")
## Length as a fraction of the host's body_height.
@export_range(0.02, 0.12) var length_fraction: float = 0.045
## Radius as a fraction of the host's body_height.
@export_range(0.005, 0.04) var radius_fraction: float = 0.015
## Mass of the shaft in kg.
@export_range(0.05, 1.0) var shaft_mass: float = 0.15

@export_group("Visuals")
## Color of the toy.  Default: silicone grey.
@export var toy_color: Color = Color(0.35, 0.3, 0.35, 1.0)
## Whether to add a simple mesh for visual feedback.
@export var show_mesh: bool = true

@export_group("Nerve Passthrough")
## Whether stimulation on the toy is forwarded to the wearer's NerveSystem.
@export var nerve_passthrough: bool = true
## Multiplier on forwarded stimulation (0 = nothing felt, 1 = full, >1 = amplified).
@export_range(0.0, 2.0) var passthrough_intensity: float = 0.5
## The body part name used when forwarding to NerveSystem.
## "genitals" maps to whatever the host's genital sensitivity entry is.
@export var passthrough_part_name: String = "genitals"

@export_group("Attachment")
## Offset from pelvis anchor (local coords of the pelvis bone).
@export var attach_offset: Vector3 = Vector3.ZERO
## If true, adds a scrotum-like counterweight behind the shaft.
@export var include_base_weight: bool = false

# ── State ────────────────────────────────────────────────────────────────────
var _host_npc: NPCPlaceholder = null
var _shaft: BodyPart = null
var _base_weight: BodyPart = null
var _joint: Generic6DOFJoint3D = null
var _base_joint: Generic6DOFJoint3D = null
var _is_equipped: bool = false


## Attach this toy to an NPC.  Creates physics bodies and joints.
func equip(npc: NPCPlaceholder) -> void:
	if _is_equipped:
		push_warning("[EquippablePhallus] Already equipped — unequip first.")
		return
	if npc == null or npc.ragdoll == null:
		push_error("[EquippablePhallus] Cannot equip: NPC or ragdoll is null.")
		return

	_host_npc = npc
	var h: float = npc.body_height

	# Find the pelvis body
	var pelvis: BodyPart = npc.ragdoll.parts.get("pelvis") as BodyPart
	if pelvis == null:
		push_error("[EquippablePhallus] No pelvis found on %s" % npc.npc_name)
		return

	# Calculate placement
	var pelvis_pos: Vector3 = pelvis.global_position
	var pelvis_front: Vector3 = -pelvis.global_basis.z  # forward
	var groin_offset: Vector3 = pelvis_front * 0.04 * h + Vector3.DOWN * 0.02 * h
	var shaft_pos: Vector3 = pelvis_pos + groin_offset + attach_offset

	# ── Create shaft BodyPart ────────────────────────────────────────────
	_shaft = BodyPart.new()
	_shaft.name = "EquippedShaft"
	_shaft.part_name = "equipped_shaft"
	_shaft.display_name = "Strap-On"
	_shaft.is_grabbable = true
	_shaft.grab_stiffness = 0.3
	_shaft.grab_break_distance = 1.0
	_shaft.mass = shaft_mass
	_shaft.gravity_scale = 1.0
	_shaft.linear_damp = 2.0
	_shaft.angular_damp = 4.0
	_shaft.continuous_cd = true  # Prevent tunneling through thin body parts

	# Capsule collision
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = radius_fraction * h
	capsule.height = length_fraction * h
	var col: CollisionShape3D = CollisionShape3D.new()
	col.shape = capsule
	col.name = "ShaftCollision"
	_shaft.add_child(col)

	# Optional mesh
	if show_mesh:
		var mesh_inst: MeshInstance3D = MeshInstance3D.new()
		var mesh: CapsuleMesh = CapsuleMesh.new()
		mesh.radius = radius_fraction * h
		mesh.height = length_fraction * h
		mesh_inst.mesh = mesh
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = toy_color
		mat.roughness = 0.6
		mesh_inst.material_override = mat
		mesh_inst.name = "ShaftMesh"
		_shaft.add_child(mesh_inst)

	# Place in scene
	var scene_root: Node = npc.get_tree().current_scene
	scene_root.add_child(_shaft)
	_shaft.global_position = shaft_pos

	# Set equipment layer (7) + external NPC layer (3) for interaction queries
	_shaft.collision_layer = 0
	_shaft.set_collision_layer_value(3, true)   # NPC_External (targeting)
	_shaft.set_collision_layer_value(4, true)   # Interactable
	_shaft.set_collision_layer_value(7, true)   # Equipment
	_shaft.collision_mask = 0
	_shaft.set_collision_mask_value(1, true)    # Environment
	_shaft.set_collision_mask_value(2, true)    # Player
	_shaft.set_collision_mask_value(3, true)    # Other NPC parts
	_shaft.set_collision_mask_value(6, true)    # NPC_Internal (passages)

	# Exclude collision between shaft and host pelvis (they're jointed)
	_shaft.add_collision_exception_with(pelvis)

	# Link the shaft to the NPC's ragdoll_owner so it can find nerve system
	_shaft.ragdoll_owner = npc
	if nerve_passthrough and npc.nerve_system != null:
		_shaft._nerve_system = npc.nerve_system
		# Register a custom sensitivity for the toy
		var toy_sens: NerveSensitivity = NerveSensitivity.create(
			0.5 * passthrough_intensity,
			NerveSensitivity.Zone.EROGENOUS,
			0.6 * passthrough_intensity,
			0.15, 0.4)
		npc.nerve_system.register_part("equipped_shaft", toy_sens)

	# Joint: shaft → pelvis
	_joint = Generic6DOFJoint3D.new()
	_joint.name = "ShaftPelvisJoint"
	_joint.node_a = pelvis.get_path()
	_joint.node_b = _shaft.get_path()
	_joint.global_position = shaft_pos + Vector3.UP * (length_fraction * h * 0.45)

	# Relatively stiff — toy doesn't flop as much as real anatomy
	var slack: float = 0.01
	_joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -slack)
	_joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, slack)
	_joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -slack)
	_joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, slack)
	_joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -slack)
	_joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, slack)

	_joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(-30))
	_joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(30))
	_joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(-20))
	_joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(20))
	_joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(-20))
	_joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(20))

	scene_root.add_child(_joint)

	# ── Optional base weight ─────────────────────────────────────────────
	if include_base_weight:
		_create_base_weight(scene_root, pelvis, shaft_pos, h)

	# Register shaft in ragdoll parts dict so interaction system can find it
	npc.ragdoll.parts["equipped_shaft"] = _shaft

	# Connect shaft signals to brain if available
	if npc.brain != null:
		if not _shaft.part_grabbed.is_connected(npc.brain._on_part_grabbed):
			_shaft.part_grabbed.connect(npc.brain._on_part_grabbed)
		if not _shaft.part_released.is_connected(npc.brain._on_part_released):
			_shaft.part_released.connect(npc.brain._on_part_released)
		if not _shaft.part_impact.is_connected(npc.brain._on_part_impact):
			_shaft.part_impact.connect(npc.brain._on_part_impact)

	_is_equipped = true
	equipped.emit(npc)
	print("[EquippablePhallus] Equipped on %s" % npc.npc_name)


## Remove the toy from the NPC.  Cleans up all physics bodies and joints.
func unequip() -> void:
	if not _is_equipped:
		return

	# Remove from ragdoll parts dict
	if _host_npc != null and _host_npc.ragdoll != null:
		_host_npc.ragdoll.parts.erase("equipped_shaft")
		if include_base_weight:
			_host_npc.ragdoll.parts.erase("equipped_base")

	# Free physics objects
	_safe_free(_base_joint)
	_safe_free(_base_weight)
	_safe_free(_joint)
	_safe_free(_shaft)

	_shaft = null
	_base_weight = null
	_joint = null
	_base_joint = null
	_is_equipped = false
	_host_npc = null

	unequipped.emit()


## Whether the toy is currently equipped.
func is_equipped() -> bool:
	return _is_equipped


## Get the shaft BodyPart (for external interaction).
func get_shaft() -> BodyPart:
	return _shaft


## Get the host NPC.
func get_host() -> NPCPlaceholder:
	return _host_npc


# ── Internal ─────────────────────────────────────────────────────────────────

func _create_base_weight(scene_root: Node, pelvis: BodyPart,
		shaft_pos: Vector3, h: float) -> void:
	_base_weight = BodyPart.new()
	_base_weight.name = "EquippedBase"
	_base_weight.part_name = "equipped_base"
	_base_weight.display_name = "Strap-On Base"
	_base_weight.is_grabbable = false
	_base_weight.mass = shaft_mass * 0.3
	_base_weight.gravity_scale = 1.0
	_base_weight.linear_damp = 3.0
	_base_weight.angular_damp = 5.0

	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = radius_fraction * h * 1.5
	var base_col: CollisionShape3D = CollisionShape3D.new()
	base_col.shape = sphere
	base_col.name = "BaseCollision"
	_base_weight.add_child(base_col)

	if show_mesh:
		var mesh_inst: MeshInstance3D = MeshInstance3D.new()
		var mesh: SphereMesh = SphereMesh.new()
		mesh.radius = radius_fraction * h * 1.5
		mesh.height = radius_fraction * h * 3.0
		mesh_inst.mesh = mesh
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = toy_color
		mat.roughness = 0.6
		mesh_inst.material_override = mat
		mesh_inst.name = "BaseMesh"
		_base_weight.add_child(mesh_inst)

	scene_root.add_child(_base_weight)
	var base_offset: Vector3 = Vector3(0.0, 0.0, -0.02 * h)
	_base_weight.global_position = shaft_pos + base_offset

	_base_weight.ragdoll_owner = _host_npc

	# Joint base → pelvis
	_base_joint = Generic6DOFJoint3D.new()
	_base_joint.name = "BasePelvisJoint"
	_base_joint.node_a = pelvis.get_path()
	_base_joint.node_b = _base_weight.get_path()
	_base_joint.global_position = _base_weight.global_position

	var b_slack: float = 0.005
	_base_joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -b_slack)
	_base_joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, b_slack)
	_base_joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -b_slack)
	_base_joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, b_slack)
	_base_joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -b_slack)
	_base_joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, b_slack)
	_base_joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(-10))
	_base_joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(10))
	_base_joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(-10))
	_base_joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(10))
	_base_joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(-10))
	_base_joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(10))

	scene_root.add_child(_base_joint)

	if _host_npc != null and _host_npc.ragdoll != null:
		_host_npc.ragdoll.parts["equipped_base"] = _base_weight


func _safe_free(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.queue_free()
