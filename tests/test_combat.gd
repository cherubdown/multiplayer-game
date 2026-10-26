extends SceneTree
## Checks player health, stamina and the Big Frog without a network: taking
## damage, dying, health coming back, sprinting and attacking using stamina,
## poison wearing health down and wearing off, the frog turning towards
## players no faster than it should, licking and poisoning players a way off
## (unless they step out of the tongue's way), chasing and biting players
## nearby (missing one bite in five) and leaving far ones alone, taking twelve wood sword hits to kill, and what it drops: Frog Meat
## every time and Frog Bile now and then, popping out of it and bouncing to a
## stop. Run from the project folder:
##   godot --headless --path . -s tests/test_combat.gd
## Exits non-zero if any check fails.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const FROG_SCENE := preload("res://scenes/big_frog.tscn")
const Player := preload("res://scripts/player.gd")
const BigFrog := preload("res://scripts/big_frog.gd")
const Items := preload("res://scripts/items.gd")
const DropBounce := preload("res://scripts/drop_bounce.gd")

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(Player.MAX_HEALTH == 50, "players have 50 health")
	_check(BigFrog.MAX_HEALTH == 120, "a Big Frog has 120 health")

	# Outside any network this tree acts as the server, as the world does.
	var world := Node3D.new()
	world.name = "World"
	root.add_child(world)
	var floor := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = WorldBoundaryShape3D.new()
	floor.add_child(floor_shape)
	world.add_child(floor)
	var players := Node3D.new()
	players.name = "Players"
	world.add_child(players)

	# A script that fails to load leaves plain nodes behind; don't go on.
	var probe := PLAYER_SCENE.instantiate()
	var loaded: bool = probe.get_script() == Player and FROG_SCENE.instantiate().get_script() == BigFrog
	probe.free()
	_check(loaded, "the player and frog scripts load")
	if loaded:
		await _check_player_health(players)
		await _check_stamina(players)
		await _check_poison(players)
		await _check_frog(world, players)
		await _check_loot()

	world.queue_free()
	print("Combat: %s" % ("all checks passed" if _failures == 0 else "%d checks failed" % _failures))
	quit(1 if _failures > 0 else 0)


func _check_loot() -> void:
	var meat := 0
	var bile := 0
	var rolls := 4000
	for roll in rolls:
		for drop in BigFrog.roll_loot():
			_check(drop[1] == 1, "drops one at a time (%s)" % [drop])
			if drop[0] == "frog_meat":
				meat += 1
			elif drop[0] == "frog_bile":
				bile += 1
	_check(meat == rolls, "always drops Frog Meat (%d of %d)" % [meat, rolls])
	var chance := float(bile) / rolls
	_check(chance > 0.12 and chance < 0.18, "drops Frog Bile about 15%% of the time (%.1f%%)" % (chance * 100.0))
	for item in ["frog_meat", "frog_bile"]:
		_check(Items.is_valid(item), "%s is an item" % item)

	# A dead frog throws its loot out of its body onto the ground around it.
	var catcher_script := GDScript.new()
	catcher_script.source_code = """extends Node3D
var dropped := []
func spawn_item(item: String, count: int, spot: Vector3, from := Vector3.INF) -> void:
	dropped.append([item, count, spot, from])
"""
	catcher_script.reload()
	var catcher := Node3D.new()
	catcher.set_script(catcher_script)
	root.add_child(catcher)
	var frog := FROG_SCENE.instantiate()
	frog.world = catcher
	frog.position = Vector3(-40.0, 0.0, 0.0)
	catcher.add_child(frog)
	await physics_frame
	frog.take_damage(BigFrog.MAX_HEALTH, 0)
	var meat_drop: Array = catcher.dropped.filter(func(d: Array) -> bool: return d[0] == "frog_meat")
	_check(meat_drop.size() == 1, "a killed frog drops its meat (%s)" % [catcher.dropped])
	if meat_drop.size() == 1:
		var spot: Vector3 = meat_drop[0][2]
		var from: Vector3 = meat_drop[0][3]
		var gap := Vector2(spot.x - frog.position.x, spot.z - frog.position.z).length()
		_check(gap >= BigFrog.LOOT_SPREAD.x - 0.01 and gap <= BigFrog.LOOT_SPREAD.y + 0.01,
			"lands a little way off the frog (%.2f m)" % gap)
		_check(from.is_finite() and from.y > frog.position.y and Vector2(from.x - frog.position.x, from.z - frog.position.z).length() < 0.1,
			"flies out of the frog's body (%s)" % [from])
	catcher.queue_free()

	# Dropped things fly out of where they came from, bounce, and lie still.
	var launch := Vector3(1.0, 1.5, 0.0)
	var start = DropBounce.pose(0.0, launch)
	_check(start != null and start[0].is_equal_approx(launch), "a drop starts where it came out of (%s)" % [start])
	var landed = DropBounce.pose(DropBounce.FLIGHT_SECONDS + 0.001, launch)
	_check(landed != null and landed[0].length() < 0.05 and landed[1] < 1.0, "lands where it lies, squashed (%s)" % [landed])
	var highest := 0.0
	var t := DropBounce.FLIGHT_SECONDS
	while t < DropBounce.drop_seconds():
		var pose = DropBounce.pose(t, launch)
		if pose != null:
			highest = maxf(highest, pose[0].y)
		t += 0.01
	_check(highest > 0.25 and highest <= DropBounce.BOUNCES[0] + 0.001, "bounces up after landing (%.2f m)" % highest)
	_check(DropBounce.pose(DropBounce.drop_seconds() + 0.01, launch) == null, "and then lies still")


