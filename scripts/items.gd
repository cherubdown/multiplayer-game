extends RefCounted
## Every kind of item. Inventories and chests store items by id with a count;
## everything else about an item (its name, what it's for, how many fit in one
## slot, its icon and how it looks lying on the ground) comes from here.
##
## Icons are SVG drawn in code, so they load on a fresh checkout without the
## editor having imported anything.
##
## An item with a "tool" entry can be held in the hand and swung with the left
## mouse button. Its "type" says what it's good for (see scripts/harvestables.gd
## for what each type can break). A tool with an "attack" in its "tool" entry
## is a weapon: that's how much health one hit takes off an enemy (see
## scripts/big_frog.gd).
##
## An item with an "equip" entry can be worn in that slot of the character
## sheet (see scripts/equipment.gd): "helm", "amulet", "shoulders", "chest",
## "hands", "belt", "leggings", "boots", "ring" (either ring slot) or
## "off_hand".

const IDS: Array[String] = ["wood", "stone", "flint", "berries", "blueberries", "mushroom", "apple",
	"frog_meat", "frog_bile", "wood_sword", "stone_axe", "stone_pickaxe", "stone_sword",
	"leather_cap", "bone_amulet", "hide_pauldrons", "leather_tunic", "leather_gloves", "rope_belt",
	"hide_leggings", "leather_boots", "copper_ring", "wooden_buckler"]

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
	"frog_meat": {
		"name": "Frog Meat",
		"description": "A slab of rubbery meat from a Big Frog. Every frog you kill drops some.",
		"max_stack": 50,
		"color": Color(0.86, 0.5, 0.46),
		"shape": "meat",
	},
	"frog_bile": {
		"name": "Frog Bile",
		"description": "A vial of a Big Frog's poisonous bile. Only some frogs have any worth taking.",
		"max_stack": 50,
		"color": Color(0.55, 0.85, 0.2),
		"shape": "vial",
	},
	"wood_sword": {
		"name": "Wood Sword",
		"description": "A blade whittled from a single length of wood. Hold it and click to fight. Hits for 10.",
		"max_stack": 1,
		"color": Color(0.66, 0.46, 0.26),
		"shape": "tool",
		"tool": { "type": "sword", "damage": 1, "attack": 10 },
	},
	"stone_axe": {
		"name": "Stone Axe",
		"description": "A stone head lashed to a wooden haft. Hold it and click to chop down trees for wood.",
		"max_stack": 1,
		"color": Color(0.55, 0.55, 0.58),
		"shape": "tool",
		"tool": { "type": "axe", "damage": 1 },
	},
	"stone_pickaxe": {
		"name": "Stone Pickaxe",
		"description": "A pointed stone head on a wooden haft. Hold it and click to break big rocks for stone.",
		"max_stack": 1,
		"color": Color(0.55, 0.55, 0.58),
		"shape": "tool",
		"tool": { "type": "pickaxe", "damage": 1 },
	},
	"stone_sword": {
		"name": "Stone Sword",
		"description": "A ground stone blade on a wooden grip. Crude, but it has an edge. Hits for 15.",
		"max_stack": 1,
		"color": Color(0.55, 0.55, 0.58),
		"shape": "tool",
		"tool": { "type": "sword", "damage": 2, "attack": 15 },
	},
	"leather_cap": {
		"name": "Leather Cap",
		"description": "A snug cap of stitched leather. Wear it on your head.",
		"max_stack": 1,
		"color": Color(0.55, 0.36, 0.2),
		"shape": "armor",
		"equip": "helm",
	},
	"bone_amulet": {
		"name": "Bone Amulet",
		"description": "A carved bone charm on a leather cord. Wear it around your neck.",
		"max_stack": 1,
		"color": Color(0.9, 0.86, 0.74),
		"shape": "armor",
		"equip": "amulet",
	},
	"hide_pauldrons": {
		"name": "Hide Pauldrons",
		"description": "Thick hide shoulder guards. Wear them on your shoulders.",
		"max_stack": 1,
		"color": Color(0.48, 0.34, 0.24),
		"shape": "armor",
		"equip": "shoulders",
	},
	"leather_tunic": {
		"name": "Leather Tunic",
		"description": "A sleeveless tunic of tanned leather. Wear it on your chest.",
		"max_stack": 1,
		"color": Color(0.6, 0.4, 0.22),
		"shape": "armor",
		"equip": "chest",
	},
	"leather_gloves": {
		"name": "Leather Gloves",
		"description": "Work gloves of soft leather. Wear them on your hands.",
		"max_stack": 1,
		"color": Color(0.5, 0.32, 0.18),
		"shape": "armor",
		"equip": "hands",
	},
	"rope_belt": {
		"name": "Rope Belt",
		"description": "A length of braided rope, knotted at the waist. Wear it as a belt.",
		"max_stack": 1,
		"color": Color(0.76, 0.64, 0.42),
		"shape": "armor",
		"equip": "belt",
	},
	"hide_leggings": {
		"name": "Hide Leggings",
		"description": "Hard-wearing hide trousers. Wear them on your legs.",
		"max_stack": 1,
		"color": Color(0.42, 0.3, 0.2),
		"shape": "armor",
		"equip": "leggings",
	},
	"leather_boots": {
		"name": "Leather Boots",
		"description": "Sturdy boots with thick soles. Wear them on your feet.",
		"max_stack": 1,
		"color": Color(0.36, 0.24, 0.14),
		"shape": "armor",
		"equip": "boots",
	},
	"copper_ring": {
		"name": "Copper Ring",
		"description": "A plain band of beaten copper. Wear it on either hand; you have room for two.",
		"max_stack": 1,
		"color": Color(0.85, 0.5, 0.25),
		"shape": "armor",
		"equip": "ring",
	},
	"wooden_buckler": {
		"name": "Wooden Buckler",
		"description": "A small round shield of planks. Wear it in your off hand.",
		"max_stack": 1,
		"color": Color(0.6, 0.42, 0.24),
		"shape": "armor",
		"equip": "off_hand",
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
	"frog_meat": """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
		<path d="M10 34 C8 20 24 10 40 14 C54 17 60 30 54 42 C48 54 28 56 18 50 C12 46 11 40 10 34 Z" fill="#d9786e" stroke="#6e2a24" stroke-width="2.5" stroke-linejoin="round"/>
		<path d="M18 32 C24 24 36 22 46 26 M20 42 C28 36 40 36 50 38" fill="none" stroke="#f2b2a6" stroke-width="3" stroke-linecap="round"/>
		<ellipse cx="44" cy="44" rx="6" ry="4" fill="#f4ead6" stroke="#8a7a5e" stroke-width="2"/>
	</svg>""",
	"frog_bile": """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
		<rect x="26" y="6" width="12" height="8" rx="2" fill="#8a5a2e" stroke="#3b220e" stroke-width="2"/>
		<path d="M27 14 H37 V24 C48 28 52 38 48 48 C44 58 20 58 16 48 C12 38 16 28 27 24 Z" fill="#cfe9e2" stroke="#2c4a44" stroke-width="2.5" stroke-linejoin="round"/>
		<path d="M17 40 C24 36 40 36 47 40 C48 46 46 52 40 54 C32 57 22 56 19 50 C17 47 16 44 17 40 Z" fill="#8fd630" stroke="#3f6a12" stroke-width="2"/>
		<circle cx="28" cy="46" r="2.5" fill="#d8ff8a"/>
		<circle cx="38" cy="49" r="1.8" fill="#d8ff8a"/>
		<path d="M22 30 C21 34 20 36 20 38" stroke="#ffffff" stroke-width="2.5" stroke-linecap="round"/>
	</svg>""",
	"wood_sword": """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
		<path d="M28 34 L52 8 L58 6 L56 12 L30 36 Z" fill="#b07a44" stroke="#4a2c12" stroke-width="2.5" stroke-linejoin="round"/>
		<path d="M32 32 L54 9" stroke="#e0b47a" stroke-width="2" stroke-linecap="round"/>
		<path d="M20 30 L34 44" stroke="#3b220e" stroke-width="7" stroke-linecap="round"/>
		<path d="M20 30 L34 44" stroke="#7a4a22" stroke-width="4" stroke-linecap="round"/>
		<path d="M28 40 L12 56" stroke="#3b220e" stroke-width="8" stroke-linecap="round"/>
		<path d="M28 40 L12 56" stroke="#9a6430" stroke-width="5" stroke-linecap="round"/>
	</svg>""",
	"stone_axe": """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
		<path d="M18 58 L44 12" stroke="#3b220e" stroke-width="8" stroke-linecap="round"/>
		<path d="M18 58 L44 12" stroke="#9a6430" stroke-width="5" stroke-linecap="round"/>
		<path d="M36 16 C40 6 54 6 60 14 C58 24 50 30 42 30 Z" fill="#8c8c92" stroke="#3c3c42" stroke-width="2.5" stroke-linejoin="round"/>
		<path d="M48 9 C54 10 58 13 59 16" fill="none" stroke="#d4d4da" stroke-width="2.5" stroke-linecap="round"/>
		<path d="M36 22 L46 26" stroke="#c9a46a" stroke-width="3"/>
	</svg>""",
	"stone_pickaxe": """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
		<path d="M20 58 L42 14" stroke="#3b220e" stroke-width="8" stroke-linecap="round"/>
		<path d="M20 58 L42 14" stroke="#9a6430" stroke-width="5" stroke-linecap="round"/>
		<path d="M8 18 C20 6 44 4 58 14 C46 12 36 14 42 18 C36 16 24 16 8 18 Z" fill="#8c8c92" stroke="#3c3c42" stroke-width="2.5" stroke-linejoin="round"/>
		<path d="M14 15 C24 9 38 8 50 10" fill="none" stroke="#d4d4da" stroke-width="2" stroke-linecap="round"/>
	</svg>""",
	"stone_sword": """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
		<path d="M28 34 L52 8 L58 6 L56 12 L30 36 Z" fill="#8c8c92" stroke="#3c3c42" stroke-width="2.5" stroke-linejoin="round"/>
		<path d="M32 32 L54 9" stroke="#d4d4da" stroke-width="2" stroke-linecap="round"/>
		<path d="M20 30 L34 44" stroke="#3b220e" stroke-width="7" stroke-linecap="round"/>
		<path d="M20 30 L34 44" stroke="#7a4a22" stroke-width="4" stroke-linecap="round"/>
		<path d="M28 40 L12 56" stroke="#3b220e" stroke-width="8" stroke-linecap="round"/>
		<path d="M28 40 L12 56" stroke="#9a6430" stroke-width="5" stroke-linecap="round"/>
	</svg>""",
	"leather_cap": """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
		<path d="M10 42 C10 18 54 18 54 42 Z" fill="#8a5a2e" stroke="#3b220e" stroke-width="2.5" stroke-linejoin="round"/>
		<path d="M6 42 H58 V48 H6 Z" fill="#6e4422" stroke="#3b220e" stroke-width="2.5" stroke-linejoin="round"/>
		<path d="M32 22 V42 M20 28 C24 26 28 25 32 25" fill="none" stroke="#c99560" stroke-width="2" stroke-linecap="round"/>
	</svg>""",
	"bone_amulet": """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
		<path d="M12 8 C14 30 24 38 32 40 C40 38 50 30 52 8" fill="none" stroke="#5a3415" stroke-width="3" stroke-linecap="round"/>
		<path d="M32 38 L42 50 L32 60 L22 50 Z" fill="#ece3cc" stroke="#7d6f55" stroke-width="2.5" stroke-linejoin="round"/>
		<circle cx="32" cy="50" r="3" fill="#7d6f55"/>
	</svg>""",
	"hide_pauldrons": """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
		<path d="M4 40 C4 22 16 14 28 18 L26 44 C18 40 10 42 4 40 Z" fill="#7a5638" stroke="#3b220e" stroke-width="2.5" stroke-linejoin="round"/>
		<path d="M60 40 C60 22 48 14 36 18 L38 44 C46 40 54 42 60 40 Z" fill="#7a5638" stroke="#3b220e" stroke-width="2.5" stroke-linejoin="round"/>
		<path d="M10 30 C14 24 20 22 24 23 M54 30 C50 24 44 22 40 23" fill="none" stroke="#b8875e" stroke-width="2.5" stroke-linecap="round"/>
	</svg>""",
	"leather_tunic": """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
		<path d="M20 8 L28 12 H36 L44 8 L56 18 L50 28 L46 26 V58 H18 V26 L14 28 L8 18 Z" fill="#9a6430" stroke="#3b220e" stroke-width="2.5" stroke-linejoin="round"/>
		<path d="M28 12 L32 22 L36 12 M32 22 V40" fill="none" stroke="#5a3415" stroke-width="2"/>
		<path d="M18 46 H46" stroke="#5a3415" stroke-width="3"/>
	</svg>""",
	"leather_gloves": """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
		<path d="M18 58 V44 L10 30 C8 26 12 24 15 27 L20 34 V12 C20 8 26 8 26 12 V28 V8 C26 4 32 4 32 8 V28 V10 C32 6 38 6 38 10 V30 V16 C38 12 44 12 44 16 V44 L40 58 Z" fill="#87552c" stroke="#3b220e" stroke-width="2.5" stroke-linejoin="round"/>
		<path d="M18 50 H40" stroke="#5a3415" stroke-width="3"/>
	</svg>""",
	"rope_belt": """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
		<path d="M4 30 C20 24 44 24 60 30 V38 C44 32 20 32 4 38 Z" fill="#c2a46a" stroke="#6b5530" stroke-width="2" stroke-linejoin="round"/>
		<path d="M10 28 L14 36 M20 27 L24 34 M30 26 L34 33 M40 27 L44 34 M50 28 L54 35" stroke="#8a7144" stroke-width="2"/>
		<circle cx="32" cy="34" r="6" fill="#c2a46a" stroke="#6b5530" stroke-width="2"/>
		<path d="M30 38 L26 56 M34 38 L40 54" stroke="#c2a46a" stroke-width="4" stroke-linecap="round"/>
	</svg>""",
	"hide_leggings": """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
		<path d="M16 6 H48 L52 58 H36 L32 24 L28 58 H12 Z" fill="#6b4a32" stroke="#2e1d10" stroke-width="2.5" stroke-linejoin="round"/>
		<path d="M16 12 H48" stroke="#3b2414" stroke-width="3"/>
		<path d="M20 30 L18 50 M44 30 L46 50" stroke="#9c7552" stroke-width="2" stroke-linecap="round"/>
	</svg>""",
	"leather_boots": """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
		<path d="M14 6 H32 V40 L52 44 C58 46 58 56 54 56 H12 Z" fill="#5c3a1e" stroke="#26170a" stroke-width="2.5" stroke-linejoin="round"/>
		<path d="M12 52 H56" stroke="#26170a" stroke-width="4"/>
		<path d="M14 14 H32 M18 22 L28 22 M18 30 L28 30" stroke="#a87436" stroke-width="2"/>
	</svg>""",
	"copper_ring": """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
		<ellipse cx="32" cy="36" rx="20" ry="18" fill="none" stroke="#7a3f14" stroke-width="10"/>
		<ellipse cx="32" cy="36" rx="20" ry="18" fill="none" stroke="#d98a45" stroke-width="6"/>
		<path d="M18 26 C22 22 26 20 30 20" fill="none" stroke="#ffd0a0" stroke-width="2.5" stroke-linecap="round"/>
	</svg>""",
	"wooden_buckler": """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
		<circle cx="32" cy="32" r="26" fill="#9a6a38" stroke="#3b220e" stroke-width="3"/>
		<path d="M20 9 V55 M32 6 V58 M44 9 V55" stroke="#6e4422" stroke-width="2"/>
		<circle cx="32" cy="32" r="26" fill="none" stroke="#8c8c92" stroke-width="3"/>
		<circle cx="32" cy="32" r="7" fill="#8c8c92" stroke="#3c3c42" stroke-width="2"/>
	</svg>""",
}

