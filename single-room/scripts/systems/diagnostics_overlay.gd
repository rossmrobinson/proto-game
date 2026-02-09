class_name DiagnosticsOverlay
extends CanvasLayer
## Debug overlay displaying performance metrics.
## Toggle with F3. Useful for monitoring GTX 1070 performance.

var _visible: bool = false
var _label: Label


func _ready() -> void:
	layer = 100
	_label = Label.new()
	_label.position = Vector2(10.0, 10.0)
	_label.add_theme_font_size_override(&"font_size", 14)
	_label.add_theme_color_override(&"font_color", Color.GREEN)
	_label.visible = false
	add_child(_label)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_F3:
		_visible = not _visible
		_label.visible = _visible


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
