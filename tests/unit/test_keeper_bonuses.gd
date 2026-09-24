extends GutTest

# ig-wgj.10: a home keeper's skill counts as half a building level in its building's own term, past
# the cap; the Apothecary cuts draught cost instead. Keepers earn XP on the live tick only. A running
# rescue window or cache keeps the longest lifetime it has had (SYSTEMS.md § Keepers and professions).

const BALANCE: BalanceTable = preload("res://balance.tres")
const SKILL_XP: Dictionary[int, float] = {0: 0.0, 3: 120.0 * 60.0, 5: 300.0 * 60.0}
const LOADOUT: Dictionary = {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0}
const BASE_LIFETIME: float = 900.0
const TRACKER_LIFETIME: float = 900.0 + 300.0 * 2.5


func before_each() -> void:
	GameSession.set_process(false)
	SaveService.load_blocked = false
	SaveService.load_block_reason = ""
	GameSession.from_dict({"roster": []})


func after_each() -> void:
	GameSession.set_process(true)


func test_forge_salvage_at_skill_0_3_5_matches_systems_and_the_settle() -> void:
	GameSession.building_levels[1] = 5
	var smith: Hero = _keeper("Mira", &"Forge", &"smithing")
	# Base 8 parts (+5) at a maxed Forge: x1.5, then +5% per skill level past the cap.
	for case: Array in [[0, 12], [3, 13], [5, 14]]:
		_set_skill(smith, &"smithing", case[0])
		var item := Item.new(&"ring", 1)
		item.enhance_level = 5
		GameSession.add_item(item)
		assert_eq(GameSession.keeper_skill(&"Forge"), case[0])
		assert_eq(GameSession.salvage_yield(item), case[1], "skill %d" % case[0])
		var plan: Dictionary = GameSession.preview_bulk_salvage([item.instance_id] as Array[String], 0)
		assert_eq(int(plan["gain_parts"][1]), case[1], "bulk preview")
		var before: int = GameSession.parts[1]
		GameSession.salvage_item(item, BALANCE)
		assert_eq(GameSession.parts[1] - before, case[1], "the settle pays the preview")
	GameSession.building_levels[1] = 999
	var capped := Item.new(&"ring", 1)
	capped.enhance_level = 5
	assert_eq(GameSession.salvage_yield(capped), 14, "the level clamps first, then the keeper adds")


func test_bulk_salvage_commit_pays_its_preview_and_goes_stale_when_the_keeper_leaves() -> void:
	var smith: Hero = _keeper("Mira", &"Forge", &"smithing")
	_set_skill(smith, &"smithing", 5)
	var item := Item.new(&"ring", 2)
	GameSession.add_item(item)
	var plan: Dictionary = GameSession.preview_bulk_salvage([item.instance_id] as Array[String], 0)
	assert_eq(int(plan["gain_parts"][2]), roundi(3 * 1.25))
	assert_true(GameSession.unstation_hero(smith), GameSession.last_action_error)
	assert_false(GameSession.commit_bulk_plan(plan), "a plan priced with the keeper is stale without it")
	assert_true(GameSession.station_hero(smith, &"Forge"), GameSession.last_action_error)
	var before: int = GameSession.parts[2]
	assert_true(GameSession.commit_bulk_plan(plan), GameSession.last_action_error)
	assert_eq(GameSession.parts[2] - before, int(plan["gain_parts"][2]))


func test_sacrifice_and_supply_plans_go_stale_when_the_keeper_changes() -> void:
	var priest: Hero = _keeper("Sera", &"Sanctum", &"rites")
	_set_skill(priest, &"rites", 5)
	var target: Hero = _add_hero("Target")
	var fodder: Hero = _add_hero("Fodder")
	var sacrifice: Dictionary = GameSession.preview_bulk_sacrifice([fodder.instance_id] as Array[String], target.instance_id, 0)
	var alchemist: Hero = _keeper("Ivo", &"Apothecary", &"alchemy")
	_set_skill(alchemist, &"alchemy", 5)
	GameSession.parts[0] = 100
	var supplies: Dictionary = GameSession.preview_bulk_supplies("revival", 2, 0)
	_set_skill(priest, &"rites", 3)
	_set_skill(alchemist, &"alchemy", 3)
	assert_false(GameSession.commit_bulk_plan(sacrifice), "priced at Rites 5")
	assert_false(GameSession.commit_bulk_plan(supplies), "priced at Alchemy 5")
	assert_eq(GameSession.parts[0], 100)
	assert_true(GameSession.roster.has(fodder))


