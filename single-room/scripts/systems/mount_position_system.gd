class_name MountPositionSystem
extends Node
## Calculates and drives mount/approach positions for sexual interactions.
## Supports both player (via genitals_pressed signal from HandInteractionSystem)
## and NPC-driven mounting (via NPCInteractionIntent with GoalCategory.MOUNT).
##
## Computes a target transform that aligns the mounter's genitals with the
## target's passage entrance, accounting for body orientation and posture.
##
## Attach as child of NPCPlaceholder OR PlayerController.

signal mount_started(mounter: Node3D, target: Node3D, passage_area: String)
signal mount_aligned(mounter: Node3D, target: Node3D)
signal mount_cancelled(reason: String)

const FORCE_REFERENCE_TPS: float = 120.0

# ── Config ───────────────────────────────────────────────────────────────────

@export_group("Alignment")
## How close (meters) the genital tip must be to the passage entrance
## to count as "aligned".
@export var alignment_threshold: float = 0.06
## Force applied to the pelvis to drive toward mount position.
@export var mount_drive_force: float = 25.0
## Damping on pelvis during mount approach to prevent overshoot.
@export var mount_damping: float = 8.0
## Maximum approach speed (m/s).
@export var max_approach_speed: float = 0.6

@export_group("Offset")
## Forward offset from passage entrance (meters) — gap to avoid clipping.
@export var approach_standoff: float = 0.12
## Vertical offset adjustment for height mismatch.
@export var height_adjust_speed: float = 2.0

# ── Passage Prioritization ──────────────────────────────────────────────────
## Which passage types to try, in order, for genital-to-passage mounting.
const VAGINAL_ENTRANCES: PackedStringArray = [
	"vaginal_passage_entrance_0", "vaginal_passage_entrance_1",
	"vaginal_passage_entrance_2", "vaginal_passage_entrance_3",
]
const ANAL_ENTRANCES: PackedStringArray = [
	"anal_passage_entrance_0", "anal_passage_entrance_1",
	"anal_passage_entrance_2", "anal_passage_entrance_3",
]
const ORAL_ENTRANCES: PackedStringArray = [
	"oral_passage_entrance_0", "oral_passage_entrance_1",
	"oral_passage_entrance_2", "oral_passage_entrance_3",
]

# ── State ────────────────────────────────────────────────────────────────────

enum MountPhase {
	IDLE,          ## Not mounting
	SEEKING,       ## Looking for passage entrance
	APPROACHING,   ## Moving toward alignment
	ALIGNED,       ## Genitals at passage entrance
	INSERTED,      ## Penetration detected (passage response active)
}

var mount_phase: MountPhase = MountPhase.IDLE
var _mounter_pelvis: BodyPart = null
var _mounter_tip: BodyPart = null  # penis_tip or equipped_shaft tip
var _target_npc: NPCPlaceholder = null
var _target_entrance: BodyPart = null
var _passage_area: String = ""  # "vaginal", "anal", or "oral"
var _owner: Node3D = null
var _force_tick_scale: float = 1.0


func _ready() -> void:
	_owner = get_parent() as Node3D
	var physics_tps: float = float(ProjectSettings.get_setting("physics/common/physics_ticks_per_second"))
	_force_tick_scale = FORCE_REFERENCE_TPS / maxf(physics_tps, 1.0)


func _physics_process(delta: float) -> void:
	if mount_phase == MountPhase.IDLE:
		return

	match mount_phase:
		MountPhase.SEEKING:
			_do_seek()
		MountPhase.APPROACHING:
			_do_approach(delta)
		MountPhase.ALIGNED:
			_do_aligned(delta)
		MountPhase.INSERTED:
			_do_inserted(delta)


# ═════════════════════════════════════════════════════════════════════════════
#  PUBLIC API
# ═════════════════════════════════════════════════════════════════════════════

## Begin mounting toward a target NPC.  Finds the best passage entrance.
## mounter_ragdoll: the ragdoll that has the penis/strap-on.
## target_npc: the NPC being mounted.
## preferred_area: "vaginal", "anal", "oral", or "" for auto-detect.
func begin_mount(mounter_ragdoll: HumanoidRagdollBuilder,
		target_npc: NPCPlaceholder,
		preferred_area: String = "") -> bool:
	if mounter_ragdoll == null or target_npc == null:
		return false

	# Find mounter's genital tip
	_mounter_tip = _find_genital_tip(mounter_ragdoll)
	if _mounter_tip == null:
		mount_cancelled.emit("no_genital_tip")
		return false

	# Find mounter's pelvis for whole-body drive
	if mounter_ragdoll.parts.has("pelvis"):
		_mounter_pelvis = mounter_ragdoll.parts["pelvis"] as BodyPart

	_target_npc = target_npc
	_passage_area = preferred_area
	mount_phase = MountPhase.SEEKING
	mount_started.emit(_owner, target_npc, preferred_area)
	return true


## Cancel an active mount.
func cancel_mount() -> void:
	var was_active: bool = mount_phase != MountPhase.IDLE
	mount_phase = MountPhase.IDLE
	_mounter_pelvis = null
	_mounter_tip = null
	_target_npc = null
	_target_entrance = null
	_passage_area = ""
	if was_active:
		mount_cancelled.emit("cancelled")


