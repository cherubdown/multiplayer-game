extends Node
## Collects input on the owning client and replicates it to the server via
## InputSynchronizer. Only the owning peer has authority over this node.

const MOUSE_SENSITIVITY := 0.003

## Movement input, x = right, y = back (matches Input.get_vector).
@export var direction := Vector2.ZERO
## Camera yaw, replicated so the server can move the body camera-relative.
@export var yaw := 0.0
## Camera pitch, local only.
var pitch := -0.3

## Set on the server by the jump RPC, consumed by the player's physics step.
var jumping := false


func _ready() -> void:
	var is_local := is_multiplayer_authority()
	set_process(is_local)
	set_process_unhandled_input(is_local)


func _process(_delta: float) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		direction = Vector2.ZERO
		return
	direction = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if Input.is_action_just_pressed("jump"):
		jump.rpc_id(1)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw = wrapf(yaw - event.relative.x * MOUSE_SENSITIVITY, -PI, PI)
		pitch = clampf(pitch - event.relative.y * MOUSE_SENSITIVITY, -1.2, 0.5)


@rpc("authority", "call_local", "reliable")
func jump() -> void:
	if multiplayer.is_server():
		jumping = true
