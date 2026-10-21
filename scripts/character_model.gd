extends Node3D
## The animated model for one race and sex, used by players in the world and
## by the preview in character select. Call setup() once, then set_motion()
## whenever the character moves; it picks and blends idle, walk, run and jump.
##
## The model is built in code from the race's body measurements (see
## scripts/races.gd): a jointed body of lofted meshes for the torso, head and
## limbs, a face, hair, and the tunic, trousers and foot wraps every character
## starts in. The animations are keyframed on those joints here too.
##
## The look is old-school MMO: chunky low-poly shapes with exaggerated
## shoulders, hands, feet and noses so they read at a distance, and the detail
## hand painted on top by shaders/hand_painted.gdshader (cloth weave and folds,
## hair strands, painted light and shade, and the whole face).
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
## Sides around limbs, and around the torso and head. Few on purpose.
const SEGMENTS := 8
const BODY_SEGMENTS := 10
## How much bigger than life hands and feet are, for the chunky look.
const HAND_SCALE := 1.4
const FOOT_SCALE := 1.35

const PAINTED_SHADER := preload("res://shaders/hand_painted.gdshader")
## The patterns the shader paints (see shaders/hand_painted.gdshader).
enum { SKIN, LINEN, WOOL, LEATHER, HAIR, METAL, ROPE }

