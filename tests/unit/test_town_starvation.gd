extends GutTest

# ig-6m2.5.2: starvation, warned and never offline. The clock runs while the town can't feed its
# eaters, stops at a last warning until acknowledged, and each due point kills one eater
# (SYSTEMS.md § Food and starvation). Boundaries #1 (the two save keys) and #3 (kill_hero only).

const BALANCE: BalanceTable = preload("res://balance.tres")
const LOADOUT: Dictionary = {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0}
const ZONE: String = "verdant_outskirts"
const STOP_1: float = 900.0
const DUE_1: float = 1200.0
const STOP_2: float = 1500.0
const DUE_2: float = 1800.0


func before_each() -> void:
	GameSession.set_process(false)
	SaveService.load_blocked = false
	SaveService.load_block_reason = ""
	GameSession.from_dict({"roster": []})
	GameSession.town_resources["wood"] = 1000.0


func after_each() -> void:
	GameSession.set_process(true)


func test_the_numbers_put_the_stops_and_deaths_where_the_spec_says() -> void:
	assert_eq(TownRules.starve_due_seconds(0.0, BALANCE), DUE_1)
	assert_eq(TownRules.starve_stop_seconds(0.0, BALANCE), STOP_1)
	assert_eq(TownRules.starve_due_seconds(DUE_1, BALANCE), DUE_2, "a reached due point has had its death")
	assert_eq(TownRules.starve_stop_seconds(DUE_1 + 1.0, BALANCE), STOP_2)
	assert_eq(TownRules.starve_stop_seconds(DUE_2, BALANCE), 2100.0)


func test_the_clock_runs_unfed_resets_fed_and_holds_between() -> void:
	_housed("Ada", Vector2i(0, 2))
	GameSession.town_resources["food"] = 0.0
	GameSession.tick_expeditions(60.0)
	assert_eq(GameSession.town_starving_seconds, 60.0, "demand not met: it runs by delta")
	assert_eq(GameSession.town_resources["food"], 0.0)
	GameSession.town_resources["food"] = TownRules.food_low_line(1, BALANCE) * 0.5
	GameSession.tick_expeditions(1.0)
	assert_eq(GameSession.town_starving_seconds, 60.0, "fed but under the low line: it holds")
	GameSession.town_resources["food"] = TownRules.food_low_line(1, BALANCE) + 1.0
	GameSession.tick_expeditions(1.0)
	assert_eq(GameSession.town_starving_seconds, 0.0, "over the line: fed, it resets")
	assert_false(GameSession.town_starve_acked)


func test_a_farm_short_of_the_eating_still_starves() -> void:
	var farmer: Hero = _housed("Farmer", Vector2i(0, 2))
	assert_true(GameSession.station_hero(farmer, _place(TownRules.FARM, Vector2i(0, 1))), GameSession.last_action_error)
	for index: int in 5:
		_housed("H%d" % index, Vector2i(index + 1, 2))
	GameSession.town_resources["food"] = 0.0
	for _tick: int in 10:
		GameSession.tick_expeditions(30.0)
		assert_lt(float(GameSession.town_resources["food"]), TownRules.food_low_line(6, BALANCE))
	assert_eq(GameSession.town_starving_seconds, 300.0, "1.0 a minute made, 1.2 eaten: it starves")


