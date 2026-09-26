extends RefCounted
## Server-side accounts and characters kept in PostgreSQL. Same methods as
## AccountStore (the JSON file store), plus open().
##
## Passwords are hashed with bcrypt by the database's pgcrypto extension
## (crypt() with gen_salt('bf')), so only the salted hash is stored. The
## server creates the tables itself the first time it connects.
##
## Every call blocks on the database; Session runs them on AccountWorker's
## thread.

const PostgresClient := preload("res://scripts/postgres_client.gd")

const MAX_CHARACTERS := 5
## bcrypt work factor: each step doubles the time a hash takes. 12 is about a
## quarter of a second on a desktop CPU.
const DEFAULT_BCRYPT_COST := 12
## bcrypt only uses the first 72 bytes of a password.
const MAX_PASSWORD_BYTES := 72
## Held while migrating so two servers starting together don't collide.
const MIGRATION_LOCK_ID := 7_345_001

## Each entry runs once, in order, and is recorded in schema_migrations.
## Append new ones; never edit one that has shipped.
const MIGRATIONS := [
	"""
	CREATE EXTENSION IF NOT EXISTS pgcrypto;
	CREATE TABLE accounts (
		id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
		username text NOT NULL,
		username_key text NOT NULL UNIQUE,
		password_hash text NOT NULL,
		created_at timestamptz NOT NULL DEFAULT now(),
		last_login_at timestamptz
	);
	CREATE TABLE characters (
		id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
		account_id bigint NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
		name text NOT NULL,
		name_key text NOT NULL,
		created_at timestamptz NOT NULL DEFAULT now(),
		UNIQUE (account_id, name_key)
	);
	""",
]

## Compared against when the username doesn't exist, so a wrong username
## takes as long as a wrong password and doesn't reveal which accounts exist.
const DUMMY_HASH := "$2a$12$5GL2NUSvQMtKkybOCtHSzuha0sTQyYO0gLvFG1AYoIsk/GTGOrAeO"

var url: String
var bcrypt_cost := DEFAULT_BCRYPT_COST
var _db := PostgresClient.new()
var _username_regex := RegEx.create_from_string("^[A-Za-z0-9_]{3,16}$")
var _character_regex := RegEx.create_from_string("^[A-Za-z][A-Za-z' -]{1,15}$")


func _init(p_url: String) -> void:
	url = p_url


## Where the accounts live, for the server log. Leaves out the password.
func describe() -> String:
	var config := PostgresClient.parse_url(url)
	if config.is_empty():
		return "PostgreSQL (bad DATABASE_URL)"
	return "PostgreSQL database %s on %s:%d as %s" % [config["dbname"], config["host"], config["port"], config["user"]]


## Connects and brings the schema up to date. Returns "" or what went wrong.
func open() -> String:
	var err := _db.connect_to(url)
	if err != "":
		return err
	return _migrate()


func close() -> void:
	_db.close()


func has_account(username: String) -> bool:
	return not _rows("SELECT 1 FROM accounts WHERE username_key = $1", [username.to_lower()]).is_empty()


## The username as it was typed when the account was created.
func display_name(username: String) -> String:
	var rows := _rows("SELECT username FROM accounts WHERE username_key = $1", [username.to_lower()])
	return rows[0]["username"] if not rows.is_empty() else username


func register(username: String, password: String) -> String:
	if not _username_regex.search(username):
		return "Usernames are 3 to 16 letters, numbers or underscores."
	if password.length() < 6 or password.length() > 64:
		return "Passwords are 6 to 64 characters."
	if password.to_utf8_buffer().size() > MAX_PASSWORD_BYTES:
		return "That password is too long."
	var result := _query(
		"""INSERT INTO accounts (username, username_key, password_hash)
		VALUES ($1, $2, crypt($3, gen_salt('bf', $4::int)))
		ON CONFLICT (username_key) DO NOTHING
		RETURNING id""",
		[username, username.to_lower(), password, bcrypt_cost])
	if result["error"] != "":
		return "The server could not save your account."
	if result["rows"].is_empty():
		return "That username is taken."
	return ""


