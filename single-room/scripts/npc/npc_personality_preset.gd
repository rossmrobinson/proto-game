class_name NPCPersonalityPreset
extends RefCounted
## Static library of personality presets.
## Each preset returns a Dictionary of overrides keyed by subsystem → param → value.
## NPCPlaceholder.apply_personality_preset() reads these and pushes values into
## CharacterProfile, NPCBrain, NPCBehavior, NPCInteractionTargeting, and
## NPCAutonomousDrive.

# ── Preset Enum ──────────────────────────────────────────────────────────────

enum Type {
	NEUTRAL,             ## Baseline — default values
	PRUDE,               ## Avoids sexual contact, extremely hard to seduce
	FRIENDLY,            ## Open to non-sexual touch, easy to seduce
	HANDSY,              ## Friendly but drifts toward intimate contact
	HORNY,               ## Actively seeks sex, masturbates when idle
	AGGRESSIVE,          ## Forces sexual contact, disrupts others, high force
	AGGRESSIVE_HELPER,   ## Brings NPCs to player, physically assists intercourse
}


# ── Public API ───────────────────────────────────────────────────────────────

## Returns a nested Dictionary: { "profile": {}, "brain": {}, "behavior": {},
##   "targeting": {}, "drive": {} }.
## Missing keys mean "keep default".
static func get_preset(preset_type: Type) -> Dictionary:
	match preset_type:
		Type.NEUTRAL:
			return _neutral()
		Type.PRUDE:
			return _prude()
		Type.FRIENDLY:
			return _friendly()
		Type.HANDSY:
			return _handsy()
		Type.HORNY:
			return _horny()
		Type.AGGRESSIVE:
			return _aggressive()
		Type.AGGRESSIVE_HELPER:
			return _aggressive_helper()
	return _neutral()


## Human-readable label for UI / debug.
static func get_label(preset_type: Type) -> String:
	match preset_type:
		Type.NEUTRAL:
			return "Neutral"
		Type.PRUDE:
			return "Prude"
		Type.FRIENDLY:
			return "Friendly"
		Type.HANDSY:
			return "Handsy"
		Type.HORNY:
			return "Horny"
		Type.AGGRESSIVE:
			return "Aggressive"
		Type.AGGRESSIVE_HELPER:
			return "Aggressive Helper"
	return "Unknown"


# ══════════════════════════════════════════════════════════════════════════════
#  PRESET DEFINITIONS
# ══════════════════════════════════════════════════════════════════════════════

static func _neutral() -> Dictionary:
	return {
		"profile": {
			"pain_tolerance": 0.5,
			"touch_receptivity": 0.5,
			"erogenous_sensitivity": 1.0,
			"emotional_recovery_rate": 1.0,
		},
		"brain": {
			"talkativeness": 0.5,
			"nervousness": 0.3,
			"touch_openness": 0.5,
			"defiance": 0.2,
			"idle_speak_interval": 15.0,
			"annoyance_grab_threshold": 3,
		},
		"behavior": {
			"idle_change_interval": 5.0,
			"idle_change_jitter": 2.0,
		},
		"targeting": {
			"approach_force": 15.0,
			"approach_max_speed": 0.8,
		},
		"drive": {
			"sexual_initiative": 0.0,
			"seduction_resistance": 0.5,
			"physical_force_level": 0.3,
			"preferred_approach": NPCInteractionIntent.ApproachStyle.WAIT,
			"auto_masturbate": false,
			"disrupts_others": false,
			"helper_mode": false,
			"initiative_interval": 30.0,
			"initiative_jitter": 10.0,
		},
	}