func test_starving_halves_every_workplace_and_the_reset_restores_it() -> void:
	var workers: Array[Hero] = []
	var places: Array[StringName] = [_place(TownRules.LUMBERMILL, Vector2i(-2, 1)), _place(TownRules.MINE, Vector2i(0, 1)), _place(TownRules.FARM, Vector2i(2, 1))]
	for index: int in places.size():
		workers.append(_housed("W%d" % index, Vector2i(index * 2 - 2, 2)))
		assert_true(GameSession.station_hero(workers[index], places[index]), GameSession.last_action_error)
	assert_almost_eq(float(TownRules.starve_step(10.0, 60.0, false, 1, 0, true, 60.0, BALANCE)["food"]), 10.0 + 0.5 * BALANCE.food_per_worker_minute, 0.0001, "food at half speed")
	GameSession.town_starving_seconds = 60.0
	GameSession.town_resources["food"] = 0.0
	var wood: float = GameSession.town_resources["wood"]
	var stone: float = GameSession.town_resources["stone"]
	GameSession.tick_expeditions(60.0)
	assert_almost_eq(float(GameSession.town_resources["wood"]), wood + 0.5 * BALANCE.wood_per_worker_minute, 0.0001)
	assert_almost_eq(float(GameSession.town_resources["stone"]), stone + 0.5 * BALANCE.stone_per_worker_minute, 0.0001)
	assert_eq(GameSession.town_starving_seconds, 120.0, "half a farm short of three eaters: still starving")
	GameSession.town_resources["food"] = 100.0
	GameSession.tick_expeditions(1.0)
	assert_eq(GameSession.town_starving_seconds, 0.0)
	wood = GameSession.town_resources["wood"]
	GameSession.tick_expeditions(60.0)
	assert_almost_eq(float(GameSession.town_resources["wood"]), wood + BALANCE.wood_per_worker_minute, 0.0001, "full speed")


func test_the_ladder_stops_until_acked_and_each_ack_lets_one_death_through() -> void:
	var heroes: Array[Hero] = [_housed("Ada", Vector2i(0, 2), 2), _housed("Bea", Vector2i(1, 2), 1), _housed("Cy", Vector2i(2, 2), 3)]
	GameSession.town_resources["food"] = 0.0
	for _tick: int in 40:
		GameSession.tick_expeditions(60.0)
	assert_eq(GameSession.town_starving_seconds, STOP_1, "stopped at 15:00")
	GameSession.tick_expeditions(1.0e7)
	assert_eq(GameSession.town_starving_seconds, STOP_1, "a huge delta can't skip the warning")
	assert_true(GameSession.is_starvation_stopped())
	assert_eq(GameSession.roster.size(), 3)
	assert_true(GameSession.acknowledge_starvation(), GameSession.last_action_error)
	assert_false(GameSession.is_starvation_stopped())
	assert_false(GameSession.acknowledge_starvation(), "a no-op off a stop point")
	GameSession.tick_expeditions(DUE_1 - STOP_1 - 1.0)
	assert_eq(GameSession.roster.size(), 3, "not yet")
	GameSession.tick_expeditions(1.0e7)
	assert_eq(GameSession.town_starving_seconds, DUE_1, "the death is capped at 20:00")
	assert_null(GameSession.hero_by_id(heroes[1].instance_id), "Bea, the lowest rank, at 20:00")
	assert_false(GameSession.town_starve_acked)
	for _tick: int in 40:
		GameSession.tick_expeditions(60.0)
	assert_eq(GameSession.town_starving_seconds, STOP_2, "the next stop is 25:00")
	assert_eq(GameSession.roster.size(), 2)
	assert_true(GameSession.acknowledge_starvation())
	GameSession.tick_expeditions(1.0e7)
	assert_eq(GameSession.town_starving_seconds, DUE_2)
	assert_null(GameSession.hero_by_id(heroes[0].instance_id), "Ada at 30:00")
	assert_not_null(GameSession.hero_by_id(heroes[2].instance_id))


func test_nothing_moves_offline_and_hours_unacked_kill_nobody() -> void:
	var heroes: Array[Hero] = [_housed("Ada", Vector2i(0, 2)), _housed("Bea", Vector2i(1, 2))]
	assert_ne(GameSession.dispatch_expedition([heroes[1].instance_id], ZONE, 1, "Out"), "", GameSession.last_action_error)
	GameSession.town_resources["food"] = 0.0
	GameSession.town_starving_seconds = 300.0
	GameSession.saved_at_unix = Time.get_unix_time_from_system() - 36000.0
	GameSession.apply_offline_expedition_progress(Time.get_unix_time_from_system())
	GameSession._advance_orders_in_memory(360000.0)
	assert_eq(GameSession.town_starving_seconds, 300.0, "the catch-up moves no clock")
	assert_eq(GameSession.town_resources["food"], 0.0)
	for _tick: int in 3 * 60:
		GameSession.tick_expeditions(60.0)
	assert_eq(GameSession.town_starving_seconds, STOP_1, "three hours, no ack")
	assert_not_null(GameSession.hero_by_id(heroes[0].instance_id), "nobody died")


