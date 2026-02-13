class_name FluidSystem
extends Node
## Top-level fluid coordinator for a single NPC.
##
## Owns and wires:
##   - FluidAccumulator  (passage retention)
##   - FluidSurface      (external decals / drips)
##   - Emitter pool      (BodyFluidEmitters for passages, eyes, skin)
##   - FluidString pool  (viscous threads)
##
## Listens to:
##   - ArousalSystem.orgasm_started  → trigger ejaculation deposit
##   - ThirdPartyInsertion signals   → mark passages as penetrated
##   - FluidAccumulator signals      → spawn leak / expel emitters
##   - NerveSystem stimulation       → tears, sweat triggers

signal ejaculation_started(passage: String, volume: float)
signal fluid_spit(from_npc: Node, target_pos: Vector3, fluid: FluidType, volume: float)
## Emitted when this NPC ejaculates inside another NPC's passage.
## The orchestrator must route this to the receiving NPC's deposit_into_passage().
signal internal_ejaculation(passage: String, fluid: FluidType, volume: float)

# ── Tuning ───────────────────────────────────────────────────────────────────

@export_group("Ejaculation")
## Volume (mL) of a single full ejaculation.
@export var ejaculation_volume: float = 5.0
## Duration (seconds) over which ejaculation emits.
@export var ejaculation_duration: float = 2.5
## Number of spurts per ejaculation.
@export_range(1, 12) var ejaculation_spurts: int = 6

@export_group("Tears")
## Discomfort level (0–1) that triggers tearing.
@export_range(0.0, 1.0) var tear_discomfort_threshold: float = 0.6
## Arousal level (0–1) that triggers pleasure tears.
@export_range(0.0, 1.0) var tear_pleasure_threshold: float = 0.85
## Tear emission rate (particles/sec) at full crying.
@export var tear_emission_rate: float = 10.0

@export_group("Sweat")
## Arousal level above which sweat starts.
@export_range(0.0, 1.0) var sweat_arousal_threshold: float = 0.5
## Sweat emission rate at full arousal.
@export var sweat_emission_rate: float = 8.0

@export_group("Vaginal Lubrication")
## Arousal threshold for vaginal lubrication to begin.
@export_range(0.0, 1.0) var lubrication_arousal_threshold: float = 0.25
## Lubrication rate (mL/s) at full arousal.
@export var lubrication_rate: float = 0.8

@export_group("Strings")
## Maximum simultaneous string renderers.
@export_range(0, 8) var max_strings: int = 4

# ── References ───────────────────────────────────────────────────────────────

var accumulator: FluidAccumulator = null
var surface: FluidSurface = null

var _ragdoll: HumanoidRagdollBuilder = null
var _arousal_system: ArousalSystem = null
var _nerve_system: NerveSystem = null
var _character_profile: CharacterProfile = null
var _insertion_system: ThirdPartyInsertion = null

## External insertion systems we're monitoring for cross-NPC wiring.
var _external_insertion_systems: Array[ThirdPartyInsertion] = []
## Receiving NPC FluidSystems for internal ejaculation routing.
## Keyed by passage base name → FluidSystem.
var _receiving_fluid_systems: Dictionary = {}
## Interaction partners (FluidSystem references, for participant counting).
var _interaction_partners: Array[Node] = []

## Emitter pool: Array[BodyFluidEmitter]
var _emitter_pool: Array[BodyFluidEmitter] = []
## Active emitters keyed by purpose: "ejaculation_oral" → BodyFluidEmitter
var _active_emitters: Dictionary = {}

## String renderer pool
var _string_pool: Array[FluidString] = []
var _active_strings: Array[FluidString] = []

## Ejaculation state
var _ejaculation_timer: float = 0.0
var _ejaculation_remaining: float = 0.0
var _ejaculation_passage: String = ""
var _ejaculation_fluid: FluidType = null
## Per-orgasm scaled values (set in _begin_ejaculation).
var _ejac_scaled_duration: float = 2.5
var _ejac_scaled_spurts: int = 6

