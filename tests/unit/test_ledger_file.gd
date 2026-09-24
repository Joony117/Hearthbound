extends GutTest

## ig-m6o.9: the Ledger's side file (DECISIONS.md 2026-09-24 "The Ledger", items 1 and 8). The
## records live in user://ledger.jsonl and the main save keeps only ledger_next_seq, the mark. Every
## case goes through a real disk reload (risky boundary #1).

const BALANCE: BalanceTable = preload("res://balance.tres")
const KEPT: Array[String] = [SaveService.SAVE_PATH, SaveService.LEDGER_PATH]

var _originals: Dictionary = {}


func before_all() -> void:
	for path: String in KEPT:
		if FileAccess.file_exists(path):
			_originals[path] = FileAccess.get_file_as_bytes(path)


func after_all() -> void:
	SaveService.load_blocked = false
	GameSession.set("_save_deferred_depth", 0)
	for path: String in KEPT:
		if _originals.has(path):
			FileAccess.open(path, FileAccess.WRITE).store_buffer(_originals[path])
		else:
			_remove(path)


func before_each() -> void:
	SaveService.load_blocked = false
	GameSession.set("_save_deferred_depth", 1)
	GameSession.from_dict({"roster": []})
	GameSession.set("_save_deferred_depth", 0)
	for path: String in KEPT:
		_remove(path)


func after_each() -> void:
	for path: String in [SaveService.TMP_PATH, SaveService.LEDGER_TMP_PATH]:
		if DirAccess.dir_exists_absolute(path):
			DirAccess.remove_absolute(path)
		_remove(path)
	GameSession.set("_save_deferred_depth", 0)


func test_a_commit_appends_only_its_own_line_and_a_reload_keeps_every_record_and_the_mark() -> void:
	assert_true(_commit("summoned", _summoned(1)))
	# Mark the first line on disk, same length: a rewrite would put it back, an append leaves it.
	_write_text(_text().replace("\"summoned\"", "\"SUMMONED\""))
	var first: PackedByteArray = _bytes()
	assert_true(_commit("summoned", _summoned(2)))
	var second: PackedByteArray = _bytes()
	assert_eq(second.slice(0, first.size()), first, "an append: the first line is untouched")
	assert_eq(_lines().size(), 2)
	_write_text(_text().replace("\"SUMMONED\"", "\"summoned\""))
	second = _bytes()
	assert_true(SaveService.save())
	assert_eq(_bytes(), second, "a save with nothing new writes no ledger bytes")
	assert_false(FileAccess.get_file_as_string(SaveService.SAVE_PATH).contains("\"ledger\":"), "the main save keeps only the mark")
	var before: String = JSON.stringify(GameSession.ledger)
	_reload()
	assert_eq(JSON.stringify(GameSession.ledger), before)
	assert_eq(GameSession.ledger_next_seq, 3)


## The append lands, then the main save fails: the mutation rolls back, the undo cuts the line, and
## the next record takes the seq without meeting a stale line of the same seq.
func test_an_append_whose_main_save_fails_leaves_no_line_that_survives_a_reload() -> void:
	assert_true(_commit("summoned", _summoned(1)))
	var committed: PackedByteArray = _bytes()
	assert_eq(DirAccess.make_dir_absolute(SaveService.TMP_PATH), OK)
	assert_false(_commit("summoned", _summoned(2)))
	assert_push_error("Save failed")
	assert_eq(DirAccess.remove_absolute(SaveService.TMP_PATH), OK)
	assert_eq(_seqs(), [1])
	assert_eq(GameSession.ledger_next_seq, 2)
	assert_eq(_bytes(), committed, "the appended line was cut back")
	_reload()
	assert_eq(_seqs(), [1])
	assert_true(_commit("ranked_up", _ranked_up()))
	_reload()
	assert_eq(_seqs(), [1, 2])
	assert_eq(GameSession.ledger[1]["kind"], "ranked_up", "seq 2 is the committed record, not the rolled-back one")


