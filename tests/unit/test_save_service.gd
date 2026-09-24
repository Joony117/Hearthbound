extends GutTest

const HERO_NAME := "Refusal Aster"
const HERO_RANK := 3
const ITEM_DEF_ID := &"ring"
const ITEM_RANK := 2
const ITEM_ENHANCE_LEVEL := 4
const PARTS: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8]
const STONES := 987
const CLEARED_ZONE_ID := &"verdant_outskirts"

var _original_save_existed: bool = false
var _original_save_bytes: PackedByteArray


func before_all() -> void:
	_original_save_existed = FileAccess.file_exists(SaveService.SAVE_PATH)
	if not _original_save_existed:
		return
	var save_file: FileAccess = FileAccess.open(SaveService.SAVE_PATH, FileAccess.READ)
	assert_not_null(save_file)
	if save_file == null:
		return
	_original_save_bytes = save_file.get_buffer(save_file.get_length())
	save_file.close()


func after_all() -> void:
	SaveService.load_blocked = false
	SaveService.load_block_reason = ""
	SaveService.last_write_error = ""
	_remove_file_if_exists(SaveService.CORRUPT_PATH)
	_remove_temp_path()
	if not _original_save_existed:
		_remove_file_if_exists(SaveService.SAVE_PATH)
		return
	var save_file: FileAccess = FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	assert_not_null(save_file)
	if save_file == null:
		return
	save_file.store_buffer(_original_save_bytes)
	save_file.close()

	save_file = FileAccess.open(SaveService.SAVE_PATH, FileAccess.READ)
	assert_not_null(save_file)
	if save_file == null:
		return
	var restored_bytes: PackedByteArray = save_file.get_buffer(save_file.get_length())
	save_file.close()
	assert_eq(restored_bytes, _original_save_bytes)


func before_each() -> void:
	GameSession.set_process(false)
	SaveService.load_blocked = false
	SaveService.load_block_reason = ""
	SaveService.last_write_error = ""
	GameSession.from_dict({"roster": []})
	_remove_file_if_exists(SaveService.CORRUPT_PATH)
	_remove_temp_path()


func after_each() -> void:
	GameSession.set_process(true)


func test_failed_temp_write_preserves_existing_save() -> void:
	var original_bytes := "previous save".to_utf8_buffer()
	_write_save(SaveService.SAVE_PATH, original_bytes)
	var make_directory_error: Error = DirAccess.make_dir_absolute(SaveService.TMP_PATH)
	assert_eq(make_directory_error, OK)

	SaveService.save()

	assert_push_error("Save failed")
	assert_eq(_read_file_bytes(SaveService.SAVE_PATH), original_bytes)
	assert_eq(DirAccess.remove_absolute(SaveService.TMP_PATH), OK)


## Clearing the session in-memory autosaves over the file we are about to load, so the good bytes
## are captured first and restored after. This also pins the interlock the staged write introduced:
## load_game() -> from_dict() -> roster_changed -> save() renames over the path load_game() is
## reading, which fails outright if that read handle is still open.
func test_stale_temp_file_is_ignored_then_replaced() -> void:
	_set_distinctive_state()
	SaveService.save()
	var good_save_bytes := _read_file_bytes(SaveService.SAVE_PATH)
	GameSession.from_dict({"roster": []})
	_write_save(SaveService.SAVE_PATH, good_save_bytes)
	_write_save(SaveService.TMP_PATH, "stale".to_utf8_buffer())

	assert_true(SaveService.load_game())
	_assert_distinctive_state()
	SaveService.save()
	assert_false(FileAccess.file_exists(SaveService.TMP_PATH))
	var expected: Dictionary = JSON.parse_string(good_save_bytes.get_string_from_utf8()) as Dictionary
	var actual: Dictionary = JSON.parse_string(_read_file_bytes(SaveService.SAVE_PATH).get_string_from_utf8()) as Dictionary
	expected.erase("saved_at_unix")
	actual.erase("saved_at_unix")
	assert_eq(actual, expected)


func test_save_replaces_temp_file_with_session_state() -> void:
	_set_distinctive_state()
	SaveService.save()

	assert_false(FileAccess.file_exists(SaveService.TMP_PATH))
	# Save files are untrusted JSON, so their parser result remains Variant until shape-checked.
	var parsed: Variant = JSON.parse_string(_read_file_bytes(SaveService.SAVE_PATH).get_string_from_utf8())
	assert_true(parsed is Dictionary)
	var saved_state: Dictionary = parsed as Dictionary
	# JSON decodes every number as a float, the shape Item.int_field() absorbs on the way back in.
	assert_eq(int(saved_state.get("stones")), STONES)
	assert_eq(saved_state.get("cleared_zone_ids"), [str(CLEARED_ZONE_ID)])


func test_non_dictionary_save_is_refused_without_resetting_game_session() -> void:
	_set_distinctive_state()
	var corrupt_save_bytes := "[1, 2, 3]".to_utf8_buffer()
	var save_file: FileAccess = FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	assert_not_null(save_file)
	if save_file == null:
		return
	save_file.store_buffer(corrupt_save_bytes)
	save_file.close()

	assert_false(SaveService.load_game())
	assert_push_error("Save file is corrupt")
	assert_true(SaveService.load_blocked)
	assert_eq(_read_file_bytes(SaveService.SAVE_PATH), corrupt_save_bytes)
	assert_false(FileAccess.file_exists(SaveService.CORRUPT_PATH))
	_assert_distinctive_state()
	assert_ne(SaveService.take_load_notice(), "")
	assert_eq(SaveService.take_load_notice(), "")


func test_roster_change_after_corrupt_refusal_cannot_overwrite_canonical_save() -> void:
	var corrupt_save_bytes := "[1, 2, 3]".to_utf8_buffer()
	var save_file: FileAccess = FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	assert_not_null(save_file)
	if save_file == null:
		return
	save_file.store_buffer(corrupt_save_bytes)
	save_file.close()

	assert_false(SaveService.load_game())
	assert_push_error("Save file is corrupt")
	GameSession.add_hero(Hero.new(HERO_NAME, HERO_RANK))
	assert_false(SaveService.save())
	assert_eq(_read_file_bytes(SaveService.SAVE_PATH), corrupt_save_bytes)
	assert_false(FileAccess.file_exists(SaveService.CORRUPT_PATH))
	# SaveService outlives every test in this process, so an unread notice leaks into the next one.
	assert_ne(SaveService.take_load_notice(), "")


