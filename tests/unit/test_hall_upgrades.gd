extends GutTest

# ig-6m2.4: a hall upgrade costs wood and stone on top of its parts (SYSTEMS.md § Hall upgrades cost
# wood and stone). Boundary #1: it goes through the commit path, and the save gains no key.

const BALANCE: BalanceTable = preload("res://balance.tres")
const HALLS: Array[String] = ["Summoning Circle", "Forge", "Training Hall", "Sanctum", "Reliquary"]


func before_each() -> void:
	GameSession.set_process(false)
	SaveService.load_blocked = false
	SaveService.load_block_reason = ""
	GameSession.from_dict({"roster": []})


func after_each() -> void:
	GameSession.set_process(true)
	SaveService.load_blocked = false
	SaveService.load_block_reason = ""


func test_the_cost_table_and_the_cap() -> void:
	assert_eq(BalanceTable.new().hall_upgrade_wood_per_level, BALANCE.hall_upgrade_wood_per_level)
	assert_eq(BalanceTable.new().hall_upgrade_stone_per_level, BALANCE.hall_upgrade_stone_per_level)
	for level: int in 5:
		GameSession.building_levels[1] = level
		var plan: Dictionary = GameSession.preview_building_upgrade(1)
		assert_eq([plan["wood_cost"], plan["stone_cost"]], [20 * (level + 1), 10 * (level + 1)], "Lv %d" % level)
		assert_eq([plan["part_rank"], plan["part_cost"]], [level, 10 * (level + 2)], "parts unchanged at Lv %d" % level)
	GameSession.building_levels[1] = 5
	_rich()
	var before: Dictionary = GameSession.to_dict()
	var capped: Dictionary = GameSession.preview_building_upgrade(1)
	assert_false(bool(capped["valid"]))
	assert_eq([capped["part_cost"], capped["wood_cost"], capped["stone_cost"]], [0, 0, 0])
	assert_false(GameSession.upgrade_building(1, BALANCE))
	assert_eq(GameSession.last_action_error, "That building is already at the maximum level.")
	assert_eq(GameSession.to_dict(), before)


func test_each_shortage_refuses_spends_nothing_and_names_only_the_short_ones() -> void:
	# [F parts, wood, stone] -> error. The Summoning Circle at Lv 0 needs 20 F parts, 20 wood, 10 stone.
	var cases: Array = [
		[[12, 20.0, 10.0], "Need 20 F parts (have 12)."],
		[[20, 19.9, 10.0], "Need 20 wood (have 19)."],
		[[20, 20.0, 0.0], "Need 10 stone (have 0)."],
		[[12, 20.0, 0.0], "Need 20 F parts (have 12) and 10 stone (have 0)."],
		[[0, 5.0, 9.0], "Need 20 F parts (have 0), 20 wood (have 5) and 10 stone (have 9)."],
	]
	for case: Array in cases:
		GameSession.parts[0] = case[0][0]
		GameSession.town_resources["wood"] = case[0][1]
		GameSession.town_resources["stone"] = case[0][2]
		var before: Dictionary = GameSession.to_dict()
		assert_eq(GameSession.preview_building_upgrade(0)["error"], case[1])
		assert_false(GameSession.upgrade_building(0, BALANCE), case[1])
		assert_eq(GameSession.last_action_error, case[1])
		assert_eq(GameSession.to_dict(), before, "nothing spent: " + case[1])


func test_the_preview_is_the_result_for_every_hall_down_to_the_last_unit() -> void:
	GameSession.building_levels.assign([0, 1, 2, 3, 4])
	for index: int in HALLS.size():
		var plan: Dictionary = GameSession.preview_building_upgrade(index)
		GameSession.parts[int(plan["part_rank"])] = int(plan["part_cost"])
		GameSession.town_resources["wood"] = float(plan["wood_cost"])
		GameSession.town_resources["stone"] = float(plan["stone_cost"])
		plan = GameSession.preview_building_upgrade(index)
		assert_true(bool(plan["valid"]), HALLS[index])
		assert_true(GameSession.upgrade_building(index, BALANCE), HALLS[index])
		assert_eq(GameSession.building_levels[index], plan["next_level"], HALLS[index])
		assert_eq([GameSession.parts[int(plan["part_rank"])], GameSession.town_resources["wood"], GameSession.town_resources["stone"]], [0, 0.0, 0.0], HALLS[index])


