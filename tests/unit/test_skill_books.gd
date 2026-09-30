extends GutTest

# ig-gy0.7: skills are also learned from skill books and the Training Hall (GAME_SPEC.md § Skills, "Learning";
# SYSTEMS.md § Skills, Learning). Boundary #1: skill_books and the report's "books" ride the save; #4: the
# Field Dressing guard is in the sim, so both resolve paths get it.

const BALANCE: BalanceTable = preload("res://balance.tres")
const SIM = preload("res://combat/battle/battle_simulation.gd")
const GENERAL: Array[String] = ["general_catch_breath", "general_field_dressing", "general_tumble", "general_brace", "general_disrupt", "general_hearten"]

var _verdant_chance: float = 0.0
## Held, so the resource cache keeps the one instance the settlement reads: an unreferenced resource is freed
## and the next load is a fresh copy of the file.
var _zone: ZoneDefinition


func before_each() -> void:
	GameSession.set_process(false)
	GameSession.set("_save_deferred_depth", 1)
	GameSession.from_dict({"roster": []})
	GameSession.set("_save_deferred_depth", 0)
	GameSession.last_action_error = ""
	SaveService.load_blocked = false
	SaveService.load_block_reason = ""
	_zone = ZoneDefinition.definition_for(&"verdant_outskirts")
	_verdant_chance = _zone.skill_book_drop_chance


func after_each() -> void:
	_verdant().skill_book_drop_chance = _verdant_chance
	SaveService.load_blocked = false
	GameSession.set_process(true)


## ---- the spine

func test_the_book_roll_changes_no_stone_or_item_for_a_seed() -> void:
	var off: Dictionary = _settle(0.0, 777)
	var on: Dictionary = _settle(1.0, 777)
	assert_eq(off["books"], [], "chance 0: no book")
	assert_eq((on["books"] as Array).size(), 6, "chance 1 at pace 6: a book per loot roll")
	assert_eq(on["stones"], off["stones"], "the stones")
	assert_gt((off["items"] as Array).size(), 0)
	assert_eq(on["items"], off["items"], "the dropped Items, def_id and rank")


func test_learning_skills_leaves_the_essence_yield_alone() -> void:
	var fodder: Hero = _hero("knight", 10, "hero:f")
	var target: Hero = _hero("knight", 10, "hero:t")
	var before: int = Hero.compute_essence_yield(fodder, target, BALANCE, 2, 1)
	GameSession.building_levels[2] = 3
	GameSession.parts[0] = 500
	GameSession.skill_books["general_brace"] = 1
	assert_true(GameSession.teach_skill(fodder, "knight_gauntlet_toss"), GameSession.last_action_error)
	assert_true(GameSession.teach_skill(fodder, "general_catch_breath"), GameSession.last_action_error)
	assert_true(GameSession.use_skill_book(fodder, "general_brace"), GameSession.last_action_error)
	assert_eq(fodder.learned_skills.size(), 3)
	assert_eq(Hero.compute_essence_yield(fodder, target, BALANCE, 2, 1), before)


func test_the_level_helper_counts_level_zero_as_one() -> void:
	assert_eq(Hero.skill_level(-3), 1)
	assert_eq(Hero.skill_level(0), 1)
	assert_eq(Hero.skill_level(7), 7)


## ---- the drop

func test_roll_book_is_deterministic_and_a_zero_chance_zone_never_drops() -> void:
	var zone: ZoneDefinition = _zone_with(1.0)
	var roster: Array[String] = ["knight", "mage"]
	var ids: Dictionary = {}
	for roll: int in 50:
		var first: String = Expedition.roll_book(zone, BALANCE, 4242, roll, roster)
		assert_eq(Expedition.roll_book(zone, BALANCE, 4242, roll, roster), first, "roll %d" % roll)
		ids[first] = true
	assert_gt(ids.size(), 1, "the seeds differ by roll")
	var none: ZoneDefinition = _zone_with(0.0)
	var dropped: int = 0
	for roll: int in 2000:
		if not Expedition.roll_book(none, BALANCE, 4242 + roll, roll % 6, roster).is_empty():
			dropped += 1
	assert_eq(dropped, 0, "a chance-0 zone never drops")


