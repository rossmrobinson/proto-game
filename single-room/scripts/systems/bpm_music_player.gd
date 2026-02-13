class_name BPMMusicPlayer
extends Node
## Ambient scene music player with real-time BPM tracking.
##
## Plays MP3/OGG files from res://assets/audio/music/ through the Music bus.
## Detects BPM via onset-energy analysis (AudioEffectSpectrumAnalyzer).
## Alternatively accepts external BPM from BPMExternalListener.
##
## Other systems read current_bpm to sync animations.

signal bpm_changed(new_bpm: float)
signal beat_pulse()
signal track_changed(track_name: String)

# ── Config ───────────────────────────────────────────────────────────────────

@export_group("Playback")
## Volume in dB for the music player.
@export_range(-40.0, 6.0) var volume_db: float = -6.0
## Whether to loop the current track.
@export var loop: bool = true
## Auto-play on ready.
@export var autoplay: bool = false
## Path to folder containing music files.
@export var music_folder: String = "res://assets/audio/music"

@export_group("BPM Detection")
## Whether to detect BPM from audio spectrum (disable when using external BPM).
@export var detect_bpm: bool = true
## Minimum believable BPM (filters out sub-harmonic detections).
@export_range(40.0, 100.0) var min_bpm: float = 60.0
## Maximum believable BPM (filters out double-time detections).
@export_range(100.0, 240.0) var max_bpm: float = 180.0
## Smoothing factor for BPM estimate (higher = more stable, slower response).
@export_range(0.5, 0.99) var bpm_smoothing: float = 0.92
## Energy threshold for onset detection (relative to running average).
@export_range(1.2, 3.0) var onset_threshold: float = 1.6

@export_group("Manual Override")
## Set > 0 to force a specific BPM (overrides detection).
@export_range(0.0, 240.0) var manual_bpm: float = 0.0

# ── Runtime State ────────────────────────────────────────────────────────────

## Current estimated BPM (smoothed).
var current_bpm: float = 0.0
## Seconds since last detected beat onset.
var time_since_beat: float = 0.0
## Beat interval based on current BPM (seconds per beat).
var beat_interval: float = 0.0

var _player: AudioStreamPlayer = null
var _spectrum_analyzer: AudioEffectSpectrumAnalyzerInstance = null
var _spectrum_effect: AudioEffectSpectrumAnalyzer = null
var _music_bus_idx: int = -1

# Onset detection state
var _energy_history: PackedFloat32Array = PackedFloat32Array()
var _energy_avg: float = 0.0
var _onset_times: PackedFloat64Array = PackedFloat64Array()
var _time_accumulator: float = 0.0
var _raw_bpm: float = 0.0
const ENERGY_HISTORY_SIZE: int = 60  # ~1 second at 60fps


func _ready() -> void:
	_setup_music_bus()
	_setup_player()

	_energy_history.resize(ENERGY_HISTORY_SIZE)
	for i: int in range(ENERGY_HISTORY_SIZE):
		_energy_history[i] = 0.0

	if manual_bpm > 0.0:
		_set_bpm(manual_bpm)


func _process(delta: float) -> void:
	_time_accumulator += delta
	time_since_beat += delta

	if manual_bpm > 0.0:
		_set_bpm(manual_bpm)
		_check_beat_pulse()
		return

	if detect_bpm and _spectrum_analyzer != null and _player.playing:
		_process_spectrum()

	_check_beat_pulse()


# ═════════════════════════════════════════════════════════════════════════════
#  PLAYBACK
# ═════════════════════════════════════════════════════════════════════════════

## Load and play a music file. Accepts res:// path or filename in music_folder.
func play_track(path: String) -> void:
	var full_path: String = path
	if not path.begins_with("res://") and not path.begins_with("user://"):
		full_path = music_folder.path_join(path)

	if not ResourceLoader.exists(full_path):
		push_error("[BPMMusicPlayer] Track not found: %s" % full_path)
		return

	var stream: AudioStream = load(full_path) as AudioStream
	if stream == null:
		push_error("[BPMMusicPlayer] Failed to load stream: %s" % full_path)
		return

	_player.stream = stream
	_player.play()
	_onset_times.clear()
	_raw_bpm = 0.0
	track_changed.emit(full_path.get_file().get_basename())
	print("[BPMMusicPlayer] Playing: %s" % full_path)


func stop() -> void:
	_player.stop()


func set_volume(linear: float) -> void:
	_player.volume_db = linear_to_db(clampf(linear, 0.001, 1.0))


## Force BPM from an external source (e.g. BPMExternalListener).
func set_external_bpm(bpm: float) -> void:
	if bpm > 0.0:
		_set_bpm(bpm)


# ═════════════════════════════════════════════════════════════════════════════
#  BPM DETECTION (onset energy in bass band)
# ═════════════════════════════════════════════════════════════════════════════

