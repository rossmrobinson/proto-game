class_name BodyStackManager
extends Node
## Global singleton that tracks vertical stacking of NPC bodies.
## Limits stacking to a configurable maximum (default 3) and distributes
## weight downward so bottom NPCs don't explode under physics pressure.
##
## Also provides spatial queries: "who is on top of whom", "is this
## position occupied by another NPC's torso", etc.
##
## Add to scene tree ONCE (autoload or scene root child).

signal stack_formed(bottom: NPCPlaceholder, top: NPCPlaceholder)
signal stack_collapsed(reason: String)
signal stack_limit_reached(npc: NPCPlaceholder)

# ── Config ───────────────────────────────────────────────────────────────────

@export_group("Stacking")
## Maximum bodies that can stack vertically.
@export var max_stack_height: int = 3
## Vertical overlap distance (meters) to consider two NPCs "stacked".
@export var stack_detect_distance: float = 0.4
## How often (seconds) to re-evaluate stacking relationships.
@export var scan_interval: float = 0.5
## Weight multiplier applied per stack level to keep bottom bodies stable.
## Level 0 (bottom) = 1.0, level 1 = 1.0 + cushion_weight_per_level, etc.
@export var cushion_weight_per_level: float = 0.3
## Extra damping applied to bottom NPCs to prevent jitter.
@export var stack_damping_bonus: float = 2.0

# ── State ────────────────────────────────────────────────────────────────────

## Represents one stacking relationship.
class StackEntry:
	var npc: NPCPlaceholder = null
	## 0 = ground/support, 1 = first body on top, 2 = second, etc.
	var level: int = 0
	## Who is directly below this NPC (null = ground/furniture).
	var below: NPCPlaceholder = null
	## Who is directly above this NPC (null = nobody).
	var above: NPCPlaceholder = null

## NPC instance_id → StackEntry
var _entries: Dictionary = {}
var _scan_timer: float = 0.0
var _npcs: Array[NPCPlaceholder] = []
var _had_active_stack: bool = false


func _ready() -> void:
	add_to_group(&"body_stack_manager")


func _physics_process(delta: float) -> void:
	_scan_timer += delta
	if _scan_timer < scan_interval:
		return
	_scan_timer = 0.0
	_refresh_npc_list()
	_evaluate_stacking()
	_apply_weight_distribution()


# ═════════════════════════════════════════════════════════════════════════════
#  PUBLIC API
# ═════════════════════════════════════════════════════════════════════════════

## Query: what stack level is this NPC at? Returns -1 if not tracked.
func get_stack_level(npc: NPCPlaceholder) -> int:
	var npc_id: int = npc.get_instance_id()
	if not _entries.has(npc_id):
		return -1
	return (_entries[npc_id] as StackEntry).level


## Query: who is directly below this NPC?
func get_below(npc: NPCPlaceholder) -> NPCPlaceholder:
	var npc_id: int = npc.get_instance_id()
	if not _entries.has(npc_id):
		return null
	return (_entries[npc_id] as StackEntry).below


## Query: who is directly above this NPC?
func get_above(npc: NPCPlaceholder) -> NPCPlaceholder:
	var npc_id: int = npc.get_instance_id()
	if not _entries.has(npc_id):
		return null
	return (_entries[npc_id] as StackEntry).above


## Query: can another NPC stack on top of this one?
func can_stack_on(npc: NPCPlaceholder) -> bool:
	var npc_id: int = npc.get_instance_id()
	if not _entries.has(npc_id):
		return true
	var entry: StackEntry = _entries[npc_id] as StackEntry
	return entry.level < (max_stack_height - 1) and entry.above == null


## Query: is the given world position occupied by any NPC's torso?
func is_position_occupied(world_pos: Vector3, radius: float = 0.3) -> bool:
	for npc: NPCPlaceholder in _npcs:
		if npc.ragdoll == null:
			continue
		if not npc.ragdoll.parts.has("pelvis"):
			continue
		var pelvis: BodyPart = npc.ragdoll.parts["pelvis"] as BodyPart
		if pelvis.global_position.distance_to(world_pos) < radius:
			return true
	return false


## Query: find all NPCs within a horizontal radius of a position.
func get_npcs_near(world_pos: Vector3, radius: float) -> Array[NPCPlaceholder]:
	var result: Array[NPCPlaceholder] = []
	for npc: NPCPlaceholder in _npcs:
		if npc.ragdoll == null:
			continue
		if not npc.ragdoll.parts.has("pelvis"):
			continue
		var pelvis: BodyPart = npc.ragdoll.parts["pelvis"] as BodyPart
		var horiz_dist: float = Vector2(
			pelvis.global_position.x - world_pos.x,
			pelvis.global_position.z - world_pos.z
		).length()
		if horiz_dist < radius:
			result.append(npc)
	return result


## Query: get the full stack chain starting from the bottom.
func get_stack_chain(bottom_npc: NPCPlaceholder) -> Array[NPCPlaceholder]:
	var chain: Array[NPCPlaceholder] = [bottom_npc]
	var current: NPCPlaceholder = bottom_npc
	while true:
		var above: NPCPlaceholder = get_above(current)
		if above == null:
			break
		chain.append(above)
		current = above
	return chain