func _check_player_health(players: Node3D) -> void:
	var player := _add_player(players, "2", Vector3(30.0, 0.0, 0.0))
	await physics_frame
	_check(player.health == Player.MAX_HEALTH, "a player starts at full health")
	var changes := []
	player.health_changed.connect(func(new: int, old: int) -> void: changes.append([new, old]))
	var kills := []
	player.killed.connect(func(by: String) -> void: kills.append(by))
	_check(player.take_damage(5, "a test") and player.health == 45, "taking damage lowers health")
	_check(changes == [[45, 50]], "everyone hears health changed (%s)" % [changes])
	_check(not player.take_damage(0, "a test") and player.health == 45, "no damage, no change")

	# Health comes back a point at a time, but only after a while unhurt.
	player._physics_process(Player.REGEN_SECONDS)
	_check(player.health == 45, "health doesn't come back straight after being hurt")
	player._since_hurt = Player.REGEN_DELAY
	player._physics_process(Player.REGEN_SECONDS)
	_check(player.health == 46, "health comes back once unhurt for a while")

	_check(player.take_damage(100, "a test") and player.health == 0, "health stops at 0")
	_check(kills == ["a test"], "a player at 0 health is killed, by what hurt them (%s)" % [kills])
	_check(not player.take_damage(5, "a test") and kills.size() == 1, "can't hurt a dead player")
	player._since_hurt = Player.REGEN_DELAY
	player._physics_process(Player.REGEN_SECONDS * 2.0)
	_check(player.health == 0, "the dead don't heal")
	player.restore_health()
	_check(player.health == Player.MAX_HEALTH, "back to full health after dying")
	player.queue_free()
	await process_frame


