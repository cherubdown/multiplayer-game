extends SceneTree
## Checks player health, stamina and frogs without a network: taking
## damage, dying, health coming back, sprinting and attacking using stamina,
## poison wearing health down and wearing off, a frog turning towards
## players, chasing down and biting the player it was sent after (missing one
## bite in four), going after someone else nearby once its player is gone and
## giving up when there's nobody, dying to three wood sword hits or two stone
## sword hits, and what it drops: Frog Meat now and then and Frog Bile
## rarely, popping out of it and bouncing to a stop. Run from the project folder:
##   godot --headless --path . -s tests/test_combat.gd
## Exits non-zero if any check fails.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const FROG_SCENE := preload("res://scenes/frog.tscn")
const Player := preload("res://scripts/player.gd")
const Frog := preload("res://scripts/frog.gd")
const Items := preload("res://scripts/items.gd")
const DropBounce := preload("res://scripts/drop_bounce.gd")

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(Player.MAX_HEALTH == 50, "players have 50 health")
	_check(Frog.MAX_HEALTH == 25, "a frog has 25 health")

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
	var loaded: bool = probe.get_script() == Player and FROG_SCENE.instantiate().get_script() == Frog
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
		for drop in Frog.roll_loot():
			_check(drop[1] == 1, "drops one at a time (%s)" % [drop])
			if drop[0] == "frog_meat":
				meat += 1
			elif drop[0] == "frog_bile":
				bile += 1
	var chance := float(meat) / rolls
	_check(chance > 0.26 and chance < 0.34, "drops Frog Meat about 30%% of the time (%.1f%%)" % (chance * 100.0))
	chance = float(bile) / rolls
	_check(chance > 0.03 and chance < 0.07, "drops Frog Bile about 5%% of the time (%.1f%%)" % (chance * 100.0))
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
	# Kills frogs until one drops some meat.
	var frog: Node3D = null
	for attempt in 60:
		frog = FROG_SCENE.instantiate()
		frog.world = catcher
		frog.position = Vector3(-40.0, 0.0, 0.0)
		catcher.add_child(frog)
		frog.take_damage(Frog.MAX_HEALTH, 0)
		if catcher.dropped.any(func(d: Array) -> bool: return d[0] == "frog_meat"):
			break
		frog.free()
		frog = null
	var meat_drop: Array = catcher.dropped.filter(func(d: Array) -> bool: return d[0] == "frog_meat")
	_check(meat_drop.size() == 1, "a killed frog drops its meat (%s)" % [catcher.dropped])
	if meat_drop.size() == 1:
		var spot: Vector3 = meat_drop[0][2]
		var from: Vector3 = meat_drop[0][3]
		var gap := Vector2(spot.x - frog.position.x, spot.z - frog.position.z).length()
		_check(gap >= Frog.LOOT_SPREAD.x - 0.01 and gap <= Frog.LOOT_SPREAD.y + 0.01,
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
	_check(frog.prompt_for("wood_sword").contains("25/25"), "says how much health it has: %s" % frog.prompt_for("wood_sword"))
	_check(frog.prompt_for("stone_axe").begins_with("Hold a sword"), "an axe isn't a weapon")

	# It turns towards the player it's after, quickly but not instantly.
	var behind := _add_player(players, "3", Vector3(0.0, 0.0, 6.0))
	frog.prey = behind
	frog.rotation.y = 0.0
	await _wait(0.1)
	var turned := absf(rad_to_deg(frog.rotation.y))
	_check(turned > 5.0 and turned <= Frog.TURN_DEGREES * 0.15 + 1.0,
		"turns towards someone behind it at no more than %.0f degrees a second (%.0f in 0.1 s)" % [Frog.TURN_DEGREES, turned])
	await _wait(0.6)
	_check(frog._off_facing(behind.global_position) < 10.0, "and ends up facing them (%.0f degrees off)" % frog._off_facing(behind.global_position))
	behind.queue_free()
	frog.queue_free()
	await process_frame

	# One bite in four misses.
	var hits := 0
	for roll in 4000:
		if Frog.bite_hits():
			hits += 1
	var missed := 1.0 - hits / 4000.0
	_check(missed > 0.21 and missed < 0.29, "misses about 25%% of bites (%.1f%%)" % (missed * 100.0))

	# The player it was sent after, a way off, is chased down and bitten.
	var prey := _add_player(players, "4", Vector3(10.0, 0.0, 0.0))
	frog = _add_frog(world, Vector3.ZERO)
	frog.prey = prey
	frog.bite_miss_chance = 0.0
	var bites := []
	prey.health_changed.connect(func(new: int, old: int) -> void:
		if old - new == Frog.DAMAGE:
			bites.append(old - new))
	await _wait(6.0)
	_check(bites.size() > 0, "hops over and bites the player it's after, %d at a time (health %d)" % [Frog.DAMAGE, prey.health])
	_check(frog.gap_to(prey.global_position) < Frog.BITE_REACH + 0.6, "ends up next to them (%.2f m)" % frog.gap_to(prey.global_position))
	_check(bites.size() <= ceili(6.0 / Frog.BITE_SECONDS), "bites no more than every %.1f s (%d bites)" % [Frog.BITE_SECONDS, bites.size()])

	# Its player gone, it goes after someone else nearby.
	var other := _add_player(players, "9", frog.position + Vector3(0.0, 0.0, 5.0))
	prey.queue_free()
	await _wait(3.0)
	_check(is_instance_valid(frog) and frog.gap_to(other.global_position) < Frog.BITE_REACH + 0.6,
		"goes after someone else nearby once its player is gone")

	# Three hits with a wood sword kill it, and it goes away.
	var died := []
	frog.killed.connect(func() -> void: died.append(true))
	var damage := Items.attack_damage("wood_sword")
	_check(frog.take_damage(damage, 0) and frog.health == Frog.MAX_HEALTH - damage and frog.is_alive(), "one hit takes %d off" % damage)
	_check(frog.prompt_for("wood_sword").contains("15/25"), "shows its health going down: %s" % frog.prompt_for("wood_sword"))
	frog.take_damage(damage, 0)
	_check(frog.is_alive(), "still alive after two wood sword hits (%d)" % frog.health)
	_check(frog.take_damage(damage, 0) and not frog.is_alive(), "the third hit kills it")
	_check(died.size() == 1, "it says it died")
	_check(not frog.take_damage(damage, 0) and died.size() == 1, "can't hit a dead frog")
	_check(frog.prompt_for("wood_sword") == "", "nothing to say about a dead frog")
	await _wait(Frog.DEATH_SECONDS + 0.3)
	_check(not is_instance_valid(frog), "a dead frog goes away")
	other.queue_free()
	await process_frame

	# Two stone sword hits do it too.
	frog = _add_frog(world, Vector3(20.0, 0.0, 20.0))
	frog.take_damage(Items.attack_damage("stone_sword"), 0)
	_check(frog.is_alive(), "survives one stone sword hit")
	frog.take_damage(Items.attack_damage("stone_sword"), 0)
	_check(not frog.is_alive(), "two stone sword hits kill it")
	await _wait(Frog.DEATH_SECONDS + 0.3)

	# With nobody to chase, it gives up and goes away.
	var far := _add_player(players, "5", Vector3(Frog.AGGRO_RANGE + 10.0, 0.0, 0.0))
	frog = _add_frog(world, Vector3.ZERO)
	await _wait(Frog.GIVE_UP_SECONDS + 1.0)
	_check(not is_instance_valid(frog), "gives up and goes away when nobody is near")
	far.queue_free()
	await process_frame


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
	world.add_child(frog)
	return frog


func _wait(seconds: float) -> void:
	await create_timer(seconds, true, true).timeout


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: %s" % what)
