extends GutTest


func before_each() -> void:
	GameSession.set("_save_deferred_depth", 1)
	GameSession.from_dict({"roster": []})
	GameSession.last_action_error = ""
	SaveService.load_blocked = false


func after_each() -> void:
	GameSession.set("_save_deferred_depth", 0)


func test_force_dispatch_escrows_supplies_and_returns_detached_snapshot() -> void:
	var hero := Hero.new("Battle Tester", 0)
	hero.def_id = &"knight"
	hero.instance_id = "hero:battle"
	GameSession.roster.append(hero)
	var preset_id: String = GameSession.save_team_preset("", "Alpha", [hero.instance_id], "verdant_outskirts")
	var order_id: String = GameSession.dispatch_force([preset_id], "verdant_outskirts", 1, {}, {"healing": 1, "revival": 1, "keep_healing": 0, "keep_revival": 0})
	assert_ne(order_id, "")
	assert_eq(GameSession.supplies, {"healing": 2, "revival": 0, "healing_masterwork": 0, "revival_masterwork": 0})
	var snapshot: Dictionary = GameSession.get_battle_snapshot(order_id)
	assert_eq(snapshot["phase"], "fighting")
	assert_false(bool(snapshot["paused"]))
	snapshot["status"] = "tampered"
	assert_ne(GameSession.get_battle_snapshot(order_id)["status"], "tampered")


func test_pause_is_transient_and_item_auto_command_updates_both_flags() -> void:
	var order_id: String = _dispatch_one()
	GameSession.set_battle_paused(order_id, true)
	assert_true(bool(GameSession.get_battle_snapshot(order_id)["paused"]))
	var result: Dictionary = GameSession.issue_battle_command(order_id, {"kind": BattleSimulation.COMMAND_SET_ITEM_AUTO, "value": {"auto_heal": false, "auto_revive": true}})
	assert_true(bool(result["accepted"]))
	var durable: Dictionary = GameSession.to_dict()
	GameSession.from_dict(durable)
	assert_false(bool(GameSession.get_battle_snapshot(order_id)["paused"]))
	var policies: Dictionary = GameSession.get_battle_snapshot(order_id)["policies"] as Dictionary
	assert_false(bool(policies["auto_heal"]))
	assert_true(bool(policies["auto_revive"]))


func test_force_dispatch_supports_authored_3_5_30_and_50_hero_sizes() -> void:
	for fixture: Dictionary in [
		{"count": 3, "zone": "verdant_outskirts", "squads": 1},
		{"count": 5, "zone": "verdant_outskirts", "squads": 1},
		{"count": 30, "zone": "fallen_citadel", "squads": 6},
		{"count": 50, "zone": "frontier_march", "squads": 10},
	]:
		GameSession.from_dict({"roster": []})
		GameSession.cleared_zone_ids[&"verdant_outskirts"] = true
		GameSession.cleared_zone_ids[&"ashfall_reaches"] = true
		var preset_ids: Array[String] = _add_force(int(fixture["count"]), int(fixture["squads"]), str(fixture["zone"]))
		var order_id: String = GameSession.dispatch_force(preset_ids, str(fixture["zone"]), 1, {}, _zero_loadout())
		assert_ne(order_id, "", "%d heroes must dispatch to %s" % [fixture["count"], fixture["zone"]])
		assert_eq((GameSession.expedition_orders[0]["hero_ids"] as Array).size(), int(fixture["count"]))
		assert_true(GameSession.is_hero_busy(GameSession.roster[0]))
		assert_true(GameSession.is_hero_busy(GameSession.roster.back()))


