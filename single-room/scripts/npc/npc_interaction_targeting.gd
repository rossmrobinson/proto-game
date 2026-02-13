class_name NPCInteractionTargeting
extends Node
## Per-NPC targeting system. Reads the current InteractionGoal from
## NPCInteractionIntent and resolves it to a specific BodyPart + approach
## vector.  Handles:
##   - Body-area scanning (find best part matching the goal)
##   - Reach checking (is the part physically accessible?)
##   - Obstacle detection (other NPCs in the way)
##   - Claim acquisition (via InteractionClaimSystem)
##   - Physical approach (move own body part toward target)
##
## Attach as child of NPCPlaceholder.

signal target_acquired(part: BodyPart)
signal target_lost(reason: String)
signal approach_complete()
signal obstacle_detected(blocker: Node3D)

# ── Body Area Categories ─────────────────────────────────────────────────────
# Mapping goal categories to ordered lists of preferred target part names.
# The system tries each part in order until it finds one that is reachable
# and not claimed by a higher-priority actor.

const AREA_GENITALS: PackedStringArray = [
	"penis_tip", "penis_mid", "penis_base",
	"clitoris", "labia_left", "labia_right",
]
const AREA_BREASTS: PackedStringArray = [
	"left_breast_nipple", "right_breast_nipple",
	"left_breast_inner", "left_breast_outer",
	"left_breast_upper", "left_breast_lower",
	"right_breast_inner", "right_breast_outer",
	"right_breast_upper", "right_breast_lower",
]
const AREA_BUTTOCKS: PackedStringArray = [
	"left_inner_glute", "left_outer_glute",
	"right_inner_glute", "right_outer_glute",
]
const AREA_ORAL: PackedStringArray = [
	"tongue_tip", "tongue_mid", "tongue_base", "jaw",
]
const AREA_HANDS: PackedStringArray = [
	"left_hand", "right_hand",
]
const AREA_VAGINAL_PASSAGE: PackedStringArray = [
	"vaginal_passage_entrance_0", "vaginal_passage_entrance_1",
	"vaginal_passage_entrance_2", "vaginal_passage_entrance_3",
]
const AREA_ANAL_PASSAGE: PackedStringArray = [
	"anal_passage_entrance_0", "anal_passage_entrance_1",
	"anal_passage_entrance_2", "anal_passage_entrance_3",
]
const AREA_ORAL_PASSAGE: PackedStringArray = [
	"oral_passage_entrance_0", "oral_passage_entrance_1",
	"oral_passage_entrance_2", "oral_passage_entrance_3",
]

# ── Config ───────────────────────────────────────────────────────────────────

@export_group("Reach")
## Maximum distance (meters) the NPC's tool part can reach a target part.
@export var max_reach_distance: float = 1.2
## When within this distance, consider "arrived" and start interaction.
@export var contact_distance: float = 0.08
## Physics ray layers to check for obstacles between tool and target.
@export_flags_3d_physics var obstacle_mask: int = 1 | 4 | 8  # Env + NPC_Ext + SoftTissue

@export_group("Approach")
## Force applied to move the NPC's body toward the target position.
@export var approach_force: float = 15.0
## Maximum approach velocity (m/s).
@export var approach_max_speed: float = 0.8
## How often (seconds) to re-scan for better targets.
@export var rescan_interval: float = 2.0

# ── State ────────────────────────────────────────────────────────────────────

enum Phase {
	IDLE,          ## No active target
	SCANNING,      ## Looking for a suitable target part
	CLAIMING,      ## Attempting to claim the target
	APPROACHING,   ## Moving tool part toward target
	CONTACT,       ## In contact — interaction active
	BLOCKED,       ## Path obstructed, waiting or pushing
}

var phase: Phase = Phase.IDLE
var _npc: NPCPlaceholder = null
var _intent: NPCInteractionIntent = null
var _claim_system: InteractionClaimSystem = null
var _rescan_timer: float = 0.0


func _ready() -> void:
	_npc = get_parent() as NPCPlaceholder
	# Find siblings
	call_deferred(&"_wire")


func _wire() -> void:
	for child: Node in _npc.get_children():
		if child is NPCInteractionIntent:
			_intent = child as NPCInteractionIntent
			_intent.intent_changed.connect(_on_intent_changed)
	# Find global claim system
	var nodes: Array[Node] = get_tree().get_nodes_in_group(
		&"interaction_claim_system")
	if not nodes.is_empty():
		_claim_system = nodes[0] as InteractionClaimSystem


func _physics_process(delta: float) -> void:
	if _intent == null or not _intent.has_active_intent():
		if phase != Phase.IDLE:
			_go_idle()
		return

	match phase:
		Phase.IDLE:
			_begin_scan()
		Phase.SCANNING:
			_do_scan()
		Phase.CLAIMING:
			_do_claim()
		Phase.APPROACHING:
			_do_approach(delta)
		Phase.CONTACT:
			_do_contact(delta)
		Phase.BLOCKED:
			_do_blocked(delta)

	# Periodic rescan for better targets
	_rescan_timer += delta
	if _rescan_timer >= rescan_interval and phase == Phase.CONTACT:
		_rescan_timer = 0.0
		# Check if current target is still valid and reachable
		if _intent.resolved_target != null:
			if not _is_reachable(_get_tool_part(), _intent.resolved_target):
				target_lost.emit("unreachable")
				_begin_scan()


