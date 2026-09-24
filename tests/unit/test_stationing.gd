extends GutTest

# ig-wgj.9: a hero keeps a town building (DECISIONS.md 2026-09-23 item 5). Protected, never busy.

const BALANCE: BalanceTable = preload("res://balance.tres")
const LOADOUT: Dictionary = {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0}


func before_each() -> void:
	GameSession.set_process(false)
	GameSession.from_dict({"roster": []})


func after_each() -> void:
	GameSession.set_process(true)


func test_one_keeper_per_building_and_a_new_one_replaces_the_old() -> void:
	var mira: Hero = _add_hero("Mira")
	var bo: Hero = _add_hero("Bo")
	watch_signals(GameSession)
	assert_true(GameSession.station_hero(mira, &"Forge"))
	assert_eq(GameSession.keeper_for(&"Forge"), mira)
	assert_signal_emitted(GameSession, "roster_changed")
	assert_true(GameSession.station_hero(bo, &"Forge"))
	assert_eq(GameSession.keeper_for(&"Forge"), bo)
	assert_eq(mira.station, Hero.NO_STATION, "the old keeper leaves the counter")


func test_moving_a_keeper_moves_its_station() -> void:
	var mira: Hero = _add_hero("Mira")
	assert_true(GameSession.station_hero(mira, &"Forge"))
	assert_true(GameSession.station_hero(mira, &"Sanctum"))
	assert_null(GameSession.keeper_for(&"Forge"))
	assert_eq(GameSession.keeper_for(&"Sanctum"), mira)


func test_unstation_clears_the_building() -> void:
	var mira: Hero = _add_hero("Mira")
	assert_true(GameSession.station_hero(mira, &"Apothecary"))
	assert_true(GameSession.unstation_hero(mira))
	assert_eq(mira.station, Hero.NO_STATION)
	assert_null(GameSession.keeper_for(&"Apothecary"))


func test_a_building_without_a_counter_or_a_stranger_is_refused() -> void:
	var mira: Hero = _add_hero("Mira")
	for building_id: StringName in [&"SummoningCircle", &"TownGate", &"Nowhere", Hero.NO_STATION]:
		assert_false(GameSession.station_hero(mira, building_id), "%s takes no keeper" % building_id)
		assert_ne(GameSession.last_action_error, "")
	assert_eq(mira.station, Hero.NO_STATION)
	var stranger := Hero.new("Stranger", 0)
	assert_false(GameSession.station_hero(stranger, &"Forge"))
	assert_false(GameSession.station_hero(null, &"Forge"))
	assert_null(GameSession.keeper_for(&"Forge"))


func test_a_keeper_cannot_be_sacrificed_single_or_bulk_but_stays_free_to_work() -> void:
	var keeper: Hero = _add_hero("Keeper")
	var target: Hero = _add_hero("Target")
	assert_true(GameSession.station_hero(keeper, &"Forge"))
	assert_true(GameSession.is_hero_protected(keeper))
	assert_false(GameSession.is_hero_busy(keeper), "protected, not busy")
	assert_false(GameSession.sacrifice_hero(keeper, target, BALANCE))
	assert_true(GameSession.roster.has(keeper))
	var plan: Dictionary = GameSession.preview_bulk_sacrifice([keeper.instance_id], target.instance_id, 0)
	assert_true((plan["entries"] as Array).is_empty())
	assert_eq((plan["excluded"] as Array)[0]["reason"], "Keeps the Forge")
	# Gear and rank-up stay open.
	var ring := Item.new(&"ring", 0)
	GameSession.add_item(ring)
	GameSession.equip_item(keeper, ring)
	assert_true(keeper.equipped.values().has(ring))
	keeper.rank = 0
	GameSession.essence = 1000000
	assert_true(GameSession.rank_up_hero(keeper, BALANCE))


