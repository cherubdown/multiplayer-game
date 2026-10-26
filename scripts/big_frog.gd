extends CharacterBody3D
## The Big Frog: the island's first enemy, and a tough one. Frogs live in a
## few patches of the Meadows (see WorldGen.frog_areas()). Each sits by its
## home spot, hopping about now and then, until a player comes close. Then it
## hops after them and bites, taking DAMAGE health per bite (though one bite
## in five misses), until they get away (it won't follow further than LEASH
## from home) or one of them dies. It's no quicker on its feet than that: it
## turns towards whoever it's after at TURN_DEGREES a second, and only hops,
## bites or licks once it's facing them, so a nimble player can run rings
## around it.
##
## From further off, up to LICK_RANGE away, it lashes out its long tongue every
## LICK_SECONDS. It crouches for LICK_WINDUP seconds first, then the tongue
## flies straight out ahead of it, taking LICK_OUT seconds to reach where the
## player was, so they can see it coming and step aside. A lick that lands
## stings for LICK_DAMAGE and poisons the player, who then loses
## POISON_DAMAGE health every second for POISON_SECONDS (see Player.poison()).
## Hitting it with a weapon (see scripts/items.gd) takes the
## weapon's attack off its 120 health, and it goes after whoever hit it.
## Killed, it drops its LOOT, which pops out of it onto the ground.
##
## Server-authoritative like the players: the server runs the frog and
## replicates where it is, which way it faces and its health to every peer
## through ServerSynchronizer, and plays its hops, bites, licks and hurts on
## every peer, with the damage they do floating up as numbers (see
## scripts/damage_numbers.gd). The world spawns it through a MultiplayerSpawner, so it shows up for
## everyone, and a new one turns up in each frog area every hour (see
## scripts/test_world.gd).
##
## It's solid to the ground, trees and rocks, and stops against players, but
## players can walk through it, so it can never pin anyone in place.
##
## Everyone near enough hears it (see scripts/sounds.gd): thumps as it hops,
## croaks now and then and as it crouches for a lick (a warning to dodge), the
## snap of a bite, the thwip and slurp of its tongue,
## a wet smack and a squawk when it's hit, and a long last croak as it dies.
##
## The model is a few chunky shapes built in code and hand painted by the
## characters' shader (see scripts/character_model.gd), so there's nothing to
## import.

const CharacterModel := preload("res://scripts/character_model.gd")
const HealthBar3D := preload("res://scripts/health_bar_3d.gd")
const Items := preload("res://scripts/items.gd")
const Sounds := preload("res://scripts/sounds.gd")
const DamageNumbers := preload("res://scripts/damage_numbers.gd")