func test_the_inventory_tooltip_shows_the_keeper_salvage() -> void:
	var smith: Hero = _keeper("Mira", &"Forge", &"smithing")
	_set_skill(smith, &"smithing", 5)
	var item := Item.new(&"ring", 1)
	item.enhance_level = 5
	GameSession.add_item(item)
	var hub: Node3D = _instantiate_hub()
	var tooltip: String = (hub.get_node("%InventoryList") as ItemList).get_item_tooltip(0)
	assert_string_contains(tooltip, "Salvage: %d %s parts" % [roundi(8 * 1.25), item.rank_label(BALANCE)])


func test_sanctum_essence_at_skill_0_3_5_matches_systems_and_the_settle() -> void:
	var priest: Hero = _keeper("Sera", &"Sanctum", &"rites")
	var target: Hero = _add_hero("Target")
	for case: Array in [[0, 1.0], [3, 1.15], [5, 1.25]]:
		_set_skill(priest, &"rites", case[0])
		var fodder: Hero = _add_hero("Fodder")
		fodder.def_id = &"rogue"
		# The yield before any bonus (SYSTEMS.md § Sacrifice); the keeper multiplies it once, at the end.
		var cap: int = maxi(BALANCE.level_caps[fodder.rank], 1)
		var before_bonus: float = BALANCE.essence_bases[fodder.rank] * (1.0 + float(Hero.level_for(fodder, BALANCE)) / float(cap))
		var expected: int = roundi(before_bonus * case[1])
		var plan: Dictionary = GameSession.preview_bulk_sacrifice([fodder.instance_id] as Array[String], target.instance_id, 0)
		assert_eq(int(plan["essence_gain"]), expected, "skill %d preview" % case[0])
		var before: int = GameSession.essence
		assert_true(GameSession.sacrifice_hero(fodder, target, BALANCE))
		assert_eq(GameSession.essence - before, expected, "skill %d settle" % case[0])


func test_training_hall_xp_multiplier_at_skill_0_3_5() -> void:
	var drill: Hero = _keeper("Brakk", &"TrainingHall", &"drill")
	for case: Array in [[0, 1.0], [3, 1.225], [5, 1.375]]:
		_set_skill(drill, &"drill", case[0])
		assert_almost_eq(GameSession.training_xp_multiplier(), case[1], 0.0001, "skill %d" % case[0])
	GameSession.building_levels[2] = 999
	assert_almost_eq(GameSession.training_xp_multiplier(), 1.0 + 0.15 * 7.5, 0.0001, "a maxed hall reads as level 7.5")


func test_reliquary_lifetime_at_skill_0_3_5() -> void:
	var tracker: Hero = _keeper("Tam", &"Reliquary", &"tracking")
	for case: Array in [[0, 900.0], [3, 1350.0], [5, 1650.0]]:
		_set_skill(tracker, &"tracking", case[0])
		assert_almost_eq(GameSession.recovery_lifetime_seconds(), case[1], 0.001, "skill %d" % case[0])


func test_apothecary_draught_cost_follows_the_alchemy_table_and_the_settle() -> void:
	var healing: Array[int] = [5, 5, 4, 4, 3, 3]
	var revival: Array[int] = [15, 14, 12, 11, 9, 8]
	for skill: int in 6:
		assert_eq(BulkOperations.supply_parts_cost("healing", skill, BALANCE), healing[skill], "healing %d" % skill)
		assert_eq(BulkOperations.supply_parts_cost("revival", skill, BALANCE), revival[skill], "revival %d" % skill)
	var alchemist: Hero = _keeper("Ivo", &"Apothecary", &"alchemy")
	for skill: int in [0, 3, 5]:
		_set_skill(alchemist, &"alchemy", skill)
		GameSession.parts[0] = 100
		var plan: Dictionary = GameSession.preview_bulk_supplies("revival", 2, 0)
		assert_eq(int(plan["cost_parts"][0]), 2 * revival[skill], "skill %d preview" % skill)
		assert_true(GameSession.commit_bulk_plan(plan), GameSession.last_action_error)
		assert_eq(GameSession.parts[0], 100 - 2 * revival[skill], "skill %d settle" % skill)


