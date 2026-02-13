class_name RagdollCalibrationConfig
extends Resource

@export var enabled: bool = true
@export var auto_start: bool = true
@export var npc_name: String = "Ada"
@export var pose_name: String = ""
@export var pose_settle_seconds: float = 0.5
@export var baseline_hold_seconds: float = 0.2
@export var run_seconds: float = 3.0
@export var sample_interval: float = 0.1
@export var iterations: int = 3
@export var max_report_parts: int = 10
@export var log_dir: String = "J:/proto-game/single-room/logs"
@export var overrides_path: String = "J:/proto-game/single-room/logs/llm_overrides.json"
@export var log_max_files: int = 5
@export var log_max_age_days: int = 2

@export_group("Suggestions")
@export var auto_apply_suggestions: bool = false
@export var suggest_min_drift_z: float = 0.05
@export var suggest_scale: float = 1.0
@export var suggest_max_step: float = 0.6
@export var suggest_parts: PackedStringArray = [
	"chest",
	"left_lower_leg",
	"right_lower_leg",
	"left_foot",
	"right_foot",
	"left_toes",
	"right_toes",
]
