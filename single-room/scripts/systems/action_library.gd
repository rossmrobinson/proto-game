class_name ActionLibrary
extends Node
## Static registry for all built-in ActionMotions, Tempos, and Patterns.
##
## This is the content backbone — all available motions, tempos, and patterns
## are defined here for lookup by name or tag. Used by ActionDriver and UI.

# ── Static Registries ────────────────────────────────────────────────────────

static var _motions: Dictionary = {}
static var _tempos: Dictionary = {}
static var _patterns: Dictionary = {}

# ── Built-in Content ─────────────────────────────────────────────────────────

static func _init() -> void:
	if _motions.size() > 0:
		return  # Already initialized
	# Motions
	_motions["linear_thrust"] = ActionMotion.create("linear_thrust", "thrust", "active", {
		"pelvis_to_spine_lower": {"axis": Vector3(1,0,0), "amplitude_deg": 18.0, "phase_offset": 0.0, "curve": ActionMotion.CurveType.SINE},
	})
	_motions["circular_grind"] = ActionMotion.create("circular_grind", "grind", "active", {
		"pelvis_to_spine_lower": {"axis": Vector3(1,0,0), "amplitude_deg": 8.0, "phase_offset": 0.0, "curve": ActionMotion.CurveType.SINE},
		"pelvis_to_spine_lower_yaw": {"axis": Vector3(0,1,0), "amplitude_deg": 6.0, "phase_offset": 0.25, "curve": ActionMotion.CurveType.SINE},
	})
	# ... (add more built-in motions as needed)
	# Tempos
	_tempos["tender"] = ActionTempo.create("tender", 0.7, 0.4, 0.8, 0.3)
	_tempos["aggressive"] = ActionTempo.create("aggressive", 2.0, 0.7, 1.0, 0.8)
	# ... (add more built-in tempos as needed)
	# Patterns
	_patterns["missionary_gentle"] = ActionPattern.create("missionary_gentle", _motions["linear_thrust"], _tempos["tender"], "missionary_base")
	_patterns["cowgirl_grind"] = ActionPattern.create("cowgirl_grind", _motions["circular_grind"], _tempos["tender"], "cowgirl_base")
	# ... (add more built-in patterns as needed)

# ── API ─────────────────────────────────────────────────────────────────────-

static func get_motion(name: String) -> ActionMotion:
	_init()
	return _motions.get(name, null)

static func get_tempo(name: String) -> ActionTempo:
	_init()
	return _tempos.get(name, null)

static func get_pattern(name: String) -> ActionPattern:
	_init()
	return _patterns.get(name, null)

static func find_patterns(interaction_type: String, tags: Array = []) -> Array:
	_init()
	var results: Array = []
	for p in _patterns.values():
		if interaction_type in p.interaction_types or interaction_type == "":
			if tags.size() == 0 or tags.all(func(t): return t in p.tags):
				results.append(p)
	return results
