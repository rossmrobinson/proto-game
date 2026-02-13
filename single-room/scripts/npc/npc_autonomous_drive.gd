class_name NPCAutonomousDrive
extends Node
## Drives autonomous NPC sexual/social behavior based on personality preset.
##
## Reads drive parameters (sexual_initiative, seduction_resistance, etc.) and
## periodically evaluates whether the NPC should initiate an interaction on
## its own — touch, grab, mount, masturbate, disrupt others, or assist the
## player (helper mode).
##
## Attach as child of NPCPlaceholder (created automatically by the preset
## system).

# ── Drive Parameters (set by preset) ────────────────────────────────────────

## Likelihood (0–1) of autonomously initiating sexual contact each cycle.
var sexual_initiative: float = 0.0
## How hard it is to seduce this NPC (0 = instant, 1 = nearly impossible).
var seduction_resistance: float = 0.5
## Physical force multiplier applied to approach / mount interactions.
var physical_force_level: float = 0.3
## Approach style when the NPC initiates on its own.
var preferred_approach: NPCInteractionIntent.ApproachStyle = \
	NPCInteractionIntent.ApproachStyle.WAIT
## Whether the NPC masturbates when idle and aroused.
var auto_masturbate: bool = false
## Whether the NPC aggressively interrupts others' non-sexual activities.
var disrupts_others: bool = false
## Whether the NPC acts as a helper — brings other NPCs to the player and
## physically facilitates intercourse.
var helper_mode: bool = false
## Base interval (seconds) between initiative checks.
var initiative_interval: float = 30.0
## Random jitter (± seconds) on the interval.
var initiative_jitter: float = 10.0

# ── Internal State ───────────────────────────────────────────────────────────

var _npc: NPCPlaceholder = null
var _intent: NPCInteractionIntent = null
var _arousal: Node = null  # ArousalSystem (loose typed for class resolution)
var _profile: CharacterProfile = null
var _brain: NPCBrain = null
var _timer: float = 0.0
var _next_check: float = 30.0
var _initialized: bool = false
## Track consecutive failed attempts — back off after too many.
var _fail_streak: int = 0
const MAX_FAIL_STREAK: int = 5
const FAIL_BACKOFF_MULTIPLIER: float = 1.5

# ── Goal weights for target selection ────────────────────────────────────────
# Higher-initiative NPCs escalate faster through categories.

const ESCALATION_SEQUENCE: Array[NPCInteractionIntent.GoalCategory] = [
	NPCInteractionIntent.GoalCategory.TOUCH,
	NPCInteractionIntent.GoalCategory.GRAB,
	NPCInteractionIntent.GoalCategory.ORAL,
	NPCInteractionIntent.GoalCategory.MOUNT,
]


func _ready() -> void:
	_npc = get_parent() as NPCPlaceholder
	call_deferred(&"_wire")


func _wire() -> void:
	if _npc == null:
		return
	for child: Node in _npc.get_children():
		if child is NPCInteractionIntent:
			_intent = child as NPCInteractionIntent
			_intent.intent_completed.connect(_on_intent_completed)
			_intent.intent_failed.connect(_on_intent_failed)
		elif child is CharacterProfile:
			_profile = child as CharacterProfile
		elif child is NPCBrain:
			_brain = child as NPCBrain
		elif child.has_method(&"get_arousal_level"):
			_arousal = child
	_randomize_timer()
	_initialized = true


func _physics_process(delta: float) -> void:
	if not _initialized:
		return
	if sexual_initiative <= 0.0 and not helper_mode:
		return
	# Don't act while the NPC is being commanded by the player.
	if _brain != null and _brain._is_commanded:
		return
	# Don't stack intents — wait for the current one to resolve.
	if _intent != null and _intent.has_active_intent():
		return

	_timer += delta
	if _timer < _next_check:
		return
	_timer = 0.0
	_randomize_timer()

	_evaluate_drive()


# ══════════════════════════════════════════════════════════════════════════════
#  DRIVE EVALUATION
# ══════════════════════════════════════════════════════════════════════════════