func test_corrupt_save_preserves_unrelated_old_corrupt_file_and_canonical_bytes() -> void:
	_write_save(SaveService.CORRUPT_PATH, "stale".to_utf8_buffer())
	var corrupt_save_bytes := "[4, 5, 6]".to_utf8_buffer()
	_write_save(SaveService.SAVE_PATH, corrupt_save_bytes)

	assert_false(SaveService.load_game())
	assert_push_error("Save file is corrupt")
	assert_eq(_read_file_bytes(SaveService.SAVE_PATH), corrupt_save_bytes)
	assert_eq(_read_file_bytes(SaveService.CORRUPT_PATH), "stale".to_utf8_buffer())
	assert_ne(SaveService.take_load_notice(), "")


func test_newer_version_save_is_refused_without_resetting_game_session() -> void:
	_set_distinctive_state()
	var newer_version_bytes := ('{"version": %d}' % (SaveService.SAVE_VERSION + 1)).to_utf8_buffer()
	var save_file: FileAccess = FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	assert_not_null(save_file)
	if save_file == null:
		return
	save_file.store_buffer(newer_version_bytes)
	save_file.close()

	assert_false(SaveService.load_game())
	assert_push_error("Save is from a newer build")
	assert_true(SaveService.load_blocked)
	_assert_distinctive_state()
	assert_false(FileAccess.file_exists(SaveService.CORRUPT_PATH))
	assert_eq(_read_file_bytes(SaveService.SAVE_PATH), newer_version_bytes)
	GameSession.add_hero(Hero.new("Must not persist", 0))
	assert_false(SaveService.save())
	assert_eq(_read_file_bytes(SaveService.SAVE_PATH), newer_version_bytes)


func test_explicit_invalid_version_blocks_load_and_preserves_canonical_bytes() -> void:
	var invalid_bytes := '{"version": null, "roster": []}'.to_utf8_buffer()
	_write_save(SaveService.SAVE_PATH, invalid_bytes)

	assert_false(SaveService.load_game())
	assert_push_error("Save version is invalid")
	assert_true(SaveService.load_blocked)
	assert_false(SaveService.save())
	assert_eq(_read_file_bytes(SaveService.SAVE_PATH), invalid_bytes)


func test_malformed_v2_blocks_followup_mutation_writes() -> void:
	var first := Hero.new("First", 0)
	first.def_id = &"knight"
	var second := Hero.new("Second", 0)
	second.def_id = &"rogue"
	second.instance_id = first.instance_id
	GameSession.from_dict({"roster": []})
	var invalid_state: Dictionary = GameSession.to_dict()
	invalid_state["roster"] = [first.to_dict(), second.to_dict()]
	var invalid_bytes: PackedByteArray = JSON.stringify(invalid_state).to_utf8_buffer()
	_write_save(SaveService.SAVE_PATH, invalid_bytes)

	assert_false(SaveService.load_game())
	assert_push_error("globally unique")
	assert_true(SaveService.load_blocked)
	GameSession.add_hero(Hero.new("Fresh default mutation", 0))
	assert_eq(_read_file_bytes(SaveService.SAVE_PATH), invalid_bytes)


func test_v2_order_remaining_time_cannot_exceed_its_initial_duration() -> void:
	var hero: Hero = _add_expedition_hero("Impossible Timer")
	var order_id: String = GameSession.dispatch_expedition(
		[hero.instance_id],
		"verdant_outskirts",
		2,
		"Impossible Timer",
	)
	assert_ne(order_id, "")
	var invalid_state: Dictionary = GameSession.to_dict()
	var orders: Array = invalid_state["expedition_orders"] as Array
	var order: Dictionary = orders[0] as Dictionary
	order["remaining_seconds"] = float(order["initial_duration_seconds"]) + 1.0
	var invalid_bytes: PackedByteArray = JSON.stringify(invalid_state).to_utf8_buffer()
	_write_save(SaveService.SAVE_PATH, invalid_bytes)

	assert_false(SaveService.load_game())
	assert_push_error("cannot exceed initial_duration_seconds")
	assert_true(SaveService.load_blocked)
	assert_false(SaveService.save())
	assert_eq(_read_file_bytes(SaveService.SAVE_PATH), invalid_bytes)


func test_v1_identity_migration_persists_once_and_reloads_same_ids() -> void:
	var legacy_state: Dictionary = {
		"version": 1,
		"roster": [{"name": "Legacy", "rank": 0, "def_id": "knight", "equipped": []}],
		"inventory": [{"def_id": "head", "rank": 0}],
		"turns": 7,
		"lost_caches": [{
			"hero_name": "Lost",
			"zone_id": "verdant_outskirts",
			"items": [{"def_id": "ring", "rank": 1}],
			"turn_lost": 2,
		}],
	}
	_write_save(SaveService.SAVE_PATH, JSON.stringify(legacy_state).to_utf8_buffer())

	assert_true(SaveService.load_game())
	var hero_id: String = GameSession.roster[0].instance_id
	var inventory_id: String = GameSession.inventory[0].instance_id
	var cache_item_id: String = GameSession.lost_caches[0].items[0].instance_id
	assert_false(hero_id.is_empty())
	assert_true(GameSession.recovery_clock_paused)
	assert_eq(GameSession.recovery_clock_seconds, 420.0)
	assert_eq(GameSession.lost_caches[0].recovery_created_at, 120.0)
	var migrated_bytes: PackedByteArray = _read_file_bytes(SaveService.SAVE_PATH)

	GameSession.from_dict({"roster": []})
	_write_save(SaveService.SAVE_PATH, migrated_bytes)
	assert_true(SaveService.load_game())
	assert_eq(GameSession.roster[0].instance_id, hero_id)
	assert_eq(GameSession.inventory[0].instance_id, inventory_id)
	assert_eq(GameSession.lost_caches[0].items[0].instance_id, cache_item_id)
	assert_true(GameSession.recovery_clock_paused)