const SHIRT_COLOR := Color(0.8, 0.74, 0.6)
const TRIM_COLOR := Color(0.5, 0.2, 0.15)
const PANTS_COLOR := Color(0.36, 0.27, 0.19)
const WRAP_COLOR := Color(0.62, 0.56, 0.46)
const ROPE_COLOR := Color(0.66, 0.55, 0.36)
const SOLE_COLOR := Color(0.3, 0.21, 0.14)
const LIP_COLOR := Color(0.62, 0.3, 0.27)
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
	var skin := _skin_material()
	var shirt := _paint(LINEN, SHIRT_COLOR)
	var trim := _paint(LINEN, TRIM_COLOR)
	var pants := _paint(WOOL, PANTS_COLOR)
	var torso: float = b["torso"]
	var chest: Vector2 = b["chest"]
	var waist: Vector2 = b["waist"]
	var pelvis: Vector2 = b["pelvis"]
	var belly: float = b["belly"]
	var bust: float = b["bust"]
	var leg_r: float = b["leg_r"]
	var arm_r: float = b["arm_r"]

	# Trousers from the crotch up to just under the tunic.
	var hips := _joint("Hips", null, Vector3(0.0, b["leg"], 0.0))
	var top := pelvis.lerp(waist, 0.6)
	_add(hips, _loft([
		[-leg_r * 1.1, pelvis.x * 0.78, pelvis.y * 0.75, pelvis.y * 0.8],
		[-leg_r * 0.45, pelvis.x * 0.97, pelvis.y * 0.95, pelvis.y],
		[0.0, pelvis.x, pelvis.y + belly * 0.2, pelvis.y * 1.04],
		[torso * 0.24, top.x, top.y + belly * 0.4, top.y],
	]), pants)

	# The tunic's skirt flares over the top of the legs, with a dyed hem. It
	# hangs from the hips so it stays put when the body leans.
	var flare := pelvis * 1.28
	var belt_y := torso * 0.2
	var skirt := [
		[-leg_r * 0.85, flare.x, flare.y + belly * 0.3, flare.y],
		[-leg_r * 0.2, pelvis.x * 1.2, pelvis.y * 1.18 + belly * 0.3, pelvis.y * 1.18],
		[belt_y + 0.01, top.x * 1.06, top.y * 1.06 + belly * 0.45, top.y * 1.06],
	]
	_add(hips, _loft(skirt, true, true, BODY_SEGMENTS), shirt)
	_add(hips, _band(-leg_r * 0.85, -leg_r * 0.68, flare * 1.03, belly * 0.3), trim)
	# A rope belt knotted at the side, its ends hanging.
	var belt := top * 1.12
	_add(hips, _band(belt_y - 0.016, belt_y + 0.016, belt, belly * 0.45), _paint(ROPE, ROPE_COLOR, Vector3.RIGHT))
	var rope := _paint(ROPE, ROPE_COLOR)
	var knot := Vector3(belt.x * 0.55, belt_y, -(belt.y + belly * 0.45) * 0.93)
	_add(hips, _ellipsoid(Vector3(0.03, 0.026, 0.024)), rope, knot)
	for end in [-1.0, 1.0]:
		_add(hips, _loft([[0.0, 0.011, 0.011, 0.011], [-torso * 0.2, 0.009, 0.009, 0.009]], true, true, 5), rope,
			knot + Vector3(0.012 * end, 0.0, -0.008), Vector3(deg_to_rad(-6.0), 0.0, deg_to_rad(6.0 * end + 4.0)))

	# The rest of the torso bends at the waist, inside the tunic.
	var spine_y := torso * 0.2
	var spine := _joint("Spine", "Hips", Vector3(0.0, spine_y, 0.0))
	var hem := pelvis.lerp(waist, 0.45) * 1.07
	var mid := waist.lerp(chest, 0.6)
	var shoulder_x: float = b["shoulders"] + arm_r * 0.45
	var neckline := Vector2(maxf(b["neck_r"] * 1.6, shoulder_x * 0.5), b["neck_r"] * 1.45)
	_add(spine, _loft([
		[torso * 0.13 - spine_y, hem.x, hem.y + belly * 0.45, hem.y],
		[torso * 0.36 - spine_y, waist.x, waist.y + belly, waist.y],
		[torso * 0.55 - spine_y, mid.x, mid.y + belly * 0.6 + bust * 0.3, mid.y],
		[torso * 0.72 - spine_y, chest.x, chest.y + bust, chest.y],
		[torso * 0.86 - spine_y, chest.x, chest.y * 0.95 + bust * 0.35, chest.y * 0.95],
		[torso * 0.95 - spine_y, shoulder_x, chest.y * 0.72, chest.y * 0.75],
		[torso * 1.02 - spine_y, neckline.x, neckline.y, b["neck_r"] * 1.5],
	], true, true, BODY_SEGMENTS), shirt)
	# A dyed collar.
	_add(spine, _loft([
		[torso * 0.975 - spine_y, neckline.x * 1.12, neckline.y * 1.12, neckline.y * 1.1],
		[torso * 1.035 - spine_y, neckline.x * 0.98, neckline.y * 1.0, neckline.y * 1.0],
	], true, true, BODY_SEGMENTS), trim)

	var neck := _joint("Neck", "Spine", Vector3(0.0, torso * 0.97 - spine_y, 0.0))
	var neck_r: float = b["neck_r"]
	_add(neck, _loft([[-b["neck"] * 0.6, neck_r, neck_r, neck_r], [b["neck"] + b["head"] * 0.5, neck_r * 0.92, neck_r * 0.92, neck_r * 0.92]]), skin)
	var head := _joint("Head", "Neck", Vector3(0.0, b["neck"], 0.0))
	_build_head(head, skin, _paint(HAIR, info["hair_color"]))

	for side in ["L", "R"]:
		var s := -1.0 if side == "L" else 1.0
		_build_arm(side, s, spine, Vector3(b["shoulders"] * s, torso * 0.9 - spine_y, 0.0), skin, shirt, trim)
		_build_leg(side, s, skin, pants)