static var _icon_cache := {}
static var _tool_meshes := {}


static func is_valid(item: String) -> bool:
	return INFO.has(item)


static func display_name(item: String) -> String:
	return INFO[item]["name"] if INFO.has(item) else item


static func max_stack(item: String) -> int:
	return INFO[item]["max_stack"] if INFO.has(item) else 1


static func color(item: String) -> Color:
	return INFO[item]["color"] if INFO.has(item) else Color.MAGENTA


## What kind of tool the item is ("axe", "pickaxe", "sword"), or "" if it
## isn't one.
static func tool_type(item: String) -> String:
	return INFO[item]["tool"]["type"] if INFO.has(item) and INFO[item].has("tool") else ""


static func is_tool_item(item: String) -> bool:
	return tool_type(item) != ""


## How much one swing of the tool does.
static func tool_damage(item: String) -> int:
	return INFO[item]["tool"]["damage"] if is_tool_item(item) else 0


## How much health one hit with the item takes off an enemy, 0 if it isn't a
## weapon.
static func attack_damage(item: String) -> int:
	return INFO[item]["tool"].get("attack", 0) if is_tool_item(item) else 0


static func is_weapon(item: String) -> bool:
	return attack_damage(item) > 0


## Which kind of equipment slot the item is worn in (see
## scripts/equipment.gd), or "" if it can't be worn.
static func equip_slot(item: String) -> String:
	return INFO[item].get("equip", "") if INFO.has(item) else ""