func test_the_hub_shows_the_three_costs_and_spends_them() -> void:
	_rich()
	var hub: Node = (load("res://hub/hub.tscn") as PackedScene).instantiate()
	add_child_autofree(hub)
	var forge: Label = hub.get_node("%ForgeLevel") as Label
	assert_eq(forge.text, "Forge — Lv 0 · Next 20 F parts · 20 wood · 10 stone")
	(hub.get_node("%UpgradeForge") as Button).pressed.emit()
	assert_eq((hub.get_node("%Status") as Label).text, "Upgraded Forge to Lv 1 for 20 F parts, 20 wood and 10 stone.")
	assert_eq(forge.text, "Forge — Lv 1 · Next 30 D parts · 40 wood · 20 stone")
	assert_eq([GameSession.town_resources["wood"], GameSession.town_resources["stone"]], [980.0, 990.0])
	(hub.get_node("%UpgradeForge") as Button).pressed.emit()
	assert_eq((hub.get_node("%Status") as Label).text, "Upgraded Forge to Lv 2 for 30 D parts, 40 wood and 20 stone.")
	GameSession.town_resources["stone"] = 0.0
	(hub.get_node("%UpgradeForge") as Button).pressed.emit()
	assert_eq((hub.get_node("%Status") as Label).text, "Cannot upgrade Forge. Need 30 stone (have 0).")
	assert_eq(GameSession.building_levels[1], 2)


func test_an_upgrade_survives_a_disk_round_trip() -> void:
	_rich()
	assert_true(GameSession.upgrade_building(2, BALANCE))
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(SaveService.SAVE_PATH)
	var saved: Dictionary = JSON.parse_string(bytes.get_string_from_utf8()) as Dictionary
	assert_eq(saved["building_levels"], [0.0, 0.0, 1.0, 0.0, 0.0], "the commit path saved it")
	GameSession.from_dict({"roster": []})
	_write(bytes)
	assert_true(SaveService.load_game())
	assert_eq(GameSession.building_levels, [0, 0, 1, 0, 0] as Array[int])
	assert_eq([GameSession.town_resources["wood"], GameSession.town_resources["stone"]], [980.0, 990.0])


func test_a_save_from_before_this_change_loads_its_levels_unchanged() -> void:
	assert_true(SaveService.save())
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveService.SAVE_PATH)) as Dictionary
	saved["building_levels"] = [1, 2, 0, 3, 5]
	saved["town_resources"] = {"wood": 7.0, "stone": 3.0, "food": 30.0}
	_write(JSON.stringify(saved, "\t").to_utf8_buffer())
	assert_true(SaveService.load_game())
	assert_eq(GameSession.building_levels, [1, 2, 0, 3, 5] as Array[int])
	assert_eq([GameSession.town_resources["wood"], GameSession.town_resources["stone"]], [7.0, 3.0])


func test_a_failed_save_takes_back_the_upgrade_and_all_three_costs() -> void:
	_rich()
	assert_true(SaveService.save())
	var before: Dictionary = GameSession.to_dict().duplicate(true)
	assert_eq(DirAccess.make_dir_absolute(SaveService.TMP_PATH), OK)
	assert_false(GameSession.upgrade_building(1, BALANCE))
	assert_push_error("Save failed")
	assert_ne(GameSession.last_action_error, "")
	assert_eq(DirAccess.remove_absolute(SaveService.TMP_PATH), OK)
	for key: String in ["building_levels", "parts", "town_resources"]:
		assert_eq(GameSession.to_dict()[key], before[key], key)


func test_a_blocked_load_refuses_and_the_preview_says_so() -> void:
	_rich()
	var before: Dictionary = GameSession.to_dict()
	SaveService.load_blocked = true
	SaveService.load_block_reason = "Blocked for the test."
	assert_false(bool(GameSession.preview_building_upgrade(0)["valid"]))
	assert_eq(GameSession.preview_building_upgrade(0)["error"], "Blocked for the test.")
	assert_false(GameSession.upgrade_building(0, BALANCE))
	assert_eq(GameSession.last_action_error, "Blocked for the test.")
	assert_eq(GameSession.to_dict(), before)
	GameSession.town_resources["stone"] = 0.0
	assert_eq(GameSession.preview_building_upgrade(0)["error"], "Blocked for the test.", "blocked wins over short")
	assert_false(GameSession.upgrade_building(0, BALANCE))
	assert_eq(GameSession.last_action_error, "Blocked for the test.", "blocked wins over short")


func _rich() -> void:
	GameSession.parts.fill(99)
	GameSession.town_resources["wood"] = 1000.0
	GameSession.town_resources["stone"] = 1000.0


func _write(bytes: PackedByteArray) -> void:
	var file := FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
