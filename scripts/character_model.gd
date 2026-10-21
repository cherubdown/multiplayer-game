extends Node3D
## The animated model for one race and sex, used by players in the world and
## by the preview in character select. Call setup() once, then set_motion()
## whenever the character moves; it picks and blends idle, walk, run and jump.
##
## The model is built in code from the race's body measurements (see
## scripts/races.gd): a jointed body of lofted meshes for the torso, head and
## limbs, a face, hair, and the t-shirt and trousers every character starts
## in. The animations are keyframed on those joints here too.
##
## Models are only built where something can see them. Dedicated and headless
## servers skip them.

const Races := preload("res://scripts/races.gd")
const Items := preload("res://scripts/items.gd")

## Speeds (m/s) the walk and run animations were made for, for legs as long as
## REFERENCE_LEG. Shorter legs play them faster so the feet don't slide.
const WALK_ANIM_SPEED := 2.0
const RUN_ANIM_SPEED := 5.5
const REFERENCE_LEG := 0.88
## Above this horizontal speed the character walks, and above RUN_FROM runs.
const MOVE_FROM := 0.3
const RUN_FROM := 3.2
const BLEND := 0.2

## The head is about this many times its half-width tall.
const HEAD_HEIGHT := 2.2
const SEGMENTS := 16

const SHIRT_COLOR := Color(0.86, 0.82, 0.71)
const PANTS_COLOR := Color(0.36, 0.27, 0.19)
const EYE_COLOR := Color(0.09, 0.07, 0.06)
const MOUTH_COLOR := Color(0.47, 0.22, 0.2)
const TUSK_COLOR := Color(0.94, 0.9, 0.78)
const GOLD_COLOR := Color(0.95, 0.72, 0.2)

## Every joint the animations move. The character faces -Z and its right
## hand side is +X.
const JOINTS: Array[String] = [
	"Hips", "Spine", "Neck", "Head",
	"ArmUpper_L", "ArmLower_L", "Hand_L", "ArmUpper_R", "ArmLower_R", "Hand_R",
	"Leg_L", "Shin_L", "Foot_L", "Leg_R", "Shin_R", "Foot_R",
]

static var _materials := {}

var race := ""
var sex := ""
## From the soles of the feet to the top of the head, in meters.
var height := 0.0

var _body: Dictionary
var _joints := {}   # joint name -> Node3D
var _paths := {}    # joint name -> path from this node
var _rest := {}     # joint name -> rest rotation (radians)
var _stride := 1.0
var _animation: AnimationPlayer
var _current := ""
var _held: MeshInstance3D
## The one-off animation playing (see play_once()), which set_motion() leaves
## alone until it ends.
var _one_shot := ""


static func can_show_models() -> bool:
	return DisplayServer.get_name() != "headless" and not OS.has_feature("dedicated_server")


## Builds the model for race and sex. Returns false (and adds nothing) if
## models can't be shown here; height is set either way.
func setup(p_race: String, p_sex: String = Races.DEFAULT_SEX) -> bool:
	race = p_race if Races.is_valid(p_race) else Races.DEFAULT
	sex = p_sex if Races.is_valid_sex(p_sex) else Races.DEFAULT_SEX
	_body = Races.body(race, sex)
	height = _body["leg"] + _body["torso"] * 0.97 + _body["neck"] + _body["head"] * HEAD_HEIGHT
	_stride = _body["leg"] / REFERENCE_LEG
	if not can_show_models():
		return false
	_build_body()
	_build_animations()
	_play("Idle", 1.0)
	return true


## horizontal_speed in m/s; airborne while jumping or falling.
func set_motion(horizontal_speed: float, airborne: bool) -> void:
	if _animation == null or _one_shot != "":
		return
	if airborne:
		_play("Jump_Idle", 1.0)
	elif horizontal_speed < MOVE_FROM:
		_play("Idle", 1.0)
	elif horizontal_speed < RUN_FROM:
		_play("Walking_A", clampf(horizontal_speed / (WALK_ANIM_SPEED * _stride), 0.6, 2.4))
	else:
		_play("Running_A", clampf(horizontal_speed / (RUN_ANIM_SPEED * _stride), 0.7, 2.2))


