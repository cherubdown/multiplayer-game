extends RefCounted
## The hotbar: four slots along the bottom of the screen for the tools and
## weapons a character switches between, picked with the 1 to 4 keys (or the
## mouse wheel) to hold in the main hand. Used on the server, which owns it
## (see Session); clients only ever see the plain array from to_array().
##
## A slot only names an item: the tool itself stays in the inventory, like
## the main hand (Session.hold()). A slot keeps its tool while it's away, such
## as in a chest, and it can be held again once it's back. Each tool is on the
## hotbar at most once.

const Items := preload("res://scripts/items.gd")

const SIZE := 4

## The item id in each slot, "" for an empty one.
var slots: Array[String] = []


func _init() -> void:
	slots.resize(SIZE)
	slots.fill("")


static func has_slot(index) -> bool:
	return index is int and index >= 0 and index < SIZE


## The item in slot `index`, or "".
func item_in(index: int) -> String:
	return slots[index] if has_slot(index) else ""


## Puts `item` in slot `index` ("" empties it). A tool already in another slot
## swaps places with what was here. Only tools fit. Returns whether anything
## changed.
func set_slot(index: int, item: String) -> bool:
	if not has_slot(index) or (item != "" and not Items.is_tool_item(item)) or slots[index] == item:
		return false
	var was := slots.find(item) if item != "" else -1
	if was >= 0:
		slots[was] = slots[index]
	slots[index] = item
	return true


## Swaps two slots. Returns whether anything changed.
func swap(from: int, to: int) -> bool:
	if not has_slot(from) or not has_slot(to) or from == to or slots[from] == slots[to]:
		return false
	var item := slots[from]
	slots[from] = slots[to]
	slots[to] = item
	return true


## Puts `item` in the first empty slot if it isn't on the hotbar yet. Returns
## whether anything changed.
func add(item: String) -> bool:
	if not Items.is_tool_item(item) or item in slots:
		return false
	var free := slots.find("")
	return free >= 0 and set_slot(free, item)


## A copy, safe to send over the network or save as JSON.
func to_array() -> Array:
	var copy := []
	copy.append_array(slots)
	return copy


## Loads what to_array() saved. Unknown items, anything that isn't a tool,
## repeats and anything past the last slot are dropped.
func load_array(data) -> void:
	slots.fill("")
	if not data is Array:
		return
	for i in mini(data.size(), SIZE):
		var item := str(data[i]) if data[i] != null else ""
		if Items.is_tool_item(item) and not item in slots:
			slots[i] = item