func test_v2_inflight_order_round_trips_identity_favorite_preset_and_busy_state() -> void:
	var hero := Hero.new("Courier", 7)
	hero.def_id = &"knight"
	hero.level = 80
	hero.favorite = true
	GameSession.add_hero(hero)
	var item := Item.new(&"head", 2)
	item.favorite = true
	GameSession.add_item(item)
	var preset_id: String = GameSession.save_team_preset("", "Courier Team", [hero.instance_id], "verdant_outskirts")
	var order_id: String = GameSession.dispatch_expedition([hero.instance_id], "verdant_outskirts", 2, "Courier Team", preset_id)
	assert_ne(order_id, "")
	var good_bytes: PackedByteArray = _read_file_bytes(SaveService.SAVE_PATH)
	var hero_id: String = hero.instance_id
	var item_id: String = item.instance_id

	GameSession.from_dict({"roster": []})
	_write_save(SaveService.SAVE_PATH, good_bytes)
	assert_true(SaveService.load_game())
	var reloaded_hero: Hero = GameSession.hero_by_id(hero_id)
	assert_not_null(reloaded_hero)
	assert_true(reloaded_hero.favorite)
	assert_eq(GameSession.inventory[0].instance_id, item_id)
	assert_true(GameSession.inventory[0].favorite)
	assert_eq(GameSession.team_presets[0]["id"], preset_id)
	assert_eq(GameSession.expedition_orders[0]["id"], order_id)
	assert_true(GameSession.is_hero_busy(reloaded_hero))


func test_v2_inflight_order_applies_old_route_offline_once_then_persists_v3_battle_start() -> void:
	var hero: Hero = _add_expedition_hero("Legacy Courier")
	var preset_id: String = GameSession.save_team_preset("", "Legacy Team", [hero.instance_id], "verdant_outskirts")
	var order_id: String = GameSession.dispatch_expedition([hero.instance_id], "verdant_outskirts", 2, "Legacy Team", preset_id)
	assert_ne(order_id, "")
	var fixture: Dictionary = GameSession.to_dict()
	fixture["version"] = 2
	fixture.erase("supplies")
	fixture.erase("stranded_incidents")
	fixture.erase("rescue_clock_seconds")
	var order: Dictionary = (fixture["expedition_orders"] as Array)[0]
	for key: String in ["backend", "preset_ids", "squads", "battle", "phase", "loadout", "policies", "escrow", "last_command_error", "checkpoint_error", "incident_id"]:
		order.erase(key)
	var old_remaining: float = minf(float(order["initial_duration_seconds"]), 60.0)
	order["remaining_seconds"] = old_remaining
	fixture["saved_at_unix"] = Time.get_unix_time_from_system() - 10.0
	_write_save(SaveService.SAVE_PATH, JSON.stringify(fixture).to_utf8_buffer())
	_clear_session_without_saving()

	assert_true(SaveService.load_game())
	assert_eq(GameSession.expedition_orders[0]["backend"], "battle_v1")
	assert_almost_eq(float(GameSession.expedition_orders[0]["remaining_seconds"]), old_remaining - 10.0, 0.25)
	assert_eq(int((GameSession.expedition_orders[0]["battle"] as Dictionary)["tick"]), 0)
	var migrated_bytes: PackedByteArray = _read_file_bytes(SaveService.SAVE_PATH)
	_clear_session_without_saving()
	_write_save(SaveService.SAVE_PATH, migrated_bytes)
	assert_true(SaveService.load_game())
	assert_eq(int(GameSession.expedition_orders[0]["runs_completed"]), 0)
	assert_almost_eq(float(GameSession.expedition_orders[0]["remaining_seconds"]), old_remaining - 10.0, 0.5)


func test_offline_reload_completes_one_run_without_chaining_the_repeat() -> void:
	var hero: Hero = _add_expedition_hero("Offline Courier")
	var order_id: String = GameSession.dispatch_expedition(
		[hero.instance_id],
		"verdant_outskirts",
		2,
		"Offline Team",
	)
	assert_ne(order_id, "")
	var duration: float = float(GameSession.expedition_orders[0]["initial_duration_seconds"])
	var fixture: Dictionary = JSON.parse_string(
		_read_file_bytes(SaveService.SAVE_PATH).get_string_from_utf8()
	) as Dictionary
	fixture["saved_at_unix"] = Time.get_unix_time_from_system() - duration * 20.0
	_clear_session_without_saving()
	_write_save(SaveService.SAVE_PATH, JSON.stringify(fixture).to_utf8_buffer())

	assert_true(SaveService.load_game())
	assert_eq(GameSession.expedition_reports.size(), 1)
	assert_eq(GameSession.expedition_orders.size(), 1)
	assert_eq(GameSession.expedition_orders[0]["id"], order_id)
	assert_eq(int(GameSession.expedition_orders[0]["runs_completed"]), 1)
	assert_almost_eq(
		float(GameSession.expedition_orders[0]["remaining_seconds"]),
		float(GameSession.expedition_orders[0]["initial_duration_seconds"]),
		0.001,
	)
	var committed_bytes: PackedByteArray = _read_file_bytes(SaveService.SAVE_PATH)
	_clear_session_without_saving()
	_write_save(SaveService.SAVE_PATH, committed_bytes)
	assert_true(SaveService.load_game())
	assert_eq(GameSession.expedition_reports.size(), 1)
	assert_eq(int(GameSession.expedition_orders[0]["runs_completed"]), 1)


