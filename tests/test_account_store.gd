extends SceneTree
## Checks AccountStore without a network. Run from the project folder:
##   godot --headless --path . -s tests/test_account_store.gd
## Exits non-zero if any check fails.

const AccountStore := preload("res://scripts/account_store.gd")
const PATH := "user://test_accounts.json"

var _failures := 0


func _init() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))

	var store := AccountStore.new(PATH)
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

	var reloaded := AccountStore.new(PATH)
	_check(reloaded.verify("chris", "secret1") == "", "password survives a reload")
	var names := reloaded.list_characters("chris").map(func(c: Dictionary) -> String: return c["name"])
	_check(names == ["Ragnar", "Astrid", "Freya", "Leif"], "characters survive a reload in order")
	_check(not FileAccess.get_file_as_string(PATH).contains("secret1"), "password is not stored in plain text")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	print("AccountStore: %s" % ("all checks passed" if _failures == 0 else "%d checks failed" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: %s" % what)
