extends Node
## The only thing that reads or writes save files. Autoload.
## See docs/ARCHITECTURE.md rule 4.

const SAVE_PATH := "user://save.json"
const TMP_PATH := "user://save.tmp.json"
const CORRUPT_PATH := "user://save.corrupt.json"
## The Ledger's records, one JSON object per line (DECISIONS.md "The Ledger", item 1). The main save
## keeps ledger_next_seq, the high-water mark: a line at or past it was appended by a save that
## never landed, and load drops it.
const LEDGER_PATH := "user://ledger.jsonl"
const LEDGER_TMP_PATH := "user://ledger.tmp.jsonl"
const SAVE_VERSION := 3

var _load_notice: String = ""
var load_blocked: bool = false
var load_block_reason: String = ""
var last_write_error: String = ""
var _loading: bool = false
## Every record of _ledger_on_disk below _ledger_disk_seq is in LEDGER_PATH, which is
## _ledger_disk_length bytes long. A different list (a load, a from_dict) or a failed undo clears
## _ledger_synced, and the next save rewrites the file whole.
var _ledger_on_disk: Array[Dictionary] = []
var _ledger_disk_seq: int = 1
var _ledger_disk_length: int = 0
var _ledger_synced: bool = false


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
	var text: String = JSON.stringify(payload, "\t")

	# ig-6pm: never write a file this build's own load would refuse. Checked on the text load will read
	# (numbers as floats, names as Strings, a NaN that does not survive), not on the dict. Before the
	# ledger, so a refusal touches no file. Do not remove for speed: a bad state would lock the save.
	var parsed: Variant = JSON.parse_string(text)
	var refusal: String = "the save text is not a Dictionary" if parsed is not Dictionary else _load_refusal(parsed as Dictionary, SAVE_VERSION)
	if not refusal.is_empty():
		return _write_failed("Save refused: this game state would not load (%s). Your last save is safe; restart to return to it." % refusal)

	# The ledger goes first: a main save that then fails leaves lines past its mark, which the undo
	# below cuts and load would drop anyway. The reverse order could lose committed records.
	var ledger: Array[Dictionary] = GameSession.ledger
	var rewrite_ledger: bool = not _ledger_synced or not is_same(ledger, _ledger_on_disk) or GameSession.ledger_next_seq < _ledger_disk_seq
	var ledger_length: int = _write_ledger_file(ledger) if rewrite_ledger else _append_ledger(ledger)
	if ledger_length < 0:
		return _write_failed("Save failed: the ledger could not be written. The previous save is unchanged.")

	var file := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if file == null:
		var open_error: Error = FileAccess.get_open_error()
		_undo_ledger(rewrite_ledger, ledger_length)
		return _write_failed("Save failed: %s" % error_string(open_error))
	# store_string() returns false when the write itself fails - a full disk, a quota, a lock - and
	# the handle stays non-null through it, so the open check above does not cover this. Renaming a
	# truncated temp over a good save is the exact loss staging exists to prevent, so a failed write
	# leaves both files alone and the previous save stands.
	var wrote: bool = file.store_string(text)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if not wrote or write_error != OK:
		_undo_ledger(rewrite_ledger, ledger_length)
		return _write_failed("Save failed: the staged save could not be written (%s). The previous save is unchanged." % error_string(write_error))

	var rename_error: Error = DirAccess.rename_absolute(TMP_PATH, SAVE_PATH)
	if rename_error != OK:
		_undo_ledger(rewrite_ledger, ledger_length)
		return _write_failed("Could not replace save with temporary save: %s" % error_string(rename_error))
	GameSession.saved_at_unix = saved_at
	_ledger_on_disk = ledger
	_ledger_disk_seq = GameSession.ledger_next_seq
	_ledger_disk_length = ledger_length
	_ledger_synced = true
	return true


## Returns true when a save was found and applied.
func load_game() -> bool:
	load_blocked = false
	load_block_reason = ""
	last_write_error = ""
	# No main save means no mark: any side file is orphaned, and the first save rewrites it.
	_ledger_synced = false
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
		var validation_error: String = _load_refusal(parsed_dictionary, version)
		if not validation_error.is_empty():
			_block_load("Save v%d is invalid: %s" % [version, validation_error])
			return false

	# A legacy save embeds its records: they migrate to the side file once, below, and the next save
	# stops writing the key. Otherwise the side file's committed lines come in as "ledger".
	var ledger_rewrite: bool = parsed_dictionary.has("ledger")
	var ledger_lines: int = 0
	if not ledger_rewrite:
		var read: Dictionary = _read_ledger_file(Item.int_field(parsed_dictionary, "ledger_next_seq", 1, "game session"))
		if read.has("error"):
			_block_load("The history file exists but could not be opened: %s. Nothing was changed." % read["error"])
			return false
		parsed_dictionary["ledger"] = read["records"]
		ledger_rewrite = read["rewrite"]
		ledger_lines = (read["records"] as Array).size()

	_loading = true
	GameSession.from_dict(parsed_dictionary)
	_loading = false
	_compact_ledger(ledger_rewrite or ledger_lines != GameSession.ledger.size())
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


