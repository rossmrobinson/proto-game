class_name RagdollDebugConfig
extends Resource

@export var enabled: bool = true
@export var show_overlay: bool = true
@export var show_debug_meshes: bool = false
@export var show_part_labels: bool = false
@export var show_offset_lines: bool = true
@export var show_joint_axes: bool = false
@export var log_to_file: bool = true

@export var sample_interval: float = 0.1
@export var label_update_interval: float = 0.2
@export var max_joint_axes: int = 24
@export var axis_length: float = 0.08

@export var floor_y: float = 0.0
@export var max_offset: float = 0.02
@export var max_linear_velocity: float = 2.0
@export var max_angular_velocity: float = 10.0
@export var max_penetration: float = 0.01
@export var max_joint_error_deg: float = 25.0
@export var max_unmatched_bones: int = 0
@export var min_axis_align: float = 0.6

@export var disable_joint_limits: bool = false
@export var disable_position_springs: bool = false
@export var disable_joint_pd: bool = false
@export var disable_pelvis_lock: bool = false
@export var use_physics_rest_relative: bool = true

@export var log_frames: int = 120
@export var log_dir: String = "J:/proto-game/single-room/logs"
@export var auto_snapshot_on_issue: bool = true
@export var auto_snapshot_cooldown: float = 2.0
@export var snapshot_max_parts: int = 80
@export var snapshot_max_joints: int = 80
@export var log_use_timestamped_files: bool = false
@export var log_max_files_per_npc: int = 2
@export var log_max_age_days: int = 2
@export var snapshot_max_files: int = 10
@export var pose_report_max_files: int = 10
