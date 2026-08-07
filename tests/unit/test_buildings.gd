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


func test_forge_hub_status_matches_salvage_yield_and_enhance_cap() -> void:
	GameSession.building_levels[1] = 2
	var salvaged_item := Item.new(&"ring", 3)
	var capped_item := Item.new(&"ring", 3)
	capped_item.enhance_level = 6
	GameSession.add_item(salvaged_item)
	GameSession.add_item(capped_item)
	GameSession.parts[3] = 99
	var hub_scene: PackedScene = load("res://hub/hub.tscn") as PackedScene
	assert_not_null(hub_scene)
	var hub: Node3D = hub_scene.instantiate() as Node3D
	add_child_autofree(hub)
	var inventory_list: ItemList = hub.get_node("%InventoryList") as ItemList
	var salvage_button: Button = hub.get_node("UI/Root/EquipmentPanel/Columns/Inventory/Salvage") as Button
	var enhance_button: Button = hub.get_node("UI/Root/EquipmentPanel/Columns/Inventory/Enhance") as Button
	var status: Label = hub.get_node("%Status") as Label

	inventory_list.select(0)
	var parts_before: int = GameSession.parts[3]
	salvage_button.pressed.emit()
	assert_eq(status.text, "Salvaged B item into 4 B parts.")
	assert_eq(GameSession.parts[3] - parts_before, 4)

	inventory_list.select(0)
	parts_before = GameSession.parts[3]
	enhance_button.pressed.emit()
	assert_eq(status.text, "Cannot enhance: item is already at the +6 cap.")
	assert_eq(capped_item.enhance_level, 6)
	assert_eq(GameSession.parts[3], parts_before)
