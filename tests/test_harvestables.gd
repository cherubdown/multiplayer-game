extends SceneTree
## Checks where trees and rocks stand, that they're solid, and how chopping,
## breaking and growing back work, without a network. Run from the project
## folder:
##   godot --headless --path . -s tests/test_harvestables.gd
## Exits non-zero if any check fails.

const WorldGen := preload("res://scripts/world_gen.gd")
const Harvestables := preload("res://scripts/harvestables.gd")
const Forage := preload("res://scripts/forage.gd")
const Items := preload("res://scripts/items.gd")
const TreeMeshes := preload("res://scripts/tree_meshes.gd")

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var gen := WorldGen.new("hello world")
	var spots := Harvestables.scatter(gen)
	_check(spots == Harvestables.scatter(WorldGen.new("hello world")), "the same seed grows the same trees and rocks")
	_check(spots != Harvestables.scatter(WorldGen.new("Hello world")), "a different seed grows different ones")
	for seed_text in ["hello world", "valheim", "Chris's world"]:
		_check_spots(WorldGen.new(seed_text))
	for kind in Harvestables.KINDS:
		_check(Items.is_valid(Harvestables.KINDS[kind]["drop"]), "%s drops a real item" % kind)
	for kind in TreeMeshes.SWAY:
		var mesh := TreeMeshes.mesh(kind)
		_check(mesh.get_surface_count() == (1 if kind == "dead" else 2), "%s has bark and a crown" % kind)
		for n in mesh.get_surface_count():
			var material := mesh.surface_get_material(n) as ShaderMaterial
			_check(material != null and material.shader == TreeMeshes.SHADER, "%s is painted" % kind)

	# On a node outside any network it acts as the server without sending
	# anything.
	var world := Node3D.new()
	root.add_child(world)
	var harvest := Harvestables.new()
	world.add_child(harvest)
	harvest.setup(gen, true)
	var dropped := []
	harvest.harvested.connect(func(index: int, item: String, count: int, at: Vector3) -> void:
		dropped.append([index, item, count, at]))
	await physics_frame
	await physics_frame
	var tree := _first(harvest.spots, "pine")
	var rock := _first(harvest.spots, "rock")
	_check(tree >= 0 and rock >= 0, "there's a pine and a rock to test on")
	if tree >= 0 and rock >= 0:
		await _check_chopping(harvest, tree, dropped)
		await _check_breaking(harvest, rock, dropped)

	# Loose wood and stone to pick up, never inside a trunk or rock.
	var forage := Forage.scatter(gen, harvest.occupied)
	var kinds := {}
	var clear := true
	for spot in forage:
		kinds[spot["kind"]] = true
		clear = clear and not harvest.occupied(spot["position"].x, spot["position"].z, 0.5)
	_check(kinds.has("branches") and kinds.has("loose_stones"), "branches and loose stones lie around the island")
	_check(Forage.KINDS["branches"]["item"] == "wood" and Forage.KINDS["loose_stones"]["item"] == "stone",
		"branches give wood and loose stones give stone")
	_check(clear, "nothing to pick grows inside a trunk or rock")

	world.queue_free()
	print("Harvestables: %s" % ("all checks passed" if _failures == 0 else "%d checks failed" % _failures))
	quit(1 if _failures > 0 else 0)


func _check_spots(gen: WorldGen) -> void:
	var spots := Harvestables.scatter(gen)
	var counts := {}
	var ok := true
	for spot in spots:
		counts[spot["kind"]] = counts.get(spot["kind"], 0) + 1
		var at: Vector3 = spot["position"]
		ok = ok and Harvestables.DENSITY.get(gen.biome_for(at.x, at.z, at.y), {}).has(spot["kind"]) \
			and Vector2(at.x, at.z).length() >= Harvestables.SPAWN_CLEARING
	_check(ok, "seed \"%s\" grows trees and rocks in their own biomes, off the spawn" % gen.seed_text)
	_check(counts.get("pine", 0) > 500 and counts.get("leafy", 0) > 20 and counts.get("rock", 0) > 50,
		"seed \"%s\" has plenty of trees and rocks (%s)" % [gen.seed_text, counts])


