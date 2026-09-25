extends GutTest
## ig-7sn.12: a load runs no sim. Each active battle owes its offline seconds as catch_up_seconds; the
## pulse sends one job per owed order, and the round commits once every job in it is in (DECISIONS.md
## 2026-09-25 "Battle sim threading", item 8).

const OWED: float = 20.0
const LOADOUT: Dictionary = {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0}


func before_each() -> void:
	_clear_session_without_saving()
	GameSession.last_action_error = ""
	SaveService.load_blocked = false
	for zone_id: StringName in [&"verdant_outskirts", &"ashfall_reaches", &"sundered_vault", &"fallen_citadel", &"frontier_march"]:
		GameSession.cleared_zone_ids[zone_id] = true


func after_each() -> void:
	_clear_session_without_saving()


func test_the_load_owes_the_seconds_and_the_round_lands_the_synchronous_advance() -> void:
	var verdant: String = _dispatch("verdant_outskirts", 5)
	var citadel: String = _dispatch("fallen_citadel", 30)
	var before: Dictionary = {}
	var expected: Dictionary = {}
	for order: Dictionary in GameSession.expedition_orders:
		before[order["id"]] = order["battle"]
		var state := BattleState.from_dict((order["battle"] as Dictionary).duplicate(true))
		BattleSimulation.advance(state, OWED)
		expected[order["id"]] = state.to_dict()
	GameSession.saved_at_unix = 1000.0
	GameSession.apply_offline_expedition_progress(1000.0 + OWED)
	for order: Dictionary in GameSession.expedition_orders:
		assert_true(is_same(order["battle"], before[order["id"]]), "the load ran no sim")
		assert_eq(float(order["catch_up_seconds"]), OWED)
	# The first pulse stops both clocks and sends one job each.
	GameSession.tick_expeditions(0.25)
	for order: Dictionary in GameSession.expedition_orders:
		assert_true(is_same(order["battle"], before[order["id"]]), "a catching-up battle's clock is stopped")
		assert_true(GameSession.get_battle_snapshot(order["id"])["catching_up"])
	assert_eq(GameSession._battle_jobs.size(), 2)
	# One round: verdant's job alone landing commits nothing.
	var small: BattleJob = GameSession._battle_checks[verdant]["catch_up"]
	var big: BattleJob = GameSession._battle_checks[citadel]["catch_up"]
	while not WorkerThreadPool.is_task_completed(small.task_id):
		OS.delay_msec(1)
	if not WorkerThreadPool.is_task_completed(big.task_id):
		GameSession._land_battle_checks()
		assert_true(GameSession.expedition_orders[GameSession._order_index(verdant)].has("catch_up_seconds"), "the round waits for its slowest job")
	_land_catch_ups()
	for order: Dictionary in GameSession.expedition_orders:
		assert_false(order.has("catch_up_seconds"))
		assert_true(var_to_bytes(order["battle"]) == var_to_bytes(expected[order["id"]]), "%s: the job's battle == advance by the same seconds" % order["zone_id"])
		if str((order["battle"] as Dictionary)["status"]) != "active":
			assert_true(str(order["phase"]) in ["returning", "checking"], "%s: the landing did what the load's advance did" % order["zone_id"])
	assert_false(GameSession.get_battle_snapshot(verdant)["catching_up"])


