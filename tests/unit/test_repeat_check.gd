extends GutTest
## ig-7sn.6: a due repeat settles at once, then waits in "checking" while its forecast runs as two jobs
## off the settle pulse (DECISIONS.md 2026-09-25 "Battle sim threading", item 9).

const STOCK: Dictionary = {"healing": 5, "revival": 5, "healing_masterwork": 0, "revival_masterwork": 0}
const LOADOUT: Dictionary = {"healing": 1, "revival": 1, "keep_healing": 0, "keep_revival": 0}
const ESCROW: Dictionary = {"healing": 1, "revival": 1, "healing_masterwork": 0, "revival_masterwork": 0}
const SPENT: Dictionary = {"healing": 4, "revival": 4, "healing_masterwork": 0, "revival_masterwork": 0}


func before_each() -> void:
	_clear_session_without_saving()
	GameSession.last_action_error = ""
	SaveService.load_blocked = false
	GameSession.supplies = STOCK.duplicate()


func after_each() -> void:
	_clear_session_without_saving()


func test_a_due_repeat_settles_now_and_its_check_starts_the_run_it_checked() -> void:
	var order_id: String = _settle_into_check()
	var order: Dictionary = GameSession.expedition_orders[0]
	assert_eq(int(order["runs_completed"]), 1, "settled at once")
	assert_eq(GameSession.expedition_reports.size(), 1)
	assert_eq(str(GameSession.expedition_reports[0]["stopped_reason"]), "")
	assert_eq(GameSession.supplies, SPENT, "the repeat's escrow is spent at the settle")
	assert_eq(order["escrow"], ESCROW)
	assert_true(GameSession._battle_checks.has(order_id), "the settle pulse sent the check")
	var check: Dictionary = GameSession._battle_checks[order_id]
	assert_true(check["normal"] is BattleJob and check["stress"] is BattleJob, "two jobs: normal and stress")
	# The double-settle guard: a checking order is never due again.
	GameSession._resolve_due_orders_in_memory()
	assert_eq(GameSession.expedition_reports.size(), 1)
	assert_eq(int(order["runs_completed"]), 1)
	var snapshots: Array[Dictionary] = (check["snapshots"] as Array[Dictionary]).duplicate(true)
	var expected: Dictionary = _expected_run(order, snapshots)
	assert_true(bool(expected["verdict"]["safe"]), "a strong team's repeat is safe")
	_land_repeat_checks()
	assert_eq(order["phase"], "fighting")
	assert_eq(order["battle"], expected["battle"], "the run uses the snapshots and seed the check used")
	assert_almost_eq(float(order["remaining_seconds"]), float(order["initial_duration_seconds"]), 0.001)
	assert_eq(GameSession.expedition_reports.size(), 1)
	assert_eq(GameSession.supplies, SPENT)


func test_a_save_mid_check_reloads_still_checking_and_never_settles_twice() -> void:
	var order_id: String = _settle_into_check()
	var order: Dictionary = GameSession.expedition_orders[0]
	var seed: int = int(order["run_seed"])
	# Through JSON, as the save stores them (its numbers come back as floats).
	var reports: Variant = JSON.parse_string(JSON.stringify(GameSession.expedition_reports))
	var ledger_size: int = GameSession.ledger.size()
	var stones: int = GameSession.stones
	var checked: Array[Dictionary] = (GameSession._battle_checks[order_id]["snapshots"] as Array[Dictionary]).duplicate(true)
	var saved: PackedByteArray = _read_file_bytes(SaveService.SAVE_PATH)
	assert_true(saved.get_string_from_utf8().contains("\"checking\""), "the settle's save holds the phase")
	_clear_session_without_saving()
	_write_save(SaveService.SAVE_PATH, saved)
	assert_true(SaveService.load_game())
	assert_true(GameSession._battle_checks.is_empty(), "the load runs no check")
	order = GameSession.expedition_orders[GameSession._order_index(order_id)]
	assert_eq(order["phase"], "checking")
	assert_eq(int(order["run_seed"]), seed)
	assert_eq(int(order["runs_completed"]), 1)
	assert_eq(GameSession.supplies, SPENT)
	# Real pulses from here: the first sends the check again, a later one lands it.
	var deadline: int = Time.get_ticks_msec() + 60000
	while order["phase"] == "checking" and Time.get_ticks_msec() < deadline:
		GameSession.tick_expeditions(0.01)
		OS.delay_msec(1)
	assert_eq(order["phase"], "fighting")
	assert_eq(JSON.parse_string(JSON.stringify(GameSession.expedition_reports)), reports, "no second settle: rewards, runs and report unchanged")
	assert_eq(GameSession.ledger.size(), ledger_size)
	assert_eq(GameSession.stones, stones)
	assert_eq(GameSession.supplies, SPENT)
	# The check sent again after the reload rebuilt its snapshots from the saved heroes: the same team,
	# seed and verdict as the one the save interrupted, and the run it starts.
	assert_eq(GameSession._team_snapshots(_team(order), _squads(order)), checked)
	var expected: Dictionary = _expected_run(order, checked)
	assert_true(bool(expected["verdict"]["safe"]))
	assert_eq(order["battle"], expected["battle"], "the same run as before the save")


