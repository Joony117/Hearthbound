extends GutTest

# ig-6m2.1: place a House and a Lumbermill on hexes, house a hero, put it to work, wood goes up
# (DECISIONS.md 2026-09-23, the town builder). ig-6m2.2: the seven halls are placed buildings too,
# unique, and any building moves.

const BALANCE: BalanceTable = preload("res://balance.tres")
const LOADOUT: Dictionary = {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0}
const FREE_HEX: Vector2i = Vector2i(0, 2)
const NEXT_HEX: Vector2i = Vector2i(1, 2)


func before_each() -> void:
	GameSession.set_process(false)
	SaveService.load_blocked = false
	SaveService.load_block_reason = ""
	GameSession.from_dict({"roster": []})


func after_each() -> void:
	GameSession.set_process(true)


# The tile is measured, not assumed: HEX_SIZE must match hex_grass.gltf at the staging scale.
func test_the_hex_size_matches_the_staged_tile_and_the_math_round_trips() -> void:
	var tile: Node = (load("res://hub/town/models/hexagon/hex_grass.gltf") as PackedScene).instantiate()
	var bounds: AABB = (tile.find_children("*", "MeshInstance3D")[0] as MeshInstance3D).get_aabb()
	tile.free()
	assert_almost_eq(bounds.size.x * TownRules.MODEL_SCALE, TownRules.HEX_SIZE * sqrt(3.0), 0.01, "across the flats")
	assert_almost_eq(bounds.size.z * TownRules.MODEL_SCALE, TownRules.HEX_SIZE * 2.0, 0.01, "point to point")
	assert_almost_eq(bounds.end.y, 0.0, 0.001, "the top face is the ground")
	var hexes: Array[Vector2i] = TownRules.map_hexes(BALANCE)
	assert_eq(hexes.size(), 217, "radius 8")
	for hex: Vector2i in hexes:
		assert_eq(TownRules.world_to_hex(TownRules.hex_to_world(hex)), hex)
		assert_eq(TownRules.world_to_hex(TownRules.hex_to_world(hex) + Vector3(1.4, 0.0, -1.4)), hex, "a click off the centre")
	assert_almost_eq(TownRules.hex_to_world(Vector2i(1, 0)).distance_to(TownRules.hex_to_world(Vector2i.ZERO)), 6.0, 0.01)


func test_a_new_profile_has_the_halls_on_their_hexes_and_the_view_spawns_them() -> void:
	assert_eq(GameSession.town_buildings, TownRules.default_halls())
	var town: TownView = (load("res://hub/town/town.tscn") as PackedScene).instantiate() as TownView
	assert_false(town.get_children().any(func(node: Node) -> bool: return node.has_node("Pick")), "town.tscn authors no building")
	add_child_autofree(town)
	town.show_buildings(GameSession.town_buildings)
	for hall: StringName in TownRules.HALL_HEXES:
		var node: Node3D = town.get_node(NodePath(hall)) as Node3D
		assert_eq(node.position, TownRules.hex_to_world(TownRules.HALL_HEXES[hall]), str(hall))
		assert_ne(TownRules.hex_refusal(TownRules.HALL_HEXES[hall], GameSession.town_buildings, BALANCE), "", str(hall))
	for type: StringName in TownView.SCENES:
		var building: Node = TownView.SCENES[type].instantiate()
		for part: String in ["Model", "Label", "Pick", "WorkSpot"]:
			assert_true(building.has_node(part), "%s has a %s" % [type, part])
		assert_eq((building.get_node("Pick") as StaticBody3D).collision_layer, TownView.PICK_LAYER, str(type))
		building.free()
	assert_eq(TownRules.HALL_HEXES.size(), HubUiBuilder.BUILDINGS.size(), "every hall has a hex")


func test_a_second_hall_is_refused() -> void:
	var before: Dictionary = GameSession.to_dict()
	for hall: StringName in TownRules.HALL_HEXES:
		var reason: String = "The town has its %s already." % String(hall).capitalize()
		assert_eq(GameSession.preview_place_building(hall, FREE_HEX)["reason"], reason)
		assert_false(GameSession.place_building(hall, FREE_HEX))
		assert_eq(GameSession.last_action_error, reason)
	assert_eq(GameSession.to_dict(), before)


func test_every_move_refusal_changes_nothing_and_says_why() -> void:
	_place(TownRules.HOUSE, FREE_HEX)
	var before: Dictionary = GameSession.to_dict()
	for case: Array in [
		[&"Forge", TownRules.HALL_HEXES[&"Sanctum"], "The Sanctum stands there."],
		[&"Forge", TownRules.HALL_HEXES[&"Forge"], "The Forge stands there."],
		[&"Forge", FREE_HEX, "House 1 stands there."],
		[&"House_1", TownRules.HALL_HEXES[&"TownGate"], "The Town Gate stands there."],
		[&"Forge", Vector2i(9, 0), "That hex is off the map."],
		[&"Castle", NEXT_HEX, "There is no Castle to move."],
	]:
		assert_false(GameSession.move_building(case[0], case[1]), str(case))
		assert_eq(GameSession.last_action_error, case[2])
		assert_eq(GameSession.to_dict(), before, str(case))
	SaveService.load_blocked = true
	SaveService.load_block_reason = "blocked"
	assert_false(GameSession.move_building(&"Forge", NEXT_HEX))
	assert_eq(GameSession.last_action_error, "blocked")
	assert_eq(GameSession.to_dict(), before)


