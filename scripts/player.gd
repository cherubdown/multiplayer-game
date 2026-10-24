extends CharacterBody3D
## Server-authoritative third-person player.
##
## The server (peer 1) owns this body and runs its physics. The owning client
## only owns the PlayerInput child, whose state is replicated to the server.
## Position and rotation are replicated from the server to every peer by
## ServerSynchronizer, along with velocity and airborne so every peer can play
## the right animation on the character's model.
##
## Every character has health, 50 when full, which the server owns and
## replicates so everyone sees it (the local player in the corner of the
## screen, see scripts/hud.gd, and other players above their heads). Enemies
## take it away with take_damage(); it slowly comes back once nothing has hurt
## the character for a while. At 0 the character dies and the world brings
## them back at the spawn with full health (see scripts/test_world.gd). Health
## is saved with the character when they leave (see Session).
##
## Every peer sees how much each hurt or bit of healing was, as a number
## floating up over the character (see scripts/damage_numbers.gd): red for
## damage, green for healing, "Miss" when an enemy's attack misses.
##
## Some enemies poison (see poison()): a poisoned character loses a little
## health every POISON_TICK seconds until it wears off, which everyone sees
## through `poisoned`. Dying or coming back cures it.
##
## Every character also has stamina, which the server owns the same way and
## replicates for the local player's bar under their health. Sprinting (held
## Shift) burns it while moving, and every swing of a weapon costs a chunk of
## it (see spend_stamina()). It comes back quickly a moment after it was last
## used. With none left the character can't sprint or attack, and once it runs
## dry sprinting stays off until it has come back a little.

# Preloaded rather than a class_name so it resolves on a fresh checkout that
# hasn't been imported in the editor (no global class cache yet).
const PlayerInput := preload("res://scripts/player_input.gd")
const CharacterModel := preload("res://scripts/character_model.gd")
const Races := preload("res://scripts/races.gd")
const HealthBar3D := preload("res://scripts/health_bar_3d.gd")
const DamageNumbers := preload("res://scripts/damage_numbers.gd")

const SPEED := 5.0
const WALK_SPEED := 2.0
const SPRINT_SPEED := 8.0
const JUMP_VELOCITY := 4.5
const TURN_SPEED := 10.0
## Health when full, and that a new character starts with.
const MAX_HEALTH := 50
## Seconds without being hurt before health starts coming back, then seconds
## per point of health it gets back.
const REGEN_DELAY := 10.0
const REGEN_SECONDS := 2.0
## Seconds between the health a poison takes.
const POISON_TICK := 1.0
## Stamina when full. Sprinting burns SPRINT_STAMINA a second (5 seconds from
## full), and a weapon swing costs ATTACK_STAMINA. It comes back at
## STAMINA_REGEN a second (about 3 seconds from empty), starting
## STAMINA_REGEN_DELAY seconds after it was last used. After running dry,
## sprinting waits until it's back to SPRINT_RECOVER.
const MAX_STAMINA := 100.0
const SPRINT_STAMINA := 20.0
const ATTACK_STAMINA := 15.0
const STAMINA_REGEN := 35.0
const STAMINA_REGEN_DELAY := 0.8
const SPRINT_RECOVER := 25.0

## Every peer: health went from `old` to `new` (see `health`).
signal health_changed(new: int, old: int)
## Server side: health reached 0. `by` names what did it.
signal killed(by: String)
## Every peer: the character died, to `by` (see killed).
signal died(by: String)

@onready var input: PlayerInput = $PlayerInput
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var camera_pivot: Node3D = $CameraPivot
@onready var model: CharacterModel = $Model

## Set by the server before spawning; replicated once at spawn time.
@export var character_name := ""
@export var race := Races.DEFAULT
@export var sex := Races.DEFAULT_SEX
## Set by the server every physics step, for animations.
@export var airborne := false
## The tool in the character's right hand, "" for none. Set by the server
## (see Session.hold()) and replicated so everyone sees it.
@export var held_item := "":
	set(value):
		held_item = value
		if is_node_ready():
			model.set_held(value)

