extends RefCounted
## Every sound effect in the game. They're made in code from noise, tones and
## filters the first time they're needed (UiSounds warms them all up in the
## background, see scripts/ui_sounds.gd), so there are no audio files to
## import and nothing to license.
##
##   Sounds.play_on(node, "chop")              at a node, heard in 3D
##   Sounds.play_at(node, "chop", position)    at a point in the world
##   Sounds.play_ui(node, "click")             not in the world (menus, HUD)
##
## Each sound comes in a few variants, picked at random and played at a
## slightly random pitch, so repeated sounds (footsteps, chops) don't sound
## like a machine gun. Everything plays on the Effects bus, whose volume (and
## the master volume) are in the options window (see Settings).
##
## Nothing plays on a dedicated server or anywhere else without a screen, so
## calling these from server code is fine.

const RATE := 22050
## The bus everything plays on, under Master.
const BUS := &"Effects"
## How far play() strays from the pitch it's asked for, either way.
const PITCH_JITTER := 0.06

## Each sound: how many variants, its volume (dB) and how far away it can be
## heard (m, for sounds in the world).
const SOUNDS := {
	# The players.
	"step": { "variants": 4, "volume": -14.0, "range": 25.0 },
	"jump": { "variants": 2, "volume": -14.0, "range": 25.0 },
	"land": { "variants": 2, "volume": -9.0, "range": 25.0 },
	"swing": { "variants": 3, "volume": -8.0, "range": 30.0 },
	"swing_heavy": { "variants": 3, "volume": -7.0, "range": 30.0 },
	"hurt": { "variants": 3, "volume": -5.0, "range": 35.0 },
	"death": { "variants": 1, "volume": -3.0, "range": 45.0 },
	"poison": { "variants": 2, "volume": -8.0, "range": 25.0 },
	"tired": { "variants": 2, "volume": -10.0, "range": 15.0 },
	"heal": { "variants": 1, "volume": -12.0, "range": 15.0 },
	"respawn": { "variants": 1, "volume": -9.0, "range": 30.0 },
	# Trees, rocks and plants.
	"chop": { "variants": 3, "volume": -4.0, "range": 45.0 },
	"tree_fall": { "variants": 2, "volume": -2.0, "range": 70.0 },
	"pick": { "variants": 3, "volume": -6.0, "range": 45.0 },
	"rock_break": { "variants": 2, "volume": -2.0, "range": 60.0 },
	"pluck": { "variants": 3, "volume": -9.0, "range": 20.0 },
	# Things on the ground.
	"drop": { "variants": 3, "volume": -9.0, "range": 25.0 },
	"bounce": { "variants": 3, "volume": -14.0, "range": 20.0 },
	"pickup": { "variants": 3, "volume": -10.0, "range": 15.0 },
	# The Big Frog.
	"frog_hop": { "variants": 3, "volume": -10.0, "range": 35.0 },
	"frog_croak": { "variants": 3, "volume": -6.0, "range": 55.0 },
	"frog_bite": { "variants": 3, "volume": -4.0, "range": 40.0 },
	"tongue_lick": { "variants": 2, "volume": -5.0, "range": 40.0 },
	"frog_hurt": { "variants": 3, "volume": -8.0, "range": 40.0 },
	"frog_death": { "variants": 1, "volume": -4.0, "range": 55.0 },
	"hit_flesh": { "variants": 3, "volume": -4.0, "range": 40.0 },
	# Chests, the inventory and crafting.
	"chest_open": { "variants": 2, "volume": -8.0, "range": 25.0 },
	"chest_close": { "variants": 2, "volume": -8.0, "range": 25.0 },
	"bag_open": { "variants": 2, "volume": -13.0 },
	"bag_close": { "variants": 2, "volume": -14.0 },
	"move": { "variants": 3, "volume": -15.0 },
	"equip": { "variants": 2, "volume": -11.0 },
	"unequip": { "variants": 2, "volume": -12.0 },
	"craft": { "variants": 2, "volume": -8.0 },
	"discover": { "variants": 1, "volume": -9.0 },
	# Menus.
	"click": { "variants": 2, "volume": -16.0 },
	"error": { "variants": 1, "volume": -14.0 },
}

