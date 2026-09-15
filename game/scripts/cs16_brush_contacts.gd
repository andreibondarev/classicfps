extends RefCounted

## Collect real body-solver contacts, including multiple contacts in one slide.
## Call after each accepted/attempted source movement, before another move can
## replace CharacterBody3D's collision results. Touch is separate from clipping.
static func append_motion_contacts(body: CharacterBody3D, contacts: PackedInt32Array) -> void:
	for slide_index in body.get_slide_collision_count():
		var collision := body.get_slide_collision(slide_index)
		for index in collision.get_collision_count():
			var collider := collision.get_collider(index) as Node
			if collider == null:
				continue
			var entity_id := int(collider.get_meta("entity_index", -1))
			if entity_id >= 0 and not contacts.has(entity_id):
				contacts.append(entity_id)