func test_a_roster_with_no_class_book_gets_a_general_book() -> void:
	var zone: ZoneDefinition = _zone_with(1.0)
	var strays: int = 0
	var none: Array[String] = []
	var unknown: Array[String] = ["nobody"]
	for archetypes: Array[String] in [none, unknown]:
		for roll: int in 100:
			if not Expedition.roll_book(zone, BALANCE, 7, roll, archetypes) in GENERAL:
				strays += 1
	assert_eq(strays, 0, "no class on the roster has a book: every drop is a general one")


func test_book_roll_i_is_seeded_from_the_run_seed_and_i_alone() -> void:
	var zone: ZoneDefinition = _zone_with(0.5)
	var roster: Array[String] = ["knight"]
	var mismatches: int = 0
	var hits: int = 0
	for roll: int in 400:
		var rng := RandomNumberGenerator.new()
		rng.seed = ("%d:book:%d" % [9, roll]).hash()
		var expected: bool = rng.randf() < 0.5
		var book: String = Expedition.roll_book(zone, BALANCE, 9, roll, roster)
		if expected != not book.is_empty():
			mismatches += 1
		if expected:
			hits += 1
	assert_eq(mismatches, 0, "the first draw of the seeded generator decides the drop")
	assert_between(hits, 150, 250, "about half at chance 0.5")


func test_book_drops_split_half_general_and_go_only_to_the_rosters_classes() -> void:
	var zone: ZoneDefinition = _zone_with(1.0)
	var roster: Array[String] = ["knight", "knight", "knight", "knight", "mage"]
	var general: int = 0
	var seen: Dictionary = {}
	var classes: Dictionary = {"knight": 0, "mage": 0}
	var stray: int = 0
	var total: int = 3000
	for roll: int in total:
		var id: String = Expedition.roll_book(zone, BALANCE, 4242, roll, roster)
		var skill: AbilityDefinition = SIM.ABILITIES.get(id) as AbilityDefinition
		if skill == null:
			stray += 1
		elif skill.archetype == "general":
			general += 1
			seen[id] = true
		elif skill.book_only and classes.has(skill.archetype):
			classes[skill.archetype] += 1
		else:
			stray += 1
	assert_eq(stray, 0, "a book is a general skill or a book-only skill of a roster class")
	assert_almost_eq(float(general) / total, 0.5, 0.05, "the general share")
	for id: String in GENERAL:
		assert_true(seen.has(id), "%s appears" % id)
	var class_total: int = int(classes["knight"]) + int(classes["mage"])
	assert_almost_eq(float(classes["knight"]) / class_total, 0.5, 0.05, "4 Knights and 1 Mage: each archetype counts once")
	assert_almost_eq(float(classes["mage"]) / class_total, 0.5, 0.05)


func test_a_victory_rolls_the_book_once_per_pace_and_a_legacy_battle_once() -> void:
	var expected: Array[String] = []
	for roll: int in 6:
		expected.append(Expedition.roll_book(_zone_with(1.0), BALANCE, 31, roll, ["knight"]))
	var six: Dictionary = _settle(1.0, 31)
	assert_eq(six["books"], expected, "six rolls, in roll order")
	assert_eq(six["items"].size(), 6)
	var legacy: Dictionary = _settle(1.0, 31, 6, true)
	assert_eq(legacy["books"], [expected[0]], "a battle without a pace key rolls once")
	assert_eq(legacy["items"].size(), 1)
	assert_eq(GameSession.skill_books.values().reduce(func(sum: int, count: int) -> int: return sum + count, 0), 1)


func test_two_drops_in_a_victory_add_both_and_a_book_takes_no_route_factor() -> void:
	var short: Dictionary = _settle(1.0, 55, 2, false, 600.0)
	var counts: Dictionary = GameSession.skill_books.duplicate()
	assert_eq((short["books"] as Array).size(), 2)
	var listed: Dictionary = {}
	for id: String in short["books"]:
		listed[id] = int(listed.get(id, 0)) + 1
	assert_eq(counts, listed, "both are in skill_books, and both are in the report")
	var long: Dictionary = _settle(1.0, 55, 2, false, 86400.0)
	assert_eq(long["books"], short["books"], "the route's length changes the stones, not the books")


func test_each_zones_book_chance_is_in_its_file() -> void:
	var chances: Dictionary = {&"verdant_outskirts": 0.02, &"ashfall_reaches": 0.04, &"sundered_vault": 0.06, &"fallen_citadel": 0.08, &"frontier_march": 0.10}
	for zone_id: StringName in chances:
		assert_almost_eq(ZoneDefinition.definition_for(zone_id).skill_book_drop_chance, float(chances[zone_id]), 0.00001, str(zone_id))


