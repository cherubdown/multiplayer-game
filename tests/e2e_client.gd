extends SceneTree
## End-to-end check against a running server. Start one first:
##   godot --headless --path . --server --port=7790
## then run:
##   godot --headless --path . -s tests/e2e_client.gd -- --port=7790
## or, to check the same flow as a listen-server host with no separate server:
##   godot --headless --path . -s tests/e2e_client.gd -- --host --port=7790
## Registers (or logs in), creates, deletes and picks a character, and checks
## that the server spawns the player into the world with its race and sex. Then walks
## to an item, picks it up, moves it between slots, drops it on the ground and
## picks it up again, puts it in the test chest and takes it back, picks food
## off the nearest plant, gathers wood and stone to craft a stone axe, chops
## down the nearest tree with it and picks up its wood, and checks
## the inventory is still there after re-entering the world, and that the
## player comes back where they stood, facing the same way. Exits non-zero on
## failure.
## Against a server started with --server-password=<password>, pass the same
## flag: the test first checks a wrong password is turned away.
## Pass --expect-seed=<text> to check the server sends that world seed.

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var network: Node = root.get_node("Network")
	var session: Node = root.get_node("Session")
	var port := 7790
	var as_host := false
	var server_password := ""
	var expect_seed := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = int(arg.get_slice("=", 1))
		if arg.begins_with("--server-password="):
			server_password = arg.substr(arg.find("=") + 1)
		if arg.begins_with("--expect-seed="):
			expect_seed = arg.substr(arg.find("=") + 1)
		as_host = as_host or arg == "--host"
	var world: Node = load("res://scenes/test_world.tscn").instantiate()
	# Same path as on the server (child of the Main scene root).
	var main := Node.new()
	main.name = "Main"
	root.add_child(main)
	main.add_child(world)

	if as_host:
		network.host(port)
		session.open_accounts()
		session.setup_world(expect_seed)
	else:
		if server_password != "":
			# Only returns once the server turns us away.
			await _call_and_wait(network.wrong_password, network.join.bind("127.0.0.1", port, server_password + "x"))
			_check(network.mode == network.Mode.OFFLINE, "wrong server password is turned away")
		network.join("127.0.0.1", port, server_password)
		await root.multiplayer.connected_to_server
	while session.world_seed == "":
		await process_frame
	_check(expect_seed == "" or session.world_seed == expect_seed,
		"got the world seed \"%s\" (expected \"%s\")" % [session.world_seed, expect_seed])
	var terrain: Node = world.get_node("Terrain")
	_check(terrain.gen != null and terrain.gen.seed_text == session.world_seed, "built the terrain from the seed")
	var user := "e2e_%d" % (randi() % 100000)

	var result: Array = await _call_and_wait(session.login_finished, session.login.bind(user, "password1"))
	_check(not result[0], "unknown account can't log in")

	result = await _call_and_wait(session.login_finished, session.register.bind(user, "password1"))
	_check(result[0], "registers and logs in: %s" % result[1])

	result = await _call_and_wait(session.characters_changed, session.create_character.bind("Ragnar", "dwarf", "female"))
	_check(result[0].size() == 1 and result[1] == "", "creates a character")
	_check(result[0].size() == 1 and result[0][0]["race"] == "dwarf", "character keeps its race")
	_check(result[0].size() == 1 and result[0][0]["sex"] == "female", "character keeps its sex")
	result = await _call_and_wait(session.characters_changed, session.create_character.bind("Grom", "orc"))
	_check(result[0].size() == 1 and result[1] != "", "rejects an unknown race")
	await _call_and_wait(session.characters_changed, session.create_character.bind("Astrid"))
	result = await _call_and_wait(session.characters_changed, session.delete_character.bind("Astrid"))
	_check(result[0].size() == 1 and result[0][0]["name"] == "Ragnar", "deletes a character")

	result = await _call_and_wait(session.entered_world, session.enter_world.bind("Ragnar"))
	_check(result[0] == "Ragnar", "enters the world")
	await create_timer(0.5).timeout
	var player := world.get_node_or_null("Players/%d" % root.multiplayer.get_unique_id())
	_check(player != null, "server spawned our player")
	_check(player != null and player.character_name == "Ragnar", "player carries the character name")
	_check(player != null and player.race == "dwarf", "player carries the character's race")
	_check(player != null and player.sex == "female", "player carries the character's sex")
	# Give the server time to drop the player onto the ground.
	await create_timer(1.5).timeout
	if player != null:
		var ground: float = terrain.ground_height(player.position.x, player.position.z)
		_check(absf(player.position.y - ground) < 1.5,
			"player stands on the ground (y %.2f, ground %.2f)" % [player.position.y, ground])

	if player != null:
		await _check_inventory(world, player)
		await _check_crafting(world, player)
		# What re-entering the world should bring back.
		_picked_item = "stone_axe"
		_picked_count = _count(session.inventory, "stone_axe")

	# Turn somewhere the spawn would never face, and remember where we stand.
	var left_at := Vector3.ZERO
	var left_facing := 0.0
	if player != null:
		await _turn_to(player, 2.0)
		left_at = player.global_position
		left_facing = player.global_rotation.y
	await _call_and_wait(session.left_world, session.leave_world)
	await create_timer(0.5).timeout
	_check(world.get_node_or_null("Players/%d" % root.multiplayer.get_unique_id()) == null, "leaving despawns the player")

	var saved: Array = session.inventory
	result = await _call_and_wait(session.inventory_changed, session.enter_world.bind("Ragnar"))
	_check(_count(result[0], _picked_item) == _picked_count and _picked_count > 0,
		"inventory is still there after re-entering the world")
	_check(saved == [], "leaving the world clears the client's copy of the inventory")
	await create_timer(0.5).timeout
	player = world.get_node_or_null("Players/%d" % root.multiplayer.get_unique_id())
	_check(player != null, "server spawned our player again")
	if player != null:
		var back := Vector2(player.global_position.x - left_at.x, player.global_position.z - left_at.z).length()
		_check(back < 0.5, "comes back where they left (%.2f m away, at %s, left at %s)" % [back, player.global_position, left_at])
		_check(absf(player.global_position.y - left_at.y) < 1.0, "comes back at the same height")
		_check(absf(angle_difference(player.global_rotation.y, left_facing)) < 0.05,
			"faces the same way (%.2f, left facing %.2f)" % [player.global_rotation.y, left_facing])
		var input: Node = player.get_node("PlayerInput")
		_check(absf(angle_difference(input.yaw, left_facing)) < 0.05, "the camera looks the way the character faces")

	print("E2E: %s" % ("all checks passed" if _failures == 0 else "%d checks failed" % _failures))
	# Disconnect while still in the world, as the menu's Leave button does. The
	# server must cope with a player vanishing mid-game (run-tests.sh checks
	# the dedicated server's log for errors).
	network.disconnect_from_game()
	await create_timer(0.5).timeout
	quit(1 if _failures > 0 else 0)


