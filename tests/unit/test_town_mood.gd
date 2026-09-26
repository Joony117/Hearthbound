extends GutTest

# ig-0og.1: economy phase 1. The route pay factor and rate B (ACC 1), the town mood (ACC 5), the strike
# (ACC 6), the hub's lines (ACC 7) and town_mood's save (ACC 8, boundary #1). SYSTEMS.md § Town mood
# and revolt, § Summon Stones.

const BALANCE: BalanceTable = preload("res://balance.tres")
const LOADOUT: Dictionary = {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0}
const ZONE: String = "verdant_outskirts"
const RATIOS: Array[float] = [0.25, 1.0, 2.0, 4.0, 16.0, 64.0]


func before_each() -> void:
	GameSession.set_process(false)
	SaveService.load_blocked = false
	SaveService.load_block_reason = ""
	GameSession.from_dict({"roster": []})
	GameSession.town_resources["wood"] = 1000.0
	GameSession.last_action_error = ""


func after_each() -> void:
	GameSession._cancel_battle_jobs()
	GameSession.set_process(true)


# ACC 1, pure math: per route-hour a clear never pays more than the zone's matched rate, and pays it
# for r >= 1. Within 1% before the integer round; the round itself is at most half a stone.
func test_the_route_factor_pays_the_matched_rate_per_route_hour_and_never_more() -> void:
	var pace: int = BALANCE.battle_pace
	var zones: Array[ZoneDefinition] = []
	for zone_id: StringName in [&"verdant_outskirts", &"ashfall_reaches", &"sundered_vault"]:
		zones.append(ZoneDefinition.definition_for(zone_id))
	var best: Array[float] = []
	var matched_rates: Array[float] = []
	for zone: ZoneDefinition in zones:
		var zone_best: float = 0.0
		var full: float = zone.stone_reward * pace * BALANCE.stone_reward_scale
		for team_size: int in [5, 3]:
			var matched: float = ExpeditionOrders.route_seconds(zone, pace, team_size, 1.0)
			var matched_rate: float = full * 3600.0 / matched
			if team_size == 5:
				matched_rates.append(matched_rate)
			for ratio: float in RATIOS:
				var route: float = ExpeditionOrders.route_seconds(zone, pace, team_size, ratio)
				var factor: float = ExpeditionOrders.route_pay_factor(zone, route, team_size, pace)
				var rate: float = full * factor * 3600.0 / route
				var label: String = "%s, %d heroes, r %s" % [zone.zone_id, team_size, ratio]
				assert_true(rate <= matched_rate * 1.01, "%s: %f over %f" % [label, rate, matched_rate])
				if ratio >= 1.0:
					assert_almost_eq(rate, matched_rate, matched_rate * 0.01, label)
				assert_true(absf(ExpeditionOrders.stone_payout(zone, pace, BALANCE, factor) - full * factor) <= 0.5, "%s: the round" % label)
				zone_best = maxf(zone_best, rate)
		best.append(zone_best)
	for easier: int in zones.size():
		for harder: int in range(easier + 1, zones.size()):
			assert_true(best[easier] <= matched_rates[harder] * 1.01, "%s's best %f vs %s's matched %f" % [zones[easier].zone_id, best[easier], zones[harder].zone_id, matched_rates[harder]])


func test_rate_b_pays_verdant_50_a_clear_at_pace_6() -> void:
	assert_eq(ExpeditionOrders.stone_payout(ZoneDefinition.definition_for(&"verdant_outskirts"), 6, BALANCE), 50)


