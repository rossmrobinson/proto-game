class_name DiagnosticsOverlay
extends CanvasLayer
## Debug overlay displaying performance metrics.
## Toggle with F3. Useful for monitoring GTX 1070 performance.

var _visible: bool = false
var _label: Label
var _controls_label: Label
var _ragdoll_diag: Node = null
var _calibration_runner: Node = null
var _calibration_root: Control = null
var _calibration_button: Button = null


func _ready() -> void:
	layer = 100
	_label = Label.new()
	_label.position = Vector2(10.0, 10.0)
	_label.add_theme_font_size_override(&"font_size", 14)
	_label.add_theme_color_override(&"font_color", Color.GREEN)
	_label.visible = false
	add_child(_label)
	_controls_label = Label.new()
	_controls_label.add_theme_font_size_override(&"font_size", 13)
	_controls_label.add_theme_color_override(&"font_color", Color(0.9, 0.9, 0.9, 0.95))
	_controls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_controls_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_controls_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_controls_label.anchor_left = 1.0
	_controls_label.anchor_right = 1.0
	_controls_label.anchor_top = 0.0
	_controls_label.anchor_bottom = 0.0
	_controls_label.offset_left = -360.0
	_controls_label.offset_right = -10.0
	_controls_label.offset_top = 10.0
	_controls_label.offset_bottom = 460.0
	_controls_label.visible = false
	_controls_label.text = _build_controls_text()
	add_child(_controls_label)
	_ragdoll_diag = get_tree().root.get_node_or_null(^"RagdollDiagnostics")
	_calibration_runner = _find_calibration_runner()
	_setup_calibration_button()
	_set_overlay_visible(_visible)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.physical_keycode == KEY_F3:
			_set_overlay_visible(not _visible)
			return
		if event.physical_keycode == KEY_F2:
			_trigger_calibration()
			return


func _process(_delta: float) -> void:
	if not _visible:
		return
	
	var fps: float = Engine.get_frames_per_second()
	var frame_time: float = 1000.0 / maxf(fps, 1.0)
	var static_mem: float = OS.get_static_memory_usage() / 1048576.0
	
	# Object and physics stats
	var object_count: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var node_count: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphan_count: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	
	# Render stats  
	var draw_calls: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var primitives: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var vram_usage: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	
	# Physics
	var physics_active: int = int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))
	
	_label.text = (
		"FPS: %d (%.1f ms)\n" % [fps, frame_time]
		+ "Draw Calls: %d | Primitives: %d\n" % [draw_calls, primitives]
		+ "VRAM: %.0f MB | RAM: %.0f MB\n" % [vram_usage, static_mem]
		+ "Objects: %d | Nodes: %d | Orphans: %d\n" % [object_count, node_count, orphan_count]
		+ "Physics Bodies: %d" % physics_active
	)

	if _ragdoll_diag != null:
		var ragdoll_text: String = _ragdoll_diag.get_overlay_text()
		if ragdoll_text != "":
			_label.text += "\n" + ragdoll_text


func _setup_calibration_button() -> void:
	_calibration_root = Control.new()
	add_child(_calibration_root)
	_calibration_button = Button.new()
	_calibration_button.text = "Calibrate"
	_calibration_button.anchor_left = 1.0
	_calibration_button.anchor_right = 1.0
	_calibration_button.anchor_top = 0.0
	_calibration_button.anchor_bottom = 0.0
	_calibration_button.offset_left = -120.0
	_calibration_button.offset_right = -10.0
	_calibration_button.offset_top = 10.0
	_calibration_button.offset_bottom = 38.0
	_calibration_button.pressed.connect(_on_calibration_pressed)
	_calibration_root.add_child(_calibration_button)


func _set_overlay_visible(next_visible: bool) -> void:
	_visible = next_visible
	_label.visible = _visible
	if _controls_label != null:
		_controls_label.visible = _visible
	if _calibration_button == null:
		return
	_calibration_button.visible = _visible and OS.is_debug_build()


func _build_controls_text() -> String:
	return "Controls:\n" + \
		"LMB/RMB: grab or use held\n" + \
		"Double click: drop\n" + \
		"Double + hold: throw\n" + \
		"Wheel: adjust hold / thrust\n" + \
		"Wheel left/right: rotate pelvis\n" + \
		"Middle x2: press genitals\n" + \
		"Middle hold: autopilot\n" + \
		"CapsLock: free hands\n" + \
		"CapsLock hold: temp override\n" + \
		"Alt: swap hand (hold = both)\n" + \
		"V: toggle camera\n" + \
		"Enter: LLM chat\n" + \
		"F3: overlay"


func _on_calibration_pressed() -> void:
	_trigger_calibration()


func _trigger_calibration() -> void:
	if not OS.is_debug_build():
		return
	if _calibration_runner == null:
		_calibration_runner = _find_calibration_runner()
	if _calibration_runner != null and _calibration_runner.has_method(&"request_start"):
		_calibration_runner.call(&"request_start")
		return
	push_warning("[DiagnosticsOverlay] Calibration runner not found")


func _find_calibration_runner() -> Node:
	var parent: Node = get_parent()
	if parent != null:
		var direct: Node = parent.get_node_or_null("RagdollCalibrationRunner")
		if direct != null:
			return direct
	var nodes: Array = get_tree().get_nodes_in_group(&"ragdoll_calibration")
	if not nodes.is_empty():
		return nodes[0] as Node
	return null
