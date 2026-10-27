extends Node
## Autoload for logging in and picking a character.
##
## The server (host or dedicated) owns the accounts in an AccountStore. After
## connecting, a client registers or logs in, manages its characters, then asks
## to enter the world with one of them. The server only spawns a player for a
## peer once that peer has entered the world.
##
## Requests go to peer 1 and answers come back to the asking peer. Every RPC is
## call_local so the host, which is peer 1 itself, uses the same path.

## Client side: the server answered a register or login request.
signal login_finished(ok: bool, message: String)
## Client side: the character list changed, with an error message if a
## request failed.
signal characters_changed(characters: Array, message: String)
## Client side: the server put this client in the world, or took it out.
signal entered_world(character_name: String)
signal left_world
## Every peer: the characters currently in the world, keyed by peer id.
signal roster_changed(roster: Dictionary)
## Client side: about to ask the server to leave the world. The local player
## stops syncing its input so none arrives after the server despawns it.
signal leaving_world

## Client side: the server sent this client's inventory (Inventory slots).
signal inventory_changed(slots: Array)
## Client side: the server answered a craft request; message is "" if it
## worked, else why not.
signal craft_finished(recipe_id: String, message: String)
## Client side: the recipes this client's character knows (ids, in order),
## and which of them it has only just discovered, to announce.
signal recipes_changed(recipe_ids: Array, new_ids: Array)
## Client side: the item this client's character holds changed ("" for none).
signal held_changed(item: String)
## Client side: what this client's character wears changed (slot -> item, see
## scripts/equipment.gd).
signal equipment_changed(worn: Dictionary)
## Client side: the tools on this client's hotbar changed (see
## scripts/hotbar.gd).
signal hotbar_changed(slots: Array)

## Every peer: the world seed is known (or changed). The world is generated
## from it; see scripts/world_gen.gd.
signal world_seed_changed(seed_text: String)

## Server side: spawn or despawn this peer's player.
signal player_entered(peer_id: int, character_name: String, race: String)
signal player_left(peer_id: int)
## Server side: a player dropped a stack on the ground, for the world to spawn
## next to them.
signal item_dropped(peer_id: int, item: String, count: int)

# Preloaded rather than a class_name so it resolves on a fresh checkout that
# hasn't been imported in the editor (no global class cache yet).
const AccountStore := preload("res://scripts/account_store.gd")
const Races := preload("res://scripts/races.gd")
const WorldGen := preload("res://scripts/world_gen.gd")
const Inventory := preload("res://scripts/inventory.gd")
const Items := preload("res://scripts/items.gd")
const Recipes := preload("res://scripts/recipes.gd")
const Equipment := preload("res://scripts/equipment.gd")
const Hotbar := preload("res://scripts/hotbar.gd")
const MAX_FAILED_LOGINS := 5
## Slots in every character's inventory.
const INVENTORY_SLOTS := 20

## Client side state.
var username := ""
var characters: Array = []
var character_name := ""
var roster := {}
## The slots of this client's inventory, [] when not in the world.
var inventory: Array = []
## The ids of the recipes this client's character knows (see
## scripts/recipes.gd), [] when not in the world.
var recipes: Array = []
## The item this client's character holds in its hand, "" for none.
var held_item := ""
## What this client's character wears, slot -> item (see
## scripts/equipment.gd), {} when not in the world.
var equipment := {}
## The tools on this client's hotbar, an item id or "" per slot (see
## scripts/hotbar.gd), [] when not in the world.
var hotbar: Array = []
## Every peer: the seed of the world being played, "" until the server says.
var world_seed := ""

## Server side state.
var _store: AccountStore
var _usernames := {}          # peer id -> logged in username (lowercase)
var _in_world := {}           # peer id -> character name
var _races := {}              # peer id -> race of the character in the world
var _sexes := {}              # peer id -> sex of the character in the world
var _inventories := {}        # peer id -> Inventory of the character in the world
var _discovered := {}         # peer id -> items the character has ever had (item -> true)
var _saved_spots := {}        # peer id -> where the character last left the world (see AccountStore.load_position())
var _saved_health := {}       # peer id -> the character's health when it last left the world, -1 for full
var _bodies := {}             # peer id -> the character's player node in the world
var _held := {}               # peer id -> the tool the character holds, if any
var _equipment := {}          # peer id -> Equipment the character wears
var _hotbars := {}            # peer id -> the character's Hotbar
var _failed_logins := {}      # peer id -> count


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func is_logged_in() -> bool:
	return username != ""


