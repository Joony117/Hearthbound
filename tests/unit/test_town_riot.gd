extends GutTest

# ig-0og.3: the riot. A revolt that lasts town_riot_after_minutes burns a share of the spare wood and of
# the town stone every town_riot_burn_minutes, on the live tick only (SYSTEMS.md § Town mood and revolt).
# The pure rules (ACC 2), the clock (ACC 3), the fire (ACC 4), town_revolt_seconds' save (ACC 5,
# boundary #1) and the hub's lines and notice (ACC 6, boundary #2).

const BALANCE: BalanceTable = preload("res://balance.tres")
const RIOT: float = 1800.0
const BURN: float = 600.0
const LOADOUT: Dictionary = {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0}
const ZONE: String = "verdant_outskirts"


func before_each() -> void:
	GameSession.set_process(false)
	SaveService.load_blocked = false
	SaveService.load_block_reason = ""
	GameSession.from_dict({"roster": []})
	GameSession.town_resources["food"] = 1000.0
	GameSession.last_action_error = ""


func after_each() -> void:
	GameSession._cancel_battle_jobs()
	GameSession.set_process(true)


# ACC 1: the rows.
func test_the_riot_rows() -> void:
	assert_eq([BALANCE.town_riot_after_minutes, BALANCE.town_riot_burn_minutes, BALANCE.town_riot_burn_share], [30.0, 10.0, 0.1])


# ACC 2, pure: a fire at 30:00, then every 10:00; a long step fires once for each crossing it passes.
func test_riot_fires_counts_each_crossing() -> void:
	assert_eq(TownRules.riot_fires(0.0, RIOT - 1.0, BALANCE), 0, "before 30:00")
	assert_eq(TownRules.riot_fires(RIOT - 1.0, RIOT, BALANCE), 1, "at 30:00")
	assert_eq(TownRules.riot_fires(RIOT, RIOT + 1.0, BALANCE), 0, "a clock resting on a fire doesn't fire it again")
	assert_eq(TownRules.riot_fires(RIOT + 1.0, RIOT + BURN - 1.0, BALANCE), 0, "between fires")
	assert_eq(TownRules.riot_fires(RIOT + BURN - 1.0, RIOT + BURN, BALANCE), 1, "at 40:00")
	assert_eq(TownRules.riot_fires(RIOT - 1.0, RIOT + BURN + 1.0, BALANCE), 2, "29:59 to 40:01 in one step")
	assert_eq(TownRules.riot_fires(0.0, RIOT + 5.0 * BURN, BALANCE), 6, "30:00 to 80:00")
	assert_eq(TownRules.riot_seconds_to_next_fire(0.0, BALANCE), RIOT)
	assert_eq(TownRules.riot_seconds_to_next_fire(RIOT - 300.0, BALANCE), 300.0)
	assert_eq(TownRules.riot_seconds_to_next_fire(RIOT, BALANCE), BURN, "just fired: the next is a burn away")
	assert_eq(TownRules.riot_seconds_to_next_fire(RIOT + 420.0, BALANCE), 180.0)


# A burn gap of 0 or less (a bad balance row) fires once, at the riot's start, never again.
func test_a_zero_or_negative_burn_gap_fires_once_and_never_again() -> void:
	for gap: float in [0.0, -10.0]:
		var balance: BalanceTable = BALANCE.duplicate() as BalanceTable
		balance.town_riot_burn_minutes = gap
		assert_eq(TownRules.riot_fires(0.0, RIOT - 1.0, balance), 0, "before 30:00, gap %s" % gap)
		assert_eq(TownRules.riot_fires(0.0, 1.0e7, balance), 1, "one fire in a huge step, gap %s" % gap)
		assert_eq(TownRules.riot_fires(RIOT, 1.0e7, balance), 0, "none after it, gap %s" % gap)


