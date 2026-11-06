extends CharacterBody3D
## A frog: small, weak and never alone. Every WAVE_SECONDS the world puts
## WAVE_SIZE of them in a ring around each player (see
## scripts/test_world.gd), and they hop straight for that player and bite
## them, DAMAGE health a bite (though some bites miss), until they or the
## player die. One goes down in two or three hits from a sword (see
## scripts/items.gd), so the fun is in not being swarmed.
##
## A frog whose player dies, leaves or gets away goes after whoever else is
## near, and if there's nobody it gives up after GIVE_UP_SECONDS and is gone
## (without dropping anything). Killed, it sometimes drops its LOOT, which
## pops out of it onto the ground.
##
## Server-authoritative like the players: the server runs the frog and
## replicates where it is, which way it faces and its health to every peer
## through ServerSynchronizer, and plays its hops, bites and hurts on every
## peer, with the damage they do floating up as numbers (see
## scripts/damage_numbers.gd). The world spawns it through a
## MultiplayerSpawner, so it shows up for everyone.
##
## Frogs are solid to the ground, trees, rocks and each other, so a swarm
## spreads out around you rather than piling into one spot.
##
## Everyone near enough hears them (see scripts/sounds.gd), pitched up for
## their size: thumps as they hop, croaks now and then, the snap of a bite,
## a wet smack and a squawk when one is hit, and a last croak as it dies.
## There are a lot of them, so most hops are quiet.
##
## The model is a few chunky shapes built in code and hand painted by the
## characters' shader (see scripts/character_model.gd), so there's nothing to
## import.

const CharacterModel := preload("res://scripts/character_model.gd")
const HealthBar3D := preload("res://scripts/health_bar_3d.gd")
const Items := preload("res://scripts/items.gd")
const Sounds := preload("res://scripts/sounds.gd")
const DamageNumbers := preload("res://scripts/damage_numbers.gd")

const DISPLAY_NAME := "Frog"
## Two hits from a stone sword (15), three from a wood sword (10).
const MAX_HEALTH := 25
## Health one bite takes off a player, and seconds between one frog's bites.
const DAMAGE := 1
const BITE_SECONDS := 1.5
## The chance (0 to 1) that a bite misses.
const BITE_MISS_CHANCE := 0.25
## How fast it turns towards whoever it's after, in degrees a second, and how
## far off facing them it can be and still hop at them or bite.
const TURN_DEGREES := 360.0
const HOP_FACING_DEGREES := 60.0
const BITE_FACING_DEGREES := 45.0
## How close another player has to be for a frog that lost its own to go
## after them instead, and how far off it loses track of whoever it's after.
const AGGRO_RANGE := 15.0
const LOSE_RANGE := 45.0
## Seconds a frog with nobody to chase hangs about before it's gone.
const GIVE_UP_SECONDS := 3.0
## Hops: how fast and high, and seconds it sits between them while chasing
## (slower than a running player on average, so you can get away).
const HOP_SPEED := 5.0
const HOP_UP := 2.5
const CHASE_HOP_SECONDS := 0.25
## Half the frog's width, for reach: a bite lands within BITE_REACH of the
## frog's edge. Within REACH of it, a player is shown a prompt to attack it
## (a slash reaches a little further: see scripts/slash.gd).
const RADIUS := 0.35
const BITE_REACH := 0.8
const REACH := 1.8
## Seconds it lies there after dying before it's gone.
const DEATH_SECONDS := 1.0
## What a dead frog drops: item, how many, and the chance (0 to 1) of
## dropping it at all. Low, since there are so many of them.
const LOOT := [
	["frog_meat", 1, 0.3],
	["frog_bile", 1, 0.05],
]
## How far from the frog's middle its loot lands.
const LOOT_SPREAD := Vector2(0.5, 1.0)
## The chance a hop makes a sound, and that it croaks as it hops.
const HOP_SOUND_CHANCE := 0.3
const CROAK_CHANCE := 0.06
## How much smaller than full size the model is, and how much higher its
## sounds are.
const MODEL_SCALE := 0.45
const PITCH := 1.6

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
				Sounds.play_on(self, "frog_death", -4.0, PITCH)

