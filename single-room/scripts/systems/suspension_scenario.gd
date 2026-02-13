class_name SuspensionScenario
extends Node
## Orchestrates the multi-NPC suspension scenario as a sequence of phases.
## Each phase is a list of parallel tasks that must all complete before the
## next phase starts.
##
## Phases:
##   0. Setup        — Assign roles, set LOD levels, spawn hardware.
##   1. Cuff         — Person 4 attaches cuffs to Person 1's wrists.
##   2. Hoist        — Person 4 pulls chain handle, Person 1 rises.
##   3. Latch        — Person 4 releases handle, chain latches.
##   4. Spread       — Persons 2-3 grab Person 1's ankles, pull apart.
##   5. Insert       — Person 6 grabs Player's penis and inserts it.
##   6. Bounce       — Persons 2-3 bounce in rhythm.
##   7. Interact     — Person 5 adjusts chain; Person 6 thrusts.
##   8. Cool-down    — Gradual stop, unlatch, lower, detach cuffs.
##
## This script is data-driven: each phase is a Dictionary describing what
## happens.  The orchestrator ticks tasks and advances phases automatically.

signal phase_started(phase_index: int, phase_name: String)
signal phase_completed(phase_index: int, phase_name: String)
signal scenario_completed()
signal scenario_aborted(reason: String)

# ── Configuration ────────────────────────────────────────────────────────────

@export_group("Timing")
## Seconds to wait after all tasks in a phase complete before advancing.
@export var phase_gap: float = 0.5
## Maximum seconds any single phase is allowed to take before timeout.
@export var phase_timeout: float = 30.0

# ── Role Assignments ─────────────────────────────────────────────────────────

## Populated by the caller before calling run().
## Key: role name ("person_1" .. "person_6", "player").
## Value: NPC root Node3D (or Player root).
var roles: Dictionary = {}

## Systems created / wired during setup.
var chain_rig: ChainRig = null
var bounce_coord: BounceCoordinator = null
var suspension_det: SuspensionDetector = null
var insertion_sys: ThirdPartyInsertion = null

# ── Internal State ───────────────────────────────────────────────────────────

var _phases: Array[Dictionary] = []
var _current_phase: int = -1
var _phase_timer: float = 0.0
var _gap_timer: float = 0.0
var _waiting_gap: bool = false
var _running: bool = false
var _tasks_complete: Dictionary = {}  # task_name → bool


func _ready() -> void:
	set_physics_process(false)
	_define_phases()


## Start the scenario. Roles must be populated first.
func run() -> void:
	if roles.is_empty():
		push_error("[SuspensionScenario] No roles assigned.")
		return
	_current_phase = -1
	_running = true
	set_physics_process(true)
	_advance_phase()


## Abort the scenario immediately.
func abort(reason: String = "manual") -> void:
	_running = false
	set_physics_process(false)
	if bounce_coord != null:
		bounce_coord.stop()
	scenario_aborted.emit(reason)
	print("[SuspensionScenario] ABORTED: %s" % reason)


func _physics_process(delta: float) -> void:
	if not _running:
		return

	if _waiting_gap:
		_gap_timer += delta
		if _gap_timer >= phase_gap:
			_waiting_gap = false
			_advance_phase()
		return

	_phase_timer += delta
	if _phase_timer >= phase_timeout:
		push_warning("[SuspensionScenario] Phase %d timed out" % _current_phase)
		_waiting_gap = true
		_gap_timer = 0.0
		phase_completed.emit(_current_phase, _get_phase_name())
		return

	# Tick current phase — check if all tasks are done
	if _all_tasks_complete():
		phase_completed.emit(_current_phase, _get_phase_name())
		print("[SuspensionScenario] Phase %d '%s' complete (%.1fs)" % [
			_current_phase, _get_phase_name(), _phase_timer])
		_waiting_gap = true
		_gap_timer = 0.0


