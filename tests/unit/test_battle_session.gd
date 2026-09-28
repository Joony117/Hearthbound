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
	assert_eq(GameSession.team_snapshot_builds, builds + 2, "until stopped: the preview that sent the check, then the dispatch (its key and the run)")
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
	var active_decodes: int = GameSession.pulse_decodes_active
	var mismatched: Array[int] = []
	# ig-1jw: a pace-6 battle runs about 6x longer; the loop ends when the battle does.
	for pulse: int in 4000 * preload("res://balance.tres").battle_pace:
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
	assert_gte(active_pulses, 200, "ig-7sn.15 ACC 4: 200 pulses or more with reuse")
	assert_eq(mismatched, [] as Array[int], "every pulse leaves what a fresh advance would")
	assert_eq(GameSession.pulse_battle_advances - advances, active_pulses, "one advance per active pulse (was two)")
	# ig-7sn.15: decoded once, on the first advance; every later pulse reuses the kept state.
	assert_eq(GameSession.pulse_decodes_active - active_decodes, 1, "the battle is decoded once")
	# ACC 3: walking home after the fight, a pulse that is not due decodes nothing.
	var idle_decodes: int = GameSession.pulse_decodes_idle
	while not GameSession.expedition_orders.is_empty() and float(GameSession.expedition_orders[0]["remaining_seconds"]) > 0.5:
		GameSession.tick_expeditions(0.25)
	assert_eq(GameSession.pulse_decodes_idle, idle_decodes, "no decode walking home")
	# ig-1jw: at pace 6 the route (xP) can outlast the battle; walk the rest of it home.
	if not GameSession.expedition_orders.is_empty():
		GameSession.tick_expeditions(float(GameSession.expedition_orders[0]["remaining_seconds"]) + 0.25)
	assert_eq(GameSession.expedition_reports.size(), 1, "the run settled")


## ig-7sn.15 (ACC 3, 4): a battle Dictionary another writer replaced is decoded once; a pulse after that
## on which the returning order is not due decodes nothing.
func test_a_returning_battle_is_not_decoded_on_a_pulse_where_it_is_not_due() -> void:
	assert_ne(_dispatch_one(), "", GameSession.last_action_error)
	var battle: Dictionary = (GameSession.expedition_orders[0]["battle"] as Dictionary).duplicate(true)
	battle["status"] = "victory"
	GameSession.expedition_orders[0]["battle"] = battle
	GameSession.expedition_orders[0]["remaining_seconds"] = 60.0
	var decodes: int = GameSession.pulse_decodes_idle
	GameSession.tick_expeditions(0.25)
	assert_eq(GameSession.pulse_decodes_idle - decodes, 1, "the replaced Dictionary is decoded")
	assert_eq(GameSession.expedition_orders[0]["phase"], "returning")
	for ignored_pulse: int in 100:
		GameSession.tick_expeditions(0.25)
	assert_eq(GameSession.pulse_decodes_idle - decodes, 1, "and not again on a pulse where it is not due")
	assert_eq(GameSession.expedition_orders.size(), 1, "still walking home")


## ig-7sn.15 (ACC 4): a command issued between two advances is in the next advance's state. Its writer
## replaced the battle Dictionary, so the advance decodes it rather than reusing its own; a load too.
func test_a_command_between_advances_and_a_load_are_decoded_not_reused() -> void:
	var order_id: String = _dispatch_one()
	assert_ne(order_id, "", GameSession.last_action_error)
	GameSession.tick_expeditions(0.25)
	var decodes: int = GameSession.pulse_decodes_active
	GameSession.tick_expeditions(0.25)
	assert_eq(GameSession.pulse_decodes_active, decodes, "an unchanged battle is reused")
	var result: Dictionary = GameSession.issue_battle_command(order_id, {"kind": BattleSimulation.COMMAND_SET_ITEM_AUTO, "value": {"auto_heal": false, "auto_revive": true}})
	assert_true(bool(result["accepted"]), str(result))
	var commanded: Dictionary = GameSession.expedition_orders[0]["battle"] as Dictionary
	var fresh := BattleState.from_dict(commanded)
	BattleSimulation.advance(fresh, 0.25)
	GameSession.tick_expeditions(0.25)
	assert_eq(GameSession.pulse_decodes_active, decodes + 1, "the commanded battle is decoded")
	var advanced: Dictionary = GameSession.expedition_orders[0]["battle"] as Dictionary
	assert_eq(advanced, fresh.to_dict(), "the advance is the commanded state's")
	assert_gt(int(advanced["command_sequence"]), 0)
	assert_eq(advanced["command_sequence"], commanded["command_sequence"], "and carries the command")
	GameSession.from_dict(GameSession.to_dict())
	fresh = BattleState.from_dict(GameSession.expedition_orders[0]["battle"] as Dictionary)
	BattleSimulation.advance(fresh, 0.25)
	GameSession.tick_expeditions(0.25)
	assert_eq(GameSession.pulse_decodes_active, decodes + 2, "a loaded battle is decoded")
	assert_eq(GameSession.expedition_orders[0]["battle"], fresh.to_dict())


## ig-7sn.15 (ACC 5): between pulses _process advances at most one battle a frame and none on the pulse's
## frame; each active battle keeps up with real time, and a battle_changed goes out once per advance.
## ig-7sn.18 (ACC 3f): an advance is a job's landing now, under the same rules.
func test_frames_advance_one_battle_each_and_keep_up_with_real_time() -> void:
	_dispatch_frame_battles()
	var bad_frames: Array[String] = _drive_frames(1.0 / 60.0, 3600, 1800)
	assert_eq(bad_frames.slice(0, 10), [] as Array[String])


