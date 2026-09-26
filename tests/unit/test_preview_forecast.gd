extends GutTest
## ig-7sn.14: the dispatch preview's forecast runs as two jobs, cached by its exact inputs, and lands
## at the pulse without a commit. An until-stopped dispatch starts from the landed entry's seed.

const LOADOUT: Dictionary = {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0}
const ZONE: String = "verdant_outskirts"


func before_each() -> void:
	_clear_session_without_saving()
	GameSession.last_action_error = ""
	SaveService.load_blocked = false


func after_each() -> void:
	_clear_session_without_saving()


func test_a_preview_checks_as_jobs_once_and_lands_the_main_thread_verdict() -> void:
	var presets: Array[String] = _strong_team()
	var saved: Dictionary = GameSession.to_dict()
	var jobs: int = GameSession._battle_jobs.size()
	var preview: Dictionary = GameSession.preview_force(presets, ZONE, 0, {}, LOADOUT)
	assert_true(bool(preview["checking"]))
	assert_false(bool(preview["safe"]))
	assert_false(bool(preview["valid"]), "until stopped is not valid while checking")
	assert_eq(str(preview["reason"]), "Checking...")
	assert_eq(GameSession._battle_jobs.size(), jobs + 2, "normal and stress")
	assert_true(bool(GameSession.preview_force(presets, ZONE, 1, {}, LOADOUT)["valid"]), "a fixed-run preview is valid while checking")
	assert_eq(GameSession._battle_jobs.size(), jobs + 2, "the same inputs send no new job")
	assert_eq(GameSession._preview_forecasts.size(), 1)
	watch_signals(GameSession)
	_land_previews()
	assert_signal_emitted(GameSession, "preview_forecast_ready")
	var entry: Dictionary = GameSession._preview_forecasts[0]
	var key: Array = entry["key"]
	var expected: Dictionary = BattleSimulation.forecast("forecast", key[0], ZoneDefinition.definition_for(StringName(ZONE)), key[2], key[3], key[4], int(entry["seed"]))
	preview = GameSession.preview_force(presets, ZONE, 0, {}, LOADOUT)
	assert_false(bool(preview["checking"]))
	assert_true(bool(expected["safe"]), "setup: a strong team is safe")
	assert_eq(bool(preview["safe"]), bool(expected["safe"]), "the landed verdict is the main thread's")
	assert_eq(str(preview["reason"]), str(expected["reason"]))
	assert_true(bool(preview["valid"]))
	assert_eq(GameSession.to_dict(), saved, "a preview saves nothing")


func test_until_stopped_waits_for_a_safe_verdict_then_runs_its_seed_and_consumes_it() -> void:
	var presets: Array[String] = _strong_team()
	GameSession.preview_force(presets, ZONE, 0, {}, LOADOUT)
	assert_eq(GameSession.dispatch_force(presets, ZONE, 0, {}, LOADOUT), "", "refused while checking")
	assert_eq(GameSession.last_action_error, "Until-stopped dispatch waits for the forecast.")
	assert_true(GameSession.expedition_orders.is_empty())
	assert_eq(GameSession._preview_forecasts.size(), 1, "the refusal keeps the entry")
	_land_previews()
	var entry: Dictionary = GameSession._preview_forecasts[0]
	var key: Array = entry["key"]
	var jobs: int = GameSession._battle_jobs.size()
	var order_id: String = GameSession.dispatch_force(presets, ZONE, 0, {}, LOADOUT)
	assert_ne(order_id, "", GameSession.last_action_error)
	assert_eq(GameSession._battle_jobs.size(), jobs, "the dispatch sends no job")
	assert_true(GameSession._preview_forecasts.is_empty(), "the entry is consumed")
	var order: Dictionary = GameSession.expedition_orders[0]
	assert_eq(int(order["run_seed"]), int(entry["seed"]))
	var state: BattleState = BattleSimulation.create_run(order_id, key[0], ZoneDefinition.definition_for(StringName(ZONE)), key[2], key[3], key[4], int(entry["seed"]))
	assert_eq(order["battle"], state.to_dict(), "the run the entry checked")


