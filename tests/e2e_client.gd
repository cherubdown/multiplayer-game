extends SceneTree
## End-to-end check against a running server. Start one first:
##   godot --headless --path . --server --port=7790
## then run:
##   godot --headless --path . -s tests/e2e_client.gd -- --port=7790
## or, to check the same flow as a listen-server host with no separate server:
##   godot --headless --path . -s tests/e2e_client.gd -- --host --port=7790
## Registers (or logs in), creates, deletes and picks a character, and checks
## that the server spawns the player into the world with its race. Then walks
## to an item, picks it up, puts it in the test chest and takes it back, and
## checks the inventory is still there after re-entering the world. Exits
## non-zero on failure.
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

	result = await _call_and_wait(session.characters_changed, session.create_character.bind("Ragnar", "dwarf"))
	_check(result[0].size() == 1 and result[1] == "", "creates a character")
	_check(result[0].size() == 1 and result[0][0]["race"] == "dwarf", "character keeps its race")
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
	# Give the server time to drop the player onto the ground.
	await create_timer(1.5).timeout
	if player != null:
		var ground: float = terrain.ground_height(player.position.x, player.position.z)
		_check(absf(player.position.y - ground) < 1.5,
			"player stands on the ground (y %.2f, ground %.2f)" % [player.position.y, ground])

	if player != null:
		await _check_inventory(world, player)

	await _call_and_wait(session.left_world, session.leave_world)
	await create_timer(0.5).timeout
	_check(world.get_node_or_null("Players/%d" % root.multiplayer.get_unique_id()) == null, "leaving despawns the player")

	var saved: Array = session.inventory
	result = await _call_and_wait(session.inventory_changed, session.enter_world.bind("Ragnar"))
	_check(_count(result[0], _picked_item) == _picked_count and _picked_count > 0,
		"inventory is still there after re-entering the world")
	_check(saved == [], "leaving the world clears the client's copy of the inventory")
	await create_timer(0.5).timeout
	await _call_and_wait(session.left_world, session.leave_world)

	print("E2E: %s" % ("all checks passed" if _failures == 0 else "%d checks failed" % _failures))
	network.disconnect_from_game()
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

	await _walk_to(player, chest.global_position)
	result = await _call_and_wait(chest.contents_changed, chest.interact)
	_check(chest.is_open and result[0].size() == chest.SLOTS, "opens the chest")
	var total := _count(chest.contents, _picked_item) + _picked_count
	var slot := _find(session.inventory, _picked_item)
	await _call_and_wait(session.inventory_changed, chest.store.bind(slot))
	_check(_count(session.inventory, _picked_item) == 0, "the stored item leaves the inventory")
	_check(_count(chest.contents, _picked_item) == total, "the stored item is in the chest")
	await _call_and_wait(session.inventory_changed, chest.take.bind(_find(chest.contents, _picked_item)))
	_check(_count(session.inventory, _picked_item) > 0, "takes the item back out of the chest")
	_check(_count(session.inventory, _picked_item) + _count(chest.contents, _picked_item) == total,
		"nothing is lost or copied moving items around")
	_picked_count = _count(session.inventory, _picked_item)
	chest.close()
	_check(not chest.is_open, "closes the chest")


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