## Sound name -> Array of AudioStreamWAV, one per variant, made on first use.
static var _streams := {}
## True while UiSounds is making every sound in the background. Until it's
## done, a sound it hasn't got to yet is skipped rather than made on the spot,
## which would stall the game for a moment.
static var warming := false


## Whether sounds play here: not on a dedicated server or anything headless.
static func enabled() -> bool:
	return DisplayServer.get_name() != "headless" and not OS.has_feature("dedicated_server")


## Plays `sound` where `node` is in the world, for whoever's near enough to
## hear. `pitch` above 1 is higher (voices of smaller folk, say).
static func play_on(node: Node3D, sound: String, volume_db := 0.0, pitch := 1.0) -> void:
	if enabled() and node != null and node.is_inside_tree():
		play_at(node, sound, node.global_position, volume_db, pitch)


## Plays `sound` at `at` in the world `node` is in. It keeps playing if `node`
## goes away, such as a frog dying.
static func play_at(node: Node, sound: String, at: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	if not enabled() or node == null or not node.is_inside_tree() or not SOUNDS.has(sound):
		return
	var stream := _pick(sound)
	if stream == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.bus = bus_name()
	player.volume_db = SOUNDS[sound]["volume"] + volume_db
	player.pitch_scale = pitch * randf_range(1.0 - PITCH_JITTER, 1.0 + PITCH_JITTER)
	player.unit_size = 4.0
	player.max_distance = SOUNDS[sound].get("range", 30.0)
	player.finished.connect(player.queue_free)
	node.get_viewport().add_child(player)
	player.global_position = at
	player.play()


## Plays `sound` flat, not from anywhere in the world: menus, the inventory
## screen, the local player's own cues.
static func play_ui(node: Node, sound: String, volume_db := 0.0, pitch := 1.0) -> void:
	if not enabled() or node == null or not node.is_inside_tree() or not SOUNDS.has(sound):
		return
	var stream := _pick(sound)
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = bus_name()
	player.volume_db = SOUNDS[sound]["volume"] + volume_db
	player.pitch_scale = pitch * randf_range(1.0 - PITCH_JITTER * 0.5, 1.0 + PITCH_JITTER * 0.5)
	player.finished.connect(player.queue_free)
	node.get_tree().root.add_child(player)
	player.play()


## The Effects bus, made (under Master) if it isn't there yet.
static func bus_name() -> StringName:
	if AudioServer.get_bus_index(BUS) < 0:
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, BUS)
		AudioServer.set_bus_send(index, &"Master")
	return BUS


## Every variant of `sound`, made now if they haven't been yet.
static func streams(sound: String) -> Array:
	if not _streams.has(sound):
		var made := []
		for variant in SOUNDS[sound]["variants"]:
			made.append(to_stream(render(sound, variant)))
		_streams[sound] = made
	return _streams[sound]


static func _pick(sound: String) -> AudioStreamWAV:
	if warming and not _streams.has(sound):
		return null
	var options := streams(sound)
	return options[randi() % options.size()]


## A playable stream of samples from render().
static func to_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	return stream


