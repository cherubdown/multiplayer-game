extends RefCounted
## Every kind of item. Inventories and chests store items by id with a count;
## everything else about an item (its name, what it's for, how many fit in one
## slot, its icon and how it looks lying on the ground) comes from here.
##
## Icons are SVG drawn in code, so they load on a fresh checkout without the
## editor having imported anything.

const IDS: Array[String] = ["wood", "stone", "flint", "berries"]

const INFO := {
	"wood": {
		"name": "Wood",
		"description": "Logs from the forest. The building block of walls, floors and campfires.",
		"max_stack": 50,
		"color": Color(0.55, 0.36, 0.2),
		"shape": "log",
	},
	"stone": {
		"name": "Stone",
		"description": "Sturdy rock. Used for hearths, foundations and heavier tools.",
		"max_stack": 50,
		"color": Color(0.55, 0.55, 0.58),
		"shape": "rock",
	},
	"flint": {
		"name": "Flint",
		"description": "A sharp-edged stone. Knapped into the edges of your first axes and spears.",
		"max_stack": 50,
		"color": Color(0.25, 0.27, 0.32),
		"shape": "shard",
	},
	"berries": {
		"name": "Raspberries",
		"description": "Sweet wild berries. Eat them to keep your strength up.",
		"max_stack": 50,
		"color": Color(0.85, 0.1, 0.25),
		"shape": "berries",
	},
}


## 64x64 SVG icons, keyed by item id.
const ICONS := {
	"wood": """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
		<g transform="rotate(-30 32 32)">
			<rect x="8" y="22" width="44" height="20" rx="4" fill="#7a4a22" stroke="#3b220e" stroke-width="2"/>
			<path d="M14 28 H40 M18 36 H46" stroke="#5a3415" stroke-width="2"/>
			<ellipse cx="50" cy="32" rx="7" ry="10" fill="#d9a865" stroke="#3b220e" stroke-width="2"/>
			<ellipse cx="50" cy="32" rx="3" ry="5" fill="none" stroke="#a87436" stroke-width="1.5"/>
		</g>
	</svg>""",
	"stone": """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
		<path d="M10 44 L16 24 L30 14 L46 18 L56 34 L50 50 L28 54 Z" fill="#8c8c92" stroke="#3c3c42" stroke-width="2.5" stroke-linejoin="round"/>
		<path d="M18 26 L30 18 L42 21" fill="none" stroke="#c4c4ca" stroke-width="3" stroke-linecap="round"/>
		<path d="M30 54 L34 36 L56 34" fill="none" stroke="#5e5e64" stroke-width="2"/>
	</svg>""",
	"flint": """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
		<path d="M14 50 L24 12 L44 8 L52 28 L36 56 Z" fill="#3a3f4a" stroke="#14161b" stroke-width="2.5" stroke-linejoin="round"/>
		<path d="M24 12 L32 30 L44 8 M32 30 L36 56 M32 30 L52 28" fill="none" stroke="#5b6372" stroke-width="2"/>
		<path d="M26 16 L30 26" stroke="#aeb6c6" stroke-width="2.5" stroke-linecap="round"/>
	</svg>""",
	"berries": """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
		<path d="M32 18 C26 6 14 8 12 14 C20 14 26 16 32 18 Z" fill="#3f8f3a" stroke="#1f4d1c" stroke-width="2"/>
		<path d="M32 18 C38 8 50 10 52 16 C44 16 38 17 32 18 Z" fill="#4fa548" stroke="#1f4d1c" stroke-width="2"/>
		<circle cx="22" cy="38" r="11" fill="#d01c3c" stroke="#6e0c1e" stroke-width="2"/>
		<circle cx="42" cy="36" r="11" fill="#e0284a" stroke="#6e0c1e" stroke-width="2"/>
		<circle cx="32" cy="50" r="10" fill="#c41634" stroke="#6e0c1e" stroke-width="2"/>
		<circle cx="18" cy="34" r="2.5" fill="#ff8fa3"/>
		<circle cx="38" cy="32" r="2.5" fill="#ff8fa3"/>
		<circle cx="28" cy="46" r="2.5" fill="#ff8fa3"/>
	</svg>""",
}

static var _icon_cache := {}


static func is_valid(item: String) -> bool:
	return INFO.has(item)


static func display_name(item: String) -> String:
	return INFO[item]["name"] if INFO.has(item) else item


static func max_stack(item: String) -> int:
	return INFO[item]["max_stack"] if INFO.has(item) else 1


static func color(item: String) -> Color:
	return INFO[item]["color"] if INFO.has(item) else Color.MAGENTA


## What the item is for, for tooltips.
static func description(item: String) -> String:
	return INFO[item]["description"] if INFO.has(item) else ""


## The item's icon, or null if it has none (or SVG support is missing).
static func icon(item: String) -> Texture2D:
	if _icon_cache.has(item):
		return _icon_cache[item]
	var texture: Texture2D = null
	if ICONS.has(item):
		var image := Image.new()
		if image.load_svg_from_string(ICONS[item]) == OK:
			texture = ImageTexture.create_from_image(image)
	_icon_cache[item] = texture
	return texture


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