var _picked_item := ""
var _picked_count := 0


func _check_inventory(world: Node, player: Node3D) -> void:
	var session: Node = root.get_node("Session")
	_check(session.inventory.size() == session.INVENTORY_SLOTS and session.inventory.all(func(s) -> bool: return s == null),
		"a new character gets an empty inventory")
	var items: Array = world.get_node("Items").get_children()
	_check(items.size() == world.TEST_ITEMS.size(), "the server spawned %d test items (got %d)" % [world.TEST_ITEMS.size(), items.size()])
	var chest: Node3D = world.get_node_or_null("TestChest")
	_check(chest != null, "there is a test chest")
	if items.is_empty() or chest == null:
		return
	items.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_to(player.global_position) < b.global_position.distance_to(player.global_position))
	var pickup: Node3D = items[0]
	_picked_item = pickup.item
	_picked_count = pickup.count

	if pickup.global_position.distance_to(player.global_position) > world.SERVER_INTERACT_RANGE + 0.5:
		pickup.interact()
		await create_timer(0.5).timeout
		_check(_count(session.inventory, _picked_item) == 0, "can't pick up an item from far away")

	await _walk_to(player, pickup.global_position)
	var result: Array = await _call_and_wait(session.inventory_changed, pickup.interact)
	_check(_count(result[0], _picked_item) == _picked_count,
		"picks up %d %s (has %d)" % [_picked_count, _picked_item, _count(result[0], _picked_item)])
	await create_timer(0.5).timeout
	_check(not is_instance_valid(pickup) or pickup.is_queued_for_deletion(), "the picked up item is gone")

	var slot := _find(session.inventory, _picked_item)
	await _call_and_wait(session.inventory_changed, session.move_item.bind(slot, 7))
	_check(session.inventory[7] != null and session.inventory[7]["item"] == _picked_item and session.inventory[slot] == null,
		"drags a stack to another inventory slot")
	await _call_and_wait(session.inventory_changed, session.drop_item.bind(7))
	_check(_count(session.inventory, _picked_item) == 0, "dropping a stack takes it out of the inventory")
	await create_timer(0.5).timeout
	var dropped: Node3D = null
	for node in world.get_node("Items").get_children():
		if node.item == _picked_item and node.count == _picked_count \
				and node.global_position.distance_to(player.global_position) < world.INTERACT_RANGE:
			dropped = node
	_check(dropped != null, "the dropped stack lies on the ground next to the player")
	if dropped != null:
		await _call_and_wait(session.inventory_changed, dropped.interact)
	_check(_count(session.inventory, _picked_item) == _picked_count, "picks the dropped stack up again")

	await _walk_to(player, chest.global_position)
	result = await _call_and_wait(chest.contents_changed, chest.interact)
	_check(chest.is_open and result[0].size() == chest.SLOTS, "opens the chest")
	var total := _count(chest.contents, _picked_item) + _picked_count
	slot = _find(session.inventory, _picked_item)
	await _call_and_wait(session.inventory_changed, chest.store.bind(slot))
	_check(_count(session.inventory, _picked_item) == 0, "the stored item leaves the inventory")
	_check(_count(chest.contents, _picked_item) == total, "the stored item is in the chest")
	var empty: int = chest.contents.find(null)
	await _call_and_wait(chest.contents_changed, chest.move.bind(true, _find(chest.contents, _picked_item), true, empty))
	_check(chest.contents[empty] != null and chest.contents[empty]["item"] == _picked_item, "drags a stack to another chest slot")
	await _call_and_wait(session.inventory_changed, chest.move.bind(true, empty, false, 12))
	_check(session.inventory[12] != null and session.inventory[12]["item"] == _picked_item,
		"drags a stack from the chest into an inventory slot")
	_check(_count(session.inventory, _picked_item) + _count(chest.contents, _picked_item) == total,
		"nothing is lost or copied moving items around")
	_picked_count = _count(session.inventory, _picked_item)
	chest.close()
	_check(not chest.is_open, "closes the chest")

	await _check_foraging(world, player)
	_picked_count = _count(session.inventory, _picked_item)