## Server side: every peer currently in the world, keyed by peer id.
func players_in_world() -> Dictionary:
	return _in_world.duplicate()


## Server side: the race of a peer's character in the world.
func race_of(peer: int) -> String:
	return _races.get(peer, Races.DEFAULT)


## Server side: the sex of a peer's character in the world.
func sex_of(peer: int) -> String:
	return _sexes.get(peer, Races.DEFAULT_SEX)


## Server side: the inventory of a peer's character in the world, or null.
## Call inventory_updated() after changing it.
func inventory_of(peer: int) -> Inventory:
	return _inventories.get(peer)


## Server side: saves a peer's inventory and sends it to them. Anything in it
## for the first time is discovered, and if that unlocks recipes the peer is
## told so they can announce them.
func inventory_updated(peer: int) -> void:
	var inv: Inventory = _inventories.get(peer)
	if inv == null:
		return
	_accounts().save_inventory(_usernames[peer], _in_world[peer], inv.to_array())
	var unlocked := _discover(peer)
	if not unlocked.is_empty():
		for id in unlocked:
			print("Peer %d (%s) discovered the %s recipe" % [peer, _in_world[peer], Items.display_name(Recipes.find(id)["result"])])
		_set_recipes.rpc_id(peer, Recipes.unlocked(_discovered[peer]), unlocked)
	_set_inventory.rpc_id(peer, inv.to_array())
	# A tool that's been dropped or put away can't stay in the hand.
	if held_of(peer) != "" and inv.count_of(held_of(peer)) == 0:
		_set_held_of(peer, "")


## Server side: what a peer's character wears, or null. Call
## equipment_updated() after changing it.
func equipment_of(peer: int) -> Equipment:
	return _equipment.get(peer)


## Server side: saves what a peer's character wears and sends it to them.
## Clients count on the inventory coming straight after (see UiSounds), so
## call inventory_updated() next even if it didn't change.
func equipment_updated(peer: int) -> void:
	var gear: Equipment = _equipment.get(peer)
	if gear == null:
		return
	_accounts().save_equipment(_usernames[peer], _in_world[peer], gear.to_dict())
	_set_equipment.rpc_id(peer, gear.to_dict())


## Server side: a peer's character's hotbar, or null.
func hotbar_of(peer: int) -> Hotbar:
	return _hotbars.get(peer)


## Server side: the items a peer's character has discovered (item -> true).
func discovered_of(peer: int) -> Dictionary:
	return _discovered.get(peer, {})


## Server side: the tool a peer's character holds, or "".
func held_of(peer: int) -> String:
	return _held.get(peer, "")


## Server side: the player node of a peer's character in the world, or null.
func body_of(peer: int) -> Node3D:
	var body = _bodies.get(peer)
	return body if is_instance_valid(body) else null


## Server side: where a peer's character stood and faced when it last left the
## world, as { "position": Vector3, "yaw": float }, or {} to use the spawn.
func saved_spot_of(peer: int) -> Dictionary:
	return _saved_spots.get(peer, {})


## Server side: a peer's character's health when it last left the world, or
## -1 to start at full health.
func saved_health_of(peer: int) -> int:
	return _saved_health.get(peer, -1)


## Server side: the world calls this with each player it spawns, so where the
## player stands can be saved when they leave (and every so often in between).
func set_player_body(peer: int, body: Node3D) -> void:
	_bodies[peer] = body


## Server side: saves where every player in the world is standing (and their
## health), in case the server stops without them leaving first.
func save_positions() -> void:
	for peer in _in_world:
		_save_position(peer)


## Server side: the database that also holds the world's chests.
func accounts() -> AccountStore:
	return _accounts()


