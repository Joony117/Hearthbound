extends GutTest

const ERROR_MARGIN: float = 0.0001


func test_level_for_clamps_level_and_corrupt_rank() -> void:
	var balance := BalanceTable.new()
	var hero := Hero.new("Test Hero")
	hero.level = 5
	for rank: int in balance.level_caps.size():
		hero.rank = rank
		assert_eq(Hero.level_for(hero, balance), 5)
	hero.level = 999
	hero.rank = balance.level_caps.size()
	assert_eq(Hero.level_for(hero, balance), balance.level_caps.back())
	hero.level = -1
	hero.rank = -1
	assert_eq(Hero.level_for(hero, balance), 0)


func test_grant_xp_levels_repeatedly_and_discards_cap_overflow() -> void:
	var balance := BalanceTable.new()
	var hero := Hero.new("Test Hero")

	assert_eq(Hero.xp_to_next_level(0, balance), 10)
	assert_eq(Hero.xp_to_next_level(3, balance), 40)
	Hero.grant_xp(hero, 65, balance)
	assert_eq(hero.level, 3)
	assert_eq(hero.xp, 5)

	hero.level = 9
	hero.xp = 0
	Hero.grant_xp(hero, 200, balance)
	assert_eq(hero.level, 10)
	assert_eq(hero.xp, 0)
	Hero.grant_xp(hero, 50, balance)
	assert_eq(hero.xp, 0)

	hero.rank = 1
	Hero.grant_xp(hero, 50, balance)
	assert_eq(hero.level, 10)
	assert_eq(hero.xp, 50)


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


## ig-vl1.3: a nonzero offset drives the multiplier (the shipped one is 0, pinned below).
func test_a_caster_gets_hp_atk_def_times_the_offset_and_a_knight_does_not() -> void:
	var balance := BalanceTable.new()
	balance.caster_rank_offset = 1.5
	var scale: float = pow(balance.stat_multipliers[1], balance.caster_rank_offset)
	for def_id: String in ["mage", "cleric"]:
		var definition := load("res://heroes/defs/%s.tres" % def_id) as HeroDefinition
		assert_true(definition.caster, def_id)
		var plain := definition.duplicate() as HeroDefinition
		plain.caster = false
		var hero := Hero.new("Caster", 0)
		var stats := Hero.compute_final_stats(hero, definition, balance, 10)
		var base := Hero.compute_final_stats(hero, plain, balance, 10)
		assert_almost_eq(stats[Hero.STAT_HP], (definition.base_hp + definition.hp_growth * 10) * scale, ERROR_MARGIN, def_id)
		for stat: StringName in [Hero.STAT_HP, Hero.STAT_ATK, Hero.STAT_DEF]:
			assert_almost_eq(stats[stat], base[stat] * scale, ERROR_MARGIN, "%s %s" % [def_id, stat])
		for stat: StringName in [Hero.STAT_SPD, Hero.STAT_CRIT_RATE, Hero.STAT_CRIT_DMG]:
			assert_eq(stats[stat], base[stat], "%s %s" % [def_id, stat])
	var knight := load("res://heroes/defs/knight.tres") as HeroDefinition
	assert_false(knight.caster, "knight")
	var knight_stats := Hero.compute_final_stats(Hero.new("Knight", 0), knight, balance, 10)
	assert_eq(knight_stats[Hero.STAT_HP], knight.base_hp + knight.hp_growth * 10, "knight HP")
	assert_eq(knight_stats[Hero.STAT_ATK], knight.base_atk + knight.atk_growth * 10, "knight ATK")


## ig-vl1.3 ruling: casters ship with no stat bonus (the presence test found none that fits), so a
## caster's stats are exactly its plain definition's.
func test_the_shipped_caster_offset_is_zero_and_changes_nothing() -> void:
	var balance := load("res://balance.tres") as BalanceTable
	assert_eq(balance.caster_rank_offset, 0.0)
	var definition := load("res://heroes/defs/mage.tres") as HeroDefinition
	var plain := definition.duplicate() as HeroDefinition
	plain.caster = false
	var hero := Hero.new("Mage", 2)
	assert_eq(Hero.compute_final_stats(hero, definition, balance, 30), Hero.compute_final_stats(hero, plain, balance, 30))


func test_team_power_sums_two_heroes() -> void:
	var balance := BalanceTable.new()
	var first := Hero.new("First", 0)
	var second := Hero.new("Second", 3)
	var knight := load("res://heroes/defs/knight.tres") as HeroDefinition
	var mage := load("res://heroes/defs/mage.tres") as HeroDefinition
	var team: Array[Hero] = [first, second]
	var definitions: Array[HeroDefinition] = [knight, mage]
	var levels: Array[int] = [1, 4]

	# Knight 152.6; the B Mage's SPD 99.8 x 2.46, and its ATK + DEF + HP/10 (71.2 x 2.46) x the caster scale.
	assert_almost_eq(
		Hero.compute_team_power(team, definitions, levels, balance),
		152.6 + 99.8 * 2.46 + 71.2 * 2.46 * pow(balance.stat_multipliers[1], balance.caster_rank_offset),
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
