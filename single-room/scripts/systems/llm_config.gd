class_name LLMConfig
extends Resource
## Central config for LLM-driven NPC decisions.

@export_group("Timing")
@export var decision_interval: float = 0.5
@export var max_tokens: int = 80
@export var reply_max_chars: int = 160
@export var request_timeout_sec: float = 1.5

@export_group("Temperature")
@export var temperature_base: float = 0.2
@export var temperature_pain_scale: float = 0.6
@export var temperature_pleasure_scale: float = 0.6
@export var temperature_min: float = 0.1
@export var temperature_max: float = 1.2

@export_group("Pleasure Spike")
@export var pleasure_spike_threshold: float = 95.0
@export var pleasure_spike_duration: float = 4.0
@export var pleasure_spike_min: float = 0.2
@export var pleasure_spike_max: float = 1.6
@export var pleasure_spike_cooldown: float = 20.0

@export_group("Prompt")
@export var recent_event_window: float = 12.0
@export var recent_event_limit: int = 6
@export var chat_history_limit: int = 6
@export var memory_note_limit: int = 4

@export_group("Persona")
@export var persona_presets: Dictionary = {
	"default": "You are the NPC. Stay in-character, concise, and grounded.",
	"playful": "You are playful and teasing, but stay safe and concise.",
	"gentle": "You are gentle and reassuring. Keep replies short and warm.",
}