func test_the_victim_is_lowest_rank_then_level_then_newest_and_only_an_eater() -> void:
	var a := _hero("A", 1, 1)
	var b := _hero("B", 0, 9)
	var c := _hero("C", 0, 3)
	var d := _hero("D", 0, 3)
	var eaters: Array[Hero] = [a, b, c, d]
	assert_eq(TownRules.starvation_victim(eaters), d.instance_id, "rank 0, level 3, newest")
	eaters = [a, b, c]
	assert_eq(TownRules.starvation_victim(eaters), c.instance_id)
	eaters = [a, b]
	assert_eq(TownRules.starvation_victim(eaters), b.instance_id, "rank beats level")
	assert_eq(TownRules.starvation_victim([] as Array[Hero]), "")
	# ig-0og.1: the same order, among the heroes at home (an unhoused one is at home too).
	var home: Hero = _housed("Home", Vector2i(0, 2), 5)
	var away: Hero = _housed("Away", Vector2i(1, 2), 0)
	var fighting: Hero = _housed("Fighting", Vector2i(2, 2), 0)
	var stray: Hero = _add_hero("Stray", 1)
	assert_ne(GameSession.dispatch_expedition([away.instance_id], ZONE, 1, "Out"), "", GameSession.last_action_error)
	var preset: String = GameSession.save_team_preset("", "Fighters", [fighting.instance_id], ZONE)
	assert_ne(GameSession.dispatch_force([preset], ZONE, 1, {}, LOADOUT), "", GameSession.last_action_error)
	assert_eq(GameSession.starvation_candidates(), [home, stray] as Array[Hero], "away and in a battle are never candidates")
	assert_eq(TownRules.starvation_victim(GameSession.starvation_candidates()), stray.instance_id, "rank 1 at home before rank 5; the rank-0 fighters are out")


# ig-0og.1 (ACC 4, boundary #3): only a hero at home starves. With every eater away the clock holds at
# the stop point and nobody dies. The death comes once one is home and the warning is acked.
func test_with_every_eater_away_the_clock_holds_at_the_stop_until_one_is_home_and_acked() -> void:
	var ada: Hero = _housed("Ada", Vector2i(0, 2))
	_strand([ada])
	GameSession.town_resources["food"] = 0.0
	GameSession.tick_expeditions(1.0e7)
	assert_eq(GameSession.town_starving_seconds, STOP_1, "held at the stop")
	assert_true(GameSession.is_starvation_stopped())
	assert_not_null(GameSession.hero_by_id(ada.instance_id))
	GameSession.stranded_incidents.clear()
	GameSession.tick_expeditions(1.0e7)
	assert_eq(GameSession.town_starving_seconds, STOP_1, "home, but not acked yet")
	assert_not_null(GameSession.hero_by_id(ada.instance_id))
	assert_true(GameSession.acknowledge_starvation(), GameSession.last_action_error)
	GameSession.tick_expeditions(1.0e7)
	assert_eq(GameSession.town_starving_seconds, DUE_1)
	assert_null(GameSession.hero_by_id(ada.instance_id), "home and acked: she dies")


