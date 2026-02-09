@tool
extends EditorScript

func _run() -> void:
	var project_name: String = ProjectSettings.get_setting("application/config/name") as String
	var project_root: String = ProjectSettings.globalize_path("res://")
	var project_cache: String = project_root.path_join(".godot")
	var user_dir: String = OS.get_user_data_dir()
	print("[CachePaths] project_name=%s" % project_name)
	print("[CachePaths] project_root=%s" % project_root)
	print("[CachePaths] project_cache=%s" % project_cache)
	print("[CachePaths] user_data_dir=%s" % user_dir)