const DISPLAY_NAME := "Big Frog"
const MAX_HEALTH := 120
## Health one bite takes off a player, and seconds between bites.
const DAMAGE := 10
const BITE_SECONDS := 1.8
## The chance (0 to 1) that a bite misses.
const BITE_MISS_CHANCE := 0.2
## How fast it turns towards whoever it's after, in degrees a second, and how
## far off facing them it can be and still hop at them, bite or start a lick.
const TURN_DEGREES := 120.0
const HOP_FACING_DEGREES := 40.0
const BITE_FACING_DEGREES := 35.0
const LICK_FACING_DEGREES := 15.0
## How close a player has to come before the frog notices them, and how far
## from home it will chase them.
const AGGRO_RANGE := 10.0
const LEASH := 20.0
## The lick: how far from the frog's edge its tongue reaches, seconds between
## licks, and the health a lick takes straight away. Then the player is
## poisoned for POISON_SECONDS, losing POISON_DAMAGE health every second.
const LICK_RANGE := 8.0
const LICK_SECONDS := 5.0
const LICK_DAMAGE := 2
## Seconds it crouches before the tongue comes out, and seconds the tongue
## takes to reach its end. It only hits whoever's still within LICK_WIDTH of
## the tongue's line when it gets there, and reaches LICK_OVERSHOOT past where
## they stood when it was let go.
const LICK_WINDUP := 0.6
const LICK_OUT := 0.35
const LICK_WIDTH := 0.8
const LICK_OVERSHOOT := 0.5
const POISON_SECONDS := 8.0
const POISON_DAMAGE := 2
## How far it wanders from home when nobody's about.
const WANDER := 2.5
## Hops: how fast and high, and seconds between them while chasing and while
## idle (between the two numbers).
const HOP_SPEED := 3.5
const HOP_UP := 4.0
const CHASE_HOP_SECONDS := 0.5
const IDLE_HOP_SECONDS := Vector2(2.5, 5.0)
## Half the frog's width, for reach: a bite lands within BITE_REACH of the
## frog's edge, and a player's weapon within REACH of it (the server allows
## SERVER_REACH, since it sees players slightly later).
const RADIUS := 0.75
const BITE_REACH := 1.0
const REACH := 1.6
const SERVER_REACH := 2.6
## Seconds between a player's swings, as for tools (see scripts/harvestables.gd).
const SWING_SECONDS := 0.6
## Seconds it ignores everyone after killing a player, heading home.
const CALM_SECONDS := 8.0
## Seconds it lies there after dying before it's gone.
const DEATH_SECONDS := 1.0
## What a dead frog drops: item, how many, and the chance (0 to 1) of
## dropping it at all.
const LOOT := [
	["frog_meat", 1, 1.0],
	["frog_bile", 1, 0.15],
]
## How far from the frog's middle its loot lands.
const LOOT_SPREAD := Vector2(0.9, 1.6)
## The chance it croaks as it hops.
const CROAK_CHANCE := 0.3

## Server side: the frog died.
signal killed

## Replicated: health left, and set by the server.
@export var health := MAX_HEALTH:
	set(value):
		var was_alive := health > 0
		health = clampi(value, 0, MAX_HEALTH)
		if _health_bar != null:
			_health_bar.fraction = float(health) / MAX_HEALTH
		if health <= 0:
			_show_dead()
			if was_alive and is_inside_tree():
				Sounds.play_on(self, "frog_death")

## Server side: the world, for finding players; where the frog lives.
var world: Node
var home := Vector3.ZERO
## Server side: which of the world's frog areas it lives in (-1 for none).
var area := -1

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
## Server side: the player being chased, or null.
var _target: Node3D
var _hop_in := 1.0
var _bite_in := 0.0
var _lick_in := 0.0
var _calm_for := 0.0
## Server side: the chance a bite misses, BITE_MISS_CHANCE (tests change it).
var bite_miss_chance := BITE_MISS_CHANCE
## Server side, while licking: who at, seconds since it started, and once the
## tongue's out, how far from the frog's middle it reaches (0 before then).
var _lick_at: Node3D
var _lick_time := -1.0
var _lick_reach := 0.0
var _last_swing := {}  # peer -> Time.get_ticks_msec() of their last swing at the frog
var _model: Node3D
## The tongue, hidden in the mouth until a lick: the pink part, and its
## poisonous tip.
var _tongue: Node3D
var _tongue_tip: Node3D
var _health_bar: HealthBar3D


func _ready() -> void:
	add_to_group("enemies")
	if multiplayer.is_server() and home == Vector3.ZERO:
		home = position
	if CharacterModel.can_show_models():
		_build_model()


## Whether it's still alive.
func is_alive() -> bool:
	return health > 0


## How far `point` is from the frog's edge, across the ground.
func gap_to(point: Vector3) -> float:
	return Vector2(global_position.x - point.x, global_position.z - point.z).length() - RADIUS


## What the on-screen prompt says about the frog, holding `held` (an item id).
func prompt_for(held: String) -> String:
	if not is_alive():
		return ""
	if not Items.is_weapon(held):
		return "Hold a sword to fight the %s (%d/%d)" % [DISPLAY_NAME, health, MAX_HEALTH]
	return "[Left click] Attack the %s (%d/%d)" % [DISPLAY_NAME, health, MAX_HEALTH]