func test_force_rejects_overlap_capacity_and_malformed_policies_without_reserving_heroes() -> void:
	GameSession.cleared_zone_ids[&"verdant_outskirts"] = true
	GameSession.cleared_zone_ids[&"ashfall_reaches"] = true
	var preset_ids: Array[String] = _add_force(35, 7, "fallen_citadel")
	var over_cap: Dictionary = GameSession.preview_force(preset_ids, "fallen_citadel", 1, {}, _zero_loadout())
	assert_false(bool(over_cap["valid"]))
	assert_string_contains(str(over_cap["error"]), "at most 6 squads")
	var overlap_ids: Array[String] = [preset_ids[0], preset_ids[1]]
	var duplicate_hero_id: String = str(GameSession.team_presets[0]["hero_ids"][0])
	GameSession.team_presets[1]["hero_ids"][0] = duplicate_hero_id
	var overlap: Dictionary = GameSession.preview_force(overlap_ids, "fallen_citadel", 1, {}, _zero_loadout())
	assert_false(bool(overlap["valid"]))
	assert_string_contains(str(overlap["error"]), "more than one squad")
	var malformed: Dictionary = GameSession.preview_force([preset_ids[0]], "fallen_citadel", 1, {"auto_battle": "yes"}, _zero_loadout())
	assert_false(bool(malformed["valid"]))
	assert_true(GameSession.expedition_orders.is_empty())
	assert_false(GameSession.is_hero_busy(GameSession.roster[0]))


func test_force_rejects_authored_squad_count_even_when_hero_capacity_allows_it() -> void:
	GameSession.cleared_zone_ids[&"verdant_outskirts"] = true
	GameSession.cleared_zone_ids[&"ashfall_reaches"] = true
	var standard_presets: Array[String] = _add_force(2, 2, "verdant_outskirts")
	var standard: Dictionary = GameSession.preview_force(standard_presets, "verdant_outskirts", 1, {}, _zero_loadout())
	assert_false(bool(standard["valid"]))
	assert_string_contains(str(standard["error"]), "at most 1 squads")
	GameSession.from_dict({"roster": []})
	GameSession.cleared_zone_ids[&"verdant_outskirts"] = true
	GameSession.cleared_zone_ids[&"ashfall_reaches"] = true
	var raid_presets: Array[String] = _add_force(7, 7, "fallen_citadel")
	var raid: Dictionary = GameSession.preview_force(raid_presets, "fallen_citadel", 1, {}, _zero_loadout())
	assert_false(bool(raid["valid"]))
	assert_string_contains(str(raid["error"]), "at most 6 squads")
	assert_true(GameSession.expedition_orders.is_empty())


func test_background_tick_matches_direct_canonical_simulation_checkpoint() -> void:
	var order_id: String = _dispatch_one()
	var expected := BattleState.from_dict(GameSession.get_battle_snapshot(order_id))
	BattleSimulation.advance(expected, 2.5)
	GameSession.tick_expeditions(2.5)
	var actual: Dictionary = GameSession.get_battle_snapshot(order_id)
	for transient_key: String in ["phase", "route_remaining_seconds", "team_name", "paused", "catching_up", "last_command_error", "checkpoint_error"]:
		actual.erase(transient_key)
	assert_eq(actual, expected.to_dict())


func test_completed_leg_stops_on_request_and_refunds_unused_supply_once() -> void:
	var hero := Hero.new("Stop Tester", 7)
	hero.def_id = &"knight"
	hero.level = 80
	hero.instance_id = "hero:stop"
	GameSession.roster.append(hero)
	var preset_id: String = GameSession.save_team_preset("", "Stop Team", [hero.instance_id], "verdant_outskirts")
	var order_id: String = GameSession.dispatch_force([preset_id], "verdant_outskirts", 2, {}, {"healing": 1, "revival": 0, "keep_healing": 0, "keep_revival": 0})
	assert_ne(order_id, "")
	var order: Dictionary = GameSession.expedition_orders[0]
	order["stop_requested"] = true
	(order["battle"] as Dictionary)["status"] = "victory"
	order["remaining_seconds"] = 0.0
	GameSession.tick_expeditions(0.1)
	assert_true(GameSession.expedition_orders.is_empty())
	assert_eq(GameSession.supplies["healing"], 3)
	assert_eq(GameSession.expedition_reports.back()["stopped_reason"], "requested")


