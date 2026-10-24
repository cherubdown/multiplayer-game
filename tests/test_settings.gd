extends SceneTree
## Checks that Settings saves and loads, and that the options window shows each
## setting and changes it. Run from the project folder:
##   godot --headless --path . -s tests/test_settings.gd
## Exits non-zero if any check fails.

const PATH := "user://test_settings.cfg"

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var settings: Node = root.get_node("Settings")
	var options: CanvasLayer = root.get_node("OptionsMenu")
	settings.path = PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	settings.load_settings()

	_check(settings.get_value("display/fullscreen") == false, "full screen is off by default")
	_check(settings.sections() == PackedStringArray(["display", "audio"]), "lists the sections")
	_check(settings.section_name("display") == "Display", "names the display section")
	_check(settings.section_name("audio") == "Audio", "names the audio section")

	var heard := []
	settings.changed.connect(func(id: String, value: Variant) -> void: heard.append([id, value]))
	settings.set_value("display/fullscreen", true)
	_check(settings.get_value("display/fullscreen") == true, "turns full screen on")
	_check(heard == [["display/fullscreen", true]], "says when a setting changes")
	settings.set_value("display/fullscreen", true)
	_check(heard.size() == 1, "stays quiet when nothing changes")
	settings.set_value("display/fullscreen", "yes please")
	_check(settings.get_value("display/fullscreen") == true, "ignores a value of the wrong kind")

	settings.load_settings()
	_check(settings.get_value("display/fullscreen") == true, "full screen survives a reload")

	var file := ConfigFile.new()
	file.set_value("display", "fullscreen", "garbage")
	file.set_value("display", "no_such_setting", 3)
	file.save(PATH)
	settings.load_settings()
	_check(settings.get_value("display/fullscreen") == false, "a broken settings file falls back to defaults")

	# The options window.
	_check(options.find_child("OptionsButton", true, false) == null, "no Options button of its own on screen")
	_check(not options.is_open(), "the window starts closed")
	options.open()
	_check(options.is_open(), "opens the window")
	var toggle: CheckButton = options.control_for("display/fullscreen")
	_check(toggle != null and not toggle.button_pressed, "shows a full screen toggle in its current state")
	toggle.button_pressed = true
	_check(settings.get_value("display/fullscreen") == true, "the toggle turns full screen on")
	settings.set_value("display/fullscreen", false)
	_check(not toggle.button_pressed, "the toggle follows the setting")
	var quit_button: Button = options.find_child("QuitButton", true, false)
	_check(quit_button != null and quit_button.text == "Quit game", "has a Quit game button")
	if quit_button != null:
		quit_button.pressed.emit()
	_check(options.quit_confirm.visible, "Quit game asks before closing")
	options.quit_confirm.hide()
	var extra: Control = options.add_page("Extra", Label.new())
	_check(extra.get_parent() != null, "takes extra pages")
	# Volume.
	var effects_bus := AudioServer.get_bus_index(&"Effects")
	_check(effects_bus > 0, "has an Effects bus for the sound effects")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(0), linear_to_db(0.8)), "the master volume starts at 80%")
	var volume: HSlider = options.control_for("audio/effects_volume")
	_check(volume != null and is_equal_approx(volume.value, 1.0), "shows a sound effects volume slider")
	if volume != null:
		volume.value = 0.5
	_check(is_equal_approx(settings.get_value("audio/effects_volume"), 0.5), "the slider sets the sound effects volume")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(effects_bus), linear_to_db(0.5)), "turns the Effects bus down")
	settings.set_value("audio/master_volume", 0.0)
	_check(AudioServer.is_bus_mute(0), "a master volume of 0 mutes the game")
	settings.set_value("audio/master_volume", 7)
	_check(settings.get_value("audio/master_volume") == 1.0, "keeps a volume between 0 and 1")
	_check(not AudioServer.is_bus_mute(0), "turning it back up unmutes")
	settings.load_settings()
	_check(is_equal_approx(settings.get_value("audio/effects_volume"), 0.5), "the volume survives a reload")

	settings.set_value("display/fullscreen", true)
	settings.reset_to_defaults()
	_check(settings.get_value("display/fullscreen") == false, "resets to defaults")
	_check(is_equal_approx(settings.get_value("audio/effects_volume"), 1.0), "resets the volume too")
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	root.push_input(esc)
	_check(not options.is_open(), "Esc closes the window")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	if _failures > 0:
		printerr("%d settings check(s) failed" % _failures)
	else:
		print("All settings checks passed")
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: %s" % what)