## Client side: swing the held weapon at the frog, looking towards `yaw`.
func attack(yaw: float) -> void:
	_request_hit.rpc_id(1, yaw)


## Server side: takes `amount` health off the frog. `peer` is who did it (0
## for nobody); it goes after them. Returns whether it counted.
func take_damage(amount: int, peer := 0) -> bool:
	if not is_alive() or amount <= 0:
		return false
	health -= amount
	_play_hurt.rpc()
	if peer != 0 and world != null:
		var attacker := world.get_node_or_null("Players/%d" % peer) as Node3D
		if attacker != null:
			_target = attacker
			_calm_for = 0.0
	_pop_number.rpc(-amount)
	if health <= 0:
		print("A %s was killed" % DISPLAY_NAME)
		_target = null
		_lick_time = -1.0
		velocity = Vector3.ZERO
		collision_layer = 0
		killed.emit()
		_drop_loot()
		get_tree().create_timer(DEATH_SECONDS).timeout.connect(queue_free)
	return true


## What one dead frog drops, rolled from LOOT: [item, count] pairs.
static func roll_loot() -> Array:
	var drops := []
	for loot in LOOT:
		if randf() < loot[2]:
			drops.append([loot[0], loot[1]])
	return drops


## Server side: throws the loot out of the frog's body onto the ground around
## it, each piece in its own direction.
func _drop_loot() -> void:
	if world == null or not world.has_method("spawn_item"):
		return
	var from := global_position + Vector3.UP * 0.6
	var angle := randf() * TAU
	for drop in roll_loot():
		var away := Vector2.from_angle(angle) * randf_range(LOOT_SPREAD.x, LOOT_SPREAD.y)
		angle += TAU / LOOT.size() + randf_range(-0.5, 0.5)
		world.spawn_item(drop[0], drop[1], global_position + Vector3(away.x, 0.0, away.y), from)


## Whether a bite hits, rolled from `miss_chance`.
static func bite_hits(miss_chance := BITE_MISS_CHANCE) -> bool:
	return randf() >= miss_chance


## Whether it's in the middle of a lick, crouched or with its tongue out.
func is_licking() -> bool:
	return _lick_time >= 0.0


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if is_alive():
		# Turns towards whoever it's after, but not once its tongue is out:
		# the lick goes where it was facing then.
		if _target != null and is_instance_valid(_target) and _lick_reach <= 0.0:
			_turn_towards(_target.global_position, delta)
		if is_licking():
			_lick(delta)
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif velocity.y <= 0.0:
		# Lands and sits still between hops.
		velocity.x = 0.0
		velocity.z = 0.0
		if is_alive():
			_think(delta)
	move_and_slide()


## Server side, on the ground: chase, bite, go home or wander.
func _think(delta: float) -> void:
	_hop_in -= delta
	_bite_in -= delta
	_lick_in -= delta
	_calm_for -= delta
	var was_chasing := _target != null
	_target = _pick_target() if _calm_for <= 0.0 else null
	if _target != null:
		if not was_chasing:
			# Spotted someone: no more lazing about.
			_hop_in = minf(_hop_in, CHASE_HOP_SECONDS)
		if is_licking():
			# Sits still until the tongue's back.
			return
		var gap := gap_to(_target.global_position)
		var off := _off_facing(_target.global_position)
		if gap <= BITE_REACH + 0.5:
			if _bite_in <= 0.0 and off <= BITE_FACING_DEGREES:
				_bite_in = BITE_SECONDS
				_play_bite.rpc()
				if bite_hits(bite_miss_chance):
					_hurt(_target, DAMAGE)
				else:
					_target.show_miss()
		elif gap <= LICK_RANGE and _lick_in <= 0.0 and off <= LICK_FACING_DEGREES:
			_lick_in = LICK_SECONDS
			_lick_at = _target
			_lick_time = 0.0
			_lick_reach = 0.0
			_play_crouch.rpc(LICK_WINDUP)
		elif _hop_in <= 0.0 and off <= HOP_FACING_DEGREES:
			_hop_towards(_target.global_position, CHASE_HOP_SECONDS, false)
		return
	if _hop_in > 0.0:
		return
	var away := Vector2(global_position.x - home.x, global_position.z - home.z).length()
	if away > WANDER:
		_hop_towards(home, randf_range(IDLE_HOP_SECONDS.x, IDLE_HOP_SECONDS.y) * 0.3)
	else:
		var spot := home + Vector3(randf_range(-WANDER, WANDER), 0.0, randf_range(-WANDER, WANDER))
		_hop_towards(spot, randf_range(IDLE_HOP_SECONDS.x, IDLE_HOP_SECONDS.y))