## Puts a tool (an item id from scripts/items.gd) in the right hand, or
## empties it with "".
func set_held(item: String) -> void:
	if _held != null:
		_held.queue_free()
		_held = null
	if item == "" or not _joints.has("Hand_R"):
		return
	_held = MeshInstance3D.new()
	_held.name = "Held"
	_held.mesh = Items.tool_mesh(item)
	# Gripped in the fist, pointing forward when the arm hangs down.
	_held.position = Vector3(0.0, -_body["arm_r"] * 0.95, 0.0)
	_held.rotation = Vector3(deg_to_rad(-90.0), 0.0, 0.0)
	_held.scale = Vector3.ONE * clampf(_stride, 0.8, 1.5)
	_joints["Hand_R"].add_child(_held)


## Plays a one-off animation such as "Cheer", then goes back to looping.
func play_once(anim_name: String) -> void:
	if _animation and _animation.has_animation(anim_name):
		_current = anim_name
		_one_shot = anim_name
		_animation.speed_scale = 1.0
		# Starting over from the top lets a swing follow a swing.
		_animation.stop()
		_animation.play(anim_name, BLEND * 0.5)
		await _animation.animation_finished
		if _current == anim_name:
			_current = ""
			_one_shot = ""
			_play("Idle", 1.0)


## Tints the whole model `color` for a moment, as when it's hurt.
func flash(color: Color) -> void:
	flash_meshes(self, color)


## Tints every mesh under `root` `color` for a moment. Materials are shared
## between models, so this lays a see-through overlay on top instead of
## changing them.
static func flash_meshes(root: Node, color: Color, seconds := 0.18) -> void:
	if not root.is_inside_tree():
		return
	var overlay := StandardMaterial3D.new()
	overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	overlay.albedo_color = Color(color, 0.55)
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	for mesh: MeshInstance3D in meshes:
		mesh.material_overlay = overlay
	await root.get_tree().create_timer(seconds).timeout
	for mesh in meshes:
		if is_instance_valid(mesh) and mesh.material_overlay == overlay:
			mesh.material_overlay = null


func _play(anim_name: String, speed: float) -> void:
	_animation.speed_scale = speed
	if _current == anim_name:
		return
	_current = anim_name
	_animation.play(anim_name, BLEND)


# --- The body ---------------------------------------------------------------

