class_name SFXEngine
extends Node
## Centralized audio manager with bus routing, 3D spatial pooling, and 2.1 support.
## Add as autoload or child of main scene. Surround-ready architecture —
## currently targeting stereo + subwoofer (LFE bus with low-pass filter).

signal sound_played(sound_path: String, world_pos: Vector3)

# ── Bus Names ────────────────────────────────────────────────────────────────
const BUS_SFX: StringName = &"SFX"
const BUS_MUSIC: StringName = &"Music"
const BUS_AMBIENT: StringName = &"Ambient"
const BUS_UI: StringName = &"UI"
const BUS_LFE: StringName = &"LFE"

# ── Pool Config ──────────────────────────────────────────────────────────────
const POOL_3D_SIZE: int = 24
const POOL_2D_SIZE: int = 8

# ── Sound Categories ─────────────────────────────────────────────────────────
enum Category {
	IMPACT,      ## Body hits, slaps, thuds
	FRICTION,    ## Sliding, rubbing, dragging
	FLUID,       ## Drips, splashes, squishes
	VOCAL,       ## Breathing, gasps, grunts
	AMBIENT,     ## Room tone, environment
	UI,          ## Menu clicks, notifications
	BODY,        ## Joint pops, stretching, cracking
}

# ── Volume (linear 0–1) ─────────────────────────────────────────────────────
@export_group("Volume")
@export_range(0.0, 1.0) var master_volume: float = 1.0
@export_range(0.0, 1.0) var sfx_volume: float = 0.8
@export_range(0.0, 1.0) var music_volume: float = 0.5
@export_range(0.0, 1.0) var ambient_volume: float = 0.6
@export_range(0.0, 1.0) var ui_volume: float = 0.7
@export_range(0.0, 1.0) var lfe_volume: float = 0.9

# ── Spatial Config ───────────────────────────────────────────────────────────
@export_group("Spatial Audio")
@export var max_hearing_distance: float = 25.0
@export var reference_distance: float = 1.0

# ── Runtime ──────────────────────────────────────────────────────────────────
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _pool_2d: Array[AudioStreamPlayer] = []
## Sound library: Category enum → sound_name → AudioStream
var _sound_library: Dictionary = {}
## Follow targets: AudioStreamPlayer3D instance → Node3D to track
var _follow_targets: Dictionary = {}


func _ready() -> void:
	_setup_buses()
	_build_pools()


func _process(_delta: float) -> void:
	# Update follow-target positions for play_on sounds.
	var expired: Array[AudioStreamPlayer3D] = []
	for player: AudioStreamPlayer3D in _follow_targets.keys():
		var target: Node3D = _follow_targets[player] as Node3D
		if is_instance_valid(target) and is_instance_valid(player) and player.playing:
			player.global_position = target.global_position
		else:
			expired.append(player)
	for p: AudioStreamPlayer3D in expired:
		_follow_targets.erase(p)


# ── Public API ───────────────────────────────────────────────────────────────

## Play a sound at a 3D world position. Returns the player for further control.
func play_at(stream: AudioStream, world_pos: Vector3,
		bus: StringName = BUS_SFX, volume_db: float = 0.0,
		pitch_scale: float = 1.0) -> AudioStreamPlayer3D:
	var player: AudioStreamPlayer3D = _get_free_3d()
	if player == null:
		push_warning("[SFXEngine] 3D pool exhausted — sound dropped.")
		return null
	player.stream = stream
	player.global_position = world_pos
	player.bus = bus
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.play()
	sound_played.emit(stream.resource_path, world_pos)
	return player


## Play a sound that follows a node's position.
func play_on(stream: AudioStream, target: Node3D,
		bus: StringName = BUS_SFX, volume_db: float = 0.0,
		pitch_scale: float = 1.0) -> AudioStreamPlayer3D:
	var player: AudioStreamPlayer3D = _get_free_3d()
	if player == null:
		push_warning("[SFXEngine] 3D pool exhausted — sound dropped.")
		return null
	player.stream = stream
	player.global_position = target.global_position
	player.bus = bus
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.play()
	_follow_targets[player] = target
	sound_played.emit(stream.resource_path, target.global_position)
	return player


