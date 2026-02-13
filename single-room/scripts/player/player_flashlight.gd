class_name PlayerFlashlight
extends SpotLight3D
## Toggleable flashlight projecting from the player camera.
## Starts off. Press F to toggle.

@export var toggle_action: StringName = &"toggle_flashlight"


func _ready() -> void:
	_ensure_flashlight_action()
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(toggle_action):
		visible = not visible


func _ensure_flashlight_action() -> void:
	if InputMap.has_action(toggle_action):
		return
	InputMap.add_action(toggle_action)
	var ev: InputEventKey = InputEventKey.new()
	ev.physical_keycode = KEY_F
	InputMap.action_add_event(toggle_action, ev)
