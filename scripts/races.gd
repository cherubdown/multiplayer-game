extends RefCounted
## The playable races and sexes. Both are picked when a character is created,
## saved with the character on the server, and decide which model everyone
## sees.
##
## The models are built in code by CharacterModel from the body measurements
## below (in meters), so every race and sex has its own shape without any
## imported assets. Every new character wears the same plain linen t-shirt and
## brown trousers, and nothing else.

const DEFAULT := "human"
const IDS: Array[String] = ["human", "elf", "dwarf", "ogre"]

const DEFAULT_SEX := "male"
const SEXES: Array[String] = ["male", "female"]
const SEX_NAMES := { "male": "Male", "female": "Female" }

## Body measurements, used by CharacterModel:
##   leg       hip joint to the ground
##   torso     hip joint to the base of the neck
##   neck      length of the neck; neck_r its radius
##   head      half the width of the head (it is about 2.25 times as tall)
##   jaw       how wide the lower face is, 1 for a human
##   shoulders, hips   half the distance between the arm and leg joints
##   chest, waist, pelvis   half the width (x) and depth (y) of the torso there
##   belly, bust   how far the belly or chest sticks out in front
##   arm       upper arm length (the forearm is a little shorter); arm_r its radius
##   leg_r     thigh radius
##   hair      style: short, long, ponytail, braids, topknot or bun
const INFO := {
	"human": {
		"name": "Human",
		"description": "Sturdy and adaptable, at home in any land.",
		"skin": Color(0.89, 0.69, 0.56),
		"hair_color": Color(0.33, 0.21, 0.12),
		"bodies": {
			"male": {
				"leg": 0.88, "torso": 0.55, "neck": 0.07, "neck_r": 0.061, "head": 0.141, "jaw": 1.0,
				"shoulders": 0.2, "hips": 0.095,
				"chest": Vector2(0.18, 0.11), "waist": Vector2(0.145, 0.095), "pelvis": Vector2(0.16, 0.105),
				"belly": 0.0, "bust": 0.0, "arm": 0.3, "arm_r": 0.055, "leg_r": 0.083,
				"hair": "short",
			},
			"female": {
				"leg": 0.84, "torso": 0.5, "neck": 0.075, "neck_r": 0.052, "head": 0.133, "jaw": 0.92,
				"shoulders": 0.17, "hips": 0.1,
				"chest": Vector2(0.15, 0.095), "waist": Vector2(0.12, 0.082), "pelvis": Vector2(0.17, 0.11),
				"belly": 0.0, "bust": 0.05, "arm": 0.28, "arm_r": 0.046, "leg_r": 0.081,
				"hair": "long",
			},
		},
	},
	"elf": {
		"name": "Elf",
		"description": "Tall, swift and keen-eyed children of the old forests.",
		"skin": Color(0.96, 0.85, 0.76),
		"hair_color": Color(0.93, 0.85, 0.6),
		"ears": true,
		"bodies": {
			"male": {
				"leg": 0.98, "torso": 0.58, "neck": 0.085, "neck_r": 0.053, "head": 0.133, "jaw": 0.92,
				"shoulders": 0.19, "hips": 0.09,
				"chest": Vector2(0.165, 0.1), "waist": Vector2(0.13, 0.085), "pelvis": Vector2(0.145, 0.095),
				"belly": 0.0, "bust": 0.0, "arm": 0.33, "arm_r": 0.048, "leg_r": 0.073,
				"hair": "ponytail",
			},
			"female": {
				"leg": 0.95, "torso": 0.53, "neck": 0.09, "neck_r": 0.046, "head": 0.127, "jaw": 0.86,
				"shoulders": 0.16, "hips": 0.095,
				"chest": Vector2(0.14, 0.088), "waist": Vector2(0.108, 0.076), "pelvis": Vector2(0.155, 0.1),
				"belly": 0.0, "bust": 0.042, "arm": 0.31, "arm_r": 0.041, "leg_r": 0.072,
				"hair": "long",
			},
		},
	},
	"dwarf": {
		"name": "Dwarf",
		"description": "Short, broad and stubborn as the mountains they mine.",
		"skin": Color(0.87, 0.63, 0.5),
		"hair_color": Color(0.55, 0.24, 0.1),
		"bodies": {
			"male": {
				"leg": 0.5, "torso": 0.5, "neck": 0.04, "neck_r": 0.077, "head": 0.153, "jaw": 1.1,
				"shoulders": 0.23, "hips": 0.11,
				"chest": Vector2(0.22, 0.15), "waist": Vector2(0.2, 0.15), "pelvis": Vector2(0.2, 0.14),
				"belly": 0.04, "bust": 0.0, "arm": 0.24, "arm_r": 0.071, "leg_r": 0.099,
				"hair": "short", "beard": true,
			},
			"female": {
				"leg": 0.48, "torso": 0.46, "neck": 0.045, "neck_r": 0.066, "head": 0.145, "jaw": 1.0,
				"shoulders": 0.2, "hips": 0.115,
				"chest": Vector2(0.19, 0.13), "waist": Vector2(0.165, 0.12), "pelvis": Vector2(0.2, 0.14),
				"belly": 0.0, "bust": 0.055, "arm": 0.22, "arm_r": 0.06, "leg_r": 0.097,
				"hair": "braids",
			},
		},
	},
	"ogre": {
		"name": "Ogre",
		"description": "Huge, tusked and terribly strong, if not terribly patient.",
		"skin": Color(0.56, 0.64, 0.4),
		"hair_color": Color(0.12, 0.1, 0.09),
		"tusks": true,
		"bodies": {
			"male": {
				"leg": 1.0, "torso": 0.9, "neck": 0.05, "neck_r": 0.132, "head": 0.181, "jaw": 1.3,
				"shoulders": 0.38, "hips": 0.17,
				"chest": Vector2(0.36, 0.24), "waist": Vector2(0.34, 0.26), "pelvis": Vector2(0.32, 0.22),
				"belly": 0.12, "bust": 0.0, "arm": 0.5, "arm_r": 0.115, "leg_r": 0.154,
				"hair": "topknot",
			},
			"female": {
				"leg": 0.95, "torso": 0.8, "neck": 0.06, "neck_r": 0.11, "head": 0.169, "jaw": 1.18,
				"shoulders": 0.32, "hips": 0.17,
				"chest": Vector2(0.3, 0.2), "waist": Vector2(0.27, 0.2), "pelvis": Vector2(0.31, 0.22),
				"belly": 0.05, "bust": 0.08, "arm": 0.46, "arm_r": 0.098, "leg_r": 0.143,
				"hair": "bun",
			},
		},
	},
}


static func is_valid(id: Variant) -> bool:
	return id is String and id in IDS


static func is_valid_sex(sex: Variant) -> bool:
	return sex is String and sex in SEXES


static func display_name(id: String) -> String:
	return INFO.get(id, INFO[DEFAULT])["name"]


## "Female Elf", "Male Ogre".
static func describe(id: String, sex: String) -> String:
	return "%s %s" % [SEX_NAMES.get(sex, SEX_NAMES[DEFAULT_SEX]), display_name(id)]


## The body measurements for a race and sex (see INFO).
static func body(id: String, sex: String) -> Dictionary:
	var bodies: Dictionary = INFO.get(id, INFO[DEFAULT])["bodies"]
	return bodies.get(sex, bodies[DEFAULT_SEX])
