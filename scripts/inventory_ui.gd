extends CanvasLayer
## The local player's inventory screen with the crafting window beside it, the
## chest screen, and the on-screen prompt. Added to the world on every peer
## that has a player (not a dedicated server).
##
## Tab (or I) shows the inventory, with what can be crafted on the right (see
## scripts/recipes.gd). Only recipes the character has discovered are listed;
## a notice pops up at the top of the screen when one is discovered. E picks up the nearest item, picks the nearest plant
## (see scripts/forage.gd) or opens the nearest chest. Drag a stack onto
## another slot to move it (in the inventory, in the chest or between the two),
## or off the panels to drop it on the ground; with a chest open, the chest
## takes the crafting window's place and clicking a stack sends it across.
## Right-click a tool to hold it (or put it away), then left-click in the world
## to swing it at the tree or rock in reach (see scripts/harvestables.gd), or
## with a weapon at the enemy in reach (see scripts/big_frog.gd).
## Hovering a stack says what it is. Esc, Tab or E closes the screen again.
## All of it only sends requests: the server owns every inventory (see Session
## and scripts/chest.gd).

const Items := preload("res://scripts/items.gd")
const Recipes := preload("res://scripts/recipes.gd")
const Harvestables := preload("res://scripts/harvestables.gd")
const BigFrog := preload("res://scripts/big_frog.gd")

const COLUMNS := 5

var _prompt: Label
var _screen: Control
## Behind the panels: dropping a dragged stack here puts it on the ground.
var _drop_zone: Control
var _inventory_grid: GridContainer
var _chest_panel: Control
var _chest_grid: GridContainer
var _hint: Label
var _crafting_panel: Control
var _recipe_list: VBoxContainer
## The last thing the server said about crafting, shown under the recipes.
var _craft_message: Label
## Pops up at the top of the screen when recipes are discovered.
var _discovery: PanelContainer
var _discovery_heading: Label
var _discovery_list: VBoxContainer
var _discovery_tween: Tween
## The chest whose screen is showing, or null.
var _chest: Node
## Time.get_ticks_msec() of the last swing, so holding the button doesn't spam.
var _last_swing := -100000


func _ready() -> void:
	_build()
	Session.inventory_changed.connect(func(_slots: Array) -> void: _refresh())
	Session.held_changed.connect(func(_item: String) -> void: _refresh())
	Session.craft_finished.connect(_on_craft_finished)
	Session.recipes_changed.connect(_on_recipes_changed)
	Session.left_world.connect(_close)
	Session.leaving_world.connect(_close)
	for chest in get_tree().get_nodes_in_group("interactable"):
		_watch_chest(chest)
	get_tree().node_added.connect(_watch_chest)
	_close()


func _watch_chest(node: Node) -> void:
	if node.has_signal("contents_changed") and not node.contents_changed.is_connected(_on_chest_contents):
		node.contents_changed.connect(_on_chest_contents.bind(node))
		node.closed.connect(_on_chest_closed.bind(node))


func _process(_delta: float) -> void:
	var player := _local_player()
	if _chest != null and (player == null or _distance(player, _chest) > get_parent().INTERACT_RANGE + 1.0):
		_chest.close()
	var target := _target() if not _screen.visible else null
	var text := ""
	if target != null:
		text = "[E] %s" % target.prompt()
	elif not _screen.visible:
		var harvestables: Node = get_parent().get("harvestables")
		var enemy := _enemy_target()
		var index := _harvest_target()
		if enemy != null:
			text = enemy.prompt_for(Session.held_item)
		elif index >= 0:
			text = harvestables.prompt_for(index, Session.held_item)
	_prompt.visible = text != ""
	_prompt.text = text


func _input(event: InputEvent) -> void:
	if Session.character_name == "" or event.is_echo():
		return
	if _screen.visible:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("inventory") \
				or event.is_action_pressed("interact"):
			_close()
			get_viewport().set_input_as_handled()
		return
	# Only while playing, not while the Esc menu is up.
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event.is_action_pressed("inventory"):
		_open(null)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact"):
		var target := _target()
		if target != null:
			target.interact()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("attack"):
		_swing()


