class_name LLMNPCController
extends Node
## LLM-driven decision layer for NPCs. Uses a local API endpoint.

signal llm_reply(reply_text: String, voice_id: String, action_id: String)

@export_group("LLM")
@export var llm_config: LLMConfig = null
@export var persona_id: String = "default"
@export var model_name: String = ""
@export var enable_autonomous: bool = true
@export var allow_actions: bool = true
@export var allow_voice: bool = true
@export var pause_when_commanded: bool = true
@export var debug_logging: bool = false

const DEFAULT_CONFIG_PATH: String = "res://config/llm-config.tres"
const NETWORK_CONFIG: GDScript = preload("res://config/network-config.gd")

var _npc: NPCPlaceholder = null
var _profile: CharacterProfile = null
var _memory: NPCMemory = null
var _voice: NPCVoicePlayer = null
var _behavior: NPCBehavior = null
var _attention: NPCAttention = null
var _command_system: NPCCommandSystem = null
var _http: HTTPRequest = null

var _pending_request: bool = false
var _pending_kind: String = ""
var _pending_chat_message: String = ""
var _decision_timer: float = 0.0
var _missing_config_warned: bool = false

var _chat_queue: Array[String] = []
var _chat_history: Array[String] = []
var _memory_summary: String = ""
var _memory_notes: Array[String] = []

var _spike_active: bool = false
var _spike_end_time: float = 0.0
var _spike_cooldown_until: float = 0.0


func _ready() -> void:
	add_to_group(&"llm_npc")
	_npc = get_parent() as NPCPlaceholder
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	_load_default_config()
	if llm_config != null:
		_http.timeout = llm_config.request_timeout_sec
	call_deferred(&"_wire_subsystems")


func _physics_process(delta: float) -> void:
	if llm_config == null:
		return
	_update_spike_state()
	if not _chat_queue.is_empty() and not _pending_request:
		var msg: String = _chat_queue.pop_front()
		_send_request("chat", msg)
		return
	if not _should_run_autonomous():
		return
	_decision_timer += delta
	if _decision_timer >= llm_config.decision_interval:
		_decision_timer = 0.0
		_send_request("tick", "")


# ── Public API ───────────────────────────────────────────────────────────────

func request_chat(message: String) -> void:
	var trimmed: String = message.strip_edges()
	if trimmed == "":
		return
	_chat_queue.append(trimmed)


func set_memory_summary(summary: String) -> void:
	_memory_summary = summary


func add_memory_note(note: String) -> void:
	var trimmed: String = note.strip_edges()
	if trimmed == "":
		return
	_memory_notes.append(trimmed)
	if llm_config != null and _memory_notes.size() > llm_config.memory_note_limit:
		_memory_notes = _memory_notes.slice(_memory_notes.size() - llm_config.memory_note_limit)


# ── Internal ─────────────────────────────────────────────────────────────────

func _load_default_config() -> void:
	if llm_config != null:
		return
	if ResourceLoader.exists(DEFAULT_CONFIG_PATH):
		llm_config = load(DEFAULT_CONFIG_PATH) as LLMConfig
	if llm_config == null:
		llm_config = LLMConfig.new()


func _wire_subsystems() -> void:
	if _npc == null:
		push_error("[LLMNPCController] No NPCPlaceholder parent found")
		return
	for child: Node in _npc.get_children():
		if child is CharacterProfile:
			_profile = child as CharacterProfile
		elif child is NPCMemory:
			_memory = child as NPCMemory
		elif child is NPCVoicePlayer:
			_voice = child as NPCVoicePlayer
		elif child is NPCBehavior:
			_behavior = child as NPCBehavior
		elif child is NPCAttention:
			_attention = child as NPCAttention
	_command_system = _find_command_system()


func _should_run_autonomous() -> bool:
	if not enable_autonomous:
		return false
	if pause_when_commanded and _is_commanded():
		return false
	return true


func _is_commanded() -> bool:
	if _command_system == null:
		return false
	return _command_system.commanded_npc == _npc


func _find_command_system() -> NPCCommandSystem:
	_find_command_recursive(get_tree().current_scene)
	return _command_system


func _find_command_recursive(node: Node) -> void:
	if node == null or _command_system != null:
		return
	if node is NPCCommandSystem:
		_command_system = node as NPCCommandSystem
		return
	for child: Node in node.get_children():
		_find_command_recursive(child)
		if _command_system != null:
			return