## Query: is currently in any mount phase?
func is_mounting() -> bool:
	return mount_phase != MountPhase.IDLE


## Query: is aligned and ready for insertion?
func is_aligned() -> bool:
	return mount_phase == MountPhase.ALIGNED or mount_phase == MountPhase.INSERTED


# ═════════════════════════════════════════════════════════════════════════════
#  PHASE LOGIC
# ═════════════════════════════════════════════════════════════════════════════

func _do_seek() -> void:
	if _target_npc == null or _target_npc.ragdoll == null:
		cancel_mount()
		return

	var ragdoll: HumanoidRagdollBuilder = _target_npc.ragdoll

	# Build prioritized entrance list
	var entrances: PackedStringArray = _get_entrance_list()

	# Find nearest accessible entrance
	var best: BodyPart = null
	var best_dist: float = INF

	for ename: String in entrances:
		if not ragdoll.parts.has(ename):
			continue
		var part: BodyPart = ragdoll.parts[ename] as BodyPart
		if part == null:
			continue
		var dist: float = _mounter_tip.global_position.distance_to(
			part.global_position)
		if dist < best_dist:
			best_dist = dist
			best = part

	if best == null:
		mount_cancelled.emit("no_entrance_found")
		mount_phase = MountPhase.IDLE
		return

	_target_entrance = best
	mount_phase = MountPhase.APPROACHING


func _do_approach(_delta: float) -> void:
	if _mounter_tip == null or _target_entrance == null:
		cancel_mount()
		return
	if not is_instance_valid(_mounter_tip) or not is_instance_valid(_target_entrance):
		cancel_mount()
		return

	# Calculate approach vector
	var target_pos: Vector3 = _target_entrance.global_position
	var tip_pos: Vector3 = _mounter_tip.global_position
	var to_target: Vector3 = target_pos - tip_pos
	var dist: float = to_target.length()

	# Check alignment
	if dist < alignment_threshold:
		mount_phase = MountPhase.ALIGNED
		mount_aligned.emit(_owner, _target_npc)
		return

	# Apply force to pelvis to drive whole body, plus gentle force on tip
	var norm: Vector3 = to_target.normalized()

	if _mounter_pelvis != null and is_instance_valid(_mounter_pelvis):
		var pelvis_speed: float = _mounter_pelvis.linear_velocity.length()
		if pelvis_speed < max_approach_speed:
			_mounter_pelvis.apply_central_force(
				norm * mount_drive_force * _force_tick_scale)
		# Damping to prevent overshoot
		_mounter_pelvis.linear_damp = mount_damping

	# Gentle guide on tip itself
	_mounter_tip.apply_central_force(norm * mount_drive_force * 0.3 * _force_tick_scale)


func _do_aligned(_delta: float) -> void:
	# Check if still aligned
	if _mounter_tip == null or _target_entrance == null:
		cancel_mount()
		return
	if not is_instance_valid(_mounter_tip) or not is_instance_valid(_target_entrance):
		cancel_mount()
		return

	var dist: float = _mounter_tip.global_position.distance_to(
		_target_entrance.global_position)

	if dist > alignment_threshold * 3.0:
		# Lost alignment — go back to approaching
		mount_phase = MountPhase.APPROACHING
		return

	# Check if passage_response has detected intruder (= insertion)
	if _target_npc != null and _target_npc.passage_response != null:
		# The passage grip system handles the actual insertion detection
		mount_phase = MountPhase.INSERTED


func _do_inserted(_delta: float) -> void:
	# Monitor insertion — if tip drifts too far, downgrade phase
	if _mounter_tip == null or _target_entrance == null:
		cancel_mount()
		return
	if not is_instance_valid(_mounter_tip) or not is_instance_valid(_target_entrance):
		cancel_mount()
		return

	var dist: float = _mounter_tip.global_position.distance_to(
		_target_entrance.global_position)
	if dist > alignment_threshold * 5.0:
		mount_phase = MountPhase.APPROACHING


# ═════════════════════════════════════════════════════════════════════════════
#  HELPERS
# ═════════════════════════════════════════════════════════════════════════════

func _find_genital_tip(ragdoll: HumanoidRagdollBuilder) -> BodyPart:
	# Check for equipped phallus first
	if ragdoll.parts.has("equipped_shaft"):
		return ragdoll.parts["equipped_shaft"] as BodyPart
	# Natural penis
	if ragdoll.parts.has("penis_tip"):
		return ragdoll.parts["penis_tip"] as BodyPart
	# Clitoris as fallback for female NPCs with strap-on
	if ragdoll.parts.has("clitoris"):
		return ragdoll.parts["clitoris"] as BodyPart
	return null


func _get_entrance_list() -> PackedStringArray:
	# If preferred area is set, prioritize it
	match _passage_area:
		"vaginal":
			return VAGINAL_ENTRANCES + ANAL_ENTRANCES
		"anal":
			return ANAL_ENTRANCES + VAGINAL_ENTRANCES
		"oral":
			return ORAL_ENTRANCES
		_:
			# Auto-detect: try vaginal first, then anal, then oral
			return VAGINAL_ENTRANCES + ANAL_ENTRANCES + ORAL_ENTRANCES
