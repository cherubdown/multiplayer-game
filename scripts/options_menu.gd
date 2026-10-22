extends CanvasLayer
## The options window (autoload "OptionsMenu"). It sits above every other
## screen and opens from the Options buttons on the Host / Join menu and on the
## Esc menu in the world (see main.gd).
##
## The window has one tab per section of Settings.DEFINITIONS, with a control
## for each setting built from its type, so new settings show up here without
## touching this script. Pages that aren't simple settings (key bindings, say)
## can be added with add_page(). Esc or Close shuts the window; changes save
## and take effect straight away. Quit game leaves the game cleanly and closes
## the app (see Network.quit_game()), after asking to make sure.

## Above the menu and the inventory screen.
const LAYER := 100

var _window: Control
var _tabs: TabContainer
## Asks before Quit game closes the app.
var quit_confirm: ConfirmationDialog
## Setting id -> the control showing it.
var _controls := {}


func _ready() -> void:
	layer = LAYER
	# Keeps working while anything pauses the game.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	Settings.changed.connect(_on_setting_changed)
	close()
	# Nobody sees a dedicated server's screen.
	visible = DisplayServer.get_name() != "headless" and not OS.has_feature("dedicated_server")


func is_open() -> bool:
	return _window.visible


func open() -> void:
	_refresh_all()
	_window.show()


func close() -> void:
	_window.hide()


func toggle() -> void:
	if is_open():
		close()
	else:
		open()


## Adds a tab of its own, after the settings tabs. Returns the page.
func add_page(title: String, page: Control) -> Control:
	_add_tab(title, page)
	return page


## The control showing a setting, or null. Mostly for tests.
func control_for(id: String) -> Control:
	return _controls.get(id)


func _input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed("ui_cancel") and not event.is_echo():
		close()
		get_viewport().set_input_as_handled()


func _build() -> void:
	# Fills the screen so clicks don't reach the menu or the game behind it.
	_window = Control.new()
	_window.name = "OptionsWindow"
	_window.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_window.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_window)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_window.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_window.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.17)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Options"
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(0, 200)
	vbox.add_child(_tabs)

	var buttons := HBoxContainer.new()
	vbox.add_child(buttons)
	var reset := Button.new()
	reset.text = "Reset to defaults"
	reset.pressed.connect(Settings.reset_to_defaults)
	buttons.add_child(reset)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	var quit_button := Button.new()
	quit_button.name = "QuitButton"
	quit_button.text = "Quit game"
	quit_button.tooltip_text = "Save, leave the game and close the window"
	quit_button.pressed.connect(_on_quit_pressed)
	buttons.add_child(quit_button)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(close)
	buttons.add_child(close_button)

	quit_confirm = ConfirmationDialog.new()
	quit_confirm.name = "QuitConfirm"
	quit_confirm.title = "Quit game"
	quit_confirm.dialog_text = "Quit the game? Your character is saved before it closes."
	quit_confirm.ok_button_text = "Quit"
	quit_confirm.confirmed.connect(func() -> void: Network.quit_game())
	add_child(quit_confirm)

	_build_tabs()
	_refresh_all()


func _on_quit_pressed() -> void:
	quit_confirm.popup_centered()


## One tab per section of Settings.DEFINITIONS.
func _build_tabs() -> void:
	for section in Settings.sections():
		var rows := VBoxContainer.new()
		rows.add_theme_constant_override("separation", 8)
		rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for id in Settings.ids_in(section):
			rows.add_child(_setting_row(id))
		var page := MarginContainer.new()
		for side in ["left", "top", "right", "bottom"]:
			page.add_theme_constant_override("margin_" + side, 8)
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.add_child(rows)
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.add_child(page)
		_add_tab(Settings.section_name(section), scroll)


func _add_tab(title: String, page: Control) -> void:
	page.name = title.validate_node_name()
	_tabs.add_child(page)
	_tabs.set_tab_title(_tabs.get_tab_idx_from_control(page), title)


## A label and a control for one setting, laid out as a row.
func _setting_row(id: String) -> Control:
	var definition: Dictionary = Settings.DEFINITIONS[id]
	var row := HBoxContainer.new()
	row.tooltip_text = definition.get("tooltip", "")
	var label := Label.new()
	label.text = definition["label"]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(label)
	var control := _setting_control(id, definition)
	control.tooltip_text = row.tooltip_text
	row.add_child(control)
	_controls[id] = control
	return row


func _setting_control(id: String, definition: Dictionary) -> Control:
	match definition["type"]:
		"toggle":
			var check := CheckButton.new()
			check.toggled.connect(func(on: bool) -> void: Settings.set_value(id, on))
			return check
		"slider":
			var slider := HSlider.new()
			slider.min_value = definition["min"]
			slider.max_value = definition["max"]
			slider.step = definition.get("step", 0.01)
			slider.custom_minimum_size = Vector2(160, 0)
			slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			slider.value_changed.connect(func(value: float) -> void: Settings.set_value(id, value))
			return slider
		"choice":
			var picker := OptionButton.new()
			for value: String in definition["options"]:
				picker.add_item(definition["options"][value])
				picker.set_item_metadata(picker.item_count - 1, value)
			picker.item_selected.connect(func(index: int) -> void:
				Settings.set_value(id, picker.get_item_metadata(index)))
			return picker
	push_error("Setting %s has unknown type %s" % [id, definition["type"]])
	return Label.new()


func _refresh_all() -> void:
	for id: String in _controls:
		_show_value(id, Settings.get_value(id))


func _on_setting_changed(id: String, value: Variant) -> void:
	_show_value(id, value)


## Shows a value on its control without sending it back to Settings.
func _show_value(id: String, value: Variant) -> void:
	var control: Control = _controls.get(id)
	if control is CheckButton:
		control.set_pressed_no_signal(value)
	elif control is HSlider:
		control.set_value_no_signal(value)
	elif control is OptionButton:
		for i in control.item_count:
			if control.get_item_metadata(i) == value:
				control.select(i)