func test_failed_completion_save_rolls_back_then_replays_the_same_seed_once() -> void:
	var hero: Hero = _add_expedition_hero("Seeded Courier")
	var hero_id: String = hero.instance_id
	var order_id: String = GameSession.dispatch_expedition(
		[hero_id],
		"verdant_outskirts",
		1,
		"Seeded Team",
	)
	assert_ne(order_id, "")
	var order: Dictionary = GameSession.expedition_orders[0]
	var run_seed: int = int(order["run_seed"])
	(order["battle"] as Dictionary)["status"] = "victory"
	order["remaining_seconds"] = 0.0
	var zone: ZoneDefinition = ZoneDefinition.definition_for(&"verdant_outskirts")
	var expected_loot: Item = Expedition.roll_loot(zone, preload("res://balance.tres"), run_seed)
	var canonical_before: PackedByteArray = _read_file_bytes(SaveService.SAVE_PATH)
	var make_directory_error: Error = DirAccess.make_dir_absolute(SaveService.TMP_PATH)
	assert_eq(make_directory_error, OK)
	watch_signals(GameSession)

	GameSession.tick_expeditions(0.1)

	assert_push_error("Save failed")
	assert_ne(GameSession.last_action_error, "")
	assert_string_contains(GameSession.last_action_error, "Save failed")
	assert_eq(_read_file_bytes(SaveService.SAVE_PATH), canonical_before)
	assert_true(GameSession.expedition_reports.is_empty())
	assert_eq(GameSession.expedition_orders.size(), 1)
	assert_eq(GameSession.expedition_orders[0]["id"], order_id)
	assert_eq(GameSession.expedition_orders[0]["run_seed"], run_seed)
	assert_eq(GameSession.expedition_orders[0]["runs_completed"], 0)
	var rebuilt_hero: Hero = GameSession.hero_by_id(hero_id)
	assert_not_null(rebuilt_hero)
	assert_false(rebuilt_hero == hero, "Rollback rebuilds live objects and refreshes UI identity references.")
	assert_signal_emit_count(GameSession, "roster_changed", 1)
	assert_signal_emit_count(GameSession, "expeditions_changed", 1)
	assert_eq(DirAccess.remove_absolute(SaveService.TMP_PATH), OK)

	GameSession.tick_expeditions(0.1)

	assert_eq(GameSession.expedition_reports.size(), 1)
	assert_true(GameSession.expedition_orders.is_empty())
	assert_eq(GameSession.stones, GameSession.STARTING_STONES + zone.stone_reward)
	assert_eq(GameSession.inventory.size(), 1)
	assert_eq(GameSession.inventory[0].def_id, expected_loot.def_id)
	assert_eq(GameSession.inventory[0].rank, expected_loot.rank)
	var committed_bytes: PackedByteArray = _read_file_bytes(SaveService.SAVE_PATH)
	_clear_session_without_saving()
	_write_save(SaveService.SAVE_PATH, committed_bytes)
	assert_true(SaveService.load_game())
	assert_eq(GameSession.expedition_reports.size(), 1)
	assert_true(GameSession.expedition_orders.is_empty())


func test_failed_bulk_save_rolls_back_memory_and_preserves_the_canonical_file() -> void:
	var item := Item.new(&"head", 0)
	GameSession.add_item(item)
	var item_id: String = item.instance_id
	assert_true(SaveService.save())
	var canonical_before: PackedByteArray = _read_file_bytes(SaveService.SAVE_PATH)
	var plan: Dictionary = GameSession.preview_bulk_salvage([item_id], 1)
	assert_true(bool(plan["valid"]))
	assert_eq(DirAccess.make_dir_absolute(SaveService.TMP_PATH), OK)

	assert_false(GameSession.commit_bulk_plan(plan))
	assert_push_error("Save failed")
	assert_ne(GameSession.last_action_error, "")
	assert_string_contains(GameSession.last_action_error, "Save failed")
	assert_eq(_read_file_bytes(SaveService.SAVE_PATH), canonical_before)
	assert_not_null(GameSession.item_by_id(item_id))
	assert_eq(GameSession.parts[0], 0)
	assert_eq(DirAccess.remove_absolute(SaveService.TMP_PATH), OK)


func test_battle_policy_toggle_saves_and_reloads_matching_order_checkpoint() -> void:
	var hero: Hero = _add_expedition_hero("Policy Courier")
	var preset_id: String = GameSession.save_team_preset("", "Policy Team", [hero.instance_id], "verdant_outskirts")
	var order_id: String = GameSession.dispatch_force([preset_id], "verdant_outskirts", 1, {}, {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0})
	assert_ne(order_id, "")
	var result: Dictionary = GameSession.issue_battle_command(order_id, {"kind": BattleSimulation.COMMAND_SET_AUTO_BATTLE, "value": false})
	assert_true(bool(result["accepted"]))
	var saved_bytes: PackedByteArray = _read_file_bytes(SaveService.SAVE_PATH)
	var saved_payload: Dictionary = JSON.parse_string(saved_bytes.get_string_from_utf8()) as Dictionary
	assert_eq(GameSession.validate_saved_state(saved_payload, 3), "")
	_clear_session_without_saving()
	_write_save(SaveService.SAVE_PATH, saved_bytes)
	assert_true(SaveService.load_game())
	assert_false(bool((GameSession.get_battle_snapshot(order_id)["policies"] as Dictionary)["auto_battle"]))


func test_periodic_checkpoint_failure_freezes_current_state_and_retries_without_erasing_durable_profile_changes() -> void:
	var hero: Hero = _add_expedition_hero("Checkpoint Courier")
	var preset_id: String = GameSession.save_team_preset("", "Checkpoint Team", [hero.instance_id], "verdant_outskirts")
	var order_id: String = GameSession.dispatch_force([preset_id], "verdant_outskirts", 1, {}, {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0})
	assert_ne(order_id, "")
	var durable_item := Item.new(&"ring", 0)
	GameSession.add_item(durable_item)
	assert_true(SaveService.save())
	GameSession.tick_expeditions(1.0)
	assert_eq(DirAccess.make_dir_absolute(SaveService.TMP_PATH), OK)
	GameSession.set("_periodic_save_accumulator", GameSession.PERIODIC_SAVE_SECONDS - 0.1)

	GameSession._process(0.25)

	assert_push_error("Save failed")
	assert_not_null(GameSession.item_by_id(durable_item.instance_id))
	var frozen_snapshot: Dictionary = GameSession.get_battle_snapshot(order_id)
	assert_ne(str(frozen_snapshot["checkpoint_error"]), "")
	GameSession._process(1.0)
	assert_eq(GameSession.get_battle_snapshot(order_id)["tick"], frozen_snapshot["tick"])
	var rejected: Dictionary = GameSession.issue_battle_command(order_id, {"kind": BattleSimulation.COMMAND_SET_AUTO_BATTLE, "value": false})
	assert_false(bool(rejected["accepted"]))
	assert_eq(DirAccess.remove_absolute(SaveService.TMP_PATH), OK)
	GameSession.set("_periodic_save_accumulator", GameSession.PERIODIC_SAVE_SECONDS - 0.1)
	GameSession._process(0.25)
	assert_eq(str(GameSession.get_battle_snapshot(order_id)["checkpoint_error"]), "")
	var retried_payload: Dictionary = JSON.parse_string(_read_file_bytes(SaveService.SAVE_PATH).get_string_from_utf8()) as Dictionary
	assert_eq(GameSession.validate_saved_state(retried_payload, 3), "")
	assert_eq(str(((retried_payload["inventory"] as Array)[0] as Dictionary)["instance_id"]), durable_item.instance_id)
	assert_eq(int((((retried_payload["expedition_orders"] as Array)[0] as Dictionary)["battle"] as Dictionary)["tick"]), int(GameSession.get_battle_snapshot(order_id)["tick"]))