func test_a_failed_save_takes_the_move_back() -> void:
	assert_true(SaveService.save())
	var before: Dictionary = GameSession.to_dict().duplicate(true)
	assert_eq(DirAccess.make_dir_absolute(SaveService.TMP_PATH), OK)
	assert_false(GameSession.move_building(&"Forge", FREE_HEX))
	assert_push_error("Save failed")
	assert_ne(GameSession.last_action_error, "")
	assert_eq(DirAccess.remove_absolute(SaveService.TMP_PATH), OK)
	assert_eq(GameSession.town_building(&"Forge"), {"id": "Forge", "type": "Forge", "q": -1, "r": 0})
	assert_eq(GameSession.to_dict()["town_buildings"], before["town_buildings"])


# Boundary #1: move the Forge and a lived-in House, then save and reload through the disk.
func test_a_moved_building_keeps_its_id_level_and_people_through_a_disk_round_trip() -> void:
	var mira: Hero = _add_hero("Mira")
	var bo: Hero = _add_hero("Bo")
	assert_true(GameSession.station_hero(mira, &"Forge"), GameSession.last_action_error)
	var house: StringName = _place(TownRules.HOUSE, FREE_HEX)
	assert_true(GameSession.assign_home(bo, house), GameSession.last_action_error)
	GameSession.building_levels[1] = 3
	assert_true(GameSession.move_building(&"Forge", Vector2i(3, 3)), GameSession.last_action_error)
	assert_true(GameSession.move_building(house, Vector2i(-1, 0)), "onto the Forge's old hex")
	assert_eq(GameSession.town_building(&"Forge"), {"id": "Forge", "type": "Forge", "q": 3, "r": 3})
	assert_eq(GameSession.keeper_for(&"Forge"), mira)
	assert_eq(GameSession.residents_of(house), [bo] as Array[Hero])
	assert_true(SaveService.save())
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(SaveService.SAVE_PATH)
	GameSession.from_dict({"roster": []})
	var file := FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	assert_true(SaveService.load_game())
	assert_eq(GameSession.town_building(&"Forge"), {"id": "Forge", "type": "Forge", "q": 3, "r": 3})
	assert_eq(GameSession.town_building(house), {"id": "House_1", "type": "House", "q": -1, "r": 0})
	assert_eq(GameSession.building_levels[1], 3)
	assert_eq(GameSession.keeper_for(&"Forge").instance_id, mira.instance_id)
	assert_eq(GameSession.hero_by_id(bo.instance_id).home, house)
	assert_eq(GameSession.town_buildings.size(), 8)
	assert_push_warning_count(0)


# Boundary #1: an ig-6m2.1 save names no hall; it loads with the default layout and nothing else moves.
func test_a_save_from_before_the_halls_gets_the_default_layout_and_keeps_its_town() -> void:
	var workers: Array[Hero] = _staffed_lumbermill()
	var keeper: Hero = _add_hero("Keeper")
	assert_true(GameSession.station_hero(keeper, &"Sanctum"))
	assert_true(SaveService.save())
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveService.SAVE_PATH)) as Dictionary
	var placed: Array = (saved["town_buildings"] as Array).filter(func(building: Dictionary) -> bool: return not TownRules.is_hall(building["id"]))
	saved["town_buildings"] = placed
	GameSession.from_dict({"roster": []})
	var file := FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(saved, "	"))
	file.close()
	assert_true(SaveService.load_game())
	assert_eq(GameSession.town_buildings.slice(0, 7), TownRules.default_halls())
	assert_eq(_placed(), [
		{"id": "Lumbermill_1", "type": "Lumbermill", "q": 0, "r": 1},
		{"id": "House_2", "type": "House", "q": 0, "r": 2},
		{"id": "House_3", "type": "House", "q": 1, "r": 2},
	] as Array[Dictionary])
	for worker: Hero in workers:
		var reloaded: Hero = GameSession.hero_by_id(worker.instance_id)
		assert_eq([reloaded.home, reloaded.station], [worker.home, &"Lumbermill_1"])
	assert_eq(GameSession.keeper_for(&"Sanctum").instance_id, keeper.instance_id)
	assert_eq(GameSession.town_next_id, 4)
	assert_push_warning_count(0)