func _evaluate_drive() -> void:
	# Back off after repeated failures.
	if _fail_streak >= MAX_FAIL_STREAK:
		_fail_streak = 0  # Reset after one skipped cycle.
		return

	var arousal_level: float = _get_arousal()

	# ── Helper mode: priority is bringing NPCs to the player ────────────
	if helper_mode:
		if _try_helper_action():
			return

	# ── Masturbation: when idle + aroused + initiative allows it ────────
	if auto_masturbate and arousal_level > 0.3:
		if _try_masturbate():
			return

	# ── Sexual initiative: chance to approach someone ───────────────────
	if sexual_initiative > 0.0:
		var roll: float = randf()
		# Initiative check — boost by arousal (horny + aroused = near-certain).
		var effective_initiative: float = sexual_initiative + arousal_level * 0.3
		if roll < clampf(effective_initiative, 0.0, 1.0):
			if _try_initiate_sexual():
				return

	# ── Disruption: interrupt another NPC's non-sexual idle ─────────────
	if disrupts_others:
		if randf() < 0.4:
			_try_disrupt()


# ══════════════════════════════════════════════════════════════════════════════
#  ACTION ATTEMPTS
# ══════════════════════════════════════════════════════════════════════════════

## Attempt to initiate a sexual interaction with a nearby NPC or the player.
func _try_initiate_sexual() -> bool:
	if _intent == null or _npc == null:
		return false

	var target: NPCPlaceholder = _pick_target_npc()
	if target == null:
		return false

	# Pick escalation level based on arousal + initiative.
	var escalation_index: int = _get_escalation_index()
	var goal_cat: NPCInteractionIntent.GoalCategory = \
		ESCALATION_SEQUENCE[escalation_index]

	var priority: InteractionClaimSystem.ClaimPriority = _get_claim_priority()

	_intent.set_intent(
		goal_cat, target, "", "",
		priority, preferred_approach, 45.0)
	return true


## Attempt self-stimulation (masturbation).
func _try_masturbate() -> bool:
	if _intent == null or _npc == null:
		return false

	# Target own genitals with own hand.
	_intent.set_intent(
		NPCInteractionIntent.GoalCategory.TOUCH,
		_npc,  # Target self
		"",    # Auto-resolve to genitals
		"right_hand",
		InteractionClaimSystem.ClaimPriority.NORMAL,
		NPCInteractionIntent.ApproachStyle.WAIT,
		60.0)
	return true


## Helper mode: find an un-occupied NPC and push/guide them toward the player.
func _try_helper_action() -> bool:
	if _intent == null or _npc == null:
		return false

	var player_pos: Vector3 = _get_player_position()
	if player_pos == Vector3.ZERO:
		return false

	# Find another NPC that is idle (no active intent) and not the player.
	var candidates: Array[NPCPlaceholder] = _get_other_npcs()
	if candidates.is_empty():
		return false

	# Pick the one furthest from the player (most useful to move).
	var best: NPCPlaceholder = null
	var best_dist: float = 0.0
	for candidate: NPCPlaceholder in candidates:
		if candidate.interaction_intent != null \
				and candidate.interaction_intent.has_active_intent():
			continue  # Already busy.
		var dist: float = candidate.global_position.distance_to(player_pos)
		if dist > best_dist:
			best_dist = dist
			best = candidate

	if best == null:
		return false

	# Grab the other NPC to move them toward the player.
	_intent.set_intent(
		NPCInteractionIntent.GoalCategory.GRAB,
		best,
		"",             # Auto-resolve body part
		"right_hand",
		InteractionClaimSystem.ClaimPriority.AGGRESSIVE,
		NPCInteractionIntent.ApproachStyle.SHOVE,
		30.0)
	return true


## Disrupt another NPC's activity by grabbing them.
func _try_disrupt() -> bool:
	if _intent == null or _npc == null:
		return false

	var candidates: Array[NPCPlaceholder] = _get_other_npcs()
	if candidates.is_empty():
		return false

	# Pick a random NPC to disrupt.
	var target: NPCPlaceholder = candidates[randi() % candidates.size()]

	_intent.set_intent(
		NPCInteractionIntent.GoalCategory.GRAB,
		target, "", "",
		InteractionClaimSystem.ClaimPriority.AGGRESSIVE,
		NPCInteractionIntent.ApproachStyle.SHOVE,
		20.0)
	return true


# ══════════════════════════════════════════════════════════════════════════════
#  TARGET SELECTION
# ══════════════════════════════════════════════════════════════════════════════