## Walks to the nearest plant with food on it, picks it and checks the food
## lands in the inventory and the server says the plant has been picked.
func _check_foraging(world: Node, player: Node3D) -> void:
	var session: Node = root.get_node("Session")
	var forage: Node = world.forage
	_check(forage != null and forage.spots.size() > 100, "food grows around the island")
	if forage == null:
		return
	# Step away from the chest first, then go for the nearest one that walking
	# straight at won't run into anything.
	await _walk_to(player, world.terrain.gen.spawn_point(PI, 3.0))
	var index := -1
	for i in forage.spots.size():
		if forage.picks_left(i) > 0 and (index < 0 or forage.spots[i]["position"].distance_to(player.global_position)
				< forage.spots[index]["position"].distance_to(player.global_position)) \
				and _path_clear(world, player.global_position, forage.spots[i]["position"], -1):
			index = i
	_check(index >= 0, "there's something to pick within walking distance")
	if index < 0:
		return
	var spot: Dictionary = forage.spots[index]
	var kind: Dictionary = forage.KINDS[spot["kind"]]
	var before := _count(session.inventory, kind["item"])
	var had: int = forage.picks_left(index)
	await _walk_to(player, spot["position"])
	var plant: Node3D = forage.nearest_plant(player.global_position, world.INTERACT_RANGE)
	_check(plant != null and plant.index == index, "stands next to a %s (%s)" % [spot["kind"], plant.prompt() if plant else "nothing"])
	if plant == null:
		return
	var result: Array = await _call_and_wait(session.inventory_changed, plant.interact)
	_check(_count(result[0], kind["item"]) == before + kind["yield"],
		"picks %d %s from a %s" % [kind["yield"], kind["item"], spot["kind"]])
	await create_timer(0.3).timeout
	_check(forage.picks_left(index) == had - 1, "the server says the %s has been picked" % spot["kind"])