func test_an_unsafe_verdict_refuses_until_stopped() -> void:
	var presets: Array[String] = _strong_team()
	for hero: Hero in GameSession.roster:
		hero.rank = 0
		hero.level = 0
	GameSession.preview_force(presets, ZONE, 0, {}, LOADOUT)
	_land_previews()
	var preview: Dictionary = GameSession.preview_force(presets, ZONE, 0, {}, LOADOUT)
	assert_false(bool(preview["checking"]))
	assert_false(bool(preview["safe"]), "setup: a weak team is unsafe")
	assert_false(bool(preview["valid"]))
	assert_eq(GameSession.dispatch_force(presets, ZONE, 0, {}, LOADOUT), "")
	assert_eq(GameSession.last_action_error, "Until-stopped dispatch requires a Safe forecast.")


func test_a_fixed_run_dispatch_never_waits() -> void:
	var presets: Array[String] = _strong_team()
	GameSession.preview_force(presets, ZONE, 1, {}, LOADOUT)
	var jobs: int = GameSession._battle_jobs.size()
	assert_ne(GameSession.dispatch_force(presets, ZONE, 1, {}, LOADOUT), "", GameSession.last_action_error)
	assert_eq(GameSession._battle_jobs.size(), jobs, "a fixed-run dispatch sends no forecast")


func test_each_input_misses_the_cache() -> void:
	var presets: Array[String] = _strong_team()
	GameSession.supplies = {"healing": 5, "revival": 5, "healing_masterwork": 0, "revival_masterwork": 0}
	var hero: Hero = GameSession.roster[0]
	var zone_id: Array[String] = [ZONE]
	var policies: Array[Dictionary] = [{}]
	var loadout: Array[Dictionary] = [LOADOUT]
	var changes: Dictionary[String, Callable] = {
		"level": func() -> void: hero.level = 70,
		"gear": func() -> void:
			var ring := Item.new(&"ring", 2)
			GameSession.add_item(ring)
			GameSession.equip_item(hero, ring),
		"skills": func() -> void: hero.skill_chains = [{"trigger": "knight_iron_cut", "then": ["knight_rally"]}] as Array[Dictionary],
		"zone": func() -> void: zone_id[0] = "ashfall_reaches",
		"squads": func() -> void: GameSession.save_team_preset(presets[0], "Renamed", GameSession._string_array(GameSession.team_presets[0]["hero_ids"]), ZONE),
		"policies": func() -> void: policies[0] = {"heal_below": 0.5},
		"loadout": func() -> void: loadout[0] = {"healing": 1, "revival": 0, "keep_healing": 0, "keep_revival": 0},
	}
	GameSession.cleared_zone_ids[&"verdant_outskirts"] = true
	GameSession.preview_force(presets, zone_id[0], 0, policies[0], loadout[0])
	for change: String in changes:
		var entries: int = GameSession._preview_forecasts.size()
		changes[change].call()
		var preview: Dictionary = GameSession.preview_force(presets, zone_id[0], 0, policies[0], loadout[0])
		assert_eq(str(preview["error"]), "Until-stopped dispatch waits for the forecast.", change)
		assert_eq(GameSession._preview_forecasts.size(), entries + 1, "a %s change misses" % change)


func test_the_cache_keeps_the_newest_sixteen_and_cancels_the_dropped() -> void:
	var presets: Array[String] = _strong_team()
	var hero: Hero = GameSession.roster[0]
	hero.level = 1
	GameSession.preview_force(presets, ZONE, 0, {}, LOADOUT)
	var oldest: Dictionary = GameSession._preview_forecasts[0]
	for level: int in range(2, 2 + GameSession.PREVIEW_FORECAST_CAP):
		hero.level = level
		GameSession.preview_force(presets, ZONE, 0, {}, LOADOUT)
	assert_eq(GameSession._preview_forecasts.size(), GameSession.PREVIEW_FORECAST_CAP)
	assert_false(GameSession._preview_forecasts.has(oldest))
	assert_true((oldest["normal"] as BattleJob).cancelled and (oldest["stress"] as BattleJob).cancelled)
	_land_previews()