func _build_arm(side: String, s: float, spine: Node3D, at: Vector3, skin: Material, shirt: Material, trim: Material) -> void:
	var b := _body
	var arm: float = b["arm"]
	var forearm := arm * 0.9
	var r: float = b["arm_r"]
	# Hang the arms out just far enough to clear the hips and the tunic.
	var clearance: float = b["pelvis"].x * 1.28 + r * 1.3 - b["shoulders"]
	var out := maxf(atan2(clearance, arm + forearm), deg_to_rad(3.0))
	var upper := _joint("ArmUpper_" + side, "Spine", at, Vector3(0.0, 0.0, out * s))
	# Big rounded shoulders and short, wide sleeves with a dyed cuff.
	_add(upper, _ellipsoid(Vector3(r * 1.45, r * 1.35, r * 1.4)), shirt, Vector3(0.0, -r * 0.1, 0.0))
	_add(upper, _loft([[0.0, r * 1.3, r * 1.3, r * 1.3], [-arm * 0.45, r * 1.32, r * 1.32, r * 1.32]]), shirt)
	_add(upper, _band(-arm * 0.47, -arm * 0.39, Vector2(r, r) * 1.38, 0.0), trim)
	_add(upper, _loft([[0.0, r, r, r], [-arm, r * 0.88, r * 0.88, r * 0.88]]), skin)

	var lower := _joint("ArmLower_" + side, "ArmUpper_" + side, Vector3(0.0, -arm, 0.0), Vector3(deg_to_rad(8.0), 0.0, 0.0))
	_add(lower, _ellipsoid(Vector3.ONE * r * 0.9), skin)
	# Chunky forearms, thicker toward the wrist, the way old models drew them.
	_add(lower, _loft([[0.0, r * 0.88, r * 0.88, r * 0.88], [-forearm * 0.45, r * 0.92, r * 0.85, r * 0.85], [-forearm, r * 0.72, r * 0.7, r * 0.7]]), skin)

	# Big, blocky hands read at a distance.
	var hand := _joint("Hand_" + side, "ArmLower_" + side, Vector3(0.0, -forearm, 0.0))
	var h := r * HAND_SCALE
	_add(hand, _ellipsoid(Vector3(h * 0.5, h * 1.1, h * 0.85)), skin, Vector3(0.0, -h * 0.85, 0.0))
	_add(hand, _ellipsoid(Vector3(h * 0.28, h * 0.5, h * 0.3)), skin, Vector3(-s * h * 0.15, -h * 0.5, -h * 0.7), Vector3(deg_to_rad(-30.0), 0.0, 0.0))


func _build_leg(side: String, s: float, skin: Material, pants: Material) -> void:
	var b := _body
	var r: float = b["leg_r"]
	var ankle := maxf(b["leg"] * 0.06, r * 0.6)
	var thigh: float = (b["leg"] - ankle) * 0.5
	var shin := thigh
	var wraps := _paint(LINEN, WRAP_COLOR, Vector3.RIGHT)

	var upper := _joint("Leg_" + side, "Hips", Vector3(b["hips"] * s, 0.0, 0.0))
	_add(upper, _loft([[r * 0.6, r * 0.95, r * 0.95, r * 0.95], [-thigh, r * 0.76, r * 0.76, r * 0.76]]), pants)

	var lower := _joint("Shin_" + side, "Leg_" + side, Vector3(0.0, -thigh, 0.0))
	_add(lower, _ellipsoid(Vector3.ONE * r * 0.78), pants)
	_add(lower, _loft([[0.0, r * 0.76, r * 0.76, r * 0.76], [-shin * 0.5, r * 0.68, r * 0.68, r * 0.68]]), pants)
	# Cloth wraps bound around the shin, wider toward the ankle.
	_add(lower, _loft([
		[-shin * 0.42, r * 0.66, r * 0.68, r * 0.66],
		[-shin * 0.75, r * 0.6, r * 0.62, r * 0.6],
		[-shin - ankle * 0.4, r * 0.66, r * 0.7, r * 0.66],
	]), wraps)
	for k in 3:
		_add(lower, _band(-shin * (0.48 + k * 0.17) - 0.007, -shin * (0.48 + k * 0.17) + 0.007, Vector2(r * 0.68, r * 0.7), 0.0), _paint(LEATHER, SOLE_COLOR))

	# Big wrapped feet.
	var foot := _joint("Foot_" + side, "Shin_" + side, Vector3(0.0, -shin, 0.0))
	var f := r * FOOT_SCALE
	_add(foot, _ellipsoid(Vector3(f * 0.55, ankle * 0.6, f * 1.2)), wraps, Vector3(0.0, -ankle * 0.45, -f * 0.5))
	_add(foot, _ellipsoid(Vector3(f * 0.5, ankle * 0.3, f * 1.15)), _paint(LEATHER, SOLE_COLOR), Vector3(0.0, -ankle * 0.85, -f * 0.5))