## ---- boundary #1: the save

func test_books_and_learned_skills_survive_a_disk_round_trip() -> void:
	var knight: Hero = _hero("knight", 30, "hero:k")
	GameSession.building_levels[2] = 1
	GameSession.parts[0] = 100
	GameSession.skill_books["general_tumble"] = 2
	GameSession.skill_books["knight_anvilheart"] = 1
	assert_true(GameSession.teach_skill(knight, "general_catch_breath"), GameSession.last_action_error)
	assert_true(GameSession.use_skill_book(knight, "knight_anvilheart"), GameSession.last_action_error)
	assert_string_contains(FileAccess.get_file_as_string(SaveService.SAVE_PATH), "skill_books", "saved by the mutator")
	_disk_round_trip()
	assert_eq(GameSession.skill_books.size(), 1)
	assert_eq(GameSession.skill_books.get("general_tumble"), 2)
	var loaded: Hero = GameSession.hero_by_id("hero:k")
	assert_eq(loaded.learned_skills, ["general_catch_breath", "knight_anvilheart"] as Array[String])
	assert_true(SIM.ABILITIES["knight_anvilheart"] in Hero.known_skills(loaded, BALANCE))
	assert_eq(GameSession.parts[0], 100 - BALANCE.training_hall_general_parts[0])
	assert_push_warning_count(0)
	assert_push_error_count(0)


func test_a_save_from_before_books_loads_empty_and_quiet() -> void:
	var knight: Hero = _hero("knight", 30, "hero:k")
	knight.learned_skills.append("general_brace")
	GameSession.skill_books["general_tumble"] = 2
	assert_true(SaveService.save(), SaveService.last_write_error)
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveService.SAVE_PATH)) as Dictionary
	assert_true(saved.has("skill_books"), "written now")
	saved.erase("skill_books")
	((saved["roster"] as Array)[0] as Dictionary).erase("learned_skills")
	GameSession.from_dict({"roster": []})
	_write(JSON.stringify(saved, "\t").to_utf8_buffer())
	assert_true(SaveService.load_game(), SaveService.load_block_reason)
	assert_eq(GameSession.skill_books.size(), 0)
	assert_eq(GameSession.hero_by_id("hero:k").learned_skills.size(), 0)
	assert_push_warning_count(0)
	assert_push_error_count(0)


func test_bad_book_entries_are_dropped_with_a_warning_and_the_rest_are_kept() -> void:
	_hero("knight", 30, "hero:k")
	assert_true(SaveService.save(), SaveService.last_write_error)
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveService.SAVE_PATH)) as Dictionary
	saved["skill_books"] = {"no_such_skill": 1, "knight_bulwark": 1, "general_tumble": 0, "general_brace": -2, "general_catch_breath": 1.5, "knight_anvilheart": 3, "general_hearten": 2}
	GameSession.from_dict({"roster": []})
	_write(JSON.stringify(saved, "\t").to_utf8_buffer())
	assert_true(SaveService.load_game(), SaveService.load_block_reason)
	assert_eq(GameSession.skill_books.size(), 2)
	assert_eq(GameSession.skill_books.get("knight_anvilheart"), 3)
	assert_eq(GameSession.skill_books.get("general_hearten"), 2)
	assert_push_warning_count(5)


func test_a_report_with_books_round_trips_and_one_without_still_shows() -> void:
	for pace: int in [1, 2, 6]:
		var settled: Dictionary = _settle(1.0, 90 + pace, pace, pace == 1)
		var books: Array = settled["books"]
		assert_eq(books.size(), pace, "%d books" % pace)
		_disk_round_trip()
		assert_eq(GameSession.expedition_reports[0].get("books"), books, "pace %d: the report keeps its books" % pace)
	var none: Dictionary = _settle(0.0, 91, 2)
	assert_eq(none["books"], [])
	assert_false(GameSession.expedition_reports[0].has("books"), "no drop, no key")
	_disk_round_trip()
	assert_eq(GameSession.expedition_reports.size(), 1)
	assert_false(GameSession.expedition_reports[0].has("books"))
	var hub: Node3D = _hub()
	hub._refresh_recent_returns()
	assert_false((hub.get_node("%RecentReturns") as ItemList).get_item_text(0).contains("skill book"), "a report without books reads as before")
	assert_push_warning_count(0)