# ACC 1, the seam: a battle_v1 victory pays stone_reward x P x rate x factor from its own route and team
# size; at r <= 1 (a route at least the matched one) it pays in full.
func test_a_victory_pays_by_its_own_route_and_team_size() -> void:
	var zone: ZoneDefinition = ZoneDefinition.definition_for(StringName(ZONE))
	var preset: String = _preset(_add_heroes(5, "Seam"))
	assert_ne(GameSession.dispatch_force([preset], ZONE, 1, {}, LOADOUT), "", GameSession.last_action_error)
	var order: Dictionary = GameSession.expedition_orders[0]
	var route: float = float(order["initial_duration_seconds"])
	var factor: float = ExpeditionOrders.route_pay_factor(zone, route, 5, BALANCE.battle_pace)
	assert_lt(factor, 1.0, "setup: five level-80 knights are over-strong in Verdant")
	assert_eq(_settle_first_as_victory(), ExpeditionOrders.stone_payout(zone, BALANCE.battle_pace, BALANCE, factor))
	assert_ne(GameSession.dispatch_force([preset], ZONE, 1, {}, LOADOUT), "", GameSession.last_action_error)
	GameSession.expedition_orders[0]["initial_duration_seconds"] = ExpeditionOrders.route_seconds(zone, BALANCE.battle_pace, 5, 1.0) * 2.0
	assert_eq(_settle_first_as_victory(), ExpeditionOrders.stone_payout(zone, BALANCE.battle_pace, BALANCE), "a long route: full pay")


# ACC 5, pure: over the grace the mood falls 1 a minute a homeless hero, at most 5; at or under it rises 2.
func test_the_mood_falls_by_the_homeless_over_the_grace_and_rises_under_it() -> void:
	assert_eq(TownRules.mood_step(100.0, 3, 60.0, BALANCE), 99.0, "3 homeless: 1 over, 1 a minute")
	assert_eq(TownRules.mood_step(100.0, 12, 60.0, BALANCE), 95.0, "12 homeless: the cap, 5 a minute")
	assert_eq(TownRules.mood_step(50.0, 2, 60.0, BALANCE), 52.0, "2 homeless: rises 2 a minute")
	assert_eq(TownRules.mood_step(50.0, 0, 60.0, BALANCE), 52.0)
	assert_eq(TownRules.mood_step(3.0, 12, 60.0, BALANCE), 0.0, "never below 0")
	assert_eq(TownRules.mood_step(99.5, 0, 60.0, BALANCE), 100.0, "never above 100")
	assert_false(TownRules.in_revolt(0.0, 2, BALANCE), "at the grace: no revolt, even at 0")
	assert_true(TownRules.in_revolt(0.0, 3, BALANCE))
	assert_false(TownRules.in_revolt(0.5, 12, BALANCE), "not yet 0")


func test_the_offline_catch_up_moves_the_mood_not_at_all_and_the_live_tick_does() -> void:
	var heroes: Array[Hero] = _add_heroes(5, "Out")
	assert_ne(GameSession.dispatch_force([_preset([heroes[0]])], ZONE, 1, {}, LOADOUT), "", GameSession.last_action_error)
	GameSession.town_mood = 50.0
	GameSession.saved_at_unix = Time.get_unix_time_from_system() - 36000.0
	GameSession.apply_offline_expedition_progress(Time.get_unix_time_from_system())
	GameSession._advance_orders_in_memory(360000.0)
	assert_eq(GameSession.town_mood, 50.0, "the catch-up")
	GameSession._advance_clocks_in_memory(60.0)
	assert_eq(GameSession.town_mood, 47.0, "5 homeless, 3 over: 3 a minute live")


# ACC 6: in revolt, a new order is refused before any forecast job starts.
func test_in_revolt_preview_and_dispatch_refuse_and_start_no_forecast() -> void:
	var heroes: Array[Hero] = _add_heroes(3, "Striker")
	var preset: String = _preset([heroes[0]])
	GameSession.town_mood = 0.0
	assert_true(GameSession.is_in_revolt())
	var message: String = "The town is in revolt: 3 heroes have no bed. House them, or sacrifice some, to send orders again."
	assert_eq(GameSession.strike_refusal(), message)
	var preview: Dictionary = GameSession.preview_force([preset], ZONE, 1, {}, LOADOUT)
	assert_false(bool(preview["valid"]))
	assert_eq(str(preview["reason"]), message)
	assert_eq(GameSession.dispatch_force([preset], ZONE, 1, {}, LOADOUT), "")
	assert_eq(GameSession.last_action_error, message)
	assert_true(GameSession._preview_forecasts.is_empty(), "no forecast entry")
	assert_true(GameSession._battle_jobs.is_empty(), "no job")
	assert_true(GameSession.expedition_orders.is_empty())


