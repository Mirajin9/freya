extends RefCounted
## Visibility policy for the opening overlay. No chapter state is changed here.

func update(world: Node3D) -> void:
	if not world.chapter:
		return
	var chapter: RefCounted = world.chapter
	var in_kesh: bool = world.kesh_demo != null and world.kesh_demo.arrived
	var encounter_active: bool = not in_kesh and chapter.pack.active()
	var scene_view: bool = not in_kesh and (chapter.cinematic() or chapter.phase == "landed") and not encounter_active
	world.tracker.visible = not scene_view and not encounter_active
	world.toast.visible = not scene_view and not encounter_active
	world.pickup_prompt.visible = not scene_view and not encounter_active
	chapter.subtitle.visible = chapter.phase != "landed" and not chapter.cinematic()