## Current insertion target passage (set by orchestrator or auto-detected).
var _current_insertion_target: String = ""

## Continuous secretion tracking
var _lubrication_accumulator: float = 0.0
var _sweat_accumulator: float = 0.0
var _tear_active: bool = false
var _has_vaginal_passage: bool = false
var _has_penis: bool = false


func _ready() -> void:
	# Create sub-systems
	accumulator = FluidAccumulator.new()
	accumulator.name = "FluidAccumulator"
	add_child(accumulator)

	surface = FluidSurface.new()
	surface.name = "FluidSurface"
	add_child(surface)

	# Wire accumulator signals
	accumulator.fluid_leaking.connect(_on_fluid_leaking)
	accumulator.fluid_expelled.connect(_on_fluid_expelled)
	accumulator.passage_emptied.connect(_on_passage_emptied)

	set_physics_process(false)


## Wire up to NPC subsystems. Call after ragdoll and all systems are built.
func setup(npc: Node) -> void:
	_ragdoll = npc.get("ragdoll") as HumanoidRagdollBuilder
	_arousal_system = npc.get("arousal_system") as ArousalSystem
	_nerve_system = npc.get("nerve_system") as NerveSystem
	_character_profile = npc.get("character_profile") as CharacterProfile
	_insertion_system = npc.get("insertion_system") as ThirdPartyInsertion

	if _ragdoll != null:
		accumulator.setup(_ragdoll)
		surface.activate()
		_has_vaginal_passage = _ragdoll.parts.has("vaginal_ring_top")
		_has_penis = _ragdoll.parts.has("penis_base")

	# Connect to arousal system orgasm signal
	if _arousal_system != null and _arousal_system.has_signal(&"orgasm_started"):
		_arousal_system.orgasm_started.connect(_on_orgasm_started)

	# Connect to insertion system
	if _insertion_system != null:
		_insertion_system.insertion_started.connect(_on_insertion_started)
		_insertion_system.insertion_ended.connect(_on_insertion_ended)

	set_physics_process(true)


## External API: voluntarily expel fluid from a passage (spit, push out).
## Returns the result dict from FluidAccumulator.expel().
func expel_from_passage(passage: String, direction: Vector3) -> Dictionary:
	var result: Dictionary = accumulator.expel(passage, direction)
	return result


## External API: deposit fluid into a passage (e.g., another NPC ejaculates here).
func deposit_into_passage(passage: String, fluid: FluidType, volume: float) -> void:
	accumulator.deposit(passage, fluid, volume)


## External API: place fluid on external body surface.
func splash_on_body(body_part: RigidBody3D, part_name: String,
		world_pos: Vector3, fluid: FluidType, volume: float) -> void:
	surface.add_patch(body_part, part_name, world_pos, fluid, volume)


## External API: start a viscous string between two nodes.
func start_string(point_a: Node3D, point_b: Node3D, fluid: FluidType) -> FluidString:
	if not fluid.can_form_strings:
		return null
	if fluid.viscosity < fluid.string_viscosity_threshold:
		return null
	if _active_strings.size() >= max_strings:
		# Recycle oldest
		_active_strings[0].break_string()
		_active_strings.remove_at(0)

	var fs: FluidString = _acquire_string()
	fs.start_string(point_a, point_b, fluid)
	_active_strings.append(fs)
	return fs


func _physics_process(delta: float) -> void:
	_update_ejaculation(delta)
	_update_continuous_secretions(delta)
	_cleanup_strings()


## Handle orgasm signal — begin ejaculation sequence.
## intensity: 0.3–2.0+ from ArousalSystem (1.0 = baseline).
func _on_orgasm_started(intensity: float) -> void:
	if _has_penis:
		var target_passage: String = _find_current_insertion_target()
		_begin_ejaculation(target_passage, intensity)
	elif _has_vaginal_passage:
		# Female orgasm → extra vaginal fluid surge, scaled by intensity
		var surge_volume: float = ejaculation_volume * 0.6 * intensity
		var fluid: FluidType = BodyFluidLibrary.vaginal_fluid()
		accumulator.deposit("vaginal", fluid, surge_volume)