# ACC 6: a due repeat stops with "revolt", writes its report, spends no escrow and is removed.
func test_in_revolt_a_due_repeat_stops_with_its_report_and_spends_no_escrow() -> void:
	GameSession.supplies = {"healing": 5, "revival": 5, "healing_masterwork": 0, "revival_masterwork": 0}
	var preset: String = _preset(_add_heroes(5, "Repeat"))
	var order_id: String = GameSession.dispatch_force([preset], ZONE, 2, {}, {"healing": 1, "revival": 1, "keep_healing": 0, "keep_revival": 0})
	assert_ne(order_id, "", GameSession.last_action_error)
	GameSession.town_mood = 0.0
	assert_true(GameSession.is_in_revolt(), "five homeless at 0")
	var order: Dictionary = GameSession.expedition_orders[0]
	(order["battle"] as Dictionary)["status"] = "victory"
	order["remaining_seconds"] = 0.0
	GameSession.tick_expeditions(0.1)
	assert_eq(GameSession._order_index(order_id), -1, "removed")
	assert_eq(GameSession.expedition_reports.size(), 1)
	assert_eq(str(GameSession.expedition_reports[0]["stopped_reason"]), "revolt")
	assert_eq(GameSession.supplies, {"healing": 5, "revival": 5, "healing_masterwork": 0, "revival_masterwork": 0}, "no repeat escrow spent")
	assert_true(GameSession._battle_checks.is_empty(), "no check sent")


# ACC 6: an order already checking when the revolt starts lands and runs its leg.
func test_an_order_already_checking_lands_and_runs_its_leg_in_revolt() -> void:
	var preset: String = _preset(_add_heroes(5, "Checking"))
	var order_id: String = GameSession.dispatch_force([preset], ZONE, 2, {}, LOADOUT)
	assert_ne(order_id, "", GameSession.last_action_error)
	var order: Dictionary = GameSession.expedition_orders[0]
	(order["battle"] as Dictionary)["status"] = "victory"
	order["remaining_seconds"] = 0.0
	GameSession.tick_expeditions(0.1)
	assert_eq(order["phase"], "checking")
	GameSession.town_mood = 0.0
	assert_true(GameSession.is_in_revolt())
	var deadline: int = Time.get_ticks_msec() + 60000
	while not GameSession._battle_checks.is_empty() and Time.get_ticks_msec() < deadline:
		OS.delay_msec(1)
		GameSession._land_battle_checks()
	assert_eq(order["phase"], "fighting", "the check landed and the leg runs")
	assert_ne(GameSession._order_index(order_id), -1)


# ACC 6: a rescue never asks.
func test_a_rescue_goes_out_in_revolt() -> void:
	var heroes: Array[Hero] = _add_heroes(4, "Town")
	var incident_id: String = _strand(heroes[3])
	GameSession.town_mood = 0.0
	assert_true(GameSession.is_in_revolt(), "4 homeless at 0")
	assert_ne(GameSession.dispatch_rescue(incident_id, _preset([heroes[0]]), LOADOUT), "", GameSession.last_action_error)


# ACC 6: an assign_home or a sacrifice that brings the homeless to the grace ends the revolt in that call.
func test_a_bed_or_a_sacrifice_ends_the_revolt_in_the_same_call() -> void:
	var heroes: Array[Hero] = _add_heroes(3, "Homeless")
	var preset: String = _preset([heroes[0]])
	GameSession.town_mood = 0.0
	assert_true(GameSession.is_in_revolt())
	assert_true(GameSession.assign_home(heroes[2], _place(TownRules.HOUSE, Vector2i(0, 2))), GameSession.last_action_error)
	assert_false(GameSession.is_in_revolt(), "two homeless: over")
	assert_ne(GameSession.dispatch_force([preset], ZONE, 1, {}, LOADOUT), "", GameSession.last_action_error)
	GameSession.from_dict({"roster": []})
	heroes = _add_heroes(4, "Fodder")
	GameSession.town_mood = 0.0
	assert_true(GameSession.is_in_revolt())
	assert_true(GameSession.sacrifice_hero(heroes[3], heroes[0], BALANCE))
	assert_true(GameSession.is_in_revolt(), "three homeless still")
	assert_true(GameSession.sacrifice_hero(heroes[2], heroes[0], BALANCE))
	assert_false(GameSession.is_in_revolt(), "the sacrifice that brings it to 2")
	assert_ne(GameSession.dispatch_force([_preset([heroes[0]])], ZONE, 1, {}, LOADOUT), "", GameSession.last_action_error)