func test_a_malformed_books_key_on_a_report_is_dropped_with_a_warning() -> void:
	_settle(1.0, 92, 2)
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveService.SAVE_PATH)) as Dictionary
	((saved["expedition_reports"] as Array)[0] as Dictionary)["books"] = ["general_tumble", 5]
	GameSession.from_dict({"roster": []})
	_write(JSON.stringify(saved, "\t").to_utf8_buffer())
	assert_true(SaveService.load_game(), SaveService.load_block_reason)
	assert_eq(GameSession.expedition_reports.size(), 1, "the report itself stays")
	assert_false(GameSession.expedition_reports[0].has("books"))
	assert_push_warning_count(1)


## ---- refusals: a message each, and nothing spent

func test_every_refusal_says_why_and_spends_nothing() -> void:
	var knight: Hero = _hero("knight", 1, "hero:k")
	GameSession.building_levels[2] = 1
	GameSession.parts[0] = 14
	GameSession.skill_books["cleric_hearthcall"] = 1
	GameSession.skill_books["general_tumble"] = 1
	GameSession.skill_books["general_catch_breath"] = 1
	knight.learned_skills.append("general_catch_breath")
	var cases: Array[Dictionary] = [
		{"what": "a class book for another class", "call": func() -> bool: return GameSession.use_skill_book(knight, "cleric_hearthcall"), "says": "another class"},
		{"what": "no book left", "call": func() -> bool: return GameSession.use_skill_book(knight, "knight_anvilheart"), "says": "no Anvilheart book"},
		{"what": "already known by level", "call": func() -> bool: return GameSession.teach_skill(knight, "knight_charge"), "says": "already knows"},
		{"what": "already learned", "call": func() -> bool: return GameSession.use_skill_book(knight, "general_catch_breath"), "says": "already knows"},
		{"what": "a general book below the tier minimum", "call": func() -> bool: return GameSession.use_skill_book(knight, "general_tumble"), "says": "needs hero level 10"},
		{"what": "a general lesson above the hall", "call": func() -> bool: return GameSession.teach_skill(knight, "general_tumble"), "says": "Training Hall of level 2"},
		{"what": "a class lesson past the reach", "call": func() -> bool: return GameSession.teach_skill(knight, "knight_gauntlet_toss"), "says": "opens at level 15"},
		{"what": "not enough F parts", "call": func() -> bool: return GameSession.teach_skill(knight, "knight_buckler_blow"), "says": "costs 15 F parts; you have 14"},
		{"what": "a book-only skill at the hall", "call": func() -> bool: return GameSession.teach_skill(knight, "knight_anvilheart"), "says": "only be learned from a book"},
		{"what": "another class's skill at the hall", "call": func() -> bool: return GameSession.teach_skill(knight, "cleric_mend"), "says": "another class"},
		{"what": "not a skill", "call": func() -> bool: return GameSession.teach_skill(knight, "no_such_skill"), "says": "not a skill"},
		{"what": "a hero not on the roster (book)", "call": func() -> bool: return GameSession.use_skill_book(Hero.new("Ghost", 0), "general_catch_breath"), "says": "not on the roster"},
		{"what": "a hero not on the roster (lesson)", "call": func() -> bool: return GameSession.teach_skill(null, "general_catch_breath"), "says": "not on the roster"},
	]
	for entry: Dictionary in cases:
		var before: Array = _snapshot(knight)
		GameSession.last_action_error = ""
		assert_false((entry["call"] as Callable).call(), str(entry["what"]))
		assert_string_contains(GameSession.last_action_error, str(entry["says"]), str(entry["what"]))
		assert_eq(_snapshot(knight), before, "%s: nothing spent" % entry["what"])
	# A level-5 hero is under the general tier 2 minimum even when it holds the book and the hall allows it.
	knight.level = 5
	GameSession.building_levels[2] = 2
	GameSession.parts[0] = 500
	var below: Array = _snapshot(knight)
	assert_false(GameSession.teach_skill(knight, "general_tumble"))
	assert_string_contains(GameSession.last_action_error, "needs hero level 10")
	assert_false(GameSession.use_skill_book(knight, "general_tumble"))
	assert_string_contains(GameSession.last_action_error, "needs hero level 10")
	assert_eq(_snapshot(knight), below)


