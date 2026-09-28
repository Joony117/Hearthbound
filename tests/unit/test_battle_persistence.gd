extends GutTest

const Compare = preload("res://tests/unit/compare.gd")


func before_each() -> void:
	GameSession.set("_save_deferred_depth", 1)
	GameSession.from_dict({"roster": []})
	SaveService.load_blocked = false


func after_each() -> void:
	GameSession.set("_save_deferred_depth", 0)


func test_v3_profile_round_trip_preserves_battle_rng_and_supplies() -> void:
	var hero := Hero.new("Persistent", 0)
	hero.def_id = &"mage"
	hero.instance_id = "hero:persistent"
	GameSession.roster.append(hero)
	var preset_id: String = GameSession.save_team_preset("", "Persistent", [hero.instance_id], "verdant_outskirts")
	var order_id: String = GameSession.dispatch_force([preset_id], "verdant_outskirts", 1, {}, {"healing": 1, "revival": 0, "keep_healing": 0, "keep_revival": 0})
	var saved: Dictionary = GameSession.to_dict()
	var rng_before: String = str((saved["expedition_orders"][0]["battle"] as Dictionary)["rng_state"])
	assert_eq(saved["version"], 3)
	assert_eq(GameSession.validate_saved_state(saved, 3), "")
	GameSession.from_dict(saved)
	assert_eq(str((GameSession.get_battle_snapshot(order_id))["rng_state"]), rng_before)
	assert_eq(GameSession.supplies, {"healing": 2, "revival": 1, "healing_masterwork": 0, "revival_masterwork": 0})


func test_v3_validation_rejects_non_string_rng_without_mutating_profile() -> void:
	var hero := Hero.new("Persistent", 0)
	hero.def_id = &"mage"
	hero.instance_id = "hero:persistent"
	GameSession.roster.append(hero)
	var preset_id: String = GameSession.save_team_preset("", "Persistent", [hero.instance_id], "verdant_outskirts")
	GameSession.dispatch_force([preset_id], "verdant_outskirts", 1, {}, {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0})
	var saved: Dictionary = GameSession.to_dict()
	(saved["expedition_orders"][0]["battle"] as Dictionary)["rng_state"] = 12.0
	assert_string_contains(GameSession.validate_saved_state(saved, 3), "rng_state")


func test_v3_validation_rejects_order_checkpoint_identity_actor_and_nullable_contract_breaks() -> void:
	var hero := Hero.new("Validator", 7)
	hero.def_id = &"knight"
	hero.level = 80
	hero.instance_id = "hero:validator"
	GameSession.roster.append(hero)
	var preset_id: String = GameSession.save_team_preset("", "Validator", [hero.instance_id], "verdant_outskirts")
	GameSession.dispatch_force([preset_id], "verdant_outskirts", 1, {}, _zero_loadout())
	var identity_fixture: Dictionary = GameSession.to_dict()
	var identity_order: Dictionary = (identity_fixture["expedition_orders"] as Array)[0]
	(identity_order["battle"] as Dictionary)["order_id"] = "wrong"
	assert_string_contains(GameSession.validate_saved_state(identity_fixture, 3), "identities")
	var nullable_fixture: Dictionary = GameSession.to_dict()
	((nullable_fixture["expedition_orders"] as Array)[0] as Dictionary)["loadout"] = null
	assert_string_contains(GameSession.validate_saved_state(nullable_fixture, 3), "loadout")
	var actor_fixture: Dictionary = GameSession.to_dict()
	var actor_order: Dictionary = (actor_fixture["expedition_orders"] as Array)[0]
	var actor_data: Dictionary = ((actor_order["battle"] as Dictionary)["actors"] as Array)[0]
	actor_data["hero_id"] = "hero:unrelated"
	assert_ne(GameSession.validate_saved_state(actor_fixture, 3), "")


func test_last_crit_tick_is_optional_round_trips_and_is_validated() -> void:
	var hero := Hero.new("Crit Recorder", 7)
	hero.def_id = &"knight"
	hero.level = 80
	hero.instance_id = "hero:crit"
	GameSession.roster.append(hero)
	var preset_id: String = GameSession.save_team_preset("", "Crit", [hero.instance_id], "verdant_outskirts")
	var order_id: String = GameSession.dispatch_force([preset_id], "verdant_outskirts", 1, {}, _zero_loadout())
	GameSession.tick_expeditions(1.0)
	var profile: Dictionary = GameSession.to_dict()
	var tick: int = int(((profile["expedition_orders"] as Array)[0]["battle"] as Dictionary)["tick"])
	assert_gt(tick, 0)

	var old_shape: Dictionary = Compare.json_round_trip(profile)
	for raw_actor: Variant in ((old_shape["expedition_orders"] as Array)[0]["battle"] as Dictionary)["actors"]:
		((raw_actor as Dictionary)["effect_state"] as Dictionary).erase("last_crit_tick")
	assert_eq(GameSession.validate_saved_state(old_shape, 3), "", "a save from before crits were recorded still loads")
	GameSession.from_dict(old_shape)
	assert_false(GameSession.get_battle_snapshot(order_id).is_empty())

	var with_crit: Dictionary = profile.duplicate(true)
	_first_actor_effects(with_crit)["last_crit_tick"] = tick
	var recorded: Dictionary = Compare.json_round_trip(with_crit)
	assert_eq(GameSession.validate_saved_state(recorded, 3), "")
	GameSession.from_dict(recorded)
	var reloaded: Dictionary = ((GameSession.get_battle_snapshot(order_id)["actors"] as Array)[0] as Dictionary)["effect_state"]
	assert_eq(int(reloaded["last_crit_tick"]), tick, "value survives the round trip")
	var resaved: Dictionary = Compare.json_round_trip(GameSession.to_dict())
	assert_eq(int(_first_actor_effects(resaved)["last_crit_tick"]), tick, "and survives the next save")

	for bad_value: Variant in [-1, 1.5, "3", tick + 1]:
		var broken: Dictionary = Compare.json_round_trip(profile)
		_first_actor_effects(broken)["last_crit_tick"] = bad_value
		assert_ne(GameSession.validate_saved_state(broken, 3), "", "last_crit_tick %s is rejected" % str(bad_value))