# ACC 2, pure: a tenth of the wood over the House price, and a tenth of the stone.
func test_riot_burn_takes_a_tenth_of_the_spare_wood_and_of_the_stone() -> void:
	assert_eq(TownRules.riot_burn(150.0, 40.0, 50, BALANCE), {"wood": 140.0, "stone": 36.0, "burned_wood": 10.0, "burned_stone": 4.0})
	assert_eq(TownRules.riot_burn(50.0, 40.0, 50, BALANCE)["burned_wood"], 0.0, "at the price: nothing")
	assert_eq(TownRules.riot_burn(30.0, 40.0, 50, BALANCE)["wood"], 30.0, "under the price: nothing")
	assert_eq(TownRules.riot_burn(30.0, 0.0, 0, BALANCE), {"wood": 27.0, "stone": 0.0, "burned_wood": 3.0, "burned_stone": 0.0}, "a free House: all the wood is spare")


# ACC 3: in revolt the clock rises by the live delta; the first live tick outside one sets it to 0.
func test_the_revolt_clock_rises_by_the_live_delta_and_the_first_tick_out_resets_it() -> void:
	var heroes: Array[Hero] = _add_heroes(3, "Clock")
	GameSession.town_mood = 0.0
	GameSession.tick_expeditions(60.0)
	assert_eq(GameSession.town_revolt_seconds, 60.0)
	GameSession.tick_expeditions(0.25)
	assert_eq(GameSession.town_revolt_seconds, 60.25)
	assert_true(GameSession.assign_home(heroes[0], _place(TownRules.HOUSE, Vector2i(0, 2))), GameSession.last_action_error)
	assert_false(GameSession.is_in_revolt(), "two homeless")
	assert_eq(GameSession.town_revolt_seconds, 60.25, "a bed alone moves no clock")
	GameSession.tick_expeditions(0.25)
	assert_eq(GameSession.town_revolt_seconds, 0.0, "the first live tick out")


# ACC 3: a revolt that ends at 29 minutes and starts again waits a fresh 30.
func test_a_revolt_that_ends_at_29_minutes_and_starts_again_waits_a_fresh_30() -> void:
	var heroes: Array[Hero] = _add_heroes(3, "Again")
	GameSession.town_resources["wood"] = 100.0
	GameSession.town_mood = 0.0
	for _minute: int in 29:
		GameSession.tick_expeditions(60.0)
	assert_eq(GameSession.town_revolt_seconds, 29.0 * 60.0)
	assert_true(GameSession.assign_home(heroes[0], _place(TownRules.HOUSE, Vector2i(0, 2))), GameSession.last_action_error)
	GameSession.tick_expeditions(60.0)
	assert_eq(GameSession.town_revolt_seconds, 0.0)
	_add_heroes(1, "Back")
	GameSession.town_mood = 0.0
	var wood: float = GameSession.town_resources["wood"]
	for _minute: int in 29:
		GameSession.tick_expeditions(60.0)
	assert_eq(GameSession.town_resources["wood"], wood, "29 fresh minutes: no fire")
	GameSession.tick_expeditions(60.0)
	assert_lt(float(GameSession.town_resources["wood"]), wood, "the 30th")


# ACC 3: the offline catch-up moves neither the clock nor any stock.
func test_the_offline_catch_up_moves_no_clock_and_no_stock() -> void:
	var heroes: Array[Hero] = _add_heroes(3, "Offline")
	# A real order, so apply_offline_expedition_progress runs its committed catch-up, not its early return.
	var order_id: String = GameSession.dispatch_force([_preset([heroes[0]])], ZONE, 1, {}, LOADOUT)
	assert_ne(order_id, "", GameSession.last_action_error)
	var remaining: float = float(GameSession.expedition_orders[0]["remaining_seconds"])
	GameSession.town_mood = 0.0
	GameSession.town_revolt_seconds = RIOT - 10.0
	GameSession.town_resources["wood"] = 100.0
	GameSession.town_resources["stone"] = 50.0
	var before: Dictionary = GameSession.town_resources.duplicate()
	GameSession.saved_at_unix = Time.get_unix_time_from_system() - 36000.0
	GameSession.apply_offline_expedition_progress(Time.get_unix_time_from_system())
	var index: int = GameSession._order_index(order_id)
	assert_true(index < 0 or float(GameSession.expedition_orders[index]["remaining_seconds"]) < remaining, "the catch-up ran")
	assert_eq(GameSession.town_revolt_seconds, RIOT - 10.0, "the clock, after the committed catch-up")
	assert_eq(GameSession.town_resources, before, "the stock, after the committed catch-up")
	GameSession._advance_orders_in_memory(360000.0)
	assert_eq(GameSession.town_revolt_seconds, RIOT - 10.0, "the clock")
	assert_eq(GameSession.town_resources, before, "the stock")
	assert_eq(GameSession.take_town_notice()["fires"], 0)


