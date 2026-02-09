class_name NPCCommandSystem
extends Node
## Cycles through scene NPCs and proxies the player's controls to the
## selected NPC.  Backtick (`) cycles: None/Self → NPC1 → NPC2 → …  → None/Self.
##
## When an NPC is selected ("commanded"), mouse clicks route through the
## commanded NPC's position/orientation instead of the player's.  For example,
## a right-click on another NPC's arm makes the commanded NPC reach out and
## grab that arm with its right hand.
##
## Attach as child of PlayerController.

signal commanded_npc_changed(npc: NPCPlaceholder)
## Fired when cycling back to None/Self.
signal command_cleared()
## Fired when an NPC enters or exits autonomous (loop) mode.
signal npc_autonomy_changed(npc: NPCPlaceholder, autonomous: bool)

# ── State ────────────────────────────────────────────────────────────────────
## Currently commanded NPC, or null when controlling self.
var commanded_npc: NPCPlaceholder = null
## Index into _npc_list.  -1 = None/Self.
var _command_index: int = -1
## Cached list of NPCs in the scene (rebuilt when scene changes).
var _npc_list: Array[NPCPlaceholder] = []
## Per-NPC autonomy flag.  Key = NPC instance-id, Value = bool.
var _autonomy: Dictionary = {}


func _ready() -> void:
	# Defer NPC scan so all scene children are ready.
	call_deferred(&"_scan_npcs")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"cycle_command_target"):
		cycle()


# ── Public API ───────────────────────────────────────────────────────────────

## Advance to the next command target (or wrap to None/Self).
func cycle() -> void:
	_ensure_npc_list()
	if _npc_list.is_empty():
		_set_index(-1)
		return
	_set_index((_command_index + 1) % (_npc_list.size() + 1) - 1)


## Directly set the commanded NPC (or null for self).
func set_commanded(npc: NPCPlaceholder) -> void:
	if npc == null:
		_set_index(-1)
		return
	_ensure_npc_list()
	var idx: int = _npc_list.find(npc)
	if idx == -1:
		push_warning("[NPCCommandSystem] NPC not in scan list: %s" % str(npc))
		return
	_set_index(idx)


## Whether any NPC is currently being commanded.
func is_commanding() -> bool:
	return commanded_npc != null


## Toggle autonomous (loop) mode on the given NPC.
func toggle_autonomy(npc: NPCPlaceholder) -> void:
	var npc_id: int = npc.get_instance_id()
	var was: bool = _autonomy.get(npc_id, false) as bool
	_autonomy[npc_id] = not was
	npc_autonomy_changed.emit(npc, not was)


## Check whether an NPC is autonomous.
func is_autonomous(npc: NPCPlaceholder) -> bool:
	return _autonomy.get(npc.get_instance_id(), false) as bool


## Returns the display name for the current command target.
func get_command_label() -> String:
	if commanded_npc == null:
		return "Self"
	return commanded_npc.npc_name


## Force a re-scan of NPCs in the scene (call after spawning/removing NPCs).
func rescan() -> void:
	_scan_npcs()


# ── Internal ─────────────────────────────────────────────────────────────────

func _scan_npcs() -> void:
	_npc_list.clear()
	var nodes: Array[Node] = get_tree().get_nodes_in_group(&"npc")
	for node: Node in nodes:
		if node is NPCPlaceholder:
			_npc_list.append(node as NPCPlaceholder)
	# Fallback: if no group, just find all NPCPlaceholders in tree
	if _npc_list.is_empty():
		_find_npcs_recursive(get_tree().current_scene)
	# Invalidate index if list shrank
	if _command_index >= _npc_list.size():
		_set_index(-1)


func _find_npcs_recursive(node: Node) -> void:
	if node is NPCPlaceholder:
		_npc_list.append(node as NPCPlaceholder)
	for child: Node in node.get_children():
		_find_npcs_recursive(child)


func _set_index(idx: int) -> void:
	_command_index = idx
	if idx < 0 or idx >= _npc_list.size():
		_command_index = -1
		commanded_npc = null
		command_cleared.emit()
	else:
		commanded_npc = _npc_list[idx]
		commanded_npc_changed.emit(commanded_npc)


func _ensure_npc_list() -> void:
	if _npc_list.is_empty():
		_scan_npcs()
