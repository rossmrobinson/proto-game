class_name ActionPattern
extends Resource
## Combines an ActionMotion + ActionTempo + base pose + metadata to form
## a complete, playable sexual/physical interaction pattern.
##
## This is the unit of content that gets handed to ActionDriver — it knows
## what moves (motion), how fast/deep/hard (tempo), and what context it
## applies to (metadata).

# ── Core Components ──────────────────────────────────────────────────────────

@export_group("Components")
## The motion trajectory.
@export var motion: ActionMotion = null
## The tempo / speed / force profile.
@export var tempo: ActionTempo = null
## Name of the RagdollPose to set as the base before motion starts.
@export var base_pose_name: String = ""

# ── Identity ─────────────────────────────────────────────────────────────────

@export_group("Identity")
## Unique pattern name (e.g. "missionary_gentle", "cowgirl_bounce").
@export var pattern_name: String = ""
## Interaction type tags: "vaginal", "anal", "oral", "manual", "locomotion", "idle".
@export var interaction_types: Array[String] = []
## Freeform tags for library queries: "gentle", "rough", "teasing", etc.
@export var tags: Array[String] = []

# ── Participants ─────────────────────────────────────────────────────────────

@export_group("Participants")
## Minimum actors required.
@export_range(1, 4) var min_participants: int = 2
## Maximum actors supported.
@export_range(1, 4) var max_participants: int = 2
## Body parts involved (e.g. ["pelvis", "vagina", "penis"]).
@export var involved_parts: Array[String] = []
## Anatomy required for this pattern (e.g. ["penis"] or ["vagina"]).
@export var required_anatomy: Array[String] = []

# ── Escalation ───────────────────────────────────────────────────────────────

@export_group("Escalation")
## Pattern to escalate TO when conditions are met.
@export var escalation_target: String = ""
## Seconds of play before escalation becomes available.
@export_range(0.0, 120.0) var escalation_after: float = 30.0
## Arousal threshold (0–1) that triggers escalation.
@export_range(0.0, 1.0) var escalation_on_arousal: float = 0.7


## Factory method.
static func create(p_name: String, p_motion: ActionMotion,
		p_tempo: ActionTempo, p_base_pose: String = "") -> ActionPattern:
	var pat: ActionPattern = ActionPattern.new()
	pat.pattern_name = p_name
	pat.motion = p_motion
	pat.tempo = p_tempo
	pat.base_pose_name = p_base_pose
	return pat
