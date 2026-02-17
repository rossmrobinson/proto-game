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

@export_group("Pleasure Spike Phases")
@export var pleasure_spike_threshold: float = 95.0
@export var pleasure_spike_cooldown: float = 20.0

@export_subgroup("Phase Durations")
## Seconds of buildup: temperature and token ramp up.
@export_range(0.5, 5.0) var spike_buildup_duration: float = 2.0
## Seconds of peak: max chaos, sensory barrage fires.
@export_range(0.5, 5.0) var spike_peak_duration: float = 2.0
## Seconds of afterglow: temperature decays back toward warm baseline.
@export_range(0.5, 10.0) var spike_afterglow_duration: float = 3.0
## Seconds of refractory: temperature drops below baseline, lucid and clear.
@export_range(5.0, 60.0) var spike_refractory_duration: float = 15.0

@export_subgroup("Phase Temperatures")
## Temperature during buildup (rising urgency).
@export_range(0.3, 1.5) var spike_buildup_temp: float = 0.9
## Temperature at peak (max chaos).
@export_range(0.5, 2.0) var spike_peak_temp: float = 1.6
## Temperature during afterglow (warm, dreamy).
@export_range(0.3, 1.2) var spike_afterglow_temp: float = 0.7
## Temperature multiplier during refractory (applied to base — below 1.0 = lucid).
@export_range(0.2, 1.0) var spike_refractory_temp_mult: float = 0.5

@export_subgroup("Phase Token Limits")
## Max tokens during buildup (short, urgent).
@export_range(5, 60) var spike_buildup_max_tokens: int = 30
## Max tokens during peak (fragments only).
@export_range(3, 30) var spike_peak_max_tokens: int = 12
## Max tokens during afterglow (brief, warm).
@export_range(10, 120) var spike_afterglow_max_tokens: int = 40

@export_subgroup("Phase Timing")
## Decision interval during buildup (faster decisions).
@export_range(0.1, 1.0) var spike_buildup_interval: float = 0.3
## Decision interval during peak (rapid-fire).
@export_range(0.05, 0.5) var spike_peak_interval: float = 0.12
## Decision interval during afterglow (slow, languid).
@export_range(0.5, 3.0) var spike_afterglow_interval: float = 1.5

@export_subgroup("Sensory Barrage")
## Max number of barrage fragments that survive (oldest cancelled).
@export_range(1, 6) var barrage_max_survivors: int = 3
## Barrage fire interval in seconds.
@export_range(0.05, 0.5) var barrage_fire_interval: float = 0.12

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