func _build_body() -> void:
	var b := _body
	var info: Dictionary = Races.INFO[race]
	var skin := _material(info["skin"])
	var shirt := _material(SHIRT_COLOR)
	var pants := _material(PANTS_COLOR)
	var torso: float = b["torso"]
	var chest: Vector2 = b["chest"]
	var waist: Vector2 = b["waist"]
	var pelvis: Vector2 = b["pelvis"]
	var belly: float = b["belly"]
	var bust: float = b["bust"]
	var leg_r: float = b["leg_r"]
	var arm_r: float = b["arm_r"]

	# Trousers from the crotch up to just under the shirt's hem.
	var hips := _joint("Hips", null, Vector3(0.0, b["leg"], 0.0))
	var top := pelvis.lerp(waist, 0.6)
	_add(hips, _loft([
		[-leg_r * 1.1, pelvis.x * 0.78, pelvis.y * 0.75, pelvis.y * 0.8],
		[-leg_r * 0.45, pelvis.x * 0.97, pelvis.y * 0.95, pelvis.y],
		[0.0, pelvis.x, pelvis.y + belly * 0.2, pelvis.y * 1.04],
		[torso * 0.24, top.x, top.y + belly * 0.4, top.y],
	]), pants)

	# The rest of the torso bends at the waist, inside the shirt.
	var spine_y := torso * 0.2
	var spine := _joint("Spine", "Hips", Vector3(0.0, spine_y, 0.0))
	var hem := pelvis.lerp(waist, 0.45) * 1.07
	var mid := waist.lerp(chest, 0.6)
	var shoulder_x: float = b["shoulders"] + arm_r * 0.45
	_add(spine, _loft([
		[torso * 0.13 - spine_y, hem.x, hem.y + belly * 0.45, hem.y],
		[torso * 0.36 - spine_y, waist.x, waist.y + belly, waist.y],
		[torso * 0.55 - spine_y, mid.x, mid.y + belly * 0.6 + bust * 0.3, mid.y],
		[torso * 0.72 - spine_y, chest.x, chest.y + bust, chest.y],
		[torso * 0.86 - spine_y, chest.x, chest.y * 0.95 + bust * 0.35, chest.y * 0.95],
		[torso * 0.95 - spine_y, shoulder_x, chest.y * 0.72, chest.y * 0.75],
		[torso * 1.02 - spine_y, maxf(b["neck_r"] * 1.6, shoulder_x * 0.5), b["neck_r"] * 1.4, b["neck_r"] * 1.5],
	]), shirt)

	var neck := _joint("Neck", "Spine", Vector3(0.0, torso * 0.97 - spine_y, 0.0))
	var neck_r: float = b["neck_r"]
	_add(neck, _loft([[-b["neck"] * 0.6, neck_r, neck_r, neck_r], [b["neck"] + b["head"] * 0.5, neck_r * 0.92, neck_r * 0.92, neck_r * 0.92]]), skin)
	var head := _joint("Head", "Neck", Vector3(0.0, b["neck"], 0.0))
	_build_head(head, skin, _material(info["hair_color"]))

	for side in ["L", "R"]:
		var s := -1.0 if side == "L" else 1.0
		_build_arm(side, s, spine, Vector3(b["shoulders"] * s, torso * 0.9 - spine_y, 0.0), skin, shirt)
		_build_leg(side, s, skin, pants)


func _build_arm(side: String, s: float, spine: Node3D, at: Vector3, skin: Material, shirt: Material) -> void:
	var b := _body
	var arm: float = b["arm"]
	var forearm := arm * 0.9
	var r: float = b["arm_r"]
	# Hang the arms out just far enough to clear the hips.
	var clearance: float = b["pelvis"].x + r * 1.3 - b["shoulders"]
	var out := maxf(atan2(clearance, arm + forearm), deg_to_rad(3.0))
	var upper := _joint("ArmUpper_" + side, "Spine", at, Vector3(0.0, 0.0, out * s))
	_add(upper, _ellipsoid(Vector3.ONE * r * 1.25), shirt)
	_add(upper, _loft([[0.0, r * 1.2, r * 1.2, r * 1.2], [-arm * 0.42, r * 1.16, r * 1.16, r * 1.16]]), shirt)
	_add(upper, _loft([[0.0, r, r, r], [-arm, r * 0.82, r * 0.82, r * 0.82]]), skin)

	var lower := _joint("ArmLower_" + side, "ArmUpper_" + side, Vector3(0.0, -arm, 0.0), Vector3(deg_to_rad(8.0), 0.0, 0.0))
	_add(lower, _ellipsoid(Vector3.ONE * r * 0.84), skin)
	_add(lower, _loft([[0.0, r * 0.82, r * 0.82, r * 0.82], [-forearm, r * 0.6, r * 0.6, r * 0.6]]), skin)

	var hand := _joint("Hand_" + side, "ArmLower_" + side, Vector3(0.0, -forearm, 0.0))
	_add(hand, _ellipsoid(Vector3(r * 0.48, r * 1.15, r * 0.85)), skin, Vector3(0.0, -r * 0.95, 0.0))
	_add(hand, _ellipsoid(Vector3(r * 0.28, r * 0.5, r * 0.28)), skin, Vector3(-s * r * 0.15, -r * 0.55, -r * 0.7), Vector3(deg_to_rad(-30.0), 0.0, 0.0))