## ig-gy0.1: a v3 profile saved by SaveService before skills were data (ability_cooldown and
## ability_auto on each actor, the Mage set to manual) loads, migrates and finishes deterministically.
## The pre-change build recorded the expected finish. It was re-recorded at ig-gy0.4
## (.agent-results/ig-gy0.4/regen_pre_skills_expected.gd), because counters and enemy kits change
## this fight on purpose. The match with the old build is proven by a run with both switched off,
## which finished as the old build did (.agent-results/ig-gy0.4/experiment_off.log). It was
## re-recorded again at ig-9gf (.agent-results/ig-9gf/regen_pre_skills_expected.gd): the reach fix
## lets fighters on both sides close on still targets, so this fight now ends stranded at 71.7 s.
## With the fix off, that script reproduced the previous file byte for byte
## (.agent-results/ig-9gf/expected_fix_off.json).
func test_pre_skills_checkpoint_loads_migrates_and_finishes_identically() -> void:
	var fixture_path: String = "res://tests/fixtures/battle_checkpoint_pre_skills.json"
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fixture_path)) as Dictionary
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fixture_path.replace(".json", ".expected.json"))) as Dictionary
	var raw_actor: Dictionary = (((saved["expedition_orders"] as Array)[0]["battle"] as Dictionary)["actors"] as Array)[0]
	assert_true(raw_actor.has("ability_cooldown") and not raw_actor.has("skills"), "the fixture is the old shape")
	# Through the real loader. Saved "in the future" so offline progress adds no wall-clock time.
	saved["saved_at_unix"] = Time.get_unix_time_from_system() + 3600.0
	var original_save: PackedByteArray = FileAccess.get_file_as_bytes(SaveService.SAVE_PATH)
	var original_existed: bool = FileAccess.file_exists(SaveService.SAVE_PATH)
	var save_file := FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	save_file.store_string(JSON.stringify(saved, "\t"))
	save_file.close()
	var loaded: bool = SaveService.load_game()
	if original_existed:
		FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE).store_buffer(original_save)
	else:
		DirAccess.remove_absolute(SaveService.SAVE_PATH)
	assert_true(loaded, SaveService.load_block_reason)
	assert_false(SaveService.load_blocked, SaveService.load_block_reason)
	var order_id: String = str(expected["order_id"])
	assert_false(GameSession.get_battle_snapshot(order_id).is_empty())

	var state := BattleState.from_dict(GameSession.expedition_orders[0]["battle"] as Dictionary)
	for actor: BattleActor in state.actors:
		if actor.faction == "ally":
			var mode: String = "manual" if actor.hero_id == "hero:checkpoint:2" else "auto"
			assert_eq(str(actor.skills[1]["mode"]), mode, "%s signature mode survives migration" % actor.hero_id)
	var resaved: Dictionary = Compare.json_round_trip(state.to_dict())
	assert_eq(BattleSimulation.validate_snapshot(resaved), "", "the migrated battle saves in the new shape")
	state = BattleState.from_dict(resaved)
	# Tick by tick, to rebuild the old guard_reduction, which only ever grew (ig-gy0.2), from the
	# value the checkpoint carried in.
	var rallied: Dictionary = {}
	for raw: Dictionary in ((saved["expedition_orders"] as Array)[0]["battle"] as Dictionary)["actors"]:
		rallied[raw["id"]] = float((raw["effect_state"] as Dictionary).get("guard_reduction", 0.0))
	var outcome: BattleOutcome = null
	while state.status == "active":
		outcome = BattleSimulation.advance(state, 0.1)
		for actor: BattleActor in state.actors:
			for status: Dictionary in actor.statuses:
				if status["id"] == "knight_rally":
					rallied[actor.id] = maxf(float(rallied.get(actor.id, 0.0)), float(status["magnitude"]))
	# ig-1jw: a checkpoint without pace is pace 1, so it finishes at the pace-1 numbers below.
	assert_eq(state.pace, 1, "a legacy checkpoint loads as pace 1")
	# The fixture predates the Ledger (ig-m6o.1): its bookkeeping keys are the only difference.
	assert_false(outcome.moments.is_empty(), "the fight reports moments")
	assert_eq(_exact_json(_without_ledger_keys(outcome.to_dict())), _exact_json(expected["outcome"]))
	assert_eq(_exact_json(_pre_skills_shape(state, rallied)), _exact_json(expected["final"]), "final state matches the pre-change finish")

	GameSession.tick_expeditions(0.1)
	var profile: Dictionary = Compare.json_round_trip(GameSession.to_dict())
	assert_eq(GameSession.validate_saved_state(profile, 3), "", "the session re-saves the migrated battle")
	assert_true(((((profile["expedition_orders"] as Array)[0]["battle"] as Dictionary)["actors"] as Array)[0] as Dictionary).has("skills"))


## The battle as the pre-skills build recorded it: one signature cooldown and one auto flag per actor.
func _pre_skills_shape(state: BattleState, rallied: Dictionary = {}) -> Dictionary:
	var data: Dictionary = _without_ledger_keys(state.to_dict())
	# ig-1jw: the old build had no pace key; the test asserts the checkpoint loaded as pace 1.
	data.erase("pace")
	# ig-vl1.4: nor zones, and a pre-skills kit casts none.
	assert_eq([data["field_objects"], data["field_sequence"]], [[], 0], "no zone in a pre-skills fight")
	data.erase("field_objects")
	data.erase("field_sequence")
	for index: int in state.actors.size():
		var actor: BattleActor = state.actors[index]
		var actor_data: Dictionary = (data["actors"] as Array)[index]
		actor_data.erase("skills")
		actor_data.erase("skill_cooldowns")
		# ig-gy0.2 bookkeeping the old build never had: the ability lock, combos, statuses.
		for key: String in ["ability_lock", "combo_skill", "combo_tick", "statuses"]:
			actor_data.erase(key)
		(actor_data["effect_state"] as Dictionary).erase("last_skill_id")
		(actor_data["effect_state"] as Dictionary).erase("telegraph_skill")
		# ig-gy0.4 bookkeeping: the telegraph claim and the answer tick.
		(actor_data["effect_state"] as Dictionary).erase("telegraph_claimed_by")
		(actor_data["effect_state"] as Dictionary).erase("last_counter_tick")
		# ig-36y view cues: where the last hit came from, and the last push.
		(actor_data["effect_state"] as Dictionary).erase("hit_from")
		(actor_data["effect_state"] as Dictionary).erase("last_push_tick")
		# The old guard keys: Stand Fast's time left, and the largest reduction it ever gave.
		var guard_remaining: float = 0.0
		for status: Dictionary in actor.statuses:
			if status["id"] == "knight_rally":
				guard_remaining = float(status["remaining"])
		(actor_data["effect_state"] as Dictionary)["guard_remaining"] = guard_remaining
		(actor_data["effect_state"] as Dictionary)["guard_reduction"] = float(rallied.get(actor.id, 0.0))
		var cooldown: float = 0.0
		for value: float in actor.skill_cooldowns.values():
			cooldown += value
		actor_data["signature_cooldown"] = cooldown
		actor_data["signature_auto"] = not actor.skills.any(func(entry: Dictionary) -> bool: return entry["mode"] == "manual")
	return data


