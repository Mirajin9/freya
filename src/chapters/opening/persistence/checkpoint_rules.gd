extends RefCounted
## Validates the chapter/world/inventory envelope without mutating the scene.
## The existing subsystem validators remain authoritative for their own data.

const WorldState = preload("res://src/framework/world_state.gd")
const AT_BANK: Array[String] = ["near_bank", "family_crossing", "far_bank", "last_crossing", "fracture", "falling", "landing", "landed"]
const ACROSS: Array[String] = ["far_bank", "last_crossing", "fracture", "falling", "landing", "landed"]

func valid(data: Variant, chapter_validator: Callable, base_validator: Callable, inventory_factory: Callable, item_catalog: Dictionary) -> bool:
	if not data is Dictionary or not chapter_validator.call(data.get("opening", null)):
		return false
	var chapter: Dictionary = data.opening
	var inventory: RefCounted = inventory_factory.call()
	if not inventory.load_catalog(item_catalog) or not inventory.restore(data.get("inventory", null)):
		return false
	var state: RefCounted = WorldState.new()
	if not state.restore(data.get("state", null)):
		return false
	if chapter.phase != "locked" and not state.has("flag:family_reunited"):
		return false
	if state.has("flag:party_at_crossing") != (chapter.phase in AT_BANK):
		return false
	if state.has("flag:family_across") != (chapter.phase in ACROSS):
		return false
	if state.has("flag:crossing_started") != (int(chapter.crossings) == 1):
		return false
	if state.has("flag:crevice_landed") != (int(chapter.falls) == 1):
		return false
	return base_validator.call(data)