func _build_head(head: Node3D, skin: Material, hair: Material) -> void:
	var r: float = _body["head"]
	var j: float = _body["jaw"]
	var info: Dictionary = Races.INFO[race]
	var rings := []
	# A squarer jaw and cheekbones than a real skull, for a strong silhouette.
	for ring in [
		[-0.1, 0.5 * j, 0.55, 0.45], [0.2, 0.8 * j, 0.86, 0.78], [0.55, 0.95 * lerpf(1.0, j, 0.5), 0.98, 0.95],
		[0.95, 1.02, 1.0, 1.0], [1.35, 0.98, 0.95, 1.0], [1.7, 0.85, 0.8, 0.86], [2.0, 0.55, 0.5, 0.56],
		[2.18, 0.15, 0.14, 0.15],
	]:
		rings.append(ring.map(func(v: float) -> float: return v * r))
	# The eyes, brows, mouth and cheeks are painted on the face.
	_add(head, _loft(rings, true, true, BODY_SEGMENTS), _face_material(r, j))

	var ogre: bool = info.get("tusks", false)
	if ogre:
		# A heavy brow ridge scowling down to the nose, a flat broad nose and
		# tusks.
		for s in [-1.0, 1.0]:
			_add(head, _ellipsoid(Vector3(0.46, 0.15, 0.22) * r), skin, Vector3(0.36 * s, 1.3, -0.86) * r, Vector3(0.0, 0.0, deg_to_rad(16.0 * s)))
		_add(head, _ellipsoid(Vector3(0.28, 0.19, 0.22) * r), skin, Vector3(0.0, 0.8, -0.98) * r)
		var tusk := _paint(SKIN, TUSK_COLOR)
		for s in [-1.0, 1.0]:
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 0.08 * r
			cone.height = 0.42 * r
			cone.radial_segments = 6
			cone.rings = 1
			_add(head, cone, tusk, Vector3(0.34 * j * s, 0.64, -0.86) * r, Vector3(deg_to_rad(-12.0), 0.0, deg_to_rad(-12.0 * s)))
	else:
		# A big, wedge-shaped nose.
		var nose := 1.2 if race == "dwarf" else 1.0
		_add(head, _ellipsoid(Vector3(0.13, 0.19, 0.16) * r * nose), skin, Vector3(0.0, 0.8, -0.98) * r, Vector3(deg_to_rad(-12.0), 0.0, 0.0))

	# Ears.
	for s in [-1.0, 1.0]:
		if info.get("ears", false):
			# Long, swept-back points.
			var point := PrismMesh.new()
			point.size = Vector3(0.4, 1.35, 0.12) * r
			_add(head, point, skin, Vector3(1.08 * s, 1.3, 0.15) * r, Vector3(deg_to_rad(-28.0), 0.0, deg_to_rad(-55.0 * s)))
		else:
			var ear := 0.32 if ogre else 0.26
			_add(head, _ellipsoid(Vector3(0.5, 1.0, 0.75) * ear * r), skin, Vector3(1.04 * s, 0.92, 0.0) * r)

	_build_hair(head, r, hair)
	if _body.get("beard", false):
		_build_beard(head, r, hair)