func _without_ledger_keys(data: Dictionary) -> Dictionary:
	for key: String in ["moments", "moments_truncated", "kills"]:
		data.erase(key)
	return data


## Full precision, sorted keys, and ints read back as floats like the parsed expectation.
func _exact_json(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value, "", true, true)), "", true, true)


func _first_actor_effects(profile: Dictionary) -> Dictionary:
	var actors: Array = ((profile["expedition_orders"] as Array)[0]["battle"] as Dictionary)["actors"]
	return (actors[0] as Dictionary)["effect_state"] as Dictionary


## ---- ig-uu7.4: a Knight's cover order in the team snapshot and the saved battle

func test_a_knights_cover_order_is_its_back_row_partner_then_points_then_team_order() -> void:
	var knight: Hero = _cover_hero("hero:k", &"knight")
	var mage: Hero = _cover_hero("hero:m", &"mage")
	var ranger: Hero = _cover_hero("hero:r", &"ranger")
	var cleric: Hero = _cover_hero("hero:c", &"cleric")
	var rogue: Hero = _cover_hero("hero:q", &"rogue")
	# The mage is the partner (9 points), the ranger has 3, the cleric shared a routine win (0).
	_bond_ledger({"hero:m": 3, "hero:r": 1, "hero:c": 0})
	var builds: int = GameSession.bond_builds
	var snapshots: Array[Dictionary] = GameSession._team_snapshots([mage, cleric, rogue] as Array[Hero])
	assert_false(snapshots.any(func(snapshot: Dictionary) -> bool: return snapshot.has("cover_order")), "no Knight, no cover order")
	snapshots = GameSession._team_snapshots([knight, rogue] as Array[Hero])
	assert_eq(snapshots[0]["cover_order"], [], "a Knight with no back-row teammate")
	assert_eq(GameSession.bond_builds, builds, "neither team reads the bond index")
	snapshots = GameSession._team_snapshots([knight, cleric, ranger, mage] as Array[Hero])
	assert_eq(snapshots[0]["cover_order"], ["hero:m", "hero:r"], "the partner, then points; 0 points is left out")
	assert_false(snapshots[3].has("cover_order"), "only a Knight's snapshot carries it")
	assert_eq(GameSession.bond_builds, builds + 1, "one index read")
	# A rogue partner (12 points) is left out; the mage and ranger tie at 3 and keep team order.
	_bond_ledger({"hero:q": 4, "hero:m": 1, "hero:r": 1})
	assert_eq(GameSession._team_snapshots([knight, rogue, ranger, mage] as Array[Hero])[0]["cover_order"], ["hero:r", "hero:m"])
	assert_eq(GameSession._team_snapshots([knight, rogue, mage, ranger] as Array[Hero])[0]["cover_order"], ["hero:m", "hero:r"])
	# A tie at 9 points: the partner is the one with the later save, and it goes first over team order.
	_bond_ledger({"hero:m": 3, "hero:r": 3})
	assert_eq(Bonds.bond_from(GameSession.bond_index(), "hero:k", {"hero:m": true, "hero:r": true}, preload("res://balance.tres"))["partner"], "hero:r")
	assert_eq(GameSession._team_snapshots([knight, mage, ranger] as Array[Hero])[0]["cover_order"], ["hero:r", "hero:m"])


func test_a_cover_order_survives_a_real_save_and_reload_and_a_legacy_battle_reads_as_empty() -> void:
	var knight: Hero = _cover_hero("hero:k", &"knight")
	var mage: Hero = _cover_hero("hero:m", &"mage")
	_bond_ledger({"hero:m": 3})
	var preset_id: String = GameSession.save_team_preset("", "Cover", [knight.instance_id, mage.instance_id], "verdant_outskirts")
	var order_id: String = GameSession.dispatch_force([preset_id], "verdant_outskirts", 1, {}, _zero_loadout())
	assert_ne(order_id, "", GameSession.last_action_error)
	GameSession.tick_expeditions(1.0)
	assert_eq(_knight_cover(GameSession.to_dict()), ["hero:m"], "the launch copied it onto the Knight actor")
	# Through disk: SaveService writes the file and a fresh session reads it back.
	GameSession.set("_save_deferred_depth", 0)
	var saved: bool = SaveService.save()
	GameSession.set("_save_deferred_depth", 1)
	assert_true(saved, SaveService.last_write_error)
	GameSession.from_dict({"roster": []})
	assert_true(GameSession.get_battle_snapshot(order_id).is_empty())
	assert_true(SaveService.load_game(), SaveService.load_block_reason)
	_land_catch_ups()
	assert_eq(_knight_cover(GameSession.to_dict()), ["hero:m"], "equal after the reload")
	var profile: Dictionary = Compare.json_round_trip(GameSession.to_dict())
	# A battle from before the key: it loads as [] and advances.
	var legacy: Dictionary = Compare.json_round_trip(profile)
	_knight_effects(legacy).erase("cover_order")
	assert_eq(GameSession.validate_saved_state(legacy, 3), "")
	GameSession.from_dict(legacy)
	var tick: int = int(GameSession.get_battle_snapshot(order_id)["tick"])
	for actor: Dictionary in GameSession.get_battle_snapshot(order_id)["actors"]:
		if actor["archetype"] == "knight":
			assert_eq((actor["effect_state"] as Dictionary).get("cover_order", []), [], "a legacy Knight reads as []")
	GameSession.tick_expeditions(1.0)
	assert_gt(int(GameSession.get_battle_snapshot(order_id)["tick"]), tick, "and advances")
	for bad_value: Variant in [["hero:m", 3], "hero:m", [null], {}]:
		var broken: Dictionary = Compare.json_round_trip(profile)
		_knight_effects(broken)["cover_order"] = bad_value
		assert_string_contains(GameSession.validate_saved_state(broken, 3), "cover_order", "cover_order %s is rejected" % str(bad_value))


