extends RefCounted
## Every kind of item. Inventories and chests store items by id with a count;
## everything else about an item (its name, what it's for, how many fit in one
## slot, its icon and how it looks lying on the ground) comes from here.
##
## Icons are SVG drawn in code, so they load on a fresh checkout without the
## editor having imported anything.

const IDS: Array[String] = ["wood", "stone", "flint", "berries", "blueberries", "mushroom", "apple"]

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
	"blueberries": {
		"name": "Blueberries",
		"description": "Small, dark forest berries. Rarer than raspberries, and just as sweet.",
		"max_stack": 50,
		"color": Color(0.22, 0.28, 0.7),
		"shape": "berries",
	},
	"mushroom": {
		"name": "Mushroom",
		"description": "A plump brown mushroom from the forest floor. Good in a stew.",
		"max_stack": 50,
		"color": Color(0.62, 0.42, 0.24),
		"shape": "mushroom",
	},
	"apple": {
		"name": "Apple",
		"description": "A crisp red apple, picked from one of the island's rare apple trees.",
		"max_stack": 50,
		"color": Color(0.8, 0.12, 0.1),
		"shape": "apple",
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
	"blueberries": """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
		<path d="M32 20 C24 8 12 10 10 16 C18 16 25 18 32 20 Z" fill="#3f8f3a" stroke="#1f4d1c" stroke-width="2"/>
		<circle cx="20" cy="38" r="10" fill="#34449e" stroke="#151c4a" stroke-width="2"/>
		<circle cx="42" cy="34" r="10" fill="#3b4db0" stroke="#151c4a" stroke-width="2"/>
		<circle cx="32" cy="50" r="9" fill="#2e3d8e" stroke="#151c4a" stroke-width="2"/>
		<circle cx="44" cy="52" r="7" fill="#34449e" stroke="#151c4a" stroke-width="2"/>
		<path d="M18 34 l4 0 M40 30 l4 0 M30 46 l4 0" stroke="#9aa6e6" stroke-width="2" stroke-linecap="round"/>
	</svg>""",
	"mushroom": """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
		<path d="M26 34 L24 54 Q32 58 40 54 L38 34 Z" fill="#efe6d2" stroke="#7d6f55" stroke-width="2" stroke-linejoin="round"/>
		<path d="M8 36 C8 14 56 14 56 36 Q32 42 8 36 Z" fill="#9c6634" stroke="#4a2c12" stroke-width="2.5" stroke-linejoin="round"/>
		<path d="M18 26 C22 20 30 18 36 19" fill="none" stroke="#c99560" stroke-width="3" stroke-linecap="round"/>
	</svg>""",
	"apple": """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
		<path d="M32 20 C22 12 8 18 10 34 C12 50 24 58 32 54 C40 58 52 50 54 34 C56 18 42 12 32 20 Z" fill="#d42a1e" stroke="#6b0f08" stroke-width="2.5"/>
		<path d="M32 20 C32 14 34 10 37 7" fill="none" stroke="#5a3415" stroke-width="3" stroke-linecap="round"/>
		<path d="M35 14 C40 8 48 9 50 12 C45 15 40 15 35 14 Z" fill="#4fa548" stroke="#1f4d1c" stroke-width="1.5"/>
		<path d="M18 28 C19 24 22 22 25 22" fill="none" stroke="#ff9a8a" stroke-width="3" stroke-linecap="round"/>
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
		"mushroom":
			var cap := SphereMesh.new()
			cap.radius = 0.15
			cap.height = 0.15
			cap.is_hemisphere = true
			result = cap
		"apple":
			var sphere := SphereMesh.new()
			sphere.radius = 0.12
			sphere.height = 0.22
			result = sphere
		_:
			var box := BoxMesh.new()
			box.size = Vector3.ONE * 0.3
			result = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color(item)
	result.material = mat
	return result