func test_a_keeper_goes_out_on_an_expedition_and_a_force_and_keeps_its_station() -> void:
	var keeper: Hero = _add_hero("Keeper")
	assert_true(GameSession.station_hero(keeper, &"Forge"))
	assert_ne(GameSession.dispatch_expedition([keeper.instance_id], "verdant_outskirts", 1, "Out"), "", GameSession.last_action_error)
	assert_true(GameSession.is_hero_busy(keeper))
	assert_eq(GameSession.keeper_for(&"Forge"), keeper, "the station stays while it is away")
	_settle()
	assert_eq(GameSession.keeper_for(&"Forge"), keeper, "and after it returns")
	var ids: Array[String] = [keeper.instance_id]
	var presets: Array[String] = [GameSession.save_team_preset("", "Team", ids, "verdant_outskirts")]
	assert_true(bool(GameSession.preview_force(presets, "verdant_outskirts", 1, {}, LOADOUT).get("valid", false)))
	assert_ne(GameSession.dispatch_force(presets, "verdant_outskirts", 1, {}, LOADOUT), "", GameSession.last_action_error)
	assert_true(GameSession.is_hero_busy(keeper))
	_settle()
	assert_eq(GameSession.keeper_for(&"Forge"), keeper)


func test_a_keeper_goes_on_a_rescue_and_recovers_a_cache_and_keeps_its_station() -> void:
	GameSession.cleared_zone_ids = {&"verdant_outskirts": true, &"ashfall_reaches": true}
	var victim := Hero.new("Doomed", 0)
	victim.def_id = &"mage"
	GameSession.add_hero(victim)
	var doomed: Array[String] = [GameSession.save_team_preset("", "Doomed", [victim.instance_id], "sundered_vault")]
	assert_ne(GameSession.dispatch_force(doomed, "sundered_vault", 1, {}, LOADOUT), "")
	for _second: int in 300:
		if not GameSession.stranded_incidents.is_empty():
			break
		GameSession.tick_expeditions(1.0)
	assert_eq(GameSession.stranded_incidents.size(), 1, "the victim strands")
	if GameSession.stranded_incidents.is_empty():
		return
	var keeper: Hero = _add_hero("Keeper")
	assert_true(GameSession.station_hero(keeper, &"Sanctum"))
	var rescue_preset: String = GameSession.save_team_preset("", "Rescue", [keeper.instance_id], "sundered_vault")
	assert_ne(GameSession.dispatch_rescue(str(GameSession.stranded_incidents[0]["id"]), rescue_preset, LOADOUT), "", GameSession.last_action_error)
	assert_true(GameSession.is_hero_busy(keeper))
	_settle()
	assert_eq(GameSession.keeper_for(&"Sanctum"), keeper, "home from the rescue, still the keeper")
	var cache := LostCache.new("Lost", &"verdant_outskirts", 0)
	GameSession.lost_caches.append(cache)
	var team: Array[Hero] = [keeper]
	assert_eq(GameSession.recover_cache(cache, team, BALANCE), GameSession.RECOVERY_COMPLETED, GameSession.last_action_error)
	assert_eq(GameSession.keeper_for(&"Sanctum"), keeper)


func test_the_station_leaves_with_a_dead_keeper() -> void:
	var keeper: Hero = _add_hero("Doomed Keeper")
	assert_true(GameSession.station_hero(keeper, &"Reliquary"))
	GameSession.kill_hero(keeper, &"verdant_outskirts", BALANCE)
	assert_null(GameSession.keeper_for(&"Reliquary"))
	# Nothing cleared it: the station went with the hero, so no second path ran after the death.
	assert_eq(keeper.station, &"Reliquary")


func test_a_station_survives_save_and_reload_through_disk() -> void:
	var keeper: Hero = _add_hero("Mira")
	_add_hero("Bo")
	assert_true(GameSession.station_hero(keeper, &"TrainingHall"))
	assert_true(SaveService.save())
	# Changed in memory only, so only the file can put it back.
	keeper.station = Hero.NO_STATION
	assert_true(SaveService.load_game())
	var loaded: Hero = GameSession.keeper_for(&"TrainingHall")
	assert_not_null(loaded)
	if loaded != null:
		assert_eq(loaded.instance_id, keeper.instance_id)
	assert_eq(GameSession.roster.size(), 2)