func test_an_away_keeper_gives_nothing_and_is_not_a_master() -> void:
	var smith: Hero = _keeper("Mira", &"Forge", &"smithing")
	_set_skill(smith, &"smithing", 5)
	assert_eq(GameSession.keeper_skill(&"Forge"), 5)
	assert_true(GameSession.keeper_is_master(&"Forge"))
	_send_away(smith)
	assert_eq(GameSession.keeper_skill(&"Forge"), 0)
	assert_false(GameSession.keeper_is_master(&"Forge"))
	var item := Item.new(&"ring", 0)
	assert_eq(GameSession.salvage_yield(item), 3, "no bonus while away")


func test_master_needs_the_passion_skill_5_and_home() -> void:
	var smith: Hero = _add_hero("Mira")
	smith.passions = [&"rites", &"drill"] as Array[StringName]
	assert_true(GameSession.station_hero(smith, &"Forge"), GameSession.last_action_error)
	_set_skill(smith, &"smithing", 5)
	assert_false(GameSession.keeper_is_master(&"Forge"), "skill 5 without the passion")
	smith.passions = [&"smithing", &"drill"] as Array[StringName]
	_set_skill(smith, &"smithing", 3)
	assert_false(GameSession.keeper_is_master(&"Forge"), "the passion at skill 3")
	_set_skill(smith, &"smithing", 5)
	assert_true(GameSession.keeper_is_master(&"Forge"))
	assert_false(GameSession.keeper_is_master(&"Sanctum"), "only its own building")
	_send_away(smith)
	assert_false(GameSession.keeper_is_master(&"Forge"), "away")


func test_a_skill_5_keeper_never_touches_summon_weights_the_enhance_cap_or_the_damage_chance() -> void:
	for index: int in 5:
		GameSession.building_levels[index] = 3
	var cache := LostCache.new("Lost", &"verdant_outskirts", 0, 0.0)
	var before: Array = [
		Summon.weights_for_circle_level(GameSession.building_levels[0], BALANCE.summon_weights),
		Item.compute_enhance_cap(GameSession.building_levels[1], true, BALANCE),
		LostCache.compute_damage_chance(cache, 100, 80.0, 120.0, GameSession.building_levels[4], BALANCE),
	]
	for building: StringName in Hero.PROFESSIONS.values():
		var keeper: Hero = _keeper(str(building), building, Hero.profession_for_building(building))
		_set_skill(keeper, Hero.profession_for_building(building), 5)
		assert_eq(GameSession.keeper_skill(building), 5)
	assert_eq(Hero.profession_for_building(&"SummoningCircle"), &"", "the Circle takes no keeper")
	assert_eq([
		Summon.weights_for_circle_level(GameSession.building_levels[0], BALANCE.summon_weights),
		GameSession.enhance_cap(BALANCE),
		LostCache.compute_damage_chance(cache, 100, 80.0, 120.0, GameSession.building_levels[4], BALANCE),
	], before, "skill adds nothing to the cap; a master only opens the band up to it (ig-wgj.12)")


func test_home_keepers_earn_xp_on_the_live_tick_only() -> void:
	var smith: Hero = _keeper("Mira", &"Forge", &"smithing")
	var priest: Hero = _add_hero("Sera")
	priest.passions = [&"drill", &"alchemy"] as Array[StringName]
	assert_true(GameSession.station_hero(priest, &"Sanctum"), GameSession.last_action_error)
	var away: Hero = _keeper("Tam", &"Reliquary", &"tracking")
	_send_away(away)
	GameSession.tick_expeditions(60.0)
	assert_almost_eq(float(smith.profession_xp.get(&"smithing", 0.0)), 240.0, 0.001, "x4 in a passion")
	assert_almost_eq(float(priest.profession_xp.get(&"rites", 0.0)), 60.0, 0.001, "x1 otherwise")
	assert_almost_eq(float(away.profession_xp.get(&"tracking", 0.0)), 0.0, 0.001, "away earns nothing")
	_come_home()  # The catch-up saves, and the fake order would not load (ig-6pm).
	GameSession._advance_orders_in_memory(3600.0)
	assert_almost_eq(float(smith.profession_xp.get(&"smithing", 0.0)), 240.0, 0.001, "the offline catch-up grants none")
	assert_almost_eq(float(priest.profession_xp.get(&"rites", 0.0)), 60.0, 0.001)