## Server side, licking: crouches for LICK_WINDUP, then lets the tongue go
## straight ahead, and LICK_OUT later sees whether it caught anyone.
func _lick(delta: float) -> void:
	_lick_time += delta
	if _lick_reach <= 0.0:
		if _lick_time < LICK_WINDUP:
			return
		var reach := RADIUS + LICK_RANGE
		if is_instance_valid(_lick_at) and _lick_at.is_inside_tree():
			reach = minf(gap_to(_lick_at.global_position) + RADIUS + LICK_OVERSHOOT, reach)
		_lick_reach = reach
		_play_lick.rpc(_lick_reach, LICK_OUT)
		return
	if _lick_time < LICK_WINDUP + LICK_OUT:
		return
	var victim := _lick_at
	var reach := _lick_reach
	_lick_at = null
	_lick_time = -1.0
	_lick_reach = 0.0
	# A short pause while the tongue rolls back in.
	_hop_in = maxf(_hop_in, 0.4)
	if not is_instance_valid(victim) or not victim.is_inside_tree() or victim.health <= 0:
		return
	if not tongue_catches(victim.global_position, reach):
		victim.show_miss()
		return
	_hurt(victim, LICK_DAMAGE)
	if victim.health > 0:
		victim.poison(POISON_SECONDS, POISON_DAMAGE, "a %s's poison" % DISPLAY_NAME)


## Whether the tongue, let go from where the frog faces now and reaching
## `reach` from its middle, catches someone standing at `point`.
func tongue_catches(point: Vector3, reach: float) -> bool:
	var ahead := Vector2(-sin(rotation.y), -cos(rotation.y))
	var at := Vector2(point.x - global_position.x, point.z - global_position.z)
	var along := at.dot(ahead)
	var aside := absf(at.cross(ahead))
	return along >= 0.0 and along <= reach + LICK_WIDTH * 0.5 and aside <= LICK_WIDTH


## Server side: takes `amount` off `player`. If that kills them, they come
## back at the spawn; it leaves them be for a bit.
func _hurt(player: Node3D, amount: int) -> void:
	var fatal: bool = player.health <= amount
	player.take_damage(amount, "a " + DISPLAY_NAME)
	if fatal:
		if _target == player:
			_target = null
		_calm_for = CALM_SECONDS


## The player to go after: whoever it's already chasing while they're still
## alive and near enough to home, else the nearest one that's come close.
func _pick_target() -> Node3D:
	if is_instance_valid(_target) and _target.is_inside_tree() and _target.health > 0 \
			and _from_home(_target.global_position) <= LEASH:
		return _target
	if world == null:
		return null
	var best: Node3D = null
	var best_gap := AGGRO_RANGE
	for player: Node3D in world.get_node("Players").get_children():
		var gap := gap_to(player.global_position)
		if player.health > 0 and gap <= best_gap and _from_home(player.global_position) <= LEASH:
			best = player
			best_gap = gap
	return best


func _from_home(point: Vector3) -> float:
	return Vector2(point.x - home.x, point.z - home.z).length()


## The way to face to look at `point`, or its current way if it's right on it.
func _yaw_to(point: Vector3) -> float:
	var at := point - global_position
	if Vector2(at.x, at.z).length() <= 0.01:
		return rotation.y
	return atan2(-at.x, -at.z)