## Begin an ejaculation over multiple spurts, scaled by orgasm intensity.
func _begin_ejaculation(target_passage: String, intensity: float = 1.0) -> void:
	_ejaculation_passage = target_passage
	# Scale volume and duration by intensity
	_ejaculation_remaining = ejaculation_volume * intensity
	_ejaculation_timer = 0.0
	_ejaculation_fluid = BodyFluidLibrary.semen()
	# Stronger orgasms last longer and have more spurts
	var scaled_duration: float = ejaculation_duration * lerpf(0.7, 1.5, clampf(intensity - 0.3, 0.0, 1.7) / 1.7)
	var scaled_spurts: int = clampi(ceili(float(ejaculation_spurts) * intensity), 3, 20)
	_ejac_scaled_duration = scaled_duration
	_ejac_scaled_spurts = scaled_spurts
	ejaculation_started.emit(target_passage, _ejaculation_remaining)


## Spurt-based ejaculation over time.
func _update_ejaculation(delta: float) -> void:
	if _ejaculation_remaining <= 0.0:
		return

	_ejaculation_timer += delta
	var spurt_interval: float = _ejac_scaled_duration / float(_ejac_scaled_spurts)
	var spurt_volume: float = _ejaculation_remaining / float(maxi(_ejac_scaled_spurts, 1))

	if _ejaculation_timer >= spurt_interval:
		_ejaculation_timer -= spurt_interval
		var vol: float = minf(spurt_volume, _ejaculation_remaining)
		_ejaculation_remaining -= vol

		if _ejaculation_passage.is_empty():
			# External ejaculation — emit particles from penis tip
			_emit_external_ejaculation(vol)
		else:
			# Internal — deposit into target passage on the RECEIVING NPC.
			# Emit signal so the orchestrator routes it to the correct NPC.
			internal_ejaculation.emit(
				_ejaculation_passage, _ejaculation_fluid, vol)

	if _ejaculation_remaining <= 0.0:
		_ejaculation_passage = ""
		_ejaculation_fluid = null


## Emit particles for an external (not-in-passage) ejaculation from penis tip.
func _emit_external_ejaculation(volume: float) -> void:
	if _ragdoll == null or not _ragdoll.parts.has("penis_tip"):
		return
	var tip: RigidBody3D = _ragdoll.parts["penis_tip"] as RigidBody3D
	var emitter: BodyFluidEmitter = _acquire_emitter("ejaculation_external")
	emitter.global_position = tip.global_position
	emitter.fluid_type = _ejaculation_fluid
	emitter.interior_origin = true
	emitter.origin_body = tip
	emitter.emission_rate = 50.0
	emitter.emit_burst(ceili(volume * 8.0))


## Continuous vaginal lubrication, sweat, and tears based on arousal/discomfort.
func _update_continuous_secretions(delta: float) -> void:
	if _arousal_system == null:
		return

	var arousal: float = _arousal_system.arousal_level

	# Vaginal lubrication
	if _has_vaginal_passage and arousal > lubrication_arousal_threshold:
		var t: float = (arousal - lubrication_arousal_threshold) \
			/ (1.0 - lubrication_arousal_threshold)
		_lubrication_accumulator += lubrication_rate * t * delta
		# Deposit in small increments to avoid per-frame noise
		if _lubrication_accumulator >= 0.2:
			var fluid: FluidType = BodyFluidLibrary.vaginal_fluid()
			accumulator.deposit("vaginal", fluid, _lubrication_accumulator)
			_lubrication_accumulator = 0.0

	# ── Sweat (surface patches on torso/forehead) ──
	if arousal > sweat_arousal_threshold:
		var sweat_t: float = (arousal - sweat_arousal_threshold) \
			/ (1.0 - sweat_arousal_threshold)
		_sweat_accumulator += sweat_emission_rate * sweat_t * delta
		if _sweat_accumulator >= 3.0:
			_spawn_sweat_patches(sweat_t)
			_sweat_accumulator = 0.0
	else:
		_sweat_accumulator = maxf(_sweat_accumulator - delta * 2.0, 0.0)

	# ── Tears (emitter on eye parts driven by discomfort) ──
	_update_tears(delta)


