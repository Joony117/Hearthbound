extends GutTest

const BALANCE: BalanceTable = preload("res://balance.tres")


func test_passions_are_two_different_known_professions_stable_per_instance_id() -> void:
	var hero := Hero.new("Born", 0)
	assert_eq(hero.passions.size(), 2)
	assert_ne(hero.passions[0], hero.passions[1])
	for passion: StringName in hero.passions:
		assert_true(Hero.ALL_PROFESSIONS.has(passion), str(passion))
	assert_eq(Hero.passions_for(hero.instance_id), hero.passions)
	assert_eq(Hero.passions_for(hero.instance_id), Hero.passions_for(hero.instance_id))


# Golden values: String.hash() must give the same passions on every run and machine, or a legacy
# hero with no saved passions would change them on each load.
func test_the_roll_is_the_same_on_every_run() -> void:
	assert_eq(Hero.passions_for("0123456789abcdef0123456789abcdef"), [&"rites", &"smithing"] as Array[StringName])
	assert_eq(Hero.passions_for("ffffffffffffffffffffffffffffffff"), [&"woodcutting", &"smithing"] as Array[StringName])


func test_the_eight_professions_keep_their_order_and_the_halls_stay_five() -> void:
	assert_eq(Hero.ALL_PROFESSIONS, [&"smithing", &"rites", &"drill", &"tracking", &"alchemy", &"woodcutting", &"mining", &"farming"] as Array[StringName])
	assert_eq(Hero.PROFESSIONS.keys(), Hero.ALL_PROFESSIONS.slice(0, 5))


func test_passions_are_always_distinct_and_spread_evenly_over_a_thousand_heroes() -> void:
	var counts: Dictionary = {}
	for profession: StringName in Hero.ALL_PROFESSIONS:
		counts[profession] = 0
	for index: int in 1000:
		var passions: Array[StringName] = Hero.new("", 0).passions
		assert_ne(passions[0], passions[1])
		for passion: StringName in passions:
			counts[passion] += 1
	# Each profession is one of two passions for 1 hero in 4: about 250 of 1000.
	for profession: StringName in counts:
		assert_between(counts[profession] as int, 180, 320, "%s share" % profession)


func test_a_new_hero_draws_nothing_from_the_summon_rng() -> void:
	seed(4242)
	var expected: Array[int] = [randi(), randi(), randi()]
	seed(4242)
	for index: int in 10:
		Hero.new("Rolled", 0)
	assert_eq([randi(), randi(), randi()] as Array[int], expected)


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


func test_work_in_either_passion_earns_four_times_the_xp() -> void:
	var hero := _hero_with_passions(&"smithing", &"alchemy")
	for profession: StringName in [&"smithing", &"alchemy", &"rites"]:
		Hero.add_profession_xp(hero, profession, 60.0, BALANCE)
	assert_eq(BALANCE.passion_xp_multiplier, 4.0, "balance.tres carries the renamed row, not the script default")
	assert_eq(hero.profession_xp[&"smithing"], 240.0)
	assert_eq(hero.profession_xp[&"alchemy"], 240.0)
	assert_eq(hero.profession_xp[&"rites"], 60.0)


func test_bad_work_seconds_are_refused_so_nan_never_reaches_the_save() -> void:
	var hero := Hero.new("Worker", 0)
	Hero.add_profession_xp(hero, hero.passions[0], NAN, BALANCE)
	Hero.add_profession_xp(hero, hero.passions[0], INF, BALANCE)
	Hero.add_profession_xp(hero, hero.passions[0], -5.0, BALANCE)
	for i in 3:
		assert_push_error("bad work_seconds")
	assert_false(hero.profession_xp.has(hero.passions[0]))