## Forgets everything, on both sides. Called when leaving a game.
func reset() -> void:
	# A host leaving its own game: save where everyone was first.
	save_positions()
	username = ""
	characters = []
	character_name = ""
	roster = {}
	inventory = []
	recipes = []
	world_seed = ""
	_usernames.clear()
	_in_world.clear()
	_races.clear()
	_sexes.clear()
	_inventories.clear()
	_discovered.clear()
	_saved_spots.clear()
	_saved_health.clear()
	_bodies.clear()
	_failed_logins.clear()
	_held.clear()
	_equipment.clear()
	_hotbars.clear()
	held_item = ""
	equipment = {}
	hotbar = []


# --- Client API -------------------------------------------------------------

func register(p_username: String, password: String) -> void:
	_request_register.rpc_id(1, p_username, password)


func login(p_username: String, password: String) -> void:
	_request_login.rpc_id(1, p_username, password)


func logout() -> void:
	_request_logout.rpc_id(1)
	username = ""
	characters = []
	character_name = ""


func create_character(p_name: String, race: String = Races.DEFAULT, sex: String = Races.DEFAULT_SEX) -> void:
	_request_create_character.rpc_id(1, p_name, race, sex)


func delete_character(p_name: String) -> void:
	_request_delete_character.rpc_id(1, p_name)


func enter_world(p_name: String) -> void:
	_request_enter_world.rpc_id(1, p_name)


## Moves the stack in inventory slot `from` to slot `to` (merging or swapping),
## or with `split` just half of it (see Inventory.split_slot()).
func move_item(from: int, to: int, split := false) -> void:
	_request_move_item.rpc_id(1, from, to, split)


## Drops the stack in inventory slot `slot` on the ground.
func drop_item(slot: int) -> void:
	_request_drop_item.rpc_id(1, slot)


## Crafts one of a recipe (see scripts/recipes.gd) from what's in the
## inventory. The answer comes back as craft_finished.
func craft(recipe_id: String) -> void:
	_request_craft.rpc_id(1, recipe_id)


## Holds a tool from the inventory in the character's hand, or puts it away
## with "".
func hold(item: String) -> void:
	_request_hold.rpc_id(1, item)


## Wears the item in inventory slot `from` in equipment slot `slot` (see
## scripts/equipment.gd), putting what was worn there back in its place.
func equip(from: int, slot: String) -> void:
	_request_equip.rpc_id(1, from, slot)


## Takes off what's worn in equipment slot `slot`, into inventory slot `to`
## (-1 for wherever it fits).
func unequip(slot: String, to: int = -1) -> void:
	_request_unequip.rpc_id(1, slot, to)


## Moves what's worn in one equipment slot to another, such as between the
## ring slots.
func move_equipped(from: String, to: String) -> void:
	_request_move_equipped.rpc_id(1, from, to)


## Drops what's worn in equipment slot `slot` on the ground.
func drop_equipped(slot: String) -> void:
	_request_drop_equipped.rpc_id(1, slot)


## Puts a tool from the inventory in hotbar slot `index`, or empties it with
## "". A tool already on the hotbar swaps places with what was there.
func set_hotbar_slot(index: int, item: String) -> void:
	_request_set_hotbar_slot.rpc_id(1, index, item)


## Swaps two hotbar slots.
func swap_hotbar(from: int, to: int) -> void:
	_request_swap_hotbar.rpc_id(1, from, to)


## Holds the tool in hotbar slot `index`, or puts it away if it's already in
## hand. Returns false if there's nothing there to hold (an empty slot, or a
## tool that isn't in the inventory just now).
func use_hotbar(index: int) -> bool:
	var item: String = hotbar[index] if index >= 0 and index < hotbar.size() else ""
	if item == "":
		return false
	if item == held_item:
		hold("")
		return true
	for slot in inventory:
		if slot != null and slot["item"] == item:
			hold(item)
			return true
	return false


## Back to character select without disconnecting.
func leave_world() -> void:
	if character_name == "":
		return
	leaving_world.emit()
	# Give input packets already on the wire time to land first.
	await get_tree().create_timer(0.25).timeout
	_request_leave_world.rpc_id(1)


# --- Server side requests ---------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func _request_register(p_username, password) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if _usernames.has(peer) or not (p_username is String and password is String):
		return
	var err := _accounts().register(p_username, password)
	if err != "":
		_login_result.rpc_id(peer, false, err, "", [])
		return
	print("Account %s created by peer %d" % [p_username, peer])
	_finish_login(peer, p_username)


