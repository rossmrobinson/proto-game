@tool
extends EditorPlugin

const SETTINGS_ENDPOINT: String = "llm_diagnostics/endpoint"
const SETTINGS_AUTO: String = "llm_diagnostics/auto_analyze"
const SETTINGS_LINES: String = "llm_diagnostics/log_tail_lines"
const SETTINGS_INCLUDE_DIAG: String = "llm_diagnostics/include_diag"
const SETTINGS_INCLUDE_INDEX: String = "llm_diagnostics/include_index"
const SETTINGS_INCLUDE_SCREENSHOT: String = "llm_diagnostics/include_screenshot"
const SETTINGS_INDEX_MAX: String = "llm_diagnostics/index_max"
const SETTINGS_TUNING_OPEN: String = "llm_diagnostics/tuning_open"
const SETTINGS_COLOR: String = "llm_diagnostics/enable_color"
const SETTINGS_SECTION_DIAG_OPEN: String = "llm_diagnostics/section_diag_open"
const SETTINGS_SECTION_CHAT_OPEN: String = "llm_diagnostics/section_chat_open"
const SETTINGS_SECTION_OVERRIDES_OPEN: String = "llm_diagnostics/section_overrides_open"
const SETTINGS_INCLUDE_INSPECTOR: String = "llm_diagnostics/include_inspector"
const DEFAULT_ENDPOINT: String = "http://127.0.0.1:8787/analyze"
const DEFAULT_INDEX_MAX: int = 300
const MAX_CHAT_MESSAGES: int = 12
const OVERRIDES_PATH: String = "J:/proto-game/single-room/logs/llm_overrides.json"
const OVERRIDES_LOG_PATH: String = "J:/proto-game/single-room/logs/llm_overrides.jsonl"
const OVERRIDES_BANK_PATH: String = "J:/proto-game/single-room/logs/llm-overrides-bank.json"
const CHAT_HISTORY_PATH: String = "J:/proto-game/single-room/logs/llm-chat-history.json"
const CHAT_LOG_PATH: String = "J:/proto-game/single-room/logs/llm-chat-log.jsonl"
const RESPAWN_REQUEST_PATH: String = "J:/proto-game/single-room/logs/llm-respawn-request.json"
const POSE_REPORT_REQUEST_PATH: String = "J:/proto-game/single-room/logs/llm-pose-report-request.json"
const SCREENSHOT_DIR: String = "J:/proto-game/single-room/logs/llm_screenshots"
const MAX_SCREENSHOT_EDGE: int = 512

const SAFE_OVERRIDE_KEYS: PackedStringArray = [
	"spring_stiffness",
	"spring_damping",
	"angular_stiffness",
	"angular_damping",
	"max_torque",
	"grabbed_motor_ratio",
	"spawn_ramp_time",
	"spawn_ramp_floor",
	"spawn_freeze_frames",
	"passive_motor_floor",
	"passive_core_scale",
	"passive_limb_scale",
	"passive_joint_scale",
	"passive_pelvis_scale",
	"passive_damp_multiplier",
	"recover_delay",
	"recover_ramp_time",
	"recover_linear_threshold",
	"recover_angular_threshold",
	"recover_use_core_parts",
	"allow_passive_limit_widen",
	"stand_up_force",
	"stand_up_damping",
	"stand_up_max_force",
	"stand_up_torque",
	"stand_up_torque_damping",
	"stand_up_min_scale",
	"auto_recover",
	"stand_assist_enabled",
]

const INT_OVERRIDE_KEYS: PackedStringArray = [
	"spawn_freeze_frames",
]

const TUNING_LAYOUT: Array = [
	{"type": "section", "label": "Core"},
	{"type": "slider", "key": "spring_stiffness", "label": "Spring Stiffness", "min": 0.0, "max": 1200.0, "step": 5.0, "default": 400.0},
	{"type": "slider", "key": "spring_damping", "label": "Spring Damping", "min": 0.0, "max": 200.0, "step": 1.0, "default": 40.0},
	{"type": "slider", "key": "angular_stiffness", "label": "Angular Stiffness", "min": 0.0, "max": 200.0, "step": 1.0, "default": 80.0},
	{"type": "slider", "key": "angular_damping", "label": "Angular Damping", "min": 0.0, "max": 50.0, "step": 0.5, "default": 12.0},
	{"type": "slider", "key": "max_torque", "label": "Max Torque", "min": 0.0, "max": 200.0, "step": 1.0, "default": 50.0},
	{"type": "slider", "key": "grabbed_motor_ratio", "label": "Grabbed Motor Ratio", "min": 0.0, "max": 1.0, "step": 0.01, "default": 0.05},

	{"type": "section", "label": "Spawn"},
	{"type": "slider", "key": "spawn_ramp_time", "label": "Spawn Ramp Time", "min": 0.0, "max": 2.0, "step": 0.05, "default": 0.4},
	{"type": "slider", "key": "spawn_ramp_floor", "label": "Spawn Ramp Floor", "min": 0.0, "max": 1.0, "step": 0.01, "default": 0.3},
	{"type": "slider", "key": "spawn_freeze_frames", "label": "Spawn Freeze Frames", "min": 0.0, "max": 60.0, "step": 1.0, "default": 10.0},

	{"type": "section", "label": "Recovery"},
	{"type": "toggle", "key": "auto_recover", "label": "Auto Recover", "default": true},
	{"type": "toggle", "key": "recover_use_core_parts", "label": "Recover Use Core Parts", "default": true},
	{"type": "toggle", "key": "allow_passive_limit_widen", "label": "Allow Passive Limit Widen", "default": false},
	{"type": "slider", "key": "recover_delay", "label": "Recover Delay", "min": 0.0, "max": 3.0, "step": 0.05, "default": 0.8},
	{"type": "slider", "key": "recover_ramp_time", "label": "Recover Ramp Time", "min": 0.0, "max": 3.0, "step": 0.05, "default": 0.8},
	{"type": "slider", "key": "recover_linear_threshold", "label": "Recover Linear Threshold", "min": 0.0, "max": 3.0, "step": 0.05, "default": 0.35},
	{"type": "slider", "key": "recover_angular_threshold", "label": "Recover Angular Threshold", "min": 0.0, "max": 6.0, "step": 0.1, "default": 1.5},
	{"type": "slider", "key": "passive_damp_multiplier", "label": "Passive Damping Mult", "min": 0.0, "max": 6.0, "step": 0.1, "default": 2.5},
	{"type": "slider", "key": "passive_motor_floor", "label": "Passive Motor Floor", "min": 0.0, "max": 1.0, "step": 0.01, "default": 0.3},
	{"type": "slider", "key": "passive_core_scale", "label": "Passive Core Scale", "min": 0.0, "max": 2.0, "step": 0.05, "default": 1.0},
	{"type": "slider", "key": "passive_limb_scale", "label": "Passive Limb Scale", "min": 0.0, "max": 2.0, "step": 0.05, "default": 0.35},
	{"type": "slider", "key": "passive_joint_scale", "label": "Passive Joint Scale", "min": 0.0, "max": 1.0, "step": 0.01, "default": 0.15},
	{"type": "slider", "key": "passive_pelvis_scale", "label": "Passive Pelvis Scale", "min": 0.0, "max": 1.0, "step": 0.01, "default": 0.1},

	{"type": "section", "label": "Stand Assist"},
	{"type": "toggle", "key": "stand_assist_enabled", "label": "Stand Assist Enabled", "default": true},
	{"type": "slider", "key": "stand_up_force", "label": "Stand Up Force", "min": 0.0, "max": 60.0, "step": 0.5, "default": 18.0},
	{"type": "slider", "key": "stand_up_damping", "label": "Stand Up Damping", "min": 0.0, "max": 20.0, "step": 0.2, "default": 6.0},
	{"type": "slider", "key": "stand_up_max_force", "label": "Stand Up Max Force", "min": 0.0, "max": 200.0, "step": 1.0, "default": 80.0},
	{"type": "slider", "key": "stand_up_torque", "label": "Stand Up Torque", "min": 0.0, "max": 40.0, "step": 0.5, "default": 14.0},
	{"type": "slider", "key": "stand_up_torque_damping", "label": "Stand Up Torque Damping", "min": 0.0, "max": 20.0, "step": 0.2, "default": 4.0},
	{"type": "slider", "key": "stand_up_min_scale", "label": "Stand Up Min Scale", "min": 0.0, "max": 1.0, "step": 0.01, "default": 0.1},
]

