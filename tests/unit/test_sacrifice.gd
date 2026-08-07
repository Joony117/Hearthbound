extends GutTest


func test_compute_essence_yield_handles_dupes_and_non_dupes() -> void:
	var balance := BalanceTable.new()
	var fodder := Hero.new("Fodder", 2)
	var target := Hero.new("Target", 0)
	fodder.def_id = &"rogue"
	target.def_id = &"mage"

	assert_eq(Hero.compute_essence_yield(fodder, target, balance, 0), 65)
	target.def_id = &"rogue"
	assert_eq(Hero.compute_essence_yield(fodder, target, balance, 0), 195)
	fodder.def_id = Hero.NO_ARCHETYPE_DEF_ID
	target.def_id = Hero.NO_ARCHETYPE_DEF_ID
	assert_eq(Hero.compute_essence_yield(fodder, target, balance, 0), 65)


func test_compute_essence_yield_applies_sanctum_bonus_once_after_dupe_multiplier() -> void:
	var balance := BalanceTable.new()
	var fodder := Hero.new("Fodder", 2)
	var target := Hero.new("Target", 0)
	fodder.def_id = &"rogue"
	target.def_id = &"rogue"

	assert_eq(Hero.compute_essence_yield(fodder, target, balance, 1), 215)


func test_compute_essence_yield_scales_with_fodder_level() -> void:
	var balance := BalanceTable.new()
	var fodder := Hero.new("Fodder", 2)
	var target := Hero.new("Target", 0)
	fodder.def_id = &"rogue"
	target.def_id = &"mage"

	# C's cap is 30, so half-way up is +50% and the cap is double. Int division would give both 65.
	fodder.level = 15
	assert_eq(Hero.compute_essence_yield(fodder, target, balance, 0), 98)
	fodder.level = 30
	assert_eq(Hero.compute_essence_yield(fodder, target, balance, 0), 130)
	# Above the cap clamps rather than paying out - a corrupt save must not mint essence.
	fodder.level = 999
	assert_eq(Hero.compute_essence_yield(fodder, target, balance, 0), 130)
	# The level term lands inside the dupe multiplier, not after it.
	target.def_id = &"rogue"
	assert_eq(Hero.compute_essence_yield(fodder, target, balance, 0), 390)


func test_compute_rank_up_cost_looks_up_current_rank() -> void:
	var balance := BalanceTable.new()
	var hero := Hero.new("Target", 3)

	assert_eq(Hero.compute_rank_up_cost(hero, balance), 800)
