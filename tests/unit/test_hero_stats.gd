extends GutTest

const ERROR_MARGIN: float = 0.0001


func test_rank_and_level_scale_combat_stats_but_not_crit() -> void:
	var definition := _make_definition()
	var balance := BalanceTable.new()
	var hero := Hero.new("Test Hero", 0)
	var low_stats := Hero.compute_final_stats(hero, definition, balance, 1)

	hero.rank = 3
	var high_stats := Hero.compute_final_stats(hero, definition, balance, 4)

	assert_eq(low_stats.size(), 6)
	assert_eq(high_stats.size(), 6)
	assert_almost_eq(low_stats[Hero.STAT_HP], 110.0, ERROR_MARGIN)
	assert_almost_eq(low_stats[Hero.STAT_ATK], 22.0, ERROR_MARGIN)
	assert_almost_eq(low_stats[Hero.STAT_DEF], 11.0, ERROR_MARGIN)
	assert_almost_eq(low_stats[Hero.STAT_SPD], 83.0, ERROR_MARGIN)
	assert_almost_eq(high_stats[Hero.STAT_HP], 344.4, ERROR_MARGIN)
	assert_almost_eq(high_stats[Hero.STAT_ATK], 68.88, ERROR_MARGIN)
	assert_almost_eq(high_stats[Hero.STAT_DEF], 34.44, ERROR_MARGIN)
	assert_almost_eq(high_stats[Hero.STAT_SPD], 226.32, ERROR_MARGIN)
	assert_eq(low_stats[Hero.STAT_CRIT_RATE], definition.crit_rate)
	assert_eq(low_stats[Hero.STAT_CRIT_DMG], definition.crit_dmg)
	assert_eq(high_stats[Hero.STAT_CRIT_RATE], definition.crit_rate)
	assert_eq(high_stats[Hero.STAT_CRIT_DMG], definition.crit_dmg)


func test_rank_zero_level_zero_uses_definition_base_stats() -> void:
	var definition := _make_definition()
	var balance := BalanceTable.new()
	var hero := Hero.new("Baseline Hero", 0)
	var stats := Hero.compute_final_stats(hero, definition, balance, 0)

	assert_eq(stats[Hero.STAT_HP], definition.base_hp)
	assert_eq(stats[Hero.STAT_ATK], definition.base_atk)
	assert_eq(stats[Hero.STAT_DEF], definition.base_def)
	assert_eq(stats[Hero.STAT_SPD], definition.base_spd)
	assert_eq(stats[Hero.STAT_CRIT_RATE], definition.crit_rate)
	assert_eq(stats[Hero.STAT_CRIT_DMG], definition.crit_dmg)


func test_team_power_sums_two_heroes() -> void:
	var balance := BalanceTable.new()
	var first := Hero.new("First", 0)
	var second := Hero.new("Second", 3)
	var knight := load("res://heroes/defs/knight.tres") as HeroDefinition
	var mage := load("res://heroes/defs/mage.tres") as HeroDefinition
	var team: Array[Hero] = [first, second]
	var definitions: Array[HeroDefinition] = [knight, mage]
	var levels: Array[int] = [1, 4]

	assert_almost_eq(
		Hero.compute_team_power(team, definitions, levels, balance),
		573.26,
		ERROR_MARGIN,
	)


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
