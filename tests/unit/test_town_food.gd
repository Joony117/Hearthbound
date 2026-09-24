extends GutTest

# ig-6m2.5.1: Farms make food and housed heroes who are home eat it, on the live tick only
# (SYSTEMS.md § Food and starvation). Food at 0 just stays at 0 in this slice.
# Boundary #1: town_resources.food is additive, and a save without it gets town_start_food once.

const BALANCE: BalanceTable = preload("res://balance.tres")
const LOADOUT: Dictionary = {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0}
const ZONE: String = "verdant_outskirts"
const FARM_HEX: Vector2i = Vector2i(0, 1)


func before_each() -> void:
	GameSession.set_process(false)
	SaveService.load_blocked = false
	SaveService.load_block_reason = ""
	GameSession.from_dict({"roster": []})
	GameSession.town_resources["wood"] = 1000.0


func after_each() -> void:
	GameSession.set_process(true)


func test_the_first_farm_is_free_and_the_next_costs_the_table_price() -> void:
	assert_eq(int(GameSession.preview_place_building(TownRules.FARM, FARM_HEX)["cost"]), 0, "no Farm yet")
	var farm: StringName = _place(TownRules.FARM, FARM_HEX)
	assert_eq(GameSession.town_resources["wood"], 1000.0)
	assert_eq(TownRules.type_of(farm), TownRules.FARM)
	assert_eq(int(GameSession.preview_place_building(TownRules.FARM, Vector2i(1, 1))["cost"]), BALANCE.farm_wood_cost, "one Farm standing")
	_place(TownRules.FARM, Vector2i(1, 1))
	assert_eq(GameSession.town_resources["wood"], 1000.0 - BALANCE.farm_wood_cost, "the preview is what it spends")


func test_housed_heroes_at_home_eat_and_nobody_else_does() -> void:
	var eaters: Array[Hero] = []
	for index: int in 5:
		eaters.append(_housed("H%d" % index, Vector2i(index - 2, 2)))
	var unhoused: Hero = _add_hero("Stray")
	GameSession.town_resources["food"] = 100.0
	GameSession.tick_expeditions(60.0)
	assert_almost_eq(float(GameSession.town_resources["food"]), 99.0, 0.0001, "five eat 1.0 a minute; the unhoused one eats nothing")
	assert_false(unhoused in GameSession.food_eaters())
	assert_ne(GameSession.dispatch_expedition([eaters[0].instance_id], ZONE, 1, "Out"), "", GameSession.last_action_error)
	var preset: String = GameSession.save_team_preset("", "Fighters", [eaters[1].instance_id], ZONE)
	assert_ne(GameSession.dispatch_force([preset], ZONE, 1, {}, LOADOUT), "", GameSession.last_action_error)
	assert_true(GameSession.clear_home(eaters[2]), GameSession.last_action_error)
	assert_eq(GameSession.food_eaters().size(), 2, "away, in a battle and unhoused don't eat")
	GameSession.town_resources["food"] = 100.0
	GameSession._advance_clocks_in_memory(60.0)
	assert_almost_eq(float(GameSession.town_resources["food"]), 100.0 - 2 * BALANCE.food_per_housed_hero_minute, 0.0001)


func test_a_farm_worker_makes_food_and_food_never_goes_below_zero() -> void:
	assert_almost_eq(float(TownRules.starve_step(0.0, 0.0, false, 1, 0, 60.0, BALANCE)["food"]), BALANCE.food_per_worker_minute, 0.0001, "one worker, one minute")
	var stray: Hero = _add_hero("Stray")
	var farm: StringName = _place(TownRules.FARM, FARM_HEX)
	assert_false(GameSession.station_hero(stray, farm))
	assert_eq(GameSession.last_action_error, "Stray needs a house before working at the %s." % String(farm).capitalize())
	var farmer: Hero = _housed("Farmer", Vector2i(0, 2))
	assert_true(GameSession.station_hero(farmer, farm), GameSession.last_action_error)
	GameSession.town_resources["food"] = 10.0
	GameSession.tick_expeditions(60.0)
	assert_almost_eq(float(GameSession.town_resources["food"]), 10.0 + BALANCE.food_per_worker_minute - BALANCE.food_per_housed_hero_minute, 0.0001, "makes 1.0, eats 0.2")
	var others: Array[Hero] = []
	for index: int in 4:
		others.append(_housed("H%d" % index, Vector2i(index + 1, 2)))
	assert_true(GameSession.station_hero(others[0], farm), GameSession.last_action_error)
	assert_false(GameSession.station_hero(others[1], farm))
	assert_eq(GameSession.last_action_error, "The %s is full." % String(farm).capitalize())
	assert_true(GameSession.unstation_hero(farmer), GameSession.last_action_error)
	assert_true(GameSession.unstation_hero(others[0]), GameSession.last_action_error)
	GameSession.town_resources["food"] = 0.1
	GameSession.tick_expeditions(600.0)
	assert_eq(GameSession.town_resources["food"], 0.0, "it stops at 0")