@rpc("any_peer", "call_local", "reliable")
func _request_login(p_username, password) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if _usernames.has(peer) or not (p_username is String and password is String):
		return
	var err := _accounts().verify(p_username, password)
	if err == "" and p_username.to_lower() in _usernames.values():
		err = "That account is already logged in."
	if err != "":
		_failed_logins[peer] = _failed_logins.get(peer, 0) + 1
		_login_result.rpc_id(peer, false, err, "", [])
		if _failed_logins[peer] >= MAX_FAILED_LOGINS and peer != 1:
			print("Disconnecting peer %d after %d failed logins" % [peer, MAX_FAILED_LOGINS])
			multiplayer.multiplayer_peer.disconnect_peer(peer)
		return
	_finish_login(peer, p_username)


@rpc("any_peer", "call_local", "reliable")
func _request_logout() -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	_remove_from_world(peer)
	_usernames.erase(peer)


@rpc("any_peer", "call_local", "reliable")
func _request_create_character(p_name, race, sex) -> void:
	var peer := _logged_in_sender()
	if peer == 0 or not p_name is String or not race is String or not sex is String:
		return
	var account: String = _usernames[peer]
	var err := _accounts().create_character(account, p_name, race, sex)
	_characters_result.rpc_id(peer, _accounts().list_characters(account), err)


@rpc("any_peer", "call_local", "reliable")
func _request_delete_character(p_name) -> void:
	var peer := _logged_in_sender()
	if peer == 0 or not p_name is String:
		return
	var account: String = _usernames[peer]
	var err := ""
	if _in_world.get(peer, "").to_lower() == p_name.to_lower():
		err = "Leave the world before deleting that character."
	else:
		err = _accounts().delete_character(account, p_name)
	_characters_result.rpc_id(peer, _accounts().list_characters(account), err)


@rpc("any_peer", "call_local", "reliable")
func _request_enter_world(p_name) -> void:
	var peer := _logged_in_sender()
	if peer == 0 or not p_name is String or _in_world.has(peer):
		return
	var account: String = _usernames[peer]
	if not _accounts().has_character(account, p_name):
		_characters_result.rpc_id(peer, _accounts().list_characters(account), "No character called %s." % p_name)
		return
	var race := Races.DEFAULT
	var sex := Races.DEFAULT_SEX
	for character in _accounts().list_characters(account):
		if str(character["name"]).to_lower() == p_name.to_lower():
			p_name = character["name"]
			race = character["race"]
			sex = character["sex"]
	_in_world[peer] = p_name
	_races[peer] = race
	_sexes[peer] = sex
	var inv := Inventory.new(INVENTORY_SLOTS)
	inv.load_array(_accounts().load_inventory(account, p_name))
	_inventories[peer] = inv
	_discovered[peer] = _accounts().load_discoveries(account, p_name)
	# Quietly: whatever a character carries is already known to them, such as
	# one saved before recipes had to be discovered.
	_discover(peer)
	_saved_spots[peer] = _accounts().load_position(account, p_name)
	_saved_health[peer] = _accounts().load_health(account, p_name)
	var gear := Equipment.new()
	gear.load_dict(_accounts().load_equipment(account, p_name))
	_equipment[peer] = gear
	var bar := Hotbar.new()
	bar.load_array(_accounts().load_hotbar(account, p_name))
	_hotbars[peer] = bar
	print("Peer %d entered the world as %s the %s" % [peer, p_name, Races.describe(race, sex)])
	_entered_world.rpc_id(peer, p_name)
	_set_recipes.rpc_id(peer, Recipes.unlocked(_discovered[peer]), [])
	_set_equipment.rpc_id(peer, gear.to_dict())
	_set_hotbar.rpc_id(peer, bar.to_array())
	_set_inventory.rpc_id(peer, inv.to_array())
	player_entered.emit(peer, p_name, race)
	_broadcast_roster()


@rpc("any_peer", "call_local", "reliable")
func _request_move_item(from, to, split) -> void:
	var peer := _logged_in_sender()
	var inv := inventory_of(peer)
	if inv == null or not (from is int and to is int and split is bool):
		return
	if inv.split_slot(from, inv, to) if split else inv.move_slot(from, inv, to):
		inventory_updated(peer)


