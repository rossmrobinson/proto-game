class_name NPCVoicePlayer
extends Node
## Loads and plays voice lines from `res://assets/audio/voices/<npc>/<category>/`.
## The brain tells this system WHICH category to speak from; this system picks
## a random line, avoids immediate repeats, and respects cooldowns.
##
## Requires an AudioStreamPlayer3D on the NPC (or creates one).
## Attach as child of NPCPlaceholder.

signal voice_started(category: String, file_path: String)
signal voice_finished(category: String)

@export_group("Playback")
## Minimum seconds between any two voice lines.
@export var global_cooldown: float = 2.0
## Minimum seconds before replaying the SAME category.
@export var category_cooldown: float = 8.0
## Volume offset in dB for voice lines.
@export var volume_db: float = 0.0
## Audio bus name for voice output.
@export var bus_name: StringName = &"SFX"

# ── State ────────────────────────────────────────────────────────────────────
## Loaded audio streams keyed by category → Array[AudioStream].
var _banks: Dictionary = {}  # category_name → Array[AudioStream]
## Last played index per category to avoid immediate repeats.
var _last_index: Dictionary = {}  # category_name → int
## Cooldown timers: category_name → seconds_remaining.
var _category_timers: Dictionary = {}
## Global cooldown timer.
var _global_timer: float = 0.0
## Whether any voice is currently playing.
var _playing: bool = false
## Category of the currently playing line.
var _current_category: String = ""

var _player: AudioStreamPlayer3D = null
var _npc: Node3D = null


func _ready() -> void:
	_npc = get_parent() as Node3D
	_setup_audio_player()
	# Defer loading so file system is ready.
	call_deferred(&"_load_all_banks")


func _physics_process(delta: float) -> void:
	# Tick cooldowns
	if _global_timer > 0.0:
		_global_timer -= delta

	var keys_to_remove: Array[String] = []
	for cat: String in _category_timers.keys():
		var t: float = _category_timers[cat] as float
		t -= delta
		if t <= 0.0:
			keys_to_remove.append(cat)
		else:
			_category_timers[cat] = t

	for key: String in keys_to_remove:
		_category_timers.erase(key)


# ── Public API ───────────────────────────────────────────────────────────────

## Speak a random line from the given category. Returns true if a line started.
func speak(category: String, interrupt: bool = false) -> bool:
	# Respect cooldowns unless interrupting
	if not interrupt:
		if _global_timer > 0.0:
			return false
		if _category_timers.has(category):
			return false
		if _playing:
			return false

	# Stop current line if interrupting
	if interrupt and _playing:
		stop()

	if not _banks.has(category):
		return false

	var bank: Array = _banks[category] as Array
	if bank.is_empty():
		return false

	# Pick random index, avoiding immediate repeat
	var idx: int = _pick_index(category, bank.size())
	var stream: AudioStream = bank[idx] as AudioStream
	if stream == null:
		return false

	_player.stream = stream
	_player.volume_db = volume_db
	_player.bus = bus_name
	_player.play()

	_playing = true
	_current_category = category
	_global_timer = global_cooldown
	_category_timers[category] = category_cooldown
	_last_index[category] = idx

	voice_started.emit(category, stream.resource_path)
	return true


## Immediately stop any playing voice line.
func stop() -> void:
	if _player != null and _player.playing:
		_player.stop()
	_playing = false
	var cat: String = _current_category
	_current_category = ""
	if cat != "":
		voice_finished.emit(cat)


## Check whether a category can be spoken right now (cooldowns + has lines).
func can_speak(category: String) -> bool:
	if _global_timer > 0.0:
		return false
	if _category_timers.has(category):
		return false
	if _playing:
		return false
	if not _banks.has(category):
		return false
	return not (_banks[category] as Array).is_empty()


## Whether any voice is currently playing.
func is_playing() -> bool:
	return _playing


## Get the list of loaded category names.
func get_categories() -> Array[String]:
	var result: Array[String] = []
	for key: String in _banks.keys():
		result.append(key)
	return result


## How many lines are loaded in a category.
func get_line_count(category: String) -> int:
	if not _banks.has(category):
		return 0
	return (_banks[category] as Array).size()


# ── Internal ─────────────────────────────────────────────────────────────────

func _setup_audio_player() -> void:
	_player = AudioStreamPlayer3D.new()
	_player.name = "VoiceAudioPlayer"
	_player.bus = bus_name
	_player.max_distance = 15.0
	_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_player.unit_size = 3.0
	_player.finished.connect(_on_playback_finished)
	add_child(_player)


func _on_playback_finished() -> void:
	_playing = false
	var cat: String = _current_category
	_current_category = ""
	if cat != "":
		voice_finished.emit(cat)


func _load_all_banks() -> void:
	# Determine NPC name for folder lookup
	var npc_name: String = ""
	if _npc != null and _npc.has_method(&"get") and "npc_name" in _npc:
		npc_name = (_npc.get(&"npc_name") as String).to_lower()
	elif _npc != null:
		npc_name = _npc.name.to_lower()

	if npc_name == "":
		push_warning("[NPCVoicePlayer] Could not determine NPC name for voice loading.")
		return

	var base_path: String = "res://assets/audio/voices/%s" % npc_name
	if not DirAccess.dir_exists_absolute(base_path):
		# No voice files generated yet — this is fine
		return

	var dir: DirAccess = DirAccess.open(base_path)
	if dir == null:
		return

	dir.list_dir_begin()
	var folder_name: String = dir.get_next()
	while folder_name != "":
		if dir.current_is_dir() and not folder_name.begins_with("."):
			_load_bank(folder_name, "%s/%s" % [base_path, folder_name])
		folder_name = dir.get_next()
	dir.list_dir_end()

	var total: int = 0
	for cat: String in _banks.keys():
		total += (_banks[cat] as Array).size()
	if total > 0:
		print("[NPCVoicePlayer] %s: loaded %d lines across %d categories" % [
			npc_name, total, _banks.size()])


func _load_bank(category: String, folder_path: String) -> void:
	var streams: Array[AudioStream] = []
	var bank_dir: DirAccess = DirAccess.open(folder_path)
	if bank_dir == null:
		return

	bank_dir.list_dir_begin()
	var file_name: String = bank_dir.get_next()
	while file_name != "":
		if not bank_dir.current_is_dir():
			# Accept .wav, .ogg, .mp3 and their .import versions
			var lower: String = file_name.to_lower()
			if lower.ends_with(".wav") or lower.ends_with(".ogg") or lower.ends_with(".mp3"):
				var full_path: String = "%s/%s" % [folder_path, file_name]
				var stream: AudioStream = load(full_path) as AudioStream
				if stream != null:
					streams.append(stream)
		file_name = bank_dir.get_next()
	bank_dir.list_dir_end()

	if not streams.is_empty():
		_banks[category] = streams


func _pick_index(category: String, count: int) -> int:
	if count <= 1:
		return 0
	var last: int = _last_index.get(category, -1) as int
	var idx: int = randi() % count
	# One retry to avoid immediate repeat
	if idx == last:
		idx = (idx + 1) % count
	return idx
