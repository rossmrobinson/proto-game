class_name NPCInteractionIntent
extends Node
## Per-NPC node that stores the NPC's current interaction goal.
## Bridge between NPCBrain (decision-making) and InteractionClaimSystem
## (arbitration) and NPCInteractionTargeting (execution).
##
## The intent describes WHAT the NPC wants to do, to WHOM, and HOW urgently.
## The targeting system then figures out HOW to get there physically.
##
## Attach as child of NPCPlaceholder.

signal intent_changed(new_intent: InteractionGoal)
signal intent_completed(goal: InteractionGoal)
signal intent_failed(goal: InteractionGoal, reason: String)
signal intent_blocked(goal: InteractionGoal, blocker: Node3D)

# ── Goal Categories ──────────────────────────────────────────────────────────

## High-level categories that drive targeting heuristics.
enum GoalCategory {
	NONE,              ## No active goal — idle
	TOUCH,             ## Reach out and touch a body part (hand contact)
	GRAB,              ## Seize and hold a body part
	MOUNT,             ## Move body to mounting position (penetration aligned)
	ORAL,              ## Move mouth to target (lick, kiss, oral)
	STRADDLE,          ## Position hips over target (sitting on)
	PRESENT,           ## Offer own body part to another NPC
	WITHDRAW,          ## Pull away / release current interaction
}

## How the NPC approaches when others are in the way.
enum ApproachStyle {
	YIELD,             ## Give up if path is blocked by another NPC
	WAIT,              ## Queue and wait for the spot to open
	NUDGE,             ## Gently push into position (polite)
	SHOVE,             ## Aggressively push others aside
}

## The full intent description.
class InteractionGoal:
	## What the NPC wants to do.
	var category: GoalCategory = GoalCategory.NONE
	## Target NPC (whose body part we want).
	var target_npc: NPCPlaceholder = null
	## Specific body part name (or empty for "nearest suitable").
	var target_part_name: String = ""
	## Which of the NPC's own body parts to use ("left_hand", "mouth", "penis_base", etc).
	var tool_part_name: String = ""
	## Priority for the claim system.
	var claim_priority: InteractionClaimSystem.ClaimPriority = \
		InteractionClaimSystem.ClaimPriority.NORMAL
	## Approach style when blocked.
	var approach_style: ApproachStyle = ApproachStyle.WAIT
	## Maximum time (seconds) to pursue this goal before giving up.
	var timeout: float = 30.0
	## Internal: time at which this goal was set.
	var started_at: float = 0.0

	func is_active() -> bool:
		return category != GoalCategory.NONE

	func is_timed_out() -> bool:
		if timeout <= 0.0:
			return false
		return (Time.get_ticks_msec() / 1000.0 - started_at) > timeout

# ── State ────────────────────────────────────────────────────────────────────

## The current active goal.
var current_goal: InteractionGoal = InteractionGoal.new()
## Resolved target BodyPart (set by targeting system after scanning).
var resolved_target: BodyPart = null
## Resolved tool BodyPart (our own part we're using).
var resolved_tool: BodyPart = null

var _npc: NPCPlaceholder = null


func _ready() -> void:
	_npc = get_parent() as NPCPlaceholder


func _physics_process(_delta: float) -> void:
	if current_goal.is_active() and current_goal.is_timed_out():
		var g: InteractionGoal = current_goal
		clear_intent()
		intent_failed.emit(g, "timeout")


# ═════════════════════════════════════════════════════════════════════════════
#  PUBLIC API
# ═════════════════════════════════════════════════════════════════════════════

## Set a new interaction intent. Clears any previous goal.
func set_intent(category: GoalCategory, target_npc: NPCPlaceholder,
		target_part: String = "", tool_part: String = "",
		priority: InteractionClaimSystem.ClaimPriority = \
			InteractionClaimSystem.ClaimPriority.NORMAL,
		approach: ApproachStyle = ApproachStyle.WAIT,
		timeout_sec: float = 30.0) -> void:
	var goal: InteractionGoal = InteractionGoal.new()
	goal.category = category
	goal.target_npc = target_npc
	goal.target_part_name = target_part
	goal.tool_part_name = tool_part
	goal.claim_priority = priority
	goal.approach_style = approach
	goal.timeout = timeout_sec
	goal.started_at = Time.get_ticks_msec() / 1000.0

	current_goal = goal
	resolved_target = null
	resolved_tool = null
	intent_changed.emit(goal)


## Clear the current intent. Releases any claims.
func clear_intent() -> void:
	_release_claims()
	current_goal = InteractionGoal.new()
	resolved_target = null
	resolved_tool = null
	intent_changed.emit(current_goal)


## Mark the current goal as completed.
func complete_intent() -> void:
	var g: InteractionGoal = current_goal
	clear_intent()
	intent_completed.emit(g)


## Report that the goal is blocked by another actor.
func report_blocked(blocker: Node3D) -> void:
	intent_blocked.emit(current_goal, blocker)
	# Behavior depends on approach style
	match current_goal.approach_style:
		ApproachStyle.YIELD:
			var g: InteractionGoal = current_goal
			clear_intent()
			intent_failed.emit(g, "yielded")
		ApproachStyle.WAIT:
			pass  # Keep trying — targeting system will re-check
		ApproachStyle.NUDGE, ApproachStyle.SHOVE:
			pass  # Targeting system handles push force


## Get the NPC this intent belongs to.
func get_npc() -> NPCPlaceholder:
	return _npc


## Convenience: is the NPC trying to do anything?
func has_active_intent() -> bool:
	return current_goal.is_active()


# ═════════════════════════════════════════════════════════════════════════════
#  INTERNAL
# ═════════════════════════════════════════════════════════════════════════════

func _release_claims() -> void:
	if resolved_target == null:
		return
	var claim_sys: InteractionClaimSystem = _find_claim_system()
	if claim_sys == null:
		return
	claim_sys.release_claim(resolved_target, _npc)


func _find_claim_system() -> InteractionClaimSystem:
	var nodes: Array[Node] = get_tree().get_nodes_in_group(
		&"interaction_claim_system")
	if nodes.is_empty():
		return null
	return nodes[0] as InteractionClaimSystem