## How many degrees it would have to turn to face `point`.
func _off_facing(point: Vector3) -> float:
	return absf(rad_to_deg(angle_difference(rotation.y, _yaw_to(point))))


func _face(point: Vector3) -> void:
	rotation.y = _yaw_to(point)


## Turns towards `point` at no more than TURN_DEGREES a second.
func _turn_towards(point: Vector3, delta: float) -> void:
	rotation.y = wrapf(rotate_toward(rotation.y, _yaw_to(point), deg_to_rad(TURN_DEGREES) * delta), -PI, PI)


## One hop towards `point`, landing short of it rather than overshooting.
## Turns to face it first if `turn`; when chasing, it turns on its own (see
## _turn_towards()).
func _hop_towards(point: Vector3, wait: float, turn := true) -> void:
	if turn:
		_face(point)
	_hop_in = wait
	var at := Vector2(point.x - global_position.x, point.z - global_position.z)
	var airtime := 2.0 * HOP_UP / gravity
	var speed := minf(HOP_SPEED, maxf(at.length() - RADIUS, 0.0) / airtime)
	if speed < 0.2:
		return
	var dir := at.normalized() * speed
	velocity = Vector3(dir.x, HOP_UP, dir.y)
	_play_hop.rpc()


# --- Network ----------------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func _request_hit(yaw) -> void:
	if not multiplayer.is_server() or not (yaw is float or yaw is int):
		return
	var peer := multiplayer.get_remote_sender_id()
	# Looked up rather than named, so tests can load this without autoloads.
	var session := get_node("/root/Session")
	var body: Node3D = session.body_of(peer)
	var held: String = session.held_of(peer)
	if body == null or not Items.is_weapon(held) or not is_alive() or body.health <= 0:
		return
	var now := Time.get_ticks_msec()
	if now - _last_swing.get(peer, -100000) < int(SWING_SECONDS * 1000.0 * 0.8):
		return
	if not body.spend_stamina(body.ATTACK_STAMINA):
		return
	_last_swing[peer] = now
	if gap_to(body.global_position) > SERVER_REACH:
		body.swing(float(yaw))
		return
	var at := global_position - body.global_position
	body.swing(atan2(-at.x, -at.z))
	take_damage(Items.attack_damage(held), peer)


@rpc("authority", "call_local", "unreliable")
func _play_hop() -> void:
	Sounds.play_on(self, "frog_hop")
	if randf() < CROAK_CHANCE:
		Sounds.play_on(self, "frog_croak")
	if _model == null:
		return
	var tween := create_tween()
	tween.tween_property(_model, "scale", Vector3(0.9, 1.25, 1.1), 0.12)
	tween.tween_property(_model, "scale", Vector3.ONE, 0.5)


@rpc("authority", "call_local", "unreliable")
func _play_bite() -> void:
	Sounds.play_on(self, "frog_bite")
	if _model == null:
		return
	var tween := create_tween()
	tween.tween_property(_model, "position:z", -0.45, 0.08)
	tween.tween_property(_model, "position:z", 0.0, 0.25)


## Crouches down, puffing out, for `seconds` before a lick.
@rpc("authority", "call_local", "unreliable")
func _play_crouch(seconds) -> void:
	Sounds.play_on(self, "frog_croak")
	if _model == null or not (seconds is float or seconds is int):
		return
	var tween := create_tween()
	tween.tween_property(_model, "scale", Vector3(1.12, 0.8, 1.05), float(seconds) * 0.85) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_property(_model, "position:z", 0.2, float(seconds) * 0.85)
	tween.tween_property(_model, "scale", Vector3(0.95, 1.1, 1.0), float(seconds) * 0.15)
	tween.parallel().tween_property(_model, "position:z", 0.0, float(seconds) * 0.15)
	tween.tween_property(_model, "scale", Vector3.ONE, 0.2)