func test_failed_force_dispatch_and_manual_command_preserve_canonical_bytes_and_battle_state() -> void:
	var hero: Hero = _add_expedition_hero("Atomic Courier")
	var preset_id: String = GameSession.save_team_preset("", "Atomic Team", [hero.instance_id], "verdant_outskirts")
	assert_true(SaveService.save())
	var before_dispatch: PackedByteArray = _read_file_bytes(SaveService.SAVE_PATH)
	assert_eq(DirAccess.make_dir_absolute(SaveService.TMP_PATH), OK)
	var refused_order: String = GameSession.dispatch_force([preset_id], "verdant_outskirts", 1, {}, {"healing": 1, "revival": 0, "keep_healing": 0, "keep_revival": 0})
	assert_push_error("Save failed")
	assert_eq(refused_order, "")
	assert_true(GameSession.expedition_orders.is_empty())
	assert_eq(GameSession.supplies, {"healing": 3, "revival": 1})
	assert_eq(_read_file_bytes(SaveService.SAVE_PATH), before_dispatch)
	assert_eq(DirAccess.remove_absolute(SaveService.TMP_PATH), OK)
	var order_id: String = GameSession.dispatch_force([preset_id], "verdant_outskirts", 1, {}, {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0})
	assert_ne(order_id, "")
	var before_command: Dictionary = GameSession.get_battle_snapshot(order_id)
	var canonical_before_command: PackedByteArray = _read_file_bytes(SaveService.SAVE_PATH)
	assert_eq(DirAccess.make_dir_absolute(SaveService.TMP_PATH), OK)
	var rejected: Dictionary = GameSession.issue_battle_command(order_id, {"kind": BattleSimulation.COMMAND_SET_AUTO_BATTLE, "value": false})
	assert_push_error("Save failed")
	assert_false(bool(rejected["accepted"]))
	var after_command: Dictionary = GameSession.get_battle_snapshot(order_id)
	for transient_key: String in ["last_command_error", "checkpoint_error"]:
		before_command.erase(transient_key)
		after_command.erase(transient_key)
	assert_eq(after_command, before_command)
	assert_eq(_read_file_bytes(SaveService.SAVE_PATH), canonical_before_command)
	assert_eq(DirAccess.remove_absolute(SaveService.TMP_PATH), OK)


func test_failed_battle_settlement_rolls_back_refund_then_retry_refunds_once() -> void:
	var hero: Hero = _add_expedition_hero("Refund Courier")
	var preset_id: String = GameSession.save_team_preset("", "Refund Team", [hero.instance_id], "verdant_outskirts")
	var order_id: String = GameSession.dispatch_force([preset_id], "verdant_outskirts", 1, {}, {"healing": 1, "revival": 0, "keep_healing": 0, "keep_revival": 0})
	assert_ne(order_id, "")
	var order: Dictionary = GameSession.expedition_orders[0]
	(order["battle"] as Dictionary)["status"] = "victory"
	(order["battle"] as Dictionary)["supplies_remaining"] = {"healing": 1, "revival": 0}
	order["phase"] = "returning"
	order["remaining_seconds"] = 0.0
	assert_true(SaveService.save())
	var canonical_before: PackedByteArray = _read_file_bytes(SaveService.SAVE_PATH)
	assert_eq(DirAccess.make_dir_absolute(SaveService.TMP_PATH), OK)
	GameSession.tick_expeditions(0.1)
	assert_push_error("Save failed")
	assert_eq(GameSession.supplies["healing"], 2)
	assert_eq(GameSession.expedition_orders.size(), 1)
	assert_true(GameSession.expedition_reports.is_empty())
	assert_eq(_read_file_bytes(SaveService.SAVE_PATH), canonical_before)
	assert_eq(DirAccess.remove_absolute(SaveService.TMP_PATH), OK)
	GameSession.tick_expeditions(0.1)
	assert_eq(GameSession.supplies["healing"], 3)
	assert_true(GameSession.expedition_orders.is_empty())
	assert_eq(GameSession.expedition_reports.size(), 1)


func test_every_summonable_archetype_survives_a_battle_save_and_reload() -> void:
	for def_id: String in Summon.ARCHETYPE_DEF_IDS:
		GameSession.from_dict({"roster": []})
		var hero: Hero = _add_expedition_hero("Deployed %s" % def_id)
		hero.def_id = StringName(def_id)
		var preset_id: String = GameSession.save_team_preset("", "Deployed", [hero.instance_id], "verdant_outskirts")
		var order_id: String = GameSession.dispatch_force([preset_id], "verdant_outskirts", 1, {}, {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0})
		assert_ne(order_id, "", "%s dispatches" % def_id)
		assert_true(SaveService.save(), "%s saves" % def_id)
		assert_true(SaveService.load_game(), "%s reloads" % def_id)
		assert_false(SaveService.load_blocked, "%s does not block the next load" % def_id)
	assert_push_error_count(0)


func test_rescue_of_a_hero_downed_by_real_damage_survives_save_and_reload() -> void:
	var rescue_order_id: String = _strand_and_dispatch_rescue()
	var rescue: Dictionary = GameSession.get_battle_snapshot(rescue_order_id)
	assert_eq(int(rescue["tick"]), 0)
	for actor: Variant in rescue["actors"]:
		for key: String in TIMESTAMP_KEYS:
			assert_eq(int((actor as Dictionary)["effect_state"][key]), 0, "%s restarts with the rescue" % key)
	assert_true(SaveService.save(), "the rescue saves at its first tick")
	assert_true(SaveService.load_game(), "and reloads")
	assert_false(SaveService.load_blocked)
	assert_false(GameSession.get_battle_snapshot(rescue_order_id).is_empty())
	assert_push_error_count(0)


