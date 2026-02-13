class_name FluidAccumulator
extends Node
## Tracks fluid volumes retained inside body passages (oral, vaginal, anal).
##
## Fluids are deposited during ejaculation / secretion and can be:
##   - Expelled on command (spit, push out)
##   - Leaked passively during continued penetration or gravity
##   - Mixed when multiple fluid types coexist
##
## Purely data-driven — rendering is handled by emitters spawned through
## FluidSystem when deposit/expel/leak events fire.

signal fluid_deposited(passage: String, fluid_name: String, volume: float)
signal fluid_expelled(passage: String, fluid_type: FluidType, volume: float, direction: Vector3)
signal fluid_leaking(passage: String, fluid_type: FluidType, rate: float)
signal passage_emptied(passage: String)

# ── Tuning ───────────────────────────────────────────────────────────────────

@export_group("Capacity")
## Maximum fluid volume (mL) a passage can retain before auto-leaking.
@export var max_oral_volume: float = 40.0
@export var max_vaginal_volume: float = 25.0
@export var max_anal_volume: float = 20.0

@export_group("Leaking")
## During penetration, what fraction of max capacity triggers leak.
@export_range(0.0, 1.0) var penetration_leak_threshold: float = 0.3
## Leak rate (mL/s) per unit of excess above threshold during penetration.
@export var penetration_leak_rate: float = 4.0
## Passive gravity leak rate (mL/s) when passage opening faces downward.
@export var gravity_leak_rate: float = 1.5
## Minimum volume below which fluid evaporates instead of leaking.
@export var evaporation_threshold: float = 0.5

@export_group("Expulsion")
## Volume (mL) expelled in a single spit/push action.
@export var expel_burst_volume: float = 15.0
## How fast the expulsion stream fires (m/s).
@export var expel_speed: float = 1.2

# ── Runtime ──────────────────────────────────────────────────────────────────

## Per-passage stored fluids: { "oral": Array[StoredFluid], "vaginal": [...] }
var _stores: Dictionary = {}

## Passage capacity lookup.
var _capacity: Dictionary = {}

## Active penetrations (set by FluidSystem from ThirdPartyInsertion signals).
var _penetrated_passages: Dictionary = {}

## Reference to owning NPC's ragdoll for orientation queries.
var _ragdoll: HumanoidRagdollBuilder = null


## Inner data class for a stored fluid deposit.
class StoredFluid:
	var fluid_type: FluidType
	var volume: float  ## mL
	var deposited_at: float  ## Engine time

	func _init(p_fluid: FluidType, p_volume: float) -> void:
		fluid_type = p_fluid
		volume = p_volume
		deposited_at = Time.get_ticks_msec() / 1000.0


func _ready() -> void:
	_capacity = {
		"oral": max_oral_volume,
		"vaginal": max_vaginal_volume,
		"anal": max_anal_volume,
	}
	for passage: String in _capacity:
		_stores[passage] = [] as Array[StoredFluid]
	set_physics_process(false)


## Wire up after ragdoll is built.
func setup(ragdoll: HumanoidRagdollBuilder) -> void:
	_ragdoll = ragdoll
	set_physics_process(true)


## Deposit fluid into a passage (e.g., ejaculation into oral cavity).
func deposit(passage: String, fluid: FluidType, volume: float) -> void:
	if not _stores.has(passage):
		push_warning("[FluidAccumulator] Unknown passage '%s'" % passage)
		return
	var entry: StoredFluid = StoredFluid.new(fluid, volume)
	(_stores[passage] as Array[StoredFluid]).append(entry)
	fluid_deposited.emit(passage, fluid.fluid_name, volume)
	# If over capacity, begin immediate leak
	if get_total_volume(passage) > _capacity.get(passage, 999.0):
		_start_overflow_leak(passage)


## Voluntarily expel fluid (spit, push out). Returns the mixed FluidType
## and actual volume removed, or null if passage is empty.
func expel(passage: String, direction: Vector3 = Vector3.FORWARD) -> Dictionary:
	if not _stores.has(passage):
		return {}
	var contents: Array[StoredFluid] = _stores[passage] as Array[StoredFluid]
	if contents.is_empty():
		return {}

	var mixed: FluidType = _get_mixed_fluid(passage)
	var total: float = get_total_volume(passage)
	var removed: float = minf(expel_burst_volume, total)

	# Drain proportionally from all stored deposits
	_drain_volume(passage, removed)

	fluid_expelled.emit(passage, mixed, removed, direction.normalized())
	if get_total_volume(passage) < evaporation_threshold:
		_evaporate(passage)

	return { "fluid_type": mixed, "volume": removed }


## Mark passage as currently penetrated (enables penetration leaking).
func set_penetrated(passage: String, is_penetrated: bool) -> void:
	_penetrated_passages[passage] = is_penetrated


## Get total stored volume in a passage (mL).
func get_total_volume(passage: String) -> float:
	if not _stores.has(passage):
		return 0.0
	var total: float = 0.0
	var contents: Array[StoredFluid] = _stores[passage] as Array[StoredFluid]
	for entry: StoredFluid in contents:
		total += entry.volume
	return total


## Get the blended fluid from all deposits in a passage.
func get_mixed_fluid(passage: String) -> FluidType:
	return _get_mixed_fluid(passage)


## Check if a passage has any stored fluid.
func has_fluid(passage: String) -> bool:
	return get_total_volume(passage) > evaporation_threshold