func test_a_blocked_load_refuses_both_and_says_so() -> void:
	var knight: Hero = _hero("knight", 30, "hero:k")
	GameSession.building_levels[2] = 3
	GameSession.parts[0] = 500
	GameSession.skill_books["general_tumble"] = 1
	SaveService.load_blocked = true
	SaveService.load_block_reason = "The save could not be read."
	var before: Array = _snapshot(knight)
	assert_false(GameSession.use_skill_book(knight, "general_tumble"))
	assert_eq(GameSession.last_action_error, "The save could not be read.")
	GameSession.last_action_error = ""
	assert_false(GameSession.teach_skill(knight, "general_catch_breath"))
	assert_eq(GameSession.last_action_error, "The save could not be read.")
	assert_eq(_snapshot(knight), before)
	# The panel disables every learn button with the reason as its tooltip, and keeps the cost text.
	var young: Hero = _hero("knight", 1, "hero:y")
	var panel := SkillPanel.new()
	add_child_autofree(panel)
	panel.show_hero(young)
	var rows: Node = panel.find_child("Rows", true, false)
	for path: String in ["Teach_knight_buckler_blow", "General_general_catch_breath/Teach", "General_general_tumble/Book"]:
		var button: Button = rows.get_node(path) as Button
		assert_true(button.disabled, path)
		assert_eq(button.tooltip_text, "The save could not be read.", path)
	assert_eq((rows.get_node("Teach_knight_buckler_blow") as Button).text, "Teach · 15 F parts")


## ---- successes

func test_a_book_teaches_spends_one_and_the_key_goes_at_zero() -> void:
	var knight: Hero = _hero("knight", 12, "hero:k")
	GameSession.skill_books["general_tumble"] = 2
	GameSession.skill_books["knight_anvilheart"] = 1
	assert_true(GameSession.use_skill_book(knight, "general_tumble"), GameSession.last_action_error)
	assert_eq(GameSession.skill_books["general_tumble"], 1)
	assert_true(GameSession.use_skill_book(knight, "knight_anvilheart"), GameSession.last_action_error)
	assert_false(GameSession.skill_books.has("knight_anvilheart"), "the key is gone at 0")
	assert_eq(knight.learned_skills, ["general_tumble", "knight_anvilheart"] as Array[String])
	var known: Array[AbilityDefinition] = Hero.known_skills(knight, BALANCE)
	assert_true(SIM.ABILITIES["general_tumble"] in known)
	assert_true(SIM.ABILITIES["knight_anvilheart"] in known)
	var bar: Array[Dictionary] = Hero.bar_for(knight, BALANCE)
	assert_eq(bar.slice(-2), [{"id": "general_tumble", "mode": "auto"}, {"id": "knight_anvilheart", "mode": "auto"}] as Array[Dictionary], "appended as auto")


func test_a_class_lesson_costs_three_parts_per_unlock_level() -> void:
	var knight: Hero = _hero("knight", 20, "hero:k")
	GameSession.building_levels[2] = 1
	GameSession.parts[0] = 100
	var plan: Dictionary = GameSession.preview_lesson(knight, "knight_sweeping_blow")
	assert_eq(plan, {"cost": 75, "refusal": ""}, "a level-25 skill: 20 + 5 x 1 reaches it")
	assert_true(GameSession.teach_skill(knight, "knight_sweeping_blow"), GameSession.last_action_error)
	assert_eq(GameSession.parts[0], 25)
	assert_true(SIM.ABILITIES["knight_sweeping_blow"] in Hero.known_skills(knight, BALANCE))
	assert_eq(Hero.bar_for(knight, BALANCE).back(), {"id": "knight_sweeping_blow", "mode": "auto"})
	var younger: Hero = _hero("knight", 10, "hero:y")
	GameSession.parts[0] = 100
	assert_eq(GameSession.preview_lesson(younger, "knight_gauntlet_toss"), {"cost": 45, "refusal": ""}, "10 + 5 reaches level 15")


func test_general_lessons_cost_twenty_forty_and_eighty() -> void:
	var knight: Hero = _hero("knight", 30, "hero:k")
	GameSession.building_levels[2] = 3
	GameSession.parts[0] = 200
	for entry: Array in [["general_catch_breath", 20], ["general_tumble", 40], ["general_hearten", 80]]:
		var before: int = GameSession.parts[0]
		assert_true(GameSession.teach_skill(knight, entry[0]), GameSession.last_action_error)
		assert_eq(before - GameSession.parts[0], entry[1], str(entry[0]))
	assert_eq(knight.learned_skills, ["general_catch_breath", "general_tumble", "general_hearten"] as Array[String])


