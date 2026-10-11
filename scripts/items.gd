extends RefCounted
## Every kind of item. Inventories and chests store items by id with a count;
## everything else about an item (its name, how many fit in one slot, how it
## looks lying on the ground) comes from here.

const IDS: Array[String] = ["wood", "stone", "flint", "berries"]

const INFO := {
	"wood": {
		"name": "Wood",
		"max_stack": 50,
		"color": Color(0.55, 0.36, 0.2),
		"shape": "log",
	},
	"stone": {
		"name": "Stone",
		"max_stack": 50,
		"color": Color(0.55, 0.55, 0.58),
		"shape": "rock",
	},
	"flint": {
		"name": "Flint",
		"max_stack": 50,
		"color": Color(0.25, 0.27, 0.32),
		"shape": "shard",
	},
	"berries": {
		"name": "Raspberries",
		"max_stack": 50,
		"color": Color(0.85, 0.1, 0.25),
		"shape": "berries",
	},
}


static func is_valid(item: String) -> bool:
	return INFO.has(item)


static func display_name(item: String) -> String:
	return INFO[item]["name"] if INFO.has(item) else item


static func max_stack(item: String) -> int:
	return INFO[item]["max_stack"] if INFO.has(item) else 1


static func color(item: String) -> Color:
	return INFO[item]["color"] if INFO.has(item) else Color.MAGENTA


## A small mesh for an item lying on the ground, about 0.4 m across.
static func mesh(item: String) -> Mesh:
	var shape: String = INFO[item]["shape"] if INFO.has(item) else ""
	var result: PrimitiveMesh
	match shape:
		"log":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.1
			cylinder.bottom_radius = 0.1
			cylinder.height = 0.5
			result = cylinder
		"rock":
			var sphere := SphereMesh.new()
			sphere.radius = 0.18
			sphere.height = 0.28
			result = sphere
		"shard":
			var prism := PrismMesh.new()
			prism.size = Vector3(0.25, 0.3, 0.1)
			result = prism
		"berries":
			var sphere := SphereMesh.new()
			sphere.radius = 0.1
			sphere.height = 0.2
			result = sphere
		_:
			var box := BoxMesh.new()
			box.size = Vector3.ONE * 0.3
			result = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color(item)
	result.material = mat
	return result
