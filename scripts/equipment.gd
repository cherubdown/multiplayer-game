extends RefCounted
## What a character wears, one item per slot of the character sheet, laid out
## like Diablo II's: helm, amulet, shoulders, chest, hands, belt, leggings,
## boots, two rings and an off hand. Used on the server, which owns it (see
## Session); clients only ever see the plain dictionary from to_dict().
##
## An item fits a slot when its "equip" entry in scripts/items.gd names that
## slot. Both ring slots take a "ring". The main hand isn't here: it's the tool
## held in the hand (Session.hold()), which stays in the inventory.
##
## Equipping takes the item out of an inventory slot and puts whatever was worn
## there back in its place; taking it off puts it back in the inventory.

const Items := preload("res://scripts/items.gd")

## Every slot, in the order the character sheet lists them.
const SLOTS: Array[String] = ["helm", "amulet", "shoulders", "chest", "hands", "belt", "leggings",
	"boots", "ring_1", "ring_2", "off_hand"]

const SLOT_NAMES := {
	"helm": "Helm",
	"amulet": "Amulet",
	"shoulders": "Shoulders",
	"chest": "Chest",
	"hands": "Hands",
	"belt": "Belt",
	"leggings": "Leggings",
	"boots": "Boots",
	"ring_1": "Ring",
	"ring_2": "Ring",
	"off_hand": "Off hand",
}

## Slot -> item id, for the slots with something in them.
var worn := {}


static func is_slot(slot) -> bool:
	return slot is String and slot in SLOTS


## Whether `item` can be worn in `slot`.
static func fits(item: String, slot: String) -> bool:
	if not is_slot(slot) or not Items.is_wearable(item):
		return false
	return Items.equip_slot(item) == ("ring" if slot.begins_with("ring_") else slot)


## The slot right-clicking `item` puts it in: its own, or for a ring the first
## free ring slot. "" if it can't be worn. `worn_now` is slot -> item, as
## to_dict() gives it.
static func slot_for(item: String, worn_now: Dictionary) -> String:
	var kind := Items.equip_slot(item)
	if kind == "ring":
		return "ring_2" if worn_now.has("ring_1") and not worn_now.has("ring_2") else "ring_1"
	return kind if is_slot(kind) else ""


## The item worn in `slot`, or "".
func item_in(slot: String) -> String:
	return worn.get(slot, "")


## Puts on the item in slot `index` of `inv` (an Inventory) in `slot`. What was
## worn there goes back in the inventory where the item came from. Returns
## whether anything changed.
func equip(inv, index: int, slot: String) -> bool:
	if not inv.has_slot(index) or inv.slots[index] == null:
		return false
	var stack: Dictionary = inv.slots[index]
	var item: String = stack["item"]
	if not fits(item, slot):
		return false
	var old := item_in(slot)
	if stack["count"] > 1:
		# Only one comes off the stack, so what was worn needs room elsewhere.
		if old != "" and inv.copy().add(old, 1) > 0:
			return false
		stack["count"] -= 1
		if old != "":
			inv.add(old, 1)
	else:
		inv.slots[index] = null if old == "" else { "item": old, "count": 1 }
	worn[slot] = item
	return true


## Takes off what's worn in `slot` into slot `index` of `inv`, or wherever it
## fits if `index` is -1. Onto something else that fits `slot`, the two swap.
## Returns whether anything changed.
func unequip(slot: String, inv, index := -1) -> bool:
	var item := item_in(slot)
	if item == "":
		return false
	if index == -1:
		if inv.add(item, 1) > 0:
			return false
	elif not inv.has_slot(index):
		return false
	else:
		var there = inv.slots[index]
		if there == null:
			inv.slots[index] = { "item": item, "count": 1 }
		elif there["item"] == item and there["count"] < Items.max_stack(item):
			there["count"] += 1
		elif there["count"] == 1 and fits(there["item"], slot):
			inv.slots[index] = { "item": item, "count": 1 }
			worn[slot] = there["item"]
			return true
		else:
			return false
	worn.erase(slot)
	return true


## Moves what's worn in `from` to `to`, swapping with what's there if that fits
## `from` (such as one ring hand to the other). Returns whether anything
## changed.
func move(from: String, to: String) -> bool:
	var item := item_in(from)
	if from == to or item == "" or not fits(item, to):
		return false
	var other := item_in(to)
	if other != "" and not fits(other, from):
		return false
	worn[to] = item
	if other == "":
		worn.erase(from)
	else:
		worn[from] = other
	return true


## Takes off what's worn in `slot` and returns it, or "" if nothing was.
func take(slot: String) -> String:
	var item := item_in(slot)
	worn.erase(slot)
	return item


## A copy, safe to send over the network or save as JSON.
func to_dict() -> Dictionary:
	return worn.duplicate()


## Loads what to_dict() saved. Unknown slots and items, and items in slots
## they don't fit, are dropped.
func load_dict(data) -> void:
	worn.clear()
	if not data is Dictionary:
		return
	for slot in data:
		var item := str(data[slot])
		if is_slot(slot) and Items.is_valid(item) and fits(item, slot):
			worn[slot] = item
