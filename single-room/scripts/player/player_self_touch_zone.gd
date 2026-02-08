class_name PlayerSelfTouchZone
extends Area3D
## Invisible collision zone on the player's body that can be targeted by
## the player's own hand system. Allows interaction with own breasts/genitals.
##
## Instantiate via PlayerSelfTouch, which creates and positions these zones.

signal self_touched(zone_name: String, hand: int)
signal self_released(zone_name: String, hand: int)

@export var zone_name: String = ""
@export var display_name: String = ""
## Maps to the same NerveSensitivity zones as NPC body parts.
@export var sensitivity: float = 0.8

var _is_touched: bool = false


func _ready() -> void:
	add_to_group(&"self_touch_zone")
	add_to_group(&"interactable")
	# Same layers as body parts so the targeting system can find them
	collision_layer = 8  # layer 4 (Interactable)
	collision_mask = 0   # Doesn't need to detect anything itself
	monitoring = false
	monitorable = true


func get_part_name() -> String:
	return zone_name


func get_display_name() -> String:
	if display_name != "":
		return display_name
	return zone_name.replace("_", " ").capitalize()


func touch(hand: int) -> void:
	_is_touched = true
	self_touched.emit(zone_name, hand)


func release_touch(hand: int) -> void:
	_is_touched = false
	self_released.emit(zone_name, hand)


func is_touched() -> bool:
	return _is_touched