func test_keeper_xp_and_skill_survive_a_disk_round_trip() -> void:
	var smith: Hero = _keeper("Mira", &"Forge", &"smithing")
	smith.profession_xp[&"smithing"] = 125.0 * 60.0
	GameSession.tick_expeditions(15.0)
	var xp: float = float(smith.profession_xp[&"smithing"])
	_disk_round_trip()
	var loaded: Hero = GameSession.hero_by_id(smith.instance_id)
	assert_almost_eq(float(loaded.profession_xp[&"smithing"]), xp, 0.001)
	assert_eq(Hero.profession_skill(loaded, &"smithing", BALANCE), 3)
	assert_eq(GameSession.keeper_skill(&"Forge"), 3)
	assert_almost_eq(Hero.profession_xp_to_next(loaded, &"smithing", BALANCE), 200.0 * 60.0 - xp, 0.001)


func test_a_rescue_window_never_shrinks_when_the_tracker_leaves() -> void:
	var tracker: Hero = _keeper("Tam", &"Reliquary", &"tracking")
	_set_skill(tracker, &"tracking", 5)
	var id: String = _strand(_add_hero("Stranded"))
	assert_true(GameSession.start_rescue_window(id), GameSession.last_action_error)
	GameSession.tick_expeditions(100.0)
	var remaining: float = _incident_remaining(id)
	assert_almost_eq(remaining, TRACKER_LIFETIME - 100.0, 0.001)
	assert_gt(remaining, BASE_LIFETIME, "past the base lifetime")
	_send_away(tracker)
	assert_eq(GameSession.keeper_skill(&"Reliquary"), 0)
	assert_almost_eq(_incident_remaining(id), remaining, 0.001, "sent away: unchanged")
	GameSession.tick_expeditions(BASE_LIFETIME)
	assert_eq(GameSession.stranded_incidents.size(), 1, "alive past the base lifetime")
	assert_almost_eq(_incident_remaining(id), remaining - BASE_LIFETIME, 0.001)
	_come_home()
	assert_true(GameSession.unstation_hero(tracker), GameSession.last_action_error)
	_disk_round_trip()
	assert_eq(GameSession.stranded_incidents.size(), 1)
	assert_almost_eq(_incident_remaining(id), remaining - BASE_LIFETIME, 0.001, "the mark survives the disk")


# The Tracker may lead the rescue itself: the window starts at its lifetime before the order makes it busy.
func test_a_tracker_on_the_rescue_team_keeps_its_window() -> void:
	var tracker: Hero = _keeper("Tam", &"Reliquary", &"tracking")
	_set_skill(tracker, &"tracking", 5)
	var id: String = _strand(_add_hero("Stranded"))
	GameSession.team_presets.append({"id": "rescue", "name": "Rescue", "hero_ids": [tracker.instance_id], "zone_id": "verdant_outskirts"})
	assert_ne(GameSession.dispatch_rescue(id, "rescue", LOADOUT), "", GameSession.last_action_error)
	assert_true(GameSession.is_hero_busy(tracker))
	assert_eq(GameSession.keeper_skill(&"Reliquary"), 0)
	assert_almost_eq(float(GameSession.stranded_incidents[0]["lifetime_seconds"]), TRACKER_LIFETIME, 0.001)
	assert_almost_eq(_incident_remaining(id), TRACKER_LIFETIME, 0.001)
	_disk_round_trip()
	assert_almost_eq(_incident_remaining(id), TRACKER_LIFETIME, 0.001, "the mark survives the disk")


