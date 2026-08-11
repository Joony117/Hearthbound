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

	var salvage_index: int = -1
	for item_index: int in inventory_list.item_count:
		if inventory_list.get_item_metadata(item_index) == salvaged_item:
			salvage_index = item_index
			break
	assert_ne(salvage_index, -1)
	# Same rank, so the +6 sorts first (P2-25 criterion 4). The +0 is what this test salvages —
	# selecting index 0 would destroy the +6 and leave nothing for the enhance-cap half below.
	assert_eq(salvage_index, 1)
	inventory_list.select(salvage_index)
	var parts_before: int = GameSession.parts[3]
	salvage_button.pressed.emit()
	# The press only asks; salvage destroys the item, so it waits for the confirm.
	assert_eq(GameSession.parts[3], parts_before)
	(hub.get_node("%ConfirmDialog") as ConfirmationDialog).confirmed.emit()
	assert_eq(status.text, "Salvaged B item into 4 B parts.")
	assert_eq(GameSession.parts[3] - parts_before, 4)

	var capped_index: int = -1
	for item_index: int in inventory_list.item_count:
		if inventory_list.get_item_metadata(item_index) == capped_item:
			capped_index = item_index
			break
	assert_ne(capped_index, -1)
	inventory_list.select(capped_index)
	parts_before = GameSession.parts[3]
	enhance_button.pressed.emit()
	assert_eq(status.text, "Cannot enhance: item is already at the +6 cap.")
	assert_eq(capped_item.enhance_level, 6)
	assert_eq(GameSession.parts[3], parts_before)


func test_training_hall_upgrade_updates_hub() -> void:
	GameSession.parts[0] = 20
	var hub_scene: PackedScene = load("res://hub/hub.tscn") as PackedScene
	assert_not_null(hub_scene)
	var hub: Node3D = hub_scene.instantiate() as Node3D
	add_child_autofree(hub)
	var upgrade_button: Button = hub.get_node("UI/Root/BuildingsPanel/VBox/UpgradeTrainingHall") as Button
	var status: Label = hub.get_node("%Status") as Label
	var training_hall_level: Label = hub.get_node("%TrainingHallLevel") as Label

	upgrade_button.pressed.emit()
	assert_eq(GameSession.building_levels[2], 1)
	assert_eq(GameSession.parts[0], 0)
	assert_eq(status.text, "Upgraded Training Hall to Lv 1 for 20 F parts.")
	assert_eq(training_hall_level.text, "Training Hall — Lv 1")


func test_reliquary_upgrade_updates_hub() -> void:
	GameSession.parts[0] = 20
	var hub_scene: PackedScene = load("res://hub/hub.tscn") as PackedScene
	assert_not_null(hub_scene)
	var hub: Node3D = hub_scene.instantiate() as Node3D
	add_child_autofree(hub)
	var upgrade_button: Button = hub.get_node("UI/Root/BuildingsPanel/VBox/UpgradeReliquary") as Button
	var status: Label = hub.get_node("%Status") as Label
	var reliquary_level: Label = hub.get_node("%ReliquaryLevel") as Label

	upgrade_button.pressed.emit()
	assert_eq(GameSession.building_levels[4], 1)
	assert_eq(GameSession.parts[0], 0)
	assert_eq(status.text, "Upgraded Reliquary to Lv 1 for 20 F parts.")
	assert_eq(reliquary_level.text, "Reliquary — Lv 1")


func test_reliquary_upgrade_refuses_without_parts() -> void:
	GameSession.parts[0] = 19
	var hub_scene: PackedScene = load("res://hub/hub.tscn") as PackedScene
	var hub: Node3D = hub_scene.instantiate() as Node3D
	add_child_autofree(hub)
	var upgrade_button: Button = hub.get_node("UI/Root/BuildingsPanel/VBox/UpgradeReliquary") as Button
	var status: Label = hub.get_node("%Status") as Label
	var reliquary_level: Label = hub.get_node("%ReliquaryLevel") as Label

	upgrade_button.pressed.emit()
	assert_eq(GameSession.building_levels[4], 0)
	assert_eq(GameSession.parts[0], 19)
	assert_eq(status.text, "Cannot upgrade Reliquary: need 20 F parts.")
	assert_eq(reliquary_level.text, "Reliquary — Lv 0")


## The point of P2-24 is the wiring, not the formulas - both already read building_levels[4]
## correctly. So the level has to arrive by pressing the button, never by writing the array:
## P2-21 proved the Training Hall's arithmetic with a direct write, which would have passed
## just as green with the button absent.
func test_reliquary_upgrade_reaches_both_consumers_from_the_hub() -> void:
	var balance := BalanceTable.new()
	GameSession.parts[0] = 20
	var cache := LostCache.new("Doomed", &"verdant_outskirts", 0)
	GameSession.lost_caches.append(cache)
	var hub_scene: PackedScene = load("res://hub/hub.tscn") as PackedScene
	var hub: Node3D = hub_scene.instantiate() as Node3D
	add_child_autofree(hub)
	var upgrade_button: Button = hub.get_node("UI/Root/BuildingsPanel/VBox/UpgradeReliquary") as Button
	var lost_cache_list: ItemList = hub.get_node("%LostCacheList") as ItemList
	# team_power far above the zone's 900 keeps power_deficit_penalty at 0, so the only term
	# moving between the two readings is the Reliquary's.
	var damage_before: float = LostCache.compute_damage_chance(
		cache, 900, 9000.0, GameSession.turns, GameSession.building_levels[4], balance
	)
	assert_eq(lost_cache_list.get_item_text(0), "Doomed — Verdant Outskirts — 0 items — 15 turns remaining")

	upgrade_button.pressed.emit()

	assert_eq(
		lost_cache_list.get_item_text(0),
		"Doomed — Verdant Outskirts — 0 items — %d turns remaining" % (15 + balance.reliquary_decay_turns_bonus)
	)
	var damage_after: float = LostCache.compute_damage_chance(
		cache, 900, 9000.0, GameSession.turns, GameSession.building_levels[4], balance
	)
	assert_almost_eq(damage_before - damage_after, balance.reliquary_damage_chance_reduction, 0.0001)