@rpc("any_peer", "call_local", "reliable")
func _request_drop_item(slot) -> void:
	var peer := _logged_in_sender()
	var inv := inventory_of(peer)
	if inv == null or not slot is int:
		return
	var stack := inv.take(slot)
	if stack.is_empty():
		return
	inventory_updated(peer)
	item_dropped.emit(peer, stack["item"], stack["count"])


@rpc("any_peer", "call_local", "reliable")
func _request_craft(recipe_id) -> void:
	var peer := _logged_in_sender()
	var inv := inventory_of(peer)
	if inv == null or not recipe_id is String:
		return
	var err := Recipes.craft(recipe_id, inv, discovered_of(peer))
	if err == "":
		var made: String = Recipes.find(recipe_id)["result"]
		print("Peer %d (%s) crafted a %s" % [peer, _in_world[peer], Items.display_name(made)])
		inventory_updated(peer)
		# Empty handed: take the new tool straight into the hand.
		if held_of(peer) == "" and Items.is_tool_item(made):
			_set_held_of(peer, made)
	_craft_result.rpc_id(peer, recipe_id, err)


@rpc("any_peer", "call_local", "reliable")
func _request_hold(item) -> void:
	var peer := _logged_in_sender()
	var inv := inventory_of(peer)
	if inv == null or not item is String:
		return
	if item == "" or (Items.is_tool_item(item) and inv.count_of(item) > 0):
		_set_held_of(peer, item)


@rpc("any_peer", "call_local", "reliable")
func _request_set_hotbar_slot(index, item) -> void:
	var peer := _logged_in_sender()
	var inv := inventory_of(peer)
	var bar := hotbar_of(peer)
	if inv == null or bar == null or not Hotbar.has_slot(index) or not item is String:
		return
	# Only a tool the character has can go on; any slot can be emptied.
	if item != "" and inv.count_of(item) == 0:
		return
	if bar.set_slot(index, item):
		_hotbar_updated(peer)


@rpc("any_peer", "call_local", "reliable")
func _request_swap_hotbar(from, to) -> void:
	var peer := _logged_in_sender()
	var bar := hotbar_of(peer)
	if bar != null and from is int and to is int and bar.swap(from, to):
		_hotbar_updated(peer)


@rpc("any_peer", "call_local", "reliable")
func _request_equip(from, slot) -> void:
	var peer := _logged_in_sender()
	var inv := inventory_of(peer)
	var gear := equipment_of(peer)
	if inv == null or gear == null or not from is int or not Equipment.is_slot(slot):
		return
	if gear.equip(inv, from, slot):
		# Equipment first, so the inventory arriving after doesn't look like
		# something was dropped.
		equipment_updated(peer)
		inventory_updated(peer)


@rpc("any_peer", "call_local", "reliable")
func _request_unequip(slot, to) -> void:
	var peer := _logged_in_sender()
	var inv := inventory_of(peer)
	var gear := equipment_of(peer)
	if inv == null or gear == null or not Equipment.is_slot(slot) or not to is int:
		return
	if gear.unequip(slot, inv, to):
		equipment_updated(peer)
		inventory_updated(peer)


@rpc("any_peer", "call_local", "reliable")
func _request_move_equipped(from, to) -> void:
	var peer := _logged_in_sender()
	var gear := equipment_of(peer)
	if gear != null and Equipment.is_slot(from) and Equipment.is_slot(to) and gear.move(from, to):
		equipment_updated(peer)
		inventory_updated(peer)


@rpc("any_peer", "call_local", "reliable")
func _request_drop_equipped(slot) -> void:
	var peer := _logged_in_sender()
	var gear := equipment_of(peer)
	if gear == null or not Equipment.is_slot(slot):
		return
	var item := gear.take(slot)
	if item == "":
		return
	equipment_updated(peer)
	inventory_updated(peer)
	item_dropped.emit(peer, item, 1)


@rpc("any_peer", "call_local", "reliable")
func _request_leave_world() -> void:
	var peer := _logged_in_sender()
	if peer == 0 or not _in_world.has(peer):
		return
	_remove_from_world(peer)
	_left_world.rpc_id(peer)


