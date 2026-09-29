extends GutTest
## ig-7sn.13 (DECISIONS.md 2026-09-25, "Battle sim threading"): a sim job gives the same bytes on
## WorkerThreadPool as on the main thread, and GameSession stops every job fast on quit and on load.

const BALANCE: BalanceTable = preload("res://balance.tres")
const SEEDS: Array[int] = [11, 12, 13]
const ZONES: Array[StringName] = [&"verdant_outskirts", &"ashfall_reaches", &"sundered_vault", &"fallen_citadel", &"frontier_march"]
## Long enough for contact at both zones; short enough to keep the suite quick.
const RUN_SECONDS: float = 20.0


func test_a_battle_job_on_the_pool_matches_the_main_thread_byte_for_byte() -> void:
	for zone_id: StringName in [&"frontier_march", &"fallen_citadel"]:
		var zone: ZoneDefinition = ZoneDefinition.definition_for(zone_id)
		var hero_count: int = 50 if zone_id == &"frontier_march" else 30
		# Every seed's pool job runs at once, sharing one zone, so the threads overlap.
		var jobs: Array[BattleJob] = []
		for run_seed: int in SEEDS:
			var job := BattleJob.new()
			var state: BattleState = _run(zone, hero_count, run_seed)
			job.task_id = WorkerThreadPool.add_task(func() -> void: job.result = BattleJob.run_battle(state, RUN_SECONDS, job))
			jobs.append(job)
		for index: int in SEEDS.size():
			var run_seed: int = SEEDS[index]
			WorkerThreadPool.wait_for_task_completion(jobs[index].task_id)
			var pooled: Dictionary = jobs[index].result
			var direct: Dictionary = BattleJob.run_battle(_run(zone, hero_count, run_seed), RUN_SECONDS, null)
			var one_call: BattleState = _run(zone, hero_count, run_seed)
			BattleSimulation.advance(one_call, RUN_SECONDS)
			var label: String = "%s seed %d" % [zone_id, run_seed]
			assert_false(bool(pooled.get("cancelled", true)), label)
			assert_true(var_to_bytes(pooled["battle"]) == var_to_bytes(direct["battle"]), "%s: pool == main thread" % label)
			# The 5 s chunks run the same ticks as one advance() call.
			assert_true(var_to_bytes(direct["battle"]) == var_to_bytes(one_call.to_dict()), "%s: chunks == one call" % label)
			assert_gt(int((direct["battle"] as Dictionary)["tick"]), 0, label)


## ig-vl1.4: zones read their skill from BattleSimulation.ABILITIES, never a load, so a battle with both
## zones up gives the pool the main thread's bytes too. ig-0qh: and three walls, whose corner graph each
## state builds for itself. ig-vl1.5: and the Rime Walls its Mages cast.
func test_a_battle_with_both_zones_and_walls_up_matches_on_the_pool_byte_for_byte() -> void:
	var zone: ZoneDefinition = ZoneDefinition.definition_for(&"frontier_march")
	var jobs: Array[BattleJob] = []
	for run_seed: int in SEEDS:
		var job := BattleJob.new()
		var state: BattleState = _run_with_zones(zone, run_seed)
		job.task_id = WorkerThreadPool.add_task(func() -> void: job.result = BattleJob.run_battle(state, RUN_SECONDS, job))
		jobs.append(job)
	for index: int in SEEDS.size():
		WorkerThreadPool.wait_for_task_completion(jobs[index].task_id)
		var pooled: Dictionary = jobs[index].result
		var direct: Dictionary = BattleJob.run_battle(_run_with_zones(zone, SEEDS[index]), RUN_SECONDS, null)
		var label: String = "seed %d" % SEEDS[index]
		assert_false(bool(pooled.get("cancelled", true)), label)
		assert_true(var_to_bytes(pooled["battle"]) == var_to_bytes(direct["battle"]), "%s: pool == main thread" % label)
		var live: Array = ((direct["battle"] as Dictionary)["field_objects"] as Array).map(func(field: Dictionary) -> String: return str(field["skill_id"]))
		assert_true("mage_rime_circle" in live and "cleric_hearthward" in live, "%s: both zones still up at the end: %s" % [label, live])
		# ig-vl1.5: the level-80 Mages cast Rime Walls too, each ending the oldest wall at the cap of 3.
		var walls: int = ((direct["battle"] as Dictionary)["field_objects"] as Array).filter(func(field: Dictionary) -> bool: return field["kind"] == "wall").size()
		assert_eq(walls, live.count("test_wall") + live.count("mage_rime_wall"), "%s: and the walls: %s" % [label, live])
		assert_eq(walls, BALANCE.battle_wall_cap, "%s: none ends in 20 s, so the cap stays full" % label)
		assert_true("mage_rime_wall" in live, "%s: a Rime Wall was cast on the pool: %s" % [label, live])