const SECTION_COLORS: Dictionary = {
	"Core": Color(0.95, 0.75, 0.3),
	"Spawn": Color(0.35, 0.75, 0.95),
	"Recovery": Color(0.45, 0.9, 0.6),
	"Stand Assist": Color(0.9, 0.55, 0.85),
}

const TUNING_DESCRIPTIONS: Dictionary = {
	"spring_stiffness": "Position spring strength; higher = tighter body pose.",
	"spring_damping": "Position spring damping; higher = less bounce.",
	"angular_stiffness": "Rotation spring strength; higher = stiffer joints.",
	"angular_damping": "Rotation damping; higher = less wobble.",
	"max_torque": "Torque clamp per mass; limits joint force spikes.",
	"grabbed_motor_ratio": "Motor scale while grabbed; lower = easier to pull.",
	"spawn_ramp_time": "Seconds to ramp motors after unfreeze.",
	"spawn_ramp_floor": "Minimum motor scale during spawn ramp.",
	"spawn_freeze_frames": "Physics frames to keep parts frozen at spawn.",
	"recover_delay": "Seconds to stay passive before recovery.",
	"recover_ramp_time": "Seconds to ramp back to full strength.",
	"recover_linear_threshold": "Max linear speed to count as settled.",
	"recover_angular_threshold": "Max angular speed to count as settled.",
	"passive_damp_multiplier": "Extra damping while passive.",
	"passive_motor_floor": "Minimum motor scale while passive.",
	"passive_core_scale": "Passive spring scale for core parts.",
	"passive_limb_scale": "Passive spring scale for limbs.",
	"passive_joint_scale": "Passive joint PD scale.",
	"passive_pelvis_scale": "Passive pelvis lock scale.",
	"stand_up_force": "Pelvis lift strength.",
	"stand_up_damping": "Pelvis lift damping.",
	"stand_up_max_force": "Max pelvis lift per mass.",
	"stand_up_torque": "Upright torque strength.",
	"stand_up_torque_damping": "Upright torque damping.",
	"stand_up_min_scale": "Minimum recovery scale for assist.",
	"auto_recover": "Auto passive-to-active recovery.",
	"recover_use_core_parts": "Only core parts determine stability.",
	"allow_passive_limit_widen": "Widen limits while passive.",
	"stand_assist_enabled": "Enable stand assist during recovery.",
}

var _dock: Control = null
var _endpoint_edit: LineEdit = null
var _auto_check: CheckBox = null
var _output: TextEdit = null
var _status: Label = null
var _http: HTTPRequest = null
var _timer: Timer = null
var _last_mtime: int = 0
var _pending_mode: String = "analyze"

var _chat_history: TextEdit = null
var _chat_input: TextEdit = null
var _overrides_edit: TextEdit = null
var _apply_overrides_btn: Button = null
var _capture_btn: Button = null
var _clear_chat_btn: Button = null
var _send_chat_btn: Button = null
var _screenshot_label: Label = null
var _include_diag: CheckBox = null
var _include_index: CheckBox = null
var _include_screenshot: CheckBox = null
var _include_inspector: CheckBox = null
var _chat_messages: Array = []
var _last_screenshot_path: String = ""
var _last_screenshot_b64: String = ""

var _tuning_list: VBoxContainer = null
var _tuning_container: VBoxContainer = null
var _tuning_scroll: ScrollContainer = null
var _tuning_toggle: Button = null
var _color_check: CheckBox = null
var _slider_controls: Dictionary = {}
var _toggle_controls: Dictionary = {}
var _slider_overrides: Dictionary = {}
var _preset_name_edit: LineEdit = null
var _preset_list: OptionButton = null
var _save_preset_btn: Button = null
var _load_preset_btn: Button = null
var _revert_btn: Button = null
var _preset_bank: Array = []
var _suspend_slider_events: bool = false
var _color_labels: Array = []


func _enter_tree() -> void:
	_dock = _build_dock()
	if _dock == null or not is_instance_valid(_dock):
		push_error("LLM Diagnostics: Dock build failed")
		return
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)


func _exit_tree() -> void:
	_persist_chat_history()
	if _dock != null and is_instance_valid(_dock):
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null