func _check_stamina(players: Node3D) -> void:
	var player := _add_player(players, "6", Vector3(-30.0, 0.0, 0.0))
	await physics_frame
	var input: Node = player.get_node("PlayerInput")
	_check(player.stamina == Player.MAX_STAMINA, "a player starts with full stamina")

	# Attacks cost stamina, and can't be paid for once it's low.
	_check(player.spend_stamina(Player.ATTACK_STAMINA) and player.stamina == Player.MAX_STAMINA - Player.ATTACK_STAMINA,
		"an attack uses %d stamina" % Player.ATTACK_STAMINA)
	player.stamina = Player.ATTACK_STAMINA - 1.0
	_check(not player.spend_stamina(Player.ATTACK_STAMINA) and player.stamina == Player.ATTACK_STAMINA - 1.0,
		"can't attack without enough stamina")

	# Sprinting is faster and burns stamina while moving.
	player.stamina = Player.MAX_STAMINA
	input.direction = Vector2(0.0, -1.0)
	input.sprinting = true
	player._physics_process(0.5)
	_check(is_equal_approx(Vector2(player.velocity.x, player.velocity.z).length(), Player.SPRINT_SPEED),
		"sprinting runs at %.1f (%.2f)" % [Player.SPRINT_SPEED, Vector2(player.velocity.x, player.velocity.z).length()])
	_check(is_equal_approx(player.stamina, Player.MAX_STAMINA - Player.SPRINT_STAMINA * 0.5),
		"sprinting uses stamina (%.1f)" % player.stamina)
	input.direction = Vector2.ZERO
	player._physics_process(0.5)
	_check(is_equal_approx(player.stamina, Player.MAX_STAMINA - Player.SPRINT_STAMINA * 0.5),
		"standing still with sprint held uses none")

	# Run dry and sprinting stops, until it has come back a bit.
	input.direction = Vector2(0.0, -1.0)
	player._physics_process(Player.MAX_STAMINA / Player.SPRINT_STAMINA)
	_check(player.stamina == 0.0, "sprinting can run stamina out")
	player._physics_process(0.1)
	_check(not player.is_sprinting() and is_equal_approx(Vector2(player.velocity.x, player.velocity.z).length(), Player.SPEED),
		"out of stamina, back to a normal run")
	_check(player.stamina == 0.0, "stamina doesn't come back straight after using it")
	input.sprinting = false
	player._since_tired = Player.STAMINA_REGEN_DELAY
	player._physics_process(0.2)
	_check(player.stamina > 0.0 and player.stamina < Player.SPRINT_RECOVER, "stamina comes back after a moment (%.1f)" % player.stamina)
	input.sprinting = true
	_check(not player.is_sprinting(), "can't sprint again straight away")
	input.sprinting = false
	player._physics_process(Player.MAX_STAMINA / Player.STAMINA_REGEN)
	_check(player.stamina == Player.MAX_STAMINA, "stamina comes back to full within a few seconds")
	input.sprinting = true
	_check(player.is_sprinting(), "and sprinting works again")
	input.walking = true
	_check(not player.is_sprinting(), "walking isn't sprinting")
	player.queue_free()
	await process_frame


func _check_poison(players: Node3D) -> void:
	var player := _add_player(players, "7", Vector3(0.0, 0.0, 30.0))
	await physics_frame
	_check(not player.poisoned, "a player starts unpoisoned")
	_check(player.poison(3.0, 2, "a test poison") and player.poisoned, "can be poisoned")
	player._physics_process(Player.POISON_TICK * 0.5)
	_check(player.health == Player.MAX_HEALTH, "poison doesn't hurt straight away")
	player._physics_process(Player.POISON_TICK * 0.5)
	_check(player.health == Player.MAX_HEALTH - 2, "poison takes 2 a tick (health %d)" % player.health)
	player._physics_process(Player.POISON_TICK)
	player._physics_process(Player.POISON_TICK)
	_check(player.health == Player.MAX_HEALTH - 6 and not player.poisoned,
		"and wears off after 3 seconds (health %d, poisoned %s)" % [player.health, player.poisoned])
	player._physics_process(Player.POISON_TICK)
	_check(player.health == Player.MAX_HEALTH - 6, "no more harm once it's worn off")

	var kills := []
	player.killed.connect(func(by: String) -> void: kills.append(by))
	player.health = 2
	player.poison(5.0, 2, "a test poison")
	player._physics_process(Player.POISON_TICK)
	_check(player.health == 0 and kills == ["a test poison"], "poison can kill (%s)" % [kills])
	_check(not player.poisoned, "dying cures poison")
	_check(not player.poison(5.0, 2, "a test poison"), "can't poison the dead")
	player.restore_health()
	player.poison(5.0, 2, "a test poison")
	player.restore_health()
	_check(not player.poisoned, "coming back cures poison")
	player.queue_free()
	await process_frame