## Play with random pitch variation (±pitch_range) for natural repetition.
func play_at_varied(stream: AudioStream, world_pos: Vector3,
		bus: StringName = BUS_SFX, volume_db: float = 0.0,
		pitch_range: float = 0.1) -> AudioStreamPlayer3D:
	var pitch: float = 1.0 + randf_range(-pitch_range, pitch_range)
	return play_at(stream, world_pos, bus, volume_db, pitch)


## Play a bass rumble through the LFE (subwoofer) bus.
func play_bass(stream: AudioStream, world_pos: Vector3,
		volume_db: float = 0.0) -> AudioStreamPlayer3D:
	return play_at(stream, world_pos, BUS_LFE, volume_db)


## Play a non-positional 2D sound (UI, music, etc.).
func play_2d(stream: AudioStream, bus: StringName = BUS_UI,
		volume_db: float = 0.0, pitch_scale: float = 1.0) -> AudioStreamPlayer:
	var player: AudioStreamPlayer = _get_free_2d()
	if player == null:
		push_warning("[SFXEngine] 2D pool exhausted — sound dropped.")
		return null
	player.stream = stream
	player.bus = bus
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.play()
	return player


## Register a sound in the library for lookup by name.
func register_sound(category: Category, sound_name: String,
		stream: AudioStream) -> void:
	if not _sound_library.has(category):
		_sound_library[category] = {}
	_sound_library[category][sound_name] = stream


## Get a registered sound by category and name.
func get_sound(category: Category, sound_name: String) -> AudioStream:
	if _sound_library.has(category):
		var cat: Dictionary = _sound_library[category] as Dictionary
		if cat.has(sound_name):
			return cat[sound_name] as AudioStream
	return null


## Set volume for a named bus (0–1 linear).
func set_bus_volume(bus_name: StringName, volume_linear: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx,
			linear_to_db(clampf(volume_linear, 0.001, 1.0)))


## Get current volume for a named bus (0–1 linear).
func get_bus_volume(bus_name: StringName) -> float:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		return db_to_linear(AudioServer.get_bus_volume_db(idx))
	return 0.0


# ── Internal ─────────────────────────────────────────────────────────────────

func _setup_buses() -> void:
	_ensure_bus(BUS_SFX, &"Master")
	_ensure_bus(BUS_MUSIC, &"Master")
	_ensure_bus(BUS_AMBIENT, &"Master")
	_ensure_bus(BUS_UI, &"Master")
	_ensure_bus(BUS_LFE, &"Master")

	# Low-pass filter on LFE for subwoofer frequency isolation
	var lfe_idx: int = AudioServer.get_bus_index(BUS_LFE)
	if lfe_idx >= 0 and AudioServer.get_bus_effect_count(lfe_idx) == 0:
		var lpf: AudioEffectLowPassFilter = AudioEffectLowPassFilter.new()
		lpf.cutoff_hz = 120.0
		lpf.resonance = 0.5
		AudioServer.add_bus_effect(lfe_idx, lpf)

	# Apply default volumes
	set_bus_volume(BUS_SFX, sfx_volume)
	set_bus_volume(BUS_MUSIC, music_volume)
	set_bus_volume(BUS_AMBIENT, ambient_volume)
	set_bus_volume(BUS_UI, ui_volume)
	set_bus_volume(BUS_LFE, lfe_volume)


func _ensure_bus(bus_name: StringName, send_to: StringName) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var idx: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, String(bus_name))
	AudioServer.set_bus_send(idx, send_to)


func _build_pools() -> void:
	for i: int in POOL_3D_SIZE:
		var p: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		p.name = "Pool3D_%02d" % i
		p.bus = BUS_SFX
		p.max_distance = max_hearing_distance
		p.unit_size = reference_distance
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_pool_3d.append(p)

	for i: int in POOL_2D_SIZE:
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.name = "Pool2D_%02d" % i
		p.bus = BUS_UI
		add_child(p)
		_pool_2d.append(p)


func _get_free_3d() -> AudioStreamPlayer3D:
	for p: AudioStreamPlayer3D in _pool_3d:
		if not p.playing:
			return p
	# All busy — steal the oldest (index 0)
	_pool_3d[0].stop()
	return _pool_3d[0]


func _get_free_2d() -> AudioStreamPlayer:
	for p: AudioStreamPlayer in _pool_2d:
		if not p.playing:
			return p
	_pool_2d[0].stop()
	return _pool_2d[0]