func _process_spectrum() -> void:
	# Read bass band energy (20Hz – 200Hz)
	var magnitude: Vector2 = _spectrum_analyzer.get_magnitude_for_frequency_range(
		20.0, 200.0)
	var energy: float = (magnitude.x + magnitude.y) * 0.5

	# Shift history and insert new sample
	for i: int in range(ENERGY_HISTORY_SIZE - 1):
		_energy_history[i] = _energy_history[i + 1]
	_energy_history[ENERGY_HISTORY_SIZE - 1] = energy

	# Running average
	var sum: float = 0.0
	for i: int in range(ENERGY_HISTORY_SIZE):
		sum += _energy_history[i]
	_energy_avg = sum / float(ENERGY_HISTORY_SIZE)

	# Onset detection: spike above threshold × average
	if energy > _energy_avg * onset_threshold and _energy_avg > 0.0001:
		# Debounce: minimum 0.2s between onsets (300 BPM cap)
		var onset_count: int = _onset_times.size()
		if onset_count == 0 or (_time_accumulator - _onset_times[onset_count - 1]) > 0.2:
			_onset_times.append(_time_accumulator)
			time_since_beat = 0.0

			# Keep last 16 onsets for interval analysis
			while _onset_times.size() > 16:
				_onset_times.remove_at(0)

			_estimate_bpm_from_onsets()


func _estimate_bpm_from_onsets() -> void:
	if _onset_times.size() < 4:
		return

	# Compute intervals between consecutive onsets
	var intervals: PackedFloat64Array = PackedFloat64Array()
	for i: int in range(1, _onset_times.size()):
		var interval: float = _onset_times[i] - _onset_times[i - 1]
		if interval > 0.0:
			intervals.append(interval)

	if intervals.is_empty():
		return

	# Median interval (robust to outliers)
	var sorted: Array[float] = []
	for val: float in intervals:
		sorted.append(val)
	sorted.sort()
	@warning_ignore("integer_division")
	var median_interval: float = sorted[sorted.size() / 2]

	if median_interval <= 0.0:
		return

	var detected: float = 60.0 / median_interval

	# Fold into believable range (handle half/double time)
	while detected < min_bpm and detected > 0.0:
		detected *= 2.0
	while detected > max_bpm:
		detected /= 2.0

	if detected >= min_bpm and detected <= max_bpm:
		_raw_bpm = detected
		var smoothed: float = current_bpm * bpm_smoothing + _raw_bpm * (1.0 - bpm_smoothing)
		_set_bpm(smoothed)


func _set_bpm(bpm: float) -> void:
	var old_bpm: float = current_bpm
	current_bpm = bpm
	beat_interval = 60.0 / maxf(bpm, 1.0)
	if absf(current_bpm - old_bpm) > 0.5:
		bpm_changed.emit(current_bpm)


func _check_beat_pulse() -> void:
	if current_bpm <= 0.0 or beat_interval <= 0.0:
		return
	if time_since_beat >= beat_interval:
		time_since_beat = fmod(time_since_beat, beat_interval)
		beat_pulse.emit()


# ═════════════════════════════════════════════════════════════════════════════
#  SETUP
# ═════════════════════════════════════════════════════════════════════════════

func _setup_music_bus() -> void:
	_music_bus_idx = AudioServer.get_bus_index(&"Music")
	if _music_bus_idx < 0:
		# Create Music bus if it doesn't exist
		var bus_count: int = AudioServer.bus_count
		AudioServer.add_bus(bus_count)
		AudioServer.set_bus_name(bus_count, &"Music")
		AudioServer.set_bus_send(bus_count, &"Master")
		_music_bus_idx = bus_count

	# Add spectrum analyzer effect if not present
	_spectrum_effect = AudioEffectSpectrumAnalyzer.new()
	_spectrum_effect.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_1024
	_spectrum_effect.buffer_length = 0.1
	AudioServer.add_bus_effect(_music_bus_idx, _spectrum_effect)

	# Get the instance for reading spectrum data
	var effect_idx: int = AudioServer.get_bus_effect_count(_music_bus_idx) - 1
	_spectrum_analyzer = AudioServer.get_bus_effect_instance(
		_music_bus_idx, effect_idx) as AudioEffectSpectrumAnalyzerInstance


func _setup_player() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "MusicStream"
	_player.bus = &"Music"
	_player.volume_db = volume_db
	add_child(_player)

	if autoplay:
		# Try to find first file in music folder
		var dir: DirAccess = DirAccess.open(music_folder)
		if dir != null:
			dir.list_dir_begin()
			var file_name: String = dir.get_next()
			while file_name != "":
				if file_name.ends_with(".mp3") or file_name.ends_with(".ogg"):
					play_track(file_name)
					break
				file_name = dir.get_next()
