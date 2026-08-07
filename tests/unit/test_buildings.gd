extends GutTest


func before_each() -> void:
	GameSession.from_dict({"roster": []})


func test_upgrade_uses_the_cost_ladder() -> void:
	var balance := BalanceTable.new()
	GameSession.parts[0] = 20
	GameSession.parts[1] = 30

	assert_true(GameSession.upgrade_building(0, balance))
	assert_eq(GameSession.building_levels[0], 1)
	assert_eq(GameSession.parts[0], 0)
	assert_true(GameSession.upgrade_building(0, balance))
	assert_eq(GameSession.building_levels[0], 2)
	assert_eq(GameSession.parts[1], 0)


func test_upgrade_refuses_at_cap_without_writing() -> void:
	var balance := BalanceTable.new()
	GameSession.building_levels[0] = balance.summoning_circle_level_cap
	GameSession.parts[0] = 99
	var levels_before: Array[int] = GameSession.building_levels.duplicate()
	var parts_before: Array[int] = GameSession.parts.duplicate()

	assert_false(GameSession.upgrade_building(0, balance))
	assert_eq(GameSession.building_levels, levels_before)
	assert_eq(GameSession.parts, parts_before)


func test_upgrade_refuses_insufficient_parts_without_writing() -> void:
	var balance := BalanceTable.new()
	GameSession.parts[0] = 19
	var levels_before: Array[int] = GameSession.building_levels.duplicate()
	var parts_before: Array[int] = GameSession.parts.duplicate()

	assert_false(GameSession.upgrade_building(0, balance))
	assert_eq(GameSession.building_levels, levels_before)
	assert_eq(GameSession.parts, parts_before)


func test_upgrade_refuses_out_of_range_indices_without_writing() -> void:
	var balance := BalanceTable.new()
	GameSession.parts[0] = 99
	var levels_before: Array[int] = GameSession.building_levels.duplicate()
	var parts_before: Array[int] = GameSession.parts.duplicate()

	assert_false(GameSession.upgrade_building(-1, balance))
	assert_false(GameSession.upgrade_building(GameSession.building_levels.size(), balance))
	assert_eq(GameSession.building_levels, levels_before)
	assert_eq(GameSession.parts, parts_before)
