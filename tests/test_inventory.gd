extends SceneTree
## Checks Inventory, and that AccountStore saves inventories and chests,
## without a network. Run from the project folder:
##   godot --headless --path . -s tests/test_inventory.gd
## Exits non-zero if any check fails.

const Inventory := preload("res://scripts/inventory.gd")
const AccountStore := preload("res://scripts/account_store.gd")
const Items := preload("res://scripts/items.gd")
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

	var a := Inventory.new(3)
	var b := Inventory.new(2)
	a.add("wood", 40)
	a.slots[1] = { "item": "wood", "count": 30 }
	a.slots[2] = { "item": "stone", "count": 4 }
	_check(a.move_slot(0, a, 1) and a.slots[1]["count"] == 50 and a.slots[0]["count"] == 20,
		"dragging onto the same item tops it up and leaves the rest")
	_check(not a.move_slot(0, a, 1), "dragging onto a full stack of the same item does nothing")
	_check(a.move_slot(2, a, 0) and a.slots[0]["item"] == "stone" and a.slots[2]["item"] == "wood",
		"dragging onto a different item swaps them")
	_check(a.move_slot(0, b, 1) and b.slots[1]["item"] == "stone" and a.slots[0] == null,
		"drags into an empty slot of another inventory")
	_check(b.move_slot(1, a, 1) and a.slots[1]["item"] == "stone" and b.slots[1]["item"] == "wood",
		"swaps between inventories")
	_check(not a.move_slot(0, b, 0) and not a.move_slot(1, a, 1) and not a.move_slot(1, b, 5),
		"ignores empty, same and out of range slots")
	_check(a.take(1) == { "item": "stone", "count": 4 } and a.slots[1] == null and a.take(1).is_empty(),
		"takes a whole stack out")

	var s := Inventory.new(4)
	var t := Inventory.new(2)
	s.slots[0] = { "item": "wood", "count": 7 }
	_check(s.split_slot(0, s, 1) and s.slots[0]["count"] == 4 and s.slots[1] == { "item": "wood", "count": 3 },
		"splitting moves half into an empty slot, the original keeping the bigger half")
	_check(s.split_slot(0, s, 1) and s.slots[0]["count"] == 2 and s.slots[1]["count"] == 5,
		"splitting onto the same item tops it up with half")
	s.slots[2] = { "item": "stone", "count": 6 }
	_check(not s.split_slot(1, s, 2) and s.slots[1]["count"] == 5 and s.slots[2]["count"] == 6,
		"splitting onto a different item does nothing")
	s.slots[3] = { "item": "wood", "count": 1 }
	_check(not s.split_slot(3, s, 0) and s.slots[3]["count"] == 1, "a single item can't be split")
	s.slots[3] = { "item": "wood", "count": 49 }
	_check(s.split_slot(1, s, 3) and s.slots[3]["count"] == 50 and s.slots[1]["count"] == 4,
		"splitting onto a nearly full stack moves only what fits")
	_check(not s.split_slot(1, s, 3), "splitting onto a full stack does nothing")
	_check(s.split_slot(2, t, 0) and t.slots[0] == { "item": "stone", "count": 3 } and s.slots[2]["count"] == 3,
		"splits into another inventory")
	s.slots[0] = { "item": "stone_axe", "count": 1 }
	_check(not s.split_slot(0, t, 1) and not s.split_slot(1, s, 1) and not s.split_slot(1, s, 9),
		"ignores tools, same and out of range slots")

	for item in Items.IDS:
		_check(Items.description(item) != "", "%s has a description" % item)
		var icon := Items.icon(item)
		_check(icon != null and icon.get_width() == 64, "%s has an icon" % item)

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