func test_the_offline_catch_up_moves_food_not_at_all() -> void:
	var farmer: Hero = _housed("Farmer", Vector2i(0, 2))
	assert_true(GameSession.station_hero(farmer, _place(TownRules.FARM, FARM_HEX)), GameSession.last_action_error)
	var eaters: Array[Hero] = []
	for index: int in 3:
		eaters.append(_housed("H%d" % index, Vector2i(index + 1, 2)))
	assert_ne(GameSession.dispatch_expedition([eaters[0].instance_id], ZONE, 1, "Out"), "", GameSession.last_action_error)
	var food: float = GameSession.town_resources["food"]
	GameSession.saved_at_unix = Time.get_unix_time_from_system() - 36000.0
	GameSession.apply_offline_expedition_progress(Time.get_unix_time_from_system())
	assert_eq(GameSession.town_resources["food"], food, "the catch-up with an order out")
	GameSession._advance_orders_in_memory(360000.0)
	assert_eq(GameSession.town_resources["food"], food)


# The gate must fire for eaters alone, even at 0 food (slice 2's clock runs there), and for a Farm.
func test_the_periodic_save_fires_for_eaters_at_zero_food_and_for_a_farm() -> void:
	_housed("Eater", Vector2i(0, 2))
	GameSession.town_resources["food"] = 0.0
	assert_true(_periodic_save_wrote())
	var farmer: Hero = _housed("Farmer", Vector2i(1, 2))
	assert_true(GameSession.station_hero(farmer, _place(TownRules.FARM, FARM_HEX)), GameSession.last_action_error)
	assert_true(_periodic_save_wrote())


func test_nobody_home_means_no_periodic_save() -> void:
	_add_hero("Stray")
	assert_false(_periodic_save_wrote(), "the gate is not always open")


# Boundary #1: through SaveService and the disk, with a partial unit of food.
func test_food_survives_a_disk_round_trip() -> void:
	var farmer: Hero = _housed("Farmer", Vector2i(0, 2))
	assert_true(GameSession.station_hero(farmer, _place(TownRules.FARM, FARM_HEX)), GameSession.last_action_error)
	GameSession.tick_expeditions(45.0)
	var food: float = GameSession.town_resources["food"]
	assert_ne(food, floorf(food), "a partial unit is in play")
	assert_true(SaveService.save(), SaveService.last_write_error)
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(SaveService.SAVE_PATH)
	GameSession.from_dict({"roster": []})
	_write(bytes)
	assert_true(SaveService.load_game())
	assert_eq(GameSession.town_resources["food"], food)
	assert_push_warning_count(0)
	assert_push_error_count(0)


func test_a_save_without_food_gets_the_start_food_once() -> void:
	GameSession.town_resources = {"wood": 12.0, "stone": 3.0, "food": 5.0}
	assert_true(SaveService.save())
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveService.SAVE_PATH)) as Dictionary
	(saved["town_resources"] as Dictionary).erase("food")
	_write(JSON.stringify(saved, "\t").to_utf8_buffer())
	assert_true(SaveService.load_game())
	assert_eq(GameSession.town_resources, {"wood": 12.0, "stone": 3.0, "food": BALANCE.town_start_food}, "an ig-6m2.3.1-era save")
	GameSession.town_resources["food"] = 5.0
	GameSession.from_dict(GameSession.to_dict())
	assert_eq(GameSession.town_resources["food"], 5.0, "only when the key is missing")
	saved.erase("town_resources")
	_write(JSON.stringify(saved, "\t").to_utf8_buffer())
	assert_true(SaveService.load_game())
	assert_eq(GameSession.town_resources, {"wood": BALANCE.town_start_wood, "stone": 0.0, "food": BALANCE.town_start_food}, "a save from before the town")
	assert_push_warning_count(0)
	assert_push_error_count(0)