func test_a_rescue_saved_with_timestamps_ahead_of_its_tick_is_repaired_on_load() -> void:
	var rescue_order_id: String = _strand_and_dispatch_rescue()
	assert_true(SaveService.save())
	# The shape a rescue saved before ig-4zi has: its actors still carry their old battle's ticks.
	var stuck: Dictionary = JSON.parse_string(_read_file_bytes(SaveService.SAVE_PATH).get_string_from_utf8())
	for raw_order: Variant in stuck["expedition_orders"]:
		if str((raw_order as Dictionary)["id"]) == rescue_order_id:
			_push_ticks_ahead((raw_order as Dictionary)["battle"])
	_write_save(SaveService.SAVE_PATH, JSON.stringify(stuck).to_utf8_buffer())

	assert_true(SaveService.load_game(), "the stuck save loads")
	_assert_ticks_within(GameSession.get_battle_snapshot(rescue_order_id))
	assert_push_error_count(0)


func test_an_incident_rebuilt_from_a_stranded_rescue_is_repaired_on_load() -> void:
	var rescue_order_id: String = _strand_and_dispatch_rescue(true)
	for _second: int in 300:
		if GameSession.stranded_incidents.is_empty() or str(GameSession.stranded_incidents[0].get("active_rescue_order_id", "")).is_empty():
			break
		GameSession.tick_expeditions(1.0)
	assert_ne(rescue_order_id, "")
	assert_eq(GameSession.stranded_incidents.size(), 1, "the failed rescue leaves one incident")
	if GameSession.stranded_incidents.is_empty():
		return
	assert_eq(str(GameSession.stranded_incidents[0]["active_rescue_order_id"]), "", "the rescue settled")
	assert_eq(str(GameSession.stranded_incidents[0]["battle_snapshot"]["kind"]), "rescue", "rebuilt from the rescue")
	assert_true(SaveService.save())
	var stuck: Dictionary = JSON.parse_string(_read_file_bytes(SaveService.SAVE_PATH).get_string_from_utf8())
	_push_ticks_ahead((stuck["stranded_incidents"] as Array)[0]["battle_snapshot"])
	_write_save(SaveService.SAVE_PATH, JSON.stringify(stuck).to_utf8_buffer())

	assert_true(SaveService.load_game(), "the stuck incident loads")
	_assert_ticks_within(GameSession.stranded_incidents[0]["battle_snapshot"])
	assert_push_error_count(0)


func test_passions_and_xp_survive_a_disk_round_trip() -> void:
	var hero := Hero.new("Smith", 0)
	# Not the derived pair, so a loader that ignores the saved one fails here.
	var passions: Array[StringName] = [&"mining", &"tracking"]
	if hero.passions == passions:
		passions = [&"farming", &"rites"]
	hero.passions = passions
	# Woodcutting, mining and farming have no hall, but their XP must still survive a load.
	hero.profession_xp = {&"smithing": 18000.0, &"alchemy": 90.5, &"woodcutting": 60.0, &"mining": 1.5, &"farming": 7.0}
	GameSession.add_hero(hero)
	assert_true(SaveService.save())

	_reload_from_disk()
	var reloaded: Hero = GameSession.hero_by_id(hero.instance_id)
	assert_eq(reloaded.passions, passions)
	assert_eq(reloaded.profession_xp, hero.profession_xp)


## Boundary #1: a file as the calling build wrote it (a "calling", no "passions") and an older one
## with neither. The calling stays the first passion, and the next save writes "passions" only.
func test_a_calling_save_on_disk_migrates_to_passions_and_reloads_identically() -> void:
	var smith := Hero.new("Smith", 0)
	var elder := Hero.new("Elder", 0)
	GameSession.add_hero(smith)
	GameSession.add_hero(elder)
	var state: Dictionary = GameSession.to_dict()
	state["version"] = SaveService.SAVE_VERSION
	for entry: Dictionary in state["roster"]:
		entry.erase("passions")
	# A calling the hash would not pick first, so a loader that ignores it fails here.
	var calling: StringName = &"rites" if Hero.passions_for(smith.instance_id)[0] != &"rites" else &"alchemy"
	state["roster"][0]["calling"] = str(calling)
	state["roster"][1].erase("profession_xp")
	GameSession.from_dict({"roster": []})
	_write_save(SaveService.SAVE_PATH, JSON.stringify(state).to_utf8_buffer())
	assert_true(SaveService.load_game())
	var migrated: Hero = GameSession.hero_by_id(smith.instance_id)
	assert_eq(migrated.passions, [calling, Hero._second_passion(smith.instance_id, calling)] as Array[StringName])
	var derived: Array[StringName] = GameSession.hero_by_id(elder.instance_id).passions
	assert_eq(derived, Hero.passions_for(elder.instance_id))
	assert_true(SaveService.save())
	var on_disk: Dictionary = JSON.parse_string(_read_file_bytes(SaveService.SAVE_PATH).get_string_from_utf8()) as Dictionary
	for entry: Dictionary in on_disk["roster"]:
		assert_false(entry.has("calling"), "the resave drops calling")
	assert_eq(on_disk["roster"][0]["passions"], [str(migrated.passions[0]), str(migrated.passions[1])])
	on_disk.erase("saved_at_unix")

	_reload_from_disk()
	assert_eq(GameSession.hero_by_id(smith.instance_id).passions, migrated.passions)
	assert_eq(GameSession.hero_by_id(elder.instance_id).passions, derived)
	assert_true(SaveService.save())
	var resaved: Dictionary = JSON.parse_string(_read_file_bytes(SaveService.SAVE_PATH).get_string_from_utf8()) as Dictionary
	resaved.erase("saved_at_unix")
	assert_eq(resaved, on_disk, "a second load and save changes nothing")
	assert_push_warning_count(0)