## Set by the server and replicated whenever it changes.
@export var health := MAX_HEALTH:
	set(value):
		var old := health
		health = clampi(value, 0, MAX_HEALTH)
		if _health_bar != null:
			_health_bar.fraction = float(health) / MAX_HEALTH
		if health != old:
			health_changed.emit(health, old)

## Whether the character is poisoned. Set by the server (see poison()) and
## replicated whenever it changes.
@export var poisoned := false

## Set by the server and replicated whenever it changes.
@export var stamina := MAX_STAMINA:
	set(value):
		stamina = clampf(value, 0.0, MAX_STAMINA)

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
## Above other players' heads, under their name.
var _health_bar: HealthBar3D
## Server side: seconds since the character was last hurt, and towards the
## next point of health back.
var _since_hurt := 0.0
var _regen := 0.0
## Server side: seconds since stamina was last used, and whether it ran dry
## and sprinting is waiting for it to come back.
var _since_tired := STAMINA_REGEN_DELAY
var _winded := false
## Server side: the poison: seconds left, seconds to its next tick, health
## each tick takes, and what to name for a death by it.
var _poison_left := 0.0
var _poison_tick := 0.0
var _poison_damage := 0
var _poison_by := ""


func _enter_tree() -> void:
	# The spawner names each player after its peer id, so every peer can
	# derive who owns the input without an extra RPC.
	$PlayerInput.set_multiplayer_authority(str(name).to_int())


func _ready() -> void:
	var is_local := $PlayerInput.is_multiplayer_authority()
	camera.current = is_local
	$Nameplate.text = character_name
	$Nameplate.visible = not is_local
	if is_local:
		# Looked up rather than named, so tests can load this without autoloads.
		get_node("/root/Session").leaving_world.connect(_on_leaving_world)
		# Start looking the way the character faces (where they faced when
		# they last left), not always north.
		input.yaw = rotation.y
	if model.setup(race, sex):
		$Body.visible = false
		$Nameplate.position.y = model.height + 0.3
		model.set_held(held_item)
		if not is_local:
			_health_bar = HealthBar3D.new()
			_health_bar.name = "HealthBar"
			_health_bar.position.y = $Nameplate.position.y - 0.2
			_health_bar.fraction = float(health) / MAX_HEALTH
			add_child(_health_bar)
	elif is_local:
		# Without a model (e.g. a headless peer), the local player's capsule
		# gets a different color so you can tell yourself apart.
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.6, 1.0)
		$Body.material_override = mat


## Server side: turns the character to face `yaw` and plays a swing of the
## held tool on every peer.
func swing(yaw: float) -> void:
	rotation.y = yaw
	_play_swing.rpc()


@rpc("authority", "call_local", "unreliable")
func _play_swing() -> void:
	model.play_once("Swing")


## Server side: takes `amount` health away. `by` names what did it, for the
## death notice. At 0 the character dies (see killed). Returns whether it
## counted (not after the character has already died).
func take_damage(amount: int, by: String) -> bool:
	if health <= 0 or amount <= 0:
		return false
	health -= amount
	_since_hurt = 0.0
	_regen = 0.0
	_play_hurt.rpc()
	_pop_number.rpc(-amount)
	if health <= 0:
		_cure()
		print("%s was killed by %s" % [character_name, by])
		_announce_death.rpc(by)
		killed.emit(by)
	return true


## Server side: back to full health, after dying.
func restore_health() -> void:
	health = MAX_HEALTH
	_since_hurt = 0.0
	_regen = 0.0
	stamina = MAX_STAMINA
	_winded = false
	_cure()