func _build_hair(head: Node3D, r: float, hair: Material) -> void:
	var style: String = _body["hair"]
	var tie := _paint(LEATHER, PANTS_COLOR)
	if style == "topknot":
		# Bald but for a knot on the crown.
		_add(head, _ellipsoid(Vector3(0.28, 0.32, 0.28) * r), hair, Vector3(0.0, 2.27, 0.25) * r)
		_add(head, _ellipsoid(Vector3(0.32, 0.09, 0.32) * r), tie, Vector3(0.0, 2.08, 0.22) * r)
		return
	# A cap over the crown, tipped back so the hairline clears the brows, and
	# the back of the head down to the nape.
	var dome := []
	for k in 4:
		var angle := PI * 0.5 * k / 3.0
		dome.append([sin(angle) * 1.1 * r, maxf(cos(angle), 0.15) * 1.1 * r, cos(angle) * 1.1 * r, cos(angle) * 1.1 * r])
	_add(head, _loft(dome, true, true, BODY_SEGMENTS), hair, Vector3(0.0, 1.15, 0.05) * r, Vector3(deg_to_rad(22.0), 0.0, 0.0))
	_add(head, _ellipsoid(Vector3(0.95, 0.97, 0.92) * r), hair, Vector3(0.0, 1.05, 0.22) * r)
	match style:
		"short":
			# A tousled fringe.
			_add(head, _ellipsoid(Vector3(0.75, 0.18, 0.3) * r), hair, Vector3(0.1, 1.62, -0.78) * r, Vector3(deg_to_rad(-25.0), 0.0, deg_to_rad(-6.0)))
		"long":
			_add(head, _ellipsoid(Vector3(0.92, 1.3, 0.36) * r), hair, Vector3(0.0, 0.3, 0.72) * r, Vector3(deg_to_rad(8.0), 0.0, 0.0))
			for s in [-1.0, 1.0]:
				_add(head, _ellipsoid(Vector3(0.22, 0.8, 0.4) * r), hair, Vector3(0.88 * s, 0.55, 0.15) * r, Vector3(0.0, 0.0, deg_to_rad(4.0 * s)))
		"ponytail":
			_add(head, _ellipsoid(Vector3(0.17, 0.13, 0.17) * r), tie, Vector3(0.0, 1.15, 1.08) * r)
			_add(head, _ellipsoid(Vector3(0.24, 0.85, 0.22) * r), hair, Vector3(0.0, 0.4, 1.17) * r, Vector3(deg_to_rad(14.0), 0.0, 0.0))
		"bun":
			_add(head, _ellipsoid(Vector3(0.48, 0.45, 0.45) * r), hair, Vector3(0.0, 1.75, 0.85) * r)
		"braids":
			var gold := _paint(METAL, GOLD_COLOR)
			for s in [-1.0, 1.0]:
				_add(head, _loft([[0.0, 0.18 * r, 0.18 * r, 0.18 * r], [-1.5 * r, 0.12 * r, 0.12 * r, 0.12 * r]], true, true, 6), hair, Vector3(0.82 * s, 0.85, -0.05) * r, Vector3(deg_to_rad(12.0), 0.0, deg_to_rad(6.0 * s)))
				_add(head, _ellipsoid(Vector3(0.17, 0.07, 0.17) * r), gold, Vector3(0.95 * s, -0.45, -0.32) * r)


## A broad beard hiding the mouth, a moustache, and a forked, braided end with
## gold rings.
func _build_beard(head: Node3D, r: float, hair: Material) -> void:
	_add(head, _ellipsoid(Vector3(0.86, 0.62, 0.52) * r), hair, Vector3(0.0, 0.32, -0.55) * r)
	var wedge := PrismMesh.new()
	wedge.size = Vector3(1.4, 1.3, 0.5) * r
	_add(head, wedge, hair, Vector3(0.0, -0.38, -0.72) * r, Vector3(deg_to_rad(-10.0), 0.0, PI))
	var gold := _paint(METAL, GOLD_COLOR)
	for s in [-1.0, 1.0]:
		_add(head, _ellipsoid(Vector3(0.36, 0.11, 0.14) * r), hair, Vector3(0.22 * s, 0.6, -0.95) * r, Vector3(0.0, 0.0, deg_to_rad(-18.0 * s)))
		_add(head, _loft([[0.0, 0.12 * r, 0.12 * r, 0.12 * r], [-0.6 * r, 0.09 * r, 0.09 * r, 0.09 * r]], true, true, 6), hair, Vector3(0.2 * s, -0.78, -0.8) * r, Vector3(deg_to_rad(-12.0), 0.0, deg_to_rad(6.0 * s)))
		_add(head, _ellipsoid(Vector3(0.15, 0.07, 0.15) * r), gold, Vector3(0.23 * s, -1.1, -0.87) * r)


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
## front, half depth behind], with smooth normals, `segments` sides around.
func _loft(rings: Array, cap_bottom := true, cap_top := true, segments := SEGMENTS) -> ArrayMesh:
	if rings[-1][0] < rings[0][0]:
		# Limbs list their rings downwards; the winding below needs them upwards.
		rings = rings.duplicate()
		rings.reverse()
		var swap := cap_bottom
		cap_bottom = cap_top
		cap_top = swap
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := segments
	for ring in rings:
		for i in n:
			# Half a step round, so there's a flat face at the front rather
			# than an edge, for the face to be painted on.
			var angle := TAU * (i + 0.5) / n
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