func test_a_save_without_the_key_loads_with_no_keepers() -> void:
	var keeper: Hero = _add_hero("Mira")
	assert_true(GameSession.station_hero(keeper, &"Forge"))
	var state: Dictionary = GameSession.to_dict()
	for entry: Variant in state["roster"]:
		(entry as Dictionary).erase("station")
	var file := FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(state))
	file.close()
	assert_true(SaveService.load_game())
	assert_eq(GameSession.roster.size(), 1)
	for building_id: StringName in Hero.PROFESSIONS.values():
		assert_null(GameSession.keeper_for(building_id))
	assert_push_warning_count(0)


func test_a_doubly_claimed_building_keeps_the_first_in_roster_order() -> void:
	var first: Hero = _add_hero("First")
	var second: Hero = _add_hero("Second")
	var state: Dictionary = GameSession.to_dict()
	for entry: Variant in state["roster"]:
		(entry as Dictionary)["station"] = "Forge"
	GameSession.from_dict(state)
	assert_push_warning("Second also claimed the Forge")
	assert_eq(GameSession.keeper_for(&"Forge").instance_id, first.instance_id)
	assert_eq(GameSession.hero_by_id(second.instance_id).station, Hero.NO_STATION)


func test_an_unknown_station_loads_as_none() -> void:
	_add_hero("Mira")
	var state: Dictionary = GameSession.to_dict()
	for bad: Variant in ["Nowhere", "TownGate", 7]:
		(state["roster"][0] as Dictionary)["station"] = bad
		GameSession.from_dict(state)
		assert_eq(GameSession.roster[0].station, Hero.NO_STATION, "%s loads as none" % bad)
	assert_push_warning_count(3)


func test_a_station_loads_from_a_save_without_profession_xp() -> void:
	var keeper: Hero = _add_hero("Mira")
	var state: Dictionary = GameSession.to_dict()
	var entry: Dictionary = state["roster"][0]
	entry.erase("profession_xp")
	entry["station"] = "Forge"
	GameSession.from_dict(state)
	assert_eq(GameSession.keeper_for(&"Forge").instance_id, keeper.instance_id)


func test_a_blocked_load_refuses_even_a_no_op_station_change() -> void:
	var keeper: Hero = _add_hero("Mira")
	assert_true(GameSession.station_hero(keeper, &"Forge"))
	var loose: Hero = _add_hero("Bo")
	SaveService.load_blocked = true
	SaveService.load_block_reason = "Blocked for the test."
	assert_false(GameSession.station_hero(keeper, &"Forge"))
	assert_eq(GameSession.last_action_error, "Blocked for the test.")
	assert_false(GameSession.unstation_hero(loose))
	assert_eq(GameSession.last_action_error, "Blocked for the test.")
	SaveService.load_blocked = false
	SaveService.load_block_reason = ""


func test_a_failed_save_rolls_the_station_back() -> void:
	var keeper: Hero = _add_hero("Mira")
	assert_true(SaveService.save())
	assert_eq(DirAccess.make_dir_absolute(SaveService.TMP_PATH), OK)
	assert_false(GameSession.station_hero(keeper, &"Forge"))
	assert_push_error("Save failed")
	assert_ne(GameSession.last_action_error, "")
	assert_null(GameSession.keeper_for(&"Forge"))
	assert_eq(DirAccess.remove_absolute(SaveService.TMP_PATH), OK)


func _add_hero(hero_name: String) -> Hero:
	var hero := Hero.new(hero_name, 7)
	hero.def_id = &"knight"
	hero.level = 80
	GameSession.add_hero(hero)
	return hero


## Ticks until nothing is out, so the heroes are home again.
func _settle() -> void:
	for _second: int in 3000:
		if GameSession.expedition_orders.is_empty() and GameSession.stranded_incidents.is_empty():
			return
		GameSession.tick_expeditions(1.0)
	fail_test("the expedition never came home")
