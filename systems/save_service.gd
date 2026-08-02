extends Node
## The only thing that reads or writes save files. Autoload.
## See docs/ARCHITECTURE.md rule 4.

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1


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
		return false

	# ponytail: version is written and read but never migrated. Phase 5 owns migration; the
	# field exists now because retrofitting it onto shipped saves is the expensive version.
	var version := int((parsed as Dictionary).get("version", 0))
	if version > SAVE_VERSION:
		push_error("Save is from a newer build (v%d > v%d); refusing to load." % [version, SAVE_VERSION])
		return false

	GameSession.from_dict(parsed)
	return true
