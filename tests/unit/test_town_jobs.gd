extends GutTest

# ig-6m2.7: town jobs are professions. A worker at home earns its job's XP on the live tick and makes
# 1 + worker_skill_bonus_per_level x skill workers' worth (SYSTEMS.md § Keepers and professions, Workers).
# Boundary #1: the job XP rides the existing hero profession_xp through SaveService and the disk.

const BALANCE: BalanceTable = preload("res://balance.tres")
const SKILL_XP: Dictionary[int, float] = {0: 0.0, 1: 21.0 * 60.0, 3: 125.0 * 60.0, 5: 300.0 * 60.0}
const DUE_1: float = 1200.0
const MILL_HEX: Vector2i = Vector2i(0, 1)
const MINE_HEX: Vector2i = Vector2i(1, 1)
const FARM_HEX: Vector2i = Vector2i(-1, 1)

var _houses: int = 0


func before_each() -> void:
	GameSession.set_process(false)
	SaveService.load_blocked = false
	SaveService.load_block_reason = ""
	GameSession.from_dict({"roster": []})
	GameSession.town_resources["wood"] = 1000.0
	_houses = 0


func after_each() -> void:
	GameSession.set_process(true)


func test_workers_earn_their_jobs_xp_at_home_on_the_live_tick_only() -> void:
	var mill: StringName = _place(TownRules.LUMBERMILL, MILL_HEX)
	var mine: StringName = _place(TownRules.MINE, MINE_HEX)
	var farm: StringName = _place(TownRules.FARM, FARM_HEX)
	var cutter: Hero = _worker("Cutter", mill, 0, true)
	var plain: Hero = _worker("Plain", mill, 0, false)
	var miner: Hero = _worker("Miner", mine, 0, false)
	var away: Hero = _worker("Away", mine, 0, true)
	var farmer: Hero = _worker("Farmer", farm, 0, false)
	var smith: Hero = _hero("Smith", [&"smithing", &"rites"])
	assert_true(GameSession.station_hero(smith, &"Forge"), GameSession.last_action_error)
	_send_away(away)
	GameSession.tick_expeditions(60.0)
	assert_almost_eq(_xp(cutter, &"woodcutting"), 240.0, 0.001, "x4 in a passion")
	assert_almost_eq(_xp(plain, &"woodcutting"), 60.0, 0.001, "x1 otherwise")
	assert_almost_eq(_xp(miner, &"mining"), 60.0, 0.001, "a Mine worker earns mining")
	assert_almost_eq(_xp(farmer, &"farming"), 60.0, 0.001, "a Farm worker earns farming")
	assert_almost_eq(_xp(away, &"mining"), 0.0, 0.001, "away earns nothing")
	assert_almost_eq(_xp(smith, &"smithing"), 240.0, 0.001, "a keeper still earns in its hall's profession")
	assert_almost_eq(_xp(cutter, &"mining"), 0.0, 0.001, "and only in its own job")
	_come_home()  # The catch-up saves, and the fake order would not load (ig-6pm).
	GameSession._advance_orders_in_memory(3600.0)
	assert_almost_eq(_xp(cutter, &"woodcutting"), 240.0, 0.001, "the offline catch-up grants none")
	assert_almost_eq(_xp(plain, &"woodcutting"), 60.0, 0.001)
	assert_almost_eq(_xp(away, &"mining"), 0.0, 0.001)
	assert_almost_eq(_xp(smith, &"smithing"), 240.0, 0.001)


func test_a_skill_5_worker_makes_one_and_a_half_times_in_every_job() -> void:
	var mill: StringName = _place(TownRules.LUMBERMILL, MILL_HEX)
	var mine: StringName = _place(TownRules.MINE, MINE_HEX)
	var farm: StringName = _place(TownRules.FARM, FARM_HEX)
	_worker("Cutter", mill, 5, false)
	_worker("Miner", mine, 5, false)
	_worker("Farmer", farm, 5, false)
	var before: Dictionary = GameSession.town_resources.duplicate()
	GameSession.tick_expeditions(60.0)
	assert_almost_eq(float(GameSession.town_resources["wood"]) - float(before["wood"]), 1.5, 0.0001)
	assert_almost_eq(float(GameSession.town_resources["stone"]) - float(before["stone"]), 0.75, 0.0001)
	# Three heroes eat food_per_hero_minute each.
	assert_almost_eq(float(GameSession.town_resources["food"]) - float(before["food"]), 1.5 - 3 * BALANCE.food_per_hero_minute, 0.0001)