## A crash between the append and the main save leaves the line on disk: load drops it (its seq is
## at the mark), compacts it away, and the next record's seq meets no stale line.
func test_an_orphan_line_from_a_crash_is_dropped_at_load_and_never_collides() -> void:
	assert_true(_commit("summoned", _summoned(1)))
	_append_raw(JSON.stringify({"seq": 2, "time": 1, "kind": "summoned", "hero": "hero:ghost", "name": "Ghost", "rank": 0, "archetype": "mage"}) + "\n")
	_reload()
	assert_eq(_seqs(), [1])
	assert_eq(GameSession.ledger_next_seq, 2)
	assert_false(_text().contains("ghost"), "compacted away at load")
	assert_true(_commit("ranked_up", _ranked_up()))
	_reload()
	assert_eq(_seqs(), [1, 2])
	assert_eq(GameSession.ledger[1]["kind"], "ranked_up")
	assert_false(_text().contains("ghost"))


func test_a_torn_last_line_is_dropped_at_load() -> void:
	assert_true(_commit("summoned", _summoned(1)))
	assert_true(_commit("summoned", _summoned(2)))
	_append_raw("{\"seq\":3,\"time\":1,\"ki")
	_reload()
	assert_eq(_seqs(), [1, 2])
	assert_true(_text().ends_with("\n"), "the torn piece is gone")
	assert_eq(_lines().size(), 2)
	assert_true(_commit("ranked_up", _ranked_up()))
	_reload()
	assert_eq(_seqs(), [1, 2, 3])


func test_a_missing_side_file_loads_an_empty_ledger_and_the_game_plays_on() -> void:
	assert_true(_commit("summoned", _summoned(1)))
	assert_true(_commit("summoned", _summoned(2)))
	_remove(SaveService.LEDGER_PATH)
	_reload()
	assert_eq(GameSession.ledger, [] as Array[Dictionary])
	assert_eq(GameSession.ledger_next_seq, 3, "the mark stands, so no seq is reused")
	assert_true(_commit("ranked_up", _ranked_up()))
	_reload()
	assert_eq(_seqs(), [3])


## Compaction writes a temp file, then renames it over the side file. A failed temp write (a crash
## before the rename is the same) leaves the old file whole; the next save rewrites it.
func test_an_interrupted_compaction_leaves_the_old_file_whole() -> void:
	assert_true(_commit("summoned", _summoned(1)))
	_append_raw(JSON.stringify({"seq": 2, "time": 1, "kind": "summoned", "hero": "hero:ghost", "name": "Ghost", "rank": 0, "archetype": "mage"}) + "\n")
	var on_disk: PackedByteArray = _bytes()
	assert_eq(DirAccess.make_dir_absolute(SaveService.LEDGER_TMP_PATH), OK)
	_reload()
	assert_eq(_seqs(), [1])
	assert_eq(_bytes(), on_disk, "the old file is whole")
	assert_eq(DirAccess.remove_absolute(SaveService.LEDGER_TMP_PATH), OK)
	assert_true(_commit("ranked_up", _ranked_up()))
	assert_false(_text().contains("ghost"), "the next save rewrote the file")
	_reload()
	assert_eq(_seqs(), [1, 2])
	assert_eq(GameSession.ledger[1]["kind"], "ranked_up")