## Gathers wood and stone from the test items, crafts a stone axe (which goes
## straight into the empty hand), then chops down the nearest tree and picks up
## the wood it drops.
func _check_crafting(world: Node, player: Node3D) -> void:
	var session: Node = root.get_node("Session")
	var axe := { "wood": 5, "stone": 3 }
	var result: Array
	if _count(session.inventory, "wood") < 5:
		var before: Array = session.inventory
		result = await _call_and_wait(session.craft_finished, session.craft.bind("stone_axe"))
		_check(result[1] != "" and session.inventory == before, "can't craft an axe without the wood and stone: %s" % result[1])
	for item in axe:
		while _count(session.inventory, item) < axe[item]:
			var pickup := _nearest_pickup(world, player, item)
			if pickup == null:
				break
			await _walk_to(player, pickup.global_position)
			await _call_and_wait(session.inventory_changed, pickup.interact)
		_check(_count(session.inventory, item) >= axe[item], "gathers %d %s (has %d)" % [axe[item], item, _count(session.inventory, item)])
	var wood := _count(session.inventory, "wood")
	var stone := _count(session.inventory, "stone")
	result = await _call_and_wait(session.craft_finished, session.craft.bind("stone_axe"))
	_check(result[1] == "", "crafts a stone axe: %s" % result[1])
	await create_timer(0.3).timeout
	_check(_count(session.inventory, "stone_axe") == 1 and _count(session.inventory, "wood") == wood - 5 \
		and _count(session.inventory, "stone") == stone - 3, "crafting uses 5 wood and 3 stone for the axe")
	_check(session.held_item == "stone_axe" and player.held_item == "stone_axe", "the new axe goes into the empty hand")

	var harvest: Node = world.harvestables
	var tree := _clear_tree(world, player.global_position)
	_check(tree >= 0, "there's a tree to chop")
	if tree < 0:
		return
	var at: Vector3 = harvest.spots[tree]["position"]
	# Walking at the trunk stops against it.
	await _walk_to(player, at)
	_check(harvest.nearest(player.global_position, harvest.REACH) == tree, "stands within reach of the tree")
	var hits: int = harvest.hits_left(tree)
	var input: Node = player.get_node("PlayerInput")
	for n in hits:
		await _call_and_wait(harvest.changed, harvest.swing.bind(tree, input.yaw))
		await create_timer(harvest.SWING_SECONDS).timeout
	_check(harvest.felled.has(tree), "chops the tree down in %d hits" % hits)
	_check(not harvest.is_solid(tree), "the felled tree can be walked through")
	await create_timer(0.5).timeout
	var logs := _nearest_pickup(world, player, "wood")
	_check(logs != null and logs.global_position.distance_to(at) < harvest.radius_of(tree) + 2.0,
		"the tree drops wood on the ground")
	if logs != null:
		wood = _count(session.inventory, "wood")
		var amount: int = logs.count
		await _walk_to(player, logs.global_position)
		await _call_and_wait(session.inventory_changed, logs.interact)
		_check(_count(session.inventory, "wood") == wood + amount, "picks up the tree's %d wood" % amount)