func test_skill_0_makes_one_and_workers_add_up() -> void:
	var mill: StringName = _place(TownRules.LUMBERMILL, MILL_HEX)
	_worker("Rookie", mill, 0, false)
	var wood: float = GameSession.town_resources["wood"]
	GameSession.tick_expeditions(60.0)
	assert_almost_eq(float(GameSession.town_resources["wood"]) - wood, 1.0, 0.0001)
	_worker("Pro", mill, 5, false)
	wood = GameSession.town_resources["wood"]
	GameSession.tick_expeditions(60.0)
	assert_almost_eq(float(GameSession.town_resources["wood"]) - wood, 2.5, 0.0001, "skills 0 and 5")


# The skill bonus first, then the starving cut: 1.5 x 0.5.
func test_a_starving_town_halves_the_skilled_rate() -> void:
	var mill: StringName = _place(TownRules.LUMBERMILL, MILL_HEX)
	_worker("Cutter", mill, 5, false)
	GameSession.town_resources["food"] = 0.0
	GameSession.town_starving_seconds = 10.0
	var wood: float = GameSession.town_resources["wood"]
	GameSession.tick_expeditions(60.0)
	assert_almost_eq(float(GameSession.town_resources["wood"]) - wood, 0.75, 0.0001)


# The pulse's look-ahead reads the same skill as the live tick. Three eaters eat 0.6 food a minute; starving,
# an unskilled farmer makes 0.5 and a skill-5 one 0.75. So one town has its death and the other has none.
func test_the_look_ahead_and_the_live_tick_both_bring_the_death_for_an_unskilled_farmer() -> void:
	_starving_town(0)
	GameSession.tick_expeditions(1.0)
	assert_eq(GameSession.roster.size(), 2, "the live tick killed one eater")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveService.SAVE_PATH)) as Dictionary
	assert_eq((saved["roster"] as Array).size(), 2, "the look-ahead saw the death, so it was saved")


func test_the_look_ahead_and_the_live_tick_both_spare_a_skilled_farmers_town() -> void:
	_starving_town(5)
	GameSession.tick_expeditions(1.0)
	assert_eq(GameSession.roster.size(), 3, "the live tick killed nobody")
	assert_eq(GameSession.town_starving_seconds, DUE_1 - 1.0, "held")
	assert_gt(float(GameSession.town_resources["food"]), 0.0, "the farm out-ran the eating")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveService.SAVE_PATH)) as Dictionary
	assert_eq(float((saved["town_resources"] as Dictionary)["food"]), 0.0, "the look-ahead saw no death, so nothing was saved")


# Boundary #1: a real save and reload through the disk.
func test_job_xp_and_the_skill_it_reads_as_survive_a_disk_round_trip() -> void:
	var mill: StringName = _place(TownRules.LUMBERMILL, MILL_HEX)
	var hero: Hero = _worker("Ada", mill, 3, true)
	GameSession.tick_expeditions(15.0)
	hero.profession_xp[&"mining"] = SKILL_XP[5]
	hero.profession_xp[&"farming"] = SKILL_XP[1]
	var woodcutting: float = _xp(hero, &"woodcutting")
	assert_almost_eq(woodcutting, SKILL_XP[3] + 60.0, 0.001, "15 s at x4 came on top")
	_disk_round_trip()
	var loaded: Hero = GameSession.hero_by_id(hero.instance_id)
	assert_almost_eq(_xp(loaded, &"woodcutting"), woodcutting, 0.001)
	assert_eq(Hero.profession_skill(loaded, &"woodcutting", BALANCE), 3)
	assert_almost_eq(_xp(loaded, &"mining"), SKILL_XP[5], 0.001)
	assert_eq(Hero.profession_skill(loaded, &"mining", BALANCE), 5)
	assert_almost_eq(_xp(loaded, &"farming"), SKILL_XP[1], 0.001)
	assert_eq(Hero.profession_skill(loaded, &"farming", BALANCE), 1)
	assert_almost_eq(GameSession._work_home(TownRules.LUMBERMILL), 1.3, 0.0001, "the loaded worker reads its skill")
	assert_push_warning_count(0)
	assert_push_error_count(0)