func _check_frog(world: Node3D, players: Node3D) -> void:
	var frog := _add_frog(world, Vector3.ZERO)
	_check(frog.prompt_for("").begins_with("Hold a sword"), "says to hold a sword: %s" % frog.prompt_for(""))
	_check(frog.prompt_for("wood_sword").contains("120/120"), "says how much health it has: %s" % frog.prompt_for("wood_sword"))
	_check(frog.prompt_for("stone_axe").begins_with("Hold a sword"), "an axe isn't a weapon")

	# Someone far off is left alone.
	var far := _add_player(players, "3", Vector3(BigFrog.AGGRO_RANGE + 6.0, 0.0, 0.0))
	await _wait(2.0)
	_check(far.health == Player.MAX_HEALTH, "doesn't go after a player far away")
	far.queue_free()

	# Someone a way off gets licked and poisoned, but not straight away: the
	# frog crouches first and the tongue takes a moment to get there.
	var licked := _add_player(players, "8", Vector3(0.0, 0.0, -(BigFrog.LICK_RANGE - 1.0)))
	var hurts := []
	licked.health_changed.connect(func(new: int, old: int) -> void: hurts.append(old - new))
	for step in 180:
		if frog.is_licking():
			break
		await physics_frame
	await _wait(BigFrog.LICK_WINDUP * 0.5)
	_check(frog.is_licking() and hurts.is_empty(), "winds up a lick before it lands (licking %s, %s)" % [frog.is_licking(), hurts])
	await _wait(BigFrog.LICK_WINDUP * 0.5 + BigFrog.LICK_OUT + 0.1)
	_check(hurts.size() > 0 and hurts[0] == BigFrog.LICK_DAMAGE, "licks a player %.0f m off for %d (%s)" % [BigFrog.LICK_RANGE - 1.0, BigFrog.LICK_DAMAGE, hurts])
	_check(licked.poisoned, "the lick poisons them")
	await _wait(BigFrog.POISON_SECONDS + 1.0)
	_check(hurts.count(BigFrog.POISON_DAMAGE) >= 4, "the poison wears their health down (%s)" % [hurts])
	licked.queue_free()
	frog.queue_free()
	await process_frame

	# Someone who steps aside once the tongue's on its way isn't caught.
	frog = _add_frog(world, Vector3.ZERO)
	var dodger := _add_player(players, "9", Vector3(0.0, 0.0, -6.0))
	var dodged := []
	dodger.health_changed.connect(func(new: int, old: int) -> void: dodged.append(old - new))
	for step in 120:
		if frog._lick_reach > 0.0:
			break
		await physics_frame
	_check(frog._lick_reach > 0.0, "lets its tongue go at someone a way off")
	dodger.position.x += 2.0
	await _wait(BigFrog.LICK_OUT + 0.2)
	_check(dodged.is_empty() and not dodger.poisoned, "misses someone who steps aside (%s)" % [dodged])
	frog.rotation.y = 0.0
	var mouth: Vector3 = frog.global_position
	_check(frog.tongue_catches(mouth + Vector3(0.0, 0.0, -6.0), 6.5) and not frog.tongue_catches(mouth + Vector3(2.0, 0.0, -6.0), 6.5)
		and not frog.tongue_catches(mouth + Vector3(0.0, 0.0, 6.0), 6.5), "the tongue only catches what's in its way")
	dodger.queue_free()
	frog.queue_free()
	await process_frame

	# It turns towards someone behind it, but only so fast.
	frog = _add_frog(world, Vector3.ZERO)
	var behind := _add_player(players, "10", Vector3(0.0, 0.0, 3.0))
	await _wait(0.25)
	var turned := absf(rad_to_deg(frog.rotation.y))
	_check(turned > 5.0 and turned <= BigFrog.TURN_DEGREES * 0.3 + 1.0,
		"turns towards someone behind it at no more than %.0f degrees a second (%.0f in 0.25 s)" % [BigFrog.TURN_DEGREES, turned])
	await _wait(180.0 / BigFrog.TURN_DEGREES)
	_check(frog._off_facing(behind.global_position) < 5.0, "and ends up facing them (%.0f degrees off)" % frog._off_facing(behind.global_position))
	behind.queue_free()
	frog.queue_free()
	await process_frame

	# One bite in five misses.
	var hits := 0
	for roll in 4000:
		if BigFrog.bite_hits():
			hits += 1
	var missed := 1.0 - hits / 4000.0
	_check(missed > 0.17 and missed < 0.23, "misses about 20%% of bites (%.1f%%)" % (missed * 100.0))

	frog = _add_frog(world, Vector3.ZERO)
	frog.bite_miss_chance = 0.0

	# Someone close is chased down and bitten.
	var near := _add_player(players, "4", Vector3(4.5, 0.0, 0.0))
	var bites := []
	near.health_changed.connect(func(new: int, old: int) -> void:
		if old - new == BigFrog.DAMAGE:
			bites.append(old - new))
	await _wait(6.0)
	_check(bites.size() > 0, "hops over and bites a player nearby, %d at a time (health %d)" % [BigFrog.DAMAGE, near.health])
	_check(frog.gap_to(near.global_position) < BigFrog.BITE_REACH + 0.6, "ends up next to them (%.2f m)" % frog.gap_to(near.global_position))

	# A player running away past the frog's leash gets away.
	near.position = Vector3(BigFrog.LEASH + 10.0, 0.0, 0.0)
	await _wait(0.5)
	near.restore_health()
	var health: int = near.health
	await _wait(2.0)
	_check(near.health == health, "gives up on a player past its leash")

	# Twelve hits with a wood sword kill it.
	var died := []
	frog.killed.connect(func() -> void: died.append(true))
	var damage := Items.attack_damage("wood_sword")
	_check(frog.take_damage(damage, 0) and frog.health == BigFrog.MAX_HEALTH - damage and frog.is_alive(), "one hit takes %d off" % damage)
	_check(frog.prompt_for("wood_sword").contains("110/120"), "shows its health going down: %s" % frog.prompt_for("wood_sword"))
	for hit in 10:
		frog.take_damage(damage, 0)
	_check(frog.is_alive() and frog.health == damage, "still alive after eleven hits (%d)" % frog.health)
	_check(frog.take_damage(damage, 0) and frog.health == 0 and not frog.is_alive(), "the twelfth hit kills it")
	_check(died.size() == 1, "it says it died")
	_check(not frog.take_damage(damage, 0) and died.size() == 1, "can't hit a dead frog")
	_check(frog.prompt_for("wood_sword") == "", "nothing to say about a dead frog")
	await _wait(BigFrog.DEATH_SECONDS + 0.3)
	_check(not is_instance_valid(frog), "a dead frog goes away")
	near.queue_free()

	# A frog that kills someone leaves them be for a while.
	var victim := _add_player(players, "5", Vector3(0.0, 0.0, -2.0))
	victim.health = BigFrog.DAMAGE
	victim.killed.connect(func(_by: String) -> void: victim.restore_health())
	frog = _add_frog(world, Vector3.ZERO)
	frog.bite_miss_chance = 0.0
	await _wait(2.5)
	_check(victim.health == Player.MAX_HEALTH, "a bite can kill a player (who comes back at full health)")
	await _wait(2.5)
	_check(victim.health == Player.MAX_HEALTH, "the frog leaves them alone after killing them")
	frog.queue_free()
	victim.queue_free()


func _add_player(players: Node3D, peer: String, at: Vector3) -> Node3D:
	var player := PLAYER_SCENE.instantiate()
	player.name = peer
	player.character_name = "Tester " + peer
	player.position = at
	players.add_child(player)
	return player


func _add_frog(world: Node3D, at: Vector3) -> Node3D:
	var frog := FROG_SCENE.instantiate()
	frog.world = world
	frog.position = at
	frog.home = at
	world.add_child(frog)
	return frog


func _wait(seconds: float) -> void:
	await create_timer(seconds, true, true).timeout


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: %s" % what)