func test_a_cache_never_shrinks_and_its_hub_timer_only_jumps_up() -> void:
	var tracker: Hero = _keeper("Tam", &"Reliquary", &"tracking")
	_set_skill(tracker, &"tracking", 5)
	_send_away(tracker)
	var cache := LostCache.new("Lost", &"verdant_outskirts", 0, 0.0)
	GameSession.lost_caches.append(cache)
	GameSession.recovery_clock_paused = false
	var hub: Node3D = _instantiate_hub()
	(hub.get_node("%Town") as TownView).building_selected.emit(&"Reliquary")
	GameSession.tick_expeditions(10.0)
	var shown: Array[float] = [_hub_timer(hub, cache)]
	assert_almost_eq(shown[-1], BASE_LIFETIME - 10.0, 0.001)
	_come_home()
	GameSession.expeditions_changed.emit()
	shown.append(_hub_timer(hub, cache))
	assert_almost_eq(shown[-1], TRACKER_LIFETIME - 10.0, 0.001, "the Tracker comes home: up")
	GameSession.tick_expeditions(10.0)
	shown.append(_hub_timer(hub, cache))
	_send_away(tracker)
	GameSession.expeditions_changed.emit()
	shown.append(_hub_timer(hub, cache))
	assert_almost_eq(shown[-1], shown[-2], 0.001, "the Tracker sent away: unchanged, never down")
	GameSession.tick_expeditions(BASE_LIFETIME)
	assert_eq(GameSession.lost_caches.size(), 1, "alive past the base lifetime")
	for index: int in range(1, shown.size()):
		assert_true(shown[index] >= shown[index - 1] - 10.0 - 0.001, "only the clock moves it down: %s" % str(shown))
	_come_home()
	assert_true(GameSession.unstation_hero(tracker), GameSession.last_action_error)
	var remaining: float = GameSession.cache_seconds_remaining(GameSession.lost_caches[0], GameSession.recovery_clock_seconds)
	_disk_round_trip()
	assert_eq(GameSession.lost_caches.size(), 1)
	assert_almost_eq(GameSession.cache_seconds_remaining(GameSession.lost_caches[0], GameSession.recovery_clock_seconds), remaining, 0.001, "the mark survives the disk")


# Boundary #1: a save from before the mark has no lifetime_seconds; it loads and reads the live lifetime.
func test_a_save_without_lifetime_seconds_loads_with_the_live_lifetime() -> void:
	var tracker: Hero = _keeper("Tam", &"Reliquary", &"tracking")
	_set_skill(tracker, &"tracking", 5)
	var id: String = _strand(_add_hero("Stranded"))
	assert_true(GameSession.start_rescue_window(id), GameSession.last_action_error)
	GameSession.lost_caches.append(LostCache.new("Lost", &"verdant_outskirts", 0, 0.0))
	GameSession.recovery_clock_paused = false
	GameSession.tick_expeditions(30.0)
	assert_true(SaveService.save())
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveService.SAVE_PATH)) as Dictionary
	assert_true(((saved["stranded_incidents"] as Array)[0] as Dictionary).has("lifetime_seconds"), "written now")
	assert_true(((saved["lost_caches"] as Array)[0] as Dictionary).has("lifetime_seconds"), "written now")
	((saved["stranded_incidents"] as Array)[0] as Dictionary).erase("lifetime_seconds")
	((saved["lost_caches"] as Array)[0] as Dictionary).erase("lifetime_seconds")
	GameSession.from_dict({"roster": []})
	var file := FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(saved, "	"))
	file.close()
	assert_true(SaveService.load_game(), SaveService.load_block_reason)
	assert_eq(GameSession.lost_caches[0].lifetime_seconds, 0.0)
	assert_almost_eq(_incident_remaining(id), TRACKER_LIFETIME - 30.0, 0.001)
	assert_almost_eq(GameSession.cache_seconds_remaining(GameSession.lost_caches[0], GameSession.recovery_clock_seconds), TRACKER_LIFETIME - 30.0, 0.001)
	GameSession.tick_expeditions(1.0)
	assert_almost_eq(GameSession.lost_caches[0].lifetime_seconds, TRACKER_LIFETIME, 0.001, "the next live tick sets the mark")


func test_the_keeper_panel_shows_the_bonus_the_xp_to_next_and_master() -> void:
	var smith: Hero = _keeper("Mira", &"Forge", &"smithing")
	_set_skill(smith, &"smithing", 3)
	var hub: Node3D = _instantiate_hub()
	(hub.get_node("%Town") as TownView).building_selected.emit(&"Forge")
	var bonus: Label = hub.get_node("%KeeperBonus") as Label
	assert_string_contains(bonus.text, "Mira: salvage +15%")
	assert_string_contains(bonus.text, "80 XP min to Smithing 4")
	assert_false(bonus.text.contains("MASTER"))
	_set_skill(smith, &"smithing", 5)
	GameSession.roster_changed.emit()
	assert_string_contains(bonus.text, "salvage +25%")
	assert_string_contains(bonus.text, "max skill · MASTER")
	_send_away(smith)
	GameSession.expeditions_changed.emit()  # As a dispatch does; roster_changed would save the fake order (ig-6pm).
	assert_eq(bonus.text, "Away: no bonus and no XP until home")