func _build_leg(side: String, s: float, skin: Material, pants: Material) -> void:
	var b := _body
	var r: float = b["leg_r"]
	var ankle := maxf(b["leg"] * 0.06, r * 0.6)
	var thigh: float = (b["leg"] - ankle) * 0.5
	var shin := thigh

	var upper := _joint("Leg_" + side, "Hips", Vector3(b["hips"] * s, 0.0, 0.0))
	_add(upper, _loft([[r * 0.6, r * 0.95, r * 0.95, r * 0.95], [-thigh, r * 0.72, r * 0.72, r * 0.72]]), pants)

	var lower := _joint("Shin_" + side, "Leg_" + side, Vector3(0.0, -thigh, 0.0))
	_add(lower, _ellipsoid(Vector3.ONE * r * 0.74), pants)
	_add(lower, _loft([
		[0.0, r * 0.72, r * 0.72, r * 0.72],
		[-shin * 0.86, r * 0.62, r * 0.62, r * 0.62],
		[-shin * 0.93, r * 0.68, r * 0.68, r * 0.68],
	], true, false), pants)
	_add(lower, _loft([[-shin * 0.8, r * 0.42, r * 0.42, r * 0.42], [-shin - ankle * 0.3, r * 0.4, r * 0.4, r * 0.4]]), skin)

	# Bare feet.
	var foot := _joint("Foot_" + side, "Shin_" + side, Vector3(0.0, -shin, 0.0))
	_add(foot, _ellipsoid(Vector3(r * 0.52, ankle * 0.55, r * 1.25)), skin, Vector3(0.0, -ankle * 0.48, -r * 0.55))


func _build_head(head: Node3D, skin: Material, hair: Material) -> void:
	var r: float = _body["head"]
	var j: float = _body["jaw"]
	var info: Dictionary = Races.INFO[race]
	var rings := []
	for ring in [
		[-0.1, 0.45 * j, 0.5, 0.45], [0.2, 0.75 * j, 0.82, 0.78], [0.55, 0.92 * lerpf(1.0, j, 0.5), 0.95, 0.95],
		[0.95, 1.0, 0.98, 1.0], [1.35, 0.98, 0.95, 1.0], [1.7, 0.85, 0.8, 0.86], [2.0, 0.55, 0.5, 0.56],
		[2.18, 0.15, 0.14, 0.15],
	]:
		rings.append(ring.map(func(v: float) -> float: return v * r))
	_add(head, _loft(rings), skin)

	var ogre: bool = info.get("tusks", false)
	var dark := _material(EYE_COLOR)
	# Eyes, brows, nose and mouth on the front (-Z).
	for s in [-1.0, 1.0]:
		var eye := 0.09 if ogre else 0.11
		_add(head, _ellipsoid(Vector3(eye, eye * 1.25, eye * 0.6) * r), dark, Vector3(0.36 * s, 1.05, -0.9) * r)
		if not ogre:
			_add(head, _box(Vector3(0.34, 0.07, 0.08) * r), hair, Vector3(0.36 * s, 1.32, -0.9) * r, Vector3(0.0, 0.0, deg_to_rad(-8.0 * s)))
	if ogre:
		# A heavy brow ridge, a flat broad nose and tusks.
		_add(head, _ellipsoid(Vector3(0.85, 0.16, 0.2) * r), skin, Vector3(0.0, 1.3, -0.84) * r)
		_add(head, _ellipsoid(Vector3(0.24, 0.17, 0.2) * r), skin, Vector3(0.0, 0.8, -0.98) * r)
		var tusk := _material(TUSK_COLOR)
		for s in [-1.0, 1.0]:
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 0.07 * r
			cone.height = 0.36 * r
			cone.radial_segments = 8
			_add(head, cone, tusk, Vector3(0.34 * j * s, 0.62, -0.86) * r, Vector3(deg_to_rad(-12.0), 0.0, deg_to_rad(-12.0 * s)))
	else:
		_add(head, _ellipsoid(Vector3(0.11, 0.14, 0.14) * r), skin, Vector3(0.0, 0.8, -0.97) * r)
	_add(head, _box(Vector3(0.32 * j, 0.045, 0.05) * r), _material(MOUTH_COLOR), Vector3(0.0, 0.47, -0.86) * r)

	# Ears.
	for s in [-1.0, 1.0]:
		if info.get("ears", false):
			# Long, swept-back points.
			var point := PrismMesh.new()
			point.size = Vector3(0.36, 1.05, 0.1) * r
			_add(head, point, skin, Vector3(1.05 * s, 1.25, 0.12) * r, Vector3(deg_to_rad(-28.0), 0.0, deg_to_rad(-52.0 * s)))
		else:
			var ear := 0.3 if ogre else 0.24
			_add(head, _ellipsoid(Vector3(0.5, 1.0, 0.75) * ear * r), skin, Vector3(1.04 * s, 0.92, 0.0) * r)

	_build_hair(head, r, hair)
	if _body.get("beard", false):
		_build_beard(head, r, hair)