func test_negative_food_loads_zero_and_bad_food_or_bad_resources_load_the_start_food() -> void:
	var state: Dictionary = GameSession.to_dict()
	state["town_resources"] = {"wood": 12.0, "stone": 0.0, "food": -3.0}
	GameSession.from_dict(state)
	assert_eq(GameSession.town_resources["food"], 0.0)
	assert_push_error_count(0)
	state["town_resources"] = {"wood": 12.0, "stone": 0.0, "food": "plenty"}
	GameSession.from_dict(state)
	assert_push_error("Invalid town resources food")
	assert_eq(GameSession.town_resources["food"], BALANCE.town_start_food)
	state["town_resources"] = ["broken"]
	GameSession.from_dict(state)
	assert_push_error("Invalid town_resources")
	assert_eq(GameSession.town_resources, {"wood": 0.0, "stone": 0.0, "food": BALANCE.town_start_food}, "wood keeps its 0; food is repaired")
	_housed("Eater", Vector2i(0, 2))
	GameSession.tick_expeditions(60.0)
	assert_almost_eq(float(GameSession.town_resources["food"]), BALANCE.town_start_food - BALANCE.food_per_housed_hero_minute, 0.0001, "and the tick reads it")


func test_the_farm_scene_is_pickable_and_its_panel_says_food() -> void:
	var building: Node = TownView.SCENES[TownRules.FARM].instantiate()
	assert_eq((building.get_node("Pick") as StaticBody3D).collision_layer, TownView.PICK_LAYER, "layer 2 only")
	assert_true(building.has_node("WorkSpot"))
	building.free()
	var farmer: Hero = _housed("Farmer", Vector2i(0, 2))
	var farm: StringName = _place(TownRules.FARM, FARM_HEX)
	assert_eq(farm, &"Farm_2", "ids are shared across types: the House took 1")
	assert_true(GameSession.station_hero(farmer, farm), GameSession.last_action_error)
	var hub: Node3D = (load("res://hub/hub.tscn") as PackedScene).instantiate() as Node3D
	add_child_autofree(hub)
	await get_tree().physics_frame
	var town: TownView = hub.get_node("%Town") as TownView
	var camera: Camera3D = hub.get_viewport().get_camera_3d()
	var node: Node3D = town.get_node(NodePath(str(farm))) as Node3D
	assert_eq(town.building_at(camera.unproject_position(node.global_position + Vector3(0.0, 1.0, 0.0))), farm, "it is clickable")
	assert_eq((hub.get_node("%Wood") as Label).text, "Wood: 1000   Stone: 0   Food: 30")
	town.building_selected.emit(farm)
	assert_eq((hub.get_node("%PlacedInfo") as Label).text, "Workers 1/2: Farmer\nMakes 1.0 food a minute")


## Arms the periodic save, changes wood without a save, runs one pulse: did the file get the change?
func _periodic_save_wrote() -> bool:
	assert_true(SaveService.save(), SaveService.last_write_error)
	GameSession.town_resources["wood"] = float(GameSession.town_resources["wood"]) + 7.0
	GameSession.set("_periodic_save_accumulator", GameSession.PERIODIC_SAVE_SECONDS - 0.1)
	GameSession._process(0.25)
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveService.SAVE_PATH)) as Dictionary
	return float((saved["town_resources"] as Dictionary)["wood"]) == float(GameSession.town_resources["wood"])


func _housed(hero_name: String, hex: Vector2i) -> Hero:
	var hero: Hero = _add_hero(hero_name)
	assert_true(GameSession.assign_home(hero, _place(TownRules.HOUSE, hex)), GameSession.last_action_error)
	return hero


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


func _write(bytes: PackedByteArray) -> void:
	var file := FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