## Advance to the next phase, or signal completion.
func _advance_phase() -> void:
	_current_phase += 1
	if _current_phase >= _phases.size():
		_running = false
		set_physics_process(false)
		scenario_completed.emit()
		print("[SuspensionScenario] ALL PHASES COMPLETE")
		return

	_phase_timer = 0.0
	_tasks_complete.clear()
	var phase: Dictionary = _phases[_current_phase]
	phase_started.emit(_current_phase, phase.get("name", "") as String)
	print("[SuspensionScenario] Phase %d '%s' started" % [
		_current_phase, phase.get("name", "")])

	# Execute phase entry actions
	if phase.has("enter"):
		var enter_fn: Callable = phase["enter"] as Callable
		enter_fn.call()


func _all_tasks_complete() -> bool:
	var phase: Dictionary = _phases[_current_phase]
	var task_names: PackedStringArray = phase.get("tasks", PackedStringArray()) as PackedStringArray
	if task_names.is_empty():
		return true
	for tn: String in task_names:
		if not _tasks_complete.get(tn, false):
			return false
	return true


func _mark_task(task_name: String) -> void:
	_tasks_complete[task_name] = true


func _get_phase_name() -> String:
	if _current_phase >= 0 and _current_phase < _phases.size():
		return (_phases[_current_phase] as Dictionary).get("name", "") as String
	return ""


# ── Phase Definitions ────────────────────────────────────────────────────────

func _define_phases() -> void:
	_phases = [
		{
			"name": "setup",
			"tasks": PackedStringArray(["setup_done"]),
			"enter": _phase_setup,
		},
		{
			"name": "cuff",
			"tasks": PackedStringArray(["cuff_left", "cuff_right"]),
			"enter": _phase_cuff,
		},
		{
			"name": "hoist",
			"tasks": PackedStringArray(["hoist_done"]),
			"enter": _phase_hoist,
		},
		{
			"name": "latch",
			"tasks": PackedStringArray(["latch_done"]),
			"enter": _phase_latch,
		},
		{
			"name": "spread",
			"tasks": PackedStringArray(["spread_left", "spread_right"]),
			"enter": _phase_spread,
		},
		{
			"name": "insert",
			"tasks": PackedStringArray(["insertion_started"]),
			"enter": _phase_insert,
		},
		{
			"name": "bounce",
			"tasks": PackedStringArray(["bounce_running"]),
			"enter": _phase_bounce,
		},
		{
			"name": "interact",
			"tasks": PackedStringArray(),  # Timer-based, completes on timeout
			"enter": _phase_interact,
		},
		{
			"name": "cooldown",
			"tasks": PackedStringArray(["cooldown_done"]),
			"enter": _phase_cooldown,
		},
	]


# ── Phase Entry Callables ────────────────────────────────────────────────────

func _phase_setup() -> void:
	# Set LOD per role
	_set_role_lod("person_1", HumanoidRagdollBuilder.DetailLevel.FULL)
	_set_role_lod("person_2", HumanoidRagdollBuilder.DetailLevel.MEDIUM)
	_set_role_lod("person_3", HumanoidRagdollBuilder.DetailLevel.MEDIUM)
	_set_role_lod("person_4", HumanoidRagdollBuilder.DetailLevel.MINIMAL)
	_set_role_lod("person_5", HumanoidRagdollBuilder.DetailLevel.MINIMAL)
	_set_role_lod("person_6", HumanoidRagdollBuilder.DetailLevel.MEDIUM)

	# Spawn chain rig if not already present
	if chain_rig == null:
		chain_rig = ChainRig.new()
		chain_rig.name = "SuspensionChainRig"
		chain_rig.latch_enabled = true
		get_tree().current_scene.add_child(chain_rig)
		# Position near Person 1
		var p1: Node3D = _get_role("person_1")
		if p1 != null:
			chain_rig.global_position = p1.global_position + Vector3.UP * 2.5

	# Wire suspension detector for Person 1
	var p1_ragdoll: HumanoidRagdollBuilder = _get_ragdoll("person_1")
	var p1_binding: Node = _get_binding("person_1")
	if p1_ragdoll != null and p1_binding != null:
		suspension_det = SuspensionDetector.new()
		suspension_det.name = "SuspensionDetector_P1"
		_get_role("person_1").add_child(suspension_det)
		suspension_det.setup(p1_ragdoll, p1_binding)

	# Wire insertion system on Person 1
	if p1_ragdoll != null:
		insertion_sys = ThirdPartyInsertion.new()
		insertion_sys.name = "ThirdPartyInsertion_P1"
		_get_role("person_1").add_child(insertion_sys)
		insertion_sys.setup(p1_ragdoll, PackedStringArray(["vaginal", "anal"]))

	# Wire bounce coordinator (global)
	bounce_coord = BounceCoordinator.new()
	bounce_coord.name = "BounceCoordinator"
	add_child(bounce_coord)

	_mark_task("setup_done")