func test_a_save_mid_catch_up_reloads_owing_the_same_and_ends_where_an_uninterrupted_one_does() -> void:
	var order_id: String = _dispatch("fallen_citadel", 30)
	# A save from before the key: it loads owing only its time away.
	var legacy: Dictionary = _read_save()
	assert_false(JSON.stringify(legacy).contains("catch_up_seconds"))
	legacy["saved_at_unix"] = Time.get_unix_time_from_system() - OWED
	_clear_session_without_saving()
	_write_save(legacy)
	assert_true(SaveService.load_game(), SaveService.load_block_reason)
	var order: Dictionary = GameSession.expedition_orders[0]
	var owed: float = float(order["catch_up_seconds"])
	assert_between(owed, OWED, OWED + 5.0, "the legacy save caught up its time away")
	var battle: Dictionary = (order["battle"] as Dictionary).duplicate(true)
	var uninterrupted := BattleState.from_dict(battle.duplicate(true))
	BattleSimulation.advance(uninterrupted, owed)
	# Mid catch-up: the job is out when the save is taken.
	GameSession.tick_expeditions(0.01)
	assert_eq(GameSession._battle_jobs.size(), 1)
	assert_true(SaveService.save(), SaveService.last_write_error)
	var saved: Dictionary = _read_save()
	assert_eq(float(saved["expedition_orders"][0]["catch_up_seconds"]), owed, "the save holds what is owed")
	# Reloaded with no time away: the load cancels the job, and the order owes the same.
	saved["saved_at_unix"] = Time.get_unix_time_from_system() + 3600.0
	_clear_session_without_saving()
	assert_true(GameSession._battle_jobs.is_empty(), "the reload stopped the job")
	_write_save(saved)
	assert_true(SaveService.load_game(), SaveService.load_block_reason)
	order = GameSession.expedition_orders[GameSession._order_index(order_id)]
	assert_eq(float(order["catch_up_seconds"]), owed)
	assert_eq(order["battle"], battle, "the battle as saved")
	_land_catch_ups()
	assert_false(order.has("catch_up_seconds"))
	assert_true(var_to_bytes(order["battle"]) == var_to_bytes(uninterrupted.to_dict()), "the same to_dict() as an uninterrupted catch-up")


func test_a_bad_catch_up_value_loads_as_zero() -> void:
	_dispatch("verdant_outskirts", 5)
	for bad: Variant in [-5.0, "abc", [1.0]]:
		var data: Dictionary = _read_save()
		data["expedition_orders"][0]["catch_up_seconds"] = bad
		data["saved_at_unix"] = Time.get_unix_time_from_system() + 3600.0
		_clear_session_without_saving()
		_write_save(data)
		assert_true(SaveService.load_game(), "%s: %s" % [str(bad), SaveService.load_block_reason])
		var order: Dictionary = GameSession.expedition_orders[0]
		assert_false(order.has("catch_up_seconds"), "%s loads as 0" % str(bad))
		var elapsed: float = float((order["battle"] as Dictionary)["elapsed_seconds"])
		GameSession.tick_expeditions(0.25)
		assert_gt(float((order["battle"] as Dictionary)["elapsed_seconds"]), elapsed, "%s: its clock runs" % str(bad))
		assert_true(SaveService.save(), SaveService.last_write_error)


func test_catch_up_on_a_battle_that_is_over_loads_as_zero_and_never_settles_twice() -> void:
	var order_id: String = _dispatch("verdant_outskirts", 5)
	var order: Dictionary = GameSession.expedition_orders[0]
	(order["battle"] as Dictionary)["status"] = "victory"
	order["remaining_seconds"] = 0.0
	GameSession.tick_expeditions(0.1)
	order = GameSession.expedition_orders[GameSession._order_index(order_id)]
	assert_eq(order["phase"], "checking", "setup: the leg settled")
	var data: Dictionary = _read_save()
	data["expedition_orders"][0]["catch_up_seconds"] = OWED
	data["saved_at_unix"] = Time.get_unix_time_from_system() + 3600.0
	_clear_session_without_saving()
	_write_save(data)
	assert_true(SaveService.load_game(), SaveService.load_block_reason)
	order = GameSession.expedition_orders[0]
	assert_false(order.has("catch_up_seconds"), "a settled leg owes nothing")
	_land_catch_ups()
	assert_eq(GameSession.expedition_reports.size(), 1, "settled once")
	assert_eq(int(order["runs_completed"]), 1)


