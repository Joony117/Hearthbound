extends GutTest

const BALANCE: BalanceTable = preload("res://balance.tres")


func test_the_calling_is_stable_per_instance_id_and_always_one_of_the_five() -> void:
	var hero := Hero.new("Born", 0)
	assert_true(Hero.PROFESSIONS.has(hero.calling))
	assert_eq(Hero.calling_for(hero.instance_id), hero.calling)
	assert_eq(Hero.calling_for(hero.instance_id), Hero.calling_for(hero.instance_id))


func test_callings_spread_evenly_over_a_thousand_heroes() -> void:
	var counts: Dictionary = {}
	for profession: StringName in Hero.PROFESSIONS:
		counts[profession] = 0
	for index: int in 1000:
		var calling: StringName = Hero.new("", 0).calling
		counts[calling] += 1
	for profession: StringName in counts:
		assert_between(counts[profession] as int, 150, 250, "%s share" % profession)


func test_skill_steps_at_20_60_120_200_300_xp_minutes_and_stops_at_5() -> void:
	var hero := Hero.new("Learner", 0)
	var steps: Array[float] = [20.0, 60.0, 120.0, 200.0, 300.0]
	assert_eq(Hero.profession_skill(hero, &"smithing", BALANCE), 0, "no XP")
	for level: int in steps.size():
		hero.profession_xp[&"smithing"] = steps[level] * 60.0 - 1.0
		assert_eq(Hero.profession_skill(hero, &"smithing", BALANCE), level, "just under %s min" % steps[level])
		hero.profession_xp[&"smithing"] = steps[level] * 60.0
		assert_eq(Hero.profession_skill(hero, &"smithing", BALANCE), level + 1, "at %s min" % steps[level])
	hero.profession_xp[&"smithing"] = 100000.0 * 60.0
	assert_eq(Hero.profession_skill(hero, &"smithing", BALANCE), 5, "capped")


func test_work_in_the_calling_earns_four_times_the_xp() -> void:
	var hero := Hero.new("Worker", 0)
	var other: StringName = _other_profession(hero)
	Hero.add_profession_xp(hero, hero.calling, 60.0, BALANCE)
	Hero.add_profession_xp(hero, other, 60.0, BALANCE)
	assert_eq(hero.profession_xp[hero.calling], 240.0)
	assert_eq(hero.profession_xp[other], 60.0)


func test_bad_work_seconds_are_refused_so_nan_never_reaches_the_save() -> void:
	var hero := Hero.new("Worker", 0)
	Hero.add_profession_xp(hero, hero.calling, NAN, BALANCE)
	Hero.add_profession_xp(hero, hero.calling, INF, BALANCE)
	Hero.add_profession_xp(hero, hero.calling, -5.0, BALANCE)
	for i in 3:
		assert_push_error("bad work_seconds")
	assert_false(hero.profession_xp.has(hero.calling))


func test_only_the_calling_at_skill_5_is_a_master() -> void:
	var hero := Hero.new("Master", 0)
	var other: StringName = _other_profession(hero)
	hero.profession_xp[hero.calling] = 299.0 * 60.0
	assert_false(Hero.is_profession_master(hero, hero.calling, BALANCE), "calling at skill 4")
	hero.profession_xp[hero.calling] = 300.0 * 60.0
	hero.profession_xp[other] = 300.0 * 60.0
	assert_true(Hero.is_profession_master(hero, hero.calling, BALANCE), "calling at skill 5")
	assert_eq(Hero.profession_skill(hero, other, BALANCE), 5)
	assert_false(Hero.is_profession_master(hero, other, BALANCE), "skill 5 outside the calling")


func test_professions_do_not_touch_combat_stats() -> void:
	var plain := Hero.new("Twin", 3)
	plain.def_id = &"knight"
	var skilled := Hero.from_dict(plain.to_dict())
	skilled.calling = _other_profession(plain)
	skilled.profession_xp[&"drill"] = 300.0 * 60.0
	var definition: HeroDefinition = Hero.definition_for(plain.def_id)
	assert_eq(Hero.compute_final_stats(skilled, definition, BALANCE, 10), Hero.compute_final_stats(plain, definition, BALANCE, 10))


func test_calling_and_xp_survive_to_dict_and_back() -> void:
	var hero := Hero.new("Keeper", 0)
	var calling: StringName = _other_profession(hero)
	hero.calling = calling
	hero.profession_xp = {&"alchemy": 1234.5, &"rites": 60.0}
	var reloaded := Hero.from_dict(hero.to_dict())
	assert_eq(reloaded.calling, calling)
	assert_eq(reloaded.profession_xp, hero.profession_xp)


func test_a_legacy_hero_derives_its_calling_with_no_xp_and_keeps_it() -> void:
	var data: Dictionary = Hero.new("Old", 0).to_dict()
	data.erase("calling")
	data.erase("profession_xp")
	var reloaded := Hero.from_dict(data)
	assert_eq(reloaded.calling, Hero.calling_for(data["instance_id"]))
	assert_true(reloaded.profession_xp.is_empty())
	assert_eq(Hero.from_dict(reloaded.to_dict()).calling, reloaded.calling)
	assert_push_warning_count(0)
	assert_push_error_count(0)


func test_an_unknown_calling_warns_and_derives() -> void:
	var data: Dictionary = Hero.new("Odd", 0).to_dict()
	data["calling"] = "juggling"
	var reloaded := Hero.from_dict(data)
	assert_push_warning("Unknown hero calling 'juggling'")
	assert_eq(reloaded.calling, Hero.calling_for(data["instance_id"]))


func test_bad_profession_xp_warns_or_errors_without_loading_garbage() -> void:
	var data: Dictionary = Hero.new("Bad", 0).to_dict()
	data["profession_xp"] = {"juggling": 10.0, "smithing": -5.0, "rites": "lots", "drill": 30}
	var reloaded := Hero.from_dict(data)
	assert_push_warning("Unknown profession 'juggling'")
	assert_push_error("Invalid smithing XP")
	assert_push_error("Invalid rites XP")
	assert_eq(reloaded.profession_xp, {&"smithing": 0.0, &"rites": 0.0, &"drill": 30.0})

	data["profession_xp"] = [1, 2]
	assert_true(Hero.from_dict(data).profession_xp.is_empty())
	assert_push_error("Invalid hero profession_xp")


func _other_profession(hero: Hero) -> StringName:
	for profession: StringName in Hero.PROFESSIONS:
		if profession != hero.calling:
			return profession
	return &""
