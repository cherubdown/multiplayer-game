extends SceneTree
## Checks the Hotbar (the four tool slots along the bottom of the screen) and
## that AccountStore saves it. No network. Run from the project folder:
##   godot --headless --path . -s tests/test_hotbar.gd
## Exits non-zero if any check fails.

const Hotbar := preload("res://scripts/hotbar.gd")
const AccountStore := preload("res://scripts/account_store.gd")
const PATH := "user://test_hotbar.db"

var _failures := 0


func _init() -> void:
	_check_slots()
	_check_loading()
	_check_saving()
	print("Hotbar: %s" % ("all checks passed" if _failures == 0 else "%d checks failed" % _failures))
	quit(1 if _failures > 0 else 0)


func _check_slots() -> void:
	var bar := Hotbar.new()
	_check(bar.to_array() == ["", "", "", ""], "a new hotbar has four empty slots")
	_check(not bar.set_slot(0, "wood") and not bar.set_slot(0, "leather_cap") and not bar.set_slot(0, "nonsense"),
		"only tools and weapons go on the hotbar")
	_check(not bar.set_slot(4, "stone_axe") and not bar.set_slot(-1, "stone_axe"), "there are only four slots")
	_check(bar.set_slot(2, "stone_axe") and bar.item_in(2) == "stone_axe", "puts an axe in slot 3")
	_check(not bar.set_slot(2, "stone_axe"), "putting it there again changes nothing")
	_check(bar.set_slot(0, "wood_sword") and bar.set_slot(2, "wood_sword"),
		"puts a sword in slot 1, then moves it onto the axe")
	_check(bar.item_in(2) == "wood_sword" and bar.item_in(0) == "stone_axe", "the two swap rather than repeat")
	_check(bar.swap(0, 3) and bar.item_in(3) == "stone_axe" and bar.item_in(0) == "", "swaps a slot with an empty one")
	_check(not bar.swap(1, 0) and not bar.swap(3, 3) and not bar.swap(0, 7), "swapping empties, a slot with itself or a missing slot does nothing")
	_check(bar.set_slot(3, "") and bar.item_in(3) == "", "empties a slot")
	_check(bar.add("stone_axe") and bar.item_in(0) == "stone_axe", "adds a tool to the first empty slot")
	_check(not bar.add("stone_axe") and not bar.add("wood"), "but not one already there, or a material")
	bar.add("stone_pickaxe")
	bar.add("stone_sword")
	_check(not bar.add("wood_sword"), "a full hotbar takes no more")
	_check(bar.to_array() == ["stone_axe", "stone_pickaxe", "wood_sword", "stone_sword"],
		"fills up in order (%s)" % [bar.to_array()])


func _check_loading() -> void:
	var bar := Hotbar.new()
	bar.load_array(["stone_axe", "wood", "stone_axe", null, "wood_sword", "stone_pickaxe"])
	_check(bar.to_array() == ["stone_axe", "", "", ""],
		"loading drops materials, repeats, nulls and slots past the fourth (%s)" % [bar.to_array()])
	bar.load_array("nonsense")
	_check(bar.to_array() == ["", "", "", ""], "loading something that isn't a list empties it")
	var saved := Hotbar.new()
	saved.set_slot(1, "wood_sword")
	saved.set_slot(3, "stone_axe")
	bar.load_array(JSON.parse_string(JSON.stringify(saved.to_array())))
	_check(bar.to_array() == saved.to_array(), "survives a trip through JSON")


func _check_saving() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	var store := AccountStore.new(PATH)
	store.register("chris", "secret1")
	store.create_character("chris", "Ragnar", "dwarf")
	store.create_character("chris", "Astrid")
	_check(store.load_hotbar("chris", "Ragnar").is_empty(), "a new character has an empty hotbar")
	_check(store.save_hotbar("chris", "ragnar", ["", "wood_sword", "", "stone_axe"]), "saves the hotbar")
	store.close()
	var reloaded := AccountStore.new(PATH)
	var bar := Hotbar.new()
	bar.load_array(reloaded.load_hotbar("Chris", "Ragnar"))
	_check(bar.item_in(1) == "wood_sword" and bar.item_in(3) == "stone_axe", "the hotbar survives a reload")
	_check(reloaded.load_hotbar("chris", "Astrid").is_empty(), "other characters keep their own hotbar")
	reloaded.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failures += 1