func test_a_hall_the_save_names_but_drops_stands_on_the_nearest_free_hex() -> void:
	var state: Dictionary = GameSession.to_dict()
	var buildings: Array = state["town_buildings"]
	buildings.push_front({"id": "House_1", "type": "House", "q": -1, "r": 0})
	state["town_buildings"] = buildings
	GameSession.from_dict(state)
	assert_push_warning("Invalid town building")
	assert_push_warning("The Forge was dropped; it stands at")
	assert_eq(GameSession.town_building(&"House_1")["q"], -1, "the House keeps the hex it was read on")
	var forge: Dictionary = GameSession.town_building(&"Forge")
	assert_eq(TownRules.ring_distance(Vector2i(forge["q"], forge["r"]) - TownRules.HALL_HEXES[&"Forge"]), 1, "next door")


func test_placing_spends_the_cost_exactly_and_takes_the_next_id() -> void:
	assert_eq(GameSession.town_resources["wood"], BALANCE.town_start_wood)
	assert_true(GameSession.place_building(TownRules.HOUSE, FREE_HEX), GameSession.last_action_error)
	assert_true(GameSession.place_building(TownRules.LUMBERMILL, NEXT_HEX), GameSession.last_action_error)
	assert_eq(GameSession.town_resources["wood"], BALANCE.town_start_wood, "the first House and the first Lumbermill are free")
	assert_true(GameSession.place_building(TownRules.HOUSE, Vector2i(2, 2)), GameSession.last_action_error)
	assert_eq(GameSession.town_resources["wood"], BALANCE.town_start_wood - BALANCE.house_wood_cost)
	assert_eq(_placed(), [
		{"id": "House_1", "type": "House", "q": 0, "r": 2},
		{"id": "Lumbermill_2", "type": "Lumbermill", "q": 1, "r": 2},
		{"id": "House_3", "type": "House", "q": 2, "r": 2},
	] as Array[Dictionary])
	assert_eq(GameSession.town_next_id, 4)


func test_every_refusal_spends_nothing_and_says_why() -> void:
	assert_true(GameSession.place_building(TownRules.HOUSE, FREE_HEX))
	assert_true(GameSession.place_building(TownRules.LUMBERMILL, Vector2i(0, 3)), "so the next one costs")
	var cases: Array = [
		[TownRules.HOUSE, FREE_HEX, "House 1 stands there."],
		[TownRules.HOUSE, Vector2i(9, 0), "That hex is off the map."],
		[TownRules.LUMBERMILL, TownRules.HALL_HEXES[&"Forge"], "The Forge stands there."],
		[&"Castle", NEXT_HEX, "Nothing called 'Castle' can be built."],
	]
	GameSession.town_resources["wood"] = 19.5
	cases.append([TownRules.LUMBERMILL, NEXT_HEX, "A Lumbermill costs 20 wood; you have 19."])
	var before: Dictionary = GameSession.to_dict()
	for case: Array in cases:
		assert_false(GameSession.place_building(case[0], case[1]), str(case))
		assert_eq(GameSession.last_action_error, case[2])
		assert_eq(GameSession.to_dict(), before, "nothing spent for %s" % str(case))


## Five Houses spend the start wood (the first is free); without the free first Lumbermill the town could never make wood again.
func test_the_first_lumbermill_is_free_so_houses_first_cannot_lock_the_town() -> void:
	for q: int in 5:
		assert_true(GameSession.place_building(TownRules.HOUSE, Vector2i(q, 2)), GameSession.last_action_error)
	assert_eq(GameSession.town_resources["wood"], 0.0)
	assert_eq(GameSession.preview_place_building(TownRules.LUMBERMILL, Vector2i(0, 3))["cost"], 0)
	assert_true(GameSession.place_building(TownRules.LUMBERMILL, Vector2i(0, 3)), GameSession.last_action_error)
	var second: Dictionary = GameSession.preview_place_building(TownRules.LUMBERMILL, Vector2i(1, 3))
	assert_eq(second["cost"], BALANCE.lumbermill_wood_cost)
	assert_false(GameSession.place_building(TownRules.LUMBERMILL, Vector2i(1, 3)))
	assert_eq(GameSession.last_action_error, "A Lumbermill costs 20 wood; you have 0.")


## The free Lumbermill and two more spend the start wood; without the free first House nobody could
## work them, and the town could never make wood again (ig-6m2.10).
func test_the_first_house_is_free_so_lumbermills_first_cannot_lock_the_town() -> void:
	for q: int in 3:
		assert_true(GameSession.place_building(TownRules.LUMBERMILL, Vector2i(q, 3)), GameSession.last_action_error)
	assert_eq(GameSession.town_resources["wood"], 0.0)
	assert_eq(GameSession.preview_place_building(TownRules.HOUSE, FREE_HEX)["cost"], 0)
	assert_true(GameSession.place_building(TownRules.HOUSE, FREE_HEX), GameSession.last_action_error)
	assert_eq(GameSession.preview_place_building(TownRules.HOUSE, NEXT_HEX)["cost"], BALANCE.house_wood_cost)
	assert_false(GameSession.place_building(TownRules.HOUSE, NEXT_HEX))
	assert_eq(GameSession.last_action_error, "A House costs 10 wood; you have 0.")
	var mira: Hero = _add_hero("Mira")
	assert_true(GameSession.assign_home(mira, &"House_4"), GameSession.last_action_error)
	assert_true(GameSession.station_hero(mira, &"Lumbermill_1"), GameSession.last_action_error)
	GameSession._advance_clocks_in_memory(60.0)
	assert_almost_eq(float(GameSession.town_resources["wood"]), BALANCE.wood_per_worker_minute, 0.0001, "wood comes in again")