func test_the_embodied_hero_survives_a_disk_round_trip() -> void:
	var walker := Hero.new("Walker", 0)
	GameSession.add_hero(walker)
	GameSession.add_hero(Hero.new("Bystander", 0))
	assert_true(GameSession.embody_hero(walker.instance_id))
	assert_true(SaveService.save())
	var on_disk: Dictionary = JSON.parse_string(_read_file_bytes(SaveService.SAVE_PATH).get_string_from_utf8()) as Dictionary
	assert_eq(on_disk["embodied_hero_id"], walker.instance_id)

	# _reload_from_disk inlined, so the cleared state is checked: the body must come from the file.
	var saved_bytes: PackedByteArray = _read_file_bytes(SaveService.SAVE_PATH)
	GameSession.from_dict({"roster": []})
	assert_eq(GameSession.embodied_hero_id, GameSession.NO_BODY, "clearing drops the body")
	_write_save(SaveService.SAVE_PATH, saved_bytes)
	assert_true(SaveService.load_game())
	assert_eq(GameSession.embodied_hero_id, walker.instance_id)
	assert_true(GameSession.is_embodied(GameSession.hero_by_id(walker.instance_id)))
	assert_push_error_count(0)


func test_a_save_without_a_body_loads_with_none_and_no_complaint() -> void:
	var hero := Hero.new("Elder", 0)
	GameSession.add_hero(hero)
	var state: Dictionary = GameSession.to_dict()
	state["version"] = SaveService.SAVE_VERSION
	state.erase("embodied_hero_id")
	# A body in memory before the load, so only the load itself can leave none.
	assert_true(GameSession.embody_hero(hero.instance_id))
	_write_save(SaveService.SAVE_PATH, JSON.stringify(state).to_utf8_buffer())
	assert_true(SaveService.load_game())
	assert_not_null(GameSession.hero_by_id(hero.instance_id))
	assert_eq(GameSession.embodied_hero_id, GameSession.NO_BODY)
	assert_push_error_count(0)
	assert_push_warning_count(0)


func test_a_failed_save_rolls_back_embody_and_step_out() -> void:
	var walker := Hero.new("Walker", 0)
	GameSession.add_hero(walker)
	assert_true(SaveService.save())
	var before: PackedByteArray = _read_file_bytes(SaveService.SAVE_PATH)
	assert_eq(DirAccess.make_dir_absolute(SaveService.TMP_PATH), OK)
	assert_false(GameSession.embody_hero(walker.instance_id))
	assert_push_error("Save failed")
	assert_eq(GameSession.embodied_hero_id, GameSession.NO_BODY, "the failed embody is undone")
	assert_ne(GameSession.last_action_error, "")
	assert_eq(_read_file_bytes(SaveService.SAVE_PATH), before)
	assert_eq(DirAccess.remove_absolute(SaveService.TMP_PATH), OK)

	assert_true(GameSession.embody_hero(walker.instance_id))
	var embodied: PackedByteArray = _read_file_bytes(SaveService.SAVE_PATH)
	assert_eq(DirAccess.make_dir_absolute(SaveService.TMP_PATH), OK)
	assert_false(GameSession.step_out())
	assert_push_error("Save failed")
	assert_eq(GameSession.embodied_hero_id, walker.instance_id, "the failed step out is undone")
	assert_eq(_read_file_bytes(SaveService.SAVE_PATH), embodied)
	assert_eq(DirAccess.remove_absolute(SaveService.TMP_PATH), OK)


func test_a_failed_save_rolls_back_hero_and_item_favorites() -> void:
	var hero := Hero.new("Keeper", 0)
	GameSession.add_hero(hero)
	var item := Item.new(&"head", 2)
	GameSession.add_item(item)
	assert_true(SaveService.save())
	var before: PackedByteArray = _read_file_bytes(SaveService.SAVE_PATH)
	assert_eq(DirAccess.make_dir_absolute(SaveService.TMP_PATH), OK)
	assert_false(GameSession.set_hero_favorite(hero, true))
	assert_push_error("Save failed")
	assert_ne(GameSession.last_action_error, "")
	assert_false(GameSession.set_item_favorite(GameSession.inventory[0], true))
	assert_push_error("Save failed")
	assert_ne(GameSession.last_action_error, "")
	assert_false(GameSession.hero_by_id(hero.instance_id).favorite, "the failed hero favorite is undone")
	assert_false(GameSession.inventory[0].favorite, "the failed item favorite is undone")
	assert_eq(_read_file_bytes(SaveService.SAVE_PATH), before)
	assert_eq(DirAccess.remove_absolute(SaveService.TMP_PATH), OK)

	SaveService.load_blocked = true
	SaveService.load_block_reason = "Blocked for the test."
	assert_false(GameSession.set_hero_favorite(GameSession.hero_by_id(hero.instance_id), true))
	assert_eq(GameSession.last_action_error, "Blocked for the test.")
	assert_false(GameSession.set_item_favorite(GameSession.inventory[0], false), "even a no-op is refused")
	SaveService.load_blocked = false
	SaveService.load_block_reason = ""

	assert_true(GameSession.set_hero_favorite(GameSession.hero_by_id(hero.instance_id), true))
	assert_true(GameSession.set_item_favorite(GameSession.inventory[0], true))
	_reload_from_disk()
	assert_true(GameSession.hero_by_id(hero.instance_id).favorite, "a saved hero favorite survives reload")
	assert_true(GameSession.inventory[0].favorite, "a saved item favorite survives reload")
	assert_false(GameSession.set_item_favorite(Item.new(&"head", 2), true), "a stranger item is refused")
	assert_ne(GameSession.last_action_error, "")


## Clearing the session autosaves over the file, so the saved bytes are put back before loading.
func _reload_from_disk() -> void:
	var saved_bytes: PackedByteArray = _read_file_bytes(SaveService.SAVE_PATH)
	GameSession.from_dict({"roster": []})
	_write_save(SaveService.SAVE_PATH, saved_bytes)
	assert_true(SaveService.load_game())


func test_missing_save_is_refused_without_error() -> void:
	_remove_file_if_exists(SaveService.SAVE_PATH)

	assert_false(SaveService.load_game())
	assert_push_error_count(0)