# An ack with nobody home kills nobody: kill_hero never runs on a busy hero. The first one home is the
# victim, even over a lower rank still stranded.
func test_an_ack_with_nobody_home_kills_no_busy_hero_and_the_one_home_is_the_victim() -> void:
	var ada: Hero = _housed("Ada", Vector2i(0, 2), 0)
	var bea: Hero = _housed("Bea", Vector2i(1, 2), 5)
	_strand([ada])
	_strand([bea])
	GameSession.town_resources["food"] = 0.0
	GameSession.tick_expeditions(1.0e7)
	assert_true(GameSession.acknowledge_starvation(), GameSession.last_action_error)
	GameSession.tick_expeditions(1.0e7)
	assert_eq(GameSession.town_starving_seconds, STOP_1, "acked, but nobody home: still held")
	assert_eq(GameSession.roster.size(), 2, "no busy hero died")
	GameSession.stranded_incidents.remove_at(1)
	GameSession.tick_expeditions(1.0e7)
	assert_null(GameSession.hero_by_id(bea.instance_id), "Bea came home, so Bea starves")
	assert_not_null(GameSession.hero_by_id(ada.instance_id), "Ada, the lower rank, is still stranded")


# Sol, ig-0og.1: at the stop with nobody home there is no one to name, so nothing pops; once a hero is
# home, the last warning names that hero and ig-0og.2's dialog pops. If she leaves while it is open, it
# stays open, and closing it still acks (acknowledge_starvation checks only the stop).
func test_the_hub_pops_the_last_warning_only_once_someone_is_home_to_name() -> void:
	var ada: Hero = _housed("Ada", Vector2i(0, 2))
	_strand([ada])
	var hub: Node3D = (load("res://hub/hub.tscn") as PackedScene).instantiate() as Node3D
	add_child_autofree(hub)
	var text: Label = hub.get_node("%StarveText") as Label
	var dialog: AcceptDialog = hub.get_node("%StarveDialog") as AcceptDialog
	GameSession.town_resources["food"] = 0.0
	GameSession.tick_expeditions(1.0e7)
	assert_true(GameSession.is_starvation_stopped())
	assert_false(dialog.visible, "nobody home: nothing to acknowledge")
	GameSession.stranded_incidents.clear()
	GameSession.expeditions_changed.emit()
	assert_eq(text.text, "Last warning: Ada starves in 5:00 unless the town is fed. The clock waits for you.")
	assert_true(dialog.visible, "Ada is home")
	assert_eq(dialog.dialog_text, "Ada starves in 5:00 unless the town is fed. The clock waits until you close this.")
	_strand([ada])
	GameSession.expeditions_changed.emit()
	assert_true(dialog.visible, "she left, and it stays open")
	dialog.get_ok_button().pressed.emit()
	assert_true(GameSession.town_starve_acked, "closing it still acks")
	assert_false(dialog.visible)


# The pulse's look-ahead and the live tick agree: nobody home, no death either way; one home, the death
# goes through the checked, saved path.
func test_the_look_ahead_and_the_live_tick_agree_on_the_death() -> void:
	var ada: Hero = _housed("Ada", Vector2i(0, 2))
	_strand([ada])
	GameSession.town_resources["food"] = 0.0
	GameSession.town_starving_seconds = DUE_1 - 1.0
	GameSession.town_starve_acked = true
	assert_true(SaveService.save(), SaveService.last_write_error)
	GameSession.tick_expeditions(1.0)
	assert_eq(GameSession.town_starving_seconds, DUE_1 - 1.0, "held")
	assert_not_null(GameSession.hero_by_id(ada.instance_id))
	GameSession.stranded_incidents.clear()
	GameSession.tick_expeditions(1.0)
	assert_null(GameSession.hero_by_id(ada.instance_id))
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveService.SAVE_PATH)) as Dictionary
	assert_eq((saved["roster"] as Array).size(), 0, "the look-ahead saw the death, so it was saved")