## The samples (at RATE, -1 to 1) of one variant of a sound. The same every
## time for the same sound and variant.
static func render(sound: String, variant: int) -> PackedFloat32Array:
	var mix := Mix.new(hash(sound) + variant * 7919)
	var j := mix.rng.randf_range(0.92, 1.08)
	match sound:
		"step":
			mix.noise(0.0, 0.12, 1.0, 0.003, 0.03, Filter.LOW, 1400.0 * j, 350.0)
			mix.noise(0.005, 0.14, 0.35, 0.004, 0.04, Filter.BAND, 3200.0 * j, 2200.0, 1.2, 0.5)
			mix.tone(0.0, 0.1, 0.5, 95.0 * j, 55.0, 0.002, 0.03)
		"jump":
			mix.noise(0.0, 0.22, 1.0, 0.05, 0.06, Filter.BAND, 500.0 * j, 1400.0, 1.5)
			mix.noise(0.0, 0.08, 0.4, 0.002, 0.02, Filter.LOW, 900.0, 300.0)
		"land":
			mix.noise(0.0, 0.25, 1.0, 0.002, 0.06, Filter.LOW, 900.0 * j, 200.0)
			mix.tone(0.0, 0.2, 0.8, 80.0 * j, 45.0, 0.002, 0.07)
			mix.noise(0.0, 0.25, 0.3, 0.004, 0.08, Filter.BAND, 3000.0, 2000.0, 1.2, 0.5)
		"swing":
			mix.noise(0.0, 0.3, 1.0, 0.09, 0.06, Filter.BAND, 600.0 * j, 2600.0 * j, 2.0)
		"swing_heavy":
			mix.noise(0.0, 0.4, 1.0, 0.13, 0.09, Filter.BAND, 300.0 * j, 1200.0 * j, 1.6)
		"hurt":
			mix.tone(0.0, 0.12, 0.6, 100.0, 60.0, 0.001, 0.04)
			mix.noise(0.0, 0.1, 0.6, 0.001, 0.03, Filter.LOW, 700.0, 250.0)
			mix.voice(0.01, 0.26, 0.9, 150.0 * j, 112.0 * j, 0.015, 0.09, [[650.0, 5.0, 1.0], [1100.0, 6.0, 0.6], [2500.0, 8.0, 0.25]])
		"death":
			mix.voice(0.0, 0.8, 0.9, 140.0, 75.0, 0.03, 0.35, [[600.0, 4.0, 1.0], [1000.0, 5.0, 0.6], [2400.0, 8.0, 0.2]], 5.0, 0.015)
			mix.tone(0.55, 0.3, 0.8, 70.0, 40.0, 0.002, 0.1)
			mix.noise(0.55, 0.3, 0.7, 0.002, 0.08, Filter.LOW, 600.0, 200.0)
			mix.noise(0.56, 0.3, 0.25, 0.004, 0.09, Filter.BAND, 3000.0, 2000.0, 1.2, 0.5)
		"poison":
			mix.noise(0.0, 0.7, 0.45, 0.02, 0.25, Filter.HIGH, 3500.0 * j, 3500.0, 0.7, 0.8)
			for i in 9:
				var at := mix.rng.randf_range(0.0, 0.5)
				var f := mix.rng.randf_range(250.0, 500.0)
				mix.tone(at, 0.06, 0.4, f, f * 2.2, 0.002, 0.015)
		"tired":
			mix.noise(0.0, 0.45, 1.0, 0.08, 0.15, Filter.BAND, 900.0 * j, 600.0, 1.2)
			mix.noise(0.0, 0.4, 0.2, 0.08, 0.1, Filter.HIGH, 2500.0, 2500.0)
		"heal":
			mix.note(0.0, 0.5, 0.5, 659.25, 0.25)
			mix.note(0.09, 0.55, 0.5, 987.77, 0.3)
			mix.noise(0.0, 0.6, 0.05, 0.15, 0.2, Filter.HIGH, 6000.0, 6000.0)
		"respawn":
			var notes := [523.25, 659.25, 783.99, 1046.5]
			for i in notes.size():
				mix.note(i * 0.1, 1.0, 0.45, notes[i], 0.4)
			mix.noise(0.0, 1.2, 0.07, 0.2, 0.4, Filter.HIGH, 6000.0, 6000.0)
		"chop":
			mix.noise(0.0, 0.03, 0.8, 0.0005, 0.006, Filter.HIGH, 2500.0, 2500.0)
			mix.noise(0.0, 0.2, 1.0, 0.001, 0.035, Filter.BAND, 800.0 * j, 600.0 * j, 3.0)
			mix.tone(0.0, 0.25, 0.6, 210.0 * j, 190.0 * j, 0.001, 0.05, Wave.TRIANGLE)
			mix.tone(0.0, 0.2, 0.35, 460.0 * j, 440.0 * j, 0.001, 0.03)
			mix.noise(0.01, 0.3, 0.15, 0.02, 0.08, Filter.HIGH, 4000.0, 4000.0, 0.7, 0.5)
		"tree_fall":
			# It creaks, cracks, swishes down through the air and crashes.
			mix.voice(0.0, 0.9, 0.5, 70.0 * j, 55.0, 0.1, 0.5, [[600.0, 4.0, 1.0], [1300.0, 5.0, 0.6]], 0.0, 0.0, 18.0, 0.6)
			for at in [0.75, 0.8, 0.9]:
				mix.noise(at, 0.06, 0.7, 0.0005, 0.01, Filter.HIGH, 2000.0, 2000.0)
			mix.noise(0.9, 0.8, 0.5, 0.4, 0.3, Filter.BAND, 1500.0, 800.0, 1.0)
			mix.noise(1.5, 0.9, 1.0, 0.003, 0.35, Filter.LOW, 600.0, 150.0)
			mix.tone(1.5, 0.8, 0.9, 55.0, 35.0, 0.003, 0.3)
			mix.noise(1.5, 0.9, 0.4, 0.01, 0.4, Filter.HIGH, 3000.0, 3000.0, 0.7, 0.5)
			for at in [1.55, 1.72]:
				mix.tone(at, 0.15, 0.4, 180.0 * j, 170.0, 0.001, 0.05, Wave.TRIANGLE)
		"pick":
			mix.noise(0.0, 0.02, 0.9, 0.0003, 0.004, Filter.HIGH, 3000.0, 3000.0)
			mix.tone(0.0, 0.4, 0.35, 1850.0 * j, 1850.0 * j, 0.0005, 0.12)
			mix.tone(0.0, 0.3, 0.25, 2710.0 * j, 2710.0 * j, 0.0005, 0.09)
			mix.tone(0.0, 0.2, 0.2, 4020.0 * j, 4020.0 * j, 0.0005, 0.06)
			mix.noise(0.0, 0.1, 0.6, 0.0005, 0.02, Filter.BAND, 1200.0, 900.0, 2.0)
			mix.tone(0.0, 0.1, 0.5, 130.0, 90.0, 0.001, 0.03)
		"rock_break":
			for i in 8:
				var at := mix.rng.randf_range(0.0, 0.35)
				mix.noise(at, 0.2, mix.rng.randf_range(0.5, 1.0), 0.001, mix.rng.randf_range(0.03, 0.06),
					Filter.LOW, 2500.0, 500.0)
			mix.noise(0.0, 0.9, 0.8, 0.01, 0.25, Filter.LOW, 300.0, 120.0)
			mix.tone(0.0, 0.7, 0.7, 70.0, 40.0, 0.002, 0.2)
			mix.tone(0.05, 0.2, 0.2, 2200.0 * j, 2200.0 * j, 0.0005, 0.05)
			mix.tone(0.2, 0.2, 0.15, 3100.0 * j, 3100.0 * j, 0.0005, 0.04)
		"pluck":
			for i in 5:
				var at := mix.rng.randf_range(0.0, 0.15)
				mix.noise(at, 0.12, mix.rng.randf_range(0.4, 0.8), 0.003, mix.rng.randf_range(0.02, 0.04),
					Filter.BAND, mix.rng.randf_range(2500.0, 4500.0), 2000.0, 1.2)
			mix.noise(0.12, 0.03, 0.8, 0.0005, 0.004, Filter.HIGH, 3000.0, 3000.0)
			mix.tone(0.12, 0.04, 0.2, 700.0, 600.0, 0.0005, 0.01)
		"drop":
			mix.tone(0.0, 0.15, 0.8, 150.0 * j, 85.0, 0.001, 0.035)
			mix.noise(0.0, 0.15, 0.8, 0.001, 0.03, Filter.LOW, 900.0 * j, 300.0)
			mix.noise(0.0, 0.15, 0.2, 0.003, 0.04, Filter.BAND, 3000.0, 2500.0, 1.2, 0.5)
		"bounce":
			mix.tone(0.0, 0.08, 0.6, 220.0 * j, 140.0, 0.001, 0.015)
			mix.noise(0.0, 0.06, 0.6, 0.001, 0.01, Filter.LOW, 1500.0 * j, 800.0)
		"pickup":
			mix.tone(0.0, 0.15, 0.8, 520.0 * j, 880.0 * j, 0.003, 0.05)
			mix.tone(0.0, 0.1, 0.2, 1040.0 * j, 1760.0 * j, 0.003, 0.03)
			mix.noise(0.0, 0.02, 0.3, 0.0005, 0.002, Filter.HIGH, 4000.0, 4000.0)
		"frog_hop":
			mix.tone(0.0, 0.12, 0.7, 90.0 * j, 50.0, 0.001, 0.04)
			mix.noise(0.0, 0.12, 0.7, 0.001, 0.03, Filter.LOW, 500.0, 200.0)
			mix.noise(0.01, 0.1, 0.3, 0.002, 0.02, Filter.BAND, 900.0 * j, 700.0, 4.0, 0.6)
		"frog_croak":
			# "Rib-bit", low and throaty for a frog this size.
			var formants := [[450.0 * j, 4.0, 1.0], [1100.0 * j, 6.0, 0.4]]
			mix.voice(0.0, 0.2, 1.0, 85.0 * j, 80.0 * j, 0.02, 0.12, formants, 0.0, 0.0, 28.0, 0.9)
			mix.voice(0.26, 0.16, 0.9, 95.0 * j, 78.0 * j, 0.015, 0.09, formants, 0.0, 0.0, 30.0, 0.9)
		"frog_bite":
			mix.noise(0.0, 0.05, 0.9, 0.0005, 0.012, Filter.BAND, 1500.0 * j, 1500.0, 2.0)
			mix.noise(0.05, 0.05, 0.9, 0.0005, 0.012, Filter.BAND, 1300.0 * j, 1300.0, 2.0)
			mix.tone(0.0, 0.12, 0.7, 160.0, 90.0, 0.001, 0.04)
			mix.noise(0.03, 0.15, 0.4, 0.003, 0.05, Filter.BAND, 800.0, 600.0, 3.0, 0.6)
		"tongue_lick":
			# Out with a thwip, back with a slurp.
			mix.noise(0.0, 0.12, 1.0, 0.02, 0.04, Filter.BAND, 500.0 * j, 3500.0, 3.0)
			mix.tone(0.0, 0.1, 0.2, 300.0, 600.0, 0.01, 0.03)
			mix.noise(0.16, 0.3, 0.8, 0.03, 0.1, Filter.BAND, 2200.0 * j, 500.0, 4.0, 0.0, 45.0, 0.8)
		"frog_hurt":
			mix.voice(0.0, 0.3, 1.0, 180.0 * j, 120.0 * j, 0.01, 0.12, [[600.0, 4.0, 1.0], [1400.0, 6.0, 0.5]], 0.0, 0.0, 35.0, 0.7)
		"frog_death":
			mix.voice(0.0, 1.0, 1.0, 120.0, 55.0, 0.02, 0.4, [[500.0, 4.0, 1.0], [1000.0, 6.0, 0.4]], 0.0, 0.0, 24.0, 0.8)
			mix.tone(0.7, 0.3, 0.8, 75.0, 40.0, 0.002, 0.1)
			mix.noise(0.7, 0.3, 0.7, 0.002, 0.08, Filter.LOW, 600.0, 200.0)
		"hit_flesh":
			mix.tone(0.0, 0.15, 0.9, 120.0 * j, 55.0, 0.001, 0.05)
			mix.noise(0.0, 0.15, 1.0, 0.001, 0.04, Filter.LOW, 700.0 * j, 250.0)
			mix.noise(0.0, 0.12, 0.5, 0.002, 0.03, Filter.BAND, 1400.0 * j, 900.0, 3.0, 0.6)
			mix.noise(0.0, 0.02, 0.5, 0.0003, 0.004, Filter.HIGH, 3000.0, 3000.0)
		"chest_open":
			mix.noise(0.0, 0.02, 0.8, 0.0003, 0.003, Filter.HIGH, 3000.0, 3000.0)
			mix.tone(0.0, 0.04, 0.3, 1800.0, 1800.0, 0.0005, 0.01)
			mix.voice(0.05, 0.45, 0.6, 180.0 * j, 300.0 * j, 0.05, 0.3, [[900.0, 6.0, 1.0], [2000.0, 8.0, 0.5]], 0.0, 0.0, 30.0, 0.5)
		"chest_close":
			mix.tone(0.0, 0.15, 0.9, 130.0 * j, 90.0, 0.001, 0.05, Wave.TRIANGLE)
			mix.noise(0.0, 0.15, 0.8, 0.001, 0.04, Filter.LOW, 800.0, 300.0)
			mix.noise(0.06, 0.02, 0.6, 0.0003, 0.003, Filter.HIGH, 3000.0, 3000.0)
		"bag_open":
			mix.noise(0.0, 0.3, 0.9, 0.03, 0.1, Filter.BAND, 1400.0 * j, 2400.0, 1.0, 0.4)
			mix.noise(0.1, 0.2, 0.5, 0.02, 0.06, Filter.BAND, 2000.0, 1600.0, 1.0, 0.4)
		"bag_close":
			mix.noise(0.0, 0.25, 0.9, 0.02, 0.07, Filter.BAND, 2200.0 * j, 1200.0, 1.0, 0.4)
		"move":
			mix.tone(0.0, 0.08, 0.5, 600.0 * j, 420.0 * j, 0.001, 0.015, Wave.TRIANGLE)
			mix.noise(0.0, 0.05, 0.4, 0.001, 0.01, Filter.BAND, 1500.0, 1500.0, 1.0)
		"equip":
			mix.noise(0.0, 0.25, 0.5, 0.02, 0.08, Filter.HIGH, 3500.0, 6000.0)
			mix.tone(0.02, 0.45, 0.25, 2400.0 * j, 2400.0 * j, 0.01, 0.2)
			mix.tone(0.02, 0.35, 0.18, 3550.0 * j, 3550.0 * j, 0.01, 0.15)
			mix.tone(0.02, 0.25, 0.12, 5200.0 * j, 5200.0 * j, 0.01, 0.1)
			mix.tone(0.0, 0.1, 0.3, 200.0, 140.0, 0.001, 0.03)
		"unequip":
			mix.noise(0.0, 0.2, 0.6, 0.02, 0.05, Filter.BAND, 1800.0 * j, 900.0, 1.0)
			mix.tone(0.0, 0.12, 0.4, 220.0 * j, 160.0, 0.001, 0.03, Wave.TRIANGLE)
		"craft":
			# A few knocks of a hammer, then a little sparkle.
			var knocks := [330.0, 360.0, 300.0]
			for i in knocks.size():
				var at := i * 0.17
				mix.tone(at, 0.15, 0.7, knocks[i] * j, knocks[i] * j * 0.95, 0.001, 0.04, Wave.TRIANGLE)
				mix.noise(at, 0.08, 0.6, 0.001, 0.015, Filter.BAND, 1200.0, 1000.0, 2.0)
				mix.noise(at, 0.02, 0.5, 0.0003, 0.003, Filter.HIGH, 3000.0, 3000.0)
			mix.note(0.45, 0.3, 0.25, 1318.5, 0.12)
			mix.note(0.5, 0.3, 0.25, 1760.0, 0.12)
		"discover":
			var notes := [783.99, 987.77, 1174.66, 1567.98]
			for i in notes.size():
				mix.note(i * 0.08 + (0.02 if i == 3 else 0.0), 0.9, 0.4, notes[i], 0.3)
			mix.noise(0.0, 1.1, 0.06, 0.2, 0.35, Filter.HIGH, 6500.0, 6500.0)
		"click":
			mix.tone(0.0, 0.04, 0.6, 1600.0 * j, 1200.0 * j, 0.0005, 0.008)
			mix.noise(0.0, 0.01, 0.4, 0.0003, 0.002, Filter.HIGH, 5000.0, 5000.0)
		"error":
			for at in [0.0, 0.12]:
				mix.tone(at, 0.1, 0.5, 180.0, 170.0, 0.003, 0.06, Wave.SQUARE)
		_:
			push_error("No sound called %s" % sound)
	return mix.finish()


