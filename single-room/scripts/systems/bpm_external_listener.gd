class_name BPMExternalListener
extends Node
## Listens for BPM from external audio sources (system audio or microphone).
##
## Two modes:
##   MIC     — Uses Godot's AudioEffectCapture on a Record bus to pick up
##             audio from a microphone / audio interface / room mic.
##   SYSTEM  — Uses WASAPI loopback capture via a Python helper process so
##             you can detect BPM from YouTube, Spotify, etc. without a mic.
##
## Detected BPM is forwarded to a sibling BPMMusicPlayer via set_external_bpm().

signal external_bpm_detected(bpm: float)

enum Mode {
	DISABLED,  ## Not listening to external audio
	MIC,       ## Microphone / audio interface input via Godot AudioEffectCapture
	SYSTEM,    ## System audio loopback via Python helper
}

const LOOPBACK_HOST: String = "127.0.0.1"
const LOOPBACK_ENDPOINT: String = "/bpm"
const LOOPBACK_SCHEME: String = "http"

# ── Config ───────────────────────────────────────────────────────────────────

@export var mode: Mode = Mode.DISABLED

@export_group("Mic Mode")
## Input device index. -1 = default system input device.
@export var mic_device_index: int = -1

@export_group("BPM Analysis")
## Minimum believable BPM.
@export_range(40.0, 100.0) var min_bpm: float = 60.0
## Maximum believable BPM.
@export_range(100.0, 240.0) var max_bpm: float = 180.0
## Smoothing (higher = more stable).
@export_range(0.5, 0.99) var bpm_smoothing: float = 0.92
## Onset energy threshold relative to running average.
@export_range(1.2, 3.0) var onset_threshold: float = 1.6

@export_group("System Mode")
## Path to the Python BPM helper script.
@export var python_helper_path: String = "res://tools/audio/bpm_loopback_helper.py"
## Port for the helper's tiny HTTP endpoint.
@export_range(1024, 65535) var helper_port: int = 8799
## Poll interval in seconds.
@export_range(0.5, 5.0) var system_poll_interval: float = 1.0

# ── Runtime ──────────────────────────────────────────────────────────────────

var current_bpm: float = 0.0

# Mic mode state
var _mic_bus_idx: int = -1
var _capture_effect: AudioEffectCapture = null
var _mic_energy_history: PackedFloat32Array = PackedFloat32Array()
var _mic_energy_avg: float = 0.0
var _mic_onset_times: PackedFloat64Array = PackedFloat64Array()
var _mic_time: float = 0.0
var _mic_player: AudioStreamPlayer = null
const MIC_HISTORY_SIZE: int = 60

# System mode state
var _system_poll_timer: float = 0.0
var _helper_pid: int = -1
var _http_request: HTTPRequest = null

# Forward reference
var _music_player: Node = null  # BPMMusicPlayer (loose typed)


func _ready() -> void:
	_mic_energy_history.resize(MIC_HISTORY_SIZE)
	for i: int in range(MIC_HISTORY_SIZE):
		_mic_energy_history[i] = 0.0

	match mode:
		Mode.MIC:
			_setup_mic()
		Mode.SYSTEM:
			_setup_system()
		Mode.DISABLED:
			pass

	call_deferred(&"_find_music_player")


func _find_music_player() -> void:
	for sibling: Node in get_parent().get_children():
		if sibling.has_method(&"set_external_bpm"):
			_music_player = sibling
			break


func _process(delta: float) -> void:
	match mode:
		Mode.MIC:
			_process_mic(delta)
		Mode.SYSTEM:
			_process_system(delta)
		Mode.DISABLED:
			pass


func _exit_tree() -> void:
	_stop_mic()
	_stop_system()


# ═════════════════════════════════════════════════════════════════════════════
#  MIC MODE — Godot AudioEffectCapture on a Record bus
# ═════════════════════════════════════════════════════════════════════════════

func _setup_mic() -> void:
	# Create a "Record" bus with AudioEffectCapture
	var bus_count: int = AudioServer.bus_count
	AudioServer.add_bus(bus_count)
	AudioServer.set_bus_name(bus_count, &"MicCapture")
	AudioServer.set_bus_send(bus_count, &"Master")
	# Mute the output so mic audio doesn't play through speakers
	AudioServer.set_bus_mute(bus_count, true)
	_mic_bus_idx = bus_count

	_capture_effect = AudioEffectCapture.new()
	_capture_effect.buffer_length = 0.1
	AudioServer.add_bus_effect(_mic_bus_idx, _capture_effect)

	# Enable audio input
	ProjectSettings.set_setting("audio/driver/enable_input", true)

	# Create an AudioStreamPlayer with AudioStreamMicrophone routed to our bus
	_mic_player = AudioStreamPlayer.new()
	_mic_player.name = "MicInput"
	_mic_player.bus = &"MicCapture"
	var mic_stream: AudioStreamMicrophone = AudioStreamMicrophone.new()
	_mic_player.stream = mic_stream
	add_child(_mic_player)
	_mic_player.play()

	print("[BPMExternalListener] Mic capture started on bus 'MicCapture'")


