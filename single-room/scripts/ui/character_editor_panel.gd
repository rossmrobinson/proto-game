class_name CharacterEditorPanel
extends CanvasLayer
## In-game debug/tuning UI for editing NPC CharacterProfile parameters.
## Toggle with F4.  Selects NPC from a dropdown, shows sliders for every
## tunable, and persists overrides to user:// JSON.
##
## Attach to the scene root (like CommandIndicator).

const SAVE_PATH: String = "user://character_overrides.json"

var _panel: PanelContainer = null
var _vbox: VBoxContainer = null
var _npc_dropdown: OptionButton = null
var _sliders: Dictionary = {}  # param_name → HSlider
var _labels: Dictionary = {}   # param_name → Label (value readout)
var _visible: bool = false
var _npc_list: Array[NPCPlaceholder] = []
var _current_npc: NPCPlaceholder = null
var _overrides: Dictionary = {}  # npc_name → { param → value }

# Slider definitions: [param_name, display, min, max, step]
const SLIDER_DEFS: Array = [
	["pain_tolerance", "Pain Tolerance", 0.0, 1.0, 0.05],
	["touch_receptivity", "Touch Receptivity", 0.0, 1.0, 0.05],
	["erogenous_sensitivity", "Erogenous Sens.", 0.5, 2.0, 0.05],
	["emotional_recovery_rate", "Emotional Recovery", 0.1, 2.0, 0.05],
	["relaxed_threshold", "Relaxed Thresh.", 5.0, 60.0, 1.0],
	["content_threshold", "Content Thresh.", 20.0, 80.0, 1.0],
	["aroused_threshold", "Aroused Thresh.", 40.0, 100.0, 1.0],
	["tense_threshold", "Tense Thresh.", 5.0, 60.0, 1.0],
	["distressed_threshold", "Distressed Thresh.", 20.0, 80.0, 1.0],
	["overwhelmed_threshold", "Overwhelmed Thresh.", 30.0, 100.0, 1.0],
	["dynamic_pain_enabled", "Dynamic Pain On/Off", 0.0, 1.0, 1.0],
	["max_tense_shift", "Max Tense Shift", 0.0, 40.0, 1.0],
	["max_distressed_shift", "Max Distress Shift", 0.0, 40.0, 1.0],
	["shift_activation_ratio", "Shift Activation", 0.5, 2.0, 0.05],
	["shift_ramp_exponent", "Shift Ramp Exp.", 0.5, 4.0, 0.1],
	["shift_decay_rate", "Shift Decay Rate", 0.1, 5.0, 0.1],
]


func _ready() -> void:
	layer = 11  # Above diagnostics
	_build_ui()
	_load_overrides()
	call_deferred(&"_scan_npcs")
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo and key.physical_keycode == KEY_F4:
			_toggle()
			get_viewport().set_input_as_handled()


# ── UI Construction ──────────────────────────────────────────────────────────

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "CharEditorPanel"
	_panel.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_panel.position = Vector2(10.0, 80.0)
	_panel.custom_minimum_size = Vector2(340.0, 0.0)

	# Semi-transparent background
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.92)
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

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(320.0, 500.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(_vbox)

	# Title
	var title: Label = Label.new()
	title.text = "Character Editor [F4]"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.9, 0.75, 0.4))
	_vbox.add_child(title)

	# NPC selector
	_npc_dropdown = OptionButton.new()
	_npc_dropdown.add_theme_font_size_override("font_size", 13)
	_npc_dropdown.item_selected.connect(_on_npc_selected)
	_vbox.add_child(_npc_dropdown)

	# Separator
	_vbox.add_child(HSeparator.new())

	# Status readout (comfort / discomfort / state / effective thresholds)
	var status_label: Label = Label.new()
	status_label.name = "StatusLabel"
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
	status_label.text = "No NPC selected"
	_vbox.add_child(status_label)
	_labels["__status__"] = status_label

	_vbox.add_child(HSeparator.new())

	# Sliders
	for def: Array in SLIDER_DEFS:
		var param: String = def[0] as String
		var display: String = def[1] as String
		var min_val: float = def[2] as float
		var max_val: float = def[3] as float
		var step: float = def[4] as float
		_add_slider(param, display, min_val, max_val, step)

	# Buttons
	_vbox.add_child(HSeparator.new())

	var btn_row: HBoxContainer = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	_vbox.add_child(btn_row)

	var reset_btn: Button = Button.new()
	reset_btn.text = "Reset"
	reset_btn.add_theme_font_size_override("font_size", 13)
	reset_btn.pressed.connect(_on_reset_pressed)
	btn_row.add_child(reset_btn)

	var save_btn: Button = Button.new()
	save_btn.text = "Save"
	save_btn.add_theme_font_size_override("font_size", 13)
	save_btn.pressed.connect(_on_save_pressed)
	btn_row.add_child(save_btn)