func _phase_cuff() -> void:
	# Person 4 attaches cuffs to Person 1's left and right wrists.
	# In the full implementation, this would command Person 4's NPC AI to
	# pathfind to the cuffs, grab them, and attach them.  For now, we
	# directly attach using the CuffFastener API.
	var p1_ragdoll: HumanoidRagdollBuilder = _get_ragdoll("person_1")
	if p1_ragdoll == null or chain_rig == null:
		_mark_task("cuff_left")
		_mark_task("cuff_right")
		return

	# Find cuffs on the chain rig
	for child: Node in chain_rig.get_children():
		if child is CuffFastener:
			var cuff: CuffFastener = child as CuffFastener
			var target_part: String = ""
			if cuff.name.contains("Left"):
				target_part = "left_hand"
			elif cuff.name.contains("Right"):
				target_part = "right_hand"

			if target_part != "" and p1_ragdoll.parts.has(target_part):
				var wrist: BodyPart = p1_ragdoll.parts[target_part] as BodyPart
				cuff.attach_to(wrist, wrist.global_position)
				if target_part == "left_hand":
					_mark_task("cuff_left")
				else:
					_mark_task("cuff_right")


func _phase_hoist() -> void:
	# Person 4 grabs the chain handle and pulls down, hoisting Person 1.
	# Simulated by programmatically setting the spool position.
	if chain_rig != null:
		chain_rig.unlatch()
		# Animate spool over time via a tween
		var tween: Tween = create_tween()
		tween.tween_method(chain_rig.set_spool_position, 0.0,
			chain_rig.slider_min_y * 0.85, 3.0)
		tween.tween_callback(_mark_task.bind("hoist_done"))


func _phase_latch() -> void:
	# Person 4 releases — chain latches at current position.
	if chain_rig != null:
		chain_rig.latch()
	_mark_task("latch_done")


func _phase_spread() -> void:
	# Persons 2-3 grab Person 1's ankles.
	# In full implementation, NPC AI would handle this.
	# Mark complete immediately — physical interaction will follow.
	_mark_task("spread_left")
	_mark_task("spread_right")


func _phase_insert() -> void:
	# Person 6 takes Player's penis and inserts into Person 1's vaginal passage.
	if insertion_sys == null:
		_mark_task("insertion_started")
		return

	var player_ragdoll: HumanoidRagdollBuilder = _get_ragdoll("player")
	var actor: Node3D = _get_role("person_6")
	if player_ragdoll == null or actor == null:
		_mark_task("insertion_started")
		return

	# Gather penis parts as the tool
	var tool_parts: Array[RigidBody3D] = []
	for pname: String in ["penis_base", "penis_mid", "penis_tip"]:
		if player_ragdoll.parts.has(pname):
			tool_parts.append(player_ragdoll.parts[pname] as RigidBody3D)

	if tool_parts.is_empty():
		_mark_task("insertion_started")
		return

	insertion_sys.begin_attempt("vaginal", tool_parts, actor)
	# Listen for actual insertion
	insertion_sys.insertion_started.connect(
		func(_pn: String, _tip: RigidBody3D) -> void:
			_mark_task("insertion_started"),
		CONNECT_ONE_SHOT)


