extends GutTest
## ig-7sn.17: a rollback (a refused command, a failed save) is not a load. It keeps every sim job that
## is out and re-points each check that was current at its restored order's battle; only quit and a load
## cancel them (DECISIONS.md 2026-09-25 "Battle sim threading", item 5).

const LOADOUT: Dictionary = {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0}
const OWED: float = 20.0
const ZONE: String = "verdant_outskirts"


func before_each() -> void:
	GameSession.set_process(false)
	_clear_session_without_saving()
	GameSession.last_action_error = ""
	SaveService.load_blocked = false


func after_each() -> void:
	_clear_session_without_saving()
	GameSession.set_process(true)


func test_a_refused_command_keeps_every_job_and_each_lands_once_as_without_it() -> void:
	var ids: Dictionary = _fixture()
	var expected: Dictionary = _expected(ids)
	var jobs: Array[BattleJob] = _jobs_out()
	var previews: Array[Dictionary] = GameSession._preview_forecasts.duplicate()
	var generation: int = GameSession._battle_check_generation
	var before: Dictionary = GameSession.to_dict()
	watch_signals(GameSession)
	assert_false(bool(GameSession.issue_battle_command(ids["a"], {"kind": "not_a_command"})["accepted"]), "refused in the commit")
	_assert_kept(ids, jobs, previews, generation, before)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_signal_not_emitted(GameSession, "preview_forecast_ready", "no preview went back to Checking...")
	_land_and_compare(ids, expected, generation)


func test_a_failed_save_in_an_unrelated_transaction_keeps_every_job() -> void:
	var ids: Dictionary = _fixture()
	var expected: Dictionary = _expected(ids)
	var jobs: Array[BattleJob] = _jobs_out()
	var previews: Array[Dictionary] = GameSession._preview_forecasts.duplicate()
	var generation: int = GameSession._battle_check_generation
	var favorite: Hero = _hero("favorite", 0)
	_add_bad_incident(_hero("stranded", 1))
	var before: Dictionary = GameSession.to_dict()
	assert_false(GameSession.set_hero_favorite(favorite, true))
	assert_push_error("Save refused")
	_assert_kept(ids, jobs, previews, generation, before)
	GameSession.stranded_incidents.clear()
	_land_and_compare(ids, expected, generation)


func test_a_failed_save_in_the_landing_commit_brings_the_checks_back_to_land_next_pass() -> void:
	var ids: Dictionary = _fixture()
	var expected: Dictionary = _expected(ids)
	var generation: int = GameSession._battle_check_generation
	_wait_for_jobs()
	_add_bad_incident(_hero("stranded", 0))
	var before: Dictionary = GameSession.to_dict()
	GameSession._land_battle_checks()
	assert_push_error("Save refused")
	assert_eq(GameSession.to_dict(), before, "the landing rolled back exactly")
	var landed: Array = GameSession._battle_checks.keys()
	landed.sort()
	var all: Array = [ids["b"], ids["c"], ids["d"]]
	all.sort()
	assert_eq(landed, all, "the landed checks came back")
	assert_eq(str(_order(ids["b"])["phase"]), "checking")
	assert_true(_order(ids["c"]).has("catch_up_seconds") and _order(ids["d"]).has("catch_up_seconds"), "the round is still owed")
	GameSession.stranded_incidents.clear()
	# Every job is in, so one pass lands them all: the catch-ups as one round.
	GameSession._land_battle_checks()
	assert_true(GameSession._battle_checks.is_empty(), "one pass landed every check")
	_land_and_compare(ids, expected, generation)


func test_a_rolled_back_replacement_of_the_checked_battle_still_lands_its_check() -> void:
	var ids: Dictionary = _fixture()
	var expected: Dictionary = _expected(ids)
	var generation: int = GameSession._battle_check_generation
	var b_id: String = ids["b"]
	var before: Dictionary = GameSession.to_dict()
	assert_false(GameSession._commit_profile_mutation(func() -> bool:
		var order: Dictionary = GameSession.expedition_orders[GameSession._order_index(b_id)]
		order["battle"] = (order["battle"] as Dictionary).duplicate(true)
		return false))
	assert_eq(GameSession.to_dict(), before, "rolled back exactly")
	assert_true(is_same(GameSession._battle_checks[b_id]["battle"], _order(b_id)["battle"]), "re-pointed at the restored battle")
	_land_and_compare(ids, expected, generation)


