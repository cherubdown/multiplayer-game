extends SceneTree
## Checks the world generator without a network. Run from the project folder:
##   godot --headless --path . -s tests/test_world_gen.gd
## Exits non-zero if any check fails.

const WorldGen := preload("res://scripts/world_gen.gd")
const Terrain := preload("res://scripts/terrain.gd")

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var a := WorldGen.new("hello world")
	var b := WorldGen.new("hello world")
	var c := WorldGen.new("Hello world")
	_check(a.seed_number == b.seed_number, "same seed text gives the same seed number")
	_check(a.seed_number != c.seed_number, "seeds are case-sensitive")
	# Pinned so an engine or code change that would reshape existing worlds
	# is noticed.
	_check(WorldGen.seed_to_int("hello") == 3238736544897475342, "seed hashing is stable")

	var same := true
	var different := 0
	for i in 200:
		var x := (i % 20) * 47.0 - 470.0
		var z := (i / 20) * 91.0 - 455.0
		same = same and a.height_at(x, z) == b.height_at(x, z) and a.biome_at(x, z) == b.biome_at(x, z)
		if absf(a.height_at(x, z) - c.height_at(x, z)) > 0.5:
			different += 1
	_check(same, "same seed gives the same terrain and biomes")
	_check(different > 100, "a different seed gives different terrain")

	for seed_text in ["hello world", "valheim", "1", "Chris's world"]:
		_check_world(WorldGen.new(seed_text))

	var random := WorldGen.random_seed()
	_check(random.length() > 5 and random != WorldGen.random_seed(), "random seeds are readable and differ")

	var terrain: Node3D = Terrain.new()
	root.add_child(terrain)
	terrain.build("hello world")
	var names: Array = terrain.get_children().map(func(n: Node) -> String: return n.name)
	_check("Ground" in names and "GroundMesh" in names and "Sea" in names, "terrain builds collision, mesh and sea")
	_check(names.any(func(n: String) -> bool: return n.ends_with("s") and n != "Ground"), "terrain scatters decorations")
	terrain.build("hello world", false)
	await process_frame
	names = terrain.get_children().map(func(n: Node) -> String: return n.name)
	_check(names == ["Ground"], "a dedicated server only builds collision: %s" % [names])

	print("WorldGen: %s" % ("all checks passed" if _failures == 0 else "%d checks failed" % _failures))
	quit(1 if _failures > 0 else 0)


## Every world has every biome, land in the middle and sea at the edge.
func _check_world(gen: WorldGen) -> void:
	var counts := {}
	var steps := 96
	for j in steps:
		for i in steps:
			var x := (i + 0.5) / steps * WorldGen.SIZE - WorldGen.SIZE * 0.5
			var z := (j + 0.5) / steps * WorldGen.SIZE - WorldGen.SIZE * 0.5
			var biome := gen.biome_at(x, z)
			counts[biome] = counts.get(biome, 0) + 1
	var missing := WorldGen.Biome.values().filter(func(b: int) -> bool: return not counts.has(b))
	_check(missing.is_empty(), "seed \"%s\" has every biome (missing %s)" % [gen.seed_text,
		missing.map(func(b: int) -> String: return WorldGen.biome_name(b))])
	var center_ok := true
	for n in 16:
		var p := gen.spawn_point(n * TAU / 16.0, 30.0)
		center_ok = center_ok and gen.biome_at(p.x, p.z) == WorldGen.Biome.MEADOWS and p.y > WorldGen.SEA_LEVEL
	_check(center_ok, "seed \"%s\" spawns players in Meadows above the sea" % gen.seed_text)
	var edge := WorldGen.SIZE * 0.5 - 1.0
	_check(gen.biome_at(edge, 0.0) == WorldGen.Biome.OCEAN and gen.biome_at(0.0, -edge) == WorldGen.Biome.OCEAN,
		"seed \"%s\" is surrounded by ocean" % gen.seed_text)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: %s" % what)