# Boundary #3: gear to inventory first (no Lost Cache), a died record, and the body goes with it.
func test_the_death_keeps_the_gear_writes_the_ledger_and_clears_the_body() -> void:
	var victim: Hero = _housed("Mira", Vector2i(0, 2), 0)
	var survivor: Hero = _housed("Sol", Vector2i(1, 2), 5)
	var ring := Item.new(&"ring", 0)
	GameSession.add_item(ring)
	GameSession.equip_item(victim, ring)
	assert_false(ring in GameSession.inventory, "worn")
	assert_true(GameSession.embody_hero(victim.instance_id), GameSession.last_action_error)
	GameSession.town_resources["food"] = 0.0
	GameSession.town_starving_seconds = DUE_1 - 1.0
	GameSession.town_starve_acked = true
	GameSession.tick_expeditions(1.0)
	assert_null(GameSession.hero_by_id(victim.instance_id))
	assert_not_null(GameSession.hero_by_id(survivor.instance_id))
	assert_true(ring in GameSession.inventory, "the gear is in inventory")
	assert_true(GameSession.lost_caches.is_empty(), "no Lost Cache")
	assert_eq(GameSession.embodied_hero_id, GameSession.NO_BODY, "no body left behind")
	var died: Dictionary = GameSession.ledger.back()
	assert_eq([died["kind"], died["hero"], died["cause"]], ["died", victim.instance_id, "starvation"])
	assert_false(died.has("zone"))
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveService.SAVE_PATH)) as Dictionary
	assert_eq((saved["roster"] as Array).size(), 1, "the death was saved")


# The death is a checked mutation: a save that fails undoes it whole, and the next tick tries again.
func test_a_death_whose_save_fails_is_rolled_back() -> void:
	var victim: Hero = _housed("Mira", Vector2i(0, 2))
	var ring := Item.new(&"ring", 0)
	GameSession.add_item(ring)
	GameSession.equip_item(victim, ring)
	GameSession.town_resources["food"] = 0.0
	GameSession.town_starving_seconds = DUE_1 - 1.0
	GameSession.town_starve_acked = true
	var before: String = JSON.stringify(GameSession.to_dict(), "", true)
	assert_eq(DirAccess.make_dir_absolute(SaveService.TMP_PATH), OK)
	GameSession.tick_expeditions(1.0)
	assert_push_error("Save failed")
	assert_not_null(GameSession.hero_by_id(victim.instance_id), "alive: nothing was written")
	assert_eq(JSON.stringify(GameSession.to_dict(), "", true), before, "gear, inventory, food, clock, acked and the Ledger all back")
	assert_eq(DirAccess.remove_absolute(SaveService.TMP_PATH), OK)
	GameSession.tick_expeditions(1.0)
	assert_null(GameSession.hero_by_id(victim.instance_id), "the retry goes through")


# Rule 8: kill_hero is the only removal.
func test_roster_erase_appears_only_in_kill_hero() -> void:
	var hits: Array[String] = []
	_scan("res://", hits)
	assert_eq(hits.size(), 1, str(hits))
	var source: String = FileAccess.get_file_as_string("res://systems/game_session.gd")
	var at: int = source.find("roster.erase(")
	assert_eq(source.rfind("\nfunc ", at), source.find("\nfunc kill_hero("), "inside kill_hero")


# Boundary #1: stopped at a last warning, through SaveService and the disk.
func test_a_save_at_the_last_warning_reloads_stopped_and_one_after_the_ack_stays_acked() -> void:
	_housed("Ada", Vector2i(0, 2))
	GameSession.town_resources["food"] = 0.0
	GameSession.tick_expeditions(1.0e7)
	assert_true(GameSession.is_starvation_stopped())
	_disk_round_trip()
	assert_eq(GameSession.town_resources["food"], 0.0)
	assert_eq(GameSession.town_starving_seconds, STOP_1)
	assert_false(GameSession.town_starve_acked)
	GameSession.tick_expeditions(60.0)
	assert_eq(GameSession.town_starving_seconds, STOP_1, "still stopped")
	assert_true(GameSession.acknowledge_starvation())
	GameSession.tick_expeditions(60.0)
	_disk_round_trip()
	assert_eq(GameSession.town_starving_seconds, STOP_1 + 60.0)
	assert_true(GameSession.town_starve_acked, "a save made after the ack keeps it")
	assert_false(GameSession.is_starvation_stopped(), "it does not ask again")
	assert_push_warning_count(0)
	assert_push_error_count(0)