static func _prude() -> Dictionary:
	return {
		"profile": {
			"pain_tolerance": 0.3,
			"touch_receptivity": 0.1,
			"erogenous_sensitivity": 0.6,
			"emotional_recovery_rate": 0.5,
			# Lower comfort thresholds — gets uncomfortable faster
			"relaxed_threshold": 40.0,
			"content_threshold": 70.0,
			"aroused_threshold": 90.0,
			# Lower discomfort thresholds — distresses faster
			"tense_threshold": 15.0,
			"distressed_threshold": 35.0,
			"overwhelmed_threshold": 50.0,
		},
		"brain": {
			"talkativeness": 0.3,
			"nervousness": 0.7,
			"touch_openness": 0.05,
			"defiance": 0.6,
			"idle_speak_interval": 25.0,
			"annoyance_grab_threshold": 1,
			"pain_voice_threshold": 0.5,
			"startle_impact_threshold": 1.0,
		},
		"behavior": {
			"idle_change_interval": 8.0,
			"idle_change_jitter": 3.0,
		},
		"targeting": {
			"approach_force": 8.0,
			"approach_max_speed": 0.4,
		},
		"drive": {
			"sexual_initiative": 0.0,
			"seduction_resistance": 0.95,
			"physical_force_level": 0.1,
			"preferred_approach": NPCInteractionIntent.ApproachStyle.YIELD,
			"auto_masturbate": false,
			"disrupts_others": false,
			"helper_mode": false,
			"initiative_interval": 999.0,
			"initiative_jitter": 0.0,
		},
	}


static func _friendly() -> Dictionary:
	return {
		"profile": {
			"pain_tolerance": 0.5,
			"touch_receptivity": 0.8,
			"erogenous_sensitivity": 1.2,
			"emotional_recovery_rate": 1.3,
			"relaxed_threshold": 20.0,
			"content_threshold": 45.0,
		},
		"brain": {
			"talkativeness": 0.7,
			"nervousness": 0.15,
			"touch_openness": 0.8,
			"defiance": 0.1,
			"idle_speak_interval": 10.0,
			"annoyance_grab_threshold": 5,
		},
		"behavior": {
			"idle_change_interval": 4.0,
			"idle_change_jitter": 2.0,
		},
		"targeting": {
			"approach_force": 12.0,
			"approach_max_speed": 0.7,
		},
		"drive": {
			"sexual_initiative": 0.1,
			"seduction_resistance": 0.2,
			"physical_force_level": 0.2,
			"preferred_approach": NPCInteractionIntent.ApproachStyle.WAIT,
			"auto_masturbate": false,
			"disrupts_others": false,
			"helper_mode": false,
			"initiative_interval": 45.0,
			"initiative_jitter": 15.0,
		},
	}


static func _handsy() -> Dictionary:
	return {
		"profile": {
			"pain_tolerance": 0.5,
			"touch_receptivity": 0.85,
			"erogenous_sensitivity": 1.4,
			"emotional_recovery_rate": 1.2,
			"relaxed_threshold": 20.0,
			"content_threshold": 40.0,
			"aroused_threshold": 60.0,
		},
		"brain": {
			"talkativeness": 0.6,
			"nervousness": 0.1,
			"touch_openness": 0.9,
			"defiance": 0.15,
			"idle_speak_interval": 10.0,
			"annoyance_grab_threshold": 6,
		},
		"behavior": {
			"idle_change_interval": 3.5,
			"idle_change_jitter": 1.5,
		},
		"targeting": {
			"approach_force": 14.0,
			"approach_max_speed": 0.75,
		},
		"drive": {
			"sexual_initiative": 0.35,
			"seduction_resistance": 0.1,
			"physical_force_level": 0.3,
			"preferred_approach": NPCInteractionIntent.ApproachStyle.NUDGE,
			"auto_masturbate": false,
			"disrupts_others": false,
			"helper_mode": false,
			"initiative_interval": 20.0,
			"initiative_jitter": 8.0,
		},
	}