func test_commands_are_refused_stop_and_pause_are_held_and_a_stale_result_is_dropped() -> void:
	var order_id: String = _dispatch("verdant_outskirts", 5)
	GameSession.saved_at_unix = 1000.0
	GameSession.apply_offline_expedition_progress(1000.0 + OWED)
	var order: Dictionary = GameSession.expedition_orders[0]
	var battle: Dictionary = order["battle"]
	var result: Dictionary = GameSession.issue_battle_command(order_id, {"kind": BattleSimulation.COMMAND_SET_ITEM_AUTO, "value": {"auto_heal": false, "auto_revive": true}})
	assert_false(bool(result["accepted"]))
	assert_eq(result["error"], "catching_up")
	assert_true(is_same(order["battle"], battle), "the refused command changed nothing")
	GameSession.request_stop_expedition(order_id)
	assert_eq(GameSession.last_action_error, "")
	assert_true(bool(order["stop_requested"]), "the stop is held for the settle")
	assert_true(order.has("catch_up_seconds"))
	# The player's pause and un-pause (the battle view un-pauses on leave) never free the catch-up.
	GameSession.set_battle_paused(order_id, true)
	GameSession.set_battle_paused(order_id, false)
	GameSession.tick_expeditions(0.25)
	assert_true(is_same(order["battle"], battle), "still stopped")
	GameSession.set_battle_paused(order_id, true)
	# Stale: the battle was replaced while the job was out, so its result is dropped.
	var replaced: Dictionary = battle.duplicate(true)
	order["battle"] = replaced
	var deadline: int = Time.get_ticks_msec() + 60000
	while not GameSession._battle_checks.is_empty() and Time.get_ticks_msec() < deadline:
		OS.delay_msec(1)
		GameSession._land_battle_checks()
	assert_true(is_same(order["battle"], replaced), "the stale result was dropped")
	assert_true(order.has("catch_up_seconds"), "and the order still owes")
	var expected := BattleState.from_dict(replaced.duplicate(true))
	BattleSimulation.advance(expected, OWED)
	_land_catch_ups()
	assert_true(var_to_bytes(order["battle"]) == var_to_bytes(expected.to_dict()))
	assert_true(GameSession._paused_battle_orders.has(order_id), "the player's pause is kept")


func test_quit_mid_catch_up_stops_within_half_a_second() -> void:
	_dispatch("fallen_citadel", 30)
	GameSession.saved_at_unix = 1000.0
	GameSession.apply_offline_expedition_progress(1000.0 + 3600.0)
	GameSession.tick_expeditions(0.01)
	assert_eq(GameSession._battle_jobs.size(), 1)
	var started: int = Time.get_ticks_usec()
	GameSession._exit_tree()
	assert_lt(float(Time.get_ticks_usec() - started) / 1000000.0, 0.5)
	assert_true(GameSession._battle_jobs.is_empty(), "no task left")
	assert_true(GameSession._battle_checks.is_empty())


## Dispatches count level-80 knights to zone_id in 5-hero presets, two runs.
func _dispatch(zone_id: String, count: int) -> String:
	var presets: Array[String] = []
	for start: int in range(0, count, 5):
		var ids: Array[String] = []
		for index: int in range(start, start + 5):
			var hero := Hero.new("%s %d" % [zone_id, index], 7)
			hero.def_id = &"knight"
			hero.level = 80
			hero.instance_id = "hero:%s:%d" % [zone_id, index]
			GameSession.roster.append(hero)
			ids.append(hero.instance_id)
		presets.append(GameSession.save_team_preset("", "%s %d" % [zone_id, start], ids, zone_id))
	var order_id: String = GameSession.dispatch_force(presets, zone_id, 2, {}, LOADOUT)
	assert_ne(order_id, "", GameSession.last_action_error)
	return order_id


## Sends the catch-ups out and lands the round, advancing no battle.
func _land_catch_ups() -> void:
	GameSession._send_battle_checks()
	var deadline: int = Time.get_ticks_msec() + 60000
	while not GameSession._battle_checks.is_empty() and Time.get_ticks_msec() < deadline:
		OS.delay_msec(1)
		GameSession._land_battle_checks()
	assert_true(GameSession._battle_checks.is_empty(), "the catch-up landed")


func _clear_session_without_saving() -> void:
	GameSession.set("_save_deferred_depth", 1)
	GameSession.from_dict({"roster": []})
	GameSession.set("_save_deferred_depth", 0)


func _read_save() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(SaveService.SAVE_PATH)) as Dictionary


func _write_save(data: Dictionary) -> void:
	var save_file: FileAccess = FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	assert_not_null(save_file)
	if save_file == null:
		return
	save_file.store_string(JSON.stringify(data, "\t"))
	save_file.close()