func _build_dock() -> Control:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "LLM Diagnostics"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var root: VBoxContainer = VBoxContainer.new()
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(root)

	var title: Label = Label.new()
	title.text = "LLM Diagnostics"
	title.add_theme_font_size_override("font_size", 16)
	root.add_child(title)

	var tuning_header: HBoxContainer = HBoxContainer.new()
	_tuning_toggle = Button.new()
	_tuning_toggle.text = "Tuning Overrides"
	_tuning_toggle.toggle_mode = true
	_tuning_toggle.button_pressed = bool(_get_setting(SETTINGS_TUNING_OPEN, true))
	_tuning_toggle.toggled.connect(_on_tuning_toggled)
	_tuning_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tuning_header.add_child(_tuning_toggle)

	_color_check = CheckBox.new()
	_color_check.text = "Color coding"
	_color_check.button_pressed = bool(_get_setting(SETTINGS_COLOR, true))
	_color_check.toggled.connect(_on_color_toggled)
	tuning_header.add_child(_color_check)
	root.add_child(tuning_header)

	_tuning_container = VBoxContainer.new()
	_tuning_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tuning_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tuning_container.visible = _tuning_toggle.button_pressed

	_tuning_scroll = ScrollContainer.new()
	_tuning_scroll.custom_minimum_size = Vector2(0.0, 260.0)
	_tuning_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tuning_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tuning_list = VBoxContainer.new()
	_tuning_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tuning_scroll.add_child(_tuning_list)
	_tuning_container.add_child(_tuning_scroll)

	var preset_title: Label = Label.new()
	preset_title.text = "Override Presets"
	_tuning_container.add_child(preset_title)

	var preset_row: HBoxContainer = HBoxContainer.new()
	_preset_list = OptionButton.new()
	_preset_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preset_row.add_child(_preset_list)
	_load_preset_btn = Button.new()
	_load_preset_btn.text = "Load"
	_load_preset_btn.pressed.connect(_on_load_preset_pressed)
	preset_row.add_child(_load_preset_btn)
	_tuning_container.add_child(preset_row)

	var save_row: HBoxContainer = HBoxContainer.new()
	_preset_name_edit = LineEdit.new()
	_preset_name_edit.placeholder_text = "Preset name"
	_preset_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(_preset_name_edit)
	_save_preset_btn = Button.new()
	_save_preset_btn.text = "Save Settings"
	_save_preset_btn.pressed.connect(_on_save_preset_pressed)
	save_row.add_child(_save_preset_btn)
	_tuning_container.add_child(save_row)

	var revert_row: HBoxContainer = HBoxContainer.new()
	_revert_btn = Button.new()
	_revert_btn.text = "Revert Overrides"
	_revert_btn.pressed.connect(_on_revert_pressed)
	revert_row.add_child(_revert_btn)
	_tuning_container.add_child(revert_row)

	root.add_child(_tuning_container)

	var diag_section: VBoxContainer = _create_section(root, "Diagnostics", SETTINGS_SECTION_DIAG_OPEN, true)
	var endpoint_row: HBoxContainer = HBoxContainer.new()
	var endpoint_label: Label = Label.new()
	endpoint_label.text = "Endpoint"
	endpoint_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	endpoint_row.add_child(endpoint_label)

	_endpoint_edit = LineEdit.new()
	_endpoint_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_endpoint_edit.text = _get_setting(SETTINGS_ENDPOINT, DEFAULT_ENDPOINT)
	_endpoint_edit.text_submitted.connect(_on_endpoint_changed)
	_endpoint_edit.focus_exited.connect(_on_endpoint_focus_exit)
	endpoint_row.add_child(_endpoint_edit)
	diag_section.add_child(endpoint_row)

	var buttons: HBoxContainer = HBoxContainer.new()
	var analyze_btn: Button = Button.new()
	analyze_btn.text = "Analyze"
	analyze_btn.pressed.connect(_on_analyze_pressed)
	buttons.add_child(analyze_btn)

	var ping_btn: Button = Button.new()
	ping_btn.text = "Ping"
	ping_btn.pressed.connect(_on_ping_pressed)
	buttons.add_child(ping_btn)

	var clear_btn: Button = Button.new()
	clear_btn.text = "Clear"
	clear_btn.pressed.connect(_on_clear_pressed)
	buttons.add_child(clear_btn)

	var capture_debug_btn: Button = Button.new()
	capture_debug_btn.text = "Capture Debug"
	capture_debug_btn.pressed.connect(_on_debug_capture_pressed)
	buttons.add_child(capture_debug_btn)

	var respawn_btn: Button = Button.new()
	respawn_btn.text = "Respawn NPCs"
	respawn_btn.pressed.connect(_on_respawn_npcs_pressed)
	buttons.add_child(respawn_btn)

	var pose_report_btn: Button = Button.new()
	pose_report_btn.text = "Pose Report"
	pose_report_btn.pressed.connect(_on_pose_report_pressed)
	buttons.add_child(pose_report_btn)
	diag_section.add_child(buttons)

	_auto_check = CheckBox.new()
	_auto_check.text = "Auto-analyze on error"
	_auto_check.button_pressed = bool(_get_setting(SETTINGS_AUTO, true))
	_auto_check.toggled.connect(_on_auto_toggled)
	diag_section.add_child(_auto_check)

	_output = TextEdit.new()
	_set_text_edit_readonly(_output)
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output.custom_minimum_size = Vector2(0.0, 260.0)
	diag_section.add_child(_output)

	var chat_section: VBoxContainer = _create_section(root, "LLM Chat", SETTINGS_SECTION_CHAT_OPEN, true)
	var chat_opts: HBoxContainer = HBoxContainer.new()
	_include_diag = CheckBox.new()
	_include_diag.text = "Include diagnostics"
	_include_diag.button_pressed = bool(_get_setting(SETTINGS_INCLUDE_DIAG, true))
	_include_diag.toggled.connect(_on_include_changed)
	chat_opts.add_child(_include_diag)

	_include_index = CheckBox.new()
	_include_index.text = "Include project index"
	_include_index.button_pressed = bool(_get_setting(SETTINGS_INCLUDE_INDEX, true))
	_include_index.toggled.connect(_on_include_changed)
	chat_opts.add_child(_include_index)

	_include_screenshot = CheckBox.new()
	_include_screenshot.text = "Include screenshot data"
	_include_screenshot.button_pressed = bool(_get_setting(SETTINGS_INCLUDE_SCREENSHOT, false))
	_include_screenshot.toggled.connect(_on_include_changed)
	chat_opts.add_child(_include_screenshot)

	_include_inspector = CheckBox.new()
	_include_inspector.text = "Include inspector data"
	_include_inspector.button_pressed = bool(_get_setting(SETTINGS_INCLUDE_INSPECTOR, false))
	_include_inspector.toggled.connect(_on_include_changed)
	chat_opts.add_child(_include_inspector)
	chat_section.add_child(chat_opts)

	_chat_history = TextEdit.new()
	_set_text_edit_readonly(_chat_history)
	_set_text_edit_wrap(_chat_history)
	_chat_history.custom_minimum_size = Vector2(0.0, 220.0)
	_chat_history.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_section.add_child(_chat_history)

	var input_row: HBoxContainer = HBoxContainer.new()
	_chat_input = TextEdit.new()
	_set_text_edit_wrap(_chat_input)
	_chat_input.custom_minimum_size = Vector2(0.0, 80.0)
	_chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_input.gui_input.connect(_on_chat_input_gui_input)
	input_row.add_child(_chat_input)
	_send_chat_btn = Button.new()
	_send_chat_btn.text = "Send"
	_send_chat_btn.pressed.connect(_on_send_chat_pressed)
	input_row.add_child(_send_chat_btn)
	chat_section.add_child(input_row)

	var chat_buttons: HBoxContainer = HBoxContainer.new()
	_capture_btn = Button.new()
	_capture_btn.text = "Capture"
	_capture_btn.pressed.connect(_on_capture_pressed)
	chat_buttons.add_child(_capture_btn)

	_clear_chat_btn = Button.new()
	_clear_chat_btn.text = "Clear Chat"
	_clear_chat_btn.pressed.connect(_on_clear_chat_pressed)
	chat_buttons.add_child(_clear_chat_btn)
	chat_section.add_child(chat_buttons)

	_screenshot_label = Label.new()
	_screenshot_label.text = "Screenshot: none"
	chat_section.add_child(_screenshot_label)

	var overrides_section: VBoxContainer = _create_section(root, "Suggested Overrides", SETTINGS_SECTION_OVERRIDES_OPEN, true)
	var overrides_label: Label = Label.new()
	overrides_label.text = "Suggested Overrides (JSON)"
	overrides_section.add_child(overrides_label)

	_overrides_edit = TextEdit.new()
	_overrides_edit.custom_minimum_size = Vector2(0.0, 120.0)
	_overrides_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	overrides_section.add_child(_overrides_edit)

	var overrides_buttons: HBoxContainer = HBoxContainer.new()
	_apply_overrides_btn = Button.new()
	_apply_overrides_btn.text = "Apply Overrides"
	_apply_overrides_btn.pressed.connect(_on_apply_overrides_pressed)
	overrides_buttons.add_child(_apply_overrides_btn)
	overrides_section.add_child(overrides_buttons)


	_status = Label.new()
	_status.text = "Idle"
	root.add_child(_status)

	_http = HTTPRequest.new()
	_http.request_completed.connect(_on_request_completed)
	root.add_child(_http)

	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.one_shot = false
	_timer.autostart = true
	_timer.timeout.connect(_on_timer)
	root.add_child(_timer)

	_build_tuning_controls()
	_apply_color_coding(_color_check.button_pressed)
	_load_preset_bank()
	_refresh_preset_list()
	_load_initial_overrides()
	_load_chat_history()

	return scroll


func _on_endpoint_changed(new_text: String) -> void:
	_set_setting(SETTINGS_ENDPOINT, new_text)


func _on_endpoint_focus_exit() -> void:
	_set_setting(SETTINGS_ENDPOINT, _endpoint_edit.text)