## Pick a target NPC. Prefers nearby, non-busy NPCs.
func _pick_target_npc() -> NPCPlaceholder:
	var candidates: Array[NPCPlaceholder] = _get_other_npcs()
	if candidates.is_empty():
		return null

	# Score each candidate: closeness + availability.
	var best: NPCPlaceholder = null
	var best_score: float = -INF
	var my_pos: Vector3 = _npc.global_position

	for candidate: NPCPlaceholder in candidates:
		var dist: float = my_pos.distance_to(candidate.global_position)
		var score: float = -dist  # Closer is better.
		# Bonus if not busy.
		if candidate.interaction_intent != null \
				and not candidate.interaction_intent.has_active_intent():
			score += 3.0
		# Penalty if sleeping.
		if not candidate.is_awake:
			score -= 10.0

		if score > best_score:
			best_score = score
			best = candidate

	return best


func _get_other_npcs() -> Array[NPCPlaceholder]:
	var result: Array[NPCPlaceholder] = []
	var nodes: Array[Node] = get_tree().get_nodes_in_group(&"npc")
	for node: Node in nodes:
		if node is NPCPlaceholder and node != _npc:
			result.append(node as NPCPlaceholder)
	return result


func _get_player_position() -> Vector3:
	# Scan for PlayerController in tree.
	var root: Node = get_tree().current_scene
	if root == null:
		return Vector3.ZERO
	return _find_player_pos(root)


func _find_player_pos(node: Node) -> Vector3:
	if node is PlayerController:
		return (node as Node3D).global_position
	for child: Node in node.get_children():
		var pos: Vector3 = _find_player_pos(child)
		if pos != Vector3.ZERO:
			return pos
	return Vector3.ZERO


## Derive escalation level from arousal + initiative.
## 0 = TOUCH, 1 = GRAB, 2 = ORAL, 3 = MOUNT
func _get_escalation_index() -> int:
	var arousal_level: float = _get_arousal()
	# More aroused + higher initiative → more aggressive goal.
	var raw: float = (sexual_initiative * 0.5 + arousal_level * 0.5) \
		* float(ESCALATION_SEQUENCE.size())
	var idx: int = int(clampf(raw, 0.0, float(ESCALATION_SEQUENCE.size() - 1)))
	return idx


func _get_claim_priority() -> InteractionClaimSystem.ClaimPriority:
	if _brain != null:
		return _brain.get_claim_priority()
	if physical_force_level > 0.7:
		return InteractionClaimSystem.ClaimPriority.AGGRESSIVE
	if physical_force_level > 0.4:
		return InteractionClaimSystem.ClaimPriority.EAGER
	return InteractionClaimSystem.ClaimPriority.NORMAL


func _get_arousal() -> float:
	if _arousal != null and _arousal.has_method(&"get_arousal_level"):
		return _arousal.call(&"get_arousal_level") as float
	if _arousal != null and &"arousal_level" in _arousal:
		return _arousal.get(&"arousal_level") as float
	return 0.0


# ══════════════════════════════════════════════════════════════════════════════
#  CALLBACKS
# ══════════════════════════════════════════════════════════════════════════════

func _on_intent_completed(_goal: NPCInteractionIntent.InteractionGoal) -> void:
	_fail_streak = 0


func _on_intent_failed(_goal: NPCInteractionIntent.InteractionGoal,
		_reason: String) -> void:
	_fail_streak += 1


func _randomize_timer() -> void:
	_next_check = initiative_interval + randf_range(
		-initiative_jitter, initiative_jitter)
	# Lengthen interval on failure.
	if _fail_streak > 0:
		_next_check *= (1.0 + float(_fail_streak) * FAIL_BACKOFF_MULTIPLIER)
	_next_check = maxf(_next_check, 3.0)


# ══════════════════════════════════════════════════════════════════════════════
#  CONFIGURATION
# ══════════════════════════════════════════════════════════════════════════════

## Apply a drive config dictionary (from NPCPersonalityPreset).
func apply_drive(config: Dictionary) -> void:
	if config.has("sexual_initiative"):
		sexual_initiative = config["sexual_initiative"] as float
	if config.has("seduction_resistance"):
		seduction_resistance = config["seduction_resistance"] as float
	if config.has("physical_force_level"):
		physical_force_level = config["physical_force_level"] as float
	if config.has("preferred_approach"):
		preferred_approach = config["preferred_approach"] as NPCInteractionIntent.ApproachStyle
	if config.has("auto_masturbate"):
		auto_masturbate = config["auto_masturbate"] as bool
	if config.has("disrupts_others"):
		disrupts_others = config["disrupts_others"] as bool
	if config.has("helper_mode"):
		helper_mode = config["helper_mode"] as bool
	if config.has("initiative_interval"):
		initiative_interval = config["initiative_interval"] as float
	if config.has("initiative_jitter"):
		initiative_jitter = config["initiative_jitter"] as float
	_randomize_timer()