func test_a_forecast_job_on_the_pool_matches_the_main_thread_byte_for_byte() -> void:
	var zone: ZoneDefinition = ZoneDefinition.definition_for(&"verdant_outskirts")
	var heroes: Array[Dictionary] = _heroes(5)
	var squads: Array[Dictionary] = _squads(5)
	var escrow: Dictionary = {"healing": 1, "revival": 0}
	# Each seed's normal and stress legs, all out at once (ig-7sn.6 sends a repeat's check this way).
	var jobs: Array[BattleJob] = []
	for run_seed: int in SEEDS:
		for stress: bool in [false, true]:
			var job := BattleJob.new()
			job.task_id = WorkerThreadPool.add_task(func() -> void: job.result = BattleJob.run_forecast_leg("forecast", heroes, zone, squads, {}, escrow, run_seed, stress, job))
			jobs.append(job)
	for index: int in SEEDS.size():
		var normal: BattleJob = jobs[index * 2]
		var stress: BattleJob = jobs[index * 2 + 1]
		WorkerThreadPool.wait_for_task_completion(normal.task_id)
		WorkerThreadPool.wait_for_task_completion(stress.task_id)
		var direct: Dictionary = BattleSimulation.forecast("forecast", heroes, zone, squads, {}, escrow, SEEDS[index])
		assert_false(bool(normal.result.get("cancelled", true)) or bool(stress.result.get("cancelled", true)))
		var pooled: Dictionary = BattleSimulation.forecast_verdict(normal.result["leg"], stress.result["leg"])
		assert_true(var_to_bytes(pooled) == var_to_bytes(direct), "seed %d" % SEEDS[index])
		assert_true(direct.has("safe") and direct.has("normal") and direct.has("stress"))


## ig-7sn.12: a load's catch-up job starts from the battle as the save stores it (through JSON), built on
## the main thread from a deep copy, and ends where the synchronous advance by the same seconds does.
func test_a_catch_up_job_from_a_saved_battle_matches_the_advance_for_every_zone() -> void:
	var jobs: Array[BattleJob] = []
	var saved: Array[Dictionary] = []
	for zone_id: StringName in ZONES:
		var zone: ZoneDefinition = ZoneDefinition.definition_for(zone_id)
		var battle: Dictionary = JSON.parse_string(JSON.stringify(_run(zone, zone.hero_cap, 31).to_dict()))
		saved.append(battle)
		var state := BattleState.from_dict(battle.duplicate(true))
		var job := BattleJob.new()
		job.task_id = WorkerThreadPool.add_task(func() -> void: job.result = BattleJob.run_battle(state, RUN_SECONDS, job))
		jobs.append(job)
	for index: int in ZONES.size():
		WorkerThreadPool.wait_for_task_completion(jobs[index].task_id)
		var direct := BattleState.from_dict(saved[index])
		BattleSimulation.advance(direct, RUN_SECONDS)
		assert_false(bool(jobs[index].result.get("cancelled", true)))
		assert_true(var_to_bytes(jobs[index].result["battle"]) == var_to_bytes(direct.to_dict()), str(ZONES[index]))


