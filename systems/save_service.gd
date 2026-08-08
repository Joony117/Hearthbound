extends Node
## The only thing that reads or writes save files. Autoload.
## See docs/ARCHITECTURE.md rule 4.

const SAVE_PATH := "user://save.json"
const CORRUPT_PATH := "user://save.corrupt.json"
const SAVE_VERSION := 1

var _load_notice: String = ""


func save() -> void:
	var payload := GameSession.to_dict()
	payload["version"] = SAVE_VERSION

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Save failed: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(payload, "\t"))


## Returns true when a save was found and applied.
func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("Load failed: %s" % error_string(FileAccess.get_open_error()))
		return false

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		push_error("Save file is corrupt: expected a Dictionary at the top level.")
		file.close()
		var rename_error: Error = DirAccess.rename_absolute(SAVE_PATH, CORRUPT_PATH)
		if rename_error != OK:
			push_error("Could not move corrupt save aside: %s" % error_string(rename_error))
			return false
		_load_notice = "Your last save couldn't be read and was moved aside as save.corrupt.json. Starting a new game."
		return false

	# ponytail: version is written and read but never migrated. Phase 5 owns migration; the
	# field exists now because retrofitting it onto shipped saves is the expensive version.
	# Same untrusted shape the domain from_dict()s decode, so it uses the same guard: an explicit
	# "version": null is not a missing key, and int() throws on it before any of them run.
	var version := Item.int_field(parsed as Dictionary, "version", 0, "save")
	if version > SAVE_VERSION:
		push_error("Save is from a newer build (v%d > v%d); refusing to load." % [version, SAVE_VERSION])
		return false

	GameSession.from_dict(parsed)
	return true


## Returns the recovery notice once so it cannot survive another scene change.
func take_load_notice() -> String:
	var notice := _load_notice
	_load_notice = ""
	return notice