func test_an_unsafe_check_refunds_the_escrow_and_stops_on_that_settles_report() -> void:
	var order_id: String = _settle_into_check()
	var order: Dictionary = GameSession.expedition_orders[0]
	# Drop the check the settle sent and weaken the team, so the next check is unsafe.
	GameSession._cancel_battle_jobs()
	for hero: Hero in _team(order):
		hero.rank = 0
		hero.level = 0
	var expected: Dictionary = _expected_run(order, GameSession._team_snapshots(_team(order), _squads(order)))
	assert_false(bool(expected["verdict"]["safe"]), "setup: this team's repeat must be unsafe")
	_land_repeat_checks()
	assert_eq(GameSession._order_index(order_id), -1, "the order stopped")
	assert_eq(GameSession.supplies, STOCK, "escrow refunded")
	assert_eq(GameSession.expedition_reports.size(), 1, "no new report")
	assert_eq(str(GameSession.expedition_reports[0]["stopped_reason"]), "unsafe_repeat")


func test_stop_while_checking_ends_the_order_at_once_and_drops_the_late_result() -> void:
	var order_id: String = _settle_into_check()
	var check: Dictionary = GameSession._battle_checks[order_id]
	GameSession.request_stop_expedition(order_id)
	assert_eq(GameSession.last_action_error, "")
	assert_eq(GameSession._order_index(order_id), -1, "ended at once")
	assert_eq(GameSession.supplies, STOCK, "escrow refunded")
	assert_eq(str(GameSession.expedition_reports[0]["stopped_reason"]), "requested")
	assert_true((check["normal"] as BattleJob).cancelled and (check["stress"] as BattleJob).cancelled)
	var deadline: int = Time.get_ticks_msec() + 60000
	while not GameSession._battle_jobs.is_empty() and Time.get_ticks_msec() < deadline:
		OS.delay_msec(1)
		GameSession._land_battle_checks()
	assert_true(GameSession._battle_jobs.is_empty(), "the late jobs were released")
	assert_true(GameSession.expedition_orders.is_empty())
	assert_eq(GameSession.expedition_reports.size(), 1)
	assert_eq(GameSession.supplies, STOCK)


func test_quit_while_checking_stops_the_check_within_half_a_second() -> void:
	_settle_into_check()
	assert_false(GameSession._battle_jobs.is_empty())
	var started: int = Time.get_ticks_usec()
	GameSession._exit_tree()
	assert_lt(float(Time.get_ticks_usec() - started) / 1000000.0, 0.5)
	assert_true(GameSession._battle_jobs.is_empty(), "no task left")
	assert_true(GameSession._battle_checks.is_empty())


## Dispatches a strong two-run order, wins its first leg and runs the settle pulse: the order is left
## "checking", its check out.
func _settle_into_check() -> String:
	var ids: Array[String] = []
	for index: int in 5:
		var hero := Hero.new("Check %d" % index, 7)
		hero.def_id = &"knight"
		hero.level = 80
		hero.instance_id = "hero:check:%d" % index
		GameSession.roster.append(hero)
		ids.append(hero.instance_id)
	var preset_id: String = GameSession.save_team_preset("", "Check Team", ids, "verdant_outskirts")
	var order_id: String = GameSession.dispatch_force([preset_id], "verdant_outskirts", 2, {}, LOADOUT)
	assert_ne(order_id, "", GameSession.last_action_error)
	var order: Dictionary = GameSession.expedition_orders[0]
	(order["battle"] as Dictionary)["status"] = "victory"
	order["remaining_seconds"] = 0.0
	GameSession.tick_expeditions(0.1)
	assert_eq(GameSession.expedition_orders.size(), 1, GameSession.last_action_error)
	assert_eq(GameSession.expedition_orders[0]["phase"], "checking")
	return order_id


## The main thread's verdict for the order's repeat with these snapshots and its seed, and the run
## create_run starts from them.
func _expected_run(order: Dictionary, snapshots: Array[Dictionary]) -> Dictionary:
	var zone: ZoneDefinition = ZoneDefinition.definition_for(StringName(str(order["zone_id"])))
	var seed: int = int(order["run_seed"])
	var verdict: Dictionary = BattleSimulation.forecast(str(order["id"]) + ":repeat", snapshots, zone, _squads(order), order["policies"] as Dictionary, order["escrow"] as Dictionary, seed)
	var state: BattleState = BattleSimulation.create_run(str(order["id"]), snapshots, zone, _squads(order), order["policies"] as Dictionary, order["escrow"] as Dictionary, seed)
	return {"verdict": verdict, "battle": state.to_dict()}


func _team(order: Dictionary) -> Array[Hero]:
	var team: Array[Hero] = []
	for hero_id: String in GameSession._string_array(order["hero_ids"]):
		team.append(GameSession.hero_by_id(hero_id))
	return team


func _squads(order: Dictionary) -> Array[Dictionary]:
	var squads: Array[Dictionary] = []
	for squad: Dictionary in order["squads"]:
		squads.append(squad.duplicate(true))
	return squads


## Sends the checks out and lands them, advancing no battle.
func _land_repeat_checks() -> void:
	GameSession._send_battle_checks()
	var deadline: int = Time.get_ticks_msec() + 60000
	while not GameSession._battle_checks.is_empty() and Time.get_ticks_msec() < deadline:
		OS.delay_msec(1)
		GameSession._land_battle_checks()
	assert_true(GameSession._battle_checks.is_empty(), "the repeat checks landed")


func _clear_session_without_saving() -> void:
	GameSession.set("_save_deferred_depth", 1)
	GameSession.from_dict({"roster": []})
	GameSession.set("_save_deferred_depth", 0)


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
	var bytes: PackedByteArray = save_file.get_buffer(save_file.get_length())
	save_file.close()
	return bytes
