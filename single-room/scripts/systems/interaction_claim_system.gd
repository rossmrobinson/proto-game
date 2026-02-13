class_name InteractionClaimSystem
extends Node
## Global singleton that tracks which actor (player or NPC) currently "owns"
## each body part.  Provides priority-based arbitration so aggressive NPCs
## can snatch parts from timid ones, while timid NPCs yield gracefully.
##
## Add to the scene tree ONCE (autoload or scene root child).
## All NPC brains and the player hand system query this before grabbing.

signal claim_granted(part: BodyPart, claimant: Node3D)
signal claim_revoked(part: BodyPart, old_claimant: Node3D, new_claimant: Node3D)
signal claim_denied(part: BodyPart, requester: Node3D, reason: String)

# ── Types ────────────────────────────────────────────────────────────────────

## Priority tiers — higher number wins ties.
enum ClaimPriority {
	PASSIVE = 0,       ## Resting contact, no intent
	TIMID = 1,         ## Shy NPC reaching tentatively
	NORMAL = 2,        ## Standard grab
	EAGER = 3,         ## Aroused NPC actively seeking
	AGGRESSIVE = 4,    ## Dominant NPC snatching
	PLAYER = 5,        ## Player always wins unless they release
}

## One active claim record.
class ClaimRecord:
	var claimant: Node3D = null
	var priority: ClaimPriority = ClaimPriority.NORMAL
	## Arousal-boosted priority (0.0–1.0 added to base priority for tiebreaks).
	var arousal_boost: float = 0.0
	## Timestamp when the claim was made.
	var claimed_at: float = 0.0
	## If true, the claimant physically holds the part (grab joint active).
	var is_physical: bool = false

	func effective_priority() -> float:
		return float(priority) + arousal_boost

# ── State ────────────────────────────────────────────────────────────────────

## BodyPart instance_id → ClaimRecord
var _claims: Dictionary = {}
## Queued intents: BodyPart instance_id → Array[ClaimRecord] (sorted by priority)
var _queue: Dictionary = {}

# ── Config ───────────────────────────────────────────────────────────────────

@export_group("Arbitration")
## Minimum priority difference required to snatch a part from another claimant.
## Prevents constant tug-of-war between similar-priority actors.
@export_range(0.0, 3.0) var snatch_threshold: float = 1.5
## Cooldown (seconds) before an NPC can re-attempt a denied claim on the same part.
@export var deny_cooldown: float = 2.0
## Maximum number of parts a single NPC can claim simultaneously.
@export var max_claims_per_npc: int = 4
## Maximum number of parts the player can claim simultaneously (2 hands + genitals).
@export var max_claims_player: int = 3

# ── Cooldown tracking: requester_id → { part_id → earliest_retry_time } ────
var _cooldowns: Dictionary = {}


func _ready() -> void:
	add_to_group(&"interaction_claim_system")


# ═════════════════════════════════════════════════════════════════════════════
#  PUBLIC API
# ═════════════════════════════════════════════════════════════════════════════

## Attempt to claim a body part.  Returns true if granted.
func request_claim(part: BodyPart, claimant: Node3D,
		priority: ClaimPriority, arousal_boost: float = 0.0,
		physical: bool = true) -> bool:
	if part == null or claimant == null:
		return false

	var part_id: int = part.get_instance_id()
	var claimant_id: int = claimant.get_instance_id()

	# Cooldown check
	if _is_on_cooldown(claimant_id, part_id):
		claim_denied.emit(part, claimant, "cooldown")
		return false

	# Per-actor claim limit
	if _count_claims(claimant) >= _max_claims_for(claimant):
		claim_denied.emit(part, claimant, "max_claims")
		return false

	# Build the new record
	var record: ClaimRecord = ClaimRecord.new()
	record.claimant = claimant
	record.priority = priority
	record.arousal_boost = arousal_boost
	record.claimed_at = Time.get_ticks_msec() / 1000.0
	record.is_physical = physical

	# No existing claim → grant immediately
	if not _claims.has(part_id):
		_claims[part_id] = record
		claim_granted.emit(part, claimant)
		return true

	# Existing claim — can we override?
	var existing: ClaimRecord = _claims[part_id] as ClaimRecord
	if existing.claimant == claimant:
		# Same claimant refreshing — update priority
		existing.priority = priority
		existing.arousal_boost = arousal_boost
		existing.is_physical = physical
		return true

	var diff: float = record.effective_priority() - existing.effective_priority()
	if diff >= snatch_threshold:
		# Snatch — revoke old, grant new
		var old_claimant: Node3D = existing.claimant
		_claims[part_id] = record
		claim_revoked.emit(part, old_claimant, claimant)
		claim_granted.emit(part, claimant)
		return true

	# Denied — apply cooldown and add to queue
	_set_cooldown(claimant_id, part_id)
	_enqueue(part_id, record)
	claim_denied.emit(part, claimant, "outprioritized")
	return false


