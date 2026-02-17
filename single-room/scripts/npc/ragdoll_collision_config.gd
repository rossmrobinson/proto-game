class_name RagdollCollisionConfig
extends RefCounted

## Add collision exceptions between ALL body parts in this ragdoll.
## At 66 parts per NPC, intra-ragdoll collisions cause severe jitter and
## explosion when parts overlap at spawn. Non-adjacent self-collision
## (e.g. hand touching own thigh) can be re-enabled later with careful
## spawn-position validation and per-pair exceptions.
static func apply_collision_exclusions(parts: Dictionary) -> void:
	var all_parts: Array[BodyPart] = []
	for part_name_key: String in parts:
		all_parts.append(parts[part_name_key] as BodyPart)
	for i: int in range(all_parts.size()):
		for j: int in range(i + 1, all_parts.size()):
			all_parts[i].add_collision_exception_with(all_parts[j])
			all_parts[j].add_collision_exception_with(all_parts[i])


## Re-enable collisions between left/right breast parts so they can be
## pushed together and physically squeeze around objects between them.
## Must be called AFTER apply_collision_exclusions().
static func restore_breast_collisions(parts: Dictionary) -> void:
	BodyPartRegistry.ensure_loaded()
	var left_names: PackedStringArray = PackedStringArray()
	var right_names: PackedStringArray = PackedStringArray()
	for breast_part_name: String in BodyPartRegistry.get_parts_by_group("breast"):
		if breast_part_name.begins_with("left_"):
			left_names.append(breast_part_name)
		elif breast_part_name.begins_with("right_"):
			right_names.append(breast_part_name)
	# Every left breast part can collide with every right breast part.
	for l_name: String in left_names:
		for r_name: String in right_names:
			if parts.has(l_name) and parts.has(r_name):
				var a: BodyPart = parts[l_name] as BodyPart
				var b: BodyPart = parts[r_name] as BodyPart
				a.remove_collision_exception_with(b)
				b.remove_collision_exception_with(a)


## Re-enable collisions between fine motor parts (fingers, tongue) and
## internal passage parts on the SAME NPC.  This allows self-insertion.
## Must be called AFTER apply_collision_exclusions().
static func restore_self_touch_collisions(parts: Dictionary) -> void:
	BodyPartRegistry.ensure_loaded()
	var fine_motor_parts: PackedStringArray = BodyPartRegistry.get_fine_motor_parts()
	var internal_parts: PackedStringArray = BodyPartRegistry.get_internal_parts()
	for fine_name: String in fine_motor_parts:
		if not parts.has(fine_name):
			continue
		var fine: BodyPart = parts[fine_name] as BodyPart
		for int_name: String in internal_parts:
			if not parts.has(int_name):
				continue
			var internal: BodyPart = parts[int_name] as BodyPart
			fine.remove_collision_exception_with(internal)
			internal.remove_collision_exception_with(fine)


## Re-enable collisions between penis parts and internal passages on the
## SAME NPC.  This allows self-penetration when the player grabs and guides
## the penis.  Must be called AFTER apply_collision_exclusions().
static func restore_penis_passage_collisions(parts: Dictionary) -> void:
	BodyPartRegistry.ensure_loaded()
	var penis_parts: PackedStringArray = PackedStringArray()
	for groin_part_name: String in BodyPartRegistry.get_parts_by_group("groin_male"):
		if groin_part_name.begins_with("penis_"):
			penis_parts.append(groin_part_name)
	var internal_parts: PackedStringArray = BodyPartRegistry.get_internal_parts()
	for p_name: String in penis_parts:
		if not parts.has(p_name):
			continue
		var penis_part: BodyPart = parts[p_name] as BodyPart
		for int_name: String in internal_parts:
			if not parts.has(int_name):
				continue
			var internal: BodyPart = parts[int_name] as BodyPart
			penis_part.remove_collision_exception_with(internal)
			internal.remove_collision_exception_with(penis_part)


## Move passage segments to layer 6 (NPC_Internal) so they don't interact
## with external physics.  They keep mask layer 3 so rays/queries can reach them.
## Passages also mask layer 5 (NPC_SoftTissue) so objects from other NPCs
## (penis, fingers) can push them open during penetration.
static func assign_internal_layers(parts: Dictionary) -> void:
	for part_name_key: String in parts:
		var config: Dictionary = BodyPartRegistry.get_part_config(part_name_key)
		if str(config.get("collision_layer", "external")) == "internal":
			var part: BodyPart = parts[part_name_key] as BodyPart
			# Clear external layers
			part.collision_layer = 0
			part.set_collision_layer_value(6, true)  # NPC_Internal
			# Collide with other internals + equipment + soft tissue (penetration)
			part.collision_mask = 0
			part.set_collision_mask_value(5, true)  # NPC_SoftTissue (cross-NPC penetration)
			part.set_collision_mask_value(6, true)  # Other internal segments
			part.set_collision_mask_value(7, true)  # Equipment (piercings, toys)
			part.set_collision_mask_value(8, true)  # NPC_FineMotor (fingers, tongue)


## Move soft-tissue parts (breasts, glutes, genitals) to layer 5 (NPC_SoftTissue).
## They keep the same broad mask as skeletal parts but live on their own layer so
## gameplay queries can distinguish a grab on a breast vs. a grab on the ribcage.
## Soft tissue also masks layer 6 (NPC_Internal) so genitals from other NPCs
## can physically push open passage walls during cross-NPC penetration.
static func assign_soft_tissue_layers(parts: Dictionary) -> void:
	for part_name_key: String in parts:
		var config: Dictionary = BodyPartRegistry.get_part_config(part_name_key)
		if str(config.get("collision_layer", "external")) == "soft_tissue":
			var part: BodyPart = parts[part_name_key] as BodyPart
			# Move off NPC_External (3), onto NPC_SoftTissue (5).
			# Keep Interactable (4) so targeting/grab queries still find them.
			part.collision_layer = 0
			part.set_collision_layer_value(4, true)  # Interactable
			part.set_collision_layer_value(5, true)  # NPC_SoftTissue
			# Mask: Environment + NPC_External + Interactable + SoftTissue + Internal + Equipment
			# Do NOT include layer 2 (Player) — NPC parts must not push the player
			part.collision_mask = 0
			part.set_collision_mask_value(1, true)  # Environment
			part.set_collision_mask_value(3, true)  # NPC_External
			part.set_collision_mask_value(4, true)  # Interactable
			part.set_collision_mask_value(5, true)  # Other soft tissue
			part.set_collision_mask_value(6, true)  # NPC_Internal (cross-NPC penetration)
			part.set_collision_mask_value(7, true)  # Equipment


## Add layer 8 (NPC_FineMotor) to finger and tongue parts so they can
## collide with internal passages (layer 6).  These parts keep their
## existing layers (3 + 4) and gain layer 8 on top.  The part's mask
## also gains layer 6 so fine motor parts see passage walls.
static func assign_fine_motor_layers(parts: Dictionary) -> void:
	for part_name_key: String in parts:
		var config: Dictionary = BodyPartRegistry.get_part_config(part_name_key)
		if str(config.get("collision_layer", "external")) == "fine_motor":
			var part: BodyPart = parts[part_name_key] as BodyPart
			part.set_collision_layer_value(8, true)  # NPC_FineMotor
			part.set_collision_mask_value(6, true)   # NPC_Internal (passages)