func test_a_rolled_back_end_of_a_check_leaves_it_ended_and_the_pulse_sends_a_fresh_one() -> void:
	var ids: Dictionary = _fixture()
	var expected: Dictionary = _expected(ids)
	var generation: int = GameSession._battle_check_generation
	var b_id: String = ids["b"]
	# The jobs finish first, so their results are whole: the point is that they never land.
	_wait_for_jobs()
	assert_false(GameSession._commit_profile_mutation(func() -> bool:
		GameSession._end_battle_check_in_memory(b_id, "requested")
		return false))
	assert_eq(str(_order(b_id)["phase"]), "checking", "the order is back")
	assert_false(GameSession._battle_checks.has(b_id), "its ended check stays ended")
	GameSession._land_battle_checks()
	assert_eq(str(_order(b_id)["phase"]), "checking", "the cancelled check's result was not committed")
	assert_true(GameSession._battle_checks.is_empty(), "the catch-up round landed")
	GameSession._send_battle_checks()
	assert_eq(GameSession._battle_check_generation, generation + 1, "a fresh check went out")
	_land_and_compare(ids, expected, generation + 1)


## Sol (ig-7sn.17): an unsafe repeat ends its check in the landing commit. The landing erases the entry
## first, so the end cancels no job, and a failed save brings the check back to land the same verdict.
func test_a_failed_save_in_an_unsafe_landing_lands_the_same_verdict_next_pass() -> void:
	var ids: Dictionary = _fixture(true)
	var b_id: String = ids["b"]
	var generation: int = GameSession._battle_check_generation
	_wait_for_jobs()
	var check: Dictionary = GameSession._battle_checks[b_id]
	var normal: BattleJob = check["normal"]
	var stress: BattleJob = check["stress"]
	assert_false(bool(BattleSimulation.forecast_verdict(normal.result["leg"], stress.result["leg"])["safe"]), "the repeat is unsafe")
	_add_bad_incident(_hero("stranded", 0))
	var before: Dictionary = GameSession.to_dict()
	GameSession._land_battle_checks()
	assert_push_error("Save refused")
	assert_eq(GameSession.to_dict(), before, "the landing rolled back exactly")
	assert_true(GameSession._battle_checks.has(b_id), "B's check came back")
	assert_true(is_same(GameSession._battle_checks[b_id]["normal"], normal) and is_same(GameSession._battle_checks[b_id]["stress"], stress), "with the same jobs")
	assert_false(normal.cancelled or stress.cancelled, "not cancelled")
	GameSession.stranded_incidents.clear()
	GameSession._land_battle_checks()
	assert_true(GameSession._battle_checks.is_empty(), "one pass landed every check")
	assert_eq(GameSession._battle_check_generation, generation, "no job was sent again")
	assert_lt(GameSession._order_index(b_id), 0, "B ended")
	var reason: String = ""
	for report: Dictionary in GameSession.expedition_reports:
		if str(report.get("order_id", "")) == b_id:
			reason = str(report.get("stopped_reason", ""))
	assert_eq(reason, "unsafe_repeat", "on the same verdict")


func test_a_load_still_cancels_every_job() -> void:
	_fixture()
	var jobs: Array[BattleJob] = _jobs_out()
	assert_true(SaveService.load_game(), SaveService.load_block_reason)
	for job: BattleJob in jobs:
		assert_true(job.cancelled)
	assert_true(GameSession._battle_jobs.is_empty())
	assert_true(GameSession._battle_checks.is_empty())
	assert_true(GameSession._preview_forecasts.is_empty())


