class_name SensationScreenFX
extends CanvasLayer
## Full-screen post-process overlay that visualises player body sensations.
##
## Reads from PlayerRagdollBridge → NerveSystem / ArousalSystem / ConstrictionSystem
## to drive:
##   - Edge glow mapped to body-part touch location
##   - Arousal-coded bottom edge + genital pulse
##   - Tunnel vision escalating with pleasure
##   - Pain red pulse on all edges
##   - Oxygen desaturation (greyscale as O₂ drops)
##
## Add as child of Player (CanvasLayer). Expects sibling PlayerRagdollBridge.

# ── Tuning ───────────────────────────────────────────────────────────────────

@export_group("Edge Glow")
## How fast glow rises when a zone is stimulated.
@export_range(0.5, 10.0) var glow_rise_speed: float = 4.0
## How fast glow fades when stimulation stops.
@export_range(0.5, 10.0) var glow_fade_speed: float = 2.0
## Minimum stimulation to trigger visible glow.
@export_range(0.0, 5.0) var glow_threshold: float = 0.5
## Intensity scale (maps nerve stimulation to glow brightness).
@export_range(0.1, 5.0) var glow_intensity_scale: float = 0.04

@export_group("Tunnel Vision")
## Arousal level where tunnel vision begins.
@export_range(0.0, 1.0) var tunnel_onset: float = 0.4
## Maximum tunnel intensity at full arousal.
@export_range(0.0, 1.0) var tunnel_max: float = 0.7

@export_group("Pain")
## Pain pulse frequency (Hz).
@export_range(0.5, 4.0) var pain_pulse_frequency: float = 1.5
## Scale factor from discomfort to pain level.
@export_range(0.01, 1.0) var pain_intensity_scale: float = 0.03

@export_group("Oxygen")
## How fast desaturation responds to airway changes.
@export_range(0.5, 10.0) var desat_blend_speed: float = 3.0

# ── Body-Part → Screen Zone Mapping ─────────────────────────────────────────
# Maps body part name prefixes/names to one of 8 screen zones.
# Zones: top_left, top, top_right, left, right, bottom_left, bottom, bottom_right
# "side" key: "left", "right", "center" — determines horizontal placement.
# "height" key: 0.0 = bottom, 1.0 = top — determines vertical placement.

const ZONE_MAP: Dictionary = {
	# Head / face — top
	"head":            {"height": 1.0, "side": "center"},
	"jaw":             {"height": 0.92, "side": "center"},
	"tongue":          {"height": 0.88, "side": "center"},
	"left_eye":        {"height": 0.95, "side": "left"},
	"right_eye":       {"height": 0.95, "side": "right"},
	# Neck — upper
	"neck":            {"height": 0.85, "side": "center"},
	# Shoulders / clavicle
	"left_clavicle":   {"height": 0.80, "side": "left"},
	"right_clavicle":  {"height": 0.80, "side": "right"},
	# Chest / breasts — upper-mid
	"chest":           {"height": 0.75, "side": "center"},
	"left_breast":     {"height": 0.72, "side": "left"},
	"right_breast":    {"height": 0.72, "side": "right"},
	# Arms
	"left_upper_arm":  {"height": 0.68, "side": "left"},
	"right_upper_arm": {"height": 0.68, "side": "right"},
	"left_forearm":    {"height": 0.55, "side": "left"},
	"right_forearm":   {"height": 0.55, "side": "right"},
	"left_hand":       {"height": 0.45, "side": "left"},
	"right_hand":      {"height": 0.45, "side": "right"},
	# Spine / torso
	"spine_upper":     {"height": 0.70, "side": "center"},
	"spine_mid":       {"height": 0.60, "side": "center"},
	"spine_lower":     {"height": 0.50, "side": "center"},
	# Pelvis / glutes
	"pelvis":          {"height": 0.40, "side": "center"},
	"left_inner_glute":  {"height": 0.38, "side": "left"},
	"right_inner_glute": {"height": 0.38, "side": "right"},
	"left_outer_glute":  {"height": 0.38, "side": "left"},
	"right_outer_glute": {"height": 0.38, "side": "right"},
	# Genitals — bottom edge (special arousal-coded zone)
	"penis":           {"height": 0.0, "side": "center"},
	"scrotum":         {"height": 0.0, "side": "center"},
	"clitoris":        {"height": 0.0, "side": "center"},
	"labia":           {"height": 0.0, "side": "center"},
	# Legs
	"left_upper_leg":  {"height": 0.30, "side": "left"},
	"right_upper_leg": {"height": 0.30, "side": "right"},
	"left_lower_leg":  {"height": 0.18, "side": "left"},
	"right_lower_leg": {"height": 0.18, "side": "right"},
	# Feet — bottom corners
	"left_foot":       {"height": 0.05, "side": "left"},
	"right_foot":      {"height": 0.05, "side": "right"},
	"left_toe":        {"height": 0.02, "side": "left"},
	"right_toe":       {"height": 0.02, "side": "right"},
	# Fingers — map to hand side
	"left_thumb":      {"height": 0.45, "side": "left"},
	"left_index":      {"height": 0.45, "side": "left"},
	"left_middle":     {"height": 0.45, "side": "left"},
	"left_ring":       {"height": 0.45, "side": "left"},
	"left_pinky":      {"height": 0.45, "side": "left"},
	"right_thumb":     {"height": 0.45, "side": "right"},
	"right_index":     {"height": 0.45, "side": "right"},
	"right_middle":    {"height": 0.45, "side": "right"},
	"right_ring":      {"height": 0.45, "side": "right"},
	"right_pinky":     {"height": 0.45, "side": "right"},
}