func _build_hair(head: Node3D, r: float, hair: Material) -> void:
	var style: String = _body["hair"]
	if style == "topknot":
		# Bald but for a knot on the crown.
		_add(head, _ellipsoid(Vector3(0.26, 0.3, 0.26) * r), hair, Vector3(0.0, 2.25, 0.25) * r)
		_add(head, _ellipsoid(Vector3(0.3, 0.08, 0.3) * r), _material(PANTS_COLOR), Vector3(0.0, 2.08, 0.22) * r)
		return
	# A cap over the crown, tipped back so the hairline clears the brows, and
	# the back of the head down to the nape.
	var cap := SphereMesh.new()
	cap.radius = 1.07 * r
	cap.height = 1.07 * r
	cap.is_hemisphere = true
	_add(head, cap, hair, Vector3(0.0, 1.15, 0.05) * r, Vector3(deg_to_rad(22.0), 0.0, 0.0))
	_add(head, _ellipsoid(Vector3(0.93, 0.95, 0.9) * r), hair, Vector3(0.0, 1.05, 0.22) * r)
	match style:
		"long":
			_add(head, _ellipsoid(Vector3(0.88, 1.25, 0.34) * r), hair, Vector3(0.0, 0.35, 0.72) * r, Vector3(deg_to_rad(8.0), 0.0, 0.0))
			for s in [-1.0, 1.0]:
				_add(head, _ellipsoid(Vector3(0.2, 0.75, 0.38) * r), hair, Vector3(0.86 * s, 0.6, 0.15) * r, Vector3(0.0, 0.0, deg_to_rad(4.0 * s)))
		"ponytail":
			_add(head, _ellipsoid(Vector3(0.16, 0.12, 0.16) * r), _material(PANTS_COLOR), Vector3(0.0, 1.15, 1.08) * r)
			_add(head, _ellipsoid(Vector3(0.22, 0.75, 0.2) * r), hair, Vector3(0.0, 0.45, 1.15) * r, Vector3(deg_to_rad(14.0), 0.0, 0.0))
		"bun":
			_add(head, _ellipsoid(Vector3(0.45, 0.42, 0.42) * r), hair, Vector3(0.0, 1.75, 0.85) * r)
		"braids":
			var gold := _material(GOLD_COLOR)
			for s in [-1.0, 1.0]:
				_add(head, _loft([[0.0, 0.16 * r, 0.16 * r, 0.16 * r], [-1.5 * r, 0.11 * r, 0.11 * r, 0.11 * r]]), hair, Vector3(0.82 * s, 0.85, -0.05) * r, Vector3(deg_to_rad(12.0), 0.0, deg_to_rad(6.0 * s)))
				_add(head, _ellipsoid(Vector3(0.15, 0.06, 0.15) * r), gold, Vector3(0.95 * s, -0.45, -0.32) * r)