## Swings the held tool: a weapon at the enemy in reach if there is one,
## otherwise at the tree or rock in reach if there is one.
func _swing() -> void:
	var harvestables: Node = get_parent().get("harvestables")
	var player := _local_player()
	if Session.held_item == "" or harvestables == null or player == null:
		return
	var now := Time.get_ticks_msec()
	if now - _last_swing < int(Harvestables.SWING_SECONDS * 1000.0):
		return
	# Attacking takes stamina; without enough the swing doesn't happen (the
	# server checks too).
	if Items.is_weapon(Session.held_item) and player.stamina < player.ATTACK_STAMINA:
		return
	_last_swing = now
	var yaw: float = player.get_node("PlayerInput").yaw
	var enemy := _enemy_target()
	if enemy != null and Items.is_weapon(Session.held_item):
		enemy.attack(yaw)
	else:
		harvestables.swing(_harvest_target(), yaw)


## The nearest living enemy in the local player's reach, or null.
func _enemy_target() -> Node3D:
	var player := _local_player()
	if player == null:
		return null
	var best: Node3D = null
	var best_gap := BigFrog.REACH
	for enemy: Node3D in get_tree().get_nodes_in_group("enemies"):
		if not enemy.is_alive():
			continue
		var gap: float = enemy.gap_to(player.global_position)
		if gap <= best_gap:
			best = enemy
			best_gap = gap
	return best


## The standing tree or rock in the local player's reach, or -1.
func _harvest_target() -> int:
	var harvestables: Node = get_parent().get("harvestables")
	var player := _local_player()
	if harvestables == null or player == null:
		return -1
	return harvestables.nearest(player.global_position, Harvestables.REACH)


## The nearest thing in reach of the local player that E would use, or null.
func _target() -> Node3D:
	var player := _local_player()
	if player == null:
		return null
	var best: Node3D = null
	var best_distance: float = get_parent().INTERACT_RANGE
	for node in get_tree().get_nodes_in_group("interactable"):
		var distance := _distance(player, node)
		if distance <= best_distance:
			best = node
			best_distance = distance
	var forage: Node = get_parent().get("forage")
	if forage != null:
		var plant: Node3D = forage.nearest_plant(player.global_position, best_distance)
		if plant != null:
			best = plant
	return best


func _local_player() -> Node3D:
	if Session.character_name == "":
		return null
	return get_parent().get_node_or_null("Players/%d" % multiplayer.get_unique_id()) as Node3D


func _distance(a: Node3D, b: Node3D) -> float:
	return a.global_position.distance_to(b.global_position)


# --- Showing and hiding -----------------------------------------------------

func _open(chest: Node) -> void:
	_chest = chest
	_screen.visible = true
	_chest_panel.visible = chest != null
	_crafting_panel.visible = chest == null
	_craft_message.text = ""
	_hint.text = "Drag stacks between slots, or click one to send it across. Drag off the panels to drop it." \
		if chest != null else "Drag stacks to rearrange them, or off the panel to drop them. Right-click a tool to hold it."
	_refresh()
	_set_mouse_free(true)


func _close() -> void:
	if _chest != null:
		var chest := _chest
		_chest = null
		chest.close()
	if _screen != null and _screen.visible:
		_screen.visible = false
		_set_mouse_free(false)


func _on_chest_contents(_slots: Array, chest: Node) -> void:
	if _chest != chest:
		_open(chest)
	else:
		_refresh()


func _on_chest_closed(chest: Node) -> void:
	if _chest == chest:
		_chest = null
		_close()


func _set_mouse_free(free: bool) -> void:
	if DisplayServer.get_name() == "headless" or Session.character_name == "":
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if free else Input.MOUSE_MODE_CAPTURED