static func is_wearable(item: String) -> bool:
	return equip_slot(item) != ""


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
	if shape == "tool":
		return tool_mesh(item)
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
		"meat":
			var slab := SphereMesh.new()
			slab.radius = 0.18
			slab.height = 0.16
			result = slab
		"armor":
			var piece := BoxMesh.new()
			piece.size = Vector3(0.3, 0.1, 0.3)
			result = piece
		"vial":
			var vial := CapsuleMesh.new()
			vial.radius = 0.07
			vial.height = 0.26
			result = vial
		_:
			var box := BoxMesh.new()
			box.size = Vector3.ONE * 0.3
			result = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color(item)
	result.material = mat
	return result


## A tool as it's held: the grip at the origin and the haft along +Y, with the
## head at the far end. Lying on the ground it's the same mesh.
static func tool_mesh(item: String) -> Mesh:
	if _tool_meshes.has(item):
		return _tool_meshes[item]
	var wood := Color(0.5, 0.32, 0.16)
	var stone := Color(0.52, 0.52, 0.55)
	var mesh := ArrayMesh.new()
	match tool_type(item):
		"axe":
			_tool_part(mesh, _box(Vector3(0.05, 0.75, 0.05)), Vector3(0.0, 0.3, 0.0), wood)
			_tool_part(mesh, _prism(Vector3(0.22, 0.2, 0.06)), Vector3(0.0, 0.56, -0.1), stone,
				Vector3(0.0, 0.0, deg_to_rad(90.0)))
		"pickaxe":
			_tool_part(mesh, _box(Vector3(0.05, 0.75, 0.05)), Vector3(0.0, 0.3, 0.0), wood)
			_tool_part(mesh, _prism(Vector3(0.08, 0.24, 0.06)), Vector3(0.0, 0.6, -0.14), stone,
				Vector3(deg_to_rad(-90.0), 0.0, 0.0))
			_tool_part(mesh, _prism(Vector3(0.08, 0.18, 0.06)), Vector3(0.0, 0.6, 0.11), stone,
				Vector3(deg_to_rad(90.0), 0.0, 0.0))
		_:
			_tool_part(mesh, _box(Vector3(0.05, 0.2, 0.05)), Vector3(0.0, 0.0, 0.0), wood)
			_tool_part(mesh, _box(Vector3(0.22, 0.04, 0.06)), Vector3(0.0, 0.12, 0.0), wood.darkened(0.3))
			# The blade is the item's own color: stone, or wood for a wood sword.
			_tool_part(mesh, _prism(Vector3(0.08, 0.7, 0.02)), Vector3(0.0, 0.49, 0.0), color(item))
	_tool_meshes[item] = mesh
	return mesh


static func _tool_part(mesh: ArrayMesh, part: PrimitiveMesh, at: Vector3, part_color: Color, turn := Vector3.ZERO) -> void:
	var st := SurfaceTool.new()
	st.append_from(part, 0, Transform3D(Basis.from_euler(turn), at))
	st.commit(mesh)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = part_color
	mat.roughness = 0.85
	mesh.surface_set_material(mesh.get_surface_count() - 1, mat)


static func _box(size: Vector3) -> BoxMesh:
	var box := BoxMesh.new()
	box.size = size
	return box


static func _prism(size: Vector3) -> PrismMesh:
	var prism := PrismMesh.new()
	prism.size = size
	return prism
