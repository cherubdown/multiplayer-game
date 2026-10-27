extends VBoxContainer
## The character sheet: the local character's name and race over their
## equipment slots, laid out like Diablo II's. Helm in the middle at the top
## with the shoulders and amulet either side of it, the main hand and off hand
## down the sides, the chest in the middle, then the hands, a ring, the belt,
## the other ring and the boots along the bottom, with the leggings under the
## belt.
##
## The main hand is the tool held in the hand (Session.hold()), which stays in
## the inventory; the rest is what's worn (see scripts/equipment.gd).
##
## Shown beside the inventory by scripts/inventory_ui.gd, which owns dragging
## between the two. Drag an item from the inventory onto a slot it fits to put
## it on, an equipped one back onto the inventory to take it off, or off the
## panels to drop it. Right-click an equipped item to take it off. Only sends
## requests: the server owns what's worn (see Session).

const Items := preload("res://scripts/items.gd")
const Equipment := preload("res://scripts/equipment.gd")
const Races := preload("res://scripts/races.gd")
const UiStyle := preload("res://scripts/ui_style.gd")

## Where each slot sits in the sheet, and its size: x, y, width, height.
const LAYOUT := {
	"main_hand": Rect2(0, 24, 72, 140),
	"shoulders": Rect2(76, 8, 52, 52),
	"helm": Rect2(144, 0, 64, 64),
	"amulet": Rect2(224, 12, 44, 44),
	"off_hand": Rect2(280, 24, 72, 140),
	"chest": Rect2(136, 72, 80, 112),
	"hands": Rect2(0, 196, 72, 72),
	"ring_1": Rect2(88, 196, 40, 40),
	"belt": Rect2(136, 194, 80, 40),
	"ring_2": Rect2(224, 196, 40, 40),
	"boots": Rect2(280, 196, 72, 72),
	"leggings": Rect2(136, 244, 80, 72),
}
const SIZE := Vector2(352, 316)

var _name_label: Label
var _race_label: Label
var _board: Control
## Slot -> its button, so tests can find them.
var slot_buttons := {}


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiStyle.title(_name_label, 22)
	add_child(_name_label)
	_race_label = Label.new()
	_race_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_race_label.add_theme_color_override("font_color", Color(0.78, 0.76, 0.7))
	add_child(_race_label)
	_board = Control.new()
	_board.custom_minimum_size = SIZE + Vector2(0, 8)
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_board)
	refresh(null)


## Redraws every slot from what Session says is worn and held. `player` is the
## local player node, for the race line, or null.
func refresh(player: Node) -> void:
	_name_label.text = Session.character_name
	_race_label.text = Races.describe(player.race, player.sex) if player != null else ""
	_race_label.visible = _race_label.text != ""
	for child in _board.get_children():
		_board.remove_child(child)
		child.queue_free()
	slot_buttons.clear()
	for slot in LAYOUT:
		var button := _slot_button(slot)
		var rect: Rect2 = LAYOUT[slot]
		button.position = rect.position + Vector2(0, 8)
		button.size = rect.size
		_board.add_child(button)
		slot_buttons[slot] = button


## What's in a slot of the sheet: the held tool for "main_hand", else what's
## worn. "" if nothing.
static func item_in(slot: String) -> String:
	return Session.held_item if slot == "main_hand" else str(Session.equipment.get(slot, ""))


static func slot_name(slot: String) -> String:
	return "Main hand" if slot == "main_hand" else Equipment.SLOT_NAMES.get(slot, slot)


## Whether `item` can go in `slot` of the sheet.
static func fits(item: String, slot: String) -> bool:
	return Items.is_tool_item(item) if slot == "main_hand" else Equipment.fits(item, slot)


func _slot_button(slot: String) -> Button:
	var item := item_in(slot)
	var button := Button.new()
	button.name = "Slot_" + slot
	button.focus_mode = Control.FOCUS_NONE
	button.clip_text = true
	var tint := Items.color(item) if item != "" else Color.TRANSPARENT
	button.add_theme_stylebox_override("normal", UiStyle.slot_style("", tint))
	button.add_theme_stylebox_override("pressed", UiStyle.slot_style("", tint))
	button.add_theme_stylebox_override("hover", UiStyle.slot_style("hover", tint))
	if item == "":
		# An empty slot says what goes in it, faintly.
		button.text = slot_name(slot)
		button.add_theme_font_size_override("font_size", 11 if LAYOUT[slot].size.x < 50 else 13)
		for state in ["font_color", "font_hover_color", "font_pressed_color"]:
			button.add_theme_color_override(state, Color(0.5, 0.48, 0.42, 0.7))
		button.tooltip_text = "%s\n(Empty. Drag %s here.)" % [slot_name(slot),
			"a tool" if slot == "main_hand" else "something that fits"]
	else:
		var icon := Items.icon(item)
		if icon != null:
			button.icon = icon
			button.expand_icon = true
			button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		else:
			button.text = Items.display_name(item)
		button.tooltip_text = "%s\n%s\n(%s. Right-click to take it off.)" % [Items.display_name(item),
			Items.description(item), "In your hand" if slot == "main_hand" else "Worn: " + slot_name(slot)]
	button.gui_input.connect(_on_slot_input.bind(slot))
	button.set_drag_forwarding(
		_slot_drag_data.bind(button, slot),
		_can_drop_on.bind(slot),
		_drop_on.bind(slot))
	return button


## Right-clicking takes off what's in the slot.
func _on_slot_input(event: InputEvent, slot: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if item_in(slot) != "":
			if slot == "main_hand":
				Session.hold("")
			else:
				Session.unequip(slot)
		get_viewport().set_input_as_handled()


# --- Drag and drop ----------------------------------------------------------
# Dragged from here, the data is { "gear": slot }. Dropped here, an inventory
# stack is { "from_chest": false, "slot": int } (see scripts/inventory_ui.gd).

func _slot_drag_data(_at: Vector2, button: Button, slot: String) -> Variant:
	var item := item_in(slot)
	if item == "":
		return null
	var preview := Control.new()
	var icon := TextureRect.new()
	icon.texture = Items.icon(item)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.size = Vector2(56, 56)
	icon.position = -icon.size * 0.5
	icon.modulate.a = 0.85
	preview.add_child(icon)
	button.set_drag_preview(preview)
	return { "gear": slot }


func _can_drop_on(_at: Vector2, data, slot: String) -> bool:
	if not data is Dictionary:
		return false
	if data.has("gear"):
		return data["gear"] != slot and data["gear"] != "main_hand" and slot != "main_hand" \
			and fits(item_in(data["gear"]), slot)
	if data.get("from_chest", true) or not data.get("slot") is int:
		return false
	var index: int = data["slot"]
	if index < 0 or index >= Session.inventory.size() or Session.inventory[index] == null:
		return false
	return fits(Session.inventory[index]["item"], slot)


func _drop_on(_at: Vector2, data, slot: String) -> void:
	if data.has("gear"):
		Session.move_equipped(data["gear"], slot)
	elif slot == "main_hand":
		Session.hold(Session.inventory[data["slot"]]["item"])
	else:
		Session.equip(data["slot"], slot)