## ig-1jw (boundary #1): a mid-battle checkpoint keeps its pace through a real save and reload. One from
## before the key loads as pace 1 and settles at pace-1 rewards.
func test_a_battle_keeps_its_pace_through_a_real_save_and_a_legacy_one_is_pace_1() -> void:
	var balance: BalanceTable = preload("res://balance.tres")
	var zone: ZoneDefinition = ZoneDefinition.definition_for(&"verdant_outskirts")
	var knight: Hero = _cover_hero("hero:k", &"knight")
	var preset_id: String = GameSession.save_team_preset("", "Pace", [knight.instance_id], "verdant_outskirts")
	var order_id: String = GameSession.dispatch_force([preset_id], "verdant_outskirts", 1, {}, _zero_loadout())
	assert_ne(order_id, "", GameSession.last_action_error)
	GameSession.tick_expeditions(1.0)
	var battle: Dictionary = GameSession.get_battle_snapshot(order_id)
	assert_eq(str(battle["status"]), "active", "mid-battle")
	assert_eq(int(battle["pace"]), balance.battle_pace)
	# Through disk: SaveService writes the file and a fresh session reads it back.
	GameSession.set("_save_deferred_depth", 0)
	var saved: bool = SaveService.save()
	GameSession.set("_save_deferred_depth", 1)
	assert_true(saved, SaveService.last_write_error)
	GameSession.from_dict({"roster": []})
	assert_true(GameSession.get_battle_snapshot(order_id).is_empty())
	assert_true(SaveService.load_game(), SaveService.load_block_reason)
	_land_catch_ups()
	var reloaded := BattleState.from_dict(GameSession.expedition_orders[0]["battle"] as Dictionary)
	assert_eq(reloaded.pace, balance.battle_pace, "equal after the reload")
	assert_eq(reloaded.max_seconds, zone.max_battle_seconds * balance.battle_pace)
	var profile: Dictionary = Compare.json_round_trip(GameSession.to_dict())
	var paid: int = _victory_pay(balance.battle_pace)
	assert_eq(_settle_as_victory(), [paid, balance.battle_pace], "stones and loot rolls xP")
	# A battle from before the key (and inside the pace-1 bound): pace 1, pace-1 rewards.
	var legacy: Dictionary = Compare.json_round_trip(profile)
	var legacy_battle: Dictionary = (legacy["expedition_orders"] as Array)[0]["battle"] as Dictionary
	legacy_battle.erase("pace")
	legacy_battle["max_seconds"] = zone.max_battle_seconds
	assert_eq(GameSession.validate_saved_state(legacy, 3), "")
	GameSession.from_dict(legacy)
	assert_eq(BattleState.from_dict(GameSession.expedition_orders[0]["battle"] as Dictionary).pace, 1, "a legacy battle reads as pace 1")
	GameSession.tick_expeditions(1.0)
	assert_eq(int(GameSession.get_battle_snapshot(order_id)["pace"]), 1, "and keeps it as it advances")
	paid = _victory_pay(1)
	assert_eq(_settle_as_victory(), [paid, 1], "stones and one loot roll")


## ig-7sn.15 (ACC 6): five battles mid-fight, driven by frames so each holds a kept state and owed time,
## survive a real save and reload. The kept states add nothing saved, and each battle resumes.
func test_five_battles_mid_fight_survive_a_real_save_and_each_resumes() -> void:
	for index: int in 5:
		var knight: Hero = _cover_hero("hero:k%d" % index, &"knight")
		var preset_id: String = GameSession.save_team_preset("", "Five %d" % index, [knight.instance_id], "verdant_outskirts")
		assert_ne(GameSession.dispatch_force([preset_id], "verdant_outskirts", 1, {}, _zero_loadout()), "", GameSession.last_action_error)
	GameSession.set_process(false)
	for ignored_frame: int in 100:
		_finish_advance_jobs()
		GameSession._process(1.0 / 60.0)
	# ig-7sn.18: a battle whose job is out holds no kept state until it lands; run until none is out.
	for ignored_frame: int in 60:
		if GameSession._battle_advances.is_empty():
			break
		_finish_advance_jobs()
		GameSession._process(1.0 / 60.0)
	assert_true(GameSession._battle_advances.is_empty(), "every job landed")
	GameSession.set_process(true)
	var saved_battles: Dictionary = {}
	for order: Dictionary in GameSession.expedition_orders:
		var battle: Dictionary = order["battle"] as Dictionary
		assert_eq(str(battle["status"]), "active", "mid-fight")
		assert_gt(float(battle["elapsed_seconds"]), 0.0, "it advanced")
		saved_battles[order["id"]] = Compare.json_round_trip(battle)  # As the save writes it.
	assert_eq(saved_battles.size(), 5)
	assert_eq(GameSession._battle_states.size(), 5, "each holds a kept state")
	# Nothing saved reads the kept states or the owed time.
	var profile: String = _exact_json(GameSession.to_dict())
	var kept: Dictionary = GameSession._battle_states.duplicate()
	var owed: Dictionary = GameSession._battle_owed.duplicate()
	assert_false(owed.is_empty(), "the battles are owed time")
	GameSession._battle_states.clear()
	GameSession._battle_owed.clear()
	assert_eq(_exact_json(GameSession.to_dict()), profile, "no saved key")
	GameSession._battle_states.assign(kept)
	GameSession._battle_owed.assign(owed)
	# Through disk: SaveService writes the file and a fresh session reads it back.
	GameSession.set("_save_deferred_depth", 0)
	var saved: bool = SaveService.save()
	GameSession.set("_save_deferred_depth", 1)
	assert_true(saved, SaveService.last_write_error)
	GameSession.from_dict({"roster": []})
	assert_true(GameSession._battle_states.is_empty(), "from_dict clears the kept states")
	assert_true(GameSession._battle_owed.is_empty(), "and the owed time")
	assert_true(SaveService.load_game(), SaveService.load_block_reason)
	assert_eq(GameSession.expedition_orders.size(), 5)
	for order: Dictionary in GameSession.expedition_orders:
		assert_eq(_exact_json(order["battle"]), _exact_json(saved_battles[order["id"]]), "%s reloads as saved" % order["id"])
	_land_catch_ups()
	var decodes: int = GameSession.pulse_decodes_active
	var resumed: Dictionary = {}
	for order: Dictionary in GameSession.expedition_orders:
		var fresh := BattleState.from_dict(order["battle"] as Dictionary)
		BattleSimulation.advance(fresh, 0.25)
		resumed[order["id"]] = fresh.to_dict()
	GameSession.tick_expeditions(0.25)
	assert_eq(GameSession.pulse_decodes_active - decodes, 5, "each reloaded battle is decoded")
	for order: Dictionary in GameSession.expedition_orders:
		assert_eq(order["battle"], resumed[order["id"]], "%s resumes" % order["id"])
		assert_gt(float((order["battle"] as Dictionary)["elapsed_seconds"]), float((saved_battles[order["id"]] as Dictionary)["elapsed_seconds"]))