func _send_request(kind: String, chat_message: String) -> void:
	if _pending_request:
		return
	var url: String = NETWORK_CONFIG.get_llm_api_url()
	if url == "":
		if not _missing_config_warned:
			_missing_config_warned = true
			push_warning("[LLMNPCController] LLM_API_URL is not set")
		return

	if kind == "chat":
		_append_chat_history("user", chat_message)

	var payload: Dictionary = _build_request_payload(kind, chat_message)
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var api_key: String = NETWORK_CONFIG.get_llm_api_key()
	if api_key != "":
		headers.append("Authorization: Bearer %s" % api_key)

	var body: String = JSON.stringify(payload)
	var err: Error = _http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		push_warning("[LLMNPCController] Request failed: %s" % str(err))
		return
	_pending_request = true
	_pending_kind = kind
	_pending_chat_message = chat_message


func _build_request_payload(kind: String, chat_message: String) -> Dictionary:
	var actions: Array[String] = _build_action_catalog()
	var voices: Array[String] = _build_voice_catalog()
	var system_prompt: String = _build_system_prompt(actions, voices)
	var state: Dictionary = _build_state_snapshot(kind, chat_message, actions, voices)
	var user_prompt: String = "State:\n" + JSON.stringify(state)
	var messages: Array = [
		{"role": "system", "content": system_prompt},
		{"role": "user", "content": user_prompt},
	]
	var model: String = model_name
	if model == "":
		model = NETWORK_CONFIG.get_llm_model_name()

	return {
		"model": model,
		"temperature": _compute_temperature(),
		"max_tokens": llm_config.max_tokens,
		"messages": messages,
	}


func _build_system_prompt(actions: Array[String], voices: Array[String]) -> String:
	var persona: String = _get_persona_prompt()
	var action_text: String = ", ".join(actions)
	var voice_text: String = ", ".join(voices)
	if voice_text == "":
		voice_text = "(empty only)"
	return "You are an NPC decision module. " + persona + "\n" + \
		"Return JSON only with keys: action_id, target_id, voice_id, mood, reply_text.\n" + \
		"Use empty string for any unused field.\n" + \
		"action_id must be one of: " + action_text + "\n" + \
		"voice_id must be one of: " + voice_text + "\n" + \
		"reply_text max " + str(llm_config.reply_max_chars) + " chars."


func _build_state_snapshot(kind: String, chat_message: String,
		actions: Array[String], voices: Array[String]) -> Dictionary:
	var comfort: float = _profile.comfort_level if _profile != null else 0.0
	var discomfort: float = _profile.discomfort_level if _profile != null else 0.0
	return {
		"npc_name": _npc.npc_name if _npc != null else "",
		"mode": kind,
		"emotional_state": _profile.get_state_label() if _profile != null else "",
		"comfort_level": comfort,
		"discomfort_level": discomfort,
		"awareness": _attention.get_awareness_label() if _attention != null else "",
		"is_commanded": _is_commanded(),
		"memory_summary": _memory_summary,
		"memory_notes": _memory_notes,
		"recent_events": _build_recent_events(),
		"chat_history": _chat_history,
		"chat_message": chat_message,
		"action_catalog": actions,
		"voice_catalog": voices,
	}


func _build_recent_events() -> Array[Dictionary]:
	if _memory == null:
		return []
	var events: Array[Dictionary] = _memory.get_recent(llm_config.recent_event_window)
	var limit: int = llm_config.recent_event_limit
	var result: Array[Dictionary] = []
	var now: float = _memory.get_clock()
	for i: int in range(mini(events.size(), limit)):
		var ev: Dictionary = events[i]
		var time_ago: float = now - (ev["time"] as float)
		result.append({
			"type": String(ev["type"]),
			"part": ev["part"] as String,
			"intensity": ev["intensity"] as float,
			"time_ago": time_ago,
		})
	return result


func _build_action_catalog() -> Array[String]:
	var actions: Array[String] = []
	if _behavior != null:
		actions = _behavior.get_behavior_names()
	if not actions.has("idle"):
		actions.append("idle")
	actions.append("notice_player")
	actions.append("fixate_player")
	actions.append("release_focus")
	return actions


func _build_voice_catalog() -> Array[String]:
	if _voice == null:
		return []
	return _voice.get_categories()


func _compute_temperature() -> float:
	var temp: float = llm_config.temperature_base
	if _profile != null:
		var comfort: float = clampf(_profile.comfort_level / 100.0, 0.0, 1.0)
		var discomfort: float = clampf(_profile.discomfort_level / 100.0, 0.0, 1.0)
		temp += comfort * llm_config.temperature_pleasure_scale
		temp += discomfort * llm_config.temperature_pain_scale
	if _spike_active:
		temp = randf_range(llm_config.pleasure_spike_min, llm_config.pleasure_spike_max)
	return clampf(temp, llm_config.temperature_min, llm_config.temperature_max)


