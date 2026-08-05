extends GutTest


func before_each() -> void:
	GameSession.from_dict({"roster": []})


func test_equip_moves_item_to_its_definition_slot_and_out_of_inventory() -> void:
	var hero := Hero.new("Equipped Hero", 1)
	var item := Item.new(&"ring", 2)
	var definition: EquipmentDefinition = Item.definition_for(item.def_id)

	GameSession.add_hero(hero)
	GameSession.add_item(item)
	GameSession.equip_item(hero, item)

	assert_eq(hero.equipped[definition.slot], item)
	assert_false(GameSession.inventory.has(item))
	assert_eq(_count_item(hero, item), 1)


func test_equip_replaces_same_slot_without_losing_or_duplicating_items() -> void:
	var hero := Hero.new("Swap Hero", 1)
	var first := Item.new(&"ring", 1)
	var second := Item.new(&"ring", 3)
	var definition: EquipmentDefinition = Item.definition_for(first.def_id)

	GameSession.add_hero(hero)
	GameSession.add_item(first)
	GameSession.add_item(second)
	assert_eq(_count_item(hero, first), 1)
	assert_eq(_count_item(hero, second), 1)

	GameSession.equip_item(hero, first)
	GameSession.equip_item(hero, second)

	assert_eq(hero.equipped[definition.slot], second)
	assert_true(GameSession.inventory.has(first))
	assert_false(GameSession.inventory.has(second))
	assert_eq(_count_item(hero, first), 1)
	assert_eq(_count_item(hero, second), 1)


func test_unequip_returns_item_to_inventory_and_clears_slot() -> void:
	var hero := Hero.new("Unequipped Hero", 1)
	var item := Item.new(&"necklace", 2)
	var definition: EquipmentDefinition = Item.definition_for(item.def_id)

	GameSession.add_hero(hero)
	GameSession.add_item(item)
	GameSession.equip_item(hero, item)
	GameSession.unequip_item(hero, definition.slot)

	assert_false(hero.equipped.has(definition.slot))
	assert_true(GameSession.inventory.has(item))
	assert_eq(_count_item(hero, item), 1)


func test_kill_hero_returns_all_equipped_items_to_inventory() -> void:
	var hero := Hero.new("Doomed Hero", 2)
	var ring := Item.new(&"ring", 1)
	var necklace := Item.new(&"necklace", 3)

	GameSession.add_hero(hero)
	GameSession.add_item(ring)
	GameSession.add_item(necklace)
	GameSession.equip_item(hero, ring)
	GameSession.equip_item(hero, necklace)
	GameSession.kill_hero(hero)

	assert_false(GameSession.roster.has(hero))
	assert_true(hero.equipped.is_empty())
	assert_true(GameSession.inventory.has(ring))
	assert_true(GameSession.inventory.has(necklace))
	assert_eq(_count_inventory_item(ring), 1)
	assert_eq(_count_inventory_item(necklace), 1)


func test_equipped_item_survives_game_session_round_trip() -> void:
	var hero := Hero.new("Saved Hero", 3)
	hero.def_id = &"mage"
	var item := Item.new(&"ring", 4)
	var definition: EquipmentDefinition = Item.definition_for(item.def_id)

	GameSession.add_hero(hero)
	GameSession.add_item(item)
	GameSession.equip_item(hero, item)
	var saved: Dictionary = GameSession.to_dict()

	GameSession.from_dict(saved)
	var reloaded_hero: Hero = null
	for candidate: Hero in GameSession.roster:
		if candidate.def_id == &"mage" and candidate.hero_name == "Saved Hero" and candidate.rank == 3:
			reloaded_hero = candidate

	assert_not_null(reloaded_hero)
	assert_true(reloaded_hero.equipped.has(definition.slot))
	var reloaded_item: Item = reloaded_hero.equipped[definition.slot]
	assert_eq(reloaded_item.def_id, &"ring")
	assert_eq(reloaded_item.rank, 4)
	assert_false(GameSession.inventory.has(reloaded_item))


func test_legacy_hero_without_equipped_key_loads_empty() -> void:
	var saved_hero := Hero.new("Legacy Hero", 2).to_dict()
	saved_hero.erase("equipped")
	var roster_entries: Array[Dictionary] = [saved_hero]

	GameSession.from_dict({"roster": roster_entries})

	assert_eq(GameSession.roster.size(), 1)
	assert_true(GameSession.roster[0].equipped.is_empty())