func test_the_preview_equals_the_result() -> void:
	var plan: Dictionary = GameSession.preview_place_building(TownRules.LUMBERMILL, NEXT_HEX)
	var wood: float = GameSession.town_resources["wood"]
	assert_true(bool(plan["valid"]))
	assert_true(GameSession.place_building(TownRules.LUMBERMILL, NEXT_HEX))
	assert_eq(GameSession.town_buildings.back()["id"], plan["id"])
	assert_eq(wood - float(GameSession.town_resources["wood"]), float(plan["cost"]))
	var refused: Dictionary = GameSession.preview_place_building(TownRules.HOUSE, NEXT_HEX)
	assert_false(bool(refused["valid"]))
	assert_false(GameSession.place_building(TownRules.HOUSE, NEXT_HEX))
	assert_eq(GameSession.last_action_error, refused["reason"])
	SaveService.load_blocked = true
	SaveService.load_block_reason = "blocked"
	assert_eq(GameSession.preview_place_building(TownRules.HOUSE, FREE_HEX)["reason"], "blocked")
	assert_false(GameSession.place_building(TownRules.HOUSE, FREE_HEX))
	assert_eq(_placed().size(), 1)


func test_a_failed_save_takes_the_building_back() -> void:
	assert_true(GameSession.place_building(TownRules.HOUSE, FREE_HEX))
	assert_true(SaveService.save())
	var before: Dictionary = GameSession.to_dict().duplicate(true)
	assert_eq(DirAccess.make_dir_absolute(SaveService.TMP_PATH), OK)
	assert_false(GameSession.place_building(TownRules.LUMBERMILL, NEXT_HEX))
	assert_eq(_placed().size(), 1, "the Lumbermill is gone again")
	assert_push_error("Save failed")
	assert_ne(GameSession.last_action_error, "")
	assert_eq(DirAccess.remove_absolute(SaveService.TMP_PATH), OK)
	for key: String in ["town_buildings", "town_resources", "town_next_id"]:
		assert_eq(GameSession.to_dict()[key], before[key], key)


func test_one_hero_per_house() -> void:
	var mira: Hero = _add_hero("Mira")
	var bo: Hero = _add_hero("Bo")
	var first: StringName = _place(TownRules.HOUSE, FREE_HEX)
	var second: StringName = _place(TownRules.HOUSE, NEXT_HEX)
	assert_true(GameSession.assign_home(mira, first))
	assert_false(GameSession.assign_home(bo, first))
	assert_eq(GameSession.last_action_error, "House 1 is full.")
	assert_true(GameSession.assign_home(mira, second), "moving out frees the first house")
	assert_true(GameSession.assign_home(bo, first))
	assert_false(GameSession.assign_home(bo, &"Lumbermill_9"))
	assert_false(GameSession.assign_home(bo, &"Forge"))
	assert_eq(GameSession.residents_of(first), [bo] as Array[Hero])


func test_a_lumbermill_job_needs_a_home_and_takes_two_workers() -> void:
	var heroes: Array[Hero] = [_add_hero("A"), _add_hero("B"), _add_hero("C")]
	var mill: StringName = _place(TownRules.LUMBERMILL, Vector2i(0, 1))
	assert_false(GameSession.station_hero(heroes[0], mill))
	assert_eq(GameSession.last_action_error, "A needs a house before working at the Lumbermill 1.")
	GameSession.town_resources["wood"] = 100.0
	for index: int in 3:
		assert_true(GameSession.assign_home(heroes[index], _place(TownRules.HOUSE, Vector2i(index, 2))))
	assert_true(GameSession.station_hero(heroes[0], mill))
	assert_true(GameSession.station_hero(heroes[1], mill))
	assert_false(GameSession.station_hero(heroes[2], mill))
	assert_eq(GameSession.last_action_error, "The Lumbermill 1 is full.")
	assert_eq(GameSession.workers_at(mill).size(), 2)
	assert_true(GameSession.clear_home(heroes[0]))
	assert_eq(heroes[0].station, Hero.NO_STATION, "a worker without a house loses the job")
	assert_true(GameSession.station_hero(heroes[2], mill), "which frees the slot")