func test_a_master_needs_a_passion_and_skill_5_and_both_passions_can_be_mastered() -> void:
	var hero := _hero_with_passions(&"rites", &"drill")
	hero.profession_xp[&"rites"] = 299.0 * 60.0
	assert_false(Hero.is_profession_master(hero, &"rites", BALANCE), "passion at skill 4")
	for profession: StringName in [&"rites", &"drill", &"smithing"]:
		hero.profession_xp[profession] = 300.0 * 60.0
	assert_true(Hero.is_profession_master(hero, &"rites", BALANCE), "first passion at skill 5")
	assert_true(Hero.is_profession_master(hero, &"drill", BALANCE), "second passion at skill 5")
	assert_eq(Hero.profession_skill(hero, &"smithing", BALANCE), 5)
	assert_false(Hero.is_profession_master(hero, &"smithing", BALANCE), "skill 5 without the passion")


func test_professions_do_not_touch_combat_stats() -> void:
	var plain := Hero.new("Twin", 3)
	plain.def_id = &"knight"
	var skilled := Hero.from_dict(plain.to_dict())
	skilled.passions = [&"drill", &"mining"]
	skilled.profession_xp[&"drill"] = 300.0 * 60.0
	var definition: HeroDefinition = Hero.definition_for(plain.def_id)
	assert_eq(Hero.compute_final_stats(skilled, definition, BALANCE, 10), Hero.compute_final_stats(plain, definition, BALANCE, 10))


func test_passions_and_xp_survive_to_dict_and_back() -> void:
	var hero := _hero_with_passions(&"farming", &"tracking")
	hero.profession_xp = {&"alchemy": 1234.5, &"rites": 60.0}
	var data: Dictionary = hero.to_dict()
	assert_eq(data["passions"], ["farming", "tracking"])
	assert_false(data.has("calling"), "the old key is no longer written")
	var reloaded := Hero.from_dict(data)
	assert_eq(reloaded.passions, [&"farming", &"tracking"] as Array[StringName])
	assert_eq(reloaded.profession_xp, hero.profession_xp)


func test_a_legacy_calling_becomes_the_first_passion() -> void:
	var data: Dictionary = Hero.new("Old", 0).to_dict()
	data.erase("passions")
	data["calling"] = "alchemy"
	var reloaded := Hero.from_dict(data)
	assert_eq(reloaded.passions[0], &"alchemy")
	assert_ne(reloaded.passions[1], &"alchemy")
	assert_eq(reloaded.passions[1], Hero._second_passion(data["instance_id"], &"alchemy"))
	assert_eq(Hero.from_dict(data).passions, reloaded.passions, "the same on every load")
	assert_push_warning_count(0)


func test_a_hero_with_neither_key_derives_both_passions_and_keeps_them() -> void:
	var data: Dictionary = Hero.new("Older", 0).to_dict()
	data.erase("passions")
	data.erase("profession_xp")
	var reloaded := Hero.from_dict(data)
	assert_eq(reloaded.passions, Hero.passions_for(data["instance_id"]))
	assert_true(reloaded.profession_xp.is_empty())
	assert_eq(Hero.from_dict(reloaded.to_dict()).passions, reloaded.passions)
	assert_push_warning_count(0)
	assert_push_error_count(0)


func test_an_unknown_calling_warns_and_derives() -> void:
	var data: Dictionary = Hero.new("Odd", 0).to_dict()
	data.erase("passions")
	data["calling"] = "juggling"
	var reloaded := Hero.from_dict(data)
	assert_push_warning("Unknown hero calling 'juggling'")
	assert_eq(reloaded.passions, Hero.passions_for(data["instance_id"]))


func test_invalid_passions_warn_and_re_derive() -> void:
	var data: Dictionary = Hero.new("Odd", 0).to_dict()
	# A stale "calling" next to them is ignored: the calling counts only when "passions" is absent.
	data["calling"] = "tracking"
	for bad: Variant in [["rites", "rites"], ["rites"], ["rites", "juggling"], ["rites", 3], "rites", ["rites", "drill", "mining"], null]:
		data["passions"] = bad
		assert_eq(Hero.from_dict(data).passions, Hero.passions_for(data["instance_id"]), str(bad))
		assert_push_warning("Invalid hero passions")


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


func _hero_with_passions(first: StringName, second: StringName) -> Hero:
	var hero := Hero.new("Passionate", 0)
	hero.passions = [first, second]
	return hero
