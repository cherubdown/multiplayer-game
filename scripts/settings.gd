extends Node
## Player settings (autoload "Settings"). They belong to this PC, not to a
## server, and are saved in user://settings.cfg as soon as one changes.
##
## Every setting is declared once in DEFINITIONS: the options window builds
## its tabs and controls from that list, so adding a setting there (plus a
## line in _apply() if it changes something in the engine) is all it takes to
## show it, save it and load it.

const PATH := "user://settings.cfg"

## Setting id ("section/key") -> how to show it in the options window.
##   label    what the control is called
##   type     "toggle" (bool), "slider" (float, with min, max and step) or
##            "choice" (String, one of options: { value: label })
##   default  value before the player changes it
##   tooltip  optional longer explanation
## The section (the part before the slash) is the tab it shows up on. Tabs and
## settings appear in the order they are listed here.
const DEFINITIONS := {
	"display/fullscreen": {
		"label": "Full screen",
		"type": "toggle",
		"default": false,
		"tooltip": "Fill the whole screen instead of showing a window.",
	},
}

## Display names for the sections in DEFINITIONS. A section missing here is
## shown capitalized.
const SECTION_NAMES := {
	"display": "Display",
}

signal changed(id: String, value: Variant)

## Where the settings are saved. Tests point this somewhere else.
var path := PATH
var _values := {}


func _ready() -> void:
	load_settings()
	apply_all()
	if _has_window():
		# Keep the setting true to the window if the OS changes it (for example
		# a window manager shortcut taking the game out of full screen).
		get_window().size_changed.connect(_on_window_size_changed)


## Every section in DEFINITIONS, in order.
func sections() -> PackedStringArray:
	var result: PackedStringArray = []
	for id: String in DEFINITIONS:
		var section := id.get_slice("/", 0)
		if not section in result:
			result.append(section)
	return result


## The ids of the settings in one section, in order.
func ids_in(section: String) -> PackedStringArray:
	var result: PackedStringArray = []
	for id: String in DEFINITIONS:
		if id.get_slice("/", 0) == section:
			result.append(id)
	return result


static func section_name(section: String) -> String:
	return SECTION_NAMES.get(section, section.capitalize())


func get_value(id: String) -> Variant:
	if not DEFINITIONS.has(id):
		push_error("Unknown setting %s" % id)
		return null
	return _values.get(id, DEFINITIONS[id]["default"])


## Changes a setting, applies it and saves. Values of the wrong kind are
## turned into the right one (or ignored if they can't be).
func set_value(id: String, value: Variant) -> void:
	if not DEFINITIONS.has(id):
		push_error("Unknown setting %s" % id)
		return
	var clean: Variant = _sanitize(id, value)
	if clean == null or clean == get_value(id):
		return
	_values[id] = clean
	_apply(id, clean)
	save_settings()
	changed.emit(id, clean)


## Puts every setting back to its default.
func reset_to_defaults() -> void:
	for id: String in DEFINITIONS:
		set_value(id, DEFINITIONS[id]["default"])


func load_settings() -> void:
	_values.clear()
	var file := ConfigFile.new()
	if file.load(path) != OK:
		return
	for id: String in DEFINITIONS:
		var section := id.get_slice("/", 0)
		var key := id.get_slice("/", 1)
		if file.has_section_key(section, key):
			var clean: Variant = _sanitize(id, file.get_value(section, key))
			if clean != null:
				_values[id] = clean


func save_settings() -> void:
	var file := ConfigFile.new()
	for id: String in DEFINITIONS:
		file.set_value(id.get_slice("/", 0), id.get_slice("/", 1), get_value(id))
	var err := file.save(path)
	if err != OK:
		push_warning("Couldn't save settings to %s (error %d)" % [path, err])


func apply_all() -> void:
	for id: String in DEFINITIONS:
		_apply(id, get_value(id))


## Makes a setting take effect. Settings only the UI reads need no line here.
func _apply(id: String, value: Variant) -> void:
	match id:
		"display/fullscreen":
			if _has_window():
				var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if value else DisplayServer.WINDOW_MODE_WINDOWED
				if DisplayServer.window_get_mode() != mode:
					DisplayServer.window_set_mode(mode)


func _sanitize(id: String, value: Variant) -> Variant:
	var definition: Dictionary = DEFINITIONS[id]
	match definition["type"]:
		"toggle":
			if value is bool:
				return value
			if value is int or value is float:
				return value != 0
		"slider":
			if value is int or value is float:
				return clampf(float(value), definition["min"], definition["max"])
		"choice":
			if value is String and definition["options"].has(value):
				return value
	return null


func _has_window() -> bool:
	return DisplayServer.get_name() != "headless" and not OS.has_feature("dedicated_server")


func _on_window_size_changed() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_MINIMIZED:
		return
	var fullscreen := mode == DisplayServer.WINDOW_MODE_FULLSCREEN \
		or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if fullscreen != get_value("display/fullscreen"):
		set_value("display/fullscreen", fullscreen)