## C and D owe a catch-up (one round), B is a strong two-run order settled into "checking", A is an
## active order that can take a command, and a dispatch preview's forecast is out. Every job is out.
func _fixture(weak_b: bool = false) -> Dictionary:
	var c: String = _dispatch("c", 2)
	var d: String = _dispatch("d", 2)
	GameSession.saved_at_unix = 1000.0
	GameSession.apply_offline_expedition_progress(1000.0 + OWED)
	assert_true(_order(c).has("catch_up_seconds") and _order(d).has("catch_up_seconds"))
	var b: String = _dispatch("b", 2)
	var won: Dictionary = (_order(b)["battle"] as Dictionary).duplicate(true)
	won["status"] = "victory"
	_order(b)["battle"] = won
	_order(b)["remaining_seconds"] = 0.0
	if weak_b:
		# As test_repeat_check.gd does: a team weakened after its dispatch checks unsafe.
		for index: int in 5:
			var weak: Hero = GameSession.hero_by_id("hero:b:%d" % index)
			weak.rank = 0
			weak.level = 0
	GameSession.tick_expeditions(0.1)
	assert_eq(str(_order(b)["phase"]), "checking", GameSession.last_action_error)
	var a: String = _dispatch("a", 2)
	GameSession.preview_force([_preset("p")], ZONE, 0, {}, LOADOUT)
	for order_id: String in [b, c, d]:
		assert_true(GameSession._battle_checks.has(order_id), "a check is out for " + order_id)
	assert_eq(GameSession._preview_forecasts.size(), 1)
	return {"a": a, "b": b, "c": c, "d": d}


## What each check lands as with no rollback: C and D advanced by what they owe, B's repeat run.
func _expected(ids: Dictionary) -> Dictionary:
	var expected: Dictionary = {}
	for key: String in ["c", "d"]:
		var order: Dictionary = _order(ids[key])
		var caught_up := BattleState.from_dict((order["battle"] as Dictionary).duplicate(true))
		expected[key] = BattleJob.run_battle(caught_up, float(order["catch_up_seconds"]), null)["battle"]
	var b: Dictionary = _order(ids["b"])
	var check: Dictionary = GameSession._battle_checks[ids["b"]]
	var run: BattleState = BattleSimulation.create_run(ids["b"], (check["snapshots"] as Array[Dictionary]).duplicate(true), check["zone"], (check["squads"] as Array[Dictionary]).duplicate(true), b["policies"] as Dictionary, b["escrow"] as Dictionary, int(b["run_seed"]))
	expected["b"] = run.to_dict()
	return expected


func _jobs_out() -> Array[BattleJob]:
	var jobs: Array[BattleJob] = []
	for order_id: String in GameSession._battle_checks:
		for value: Variant in GameSession._battle_checks[order_id].values():
			if value is BattleJob:
				jobs.append(value)
	for entry: Dictionary in GameSession._preview_forecasts:
		jobs.append(entry["normal"])
		jobs.append(entry["stress"])
	return jobs


func _assert_kept(ids: Dictionary, jobs: Array[BattleJob], previews: Array[Dictionary], generation: int, before: Dictionary) -> void:
	assert_eq(GameSession.to_dict(), before, "rolled back exactly")
	assert_eq(_jobs_out(), jobs, "the same job objects")
	for job: BattleJob in jobs:
		assert_false(job.cancelled, "not cancelled")
		assert_true(GameSession._battle_jobs.has(job), "still out")
	assert_eq(GameSession._battle_check_generation, generation, "nothing sent again")
	assert_eq(GameSession._preview_forecasts.size(), previews.size())
	for index: int in previews.size():
		assert_true(is_same(GameSession._preview_forecasts[index], previews[index]), "the same preview entry")
	for key: String in ["b", "c", "d"]:
		assert_true(is_same(GameSession._battle_checks[ids[key]]["battle"], _order(ids[key])["battle"]), key + ": re-pointed at the restored battle")