func test_a_level_zero_hero_counts_as_level_one() -> void:
	var knight: Hero = _hero("knight", 0, "hero:k")
	GameSession.building_levels[2] = 1
	GameSession.parts[0] = 100
	GameSession.skill_books["general_catch_breath"] = 1
	GameSession.skill_books["general_tumble"] = 1
	assert_true(GameSession.use_skill_book(knight, "general_catch_breath"), "the tier-1 minimum is level 1: " + GameSession.last_action_error)
	assert_false(GameSession.use_skill_book(knight, "general_tumble"))
	assert_eq(GameSession.preview_lesson(knight, "knight_buckler_blow")["refusal"], "", "hall level 1 reaches 1 + 5 = 6")
	assert_string_contains(str(GameSession.preview_lesson(knight, "knight_gauntlet_toss")["refusal"]), "reaches level 6")
	assert_true(GameSession.teach_skill(knight, "knight_buckler_blow"), GameSession.last_action_error)
	assert_eq(GameSession.parts[0], 85)


func test_a_hero_away_can_learn() -> void:
	var knight: Hero = _hero("knight", 80, "hero:k")
	var preset_id: String = GameSession.save_team_preset("", "Away", [knight.instance_id], "verdant_outskirts")
	assert_ne(GameSession.dispatch_force([preset_id], "verdant_outskirts", 1, {}, {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0}), "", GameSession.last_action_error)
	assert_true(GameSession.is_hero_busy(knight))
	GameSession.skill_books["general_tumble"] = 1
	assert_true(GameSession.use_skill_book(knight, "general_tumble"), GameSession.last_action_error)
	assert_eq(knight.learned_skills, ["general_tumble"] as Array[String])


## ---- Field Dressing (boundary #4)

func test_field_dressing_casts_when_the_class_heal_has_nobody_in_its_band() -> void:
	# Mend's band is heal_below; Field Dressing's is its own 35%. An ally at 30% with heal_below 20%: Mend has
	# no one to aim at, so it does not hold Field Dressing back.
	var state: BattleState = _battle([_unit("hero:c", "cleric", "ally", Vector2(0, -16)), _unit("hero:k", "knight", "ally", Vector2(1, -16), {"current_hp": 30.0})])
	state.policies["heal_below"] = 0.2
	var cleric: BattleActor = state.actors[0]
	_give(cleric, ["general_field_dressing", "cleric_mend"])
	SIM._support_actions(state)
	assert_almost_eq(state.actors[1].hp, 45.0, 0.0001, "Field Dressing: 1.5 x ATK")
	assert_gt(cleric.skill_cooldowns["general_field_dressing"], 0.0)
	assert_eq(cleric.skill_cooldowns["cleric_mend"], 0.0, "Mend stayed ready")


func test_field_dressing_still_holds_while_an_ally_is_in_the_heals_band() -> void:
	var state: BattleState = _battle([_unit("hero:c", "cleric", "ally", Vector2(0, -16)), _unit("hero:k", "knight", "ally", Vector2(1, -16), {"current_hp": 15.0})])
	state.policies["heal_below"] = 0.2
	var cleric: BattleActor = state.actors[0]
	_give(cleric, ["general_field_dressing", "cleric_mend"])
	SIM._support_actions(state)
	assert_almost_eq(state.actors[1].hp, 45.0, 0.0001, "Mend: 3 x ATK")
	assert_gt(cleric.skill_cooldowns["cleric_mend"], 0.0)
	assert_eq(cleric.skill_cooldowns["general_field_dressing"], 0.0)


## ---- the panel and the inventory