# ═════════════════════════════════════════════════════════════════════════════
#  INTERNAL — SCANNING
# ═════════════════════════════════════════════════════════════════════════════

func _refresh_npc_list() -> void:
	_npcs.clear()
	for node: Node in get_tree().get_nodes_in_group(&"npc"):
		if node is NPCPlaceholder:
			_npcs.append(node as NPCPlaceholder)


func _evaluate_stacking() -> void:
	var had_stack: bool = _had_active_stack
	# Reset entries
	_entries.clear()

	# Build entries for each NPC with a pelvis height
	var sorted_npcs: Array[NPCPlaceholder] = _npcs.duplicate()

	# Sort by pelvis Y ascending (lowest first)
	sorted_npcs.sort_custom(func(a: NPCPlaceholder, b: NPCPlaceholder) -> bool:
		return _get_pelvis_y(a) < _get_pelvis_y(b)
	)

	for npc: NPCPlaceholder in sorted_npcs:
		var npc_id: int = npc.get_instance_id()
		var entry: StackEntry = StackEntry.new()
		entry.npc = npc
		entry.level = 0

		# Check if this NPC is on top of another
		var pelvis_pos: Vector3 = _get_pelvis_pos(npc)
		var best_below: NPCPlaceholder = null
		var best_below_y: float = -INF

		for other: NPCPlaceholder in sorted_npcs:
			if other == npc:
				continue
			var other_pelvis: Vector3 = _get_pelvis_pos(other)
			# Other must be below us
			if other_pelvis.y >= pelvis_pos.y:
				continue
			# Must be close horizontally
			var horiz_dist: float = Vector2(
				pelvis_pos.x - other_pelvis.x,
				pelvis_pos.z - other_pelvis.z
			).length()
			if horiz_dist > stack_detect_distance * 2.0:
				continue
			# Must be within vertical stack distance
			var vert_dist: float = pelvis_pos.y - other_pelvis.y
			if vert_dist > stack_detect_distance * 3.0:
				continue
			# Pick the highest NPC below us
			if other_pelvis.y > best_below_y:
				best_below_y = other_pelvis.y
				best_below = other

		if best_below != null:
			entry.below = best_below
			var below_id: int = best_below.get_instance_id()
			if _entries.has(below_id):
				var below_entry: StackEntry = _entries[below_id] as StackEntry
				entry.level = below_entry.level + 1
				below_entry.above = npc

				# Check stack limit
				if entry.level >= max_stack_height:
					stack_limit_reached.emit(npc)
					entry.level = max_stack_height - 1

				if entry.level == 1 and below_entry.above == npc:
					stack_formed.emit(best_below, npc)

		_entries[npc_id] = entry

	var has_stack: bool = _has_active_stack(_entries)
	if had_stack and not has_stack:
		stack_collapsed.emit("all_stacks_released")
	_had_active_stack = has_stack


func _apply_weight_distribution() -> void:
	for npc_id: int in _entries:
		var entry: StackEntry = _entries[npc_id] as StackEntry
		if entry.npc == null or entry.npc.ragdoll == null:
			continue

		# Count how many NPCs are stacked above
		var above_count: int = 0
		var check: NPCPlaceholder = entry.above
		while check != null:
			above_count += 1
			check = get_above(check)

		# Apply stabilization to NPCs bearing weight
		if above_count > 0:
			_stabilize_npc(entry.npc, above_count)


func _stabilize_npc(npc: NPCPlaceholder, weight_above: int) -> void:
	if npc.ragdoll == null:
		return

	# Apply extra damping to core parts (pelvis, spine, legs)
	var core_parts: PackedStringArray = [
		"pelvis", "spine_lower", "spine_mid", "spine_upper", "chest",
		"left_upper_leg", "left_lower_leg",
		"right_upper_leg", "right_lower_leg",
	]

	var extra_damp: float = stack_damping_bonus * float(weight_above)

	for part_name: String in core_parts:
		if not npc.ragdoll.parts.has(part_name):
			continue
		var part: BodyPart = npc.ragdoll.parts[part_name] as BodyPart
		# Add extra damping but don't exceed reasonable limits
		part.linear_damp = maxf(part.linear_damp, 1.0 + extra_damp)
		part.angular_damp = maxf(part.angular_damp, 2.0 + extra_damp)


# ═════════════════════════════════════════════════════════════════════════════
#  HELPERS
# ═════════════════════════════════════════════════════════════════════════════

func _get_pelvis_pos(npc: NPCPlaceholder) -> Vector3:
	if npc.ragdoll == null:
		return npc.global_position
	if not npc.ragdoll.parts.has("pelvis"):
		return npc.global_position
	return (npc.ragdoll.parts["pelvis"] as BodyPart).global_position


func _get_pelvis_y(npc: NPCPlaceholder) -> float:
	return _get_pelvis_pos(npc).y


func _has_active_stack(entries: Dictionary) -> bool:
	for npc_id: int in entries:
		var entry: StackEntry = entries[npc_id] as StackEntry
		if entry == null:
			continue
		if entry.level > 0 or entry.above != null or entry.below != null:
			return true
	return false