## Shoots the tongue out `reach` meters from the frog's middle, taking
## `seconds` to get there, and back.
@rpc("authority", "call_local", "unreliable")
func _play_lick(reach, seconds) -> void:
	Sounds.play_on(self, "tongue_lick")
	if _tongue == null or not (reach is float or reach is int) or not (seconds is float or seconds is int):
		return
	var length := maxf(float(reach) - 0.85, 0.3)
	var tween := create_tween()
	tween.tween_callback(func() -> void: _tongue.visible = true)
	tween.tween_method(_set_tongue, 0.05, length, float(seconds)).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_interval(0.08)
	tween.tween_method(_set_tongue, length, 0.05, 0.22)
	tween.tween_callback(func() -> void: _tongue.visible = false)


## Stretches the tongue `length` meters out of the mouth.
func _set_tongue(length: float) -> void:
	var pink := _tongue.get_child(0) as Node3D
	pink.scale.z = length
	pink.position.z = -length * 0.5
	_tongue_tip.position.z = -length


@rpc("authority", "call_local", "unreliable")
func _play_hurt() -> void:
	Sounds.play_on(self, "hit_flesh")
	Sounds.play_on(self, "frog_hurt")
	if _model != null:
		CharacterModel.flash_meshes(_model, Color(1.0, 0.9, 0.9))


## Floats `amount` up over the frog: negative for damage.
@rpc("authority", "call_local", "unreliable")
func _pop_number(amount) -> void:
	if amount is int:
		DamageNumbers.pop(self, amount, 2.0)


# --- The model --------------------------------------------------------------