## Server side: the world, for finding players.
var world: Node
## Server side: the player it was sent after (see scripts/test_world.gd), and
## the one it's chasing right now, or null.
var prey: Node3D
var _target: Node3D

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _hop_in := 0.0
var _bite_in := 0.0
var _alone_for := 0.0
## Server side: the chance a bite misses, BITE_MISS_CHANCE (tests change it).
var bite_miss_chance := BITE_MISS_CHANCE
var _model: Node3D
var _health_bar: HealthBar3D


func _ready() -> void:
	add_to_group("enemies")
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
	_pop_number.rpc(-amount)
	if health <= 0:
		_target = null
		velocity = Vector3.ZERO
		collision_layer = 0
		collision_mask = 1
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
	var from := global_position + Vector3.UP * 0.3
	var angle := randf() * TAU
	for drop in roll_loot():
		var away := Vector2.from_angle(angle) * randf_range(LOOT_SPREAD.x, LOOT_SPREAD.y)
		angle += TAU / LOOT.size() + randf_range(-0.5, 0.5)
		world.spawn_item(drop[0], drop[1], global_position + Vector3(away.x, 0.0, away.y), from)


## Whether a bite hits, rolled from `miss_chance`.
static func bite_hits(miss_chance := BITE_MISS_CHANCE) -> bool:
	return randf() >= miss_chance


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if is_alive() and _target != null and is_instance_valid(_target):
		_turn_towards(_target.global_position, delta)
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif velocity.y <= 0.0:
		# Lands and sits still between hops.
		velocity.x = 0.0
		velocity.z = 0.0
		if is_alive():
			_think(delta)
	move_and_slide()


## Server side, on the ground: hop after whoever it's chasing and bite them,
## or give up if there's nobody.
func _think(delta: float) -> void:
	_hop_in -= delta
	_bite_in -= delta
	_target = _pick_target()
	if _target == null:
		_alone_for += delta
		if _alone_for >= GIVE_UP_SECONDS:
			queue_free()
		return
	_alone_for = 0.0
	var gap := gap_to(_target.global_position)
	var off := _off_facing(_target.global_position)
	if gap <= BITE_REACH:
		if _bite_in <= 0.0 and off <= BITE_FACING_DEGREES:
			_bite_in = BITE_SECONDS
			_play_bite.rpc()
			if bite_hits(bite_miss_chance):
				_target.take_damage(DAMAGE, "a swarm of frogs")
			else:
				_target.show_miss()
	elif _hop_in <= 0.0 and off <= HOP_FACING_DEGREES:
		_hop_towards(_target.global_position)


## The player to go after: whoever it's already chasing, or the one it was
## sent after, while they're alive and near enough, else the nearest living
## player within AGGRO_RANGE.
func _pick_target() -> Node3D:
	for who in [_target, prey]:
		if _can_chase(who, LOSE_RANGE):
			return who as Node3D
	if world == null:
		return null
	var best: Node3D = null
	var best_gap := AGGRO_RANGE
	for player: Node3D in world.get_node("Players").get_children():
		var gap := gap_to(player.global_position)
		if player.health > 0 and gap <= best_gap:
			best = player
			best_gap = gap
	return best


func _can_chase(who, limit: float) -> bool:
	return is_instance_valid(who) and who.is_inside_tree() and who.health > 0 \
		and gap_to(who.global_position) <= limit


## The way to face to look at `point`, or its current way if it's right on it.
func _yaw_to(point: Vector3) -> float:
	var at := point - global_position
	if Vector2(at.x, at.z).length() <= 0.01:
		return rotation.y
	return atan2(-at.x, -at.z)