# ═════════════════════════════════════════════════════════════════════════════
#  PHASE LOGIC
# ═════════════════════════════════════════════════════════════════════════════

func _begin_scan() -> void:
	phase = Phase.SCANNING
	_rescan_timer = 0.0


func _do_scan() -> void:
	var goal: NPCInteractionIntent.InteractionGoal = _intent.current_goal
	var target_npc: NPCPlaceholder = goal.target_npc
	if target_npc == null or target_npc.ragdoll == null:
		_intent.clear_intent()
		return

	# Determine which body areas to search based on goal category
	var candidates: PackedStringArray = _get_area_for_goal(goal)
	if candidates.is_empty():
		_intent.clear_intent()
		return

	# If a specific part was requested, try it first
	if goal.target_part_name != "":
		candidates = PackedStringArray([goal.target_part_name]) + candidates

	var tool_part: BodyPart = _get_tool_part()
	if tool_part == null:
		_intent.clear_intent()
		return

	# Find best available target
	var best: BodyPart = _find_best_target(target_npc, candidates, tool_part)
	if best == null:
		_intent.report_blocked(null)
		return

	_intent.resolved_target = best
	_intent.resolved_tool = tool_part
	phase = Phase.CLAIMING
	target_acquired.emit(best)


func _do_claim() -> void:
	if _intent.resolved_target == null:
		_begin_scan()
		return

	if _claim_system == null:
		# No claim system — just proceed
		phase = Phase.APPROACHING
		return

	var goal: NPCInteractionIntent.InteractionGoal = _intent.current_goal
	var arousal_boost: float = _get_arousal_boost()

	var granted: bool = _claim_system.request_claim(
		_intent.resolved_target, _npc,
		goal.claim_priority, arousal_boost, false)

	if granted:
		phase = Phase.APPROACHING
	else:
		var claimant: Node3D = _claim_system.get_claimant(_intent.resolved_target)
		_intent.report_blocked(claimant)
		match goal.approach_style:
			NPCInteractionIntent.ApproachStyle.YIELD:
				_go_idle()
			NPCInteractionIntent.ApproachStyle.WAIT:
				phase = Phase.BLOCKED
			NPCInteractionIntent.ApproachStyle.NUDGE, \
			NPCInteractionIntent.ApproachStyle.SHOVE:
				phase = Phase.BLOCKED


func _do_approach(delta: float) -> void:
	var tool_part: BodyPart = _intent.resolved_tool
	var target: BodyPart = _intent.resolved_target
	if tool_part == null or target == null:
		_begin_scan()
		return
	if not is_instance_valid(tool_part) or not is_instance_valid(target):
		_begin_scan()
		return

	var dir: Vector3 = (target.global_position - tool_part.global_position)
	var dist: float = dir.length()

	if dist < contact_distance:
		phase = Phase.CONTACT
		# Upgrade claim to physical
		if _claim_system != null:
			var goal: NPCInteractionIntent.InteractionGoal = _intent.current_goal
			_claim_system.request_claim(target, _npc,
				goal.claim_priority, _get_arousal_boost(), true)
		approach_complete.emit()
		return

	if dist > max_reach_distance:
		# Too far — need whole-body repositioning (handled by activity controller)
		target_lost.emit("out_of_reach")
		_begin_scan()
		return

	# Apply approach force to the tool part
	var norm_dir: Vector3 = dir.normalized()
	var speed: float = minf(tool_part.linear_velocity.length(), approach_max_speed)
	if speed < approach_max_speed:
		tool_part.apply_central_force(norm_dir * approach_force * delta * 60.0)


func _do_contact(_delta: float) -> void:
	# Maintain contact — check distance hasn't drifted
	var tool_part: BodyPart = _intent.resolved_tool
	var target: BodyPart = _intent.resolved_target
	if tool_part == null or target == null:
		_begin_scan()
		return
	if not is_instance_valid(tool_part) or not is_instance_valid(target):
		_begin_scan()
		return

	var dist: float = tool_part.global_position.distance_to(target.global_position)
	if dist > contact_distance * 3.0:
		# Lost contact
		target_lost.emit("contact_lost")
		phase = Phase.APPROACHING


func _do_blocked(_delta: float) -> void:
	# Re-attempt claim periodically
	_rescan_timer += _delta
	if _rescan_timer < 1.0:
		return
	_rescan_timer = 0.0
	_do_claim()


func _go_idle() -> void:
	phase = Phase.IDLE
	_rescan_timer = 0.0


# ═════════════════════════════════════════════════════════════════════════════
#  HELPERS
# ═════════════════════════════════════════════════════════════════════════════