func test_bad_or_missing_starvation_keys_are_repaired_never_refused() -> void:
	var state: Dictionary = GameSession.to_dict()
	for key: String in ["town_starving_seconds", "town_starve_acked"]:
		state.erase(key)
	GameSession.from_dict(state)
	assert_eq([GameSession.town_starving_seconds, GameSession.town_starve_acked], [0.0, false], "no keys")
	assert_push_warning_count(0)
	_load_with(state, -1.0, false)
	assert_push_warning("Invalid town_starving_seconds")
	assert_eq(GameSession.town_starving_seconds, 0.0, "-1 reads 0")
	_load_with(state, "soon", "yes")
	assert_eq([GameSession.town_starving_seconds, GameSession.town_starve_acked], [0.0, false], "not a number, not a bool")
	_load_with(state, STOP_1 + 100.0, false)
	assert_eq(GameSession.town_starving_seconds, STOP_1, "past the stop unacked: the stop")
	_load_with(state, STOP_1 - 1.0, true)
	assert_eq([GameSession.town_starving_seconds, GameSession.town_starve_acked], [STOP_1 - 1.0, false], "acked below the stop: false")
	_load_with(state, STOP_1 + 100.0, true)
	assert_eq([GameSession.town_starving_seconds, GameSession.town_starve_acked], [STOP_1 + 100.0, true], "acked past the stop is what a save after the ack holds")
	_load_with(state, DUE_1 + 60.0, false)
	assert_eq(GameSession.town_starving_seconds, DUE_1 + 60.0, "after a death, under the next stop")
	GameSession.town_starving_seconds = STOP_1
	assert_true(SaveService.save(), SaveService.last_write_error)


func test_the_hub_shows_each_rung_pops_the_dialog_once_per_stop_and_says_who_starved() -> void:
	var mira: Hero = _housed("Mira", Vector2i(0, 2), 0)
	_housed("Sol", Vector2i(1, 2), 5)
	var hub: Node3D = (load("res://hub/hub.tscn") as PackedScene).instantiate() as Node3D
	add_child_autofree(hub)
	var warning: Control = hub.get_node("%StarveWarning") as Control
	var text: Label = hub.get_node("%StarveText") as Label
	var dialog: AcceptDialog = hub.get_node("%StarveDialog") as AcceptDialog
	var status: Label = hub.get_node("%Status") as Label
	assert_false(warning.visible, "fed")
	GameSession.town_resources["food"] = 3.0
	GameSession.expeditions_changed.emit()
	assert_eq(text.text, "Food low: 3 left, and the town eats 0.4 a minute.")
	assert_false(dialog.visible)
	GameSession.town_resources["food"] = 0.0
	GameSession.tick_expeditions(270.0)
	assert_eq(text.text, "Starving: work runs at 50% speed. Mira starves in 15:30 unless the town is fed.")
	assert_false(dialog.visible)
	GameSession.tick_expeditions(1.0e7)
	assert_eq(text.text, "Last warning: Mira starves in 5:00 unless the town is fed. The clock waits for you.")
	assert_true(dialog.visible, "the stop pops it")
	assert_eq(dialog.dialog_text, "Mira starves in 5:00 unless the town is fed. The clock waits until you close this.")
	# The row still lets town clicks through once the dialog is out of the way.
	dialog.hide()
	await wait_process_frames(2, "let the row lay out, as the player sees it")
	var row_point := Vector2(text.get_global_rect().position.x + 8.0, text.get_global_rect().get_center().y)
	var under_row: Control = _hovered(hub, row_point)
	assert_true(under_row == null or hub.is_ancestor_of(under_row), "a point GUT's own panel doesn't cover")
	assert_false(under_row in [warning, text], "the row lets town clicks through")
	GameSession.expeditions_changed.emit()
	assert_true(dialog.visible, "hidden without a close, it pops again: only a close acks")
	status.text = "before"
	dialog.get_ok_button().pressed.emit()
	assert_true(GameSession.town_starve_acked)
	assert_eq(status.text, "before", "one close is one ack: no error")
	assert_false(dialog.visible)
	GameSession.tick_expeditions(1.0)
	assert_false(dialog.visible, "not again for the same stop")
	GameSession.tick_expeditions(1.0e7)
	assert_null(GameSession.hero_by_id(mira.instance_id))
	assert_eq(status.text, "Mira starved.")
	status.text = "later"
	GameSession.expeditions_changed.emit()
	assert_eq(status.text, "later", "said once, not re-said")
	for _tick: int in 40:
		GameSession.tick_expeditions(60.0)
	assert_eq(GameSession.town_starving_seconds, STOP_2)
	assert_true(dialog.visible, "the next stop, after the next death, pops again")
	assert_eq(dialog.dialog_text, "Sol starves in 5:00 unless the town is fed. The clock waits until you close this.")