func test_a_save_with_no_job_xp_loads_zero_and_the_worker_makes_the_base_rate() -> void:
	var mill: StringName = _place(TownRules.LUMBERMILL, MILL_HEX)
	var hero: Hero = _worker("Ada", mill, 5, true)
	hero.profession_xp[&"smithing"] = 300.0
	assert_true(SaveService.save(), SaveService.last_write_error)
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveService.SAVE_PATH)) as Dictionary
	var entry: Dictionary = (saved["roster"] as Array)[0] as Dictionary
	assert_true((entry["profession_xp"] as Dictionary).has("woodcutting"), "written now")
	for profession: String in ["woodcutting", "mining", "farming"]:
		(entry["profession_xp"] as Dictionary).erase(profession)
	GameSession.from_dict({"roster": []})
	_write(JSON.stringify(saved, "\t").to_utf8_buffer())
	assert_true(SaveService.load_game(), SaveService.load_block_reason)
	var loaded: Hero = GameSession.hero_by_id(hero.instance_id)
	for profession: StringName in [&"woodcutting", &"mining", &"farming"]:
		assert_eq(_xp(loaded, profession), 0.0, str(profession))
		assert_eq(Hero.profession_skill(loaded, profession, BALANCE), 0)
	assert_almost_eq(_xp(loaded, &"smithing"), 300.0, 0.001, "the other professions stay")
	assert_almost_eq(GameSession._work_home(TownRules.LUMBERMILL), 1.0, 0.0001)
	assert_push_warning_count(0)
	assert_push_error_count(0)


func test_the_workplace_panel_shows_each_workers_skill_and_passion_and_the_summed_rate() -> void:
	var mill: StringName = _place(TownRules.LUMBERMILL, MILL_HEX)
	var farm: StringName = _place(TownRules.FARM, FARM_HEX)
	_worker("Ada", mill, 5, true)
	_worker("Bo", mill, 0, false)
	_worker("Cy", farm, 5, false)
	var hub: Node3D = _instantiate_hub()
	var town: TownView = hub.get_node("%Town") as TownView
	var info: Label = hub.get_node("%PlacedInfo") as Label
	town.building_selected.emit(mill)
	assert_eq(info.text, "Workers 2/2: Ada (Woodcutting 5, passion), Bo (Woodcutting 0)\nMakes 2.5 wood a minute")
	town.building_selected.emit(farm)
	assert_eq(info.text, "Workers 1/2: Cy (Farming 5)\nMakes 1.5 food a minute")


# The panel says what the tick pays: the skill bonus first, then the starving cut (1.5 x 0.5 = 0.75).
func test_the_workplace_panel_rate_halves_while_starving_like_the_tick() -> void:
	var mill: StringName = _place(TownRules.LUMBERMILL, MILL_HEX)
	_worker("Ada", mill, 5, false)
	var hub: Node3D = _instantiate_hub()
	var town: TownView = hub.get_node("%Town") as TownView
	var info: Label = hub.get_node("%PlacedInfo") as Label
	town.building_selected.emit(mill)
	assert_string_contains(info.text, "Makes 1.5 wood a minute")
	GameSession.town_resources["food"] = 0.0
	GameSession.town_starving_seconds = 10.0
	var wood: float = GameSession.town_resources["wood"]
	GameSession.tick_expeditions(60.0)
	assert_almost_eq(float(GameSession.town_resources["wood"]) - wood, 0.75, 0.0001, "what the tick pays")
	town.building_selected.emit(mill)
	assert_string_contains(info.text, "Makes 0.8 wood a minute")  # 0.75, to one decimal.
	GameSession.town_starving_seconds = 0.0
	town.building_selected.emit(mill)
	assert_string_contains(info.text, "Makes 1.5 wood a minute")


func test_the_workplace_picker_lists_passion_heroes_first_with_their_skill() -> void:
	var mill: StringName = _place(TownRules.LUMBERMILL, MILL_HEX)
	_hero("A", [&"smithing", &"rites"])
	var b: Hero = _hero("B", [&"woodcutting", &"rites"])
	_set_skill(b, &"woodcutting", 3)
	_hero("C", [&"rites", &"woodcutting"])
	_hero("D", [&"smithing", &"rites"])
	var hub: Node3D = _instantiate_hub()
	(hub.get_node("%Town") as TownView).building_selected.emit(mill)
	(hub.get_node("%PlacedAssign") as Button).pressed.emit()
	var picker: PopupMenu = hub.get_node("%PlacedPicker") as PopupMenu
	var rows: PackedStringArray = []
	for index: int in picker.item_count:
		rows.append(picker.get_item_text(index))
	picker.hide()
	assert_eq(rows, PackedStringArray(["B — Woodcutting 3 · passion", "C — Woodcutting 0 · passion", "A — Woodcutting 0", "D — Woodcutting 0"]))