# ACC 7 (boundary #2): the mood line's three texts, under the food line, in the existing StarveText.
func test_the_hub_says_the_fall_the_revolt_and_the_recovery() -> void:
	_add_heroes(4, "Hub")
	var hub: Node3D = _hub()
	var text: Label = hub.get_node("%StarveText") as Label
	GameSession.town_mood = 50.0
	GameSession.expeditions_changed.emit()
	assert_true((hub.get_node("%StarveWarning") as Control).visible)
	assert_eq(text.text, "4 heroes have no bed. Town mood 50: revolt in about 25:00.")
	GameSession.town_mood = 0.0
	GameSession.expeditions_changed.emit()
	assert_eq(text.text, "Revolt: no order or repeat goes out until at most 2 heroes are homeless. Riot in 30:00.")
	GameSession.town_resources["food"] = 1.0
	GameSession.expeditions_changed.emit()
	assert_eq(text.text, "Food low: 1 left, and the town eats 0.8 a minute.\nRevolt: no order or repeat goes out until at most 2 heroes are homeless. Riot in 30:00.", "under the food line")
	GameSession.town_resources["food"] = 100.0
	for hero: Hero in GameSession.roster.slice(0, 2):
		assert_true(GameSession.assign_home(hero, _place(TownRules.HOUSE, Vector2i(GameSession.roster.find(hero), 2))), GameSession.last_action_error)
	GameSession.town_mood = 40.5
	GameSession.expeditions_changed.emit()
	assert_eq(text.text, "Town mood 40, recovering.")
	GameSession.town_mood = 100.0
	GameSession.expeditions_changed.emit()
	assert_false((hub.get_node("%StarveWarning") as Control).visible, "calm: no line")


# ACC 7: Dispatch is disabled with the strike's reason, per team and combined; the pay line shows under 100%.
func test_the_hub_disables_dispatch_with_the_strike_reason_in_both_modes() -> void:
	var heroes: Array[Hero] = _add_heroes(5, "Gate")
	var presets: Array[String] = [_preset(heroes.slice(0, 2)), _preset(heroes.slice(2, 4))]
	var hub: Node3D = _hub()
	var summary: RichTextLabel = hub.get_node("%DispatchSummary") as RichTextLabel
	var dispatch: Button = hub.get_node("%DispatchSelected") as Button
	var list: ItemList = hub.get_node("%PresetDispatchList") as ItemList
	for row: int in list.item_count:
		if str((list.get_item_metadata(row) as Dictionary).get("id", "")) in presets:
			list.select(row, false)
			list.multi_selected.emit(row, true)
	_land_previews()
	hub._refresh_dispatch_summary()
	assert_string_contains(summary.text, "Pays ", "over-strong teams say their cut")
	assert_false(dispatch.disabled, "calm: it can go")
	GameSession.town_mood = 0.0
	var message: String = GameSession.strike_refusal()
	hub._refresh_dispatch_summary()
	assert_string_contains(summary.text, message, "per team: each row gives the reason")
	assert_true(dispatch.disabled, "per team")
	# Combined, with one team: Verdant takes one squad, and that cap is refused first.
	for row: int in list.item_count:
		if str((list.get_item_metadata(row) as Dictionary).get("id", "")) == presets[1]:
			list.deselect(row)
	(hub.get_node("%CombineTeams") as CheckBox).button_pressed = true
	hub._refresh_dispatch_summary()
	assert_string_contains(summary.text, "1 team(s) selected · 1 force")
	assert_string_contains(summary.text, message, "combined")
	assert_true(dispatch.disabled, "combined")