## Lands every check, then checks each landed as a run with no rollback would, and only once.
func _land_and_compare(ids: Dictionary, expected: Dictionary, generation: int) -> void:
	var reports: int = GameSession.expedition_reports.size()
	var deadline: int = Time.get_ticks_msec() + 60000
	while not GameSession._battle_checks.is_empty() and Time.get_ticks_msec() < deadline:
		OS.delay_msec(1)
		GameSession._land_battle_checks()
	assert_true(GameSession._battle_checks.is_empty(), "every check landed")
	assert_eq(GameSession._battle_check_generation, generation, "no job was sent again")
	var b: Dictionary = _order(ids["b"])
	assert_eq(str(b["phase"]), "fighting", "B's check landed")
	assert_eq(b["battle"], expected["b"], "B's repeat run is the one it checked")
	for key: String in ["c", "d"]:
		var order: Dictionary = _order(ids[key])
		assert_false(order.has("catch_up_seconds"), key + " caught up")
		assert_true(var_to_bytes(order["battle"]) == var_to_bytes(expected[key]), key + ": the advance by what it owed")
	assert_eq(GameSession.expedition_reports.size(), reports, "nothing settled twice")


func _wait_for_jobs() -> void:
	var deadline: int = Time.get_ticks_msec() + 60000
	while GameSession._battle_jobs.any(func(job: BattleJob) -> bool: return not WorkerThreadPool.is_task_completed(job.task_id)) and Time.get_ticks_msec() < deadline:
		OS.delay_msec(1)


func _order(order_id: String) -> Dictionary:
	return GameSession.expedition_orders[GameSession._order_index(order_id)]


func _hero(tag: String, index: int) -> Hero:
	var hero := Hero.new("%s %d" % [tag, index], 7)
	hero.def_id = &"knight"
	hero.level = 80
	hero.instance_id = "hero:%s:%d" % [tag, index]
	GameSession.roster.append(hero)
	return hero


func _preset(tag: String) -> String:
	var ids: Array[String] = []
	for index: int in 5:
		ids.append(_hero(tag, index).instance_id)
	return GameSession.save_team_preset("", tag, ids, ZONE)


func _dispatch(tag: String, runs: int) -> String:
	var order_id: String = GameSession.dispatch_force([_preset(tag)], ZONE, runs, {}, LOADOUT)
	assert_ne(order_id, "", GameSession.last_action_error)
	return order_id


## test_save_refusal.gd's injected write failure: in memory only, an incident whose stranded ally keeps a
## squad_id no squad lists, which load refuses, so every save is refused until it is gone.
func _add_bad_incident(stranded: Hero) -> void:
	var zone: ZoneDefinition = load("res://zones/defs/verdant_outskirts.tres") as ZoneDefinition
	var stats: Dictionary[StringName, float] = Hero.compute_final_stats(stranded, Hero.definition_for(stranded.def_id), preload("res://balance.tres"), 0)
	var state: BattleState = BattleSimulation.create_run("source", [{
		"hero_id": stranded.instance_id,
		"archetype": str(stranded.def_id),
		"hp": stats[Hero.STAT_HP],
		"atk": stats[Hero.STAT_ATK],
		"defense": stats[Hero.STAT_DEF],
		"speed": stats[Hero.STAT_SPD],
		"crit_rate": stats[Hero.STAT_CRIT_RATE],
		"crit_damage": stats[Hero.STAT_CRIT_DMG],
		"squad_id": "source-squad",
	}], zone, [{"id": "source-squad", "name": "Source", "hero_ids": [stranded.instance_id], "stance": "stay_together", "guard_target_id": ""}], {}, {}, 544)
	state.actors[0].life = BattleActor.LIFE_DOWNED
	state.actors[0].hp = 0.0
	var snapshot: Dictionary = GameSession._incident_snapshot(state, [stranded.instance_id] as Array[String])
	(snapshot["actors"] as Array)[0]["squad_id"] = "source-squad"
	GameSession.stranded_incidents.append({"id": "incident-bad", "source_order_id": "source", "zone_id": "verdant_outskirts", "hero_ids": [stranded.instance_id], "battle_snapshot": snapshot, "created_recovery_seconds": GameSession.rescue_clock_seconds, "paused": true, "expiry_pending": false, "active_rescue_order_id": ""})


func _clear_session_without_saving() -> void:
	GameSession.set("_save_deferred_depth", 1)
	GameSession.from_dict({"roster": []})
	GameSession.set("_save_deferred_depth", 0)
