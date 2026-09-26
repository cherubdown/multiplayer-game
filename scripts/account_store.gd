extends RefCounted
## Server-side accounts and characters, saved in a SQLite database
## (user://accounts.db by default). The database and its tables are created
## the first time the server needs them, so a new server needs no setup.
## Passwords are stored as salted PBKDF2-HMAC-SHA256 hashes.
##
## Every method that can fail returns "" on success or a message the player
## can read.

const Races := preload("res://scripts/races.gd")

const DEFAULT_PATH := "user://accounts.db"
const SQLITE_EXTENSION := "res://addons/godot-sqlite/gdsqlite.gdextension"
const MAX_CHARACTERS := 5
## Hashes made with fewer iterations are upgraded at the next login.
const PBKDF2_ITERATIONS := 100000
const SALT_BYTES := 16
## Bump and add a step to _migrate() when the tables change.
const SCHEMA_VERSION := 2

var path: String
var _db: Object  # SQLite, created through ClassDB (see _open()).
var _crypto := Crypto.new()
var _username_regex := RegEx.create_from_string("^[A-Za-z0-9_]{3,16}$")
var _character_regex := RegEx.create_from_string("^[A-Za-z][A-Za-z' -]{1,15}$")


func _init(p_path: String = DEFAULT_PATH) -> void:
	path = p_path
	_open()


## False if the database could not be opened; every request then fails.
func is_open() -> bool:
	return _db != null


func close() -> void:
	if _db != null:
		_db.close_db()
		_db = null


func has_account(username: String) -> bool:
	return not _account(username).is_empty()


## The username as it was typed when the account was created.
func display_name(username: String) -> String:
	return _account(username).get("name", username)


func register(username: String, password: String) -> String:
	if not _username_regex.search(username):
		return "Usernames are 3 to 16 letters, numbers or underscores."
	if password.length() < 6 or password.length() > 64:
		return "Passwords are 6 to 64 characters."
	if not is_open():
		return "The server could not save your account."
	if has_account(username):
		return "That username is taken."
	var salt := _crypto.generate_random_bytes(SALT_BYTES)
	var ok: bool = _db.query_with_bindings(
		"INSERT INTO accounts (username, name, salt, hash, iterations, created) VALUES (?, ?, ?, ?, ?, ?)",
		[username.to_lower(), username, salt, _hash_password(password, salt, PBKDF2_ITERATIONS),
			PBKDF2_ITERATIONS, _now()])
	return "" if ok else _failed("create account %s" % username)


func verify(username: String, password: String) -> String:
	var account := _account(username)
	if account.is_empty():
		return "Wrong username or password."
	var actual := _hash_password(password, account["salt"], int(account["iterations"]))
	if not _constant_time_equals(actual, account["hash"]):
		return "Wrong username or password."
	if int(account["iterations"]) < PBKDF2_ITERATIONS:
		_rehash(int(account["id"]), password)
	return ""


func list_characters(username: String) -> Array:
	if not is_open():
		return []
	_db.query_with_bindings(
		"SELECT c.name, c.race, c.created FROM characters c JOIN accounts a ON a.id = c.account_id"
		+ " WHERE a.username = ? ORDER BY c.id", [username.to_lower()])
	return _db.query_result.map(func(row: Dictionary) -> Dictionary:
		return { "name": row["name"], "race": row["race"], "created": row["created"] })


func has_character(username: String, character_name: String) -> bool:
	var target := character_name.strip_edges().to_lower()
	return list_characters(username).any(func(c: Dictionary) -> bool: return str(c["name"]).to_lower() == target)


func create_character(username: String, character_name: String, race: String = Races.DEFAULT) -> String:
	var account := _account(username)
	if account.is_empty():
		return "Not logged in."
	if not Races.is_valid(race):
		return "Pick a race for your character."
	character_name = character_name.strip_edges()
	if not _character_regex.search(character_name):
		return "Character names are 2 to 16 letters, starting with a letter."
	if has_character(username, character_name):
		return "You already have a character called %s." % character_name
	if list_characters(username).size() >= MAX_CHARACTERS:
		return "You can have at most %d characters." % MAX_CHARACTERS
	var ok: bool = _db.query_with_bindings(
		"INSERT INTO characters (account_id, name, name_key, race, created) VALUES (?, ?, ?, ?, ?)",
		[account["id"], character_name, character_name.to_lower(), race, _now()])
	return "" if ok else _failed("create character %s" % character_name)


func delete_character(username: String, character_name: String) -> String:
	var account := _account(username)
	if account.is_empty() or not has_character(username, character_name):
		return "No character called %s." % character_name
	var ok: bool = _db.query_with_bindings(
		"DELETE FROM characters WHERE account_id = ? AND name_key = ?",
		[account["id"], character_name.strip_edges().to_lower()])
	return "" if ok else _failed("delete character %s" % character_name)


