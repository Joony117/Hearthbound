extends GutTest

# ig-6m2.3.1: the Mine. Place it, staff it from a House, stone ticks live at the table rate
# (SYSTEMS.md § Stone and construction). Boundary #1: town_resources.stone is additive.

const BALANCE: BalanceTable = preload("res://balance.tres")
const MINE_HEX: Vector2i = Vector2i(0, 1)


func before_each() -> void:
	GameSession.set_process(false)
	SaveService.load_blocked = false
	SaveService.load_block_reason = ""
	GameSession.from_dict({"roster": []})
	GameSession._encounter_rng.seed = 7  # ig-m6o.2.2.4: two housed heroes can roll a meeting here; the same stream every run


func after_each() -> void:
	GameSession.set_process(true)


func test_the_first_mine_is_free_and_the_next_costs_the_table_price() -> void:
	GameSession.town_resources["wood"] = 100.0
	var plan: Dictionary = GameSession.preview_place_building(TownRules.MINE, MINE_HEX)
	assert_eq(int(plan["cost"]), 0, "no Mine yet")
	var mine: StringName = _place(TownRules.MINE, MINE_HEX)
	assert_eq(GameSession.town_resources["wood"], 100.0)
	assert_eq(TownRules.type_of(mine), TownRules.MINE)
	plan = GameSession.preview_place_building(TownRules.MINE, Vector2i(1, 1))
	assert_eq(int(plan["cost"]), BALANCE.mine_wood_cost, "one Mine standing")
	_place(TownRules.MINE, Vector2i(1, 1))
	assert_eq(GameSession.town_resources["wood"], 100.0 - BALANCE.mine_wood_cost, "the preview is what it spends")


func test_a_mine_job_needs_a_home_and_takes_two_workers() -> void:
	var heroes: Array[Hero] = [_add_hero("A"), _add_hero("B"), _add_hero("C")]
	var mine: StringName = _place(TownRules.MINE, MINE_HEX)
	assert_false(GameSession.station_hero(heroes[0], mine))
	assert_eq(GameSession.last_action_error, "A needs a house before working at the %s." % String(mine).capitalize())
	GameSession.town_resources["wood"] = 100.0
	for index: int in 3:
		assert_true(GameSession.assign_home(heroes[index], _place(TownRules.HOUSE, Vector2i(index, 2))))
	assert_true(GameSession.station_hero(heroes[0], mine))
	assert_true(GameSession.station_hero(heroes[1], mine))
	assert_false(GameSession.station_hero(heroes[2], mine))
	assert_eq(GameSession.last_action_error, "The %s is full." % String(mine).capitalize())
	assert_eq(GameSession.workers_at(mine).size(), BALANCE.mine_worker_slots)


func test_stone_ticks_live_for_a_worker_at_home_and_never_offline() -> void:
	var workers: Array[Hero] = _staffed_mine()
	var wood: float = GameSession.town_resources["wood"]
	GameSession.tick_expeditions(60.0)
	assert_almost_eq(float(GameSession.town_resources["stone"]), 2 * BALANCE.stone_per_worker_minute, 0.0001)
	assert_eq(GameSession.town_resources["wood"], wood, "a Mine makes no wood")
	assert_ne(GameSession.dispatch_expedition([workers[0].instance_id], "verdant_outskirts", 1, "Out"), "", GameSession.last_action_error)
	var stone: float = GameSession.town_resources["stone"]
	GameSession._advance_clocks_in_memory(60.0)
	assert_almost_eq(float(GameSession.town_resources["stone"]), stone + BALANCE.stone_per_worker_minute, 0.0001, "only the worker at home")
	stone = GameSession.town_resources["stone"]
	GameSession.saved_at_unix = Time.get_unix_time_from_system() - 36000.0
	GameSession.apply_offline_expedition_progress(Time.get_unix_time_from_system())
	GameSession._advance_orders_in_memory(360000.0)
	assert_eq(GameSession.town_resources["stone"], stone, "the catch-up makes nothing, however long")


# A town whose only workplace is a Mine still ticks and still gets its periodic save.
func test_a_town_with_only_a_mine_ticks_and_saves() -> void:
	_staffed_mine()
	assert_true(SaveService.save())
	GameSession.set("_periodic_save_accumulator", GameSession.PERIODIC_SAVE_SECONDS - 0.1)
	GameSession._process(0.25)
	GameSession._process(0.01)  # ig-7sn.10: the periodic save runs on the frame after its pulse.
	var stone: float = GameSession.town_resources["stone"]
	assert_gt(stone, 0.0)
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveService.SAVE_PATH)) as Dictionary
	assert_almost_eq(float((saved["town_resources"] as Dictionary)["stone"]), stone, 0.0001, "the periodic save wrote it")


