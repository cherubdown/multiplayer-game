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

# Preloaded rather than a class_name so it resolves on a fresh checkout that
# hasn't been imported in the editor (no global class cache yet).
const PlayerInput := preload("res://scripts/player_input.gd")
const CharacterModel := preload("res://scripts/character_model.gd")
const Races := preload("res://scripts/races.gd")
const HealthBar3D := preload("res://scripts/health_bar_3d.gd")

const SPEED := 5.0
const WALK_SPEED := 2.0
const JUMP_VELOCITY := 4.5
const TURN_SPEED := 10.0
## Health when full, and that a new character starts with.
const MAX_HEALTH := 50
## Seconds without being hurt before health starts coming back, then seconds
## per point of health it gets back.
const REGEN_DELAY := 10.0
const REGEN_SECONDS := 2.0

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

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
## Above other players' heads, under their name.
var _health_bar: HealthBar3D
## Server side: seconds since the character was last hurt, and towards the
## next point of health back.
var _since_hurt := 0.0
var _regen := 0.0


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
	if health <= 0:
		print("%s was killed by %s" % [character_name, by])
		_announce_death.rpc(by)
		killed.emit(by)
	return true


## Server side: back to full health, after dying.
func restore_health() -> void:
	health = MAX_HEALTH
	_since_hurt = 0.0
	_regen = 0.0


@rpc("authority", "call_local", "unreliable")
func _play_hurt() -> void:
	model.flash(Color(1.0, 0.2, 0.15))


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

	_since_hurt += delta
	if health < MAX_HEALTH and health > 0 and _since_hurt >= REGEN_DELAY:
		_regen += delta
		if _regen >= REGEN_SECONDS:
			_regen -= REGEN_SECONDS
			health += 1

	if not is_on_floor():
		velocity.y -= gravity * delta

	if input.jumping and is_on_floor():
		velocity.y = JUMP_VELOCITY
	input.jumping = false

	var dir := Vector3(input.direction.x, 0.0, input.direction.y).rotated(Vector3.UP, input.yaw)
	if dir.length_squared() > 0.0:
		dir = dir.normalized() * minf(input.direction.length(), 1.0)
		var speed := WALK_SPEED if input.walking else SPEED
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		var target_yaw := atan2(-dir.x, -dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, TURN_SPEED * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, SPEED)
		velocity.z = move_toward(velocity.z, 0.0, SPEED)

	move_and_slide()
	airborne = not is_on_floor()