# 8 zone names matching shader uniforms
const ZONE_NAMES: PackedStringArray = [
	"glow_top_left", "glow_top", "glow_top_right",
	"glow_left", "glow_right",
	"glow_bottom_left", "glow_bottom", "glow_bottom_right",
]

# ── Runtime State ────────────────────────────────────────────────────────────

# Current glow intensity per zone (smoothed)
var _zone_glow: PackedFloat32Array = PackedFloat32Array()  # 8 floats
# Target glow per zone (from nerve data this frame)
var _zone_target: PackedFloat32Array = PackedFloat32Array()  # 8 floats
# Accumulated discomfort for pain overlay
var _pain_accumulator: float = 0.0
var _pain_pulse_time: float = 0.0
# Current oxygen saturation (smoothed)
var _current_o2_sat: float = 1.0

# References
var _bridge: PlayerRagdollBridge = null
var _nerve: NerveSystem = null
var _arousal: ArousalSystem = null
var _constriction: Node = null  # ConstrictionSystem (if wired on player)
var _shader_mat: ShaderMaterial = null
var _rect: ColorRect = null


func _ready() -> void:
	layer = 100  # Render on top of everything
	_zone_glow.resize(8)
	_zone_target.resize(8)
	for i: int in range(8):
		_zone_glow[i] = 0.0
		_zone_target[i] = 0.0

	# Build the overlay ColorRect
	_rect = ColorRect.new()
	_rect.name = "FXRect"
	_rect.anchors_preset = Control.PRESET_FULL_RECT
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var shader: Shader = load("res://scripts/shaders/sensation_screen_fx.gdshader") as Shader
	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = shader
	_rect.material = _shader_mat
	add_child(_rect)

	# Find sibling systems on the player (deferred so everything is ready)
	_find_systems.call_deferred()


func _find_systems() -> void:
	var player: Node = get_parent()
	if player == null:
		return
	for child: Node in player.get_children():
		if child is PlayerRagdollBridge:
			_bridge = child as PlayerRagdollBridge
		elif child.has_method(&"_update_airway"):
			_constriction = child

	if _bridge != null:
		# Wait for ragdoll to be built so nerve/arousal systems exist
		if _bridge.nerve_system != null:
			_on_systems_available()
		else:
			_bridge.ragdoll_ready.connect(_on_ragdoll_ready)


