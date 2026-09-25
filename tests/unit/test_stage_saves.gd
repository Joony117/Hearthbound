extends GutTest

## ig-eek: the Early and Mid stage saves (SYSTEMS.md § Stage saves) load through the real SaveService,
## as play-early.cmd's and play-mid.cmd's games do. It runs in the normal suite, so a schema change
## that breaks a stage turns BUILT red. The counts are the bot's run logs
## (tests/fixtures/stages/README.md). Late's eviction check comes with its stage (ig-eek.2).

const Compare = preload("res://tests/unit/compare.gd")
const EARLY: String = "res://tests/fixtures/stages/early/"
const MID: String = "res://tests/fixtures/stages/mid/"


## Saves stay deferred, as in the other disk tests, so from_dict's roster_changed never writes the empty
## session over the stage; the test saves on purpose once.
func before_each() -> void:
	GameSession.set("_save_deferred_depth", 1)
	GameSession.from_dict({"roster": []})
	SaveService.load_blocked = false
	SaveService.take_load_notice()  # An earlier test's failed write leaves its notice behind.


func after_each() -> void:
	GameSession.from_dict({"roster": []})
	GameSession.set("_save_deferred_depth", 0)
	for path: String in [SaveService.SAVE_PATH, SaveService.LEDGER_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_early_loads_as_its_run_log_and_reloads_as_its_round_trip() -> void:
	_load_stage(EARLY)
	assert_eq(GameSession.roster.size(), 8, "the roster")
	assert_eq(str(GameSession.building_levels), "[0, 0, 0, 0, 0]", "the hall levels")
	assert_eq(GameSession.ledger.size(), 29, "the Ledger")
	assert_eq(GameSession.ledger_next_seq, 30, "nothing evicted")
	assert_true(GameSession.expedition_orders.is_empty(), "saved with no order in flight")
	assert_eq(GameSession.bond_index().size(), 0, "no bond yet: Early's battles had no moment")
	_reloads_as_its_round_trip()


## ig-eek.1: Mid's counts are seed 1's run log (RUN and CHECK "a bond").
func test_mid_loads_as_its_run_log_and_reloads_as_its_round_trip() -> void:
	_load_stage(MID)
	assert_eq(GameSession.roster.size(), 31, "the roster")
	assert_eq(str(GameSession.building_levels), "[0, 0, 0, 0, 0]", "the hall levels")
	assert_eq(GameSession.ledger.size(), 602, "the Ledger")
	assert_eq(GameSession.ledger_next_seq, 603, "nothing evicted")
	assert_true(GameSession.expedition_orders.is_empty(), "saved with no order in flight")
	assert_eq(GameSession.bond_index().size(), 5, "Mid's bonds")
	_reloads_as_its_round_trip()


func _load_stage(dir: String) -> void:
	for path: String in [SaveService.SAVE_PATH, SaveService.LEDGER_PATH]:
		assert_eq(DirAccess.copy_absolute(ProjectSettings.globalize_path(dir + path.get_file()), ProjectSettings.globalize_path(path)), OK, "copied %s" % path.get_file())
	assert_true(SaveService.load_game(), SaveService.load_block_reason)
	assert_false(SaveService.load_blocked, "not blocked")
	assert_eq(SaveService.take_load_notice(), "", "no warning")


func _reloads_as_its_round_trip() -> void:
	# ig-85w's standard (the director's ACC 4 ruling): the second load is exactly the first load's
	# full-precision round trip. Numbers compare by value (43 == 43.0), a float to the last bit.
	var first: Dictionary = GameSession.to_dict()
	var want: Dictionary = Compare.json_round_trip(first)
	var want_ledger: Array = JSON.parse_string(JSON.stringify(GameSession.ledger, "", true, true)) as Array
	GameSession.set("_save_deferred_depth", 0)
	assert_true(SaveService.save(), SaveService.last_write_error)
	GameSession.set("_save_deferred_depth", 1)
	GameSession.from_dict({"roster": []})
	assert_true(SaveService.load_game(), SaveService.load_block_reason)
	assert_eq(SaveService.take_load_notice(), "", "no warning on the reload")
	var got: Dictionary = GameSession.to_dict()
	# The re-save stamps its own time; everything else must come back.
	assert_true(float(got["saved_at_unix"]) >= float(first["saved_at_unix"]), "the re-save is newer")
	got.erase("saved_at_unix")
	want.erase("saved_at_unix")
	assert_eq(Compare.first_difference(got, want), "", "the reload is the round trip")
	assert_eq(Compare.first_difference(GameSession.ledger, want_ledger), "", "and so is its Ledger")
	# take_load_notice misses a dropped Ledger line: SaveService only warns about it.
	assert_push_warning_count(0, "no load warning")
	assert_push_error_count(0, "no load error")
