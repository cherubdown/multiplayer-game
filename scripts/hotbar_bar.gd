extends PanelContainer
## The hotbar along the bottom of the screen: four slots for tools and weapons
## (see scripts/hotbar.gd). Keys 1 to 4 take the tool in that slot in hand, or
## put it away if it's already there; the mouse wheel steps through them. The
## slot in hand has a lit rim, and a slot whose tool isn't in the inventory
## just now (such as one left in a chest) is greyed out.
##
## With the inventory open, drag a tool from it onto a slot to put it there,
## drag between slots to swap them, or drag one off the hotbar (or right-click
## it) to empty it. Left-clicking a slot takes its tool in hand. Taking a tool
## in hand any other way puts it on the hotbar if there's room. Part of the
## HUD (see scripts/hud.gd). Only sends requests: the server owns the hotbar
## (see Session).

const Items := preload("res://scripts/items.gd")
const Hotbar := preload("res://scripts/hotbar.gd")
const UiStyle := preload("res://scripts/ui_style.gd")
const Sounds := preload("res://scripts/sounds.gd")

const SLOT_SIZE := Vector2(64, 64)

var _row: HBoxContainer
## The slot buttons, in order, so tests can find them.
var slot_buttons: Array[Button] = []


func _ready() -> void:
	add_theme_stylebox_override("panel", UiStyle.panel_style())
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 6)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	Session.hotbar_changed.connect(func(_slots: Array) -> void: refresh())
	Session.inventory_changed.connect(func(_slots: Array) -> void: refresh())
	Session.held_changed.connect(func(_item: String) -> void: refresh())
	refresh()


func _input(event: InputEvent) -> void:
	# Only while playing, not while a menu or the inventory has the mouse.
	if Session.character_name == "" or not is_visible_in_tree() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	for i in Hotbar.SIZE:
		if event.is_action_pressed("hotbar_%d" % (i + 1), false, true):
			if not Session.use_hotbar(i):
				Sounds.play_ui(self, "error", -6.0)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var next := next_slot(1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1)
		if next >= 0:
			Session.use_hotbar(next)
		get_viewport().set_input_as_handled()


## The slot holding the tool in hand, or -1.
static func selected() -> int:
	return Session.hotbar.find(Session.held_item) if Session.held_item != "" else -1


## Whether the tool in hotbar slot `index` is in the inventory to be held.
static func ready_to_hold(index: int) -> bool:
	var item: String = Session.hotbar[index] if index >= 0 and index < Session.hotbar.size() else ""
	return item != "" and Session.inventory.any(
		func(slot) -> bool: return slot != null and slot["item"] == item)


## The next slot after the one in hand, `step` 1 to the right or -1 to the
## left and wrapping round, whose tool can be held. -1 if there's none (or
## the one in hand is the only one).
static func next_slot(step: int) -> int:
	var from := selected()
	var at := from if from >= 0 else (-1 if step > 0 else Hotbar.SIZE)
	for _i in Hotbar.SIZE:
		at = posmod(at + step, Hotbar.SIZE)
		if at == from:
			return -1
		if ready_to_hold(at):
			return at
	return -1


## Redraws every slot from what Session says.
func refresh() -> void:
	for child in _row.get_children():
		_row.remove_child(child)
		child.queue_free()
	slot_buttons.clear()
	for i in Hotbar.SIZE:
		var button := _slot_button(i)
		_row.add_child(button)
		slot_buttons.append(button)


func _slot_button(index: int) -> Button:
	var item: String = Session.hotbar[index] if index < Session.hotbar.size() else ""
	var button := Button.new()
	button.name = "Hotbar_%d" % (index + 1)
	button.custom_minimum_size = SLOT_SIZE
	button.focus_mode = Control.FOCUS_NONE
	var held := item != "" and item == Session.held_item
	var tint := Items.color(item) if item != "" else Color.TRANSPARENT
	var rim := "held" if held else ""
	for state in ["normal", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, UiStyle.slot_style(rim, tint))
	button.add_theme_stylebox_override("hover", UiStyle.slot_style(rim if held else "hover", tint))
	if item == "":
		button.tooltip_text = "Hotbar slot %d\n(Empty. Drag a tool or weapon here from your inventory.)" % (index + 1)
	else:
		var icon := Items.icon(item)
		if icon != null:
			button.icon = icon
			button.expand_icon = true
			button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		else:
			button.text = Items.display_name(item)
			button.clip_text = true
		var state := "In your hand" if held else ("Press %d to hold it" % (index + 1) if ready_to_hold(index) \
			else "Not in your inventory")
		button.tooltip_text = "%s\n%s\n(%s. Right-click to take it off the hotbar.)" \
			% [Items.display_name(item), Items.description(item), state]
		if not ready_to_hold(index):
			button.self_modulate.a = 0.4
	var key := Label.new()
	key.text = str(index + 1)
	key.position = Vector2(6, 2)
	key.add_theme_font_size_override("font_size", 14)
	key.add_theme_color_override("font_color", UiStyle.TITLE_COLOR if held else Color(0.8, 0.78, 0.7))
	key.add_theme_constant_override("outline_size", 4)
	key.add_theme_color_override("font_outline_color", Color.BLACK)
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(key)
	button.pressed.connect(_on_slot_pressed.bind(index))
	button.gui_input.connect(_on_slot_input.bind(index))
	button.set_drag_forwarding(
		_slot_drag_data.bind(button, index),
		_can_drop_on.bind(index),
		_drop_on.bind(index))
	return button


## Left-clicking a slot takes its tool in hand, or puts it away.
func _on_slot_pressed(index: int) -> void:
	if not Session.use_hotbar(index) and Session.hotbar[index] != "":
		Sounds.play_ui(self, "error", -6.0)


## Right-clicking a slot empties it.
func _on_slot_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if index < Session.hotbar.size() and Session.hotbar[index] != "":
			Session.set_hotbar_slot(index, "")
		get_viewport().set_input_as_handled()


# --- Drag and drop ----------------------------------------------------------
# Dragged from here, the data is { "hotbar": index }. Dropped here, an
# inventory stack is { "from_chest": false, "slot": int } (see
# scripts/inventory_ui.gd), and the character sheet's main hand is
# { "gear": "main_hand" } (see scripts/character_sheet.gd).

func _slot_drag_data(_at: Vector2, button: Button, index: int) -> Variant:
	var item: String = Session.hotbar[index] if index < Session.hotbar.size() else ""
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
	return { "hotbar": index }


## The tool `data` would put on the hotbar, or "" if it isn't one.
static func _dropped_item(data) -> String:
	if not data is Dictionary:
		return ""
	if data.get("gear") == "main_hand":
		return Session.held_item
	if data.get("from_chest", true) or not data.get("slot") is int:
		return ""
	var index: int = data["slot"]
	if index < 0 or index >= Session.inventory.size() or Session.inventory[index] == null:
		return ""
	var item: String = Session.inventory[index]["item"]
	return item if Items.is_tool_item(item) else ""


func _can_drop_on(_at: Vector2, data, index: int) -> bool:
	if data is Dictionary and data.get("hotbar") is int:
		return data["hotbar"] != index
	return _dropped_item(data) != ""


func _drop_on(_at: Vector2, data, index: int) -> void:
	if data is Dictionary and data.get("hotbar") is int:
		Session.swap_hotbar(data["hotbar"], index)
	else:
		Session.set_hotbar_slot(index, _dropped_item(data))