# A House shows no skill and lists in roster order, passion or not.
func test_a_house_panel_and_picker_are_unchanged() -> void:
	var house: StringName = _place(TownRules.HOUSE, Vector2i(0, 3))
	var a: Hero = _hero("A", [&"smithing", &"rites"])
	_hero("B", [&"woodcutting", &"rites"])
	assert_true(GameSession.assign_home(a, _place(TownRules.HOUSE, Vector2i(1, 3))), GameSession.last_action_error)
	var hub: Node3D = _instantiate_hub()
	(hub.get_node("%Town") as TownView).building_selected.emit(house)
	assert_eq((hub.get_node("%PlacedInfo") as Label).text, "Resident 0/1: none")
	(hub.get_node("%PlacedAssign") as Button).pressed.emit()
	var picker: PopupMenu = hub.get_node("%PlacedPicker") as PopupMenu
	var rows: PackedStringArray = []
	for index: int in picker.item_count:
		rows.append(picker.get_item_text(index))
	picker.hide()
	assert_eq(rows, PackedStringArray(["A · lives in House 2", "B"]))


func test_the_skill_bonus_row_is_in_the_balance_table() -> void:
	assert_eq(BALANCE.worker_skill_bonus_per_level, 0.10)
	assert_true(FileAccess.get_file_as_string("res://balance.tres").contains("worker_skill_bonus_per_level = 0.1\n"))


## Three eaters and a farmer among them at DUE_1 - 1 starving seconds, acknowledged, food 0, and the
## table saved first so a later save shows whether the look-ahead committed the tick.
func _starving_town(farm_skill: int) -> void:
	var farm: StringName = _place(TownRules.FARM, FARM_HEX)
	_worker("Farmer", farm, farm_skill, false)
	_housed(_hero("Eater1", [&"smithing", &"rites"]))
	_housed(_hero("Eater2", [&"smithing", &"rites"]))
	GameSession.town_resources["food"] = 0.0
	GameSession.town_starving_seconds = DUE_1 - 1.0
	GameSession.town_starve_acked = true
	assert_true(SaveService.save(), SaveService.last_write_error)


## Housed, at the job's building, with its job skill set; the passion is the job's or two that are not.
func _worker(hero_name: String, building: StringName, skill: int, passion: bool) -> Hero:
	var profession: StringName = TownRules.JOB_PROFESSIONS[TownRules.type_of(building)]
	var hero: Hero = _hero(hero_name, [profession, &"rites"] if passion else [&"smithing", &"rites"])
	_set_skill(hero, profession, skill)
	_housed(hero)
	assert_true(GameSession.station_hero(hero, building), GameSession.last_action_error)
	return hero


func _housed(hero: Hero) -> void:
	assert_true(GameSession.assign_home(hero, _place(TownRules.HOUSE, Vector2i(_houses - 3, 4))), GameSession.last_action_error)
	_houses += 1


## Passions are random per hero, so each test sets them.
func _hero(hero_name: String, passions: Array) -> Hero:
	var hero := Hero.new(hero_name, 7)
	hero.def_id = &"knight"
	hero.level = 80
	hero.passions.assign(passions)
	GameSession.add_hero(hero)
	return hero


func _set_skill(hero: Hero, profession: StringName, skill: int) -> void:
	hero.profession_xp[profession] = SKILL_XP[skill]


func _xp(hero: Hero, profession: StringName) -> float:
	return float(hero.profession_xp.get(profession, 0.0))


## Placed and finished at once: construction (ig-6m2.3.2) is not what this file tests.
func _place(type: StringName, hex: Vector2i) -> StringName:
	var id := StringName(GameSession.preview_place_building(type, hex)["id"])
	assert_true(GameSession.place_building(type, hex), GameSession.last_action_error)
	GameSession.town_building(id).erase("build_remaining")
	return id


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


func _instantiate_hub() -> Node3D:
	var hub: Node3D = (load("res://hub/hub.tscn") as PackedScene).instantiate() as Node3D
	add_child_autofree(hub)
	return hub