## Why load refuses a parsed save, or "". save() runs it on its own text first (ig-6pm), so the write
## side and the read side cannot drift. Repairs rescue timestamps in place, as load needs.
static func _load_refusal(parsed: Dictionary, version: int) -> String:
	GameSession.repair_rescue_timestamps(parsed)
	return GameSession.validate_saved_state(parsed, version)


## The committed records in LEDGER_PATH: lines below mark, oldest first. rewrite is true when the
## file holds anything else (an orphan past the mark, a torn last line, a bad line), so the load
## compacts it. A missing file is an empty ledger, with a warning past mark 1. A file that exists but
## will not open (often a passing lock) returns "error" instead, and the load blocks.
func _read_ledger_file(mark: int) -> Dictionary:
	var records: Array = []
	if not FileAccess.file_exists(LEDGER_PATH):
		if mark > 1:
			push_warning("The ledger file is missing; the history starts empty.")
		return {"records": records, "rewrite": false}
	var file := FileAccess.open(LEDGER_PATH, FileAccess.READ)
	if file == null:
		return {"error": error_string(FileAccess.get_open_error())}
	var lines: PackedStringArray = file.get_as_text().split("\n")
	file.close()
	# Every whole line ends in "\n", so the last piece is "" unless a crash tore the last append.
	var rewrite: bool = not lines[lines.size() - 1].is_empty()
	lines.resize(lines.size() - 1)
	var whole: Variant = JSON.parse_string("[" + ",".join(lines) + "]") if not lines.is_empty() else []
	var entries: Array = whole as Array if whole is Array and (whole as Array).size() == lines.size() else []
	for index: int in lines.size():
		var line: String = lines[index]
		var parsed: Variant = entries[index] if not entries.is_empty() else JSON.parse_string(line)
		if parsed is Dictionary and ((parsed as Dictionary).get("seq") is float or (parsed as Dictionary).get("seq") is int) and int((parsed as Dictionary)["seq"]) < mark:
			records.append(parsed)
			continue
		rewrite = true
		if not parsed is Dictionary:
			push_warning("Invalid ledger line dropped: %s" % line.left(80))
	return {"records": records, "rewrite": rewrite}


## After a load: the side file becomes exactly GameSession.ledger (orphans, a torn line and evicted
## records gone). Temp file then rename, so an interruption leaves the old file whole. If that
## fails, the next save rewrites the file instead.
func _compact_ledger(rewrite: bool) -> void:
	_ledger_on_disk = GameSession.ledger
	_ledger_disk_seq = GameSession.ledger_next_seq
	var length: int = _write_ledger_file(GameSession.ledger) if rewrite else _ledger_file_length()
	_ledger_disk_length = length
	_ledger_synced = length >= 0


func _ledger_file_length() -> int:
	if not FileAccess.file_exists(LEDGER_PATH):
		return 0
	var file := FileAccess.open(LEDGER_PATH, FileAccess.READ)
	if file == null:
		return -1
	var length: int = file.get_length()
	file.close()
	return length


## Rewrites the side file to hold exactly ledger. Returns its length, or -1.
func _write_ledger_file(ledger: Array[Dictionary]) -> int:
	var lines: PackedStringArray = []
	for record: Dictionary in ledger:
		lines.append(JSON.stringify(record) + "\n")
	var file := FileAccess.open(LEDGER_TMP_PATH, FileAccess.WRITE)
	if file == null:
		return -1
	var wrote: bool = file.store_string("".join(lines))
	file.flush()
	var error: Error = file.get_error()
	var length: int = file.get_length()
	file.close()
	if not wrote or error != OK or DirAccess.rename_absolute(LEDGER_TMP_PATH, LEDGER_PATH) != OK:
		return -1
	return length


## Appends the records not yet on disk (seq at or past _ledger_disk_seq, always the list's tail) and
## flushes. Returns the new length, or -1 after undoing a partial write.
func _append_ledger(ledger: Array[Dictionary]) -> int:
	var start: int = ledger.size()
	while start > 0 and int(ledger[start - 1].get("seq", 0)) >= _ledger_disk_seq:
		start -= 1
	if start == ledger.size():
		return _ledger_disk_length
	var lines: PackedStringArray = []
	for index: int in range(start, ledger.size()):
		lines.append(JSON.stringify(ledger[index]) + "\n")
	var file := FileAccess.open(LEDGER_PATH, FileAccess.READ_WRITE if FileAccess.file_exists(LEDGER_PATH) else FileAccess.WRITE)
	if file == null:
		return -1
	file.seek(_ledger_disk_length)
	var wrote: bool = file.store_string("".join(lines))
	file.flush()
	var error: Error = file.get_error()
	var length: int = file.get_position()
	file.close()
	if not wrote or error != OK:
		_undo_ledger(false, -1)
		return -1
	return length


## A save failed after the ledger was written: cut the file back to its committed length. If the
## file was rewritten whole, or the cut fails, the next save rewrites it (and load drops the orphans).
func _undo_ledger(rewrote: bool, length: int) -> void:
	if rewrote:
		_ledger_synced = false
		return
	if length == _ledger_disk_length:
		return
	var file := FileAccess.open(LEDGER_PATH, FileAccess.READ_WRITE)
	if file == null or file.resize(_ledger_disk_length) != OK:
		_ledger_synced = false
	if file != null:
		file.close()


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
