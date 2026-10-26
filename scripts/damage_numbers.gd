extends Label3D
## A number that pops up over something as it's hurt or healed, then floats
## up and fades away: red for damage, green for healing, and pale grey for
## "Miss" when an attack misses. Players and enemies call pop() on every peer
## from an RPC the server sends when their health changes (see
## Player.take_damage() and BigFrog.take_damage()).
##
## Drawn over everything and always facing the camera, like the nameplates.
## It's added to the viewport rather than to whatever was hit, so it stays
## where it popped up and outlives an enemy that dies.

const DAMAGE_COLOR := Color(1.0, 0.25, 0.2)
const HEAL_COLOR := Color(0.35, 1.0, 0.35)
const MISS_COLOR := Color(0.85, 0.85, 0.85)
## Seconds it shows for, and how far it rises in that time.
const SECONDS := 1.0
const RISE := 0.9
## How far to either side of the middle it pops up, so numbers in quick
## succession don't sit on top of each other.
const SPREAD := 0.45

const CharacterModel := preload("res://scripts/character_model.gd")


## Pops up `amount` over `over`, `height` meters above its feet: a loss of
## health for a negative amount, healing for a positive one. Does nothing for
## 0, or where nothing is drawn (a headless peer).
static func pop(over: Node3D, amount: int, height: float) -> void:
	if amount == 0:
		return
	show_text(over, "+%d" % amount if amount > 0 else str(-amount),
		HEAL_COLOR if amount > 0 else DAMAGE_COLOR, height)


## Pops up "Miss" over `over`.
static func miss(over: Node3D, height: float) -> void:
	show_text(over, "Miss", MISS_COLOR, height)


static func show_text(over: Node3D, text: String, color: Color, height: float) -> void:
	if not CharacterModel.can_show_models() or not over.is_inside_tree():
		return
	var label := (load("res://scripts/damage_numbers.gd") as GDScript).new() as Label3D
	label.text = text
	label.modulate = color
	# The viewport sits at the world's origin, so this is where it shows.
	label.position = over.global_position \
		+ Vector3(randf_range(-SPREAD, SPREAD), height + randf_range(0.0, 0.15), randf_range(-SPREAD, SPREAD))
	over.get_viewport().add_child(label)


func _init() -> void:
	name = "DamageNumber"
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	fixed_size = false
	font_size = 72
	outline_size = 14
	outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	render_priority = 2
	outline_render_priority = 1


func _ready() -> void:
	var tween := create_tween()
	# A quick pop bigger, then drift up and fade out.
	scale = Vector3.ONE * 0.6
	tween.tween_property(self, "scale", Vector3.ONE * 1.15, 0.08)
	tween.tween_property(self, "scale", Vector3.ONE, 0.1)
	tween.parallel().tween_property(self, "position:y", position.y + RISE, SECONDS) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_property(self, "modulate:a", 0.0, SECONDS * 0.5).set_delay(SECONDS * 0.5)
	tween.parallel().tween_property(self, "outline_modulate:a", 0.0, SECONDS * 0.5).set_delay(SECONDS * 0.5)
	tween.tween_callback(queue_free)