## Sol's ig-7sn.12 case: seconds that are not whole chunks, a saved tick_remainder, and a battle that
## ends partway. The job equals the main thread's chunked advance byte for byte. Against one advance()
## call only the ended battle's leftover tick_remainder may differ; the fight itself is the same.
func test_a_catch_up_job_ending_partway_matches_the_chunked_advance() -> void:
	var zone: ZoneDefinition = ZoneDefinition.definition_for(&"verdant_outskirts")
	var started: BattleState = _run(zone, 5, 41)
	BattleSimulation.advance(started, 0.37)
	var battle: Dictionary = JSON.parse_string(JSON.stringify(started.to_dict()))
	var owed: float = 180.25
	var state := BattleState.from_dict(battle.duplicate(true))
	var job := BattleJob.new()
	job.task_id = WorkerThreadPool.add_task(func() -> void: job.result = BattleJob.run_battle(state, owed, job))
	WorkerThreadPool.wait_for_task_completion(job.task_id)
	var chunked: Dictionary = BattleJob.run_battle(BattleState.from_dict(battle.duplicate(true)), owed, null)
	var one_call := BattleState.from_dict(battle.duplicate(true))
	BattleSimulation.advance(one_call, owed)
	assert_ne(str(one_call.status), "active", "setup: the battle ends partway")
	assert_true(var_to_bytes(job.result["battle"]) == var_to_bytes(chunked["battle"]), "job == chunked main thread")
	var job_battle: Dictionary = (job.result["battle"] as Dictionary).duplicate(true)
	var direct: Dictionary = one_call.to_dict()
	gut.p("tick_remainder: chunked %s, one call %s" % [job_battle["tick_remainder"], direct["tick_remainder"]])
	job_battle.erase("tick_remainder")
	direct.erase("tick_remainder")
	assert_true(var_to_bytes(job_battle) == var_to_bytes(direct), "the same fight as one advance() call")


func test_quit_stops_every_job_within_half_a_second_and_drops_its_result() -> void:
	var zone: ZoneDefinition = ZoneDefinition.definition_for(&"frontier_march")
	var jobs: Array[BattleJob] = []
	for run_seed: int in SEEDS:
		var state: BattleState = _run(zone, 50, run_seed)
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


## 20 heroes of level 80 (their whole kits), with a Rime Circle on the first enemy and a Hearthward on
## the first Cleric cast at tick 0: 36 s and 48 s at P = 6, so both outlast the run. Three walls 6 long
## stand side by side across the middle of the armies' way, 1 apart, for 60 s.
func _run_with_zones(zone: ZoneDefinition, run_seed: int) -> BattleState:
	var heroes: Array[Dictionary] = _heroes(20)
	for hero: Dictionary in heroes:
		hero["level"] = 80
	var state: BattleState = BattleSimulation.create_run("order:job", heroes, zone, _squads(20), {"default_stance": "advance"}, {"healing": 0, "revival": 0}, run_seed)
	var mage: BattleActor = state.actors.filter(func(actor: BattleActor) -> bool: return actor.archetype == "mage")[0]
	var cleric: BattleActor = state.actors.filter(func(actor: BattleActor) -> bool: return actor.archetype == "cleric")[0]
	var enemy: BattleActor = state.actors.filter(func(actor: BattleActor) -> bool: return actor.faction == "enemy")[0]
	mage.position = enemy.position + Vector2(0.0, -6.0)
	assert_true(BattleSimulation._use_skill(state, mage, BattleSimulation.ABILITIES["mage_rime_circle"], enemy, enemy.position))
	cleric.ability_lock = 0.0
	assert_true(BattleSimulation._use_skill(state, cleric, BattleSimulation.ABILITIES["cleric_hearthward"], cleric, cleric.position))
	var camp := Vector2.ZERO
	var foes := Vector2.ZERO
	for actor: BattleActor in state.actors:
		if actor.faction == "ally":
			camp += actor.position / 20.0
		else:
			foes += actor.position / float(state.actors.size() - 20)
	var way: Vector2 = (foes - camp).normalized()
	var across := Vector2(-way.y, way.x)
	for lane: int in [-1, 0, 1]:
		var middle: Vector2 = (camp + foes) * 0.5 + across * (7.0 * lane)
		state.field_sequence += 1
		state.field_objects.append({
			"id": "field:%d" % state.field_sequence, "kind": "wall", "skill_id": "test_wall", "owner_actor_id": mage.id, "faction": "ally",
			"start": [(middle - across * 3.0).x, (middle - across * 3.0).y], "end": [(middle + across * 3.0).x, (middle + across * 3.0).y],
			"thickness": 1.2, "remaining_seconds": 60.0,
		})
	assert_eq(BattleSimulation.validate_snapshot(state.to_dict()), "")
	return state


## Built on the main thread, as every job's state is: the zone is already resolved.
func _run(zone: ZoneDefinition, hero_count: int, run_seed: int) -> BattleState:
	return BattleSimulation.create_run("order:job", _heroes(hero_count), zone, _squads(hero_count), {"default_stance": "advance"}, {"healing": 0, "revival": 0}, run_seed)


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
