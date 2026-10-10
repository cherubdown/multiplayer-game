extends SceneTree
## Checks Inventory, and that AccountStore saves inventories and chests,
## without a network. Run from the project folder:
##   godot --headless --path . -s tests/test_inventory.gd
## Exits non-zero if any check fails.

const Inventory := preload("res://scripts/inventory.gd")
const AccountStore := preload("res://scripts/account_store.gd")
const PATH := "user://test_inventory.db"

var _failures := 0


func _init() -> void:
	var inv := Inventory.new(3)
	_check(inv.is_empty(), "a new inventory is empty")
	_check(inv.add("wood", 30) == 0, "adds a stack")
	_check(inv.add("wood", 30) == 0 and inv.slots[0]["count"] == 50 and inv.slots[1]["count"] == 10,
		"tops up a stack before starting another")
	_check(inv.add("stone", 5) == 0 and inv.slots[2]["item"] == "stone", "puts a new item in an empty slot")
	_check(inv.add("flint", 2) == 2, "returns what doesn't fit")
	_check(inv.add("wood", 45) == 5 and inv.count_of("wood") == 100, "fills the last stack and returns the rest")
	_check(inv.add("gold", 1) == 1, "rejects an unknown item")

	var chest := Inventory.new(2)
	_check(inv.move_to(2, chest) == 5 and inv.slots[2] == null, "moves a stack into another inventory")
	_check(chest.count_of("stone") == 5, "the moved stack arrives")
	_check(inv.move_to(0, chest) == 50 and chest.slots[1]["count"] == 50, "moves into the next free slot")
	_check(inv.move_to(1, chest) == 0 and inv.slots[1]["count"] == 50, "moves nothing into a full inventory")
	_check(chest.move_to(0, inv) == 5 and chest.slots[0] == null, "moves a stack back")
	_check(inv.move_to(7, chest) == 0 and inv.move_to(-1, chest) == 0, "ignores slots out of range")

	var loaded := Inventory.new(3)
	loaded.load_array(JSON.parse_string(JSON.stringify(inv.to_array())))
	_check(loaded.to_array() == inv.to_array(), "survives a round trip through JSON")
	loaded.load_array([{ "item": "gold", "count": 3 }, { "item": "wood", "count": 999 }, "junk", { "item": "stone", "count": 1 }])
	_check(loaded.slots[0] == null and loaded.slots[1]["count"] == 50 and loaded.slots[2] == null,
		"drops unknown items, clamps counts and ignores extra slots")

	_check_saving()
	print("Inventory: %s" % ("all checks passed" if _failures == 0 else "%d checks failed" % _failures))
	quit(1 if _failures > 0 else 0)


func _check_saving() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	var store := AccountStore.new(PATH)
	store.register("chris", "secret1")
	store.create_character("chris", "Ragnar", "dwarf")
	store.create_character("chris", "Astrid")
	_check(store.load_inventory("chris", "Ragnar") == [], "a new character has an empty inventory")
	var inv := Inventory.new(4)
	inv.add("berries", 7)
	_check(store.save_inventory("chris", "ragnar", inv.to_array()), "saves an inventory")
	_check(store.load_chest("test") == [], "a new chest is empty")
	_check(store.save_chest("test", inv.to_array()), "saves a chest")
	store.close()

	var reloaded := AccountStore.new(PATH)
	var slots := reloaded.load_inventory("Chris", "Ragnar")
	_check(slots.size() == 4 and slots[0] != null and slots[0]["item"] == "berries" and int(slots[0]["count"]) == 7,
		"inventory survives a reload")
	_check(reloaded.load_inventory("chris", "Astrid") == [], "other characters keep their own inventory")
	var chest := Inventory.new(4)
	chest.load_array(reloaded.load_chest("test"))
	_check(chest.count_of("berries") == 7, "chest survives a reload")
	_check(reloaded.world_seed() == "", "chests don't get in the way of the world seed")
	reloaded.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: %s" % what)