func test_the_skill_panel_teaches_uses_books_and_shows_a_refusal() -> void:
	var knight: Hero = _hero("knight", 1, "hero:k")
	GameSession.building_levels[2] = 1
	GameSession.parts[0] = 20
	GameSession.skill_books["knight_anvilheart"] = 1
	GameSession.skill_books["general_catch_breath"] = 1
	GameSession.skill_books["general_tumble"] = 1
	var panel := SkillPanel.new()
	add_child_autofree(panel)
	panel.show_hero(knight)
	var rows: Node = panel.find_child("Rows", true, false)
	var error: Label = panel.find_child("Error", true, false) as Label
	var buckler: Button = rows.get_node("Teach_knight_buckler_blow") as Button
	assert_eq(buckler.text, "Teach · 15 F parts")
	assert_false(buckler.disabled, "level 5 is inside the reach of 6")
	var toss: Button = rows.get_node("Teach_knight_gauntlet_toss") as Button
	assert_true(toss.disabled)
	assert_string_contains(toss.tooltip_text, "opens at level 15")
	assert_false(rows.has_node("Teach_knight_anvilheart"), "a class book is never a lesson")
	var class_book: Button = rows.get_node("ClassBook_knight_anvilheart/Book") as Button
	assert_eq(class_book.text, "Use book (1)")
	assert_false(class_book.disabled)
	assert_true(rows.has_node("GeneralTitle"))
	assert_false((rows.get_node("General_general_catch_breath/Teach") as Button).disabled)
	assert_eq((rows.get_node("General_general_catch_breath/Teach") as Button).text, "Teach · 20 F parts")
	assert_true((rows.get_node("General_general_tumble/Book") as Button).disabled)
	assert_string_contains((rows.get_node("General_general_tumble/Book") as Button).tooltip_text, "needs hero level 10")
	assert_string_contains((rows.get_node("General_general_tumble/Teach") as Button).tooltip_text, "Training Hall of level 2")
	assert_eq((rows.get_node("General_general_hearten/Book") as Button).text, "Use book (0)")
	assert_string_contains((rows.get_node("General_general_hearten/Book") as Button).tooltip_text, "no Hearten book")

	# A refused press shows its reason and spends nothing.
	toss.pressed.emit()
	assert_string_contains(error.text, "opens at level 15")
	assert_eq(GameSession.parts[0], 20)
	# An enabled one teaches, saves and refreshes.
	buckler.pressed.emit()
	assert_eq(error.text, "")
	assert_eq(GameSession.parts[0], 5)
	assert_true(SIM.ABILITIES["knight_buckler_blow"] in Hero.known_skills(knight, BALANCE))
	assert_false(rows.has_node("Locked_knight_buckler_blow"), "no longer locked")
	assert_true(rows.has_node("Skill_knight_buckler_blow"), "on the bar now")
	assert_true((rows.get_node("General_general_catch_breath/Teach") as Button).disabled, "5 parts left")
	(rows.get_node("ClassBook_knight_anvilheart/Book") as Button).pressed.emit()
	assert_false(GameSession.skill_books.has("knight_anvilheart"))
	assert_false(rows.has_node("ClassBook_knight_anvilheart"), "the row goes with the last book")
	assert_true(rows.has_node("Skill_knight_anvilheart"))
	(rows.get_node("General_general_catch_breath/Book") as Button).pressed.emit()
	assert_false(rows.has_node("General_general_catch_breath"), "learned")
	assert_true(rows.has_node("Skill_general_catch_breath"))
	assert_string_contains(FileAccess.get_file_as_string(SaveService.SAVE_PATH), "general_catch_breath", "saved")


func test_the_inventory_shows_the_book_counts_and_the_report_names_the_books() -> void:
	var hub: Node3D = _hub()
	var label: Label = hub.get_node("%SkillBooks") as Label
	hub._refresh_parts()
	assert_false(label.visible, "no books, no label")
	GameSession.skill_books["knight_anvilheart"] = 1
	GameSession.skill_books["general_tumble"] = 2
	hub._refresh_parts()
	assert_true(label.visible)
	assert_eq(label.text, "Skill books  Dust Roll ×2, Anvilheart ×1")
	assert_eq(hub._report_books_text({"books": ["general_tumble"]}), " and a skill book: Dust Roll")
	assert_eq(hub._report_books_text({"books": ["general_tumble", "knight_anvilheart"]}), " and skill books: Dust Roll, Anvilheart")
	assert_eq(hub._report_books_text({}), "")
	_settle(1.0, 5, 2)
	hub._refresh_recent_returns()
	assert_string_contains((hub.get_node("%RecentReturns") as ItemList).get_item_text(0), " and skill books: ")


## ---- helpers

func _verdant() -> ZoneDefinition:
	return _zone


func _zone_with(chance: float) -> ZoneDefinition:
	var zone: ZoneDefinition = _verdant().duplicate() as ZoneDefinition
	zone.skill_book_drop_chance = chance
	return zone


func _hero(def_id: String, level: int, id: String) -> Hero:
	var hero := Hero.new(def_id.capitalize(), 7)
	hero.def_id = StringName(def_id)
	hero.instance_id = id
	hero.level = level
	GameSession.roster.append(hero)
	return hero


func _snapshot(hero: Hero) -> Array:
	return [GameSession.parts.duplicate(), GameSession.skill_books.duplicate(), hero.learned_skills.duplicate()]