func _add_slider(param: String, display: String, min_val: float,
		max_val: float, step: float) -> void:
	var label: Label = Label.new()
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.85))
	_vbox.add_child(label)

	var row: HBoxContainer = HBoxContainer.new()
	_vbox.add_child(row)

	var slider: HSlider = HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = step
	slider.custom_minimum_size = Vector2(220.0, 20.0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(_on_slider_changed.bind(param))
	row.add_child(slider)

	var val_label: Label = Label.new()
	val_label.add_theme_font_size_override("font_size", 12)
	val_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	val_label.custom_minimum_size = Vector2(50.0, 0.0)
	row.add_child(val_label)

	_sliders[param] = slider
	_labels[param] = label
	_labels[param + "__val"] = val_label

	# Set display text
	label.text = display


# ── NPC Management ───────────────────────────────────────────────────────────

func _scan_npcs() -> void:
	_npc_list.clear()
	_npc_dropdown.clear()
	var nodes: Array[Node] = get_tree().get_nodes_in_group(&"npc")
	for node: Node in nodes:
		if node is NPCPlaceholder:
			_npc_list.append(node as NPCPlaceholder)
			_npc_dropdown.add_item((node as NPCPlaceholder).npc_name)
	if not _npc_list.is_empty():
		_select_npc(0)


func _select_npc(idx: int) -> void:
	if idx < 0 or idx >= _npc_list.size():
		return
	_current_npc = _npc_list[idx]
	_refresh_sliders()


func _refresh_sliders() -> void:
	if _current_npc == null or _current_npc.character_profile == null:
		return
	var profile: CharacterProfile = _current_npc.character_profile
	var params: Dictionary = profile.get_params()
	for def: Array in SLIDER_DEFS:
		var param: String = def[0] as String
		if params.has(param) and _sliders.has(param):
			var val: Variant = params[param]
			var slider: HSlider = _sliders[param] as HSlider
			# Bool → float for the toggle slider
			if val is bool:
				slider.value = 1.0 if (val as bool) else 0.0
			else:
				slider.value = val as float
			_update_value_label(param, slider.value)


func _update_value_label(param: String, value: float) -> void:
	var key: String = param + "__val"
	if not _labels.has(key):
		return
	var lbl: Label = _labels[key] as Label
	if param == "dynamic_pain_enabled":
		lbl.text = "ON" if value >= 0.5 else "OFF"
	elif _sliders.has(param):
		var slider: HSlider = _sliders[param] as HSlider
		if slider.step >= 1.0:
			lbl.text = "%.0f" % value
		else:
			lbl.text = "%.2f" % value


# ── Live Status ──────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if not _visible or _current_npc == null:
		return
	if _current_npc.character_profile == null:
		return
	var p: CharacterProfile = _current_npc.character_profile
	var status: Label = _labels.get("__status__") as Label
	if status != null:
		status.text = "C:%.0f  D:%.0f  [%s]\nEff.Tense:%.1f  Eff.Dist:%.1f  Shift:+%.1f/+%.1f" % [
			p.comfort_level, p.discomfort_level, p.get_state_label(),
			p.effective_tense_threshold, p.effective_distressed_threshold,
			p._tense_shift, p._distressed_shift,
		]


# ── Callbacks ────────────────────────────────────────────────────────────────

func _on_npc_selected(idx: int) -> void:
	_select_npc(idx)


func _on_slider_changed(value: float, param: String) -> void:
	if _current_npc == null or _current_npc.character_profile == null:
		return
	var profile: CharacterProfile = _current_npc.character_profile
	_update_value_label(param, value)
	# Bool params
	if param == "dynamic_pain_enabled":
		profile.dynamic_pain_enabled = value >= 0.5
		return
	if param in profile:
		profile.set(param, value)


func _on_reset_pressed() -> void:
	if _current_npc == null:
		return
	# Remove overrides for this NPC
	_overrides.erase(_current_npc.npc_name)
	# Reset profile to defaults by re-creating
	var profile: CharacterProfile = _current_npc.character_profile
	profile.pain_tolerance = 0.5
	profile.touch_receptivity = 0.5
	profile.erogenous_sensitivity = 1.0
	profile.emotional_recovery_rate = 0.5
	profile.relaxed_threshold = 30.0
	profile.content_threshold = 60.0
	profile.aroused_threshold = 80.0
	profile.tense_threshold = 25.0
	profile.distressed_threshold = 55.0
	profile.overwhelmed_threshold = 65.0
	profile.dynamic_pain_enabled = true
	profile.max_tense_shift = 20.0
	profile.max_distressed_shift = 15.0
	profile.shift_activation_ratio = 0.8
	profile.shift_ramp_exponent = 1.5
	profile.shift_decay_rate = 1.0
	_refresh_sliders()
	_save_overrides()


func _on_save_pressed() -> void:
	if _current_npc == null or _current_npc.character_profile == null:
		return
	var profile: CharacterProfile = _current_npc.character_profile
	_overrides[_current_npc.npc_name] = profile.get_params()
	_save_overrides()


# ── Toggle ───────────────────────────────────────────────────────────────────

func _toggle() -> void:
	_visible = not _visible
	visible = _visible
	if _visible:
		_scan_npcs()
		# Capture mouse for sliders
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


# ── Persistence ──────────────────────────────────────────────────────────────

func _save_overrides() -> void:
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("[CharacterEditorPanel] Could not write %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify(_overrides, "  "))
	file.close()


func _load_overrides() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var text: String = file.get_as_text()
	file.close()
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		push_warning("[CharacterEditorPanel] Invalid JSON in %s" % SAVE_PATH)
		return
	_overrides = json.data as Dictionary


## Apply stored overrides to all NPCs (call after scene is ready).
func apply_stored_overrides() -> void:
	for npc: NPCPlaceholder in _npc_list:
		if npc.character_profile == null:
			continue
		if _overrides.has(npc.npc_name):
			npc.character_profile.apply_overrides(_overrides[npc.npc_name] as Dictionary)
