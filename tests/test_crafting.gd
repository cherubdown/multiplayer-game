extends SceneTree
## Checks the recipes and crafting rules without a network. Run from the
## project folder:
##   godot --headless --path . -s tests/test_crafting.gd
## Exits non-zero if any check fails.

const Items := preload("res://scripts/items.gd")
const Inventory := preload("res://scripts/inventory.gd")
const Recipes := preload("res://scripts/recipes.gd")

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ids := {}
	var valid := true
	for recipe in Recipes.all():
		valid = valid and not ids.has(recipe["id"]) and Items.is_valid(recipe["result"]) and recipe["count"] > 0 \
			and not recipe["ingredients"].is_empty()
		ids[recipe["id"]] = true
		for item in recipe["ingredients"]:
			valid = valid and Items.is_valid(item) and recipe["ingredients"][item] > 0
	_check(valid, "every recipe has a unique id and makes and uses real items")

	_check(Recipes.find("stone_sword")["ingredients"] == { "wood": 5, "stone": 5 }, "a stone sword takes 5 wood and 5 stone")
	_check(Recipes.find("stone_axe")["ingredients"] == { "wood": 5, "stone": 3 }, "a stone axe takes 5 wood and 3 stone")
	_check(Recipes.find("stone_pickaxe")["ingredients"] == { "wood": 5, "stone": 5 }, "a stone pickaxe takes 5 wood and 5 stone")
	_check(Recipes.find("nothing").is_empty(), "an unknown recipe isn't found")
	_check(Items.tool_type("stone_axe") == "axe" and Items.tool_type("stone_pickaxe") == "pickaxe" \
		and Items.tool_type("stone_sword") == "sword" and Items.tool_type("wood") == "", "tools know what they are")
	_check(Items.max_stack("stone_axe") == 1, "tools don't stack")
	for item in ["stone_axe", "stone_pickaxe", "stone_sword"]:
		_check(Items.icon(item) != null, "%s has an icon" % item)
		_check(Items.tool_mesh(item).get_surface_count() >= 2, "%s has a mesh to hold" % item)

	var inv := Inventory.new(4)
	inv.add("wood", 7)
	inv.add("stone", 2)
	_check(Recipes.missing(Recipes.find("stone_axe"), inv) == { "stone": 1 }, "says what's missing")
	_check(Recipes.missing(Recipes.find("stone_axe"), inv.to_array()) == { "stone": 1 }, "works on the client's slot array too")
	var before := inv.to_array()
	var err := Recipes.craft("stone_axe", inv)
	_check(err.contains("1 more Stone"), "won't craft without enough: %s" % err)
	_check(inv.to_array() == before, "a failed craft leaves the inventory alone")
	_check(Recipes.craft("nothing", inv) != "", "won't craft an unknown recipe")

	inv.add("stone", 4)
	err = Recipes.craft("stone_axe", inv)
	_check(err == "", "crafts a stone axe: %s" % err)
	_check(inv.count_of("stone_axe") == 1 and inv.count_of("wood") == 2 and inv.count_of("stone") == 3,
		"crafting uses up the ingredients and gives the tool")
	_check(not Recipes.can_craft(Recipes.find("stone_pickaxe"), inv), "can't craft a pickaxe with what's left")

	# Crafting frees the slots its ingredients were in, so a full inventory
	# can still craft if that leaves room.
	var full := Inventory.new(2)
	full.add("wood", 5)
	full.add("stone", 5)
	_check(Recipes.craft("stone_pickaxe", full) == "" and full.count_of("stone_pickaxe") == 1,
		"crafts into a slot its ingredients emptied")
	var packed := Inventory.new(2)
	packed.add("wood", 50)
	packed.add("stone", 50)
	before = packed.to_array()
	err = Recipes.craft("stone_sword", packed)
	_check(err.contains("No room"), "won't craft with no room for the result: %s" % err)
	_check(packed.to_array() == before, "nothing is used up when there's no room")

	var spread := Inventory.new(3)
	spread.slots = [{ "item": "wood", "count": 3 }, { "item": "stone", "count": 1 }, { "item": "wood", "count": 4 }]
	_check(spread.remove("wood", 5) == 5 and spread.count_of("wood") == 2, "takes items out across stacks")
	_check(spread.slots[2] == null and spread.slots[0]["count"] == 2, "empties the last stacks first")
	_check(spread.remove("stone", 9) == 1 and spread.slots[1] == null, "takes no more than there is")

	print("Crafting: %s" % ("all checks passed" if _failures == 0 else "%d checks failed" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: %s" % what)