## Release a claim on a body part.
func release_claim(part: BodyPart, claimant: Node3D) -> void:
	if part == null or claimant == null:
		return
	var part_id: int = part.get_instance_id()
	if not _claims.has(part_id):
		return
	var existing: ClaimRecord = _claims[part_id] as ClaimRecord
	if existing.claimant != claimant:
		return

	_claims.erase(part_id)

	# Promote next in queue if any
	_promote_queue(part_id, part)


## Release ALL claims held by a specific actor (e.g., NPC dies or is removed).
func release_all(claimant: Node3D) -> void:
	var to_remove: Array[int] = []
	for part_id: int in _claims:
		var rec: ClaimRecord = _claims[part_id] as ClaimRecord
		if rec.claimant == claimant:
			to_remove.append(part_id)
	for part_id: int in to_remove:
		_claims.erase(part_id)
		_promote_queue(part_id, null)

	# Also purge from queues
	for part_id: int in _queue:
		var q: Array = _queue[part_id] as Array
		var filtered: Array = []
		for rec: ClaimRecord in q:
			if rec.claimant != claimant:
				filtered.append(rec)
		_queue[part_id] = filtered


## Query: who currently claims this part? Returns null if unclaimed.
func get_claimant(part: BodyPart) -> Node3D:
	if part == null:
		return null
	var part_id: int = part.get_instance_id()
	if not _claims.has(part_id):
		return null
	var rec: ClaimRecord = _claims[part_id] as ClaimRecord
	return rec.claimant


## Query: is this part claimed by anyone?
func is_claimed(part: BodyPart) -> bool:
	if part == null:
		return false
	return _claims.has(part.get_instance_id())


## Query: is this part claimed by a specific actor?
func is_claimed_by(part: BodyPart, claimant: Node3D) -> bool:
	if part == null or claimant == null:
		return false
	var part_id: int = part.get_instance_id()
	if not _claims.has(part_id):
		return false
	var rec: ClaimRecord = _claims[part_id] as ClaimRecord
	return rec.claimant == claimant


## Query: how many parts does this actor currently claim?
func claim_count(claimant: Node3D) -> int:
	return _count_claims(claimant)


## Query: get all parts claimed by an actor.
func get_claimed_parts(claimant: Node3D) -> Array[BodyPart]:
	var result: Array[BodyPart] = []
	for part_id: int in _claims:
		var rec: ClaimRecord = _claims[part_id] as ClaimRecord
		if rec.claimant == claimant:
			var obj: Object = instance_from_id(part_id)
			if obj is BodyPart:
				result.append(obj as BodyPart)
	return result


# ═════════════════════════════════════════════════════════════════════════════
#  INTERNAL
# ═════════════════════════════════════════════════════════════════════════════

func _count_claims(claimant: Node3D) -> int:
	var count: int = 0
	for part_id: int in _claims:
		var rec: ClaimRecord = _claims[part_id] as ClaimRecord
		if rec.claimant == claimant:
			count += 1
	return count


func _max_claims_for(claimant: Node3D) -> int:
	if claimant is PlayerController:
		return max_claims_player
	return max_claims_per_npc


func _is_on_cooldown(claimant_id: int, part_id: int) -> bool:
	if not _cooldowns.has(claimant_id):
		return false
	var cd_dict: Dictionary = _cooldowns[claimant_id] as Dictionary
	if not cd_dict.has(part_id):
		return false
	var retry_time: float = cd_dict[part_id] as float
	return (Time.get_ticks_msec() / 1000.0) < retry_time


func _set_cooldown(claimant_id: int, part_id: int) -> void:
	if not _cooldowns.has(claimant_id):
		_cooldowns[claimant_id] = {}
	var cd_dict: Dictionary = _cooldowns[claimant_id] as Dictionary
	cd_dict[part_id] = (Time.get_ticks_msec() / 1000.0) + deny_cooldown


func _enqueue(part_id: int, record: ClaimRecord) -> void:
	if not _queue.has(part_id):
		_queue[part_id] = []
	var q: Array = _queue[part_id] as Array
	# Remove existing entry from same claimant
	var filtered: Array = []
	for existing: ClaimRecord in q:
		if existing.claimant != record.claimant:
			filtered.append(existing)
	filtered.append(record)
	# Sort descending by effective priority
	filtered.sort_custom(func(a: ClaimRecord, b: ClaimRecord) -> bool:
		return a.effective_priority() > b.effective_priority()
	)
	_queue[part_id] = filtered


func _promote_queue(part_id: int, part: BodyPart) -> void:
	if not _queue.has(part_id):
		return
	var q: Array = _queue[part_id] as Array
	while not q.is_empty():
		var next: ClaimRecord = q.pop_front() as ClaimRecord
		if next.claimant == null or not is_instance_valid(next.claimant):
			continue
		_claims[part_id] = next
		if part != null:
			claim_granted.emit(part, next.claimant)
		return
	_queue.erase(part_id)
