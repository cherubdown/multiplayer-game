extends RefCounted
## Deterministic world generator. Every peer builds the same world from the
## same seed string: the height of the ground and the biome at any point.
##
## The world is an island SIZE meters across, centered on the origin. Like
## Valheim, the calm Meadows are always in the middle where players spawn, and
## the biomes get harsher further out: Black Forest and Swamp, then Plains, with
## Mountains wherever the land rises high and Ocean around the edge.
##
## Only depends on the seed and FastNoiseLite, so the server and the clients
## agree without sending any terrain over the network.

enum Biome { OCEAN, MEADOWS, BLACK_FOREST, SWAMP, PLAINS, MOUNTAINS }

## Width and depth of the world in meters.
const SIZE := 1024.0
## Height of the sea surface. Ground below it is under water.
const SEA_LEVEL := 0.0
## Players spawn within this distance of the center, which is always Meadows.
const MEADOWS_RADIUS := 140.0

const BIOME_NAMES := {
	Biome.OCEAN: "Ocean",
	Biome.MEADOWS: "Meadows",
	Biome.BLACK_FOREST: "Black Forest",
	Biome.SWAMP: "Swamp",
	Biome.PLAINS: "Plains",
	Biome.MOUNTAINS: "Mountains",
}

## Ground color of each biome.
const BIOME_COLORS := {
	Biome.OCEAN: Color(0.62, 0.56, 0.4),
	Biome.MEADOWS: Color(0.36, 0.55, 0.22),
	Biome.BLACK_FOREST: Color(0.16, 0.25, 0.13),
	Biome.SWAMP: Color(0.24, 0.23, 0.15),
	Biome.PLAINS: Color(0.5, 0.48, 0.2),
	Biome.MOUNTAINS: Color(0.3, 0.3, 0.32),
}

## The seed as typed.
var seed_text: String
## The seed as the number the noise generators use.
var seed_number: int

var _continent := FastNoiseLite.new()  # where the land is
var _detail := FastNoiseLite.new()     # small bumps
var _ridges := FastNoiseLite.new()     # mountain ridges
var _region := FastNoiseLite.new()     # which outer biome
var _warp := FastNoiseLite.new()       # wobbles the biome rings


func _init(p_seed_text: String) -> void:
	seed_text = p_seed_text
	seed_number = seed_to_int(p_seed_text)
	_setup(_continent, 0, 1.0 / 420.0, 4)
	_setup(_detail, 1, 1.0 / 40.0, 3)
	_setup(_ridges, 2, 1.0 / 180.0, 4)
	_ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_setup(_region, 3, 1.0 / 260.0, 2)
	_setup(_warp, 4, 1.0 / 150.0, 2)


## Turns any string into a 63-bit number. Uses SHA-256 rather than
## String.hash() so the result can't change between Godot versions.
static func seed_to_int(text: String) -> int:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(text.to_utf8_buffer())
	var digest := ctx.finish()
	var value := 0
	for i in 8:
		value = (value << 8) | digest[i]
	return value & 0x7FFFFFFFFFFFFFFF


## A random, readable seed for a new world, like "amber-fjord-4821".
static func random_seed() -> String:
	var words := ["amber", "ash", "birch", "cold", "deep", "elder", "fjord", "frost", "grey",
		"iron", "misty", "moss", "north", "oak", "raven", "rune", "salt", "stone", "storm", "wolf"]
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return "%s-%s-%04d" % [words[rng.randi() % words.size()], words[rng.randi() % words.size()],
		rng.randi() % 10000]


static func biome_name(biome: Biome) -> String:
	return BIOME_NAMES[biome]


## Height of the ground at (x, z), in meters above sea level.
func height_at(x: float, z: float) -> float:
	var land := _land(x, z)
	var h := land * 24.0 + _detail.get_noise_2d(x, z) * 1.5
	# Mountains rise out of the highest land.
	var mountain := smoothstep(0.35, 0.75, land)
	h += mountain * (18.0 + (_ridges.get_noise_2d(x, z) * 0.5 + 0.5) * 55.0)
	# Swamps sit just above the water and are nearly flat.
	var swamp := _swamp_weight(x, z) * (1.0 - mountain)
	h = lerpf(h, 0.6 + _detail.get_noise_2d(x, z) * 0.5, swamp * smoothstep(0.0, 0.1, land))
	return h


## Which biome (x, z) is in.
func biome_at(x: float, z: float) -> Biome:
	return biome_for(x, z, height_at(x, z))


## Same as biome_at() for when the height at (x, z) is already known.
func biome_for(x: float, z: float, h: float) -> Biome:
	if h < SEA_LEVEL + 0.3:
		return Biome.OCEAN
	if h > 32.0:
		return Biome.MOUNTAINS
	var dist := _ring_distance(x, z)
	if dist < MEADOWS_RADIUS * 1.2:
		return Biome.MEADOWS
	if _swamp_weight(x, z) > 0.5:
		return Biome.SWAMP
	if dist > SIZE * 0.34 and _region.get_noise_2d(x, z) > -0.15:
		return Biome.PLAINS
	return Biome.BLACK_FOREST


func color_at(x: float, z: float) -> Color:
	return BIOME_COLORS[biome_at(x, z)]


## A spot on land near the center for a player to stand on. Same answer for
## the same angle, so spawns spread out without bunching up.
func spawn_point(angle: float, radius: float = 4.0) -> Vector3:
	var x := cos(angle) * radius
	var z := sin(angle) * radius
	return Vector3(x, height_at(x, z), z)


## -1 (deep ocean) to 1 (highest land). Guarantees an island: always land in
## the middle and always sea at the edge.
func _land(x: float, z: float) -> float:
	var dist := Vector2(x, z).length() / (SIZE * 0.5)
	var land := _continent.get_noise_2d(x, z) * 0.9 + 0.32
	# Lift the middle so the spawn meadows never flood.
	land += 0.35 * (1.0 - smoothstep(0.0, MEADOWS_RADIUS / (SIZE * 0.5), dist))
	# Keep the middle gentle: no mountains in the Meadows.
	var middle := 1.0 - smoothstep(MEADOWS_RADIUS / (SIZE * 0.5), 0.45, dist)
	land = lerpf(land, clampf(land, 0.05, 0.25), middle)
	# Sink everything toward the edge into the ocean.
	land -= smoothstep(0.78, 1.0, dist) * 1.4
	return land


## Distance from the center with some wobble, so biome rings aren't circles.
func _ring_distance(x: float, z: float) -> float:
	return Vector2(x, z).length() + _warp.get_noise_2d(x, z) * 60.0


## 0 to 1: how swampy (x, z) is. Swamps only form outside the Meadows.
func _swamp_weight(x: float, z: float) -> float:
	var outside := smoothstep(MEADOWS_RADIUS * 1.2, MEADOWS_RADIUS * 1.6, _ring_distance(x, z))
	var inner := 1.0 - smoothstep(SIZE * 0.36, SIZE * 0.42, _ring_distance(x, z))
	return smoothstep(0.2, 0.35, -_region.get_noise_2d(x, z)) * outside * inner


func _setup(noise: FastNoiseLite, offset: int, frequency: float, octaves: int) -> void:
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	# FastNoiseLite takes a 32-bit seed; give each layer its own.
	noise.seed = int((seed_number >> (offset * 6)) & 0x7FFFFFFF) ^ (offset * 7919)
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
