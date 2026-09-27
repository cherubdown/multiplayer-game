extends SceneTree
## End-to-end check against a running server. Start one first:
##   godot --headless --path . --server --port=7790
## then run:
##   godot --headless --path . -s tests/e2e_client.gd -- --port=7790
## or, to check the same flow as a listen-server host with no separate server:
##   godot --headless --path . -s tests/e2e_client.gd -- --host --port=7790
## Registers (or logs in), creates, deletes and picks a character, and checks
## that the server spawns the player into the world with its race. Exits non-zero on failure.
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

	await _call_and_wait(session.left_world, session.leave_world)
	await create_timer(0.5).timeout
	_check(world.get_node_or_null("Players/%d" % root.multiplayer.get_unique_id()) == null, "leaving despawns the player")

	print("E2E: %s" % ("all checks passed" if _failures == 0 else "%d checks failed" % _failures))
	network.disconnect_from_game()
	quit(1 if _failures > 0 else 0)


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