# ACC 4: the first fire at 30 minutes of revolt, then every 10.
func test_the_first_fire_at_30_minutes_then_every_10() -> void:
	_add_heroes(3, "Fire")
	GameSession.town_resources["wood"] = 1000.0
	GameSession.town_resources["stone"] = 100.0
	GameSession.town_mood = 0.0
	for _minute: int in 29:
		GameSession.tick_expeditions(60.0)
	assert_eq([GameSession.town_resources["wood"], GameSession.town_resources["stone"]], [1000.0, 100.0], "29:00")
	GameSession.tick_expeditions(60.0)
	assert_eq([GameSession.town_resources["wood"], GameSession.town_resources["stone"]], [900.0, 90.0], "30:00, a free House: all the wood is spare")
	for _minute: int in 9:
		GameSession.tick_expeditions(60.0)
	assert_eq([GameSession.town_resources["wood"], GameSession.town_resources["stone"]], [900.0, 90.0], "39:00")
	GameSession.tick_expeditions(60.0)
	assert_eq([GameSession.town_resources["wood"], GameSession.town_resources["stone"]], [810.0, 81.0], "40:00")
	assert_eq(GameSession.take_town_notice(), {"starved": [], "fires": 2, "wood": 190.0, "stone": 19.0})


# ACC 4: a fire burns no food, Summon Stone, hero or building; a riot of hours kills nobody.
func test_a_fire_burns_no_food_summon_stone_hero_or_building_and_kills_nobody() -> void:
	var heroes: Array[Hero] = _add_heroes(4, "Safe")
	_place(TownRules.HOUSE, Vector2i(0, 2))
	_place(TownRules.FARM, Vector2i(1, 2))
	GameSession.town_resources["wood"] = 500.0
	GameSession.town_resources["stone"] = 80.0
	GameSession.stones = 70
	var food: float = GameSession.town_resources["food"]
	var buildings: Array[Dictionary] = GameSession.town_buildings.duplicate(true)
	GameSession._riot_in_memory(3, BALANCE)
	assert_lt(float(GameSession.town_resources["wood"]), 500.0, "wood burned")
	assert_lt(float(GameSession.town_resources["stone"]), 80.0, "stone burned")
	assert_eq(GameSession.town_resources["food"], food, "food")
	assert_eq(GameSession.stones, 70, "Summon Stones")
	assert_eq(GameSession.town_buildings, buildings, "buildings")
	assert_eq(GameSession.roster.size(), 4, "heroes")
	GameSession.town_mood = 0.0
	var seq: int = GameSession.ledger_next_seq
	for _minute: int in 3 * 60:
		GameSession.tick_expeditions(60.0)
	assert_true(GameSession.is_in_revolt())
	assert_eq(GameSession.town_revolt_seconds, 3.0 * 3600.0)
	assert_eq(GameSession.roster.size(), 4, "nobody died")
	for hero: Hero in heroes:
		assert_not_null(GameSession.hero_by_id(hero.instance_id))
	assert_eq(GameSession.ledger_next_seq, seq, "no record")
	assert_eq(GameSession.stones, 70)


