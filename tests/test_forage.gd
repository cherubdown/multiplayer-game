extends SceneTree
## Checks where food grows and how picking and growing back work, without a
## network. Run from the project folder:
##   godot --headless --path . -s tests/test_forage.gd
## Exits non-zero if any check fails.

const WorldGen := preload("res://scripts/world_gen.gd")
const Forage := preload("res://scripts/forage.gd")
const Items := preload("res://scripts/items.gd")

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var gen := WorldGen.new("hello world")
	var spots := Forage.scatter(gen)
	_check(spots == Forage.scatter(WorldGen.new("hello world")), "the same seed grows the same plants")
	_check(spots != Forage.scatter(WorldGen.new("Hello world")), "a different seed grows different plants")

	for seed_text in ["hello world", "valheim", "Chris's world"]:
		_check_spots(WorldGen.new(seed_text))

	for kind in Forage.KINDS:
		_check(Items.is_valid(Forage.KINDS[kind]["item"]), "%s gives a real item" % kind)

	# Picking and growing back, on a node outside the tree (so it acts as the
	# server without sending anything).
	var forage := Forage.new()
	root.add_child(forage)
	forage.setup(gen, func(_x: float, _z: float) -> float: return 0.0)
	var bush := _first(forage.spots, "raspberry_bush")
	var tree := _first(forage.spots, "apple_tree")
	_check(bush >= 0 and tree >= 0, "there's a raspberry bush and an apple tree to test on")
	if bush >= 0 and tree >= 0:
		_check_picking(forage, bush, tree)
	forage.queue_free()

	print("Forage: %s" % ("all checks passed" if _failures == 0 else "%d checks failed" % _failures))
	quit(1 if _failures > 0 else 0)


func _check_spots(gen: WorldGen) -> void:
	var spots := Forage.scatter(gen)
	var counts := {}
	var ok := true
	for spot in spots:
		counts[spot["kind"]] = counts.get(spot["kind"], 0) + 1
		var at: Vector3 = spot["position"]
		var biome := gen.biome_at(at.x, at.z)
		ok = ok and Forage.DENSITY.get(biome, {}).has(spot["kind"]) and at.y > WorldGen.SEA_LEVEL \
			and Vector2(at.x, at.z).length() >= Forage.SPAWN_CLEARING \
			and absf(at.y - gen.height_at(at.x, at.z)) < 0.001
		var picks: Vector2i = Forage.KINDS[spot["kind"]]["picks"]
		ok = ok and spot["picks"] >= picks.x and spot["picks"] <= picks.y
	_check(ok, "seed \"%s\" grows every plant on land, in its own biomes, off the spawn" % gen.seed_text)
	var mushrooms: int = counts.get("mushroom", 0)
	var raspberries: int = counts.get("raspberry_bush", 0)
	var blueberries: int = counts.get("blueberry_bush", 0)
	var apples: int = counts.get("apple_tree", 0)
	_check(apples > 0 and blueberries > apples and mushrooms > blueberries and raspberries > blueberries,
		"seed \"%s\": mushrooms and raspberries are common, blueberries less so, apple trees rare (%s)" % [gen.seed_text, counts])
	var near := spots.filter(func(s: Dictionary) -> bool: return Vector2(s["position"].x, s["position"].z).length() < 60.0)
	_check(not near.is_empty(), "seed \"%s\" has something to pick near the spawn" % gen.seed_text)


func _check_picking(forage: Node, bush: int, tree: int) -> void:
	var at: Vector3 = forage.spots[bush]["position"]
	_check(forage.nearest(at + Vector3(1.0, 0.0, 0.0), 2.5) == bush, "finds the plant next to a player")
	_check(forage.nearest_plant(at, 2.5) != null and forage.is_shown(bush, "Fruit"), "draws the plant")
	_check_instancing(forage)
	_check(forage.nearest(at + Vector3(10.0, 0.0, 0.0), 2.5) != bush, "doesn't reach a plant far away")

	_check(forage.take(bush, 0) == 4, "a raspberry bush gives 4 raspberries")
	_check(forage.picks_left(bush) == 0 and forage.take(bush, 0) == 0, "a picked bush has nothing left")
	_check(forage.nearest(at, 2.5) != bush, "a picked bush isn't offered to pick")
	_check(forage.is_shown(bush, "Body") and not forage.is_shown(bush, "Fruit"), "a picked bush loses its berries")
	forage.regrow(239000)
	_check(forage.picks_left(bush) == 0, "berries don't grow back straight away")
	forage.regrow(240000)
	_check(forage.picks_left(bush) == 1 and forage.is_shown(bush, "Fruit") and not forage.left.has(bush), "berries grow back")

	var full: int = forage.spots[tree]["picks"]
	_check(full >= 3 and forage.prompt_for(tree).ends_with("(%d left)" % full), "an apple tree says how many apples are on it")
	_check(forage.take(tree, 0) == 1 and forage.take(tree, 1000) == 1, "picks apples one at a time")
	_check(forage.picks_left(tree) == full - 2, "picking takes apples off the tree")
	var shown := 0
	for n in full:
		shown += 1 if forage.is_shown(tree, "Apple%d" % n) else 0
	_check(shown == full - 2, "the tree shows the apples left (%d of %d)" % [shown, full - 2])
	forage.regrow(120000)
	_check(forage.picks_left(tree) == full - 1, "apples grow back one at a time")
	forage.regrow(240000)
	_check(forage.picks_left(tree) == full and not forage.left.has(tree), "the tree fills up again")


## Every copy of a mesh in a region is drawn by one MultiMesh, and every part
## of every plant has an instance in one.
func _check_instancing(forage: Node) -> void:
	var regions := forage.get_children().filter(func(n: Node) -> bool: return n.name.begins_with("Plants_"))
	var instanced := 0
	var single := 0
	for region in regions:
		for child in region.get_children():
			if child is MultiMeshInstance3D:
				instanced += child.multimesh.instance_count
			else:
				single += 1
	for plant in forage._plants.values():
		single += plant.get_child_count()
	var parts := 0
	for spot in forage._parts.values():
		parts += spot.size()
	_check(regions.size() > 1 and single == 0 and instanced == parts and parts >= forage.spots.size(),
		"plants are drawn with one MultiMesh per mesh per region (%d regions, %d instances)" % [regions.size(), instanced])


func _first(spots: Array, kind: String) -> int:
	for i in spots.size():
		if spots[i]["kind"] == kind:
			return i
	return -1


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: %s" % what)