func _physics_process(delta: float) -> void:
	for passage: String in _stores:
		var total: float = get_total_volume(passage)
		if total < evaporation_threshold:
			continue

		var leaked_this_frame: float = 0.0

		# Penetration leaking — fluid gets pushed out by intruding body
		if _penetrated_passages.get(passage, false):
			var cap: float = _capacity.get(passage, 999.0)
			var threshold_vol: float = cap * penetration_leak_threshold
			if total > threshold_vol:
				var excess_frac: float = (total - threshold_vol) / maxf(cap - threshold_vol, 0.01)
				var leak: float = penetration_leak_rate * excess_frac * delta
				leak = minf(leak, total - evaporation_threshold)
				if leak > 0.01:
					_drain_volume(passage, leak)
					leaked_this_frame += leak
					total -= leak

		# Gravity leaking — only if penetration didn't already drain enough
		if total > evaporation_threshold:
			var gravity_factor: float = _get_gravity_factor(passage)
			if gravity_factor > 0.1:
				var leak: float = gravity_leak_rate * gravity_factor * delta
				leak = minf(leak, total - evaporation_threshold)
				if leak > 0.01:
					_drain_volume(passage, leak)
					leaked_this_frame += leak
					total -= leak

		# Emit a single combined leak signal per passage per frame
		if leaked_this_frame > 0.01:
			var mixed: FluidType = _get_mixed_fluid(passage)
			fluid_leaking.emit(passage, mixed, leaked_this_frame / delta)

	# Clean up fully drained passages
	for passage: String in _stores:
		if get_total_volume(passage) < evaporation_threshold:
			var contents: Array[StoredFluid] = _stores[passage] as Array[StoredFluid]
			if not contents.is_empty():
				_evaporate(passage)


## Compute how much gravity assists leaking (0 = opening faces up, 1 = faces down).
func _get_gravity_factor(passage: String) -> float:
	if _ragdoll == null:
		return 0.0
	# Use the ring entrance part orientation to determine if opening faces down
	var ring_name: String = "%s_ring_top" % passage
	if not _ragdoll.parts.has(ring_name):
		return 0.0
	var ring_body: RigidBody3D = _ragdoll.parts[ring_name] as RigidBody3D
	if ring_body == null:
		return 0.0
	# The passage "forward" direction (out of the body) in world space
	var forward_world: Vector3 = ring_body.global_transform.basis * Vector3.FORWARD
	# Dot with DOWN — positive means opening faces downward
	var down_dot: float = forward_world.dot(Vector3.DOWN)
	return clampf(down_dot, 0.0, 1.0)


## Remove volume proportionally from all deposits in a passage.
func _drain_volume(passage: String, amount: float) -> void:
	var contents: Array[StoredFluid] = _stores[passage] as Array[StoredFluid]
	var total: float = get_total_volume(passage)
	if total <= 0.0:
		return
	var fraction: float = minf(amount / total, 1.0)
	var to_remove: Array[int] = []
	for i: int in range(contents.size()):
		contents[i].volume -= contents[i].volume * fraction
		if contents[i].volume < 0.01:
			to_remove.append(i)
	# Remove depleted entries (reverse order)
	to_remove.reverse()
	for idx: int in to_remove:
		contents.remove_at(idx)


## Blend all stored fluids in a passage into one FluidType.
func _get_mixed_fluid(passage: String) -> FluidType:
	var contents: Array[StoredFluid] = _stores[passage] as Array[StoredFluid]
	if contents.is_empty():
		return null
	if contents.size() == 1:
		return contents[0].fluid_type

	var result: FluidType = contents[0].fluid_type
	var result_vol: float = contents[0].volume
	for i: int in range(1, contents.size()):
		var total_vol: float = result_vol + contents[i].volume
		if total_vol <= 0.0:
			continue
		var ratio: float = contents[i].volume / total_vol
		result = FluidType.mix(result, contents[i].fluid_type, ratio)
		result_vol = total_vol
	return result


## Start immediate overflow leak when deposit exceeds capacity.
func _start_overflow_leak(passage: String) -> void:
	var cap: float = _capacity.get(passage, 999.0)
	var excess: float = get_total_volume(passage) - cap
	if excess > 0.0:
		_drain_volume(passage, excess)
		var mixed: FluidType = _get_mixed_fluid(passage)
		if mixed != null:
			# Overflow is instantaneous — emit as a high rate (mL/s)
			var overflow_rate: float = excess * 10.0
			fluid_leaking.emit(passage, mixed, overflow_rate)


## Clear out trace amounts and fire emptied signal.
func _evaporate(passage: String) -> void:
	(_stores[passage] as Array[StoredFluid]).clear()
	passage_emptied.emit(passage)


## Diagnostic: current state per passage.
func get_status() -> Dictionary:
	var result: Dictionary = {}
	for passage: String in _stores:
		var contents: Array[StoredFluid] = _stores[passage] as Array[StoredFluid]
		var fluids: Array[String] = []
		for entry: StoredFluid in contents:
			fluids.append("%s(%.1fmL)" % [entry.fluid_type.fluid_name, entry.volume])
		result[passage] = {
			"total_volume": get_total_volume(passage),
			"capacity": _capacity.get(passage, 0.0),
			"penetrated": _penetrated_passages.get(passage, false),
			"fluids": fluids,
		}
	return result