# ACC 4: with wood at the next House's price, a fire burns none of it and the House still goes up.
func test_with_wood_at_the_next_house_price_placing_it_still_works_after_a_fire() -> void:
	_add_heroes(3, "Price")
	_place(TownRules.HOUSE, Vector2i(0, 2))
	var price: int = TownRules.wood_cost(TownRules.HOUSE, GameSession.town_buildings, BALANCE)
	assert_eq(price, BALANCE.house_wood_cost, "the second House")
	GameSession.town_resources["wood"] = float(price)
	GameSession.town_resources["stone"] = 50.0
	GameSession.town_mood = 0.0
	GameSession.town_revolt_seconds = RIOT - 1.0
	GameSession.tick_expeditions(1.0)
	assert_eq(GameSession.town_resources["stone"], 45.0, "it fired")
	assert_eq(GameSession.town_resources["wood"], float(price), "the House's wood stays")
	assert_true(GameSession.place_building(TownRules.HOUSE, Vector2i(1, 2)), GameSession.last_action_error)
	assert_eq(GameSession.town_resources["wood"], 0.0)


# ACC 5 (boundary #1): a real save mid-revolt, through the disk, keeps the clock exactly.
func test_the_revolt_clock_survives_a_disk_round_trip_mid_revolt() -> void:
	_add_heroes(3, "Disk")
	GameSession.town_mood = 0.0
	GameSession.tick_expeditions(45.0)
	GameSession.tick_expeditions(0.1)
	GameSession.tick_expeditions(1234.567)
	var clock: float = GameSession.town_revolt_seconds
	assert_eq(clock, 45.0 + 0.1 + 1234.567, "a fraction in play")
	_disk_round_trip()
	assert_eq(GameSession.town_revolt_seconds, clock)
	assert_push_warning_count(0)


# ACC 5: a legacy save without the key loads 0, with no warning.
func test_a_legacy_save_without_the_key_loads_0() -> void:
	_add_heroes(3, "Legacy")
	GameSession.town_mood = 0.0
	GameSession.town_revolt_seconds = 900.0
	assert_true(SaveService.save(), SaveService.last_write_error)
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveService.SAVE_PATH)) as Dictionary
	assert_eq(saved["town_revolt_seconds"], 900.0)
	saved.erase("town_revolt_seconds")
	GameSession.from_dict({"roster": []})
	_write(JSON.stringify(saved, "\t").to_utf8_buffer())
	assert_true(SaveService.load_game(), SaveService.load_block_reason)
	assert_eq(GameSession.town_revolt_seconds, 0.0)
	assert_eq(GameSession.roster.size(), 3)
	assert_push_warning_count(0)


# ACC 5: a bad value (not a number, or under 0) warns and reads 0; null reads 0 quietly.
func test_a_bad_revolt_clock_warns_and_reads_0() -> void:
	var state: Dictionary = GameSession.to_dict()
	for bad: Variant in ["soon", -5.0, INF, NAN]:
		state["town_revolt_seconds"] = bad
		GameSession.from_dict(state)
		assert_eq(GameSession.town_revolt_seconds, 0.0, str(bad))
		assert_push_warning("Invalid town_revolt_seconds")
	state["town_revolt_seconds"] = null
	GameSession.from_dict(state)
	assert_eq(GameSession.town_revolt_seconds, 0.0, "null")
	assert_push_warning_count(4)
	state["town_revolt_seconds"] = 1799.5
	GameSession.from_dict(state)
	assert_eq(GameSession.town_revolt_seconds, 1799.5)


# ACC 5: the one new key is top-level; no Hero, order or building key.
func test_the_one_new_key_is_top_level() -> void:
	_add_heroes(3, "Keys")
	GameSession.town_mood = 0.0
	GameSession.tick_expeditions(RIOT)
	_place(TownRules.HOUSE, Vector2i(0, 2))
	var state: Dictionary = GameSession.to_dict()
	assert_eq(state["town_revolt_seconds"], RIOT)
	for data: Dictionary in [state["roster"][0], state["town_buildings"][0], state["town_buildings"].back(), state["town_resources"]]:
		for key: String in data.keys():
			for word: String in ["riot", "revolt", "burn", "notice"]:
				assert_false(key.contains(word), "%s in %s" % [key, str(data.keys())])
	var top: Array = state.keys().filter(func(key: String) -> bool: return key.contains("riot") or key.contains("revolt") or key.contains("notice"))
	assert_eq(top, ["town_revolt_seconds"])