## ig-7sn.18: waits until every advance job out has finished, so the next frame can land it. The game waits
## on a job only when it lands; a frame here runs what a real one would once its job is in.
func _finish_advance_jobs() -> void:
	for entry: Dictionary in GameSession._battle_advances.values():
		var job: BattleJob = entry["job"]
		while GameSession._battle_jobs.has(job) and not WorkerThreadPool.is_task_completed(job.task_id):
			OS.delay_usec(100)


## Lands the first order as a victory; returns [stones earned, items earned].
## ig-0og.1: what the first order's victory pays at pace, read from the pay helper.
func _victory_pay(pace: int) -> int:
	var order: Dictionary = GameSession.expedition_orders[0]
	var zone: ZoneDefinition = ZoneDefinition.definition_for(StringName(str(order["zone_id"])))
	var factor: float = ExpeditionOrders.route_pay_factor(zone, float(order["initial_duration_seconds"]), (order["hero_ids"] as Array).size(), pace)
	return ExpeditionOrders.stone_payout(zone, pace, preload("res://balance.tres"), factor)


func _settle_as_victory() -> Array:
	var order: Dictionary = GameSession.expedition_orders[0]
	(order["battle"] as Dictionary)["status"] = "victory"
	order["remaining_seconds"] = 0.0
	GameSession.expedition_reports.clear()
	GameSession.tick_expeditions(0.1)
	assert_eq(GameSession.expedition_reports.size(), 1, "settled: " + GameSession.last_action_error)
	return [GameSession.expedition_reports[0]["stones_earned"], GameSession.expedition_reports[0]["items_earned"]]


## ig-85w (boundary #1): a battle saved mid-fight by the real SaveService and loaded back from the file
## is its own full-precision round trip, every field ==, no tolerance, at load and 30 s later. (Not the
## unsaved battle's bits: Godot's parser misrounds some 17-digit numbers by 1 ulp, docs/KNOWN_ISSUES.md.)
## Compare.json_round_trip is fixed at full precision, so a save back at 14 digits fails here.
func test_a_checkpoint_through_the_real_save_file_reads_back_as_its_full_precision_round_trip() -> void:
	var ids: Array[String] = []
	for archetype: StringName in [&"knight", &"ranger", &"mage", &"rogue", &"cleric"]:
		var hero := Hero.new("Exact %d" % ids.size(), 0)
		hero.def_id = archetype
		hero.level = 1
		hero.instance_id = "hero:exact:%d" % ids.size()
		GameSession.roster.append(hero)
		ids.append(hero.instance_id)
	var preset_id: String = GameSession.save_team_preset("", "Exact", ids, "verdant_outskirts")
	assert_ne(GameSession.dispatch_force([preset_id], "verdant_outskirts", 1, {}, _zero_loadout()), "", GameSession.last_action_error)
	for step: int in 200:
		GameSession.tick_expeditions(0.1)
	var battle: Dictionary = GameSession.expedition_orders[0]["battle"]
	assert_eq(str(battle["status"]), "active", "mid-fight")
	var round_trip: Dictionary = Compare.json_round_trip(battle)
	var written := BattleState.from_dict(round_trip)
	var start: int = written.tick
	GameSession.set("_save_deferred_depth", 0)
	var saved: bool = SaveService.save()
	GameSession.set("_save_deferred_depth", 1)
	assert_true(saved, SaveService.last_write_error)
	# Only the stamp changes, in the text itself, so the load adds no offline time.
	var stamp := RegEx.create_from_string("\"saved_at_unix\": ?[^,}\\n]+")
	var text: String = FileAccess.get_file_as_string(SaveService.SAVE_PATH)
	assert_not_null(stamp.search(text))
	var file := FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	file.store_string(stamp.sub(text, "\"saved_at_unix\":%d" % int(Time.get_unix_time_from_system() + 3600.0)))
	file.close()
	GameSession.from_dict({"roster": []})
	assert_true(SaveService.load_game(), SaveService.load_block_reason)
	var read_back: Dictionary = GameSession.expedition_orders[0]["battle"]
	assert_eq(Compare.first_difference(read_back, round_trip), "", "the file reads back as the round trip, raw")
	var loaded := BattleState.from_dict(read_back)
	for step: int in 300:
		BattleSimulation.advance(written, 0.1)
		BattleSimulation.advance(loaded, 0.1)
	assert_eq(written.tick, start + 300, "it ran on all 30 s")
	assert_eq(Compare.first_difference(loaded.to_dict(), written.to_dict()), "", "and runs on the same")