static func _horny() -> Dictionary:
	return {
		"profile": {
			"pain_tolerance": 0.6,
			"touch_receptivity": 0.95,
			"erogenous_sensitivity": 1.8,
			"emotional_recovery_rate": 1.5,
			"relaxed_threshold": 15.0,
			"content_threshold": 30.0,
			"aroused_threshold": 45.0,
		},
		"brain": {
			"talkativeness": 0.8,
			"nervousness": 0.05,
			"touch_openness": 0.95,
			"defiance": 0.1,
			"idle_speak_interval": 8.0,
			"annoyance_grab_threshold": 8,
		},
		"behavior": {
			"idle_change_interval": 3.0,
			"idle_change_jitter": 1.0,
		},
		"targeting": {
			"approach_force": 18.0,
			"approach_max_speed": 0.9,
		},
		"drive": {
			"sexual_initiative": 0.8,
			"seduction_resistance": 0.0,
			"physical_force_level": 0.4,
			"preferred_approach": NPCInteractionIntent.ApproachStyle.NUDGE,
			"auto_masturbate": true,
			"disrupts_others": false,
			"helper_mode": false,
			"initiative_interval": 12.0,
			"initiative_jitter": 5.0,
		},
	}


static func _aggressive() -> Dictionary:
	return {
		"profile": {
			"pain_tolerance": 0.8,
			"touch_receptivity": 0.9,
			"erogenous_sensitivity": 1.5,
			"emotional_recovery_rate": 1.8,
			"relaxed_threshold": 10.0,
			"content_threshold": 25.0,
			"aroused_threshold": 40.0,
			"tense_threshold": 50.0,
			"distressed_threshold": 75.0,
			"overwhelmed_threshold": 90.0,
		},
		"brain": {
			"talkativeness": 0.6,
			"nervousness": 0.0,
			"touch_openness": 0.95,
			"defiance": 0.8,
			"idle_speak_interval": 10.0,
			"annoyance_grab_threshold": 10,
			"pain_voice_threshold": 2.5,
			"startle_impact_threshold": 4.0,
		},
		"behavior": {
			"idle_change_interval": 2.5,
			"idle_change_jitter": 1.0,
		},
		"targeting": {
			"approach_force": 30.0,
			"approach_max_speed": 1.4,
		},
		"drive": {
			"sexual_initiative": 0.95,
			"seduction_resistance": 0.0,
			"physical_force_level": 0.85,
			"preferred_approach": NPCInteractionIntent.ApproachStyle.SHOVE,
			"auto_masturbate": true,
			"disrupts_others": true,
			"initiative_interval": 8.0,
			"initiative_jitter": 3.0,
			"helper_mode": false,
		},
	}


static func _aggressive_helper() -> Dictionary:
	return {
		"profile": {
			"pain_tolerance": 0.7,
			"touch_receptivity": 0.85,
			"erogenous_sensitivity": 1.3,
			"emotional_recovery_rate": 1.6,
			"relaxed_threshold": 15.0,
			"content_threshold": 30.0,
			"aroused_threshold": 45.0,
			"tense_threshold": 45.0,
			"distressed_threshold": 70.0,
			"overwhelmed_threshold": 85.0,
		},
		"brain": {
			"talkativeness": 0.5,
			"nervousness": 0.0,
			"touch_openness": 0.9,
			"defiance": 0.7,
			"idle_speak_interval": 12.0,
			"annoyance_grab_threshold": 8,
			"pain_voice_threshold": 2.0,
			"startle_impact_threshold": 3.5,
		},
		"behavior": {
			"idle_change_interval": 3.0,
			"idle_change_jitter": 1.5,
		},
		"targeting": {
			"approach_force": 25.0,
			"approach_max_speed": 1.2,
		},
		"drive": {
			"sexual_initiative": 0.7,
			"seduction_resistance": 0.0,
			"physical_force_level": 0.75,
			"preferred_approach": NPCInteractionIntent.ApproachStyle.SHOVE,
			"auto_masturbate": false,
			"disrupts_others": true,
			"helper_mode": true,
			"initiative_interval": 10.0,
			"initiative_jitter": 4.0,
		},
	}