func _on_ragdoll_ready(_ragdoll: HumanoidRagdollBuilder) -> void:
	# ArousalSystem spawns after binding, so wait a frame
	await get_tree().process_frame
	await get_tree().process_frame
	_on_systems_available()


func _on_systems_available() -> void:
	_nerve = _bridge.nerve_system
	_arousal = _bridge.arousal_system
	# Connect nerve stimulation for discomfort tracking (pain overlay)
	if _nerve != null:
		_nerve.stimulation_event.connect(_on_nerve_event)


func _on_nerve_event(_part_name: String, _touch_type: NerveSystem.TouchType,
		_intensity: float, _comfort_delta: float, discomfort_delta: float) -> void:
	_pain_accumulator += discomfort_delta * pain_intensity_scale


func _process(delta: float) -> void:
	if _shader_mat == null:
		return

	_update_edge_glow(delta)
	_update_arousal_uniforms()
	_update_tunnel_vision()
	_update_pain(delta)
	_update_oxygen(delta)


# ═════════════════════════════════════════════════════════════════════════════
#  EDGE GLOW — Maps body part stimulation to 8 screen zones
# ═════════════════════════════════════════════════════════════════════════════

func _update_edge_glow(delta: float) -> void:
	# Reset targets
	for i: int in range(8):
		_zone_target[i] = 0.0

	if _nerve == null:
		_smooth_zones(delta)
		_push_zone_uniforms()
		return

	# Read stimulation from every known part and route to zones
	for part_name: String in _nerve._stimulation:
		var stim: float = _nerve._stimulation[part_name] as float
		if stim < glow_threshold:
			continue
		var zone_idx: int = _part_to_zone_index(part_name)
		if zone_idx < 0:
			continue
		_zone_target[zone_idx] += stim * glow_intensity_scale

	# Clamp targets
	for i: int in range(8):
		_zone_target[i] = clampf(_zone_target[i], 0.0, 1.0)

	_smooth_zones(delta)
	_push_zone_uniforms()


func _smooth_zones(delta: float) -> void:
	for i: int in range(8):
		var target: float = _zone_target[i]
		if _zone_glow[i] < target:
			_zone_glow[i] = minf(_zone_glow[i] + glow_rise_speed * delta, target)
		else:
			_zone_glow[i] = maxf(_zone_glow[i] - glow_fade_speed * delta, 0.0)


func _push_zone_uniforms() -> void:
	for i: int in range(8):
		_shader_mat.set_shader_parameter(ZONE_NAMES[i], _zone_glow[i])


## Resolve a body part name to one of 8 zone indices.
## Uses prefix matching against ZONE_MAP, then maps (side, height) → zone.
func _part_to_zone_index(part_name: String) -> int:
	var mapping: Dictionary = _find_zone_mapping(part_name)
	if mapping.is_empty():
		return -1

	var height: float = mapping["height"] as float
	var side: String = mapping["side"] as String

	# Vertical: top (>=0.8), mid (0.2..0.8), bottom (<0.2)
	# Horizontal: left, center, right
	var is_top: bool = height >= 0.8
	var is_bottom: bool = height < 0.2

	if is_top:
		match side:
			"left":
				return 0  # top_left
			"right":
				return 2  # top_right
			_:
				return 1  # top
	elif is_bottom:
		match side:
			"left":
				return 5  # bottom_left
			"right":
				return 7  # bottom_right
			_:
				return 6  # bottom
	else:
		# Mid-body → side edges only (left or right)
		match side:
			"left":
				return 3  # left
			"right":
				return 4  # right
			_:
				# Centre-body mid → split between left and right equally
				return 3  # default to left (both will be set by overlapping parts)


func _find_zone_mapping(part_name: String) -> Dictionary:
	# Direct match first
	if ZONE_MAP.has(part_name):
		return ZONE_MAP[part_name] as Dictionary
	# Prefix match — check longest prefix first by iterating all keys
	var best_key: String = ""
	var best_len: int = 0
	for key: String in ZONE_MAP:
		if part_name.begins_with(key) and key.length() > best_len:
			best_key = key
			best_len = key.length()
	if best_key != "":
		return ZONE_MAP[best_key] as Dictionary
	return {}