func _keeper(hero_name: String, building: StringName, passion: StringName) -> Hero:
	var hero: Hero = _add_hero(hero_name)
	hero.passions = [passion, &"farming" if passion != &"farming" else &"mining"] as Array[StringName]
	assert_true(GameSession.station_hero(hero, building), GameSession.last_action_error)
	return hero


func _set_skill(hero: Hero, profession: StringName, skill: int) -> void:
	hero.profession_xp[profession] = SKILL_XP[skill]


func _add_hero(hero_name: String) -> Hero:
	var hero := Hero.new(hero_name, 7)
	hero.def_id = &"knight"
	hero.level = 80
	GameSession.add_hero(hero)
	return hero


## In memory only: a route order holding the hero makes it busy (is_hero_busy). Never saved: save() refuses it.
func _send_away(hero: Hero) -> void:
	GameSession.expedition_orders.append({
		"id": "away-" + hero.instance_id,
		"team_name": "Away",
		"hero_ids": [hero.instance_id],
		"zone_id": "verdant_outskirts",
		"initial_duration_seconds": 99999.0,
		"remaining_seconds": 99999.0,
		"runs_completed": 0,
		"total_runs": 1,
		"stop_requested": false,
	})


func _come_home() -> void:
	for index: int in range(GameSession.expedition_orders.size() - 1, -1, -1):
		if str(GameSession.expedition_orders[index]["id"]).begins_with("away-"):
			GameSession.expedition_orders.remove_at(index)


func _strand(hero: Hero) -> String:
	var zone: ZoneDefinition = load("res://zones/defs/verdant_outskirts.tres") as ZoneDefinition
	var stats: Dictionary[StringName, float] = Hero.compute_final_stats(hero, Hero.definition_for(hero.def_id), BALANCE, 0)
	var state: BattleState = BattleSimulation.create_run("source", [{
		"hero_id": hero.instance_id,
		"archetype": str(hero.def_id),
		"hp": stats[Hero.STAT_HP],
		"atk": stats[Hero.STAT_ATK],
		"defense": stats[Hero.STAT_DEF],
		"speed": stats[Hero.STAT_SPD],
		"crit_rate": stats[Hero.STAT_CRIT_RATE],
		"crit_damage": stats[Hero.STAT_CRIT_DMG],
		"squad_id": "source-squad",
	}], zone, [{"id": "source-squad", "name": "Source", "hero_ids": [hero.instance_id], "stance": "stay_together", "guard_target_id": ""}], {}, {}, 544)
	state.actors[0].life = BattleActor.LIFE_DOWNED
	state.actors[0].hp = 0.0
	# The real capture's checkpoint, so a save during the rescue validates.
	var snapshot: Dictionary = GameSession._incident_snapshot(state, [hero.instance_id] as Array[String])
	GameSession.stranded_incidents.append({"id": "incident-1", "source_order_id": "gone-source", "zone_id": "verdant_outskirts", "hero_ids": [hero.instance_id], "battle_snapshot": snapshot, "created_recovery_seconds": GameSession.rescue_clock_seconds, "paused": true, "expiry_pending": false, "active_rescue_order_id": ""})
	return "incident-1"


func _incident_remaining(id: String) -> float:
	for incident: Dictionary in GameSession.get_stranded_incidents():
		if incident["id"] == id:
			return float(incident["remaining_seconds"])
	fail_test("incident %s is gone" % id)
	return -1.0


## The hub's timer text for the cache, checked against the helper every read goes through.
func _hub_timer(hub: Node3D, cache: LostCache) -> float:
	var seconds: float = GameSession.cache_seconds_remaining(cache, GameSession.recovery_clock_seconds)
	var list: ItemList = hub.get_node("%LostCacheList") as ItemList
	assert_string_contains(list.get_item_text(0), "%s active remaining" % hub._format_duration(seconds))
	return seconds


func _disk_round_trip() -> void:
	assert_true(SaveService.save())
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(SaveService.SAVE_PATH)
	GameSession.from_dict({"roster": []})
	var file := FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	assert_true(SaveService.load_game(), SaveService.load_block_reason)


func _instantiate_hub() -> Node3D:
	var hub: Node3D = (load("res://hub/hub.tscn") as PackedScene).instantiate() as Node3D
	add_child_autofree(hub)
	return hub