func _get_area_for_goal(goal: NPCInteractionIntent.InteractionGoal) -> PackedStringArray:
	match goal.category:
		NPCInteractionIntent.GoalCategory.TOUCH:
			# Touch anything accessible — broad search
			return AREA_BREASTS + AREA_GENITALS + AREA_BUTTOCKS
		NPCInteractionIntent.GoalCategory.GRAB:
			return AREA_BREASTS + AREA_GENITALS + AREA_HANDS + AREA_BUTTOCKS
		NPCInteractionIntent.GoalCategory.MOUNT:
			return AREA_VAGINAL_PASSAGE + AREA_ANAL_PASSAGE
		NPCInteractionIntent.GoalCategory.ORAL:
			return AREA_GENITALS + AREA_BREASTS + AREA_ORAL_PASSAGE
		NPCInteractionIntent.GoalCategory.STRADDLE:
			return AREA_HANDS + AREA_GENITALS
		NPCInteractionIntent.GoalCategory.PRESENT:
			return AREA_GENITALS + AREA_BREASTS
		NPCInteractionIntent.GoalCategory.WITHDRAW:
			return PackedStringArray()
	return PackedStringArray()


func _find_best_target(target_npc: NPCPlaceholder,
		candidates: PackedStringArray,
		tool_part: BodyPart) -> BodyPart:
	var ragdoll: HumanoidRagdollBuilder = target_npc.ragdoll
	if ragdoll == null:
		return null

	var best: BodyPart = null
	var best_score: float = -INF

	for part_name: String in candidates:
		if not ragdoll.parts.has(part_name):
			continue
		var part: BodyPart = ragdoll.parts[part_name] as BodyPart
		if part == null:
			continue

		# Skip if claimed by higher priority and we can't snatch
		if _claim_system != null and _claim_system.is_claimed(part):
			if not _claim_system.is_claimed_by(part, _npc):
				# Check if we could potentially snatch
				var goal: NPCInteractionIntent.InteractionGoal = _intent.current_goal
				if goal.claim_priority < InteractionClaimSystem.ClaimPriority.AGGRESSIVE:
					continue

		# Score = -distance (closer is better) + reachability bonus
		var dist: float = tool_part.global_position.distance_to(part.global_position)
		if dist > max_reach_distance:
			continue

		var score: float = -dist
		# Bonus for parts that are directly reachable (no obstacle)
		if _is_reachable(tool_part, part):
			score += 2.0
		# Bonus for unclaimed parts
		if _claim_system != null and not _claim_system.is_claimed(part):
			score += 1.0

		if score > best_score:
			best_score = score
			best = part

	return best


func _get_tool_part() -> BodyPart:
	if _intent == null or _npc == null or _npc.ragdoll == null:
		return null

	var goal: NPCInteractionIntent.InteractionGoal = _intent.current_goal
	var tool_name: String = goal.tool_part_name

	# Default tool part based on goal category
	if tool_name == "":
		match goal.category:
			NPCInteractionIntent.GoalCategory.TOUCH, \
			NPCInteractionIntent.GoalCategory.GRAB:
				tool_name = "right_hand"
			NPCInteractionIntent.GoalCategory.MOUNT:
				# Use penis if available, else clitoris
				if _npc.ragdoll.parts.has("penis_tip"):
					tool_name = "penis_tip"
				elif _npc.ragdoll.parts.has("clitoris"):
					tool_name = "clitoris"
				else:
					tool_name = "pelvis"
			NPCInteractionIntent.GoalCategory.ORAL:
				tool_name = "tongue_tip"
			NPCInteractionIntent.GoalCategory.STRADDLE:
				tool_name = "pelvis"
			NPCInteractionIntent.GoalCategory.PRESENT:
				# Present our own part — tool is what we're presenting
				if _npc.ragdoll.parts.has("penis_tip"):
					tool_name = "penis_tip"
				else:
					tool_name = "pelvis"
			_:
				tool_name = "right_hand"

	if _npc.ragdoll.parts.has(tool_name):
		return _npc.ragdoll.parts[tool_name] as BodyPart
	return null


func _is_reachable(from_part: BodyPart, to_part: BodyPart) -> bool:
	if from_part == null or to_part == null:
		return false
	var space: PhysicsDirectSpaceState3D = from_part.get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from_part.global_position, to_part.global_position)
	query.collision_mask = obstacle_mask
	query.collide_with_bodies = true
	# Exclude both parts from the ray so it doesn't hit itself
	query.exclude = [from_part.get_rid(), to_part.get_rid()]

	var result: Dictionary = space.intersect_ray(query)
	if result.is_empty():
		return true
	var blocker: Node3D = result.get("collider", null) as Node3D
	if blocker != null:
		obstacle_detected.emit(blocker)
	return false


func _get_arousal_boost() -> float:
	if _npc == null or _npc.arousal_system == null:
		return 0.0
	return _npc.arousal_system.arousal_level


func _on_intent_changed(_goal: NPCInteractionIntent.InteractionGoal) -> void:
	# Reset targeting when intent changes
	phase = Phase.IDLE
	_rescan_timer = 0.0
