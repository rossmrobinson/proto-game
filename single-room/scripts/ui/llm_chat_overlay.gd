class_name LLMChatOverlay
extends CanvasLayer
## Text-based chat overlay for LLM-driven NPCs.

var _panel: PanelContainer = null
var _title: Label = null
var _log: RichTextLabel = null
var _input: LineEdit = null
var _scroll: ScrollContainer = null
var _visible: bool = false
var _mouse_mode_before: int = Input.MOUSE_MODE_CAPTURED
var _target: LLMNPCController = null
var _command_system: NPCCommandSystem = null
var _lines: Array[String] = []

const MAX_LINES: int = 30


func _ready() -> void:
	layer = 12
	_build_ui()
	visible = false
	call_deferred(&"_resolve_target")


func _unhandled_input(event: InputEvent) -> void:
	if event is not InputEventKey:
		return
	var key: InputEventKey = event as InputEventKey
	if key.echo or not key.pressed:
		return
	if key.physical_keycode != KEY_ENTER:
		return
	if not _visible:
		_open()
	else:
		_handle_enter_when_open()
	get_viewport().set_input_as_handled()


# ── UI ───────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "LLMChatPanel"
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_panel.position = Vector2(12.0, -12.0)
	_panel.custom_minimum_size = Vector2(460.0, 260.0)

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.08, 0.92)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(vbox)

	_title = Label.new()
	_title.text = "LLM Chat [Enter]"
	_title.add_theme_font_size_override("font_size", 15)
	_title.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	vbox.add_child(_title)

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(440.0, 170.0)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_scroll)

	_log = RichTextLabel.new()
	_log.scroll_active = false
	_log.bbcode_enabled = false
	_log.add_theme_font_size_override("font_size", 13)
	_log.add_theme_color_override("default_color", Color(0.9, 0.9, 0.95))
	_scroll.add_child(_log)

	_input = LineEdit.new()
	_input.placeholder_text = "Type message and press Enter"
	_input.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_input)


func _open() -> void:
	_visible = true
	visible = true
	_mouse_mode_before = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_input.grab_focus()


func _close() -> void:
	_visible = false
	visible = false
	Input.mouse_mode = _mouse_mode_before as Input.MouseMode
	_input.release_focus()


func _handle_enter_when_open() -> void:
	var msg: String = _input.text.strip_edges()
	if msg == "":
		_close()
		return
	_input.text = ""
	_append_line("You", msg)
	if _target == null:
		_append_line("System", "No LLM NPC available")
		return
	_target.request_chat(msg)
	_input.grab_focus()


# ── Target Resolution ───────────────────────────────────────────────────────

func _resolve_target() -> void:
	_command_system = _find_command_system(get_tree().current_scene)
	if _command_system != null:
		_command_system.commanded_npc_changed.connect(_on_commanded_npc_changed)
		_command_system.command_cleared.connect(_on_command_cleared)
	_update_target()


func _find_command_system(node: Node) -> NPCCommandSystem:
	if node == null:
		return null
	if node is NPCCommandSystem:
		return node as NPCCommandSystem
	for child: Node in node.get_children():
		var found: NPCCommandSystem = _find_command_system(child)
		if found != null:
			return found
	return null


func _on_commanded_npc_changed(_npc: NPCPlaceholder) -> void:
	_update_target()


func _on_command_cleared() -> void:
	_update_target()


func _update_target() -> void:
	var next_target: LLMNPCController = null
	if _command_system != null and _command_system.commanded_npc != null:
		var npc: NPCPlaceholder = _command_system.commanded_npc
		next_target = _find_llm_controller_on(npc)
	if next_target == null:
		var nodes: Array[Node] = get_tree().get_nodes_in_group(&"llm_npc")
		if not nodes.is_empty() and nodes[0] is LLMNPCController:
			next_target = nodes[0] as LLMNPCController
	_set_target(next_target)


func _find_llm_controller_on(npc: NPCPlaceholder) -> LLMNPCController:
	if npc == null:
		return null
	for child: Node in npc.get_children():
		if child is LLMNPCController:
			return child as LLMNPCController
	return null


func _set_target(controller: LLMNPCController) -> void:
	if _target == controller:
		return
	if _target != null and _target.llm_reply.is_connected(_on_llm_reply):
		_target.llm_reply.disconnect(_on_llm_reply)
	_target = controller
	if _target != null:
		_target.llm_reply.connect(_on_llm_reply)
		var npc_name: String = _get_target_name()
		_title.text = "LLM Chat [Enter] - %s" % npc_name
	else:
		_title.text = "LLM Chat [Enter]"


func _get_target_name() -> String:
	if _target == null:
		return ""
	var parent: Node = _target.get_parent()
	if parent is NPCPlaceholder:
		return (parent as NPCPlaceholder).npc_name
	return "NPC"


func _on_llm_reply(reply_text: String, voice_id: String, _action_id: String) -> void:
	var label: String = "NPC"
	var npc_name: String = _get_target_name()
	if npc_name != "":
		label = npc_name
	var suffix: String = ""
	if voice_id != "":
		suffix = " [voice:%s]" % voice_id
	_append_line(label, reply_text + suffix)


# ── Log ─────────────────────────────────────────────────────────────────────

func _append_line(who: String, text: String) -> void:
	var line: String = "%s: %s" % [who, text]
	_lines.append(line)
	if _lines.size() > MAX_LINES:
		_lines = _lines.slice(_lines.size() - MAX_LINES)
	_log.text = "\n".join(_lines)
	_scroll.scroll_vertical = int(_log.get_line_count() * 1000)