func verify(username: String, password: String) -> String:
	var result := _query(
		"""UPDATE accounts SET last_login_at = now()
		WHERE username_key = $1 AND password_hash = crypt($2, password_hash)
		RETURNING id""",
		[username.to_lower(), password])
	if result["error"] != "":
		return "The server could not check your password."
	if result["rows"].is_empty():
		if not has_account(username):
			_query("SELECT crypt($1, $2)", [password, DUMMY_HASH])
		return "Wrong username or password."
	return ""


## [{ name, created }] in the order they were made. created is a Unix time.
func list_characters(username: String) -> Array:
	return _rows(
		"""SELECT c.name, extract(epoch FROM c.created_at)::bigint AS created
		FROM characters c JOIN accounts a ON a.id = c.account_id
		WHERE a.username_key = $1
		ORDER BY c.id""",
		[username.to_lower()])


func has_character(username: String, character_name: String) -> bool:
	return not _rows(
		"""SELECT 1 FROM characters c JOIN accounts a ON a.id = c.account_id
		WHERE a.username_key = $1 AND c.name_key = $2""",
		[username.to_lower(), character_name.strip_edges().to_lower()]).is_empty()


func create_character(username: String, character_name: String) -> String:
	if not has_account(username):
		return "Not logged in."
	character_name = character_name.strip_edges()
	if not _character_regex.search(character_name):
		return "Character names are 2 to 16 letters, starting with a letter."
	if has_character(username, character_name):
		return "You already have a character called %s." % character_name
	var result := _query(
		"""INSERT INTO characters (account_id, name, name_key)
		SELECT a.id, $2, $3 FROM accounts a
		WHERE a.username_key = $1
			AND (SELECT count(*) FROM characters c WHERE c.account_id = a.id) < $4
		ON CONFLICT (account_id, name_key) DO NOTHING
		RETURNING id""",
		[username.to_lower(), character_name, character_name.to_lower(), MAX_CHARACTERS])
	if result["error"] != "":
		return "The server could not save your character."
	if result["rows"].is_empty():
		if has_character(username, character_name):
			return "You already have a character called %s." % character_name
		return "You can have at most %d characters." % MAX_CHARACTERS
	return ""


func delete_character(username: String, character_name: String) -> String:
	var result := _query(
		"""DELETE FROM characters c USING accounts a
		WHERE a.id = c.account_id AND a.username_key = $1 AND c.name_key = $2
		RETURNING c.id""",
		[username.to_lower(), character_name.strip_edges().to_lower()])
	if result["error"] != "":
		return "The server could not delete your character."
	if result["rows"].is_empty():
		return "No character called %s." % character_name
	return ""


func _migrate() -> String:
	var steps := [
		"CREATE TABLE IF NOT EXISTS schema_migrations (version int PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())",
		"SELECT pg_advisory_lock(%d)" % MIGRATION_LOCK_ID,
	]
	for sql in steps:
		var result := _db.execute(sql)
		if result["error"] != "":
			return "Could not set up the database: %s" % result["error"]
	var err := ""
	var done := {}
	var applied := _db.query("SELECT version FROM schema_migrations")
	if applied["error"] != "":
		err = applied["error"]
	for row in applied["rows"]:
		done[row["version"]] = true
	for i in MIGRATIONS.size():
		if err != "" or done.has(i + 1):
			continue
		var result := _db.execute("BEGIN;\n%s\nINSERT INTO schema_migrations (version) VALUES (%d);\nCOMMIT;" % [MIGRATIONS[i], i + 1])
		if result["error"] != "":
			_db.execute("ROLLBACK")
			err = "migration %d failed: %s" % [i + 1, result["error"]]
		else:
			print("Applied database migration %d" % (i + 1))
	_db.execute("SELECT pg_advisory_unlock(%d)" % MIGRATION_LOCK_ID)
	return "Could not set up the database: %s" % err if err != "" else ""


## Runs a query, reconnecting and trying once more if the connection dropped
## (say the database restarted).
func _query(sql: String, params: Array) -> Dictionary:
	var result := _db.query(sql, params)
	if result["connection_lost"] and not _db.is_open():
		push_warning("Lost the database connection; reconnecting.")
		if _db.connect_to(url) == "":
			result = _db.query(sql, params)
	if result["error"] != "":
		push_error("Database query failed: %s" % result["error"])
	return result


func _rows(sql: String, params: Array) -> Array:
	return _query(sql, params)["rows"]