# ig-0og.2 (ACC 1): OK, Esc and the X each ack, and the clock runs again. Esc goes to the dialog, not
# the pause menu.
func test_ok_esc_and_the_x_each_ack_and_the_clock_runs_again() -> void:
	var hub: Node3D = (load("res://hub/hub.tscn") as PackedScene).instantiate() as Node3D
	add_child_autofree(hub)
	var dialog: AcceptDialog = hub.get_node("%StarveDialog") as AcceptDialog
	for way: String in ["ok", "esc", "x"]:
		GameSession.from_dict({"roster": []})
		_housed("Ada", Vector2i(0, 2))
		GameSession.town_resources["food"] = 0.0
		GameSession.tick_expeditions(1.0e7)
		assert_true(dialog.visible, way)
		match way:
			"ok":
				dialog.get_ok_button().pressed.emit()
			"esc":
				for pressed: bool in [true, false]:
					var key := InputEventKey.new()
					key.keycode = KEY_ESCAPE
					key.physical_keycode = KEY_ESCAPE
					key.pressed = pressed
					hub.get_viewport().push_input(key)
			"x":
				# What the embedded window's X sends (Window._event_callback); AcceptDialog cancels on it.
				dialog.notification(NOTIFICATION_WM_CLOSE_REQUEST)
		await wait_process_frames(1, "a cancel hides the dialog deferred")
		assert_true(GameSession.town_starve_acked, way)
		assert_false(dialog.visible, way)
		assert_false((hub.get_node("%PauseMenu") as CanvasLayer).visible, way)
		GameSession.tick_expeditions(1.0)
		assert_eq(GameSession.town_starving_seconds, STOP_1 + 1.0, "%s: the clock runs again" % way)


# ig-0og.2 (ACC 2, boundary #2): the dialog is a scene node, each close signal reaches the hub once,
# and the old button is gone.
func test_the_dialog_is_in_the_scene_and_each_close_signal_is_connected_once() -> void:
	var hub: Node3D = (load("res://hub/hub.tscn") as PackedScene).instantiate() as Node3D
	add_child_autofree(hub)
	var dialog: AcceptDialog = hub.get_node_or_null("%StarveDialog") as AcceptDialog
	assert_not_null(dialog, "%StarveDialog resolves")
	assert_null(hub.get_node_or_null("%StarveAck"), "the button is gone")
	for signal_name: String in ["confirmed", "canceled"]:
		var to_hub: Array = dialog.get_signal_connection_list(signal_name).filter(func(connection: Dictionary) -> bool: return (connection["callable"] as Callable).get_object() == hub)
		assert_eq(to_hub.size(), 1, signal_name)
		assert_eq((to_hub[0]["callable"] as Callable).get_method(), &"_on_starve_ack_pressed", signal_name)


