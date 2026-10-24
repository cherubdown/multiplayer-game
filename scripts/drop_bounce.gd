extends RefCounted
## How something dropped out of a tree, a rock or a frog moves as it lands
## (see scripts/item_pickup.gd): it flies out of where it came from in an arc,
## then bounces a few times, lower each time, squashing as it hits the ground.

## Seconds the flight out takes, and how high it arcs above the straight line.
const FLIGHT_SECONDS := 0.55
const FLIGHT_ARC := 1.1
## The bounces after it lands, in meters high, each lower than the last.
const BOUNCES: Array[float] = [0.32, 0.12, 0.04]
## How fast it falls back from a bounce, in m/s², a bit snappier than real.
const BOUNCE_GRAVITY := 22.0
## Seconds the flare of its sparkle takes to die down after it first lands.
const SHINE_SECONDS := 1.4


## Seconds from being dropped until it lies still.
static func drop_seconds() -> float:
	var total := FLIGHT_SECONDS
	for height in BOUNCES:
		total += _bounce_seconds(height)
	return total


static func _bounce_seconds(height: float) -> float:
	return 2.0 * sqrt(2.0 * height / BOUNCE_GRAVITY)


## Where the item is `t` seconds after being dropped, from where it lies, and
## how squashed it is (1 for not at all): out of `from` in an arc, then the
## bounces. Null once it lies still.
static func pose(t: float, from: Vector3) -> Variant:
	if t < FLIGHT_SECONDS:
		var f := t / FLIGHT_SECONDS
		return [from * (1.0 - f) + Vector3.UP * FLIGHT_ARC * 4.0 * f * (1.0 - f), 1.0]
	var since_landing := t - FLIGHT_SECONDS
	for height in BOUNCES:
		var seconds := _bounce_seconds(height)
		if since_landing < seconds:
			var f := since_landing / seconds
			# Squashed flat as it hits the ground, springing back as it rises.
			var squash := 1.0 - 0.35 * height / BOUNCES[0] * maxf(1.0 - since_landing / 0.12, 0.0)
			return [Vector3.UP * height * 4.0 * f * (1.0 - f), squash]
		since_landing -= seconds
	return null
