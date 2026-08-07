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


func test_compute_rank_up_cost_looks_up_current_rank() -> void:
	var balance := BalanceTable.new()
	var hero := Hero.new("Target", 3)

	assert_eq(Hero.compute_rank_up_cost(hero, balance), 800)