# ═════════════════════════════════════════════════════════════════════════════
#  AROUSAL — Bottom edge colour coding + genital pulse
# ═════════════════════════════════════════════════════════════════════════════

func _update_arousal_uniforms() -> void:
	if _arousal == null:
		return

	var al: float = _arousal.arousal_level
	_shader_mat.set_shader_parameter(&"arousal_level", al)

	# Color ramp: low arousal = soft pink, high = vivid red-pink
	var color: Color = Color(0.0, 0.0, 0.0)
	if al < 0.3:
		# Cool blue-pink
		color = Color(0.5, 0.4, 0.8).lerp(Color(1.0, 0.5, 0.7), al / 0.3)
	elif al < 0.7:
		# Warm pink
		var t: float = (al - 0.3) / 0.4
		color = Color(1.0, 0.5, 0.7).lerp(Color(1.0, 0.25, 0.4), t)
	else:
		# Hot red
		var t: float = (al - 0.7) / 0.3
		color = Color(1.0, 0.25, 0.4).lerp(Color(1.0, 0.1, 0.15), t)

	_shader_mat.set_shader_parameter(&"arousal_glow_color",
		Vector3(color.r, color.g, color.b))

	# Genital pulse from throb system
	var pulse_active: float = 1.0 if _arousal.throbbing_enabled and \
		_arousal.erection_level >= _arousal.throb_erection_threshold else 0.0
	_shader_mat.set_shader_parameter(&"genital_pulse_active", pulse_active)
	_shader_mat.set_shader_parameter(&"genital_pulse", _arousal.throb_phase)


# ═════════════════════════════════════════════════════════════════════════════
#  TUNNEL VISION — Escalates with pleasure
# ═════════════════════════════════════════════════════════════════════════════

func _update_tunnel_vision() -> void:
	if _arousal == null:
		_shader_mat.set_shader_parameter(&"tunnel_intensity", 0.0)
		return

	var al: float = _arousal.arousal_level
	var tunnel: float = 0.0
	if al > tunnel_onset:
		tunnel = ((al - tunnel_onset) / (1.0 - tunnel_onset)) * tunnel_max
	_shader_mat.set_shader_parameter(&"tunnel_intensity", tunnel)


# ═════════════════════════════════════════════════════════════════════════════
#  PAIN — Red pulsing edges
# ═════════════════════════════════════════════════════════════════════════════

func _update_pain(delta: float) -> void:
	# Decay accumulated pain
	_pain_accumulator = maxf(_pain_accumulator - 0.3 * delta, 0.0)
	var pain: float = clampf(_pain_accumulator, 0.0, 1.0)

	_pain_pulse_time += delta * pain_pulse_frequency
	_shader_mat.set_shader_parameter(&"pain_level", pain)
	_shader_mat.set_shader_parameter(&"pain_pulse_phase", fmod(_pain_pulse_time, 1.0))


# ═════════════════════════════════════════════════════════════════════════════
#  OXYGEN — Screen desaturation as airway is occluded
# ═════════════════════════════════════════════════════════════════════════════

func _update_oxygen(delta: float) -> void:
	var target_sat: float = 1.0

	if _constriction != null and is_instance_valid(_constriction):
		# ConstrictionSystem provides consciousness (1 = conscious, 0 = blacked out)
		# and airway_level (0 = open, 1 = sealed)
		var consciousness: float = _constriction.get(&"consciousness") as float
		var airway: float = _constriction.get(&"airway_level") as float
		# Desaturate based on consciousness loss + partial airway occlusion
		target_sat = consciousness * (1.0 - airway * 0.4)

	_current_o2_sat = move_toward(_current_o2_sat, target_sat, desat_blend_speed * delta)
	_shader_mat.set_shader_parameter(&"oxygen_saturation", _current_o2_sat)
