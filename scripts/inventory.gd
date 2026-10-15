extends RefCounted
## A fixed number of slots, each empty (null) or holding a stack of one kind of
## item: { "item": id, "count": n }. Used for players' inventories and chests,
## on the server. Clients only ever see the plain slot array from to_array().

const Items := preload("res://scripts/items.gd")

var slots: Array = []


func _init(size: int) -> void:
	slots.resize(size)


func size() -> int:
	return slots.size()


func is_empty() -> bool:
	return slots.all(func(slot) -> bool: return slot == null)


## Puts `count` of `item` in, topping up existing stacks first, then filling
## empty slots. Returns how many didn't fit.
func add(item: String, count: int) -> int:
	if not Items.is_valid(item) or count <= 0:
		return count
	var stack_size := Items.max_stack(item)
	for slot in slots:
		if count == 0:
			break
		if slot != null and slot["item"] == item and slot["count"] < stack_size:
			var moved := mini(count, stack_size - slot["count"])
			slot["count"] += moved
			count -= moved
	for i in slots.size():
		if count == 0:
			break
		if slots[i] == null:
			var moved := mini(count, stack_size)
			slots[i] = { "item": item, "count": moved }
			count -= moved
	return count


## How many of `item` there are across every slot.
func count_of(item: String) -> int:
	var total := 0
	for slot in slots:
		if slot != null and slot["item"] == item:
			total += slot["count"]
	return total


## Takes up to `count` of `item` out, emptying the last stacks first. Returns
## how many were taken.
func remove(item: String, count: int) -> int:
	var taken := 0
	for i in range(slots.size() - 1, -1, -1):
		if taken >= count:
			break
		var slot = slots[i]
		if slot == null or slot["item"] != item:
			continue
		var moved := mini(count - taken, slot["count"])
		slot["count"] -= moved
		taken += moved
		if slot["count"] == 0:
			slots[i] = null
	return taken


## A separate copy with the same contents, to try a change on first.
func copy():
	var other = get_script().new(slots.size())
	other.slots = to_array()
	return other


## Moves as much of slot `index` as fits into `other`. Returns how many moved.
func move_to(index: int, other) -> int:
	if not has_slot(index) or slots[index] == null:
		return 0
	var stack: Dictionary = slots[index]
	var left: int = other.add(stack["item"], stack["count"])
	var moved: int = stack["count"] - left
	if left == 0:
		slots[index] = null
	else:
		stack["count"] = left
	return moved


## Moves the stack in slot `from` to slot `to` of `target`, which may be this
## inventory. Onto the same item it tops that stack up (leaving whatever
## doesn't fit); onto a different item the two swap places. Returns whether
## anything changed.
func move_slot(from: int, target, to: int) -> bool:
	if not has_slot(from) or not target.has_slot(to) or slots[from] == null:
		return false
	if target == self and from == to:
		return false
	var stack: Dictionary = slots[from]
	var other = target.slots[to]
	if other == null or other["item"] != stack["item"]:
		target.slots[to] = stack
		slots[from] = other
		return true
	var moved := mini(stack["count"], Items.max_stack(stack["item"]) - other["count"])
	if moved <= 0:
		return false
	other["count"] += moved
	stack["count"] -= moved
	if stack["count"] == 0:
		slots[from] = null
	return true


## Empties a slot and returns what was in it, or {} if it was empty.
func take(index: int) -> Dictionary:
	if not has_slot(index) or slots[index] == null:
		return {}
	var stack: Dictionary = slots[index]
	slots[index] = null
	return stack


func has_slot(index) -> bool:
	return index is int and index >= 0 and index < slots.size()


## A copy of the slots, safe to send over the network or save as JSON.
func to_array() -> Array:
	return slots.map(func(slot): return null if slot == null else slot.duplicate())


## Loads slots saved by to_array(). Unknown items and bad counts are dropped,
## and anything past this inventory's size is ignored.
func load_array(data) -> void:
	slots.fill(null)
	if not data is Array:
		return
	for i in mini(data.size(), slots.size()):
		var slot = data[i]
		if not slot is Dictionary or not Items.is_valid(str(slot.get("item", ""))):
			continue
		var count := int(slot.get("count", 0))
		if count > 0:
			slots[i] = { "item": str(slot["item"]), "count": mini(count, Items.max_stack(slot["item"])) }
