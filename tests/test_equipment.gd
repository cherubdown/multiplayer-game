extends SceneTree
## Checks Equipment (what a character wears), that AccountStore saves it, that
## the character sheet has a place for every slot, and that the old-school
## panel and slot textures draw. No network. Run from the project folder:
##   godot --headless --path . -s tests/test_equipment.gd
## Exits non-zero if any check fails.

const Equipment := preload("res://scripts/equipment.gd")
const Inventory := preload("res://scripts/inventory.gd")
const Items := preload("res://scripts/items.gd")
const AccountStore := preload("res://scripts/account_store.gd")
const CharacterSheet := preload("res://scripts/character_sheet.gd")
const UiStyle := preload("res://scripts/ui_style.gd")
const PATH := "user://test_equipment.db"

var _failures := 0


func _init() -> void:
	_check_items()
	_check_equipping()
	_check_saving()
	_check_sheet()
	_check_style()
	print("Equipment: %s" % ("all checks passed" if _failures == 0 else "%d checks failed" % _failures))
	quit(1 if _failures > 0 else 0)


func _check_items() -> void:
	# Every slot has at least one placeholder item to try it with.
	for slot in Equipment.SLOTS:
		var any := Items.IDS.any(func(item: String) -> bool: return Equipment.fits(item, slot))
		_check(any, "something can be worn in the %s slot" % slot)
	for item in Items.IDS:
		if Items.is_wearable(item):
			_check(Items.max_stack(item) == 1, "%s doesn't stack" % item)
			_check(Equipment.slot_for(item, {}) != "", "%s has a slot" % item)
	_check(Equipment.fits("leather_cap", "helm") and not Equipment.fits("leather_cap", "boots"), "a cap fits the helm slot only")
	_check(Equipment.fits("copper_ring", "ring_1") and Equipment.fits("copper_ring", "ring_2"), "a ring fits either ring slot")
	_check(not Equipment.fits("stone_axe", "off_hand") and not Equipment.fits("wood", "chest"), "tools and materials can't be worn")
	_check(not Equipment.fits("leather_cap", "hat") and not Equipment.fits("nonsense", "helm"), "unknown slots and items don't fit")
	_check(Equipment.slot_for("copper_ring", {}) == "ring_1", "the first ring goes on the first ring slot")
	_check(Equipment.slot_for("copper_ring", { "ring_1": "copper_ring" }) == "ring_2", "the second ring goes on the other hand")
	_check(Equipment.slot_for("wood", {}) == "", "materials have no slot")


func _check_equipping() -> void:
	var inv := Inventory.new(4)
	var gear := Equipment.new()
	inv.add("leather_cap", 1)
	inv.add("wood", 10)
	_check(not gear.equip(inv, 1, "helm"), "wood can't go on your head")
	_check(not gear.equip(inv, 0, "boots"), "a cap can't go on your feet")
	_check(not gear.equip(inv, 3, "helm") and not gear.equip(inv, 9, "helm"), "empty and missing slots equip nothing")
	_check(gear.equip(inv, 0, "helm") and gear.item_in("helm") == "leather_cap" and inv.slots[0] == null,
		"puts the cap on, out of the inventory")
	inv.slots[2] = { "item": "leather_cap", "count": 1 }
	_check(gear.equip(inv, 2, "helm") and inv.slots[2]["item"] == "leather_cap",
		"putting on another swaps the old one into its place")

	inv.slots[0] = { "item": "copper_ring", "count": 1 }
	inv.slots[3] = { "item": "copper_ring", "count": 1 }
	_check(gear.equip(inv, 0, "ring_1") and gear.equip(inv, 3, "ring_2"), "wears a ring on each hand")
	_check(gear.move("ring_1", "ring_2") and gear.item_in("ring_1") == "copper_ring", "moves rings between hands")
	_check(not gear.move("ring_1", "helm"), "a ring can't move to the helm slot")
	_check(not gear.move("boots", "helm"), "moving an empty slot does nothing")

	var full := Inventory.new(1)
	full.add("wood", 1)
	_check(not gear.unequip("helm", full), "taking off needs room in the inventory")
	_check(gear.item_in("helm") == "leather_cap", "and keeps it on when there isn't")
	_check(not gear.unequip("helm", full, 0), "won't take off onto a different item that doesn't fit the slot")
	var other := Inventory.new(2)
	_check(gear.unequip("helm", other, 1) and other.slots[1]["item"] == "leather_cap" and gear.item_in("helm") == "",
		"takes off into a chosen slot")
	_check(not gear.unequip("helm", other), "taking off an empty slot does nothing")
	_check(gear.take("ring_1") == "copper_ring" and gear.item_in("ring_1") == "", "takes a ring off to drop it")

	var loaded := Equipment.new()
	loaded.load_dict(JSON.parse_string(JSON.stringify(gear.to_dict())))
	_check(loaded.to_dict() == gear.to_dict(), "survives a round trip through JSON")
	loaded.load_dict({ "helm": "copper_ring", "boots": "leather_boots", "tail": "leather_cap", "chest": "gold" })
	_check(loaded.to_dict() == { "boots": "leather_boots" }, "drops misfits, unknown slots and unknown items")
	loaded.load_dict("junk")
	_check(loaded.to_dict().is_empty(), "ignores junk")


