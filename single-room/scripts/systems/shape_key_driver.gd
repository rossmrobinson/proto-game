class_name ShapeKeyDriver
extends Node
## Drives blend shapes (shape keys) on an NPC's skinned mesh based on
## arousal, erection, throbbing, and passage dilation.
##
## Finds MeshInstance3D nodes under the NPC, caches indices for known
## shape key names (from genital-names.md), and writes values each frame.
##
## Shape keys are authored in Blender and imported via .glb/.blend.
## This system is a no-op when no shape keys are present on the mesh.

# ── Shape Key Names (locked in genital-names.md) ────────────────────────────

const SK_PENIS_ERECT_LEN: StringName = &"penis_erect_len"
const SK_PENIS_ERECT_GIRTH: StringName = &"penis_erect_girth"
const SK_PENIS_ERECT_POSE: StringName = &"penis_erect_pose"
const SK_PENIS_PULSE: StringName = &"penis_pulse"
const SK_PENIS_VEINS: StringName = &"penis_veins"
const SK_SCROTUM_TENSION: StringName = &"scrotum_tension"
const SK_SCROTUM_RELAX: StringName = &"scrotum_relax"
const SK_TUNNEL_MIN: StringName = &"tunnel_min"
const SK_TUNNEL_MAX: StringName = &"tunnel_max"
const SK_TUNNEL_PULSE: StringName = &"tunnel_pulse"
const SK_LEFT_NIPPLE_ERECT: StringName = &"left_nipple_erect"
const SK_RIGHT_NIPPLE_ERECT: StringName = &"right_nipple_erect"

## All target shape key names for the cache scan.
const TARGET_KEYS: Array[StringName] = [
	SK_PENIS_ERECT_LEN, SK_PENIS_ERECT_GIRTH, SK_PENIS_ERECT_POSE,
	SK_PENIS_PULSE, SK_PENIS_VEINS,
	SK_SCROTUM_TENSION, SK_SCROTUM_RELAX,
	SK_TUNNEL_MIN, SK_TUNNEL_MAX, SK_TUNNEL_PULSE,
	SK_LEFT_NIPPLE_ERECT, SK_RIGHT_NIPPLE_ERECT,
]

@export_group("Erection Shape Key Curves")
## Girth scale relative to erection (1.0 = same as erect_len, 0.9 = slightly less).
@export_range(0.0, 1.5) var girth_scale: float = 0.9
## Pose (curvature) scale relative to erection.
@export_range(0.0, 1.0) var pose_scale: float = 0.7
## Erection level at which veins start to appear (0–1).
@export_range(0.0, 1.0) var vein_onset: float = 0.25

# ── References ───────────────────────────────────────────────────────────────

var _arousal_system: ArousalSystem = null
var _passage_response: Node = null  # PassageResponse — typed as Node to avoid hard dep
## Cached: StringName → { "mesh": MeshInstance3D, "idx": int }
var _shape_cache: Dictionary = {}
## Whether any shape keys were found (skip processing if not).
var _has_shapes: bool = false


## Wire up after ragdoll is built and systems are created.
func setup(npc: Node, arousal: ArousalSystem, passage: Node) -> void:
	_arousal_system = arousal
	_passage_response = passage
	_find_and_cache_shapes(npc)


## Scan all MeshInstance3D descendants for target shape keys.
func _find_and_cache_shapes(root: Node) -> void:
	_shape_cache.clear()
	_has_shapes = false
	var meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(root, meshes)

	for mi: MeshInstance3D in meshes:
		var mesh_res: Mesh = mi.mesh
		if mesh_res == null:
			continue
		var count: int = mi.get_blend_shape_count()
		for idx: int in range(count):
			var sk_name: StringName = mesh_res.get_blend_shape_name(idx)
			if sk_name in TARGET_KEYS and not _shape_cache.has(sk_name):
				_shape_cache[sk_name] = {"mesh": mi, "idx": idx}

	_has_shapes = not _shape_cache.is_empty()
	if _has_shapes:
		print("[ShapeKeyDriver] Cached %d shape keys" % _shape_cache.size())


func _collect_mesh_instances(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.mesh != null:
			out.append(mi)
	for child: Node in node.get_children():
		_collect_mesh_instances(child, out)


func _process(_delta: float) -> void:
	if not _has_shapes or _arousal_system == null:
		return

	var erection: float = _arousal_system.erection_level
	var throb: float = _arousal_system.throb_value
	var scrotum_t: float = _arousal_system.scrotum_tension

	# ── Penis shape keys ────────────────────────────────────────────────
	_set_shape(SK_PENIS_ERECT_LEN, erection)
	_set_shape(SK_PENIS_ERECT_GIRTH, erection * girth_scale)
	_set_shape(SK_PENIS_ERECT_POSE, erection * pose_scale)
	# Veins appear only past vein_onset, then ramp to 1.0
	var vein_range: float = 1.0 - vein_onset
	var veins: float = clampf((erection - vein_onset) / maxf(vein_range, 0.01), 0.0, 1.0)
	_set_shape(SK_PENIS_VEINS, veins)
	# Pulse from throbbing (clamped to 0–1, throb_value can be slightly negative)
	_set_shape(SK_PENIS_PULSE, clampf(throb, 0.0, 1.0))

	# ── Scrotum ─────────────────────────────────────────────────────────
	_set_shape(SK_SCROTUM_TENSION, scrotum_t)
	_set_shape(SK_SCROTUM_RELAX, 1.0 - scrotum_t)
	# ── Nipples ─────────────────────────────────────────────────────────────────
	var nipple_t: float = _arousal_system.nipple_erection
	_set_shape(SK_LEFT_NIPPLE_ERECT, nipple_t)
	_set_shape(SK_RIGHT_NIPPLE_ERECT, nipple_t)
	# ── Tunnel shape keys (from PassageResponse) ────────────────────────
	if _passage_response != null:
		var dilation: float = _passage_response.get("dilation_level") as float
		var tunnel_pulse_val: float = _passage_response.get("tunnel_pulse_value") as float
		# tunnel_min: contracted when NOT dilated (inverse)
		_set_shape(SK_TUNNEL_MIN, 1.0 - dilation)
		# tunnel_max: expanded when dilated
		_set_shape(SK_TUNNEL_MAX, dilation)
		_set_shape(SK_TUNNEL_PULSE, clampf(tunnel_pulse_val, 0.0, 1.0))


## Write a value to a cached shape key. No-op if key isn't present on mesh.
func _set_shape(sk_name: StringName, value: float) -> void:
	if not _shape_cache.has(sk_name):
		return
	var entry: Dictionary = _shape_cache[sk_name] as Dictionary
	var mi: MeshInstance3D = entry["mesh"] as MeshInstance3D
	var idx: int = entry["idx"] as int
	mi.set_blend_shape_value(idx, value)
