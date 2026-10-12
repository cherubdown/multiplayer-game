extends SubViewportContainer
## A small turntable in character select showing a race and sex's model
## idling. Hides itself where models can't be shown (headless runs).

const CharacterModel := preload("res://scripts/character_model.gd")

const TURN_SPEED := 0.4

var _viewport: SubViewport
var _camera: Camera3D
var _stand: Node3D
var _model: CharacterModel


func _ready() -> void:
	if not CharacterModel.can_show_models():
		visible = false
		set_process(false)
		return
	stretch = true
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	add_child(_viewport)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.75, 0.75, 0.8)
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_viewport.add_child(world_environment)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 35, 0)
	_viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 200, 0)
	rim.light_energy = 0.6
	rim.light_color = Color(0.7, 0.8, 1.0)
	_viewport.add_child(rim)

	_camera = Camera3D.new()
	_camera.fov = 35
	_viewport.add_child(_camera)
	_frame(1.8)

	_stand = Node3D.new()
	_stand.rotation.y = deg_to_rad(-20)
	_viewport.add_child(_stand)


## Shows race and sex, or nothing for race "".
func show_character(race: String, sex: String) -> void:
	if _stand == null or (_model != null and _model.race == race and _model.sex == sex):
		return
	if _model != null:
		_model.queue_free()
		_model = null
	if race == "":
		return
	_model = CharacterModel.new()
	_stand.add_child(_model)
	if _model.setup(race, sex):
		_frame(_model.height)
		# A little flourish so picking a race feels alive.
		_model.play_once("Cheer")
	else:
		_model.queue_free()
		_model = null


## Fits a character this tall in view. Everyone shorter than a human is shown
## at the same size, so dwarves still look short.
func _frame(model_height: float) -> void:
	var fit := maxf(model_height, 1.9) * 1.15
	var distance := fit * 0.5 / tan(deg_to_rad(_camera.fov * 0.5))
	var center := Vector3(0.0, fit * 0.45, 0.0)
	_camera.look_at_from_position(center + Vector3(0.0, fit * 0.12, distance), center)


func _process(delta: float) -> void:
	if _stand:
		_stand.rotation.y = wrapf(_stand.rotation.y + TURN_SPEED * delta, -PI, PI)
