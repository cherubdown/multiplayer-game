extends SceneTree
## Checks every sound effect (see scripts/sounds.gd) can be made, isn't silent,
## doesn't clip and fits its length. Run from the project folder:
##   godot --headless --path . -s tests/test_sounds.gd
## Add `-- --export=<folder>` to also save every variant there as a .wav, to
## listen to. Exits non-zero if any check fails.

const Sounds := preload("res://scripts/sounds.gd")

var _failures := 0


func _initialize() -> void:
	var export_to := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--export="):
			export_to = arg.get_slice("=", 1)
			DirAccess.make_dir_recursive_absolute(export_to)
	var started := Time.get_ticks_msec()
	var total := 0.0
	for sound: String in Sounds.SOUNDS:
		var variants: int = Sounds.SOUNDS[sound]["variants"]
		_check(variants >= 1, "%s has a variant" % sound)
		for variant in variants:
			var samples := Sounds.render(sound, variant)
			var seconds := samples.size() / float(Sounds.RATE)
			total += seconds
			var peak := 0.0
			var finite := true
			for x in samples:
				peak = maxf(peak, absf(x))
				finite = finite and is_finite(x)
			_check(finite, "%s %d has no broken samples" % [sound, variant])
			_check(peak > 0.5 and peak <= 1.0, "%s %d is loud enough without clipping (peak %.2f)" % [sound, variant, peak])
			_check(seconds > 0.02 and seconds < 3.0, "%s %d is a sensible length (%.2f s)" % [sound, variant, seconds])
			_check(absf(samples[samples.size() - 1]) < 0.05, "%s %d ends without a click" % [sound, variant])
			_check(samples == Sounds.render(sound, variant), "%s %d comes out the same every time" % [sound, variant])
			if export_to != "":
				Sounds.to_stream(samples).save_to_wav(export_to.path_join("%s_%d.wav" % [sound, variant + 1]))
	print("Made %.1f s of sound in %d ms" % [total, Time.get_ticks_msec() - started])

	var streams := Sounds.streams("chop")
	_check(streams.size() == Sounds.SOUNDS["chop"]["variants"], "makes a stream for every variant")
	_check(streams[0] is AudioStreamWAV and streams[0].get_length() > 0.1, "the streams play the sound")
	_check(Sounds.streams("chop")[0] == streams[0], "makes each sound only once")
	_check(not Sounds.enabled(), "plays nothing headless")
	Sounds.play_ui(root, "click")
	_check(root.get_children().filter(func(n: Node) -> bool: return n is AudioStreamPlayer).is_empty(),
		"playing headless adds no players")
	_check(AudioServer.get_bus_index(Sounds.bus_name()) > 0, "has an Effects bus under Master")

	if _failures > 0:
		printerr("%d sound check(s) failed" % _failures)
	else:
		print("All sound checks passed")
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: " + what)
