extends SceneTree
## Checks the account stores without a network. Run from the project folder:
##   godot --headless --path . -s tests/test_account_store.gd
## Always checks the JSON file store. With DATABASE_URL set it also checks the
## PostgreSQL store against that database, using throwaway accounts that it
## deletes afterwards. Exits non-zero if any check fails.

const AccountStore := preload("res://scripts/account_store.gd")
const PostgresAccountStore := preload("res://scripts/postgres_account_store.gd")
const PostgresClient := preload("res://scripts/postgres_client.gd")
const PATH := "user://test_accounts.json"

var _failures := 0


func _initialize() -> void:
	# TLS isn't ready until the main loop starts, so wait a frame.
	await process_frame

	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	_check_store("AccountStore", AccountStore.new(PATH), "Chris", func() -> Variant: return AccountStore.new(PATH))
	_check(not FileAccess.get_file_as_string(PATH).contains("secret1"), "password is not stored in plain text")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))

	var url := OS.get_environment("DATABASE_URL")
	if url == "":
		print("PostgresAccountStore: skipped (set DATABASE_URL to run it)")
	else:
		_check_postgres(url)

	print("Account stores: %s" % ("all checks passed" if _failures == 0 else "%d checks failed" % _failures))
	quit(1 if _failures > 0 else 0)


func _check_postgres(url: String) -> void:
	_check(PostgresClient.parse_url("postgres://u:p%40ss@db:6000/game?sslmode=require") == {
		"host": "db", "port": 6000, "user": "u", "password": "p@ss", "dbname": "game", "sslmode": "require", "sslrootcert": "",
	}, "parses a database URL")
	var c := PostgresClient.parse_url(url)
	var wrong := PostgresAccountStore.new("postgres://%s:%s@%s:%d/%s?sslmode=%s&sslrootcert=%s" % [
		c["user"].uri_encode(), (c["password"] + "-wrong").uri_encode(), c["host"], c["port"],
		c["dbname"].uri_encode(), c["sslmode"], c["sslrootcert"].uri_encode()])
	_check(wrong.open() != "", "a wrong database password is refused")

	var store := PostgresAccountStore.new(url)
	store.bcrypt_cost = 4  # keeps the test quick; the server uses the default
	var err := store.open()
	_check(err == "", "connects and migrates: %s" % err)
	if err != "":
		return
	_check(store.open() == "", "migrating again is a no-op")
	var username := "Pg%d" % (randi() % 100_000_000)
	_check_store("PostgresAccountStore", store, username, func() -> Variant:
		var again := PostgresAccountStore.new(url)
		again.open()
		return again)

	var db := PostgresClient.new()
	db.connect_to(url)
	var rows: Array = db.query("SELECT password_hash FROM accounts WHERE username_key = $1", [username.to_lower()])["rows"]
	_check(rows.size() == 1 and str(rows[0]["password_hash"]).begins_with("$2a$04$"), "password is stored as a bcrypt hash")
	_check(rows.size() == 1 and not str(rows[0]["password_hash"]).contains("secret1"), "password is not stored in plain text")
	_check(store.register("Robert'); DROP TABLE accounts;--", "secret1") != "", "rejects SQL in a username")
	_check(store.verify(username, "' OR '1'='1") != "", "SQL in a password is just a wrong password")
	db.query("DELETE FROM accounts WHERE username_key = $1", [username.to_lower()])
	_check(not store.has_account(username), "test account cleaned up")
	db.close()
	store.close()


## The same checks for either store. reopen makes a fresh store over the same
## data, to check that everything was saved.
func _check_store(label: String, store: Variant, username: String, reopen: Callable) -> void:
	var failures_before := _failures
	var lower := username.to_lower()
	_check(store.register("ab", "secret1") != "", "rejects a short username")
	_check(store.register(lower, "123") != "", "rejects a short password")
	_check(store.register(username, "secret1") == "", "registers an account")
	_check(store.register(username.to_upper(), "other12") != "", "usernames are case-insensitive")
	_check(store.verify(lower, "secret1") == "", "accepts the right password")
	_check(store.verify(lower, "wrong12") != "", "rejects a wrong password")
	_check(store.verify("nobody_" + lower.right(8), "secret1") != "", "rejects an unknown account")
	_check(store.display_name(lower) == username, "keeps the typed username")

	_check(store.create_character(lower, "Ragnar") == "", "creates a character")
	_check(store.create_character(lower, "ragnar") != "", "rejects a duplicate name")
	_check(store.create_character(lower, "1x") != "", "rejects an invalid name")
	for character_name in ["Astrid", "Bjorn", "Freya", "Leif"]:
		store.create_character(lower, character_name)
	_check(store.create_character(lower, "Sigrid") != "", "caps characters per account")
	_check(store.delete_character(lower, "Bjorn") == "", "deletes a character")
	_check(not store.has_character(lower, "Bjorn"), "deleted character is gone")
	_check(store.delete_character(lower, "Bjorn") != "", "can't delete a character twice")

	var reloaded: Variant = reopen.call()
	_check(reloaded.verify(lower, "secret1") == "", "password survives a reload")
	var names: Array = reloaded.list_characters(lower).map(func(c: Dictionary) -> String: return c["name"])
	_check(names == ["Ragnar", "Astrid", "Freya", "Leif"], "characters survive a reload in order")
	_check(typeof(reloaded.list_characters(lower)[0]["created"]) in [TYPE_INT, TYPE_FLOAT], "character creation time is a Unix time")
	reloaded.close()
	print("%s: %s" % [label, "all checks passed" if _failures == failures_before else "%d checks failed" % (_failures - failures_before)])


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: %s" % what)
