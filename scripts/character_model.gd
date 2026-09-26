extends Node3D
## The animated model for one race, used by players in the world and by the
## preview in character select. Call setup() once, then set_motion() whenever
## the character moves; it picks and blends idle, walk, run and jump.
##
## Models are only loaded where something can see them. Dedicated and headless
## servers skip them, which also keeps servers working from a checkout that was
## never imported in the editor (there are no imported .glb files there).

const Races := preload("res://scripts/races.gd")

## Speeds (m/s) the walk and run animations were made for, so the feet don't
## slide at other speeds.
const WALK_ANIM_SPEED := 2.0
const RUN_ANIM_SPEED := 5.5
## Above this horizontal speed the character walks, and above RUN_FROM runs.
const MOVE_FROM := 0.3
const RUN_FROM := 3.2
const BLEND := 0.2

const LOOPING := ["Idle", "Walking_A", "Running_A", "Jump_Idle"]

var race := ""
var _animation: AnimationPlayer
var _current := ""


static func can_show_models() -> bool:
	return DisplayServer.get_name() != "headless" and not OS.has_feature("dedicated_server")


## Builds the model for race. Returns false (and adds nothing) if models can't
## be shown here or the model is missing.
func setup(p_race: String) -> bool:
	race = p_race if Races.is_valid(p_race) else Races.DEFAULT
	var info: Dictionary = Races.INFO[race]
	if not can_show_models() or not ResourceLoader.exists(info["model"]):
		return false
	var model: Node3D = load(info["model"]).instantiate()
	# The models face +Z; players face -Z.
	model.rotation.y = PI
	model.scale = info["scale"]
	add_child(model)

	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	for mesh: MeshInstance3D in skeleton.find_children("*", "MeshInstance3D", true, false):
		# Body parts are skinned to the skeleton directly; accessories hang off
		# bone attachments and are only kept if the race lists them.
		if mesh.get_parent() != skeleton:
			mesh.visible = mesh.name in info["parts"]
	if info.get("ears", false):
		_add_ears(skeleton)
	if info.has("beard"):
		_add_beard(skeleton, info["beard"])

	_animation = model.find_children("*", "AnimationPlayer", true, false)[0]
	for anim_name in LOOPING:
		_animation.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	_play("Idle", 1.0)
	return true


## horizontal_speed in m/s; airborne while jumping or falling.
func set_motion(horizontal_speed: float, airborne: bool) -> void:
	if _animation == null:
		return
	if airborne:
		_play("Jump_Idle", 1.0)
	elif horizontal_speed < MOVE_FROM:
		_play("Idle", 1.0)
	elif horizontal_speed < RUN_FROM:
		_play("Walking_A", clampf(horizontal_speed / WALK_ANIM_SPEED, 0.6, 1.6))
	else:
		_play("Running_A", clampf(horizontal_speed / RUN_ANIM_SPEED, 0.7, 1.5))


## Plays a one-off animation such as "Cheer", then goes back to looping.
func play_once(anim_name: String) -> void:
	if _animation and _animation.has_animation(anim_name):
		_current = anim_name
		_animation.play(anim_name, BLEND)
		await _animation.animation_finished
		if _current == anim_name:
			_current = ""
			_play("Idle", 1.0)


func _play(anim_name: String, speed: float) -> void:
	_animation.speed_scale = speed
	if _current == anim_name:
		return
	_current = anim_name
	_animation.play(anim_name, BLEND)


## Long, swept-back pointed ears on the sides of the head.
func _add_ears(skeleton: Skeleton3D) -> void:
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.96, 0.78, 0.66)
	skin.roughness = 0.8
	var head := _attach_to_bone(skeleton, "head")
	for side in [-1.0, 1.0]:
		var ear := MeshInstance3D.new()
		var mesh := PrismMesh.new()
		mesh.size = Vector3(0.22, 0.6, 0.07)
		mesh.material = skin
		ear.mesh = mesh
		ear.name = "EarLeft" if side > 0 else "EarRight"
		# Out of the side of the head, pointing up, out and back.
		ear.position = Vector3(0.58 * side, 0.52, -0.05)
		ear.rotation = Vector3(deg_to_rad(-35), 0.0, deg_to_rad(-55 * side))
		head.add_child(ear)


## A long braided beard growing down from the model's own short one.
func _add_beard(skeleton: Skeleton3D, color: Color) -> void:
	var hair := StandardMaterial3D.new()
	hair.albedo_color = color
	hair.roughness = 0.9
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.95, 0.72, 0.2)
	gold.metallic = 0.8
	gold.roughness = 0.35
	var beard := Node3D.new()
	beard.name = "Beard"
	beard.position = Vector3(0.0, 0.12, 0.4)
	_attach_to_bone(skeleton, "head").add_child(beard)
	# A wedge pointing down, then two braids with gold rings.
	var wedge := PrismMesh.new()
	wedge.size = Vector3(0.78, 0.6, 0.22)
	wedge.material = hair
	_add_piece(beard, wedge, Vector3(0.0, -0.22, 0.0), Vector3(0.0, 0.0, PI))
	for side in [-1.0, 1.0]:
		var braid := CylinderMesh.new()
		braid.top_radius = 0.07
		braid.bottom_radius = 0.05
		braid.height = 0.42
		braid.material = hair
		_add_piece(beard, braid, Vector3(0.2 * side, -0.4, -0.02), Vector3(0.0, 0.0, deg_to_rad(6 * side)))
		var ring := CylinderMesh.new()
		ring.top_radius = 0.085
		ring.bottom_radius = 0.085
		ring.height = 0.07
		ring.material = gold
		_add_piece(beard, ring, Vector3(0.215 * side, -0.52, -0.02), Vector3(0.0, 0.0, deg_to_rad(6 * side)))


func _add_piece(parent: Node3D, mesh: Mesh, position: Vector3, rotation: Vector3) -> void:
	var piece := MeshInstance3D.new()
	piece.mesh = mesh
	piece.position = position
	piece.rotation = rotation
	parent.add_child(piece)


func _attach_to_bone(skeleton: Skeleton3D, bone: String) -> BoneAttachment3D:
	var existing := skeleton.get_node_or_null("Attach_" + bone)
	if existing:
		return existing
	var attachment := BoneAttachment3D.new()
	attachment.name = "Attach_" + bone
	attachment.bone_name = bone
	skeleton.add_child(attachment)
	return attachment