# Boundary #1: through SaveService and the disk, with a partial unit of stone.
func test_stone_and_the_staffed_mine_survive_a_disk_round_trip() -> void:
	var workers: Array[Hero] = _staffed_mine()
	var mine: StringName = workers[0].station
	GameSession.tick_expeditions(45.0)
	var stone: float = GameSession.town_resources["stone"]
	assert_ne(stone, floorf(stone), "a partial unit is in play")
	assert_true(SaveService.save(), SaveService.last_write_error)
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(SaveService.SAVE_PATH)
	GameSession.from_dict({"roster": []})
	_write(bytes)
	assert_true(SaveService.load_game())
	assert_eq(GameSession.town_resources["stone"], stone)
	assert_eq(GameSession.town_building(mine)["type"], String(TownRules.MINE))
	for worker: Hero in workers:
		assert_eq(GameSession.hero_by_id(worker.instance_id).station, mine)
	assert_push_warning_count(0)
	assert_push_error_count(0)


func test_a_save_from_before_stone_loads_zero_and_negative_stone_loads_zero() -> void:
	GameSession.town_resources = {"wood": 12.0, "stone": 3.0}
	assert_true(SaveService.save())
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveService.SAVE_PATH)) as Dictionary
	(saved["town_resources"] as Dictionary).erase("stone")
	_write(JSON.stringify(saved, "\t").to_utf8_buffer())
	assert_true(SaveService.load_game())
	assert_eq(GameSession.town_resources, {"wood": 12.0, "stone": 0.0, "food": BALANCE.town_start_food}, "the wood stays, no start stock of stone")
	var state: Dictionary = GameSession.to_dict()
	state["town_resources"] = {"wood": 12.0, "stone": -5.0}
	GameSession.from_dict(state)
	assert_eq(GameSession.town_resources["stone"], 0.0)
	assert_push_warning_count(0)
	assert_push_error_count(0)


func test_a_bad_stone_value_or_bad_resources_load_zero_stone_and_the_tick_still_runs() -> void:
	var state: Dictionary = GameSession.to_dict()
	state["town_resources"] = {"wood": 12.0, "stone": "lots"}
	GameSession.from_dict(state)
	assert_push_error("Invalid town resources stone")
	assert_eq(GameSession.town_resources, {"wood": 12.0, "stone": 0.0, "food": BALANCE.town_start_food})
	state["town_resources"] = "broken"
	GameSession.from_dict(state)
	assert_push_error("Invalid town_resources")
	assert_eq(GameSession.town_resources, {"wood": 0.0, "stone": 0.0, "food": BALANCE.town_start_food})
	GameSession.town_resources["wood"] = 100.0
	_staffed_mine()
	GameSession.tick_expeditions(60.0)
	assert_almost_eq(float(GameSession.town_resources["stone"]), 2 * BALANCE.stone_per_worker_minute, 0.0001)


func test_the_placed_panel_says_stone_on_a_mine_and_wood_on_a_lumbermill() -> void:
	var workers: Array[Hero] = _staffed_mine()
	var mill: StringName = _place(TownRules.LUMBERMILL, Vector2i(1, 1))
	var hub: Node3D = (load("res://hub/hub.tscn") as PackedScene).instantiate() as Node3D
	add_child_autofree(hub)
	var town: TownView = hub.get_node("%Town") as TownView
	town.building_selected.emit(workers[0].station)
	assert_eq((hub.get_node("%PlacedInfo") as Label).text, "Workers 2/2: A (Mining 0), B (Mining 0)\nMakes 1.0 stone a minute")
	town.building_selected.emit(mill)
	assert_eq((hub.get_node("%PlacedInfo") as Label).text, "Workers 0/2: none\nMakes 0.0 wood a minute")


func _staffed_mine() -> Array[Hero]:
	var workers: Array[Hero] = [_add_hero("A"), _add_hero("B")]
	var mine: StringName = _place(TownRules.MINE, MINE_HEX)
	for index: int in workers.size():
		assert_true(GameSession.assign_home(workers[index], _place(TownRules.HOUSE, Vector2i(index, 2))), GameSession.last_action_error)
		assert_true(GameSession.station_hero(workers[index], mine), GameSession.last_action_error)
	return workers


## Placed and finished at once: construction (ig-6m2.3.2) is not what this file tests.
func _place(type: StringName, hex: Vector2i) -> StringName:
	var id := StringName(GameSession.preview_place_building(type, hex)["id"])
	assert_true(GameSession.place_building(type, hex), GameSession.last_action_error)
	GameSession.town_building(id).erase("build_remaining")
	return id


func _add_hero(hero_name: String) -> Hero:
	var hero := Hero.new(hero_name, 7)
	hero.def_id = &"knight"
	hero.level = 80
	# Passions are random per hero: none here is for a town job, so the panel text is the same on every run.
	hero.passions = [&"smithing", &"rites"] as Array[StringName]
	GameSession.add_hero(hero)
	return hero


func _write(bytes: PackedByteArray) -> void:
	var file := FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