## How many degrees it would have to turn to face `point`.
func _off_facing(point: Vector3) -> float:
	return absf(rad_to_deg(angle_difference(rotation.y, _yaw_to(point))))


## Turns towards `point` at no more than TURN_DEGREES a second.
func _turn_towards(point: Vector3, delta: float) -> void:
	rotation.y = wrapf(rotate_toward(rotation.y, _yaw_to(point), deg_to_rad(TURN_DEGREES) * delta), -PI, PI)


## One hop towards `point`, landing short of it rather than overshooting.
func _hop_towards(point: Vector3) -> void:
	_hop_in = CHASE_HOP_SECONDS * randf_range(0.7, 1.3)
	var at := Vector2(point.x - global_position.x, point.z - global_position.z)
	var airtime := 2.0 * HOP_UP / gravity
	var speed := minf(HOP_SPEED, maxf(at.length() - RADIUS - BITE_REACH * 0.5, 0.0) / airtime)
	if speed < 0.2:
		return
	var dir := at.normalized() * speed
	velocity = Vector3(dir.x, HOP_UP, dir.y)
	_play_hop.rpc()


# --- Network ----------------------------------------------------------------

@rpc("authority", "call_local", "unreliable")
func _play_hop() -> void:
	if randf() < HOP_SOUND_CHANCE:
		Sounds.play_on(self, "frog_hop", -4.0, PITCH)
	if randf() < CROAK_CHANCE:
		Sounds.play_on(self, "frog_croak", -6.0, PITCH)
	if _model == null:
		return
	var tween := create_tween()
	tween.tween_property(_model, "scale", Vector3(0.9, 1.25, 1.1) * MODEL_SCALE, 0.1)
	tween.tween_property(_model, "scale", Vector3.ONE * MODEL_SCALE, 0.3)


@rpc("authority", "call_local", "unreliable")
func _play_bite() -> void:
	Sounds.play_on(self, "frog_bite", -6.0, PITCH)
	if _model == null:
		return
	var tween := create_tween()
	tween.tween_property(_model, "position:z", -0.25, 0.06)
	tween.tween_property(_model, "position:z", 0.0, 0.2)


@rpc("authority", "call_local", "unreliable")
func _play_hurt() -> void:
	Sounds.play_on(self, "hit_flesh")
	Sounds.play_on(self, "frog_hurt", -4.0, PITCH)
	if _model != null:
		CharacterModel.flash_meshes(_model, Color(1.0, 0.9, 0.9))


## Floats `amount` up over the frog: negative for damage.
@rpc("authority", "call_local", "unreliable")
func _pop_number(amount) -> void:
	if amount is int:
		DamageNumbers.pop(self, amount, 1.1)


# --- The model --------------------------------------------------------------

func _build_model() -> void:
	_model = Node3D.new()
	_model.name = "Model"
	_model.scale = Vector3.ONE * MODEL_SCALE
	add_child(_model)
	var Paint := CharacterModel
	var skin := Paint.paint(Paint.WARTY, Color(0.4, 0.58, 0.22))
	var belly := Paint.paint(Paint.SKIN, Color(0.82, 0.8, 0.52))
	var gold := Paint.paint(Paint.METAL, Color(0.95, 0.7, 0.18))
	var dark := Paint.paint(Paint.SKIN, Color(0.1, 0.07, 0.06))
	var mouth := Paint.paint(Paint.SKIN, Color(0.55, 0.22, 0.2))
	# Faces -Z, like the players. A squat, chunky body with a huge head,
	# shrunk to MODEL_SCALE.
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

	_health_bar = HealthBar3D.new()
	_health_bar.name = "HealthBar"
	_health_bar.position.y = 0.85
	_health_bar.fraction = float(health) / MAX_HEALTH
	add_child(_health_bar)
	if health <= 0:
		_show_dead()


## Belly up.
func _show_dead() -> void:
	if _model != null:
		_model.rotation.z = PI
		_model.position.y = 1.1 * MODEL_SCALE


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