func test_wood_ticks_live_at_the_table_rate_a_busy_worker_adds_nothing_and_offline_adds_nothing() -> void:
	var workers: Array[Hero] = _staffed_lumbermill()
	var wood: float = GameSession.town_resources["wood"]
	GameSession.tick_expeditions(45.0)
	assert_almost_eq(float(GameSession.town_resources["wood"]), wood + 2 * BALANCE.wood_per_worker_minute * 0.75, 0.0001)
	assert_ne(GameSession.dispatch_expedition([workers[0].instance_id], "verdant_outskirts", 1, "Out"), "", GameSession.last_action_error)
	wood = GameSession.town_resources["wood"]
	GameSession._advance_clocks_in_memory(60.0)
	assert_almost_eq(float(GameSession.town_resources["wood"]), wood + BALANCE.wood_per_worker_minute, 0.0001, "only the worker at home")
	wood = GameSession.town_resources["wood"]
	GameSession.saved_at_unix = Time.get_unix_time_from_system() - 36000.0
	GameSession.apply_offline_expedition_progress(Time.get_unix_time_from_system())
	GameSession._advance_orders_in_memory(360000.0)
	assert_eq(GameSession.town_resources["wood"], wood, "the catch-up makes nothing, however long")


func test_a_worker_cannot_be_sacrificed_single_or_bulk_but_can_still_be_dispatched() -> void:
	var worker: Hero = _staffed_lumbermill()[0]
	var target: Hero = _add_hero("Target")
	assert_true(GameSession.is_hero_protected(worker))
	assert_false(GameSession.is_hero_busy(worker))
	assert_false(GameSession.sacrifice_hero(worker, target, BALANCE))
	var plan: Dictionary = GameSession.preview_bulk_sacrifice([worker.instance_id], target.instance_id, 0)
	assert_true((plan["entries"] as Array).is_empty())
	assert_eq((plan["excluded"] as Array)[0]["reason"], "Works at the Lumbermill 1")
	assert_ne(GameSession.dispatch_expedition([worker.instance_id], "verdant_outskirts", 1, "Out"), "", GameSession.last_action_error)
	assert_eq(worker.station, &"Lumbermill_1", "it keeps the job while away")


func test_a_dead_worker_frees_its_house_and_its_slot() -> void:
	var worker: Hero = _staffed_lumbermill()[0]
	var house: StringName = worker.home
	GameSession.kill_hero(worker, &"", BALANCE)
	assert_true(GameSession.residents_of(house).is_empty())
	assert_eq(GameSession.workers_at(&"Lumbermill_1").size(), 1)
	var next: Hero = _add_hero("Next")
	assert_true(GameSession.assign_home(next, house))
	assert_true(GameSession.station_hero(next, &"Lumbermill_1"))


func test_load_cleanup_clears_what_no_longer_fits() -> void:
	var state: Dictionary = GameSession.to_dict()
	state["town_buildings"] = [
		{"id": "Lumbermill_1", "type": "Lumbermill", "q": 0, "r": 1},
		{"id": "House_2", "type": "House", "q": 0, "r": 2},
		{"id": "House_3", "type": "House", "q": 1, "r": 2},
		{"id": "House_4", "type": "House", "q": 2, "r": 2},
	]
	var rows: Array = [
		["A", "House_2", "Lumbermill_1"],
		["B", "House_3", "Lumbermill_1"],
		["C", "House_4", "Lumbermill_1"],  # over-full workplace
		["D", "House_2", ""],  # over-full house
		["E", "House_9", ""],  # missing house
		["F", "", "Lumbermill_7"],  # missing workplace
	]
	var roster: Array = []
	for row: Array in rows:
		var entry: Dictionary = Hero.new(row[0], 0).to_dict()
		entry["home"] = row[1]
		entry["station"] = row[2]
		roster.append(entry)
	state["roster"] = roster
	GameSession.from_dict(state)
	assert_push_warning("The Lumbermill 1 is full; C's job was cleared.")
	assert_push_warning("House 2 is full; D's home was cleared.")
	assert_push_warning("E's house, House 9, is gone; its home was cleared.")
	assert_push_warning("F's workplace, the Lumbermill 7, is gone; its job was cleared.")
	var got: Array = []
	for hero: Hero in GameSession.roster:
		got.append([hero.hero_name, str(hero.home), str(hero.station)])
	assert_eq(got, [
		["A", "House_2", "Lumbermill_1"],
		["B", "House_3", "Lumbermill_1"],
		["C", "House_4", ""],
		["D", "", ""],
		["E", "", ""],
		["F", "", ""],
	])


func test_bad_buildings_are_dropped_and_ids_are_never_reused() -> void:
	var state: Dictionary = GameSession.to_dict()
	state["town_buildings"] = [
		{"id": "House_5", "type": "House", "q": 0.0, "r": 2.0},
		{"id": "House_6", "type": "House", "q": 0, "r": 2},  # same hex
		{"id": "House_5", "type": "House", "q": 1, "r": 2},  # same id
		{"id": "House_7", "type": "House", "q": -1, "r": 0},  # the Forge's hex
		{"id": "House_8", "type": "House", "q": 20, "r": 0},  # off the map
		{"id": "House_9", "type": "Lumbermill", "q": 3, "r": 2},  # id and type disagree
		{"id": "Castle_10", "type": "Castle", "q": 4, "r": 2},
		{"id": "House_-1", "type": "House", "q": 5, "r": 2},
		{"id": "House_0", "type": "House", "q": 6, "r": 2},
		{"id": "House_07", "type": "House", "q": 5, "r": 1},
		"junk",
	]
	state["town_next_id"] = 2
	GameSession.from_dict(state)
	assert_push_warning_count(10)
	assert_eq(_placed(), [{"id": "House_5", "type": "House", "q": 0, "r": 2}] as Array[Dictionary])
	assert_eq(GameSession.town_buildings.slice(0, 7), TownRules.default_halls(), "a save that names no hall")
	assert_eq(GameSession.town_next_id, 6, "past every id still standing")


