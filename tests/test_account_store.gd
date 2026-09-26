extends SceneTree
## Checks AccountStore without a network. Run from the project folder:
##   godot --headless --path . -s tests/test_account_store.gd
## Exits non-zero if any check fails.

const AccountStore := preload("res://scripts/account_store.gd")
const PATH := "user://test_accounts.db"
const LEGACY_PATH := "user://test_accounts.json"

var _failures := 0


func _init() -> void:
	_remove_test_files()

	var store := AccountStore.new(PATH)
	_check(store.is_open(), "creates the database on first use")
	_check(FileAccess.file_exists(PATH), "database file exists")
	_check(store.register("ab", "secret1") != "", "rejects a short username")
	_check(store.register("chris", "123") != "", "rejects a short password")
	_check(store.register("Chris", "secret1") == "", "registers an account")
	_check(store.register("CHRIS", "other12") != "", "usernames are case-insensitive")
	_check(store.verify("chris", "secret1") == "", "accepts the right password")
	_check(store.verify("chris", "wrong12") != "", "rejects a wrong password")
	_check(store.verify("nobody", "secret1") != "", "rejects an unknown account")
	_check(store.display_name("chris") == "Chris", "keeps the typed username")

	_check(store.create_character("chris", "Ragnar") == "", "creates a character")
	_check(store.create_character("chris", "ragnar") != "", "rejects a duplicate name")
	_check(store.create_character("chris", "1x") != "", "rejects an invalid name")
	for character_name in ["Astrid", "Bjorn", "Freya", "Leif"]:
		store.create_character("chris", character_name)
	_check(store.create_character("chris", "Sigrid") != "", "caps characters per account")
	_check(store.delete_character("chris", "Bjorn") == "", "deletes a character")
	_check(not store.has_character("chris", "Bjorn"), "deleted character is gone")

	_check(store.register("x' OR 1=1 --", "secret1") != "", "rejects SQL in a username")
	_check(store.create_character("chris", "O'Brien") == "", "stores a name with a quote")
	_check(store.delete_character("chris", "O'Brien") == "", "deletes a name with a quote")
	store.close()

	var reloaded := AccountStore.new(PATH)
	_check(reloaded.verify("chris", "secret1") == "", "password survives a reload")
	var names := reloaded.list_characters("chris").map(func(c: Dictionary) -> String: return c["name"])
	_check(names == ["Ragnar", "Astrid", "Freya", "Leif"], "characters survive a reload in order")
	reloaded.close()
	var raw := FileAccess.get_file_as_bytes(PATH).hex_encode()
	_check(raw.contains("Ragnar".to_utf8_buffer().hex_encode()), "database was written")
	_check(not raw.contains("secret1".to_utf8_buffer().hex_encode()), "password is not stored in plain text")

	_check_legacy_import()

	_remove_test_files()
	print("AccountStore: %s" % ("all checks passed" if _failures == 0 else "%d checks failed" % _failures))
	quit(1 if _failures > 0 else 0)


## Accounts from an accounts.json written by older builds move into a new
## database, and their old 10000-iteration hashes are upgraded at login.
func _check_legacy_import() -> void:
	_remove_test_files()
	var crypto := Crypto.new()
	var salt := crypto.generate_random_bytes(16)
	var hasher := AccountStore.new("user://test_hasher.db")
	var hash := hasher._hash_password("oldpass1", salt, 10000)
	hasher.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_hasher.db"))
	var legacy := {
		"olga": {
			"name": "Olga", "salt": Marshalls.raw_to_base64(salt), "hash": Marshalls.raw_to_base64(hash),
			"iterations": 10000, "characters": [{ "name": "Sven", "created": 1 }],
		},
	}
	var file := FileAccess.open(LEGACY_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()

	var store := AccountStore.new(PATH)
	_check(store.verify("olga", "oldpass1") == "", "imports a JSON account")
	_check(store.verify("olga", "wrongpass") != "", "imported account rejects a wrong password")
	_check(store.has_character("olga", "sven"), "imports JSON characters")
	_check(not FileAccess.file_exists(LEGACY_PATH), "renames the imported JSON file")
	store.close()
	var reloaded := AccountStore.new(PATH)
	_check(int(reloaded._account("olga")["iterations"]) == AccountStore.PBKDF2_ITERATIONS, "upgrades the old hash at login")
	_check(reloaded.verify("olga", "oldpass1") == "", "upgraded hash still accepts the password")
	reloaded.close()


func _remove_test_files() -> void:
	for p in [PATH, LEGACY_PATH, LEGACY_PATH + ".imported"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: %s" % what)