func _build_model() -> void:
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	var Paint := CharacterModel
	var skin := Paint.paint(Paint.WARTY, Color(0.34, 0.48, 0.2))
	var belly := Paint.paint(Paint.SKIN, Color(0.82, 0.8, 0.52))
	var gold := Paint.paint(Paint.METAL, Color(0.95, 0.7, 0.18))
	var dark := Paint.paint(Paint.SKIN, Color(0.1, 0.07, 0.06))
	var mouth := Paint.paint(Paint.SKIN, Color(0.55, 0.22, 0.2))
	# Faces -Z, like the players. A squat, chunky body with a huge head.
	_add(_ellipsoid(Vector3(0.78, 0.52, 0.85)), skin, Vector3(0.0, 0.55, 0.08), Vector3(deg_to_rad(-12.0), 0.0, 0.0))
	_add(_ellipsoid(Vector3(0.66, 0.34, 0.72)), belly, Vector3(0.0, 0.36, -0.05))
	_add(_ellipsoid(Vector3(0.66, 0.34, 0.5)), skin, Vector3(0.0, 0.76, -0.55))
	# A pale throat pouch under a wide, grumpy mouth with a thick lip.
	_add(_ellipsoid(Vector3(0.5, 0.2, 0.32)), belly, Vector3(0.0, 0.5, -0.72))
	_add(_ellipsoid(Vector3(0.62, 0.06, 0.2)), mouth, Vector3(0.0, 0.66, -0.88))
	_add(_ellipsoid(Vector3(0.6, 0.1, 0.16)), skin, Vector3(0.0, 0.72, -0.86), Vector3(deg_to_rad(-8.0), 0.0, 0.0))
	# Ridges down the back.
	for side in [-1.0, 1.0]:
		_add(_ellipsoid(Vector3(0.09, 0.08, 0.6)), skin, Vector3(0.3 * side, 1.0, 0.05), Vector3(deg_to_rad(-14.0), 0.0, 0.0))
		# Big bulging eyes: a lump of skin, a gold eye with a flat black
		# pupil, and a glint.
		_add(_ellipsoid(Vector3(0.22, 0.2, 0.22)), skin, Vector3(0.34 * side, 1.0, -0.58))
		_add(_ellipsoid(Vector3(0.17, 0.17, 0.12)), gold, Vector3(0.37 * side, 1.05, -0.72), Vector3(0.0, deg_to_rad(18.0 * side), 0.0))
		_add(_ellipsoid(Vector3(0.11, 0.05, 0.05)), dark, Vector3(0.38 * side, 1.05, -0.82), Vector3(0.0, deg_to_rad(18.0 * side), 0.0))
		_add(_ellipsoid(Vector3(0.03, 0.03, 0.02)), Paint.paint(Paint.SKIN, Color(1.0, 0.98, 0.9)), Vector3(0.34 * side, 1.1, -0.84))
		# A heavy brow over each eye.
		_add(_ellipsoid(Vector3(0.2, 0.06, 0.12)), skin, Vector3(0.34 * side, 1.17, -0.66), Vector3(0.0, 0.0, deg_to_rad(14.0 * side)))
		# Thick folded back legs with big webbed feet.
		_add(_ellipsoid(Vector3(0.3, 0.27, 0.52)), skin, Vector3(0.64 * side, 0.32, 0.42))
		_add(_ellipsoid(Vector3(0.18, 0.12, 0.38)), skin, Vector3(0.74 * side, 0.12, 0.1))
		for toe in 3:
			var spread := deg_to_rad((toe - 1) * 22.0 + 10.0 * side)
			_add(_ellipsoid(Vector3(0.07, 0.04, 0.2)), skin, Vector3(0.74 * side + sin(spread) * 0.2, 0.04, -0.2 - cos(spread) * 0.08), Vector3(0.0, -spread, 0.0))
		# Stubby front legs with splayed fingers.
		_add(_ellipsoid(Vector3(0.1, 0.22, 0.1)), skin, Vector3(0.44 * side, 0.22, -0.6), Vector3(0.0, 0.0, deg_to_rad(-12.0 * side)))
		for toe in 3:
			var spread := deg_to_rad((toe - 1) * 30.0 + 15.0 * side)
			_add(_ellipsoid(Vector3(0.05, 0.035, 0.13)), skin, Vector3(0.48 * side + sin(spread) * 0.1, 0.03, -0.68 - cos(spread) * 0.08), Vector3(0.0, -spread, 0.0))

	# The tongue, rolled up in the mouth until it licks (see _play_lick()).
	# The pink part is a meter long at scale 1 and stretched to reach.
	_tongue = Node3D.new()
	_tongue.name = "Tongue"
	_tongue.position = Vector3(0.0, 0.64, -0.85)
	_tongue.visible = false
	_model.add_child(_tongue)
	var tongue_paint := Paint.paint(Paint.SKIN, Color(0.85, 0.36, 0.42))
	var pink := _add(_ellipsoid(Vector3(0.08, 0.035, 0.5)), tongue_paint, Vector3.ZERO, Vector3.ZERO, _tongue)
	pink.scale.z = 0.05
	_tongue_tip = _add(_ellipsoid(Vector3(0.14, 0.08, 0.12)), Paint.paint(Paint.SKIN, Color(0.55, 0.85, 0.2)),
		Vector3.ZERO, Vector3.ZERO, _tongue)

	var label := Label3D.new()
	label.name = "Nameplate"
	label.text = DISPLAY_NAME
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 40
	label.outline_size = 10
	label.position.y = 1.75
	add_child(label)
	_health_bar = HealthBar3D.new()
	_health_bar.name = "HealthBar"
	_health_bar.position.y = 1.55
	_health_bar.fraction = float(health) / MAX_HEALTH
	add_child(_health_bar)
	if health <= 0:
		_show_dead()


## Belly up.
func _show_dead() -> void:
	if _model != null:
		_model.rotation.z = PI
		_model.position.y = 1.1


func _add(mesh: Mesh, material: Material, at: Vector3, turn := Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	instance.rotation = turn
	(parent if parent != null else _model).add_child(instance)
	return instance


func _ellipsoid(radii: Vector3) -> Mesh:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	# Few sides, for the same chunky look as the characters.
	sphere.radial_segments = 8
	sphere.rings = 4
	var st := SurfaceTool.new()
	st.append_from(sphere, 0, Transform3D(Basis.from_scale(radii), Vector3.ZERO))
	return st.commit()