func test_a_save_from_before_the_town_gets_the_start_wood_once() -> void:
	var state: Dictionary = GameSession.to_dict()
	for key: String in ["town_buildings", "town_resources", "town_next_id"]:
		state.erase(key)
	GameSession.from_dict(state)
	assert_eq(GameSession.town_resources, {"wood": BALANCE.town_start_wood, "stone": 0.0})
	assert_eq(GameSession.town_buildings, TownRules.default_halls())
	assert_eq(GameSession.town_next_id, 1)
	GameSession.town_resources["wood"] = 3.0
	GameSession.from_dict(GameSession.to_dict())
	assert_eq(GameSession.town_resources["wood"], 3.0, "only when the key is missing")
	assert_push_warning_count(0)
	assert_push_error_count(0)


# Boundary #1: through SaveService and the disk, with the partial unit of wood.
func test_the_town_survives_a_disk_round_trip() -> void:
	var workers: Array[Hero] = _staffed_lumbermill()
	GameSession.tick_expeditions(45.0)
	var wood: float = GameSession.town_resources["wood"]
	assert_ne(wood, floorf(wood), "a partial unit is in play")
	assert_true(SaveService.save())
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(SaveService.SAVE_PATH)
	GameSession.from_dict({"roster": []})
	var file := FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	assert_true(SaveService.load_game())
	assert_eq(GameSession.town_resources["wood"], wood)
	assert_eq(GameSession.town_next_id, 4)
	assert_eq(_placed().size(), 3)
	for worker: Hero in workers:
		var reloaded: Hero = GameSession.hero_by_id(worker.instance_id)
		assert_eq(reloaded.home, worker.home)
		assert_eq(reloaded.station, &"Lumbermill_1")
	assert_push_warning_count(0)


func test_the_hub_builds_on_a_clicked_hex_and_staffs_the_building() -> void:
	var mira: Hero = _add_hero("Mira")
	var hub: Node3D = _instantiate_hub()
	var town: TownView = hub.get_node("%Town") as TownView
	var wood_label: Label = hub.get_node("%Wood") as Label
	assert_eq(wood_label.text, "Wood: 40   Stone: 0")
	var menu: PopupMenu = (hub.get_node("%Build") as MenuButton).get_popup()
	assert_eq([menu.get_item_text(0), menu.get_item_text(1), menu.get_item_text(2)], ["House · 0 wood", "Lumbermill · 0 wood", "Mine · 0 wood"])
	menu.index_pressed.emit(0)
	assert_eq(town.placing, TownRules.HOUSE)
	town.hex_selected.emit(TownRules.HALL_HEXES[&"Forge"])
	assert_eq((hub.get_node("%Status") as Label).text, "The Forge stands there. Esc cancels.")
	town.hex_selected.emit(FREE_HEX)
	assert_eq(town.placing, &"", "placing ends after a build")
	assert_eq(wood_label.text, "Wood: 40   Stone: 0", "the first House is free")
	assert_eq(menu.get_item_text(0), "House · 10 wood", "the next one is not")
	var placed: Node3D = town.get_node("House_1") as Node3D
	assert_eq(placed.position, TownRules.hex_to_world(FREE_HEX))
	var camera: Camera3D = hub.get_viewport().get_camera_3d()
	assert_eq(town.building_at(camera.unproject_position(placed.global_position + Vector3(0.0, 1.0, 0.0))), &"House_1", "it is clickable")
	town.building_selected.emit(&"House_1")
	assert_true((hub.get_node("%PlacedBuildingPanel") as Control).visible)
	(hub.get_node("%PlacedAssign") as Button).pressed.emit()
	var picker: PopupMenu = hub.get_node("%PlacedPicker") as PopupMenu
	picker.index_pressed.emit(0)
	picker.hide()
	assert_eq(mira.home, &"House_1")
	assert_eq((hub.get_node("%PlacedInfo") as Label).text, "Resident 1/1: Mira")
	assert_string_contains(hub.call("_hero_detail_text", mira) as String, "Home: House 1")
	menu.index_pressed.emit(1)
	town.hex_selected.emit(NEXT_HEX)
	assert_eq(menu.get_item_text(1), "Lumbermill · 20 wood", "the menu shows the second one's price")