## ig-7sn.10 ACC 3 (boundary #1): five battles out through the compact save text (one line, keys in
## to_dict's order) and a real reload. The file is the payload's own text; the reload is exact against its
## full-precision round trip; each battle, run on 30 s, stays within 1e-6 of the unsaved run; and the same
## payload in the old form (tab-indented, sorted, full precision) loads to the same state.
func test_five_battles_through_the_compact_save_and_the_old_pretty_form() -> void:
	var zones: Array[String] = ["verdant_outskirts", "ashfall_reaches", "sundered_vault", "fallen_citadel", "frontier_march"]
	for zone_id: String in zones:
		GameSession.mark_zone_cleared(StringName(zone_id))
	for zone_id: String in zones:
		assert_ne(GameSession.dispatch_force(_add_force(2, 1, zone_id, zone_id), zone_id, 1, {}, _zero_loadout()), "", GameSession.last_action_error)
	for step: int in 100:
		GameSession.tick_expeditions(0.1)
	var unsaved: Dictionary = {}
	for order: Dictionary in GameSession.expedition_orders:
		assert_eq(str((order["battle"] as Dictionary)["status"]), "active", "%s mid-fight" % order["zone_id"])
		unsaved[order["id"]] = BattleState.from_dict(order["battle"] as Dictionary)
	assert_eq(unsaved.size(), 5)
	var payload: Dictionary = GameSession.to_dict()
	GameSession.set("_save_deferred_depth", 0)
	var saved: bool = SaveService.save()
	GameSession.set("_save_deferred_depth", 1)
	assert_true(saved, SaveService.last_write_error)
	payload["version"] = SaveService.SAVE_VERSION
	payload["saved_at_unix"] = GameSession.saved_at_unix
	var text: String = FileAccess.get_file_as_string(SaveService.SAVE_PATH)
	assert_eq(text, JSON.stringify(payload, "", false, true), "the file is the payload's compact text")
	assert_false(text.contains("\n") or text.contains("\t"), "one line, no indent")
	var future: int = int(Time.get_unix_time_from_system() + 3600.0)
	payload["saved_at_unix"] = future
	var expected: Dictionary = Compare.json_round_trip(payload)
	# Only the stamp changes, in the text itself, so the load adds no offline time.
	var stamp := RegEx.create_from_string("\"saved_at_unix\":[^,}]+")
	assert_not_null(stamp.search(text))
	var file := FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	file.store_string(stamp.sub(text, "\"saved_at_unix\":%d" % future))
	file.close()
	assert_eq(Compare.first_difference(JSON.parse_string(FileAccess.get_file_as_string(SaveService.SAVE_PATH)), expected), "", "the file reads back as the payload's round trip")
	GameSession.from_dict({"roster": []})
	assert_true(SaveService.load_game(), SaveService.load_block_reason)
	assert_eq(GameSession.expedition_orders.size(), 5)
	for index: int in GameSession.expedition_orders.size():
		var order: Dictionary = GameSession.expedition_orders[index]
		assert_eq(Compare.first_difference(order["battle"], (expected["expedition_orders"][index] as Dictionary)["battle"]), "", "%s reloads exactly" % order["zone_id"])
	var compact_state: String = _exact_json(GameSession.to_dict())
	for order: Dictionary in GameSession.expedition_orders:
		var loaded := BattleState.from_dict(order["battle"] as Dictionary)
		var straight: BattleState = unsaved[order["id"]]
		for step: int in 300:
			BattleSimulation.advance(loaded, 0.1)
			BattleSimulation.advance(straight, 0.1)
		assert_eq(Compare.mismatch(_rows(loaded.to_dict()), _rows(straight.to_dict())), "", "%s runs on as the unsaved battle, to 1e-6" % order["zone_id"])
	# The old form: what every save before ig-7sn.10 wrote.
	file = FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload, "\t", true, true))
	file.close()
	GameSession.from_dict({"roster": []})
	assert_true(SaveService.load_game(), SaveService.load_block_reason)
	assert_eq(_exact_json(GameSession.to_dict()), compact_state, "the pretty form loads to the same state")
	for index: int in GameSession.expedition_orders.size():
		var order: Dictionary = GameSession.expedition_orders[index]
		assert_eq(Compare.first_difference(order["battle"], (expected["expedition_orders"][index] as Dictionary)["battle"]), "", "%s reloads exactly from the old form" % order["zone_id"])


## Rows for Compare.mismatch: each actor's id, life, tick and RNG exactly; hp and position to 1e-6.
func _rows(snapshot: Dictionary) -> Array:
	var rows: Array = []
	for actor: Dictionary in snapshot["actors"]:
		rows.append(["%s %s %s %d" % [snapshot["rng_state"], actor["id"], actor["life"], int(snapshot["tick"])], float(actor["hp"]), float(actor["position"][0]), float(actor["position"][1])])
	return rows


func _cover_hero(id: String, def_id: StringName) -> Hero:
	var hero := Hero.new(id, 7)
	hero.def_id = def_id
	hero.level = 80
	hero.instance_id = id
	GameSession.roster.append(hero)
	return hero


## A fresh ledger where the Knight "hero:k" saved each other hero `saves` times: 3 points each, and a
## routine victory together for 0.
func _bond_ledger(saves: Dictionary) -> void:
	var ledger: Array[Dictionary] = []
	for hero_id: String in saves:
		var count: int = maxi(int(saves[hero_id]), 1)
		for index: int in count:
			var moments: Array = [{"tick": 1, "what": "revived", "hero": hero_id, "by": "hero:k"}] if int(saves[hero_id]) > 0 else []
			Ledger.append(ledger, ledger.size() + 1, 0, "battle", {"order": "order:%d" % ledger.size(), "zone": "verdant_outskirts", "team": ["hero:k", hero_id], "result": "victory", "moments": moments})
	GameSession.ledger = ledger
	GameSession.ledger_next_seq = ledger.size() + 1


func _knight_effects(profile: Dictionary) -> Dictionary:
	for actor: Variant in ((profile["expedition_orders"] as Array)[0]["battle"] as Dictionary)["actors"]:
		if (actor as Dictionary)["archetype"] == "knight":
			return (actor as Dictionary)["effect_state"] as Dictionary
	return {}


func _knight_cover(profile: Dictionary) -> Variant:
	return _knight_effects(profile).get("cover_order")


func test_v3_validation_rejects_orphaned_mislinked_or_cross_zone_rescue_orders() -> void:
	var valid_fixture: Dictionary = _active_rescue_fixture()
	assert_eq(GameSession.validate_saved_state(valid_fixture, 3), "")

	var missing_incident: Dictionary = valid_fixture.duplicate(true)
	missing_incident["stranded_incidents"] = []
	assert_string_contains(GameSession.validate_saved_state(missing_incident, 3), "matching stranded incident backlink")

	var cleared_backlink: Dictionary = valid_fixture.duplicate(true)
	var cleared_incident: Dictionary = (cleared_backlink["stranded_incidents"] as Array)[0]
	cleared_incident["active_rescue_order_id"] = ""
	assert_string_contains(GameSession.validate_saved_state(cleared_backlink, 3), "matching stranded incident backlink")

	var wrong_backlink: Dictionary = valid_fixture.duplicate(true)
	var wrong_incident: Dictionary = (wrong_backlink["stranded_incidents"] as Array)[0]
	wrong_incident["active_rescue_order_id"] = "missing:rescue"
	assert_string_contains(GameSession.validate_saved_state(wrong_backlink, 3), "missing active rescue")

	var wrong_zone: Dictionary = valid_fixture.duplicate(true)
	wrong_zone["cleared_zone_ids"] = ["verdant_outskirts"]
	var wrong_zone_order: Dictionary = (wrong_zone["expedition_orders"] as Array)[0]
	wrong_zone_order["zone_id"] = "ashfall_reaches"
	(wrong_zone_order["battle"] as Dictionary)["zone_id"] = "ashfall_reaches"
	assert_string_contains(GameSession.validate_saved_state(wrong_zone, 3), "same zone")