# Sol, ig-0og.1: a live tick that takes the mood to 0 disables Dispatch with no click.
func test_a_live_tick_that_starts_the_revolt_refreshes_dispatch() -> void:
	var heroes: Array[Hero] = _add_heroes(5, "Tick")
	var preset: String = _preset(heroes.slice(0, 2))
	var hub: Node3D = _hub()
	var summary: RichTextLabel = hub.get_node("%DispatchSummary") as RichTextLabel
	var dispatch: Button = hub.get_node("%DispatchSelected") as Button
	var list: ItemList = hub.get_node("%PresetDispatchList") as ItemList
	for row: int in list.item_count:
		if str((list.get_item_metadata(row) as Dictionary).get("id", "")) == preset:
			list.select(row, false)
			list.multi_selected.emit(row, true)
	_land_previews()
	hub._refresh_dispatch_summary()
	assert_false(dispatch.disabled, "calm: it can go")
	GameSession.town_mood = 0.01
	GameSession._process(GameSession.EXPEDITION_PULSE_SECONDS)
	assert_true(GameSession.is_in_revolt(), "the tick took the mood to 0")
	assert_true(dispatch.disabled, "the tick's signal disabled it")
	assert_string_contains(summary.text, GameSession.strike_refusal())


func test_the_pay_line_is_absent_at_full_pay() -> void:
	var hub: Node3D = _hub()
	assert_eq(hub._pay_line({"pay_percent": 100}), "")
	assert_eq(hub._pay_line({}), "", "no key: a refusal's preview")
	assert_eq(hub._pay_line({"pay_percent": 25}), "Pays 25% a clear here: this team is over-strong, so it earns the same per hour.")


# ACC 8 (boundary #1): a real disk round trip mid-fall keeps town_mood exactly.
func test_the_mood_survives_a_disk_round_trip_mid_fall() -> void:
	_add_heroes(5, "Disk")
	GameSession.tick_expeditions(45.0)
	var mood: float = GameSession.town_mood
	assert_eq(mood, 100.0 - 3.0 * 0.75, "falling, a fraction in play")
	_disk_round_trip()
	assert_eq(GameSession.town_mood, mood)
	assert_push_warning_count(0)


# ACC 8: a save from before the key, with 4 unhoused heroes, loads calm, keeps them all, and strikes only
# after 20+ live minutes.
func test_a_legacy_save_without_the_key_loads_calm_and_strikes_only_after_twenty_live_minutes() -> void:
	_add_heroes(4, "Legacy")
	assert_true(SaveService.save(), SaveService.last_write_error)
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveService.SAVE_PATH)) as Dictionary
	assert_true(saved.has("town_mood"))
	saved.erase("town_mood")
	GameSession.from_dict({"roster": []})
	_write(JSON.stringify(saved, "\t").to_utf8_buffer())
	assert_true(SaveService.load_game(), SaveService.load_block_reason)
	assert_eq(GameSession.town_mood, 100.0)
	assert_eq(GameSession.roster.size(), 4, "every hero kept")
	assert_eq(GameSession.homeless_heroes().size(), 4)
	for minute: int in 20:
		GameSession.tick_expeditions(60.0)
	assert_false(GameSession.is_in_revolt(), "20 live minutes: still no strike")
	for minute: int in 30:
		GameSession.tick_expeditions(60.0)
	assert_true(GameSession.is_in_revolt(), "50 minutes at 2 a minute")
	assert_eq(GameSession.roster.size(), 4)
	assert_push_warning_count(0)


func test_a_bad_mood_warns_and_reads_calm_and_an_outside_one_is_clamped() -> void:
	var state: Dictionary = GameSession.to_dict()
	for pair: Array in [["sad", 100.0, "Invalid town_mood"], [-5.0, 0.0, "outside 0-100"], [150.0, 100.0, "outside 0-100"]]:
		state["town_mood"] = pair[0]
		GameSession.from_dict(state)
		assert_eq(GameSession.town_mood, pair[1], str(pair[0]))
		assert_push_warning(str(pair[2]))
	state["town_mood"] = null
	GameSession.from_dict(state)
	assert_eq(GameSession.town_mood, 100.0, "null reads calm")
	state["town_mood"] = 37.25
	GameSession.from_dict(state)
	assert_eq(GameSession.town_mood, 37.25)


