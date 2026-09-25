extends GutTest
## ig-7sn.13 (DECISIONS.md 2026-09-25, "Battle sim threading"): a sim job gives the same bytes on
## WorkerThreadPool as on the main thread, and GameSession stops every job fast on quit and on load.

const BALANCE: BalanceTable = preload("res://balance.tres")
const SEEDS: Array[int] = [11, 12, 13]
## Long enough for contact at both zones; short enough to keep the suite quick.
const RUN_SECONDS: float = 20.0


func test_a_battle_job_on_the_pool_matches_the_main_thread_byte_for_byte() -> void:
	for zone_id: StringName in [&"frontier_march", &"fallen_citadel"]:
		var zone: ZoneDefinition = ZoneDefinition.definition_for(zone_id)
		var hero_count: int = 50 if zone_id == &"frontier_march" else 30
		# Every seed's pool job runs at once, sharing one zone, so the threads overlap.
		var jobs: Array[BattleJob] = []
		for seed: int in SEEDS:
			var job := BattleJob.new()
			var state: BattleState = _run(zone, hero_count, seed)
			job.task_id = WorkerThreadPool.add_task(func() -> void: job.result = BattleJob.run_battle(state, RUN_SECONDS, job))
			jobs.append(job)
		for index: int in SEEDS.size():
			var seed: int = SEEDS[index]
			WorkerThreadPool.wait_for_task_completion(jobs[index].task_id)
			var pooled: Dictionary = jobs[index].result
			var direct: Dictionary = BattleJob.run_battle(_run(zone, hero_count, seed), RUN_SECONDS, null)
			var one_call: BattleState = _run(zone, hero_count, seed)
			BattleSimulation.advance(one_call, RUN_SECONDS)
			var label: String = "%s seed %d" % [zone_id, seed]
			assert_false(bool(pooled.get("cancelled", true)), label)
			assert_true(var_to_bytes(pooled["battle"]) == var_to_bytes(direct["battle"]), "%s: pool == main thread" % label)
			# The 5 s chunks run the same ticks as one advance() call.
			assert_true(var_to_bytes(direct["battle"]) == var_to_bytes(one_call.to_dict()), "%s: chunks == one call" % label)
			assert_gt(int((direct["battle"] as Dictionary)["tick"]), 0, label)


func test_a_forecast_job_on_the_pool_matches_the_main_thread_byte_for_byte() -> void:
	var zone: ZoneDefinition = ZoneDefinition.definition_for(&"verdant_outskirts")
	var heroes: Array[Dictionary] = _heroes(5)
	var squads: Array[Dictionary] = _squads(5)
	var escrow: Dictionary = {"healing": 1, "revival": 0}
	var jobs: Array[BattleJob] = []
	for seed: int in SEEDS:
		var job := BattleJob.new()
		job.task_id = WorkerThreadPool.add_task(func() -> void: job.result = BattleJob.run_forecast("forecast", heroes, zone, squads, {}, escrow, seed, job))
		jobs.append(job)
	for index: int in SEEDS.size():
		WorkerThreadPool.wait_for_task_completion(jobs[index].task_id)
		var direct: Dictionary = BattleSimulation.forecast("forecast", heroes, zone, squads, {}, escrow, SEEDS[index])
		assert_false(bool(jobs[index].result.get("cancelled", true)))
		assert_true(var_to_bytes(jobs[index].result["forecast"]) == var_to_bytes(direct), "seed %d" % SEEDS[index])
		assert_true(direct.has("safe") and direct.has("normal") and direct.has("stress"))


func test_quit_stops_every_job_within_half_a_second_and_drops_its_result() -> void:
	var zone: ZoneDefinition = ZoneDefinition.definition_for(&"frontier_march")
	var jobs: Array[BattleJob] = []
	for seed: int in SEEDS:
		var state: BattleState = _run(zone, 50, seed)
		jobs.append(GameSession._submit_battle_job(func(job: BattleJob) -> Dictionary: return BattleJob.run_battle(state, 600.0, job)))
	var started: int = Time.get_ticks_usec()
	GameSession._exit_tree()
	var waited: float = float(Time.get_ticks_usec() - started) / 1000000.0
	gut.p("CANCEL WAIT: %.3f s for %d frontier jobs" % [waited, jobs.size()])
	assert_lt(waited, 0.5)
	assert_true(GameSession._battle_jobs.is_empty(), "no task left")
	for job: BattleJob in jobs:
		assert_eq(job.result, {"cancelled": true})


func test_a_load_stops_every_job_before_the_session_is_replaced() -> void:
	var zone: ZoneDefinition = ZoneDefinition.definition_for(&"fallen_citadel")
	var state: BattleState = _run(zone, 30, 21)
	var job: BattleJob = GameSession._submit_battle_job(func(running: BattleJob) -> Dictionary: return BattleJob.run_battle(state, 600.0, running))
	GameSession.from_dict(GameSession.to_dict())
	assert_true(GameSession._battle_jobs.is_empty(), "no task left")
	assert_true(job.cancelled)
	assert_eq(job.result, {"cancelled": true})


## Built on the main thread, as every job's state is: the zone is already resolved.
func _run(zone: ZoneDefinition, hero_count: int, seed: int) -> BattleState:
	return BattleSimulation.create_run("order:job", _heroes(hero_count), zone, _squads(hero_count), {"default_stance": "advance"}, {"healing": 0, "revival": 0}, seed)


func _heroes(count: int) -> Array[Dictionary]:
	var heroes: Array[Dictionary] = []
	var roles: Array[String] = ["knight", "ranger", "mage", "rogue", "cleric"]
	for index: int in count:
		var archetype: String = roles[index % roles.size()]
		var hero := Hero.new("Job %d" % index, 7)
		hero.instance_id = "hero:job:%d" % index
		hero.def_id = StringName(archetype)
		hero.level = 80
		var stats: Dictionary[StringName, float] = Hero.compute_final_stats(hero, Hero.definition_for(hero.def_id), BALANCE, Hero.level_for(hero, BALANCE))
		heroes.append({
			"hero_id": hero.instance_id,
			"archetype": archetype,
			"hp": stats[Hero.STAT_HP],
			"atk": stats[Hero.STAT_ATK],
			"defense": stats[Hero.STAT_DEF],
			"speed": stats[Hero.STAT_SPD],
			"crit_rate": stats[Hero.STAT_CRIT_RATE],
			"crit_damage": stats[Hero.STAT_CRIT_DMG],
			"squad_id": "squad:%d" % int(index / 5.0),
		})
	return heroes


func _squads(hero_count: int) -> Array[Dictionary]:
	var squads: Array[Dictionary] = []
	for squad_index: int in ceili(hero_count / 5.0):
		var hero_ids: Array[String] = []
		for member_index: int in range(squad_index * 5, mini((squad_index + 1) * 5, hero_count)):
			hero_ids.append("hero:job:%d" % member_index)
		squads.append({"id": "squad:%d" % squad_index, "name": "Squad %d" % squad_index, "hero_ids": hero_ids, "stance": "advance", "guard_target_id": ""})
	return squads