enum Filter { LOW, BAND, HIGH }
enum Wave { SINE, TRIANGLE, SAW, SQUARE }


## A sound being made: layers of filtered noise and tones added together.
## Times are in seconds from the start of the sound.
class Mix:
	var data := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()

	func _init(seed_number: int) -> void:
		rng.seed = seed_number

	## Filtered noise, `length` seconds from `start`, rising for `attack`
	## seconds then dying away (falling to a third every `decay` seconds).
	## Every layer's `gain` is how loud its loudest moment is.
	## The filter's frequency slides from `f0` to `f1`. `grain` (0 to 1)
	## makes it crackle; `am_rate` and `am_depth` make it throb.
	func noise(start: float, length: float, gain: float, attack: float, decay: float,
			filter: int, f0: float, f1: float, q := 0.7, grain := 0.0,
			am_rate := 0.0, am_depth := 0.0) -> void:
		var svf := Svf.new()
		var layer := PackedFloat32Array()
		layer.resize(int(length * RATE))
		var crackle := 1.0
		for i in layer.size():
			var t := float(i) / RATE
			if i % 8 == 0:
				svf.tune(_sweep(f0, f1, t / length), q)
			if grain > 0.0 and i % 48 == 0:
				var r := rng.randf()
				crackle = lerpf(1.0, r * r * 2.5, grain)
			svf.process(rng.randf_range(-1.0, 1.0))
			var x: float = svf.low if filter == Filter.LOW else svf.band if filter == Filter.BAND else svf.high
			layer[i] = x * crackle * _envelope(t, length, attack, decay) * _throb(t, am_rate, am_depth)
		_add(start, layer, gain)

	## A tone sliding from `f0` to `f1` Hz, shaped like noise() is.
	func tone(start: float, length: float, gain: float, f0: float, f1: float,
			attack: float, decay: float, wave := Wave.SINE) -> void:
		var layer := PackedFloat32Array()
		layer.resize(int(length * RATE))
		var phase := 0.0
		for i in layer.size():
			var t := float(i) / RATE
			phase = fposmod(phase + _sweep(f0, f1, t / length) / RATE, 1.0)
			layer[i] = _wave(wave, phase) * _envelope(t, length, attack, decay)
		_add(start, layer, gain)

	## A bell-like note: a sine with a quieter octave above.
	func note(start: float, length: float, gain: float, frequency: float, decay: float) -> void:
		tone(start, length, gain, frequency, frequency, 0.005, decay)
		tone(start, length * 0.6, gain * 0.25, frequency * 2.0, frequency * 2.0, 0.005, decay * 0.5, Wave.TRIANGLE)

	## A buzzing sawtooth sliding from `f0` to `f1` Hz through `formants`
	## ([frequency, q, gain] band filters), for voices, croaks and creaks.
	## `vibrato` Hz wide at 5.5 a second, `wobble` a random waver (as a
	## fraction of the pitch), and `am_rate`/`am_depth` a throb.
	func voice(start: float, length: float, gain: float, f0: float, f1: float,
			attack: float, decay: float, formants: Array, vibrato := 0.0, wobble := 0.0,
			am_rate := 0.0, am_depth := 0.0) -> void:
		var filters := []
		for formant in formants:
			var svf := Svf.new()
			svf.tune(formant[0], formant[1])
			filters.append(svf)
		var layer := PackedFloat32Array()
		layer.resize(int(length * RATE))
		var phase := 0.0
		var waver := 0.0
		for i in layer.size():
			var t := float(i) / RATE
			if wobble > 0.0 and i % 64 == 0:
				waver = lerpf(waver, rng.randf_range(-wobble, wobble), 0.5)
			var f := _sweep(f0, f1, t / length) * (1.0 + waver) + vibrato * sin(TAU * 5.5 * t)
			phase = fposmod(phase + f / RATE, 1.0)
			var source := 2.0 * phase - 1.0
			var x := 0.0
			for n in filters.size():
				filters[n].process(source)
				x += filters[n].band * formants[n][2]
			layer[i] = x * _envelope(t, length, attack, decay) * _throb(t, am_rate, am_depth)
		_add(start, layer, gain)

	## The finished sound, as loud as it can be without clipping, with any
	## silence at the end trimmed off.
	func finish() -> PackedFloat32Array:
		var peak := 0.0
		for x in data:
			peak = maxf(peak, absf(x))
		if peak <= 0.0:
			return data
		var end := data.size()
		while end > 1 and absf(data[end - 1]) < peak * 0.001:
			end -= 1
		var result := data.slice(0, end)
		var scale := 0.9 / peak
		for i in result.size():
			result[i] *= scale
		return result

	## Adds a layer `start` seconds in, scaled so its loudest moment is
	## `gain`, so every layer's gain means the same whatever made it.
	func _add(start: float, layer: PackedFloat32Array, gain: float) -> void:
		var peak := 0.0
		for x in layer:
			peak = maxf(peak, absf(x))
		if peak <= 0.0:
			return
		var first := int(start * RATE)
		if data.size() < first + layer.size():
			var old := data.size()
			data.resize(first + layer.size())
			for i in range(old, data.size()):
				data[i] = 0.0
		var scale := gain / peak
		for i in layer.size():
			data[first + i] += layer[i] * scale

	static func _sweep(f0: float, f1: float, u: float) -> float:
		return f0 * pow(f1 / f0, clampf(u, 0.0, 1.0))

	## Rises over `attack`, then dies away, with a quick fade at the very end
	## so it never stops with a click.
	static func _envelope(t: float, length: float, attack: float, decay: float) -> float:
		var level := t / attack if t < attack else exp(-(t - attack) / decay)
		return level * clampf((length - t) / 0.005, 0.0, 1.0)

	static func _throb(t: float, rate: float, depth: float) -> float:
		if rate <= 0.0:
			return 1.0
		var pulse := 0.5 + 0.5 * sin(TAU * rate * t)
		return 1.0 - depth + depth * pulse * pulse

	static func _wave(wave: int, phase: float) -> float:
		match wave:
			Wave.TRIANGLE:
				return 4.0 * absf(phase - 0.5) - 1.0
			Wave.SAW:
				return 2.0 * phase - 1.0
			Wave.SQUARE:
				return 1.0 if phase < 0.5 else -1.0
		return sin(TAU * phase)


## A state variable filter (the trapezoidal kind, which stays stable however
## high it's tuned). Gives low, band and high pass at once.
class Svf:
	var low := 0.0
	var band := 0.0
	var high := 0.0
	var _k := 1.0
	var _a1 := 0.0
	var _a2 := 0.0
	var _a3 := 0.0
	var _ic1 := 0.0
	var _ic2 := 0.0

	func tune(frequency: float, q: float) -> void:
		var g := tan(PI * clampf(frequency, 20.0, RATE * 0.45) / RATE)
		_k = 1.0 / q
		_a1 = 1.0 / (1.0 + g * (g + _k))
		_a2 = g * _a1
		_a3 = g * _a2

	func process(x: float) -> void:
		var v3 := x - _ic2
		var v1 := _a1 * _ic1 + _a2 * v3
		var v2 := _ic2 + _a2 * _ic1 + _a3 * v3
		_ic1 = 2.0 * v1 - _ic1
		_ic2 = 2.0 * v2 - _ic2
		low = v2
		band = v1
		high = x - _k * v1 - v2
