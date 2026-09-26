extends CharacterBody3D
## Server-authoritative third-person player.
##
## The server (peer 1) owns this body and runs its physics. The owning client
## only owns the PlayerInput child, whose state is replicated to the server.
## Position and rotation are replicated from the server to every peer by
## ServerSynchronizer.

const SPEED := 5.0
const JUMP_VELOCITY := 4.5
const TURN_SPEED := 10.0

@onready var input: PlayerInput = $PlayerInput
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var camera_pivot: Node3D = $CameraPivot

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _enter_tree() -> void:
	# The spawner names each player after its peer id, so every peer can
	# derive who owns the input without an extra RPC.
	$PlayerInput.set_multiplayer_authority(str(name).to_int())


func _ready() -> void:
	var is_local := $PlayerInput.is_multiplayer_authority()
	camera.current = is_local
	# Local player gets a different color so you can tell yourself apart.
	if is_local:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.6, 1.0)
		$Body.material_override = mat


func _process(_delta: float) -> void:
	# The camera follows the local input's look direction, independent of
	# which way the body is facing.
	camera_pivot.global_rotation = Vector3(input.pitch, input.yaw, 0.0)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	if input.jumping and is_on_floor():
		velocity.y = JUMP_VELOCITY
	input.jumping = false

	var dir := Vector3(input.direction.x, 0.0, input.direction.y).rotated(Vector3.UP, input.yaw)
	if dir.length_squared() > 0.0:
		dir = dir.normalized() * minf(input.direction.length(), 1.0)
		velocity.x = dir.x * SPEED
		velocity.z = dir.z * SPEED
		var target_yaw := atan2(-dir.x, -dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, TURN_SPEED * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, SPEED)
		velocity.z = move_toward(velocity.z, 0.0, SPEED)

	move_and_slide()