## A broad beard hiding the mouth, a moustache, and a forked, braided end with
## gold rings.
func _build_beard(head: Node3D, r: float, hair: Material) -> void:
	_add(head, _ellipsoid(Vector3(0.82, 0.6, 0.5) * r), hair, Vector3(0.0, 0.32, -0.55) * r)
	var wedge := PrismMesh.new()
	wedge.size = Vector3(1.3, 1.2, 0.45) * r
	_add(head, wedge, hair, Vector3(0.0, -0.35, -0.72) * r, Vector3(deg_to_rad(-10.0), 0.0, PI))
	for s in [-1.0, 1.0]:
		_add(head, _ellipsoid(Vector3(0.32, 0.1, 0.13) * r), hair, Vector3(0.22 * s, 0.6, -0.93) * r, Vector3(0.0, 0.0, deg_to_rad(-15.0 * s)))
		_add(head, _loft([[0.0, 0.11 * r, 0.11 * r, 0.11 * r], [-0.55 * r, 0.08 * r, 0.08 * r, 0.08 * r]]), hair, Vector3(0.2 * s, -0.75, -0.8) * r, Vector3(deg_to_rad(-12.0), 0.0, deg_to_rad(6.0 * s)))
		_add(head, _ellipsoid(Vector3(0.13, 0.06, 0.13) * r), _material(GOLD_COLOR), Vector3(0.23 * s, -1.05, -0.86) * r)


# --- Animations -------------------------------------------------------------

## Poses are rotations away from the rest pose, in degrees, by joint name;
## "lift" raises the hips by that fraction of the character's height.
func _build_animations() -> void:
	var library := AnimationLibrary.new()

	var idle_a := { "ArmLower_L": Vector3(4, 0, 0), "ArmLower_R": Vector3(4, 0, 0) }
	var idle_b := {
		"Spine": Vector3(1.5, 0, 0), "Head": Vector3(2, 5, 0), "lift": -0.002,
		"ArmUpper_L": Vector3(0, 0, -2), "ArmUpper_R": Vector3(0, 0, 2),
		"ArmLower_L": Vector3(8, 0, 0), "ArmLower_R": Vector3(8, 0, 0),
	}
	library.add_animation("Idle", _animation_from(3.0, true, [[0.0, idle_a], [1.5, idle_b], [3.0, idle_a]]))

	var step := {
		"Leg_L": Vector3(24, 0, 0), "Shin_L": Vector3(-6, 0, 0), "Foot_L": Vector3(12, 0, 0),
		"Leg_R": Vector3(-18, 0, 0), "Shin_R": Vector3(-22, 0, 0), "Foot_R": Vector3(-14, 0, 0),
		"ArmUpper_L": Vector3(-18, 0, 0), "ArmLower_L": Vector3(8, 0, 0),
		"ArmUpper_R": Vector3(20, 0, 0), "ArmLower_R": Vector3(22, 0, 0),
		"Spine": Vector3(0, 5, 0), "Head": Vector3(0, -5, 0), "lift": -0.012,
	}
	var passing := {
		"Shin_L": Vector3(-5, 0, 0), "Leg_R": Vector3(8, 0, 0), "Shin_R": Vector3(-45, 0, 0), "Foot_R": Vector3(-5, 0, 0),
		"ArmLower_L": Vector3(12, 0, 0), "ArmLower_R": Vector3(12, 0, 0), "lift": 0.012,
	}
	library.add_animation("Walking_A", _cycle(0.75, step, passing))

	var stride := {
		"Leg_L": Vector3(40, 0, 0), "Shin_L": Vector3(-20, 0, 0), "Foot_L": Vector3(10, 0, 0),
		"Leg_R": Vector3(-25, 0, 0), "Shin_R": Vector3(-60, 0, 0), "Foot_R": Vector3(-20, 0, 0),
		"ArmUpper_L": Vector3(-35, 0, 0), "ArmLower_L": Vector3(70, 0, 0),
		"ArmUpper_R": Vector3(45, 0, 0), "ArmLower_R": Vector3(85, 0, 0),
		"Spine": Vector3(-10, 8, 0), "Head": Vector3(8, -8, 0), "lift": -0.02,
	}
	var flight := {
		"Leg_L": Vector3(-5, 0, 0), "Shin_L": Vector3(-25, 0, 0),
		"Leg_R": Vector3(35, 0, 0), "Shin_R": Vector3(-100, 0, 0), "Foot_R": Vector3(-10, 0, 0),
		"ArmUpper_L": Vector3(5, 0, 0), "ArmLower_L": Vector3(80, 0, 0),
		"ArmUpper_R": Vector3(5, 0, 0), "ArmLower_R": Vector3(80, 0, 0),
		"Spine": Vector3(-10, 0, 0), "Head": Vector3(8, 0, 0), "lift": 0.03,
	}
	library.add_animation("Running_A", _cycle(0.6, stride, flight))

	var tuck := {
		"Leg_L": Vector3(35, 0, 0), "Shin_L": Vector3(-55, 0, 0), "Foot_L": Vector3(-15, 0, 0),
		"Leg_R": Vector3(10, 0, 0), "Shin_R": Vector3(-30, 0, 0), "Foot_R": Vector3(-10, 0, 0),
		"ArmUpper_L": Vector3(-10, 0, -40), "ArmUpper_R": Vector3(-10, 0, 40),
		"ArmLower_L": Vector3(30, 0, 0), "ArmLower_R": Vector3(30, 0, 0), "Spine": Vector3(-4, 0, 0),
	}
	var tuck_b := tuck.duplicate()
	tuck_b["ArmUpper_L"] = Vector3(-10, 0, -48)
	tuck_b["ArmUpper_R"] = Vector3(-10, 0, 48)
	library.add_animation("Jump_Idle", _animation_from(1.0, true, [[0.0, tuck], [0.5, tuck_b], [1.0, tuck]]))

	var arms_up := {
		"ArmUpper_L": Vector3(0, 0, -150), "ArmUpper_R": Vector3(0, 0, 150),
		"ArmLower_L": Vector3(20, 0, 0), "ArmLower_R": Vector3(20, 0, 0), "Head": Vector3(15, 0, 0),
		"Leg_L": Vector3(10, 0, 0), "Leg_R": Vector3(10, 0, 0), "Shin_L": Vector3(-20, 0, 0), "Shin_R": Vector3(-20, 0, 0),
		"lift": -0.02,
	}
	var hop := {
		"ArmUpper_L": Vector3(0, 0, -158), "ArmUpper_R": Vector3(0, 0, 158), "Head": Vector3(15, 0, 0), "lift": 0.04,
	}
	library.add_animation("Cheer", _animation_from(1.5, false,
		[[0.0, idle_a], [0.25, arms_up], [0.5, hop], [0.75, arms_up], [1.0, hop], [1.5, idle_a]]))

	# Swinging a tool overhead with the right hand, then down in front.
	var wind_up := {
		"ArmUpper_R": Vector3(165, 0, 10), "ArmLower_R": Vector3(45, 0, 0),
		"ArmUpper_L": Vector3(20, 0, -10), "ArmLower_L": Vector3(30, 0, 0),
		"Spine": Vector3(-8, -15, 0), "Head": Vector3(-4, 10, 0),
	}
	var strike := {
		"ArmUpper_R": Vector3(45, 0, 0), "ArmLower_R": Vector3(10, 0, 0),
		"ArmUpper_L": Vector3(10, 0, 0), "ArmLower_L": Vector3(20, 0, 0),
		"Spine": Vector3(14, 12, 0), "Head": Vector3(-6, -6, 0), "lift": -0.01,
	}
	library.add_animation("Swing", _animation_from(0.6, false,
		[[0.0, idle_a], [0.22, wind_up], [0.34, strike], [0.6, idle_a]]))

	_animation = AnimationPlayer.new()
	_animation.name = "AnimationPlayer"
	add_child(_animation)
	_animation.add_animation_library("", library)