## Place sweat patches on body surface (torso, forehead, upper arms).
func _spawn_sweat_patches(intensity: float) -> void:
	if _ragdoll == null or surface == null:
		return
	var sweat_fluid: FluidType = BodyFluidLibrary.sweat()
	var sweat_parts: PackedStringArray = PackedStringArray([
		"chest", "spine_upper", "head", "left_upper_arm", "right_upper_arm",
	])
	# Pick 1-2 random body parts per batch
	var count: int = 1 + (1 if intensity > 0.6 else 0)
	for _i: int in range(count):
		var part_name: String = sweat_parts[randi() % sweat_parts.size()]
		if not _ragdoll.parts.has(part_name):
			continue
		var body: RigidBody3D = _ragdoll.parts[part_name] as RigidBody3D
		if body == null:
			continue
		# Random offset on body surface
		var offset: Vector3 = Vector3(
			randf_range(-0.05, 0.05),
			randf_range(-0.03, 0.03),
			randf_range(-0.05, 0.05),
		)
		var world_pos: Vector3 = body.global_position + offset
		var volume: float = 0.1 * intensity
		surface.add_patch(body, part_name, world_pos, sweat_fluid, volume)


## Update tear emitters based on discomfort OR intense pleasure.
func _update_tears(_delta: float) -> void:
	if _character_profile == null or _ragdoll == null:
		return
	var discomfort: float = _character_profile.discomfort_level / 100.0
	var arousal: float = _arousal_system.arousal_level if _arousal_system != null else 0.0

	# Tears from pain or overwhelming pleasure
	var pain_crying: bool = discomfort >= tear_discomfort_threshold
	var pleasure_crying: bool = arousal >= tear_pleasure_threshold
	var should_cry: bool = pain_crying or pleasure_crying

	# Use whichever driver is stronger for intensity
	var cry_t: float = 0.0
	if pain_crying:
		cry_t = maxf(cry_t, (discomfort - tear_discomfort_threshold) \
			/ (1.0 - tear_discomfort_threshold))
	if pleasure_crying:
		cry_t = maxf(cry_t, (arousal - tear_pleasure_threshold) \
			/ (1.0 - tear_pleasure_threshold))
	cry_t = clampf(cry_t, 0.0, 1.0)

	if should_cry and not _tear_active:
		_tear_active = true
		var tear_fluid: FluidType = BodyFluidLibrary.tears()
		for eye_name: String in ["left_eye", "right_eye"]:
			if not _ragdoll.parts.has(eye_name):
				continue
			var eye_body: RigidBody3D = _ragdoll.parts[eye_name] as RigidBody3D
			var key: String = "tears_%s" % eye_name
			var emitter: BodyFluidEmitter = _acquire_emitter(key)
			emitter.global_position = eye_body.global_position
			emitter.fluid_type = tear_fluid
			emitter.emission_direction = Vector3.DOWN
			emitter.emission_rate = lerpf(3.0, tear_emission_rate, cry_t)
			if not emitter.is_emitting():
				emitter.start_emitting()
	elif should_cry and _tear_active:
		for eye_name: String in ["left_eye", "right_eye"]:
			var key: String = "tears_%s" % eye_name
			if _active_emitters.has(key):
				var emitter: BodyFluidEmitter = _active_emitters[key] as BodyFluidEmitter
				emitter.emission_rate = lerpf(3.0, tear_emission_rate, cry_t)
	elif not should_cry and _tear_active:
		_tear_active = false
		for eye_name: String in ["left_eye", "right_eye"]:
			release_emitter("tears_%s" % eye_name)