func _check_saving() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	var store := AccountStore.new(PATH)
	store.register("chris", "secret1")
	store.create_character("chris", "Ragnar", "dwarf")
	store.create_character("chris", "Astrid")
	_check(store.load_equipment("chris", "Ragnar").is_empty(), "a new character wears nothing")
	_check(store.save_equipment("chris", "ragnar", { "helm": "leather_cap", "ring_2": "copper_ring" }), "saves equipment")
	store.close()
	var reloaded := AccountStore.new(PATH)
	var gear := Equipment.new()
	gear.load_dict(reloaded.load_equipment("Chris", "Ragnar"))
	_check(gear.item_in("helm") == "leather_cap" and gear.item_in("ring_2") == "copper_ring", "equipment survives a reload")
	_check(reloaded.load_equipment("chris", "Astrid").is_empty(), "other characters keep their own equipment")
	reloaded.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func _check_sheet() -> void:
	var slots: Array = CharacterSheet.LAYOUT.keys()
	for slot in Equipment.SLOTS:
		_check(slot in slots, "the character sheet has a %s slot" % slot)
	_check("main_hand" in slots and slots.size() == Equipment.SLOTS.size() + 1, "and a main hand, and nothing else")
	var bounds := Rect2(Vector2.ZERO, CharacterSheet.SIZE)
	for i in slots.size():
		var rect: Rect2 = CharacterSheet.LAYOUT[slots[i]]
		_check(bounds.encloses(rect), "the %s slot is inside the sheet" % slots[i])
		for j in range(i + 1, slots.size()):
			_check(not rect.intersects(CharacterSheet.LAYOUT[slots[j]]),
				"the %s and %s slots don't overlap" % [slots[i], slots[j]])
	_check(CharacterSheet.fits("stone_axe", "main_hand") and not CharacterSheet.fits("leather_cap", "main_hand"),
		"only tools go in the main hand")


func _check_style() -> void:
	var panel := UiStyle.panel_style()
	var size := UiStyle.CORNER * 2 + UiStyle.TILE
	_check(panel.texture != null and panel.texture.get_width() == size, "draws the stone panel")
	_check(UiStyle.panel_style() == panel, "and only once")
	var image := panel.texture.get_image()
	var stone := image.get_pixel(size / 2, size / 2)
	var frame := image.get_pixel(size / 2, UiStyle.BAND / 8)
	_check(stone.v < 0.4, "the stone is dark (%.2f)" % stone.v)
	_check(frame.r > frame.b and frame.v > stone.v, "the frame is lighter, warmer metal")
	for rim in ["", "hover", "held"]:
		var slot := UiStyle.slot_style(rim, Items.color("wood"))
		_check(slot.texture != null and slot.texture.get_width() == 24, "draws the %s slot" % (rim if rim != "" else "plain"))


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: %s" % what)