## The one save that rewrites the side file whole (after a failed compaction) and whose main save
## then fails: the old mark still reads the committed records, and the rewritten line past it drops.
func test_a_rewrite_whose_main_save_fails_keeps_every_committed_record_through_a_reload() -> void:
	assert_true(_commit("summoned", _summoned(1)))
	_append_raw(JSON.stringify({"seq": 2, "time": 1, "kind": "summoned", "hero": "hero:ghost", "name": "Ghost", "rank": 0, "archetype": "mage"}) + "
")
	assert_eq(DirAccess.make_dir_absolute(SaveService.LEDGER_TMP_PATH), OK)
	_reload()
	assert_eq(DirAccess.remove_absolute(SaveService.LEDGER_TMP_PATH), OK)
	assert_eq(DirAccess.make_dir_absolute(SaveService.TMP_PATH), OK)
	assert_false(_commit("ranked_up", _ranked_up()))
	assert_push_error("Save failed")
	assert_false(_text().contains("ghost"), "the rewrite landed before the main save failed")
	assert_eq(DirAccess.remove_absolute(SaveService.TMP_PATH), OK)
	_reload()
	assert_eq(_seqs(), [1], "the committed record stands; the rolled-back one is past the mark")
	assert_true(_commit("summoned", _summoned(3)))
	_reload()
	assert_eq(_seqs(), [1, 2])
	assert_eq(GameSession.ledger[1]["kind"], "summoned")
	assert_eq(_lines().size(), 2)


## A save from ig-m6o.1 embeds its records. They move to the side file on load, and a second load of
## the same legacy save (a crash before the next main save) does not duplicate them.
func test_a_legacy_embedded_ledger_migrates_once() -> void:
	var records: Array = [
		{"seq": 1, "time": 100, "kind": "summoned", "hero": "hero:a", "name": "A", "rank": 0, "archetype": "knight"},
		{"seq": 2, "time": 200, "kind": "ranked_up", "hero": "hero:a", "from": 0, "to": 1, "via": "essence"},
		{"seq": 4, "time": 300, "kind": "died", "hero": "hero:b", "name": "B", "rank": 0, "cause": "sacrifice", "by": "hero:a"},
	]
	var payload: Dictionary = GameSession.to_dict()
	payload["ledger"] = records
	payload["ledger_next_seq"] = 5
	payload["saved_at_unix"] = Time.get_unix_time_from_system() + 3600.0
	_write_main(payload)
	_reload()
	assert_eq(JSON.stringify(GameSession.ledger), JSON.stringify(records))
	assert_eq(_lines().size(), 3, "moved to the side file")
	_reload()
	assert_eq(_seqs(), [1, 2, 4])
	assert_eq(_lines().size(), 3, "not duplicated")
	assert_true(SaveService.save())
	assert_false(FileAccess.get_file_as_string(SaveService.SAVE_PATH).contains("\"ledger\":"), "the key is not written again")
	_reload()
	assert_eq(JSON.stringify(GameSession.ledger), JSON.stringify(records))
	assert_eq(GameSession.ledger_next_seq, 5)


## Over the cap on disk (records evicted in memory stay in the file until a load), the load applies
## the same tiered eviction and rewrites the file to match. Three over the real cap: seven chosen
## records, then deaths (the last tier) to fill.
func test_load_time_compaction_applies_the_tiered_eviction_exactly() -> void:
	var eventful: Array = [{"tick": 1, "what": "downed", "hero": "hero:a", "by": "enemy:rogue"}]
	var records: Array[Dictionary] = [
		{"seq": 1, "time": 1, "kind": "died", "hero": "hero:x", "name": "X", "rank": 0, "cause": "sacrifice", "by": "hero:a"},
		_battle(2, []),
		{"seq": 3, "time": 1, "kind": "summoned", "hero": "hero:a", "name": "A", "rank": 0, "archetype": "knight"},
		_battle(4, eventful),
		{"seq": 5, "time": 1, "kind": "ranked_up", "hero": "hero:a", "from": 0, "to": 1, "via": "essence"},
		_battle(6, []),
		{"seq": 7, "time": 1, "kind": "died", "hero": "hero:y", "name": "Y", "rank": 0, "cause": "sacrifice", "by": "hero:a"},
	]
	for seq: int in range(8, BALANCE.ledger_max_records + 4):
		records.append({"seq": seq, "time": 1, "kind": "died", "hero": "hero:f%d" % seq, "name": "F", "rank": 0, "cause": "starvation"})
	var expected: Array[Dictionary] = records.duplicate(true)
	Ledger.evict(expected, Ledger.tiers(expected), BALANCE.ledger_max_records)
	var payload: Dictionary = GameSession.to_dict()
	payload["ledger_next_seq"] = BALANCE.ledger_max_records + 4
	_write_main(payload)
	var text: String = ""
	for record: Dictionary in records:
		text += JSON.stringify(record) + "\n"
	_append_raw(text)
	_reload()
	assert_eq(_seqs().slice(0, 5), [1, 3, 5, 7, 8], "routine battles, then the other battle")
	assert_eq(GameSession.ledger.size(), BALANCE.ledger_max_records)
	assert_eq(JSON.stringify(GameSession.ledger), JSON.stringify(expected))
	assert_eq(_lines().size(), BALANCE.ledger_max_records, "the file matches")
	_reload()
	assert_eq(JSON.stringify(GameSession.ledger), JSON.stringify(expected))


## At exactly the cap, a mutation that appends and then fails leaves the ledger as it was: nothing
## evicted (eviction waits for the commit), nothing appended (the rollback truncates).
func test_a_failed_mutation_at_the_cap_rolls_back_to_the_same_ledger_through_a_reload() -> void:
	_fill(BALANCE.ledger_max_records, true)
	assert_true(SaveService.save())
	var before: String = JSON.stringify(GameSession.ledger)
	var on_disk: PackedByteArray = _bytes()
	assert_eq(DirAccess.make_dir_absolute(SaveService.TMP_PATH), OK)
	assert_false(_commit("battle", _battle(0, [])))
	assert_push_error("Save failed")
	assert_eq(DirAccess.remove_absolute(SaveService.TMP_PATH), OK)
	assert_eq(GameSession.ledger.size(), BALANCE.ledger_max_records)
	assert_eq(JSON.stringify(GameSession.ledger), before, "nothing evicted, nothing appended")
	assert_eq(_bytes(), on_disk)
	assert_false(GameSession._commit_profile_mutation(func() -> bool:
		GameSession._record("summoned", _summoned(9))
		return false))
	assert_eq(JSON.stringify(GameSession.ledger), before, "a mutation that fails by itself rolls back the same way")
	_reload()
	assert_eq(JSON.stringify(GameSession.ledger), before)


## SYSTEMS.md § The Ledger, the save budget row: at most 2 ms added to a profile action or a
## periodic save at any ledger size up to the cap. Best of seven, since noise only adds time;
## printed for the bead. The eventful ledger is the eviction's worst case: no routine battle, so it
## scans every record.
func test_a_full_ledger_adds_at_most_2_ms_to_a_commit_or_a_periodic_save() -> void:
	var empty: Dictionary = _timings()
	_fill(BALANCE.ledger_max_records, true)
	assert_true(SaveService.save())
	var mixed: Dictionary = _timings()
	GameSession.set("_save_deferred_depth", 1)
	GameSession.from_dict({"roster": []})
	GameSession.set("_save_deferred_depth", 0)
	_fill(BALANCE.ledger_max_records, false)
	assert_true(SaveService.save())
	var eventful: Dictionary = _timings()
	gut.p("LEDGER BUDGET (ms, best of 7): commit %.3f / %.3f / %.3f, periodic save %.3f / %.3f / %.3f, save with nothing new %.3f / %.3f / %.3f (empty / cap, mixed / cap, no routine battles)" % [empty["commit"], mixed["commit"], eventful["commit"], empty["periodic"], mixed["periodic"], eventful["periodic"], empty["idle"], mixed["idle"], eventful["idle"]])
	for full: Dictionary in [mixed, eventful]:
		for action: String in ["commit", "periodic", "idle"]:
			assert_lt(float(full[action]) - float(empty[action]), 2.0, action)


## Best-of-seven milliseconds of: a profile commit that records once, a settle recorded outside any commit
## plus its periodic save, and a save with nothing new.
func _timings() -> Dictionary:
	assert_true(SaveService.save())
	var samples: Dictionary = {"commit": [], "periodic": [], "idle": []}
	for run: int in 7:
		var started: int = Time.get_ticks_usec()
		assert_true(_commit("died", {"hero": "hero:t%d" % run, "name": "T", "rank": 0, "cause": "sacrifice", "by": "hero:a"}))
		samples["commit"].append((Time.get_ticks_usec() - started) / 1000.0)
		started = Time.get_ticks_usec()
		GameSession._record("battle", _battle(0, []))
		assert_true(SaveService.save())
		samples["periodic"].append((Time.get_ticks_usec() - started) / 1000.0)
		started = Time.get_ticks_usec()
		assert_true(SaveService.save())
		samples["idle"].append((Time.get_ticks_usec() - started) / 1000.0)
	var best: Dictionary = {}
	for action: String in samples:
		var sorted: Array = samples[action]
		sorted.sort()
		best[action] = sorted[0]
	return best


## count records shaped like m6o.1's cap test: five-hero battles, every fourth with moments, or
## (routine false) every one with moments, so no record is a routine battle.
func _fill(count: int, routine: bool) -> void:
	var team: Array = ["hero:a", "hero:b", "hero:c", "hero:d", "hero:e"]
	var moments: Array = [{"tick": 120, "what": "downed", "hero": "hero:c", "by": "enemy:rogue"}, {"tick": 180, "what": "revived", "hero": "hero:c", "by": "hero:a"}]
	for index: int in count:
		GameSession._record("battle", {"order": "order:%d" % index, "zone": "verdant_outskirts", "battle_kind": "normal", "result": "victory", "team": team, "kills": {"hero:a": 3, "hero:b": 2}, "moments": [] if routine and index % 4 != 0 else moments})
	assert_eq(GameSession.ledger.size(), count)


func _commit(kind: String, fields: Dictionary) -> bool:
	return GameSession._commit_profile_mutation(func() -> void: GameSession._record(kind, fields))


func _summoned(index: int) -> Dictionary:
	return {"hero": "hero:s%d" % index, "name": "S%d" % index, "rank": 0, "archetype": "knight"}


func _ranked_up() -> Dictionary:
	return {"hero": "hero:s1", "from": 0, "to": 1, "via": "essence"}


## A routine or eventful battle: a whole record for the side file, or (seq 0) the fields for _record.
func _battle(seq: int, moments: Array) -> Dictionary:
	var fields: Dictionary = {"order": "order:%d" % seq, "zone": "verdant_outskirts", "battle_kind": "normal", "result": "victory", "team": ["hero:a"], "kills": {}, "moments": moments}
	if seq == 0:
		return fields
	var record: Dictionary = {"seq": seq, "time": 1, "kind": "battle"}
	record.merge(fields)
	return record


func _reload() -> void:
	assert_true(SaveService.load_game())
	assert_false(SaveService.load_blocked, SaveService.load_block_reason)


func _seqs() -> Array:
	return GameSession.ledger.map(func(record: Dictionary) -> int: return record["seq"])


func _bytes() -> PackedByteArray:
	return FileAccess.get_file_as_bytes(SaveService.LEDGER_PATH)


func _text() -> String:
	return FileAccess.get_file_as_string(SaveService.LEDGER_PATH)


## Whole lines only: the piece after the last newline is not a line.
func _lines() -> PackedStringArray:
	var lines: PackedStringArray = _text().split("\n")
	lines.resize(lines.size() - 1)
	return lines


func _write_text(text: String) -> void:
	FileAccess.open(SaveService.LEDGER_PATH, FileAccess.WRITE).store_string(text)


func _append_raw(text: String) -> void:
	var file := FileAccess.open(SaveService.LEDGER_PATH, FileAccess.READ_WRITE if FileAccess.file_exists(SaveService.LEDGER_PATH) else FileAccess.WRITE)
	file.seek_end()
	file.store_string(text)
	file.close()


func _write_main(payload: Dictionary) -> void:
	var file := FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