func _phase_bounce() -> void:
	# Start coordinated bouncing with Persons 2-3 on Person 1's lower legs.
	if bounce_coord == null:
		_mark_task("bounce_running")
		return

	var p1_ragdoll: HumanoidRagdollBuilder = _get_ragdoll("person_1")
	if p1_ragdoll == null:
		_mark_task("bounce_running")
		return

	# Add Person 1's lower legs as bounce targets
	for side: String in ["left_lower_leg", "right_lower_leg"]:
		if p1_ragdoll.parts.has(side):
			var offset: float = 0.0 if side.begins_with("left") else 0.0
			bounce_coord.add_slot(
				p1_ragdoll.parts[side] as RigidBody3D, offset, Vector3.DOWN)

	bounce_coord.bpm = 60.0
	bounce_coord.start()
	_mark_task("bounce_running")


func _phase_interact() -> void:
	# Free-form phase — Person 5 adjusts chain, Person 6 thrusts.
	# This phase completes on timeout (no explicit tasks).
	pass


func _phase_cooldown() -> void:
	# Stop bouncing, lower Person 1, detach cuffs.
	if bounce_coord != null:
		bounce_coord.stop()
		bounce_coord.clear_slots()

	if insertion_sys != null:
		insertion_sys.end_attempt("vaginal")

	if chain_rig != null:
		chain_rig.unlatch()
		var tween: Tween = create_tween()
		tween.tween_method(chain_rig.set_spool_position,
			chain_rig.get_spool_position(), 0.0, 3.0)
		tween.tween_callback(func() -> void:
			chain_rig.latch()
			# Detach cuffs
			for child: Node in chain_rig.get_children():
				if child is CuffFastener:
					(child as CuffFastener).detach()
			_mark_task("cooldown_done"))


# ── Helpers ──────────────────────────────────────────────────────────────────

func _get_role(role_name: String) -> Node3D:
	return roles.get(role_name) as Node3D


func _get_ragdoll(role_name: String) -> HumanoidRagdollBuilder:
	var npc: Node3D = _get_role(role_name)
	if npc == null:
		return null
	var direct_ragdoll: HumanoidRagdollBuilder = npc.get("ragdoll") as HumanoidRagdollBuilder
	if direct_ragdoll != null:
		return direct_ragdoll

	for child: Node in npc.get_children():
		if child is PlayerRagdollBridge:
			var bridge: PlayerRagdollBridge = child as PlayerRagdollBridge
			if bridge.ragdoll != null:
				return bridge.ragdoll
		if child is HumanoidRagdollBuilder:
			return child as HumanoidRagdollBuilder

	return npc.get_node_or_null("HumanoidRagdoll") as HumanoidRagdollBuilder


func _get_binding(role_name: String) -> Node:
	var npc: Node3D = _get_role(role_name)
	if npc == null:
		return null
	var direct_binding: Node = npc.get("skeleton_binding") as Node
	if direct_binding != null:
		return direct_binding

	for child: Node in npc.get_children():
		if child is PlayerRagdollBridge:
			var bridge: PlayerRagdollBridge = child as PlayerRagdollBridge
			if bridge.skeleton_binding != null:
				return bridge.skeleton_binding

	var npc_binding: Node = npc.get_node_or_null("SkeletonBinding")
	if npc_binding != null:
		return npc_binding
	return npc.get_node_or_null("PlayerSkeletonBinding")


func _set_role_lod(role_name: String, level: int) -> void:
	var ragdoll: HumanoidRagdollBuilder = _get_ragdoll(role_name)
	if ragdoll == null:
		return
	# Use PhysicsLOD if present, otherwise direct
	var npc: Node3D = _get_role(role_name)
	if npc == null:
		return
	for child: Node in npc.get_children():
		if child is PhysicsLOD:
			(child as PhysicsLOD).force_lod(level)
			return
	# Fallback: direct rebuild
	ragdoll.rebuild_at_lod(level as HumanoidRagdollBuilder.DetailLevel)