## The same flow through pushed mouse clicks, so TownView's input handler and the GUI's click
## filtering are in the path, not just the signals.
func test_real_clicks_place_refuse_and_open_a_building() -> void:
	var hub: Node3D = _instantiate_hub()
	var town: TownView = hub.get_node("%Town") as TownView
	var status: Label = hub.get_node("%Status") as Label
	(hub.get_node("%Build") as MenuButton).get_popup().index_pressed.emit(0)
	var hall: Vector2 = _point_over(hub, func(hex: Vector2i) -> bool: return hex == TownRules.HALL_HEXES[&"TrainingHall"])
	assert_ne(hall, Vector2(-1, -1), "a reachable point over the Training Hall's hex")
	_click(hub, hall)
	assert_eq(status.text, "The Training Hall stands there. Esc cancels.")
	assert_true(_placed().is_empty())
	var free: Vector2 = _point_over(hub, func(hex: Vector2i) -> bool: return TownRules.hex_refusal(hex, GameSession.town_buildings, BALANCE) == "")
	assert_ne(free, Vector2(-1, -1), "a reachable point over a free hex")
	var hex: Vector2i = TownRules.world_to_hex(town.ground_point(free) as Vector3)
	_click(hub, free)
	assert_eq(_placed(), [{"id": "House_1", "type": "House", "q": hex.x, "r": hex.y}] as Array[Dictionary], status.text)
	assert_eq(town.placing, &"")
	var size: Vector2 = hub.get_viewport().get_visible_rect().size
	var on_house := Vector2(-1, -1)
	for y: int in range(0, int(size.y), 8):
		for x: int in range(0, int(size.x), 8):
			if on_house == Vector2(-1, -1) and town.building_at(Vector2(x, y)) == &"House_1" and _reachable(hub, Vector2(x, y)):
				on_house = Vector2(x, y)
	assert_ne(on_house, Vector2(-1, -1), "a reachable point over House 1")
	_click(hub, on_house)
	assert_true((hub.get_node("%PlacedBuildingPanel") as Control).visible, "a click on a placed building opens its panel")
	assert_eq((hub.get_node("%PlacedTitle") as Label).text, "HOUSE 1")


## A hand-edited save: a malformed Forge on a map every other hex fills. The Forge still stands,
## and its keeper keeps it.
func test_a_dropped_hall_on_a_full_map_takes_the_last_placed_buildings_hex() -> void:
	var mira: Hero = _add_hero("Mira")
	assert_true(GameSession.station_hero(mira, &"Forge"))
	var state: Dictionary = GameSession.to_dict()
	var buildings: Array = [{"id": "Forge", "type": "House", "q": 5, "r": 0}]
	for hall: Dictionary in TownRules.default_halls():
		if hall["id"] != "Forge":
			buildings.append(hall)
	var number: int = 0
	var last := Vector2i.ZERO
	for hex: Vector2i in TownRules.map_hexes(BALANCE):
		if hex == TownRules.HALL_HEXES[&"Forge"] or not TownRules.HALL_HEXES.values().has(hex):
			number += 1
			last = hex
			buildings.append({"id": TownRules.new_id(TownRules.HOUSE, number), "type": "House", "q": hex.x, "r": hex.y})
	state["town_buildings"] = buildings
	GameSession.from_dict(state)
	assert_push_warning("Invalid town building")
	assert_push_warning("The map is full; House %d was dropped to make room for the Forge." % number)
	assert_eq(GameSession.town_building(&"Forge"), {"id": "Forge", "type": "Forge", "q": last.x, "r": last.y})
	assert_eq(GameSession.town_buildings.size(), TownRules.map_hexes(BALANCE).size())
	assert_eq(GameSession.keeper_for(&"Forge").instance_id, mira.instance_id)


## The hub's Move flow: open, Move, a refused hex, a free hex. The node moves with its id, still
## opens the same panels by click and by key, and Esc stops a move.
func test_the_hub_moves_an_open_building_and_it_still_opens_by_click_and_key() -> void:
	var mira: Hero = _add_hero("Mira")
	assert_true(GameSession.station_hero(mira, &"Forge"))
	var hub: Node3D = _instantiate_hub()
	var town: TownView = hub.get_node("%Town") as TownView
	var status: Label = hub.get_node("%Status") as Label
	var move: Button = hub.get_node("%MoveBuilding") as Button
	assert_false(move.visible, "nothing to move in the bare town")
	town.building_selected.emit(&"Forge")
	assert_true(move.visible)
	move.pressed.emit()
	assert_eq(hub.get("_open_building"), &"", "moving shows the town")
	assert_eq(town.placing, &"Forge")
	_press_key(hub, KEY_ESCAPE)
	assert_eq([town.placing, status.text], [&"", "Stopped moving."])
	assert_false((hub.get_node("%PauseMenu") as CanvasLayer).visible)
	town.building_selected.emit(&"Forge")
	move.pressed.emit()
	town.hex_selected.emit(TownRules.HALL_HEXES[&"Sanctum"])
	assert_eq(status.text, "The Sanctum stands there. Esc cancels.")
	town.hex_selected.emit(FREE_HEX)
	assert_eq([town.placing, status.text], [&"", "Moved the Forge."])
	var forge: Node3D = town.get_node("Forge") as Node3D
	assert_eq(forge.position, TownRules.hex_to_world(FREE_HEX))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var camera: Camera3D = hub.get_viewport().get_camera_3d()
	assert_eq(town.building_at(camera.unproject_position(forge.global_position + Vector3(0.0, 1.5, 0.0))), &"Forge", "it is clickable where it stands")
	town.building_selected.emit(&"Forge")
	for panel: StringName in hub.BUILDING_PANELS[&"Forge"]:
		assert_true((hub.get_node("%" + str(panel)) as Control).visible, str(panel))
	assert_eq(GameSession.keeper_for(&"Forge"), mira)
	(hub.get_node("%ClosePanel") as Button).pressed.emit()
	_press_key(hub, KEY_2)
	assert_eq(hub.get("_open_building"), &"Forge", "key 2 still opens the moved Forge")