func _on_auto_toggled(enabled: bool) -> void:
	_set_setting(SETTINGS_AUTO, enabled)


func _on_tuning_toggled(opened: bool) -> void:
	_set_setting(SETTINGS_TUNING_OPEN, opened)
	if _tuning_container != null:
		_tuning_container.visible = opened


func _on_color_toggled(enabled: bool) -> void:
	_set_setting(SETTINGS_COLOR, enabled)
	_apply_color_coding(enabled)


func _on_revert_pressed() -> void:
	var defaults: Dictionary = _build_default_overrides()
	_apply_overrides_to_controls(defaults, true)
	_status.text = "Overrides reverted"


func _on_section_toggled(opened: bool, setting_key: String, container: Control) -> void:
	_set_setting(setting_key, opened)
	if container != null:
		container.visible = opened


func _on_analyze_pressed() -> void:
	_send_analyze()


func _on_send_chat_pressed() -> void:
	_send_chat()


func _on_clear_chat_pressed() -> void:
	_chat_messages.clear()
	if _chat_history != null:
		_chat_history.text = ""
	_overrides_edit.text = ""
	_status.text = "Chat cleared"
	_persist_chat_history()


func _on_capture_pressed() -> void:
	var path: String = _capture_screenshot()
	if path != "":
		_screenshot_label.text = "Screenshot: %s" % path
		_status.text = "Captured"
	else:
		_status.text = "Capture failed"


func _on_apply_overrides_pressed() -> void:
	var raw: String = _overrides_edit.text.strip_edges()
	if raw == "":
		_status.text = "Overrides empty"
		return
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		_status.text = "Invalid overrides JSON"
		return
	var overrides: Dictionary = parsed as Dictionary
	if overrides.has("overrides") and overrides.get("overrides") is Dictionary:
		overrides = overrides.get("overrides") as Dictionary
	var filtered: Dictionary = _filter_overrides(overrides)
	if filtered.is_empty():
		_status.text = "No safe overrides"
		return
	_write_overrides(filtered)
	_apply_overrides_to_controls(filtered, false)
	_status.text = "Overrides applied"


func _on_ping_pressed() -> void:
	var endpoint: String = _endpoint_edit.text.strip_edges()
	var health: String = endpoint.replace("/analyze", "/health")
	_status.text = "Pinging..."
	_http.request(health)


func _on_clear_pressed() -> void:
	_output.text = ""
	_status.text = "Cleared"


func _on_timer() -> void:
	if _auto_check == null or not _auto_check.button_pressed:
		return
	var log_path: String = "res://godot_check.log"
	if not FileAccess.file_exists(log_path):
		return
	var mtime: int = FileAccess.get_modified_time(log_path)
	if mtime <= 0 or mtime == _last_mtime:
		return
	_last_mtime = mtime
	var tail: String = _read_tail(log_path, _get_log_tail_lines())
	if tail.find("ERROR") == -1 and tail.find("Parse Error") == -1:
		return
	_send_analyze()


func _send_analyze() -> void:
	var endpoint: String = _endpoint_edit.text.strip_edges()
	if endpoint == "":
		_status.text = "Endpoint missing"
		return
	var payload: Dictionary = _collect_payload(
		_include_diag.button_pressed,
		_include_index.button_pressed,
		_include_screenshot.button_pressed,
		_include_inspector.button_pressed
	)
	var body: String = JSON.stringify({"payload": payload})
	var headers: PackedStringArray = ["Content-Type: application/json"]
	_pending_mode = "analyze"
	_status.text = "Analyzing..."
	_http.request(endpoint, headers, HTTPClient.METHOD_POST, body)


func _send_chat() -> void:
	var text: String = _chat_input.text.strip_edges()
	if text == "":
		return
	_append_chat("user", text)
	_chat_input.text = ""

	var context: Dictionary = _collect_payload(
		_include_diag.button_pressed,
		_include_index.button_pressed,
		_include_screenshot.button_pressed,
		_include_inspector.button_pressed
	)
	var messages: Array = []
	if _include_diag.button_pressed or _include_index.button_pressed or _include_screenshot.button_pressed or _include_inspector.button_pressed:
		messages.append({
			"role": "user",
			"content": "Context:\n" + JSON.stringify(context, "\t")
		})
	for msg: Dictionary in _chat_messages:
		messages.append(msg)

	var endpoint: String = _chat_endpoint()
	var body: String = JSON.stringify({"messages": messages})
	var headers: PackedStringArray = ["Content-Type: application/json"]
	_pending_mode = "chat"
	_status.text = "Chatting..."
	_http.request(endpoint, headers, HTTPClient.METHOD_POST, body)


func _on_request_completed(result: int, response_code: int,
		headers: PackedStringArray, body: PackedByteArray) -> void:
	var text: String = body.get_string_from_utf8()
	if result != HTTPRequest.RESULT_SUCCESS:
		_status.text = "Request failed"
		_output.text = text
		return
	if response_code < 200 or response_code >= 300:
		_status.text = "HTTP %d" % response_code
		_output.text = text
		return
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_status.text = "Invalid JSON"
		_output.text = text
		return
	var data: Dictionary = parsed as Dictionary
	var content: String = ""
	if data.has("analysis"):
		content = str(data.get("analysis", ""))
	elif data.has("response"):
		content = str(data.get("response", ""))
	else:
		content = text
	if _pending_mode == "chat":
		_append_chat("assistant", content)
		_extract_overrides(content)
		_status.text = "Chat done"
	else:
		_output.text = content
		_status.text = "Done"


func _collect_payload(include_diag: bool, include_index: bool, include_screenshot: bool, include_inspector: bool) -> Dictionary:
	var payload: Dictionary = {}
	var project_name: String = str(ProjectSettings.get_setting("application/config/name"))
	var project_root: String = ProjectSettings.globalize_path("res://")
	var version: Dictionary = Engine.get_version_info()
	payload["project"] = {
		"name": project_name,
		"root": project_root,
		"engine": version,
	}
	if include_diag:
		payload["diagnostics"] = {
			"godot_check_tail": _read_tail("res://godot_check.log", _get_log_tail_lines()),
			"ragdoll_log_tail": _read_latest_log_tail(),
			"timestamp": Time.get_datetime_string_from_system(),
		}
	if include_index:
		payload["project_index"] = _build_project_index()
	if include_screenshot:
		payload["screenshot"] = _get_screenshot_payload()
	if include_inspector:
		payload["inspector"] = _collect_inspector_payload()
	return payload


func _read_tail(path: String, max_lines: int) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	var lines: PackedStringArray = text.split("\n")
	if lines.size() <= max_lines:
		return text
	var start: int = max(lines.size() - max_lines, 0)
	var subset: PackedStringArray = lines.slice(start, lines.size())
	return "\n".join(subset)


func _read_latest_log_tail() -> String:
	var log_dir: String = OS.get_user_data_dir().path_join("logs")
	var dir: DirAccess = DirAccess.open(log_dir)
	if dir == null:
		return ""
	dir.list_dir_begin()
	var newest_path: String = ""
	var newest_time: int = 0
	var entry_name: String = dir.get_next()
	while entry_name != "":
		if not dir.current_is_dir() and entry_name.ends_with(".jsonl"):
			var full: String = log_dir.path_join(entry_name)
			var mtime: int = FileAccess.get_modified_time(full)
			if mtime > newest_time:
				newest_time = mtime
				newest_path = full
		entry_name = dir.get_next()
	dir.list_dir_end()
	return _read_tail(newest_path, _get_log_tail_lines())


