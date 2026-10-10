extends CanvasLayer
## The local player's inventory screen, the chest screen and the "E" prompt.
## Added to the world on every peer that has a player (not a dedicated server).
##
## Tab (or I) shows the inventory. E picks up the nearest item or opens the
## nearest chest; with a chest open, clicking a stack moves it between the
## inventory and the chest. Esc, Tab or E closes the screen again. All of it
## only sends requests: the server owns every inventory (see Session and
## scripts/chest.gd).

const Items := preload("res://scripts/items.gd")

const COLUMNS := 5

var _prompt: Label
var _screen: Control
var _inventory_grid: GridContainer
var _chest_panel: Control
var _chest_grid: GridContainer
var _hint: Label
## The chest whose screen is showing, or null.
var _chest: Node


func _ready() -> void:
	_build()
	Session.inventory_changed.connect(func(_slots: Array) -> void: _refresh())
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
	_prompt.visible = target != null
	if target != null:
		_prompt.text = "[E] %s" % target.prompt()


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
	_hint.text = "Click a stack to move it between your inventory and the chest." if chest != null \
		else "Walk up to a chest and press E to store things."
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
	_fill(_inventory_grid, Session.inventory, _on_inventory_slot_pressed)
	if _chest != null:
		_fill(_chest_grid, _chest.contents, _on_chest_slot_pressed)


func _fill(grid: GridContainer, slots: Array, on_pressed: Callable) -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	for i in slots.size():
		grid.add_child(_slot_button(slots[i], on_pressed.bind(i)))


func _slot_button(slot, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(84, 64)
	button.focus_mode = Control.FOCUS_NONE
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(4)
	style.bg_color = Color(0.12, 0.12, 0.14, 0.9)
	if slot != null:
		button.text = "%s\n%d" % [Items.display_name(slot["item"]), slot["count"]]
		button.tooltip_text = Items.display_name(slot["item"])
		style.bg_color = Items.color(slot["item"]).darkened(0.45)
		button.pressed.connect(on_pressed)
	else:
		button.disabled = true
	for state in ["normal", "hover", "pressed", "disabled"]:
		var state_style := style.duplicate()
		if state == "hover":
			state_style.bg_color = style.bg_color.lightened(0.2)
		button.add_theme_stylebox_override(state, state_style)
	return button


func _on_inventory_slot_pressed(slot: int) -> void:
	if _chest != null:
		_chest.store(slot)


func _on_chest_slot_pressed(slot: int) -> void:
	if _chest != null:
		_chest.take(slot)


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

	_screen = CenterContainer.new()
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_screen)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_screen.add_child(column)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	column.add_child(row)
	var inventory_panel := _panel("Inventory")
	_inventory_grid = inventory_panel.get_meta("grid")
	row.add_child(inventory_panel)
	_chest_panel = _panel("Chest")
	_chest_grid = _chest_panel.get_meta("grid")
	row.add_child(_chest_panel)
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_constant_override("outline_size", 6)
	_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	column.add_child(_hint)


func _panel(title: String) -> PanelContainer:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 20)
	box.add_child(label)
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	box.add_child(grid)
	panel.set_meta("grid", grid)
	return panel