## The account row for a username, or {} if there is none.
func _account(username: String) -> Dictionary:
	if not is_open():
		return {}
	_db.query_with_bindings("SELECT * FROM accounts WHERE username = ?", [username.to_lower()])
	return _db.query_result[0] if _db.query_result.size() > 0 else {}


func _rehash(account_id: int, password: String) -> void:
	var salt := _crypto.generate_random_bytes(SALT_BYTES)
	_db.query_with_bindings("UPDATE accounts SET salt = ?, hash = ?, iterations = ? WHERE id = ?",
		[salt, _hash_password(password, salt, PBKDF2_ITERATIONS), PBKDF2_ITERATIONS, account_id])


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


func _now() -> int:
	return int(Time.get_unix_time_from_system())


func _failed(what: String) -> String:
	push_error("Could not %s in %s: %s" % [what, path, _db.error_message])
	return "The server could not save your account."


# --- Opening the database ---------------------------------------------------

func _open() -> void:
	# A checkout that was never opened in the editor has no extension list, so
	# Godot doesn't load the SQLite extension on its own. Exports always do.
	if not ClassDB.class_exists("SQLite"):
		GDExtensionManager.load_extension(SQLITE_EXTENSION)
	if not ClassDB.class_exists("SQLite"):
		push_error("The SQLite extension (%s) did not load, so accounts can't be saved." % SQLITE_EXTENSION)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	var db: Object = ClassDB.instantiate("SQLite")
	db.path = path
	db.default_extension = ""
	db.foreign_keys = true
	db.verbosity_level = 0  # Quiet: don't log every query.
	if not db.open_db():
		push_error("Could not open the accounts database %s: %s" % [path, db.error_message])
		return
	_db = db
	if not _migrate():
		close()
		return
	_import_legacy_json()


## Creates or upgrades the tables. user_version is 0 in a new database.
func _migrate() -> bool:
	_db.query("PRAGMA user_version")
	var version := int(_db.query_result[0]["user_version"])
	if version > SCHEMA_VERSION:
		push_error("%s was made by a newer version of the server (schema %d)." % [path, version])
		return false
	if version < 1:
		var ok: bool = _db.query("""
			BEGIN;
			CREATE TABLE accounts (
				id INTEGER PRIMARY KEY,
				username TEXT NOT NULL UNIQUE,  -- lowercased, for lookups
				name TEXT NOT NULL,             -- as typed
				salt BLOB NOT NULL,
				hash BLOB NOT NULL,
				iterations INTEGER NOT NULL,
				created INTEGER NOT NULL
			);
			CREATE TABLE characters (
				id INTEGER PRIMARY KEY,
				account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
				name TEXT NOT NULL,
				name_key TEXT NOT NULL,         -- lowercased
				created INTEGER NOT NULL,
				UNIQUE (account_id, name_key)
			);
			PRAGMA user_version = 1;
			COMMIT;
		""")
		if not ok:
			push_error("Could not create the tables in %s: %s" % [path, _db.error_message])
			_db.query("ROLLBACK")
			return false
		print("Created the accounts database at %s" % ProjectSettings.globalize_path(path))
	if version < 2:
		# Characters made before races existed become humans.
		var ok: bool = _db.query("""
			BEGIN;
			ALTER TABLE characters ADD COLUMN race TEXT NOT NULL DEFAULT '%s';
			PRAGMA user_version = 2;
			COMMIT;
		""" % Races.DEFAULT)
		if not ok:
			push_error("Could not add character races to %s: %s" % [path, _db.error_message])
			_db.query("ROLLBACK")
			return false
	return true


## Older builds saved accounts as JSON next to where the database now goes
## (user://accounts.json). Moves them into a new, empty database, then renames
## the file so it isn't imported twice.
func _import_legacy_json() -> void:
	var legacy_path := path.get_basename() + ".json"
	if not FileAccess.file_exists(legacy_path):
		return
	_db.query("SELECT COUNT(*) AS n FROM accounts")
	if int(_db.query_result[0]["n"]) > 0:
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(legacy_path))
	if not data is Dictionary:
		push_error("Could not read %s to import it." % legacy_path)
		return
	_db.query("BEGIN")
	for key in data:
		var account: Dictionary = data[key]
		_db.query_with_bindings(
			"INSERT INTO accounts (username, name, salt, hash, iterations, created) VALUES (?, ?, ?, ?, ?, ?)",
			[str(key).to_lower(), account["name"], Marshalls.base64_to_raw(account["salt"]),
				Marshalls.base64_to_raw(account["hash"]), int(account["iterations"]), _now()])
		var account_id: int = _db.last_insert_rowid
		for character in account.get("characters", []):
			_db.query_with_bindings(
				"INSERT INTO characters (account_id, name, name_key, created) VALUES (?, ?, ?, ?)",
				[account_id, character["name"], str(character["name"]).to_lower(), int(character["created"])])
	_db.query("COMMIT")
	var legacy := ProjectSettings.globalize_path(legacy_path)
	DirAccess.rename_absolute(legacy, legacy + ".imported")
	print("Imported %d accounts from %s" % [data.size(), legacy])