func test_repeat_stops_on_downing_or_exact_reserve_refill_failure() -> void:
	var order_id: String = _dispatch_strong_repeat({"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0})
	assert_ne(order_id, "")
	var order: Dictionary = GameSession.expedition_orders[0]
	(order["battle"] as Dictionary)["status"] = "victory"
	(order["battle"] as Dictionary)["downed_ever_ids"] = [str((order["hero_ids"] as Array)[0])]
	order["remaining_seconds"] = 0.0
	GameSession.tick_expeditions(0.1)
	assert_true(GameSession.expedition_orders.is_empty())
	assert_eq(GameSession.expedition_reports.back()["stopped_reason"], "downed")
	GameSession.from_dict({"roster": []})
	order_id = _dispatch_strong_repeat({"healing": 1, "revival": 0, "keep_healing": 2, "keep_revival": 0})
	assert_ne(order_id, "")
	order = GameSession.expedition_orders[0]
	(order["battle"] as Dictionary)["status"] = "victory"
	(order["battle"] as Dictionary)["supplies_remaining"] = {"healing": 0, "revival": 0}
	order["remaining_seconds"] = 0.0
	GameSession.tick_expeditions(0.1)
	assert_true(GameSession.expedition_orders.is_empty())
	assert_eq(GameSession.supplies["healing"], 2)
	assert_eq(GameSession.expedition_reports.back()["stopped_reason"], "insufficient_refill")


func test_offline_progress_settles_at_most_one_leg_and_does_not_spend_excess_on_repeat() -> void:
	var order_id: String = _dispatch_strong_repeat(_zero_loadout())
	var order: Dictionary = GameSession.expedition_orders[0]
	(order["battle"] as Dictionary)["status"] = "victory"
	order["remaining_seconds"] = 0.0
	GameSession.saved_at_unix = 1.0
	GameSession.apply_offline_expedition_progress(100000.0)
	assert_eq(GameSession.expedition_reports.size(), 1)
	assert_eq(GameSession.expedition_orders.size(), 1)
	assert_eq(GameSession.expedition_orders[0]["id"], order_id)
	assert_eq(GameSession.expedition_orders[0]["runs_completed"], 1)
	# The load runs no forecast: the repeat waits in "checking" for the pulse (ig-7sn.6).
	assert_eq(GameSession.expedition_orders[0]["phase"], "checking")
	assert_true(GameSession._battle_checks.is_empty(), "no check sent inside the load")
	_land_repeat_checks()
	assert_eq(GameSession.expedition_reports.size(), 1)
	assert_eq(GameSession.expedition_orders[0]["runs_completed"], 1)
	assert_eq((GameSession.expedition_orders[0]["battle"] as Dictionary)["tick"], 0)
	assert_almost_eq(float(GameSession.expedition_orders[0]["remaining_seconds"]), float(GameSession.expedition_orders[0]["initial_duration_seconds"]), 0.001)


## ig-7sn.4: a launch or a repeat builds its team snapshot once; the forecasts and the run share it.
func test_a_launch_and_a_repeat_build_the_team_snapshot_once() -> void:
	var builds: int = GameSession.team_snapshot_builds
	var order_id: String = _dispatch_strong_repeat(_zero_loadout(), 0)
	assert_ne(order_id, "", GameSession.last_action_error)
	assert_eq(GameSession.team_snapshot_builds, builds + 1, "until stopped: the preview forecast, the forecast and the run")
	# The shared snapshot starts the same run a fresh one would.
	var order: Dictionary = GameSession.expedition_orders[0]
	var team: Array[Hero] = []
	for hero_id: String in GameSession._string_array(order["hero_ids"]):
		team.append(GameSession.hero_by_id(hero_id))
	var squads: Array[Dictionary] = []
	for squad: Dictionary in order["squads"]:
		squads.append(squad)
	var zone: ZoneDefinition = ZoneDefinition.definition_for(&"verdant_outskirts")
	var fresh: BattleState = BattleSimulation.create_run(order_id, GameSession._team_snapshots(team, squads), zone, squads, order["policies"] as Dictionary, order["escrow"] as Dictionary, int(order["run_seed"]))
	assert_eq(order["battle"], fresh.to_dict())
	builds = GameSession.team_snapshot_builds
	(order["battle"] as Dictionary)["status"] = "victory"
	order["remaining_seconds"] = 0.0
	GameSession.tick_expeditions(0.1)
	assert_eq(GameSession.expedition_orders.size(), 1, "the repeat leg starts: " + GameSession.last_action_error)
	assert_eq(GameSession.team_snapshot_builds, builds + 1, "a repeat: its forecast and its run")
	GameSession.from_dict({"roster": []})
	builds = GameSession.team_snapshot_builds
	assert_ne(_dispatch_strong_repeat(_zero_loadout(), 1), "", GameSession.last_action_error)
	assert_eq(GameSession.team_snapshot_builds, builds + 1, "a set number of runs: the preview forecast and the run")


## ig-7sn.5: the pulse's look ahead advances each battle once, and the pulse keeps that advance
## instead of simulating it again. Every pulse must still leave the battle a fresh advance would.
func test_a_pulse_advances_each_battle_once_and_as_a_fresh_advance_would() -> void:
	assert_ne(_dispatch_one(), "", GameSession.last_action_error)
	var active_pulses: int = 0
	var advances: int = GameSession.pulse_battle_advances
	var mismatched: Array[int] = []
	for pulse: int in 4000:
		var before: Dictionary = (GameSession.expedition_orders[0]["battle"] as Dictionary).duplicate(true)
		if str(before["status"]) != "active":
			break
		active_pulses += 1
		GameSession.tick_expeditions(0.25)
		var fresh := BattleState.from_dict(before)
		BattleSimulation.advance(fresh, 0.25)
		if GameSession.expedition_orders.is_empty():
			break  # The pulse that ended the battle settled the run too.
		if GameSession.expedition_orders[0]["battle"] != fresh.to_dict():
			mismatched.append(pulse)
	assert_gt(active_pulses, 10, "the battle ran")
	assert_eq(GameSession.expedition_reports.size(), 1, "the run settled")
	assert_eq(mismatched, [] as Array[int], "every pulse leaves what a fresh advance would")
	assert_eq(GameSession.pulse_battle_advances - advances, active_pulses, "one advance per active pulse (was two)")


func _dispatch_one() -> String:
	var hero := Hero.new("Battle Tester", 0)
	hero.def_id = &"knight"
	hero.instance_id = "hero:battle"
	GameSession.roster.append(hero)
	var preset_id: String = GameSession.save_team_preset("", "Alpha", [hero.instance_id], "verdant_outskirts")
	return GameSession.dispatch_force([preset_id], "verdant_outskirts", 1, {}, {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0})


func _add_force(hero_count: int, squad_count: int, zone_id: String) -> Array[String]:
	var preset_ids: Array[String] = []
	var archetypes: Array[StringName] = [&"knight", &"ranger", &"mage", &"rogue"]
	for squad_index: int in squad_count:
		var ids: Array[String] = []
		var squad_size: int = hero_count / squad_count
		for member_index: int in squad_size:
			var hero := Hero.new("Force %d-%d" % [squad_index, member_index], 0)
			hero.def_id = archetypes[member_index % archetypes.size()]
			hero.instance_id = "hero:%d:%d" % [squad_index, member_index]
			GameSession.roster.append(hero)
			ids.append(hero.instance_id)
		preset_ids.append(GameSession.save_team_preset("", "Squad %d" % squad_index, ids, zone_id))
	return preset_ids


func _dispatch_strong_repeat(loadout: Dictionary, total_runs: int = 2) -> String:
	var ids: Array[String] = []
	for index: int in 5:
		var hero := Hero.new("Repeat %d" % index, 7)
		hero.def_id = &"knight"
		hero.level = 80
		hero.instance_id = "hero:repeat:%d" % index
		GameSession.roster.append(hero)
		ids.append(hero.instance_id)
	var preset_id: String = GameSession.save_team_preset("", "Repeat Team", ids, "verdant_outskirts")
	return GameSession.dispatch_force([preset_id], "verdant_outskirts", total_runs, {}, loadout)


func _zero_loadout() -> Dictionary:
	return {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0}


## ig-7sn.6: a due repeat waits in "checking" until its forecast's two jobs land at a pulse. This sends
## them and lands them (without advancing any battle).
func _land_repeat_checks() -> void:
	GameSession._send_battle_checks()
	var deadline: int = Time.get_ticks_msec() + 60000
	while not GameSession._battle_checks.is_empty() and Time.get_ticks_msec() < deadline:
		OS.delay_msec(1)
		GameSession._land_battle_checks()
	assert_true(GameSession._battle_checks.is_empty(), "the repeat checks landed")