func test_equipping_changes_hp_and_team_power_but_ring_is_crit_blind() -> void:
	var definition := _make_definition()
	var balance := BalanceTable.new()
	var hero := Hero.new("Combat Hero", 2)
	var team: Array[Hero] = [hero]
	var definitions: Array[HeroDefinition] = [definition]
	var levels: Array[int] = [5]
	var head := Item.new(&"head", 4)
	var item := Item.new(&"ring", 4)
	var stats_before: Dictionary[StringName, float] = Hero.compute_final_stats(hero, definition, balance, 5)
	var power_before: float = Hero.compute_team_power(team, definitions, levels, balance)

	hero.equipped[EquipmentDefinition.Slot.HEAD] = head
	var stats_with_head: Dictionary[StringName, float] = Hero.compute_final_stats(hero, definition, balance, 5)
	var power_with_head: float = Hero.compute_team_power(team, definitions, levels, balance)
	assert_almost_eq(stats_before[Hero.STAT_HP], 273.0, 0.0001)
	assert_almost_eq(stats_with_head[Hero.STAT_HP], 309.2544, 0.0001)
	assert_almost_eq(power_with_head, power_before + (stats_with_head[Hero.STAT_HP] - stats_before[Hero.STAT_HP]) / 10.0, 0.0001)

	hero.equipped[EquipmentDefinition.Slot.RING] = item
	var stats_with_ring: Dictionary[StringName, float] = Hero.compute_final_stats(hero, definition, balance, 5)
	assert_almost_eq(stats_with_ring[Hero.STAT_CRIT_DMG], stats_before[Hero.STAT_CRIT_DMG] + 0.0498, 0.0001)
	assert_almost_eq(Hero.compute_team_power(team, definitions, levels, balance), power_with_head, 0.0001)


func test_same_stat_equipment_sums_before_multiplying() -> void:
	var definition := _make_definition()
	var balance := BalanceTable.new()
	var hero := Hero.new("Stacked Hero", 2)
	hero.equipped[EquipmentDefinition.Slot.HEAD] = Item.new(&"head", 4)
	hero.equipped[EquipmentDefinition.Slot.LEGS] = Item.new(&"legs", 4)

	var stats: Dictionary[StringName, float] = Hero.compute_final_stats(hero, definition, balance, 5)
	assert_almost_eq(stats[Hero.STAT_HP], 273.0 * (1.0 + 0.1328 + 0.1328), 0.0001)


func test_crit_rate_is_capped_by_equipped_necklace() -> void:
	var definition := _make_definition()
	definition.crit_rate = 0.7
	var hero := Hero.new("Capped Hero", 2)
	hero.equipped[EquipmentDefinition.Slot.NECKLACE] = Item.new(&"necklace", 7)

	var stats: Dictionary[StringName, float] = Hero.compute_final_stats(hero, definition, BalanceTable.new(), 5)
	assert_almost_eq(stats[Hero.STAT_CRIT_RATE], 0.75, 0.0001)


func test_full_same_rank_gear_scales_team_power() -> void:
	var definition := _make_definition()
	var balance := BalanceTable.new()
	var hero := Hero.new("Fully Equipped Hero", 2)
	var team: Array[Hero] = [hero]
	var definitions: Array[HeroDefinition] = [definition]
	var levels: Array[int] = [5]
	var power_before: float = Hero.compute_team_power(team, definitions, levels, balance)
	for def_id: StringName in [&"head", &"chest", &"legs", &"gloves", &"boots", &"main_hand", &"off_hand", &"necklace", &"ring", &"belt"]:
		var equipment_definition: EquipmentDefinition = Item.definition_for(def_id)
		hero.equipped[equipment_definition.slot] = Item.new(def_id, 4)

	var expected_multiplier: float = 1.0 + 2.0 * balance.equip_pct_per_rank[4]
	assert_almost_eq(Hero.compute_team_power(team, definitions, levels, balance), power_before * expected_multiplier, 0.0001)


func test_equipped_item_round_trip_keeps_geared_stats() -> void:
	var definition := _make_definition()
	var balance := BalanceTable.new()
	var hero := Hero.new("Geared Saved Hero", 2)
	hero.def_id = &"mage"
	var item := Item.new(&"head", 4)

	GameSession.add_hero(hero)
	GameSession.add_item(item)
	GameSession.equip_item(hero, item)
	GameSession.from_dict(GameSession.to_dict())

	var reloaded_hero: Hero = GameSession.roster[0]
	var stats: Dictionary[StringName, float] = Hero.compute_final_stats(reloaded_hero, definition, balance, 5)
	assert_almost_eq(stats[Hero.STAT_HP], 309.2544, 0.0001)


func _count_item(hero: Hero, item: Item) -> int:
	var count: int = _count_inventory_item(item)
	for equipped_item: Item in hero.equipped.values():
		if equipped_item == item:
			count += 1
	return count


func _count_inventory_item(item: Item) -> int:
	var count: int = 0
	for inventory_item: Item in GameSession.inventory:
		if inventory_item == item:
			count += 1
	return count


func _make_definition() -> HeroDefinition:
	var definition := HeroDefinition.new()
	definition.base_hp = 100.0
	definition.hp_growth = 10.0
	definition.base_atk = 20.0
	definition.atk_growth = 2.0
	definition.base_def = 10.0
	definition.def_growth = 1.0
	definition.base_spd = 80.0
	definition.spd_growth = 3.0
	definition.crit_rate = 0.15
	definition.crit_dmg = 1.8
	return definition