# --- Client side answers ----------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _set_world_seed(seed_text: String) -> void:
	world_seed = seed_text
	world_seed_changed.emit(seed_text)


@rpc("authority", "call_local", "reliable")
func _login_result(ok: bool, message: String, p_username: String, p_characters: Array) -> void:
	if ok:
		username = p_username
		characters = p_characters
	login_finished.emit(ok, message)
	if ok:
		characters_changed.emit(characters, "")


@rpc("authority", "call_local", "reliable")
func _characters_result(p_characters: Array, message: String) -> void:
	characters = p_characters
	characters_changed.emit(characters, message)


@rpc("authority", "call_local", "reliable")
func _entered_world(p_name: String) -> void:
	character_name = p_name
	entered_world.emit(p_name)


@rpc("authority", "call_local", "reliable")
func _set_inventory(slots: Array) -> void:
	inventory = slots
	inventory_changed.emit(slots)


@rpc("authority", "call_local", "reliable")
func _set_recipes(recipe_ids: Array, new_ids: Array) -> void:
	recipes = recipe_ids
	recipes_changed.emit(recipe_ids, new_ids)


@rpc("authority", "call_local", "reliable")
func _craft_result(recipe_id: String, message: String) -> void:
	craft_finished.emit(recipe_id, message)


@rpc("authority", "call_local", "reliable")
func _set_held(item: String) -> void:
	held_item = item
	held_changed.emit(item)


@rpc("authority", "call_local", "reliable")
func _set_equipment(worn: Dictionary) -> void:
	equipment = worn
	equipment_changed.emit(worn)


@rpc("authority", "call_local", "reliable")
func _set_hotbar(slots: Array) -> void:
	hotbar = slots
	hotbar_changed.emit(slots)


@rpc("authority", "call_local", "reliable")
func _left_world() -> void:
	character_name = ""
	inventory = []
	equipment = {}
	hotbar = []
	recipes = []
	held_item = ""
	left_world.emit()


@rpc("authority", "call_local", "reliable")
func _set_roster(p_roster: Dictionary) -> void:
	roster = p_roster
	roster_changed.emit(roster)


# --- Server helpers ---------------------------------------------------------

## Server side: opens the accounts database, creating it if it's new, so
## problems show up when the server starts rather than at the first login.
func open_accounts() -> void:
	_accounts()


## Server side: picks the world seed. A new server creates its world from
## `requested` (from --seed), or a random seed if that is "", and saves it.
## After that the saved seed always wins, so the world never changes under
## existing players.
func setup_world(requested: String) -> void:
	requested = requested.strip_edges()
	var saved := _accounts().world_seed()
	var chosen := saved
	if saved != "":
		if requested != "" and requested != saved:
			push_warning("Ignoring --seed=\"%s\": this server's world already exists with seed \"%s\". Delete %s to start a new world." \
				% [requested, saved, ProjectSettings.globalize_path(_accounts().path)])
		print("Loaded the world with seed \"%s\"" % saved)
	else:
		chosen = requested if requested != "" else WorldGen.random_seed()
		if _accounts().set_world_seed(chosen):
			print("Created a new world with seed \"%s\"%s" % [chosen, "" if requested != "" else " (random; pass --seed=<text> to pick one)"])
		else:
			push_warning("Could not save the world seed \"%s\"; the next start will make a different world." % chosen)
	_set_world_seed(chosen)


func _accounts() -> AccountStore:
	if _store == null:
		# --accounts=<path> keeps accounts somewhere else, e.g. for tests.
		var path := AccountStore.DEFAULT_PATH
		for arg in OS.get_cmdline_args() + OS.get_cmdline_user_args():
			if arg.begins_with("--accounts="):
				path = arg.get_slice("=", 1)
		_store = AccountStore.new(path)
		if _store.is_open():
			print("Accounts are saved in %s" % ProjectSettings.globalize_path(_store.path))
	return _store


## The id of the peer that sent the current RPC if it is logged in, else 0.
func _logged_in_sender() -> int:
	if not multiplayer.is_server():
		return 0
	var peer := multiplayer.get_remote_sender_id()
	return peer if _usernames.has(peer) else 0