# ACC 6 (boundary #2): the revolt line counts down to the riot; the riot line says when the next fire is.
func test_the_hub_counts_down_to_the_riot_and_to_each_next_fire() -> void:
	_add_heroes(3, "Hub")
	var hub: Node3D = _hub()
	var text: Label = hub.get_node("%StarveText") as Label
	GameSession.town_mood = 0.0
	GameSession.expeditions_changed.emit()
	assert_eq(text.text, "Revolt: no order or repeat goes out until at most 2 heroes are homeless. Riot in 30:00.")
	GameSession.town_revolt_seconds = RIOT - 300.0
	GameSession.expeditions_changed.emit()
	assert_eq(text.text, "Revolt: no order or repeat goes out until at most 2 heroes are homeless. Riot in 5:00.")
	GameSession.town_revolt_seconds = RIOT
	GameSession.expeditions_changed.emit()
	assert_eq(text.text, "Riot: a tenth of the spare wood and the stone burns every 10 minutes (next in 10:00). No order goes out until at most 2 heroes are homeless.")
	GameSession.town_revolt_seconds = RIOT + 420.0
	GameSession.expeditions_changed.emit()
	assert_eq(text.text, "Riot: a tenth of the spare wood and the stone burns every 10 minutes (next in 3:00). No order goes out until at most 2 heroes are homeless.")


# ACC 6: %Status shows the fires since the hub last looked, once, as one total; "nothing spare" at 0.
func test_the_hub_says_the_fires_once_as_one_total_and_nothing_spare_at_zero() -> void:
	_add_heroes(3, "Status")
	var hub: Node3D = _hub()
	var status: Label = hub.get_node("%Status") as Label
	GameSession.town_resources["wood"] = 1000.0
	GameSession.town_resources["stone"] = 100.0
	GameSession.town_mood = 0.0
	GameSession.town_revolt_seconds = RIOT - 1.0
	GameSession.tick_expeditions(BURN + 2.0)
	assert_eq(status.text, "Rioters burned 190 wood and 19 stone.", "two fires, one line")
	status.text = "later"
	GameSession.expeditions_changed.emit()
	assert_eq(status.text, "later", "said once")
	GameSession.town_resources["wood"] = 5.0
	GameSession.town_resources["stone"] = 0.0
	GameSession.tick_expeditions(BURN)
	assert_eq(GameSession.town_resources["wood"], 4.5, "half a wood burned")
	assert_eq(status.text, "Rioters found nothing spare to burn.")


# ACC 6: fires while the battle view is up (no hub) show when the hub comes back, once.
func test_fires_during_the_battle_view_show_when_the_hub_comes_back() -> void:
	_add_heroes(3, "Away")
	GameSession.town_resources["wood"] = 200.0
	GameSession.town_resources["stone"] = 0.0
	GameSession.town_mood = 0.0
	for _minute: int in 40:
		GameSession.tick_expeditions(60.0)
	assert_eq(GameSession.town_resources["wood"], 162.0, "two fires: 20 then 18")
	var hub: Node3D = _hub()
	var status: Label = hub.get_node("%Status") as Label
	assert_eq(status.text, "Rioters burned 38 wood and 0 stone.")
	status.text = "later"
	GameSession.expeditions_changed.emit()
	assert_eq(status.text, "later", "not again")


# ACC 6: back from the arena with a notice pending, %Status shows the arena line and the notice.
func test_back_from_the_arena_the_status_shows_the_arena_line_and_the_notice() -> void:
	_add_heroes(3, "Arena")
	GameSession.town_resources["wood"] = 100.0
	GameSession.town_resources["stone"] = 50.0
	GameSession.town_mood = 0.0
	GameSession.town_revolt_seconds = RIOT - 1.0
	GameSession.tick_expeditions(1.0)
	var survivor := Hero.new("Ada", 7)
	var result := CombatResult.new()
	result.survivors.append(survivor)
	result.hp_after[survivor] = 40.0
	result.maximum_hp[survivor] = 50.0
	SceneRouter.store_arena_result(result)
	var hub: Node3D = _hub()
	assert_eq((hub.get_node("%Status") as Label).text, "Arena victory: Ada survived with 40/50 HP. Rioters burned 10 wood and 5 stone.")