func _check_chopping(harvest: Node, tree: int, dropped: Array) -> void:
	var at: Vector3 = harvest.spots[tree]["position"]
	_check(_solid_at(harvest, at + Vector3.UP * 1.0), "a tree's trunk is solid")
	_check(harvest.nearest(at + Vector3(harvest.radius_of(tree) + 1.0, 0.0, 0.0), Harvestables.REACH) == tree,
		"finds the tree next to a player")
	_check(harvest.nearest(at + Vector3(harvest.radius_of(tree) + 6.0, 0.0, 0.0), Harvestables.REACH) != tree,
		"doesn't reach a tree far away")
	_check(harvest.prompt_for(tree, "").begins_with("Hold an axe"), "says to hold an axe: %s" % harvest.prompt_for(tree, ""))
	_check(harvest.prompt_for(tree, "stone_axe").contains("6 hits"), "says how many hits it takes: %s" % harvest.prompt_for(tree, "stone_axe"))
	_check(not harvest.hit(tree, "pickaxe", 1, 0) and not harvest.hit(tree, "sword", 1, 0), "only an axe chops trees")
	for n in 5:
		harvest.hit(tree, "axe", 1, 0)
	_check(harvest.hits_left(tree) == 1 and dropped.is_empty() and not harvest.felled.has(tree), "a pine takes six hits")
	_check(harvest.hit(tree, "axe", 1, 1000) and harvest.felled.has(tree), "the sixth hit fells it")
	_check(dropped.size() == 1 and dropped[0][0] == tree and dropped[0][1] == "wood" and dropped[0][2] >= 5 and dropped[0][2] <= 7,
		"a felled pine drops 5 to 7 wood (%s)" % [dropped])
	_check(not harvest.hit(tree, "axe", 1, 1000), "can't chop a tree that's down")
	_check(harvest.nearest(at, Harvestables.REACH) != tree, "a felled tree isn't offered to chop")
	await physics_frame
	await physics_frame
	_check(not harvest.is_solid(tree) and not _solid_at(harvest, at + Vector3.UP * 1.0), "a felled tree can be walked through")
	harvest.regrow(1000 + 599000)
	_check(harvest.felled.has(tree), "trees don't grow back straight away")
	harvest.regrow(1000 + 600000)
	_check(not harvest.felled.has(tree) and harvest.hits_left(tree) == 6 and harvest.is_solid(tree), "trees grow back")


func _check_breaking(harvest: Node, rock: int, dropped: Array) -> void:
	dropped.clear()
	var at: Vector3 = harvest.spots[rock]["position"]
	_check(_solid_at(harvest, at + Vector3.UP * 0.3), "a rock is solid")
	_check(harvest.prompt_for(rock, "stone_axe").begins_with("Hold a pickaxe"), "says to hold a pickaxe")
	_check(not harvest.hit(rock, "axe", 1, 0), "an axe doesn't break rocks")
	for n in Harvestables.KINDS["rock"]["hits"]:
		harvest.hit(rock, "pickaxe", 1, 0)
	_check(harvest.felled.has(rock) and dropped.size() == 1 and dropped[0][1] == "stone" and dropped[0][2] >= 4,
		"a pickaxe breaks a rock into stone (%s)" % [dropped])


## Whether a short ray across `point` hits something solid there.
func _solid_at(harvest: Node, point: Vector3) -> bool:
	var space: PhysicsDirectSpaceState3D = harvest.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(point + Vector3(-3.0, 0.0, 0.0), point + Vector3(3.0, 0.0, 0.0))
	query.collision_mask = Harvestables.COLLISION_LAYER
	return not space.intersect_ray(query).is_empty()


func _first(spots: Array, kind: String) -> int:
	for i in spots.size():
		if spots[i]["kind"] == kind:
			return i
	return -1


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: %s" % what)
