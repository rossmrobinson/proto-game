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

@export var log_frames: int = 120
@export var log_dir: String = "user://logs"