func _finish_login(peer: int, p_username: String) -> void:
	var key := p_username.to_lower()
	_usernames[peer] = key
	_failed_logins.erase(peer)
	print("Peer %d logged in as %s" % [peer, _accounts().display_name(key)])
	_login_result.rpc_id(peer, true, "", _accounts().display_name(key), _accounts().list_characters(key))
	_set_roster.rpc_id(peer, _in_world)


func _remove_from_world(peer: int) -> void:
	if not _in_world.has(peer):
		return
	print("Peer %d (%s) left the world" % [peer, _in_world[peer]])
	# Saved on every change already; this catches anything missed.
	if _inventories.has(peer):
		_accounts().save_inventory(_usernames[peer], _in_world[peer], _inventories[peer].to_array())
	if _equipment.has(peer):
		_accounts().save_equipment(_usernames[peer], _in_world[peer], _equipment[peer].to_dict())
	if _hotbars.has(peer):
		_accounts().save_hotbar(_usernames[peer], _in_world[peer], _hotbars[peer].to_array())
	_save_position(peer)
	_in_world.erase(peer)
	_races.erase(peer)
	_sexes.erase(peer)
	_inventories.erase(peer)
	_discovered.erase(peer)
	_saved_spots.erase(peer)
	_saved_health.erase(peer)
	_bodies.erase(peer)
	_held.erase(peer)
	_equipment.erase(peer)
	_hotbars.erase(peer)
	player_left.emit(peer)
	_broadcast_roster()


## Server side: marks everything in a peer's inventory as discovered, saving
## any that are new. Returns the ids of the recipes that unlocked.
func _discover(peer: int) -> Array:
	var inv: Inventory = _inventories[peer]
	var known: Dictionary = _discovered[peer]
	var before := Recipes.unlocked(known)
	var found := false
	for slot in inv.slots:
		if slot != null and not known.has(slot["item"]):
			known[slot["item"]] = true
			found = true
	if not found:
		return []
	_accounts().save_discoveries(_usernames[peer], _in_world[peer], known)
	return Recipes.unlocked(known).filter(func(id: String) -> bool: return not id in before)


## Server side: puts `item` in a peer's hand ("" for nothing), on their
## player for everyone to see, and tells them. A tool taken in hand that isn't
## on the hotbar yet goes in its first empty slot.
func _set_held_of(peer: int, item: String) -> void:
	if item == "":
		_held.erase(peer)
	else:
		_held[peer] = item
		var bar := hotbar_of(peer)
		if bar != null and bar.add(item):
			_hotbar_updated(peer)
	var body := body_of(peer)
	if body != null:
		body.held_item = item
	_set_held.rpc_id(peer, item)


## Server side: saves a peer's hotbar and sends it to them.
func _hotbar_updated(peer: int) -> void:
	var bar := hotbar_of(peer)
	if bar == null:
		return
	_accounts().save_hotbar(_usernames[peer], _in_world[peer], bar.to_array())
	_set_hotbar.rpc_id(peer, bar.to_array())


func _save_position(peer: int) -> void:
	var body = _bodies.get(peer)  # Untyped: it may have been freed already.
	if not is_instance_valid(body) or not body.is_inside_tree() or not _in_world.has(peer):
		return
	_accounts().save_position(_usernames[peer], _in_world[peer], body.global_position, body.global_rotation.y)
	_accounts().save_health(_usernames[peer], _in_world[peer], body.health)


func _broadcast_roster() -> void:
	# Only peers that have logged in hear about who is playing. Skip any that
	# are already gone, such as a player who just disconnected from the world.
	var connected := multiplayer.get_peers()
	for peer in _usernames:
		if peer == multiplayer.get_unique_id() or peer in connected:
			_set_roster.rpc_id(peer, _in_world)


func _on_peer_connected(peer: int) -> void:
	# Clients build the world while they log in.
	if multiplayer.is_server() and world_seed != "":
		_set_world_seed.rpc_id(peer, world_seed)


func _on_peer_disconnected(peer: int) -> void:
	if not multiplayer.is_server():
		return
	_remove_from_world(peer)
	_usernames.erase(peer)
	_failed_logins.erase(peer)