func test_a_load_drops_the_cache_and_the_preview_asks_again() -> void:
	var presets: Array[String] = _strong_team()
	GameSession.preview_force(presets, ZONE, 0, {}, LOADOUT)
	watch_signals(GameSession)
	var data: Dictionary = GameSession.to_dict()
	GameSession.set("_save_deferred_depth", 1)
	GameSession.from_dict(data)
	GameSession.set("_save_deferred_depth", 0)
	assert_true(GameSession._preview_forecasts.is_empty())
	assert_true(GameSession._battle_jobs.is_empty())
	await get_tree().process_frame
	assert_signal_emitted(GameSession, "preview_forecast_ready", "a preview left checking refreshes")
	assert_true(bool(GameSession.preview_force(presets, ZONE, 0, {}, LOADOUT)["checking"]), "the next refresh sends a new check")
	assert_eq(GameSession._preview_forecasts.size(), 1)


func test_a_stalled_pulse_still_lands_the_preview() -> void:
	var presets: Array[String] = _strong_team()
	var readies: Array[int] = [0]
	var count: Callable = func() -> void: readies[0] += 1
	GameSession.preview_forecast_ready.connect(count)
	for stall: String in ["load blocked", "checkpoint save failed"]:
		GameSession._cancel_battle_jobs()
		SaveService.load_blocked = stall == "load blocked"
		GameSession._checkpoint_save_failed = stall == "checkpoint save failed"
		GameSession.preview_force(presets, ZONE, 0, {}, LOADOUT)
		readies[0] = 0
		var deadline: int = Time.get_ticks_msec() + 60000
		while not GameSession._preview_forecasts[0].has("verdict") and Time.get_ticks_msec() < deadline:
			OS.delay_msec(1)
			# Never reaches the retry save, so the stall holds throughout.
			GameSession._periodic_save_accumulator = 0.0
			GameSession._process(GameSession.EXPEDITION_PULSE_SECONDS)
		assert_true(GameSession._preview_forecasts[0].has("verdict"), stall)
		assert_eq(readies[0], 1, "%s: the landing refreshes the preview" % stall)
	GameSession.preview_forecast_ready.disconnect(count)
	SaveService.load_blocked = false
	GameSession._checkpoint_save_failed = false


func test_the_hub_summary_refreshes_when_the_forecast_lands() -> void:
	var presets: Array[String] = _strong_team()
	var hub: Node3D = (load("res://hub/hub.tscn") as PackedScene).instantiate() as Node3D
	add_child_autofree(hub)
	hub._open(&"TownGate")
	(hub.get_node("%RepeatUntilStopped") as CheckBox).button_pressed = true
	var list: ItemList = hub.get_node("%PresetDispatchList") as ItemList
	for row: int in list.item_count:
		if str((list.get_item_metadata(row) as Dictionary).get("id", "")) in presets:
			list.select(row)
			list.multi_selected.emit(row, true)
	var summary: RichTextLabel = hub.get_node("%DispatchSummary") as RichTextLabel
	assert_string_contains(summary.text, "Checking...")
	assert_true((hub.get_node("%DispatchSelected") as Button).disabled, "until stopped waits")
	_land_previews()
	assert_false(summary.text.contains("Checking..."), "the landing refreshed it")
	assert_false((hub.get_node("%DispatchSelected") as Button).disabled)


## Five strong knights in one preset.
func _strong_team() -> Array[String]:
	var ids: Array[String] = []
	for index: int in 5:
		var hero := Hero.new("Preview %d" % index, 7)
		hero.def_id = &"knight"
		hero.level = 80
		hero.instance_id = "hero:preview:%d" % index
		GameSession.roster.append(hero)
		ids.append(hero.instance_id)
	var preset_id: String = GameSession.save_team_preset("", "Preview Team", ids, ZONE)
	assert_ne(preset_id, "", GameSession.last_action_error)
	var presets: Array[String] = [preset_id]
	return presets


## Pulses the landing until no preview is checking.
func _land_previews() -> void:
	var deadline: int = Time.get_ticks_msec() + 60000
	while GameSession._preview_forecasts.any(func(entry: Dictionary) -> bool: return not entry.has("verdict")) and Time.get_ticks_msec() < deadline:
		OS.delay_msec(1)
		GameSession._land_battle_checks()
	assert_false(GameSession._preview_forecasts.any(func(entry: Dictionary) -> bool: return not entry.has("verdict")), "the previews landed")


func _clear_session_without_saving() -> void:
	GameSession.set("_save_deferred_depth", 1)
	GameSession.from_dict({"roster": []})
	GameSession.set("_save_deferred_depth", 0)