func _remove_file_if_exists(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var remove_error: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_eq(remove_error, OK)


func _remove_temp_path() -> void:
	if FileAccess.file_exists(SaveService.TMP_PATH):
		_remove_file_if_exists(SaveService.TMP_PATH)
		return
	if DirAccess.dir_exists_absolute(SaveService.TMP_PATH):
		var remove_error: Error = DirAccess.remove_absolute(SaveService.TMP_PATH)
		assert_eq(remove_error, OK)


func _write_save(path: String, bytes: PackedByteArray) -> void:
	var save_file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(save_file)
	if save_file == null:
		return
	save_file.store_buffer(bytes)
	save_file.close()


func _read_file_bytes(path: String) -> PackedByteArray:
	var save_file: FileAccess = FileAccess.open(path, FileAccess.READ)
	assert_not_null(save_file)
	if save_file == null:
		return PackedByteArray()
	var bytes := save_file.get_buffer(save_file.get_length())
	save_file.close()
	return bytes


func _clear_session_without_saving() -> void:
	GameSession.set("_save_deferred_depth", 1)
	GameSession.from_dict({"roster": []})
	GameSession.set("_save_deferred_depth", 0)


const TIMESTAMP_KEYS: Array[String] = ["last_hit_tick", "last_skill_tick", "last_crit_tick"]


# Strands a hero downed by real damage, not a hand-edited dict, then dispatches its rescue.
# A weak rescuer strands too, so the incident is rebuilt from the rescue battle.
func _strand_and_dispatch_rescue(weak_rescuer: bool = false) -> String:
	GameSession.cleared_zone_ids = {&"verdant_outskirts": true, &"ashfall_reaches": true}
	var victim := Hero.new("Doomed", 0)
	victim.def_id = &"mage"
	victim.level = 0
	GameSession.add_hero(victim)
	var loadout: Dictionary = {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0}
	var doomed_preset: String = GameSession.save_team_preset("", "Doomed", [victim.instance_id], "sundered_vault")
	assert_ne(GameSession.dispatch_force([doomed_preset], "sundered_vault", 1, {}, loadout), "")
	for _second: int in 300:
		if not GameSession.stranded_incidents.is_empty():
			break
		GameSession.tick_expeditions(1.0)
	assert_eq(GameSession.stranded_incidents.size(), 1, "the victim strands")
	if GameSession.stranded_incidents.is_empty():
		return ""
	var incident: Dictionary = GameSession.stranded_incidents[0]
	var downed: Dictionary = ((incident["battle_snapshot"] as Dictionary)["actors"] as Array)[0]
	assert_gt(int((downed["effect_state"] as Dictionary)["last_hit_tick"]), 0, "downed by real damage")
	var rescuer: Hero
	if weak_rescuer:
		rescuer = Hero.new("Weak Rescuer", 0)
		rescuer.def_id = &"mage"
		rescuer.level = 0
		GameSession.add_hero(rescuer)
	else:
		rescuer = _add_expedition_hero("Rescuer")
	var rescue_preset: String = GameSession.save_team_preset("", "Rescue", [rescuer.instance_id], "sundered_vault")
	var rescue_order_id: String = GameSession.dispatch_rescue(str(incident["id"]), rescue_preset, loadout)
	assert_ne(rescue_order_id, "", GameSession.last_action_error)
	if weak_rescuer:
		# A level-0 rescuer still wins about 1 run in 40 on a random seed (ig-qjh); at 1 HP it
		# cannot. Each tick reloads the battle from the order, so the pin holds.
		for order: Dictionary in GameSession.expedition_orders:
			if str(order["id"]) == rescue_order_id:
				for actor: Variant in (order["battle"] as Dictionary)["actors"]:
					if str((actor as Dictionary).get("hero_id", "")) == rescuer.instance_id:
						(actor as Dictionary)["hp"] = 1.0
	return rescue_order_id


# Puts every timestamp on the first ally and the first enemy ahead of the battle's tick.
func _push_ticks_ahead(battle: Dictionary) -> void:
	var ahead: int = int(battle["tick"]) + 40
	for faction: String in ["ally", "enemy"]:
		for raw_actor: Variant in battle["actors"]:
			if str((raw_actor as Dictionary)["faction"]) == faction:
				for key: String in TIMESTAMP_KEYS:
					((raw_actor as Dictionary)["effect_state"] as Dictionary)[key] = ahead
				break


func _assert_ticks_within(battle: Dictionary) -> void:
	assert_false((battle.get("actors", []) as Array).is_empty())
	for raw_actor: Variant in battle.get("actors", []):
		for key: String in TIMESTAMP_KEYS:
			assert_lte(int((raw_actor as Dictionary)["effect_state"][key]), int(battle["tick"]), "%s clamped to the battle's tick" % key)


func _add_expedition_hero(hero_name: String) -> Hero:
	var hero := Hero.new(hero_name, 7)
	hero.def_id = &"knight"
	hero.level = 80
	GameSession.add_hero(hero)
	return hero


func _expected_loot(run_seed: int, zone: ZoneDefinition) -> Item:
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed
	var boss_loot_seed: int = 0
	for _wave_index: int in range(zone.trash_wave_count + 1):
		rng.randf()
		boss_loot_seed = rng.randi()
	return Expedition.roll_loot(zone, preload("res://balance.tres"), boss_loot_seed)


func _set_distinctive_state() -> void:
	var hero := Hero.new(HERO_NAME, HERO_RANK)
	hero.def_id = &"rogue"
	GameSession.add_hero(hero)
	var item := Item.new(ITEM_DEF_ID, ITEM_RANK)
	item.enhance_level = ITEM_ENHANCE_LEVEL
	GameSession.add_item(item)
	GameSession.parts = PARTS.duplicate()
	GameSession.stones = STONES
	GameSession.mark_zone_cleared(CLEARED_ZONE_ID)


func _assert_distinctive_state() -> void:
	assert_eq(GameSession.roster.size(), 1)
	var hero: Hero = GameSession.roster[0]
	assert_eq(hero.hero_name, HERO_NAME)
	assert_eq(hero.rank, HERO_RANK)
	assert_eq(hero.def_id, &"rogue")
	assert_eq(GameSession.inventory.size(), 1)
	var item: Item = GameSession.inventory[0]
	assert_eq(item.def_id, ITEM_DEF_ID)
	assert_eq(item.rank, ITEM_RANK)
	assert_eq(item.enhance_level, ITEM_ENHANCE_LEVEL)
	assert_eq(GameSession.parts, PARTS)
	assert_eq(GameSession.stones, STONES)
	assert_true(GameSession.cleared_zone_ids.has(CLEARED_ZONE_ID))
