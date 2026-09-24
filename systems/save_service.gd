extends Node
## The only thing that reads or writes save files. Autoload.
## See docs/ARCHITECTURE.md rule 4.

const SAVE_PATH := "user://save.json"
const TMP_PATH := "user://save.tmp.json"
const CORRUPT_PATH := "user://save.corrupt.json"
const SAVE_VERSION := 3

var _load_notice: String = ""
var load_blocked: bool = false
var load_block_reason: String = ""
var last_write_error: String = ""
var _loading: bool = false


func save() -> bool:
	if _loading or GameSession.is_save_deferred():
		return true
	last_write_error = ""
	if load_blocked:
		last_write_error = load_block_reason
		return false
	var payload := GameSession.to_dict()
	payload["version"] = SAVE_VERSION
	var saved_at: float = Time.get_unix_time_from_system()
	payload["saved_at_unix"] = saved_at

	var file := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if file == null:
		return _write_failed("Save failed: %s" % error_string(FileAccess.get_open_error()))
	# store_string() returns false when the write itself fails - a full disk, a quota, a lock - and
	# the handle stays non-null through it, so the open check above does not cover this. Renaming a
	# truncated temp over a good save is the exact loss staging exists to prevent, so a failed write
	# leaves both files alone and the previous save stands.
	var wrote: bool = file.store_string(JSON.stringify(payload, "\t"))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if not wrote or write_error != OK:
		return _write_failed("Save failed: the staged save could not be written (%s). The previous save is unchanged." % error_string(write_error))

	var rename_error: Error = DirAccess.rename_absolute(TMP_PATH, SAVE_PATH)
	if rename_error != OK:
		return _write_failed("Could not replace save with temporary save: %s" % error_string(rename_error))
	GameSession.saved_at_unix = saved_at
	return true


## Returns true when a save was found and applied.
func load_game() -> bool:
	load_blocked = false
	load_block_reason = ""
	last_write_error = ""
	if not FileAccess.file_exists(SAVE_PATH):
		return false

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		_block_load("The save exists but could not be opened: %s" % error_string(FileAccess.get_open_error()))
		return false

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	# Close before branching, not per-branch. Windows refuses to replace a file that still has an
	# open handle, and from_dict() below emits roster_changed, which save() is connected to - a
	# handle held this far fails that save()'s rename. GameSession._ready() connects only after
	# load_game() returns, so the shipped boot path is safe today and this guards every other
	# caller: the tests, and any reload-from-menu a later ticket adds.
	file.close()

	if parsed is not Dictionary:
		_block_load("Save file is corrupt: expected a Dictionary at the top level. The original save is unchanged.")
		return false

	var parsed_dictionary: Dictionary = parsed as Dictionary
	var version: int = 0
	if parsed_dictionary.has("version"):
		# Variant is required while validating the untrusted top-level version before migration.
		var raw_version: Variant = parsed_dictionary.get("version")
		if raw_version is int:
			version = raw_version as int
		elif raw_version is float:
			var float_version: float = raw_version as float
			if is_finite(float_version) and float_version == floorf(float_version):
				version = int(float_version)
			else:
				_block_load("Save version is invalid; refusing to load.")
				return false
		else:
			_block_load("Save version is invalid; refusing to load.")
			return false
		if version < 0:
			_block_load("Save version is invalid; refusing to load.")
			return false
	if version > SAVE_VERSION:
		_block_load("Save is from a newer build (v%d > v%d); refusing to load." % [version, SAVE_VERSION])
		return false

	if version >= 2:
		GameSession.repair_rescue_timestamps(parsed_dictionary)
		var validation_error: String = GameSession.validate_saved_state(parsed_dictionary, version)
		if not validation_error.is_empty():
			_block_load("Save v%d is invalid: %s" % [version, validation_error])
			return false

	_loading = true
	GameSession.from_dict(parsed_dictionary)
	_loading = false
	if version < SAVE_VERSION:
		if not GameSession.migrate_v2_orders(Time.get_unix_time_from_system()):
			_block_load("The legacy save could not be migrated to persistent battles. The original save is unchanged.")
			return false
		if not save():
			_block_load("The legacy save loaded but its v3 battle migration could not be persisted. The original save is unchanged.")
			return false
	else:
		GameSession.apply_offline_expedition_progress(Time.get_unix_time_from_system())
	return true


## Returns the recovery notice once so it cannot survive another scene change.
func take_load_notice() -> String:
	var notice := _load_notice
	_load_notice = ""
	return notice


func _write_failed(message: String) -> bool:
	last_write_error = message
	_load_notice = message
	push_error(message)
	return false


func _block_load(reason: String) -> void:
	load_blocked = true
	load_block_reason = reason
	_load_notice = reason
	push_error(reason)