func _stop_mic() -> void:
	if _mic_player != null and is_instance_valid(_mic_player):
		_mic_player.stop()


func _process_mic(delta: float) -> void:
	_mic_time += delta

	if _capture_effect == null:
		return

	# Read available frames and compute RMS energy of bass band
	var frames_available: int = _capture_effect.get_frames_available()
	if frames_available < 256:
		return

	# Read a chunk
	var buffer: PackedVector2Array = _capture_effect.get_buffer(mini(frames_available, 1024))
	if buffer.is_empty():
		return

	# Simple RMS energy (mono mix)
	var energy: float = 0.0
	for frame: Vector2 in buffer:
		var mono: float = (frame.x + frame.y) * 0.5
		energy += mono * mono
	energy = sqrt(energy / float(buffer.size()))

	# Shift history
	for i: int in range(MIC_HISTORY_SIZE - 1):
		_mic_energy_history[i] = _mic_energy_history[i + 1]
	_mic_energy_history[MIC_HISTORY_SIZE - 1] = energy

	# Running average
	var sum: float = 0.0
	for i: int in range(MIC_HISTORY_SIZE):
		sum += _mic_energy_history[i]
	_mic_energy_avg = sum / float(MIC_HISTORY_SIZE)

	# Onset detection
	if energy > _mic_energy_avg * onset_threshold and _mic_energy_avg > 0.00001:
		var onset_count: int = _mic_onset_times.size()
		if onset_count == 0 or (_mic_time - _mic_onset_times[onset_count - 1]) > 0.2:
			_mic_onset_times.append(_mic_time)
			while _mic_onset_times.size() > 16:
				_mic_onset_times.remove_at(0)
			_estimate_bpm()


func _estimate_bpm() -> void:
	if _mic_onset_times.size() < 4:
		return

	var intervals: Array[float] = []
	for i: int in range(1, _mic_onset_times.size()):
		var interval: float = _mic_onset_times[i] - _mic_onset_times[i - 1]
		if interval > 0.0:
			intervals.append(interval)

	if intervals.is_empty():
		return

	intervals.sort()
	@warning_ignore("integer_division")
	var median: float = intervals[intervals.size() / 2]
	if median <= 0.0:
		return

	var detected: float = 60.0 / median
	while detected < min_bpm and detected > 0.0:
		detected *= 2.0
	while detected > max_bpm:
		detected /= 2.0

	if detected >= min_bpm and detected <= max_bpm:
		current_bpm = current_bpm * bpm_smoothing + detected * (1.0 - bpm_smoothing)
		external_bpm_detected.emit(current_bpm)
		if _music_player != null and is_instance_valid(_music_player):
			_music_player.call(&"set_external_bpm", current_bpm)


# ═════════════════════════════════════════════════════════════════════════════
#  SYSTEM MODE — WASAPI loopback via Python helper
# ═════════════════════════════════════════════════════════════════════════════

func _setup_system() -> void:
	# Launch Python helper as a background process
	var script_path: String = ProjectSettings.globalize_path(python_helper_path)
	if not FileAccess.file_exists(python_helper_path):
		push_warning("[BPMExternalListener] Python helper not found: %s — " %
			"system BPM detection unavailable. Create the helper or use MIC mode.")
		return

	var args: PackedStringArray = PackedStringArray([
		script_path, "--port", str(helper_port),
	])
	_helper_pid = OS.create_process("python", args)
	if _helper_pid <= 0:
		push_error("[BPMExternalListener] Failed to launch Python BPM helper")
		return

	# Create HTTP client for polling
	_http_request = HTTPRequest.new()
	_http_request.name = "BPMPoller"
	add_child(_http_request)
	_http_request.request_completed.connect(_on_http_response)

	print("[BPMExternalListener] System audio capture started (PID %d, port %d)" %
		[_helper_pid, helper_port])


func _stop_system() -> void:
	if _helper_pid > 0:
		OS.kill(_helper_pid)
		_helper_pid = -1


func _process_system(delta: float) -> void:
	if _http_request == null or _helper_pid <= 0:
		return

	_system_poll_timer += delta
	if _system_poll_timer >= system_poll_interval:
		_system_poll_timer = 0.0
		var url: String = "%s://%s:%d%s" % [LOOPBACK_SCHEME, LOOPBACK_HOST, helper_port, LOOPBACK_ENDPOINT]
		var err: Error = _http_request.request(url)
		if err != OK:
			push_warning("[BPMExternalListener] HTTP poll failed: %s" % error_string(err))


func _on_http_response(_result: int, response_code: int,
		_headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code != 200:
		return

	var json: JSON = JSON.new()
	var parse_err: Error = json.parse(body.get_string_from_utf8())
	if parse_err != OK:
		return

	var data: Variant = json.data
	if data is Dictionary:
		var bpm: float = (data as Dictionary).get("bpm", 0.0) as float
		if bpm > 0.0:
			current_bpm = current_bpm * bpm_smoothing + bpm * (1.0 - bpm_smoothing)
			external_bpm_detected.emit(current_bpm)
			if _music_player != null and is_instance_valid(_music_player):
				_music_player.call(&"set_external_bpm", current_bpm)
