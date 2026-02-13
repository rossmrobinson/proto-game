extends Node
## Scene-level spawner for global interaction systems.
## Attach to a Node child of the scene root, or register as autoload.
## Creates InteractionClaimSystem and BodyStackManager if they don't exist.


func _ready() -> void:
	_ensure_singleton(InteractionClaimSystem, "InteractionClaimSystem")
	_ensure_singleton(BodyStackManager, "BodyStackManager")


func _ensure_singleton(klass: Variant, node_name: String) -> void:
	var group_name: StringName = &"interaction_claim_system" \
		if klass == InteractionClaimSystem else &"body_stack_manager"

	if not get_tree().get_nodes_in_group(group_name).is_empty():
		return

	var instance: Node = (klass as GDScript).new() if klass is GDScript \
		else _create_by_class(node_name)
	instance.name = node_name
	get_tree().current_scene.add_child(instance)


func _create_by_class(class_hint: String) -> Node:
	match class_hint:
		"InteractionClaimSystem":
			return InteractionClaimSystem.new()
		"BodyStackManager":
			return BodyStackManager.new()
	return Node.new()