# A failed save's rollback puts the notice back as it was before the transaction: an untaken fire stays.
func test_a_failed_save_keeps_an_untaken_fire_and_drops_nothing() -> void:
	var victim: Hero = _add_heroes(3, "Kept")[0]
	GameSession.town_resources["wood"] = 100.0
	GameSession.town_mood = 0.0
	GameSession.town_revolt_seconds = RIOT - 1.0
	GameSession.tick_expeditions(1.0)
	GameSession.town_resources["food"] = 0.0
	GameSession.town_starving_seconds = TownRules.starve_due_seconds(0.0, BALANCE) - 1.0
	GameSession.town_starve_acked = true
	assert_eq(DirAccess.make_dir_absolute(SaveService.TMP_PATH), OK)
	GameSession.tick_expeditions(1.0)
	assert_push_error("Save failed")
	assert_eq(DirAccess.remove_absolute(SaveService.TMP_PATH), OK)
	assert_eq(GameSession.roster.size(), 3, "the death was undone")
	assert_not_null(GameSession.hero_by_id(victim.instance_id))
	assert_eq(GameSession.town_revolt_seconds, RIOT, "the failed tick's second is undone too")
	assert_eq(GameSession.take_town_notice(), {"starved": [], "fires": 1, "wood": 10.0, "stone": 0.0}, "the fire from before stays; the undone death isn't said")


# A live tick that fires AND starves someone commits; a failed save undoes both, says neither, and the
# retry says both once.
func test_a_failed_save_on_a_tick_that_fires_and_starves_undoes_both_and_the_retry_says_both_once() -> void:
	# Four homeless, so the death leaves three and the revolt (and the fire) stand.
	var heroes: Array[Hero] = _add_heroes(4, "Both")
	var victim: Hero = heroes[3]
	GameSession.town_resources["wood"] = 100.0
	GameSession.town_resources["stone"] = 50.0
	GameSession.town_mood = 0.0
	GameSession.town_revolt_seconds = RIOT - 1.0
	GameSession.town_resources["food"] = 0.0
	GameSession.town_starving_seconds = TownRules.starve_due_seconds(0.0, BALANCE) - 1.0
	GameSession.town_starve_acked = true
	var hub: Node3D = _hub()
	var status: Label = hub.get_node("%Status") as Label
	status.text = "before"
	assert_eq(DirAccess.make_dir_absolute(SaveService.TMP_PATH), OK)
	GameSession.tick_expeditions(1.0)
	assert_push_error("Save failed")
	assert_eq(DirAccess.remove_absolute(SaveService.TMP_PATH), OK)
	assert_eq([GameSession.town_resources["wood"], GameSession.town_resources["stone"]], [100.0, 50.0], "the fire is undone")
	assert_eq(GameSession.town_revolt_seconds, RIOT - 1.0, "so is the clock")
	assert_eq(GameSession.roster.size(), 4, "and the death")
	assert_not_null(GameSession.hero_by_id(victim.instance_id))
	assert_eq(status.text, "before", "nothing said")
	assert_eq(GameSession.take_town_notice(), {"starved": [], "fires": 0, "wood": 0.0, "stone": 0.0}, "nothing pending")
	GameSession.tick_expeditions(1.0)
	assert_null(GameSession.hero_by_id(victim.instance_id), "the retry goes through")
	assert_eq([GameSession.town_resources["wood"], GameSession.town_resources["stone"]], [90.0, 45.0], "and fires")
	assert_eq(status.text, "Both 3 starved. Rioters burned 10 wood and 5 stone.")
	status.text = "later"
	GameSession.expeditions_changed.emit()
	assert_eq(status.text, "later", "once")


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


func _hub() -> Node3D:
	var hub: Node3D = (load("res://hub/hub.tscn") as PackedScene).instantiate() as Node3D
	add_child_autofree(hub)
	return hub


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