func _get_log_tail_lines() -> int:
	return int(_get_setting(SETTINGS_LINES, 200))


func _get_setting(key: String, default_value: Variant) -> Variant:
	var settings: EditorSettings = get_editor_interface().get_editor_settings()
	if not settings.has_setting(key):
		settings.set_setting(key, default_value)
	return settings.get_setting(key)


func _set_setting(key: String, value: Variant) -> void:
	var settings: EditorSettings = get_editor_interface().get_editor_settings()
	settings.set_setting(key, value)
	if settings.has_method("save"):
		settings.call("save")


func _on_include_changed(_enabled: bool) -> void:
	_set_setting(SETTINGS_INCLUDE_DIAG, _include_diag.button_pressed)
	_set_setting(SETTINGS_INCLUDE_INDEX, _include_index.button_pressed)
	_set_setting(SETTINGS_INCLUDE_SCREENSHOT, _include_screenshot.button_pressed)
	_set_setting(SETTINGS_INCLUDE_INSPECTOR, _include_inspector.button_pressed)


func _append_chat(role: String, content: String) -> void:
	_chat_messages.append({"role": role, "content": content})
	if _chat_messages.size() > MAX_CHAT_MESSAGES:
		_chat_messages = _chat_messages.slice(_chat_messages.size() - MAX_CHAT_MESSAGES, _chat_messages.size())
	if _chat_history != null:
		var prefix: String = "You" if role == "user" else "LLM"
		_chat_history.text += "%s: %s\n\n" % [prefix, content]
		call_deferred("_scroll_chat_to_bottom")
	_write_chat_log(role, content)
	_persist_chat_history()


func _on_chat_input_gui_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null:
		return
	if not key.pressed or key.echo:
		return
	if key.keycode != KEY_ENTER and key.keycode != KEY_KP_ENTER:
		return
	if key.shift_pressed:
		if _chat_input != null and _chat_input.has_method("insert_text_at_caret"):
			_chat_input.call("insert_text_at_caret", "\n")
			_chat_input.accept_event()
		return
	_on_send_chat_pressed()
	if _chat_input != null:
		_chat_input.accept_event()


func _on_debug_capture_pressed() -> void:
	var diag: Node = get_tree().root.get_node_or_null(^"RagdollDiagnostics")
	if diag == null:
		_status.text = "Debug capture not found"
		return
	if diag.has_method(&"dump_snapshot"):
		diag.call(&"dump_snapshot", "plugin_capture")
		_status.text = "Debug snapshot captured"
		return
	if diag.has_method(&"_dump_snapshot"):
		diag.call(&"_dump_snapshot", "plugin_capture")
		_status.text = "Debug snapshot captured"
		return
	_status.text = "Debug capture unsupported"


func _on_respawn_npcs_pressed() -> void:
	var nodes: Array = []
	var runtime_root: Node = _get_playing_scene_root()
	if runtime_root != null:
		nodes = _find_npc_nodes(runtime_root)
	else:
		var tree: SceneTree = get_tree()
		if tree != null:
			nodes = tree.get_nodes_in_group(&"npc")
		if nodes.is_empty():
			var editor: EditorInterface = get_editor_interface()
			if editor != null and editor.has_method("get_edited_scene_root"):
				var root: Node = editor.call("get_edited_scene_root")
				if root != null:
					nodes = _find_npc_nodes(root)
		if Engine.is_editor_hint() and runtime_root == null:
			_write_respawn_request()
			_status.text = "Respawn requested"
			return
	var respawned: int = 0
	for node: Node in nodes:
		if node == null:
			continue
		if node.has_method("is_placeholder_instance"):
			var placeholder: bool = bool(node.call("is_placeholder_instance"))
			if placeholder:
				continue
		if node.has_method(&"respawn"):
			node.call(&"respawn")
			respawned += 1
	if respawned <= 0:
		_status.text = "No NPCs to respawn"
		return
	_status.text = "Respawned %d NPCs" % respawned
	_rescan_command_system()


func _on_pose_report_pressed() -> void:
	var npc_name: String = _get_selected_npc_name()
	_write_pose_report_request(npc_name)
	_status.text = "Pose report requested"


