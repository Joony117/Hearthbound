extends GutTest


func test_active_resonance_traits_unlock_in_order() -> void:
	var balance := BalanceTable.new()
	var hero := Hero.new("Knight", 0)
	var definition := _definition("res://heroes/defs/knight.tres")
	var expected_counts: Array[int] = [0, 1, 1, 2, 2, 3, 3]
	var resonances: Array[int] = [0, 1, 2, 3, 5, 6, 99]

	for index: int in resonances.size():
		hero.resonance = resonances[index]
		var active: Array[TraitDefinition] = Hero.active_resonance_traits(hero, definition, balance)
		assert_eq(active.size(), expected_counts[index])
		for trait_index: int in active.size():
			assert_eq(active[trait_index].id, definition.resonance_trait_pool[trait_index].id)


func test_active_resonance_traits_accumulate() -> void:
	var balance := BalanceTable.new()
	var hero := Hero.new("Knight", 0)
	var definition := _definition("res://heroes/defs/knight.tres")
	hero.resonance = 6

	var active: Array[TraitDefinition] = Hero.active_resonance_traits(hero, definition, balance)
	assert_eq(active[0].id, &"knight_bulwark")
	assert_eq(active[1].id, &"knight_stalwart")
	assert_eq(active[2].id, &"knight_iron_wall")


func test_archetype_trait_pools_load_from_disk() -> void:
	_assert_pool("res://heroes/defs/knight.tres", [&"knight_bulwark", &"knight_stalwart", &"knight_iron_wall"], [2, 0, 2], [0.04, 0.05, 0.08])
	_assert_pool("res://heroes/defs/rogue.tres", [&"rogue_opening_strike", &"rogue_killer_instinct", &"rogue_executioner"], [4, 1, 5], [0.015, 0.05, 0.08])
	_assert_pool("res://heroes/defs/ranger.tres", [&"ranger_quickdraw", &"ranger_marksman", &"ranger_deadeye"], [3, 1, 4], [0.04, 0.05, 0.015])
	_assert_pool("res://heroes/defs/mage.tres", [&"mage_arcane_focus", &"mage_overload", &"mage_archmage"], [1, 5, 1], [0.05, 0.06, 0.06])
	_assert_pool("res://heroes/defs/cleric.tres", [&"cleric_devotion", &"cleric_sanctuary", &"cleric_guardian_light"], [0, 2, 0], [0.05, 0.04, 0.06])


func test_zero_resonance_matches_a_definition_without_traits() -> void:
	var balance: BalanceTable = BalanceTable.new()
	var hero: Hero = Hero.new("Knight", 0)
	var definition: HeroDefinition = _definition("res://heroes/defs/knight.tres")
	var no_path_definition: HeroDefinition = definition.duplicate() as HeroDefinition
	no_path_definition.resonance_trait_pool = []

	var stats: Dictionary[StringName, float] = Hero.compute_final_stats(hero, definition, balance, 5)
	var no_path_stats: Dictionary[StringName, float] = Hero.compute_final_stats(hero, no_path_definition, balance, 5)
	for stat: StringName in Hero.STAT_NAMES:
		assert_almost_eq(stats[stat], no_path_stats[stat], 0.0001)


func test_non_crit_traits_sum_with_gear_before_multiplying() -> void:
	var balance: BalanceTable = BalanceTable.new()
	var hero: Hero = Hero.new("Knight", 0)
	var definition: HeroDefinition = _definition("res://heroes/defs/knight.tres")
	hero.resonance = 6
	hero.equipped[EquipmentDefinition.Slot.CHEST] = Item.new(&"chest", 4)

	var stats: Dictionary[StringName, float] = Hero.compute_final_stats(hero, definition, balance, 0)
	assert_almost_eq(stats[Hero.STAT_DEF], definition.base_def * (1.0 + 0.1328 + 0.04 + 0.08), 0.0001)
	assert_almost_eq(stats[Hero.STAT_HP], definition.base_hp * 1.05, 0.0001)
	assert_almost_eq(stats[Hero.STAT_ATK], definition.base_atk, 0.0001)
	assert_almost_eq(stats[Hero.STAT_SPD], definition.base_spd, 0.0001)


func test_crit_traits_add_flat_and_atk_trait_multiplies() -> void:
	var balance: BalanceTable = BalanceTable.new()
	var hero: Hero = Hero.new("Rogue", 0)
	var definition: HeroDefinition = _definition("res://heroes/defs/rogue.tres")
	hero.resonance = 6

	var stats: Dictionary[StringName, float] = Hero.compute_final_stats(hero, definition, balance, 0)
	assert_almost_eq(stats[Hero.STAT_CRIT_RATE], definition.crit_rate + 0.015, 0.0001)
	assert_almost_eq(stats[Hero.STAT_CRIT_DMG], definition.crit_dmg + 0.08, 0.0001)
	assert_almost_eq(stats[Hero.STAT_ATK], definition.base_atk * 1.05, 0.0001)


func test_crit_rate_trait_is_capped() -> void:
	var balance: BalanceTable = BalanceTable.new()
	var hero: Hero = Hero.new("Rogue", 0)
	hero.resonance = 6
	var definition: HeroDefinition = _definition("res://heroes/defs/rogue.tres").duplicate() as HeroDefinition
	definition.crit_rate = 0.745

	var stats: Dictionary[StringName, float] = Hero.compute_final_stats(hero, definition, balance, 0)
	assert_almost_eq(stats[Hero.STAT_CRIT_RATE], balance.equip_crit_rate_cap, 0.0001)


func _assert_pool(path: String, ids: Array[StringName], stats: Array[int], magnitudes: Array[float]) -> void:
	var definition := _definition(path)
	assert_eq(definition.resonance_trait_pool.size(), 3)
	assert_true(definition.instructor_trait_pool.is_empty())
	for index: int in ids.size():
		var trait_definition: TraitDefinition = definition.resonance_trait_pool[index]
		assert_eq(trait_definition.id, ids[index])
		assert_eq(trait_definition.stat, stats[index])
		assert_eq(trait_definition.magnitude, magnitudes[index])


func _definition(path: String) -> HeroDefinition:
	var definition: HeroDefinition = load(path) as HeroDefinition
	assert_not_null(definition)
	return definition