## A looping walk or run: a step with the left foot forward, the legs passing,
## then the same mirrored for the right foot.
func _cycle(length: float, step: Dictionary, passing: Dictionary) -> Animation:
	return _animation_from(length, true, [
		[0.0, step], [length * 0.25, passing], [length * 0.5, _mirror(step)],
		[length * 0.75, _mirror(passing)], [length, step],
	])


## The same pose for the other side.
func _mirror(pose: Dictionary) -> Dictionary:
	var mirrored := {}
	for joint: String in pose:
		var other := joint
		if joint.ends_with("_L"):
			other = joint.trim_suffix("_L") + "_R"
		elif joint.ends_with("_R"):
			other = joint.trim_suffix("_R") + "_L"
		var value = pose[joint]
		mirrored[other] = Vector3(value.x, -value.y, -value.z) if value is Vector3 else value
	return mirrored


## keys: [time, pose] pairs. Every joint is keyed in every animation, so
## blending from one to another never leaves a joint where the last one put it.
func _animation_from(length: float, loop: bool, keys: Array) -> Animation:
	var animation := Animation.new()
	animation.length = length
	animation.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var hips := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(hips, _paths["Hips"])
	for key in keys:
		var lift: float = key[1].get("lift", 0.0)
		animation.position_track_insert_key(hips, key[0], Vector3(0.0, _body["leg"] + lift * height, 0.0))
	for joint in JOINTS:
		var track := animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(track, _paths[joint])
		for key in keys:
			var degrees: Vector3 = key[1].get(joint, Vector3.ZERO)
			var euler: Vector3 = _rest[joint] + degrees * (PI / 180.0)
			animation.rotation_track_insert_key(track, key[0], Basis.from_euler(euler).get_rotation_quaternion())
	return animation