## Server side: poisons the character for `seconds`, taking `damage` health
## every POISON_TICK seconds. `by` names it, should it kill them. Poisoned
## again before it wears off, it lasts `seconds` from then, not longer.
## Returns whether it took (not after the character has died).
func poison(seconds: float, damage: int, by: String) -> bool:
	if health <= 0 or seconds <= 0.0 or damage <= 0:
		return false
	if not poisoned:
		_poison_tick = POISON_TICK
	_poison_left = maxf(_poison_left, seconds)
	_poison_damage = damage
	_poison_by = by
	poisoned = true
	return true


func _cure() -> void:
	_poison_left = 0.0
	poisoned = false


## Server side: uses `amount` stamina for an action, such as an attack.
## Returns false, using none, if there isn't that much left.
func spend_stamina(amount: float) -> bool:
	if stamina < amount:
		return false
	stamina -= amount
	_since_tired = 0.0
	if stamina <= 0.0:
		_winded = true
	return true


## Whether the character is sprinting right now: Shift held while moving at a
## run, with stamina to spare. Server side, where the input is replicated to.
func is_sprinting() -> bool:
	return input.sprinting and not input.walking and not _winded and stamina > 0.0 \
		and input.direction.length_squared() > 0.0


## Server side: an enemy's attack on the character missed.
func show_miss() -> void:
	_pop_miss.rpc()


@rpc("authority", "call_local", "unreliable")
func _play_hurt() -> void:
	model.flash(Color(1.0, 0.2, 0.15))


## Floats `amount` up over the character: negative for damage, positive for
## healing.
@rpc("authority", "call_local", "unreliable")
func _pop_number(amount) -> void:
	if amount is int:
		DamageNumbers.pop(self, amount, model.height + 0.45)


@rpc("authority", "call_local", "unreliable")
func _pop_miss() -> void:
	DamageNumbers.miss(self, model.height + 0.45)


@rpc("authority", "call_local", "reliable")
func _announce_death(by: String) -> void:
	died.emit(by)


func _on_leaving_world() -> void:
	$PlayerInput/InputSynchronizer.public_visibility = false


func _process(_delta: float) -> void:
	# The camera follows the local input's look direction, independent of
	# which way the body is facing.
	camera_pivot.global_rotation = Vector3(input.pitch, input.yaw, 0.0)
	model.set_motion(Vector2(velocity.x, velocity.z).length(), airborne)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	if poisoned:
		_poison_left -= delta
		_poison_tick -= delta
		if _poison_tick <= 0.0:
			_poison_tick += POISON_TICK
			take_damage(_poison_damage, _poison_by)
		if _poison_left <= 0.0:
			_cure()

	_since_hurt += delta
	if health < MAX_HEALTH and health > 0 and _since_hurt >= REGEN_DELAY:
		_regen += delta
		if _regen >= REGEN_SECONDS:
			_regen -= REGEN_SECONDS
			health += 1
			_pop_number.rpc(1)

	var sprinting := is_sprinting()
	if sprinting:
		stamina -= SPRINT_STAMINA * delta
		_since_tired = 0.0
		if stamina <= 0.0:
			_winded = true
	else:
		_since_tired += delta
		if _since_tired >= STAMINA_REGEN_DELAY and stamina < MAX_STAMINA:
			stamina += STAMINA_REGEN * delta
	if _winded and stamina >= SPRINT_RECOVER:
		_winded = false

	if not is_on_floor():
		velocity.y -= gravity * delta

	if input.jumping and is_on_floor():
		velocity.y = JUMP_VELOCITY
	input.jumping = false

	var dir := Vector3(input.direction.x, 0.0, input.direction.y).rotated(Vector3.UP, input.yaw)
	if dir.length_squared() > 0.0:
		dir = dir.normalized() * minf(input.direction.length(), 1.0)
		var speed := WALK_SPEED if input.walking else SPRINT_SPEED if sprinting else SPEED
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		var target_yaw := atan2(-dir.x, -dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, TURN_SPEED * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, SPEED)
		velocity.z = move_toward(velocity.z, 0.0, SPEED)

	move_and_slide()
	airborne = not is_on_floor()
