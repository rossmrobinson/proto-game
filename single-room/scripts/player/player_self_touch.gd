class_name PlayerSelfTouch
extends Node3D
## Creates invisible self-touch zones on the player's body for breasts
## and genitals. Positions them relative to the player's collision capsule.
## Integrates with TargetingSystem and HandInteractionSystem.
##
## Attach as child of PlayerController.

signal self_stimulation(zone_name: String, intensity: float)

@export_group("Zone Positions (local offsets from player origin)")
@export var left_breast_offset: Vector3 = Vector3(-0.12, 1.25, -0.12)
@export var right_breast_offset: Vector3 = Vector3(0.12, 1.25, -0.12)
@export var genitals_offset: Vector3 = Vector3(0.0, 0.82, -0.08)

@export_group("Zone Sizes")
@export var breast_radius: float = 0.08
@export var genitals_radius: float = 0.06

var _zones: Dictionary = {}  # zone_name → PlayerSelfTouchZone
var _player: PlayerController = null
var _hand_system: Node = null  # HandInteractionSystem


func _ready() -> void:
	_player = get_parent() as PlayerController
	_create_zone("player_left_breast", "Left Breast", left_breast_offset, breast_radius, 0.85)
	_create_zone("player_right_breast", "Right Breast", right_breast_offset, breast_radius, 0.85)
	_create_zone("player_genitals", "Genitals", genitals_offset, genitals_radius, 0.95)

	# Find sibling HandInteractionSystem to wire up events
	for sibling: Node in _player.get_children():
		if sibling is HandInteractionSystem:
			_hand_system = sibling
			break


func _physics_process(_delta: float) -> void:
	# Keep zones positioned relative to the player
	for zone_name: String in _zones.keys():
		var zone: PlayerSelfTouchZone = _zones[zone_name] as PlayerSelfTouchZone
		# The zone is a child of this Node3D which is a child of player,
		# so local transforms are already relative. Nothing to update unless
		# posture changes — handled below.

	# Adjust genitals zone height based on posture
	var posture_node: Node = null
	for sibling: Node in _player.get_children():
		if sibling is PlayerPosture:
			posture_node = sibling
			break

	if posture_node != null:
		var posture: PlayerPosture = posture_node as PlayerPosture
		var height_ratio: float = 1.0
		match posture.current_posture:
			PlayerPosture.Posture.CROUCHING:
				height_ratio = posture.crouch_height / posture.standing_height
			PlayerPosture.Posture.KNEELING:
				height_ratio = posture.kneel_height / posture.standing_height
			PlayerPosture.Posture.PRONE:
				height_ratio = posture.prone_height / posture.standing_height
		# Scale zone positions by height ratio
		if _zones.has("player_genitals"):
			var gz: PlayerSelfTouchZone = _zones["player_genitals"] as PlayerSelfTouchZone
			gz.position = genitals_offset * Vector3(1.0, height_ratio, 1.0)
		if _zones.has("player_left_breast"):
			var lb: PlayerSelfTouchZone = _zones["player_left_breast"] as PlayerSelfTouchZone
			lb.position = left_breast_offset * Vector3(1.0, height_ratio, 1.0)
		if _zones.has("player_right_breast"):
			var rb: PlayerSelfTouchZone = _zones["player_right_breast"] as PlayerSelfTouchZone
			rb.position = right_breast_offset * Vector3(1.0, height_ratio, 1.0)


## Get a self-touch zone by name.
func get_zone(zone_name: String) -> PlayerSelfTouchZone:
	return _zones.get(zone_name, null) as PlayerSelfTouchZone


## Get all self-touch zones.
func get_all_zones() -> Dictionary:
	return _zones


func _create_zone(zone_name: String, disp_name: String,
		offset: Vector3, radius: float, sensitivity: float) -> void:
	var zone: PlayerSelfTouchZone = PlayerSelfTouchZone.new()
	zone.name = zone_name.to_pascal_case()
	zone.zone_name = zone_name
	zone.display_name = disp_name
	zone.sensitivity = sensitivity
	zone.position = offset

	var col: CollisionShape3D = CollisionShape3D.new()
	col.name = "Shape"
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = radius
	col.shape = sphere
	zone.add_child(col)

	add_child(zone)
	_zones[zone_name] = zone

	zone.self_touched.connect(_on_zone_touched)
	zone.self_released.connect(_on_zone_released)


func _on_zone_touched(zone_name: String, hand: int) -> void:
	var zone: PlayerSelfTouchZone = _zones.get(zone_name, null) as PlayerSelfTouchZone
	if zone == null:
		return
	self_stimulation.emit(zone_name, zone.sensitivity)


func _on_zone_released(zone_name: String, _hand: int) -> void:
	self_stimulation.emit(zone_name, 0.0)