## Spawn leak emitter when accumulator reports leaking.
func _on_fluid_leaking(passage: String, fluid: FluidType, rate: float) -> void:
	var key: String = "leak_%s" % passage
	var emitter: BodyFluidEmitter = _acquire_emitter(key)

	# Position at passage entrance (ring)
	var ring_name: String = "%s_ring_top" % passage
	if _ragdoll != null and _ragdoll.parts.has(ring_name):
		var ring_body: RigidBody3D = _ragdoll.parts[ring_name] as RigidBody3D
		emitter.global_position = ring_body.global_position
		emitter.interior_origin = true
		emitter.origin_body = ring_body
	emitter.fluid_type = fluid
	emitter.emission_rate = clampf(rate * 6.0, 5.0, 60.0)
	if not emitter.is_emitting():
		emitter.start_emitting()


## Spawn burst emitter for voluntary expulsion (spit, push out).
func _on_fluid_expelled(passage: String, fluid: FluidType,
		volume: float, direction: Vector3) -> void:
	var key: String = "expel_%s" % passage
	var emitter: BodyFluidEmitter = _acquire_emitter(key)

	var ring_name: String = "%s_ring_top" % passage
	if _ragdoll != null and _ragdoll.parts.has(ring_name):
		var ring_body: RigidBody3D = _ragdoll.parts[ring_name] as RigidBody3D
		emitter.global_position = ring_body.global_position
		emitter.interior_origin = true
		emitter.origin_body = ring_body
	emitter.fluid_type = fluid
	emitter.emission_direction = direction
	emitter.speed_override = accumulator.expel_speed
	emitter.emit_burst(ceili(volume * 5.0))

	var source_npc: Node = get_parent()
	if source_npc == null:
		source_npc = self
	fluid_spit.emit(source_npc, emitter.global_position, fluid, volume)


## Mark passage as penetrated when ThirdPartyInsertion starts.
func _on_insertion_started(passage_name: String, _tool_tip: RigidBody3D) -> void:
	# Extract base passage name: "vaginal_passage_3_top" → "vaginal"
	var base: String = _passage_base_name(passage_name)
	accumulator.set_penetrated(base, true)


## Unmark passage penetration on withdrawal.
func _on_insertion_ended(passage_name: String) -> void:
	var base: String = _passage_base_name(passage_name)
	accumulator.set_penetrated(base, false)


## Stop leak emitter when a passage fully empties.
func _on_passage_emptied(passage: String) -> void:
	var key: String = "leak_%s" % passage
	release_emitter(key)


## Find what passage (if any) the NPC's penis is currently inserted into.
## Returns "" if penis is free.
func _find_current_insertion_target() -> String:
	return _current_insertion_target


## Set when this NPC's penis enters/exits a passage (called automatically
## by cross-NPC wiring or manually by the orchestrator).
func set_insertion_target(passage: String) -> void:
	_current_insertion_target = passage


# ── Cross-NPC Wiring ─────────────────────────────────────────────────────────

## Register another NPC's ThirdPartyInsertion system so this FluidSystem can
## auto-detect when its own penis is inserted into that NPC's passages.
## Also wires internal_ejaculation routing and participant counting.
func register_external_insertion_system(target_insertion: ThirdPartyInsertion,
		target_fluid_system: FluidSystem) -> void:
	if target_insertion in _external_insertion_systems:
		return
	_external_insertion_systems.append(target_insertion)

	# When the target NPC's ThirdPartyInsertion detects our penis entering,
	# auto-set our insertion target.
	target_insertion.insertion_started.connect(
		func(passage_name: String, tool_tip: RigidBody3D) -> void:
			if _owns_body_part(tool_tip):
				var base: String = _passage_base_name(passage_name)
				set_insertion_target(base)
				# Register receiving NPC for ejaculation routing
				_receiving_fluid_systems[base] = target_fluid_system
				# Update participant counts on both sides
				_add_interaction_partner(target_fluid_system)
	)
	target_insertion.insertion_ended.connect(
		func(passage_name: String) -> void:
			var base: String = _passage_base_name(passage_name)
			if _current_insertion_target == base:
				set_insertion_target("")
				_receiving_fluid_systems.erase(base)
				_remove_interaction_partner(target_fluid_system)
	)

	# Route internal ejaculation to the receiving NPC automatically
	if not internal_ejaculation.is_connected(_route_internal_ejaculation):
		internal_ejaculation.connect(_route_internal_ejaculation)


