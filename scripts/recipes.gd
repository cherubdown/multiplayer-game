extends RefCounted
## Everything that can be crafted, and the rules for crafting it. Shared by the
## server, which does the crafting (see Session), and the crafting window,
## which shows what can be made from what's in the inventory.
##
## To add a recipe, add an entry to RECIPES: the item it makes (from
## scripts/items.gd), how many, and the items it uses up. The crafting window
## lists it and the server accepts it with no other changes. Recipes show in
## the order they're listed here.
##
## A character only knows a recipe once they've discovered every item it uses,
## that is, once each has been in their inventory at least once (see
## Session.inventory_updated()). Until then it isn't listed and the server
## won't craft it.

const Items := preload("res://scripts/items.gd")

const RECIPES := [
	{ "id": "wood_sword", "result": "wood_sword", "count": 1, "ingredients": { "wood": 5 } },
	{ "id": "stone_axe", "result": "stone_axe", "count": 1, "ingredients": { "wood": 5, "stone": 3 } },
	{ "id": "stone_pickaxe", "result": "stone_pickaxe", "count": 1, "ingredients": { "wood": 5, "stone": 5 } },
	{ "id": "stone_sword", "result": "stone_sword", "count": 1, "ingredients": { "wood": 5, "stone": 5 } },
]


## Every recipe, in order.
static func all() -> Array:
	return RECIPES


## The recipe with this id, or {} if there isn't one.
static func find(id: String) -> Dictionary:
	for recipe in RECIPES:
		if recipe["id"] == id:
			return recipe
	return {}


## Whether a character who has discovered `discovered` (item -> true) knows
## `recipe`.
static func is_unlocked(recipe: Dictionary, discovered: Dictionary) -> bool:
	if recipe.is_empty():
		return false
	for item in recipe["ingredients"]:
		if not discovered.has(item):
			return false
	return true


## The ids of every recipe a character who has discovered `discovered` knows,
## in order.
static func unlocked(discovered: Dictionary) -> Array:
	var ids := []
	for recipe in RECIPES:
		if is_unlocked(recipe, discovered):
			ids.append(recipe["id"])
	return ids


## How many more of each ingredient `inventory` needs before it can make
## `recipe`: item -> count, empty when it has everything. `inventory` is an
## Inventory or its slot array (as the client has it).
static func missing(recipe: Dictionary, inventory) -> Dictionary:
	var short := {}
	for item in recipe["ingredients"]:
		var have := _count(inventory, item)
		var need: int = recipe["ingredients"][item]
		if have < need:
			short[item] = need - have
	return short


static func can_craft(recipe: Dictionary, inventory) -> bool:
	return not recipe.is_empty() and missing(recipe, inventory).is_empty()


## Server side: uses up the ingredients in `inventory` (an Inventory) and puts
## the result in, if the character has discovered the recipe (see
## is_unlocked()). Returns "" on success, or why it couldn't, in which case the
## inventory is left as it was.
static func craft(id: String, inventory, discovered: Dictionary) -> String:
	var recipe := find(id)
	if recipe.is_empty():
		return "There's no recipe for that."
	if not is_unlocked(recipe, discovered):
		return "You haven't discovered that recipe yet."
	var short := missing(recipe, inventory)
	if not short.is_empty():
		var needs := []
		for item in short:
			needs.append("%d more %s" % [short[item], Items.display_name(item)])
		return "Needs %s." % " and ".join(needs)
	# Try it on a copy first, so a full inventory loses nothing.
	var trial = inventory.copy()
	for item in recipe["ingredients"]:
		trial.remove(item, recipe["ingredients"][item])
	if trial.add(recipe["result"], recipe["count"]) > 0:
		return "No room in your inventory for the %s." % Items.display_name(recipe["result"])
	inventory.slots = trial.slots
	return ""


static func _count(inventory, item: String) -> int:
	if inventory is Array:
		var total := 0
		for slot in inventory:
			if slot != null and slot["item"] == item:
				total += int(slot["count"])
		return total
	return inventory.count_of(item)