# ig-0og.2 (ACC 3): one exclusive child per window. A stop reached while %ConfirmDialog is open waits,
# and pops at the first refresh after it closes.
func test_a_stop_behind_the_confirm_dialog_waits_and_pops_after_it_closes() -> void:
	_housed("Ada", Vector2i(0, 2))
	var hub: Node3D = (load("res://hub/hub.tscn") as PackedScene).instantiate() as Node3D
	add_child_autofree(hub)
	var confirm: ConfirmationDialog = hub.get_node("%ConfirmDialog") as ConfirmationDialog
	var dialog: AcceptDialog = hub.get_node("%StarveDialog") as AcceptDialog
	confirm.popup_centered(Vector2i(400, 200))
	GameSession.town_resources["food"] = 0.0
	GameSession.tick_expeditions(1.0e7)
	assert_true(GameSession.is_starvation_stopped())
	assert_false(dialog.visible, "it waits behind the confirm dialog")
	confirm.hide()
	GameSession.expeditions_changed.emit()
	assert_true(dialog.visible, "and pops at the next refresh")
	dialog.get_ok_button().pressed.emit()
	assert_true(GameSession.town_starve_acked)


func _hovered(hub: Node3D, at: Vector2) -> Control:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	hub.get_viewport().push_input(motion, true)
	return hub.get_viewport().gui_get_hovered_control()


func _load_with(state: Dictionary, clock: Variant, acked: Variant) -> void:
	state["town_starving_seconds"] = clock
	state["town_starve_acked"] = acked
	GameSession.from_dict(state)


func _disk_round_trip() -> void:
	assert_true(SaveService.save(), SaveService.last_write_error)
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(SaveService.SAVE_PATH)
	GameSession.from_dict({"roster": []})
	var file := FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	assert_true(SaveService.load_game())


func _scan(dir_path: String, hits: Array[String]) -> void:
	for sub: String in DirAccess.get_directories_at(dir_path):
		if not sub.begins_with(".") and sub not in ["addons", "tests", "tools", "export"]:
			_scan(dir_path.path_join(sub), hits)
	for file: String in DirAccess.get_files_at(dir_path):
		if file.ends_with(".gd"):
			var path: String = dir_path.path_join(file)
			if FileAccess.get_file_as_string(path).contains("roster.erase("):
				hits.append(path)


func _housed(hero_name: String, hex: Vector2i, rank: int = 0) -> Hero:
	var hero: Hero = _add_hero(hero_name, rank)
	assert_true(GameSession.assign_home(hero, _place(TownRules.HOUSE, hex)), GameSession.last_action_error)
	return hero


## Placed and finished at once: construction (ig-6m2.3.2) is not what this file tests.
func _place(type: StringName, hex: Vector2i) -> StringName:
	var id := StringName(GameSession.preview_place_building(type, hex)["id"])
	assert_true(GameSession.place_building(type, hex), GameSession.last_action_error)
	GameSession.town_building(id).erase("build_remaining")
	return id


## A real stranded incident holding the heroes, with the capture's own checkpoint so a save validates.
func _strand(heroes: Array[Hero]) -> void:
	var ids: Array[String] = []
	for hero: Hero in heroes:
		ids.append(hero.instance_id)
	var squad: Dictionary = {"id": "source-squad", "name": "Source", "hero_ids": ids, "stance": "stay_together", "guard_target_id": ""}
	var state: BattleState = BattleSimulation.create_run("source", GameSession._team_snapshots(heroes, [squad]), ZoneDefinition.definition_for(StringName(ZONE)), [squad], {}, {}, 544)
	for actor: BattleActor in state.actors:
		if actor.hero_id in ids:
			actor.life = BattleActor.LIFE_DOWNED
			actor.hp = 0.0
	GameSession.stranded_incidents.append({"id": "incident-%d" % (GameSession.stranded_incidents.size() + 1), "source_order_id": "gone-source", "zone_id": ZONE, "hero_ids": ids, "battle_snapshot": GameSession._incident_snapshot(state, ids), "created_recovery_seconds": GameSession.rescue_clock_seconds, "paused": true, "expiry_pending": false, "active_rescue_order_id": ""})


func _hero(hero_name: String, rank: int, level: int) -> Hero:
	var hero := Hero.new(hero_name, 7)
	hero.def_id = &"knight"
	hero.rank = rank
	hero.level = level
	return hero


func _add_hero(hero_name: String, rank: int = 0) -> Hero:
	var hero: Hero = _hero(hero_name, rank, 80)
	GameSession.add_hero(hero)
	return hero
