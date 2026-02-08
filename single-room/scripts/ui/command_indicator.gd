class_name CommandIndicator
extends CanvasLayer
## Screen-edge indicator showing which NPC the player is commanding.
## Creates its own Label — no scene file needed.
##
## Displays in the top-right corner:
##   "Commanding: Self"        (dimmed)
##   "Commanding: NPC_Alpha"   (bright)
##
## Attach to the scene root (not the player) so it persists across respawns.

var _label: Label = null
var _command_system: NPCCommandSystem = null
var _flash_timer: float = 0.0
var _flash_duration: float = 0.6


func _ready() -> void:
	layer = 9  # Below crosshair layer (10), above world
	_build_ui()
	# Defer finding the command system until scene tree is ready
	call_deferred(&"_find_command_system")


func _process(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer -= delta
		# Pulse alpha for visual feedback on change
		var alpha: float = 0.5 + 0.5 * sin(_flash_timer * TAU * 3.0)
		_label.modulate.a = alpha
		if _flash_timer <= 0.0:
			_label.modulate.a = 1.0


# ── UI Construction ──────────────────────────────────────────────────────────

func _build_ui() -> void:
	var container: MarginContainer = MarginContainer.new()
	container.name = "CommandContainer"
	container.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	container.add_theme_constant_override("margin_top", 12)
	container.add_theme_constant_override("margin_right", 16)
	container.add_theme_constant_override("margin_left", 0)
	container.add_theme_constant_override("margin_bottom", 0)
	container.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(container)

	_label = Label.new()
	_label.name = "CommandLabel"
	_label.text = "Commanding: Self"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.5))
	_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.4))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	container.add_child(_label)


# ── Command System Wiring ────────────────────────────────────────────────────

func _find_command_system() -> void:
	# Walk the tree looking for an NPCCommandSystem
	_find_recursive(get_tree().current_scene)
	if _command_system == null:
		push_warning("[CommandIndicator] NPCCommandSystem not found in scene tree")
		return
	_command_system.commanded_npc_changed.connect(_on_npc_changed)
	_command_system.command_cleared.connect(_on_command_cleared)


func _find_recursive(node: Node) -> void:
	if _command_system != null:
		return
	if node is NPCCommandSystem:
		_command_system = node as NPCCommandSystem
		return
	for child: Node in node.get_children():
		_find_recursive(child)
		if _command_system != null:
			return


func _on_npc_changed(npc: NPCPlaceholder) -> void:
	_label.text = "Commanding: %s" % npc.npc_name
	_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5, 1.0))
	_flash_timer = _flash_duration
	# Pause the NPC's autonomous behavior while commanded
	if npc.behavior != null:
		npc.behavior.pause()


func _on_command_cleared() -> void:
	# Resume autonomous behavior on the previously commanded NPC
	if _command_system != null and _command_system.commanded_npc == null:
		# The NPC was already cleared, but we can resume all NPCs
		for node: Node in get_tree().get_nodes_in_group(&"npc"):
			if node is NPCPlaceholder:
				var npc: NPCPlaceholder = node as NPCPlaceholder
				if npc.behavior != null:
					npc.behavior.resume()

	_label.text = "Commanding: Self"
	_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.5))
	_flash_timer = _flash_duration