# --- Drawing ----------------------------------------------------------------

func _refresh() -> void:
	_fill(_inventory_grid, Session.inventory, false)
	if _chest != null:
		_fill(_chest_grid, _chest.contents, true)
	else:
		_fill_recipes()


## One row per discovered recipe: what it makes, what it takes (each
## ingredient showing how many you have of how many it needs) and a Craft
## button that only works when you have everything.
func _fill_recipes() -> void:
	for child in _recipe_list.get_children():
		_recipe_list.remove_child(child)
		child.queue_free()
	if Session.recipes.is_empty():
		var none := Label.new()
		none.text = "No recipes yet. Gather materials to discover what you can make with them."
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.custom_minimum_size.x = 296
		none.add_theme_color_override("font_color", Color(0.7, 0.7, 0.68))
		_recipe_list.add_child(none)
	for recipe in Recipes.all():
		if not recipe["id"] in Session.recipes:
			continue
		var result: String = recipe["result"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.tooltip_text = "%s\n%s" % [Items.display_name(result), Items.description(result)]
		var icon := TextureRect.new()
		icon.texture = Items.icon(result)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(48, 48)
		icon.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(icon)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(info)
		var title := Label.new()
		title.text = Items.display_name(result) + (" x%d" % recipe["count"] if recipe["count"] > 1 else "")
		info.add_child(title)
		var needs := HBoxContainer.new()
		needs.add_theme_constant_override("separation", 10)
		info.add_child(needs)
		var short := Recipes.missing(recipe, Session.inventory)
		for item in recipe["ingredients"]:
			var need: int = recipe["ingredients"][item]
			var chip := HBoxContainer.new()
			chip.add_theme_constant_override("separation", 3)
			chip.tooltip_text = Items.display_name(item)
			chip.mouse_filter = Control.MOUSE_FILTER_PASS
			var chip_icon := TextureRect.new()
			chip_icon.texture = Items.icon(item)
			chip_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			chip_icon.custom_minimum_size = Vector2(20, 20)
			chip.add_child(chip_icon)
			var amount := Label.new()
			amount.text = "%d/%d" % [need - short.get(item, 0), need]
			amount.add_theme_color_override("font_color",
				Color(1.0, 0.45, 0.4) if short.has(item) else Color(0.6, 0.9, 0.55))
			chip.add_child(amount)
			needs.add_child(chip)
		var craft := Button.new()
		craft.name = "Craft_" + recipe["id"]
		craft.text = "Craft"
		craft.focus_mode = Control.FOCUS_NONE
		craft.disabled = not short.is_empty()
		craft.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		craft.pressed.connect(Session.craft.bind(recipe["id"]))
		row.add_child(craft)
		_recipe_list.add_child(row)


## Refreshes the list and, for recipes just discovered, pops up a notice
## naming each.
func _on_recipes_changed(_recipe_ids: Array, new_ids: Array) -> void:
	_refresh()
	if new_ids.is_empty():
		return
	for child in _discovery_list.get_children():
		_discovery_list.remove_child(child)
		child.queue_free()
	for id in new_ids:
		var result: String = Recipes.find(id).get("result", id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var icon := TextureRect.new()
		icon.texture = Items.icon(result)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(32, 32)
		row.add_child(icon)
		var label := Label.new()
		label.text = Items.display_name(result)
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(label)
		_discovery_list.add_child(row)
	_discovery_heading.text = "New recipe discovered!" if new_ids.size() == 1 else "New recipes discovered!"
	if _discovery_tween != null:
		_discovery_tween.kill()
	_discovery.visible = true
	_discovery.modulate.a = 1.0
	_discovery_tween = create_tween()
	_discovery_tween.tween_interval(4.0)
	_discovery_tween.tween_property(_discovery, "modulate:a", 0.0, 1.0)
	_discovery_tween.tween_callback(_discovery.hide)


## Whether the recipe-discovered notice is up, and what it names.
func discovery_shown() -> Array:
	if not _discovery.visible:
		return []
	return _discovery_list.get_children().map(func(row: Node) -> String: return row.get_child(1).text)


func _on_craft_finished(recipe_id: String, message: String) -> void:
	if message == "":
		var recipe := Recipes.find(recipe_id)
		message = "Crafted a %s." % Items.display_name(recipe.get("result", recipe_id))
	_craft_message.text = message


func _fill(grid: GridContainer, slots: Array, in_chest: bool) -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	for i in slots.size():
		grid.add_child(_slot_button(slots[i], in_chest, i))


func _slot_button(slot, in_chest: bool, index: int) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(72, 72)
	button.focus_mode = Control.FOCUS_NONE
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(4)
	style.set_border_width_all(1)
	style.set_content_margin_all(8)
	style.border_color = Color(1, 1, 1, 0.12)
	style.bg_color = Color(0.12, 0.12, 0.14, 0.9)
	if slot != null:
		var item: String = slot["item"]
		var icon := Items.icon(item)
		if icon != null:
			button.icon = icon
			button.expand_icon = true
			button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		else:
			button.text = Items.display_name(item)
		button.tooltip_text = "%s\n%s" % [Items.display_name(item), Items.description(item)]
		style.bg_color = Items.color(item).darkened(0.7)
		button.pressed.connect(_on_slot_pressed.bind(in_chest, index))
		if Items.is_tool_item(item) and not in_chest:
			var held := item == Session.held_item
			button.tooltip_text += "\n(In your hand. Right-click to put it away.)" if held \
				else "\n(Right-click to hold it.)"
			button.gui_input.connect(_on_tool_slot_input.bind(item))
			if held:
				style.border_color = Color(1.0, 0.82, 0.3)
				style.set_border_width_all(3)
		var count := Label.new()
		# Things that don't stack, like tools, don't need a count.
		count.text = str(slot["count"]) if Items.max_stack(item) > 1 else ""
		count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		count.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		count.grow_vertical = Control.GROW_DIRECTION_BEGIN
		count.offset_right = -4
		count.add_theme_constant_override("outline_size", 4)
		count.add_theme_color_override("font_outline_color", Color.BLACK)
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(count)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var state_style := style.duplicate()
		if state == "hover":
			state_style.bg_color = style.bg_color.lightened(0.15)
			state_style.border_color = Color(1, 1, 1, 0.35)
		button.add_theme_stylebox_override(state, state_style)
	button.set_drag_forwarding(
		_get_slot_drag_data.bind(button, slot, in_chest, index),
		_can_drop_on_slot.bind(in_chest),
		_drop_on_slot.bind(in_chest, index))
	return button


## Right-clicking a tool holds it, or puts it away if it's already in hand.
func _on_tool_slot_input(event: InputEvent, item: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		Session.hold("" if Session.held_item == item else item)
		get_viewport().set_input_as_handled()


## Clicking a stack with a chest open sends it to the other side.
func _on_slot_pressed(in_chest: bool, index: int) -> void:
	if _chest == null:
		return
	if in_chest:
		_chest.take(index)
	else:
		_chest.store(index)


# --- Drag and drop ----------------------------------------------------------
# Dragged data is { "from_chest": bool, "slot": int }. Dropping on a slot moves
# the stack there (merging or swapping); dropping anywhere off the panels puts
# it on the ground.

func _get_slot_drag_data(_at: Vector2, button: Button, slot, in_chest: bool, index: int) -> Variant:
	if slot == null:
		return null
	var preview := Control.new()
	var icon := TextureRect.new()
	icon.texture = Items.icon(slot["item"])
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.size = Vector2(56, 56)
	icon.position = -icon.size * 0.5
	icon.modulate.a = 0.85
	preview.add_child(icon)
	var count := Label.new()
	count.text = str(slot["count"])
	count.position = Vector2(8, 8)
	count.add_theme_constant_override("outline_size", 4)
	count.add_theme_color_override("font_outline_color", Color.BLACK)
	preview.add_child(count)
	button.set_drag_preview(preview)
	return { "from_chest": in_chest, "slot": index }


func _can_drop_on_slot(_at: Vector2, data, in_chest: bool) -> bool:
	return _is_slot_data(data) and (_chest != null or not (in_chest or data["from_chest"]))


func _drop_on_slot(_at: Vector2, data, in_chest: bool, index: int) -> void:
	if data["from_chest"] or in_chest:
		_chest.move(data["from_chest"], data["slot"], in_chest, index)
	else:
		Session.move_item(data["slot"], index)


func _can_drop_on_ground(_at: Vector2, data) -> bool:
	return _is_slot_data(data) and (_chest != null or not data["from_chest"])


func _drop_on_ground(_at: Vector2, data) -> void:
	if data["from_chest"]:
		_chest.drop(data["slot"])
	else:
		Session.drop_item(data["slot"])


func _is_slot_data(data) -> bool:
	return data is Dictionary and data.has("from_chest") and data.has("slot")


func _build() -> void:
	_prompt = Label.new()
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_prompt.offset_top = -150
	_prompt.offset_bottom = -110
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.add_theme_font_size_override("font_size", 22)
	_prompt.add_theme_constant_override("outline_size", 6)
	_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	add_child(_prompt)

	# The recipe-discovered notice, top centre, over everything but the
	# inventory screen. Doesn't take clicks.
	var top := CenterContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 40
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	var discovery_box := VBoxContainer.new()
	discovery_box.add_theme_constant_override("separation", 6)
	discovery_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var heading := Label.new()
	_discovery_heading = heading
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 20)
	heading.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	discovery_box.add_child(heading)
	_discovery_list = VBoxContainer.new()
	_discovery_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	discovery_box.add_child(_discovery_list)
	var hint := Label.new()
	hint.text = "See it in the crafting window (Tab)."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.75, 0.75, 0.72))
	discovery_box.add_child(hint)
	_discovery = _panel("", discovery_box)
	_discovery.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_discovery.visible = false
	top.add_child(_discovery)

	_screen = Control.new()
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_screen)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.25)
	_drop_zone = dim
	_drop_zone.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_drop_zone.set_drag_forwarding(Callable(), _can_drop_on_ground, _drop_on_ground)
	_screen.add_child(_drop_zone)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	center.add_child(column)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	column.add_child(row)
	var inventory_panel := _panel("Inventory")
	_inventory_grid = inventory_panel.get_meta("grid")
	row.add_child(inventory_panel)
	_chest_panel = _panel("Chest")
	_chest_grid = _chest_panel.get_meta("grid")
	row.add_child(_chest_panel)
	var crafting_box := VBoxContainer.new()
	crafting_box.add_theme_constant_override("separation", 10)
	_crafting_panel = _panel("Crafting", crafting_box)
	_crafting_panel.custom_minimum_size.x = 320
	_recipe_list = VBoxContainer.new()
	_recipe_list.add_theme_constant_override("separation", 10)
	crafting_box.add_child(_recipe_list)
	_craft_message = Label.new()
	_craft_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_craft_message.custom_minimum_size.x = 296
	_craft_message.add_theme_color_override("font_color", Color(0.85, 0.85, 0.8))
	crafting_box.add_child(_craft_message)
	row.add_child(_crafting_panel)
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_constant_override("outline_size", 6)
	_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	column.add_child(_hint)


## A titled panel holding `content`, or a grid of slots (its "grid" meta) if
## none is given.
func _panel(title: String, content: Control = null) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.85)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	if title != "":
		var label := Label.new()
		label.text = title
		label.add_theme_font_size_override("font_size", 20)
		box.add_child(label)
	if content != null:
		box.add_child(content)
		return panel
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	box.add_child(grid)
	panel.set_meta("grid", grid)
	return panel