func test_no_hero_order_or_building_key_is_added() -> void:
	var heroes: Array[Hero] = _add_heroes(3, "Keys")
	_place(TownRules.HOUSE, Vector2i(0, 2))
	assert_ne(GameSession.dispatch_force([_preset([heroes[0]])], ZONE, 1, {}, LOADOUT), "", GameSession.last_action_error)
	var state: Dictionary = GameSession.to_dict()
	var nested: Array = [state["roster"][0], state["expedition_orders"][0], state["town_buildings"][0]]
	for data: Dictionary in nested:
		for key: String in data.keys():
			for word: String in ["mood", "homeless", "revolt", "riot", "pay_percent", "house_price"]:
				assert_false(key.contains(word), "%s in %s" % [key, str(data.keys())])
	assert_true(state.has("town_mood"), "the one new key, top-level")
	assert_true(state.has("town_revolt_seconds"), "ig-0og.3's, top-level too")


func _add_heroes(count: int, prefix: String) -> Array[Hero]:
	var heroes: Array[Hero] = []
	for index: int in count:
		var hero := Hero.new("%s %d" % [prefix, index], 7)
		hero.def_id = &"knight"
		hero.level = 80
		GameSession.add_hero(hero)
		heroes.append(hero)
	return heroes


func _preset(heroes: Array) -> String:
	var ids: Array[String] = []
	for hero: Hero in heroes:
		ids.append(hero.instance_id)
	var preset_id: String = GameSession.save_team_preset("", "Team %d" % GameSession.team_presets.size(), ids, ZONE)
	assert_ne(preset_id, "", GameSession.last_action_error)
	return preset_id


## Placed and finished at once: construction is not what this file tests.
func _place(type: StringName, hex: Vector2i) -> StringName:
	var id := StringName(GameSession.preview_place_building(type, hex)["id"])
	assert_true(GameSession.place_building(type, hex), GameSession.last_action_error)
	GameSession.town_building(id).erase("build_remaining")
	return id


## A real stranded incident holding the hero, with the capture's own checkpoint so a save validates.
func _strand(hero: Hero) -> String:
	var ids: Array[String] = [hero.instance_id]
	var squad: Dictionary = {"id": "source-squad", "name": "Source", "hero_ids": ids, "stance": "stay_together", "guard_target_id": ""}
	var state: BattleState = BattleSimulation.create_run("source", GameSession._team_snapshots([hero] as Array[Hero], [squad]), ZoneDefinition.definition_for(StringName(ZONE)), [squad], {}, {}, 544)
	for actor: BattleActor in state.actors:
		if actor.hero_id == hero.instance_id:
			actor.life = BattleActor.LIFE_DOWNED
			actor.hp = 0.0
	GameSession.stranded_incidents.append({"id": "incident-1", "source_order_id": "gone-source", "zone_id": ZONE, "hero_ids": ids, "battle_snapshot": GameSession._incident_snapshot(state, ids), "created_recovery_seconds": GameSession.rescue_clock_seconds, "paused": true, "expiry_pending": false, "active_rescue_order_id": ""})
	return "incident-1"


## The first order's victory, settled now; the stones it paid.
func _settle_first_as_victory() -> int:
	var order: Dictionary = GameSession.expedition_orders[0]
	(order["battle"] as Dictionary)["status"] = "victory"
	order["remaining_seconds"] = 0.0
	GameSession.expedition_reports.clear()
	GameSession.tick_expeditions(0.1)
	assert_eq(GameSession.expedition_reports.size(), 1, "settled: " + GameSession.last_action_error)
	return int(GameSession.expedition_reports[0]["stones_earned"])


func _hub() -> Node3D:
	var hub: Node3D = (load("res://hub/hub.tscn") as PackedScene).instantiate() as Node3D
	add_child_autofree(hub)
	return hub


## Pulses the landing until no preview is checking.
func _land_previews() -> void:
	var deadline: int = Time.get_ticks_msec() + 60000
	while GameSession._preview_forecasts.any(func(entry: Dictionary) -> bool: return not entry.has("verdict")) and Time.get_ticks_msec() < deadline:
		OS.delay_msec(1)
		GameSession._land_battle_checks()


func _disk_round_trip() -> void:
	assert_true(SaveService.save(), SaveService.last_write_error)
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(SaveService.SAVE_PATH)
	GameSession.from_dict({"roster": []})
	_write(bytes)
	assert_true(SaveService.load_game(), SaveService.load_block_reason)


func _write(bytes: PackedByteArray) -> void:
	var file := FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