## The nearest test item or dropped stack of `item`, or null.
func _nearest_pickup(world: Node, player: Node3D, item: String) -> Node3D:
	var best: Node3D = null
	for node: Node3D in world.get_node("Items").get_children():
		if node.item == item and not node.is_queued_for_deletion() and (best == null \
				or node.global_position.distance_to(player.global_position) < best.global_position.distance_to(player.global_position)):
			best = node
	return best


## The nearest standing tree with nothing else solid between it and `from`,
## so walking straight at it gets there.
func _clear_tree(world: Node, from: Vector3) -> int:
	var harvest: Node = world.harvestables
	var best := -1
	var best_distance := INF
	var start := Vector2(from.x, from.z)
	for i in harvest.spots.size():
		var at: Vector3 = harvest.spots[i]["position"]
		var distance := start.distance_to(Vector2(at.x, at.z))
		if harvest.tool_for(i) != "axe" or harvest.felled.has(i) or distance >= best_distance or distance > 80.0:
			continue
		if _path_clear(world, from, at, i):
			best = i
			best_distance = distance
	return best


## Whether walking straight from `from` to `to` misses every tree and rock
## (but tree or rock `skip`), apple tree and the test chest.
func _path_clear(world: Node, from: Vector3, to: Vector3, skip: int) -> bool:
	var harvest: Node = world.harvestables
	var obstacles := []  # [Vector3, radius]
	for j in harvest.spots.size():
		if j != skip:
			obstacles.append([harvest.spots[j]["position"], harvest.radius_of(j)])
	for spot in world.forage.spots:
		if spot["kind"] == "apple_tree" and spot["position"].distance_to(to) > 0.1:
			obstacles.append([spot["position"], world.forage.TRUNK_RADIUS])
	obstacles.append([world.get_node("TestChest").global_position, 0.8])
	var start := Vector2(from.x, from.z)
	var end := Vector2(to.x, to.z)
	for obstacle in obstacles:
		var point := Vector2(obstacle[0].x, obstacle[0].z)
		if point.distance_to(start) < start.distance_to(end) + 3.0 \
				and Geometry2D.get_closest_point_to_segment(point, start, end).distance_to(point) < obstacle[1] + 1.2:
			return false
	return true


## Walks the local player to within a step of `target`, as if holding W
## while looking at it.
func _walk_to(player: Node3D, target: Vector3) -> void:
	var input: Node = player.get_node("PlayerInput")
	input.set_process(false)
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		var offset := target - player.global_position
		offset.y = 0.0
		if offset.length() < 1.2:
			break
		input.yaw = atan2(-offset.x, -offset.z)
		input.direction = Vector2(0.0, -1.0)
		await physics_frame
	input.direction = Vector2.ZERO
	await create_timer(0.5).timeout
	var left := Vector2(target.x - player.global_position.x, target.z - player.global_position.z).length()
	_check(left < 2.0, "walked up to %s (%.1f m away)" % [target, left])


## Takes a few steps facing `yaw`, so the body turns that way.
func _turn_to(player: Node3D, yaw: float) -> void:
	var input: Node = player.get_node("PlayerInput")
	input.set_process(false)
	input.yaw = yaw
	input.direction = Vector2(0.0, -1.0)
	await create_timer(0.6).timeout
	input.direction = Vector2.ZERO
	await create_timer(0.5).timeout
	_check(absf(angle_difference(player.global_rotation.y, yaw)) < 0.1,
		"turned to face %.2f (facing %.2f)" % [yaw, player.global_rotation.y])


func _count(slots: Array, item: String) -> int:
	var total := 0
	for slot in slots:
		if slot != null and slot["item"] == item:
			total += int(slot["count"])
	return total


func _find(slots: Array, item: String) -> int:
	for i in slots.size():
		if slots[i] != null and slots[i]["item"] == item:
			return i
	return -1


## Calls request, then waits for sig and returns its arguments as an array.
## Connects first because on a host the answer arrives during the call.
func _call_and_wait(sig: Signal, request: Callable) -> Array:
	var box := []
	var capture := func(a = null, b = null) -> void:
		box.append_array([a, b])
	sig.connect(capture, CONNECT_ONE_SHOT)
	request.call()
	while box.is_empty():
		await process_frame
	return box


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failures += 1
