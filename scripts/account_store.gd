extends RefCounted
## Server-side accounts and characters, saved as JSON (user://accounts.json by
## default). Passwords are stored as salted PBKDF2-HMAC-SHA256 hashes.
##
## Every method that can fail returns "" on success or a message the player
## can read.

const DEFAULT_PATH := "user://accounts.json"
const MAX_CHARACTERS := 5
const PBKDF2_ITERATIONS := 10000
const SALT_BYTES := 16

var path: String
## Keyed by lowercased username:
## { name, salt, hash, iterations, characters: [{ name, created }] }
var _accounts := {}
var _crypto := Crypto.new()
var _username_regex := RegEx.create_from_string("^[A-Za-z0-9_]{3,16}$")
var _character_regex := RegEx.create_from_string("^[A-Za-z][A-Za-z' -]{1,15}$")


func _init(p_path: String = DEFAULT_PATH) -> void:
	path = p_path
	_load()


## Nothing to connect to; the file is read when the store is made.
func open() -> String:
	return ""


func close() -> void:
	pass


## Where the accounts live, for the server log.
func describe() -> String:
	return ProjectSettings.globalize_path(path)


func has_account(username: String) -> bool:
	return _accounts.has(username.to_lower())


## The username as it was typed when the account was created.
func display_name(username: String) -> String:
	var account: Dictionary = _accounts.get(username.to_lower(), {})
	return account.get("name", username)


func register(username: String, password: String) -> String:
	if not _username_regex.search(username):
		return "Usernames are 3 to 16 letters, numbers or underscores."
	if password.length() < 6 or password.length() > 64:
		return "Passwords are 6 to 64 characters."
	if has_account(username):
		return "That username is taken."
	var salt := _crypto.generate_random_bytes(SALT_BYTES)
	_accounts[username.to_lower()] = {
		"name": username,
		"salt": Marshalls.raw_to_base64(salt),
		"hash": Marshalls.raw_to_base64(_hash_password(password, salt, PBKDF2_ITERATIONS)),
		"iterations": PBKDF2_ITERATIONS,
		"characters": [],
	}
	return _save()


func verify(username: String, password: String) -> String:
	var account: Dictionary = _accounts.get(username.to_lower(), {})
	if account.is_empty():
		return "Wrong username or password."
	var salt := Marshalls.base64_to_raw(account["salt"])
	var expected := Marshalls.base64_to_raw(account["hash"])
	var actual := _hash_password(password, salt, int(account["iterations"]))
	if not _constant_time_equals(actual, expected):
		return "Wrong username or password."
	return ""


func list_characters(username: String) -> Array:
	var account: Dictionary = _accounts.get(username.to_lower(), {})
	return account.get("characters", []).duplicate(true)


func has_character(username: String, character_name: String) -> bool:
	return _find_character(username, character_name) >= 0


func create_character(username: String, character_name: String) -> String:
	var account: Dictionary = _accounts.get(username.to_lower(), {})
	if account.is_empty():
		return "Not logged in."
	character_name = character_name.strip_edges()
	if not _character_regex.search(character_name):
		return "Character names are 2 to 16 letters, starting with a letter."
	if has_character(username, character_name):
		return "You already have a character called %s." % character_name
	var characters: Array = account["characters"]
	if characters.size() >= MAX_CHARACTERS:
		return "You can have at most %d characters." % MAX_CHARACTERS
	characters.append({ "name": character_name, "created": int(Time.get_unix_time_from_system()) })
	return _save()


func delete_character(username: String, character_name: String) -> String:
	var index := _find_character(username, character_name)
	if index < 0:
		return "No character called %s." % character_name
	var characters: Array = _accounts[username.to_lower()]["characters"]
	characters.remove_at(index)
	return _save()


func _find_character(username: String, character_name: String) -> int:
	var account: Dictionary = _accounts.get(username.to_lower(), {})
	var characters: Array = account.get("characters", [])
	for i in characters.size():
		if str(characters[i]["name"]).to_lower() == character_name.strip_edges().to_lower():
			return i
	return -1


## PBKDF2-HMAC-SHA256 with a single 32-byte block.
func _hash_password(password: String, salt: PackedByteArray, iterations: int) -> PackedByteArray:
	var key := password.to_utf8_buffer()
	var block := salt.duplicate()
	block.append_array(PackedByteArray([0, 0, 0, 1]))
	var u := _crypto.hmac_digest(HashingContext.HASH_SHA256, key, block)
	var result := u.duplicate()
	for _i in iterations - 1:
		u = _crypto.hmac_digest(HashingContext.HASH_SHA256, key, u)
		for j in result.size():
			result[j] ^= u[j]
	return result


func _constant_time_equals(a: PackedByteArray, b: PackedByteArray) -> bool:
	if a.size() != b.size():
		return false
	var diff := 0
	for i in a.size():
		diff |= a[i] ^ b[i]
	return diff == 0


func _load() -> void:
	if not FileAccess.file_exists(path):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary:
		_accounts = data
	else:
		push_error("Could not read accounts from %s; starting with none." % path)


## Writes to a temporary file first so a crash mid-save can't wipe accounts.
func _save() -> String:
	var tmp_path := path + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not save accounts to %s (%s)" % [tmp_path, error_string(FileAccess.get_open_error())])
		return "The server could not save your account."
	file.store_string(JSON.stringify(_accounts, "\t"))
	file.close()
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp_path), ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("Could not save accounts to %s (%s)" % [path, error_string(err)])
		return "The server could not save your account."
	return ""