func test_partial_timeout_defers_incident_until_return_then_abandonment_removes_once() -> void:
	var returned := Hero.new("Returned", 7)
	returned.def_id = &"knight"
	returned.level = 80
	returned.instance_id = "hero:returned"
	var stranded := Hero.new("Stranded", 7)
	stranded.def_id = &"rogue"
	stranded.level = 80
	stranded.instance_id = "hero:stranded"
	stranded.equipped[0] = Item.new(&"head", 0)
	GameSession.roster.append_array([returned, stranded])
	var preset_id: String = GameSession.save_team_preset("", "Partial Team", [returned.instance_id, stranded.instance_id], "verdant_outskirts")
	var order_id: String = GameSession.dispatch_force([preset_id], "verdant_outskirts", 1, {}, _zero_loadout())
	var order: Dictionary = GameSession.expedition_orders[0]
	var battle: Dictionary = order["battle"] as Dictionary
	for actor: Dictionary in battle["actors"] as Array[Dictionary]:
		if str(actor["hero_id"]) == returned.instance_id:
			actor["life"] = BattleActor.LIFE_EXTRACTED
		elif str(actor["hero_id"]) == stranded.instance_id:
			actor["life"] = BattleActor.LIFE_DOWNED
			actor["hp"] = 0.0
	battle["status"] = "timeout"
	battle["extracted_ids"] = [returned.instance_id]
	battle["downed_ever_ids"] = [stranded.instance_id]
	order["phase"] = "returning"
	order["remaining_seconds"] = 5.0
	GameSession.tick_expeditions(0.1)
	assert_true(GameSession.stranded_incidents.is_empty())
	assert_eq(GameSession.expedition_orders[0]["id"], order_id)
	GameSession.expedition_orders[0]["remaining_seconds"] = 0.0
	GameSession.tick_expeditions(0.1)
	assert_true(GameSession.expedition_orders.is_empty())
	assert_eq(GameSession.stranded_incidents.size(), 1)
	assert_eq(GameSession.stranded_incidents[0]["hero_ids"], [stranded.instance_id])
	assert_true(GameSession.is_hero_busy(stranded))
	var sacrifice_preview: Dictionary = GameSession.preview_bulk_sacrifice([stranded.instance_id], returned.instance_id, 1)
	assert_false(bool(sacrifice_preview["valid"]))
	assert_eq((sacrifice_preview["excluded"] as Array)[0]["reason"], "away")
	var incident_id: String = str(GameSession.stranded_incidents[0]["id"])
	assert_true(GameSession.abandon_stranded(incident_id))
	assert_null(GameSession.hero_by_id(stranded.instance_id))
	assert_not_null(GameSession.hero_by_id(returned.instance_id))
	assert_eq(GameSession.lost_caches.size(), 1)
	assert_false(GameSession.abandon_stranded(incident_id))
	assert_eq(GameSession.lost_caches.size(), 1)
	assert_eq(GameSession.validate_saved_state(GameSession.to_dict(), 3), "")


func test_large_incident_keeps_original_deadline_across_two_failed_five_hero_rescues() -> void:
	GameSession.cleared_zone_ids[&"verdant_outskirts"] = true
	GameSession.cleared_zone_ids[&"ashfall_reaches"] = true
	var source_presets: Array[String] = _add_force(50, 10, "frontier_march", "source")
	var source_order_id: String = GameSession.dispatch_force(source_presets, "frontier_march", 1, {}, _zero_loadout())
	assert_ne(source_order_id, "")
	_fail_all_allies(source_order_id)
	GameSession.tick_expeditions(0.1)
	assert_true(GameSession.expedition_orders.is_empty())
	assert_eq((GameSession.stranded_incidents[0]["hero_ids"] as Array).size(), 50)
	var incident_id: String = str(GameSession.stranded_incidents[0]["id"])
	var paused_created: float = float(GameSession.stranded_incidents[0]["created_recovery_seconds"])
	assert_eq(GameSession.dispatch_rescue(incident_id, "missing", _zero_loadout()), "")
	assert_true(bool(GameSession.stranded_incidents[0]["paused"]))
	assert_eq(float(GameSession.stranded_incidents[0]["created_recovery_seconds"]), paused_created)
	for attempt: int in 2:
		var rescue_preset: String = _add_force(5, 1, "frontier_march", "rescue%d" % attempt)[0]
		var rescue_order_id: String = GameSession.dispatch_rescue(incident_id, rescue_preset, _zero_loadout())
		assert_ne(rescue_order_id, "")
		var deadline_origin: float = float(GameSession.stranded_incidents[0]["created_recovery_seconds"])
		_fail_all_allies(rescue_order_id)
		GameSession.tick_expeditions(0.1)
		assert_eq((GameSession.stranded_incidents[0]["hero_ids"] as Array).size(), 55 + attempt * 5)
		assert_eq(float(GameSession.stranded_incidents[0]["created_recovery_seconds"]), deadline_origin)
	assert_eq(GameSession.validate_saved_state(GameSession.to_dict(), 3), "")


func test_incident_expiry_defers_permanent_loss_while_rescue_attempt_is_active() -> void:
	var source_preset: String = _add_force(1, 1, "verdant_outskirts", "expiry_source")[0]
	var source_hero_id: String = str(GameSession.team_presets.back()["hero_ids"][0])
	var source_order_id: String = GameSession.dispatch_force([source_preset], "verdant_outskirts", 1, {}, _zero_loadout())
	_fail_all_allies(source_order_id)
	GameSession.tick_expeditions(0.1)
	var incident_id: String = str(GameSession.stranded_incidents[0]["id"])
	var rescue_preset: String = _add_force(1, 1, "verdant_outskirts", "expiry_rescue")[0]
	var rescue_hero_id: String = str(GameSession.team_presets.back()["hero_ids"][0])
	var rescue_order_id: String = GameSession.dispatch_rescue(incident_id, rescue_preset, _zero_loadout())
	assert_ne(rescue_order_id, "")
	var balance: BalanceTable = preload("res://balance.tres")
	GameSession.rescue_clock_seconds = float(GameSession.stranded_incidents[0]["created_recovery_seconds"]) + balance.recovery_base_duration_seconds * balance.battle_pace + 1.0
	GameSession.tick_expeditions(0.1)
	assert_eq(GameSession.stranded_incidents.size(), 1)
	assert_true(bool(GameSession.stranded_incidents[0]["expiry_pending"]))
	assert_not_null(GameSession.hero_by_id(source_hero_id))
	assert_not_null(GameSession.hero_by_id(rescue_hero_id))
	_fail_all_allies(rescue_order_id)
	GameSession.tick_expeditions(0.1)
	assert_true(GameSession.stranded_incidents.is_empty())
	assert_true(GameSession.expedition_orders.is_empty())
	assert_null(GameSession.hero_by_id(source_hero_id))
	assert_null(GameSession.hero_by_id(rescue_hero_id))