func _item_key(item: Item) -> Array:
	return [str(item.def_id), item.rank]


## Settles one dispatched victory at run_seed, at the verdant zone's book chance, and reports what it paid:
## {"stones", "items": [[def_id, rank]], "books": the report's ids}. legacy drops the battle's pace key;
## route sets the order's route length (what the stone factor reads).
func _settle(chance: float, run_seed: int, pace: int = 6, legacy: bool = false, route: float = -1.0) -> Dictionary:
	_verdant().skill_book_drop_chance = chance
	GameSession.set("_save_deferred_depth", 1)
	GameSession.from_dict({"roster": []})
	GameSession.set("_save_deferred_depth", 0)
	var hero := Hero.new("Pace Knight", 7)
	hero.def_id = &"knight"
	hero.level = 80
	hero.instance_id = "hero:pace"
	GameSession.roster.append(hero)
	var preset_id: String = GameSession.save_team_preset("", "Pace", [hero.instance_id], "verdant_outskirts")
	var order_id: String = GameSession.dispatch_force([preset_id], "verdant_outskirts", 1, {}, {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0})
	assert_ne(order_id, "", GameSession.last_action_error)
	var order: Dictionary = GameSession.expedition_orders[0]
	var battle: Dictionary = order["battle"] as Dictionary
	battle["pace"] = pace
	battle["max_seconds"] = _verdant().max_battle_seconds * pace
	if legacy:
		battle.erase("pace")
	battle["status"] = "victory"
	order["remaining_seconds"] = 0.0
	order["run_seed"] = run_seed
	if route > 0.0:
		order["initial_duration_seconds"] = route
	var stones_before: int = GameSession.stones
	GameSession.tick_expeditions(0.1)
	assert_eq(GameSession.expedition_reports.size(), 1, "settled")
	var report: Dictionary = GameSession.expedition_reports[0]
	var items: Array = GameSession.inventory.map(func(item: Item) -> Array: return _item_key(item))
	var books: Array = (report["books"] as Array).duplicate() if report.has("books") else []
	return {"stones": GameSession.stones - stones_before, "items": items, "books": books}


func _hub() -> Node3D:
	var hub: Node3D = (load("res://hub/hub.tscn") as PackedScene).instantiate() as Node3D
	add_child_autofree(hub)
	return hub


func _disk_round_trip() -> void:
	assert_true(SaveService.save(), SaveService.last_write_error)
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(SaveService.SAVE_PATH)
	GameSession.from_dict({"roster": []})
	_write(bytes)
	assert_true(SaveService.load_game(), SaveService.load_block_reason)


func _write(bytes: PackedByteArray) -> void:
	var file := FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


func _unit(id: String, archetype: String, faction: String, position: Vector2, extra: Dictionary = {}) -> Dictionary:
	var snapshot: Dictionary = {"archetype": archetype, "faction": faction, "hp": 100.0, "atk": 10.0, "defense": 0.0, "speed": 100.0, "crit_rate": 0.0, "crit_damage": 1.5, "position": [position.x, position.y]}
	if faction == "ally":
		snapshot["hero_id"] = id
		snapshot["squad_id"] = "s"
	else:
		snapshot["id"] = id
		snapshot["squad_id"] = ""
	snapshot.merge(extra, true)
	return snapshot


func _squads(snapshots: Array[Dictionary]) -> Array[Dictionary]:
	var hero_ids: Array = snapshots.filter(func(snapshot: Dictionary) -> bool: return snapshot["faction"] == "ally").map(func(snapshot: Dictionary) -> String: return snapshot["hero_id"])
	return [{"id": "s", "name": "S", "hero_ids": hero_ids, "stance": "stay_together", "guard_target_id": ""}]


## No zone spawns (the enemies come in the list), Auto Battle off, no crits, empty kits, pace 1.
func _battle(snapshots: Array[Dictionary]) -> BattleState:
	var state: BattleState = SIM.create_run("books:1", snapshots, _verdant(), _squads(snapshots), {"auto_battle": false, "suppress_ally_crit": true}, {"healing": 0, "revival": 0}, 7, "rescue", 1)
	for actor: BattleActor in state.actors:
		_give(actor, [])
	return state


func _give(actor: BattleActor, skill_ids: Array) -> void:
	actor.skills.clear()
	actor.skill_cooldowns.clear()
	for skill_id: String in skill_ids:
		actor.add_skill(SIM.ABILITIES[skill_id])