# --- Building blocks --------------------------------------------------------

func _joint(joint_name: String, parent: Variant, position: Vector3, rotation := Vector3.ZERO) -> Node3D:
	var joint := Node3D.new()
	joint.name = joint_name
	joint.position = position
	joint.rotation = rotation
	if parent == null:
		add_child(joint)
		_paths[joint_name] = joint_name
	else:
		_joints[parent].add_child(joint)
		_paths[joint_name] = "%s/%s" % [_paths[parent], joint_name]
	_joints[joint_name] = joint
	_rest[joint_name] = rotation
	return joint


func _add(parent: Node3D, mesh: Mesh, material: Material, position := Vector3.ZERO, rotation := Vector3.ZERO) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	instance.rotation = rotation
	parent.add_child(instance)
	return instance


## A closed (or open-ended) tube through rings of [y, half width, half depth in
## front, half depth behind], with smooth normals.
func _loft(rings: Array, cap_bottom := true, cap_top := true) -> ArrayMesh:
	if rings[-1][0] < rings[0][0]:
		# Limbs list their rings downwards; the winding below needs them upwards.
		rings = rings.duplicate()
		rings.reverse()
		var swap := cap_bottom
		cap_bottom = cap_top
		cap_top = swap
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := SEGMENTS
	for ring in rings:
		for i in n:
			var angle := TAU * i / n
			var s := sin(angle)
			# Front is -Z.
			var depth: float = ring[2] if s < 0.0 else ring[3]
			st.add_vertex(Vector3(cos(angle) * ring[1], ring[0], s * depth))
	for r in rings.size() - 1:
		for i in n:
			var a := r * n + i
			var b := r * n + (i + 1) % n
			# Godot's front faces wind clockwise.
			st.add_index(a)
			st.add_index(b)
			st.add_index(a + n)
			st.add_index(b)
			st.add_index(b + n)
			st.add_index(a + n)
	if cap_bottom:
		var center := rings.size() * n
		st.add_vertex(Vector3(0.0, rings[0][0], 0.0))
		for i in n:
			st.add_index(center)
			st.add_index((i + 1) % n)
			st.add_index(i)
	if cap_top:
		var center := rings.size() * n + (1 if cap_bottom else 0)
		var last := (rings.size() - 1) * n
		st.add_vertex(Vector3(0.0, rings[-1][0], 0.0))
		for i in n:
			st.add_index(center)
			st.add_index(last + i)
			st.add_index(last + (i + 1) % n)
	st.generate_normals()
	return st.commit()


## An ellipsoid with these half-sizes, centered on the origin.
func _ellipsoid(radii: Vector3) -> ArrayMesh:
	var rings := []
	for k in 9:
		var angle := PI * k / 8.0
		# Not quite zero at the poles, so every triangle has an area.
		var across := maxf(sin(angle), 0.001)
		rings.append([-radii.y * cos(angle), radii.x * across, radii.z * across, radii.z * across])
	return _loft(rings, false, false)


func _box(size: Vector3) -> BoxMesh:
	var box := BoxMesh.new()
	box.size = size
	return box


static func _material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.85
		_materials[color] = material
	return _materials[color]
