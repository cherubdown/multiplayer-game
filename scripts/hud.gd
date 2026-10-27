extends CanvasLayer
## What's always on screen while playing: the local player's health bar in the
## bottom left corner with their stamina bar under it, the hotbar of tools in
## the middle along the bottom (see scripts/hotbar_bar.gd), a red flash when they're hurt, and a notice when they
## die. While they're poisoned the health bar and the flash turn green. Added to the world on every peer that has a player (not a dedicated
## server). Only shows what the server replicates on the player (see
## scripts/player.gd).

const Player := preload("res://scripts/player.gd")
const HotbarBar := preload("res://scripts/hotbar_bar.gd")

## Seconds the death notice stays up.
const DEATH_NOTICE_SECONDS := 4.0
const HEALTH_COLOR := Color(0.8, 0.14, 0.12)
const POISONED_COLOR := Color(0.38, 0.72, 0.16)
const HURT_FLASH := Color(0.8, 0.0, 0.0, 0.25)
const POISON_FLASH := Color(0.3, 0.75, 0.05, 0.25)

var _panel: PanelContainer
var _bar: ProgressBar
var _value: Label
var _health_title: Label
var _stamina_bar: ProgressBar
var _stamina_value: Label
var _flash: ColorRect
var _flash_tween: Tween
var _death: Label
var _death_tween: Tween
## The hotbar, bottom middle (see scripts/hotbar_bar.gd).
var hotbar: HotbarBar
## The local player whose health is showing, or null.
var _player: Node3D


func _ready() -> void:
	_build()
	_show_player(null)


func _process(_delta: float) -> void:
	var player := _local_player()
	if player != _player:
		_show_player(player)
	if _player != null:
		_set_stamina(_player.stamina)
		_set_poisoned(_player.poisoned)


## The text of the health bar, such as "42 / 50", or "" when it's hidden.
func health_text() -> String:
	return _value.text if _panel.visible else ""


## The text of the stamina bar, such as "80 / 100", or "" when it's hidden.
func stamina_text() -> String:
	return _stamina_value.text if _panel.visible else ""


## Whether the health bar shows the player poisoned.
func shows_poisoned() -> bool:
	return _panel.visible and _health_title.text == "Poison"


## The death notice showing, or "" if there isn't one.
func death_notice() -> String:
	return _death.text if _death.visible else ""


func _local_player() -> Node3D:
	if Session.character_name == "":
		return null
	var player := get_parent().get_node_or_null("Players/%d" % multiplayer.get_unique_id()) as Node3D
	return player if player != null and not player.is_queued_for_deletion() else null


func _show_player(player: Node3D) -> void:
	if is_instance_valid(_player):
		_player.health_changed.disconnect(_on_health_changed)
		_player.died.disconnect(_on_died)
	_player = player
	_panel.visible = player != null
	hotbar.visible = player != null
	if player == null:
		_death.visible = false
		return
	player.health_changed.connect(_on_health_changed)
	player.died.connect(_on_died)
	_set_health(player.health)
	_set_stamina(player.stamina)


func _set_health(health: int) -> void:
	_bar.value = health
	_value.text = "%d / %d" % [health, Player.MAX_HEALTH]


func _set_poisoned(poisoned: bool) -> void:
	var title := "Poison" if poisoned else "Health"
	if _health_title.text == title:
		return
	_health_title.text = title
	(_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = POISONED_COLOR if poisoned else HEALTH_COLOR
	_flash.color = POISON_FLASH if poisoned else HURT_FLASH


func _set_stamina(stamina: float) -> void:
	_stamina_bar.value = stamina
	_stamina_value.text = "%d / %d" % [ceili(stamina), Player.MAX_STAMINA]


func _on_health_changed(health: int, old: int) -> void:
	_set_health(health)
	if health < old:
		if _flash_tween != null:
			_flash_tween.kill()
		_flash.modulate.a = 1.0
		_flash_tween = create_tween()
		_flash_tween.tween_property(_flash, "modulate:a", 0.0, 0.4)


func _on_died(by: String) -> void:
	_death.text = "You were killed by %s." % by if by != "" else "You died."
	_death.visible = true
	_death.modulate.a = 1.0
	if _death_tween != null:
		_death_tween.kill()
	_death_tween = create_tween()
	_death_tween.tween_interval(DEATH_NOTICE_SECONDS - 1.0)
	_death_tween.tween_property(_death, "modulate:a", 0.0, 1.0)
	_death_tween.tween_callback(func() -> void: _death.visible = false)


func _build() -> void:
	_flash = ColorRect.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.color = HURT_FLASH
	_flash.modulate.a = 0.0
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)

	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_panel.offset_left = 16
	_panel.offset_top = -92
	_panel.offset_right = 276
	_panel.offset_bottom = -16
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.0, 0.0, 0.0, 0.45)
	box.set_corner_radius_all(6)
	box.set_content_margin_all(8)
	_panel.add_theme_stylebox_override("panel", box)
	add_child(_panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	_panel.add_child(rows)
	_bar = ProgressBar.new()
	_value = Label.new()
	_health_title = _add_bar(rows, "Health", _bar, _value, Player.MAX_HEALTH,
			HEALTH_COLOR, Color(0.15, 0.05, 0.05, 0.9))
	_stamina_bar = ProgressBar.new()
	_stamina_value = Label.new()
	_add_bar(rows, "Stamina", _stamina_bar, _stamina_value, Player.MAX_STAMINA,
			Color(0.85, 0.7, 0.15), Color(0.15, 0.12, 0.03, 0.9))

	var bottom := CenterContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_bottom = -8
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom)
	hotbar = HotbarBar.new()
	bottom.add_child(hotbar)

	_death = Label.new()
	_death.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_death.offset_top = 140
	_death.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_death.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death.add_theme_font_size_override("font_size", 30)
	_death.add_theme_constant_override("outline_size", 8)
	_death.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35))
	_death.add_theme_color_override("font_outline_color", Color.BLACK)
	_death.visible = false
	add_child(_death)


## A row in the corner panel: `title`, then `bar` filled in `color` up to
## `max_value`, then `value` for the numbers. Returns the title's label.
func _add_bar(rows: VBoxContainer, title: String, bar: ProgressBar, value: Label,
		max_value: float, color: Color, back_color: Color) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	rows.add_child(row)
	var label := Label.new()
	label.text = title
	label.custom_minimum_size.x = 60
	row.add_child(label)
	bar.min_value = 0
	bar.max_value = max_value
	bar.step = 0.0
	bar.show_percentage = false
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.custom_minimum_size = Vector2(0, 18)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(4)
	var back := StyleBoxFlat.new()
	back.bg_color = back_color
	back.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", back)
	row.add_child(bar)
	value.custom_minimum_size.x = 64
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	return label