## ig-7sn.15 (Sol): at 20 fps (four frames free a pulse for five battles) none starves; below 4 fps (every
## frame a pulse's) the pulse's frame advances one, so the battles still move.
func test_battles_keep_up_at_low_frame_rates() -> void:
	for fixture: Array in [[0.05, 600], [0.3, 100]]:
		GameSession.from_dict({"roster": []})
		_dispatch_frame_battles()
		var bad_frames: Array[String] = _drive_frames(float(fixture[0]), int(fixture[1]), int(fixture[1]))
		assert_eq(bad_frames.slice(0, 10), [] as Array[String], "%s s frames" % fixture[0])


## ig-7sn.15 (Sol): a rejected command rolls the profile back through from_dict, but keeps the time the
## battles are owed; a load drops it.
func test_a_rollback_keeps_the_owed_time_and_a_load_drops_it() -> void:
	var order_id: String = _dispatch_one()
	GameSession.set_process(false)
	GameSession._process(0.1)
	GameSession.set_process(true)
	var owed: Dictionary = GameSession._battle_owed.duplicate()
	assert_eq(owed.keys(), [order_id])
	assert_false(bool(GameSession.issue_battle_command(order_id, {"kind": "not_a_command"})["accepted"]))
	assert_eq(GameSession._battle_owed, owed, "kept through the rollback")
	GameSession.from_dict(GameSession.to_dict())
	assert_true(GameSession._battle_owed.is_empty(), "dropped by a load")


func _dispatch_frame_battles() -> void:
	for index: int in 5:
		var hero := Hero.new("Frame %d" % index, 0)
		hero.def_id = &"knight"
		hero.instance_id = "hero:frame:%d" % index
		GameSession.roster.append(hero)
		var preset_id: String = GameSession.save_team_preset("", "Frame %d" % index, [hero.instance_id], "verdant_outskirts")
		assert_ne(GameSession.dispatch_force([preset_id], "verdant_outskirts", 1, {}, _zero_loadout()), "", GameSession.last_action_error)


## Drives GameSession._process with frames of frame seconds; returns what broke the one-battle-a-frame rule
## or let a battle fall behind real time by more than a pulse and two frames per live battle, and a frame.
## ig-7sn.18: a job lands one frame after it is sent at the soonest, and when landings are the bottleneck
## (every frame a pulse's, or one frame free per live battle) a battle's job carries a turn of the landing
## rotation while it waits another turn to land; that is the second frame per battle. At least five_live
## of the frames must start with all five battles live.
func _drive_frames(frame: float, count: int, five_live: int) -> Array[String]:
	var changes: Array[int] = [0]
	var on_change := func(_order_id: String) -> void: changes[0] += 1
	GameSession.battle_changed.connect(on_change)
	GameSession.set_process(false)
	var bad_frames: Array[String] = []
	var most_live: int = 0
	var five_live_frames: int = 0
	var advanced_frames: int = 0
	for index: int in count:
		var advances: int = GameSession.pulse_battle_advances
		var live: int = GameSession.expedition_orders.filter(func(order: Dictionary) -> bool: return GameSession._battle_live(order)).size()
		most_live = maxi(most_live, live)
		if live == 5:
			five_live_frames += 1
		changes[0] = 0
		_finish_advance_jobs()
		GameSession._process(frame)
		var ran: int = GameSession.pulse_battle_advances - advances
		advanced_frames += ran
		var pulse_frame: bool = GameSession._expedition_pulse_accumulator == 0.0
		if ran > 1 or (pulse_frame and ran > 0 and frame < GameSession.EXPEDITION_PULSE_SECONDS) or (not pulse_frame and changes[0] != ran):
			bad_frames.append("frame %d: %d advances, %d changes, pulse %s" % [index, ran, changes[0], pulse_frame])
		var real: float = (index + 1) * frame
		for order: Dictionary in GameSession.expedition_orders:
			var battle: Dictionary = order["battle"] as Dictionary
			if str(battle.get("status", "active")) != "active":
				continue
			var lag: float = real - float(battle["elapsed_seconds"]) - float(battle["tick_remainder"])
			if lag < -0.0001 or lag > GameSession.EXPEDITION_PULSE_SECONDS + (2 * live + 1) * frame + 0.0001:
				bad_frames.append("frame %d: %s lags %.4f s" % [index, order["id"], lag])
	GameSession.set_process(true)
	GameSession.battle_changed.disconnect(on_change)
	assert_gte(most_live, 2, "several battles ran at once")
	assert_gte(five_live_frames, five_live, "%s s frames: all five live" % frame)
	assert_gt(advanced_frames, int(count * frame), "the battles advanced")
	return bad_frames


## ig-7sn.18: waits until every advance job out has finished, so the next frame can land it. The game waits
## on a job only when it lands; a frame here runs what a real one would once its job is in.
func _finish_advance_jobs() -> void:
	for entry: Dictionary in GameSession._battle_advances.values():
		var job: BattleJob = entry["job"]
		while GameSession._battle_jobs.has(job) and not WorkerThreadPool.is_task_completed(job.task_id):
			OS.delay_usec(100)


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
	if total_runs == 0:
		# ig-7sn.14: until stopped waits for the preview's forecast to land.
		GameSession.preview_force([preset_id], "verdant_outskirts", 0, {}, loadout)
		var deadline: int = Time.get_ticks_msec() + 60000
		while GameSession._preview_forecasts.any(func(entry: Dictionary) -> bool: return not entry.has("verdict")) and Time.get_ticks_msec() < deadline:
			OS.delay_msec(1)
			GameSession._land_battle_checks()
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