## A chunky ellipsoid with these half-sizes, centered on the origin.
func _ellipsoid(radii: Vector3) -> ArrayMesh:
	var rings := []
	for k in 7:
		var angle := PI * k / 6.0
		# Not quite zero at the poles, so every triangle has an area.
		var across := maxf(sin(angle), 0.001)
		rings.append([-radii.y * cos(angle), radii.x * across, radii.z * across, radii.z * across])
	return _loft(rings, false, false)


## A band around the body from y0 to y1, like a hem, belt or collar, size
## half the width and depth; `belly` pushes its front out.
func _band(y0: float, y1: float, size: Vector2, belly: float) -> ArrayMesh:
	var ring := [size.x, size.y + belly, size.y]
	return _loft([[y0] + ring, [y1] + ring], true, true, BODY_SEGMENTS)


## The shared hand-painted material for a pattern in a color. The shade and
## light are painted in hue-shifted, the way an illustrator would: shadows
## cooler and richer, lights warmer.
static func _paint(pattern: int, color: Color, grain := Vector3.UP) -> ShaderMaterial:
	var key := "%d %s %s" % [pattern, color, grain]
	if not _materials.has(key):
		var material := ShaderMaterial.new()
		material.shader = PAINTED_SHADER
		var shadow := Color(0.42, 0.14, 0.16) if pattern == SKIN else Color(0.16, 0.13, 0.26)
		material.set_shader_parameter("pattern", pattern)
		material.set_shader_parameter("base_color", color)
		material.set_shader_parameter("shade_color", color.darkened(0.5).lerp(shadow, 0.3))
		material.set_shader_parameter("light_color", color.lightened(0.35).lerp(Color(1.0, 0.94, 0.75), 0.25))
		material.set_shader_parameter("grain", grain)
		_materials[key] = material
	return _materials[key]


func _skin_material() -> ShaderMaterial:
	return _paint(SKIN, Races.INFO[race]["skin"])


## The skin of the head, with this race and sex's face painted on.
func _face_material(r: float, jaw: float) -> ShaderMaterial:
	var key := "face %s %s" % [race, sex]
	if not _materials.has(key):
		var info: Dictionary = Races.INFO[race]
		var material: ShaderMaterial = _skin_material().duplicate()
		material.set_shader_parameter("face", true)
		material.set_shader_parameter("head_r", r)
		material.set_shader_parameter("jaw", jaw)
		material.set_shader_parameter("eye_size", info.get("eye_size", 1.0))
		material.set_shader_parameter("brow_tilt", info.get("brow_tilt", 0.0))
		material.set_shader_parameter("lid", info.get("lid", 0.0))
		material.set_shader_parameter("smile", info.get("smile", 0.3))
		material.set_shader_parameter("stubble", _body.get("stubble", 0.0))
		material.set_shader_parameter("hair_color", info["hair_color"])
		material.set_shader_parameter("iris_color", info["eye_color"])
		material.set_shader_parameter("lip_color", LIP_COLOR.lerp(info["skin"], 0.3))
		_materials[key] = material
	return _materials[key]