func _write_respawn_request() -> void:
	_ensure_dir(RESPAWN_REQUEST_PATH)
	var file: FileAccess = FileAccess.open(RESPAWN_REQUEST_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_line(JSON.stringify({"time_ms": Time.get_ticks_msec()}))
	file.close()


func _write_pose_report_request(npc_name: String) -> void:
	_ensure_dir(POSE_REPORT_REQUEST_PATH)
	var file: FileAccess = FileAccess.open(POSE_REPORT_REQUEST_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_line(JSON.stringify({
		"time_ms": Time.get_ticks_msec(),
		"npc_name": npc_name,
	}))
	file.close()


func _get_selected_npc_name() -> String:
	var nodes: Array = _get_inspector_nodes()
	for node: Node in nodes:
		if node == null:
			continue
		if _is_npc_node(node):
			var name_val: Variant = node.get("npc_name")
			if name_val is String and str(name_val) != "":
				return str(name_val)
			return str(node.name)
	return ""


func _get_playing_scene_root() -> Node:
	var editor: EditorInterface = get_editor_interface()
	if editor == null:
		return null
	if editor.has_method("get_playing_scene_root"):
		var root_variant: Variant = editor.call("get_playing_scene_root")
		if root_variant is Node:
			return root_variant as Node
	if editor.has_method("get_playing_scene"):
		var playing: Variant = editor.call("get_playing_scene")
		if playing is Node:
			return playing as Node
	return null


func _rescan_command_system() -> void:
	var runtime_root: Node = _get_playing_scene_root()
	var tree: SceneTree = runtime_root.get_tree() if runtime_root != null else get_tree()
	if tree == null:
		return
	var players: Array = tree.get_nodes_in_group(&"player")
	for player: Node in players:
		for child: Node in player.get_children():
			if child.has_method(&"rescan"):
				child.call(&"rescan")


func _rebuild_chat_history() -> void:
	if _chat_history == null:
		return
	_chat_history.text = ""
	for msg: Dictionary in _chat_messages:
		var role: String = str(msg.get("role", ""))
		var content: String = str(msg.get("content", ""))
		var prefix: String = "You" if role == "user" else "LLM"
		_chat_history.text += "%s: %s\n\n" % [prefix, content]
	call_deferred("_scroll_chat_to_bottom")


func _scroll_chat_to_bottom() -> void:
	if _chat_history == null:
		return
	var line_count: int = 0
	if _chat_history.has_method("get_line_count"):
		line_count = int(_chat_history.call("get_line_count"))
	if _chat_history.has_method("scroll_to_line"):
		_chat_history.call("scroll_to_line", max(0, line_count - 1))
		return
	if _chat_history.has_method("set_v_scroll"):
		_chat_history.call("set_v_scroll", line_count)
		return
	if _has_property(_chat_history, "scroll_vertical"):
		_chat_history.set("scroll_vertical", line_count)


func _persist_chat_history() -> void:
	_ensure_dir(CHAT_HISTORY_PATH)
	var file: FileAccess = FileAccess.open(CHAT_HISTORY_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_line(JSON.stringify({"messages": _chat_messages}))
	file.close()


func _write_chat_log(role: String, content: String) -> void:
	_ensure_dir(CHAT_LOG_PATH)
	var file: FileAccess = FileAccess.open(CHAT_LOG_PATH, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(CHAT_LOG_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line(JSON.stringify({
		"time_ms": Time.get_ticks_msec(),
		"role": role,
		"content": content,
	}))
	file.close()


func _load_chat_history() -> void:
	if not FileAccess.file_exists(CHAT_HISTORY_PATH):
		return
	var file: FileAccess = FileAccess.open(CHAT_HISTORY_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var data: Dictionary = parsed as Dictionary
	var messages: Array = data.get("messages", []) as Array
	if messages.is_empty():
		return
	_chat_messages = messages
	if _chat_messages.size() > MAX_CHAT_MESSAGES:
		_chat_messages = _chat_messages.slice(_chat_messages.size() - MAX_CHAT_MESSAGES, _chat_messages.size())
	_rebuild_chat_history()


func _extract_overrides(text: String) -> void:
	var overrides: Dictionary = _parse_json_block(text)
	if overrides.is_empty():
		return
	if overrides.has("overrides") and overrides.get("overrides") is Dictionary:
		overrides = overrides.get("overrides") as Dictionary
	var filtered: Dictionary = _filter_overrides(overrides)
	if filtered.is_empty():
		return
	_overrides_edit.text = JSON.stringify(filtered, "\t")


func _parse_json_block(text: String) -> Dictionary:
	var start: int = text.find("```json")
	if start == -1:
		return {}
	var end: int = text.find("```", start + 6)
	if end == -1:
		return {}
	var json_text: String = text.substr(start + 7, end - (start + 7)).strip_edges()
	var parsed: Variant = JSON.parse_string(json_text)
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed as Dictionary
	return {}


func _filter_overrides(overrides: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: String in overrides:
		if not SAFE_OVERRIDE_KEYS.has(key):
			continue
		var val: Variant = overrides[key]
		if val is float or val is int or val is bool:
			out[key] = val
	return out


func _write_overrides(overrides: Dictionary) -> void:
	_ensure_dir(OVERRIDES_PATH)
	var file: FileAccess = FileAccess.open(OVERRIDES_PATH, FileAccess.WRITE)
	if file != null:
		file.store_line(JSON.stringify({"overrides": overrides}))
		file.close()
	_write_overrides_log(overrides)


func _write_overrides_log(overrides: Dictionary) -> void:
	_ensure_dir(OVERRIDES_LOG_PATH)
	var file: FileAccess = FileAccess.open(OVERRIDES_LOG_PATH, FileAccess.READ_WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line(JSON.stringify({
		"time_ms": Time.get_ticks_msec(),
		"overrides": overrides,
	}))
	file.close()


func _capture_screenshot() -> String:
	var viewport: Viewport = null
	var editor: EditorInterface = get_editor_interface()
	if editor != null:
		var base: Control = editor.get_base_control()
		if base != null:
			viewport = base.get_viewport()
	if viewport == null:
		viewport = get_tree().root
	if viewport == null:
		return ""
	var tex: Texture2D = viewport.get_texture()
	if tex == null:
		return ""
	var img: Image = tex.get_image()
	if img == null:
		return ""
	img.flip_y()
	var size: Vector2i = img.get_size()
	if max(size.x, size.y) > MAX_SCREENSHOT_EDGE:
		var scale: float = float(MAX_SCREENSHOT_EDGE) / float(max(size.x, size.y))
		img.resize(int(size.x * scale), int(size.y * scale), Image.INTERPOLATE_BILINEAR)
	_ensure_dir_path(SCREENSHOT_DIR)
	var stamp: String = Time.get_datetime_string_from_system().replace(":", "-")
	var path: String = SCREENSHOT_DIR.path_join("llm_shot_%s.png" % stamp)
	img.save_png(path)
	_last_screenshot_path = path
	var buffer: PackedByteArray = img.save_png_to_buffer()
	_last_screenshot_b64 = Marshalls.raw_to_base64(buffer)
	return path


func _get_screenshot_payload() -> Dictionary:
	if _last_screenshot_path == "":
		return {}
	return {
		"path": _last_screenshot_path,
		"png_base64": _last_screenshot_b64,
	}


func _collect_inspector_payload() -> Array:
	var nodes: Array = _get_inspector_nodes()
	var out: Array = []
	for node: Node in nodes:
		if node == null:
			continue
		out.append({
			"node_path": str(node.get_path()),
			"node_name": str(node.name),
			"node_class": str(node.get_class()),
			"properties": _collect_node_properties(node),
		})
	return out


func _get_inspector_nodes() -> Array:
	var nodes: Array = []
	var editor: EditorInterface = get_editor_interface()
	if editor != null and editor.has_method("get_selection"):
		var selection: Object = editor.call("get_selection")
		if selection != null and selection.has_method("get_selected_nodes"):
			var selected: Array = selection.call("get_selected_nodes")
			for item: Variant in selected:
				if item is Node:
					nodes.append(item)
	if nodes.is_empty() and editor != null and editor.has_method("get_edited_scene_root"):
		var root: Node = editor.call("get_edited_scene_root")
		if root != null:
			nodes = _find_npc_nodes(root)
	var filtered: Array = []
	for node: Node in nodes:
		if _is_npc_node(node):
			filtered.append(node)
	if not filtered.is_empty():
		return filtered
	return nodes


func _find_npc_nodes(root: Node) -> Array:
	var out: Array = []
	if root == null:
		return out
	if _is_npc_node(root):
		out.append(root)
	for child: Node in root.get_children():
		out.append_array(_find_npc_nodes(child))
	return out


func _is_npc_node(node: Node) -> bool:
	if node == null:
		return false
	if str(node.get_class()) == "NPCPlaceholder":
		return true
	var script: Script = node.get_script() as Script
	if script != null:
		var path: String = script.resource_path
		if path.ends_with("/npc_placeholder.gd"):
			return true
	return false


func _collect_node_properties(node: Node) -> Dictionary:
	var out: Dictionary = {}
	if node == null:
		return out
	var props: Array = node.get_property_list()
	for prop: Variant in props:
		if not (prop is Dictionary):
			continue
		var info: Dictionary = prop as Dictionary
		var prop_name: String = str(info.get("name", ""))
		if prop_name == "" or prop_name == "script":
			continue
		var usage: int = int(info.get("usage", 0))
		if usage & PROPERTY_USAGE_EDITOR == 0:
			continue
		var value: Variant = node.get(prop_name)
		out[prop_name] = _serialize_inspector_value(value)
	return out


func _serialize_inspector_value(value: Variant) -> Variant:
	var value_type: int = typeof(value)
	match value_type:
		TYPE_NIL:
			return null
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return value
		TYPE_COLOR:
			var color: Color = value
			return {"r": color.r, "g": color.g, "b": color.b, "a": color.a}
		TYPE_VECTOR2:
			var vec2: Vector2 = value
			return {"x": vec2.x, "y": vec2.y}
		TYPE_VECTOR3:
			var vec3: Vector3 = value
			return {"x": vec3.x, "y": vec3.y, "z": vec3.z}
		TYPE_VECTOR2I:
			var vec2i: Vector2i = value
			return {"x": vec2i.x, "y": vec2i.y}
		TYPE_VECTOR3I:
			var vec3i: Vector3i = value
			return {"x": vec3i.x, "y": vec3i.y, "z": vec3i.z}
		TYPE_NODE_PATH:
			return str(value)
		TYPE_OBJECT:
			if value is Resource:
				var res: Resource = value
				if res.resource_path != "":
					return res.resource_path
				return res.get_class()
			return str(value)
		_:
			return str(value)


func _build_project_index() -> Array:
	var max_files: int = int(_get_setting(SETTINGS_INDEX_MAX, DEFAULT_INDEX_MAX))
	var exts: PackedStringArray = ["gd", "tscn", "tres", "cfg", "json", "md", "ini"]
	var out: Array = []
	var root: String = "res://"
	var stack: Array = [root]
	while not stack.is_empty() and out.size() < max_files:
		var dir_path: String = stack.pop_back()
		var dir: DirAccess = DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry_name: String = dir.get_next()
		while entry_name != "" and out.size() < max_files:
			if entry_name.begins_with("."):
				entry_name = dir.get_next()
				continue
			var full: String = dir_path.path_join(entry_name)
			if dir.current_is_dir():
				stack.append(full)
			else:
				var ext: String = entry_name.get_extension().to_lower()
				if exts.has(ext):
					var size: int = 0
					var file: FileAccess = FileAccess.open(full, FileAccess.READ)
					if file != null:
						size = int(file.get_length())
						file.close()
					out.append({"path": full, "size": size})
			entry_name = dir.get_next()
		dir.list_dir_end()
	return out


func _chat_endpoint() -> String:
	var endpoint: String = _endpoint_edit.text.strip_edges()
	if endpoint == "":
		return ""
	return endpoint.replace("/analyze", "/chat")


func _build_tuning_controls() -> void:
	if _tuning_list == null:
		return
	for child: Node in _tuning_list.get_children():
		child.queue_free()
	_slider_controls.clear()
	_toggle_controls.clear()
	_slider_overrides.clear()
	_color_labels.clear()
	_suspend_slider_events = true
	for item: Dictionary in TUNING_LAYOUT:
		var item_type: String = str(item.get("type", ""))
		if item_type == "section":
			_add_tuning_section(str(item.get("label", "")))
			continue
		if item_type == "slider":
			_create_slider_row(item)
			continue
		if item_type == "toggle":
			_create_toggle_row(item)
			continue
	_suspend_slider_events = false
	_slider_overrides = _build_default_overrides()
	_overrides_edit.text = JSON.stringify(_slider_overrides, "\t")


func _add_tuning_section(label: String) -> void:
	if label == "":
		return
	var section: Label = Label.new()
	section.text = label
	section.add_theme_font_size_override("font_size", 13)
	_tuning_list.add_child(section)
	var color: Color = Color(0.9, 0.9, 0.9)
	if SECTION_COLORS.has(label):
		color = SECTION_COLORS[label] as Color
	_color_labels.append({"label": section, "color": color})


func _apply_color_coding(enabled: bool) -> void:
	for item: Dictionary in _color_labels:
		var label: Label = item.get("label", null) as Label
		if label == null:
			continue
		if not enabled:
			label.remove_theme_color_override("font_color")
			continue
		var color: Color = item.get("color", Color(0.9, 0.9, 0.9)) as Color
		label.add_theme_color_override("font_color", color)


func _create_section(parent: VBoxContainer, title: String, setting_key: String, default_open: bool) -> VBoxContainer:
	var header: Button = Button.new()
	header.text = title
	header.toggle_mode = true
	header.button_pressed = bool(_get_setting(setting_key, default_open))
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(header)

	var container: VBoxContainer = VBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.visible = header.button_pressed
	parent.add_child(container)

	header.toggled.connect(_on_section_toggled.bind(setting_key, container))
	return container


func _create_slider_row(def: Dictionary) -> void:
	var key: String = str(def.get("key", ""))
	if key == "":
		return
	var row: HBoxContainer = HBoxContainer.new()
	var label: Label = Label.new()
	label.text = str(def.get("label", key))
	label.custom_minimum_size = Vector2(160.0, 0.0)
	if TUNING_DESCRIPTIONS.has(key):
		label.tooltip_text = str(TUNING_DESCRIPTIONS[key])
	row.add_child(label)

	var slider: HSlider = HSlider.new()
	slider.min_value = float(def.get("min", 0.0))
	slider.max_value = float(def.get("max", 1.0))
	slider.step = float(def.get("step", 0.01))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)

	var value_edit: LineEdit = LineEdit.new()
	value_edit.custom_minimum_size = Vector2(72.0, 0.0)
	row.add_child(value_edit)

	var default_val: float = float(def.get("default", 0.0))
	_slider_controls[key] = {"slider": slider, "edit": value_edit}
	_slider_overrides[key] = _normalize_override_value(key, default_val)
	_update_slider_text(key, default_val)
	slider.value = default_val

	slider.value_changed.connect(_on_slider_changed.bind(key))
	value_edit.text_submitted.connect(_on_slider_text_submitted.bind(key))
	value_edit.focus_exited.connect(_on_slider_focus_exited.bind(key))
	_tuning_list.add_child(row)


func _create_toggle_row(def: Dictionary) -> void:
	var key: String = str(def.get("key", ""))
	if key == "":
		return
	var toggle: CheckBox = CheckBox.new()
	toggle.text = str(def.get("label", key))
	if TUNING_DESCRIPTIONS.has(key):
		toggle.tooltip_text = str(TUNING_DESCRIPTIONS[key])
	var default_val: bool = bool(def.get("default", false))
	_toggle_controls[key] = toggle
	_slider_overrides[key] = default_val
	toggle.button_pressed = default_val
	toggle.toggled.connect(_on_toggle_changed.bind(key))
	_tuning_list.add_child(toggle)


func _build_default_overrides() -> Dictionary:
	var defaults: Dictionary = {}
	for item: Dictionary in TUNING_LAYOUT:
		var item_type: String = str(item.get("type", ""))
		if item_type != "slider" and item_type != "toggle":
			continue
		var key: String = str(item.get("key", ""))
		if key == "":
			continue
		var default_val: Variant = item.get("default", 0.0)
		defaults[key] = _normalize_override_value(key, default_val)
	return _filter_overrides(defaults)


func _on_slider_changed(value: float, key: String) -> void:
	if _suspend_slider_events:
		return
	var slider: HSlider = _get_slider(key)
	if slider == null:
		return
	var snapped: float = snappedf(value, slider.step)
	_update_slider_text(key, snapped)
	_apply_override_value(key, snapped)


func _on_slider_text_submitted(text: String, key: String) -> void:
	var slider: HSlider = _get_slider(key)
	if slider == null:
		return
	var trimmed: String = text.strip_edges()
	if trimmed == "" or not trimmed.is_valid_float():
		return
	var value: float = float(trimmed)
	value = clampf(value, slider.min_value, slider.max_value)
	slider.value = value


func _on_slider_focus_exited(key: String) -> void:
	var edit: LineEdit = _get_slider_edit(key)
	if edit == null:
		return
	_on_slider_text_submitted(edit.text, key)


func _on_toggle_changed(pressed: bool, key: String) -> void:
	if _suspend_slider_events:
		return
	_apply_override_value(key, pressed)


func _apply_override_value(key: String, value: Variant) -> void:
	var overrides: Dictionary = _get_current_overrides()
	overrides[key] = _normalize_override_value(key, value)
	overrides = _filter_overrides(overrides)
	_slider_overrides = overrides
	_overrides_edit.text = JSON.stringify(overrides, "\t")
	_write_overrides(overrides)
	_status.text = "Overrides updated"


func _apply_overrides_to_controls(overrides: Dictionary, write_file: bool) -> void:
	if overrides.is_empty():
		return
	var filtered: Dictionary = _filter_overrides(overrides)
	if filtered.is_empty():
		return
	var normalized: Dictionary = {}
	_suspend_slider_events = true
	for key: String in filtered:
		var val: Variant = _normalize_override_value(key, filtered[key])
		normalized[key] = val
		if _slider_controls.has(key):
			var slider: HSlider = _get_slider(key)
			if slider != null:
				var clamped: float = clampf(float(val), slider.min_value, slider.max_value)
				slider.value = clamped
				_update_slider_text(key, clamped)
		if _toggle_controls.has(key):
			var toggle: CheckBox = _toggle_controls[key] as CheckBox
			if toggle != null:
				toggle.button_pressed = bool(val)
	_suspend_slider_events = false
	_slider_overrides = normalized
	_overrides_edit.text = JSON.stringify(normalized, "\t")
	if write_file:
		_write_overrides(normalized)


func _get_current_overrides() -> Dictionary:
	var raw: String = _overrides_edit.text.strip_edges()
	if raw != "":
		var parsed: Variant = JSON.parse_string(raw)
		if typeof(parsed) == TYPE_DICTIONARY:
			var data: Dictionary = parsed as Dictionary
			if data.has("overrides") and data.get("overrides") is Dictionary:
				return _filter_overrides(data.get("overrides") as Dictionary)
			return _filter_overrides(data)
	return _filter_overrides(_slider_overrides)


func _load_initial_overrides() -> void:
	if not FileAccess.file_exists(OVERRIDES_PATH):
		return
	var file: FileAccess = FileAccess.open(OVERRIDES_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var data: Dictionary = parsed as Dictionary
	var overrides: Dictionary = {}
	if data.has("overrides") and data.get("overrides") is Dictionary:
		overrides = data.get("overrides") as Dictionary
	else:
		overrides = data
	_apply_overrides_to_controls(overrides, false)


func _load_preset_bank() -> void:
	_preset_bank.clear()
	if not FileAccess.file_exists(OVERRIDES_BANK_PATH):
		return
	var file: FileAccess = FileAccess.open(OVERRIDES_BANK_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		var data: Dictionary = parsed as Dictionary
		if data.has("presets") and data.get("presets") is Array:
			_preset_bank = data.get("presets") as Array
			return
	if typeof(parsed) == TYPE_ARRAY:
		_preset_bank = parsed as Array


func _save_preset_bank() -> void:
	_ensure_dir(OVERRIDES_BANK_PATH)
	var file: FileAccess = FileAccess.open(OVERRIDES_BANK_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_line(JSON.stringify({"presets": _preset_bank}, "\t"))
	file.close()


func _refresh_preset_list() -> void:
	if _preset_list == null:
		return
	_preset_list.clear()
	if _preset_bank.is_empty():
		_preset_list.add_item("No presets")
		_preset_list.set_item_disabled(0, true)
		return
	for i: int in range(_preset_bank.size()):
		var item: Dictionary = _preset_bank[i] as Dictionary
		var preset_label: String = str(item.get("name", "Preset %d" % [i + 1]))
		_preset_list.add_item(preset_label)


func _on_save_preset_pressed() -> void:
	var overrides: Dictionary = _get_current_overrides()
	if overrides.is_empty():
		_status.text = "No overrides to save"
		return
	var preset_name: String = _preset_name_edit.text.strip_edges()
	if preset_name == "":
		preset_name = _generate_preset_name()
	var updated: bool = false
	for i: int in range(_preset_bank.size()):
		var item: Dictionary = _preset_bank[i] as Dictionary
		if str(item.get("name", "")) == preset_name:
			_preset_bank[i] = {
				"name": preset_name,
				"time_ms": Time.get_ticks_msec(),
				"overrides": overrides,
			}
			updated = true
			break
	if not updated:
		_preset_bank.append({
			"name": preset_name,
			"time_ms": Time.get_ticks_msec(),
			"overrides": overrides,
		})
	_save_preset_bank()
	_refresh_preset_list()
	_select_preset_by_name(preset_name)
	_status.text = "Preset saved"


func _on_load_preset_pressed() -> void:
	if _preset_bank.is_empty():
		_status.text = "No presets"
		return
	var idx: int = _preset_list.selected
	if idx < 0 or idx >= _preset_bank.size():
		_status.text = "Preset missing"
		return
	var preset: Dictionary = _preset_bank[idx] as Dictionary
	var overrides: Dictionary = preset.get("overrides", {}) as Dictionary
	_apply_overrides_to_controls(overrides, true)
	_status.text = "Preset loaded"


func _select_preset_by_name(name: String) -> void:
	if _preset_list == null:
		return
	for i: int in range(_preset_list.item_count):
		if _preset_list.get_item_text(i) == name:
			_preset_list.select(i)
			return


func _generate_preset_name() -> String:
	var stamp: String = Time.get_datetime_string_from_system()
	stamp = stamp.replace(":", "-").replace(" ", "T")
	return "preset-%s" % stamp


func _normalize_override_value(key: String, value: Variant) -> Variant:
	if value is bool:
		return value
	var num: float = float(value)
	if INT_OVERRIDE_KEYS.has(key):
		return int(round(num))
	return num


func _get_slider(key: String) -> HSlider:
	if not _slider_controls.has(key):
		return null
	var data: Dictionary = _slider_controls[key] as Dictionary
	return data.get("slider", null) as HSlider


func _get_slider_edit(key: String) -> LineEdit:
	if not _slider_controls.has(key):
		return null
	var data: Dictionary = _slider_controls[key] as Dictionary
	return data.get("edit", null) as LineEdit


func _update_slider_text(key: String, value: float) -> void:
	var edit: LineEdit = _get_slider_edit(key)
	if edit == null:
		return
	if INT_OVERRIDE_KEYS.has(key):
		edit.text = str(int(round(value)))
		return
	edit.text = String.num(value, 3)


func _ensure_dir(path: String) -> void:
	if path.begins_with("user://"):
		var dir: DirAccess = DirAccess.open("user://")
		if dir == null:
			return
		var rel: String = path.trim_prefix("user://").get_base_dir()
		if rel != "":
			dir.make_dir_recursive(rel)
		return
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())


func _ensure_dir_path(path: String) -> void:
	if path.begins_with("user://"):
		var dir: DirAccess = DirAccess.open("user://")
		if dir == null:
			return
		var rel: String = path.trim_prefix("user://")
		if rel != "":
			dir.make_dir_recursive(rel)
		return
	DirAccess.make_dir_recursive_absolute(path)


func _set_text_edit_readonly(text_edit: TextEdit) -> void:
	if text_edit == null:
		return
	if text_edit.has_method("set_readonly"):
		text_edit.call("set_readonly", true)
		return
	if text_edit.has_method("set_editable"):
		text_edit.call("set_editable", false)
		return
	if _has_property(text_edit, "read_only"):
		text_edit.set("read_only", true)
		return
	if _has_property(text_edit, "readonly"):
		text_edit.set("readonly", true)
		return
	if _has_property(text_edit, "editable"):
		text_edit.set("editable", false)
		return


func _set_text_edit_wrap(text_edit: TextEdit) -> void:
	if text_edit == null:
		return
	if text_edit.has_method("set_wrap_mode"):
		text_edit.call("set_wrap_mode", 2)
		return
	if _has_property(text_edit, "wrap_mode"):
		text_edit.set("wrap_mode", 2)
		return
	if _has_property(text_edit, "line_wrapping_mode"):
		text_edit.set("line_wrapping_mode", 2)
		return
	if text_edit.has_method("set_wrap_enabled"):
		text_edit.call("set_wrap_enabled", true)
		return
	if _has_property(text_edit, "wrap_enabled"):
		text_edit.set("wrap_enabled", true)


func _has_property(obj: Object, property_name: String) -> bool:
	for prop in obj.get_property_list():
		if prop is Dictionary and String(prop.get("name", "")) == property_name:
			return true
	return false
