extends Node
## The sounds of the screens (autoload "UiSounds"): a click for every button
## in every menu, and the local player's inventory cues, heard from what the
## server sends back (see Session): a pop for something picked up, a thud for
## something dropped, a tick for a stack moved, hammering for a craft, a chime
## for a recipe discovered, a ring for taking a tool in hand or putting gear
## on (and a softer one taking it off) and a buzz when the server says no.
##
## It also makes every sound effect (see scripts/sounds.gd) on a background
## thread as the game starts, so none of them stutters the first time it
## plays. Does nothing where sounds don't play (a dedicated server, headless).

const Sounds := preload("res://scripts/sounds.gd")

## The local inventory last sent by the server, as item -> count, or null
## when not in the world (so the first inventory on entering is quiet).
var _counts = null
var _slots: Array = []
## What the local character wore when the server last said, or null when not
## in the world.
var _worn = null
## Whether gear went on or came off since the last inventory, which the server
## always sends straight after.
var _gear_changed := false
var _warm_task := -1
var _quitting := false


func _ready() -> void:
	if not Sounds.enabled():
		return
	Sounds.bus_name()
	Sounds.warming = true
	_warm_task = WorkerThreadPool.add_task(_warm_up, false, "Making sound effects")
	get_tree().node_added.connect(_watch)
	for button in get_tree().root.find_children("*", "BaseButton", true, false):
		_watch(button)
	Session.login_finished.connect(func(ok: bool, _message: String) -> void:
		if not ok:
			Sounds.play_ui(self, "error"))
	Session.characters_changed.connect(func(_characters: Array, message: String) -> void:
		if message != "":
			Sounds.play_ui(self, "error"))
	Session.entered_world.connect(func(_name: String) -> void:
		_counts = null
		_worn = null)
	Session.left_world.connect(func() -> void:
		_counts = null
		_worn = null)
	Session.equipment_changed.connect(_on_equipment_changed)
	Session.inventory_changed.connect(_on_inventory_changed)
	Session.craft_finished.connect(func(_recipe: String, message: String) -> void:
		Sounds.play_ui(self, "craft" if message == "" else "error"))
	Session.recipes_changed.connect(func(_ids: Array, new_ids: Array) -> void:
		if not new_ids.is_empty():
			Sounds.play_ui(self, "discover"))
	Session.held_changed.connect(func(item: String) -> void:
		Sounds.play_ui(self, "equip" if item != "" else "unequip"))


func _exit_tree() -> void:
	_quitting = true
	if _warm_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_warm_task)
		_warm_task = -1


func _watch(node: Node) -> void:
	if node is BaseButton and not node.pressed.is_connected(_on_button_pressed):
		node.pressed.connect(_on_button_pressed)


func _on_button_pressed() -> void:
	Sounds.play_ui(self, "click")


## Gear going on rings, coming off is softer. The inventory the server sends
## straight after is the same item moving, so it stays quiet.
func _on_equipment_changed(worn: Dictionary) -> void:
	var before = _worn
	_worn = worn.duplicate()
	if before == null:
		return
	if worn.size() >= before.size() and worn != before:
		Sounds.play_ui(self, "equip")
	elif worn.size() < before.size():
		Sounds.play_ui(self, "unequip")
	_gear_changed = true


## Item -> how many the local character has, carried or worn.
func _counted(slots: Array) -> Dictionary:
	var counts := {}
	for slot in slots:
		if slot != null:
			counts[slot["item"]] = counts.get(slot["item"], 0) + slot["count"]
	if _worn != null:
		for item in _worn.values():
			counts[item] = counts.get(item, 0) + 1
	return counts


## Works out what just happened to the inventory from how it changed.
## Crafting both takes and gives, and has its own sound (craft_finished).
func _on_inventory_changed(slots: Array) -> void:
	var counts := _counted(slots)
	var before = _counts
	var moved := slots != _slots
	_counts = counts
	_slots = slots.duplicate(true)
	# Gear going on or coming off already made its sound.
	var quiet := _gear_changed
	_gear_changed = false
	if before == null or quiet:
		return
	var gained := false
	var lost := false
	for item in counts:
		gained = gained or counts[item] > before.get(item, 0)
	for item in before:
		lost = lost or before[item] > counts.get(item, 0)
	if _chest_open():
		if gained or lost or moved:
			Sounds.play_ui(self, "move")
	elif gained and not lost:
		Sounds.play_ui(self, "pickup")
	elif lost and not gained:
		Sounds.play_ui(self, "drop", 3.0)
	elif moved and not gained:
		Sounds.play_ui(self, "move")


func _chest_open() -> bool:
	for node in get_tree().get_nodes_in_group("interactable"):
		if node.get("is_open") == true:
			return true
	return false


## On a worker thread: makes every sound, handing each to the main thread
## as it's done.
func _warm_up() -> void:
	for sound: String in Sounds.SOUNDS:
		if _quitting:
			return
		var made := []
		for variant in Sounds.SOUNDS[sound]["variants"]:
			made.append(Sounds.to_stream(Sounds.render(sound, variant)))
		_keep.call_deferred(sound, made)
	_done_warming.call_deferred()


func _keep(sound: String, made: Array) -> void:
	if not Sounds._streams.has(sound):
		Sounds._streams[sound] = made


func _done_warming() -> void:
	Sounds.warming = false