func _update_spike_state() -> void:
	if _profile == null:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	if _spike_active and now >= _spike_end_time:
		_spike_active = false
		_spike_cooldown_until = now + llm_config.pleasure_spike_cooldown
		add_memory_note("Pleasure peaked and control slipped for a moment.")
	if not _spike_active and now >= _spike_cooldown_until:
		if _profile.comfort_level >= llm_config.pleasure_spike_threshold:
			_spike_active = true
			_spike_end_time = now + llm_config.pleasure_spike_duration


func _on_request_completed(result: int, response_code: int,
		_headers: PackedStringArray, body: PackedByteArray) -> void:
	var request_kind: String = _pending_kind
	var request_message: String = _pending_chat_message
	_pending_request = false
	_pending_kind = ""
	_pending_chat_message = ""
	if result != OK or response_code < 200 or response_code >= 300:
		push_warning("[LLMNPCController] Response error: %s (%d)" % [str(result), response_code])
		return
	var text: String = body.get_string_from_utf8()
	var decision: Dictionary = _parse_decision(text)
	if decision.is_empty():
		push_warning("[LLMNPCController] Empty or invalid LLM response")
		return
	_apply_decision(decision, request_kind, request_message)


func _parse_decision(response_text: String) -> Dictionary:
	var root: Variant = _parse_json(response_text)
	if root is Dictionary:
		var dict_root: Dictionary = root as Dictionary
		if dict_root.has("choices"):
			var choices: Array = dict_root["choices"] as Array
			if not choices.is_empty():
				var choice: Dictionary = choices[0] as Dictionary
				if choice.has("message") and choice["message"] is Dictionary:
					var msg: Dictionary = choice["message"] as Dictionary
					var content: String = msg.get("content", "") as String
					return _parse_json_object(content)
				if choice.has("text"):
					var text: String = choice.get("text", "") as String
					return _parse_json_object(text)
		return _parse_json_object(response_text)
	return {}


func _parse_json(text: String) -> Variant:
	var parsed: JSON = JSON.new()
	if parsed.parse(text) == OK:
		return parsed.data
	return null


func _parse_json_object(text: String) -> Dictionary:
	var parsed: JSON = JSON.new()
	if parsed.parse(text) == OK and parsed.data is Dictionary:
		return parsed.data as Dictionary
	var extracted: String = _extract_json_object(text)
	if extracted != "":
		if parsed.parse(extracted) == OK and parsed.data is Dictionary:
			return parsed.data as Dictionary
	return {}


func _extract_json_object(text: String) -> String:
	var start: int = text.find("{")
	var end: int = text.rfind("}")
	if start == -1 or end == -1 or end <= start:
		return ""
	return text.substr(start, end - start + 1)


func _apply_decision(decision: Dictionary, request_kind: String,
		request_message: String) -> void:
	var action_id: String = String(decision.get("action_id", "")).strip_edges()
	var voice_id: String = String(decision.get("voice_id", "")).strip_edges()
	var reply_text: String = String(decision.get("reply_text", "")).strip_edges()
	if llm_config != null and reply_text.length() > llm_config.reply_max_chars:
		reply_text = reply_text.substr(0, llm_config.reply_max_chars)

	if allow_actions and action_id != "":
		_execute_action(action_id)
	if allow_voice and voice_id != "" and _voice != null:
		var interrupt: bool = request_kind == "chat" or request_message != ""
		if _voice.can_speak(voice_id):
			_voice.speak(voice_id, interrupt)

	if reply_text != "":
		_append_chat_history("npc", reply_text)
		llm_reply.emit(reply_text, voice_id, action_id)

	if debug_logging:
		print("[LLMNPCController] decision=", decision)


func _execute_action(action_id: String) -> void:
	if _behavior != null and _behavior.has_behavior(action_id):
		_behavior.force_behavior(action_id)
		return
	match action_id:
		"notice_player":
			if _attention != null:
				var player: Node3D = _find_player()
				if player != null:
					_attention.notice(player, 2.0)
		"fixate_player":
			if _attention != null:
				var player: Node3D = _find_player()
				if player != null:
					_attention.fixate(player)
		"release_focus":
			if _attention != null:
				_attention.release_fixation()


func _find_player() -> Node3D:
	var nodes: Array[Node] = get_tree().get_nodes_in_group(&"player")
	if not nodes.is_empty():
		return nodes[0] as Node3D
	return null


func _append_chat_history(role: String, text: String) -> void:
	var entry: String = "%s: %s" % [role, text]
	_chat_history.append(entry)
	if llm_config != null and _chat_history.size() > llm_config.chat_history_limit:
		_chat_history = _chat_history.slice(_chat_history.size() - llm_config.chat_history_limit)


func _get_persona_prompt() -> String:
	if llm_config == null:
		return ""
	if llm_config.persona_presets.has(persona_id):
		return llm_config.persona_presets[persona_id] as String
	return llm_config.persona_presets.get("default", "") as String