func test_the_lumbermill_panel_shows_away_and_the_dispatch_summary_names_it() -> void:
	var workers: Array[Hero] = _staffed_lumbermill()
	assert_ne(GameSession.save_team_preset("", "Loggers", [workers[0].instance_id], "verdant_outskirts"), "")
	var hub: Node3D = _instantiate_hub()
	var presets: ItemList = hub.get_node("%PresetDispatchList") as ItemList
	presets.select(0)
	presets.multi_selected.emit(0, true)
	assert_string_contains((hub.get_node("%DispatchSummary") as RichTextLabel).text, "Lumbermill 1 runs short while away (A)")
	assert_ne(GameSession.dispatch_expedition([workers[0].instance_id], "verdant_outskirts", 1, "Out"), "")
	(hub.get_node("%Town") as TownView).building_selected.emit(&"Lumbermill_1")
	assert_eq((hub.get_node("%PlacedInfo") as Label).text, "Workers 2/2: A · Away, B\nMakes 1.0 wood a minute")


## Two housed heroes working Lumbermill_1, with House_2 and House_3.
func _staffed_lumbermill() -> Array[Hero]:
	var workers: Array[Hero] = [_add_hero("A"), _add_hero("B")]
	var mill: StringName = _place(TownRules.LUMBERMILL, Vector2i(0, 1))
	for index: int in workers.size():
		assert_true(GameSession.assign_home(workers[index], _place(TownRules.HOUSE, Vector2i(index, 2))), GameSession.last_action_error)
		assert_true(GameSession.station_hero(workers[index], mill), GameSession.last_action_error)
	return workers


## town_buildings without the halls: what the player placed.
func _placed() -> Array[Dictionary]:
	return GameSession.town_buildings.filter(func(building: Dictionary) -> bool: return not TownRules.is_hall(building["id"]))


func _press_key(hub: Node3D, keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var key := InputEventKey.new()
		key.keycode = keycode
		key.physical_keycode = keycode
		key.pressed = pressed
		hub.get_viewport().push_input(key)


func _place(type: StringName, hex: Vector2i) -> StringName:
	var id := StringName(GameSession.preview_place_building(type, hex)["id"])
	assert_true(GameSession.place_building(type, hex), GameSession.last_action_error)
	return id


func _add_hero(hero_name: String) -> Hero:
	var hero := Hero.new(hero_name, 7)
	hero.def_id = &"knight"
	hero.level = 80
	GameSession.add_hero(hero)
	return hero


## A reachable screen point whose ground hex `wanted` accepts, off every building's pick box; (-1, -1) if none.
func _point_over(hub: Node3D, wanted: Callable) -> Vector2:
	var town: TownView = hub.get_node("%Town") as TownView
	var size: Vector2 = hub.get_viewport().get_visible_rect().size
	for y: int in range(0, int(size.y), 16):
		for x: int in range(0, int(size.x), 16):
			var at := Vector2(x, y)
			var ground: Variant = town.ground_point(at)
			if ground != null and wanted.call(TownRules.world_to_hex(ground as Vector3)) and _reachable(hub, at):
				return at
	return Vector2(-1, -1)


func _click(hub: Node3D, at: Vector2) -> void:
	for pressed: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = at
		click.global_position = at
		click.pressed = pressed
		hub.get_viewport().push_input(click, true)


## GUT's own output panel covers part of the headless viewport and eats clicks there
## (bd memory: headless GUT click tests); a usable point is under the hub or nothing.
func _reachable(hub: Node3D, at: Vector2) -> bool:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	hub.get_viewport().push_input(motion, true)
	var hovered: Control = hub.get_viewport().gui_get_hovered_control()
	return hovered == null or hub.is_ancestor_of(hovered)


func _instantiate_hub() -> Node3D:
	var hub: Node3D = (load("res://hub/hub.tscn") as PackedScene).instantiate() as Node3D
	add_child_autofree(hub)
	return hub