## Route internal ejaculation to whichever NPC's passage is the current target.
func _route_internal_ejaculation(passage: String, fluid: FluidType,
		volume: float) -> void:
	if _receiving_fluid_systems.has(passage):
		var target_fs: FluidSystem = _receiving_fluid_systems[passage] as FluidSystem
		if target_fs != null:
			target_fs.deposit_into_passage(passage, fluid, volume)


## Check if a RigidBody3D belongs to this NPC's penis.
func _owns_body_part(body: RigidBody3D) -> bool:
	if _ragdoll == null:
		return false
	for part_name: String in ["penis_base", "penis_mid", "penis_tip"]:
		if _ragdoll.parts.has(part_name) and _ragdoll.parts[part_name] == body:
			return true
	return false


## Add an interaction partner and update arousal system participant count.
func _add_interaction_partner(partner: Node) -> void:
	if partner in _interaction_partners:
		return
	_interaction_partners.append(partner)
	if _arousal_system != null:
		_arousal_system.set_participant_count(_interaction_partners.size() + 1)


## Remove an interaction partner and update arousal system participant count.
func _remove_interaction_partner(partner: Node) -> void:
	var idx: int = _interaction_partners.find(partner)
	if idx >= 0:
		_interaction_partners.remove_at(idx)
	if _arousal_system != null:
		_arousal_system.set_participant_count(_interaction_partners.size() + 1)


## Extract base passage name from a full part name.
func _passage_base_name(part_name: String) -> String:
	if part_name.begins_with("oral"):
		return "oral"
	elif part_name.begins_with("vaginal"):
		return "vaginal"
	elif part_name.begins_with("anal"):
		return "anal"
	return part_name.split("_")[0]


# ── Emitter Pool ─────────────────────────────────────────────────────────────

func _acquire_emitter(key: String) -> BodyFluidEmitter:
	if _active_emitters.has(key):
		return _active_emitters[key] as BodyFluidEmitter

	var emitter: BodyFluidEmitter
	if not _emitter_pool.is_empty():
		emitter = _emitter_pool.pop_back()
	else:
		emitter = BodyFluidEmitter.new()
		emitter.name = "FluidEmitter_%s" % key
		add_child(emitter)

	_active_emitters[key] = emitter
	return emitter


func release_emitter(key: String) -> void:
	if not _active_emitters.has(key):
		return
	var emitter: BodyFluidEmitter = _active_emitters[key] as BodyFluidEmitter
	emitter.stop_emitting()
	_active_emitters.erase(key)
	_emitter_pool.append(emitter)


# ── String Pool ──────────────────────────────────────────────────────────────

func _acquire_string() -> FluidString:
	if not _string_pool.is_empty():
		return _string_pool.pop_back()

	var fs: FluidString = FluidString.new()
	fs.name = "FluidString_%d" % (_active_strings.size() + _string_pool.size())
	add_child(fs)
	return fs


func _cleanup_strings() -> void:
	var to_remove: Array[int] = []
	for i: int in range(_active_strings.size()):
		if not _active_strings[i].is_active():
			to_remove.append(i)
	to_remove.reverse()
	for idx: int in to_remove:
		var fs: FluidString = _active_strings[idx]
		_active_strings.remove_at(idx)
		_string_pool.append(fs)


## Diagnostic: current status summary.
func get_status() -> Dictionary:
	return {
		"accumulator": accumulator.get_status(),
		"surface_patches": surface.get_patch_count(),
		"active_emitters": _active_emitters.size(),
		"active_strings": _active_strings.size(),
		"ejaculation_remaining": _ejaculation_remaining,
		"ejac_scaled_duration": _ejac_scaled_duration,
		"ejac_scaled_spurts": _ejac_scaled_spurts,
		"insertion_target": _current_insertion_target,
		"tear_active": _tear_active,
		"interaction_partners": _interaction_partners.size(),
		"receiving_targets": _receiving_fluid_systems.size(),
	}