func test_partial_rescue_prunes_secured_hero_so_later_profile_removal_keeps_incident_valid() -> void:
	var source_preset: String = _add_force(1, 1, "verdant_outskirts", "prune_source")[0]
	var source_hero_id: String = str(GameSession.team_presets.back()["hero_ids"][0])
	var source_order_id: String = GameSession.dispatch_force([source_preset], "verdant_outskirts", 1, {}, _zero_loadout())
	_fail_all_allies(source_order_id)
	GameSession.tick_expeditions(0.1)
	var incident_id: String = str(GameSession.stranded_incidents[0]["id"])
	var rescue_preset: String = _add_force(1, 1, "verdant_outskirts", "prune_rescuer")[0]
	var rescuer_id: String = str(GameSession.team_presets.back()["hero_ids"][0])
	var rescue_order_id: String = GameSession.dispatch_rescue(incident_id, rescue_preset, _zero_loadout())
	assert_ne(rescue_order_id, "")
	var rescue_order: Dictionary = GameSession.expedition_orders[0]
	var battle: Dictionary = rescue_order["battle"] as Dictionary
	for actor: Dictionary in battle["actors"] as Array[Dictionary]:
		if str(actor["hero_id"]) == source_hero_id:
			actor["life"] = BattleActor.LIFE_EXTRACTED
			actor["hp"] = maxf(float(actor["hp"]), 1.0)
		elif str(actor["hero_id"]) == rescuer_id:
			actor["life"] = BattleActor.LIFE_DOWNED
			actor["hp"] = 0.0
	battle["status"] = "stranded"
	battle["extracted_ids"] = [source_hero_id]
	battle["downed_ever_ids"] = [source_hero_id, rescuer_id]
	rescue_order["phase"] = "returning"
	rescue_order["remaining_seconds"] = 0.0
	GameSession.tick_expeditions(0.1)
	assert_true(GameSession.expedition_orders.is_empty())
	assert_eq(GameSession.stranded_incidents[0]["hero_ids"], [rescuer_id])
	assert_false(GameSession.is_hero_busy(GameSession.hero_by_id(source_hero_id)))
	var followup_preset: String = _add_force(1, 1, "verdant_outskirts", "prune_followup")[0]
	var followup_order_id: String = GameSession.dispatch_rescue(incident_id, followup_preset, _zero_loadout())
	assert_ne(followup_order_id, "")
	assert_eq(GameSession.expedition_orders[0]["remaining_seconds"], 0.0)
	GameSession.expedition_orders.clear()
	GameSession.stranded_incidents[0]["active_rescue_order_id"] = ""
	var source_index: int = -1
	for index: int in GameSession.roster.size():
		if GameSession.roster[index].instance_id == source_hero_id:
			source_index = index
	assert_gte(source_index, 0)
	GameSession.roster.remove_at(source_index)
	assert_eq(GameSession.validate_saved_state(GameSession.to_dict(), 3), "")
	var incident_actors: Array = (GameSession.stranded_incidents[0]["battle_snapshot"] as Dictionary)["actors"] as Array
	for actor: Dictionary in incident_actors:
		assert_ne(str(actor.get("hero_id", "")), source_hero_id)


func _fail_all_allies(order_id: String) -> void:
	var order_index: int = -1
	for index: int in GameSession.expedition_orders.size():
		if str(GameSession.expedition_orders[index]["id"]) == order_id:
			order_index = index
			break
	assert_gte(order_index, 0)
	var order: Dictionary = GameSession.expedition_orders[order_index]
	var battle: Dictionary = order["battle"] as Dictionary
	var downed_ids: Array[String] = []
	for actor: Dictionary in battle["actors"] as Array[Dictionary]:
		if str(actor["faction"]) == "ally":
			actor["life"] = BattleActor.LIFE_DOWNED
			actor["hp"] = 0.0
			downed_ids.append(str(actor["hero_id"]))
	battle["status"] = "stranded"
	battle["downed_ever_ids"] = downed_ids
	battle["extracted_ids"] = []
	order["phase"] = "returning"


func _active_rescue_fixture() -> Dictionary:
	var source_preset: String = _add_force(1, 1, "verdant_outskirts", "link_source")[0]
	var source_order_id: String = GameSession.dispatch_force([source_preset], "verdant_outskirts", 1, {}, _zero_loadout())
	assert_ne(source_order_id, "")
	_fail_all_allies(source_order_id)
	GameSession.tick_expeditions(0.1)
	assert_eq(GameSession.stranded_incidents.size(), 1)
	var incident_id: String = str(GameSession.stranded_incidents[0]["id"])
	var rescue_preset: String = _add_force(1, 1, "verdant_outskirts", "link_rescuer")[0]
	var rescue_order_id: String = GameSession.dispatch_rescue(incident_id, rescue_preset, _zero_loadout())
	assert_ne(rescue_order_id, "")
	return GameSession.to_dict()


func _add_force(hero_count: int, squad_count: int, zone_id: String, prefix: String) -> Array[String]:
	var result: Array[String] = []
	for squad_index: int in squad_count:
		var ids: Array[String] = []
		for member_index: int in hero_count / squad_count:
			var hero := Hero.new("%s %d-%d" % [prefix, squad_index, member_index], 7)
			hero.def_id = &"knight"
			hero.level = 80
			hero.instance_id = "hero:%s:%d:%d" % [prefix, squad_index, member_index]
			GameSession.roster.append(hero)
			ids.append(hero.instance_id)
		result.append(GameSession.save_team_preset("", "%s squad %d" % [prefix, squad_index], ids, zone_id))
	return result


func _zero_loadout() -> Dictionary:
	return {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0}


## ig-7sn.12: a load owes its offline battle-seconds as catch_up_seconds, run as jobs after it. This
## sends them and lands the round (without advancing any battle).
func _land_catch_ups() -> void:
	GameSession._send_battle_checks()
	var deadline: int = Time.get_ticks_msec() + 60000
	while not GameSession._battle_checks.is_empty() and Time.get_ticks_msec() < deadline:
		OS.delay_msec(1)
		GameSession._land_battle_checks()
	assert_true(GameSession._battle_checks.is_empty(), "the catch-up landed")
