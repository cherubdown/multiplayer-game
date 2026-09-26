extends RefCounted
## The playable races. A race is picked when a character is created, saved
## with the character on the server, and decides which model everyone sees.
##
## The models are from KayKit's Adventurers pack (CC0, see
## assets/characters/kaykit_adventurers/LICENSE.txt). Each race shows a subset
## of its model's parts and is scaled to its own build; CharacterModel adds the
## elf ears and dwarf beard on top.

const DEFAULT := "human"
const IDS: Array[String] = ["human", "elf", "dwarf"]

const MODEL_DIR := "res://assets/characters/kaykit_adventurers/"

const INFO := {
	"human": {
		"name": "Human",
		"description": "Sturdy and adaptable, at home in any land.",
		"model": MODEL_DIR + "Knight.glb",
		# Parts of the model to keep. Everything else attached to a bone
		# (spare weapons, shields, hats) is hidden.
		"parts": ["Knight_Helmet", "Knight_Cape", "1H_Sword", "Round_Shield"],
		"scale": Vector3(0.8, 0.8, 0.8),
	},
	"elf": {
		"name": "Elf",
		"description": "Tall, swift and keen-eyed children of the old forests.",
		"model": MODEL_DIR + "Rogue.glb",
		"parts": ["Rogue_Cape", "Knife", "Knife_Offhand"],
		"scale": Vector3(0.72, 0.87, 0.72),
		"ears": true,
	},
	"dwarf": {
		"name": "Dwarf",
		"description": "Short, broad and stubborn as the mountains they mine.",
		"model": MODEL_DIR + "Barbarian.glb",
		"parts": ["Barbarian_Cape", "1H_Axe", "Barbarian_Round_Shield"],
		"scale": Vector3(0.9, 0.64, 0.9),
		"beard": Color(0.52, 0.49, 0.46),
	},
}


static func is_valid(id: Variant) -> bool:
	return id is String and id in IDS


static func display_name(id: String) -> String:
	return INFO.get(id, INFO[DEFAULT])["name"]
