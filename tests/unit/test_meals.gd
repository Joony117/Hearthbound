extends GutTest

## ig-m6o.2.2.5: neighbours eat together. Who sits at one table is a pure rule (TownRules.meal_tables), from saved
## state only: each eater's House and the buildings. The live tick rolls it once an hour and writes one "meal" record
## per table (GameSession._roll_meals). The disk cases and the tiers are in test_ledger.gd, the bond in
## test_bonds.gd, the lines in test_lines.gd.

const BALANCE: BalanceTable = preload("res://balance.tres")
const NO_HOME: StringName = Hero.NO_HOME
const HOUSE_A: Vector2i = Vector2i(0, 2)
const HOUSE_B: Vector2i = Vector2i(1, 2)
const HOUSE_C: Vector2i = Vector2i(2, 2)
const HOUSE_FAR: Vector2i = Vector2i(3, 2)
## The shipped table: two hexes of reach, four to a table.
const REACH: int = 2
const SIZE: int = 4
## The town tests: south of the halls' row, a House and a Lumbermill with a hall between them.
const TOWN_HOUSE: Vector2i = Vector2i(1, -2)
const TOWN_MILL: Vector2i = Vector2i(0, 2)

## The House a town test's table sits at (_table).
var _house_id: StringName = &""


## ---- who sits together (the pure rule)

func test_the_shipped_table_is_two_hexes_of_reach_and_four_to_a_table() -> void:
	assert_eq([BALANCE.meal_house_hexes, BALANCE.meal_table_size], [REACH, SIZE])


func test_neighbours_share_a_table_and_houses_three_apart_never_do() -> void:
	var town: Array[Dictionary] = _town([_house("House_1", HOUSE_A), _house("House_2", HOUSE_B), _house("House_3", HOUSE_C), _house("House_4", HOUSE_FAR)])
	var one: Array[Dictionary] = TownRules.meal_tables(_eaters({"a": "House_1", "b": "House_2", "c": "House_3", "d": "House_4"}), town, REACH, SIZE)
	assert_eq(one.size(), 1, "the far House is on nobody's table")
	assert_eq([one[0]["place"], one[0]["diners"]], ["House_1", ["a", "b", "c"]], "two apart is the reach, three is not")
	assert_eq(TownRules.meal_tables(_eaters({"a": "House_1", "d": "House_4"}), town, REACH, SIZE), [] as Array[Dictionary], "three apart never")


func test_the_same_house_is_distance_zero_and_a_lone_eater_is_no_meal() -> void:
	var town: Array[Dictionary] = _town([_house("House_1", HOUSE_A), _house("House_4", HOUSE_FAR)])
	var tables: Array[Dictionary] = TownRules.meal_tables(_eaters({"a": "House_1", "b": "House_1"}), town, REACH, SIZE)
	assert_eq(tables, [{"place": "House_1", "diners": ["a", "b"]}] as Array[Dictionary])
	assert_eq(TownRules.meal_tables(_eaters({"a": "House_1"}), town, REACH, SIZE), [] as Array[Dictionary], "one eater")
	assert_eq(TownRules.meal_tables(_eaters({}), town, REACH, SIZE), [] as Array[Dictionary], "none")
	assert_eq(TownRules.meal_tables(_eaters({"a": "House_1", "z": "House_4"}), town, REACH, SIZE), [] as Array[Dictionary], "two Houses too far apart")


func test_five_side_by_side_seat_four_and_the_fifth_eats_alone() -> void:
	var town: Array[Dictionary] = _town([_house("House_1", HOUSE_A)])
	var tables: Array[Dictionary] = TownRules.meal_tables(_eaters({"e5": "House_1", "e3": "House_1", "e1": "House_1", "e4": "House_1", "e2": "House_1"}), town, REACH, SIZE)
	assert_eq(tables.size(), 1)
	assert_eq(tables[0]["diners"], ["e1", "e2", "e3", "e4"], "the host is the lowest id, then the next by id")
	assert_eq(BALANCE.meal_table_size, 4)


func test_six_in_one_house_make_a_table_of_four_and_a_table_of_two() -> void:
	var town: Array[Dictionary] = _town([_house("House_1", HOUSE_A)])
	var tables: Array[Dictionary] = TownRules.meal_tables(_eaters({"e1": "House_1", "e2": "House_1", "e3": "House_1", "e4": "House_1", "e5": "House_1", "e6": "House_1"}), town, REACH, SIZE)
	assert_eq(tables.map(func(table: Dictionary) -> Array: return table["diners"]), [["e1", "e2", "e3", "e4"], ["e5", "e6"]])


func test_a_table_of_size_two_is_a_pair_and_every_diner_is_seated_once() -> void:
	var town: Array[Dictionary] = _town([_house("House_1", HOUSE_A), _house("House_2", HOUSE_B)])
	var tables: Array[Dictionary] = TownRules.meal_tables(_eaters({"a": "House_1", "b": "House_1", "c": "House_2", "d": "House_2", "e": "House_2"}), town, REACH, 2)
	var seen: Array = []
	for table: Dictionary in tables:
		assert_eq((table["diners"] as Array).size(), 2, "a pair each")
		seen.append_array(table["diners"])
	seen.sort()
	assert_eq(seen, ["a", "b", "c", "d"], "e is left over, and nobody sits twice")


func test_the_nearest_eater_is_seated_first_and_ties_go_by_id() -> void:
	var town: Array[Dictionary] = _town([_house("House_1", HOUSE_A), _house("House_3", HOUSE_C)])
	var tables: Array[Dictionary] = TownRules.meal_tables(_eaters({"m": "House_1", "z": "House_1", "a": "House_3"}), town, REACH, 2)
	assert_eq([tables.size(), tables[0]["diners"]], [1, ["m", "z"]], "z shares m's House, a is two hexes off: the near one first, though a is the lower id")
	assert_eq(TownRules.meal_tables(_eaters({"m": "House_1", "z": "House_1", "a": "House_3"}), town, REACH, 3)[0]["diners"], ["a", "m", "z"], "room for both")


func test_the_host_is_the_first_by_hex_then_id_and_the_table_is_at_its_house() -> void:
	var town: Array[Dictionary] = _town([_house("House_1", HOUSE_A), _house("House_2", HOUSE_B)])
	var tables: Array[Dictionary] = TownRules.meal_tables(_eaters({"a": "House_2", "z": "House_1"}), town, REACH, SIZE)
	assert_eq([tables[0]["place"], tables[0]["diners"]], ["House_1", ["a", "z"]], "z's House comes first by hex, so the table is at House_1, and the ids are sorted")


func test_the_tables_are_the_same_whatever_the_order_the_eaters_come_in() -> void:
	var town: Array[Dictionary] = _town([_house("House_1", HOUSE_A), _house("House_2", HOUSE_B), _house("House_3", HOUSE_C), _house("House_4", HOUSE_FAR)])
	var who: Dictionary = {"a": "House_1", "b": "House_2", "c": "House_3", "d": "House_4", "e": "House_1", "f": "House_2", "g": "House_4", "h": "House_3"}
	var forward: Array[Dictionary] = TownRules.meal_tables(_eaters(who), town, REACH, SIZE)
	var backward_keys: Array = who.keys()
	backward_keys.reverse()
	var backward: Dictionary = {}
	for key: Variant in backward_keys:
		backward[key] = who[key]
	assert_gt(forward.size(), 0)
	assert_eq(TownRules.meal_tables(_eaters(backward), town, REACH, SIZE), forward, "reversed")
	assert_eq(TownRules.meal_tables(_eaters(who), town, REACH, SIZE), forward, "the same on a second call")


func test_an_eater_with_no_finished_house_is_skipped() -> void:
	var building: Dictionary = _house("House_2", HOUSE_B)
	building["build_remaining"] = 30.0
	var town: Array[Dictionary] = _town([_house("House_1", HOUSE_A), building])
	var tables: Array[Dictionary] = TownRules.meal_tables(_eaters({"a": "House_1", "b": "House_1", "c": "House_2", "d": String(NO_HOME), "e": "House_9"}), town, REACH, SIZE)
	assert_eq(tables.map(func(table: Dictionary) -> Array: return table["diners"]), [["a", "b"]], "a House still going up, no home and a home that names no building sit nowhere")
	assert_eq(TownRules.meal_tables(_eaters({"c": "House_2", "d": "House_2"}), town, REACH, SIZE), [] as Array[Dictionary], "two in a House that is still going up")
	var mill: Dictionary = {"id": "Lumbermill_1", "type": "Lumbermill", "q": HOUSE_C.x, "r": HOUSE_C.y}
	var with_mill: Array[Dictionary] = _town([_house("House_1", HOUSE_A), mill])
	assert_eq(TownRules.meal_tables(_eaters({"f": "Forge", "g": "Forge"}), with_mill, REACH, SIZE), [] as Array[Dictionary], "two whose home is a finished hall")
	assert_eq(TownRules.meal_tables(_eaters({"h": "Lumbermill_1", "i": "Lumbermill_1", "j": "House_1"}), with_mill, REACH, SIZE), [] as Array[Dictionary], "a finished workplace is no home either, and a lone House eater eats alone")


func test_the_rule_never_draws_a_random_number() -> void:
	var town: Array[Dictionary] = _town([_house("House_1", HOUSE_A)])
	seed(11)
	var expected: int = randi()
	seed(11)
	TownRules.meal_tables(_eaters({"a": "House_1", "b": "House_1", "c": "House_1"}), town, REACH, SIZE)
	assert_eq(randi(), expected, "the global generator was not touched")


func test_the_table_scan_costs_little_at_a_hundred_heroes() -> void:
	var houses: Array[Dictionary] = []
	for index: int in 40:
		houses.append(_house("House_%d" % (index + 1), Vector2i(index % 10 - 5, 2 + floori(index / 10.0))))
	var town: Array[Dictionary] = _town(houses)
	var who: Dictionary = {}
	for index: int in 100:
		who["h%03d" % index] = "House_%d" % (index % 40 + 1)
	var runs: Array[int] = []
	var tables: int = 0
	for _run: int in 7:
		var start: int = Time.get_ticks_usec()
		tables = TownRules.meal_tables(_eaters(who), town, REACH, SIZE).size()
		runs.append(Time.get_ticks_usec() - start)
	gut.p("MEAL TABLES: 100 heroes, %d tables, best %.2f ms, worst %.2f ms of 7" % [tables, runs.min() / 1000.0, runs.max() / 1000.0])
	assert_gt(tables, 0)
	assert_lt(runs.min() / 1000.0, 16.7, "one scan fits a frame")


## ---- the live tick rolls it (GameSession._roll_meals)

func before_each() -> void:
	GameSession.set_process(false)
	SaveService.load_blocked = false
	SaveService.load_block_reason = ""
	GameSession.from_dict({"roster": []})
	GameSession.town_resources["wood"] = 1000.0
	GameSession.town_resources["food"] = 100000.0


func after_each() -> void:
	GameSession.set_process(true)


func test_neighbours_sit_down_at_the_hour_and_the_record_says_who_and_where() -> void:
	var ada: Hero = _housed("ada", HOUSE_A)
	_housed("bea", HOUSE_B)
	_roll(3599.0)
	assert_eq(_meals().size(), 0, "not yet an hour")
	_roll(1.0)
	var records: Array[Dictionary] = _meals()
	assert_eq(records.size(), 1)
	assert_eq([records[0]["diners"], str(records[0]["place"])], [["ada", "bea"], str(ada.home)], "sorted ids, and the place is the host's House, the first by hex")
	assert_true(records[0].has("seq") and records[0].has("time"))
	assert_eq(records[0].keys().size(), 5, "seq, time, kind, diners and place, and nothing else")
	assert_eq(BALANCE.meal_interval_minutes, 60)


## The one test that goes through the live tick itself, so the wiring is proved: the shipped hour, a minute a tick.
## Neither the food nor the roster cascade is touched by a meal: the same hour with the meal put off leaves the
## same food.
func test_the_live_tick_rolls_a_meal_with_the_shipped_balance_and_leaves_the_food_alone() -> void:
	_housed("ada", HOUSE_A)
	_housed("bea", HOUSE_B)
	watch_signals(GameSession)
	for _minute: int in 60:
		GameSession.tick_expeditions(60.0)
	assert_eq(_meals().size(), 1, "one meal in the hour")
	assert_signal_not_emitted(GameSession, "roster_changed", "a meal runs no roster cascade")
	var fed: float = float(GameSession.town_resources["food"])
	GameSession.ledger.clear()
	GameSession._ledger_tiers.clear()
	GameSession.town_resources["food"] = 100000.0
	GameSession._meal_clock = -1.0e9
	for _minute: int in 60:
		GameSession.tick_expeditions(60.0)
	assert_eq(_meals().size(), 0, "the meal put off")
	assert_almost_eq(float(GameSession.town_resources["food"]), fed, 0.001, "the same hour eats the same food, with or without the meal")


func test_a_hero_who_is_away_never_eats_and_the_body_does() -> void:
	_housed("ada", HOUSE_A)
	var bea: Hero = _housed("bea", HOUSE_B)
	assert_ne(GameSession.dispatch_expedition([bea.instance_id], "verdant_outskirts", 1, "Out"), "", GameSession.last_action_error)
	_roll(3600.0)
	assert_eq(_meals().size(), 0, "one hour with one of them away")
	var cy: Hero = _housed("cy", HOUSE_C)
	assert_true(GameSession.embody_hero(cy.instance_id), GameSession.last_action_error)
	_roll(3600.0)
	var records: Array[Dictionary] = _meals()
	assert_eq(records.size(), 1, "the body is in town")
	assert_eq(records[0]["diners"], ["ada", "cy"], "and bea, away, is not seated")


func test_houses_three_apart_never_share_a_table_however_long_the_wait() -> void:
	_housed("ada", HOUSE_A)
	_housed("bea", HOUSE_FAR)
	_roll(36000.0)
	assert_eq(_meals().size(), 0, "ten hours")


func test_an_unhoused_hero_and_a_lone_eater_sit_at_no_table() -> void:
	_housed("ada", HOUSE_A)
	_add_hero("cy")
	_roll(3600.0)
	assert_eq(_meals().size(), 0, "cy has no House, and ada eats alone")


func test_five_neighbours_make_a_table_of_four_and_the_fifth_eats_alone() -> void:
	for hex: Vector2i in [Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(0, 3), Vector2i(1, 3)]:
		_housed("h%d%d" % [hex.x, hex.y], hex)
	_roll(3600.0)
	var records: Array[Dictionary] = _meals()
	assert_eq(records.size(), 1, "one table")
	assert_eq((records[0]["diners"] as Array).size(), BALANCE.meal_table_size)
	assert_true(str(records[0]["place"]).begins_with("House_"))


func test_two_far_tables_each_write_their_own_record_in_one_meal_time() -> void:
	_housed("ada", HOUSE_A)
	_housed("bea", HOUSE_B)
	_housed("dot", Vector2i(-6, 2))
	_housed("eve", Vector2i(-5, 2))
	_roll(3600.0)
	var tables: Array = _meals().map(func(record: Dictionary) -> Array: return record["diners"])
	tables.sort()
	assert_eq(tables, [["ada", "bea"], ["dot", "eve"]])


func test_the_same_town_seats_the_same_tables_at_every_meal_time() -> void:
	_housed("ada", HOUSE_A)
	_housed("bea", HOUSE_B)
	_housed("cy", HOUSE_C)
	_roll(3600.0)
	_roll(3600.0)
	_roll(3600.0)
	var records: Array[Dictionary] = _meals()
	assert_eq(records.size(), 3)
	assert_eq([records[1]["diners"], records[2]["diners"], records[1]["place"]], [records[0]["diners"], records[0]["diners"], records[0]["place"]], "no RNG: tablemates stay tablemates")
	assert_eq(records[0]["diners"], ["ada", "bea", "cy"])


func test_a_meal_time_with_no_food_seats_no_one_and_the_clock_still_runs() -> void:
	_housed("ada", HOUSE_A)
	_housed("bea", HOUSE_B)
	GameSession.town_resources["food"] = 0.0
	_roll(3600.0)
	assert_eq(_meals().size(), 0, "an empty granary: no meal")
	assert_eq(GameSession._meal_clock, 0.0, "the hour passed all the same")
	GameSession.town_resources["food"] = 100.0
	_roll(3599.0)
	assert_eq(_meals().size(), 0, "the next meal time is an hour after the last, fed or not")
	_roll(1.0)
	assert_eq(_meals().size(), 1)


## A stall of S seconds is one meal time, not S / 3600 of them: the tables do not change between the hours, and the
## clock keeps its remainder. Ten hours of one pair write one record, not ten.
func test_a_ten_hour_stall_is_one_meal_time_and_leaves_the_clock_under_an_hour() -> void:
	_housed("ada", HOUSE_A)
	_housed("bea", HOUSE_B)
	GameSession._meal_clock = 33.0
	_roll(36000.0)
	assert_eq(_meals().size(), 1, "ten hours, one meal time")
	assert_almost_eq(GameSession._meal_clock, 33.0, 0.001, "36,000 s is whole hours: the remainder stays")
	_roll(3566.0)
	assert_eq(_meals().size(), 1, "an hour after the last meal time, less a second")
	_roll(1.0)
	assert_eq(_meals().size(), 2)


func test_a_meal_draws_no_number_from_any_stream() -> void:
	_housed("ada", HOUSE_A)
	_housed("bea", HOUSE_B)
	GameSession._encounter_rng.seed = 9
	var state: int = GameSession._encounter_rng.state
	seed(13)
	var expected: int = randi()
	seed(13)
	_roll(3600.0)
	assert_eq(_meals().size(), 1)
	assert_eq(GameSession._encounter_rng.state, state, "the encounter stream was not touched")
	assert_eq(randi(), expected, "nor the global one")


func test_the_offline_catch_up_makes_no_meal() -> void:
	_housed("ada", HOUSE_A)
	_housed("bea", HOUSE_B)
	var away: Hero = _housed("cy", HOUSE_C)
	assert_ne(GameSession.dispatch_expedition([away.instance_id], "verdant_outskirts", 1, "Out"), "", GameSession.last_action_error)
	GameSession.saved_at_unix = 1000.0
	GameSession.apply_offline_expedition_progress(1000.0 + 36000.0)
	assert_eq(_meals().size(), 0, "ten hours away")
	assert_eq(GameSession._meal_clock, 0.0, "and no time spent")


func test_meals_said_once_after_the_commit_and_say_only_that() -> void:
	_housed("ada", HOUSE_A)
	_housed("bea", HOUSE_B)
	_housed("dot", Vector2i(-6, 2))
	_housed("eve", Vector2i(-5, 2))
	watch_signals(GameSession)
	var mutation := func() -> void:
		_roll(3600.0)
		assert_signal_not_emitted(GameSession, "social_recorded", "not before the commit")
	assert_true(GameSession._commit_profile_mutation(mutation), GameSession.last_action_error)
	assert_signal_emit_count(GameSession, "social_recorded", 1)
	var said: Array = get_signal_parameters(GameSession, "social_recorded", 0)[0]
	assert_eq(said.size(), 2, "both tables in one signal")
	assert_eq(said.map(func(record: Dictionary) -> int: return record["seq"]), _meals().map(func(record: Dictionary) -> int: return record["seq"]))
	assert_signal_not_emitted(GameSession, "roster_changed", "a meal changes no roster")


func test_a_tick_that_rolls_back_says_nothing_and_spends_no_time() -> void:
	_housed("ada", HOUSE_A)
	_housed("bea", HOUSE_B)
	_roll(1800.0)
	watch_signals(GameSession)
	var mutation := func() -> bool:
		_roll(2000.0)
		return false
	assert_false(GameSession._commit_profile_mutation(mutation))
	assert_eq(_meals().size(), 0)
	assert_signal_not_emitted(GameSession, "social_recorded")
	assert_eq(GameSession._meal_clock, 1800.0, "the undone tick's time is not spent")
	_roll(1800.0)
	assert_eq(_meals().size(), 1, "the same pair sits down on the tick that stands")


func test_at_the_cap_a_meal_is_still_said_but_is_not_kept() -> void:
	_housed("ada", HOUSE_A)
	_housed("bea", HOUSE_B)
	for seq: int in range(1, BALANCE.ledger_max_records + 1):
		Ledger.append(GameSession.ledger, seq, 0, "summoned", {"hero": "filler:%d" % seq, "name": "F", "rank": 0})
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1
	watch_signals(GameSession)
	_roll(3600.0)
	assert_eq(GameSession.ledger.size(), BALANCE.ledger_max_records)
	assert_eq(_meals().size(), 0, "a meal is the first record to go")
	assert_signal_emit_count(GameSession, "social_recorded", 1)
	var said: Array = get_signal_parameters(GameSession, "social_recorded", 0)[0]
	assert_eq(said[0]["diners"], ["ada", "bea"], "the town still plays it")


func test_a_load_clears_the_clock_and_a_save_holds_no_meal_key() -> void:
	_housed("ada", HOUSE_A)
	_housed("bea", HOUSE_B)
	_roll(1800.0)
	assert_eq(GameSession._meal_clock, 1800.0)
	assert_false(GameSession.to_dict().has("meal_clock"), "the clock is not saved")
	GameSession._social_pending = [{"seq": 1}] as Array[Dictionary]
	GameSession.from_dict({"roster": []})
	assert_eq([GameSession._meal_clock, GameSession._social_pending.size()], [0.0, 0])


## The bond end to end: eight hourly meals through the live roll are eight meals and a bond in the kept index.
func test_eight_hourly_meals_are_a_bond_of_meals() -> void:
	var ada: Hero = _housed("ada", HOUSE_A)
	_housed("bea", HOUSE_B)
	for _hour: int in 8:
		_roll(3600.0)
	assert_eq(_meals().size(), 8)
	assert_eq(int(GameSession.bond_index()["ada"]["bea"]["meals"]), 8)
	var found: Dictionary = Bonds.bond_from(GameSession.bond_index(), "ada", {"ada": true, "bea": true}, BALANCE)
	assert_eq([found["partner"], found["points"], found["fact"]["kind"], found["fact"]["place"]], ["bea", 8, "meal", str(ada.home)])


## ---- the town plays it (TownView.play_meal, TownWalker.dine)

func test_the_diners_walk_to_seats_on_a_ring_around_the_hosts_house_and_the_first_says_its_line_when_it_sits() -> void:
	var town: TownView = _table(["ada", "bea", "cy"])
	var seated: Array[TownWalker] = [town.walkers["ada"], town.walkers["bea"], town.walkers["cy"]]
	var centre: Vector3 = town.free_point(town.work_spot(_house_id))
	var facts: Dictionary = _facts()
	assert_true(town.play_meal(["ada", "bea", "cy"], String(_house_id), facts))
	for walker: TownWalker in seated:
		assert_true(walker.is_walking() and walker.is_meeting(), "%s is on its way and taken" % walker.hero_id)
	assert_false(seated[0].is_showing_line(), "nothing said before it sits")
	_step_until_seated(seated)
	for index: int in 3:
		var angle: float = TAU * index / 3.0
		var seat: Vector3 = centre + TownView.MEAL_RING * Vector3(sin(angle), 0.0, cos(angle))
		assert_lt(seated[index].position.distance_to(seat), 0.01, "%s sits on its seat of the ring" % seated[index].hero_id)
		assert_eq(seated[index].clip(), &"Sit_Floor_Idle")
		var want: float = atan2(centre.x - seat.x, centre.z - seat.z)
		assert_almost_eq(seated[index].facing(), want, 0.01, "and faces the table")
	assert_almost_eq(seated[0].position.distance_to(seated[1].position), 2.0 * TownView.MEAL_RING * sin(PI / 3.0), 0.01, "three seats, a third of the ring apart")
	assert_true(seated[0].is_showing_line(), "the first diner speaks as it sits")
	assert_eq((seated[0].get_node("Line") as Label3D).text, Lines.line(facts, 0))
	assert_string_contains(Lines.line(facts, 0), "Bea")
	assert_false(seated[1].is_showing_line() or seated[2].is_showing_line(), "the others say nothing")


func test_the_diners_get_up_after_the_meal_and_go_back_to_their_own_plans() -> void:
	var town: TownView = _table(["ada", "bea"])
	var ada: TownWalker = town.walkers["ada"]
	var bea: TownWalker = town.walkers["bea"]
	assert_true(town.play_meal(["ada", "bea"], String(_house_id), _facts()))
	_step_until_seated([ada, bea])
	var trips: int = ada.trips
	for _step: int in 190:
		ada.step(0.1)
		bea.step(0.1)
	assert_true(ada.is_meeting() and bea.is_meeting(), "still at the table 19 s in (MEAL_SECONDS is %s)" % TownWalker.MEAL_SECONDS)
	for _step: int in 15:
		ada.step(0.1)
		bea.step(0.1)
	assert_false(ada.is_meeting() or bea.is_meeting(), "the meal is over")
	assert_gt(ada.trips, trips, "and the planner sent it on its next trip")
	assert_true(town.play_meal(["ada", "bea"], String(_house_id), _facts()), "they may sit down again")


func test_a_worker_goes_back_to_work_after_the_meal() -> void:
	var house: StringName = _place(TownRules.HOUSE, TOWN_HOUSE)
	var mill: StringName = _place(TownRules.LUMBERMILL, TOWN_MILL)
	var town: TownView = _town_view()
	var worker: Hero = _add_hero("wren")
	assert_true(GameSession.assign_home(worker, house), GameSession.last_action_error)
	assert_true(GameSession.station_hero(worker, mill), GameSession.last_action_error)
	var visitor: Hero = _add_hero("vi")
	town.show_walkers([worker, visitor])
	var wren: TownWalker = town.walkers["wren"]
	var vi: TownWalker = town.walkers["vi"]
	vi.linger_at(town.free_point(Vector3(-12.0, 0.0, 12.0)), &"Idle_B", NAN, 1.0e6)
	assert_true(town.play_meal(["vi", "wren"], String(house), _facts()))
	_step_until_seated([wren, vi])
	for _step: int in 205:
		wren.step(0.1)
		vi.step(0.1)
	assert_false(wren.is_meeting(), "the meal is over")
	for _step: int in 3000:
		wren.step(0.1)
		if wren.activity == TownWalker.WORK and wren.position.distance_to(town.work_spot(mill)) < 0.1:
			return
	fail_test("wren never got back to work")


func test_a_meal_is_refused_for_an_unplaced_house_and_for_fewer_than_two_who_can_sit() -> void:
	var town: TownView = _table(["ada", "bea", "cy"])
	var ada: TownWalker = town.walkers["ada"]
	assert_false(town.play_meal(["ada", "bea", "cy"], "House_9", _facts()), "no such House")
	assert_false(ada.is_meeting(), "and no one is touched")
	assert_false(town.play_meal(["ada", "nobody"], String(_house_id), _facts()), "one of two not shown")
	assert_false(town.play_meal(["nobody", "no one"], String(_house_id), _facts()), "neither shown")
	assert_false(town.play_meal([], String(_house_id), _facts()), "no diners")
	assert_false(ada.is_meeting(), "still no one touched")
	var body: Hero = _add_hero("body")
	town.embody(body)
	assert_false(town.play_meal(["body", "ada"], String(_house_id), _facts()), "the body is no walker, so ada is one of one")
	assert_false(ada.is_meeting())
	assert_true(town.play_meeting("bea", "cy", _facts()))
	assert_false(town.play_meal(["ada", "bea"], String(_house_id), _facts()), "bea is in a meeting: one of two")
	assert_false(ada.is_meeting(), "so ada is left alone")
	assert_true(town.play_meal(["ada", "bea", "cy"], String(_house_id), _facts()) == false, "cy is in the meeting too: ada is one of one")


## A refusal touches no one, even a figure standing on a building hex: _lead would step it onto free ground, and
## play_meal puts it back where it stood, with its plan as it was.
func test_a_refused_meal_leaves_a_figure_on_a_building_hex_where_it_stood_with_its_plan() -> void:
	var town: TownView = _table(["ada"])
	var ada: TownWalker = town.walkers["ada"]
	ada.position = TownRules.hex_to_world(TOWN_HOUSE)
	assert_gt(ada.position.distance_to(town.work_spot(_house_id)), TownView.AT_SPOT, "off the WorkSpot, so a lead has to snap it")
	assert_ne(town.free_point(ada.position), ada.position, "and it stands on a building hex")
	var stood: Vector3 = ada.position
	var doing: StringName = ada.activity
	var going: Vector3 = ada.destination()
	assert_false(town.play_meal(["ada", "nobody"], String(_house_id), _facts()), "one of two is shown")
	assert_eq(ada.position, stood, "ada was not moved")
	assert_eq(ada.activity, doing, "nor its plan")
	assert_eq(ada.destination(), going)
	assert_false(ada.is_meeting())


func test_a_diner_in_a_meeting_leaves_a_gap_and_the_others_keep_their_seats() -> void:
	var town: TownView = _table(["ada", "bea", "cy", "dot"])
	assert_true(town.play_meeting("bea", "dot", _facts()))
	var centre: Vector3 = town.free_point(town.work_spot(_house_id))
	assert_true(town.play_meal(["ada", "bea", "cy"], String(_house_id), _facts()), "two can sit")
	assert_false(town.walkers["bea"]._seated, "bea kept its meeting")
	var seated: Array[TownWalker] = [town.walkers["ada"], town.walkers["cy"]]
	_step_until_seated(seated)
	var seat: Vector3 = centre + TownView.MEAL_RING * Vector3(sin(TAU * 2.0 / 3.0), 0.0, cos(TAU * 2.0 / 3.0))
	assert_lt(seated[1].position.distance_to(seat), 0.01, "cy sits at the third seat of three, where it would have sat with bea there")
	assert_true(town.play_meal(["ada", "cy"], String(_house_id), _facts()) == false, "both are seated now")


func test_a_first_diner_who_is_not_shown_leaves_the_table_silent() -> void:
	var town: TownView = _table(["bea", "cy"])
	_add_hero("ada")
	assert_true(town.play_meal(["ada", "bea", "cy"], String(_house_id), _facts()), "ada is not shown; bea and cy still sit")
	var seated: Array[TownWalker] = [town.walkers["bea"], town.walkers["cy"]]
	_step_until_seated(seated)
	assert_false(seated[0].is_showing_line() or seated[1].is_showing_line(), "the record's first diner speaks, and it is not there")


## A partner's greeting of the body is its own: a seated diner greets no one, and another meeting will not take it
## from the table, until it gets up.
func test_a_seated_diner_greets_no_one_and_takes_no_meeting_until_it_gets_up() -> void:
	var town: TownView = _table(["ada", "bea"])
	var ada: TownWalker = town.walkers["ada"]
	var bea: TownWalker = town.walkers["bea"]
	var body := Node3D.new()
	town.add_child(body)
	body.position = ada.position + Vector3(12.0, 0.0, 0.0)
	ada.facts = {"kinds": ["met"] as Array[String], "slots": {"name": "Cy", "place": "here"}, "start": 0}
	ada.follow(body)
	assert_true(town.play_meal(["ada", "bea"], String(_house_id), _facts()))
	_step_until_seated([ada, bea])
	body.position = ada.position + Vector3(2.0, 0.0, 0.0)
	ada.step(0.1)
	assert_eq(ada.greetings, 0, "seated: no greeting")
	assert_false(town.play_meeting("bea", "ada", _facts()), "and no meeting")
	ada.step(TownWalker.MEAL_SECONDS)
	assert_false(ada.is_meeting(), "up again")
	body.position = ada.position + Vector3(1.0, 0.0, 0.0)
	ada.step(0.1)
	assert_eq(ada.greetings, 1, "the greeting it owed the body comes now")


## ---- the hub hears it (Hub._on_social_recorded)

func test_a_meal_between_shown_figures_is_played_in_the_town_and_changes_no_roster() -> void:
	_housed("ada", HOUSE_A)
	_housed("bea", HOUSE_B)
	var hub: Node3D = _hub()
	var town: TownView = hub.get_node("%Town") as TownView
	watch_signals(GameSession)
	_roll(3600.0)
	assert_eq(_meals().size(), 1)
	var ada: TownWalker = town.walkers["ada"]
	var bea: TownWalker = town.walkers["bea"]
	assert_true(ada.is_meeting() and bea.is_meeting(), "both figures are told")
	assert_signal_not_emitted(GameSession, "roster_changed", "a meal runs no roster cascade")
	_step_until_seated([ada, bea])
	assert_true(ada.is_showing_line(), "the first diner speaks")
	assert_string_contains((ada.get_node("Line") as Label3D).text, "bea")
	assert_false(bea.is_showing_line())


func test_the_eighth_meal_says_who_grew_close_once_and_none_before_it() -> void:
	_housed("ada", HOUSE_A)
	_housed("bea", HOUSE_B)
	var hub: Node3D = _hub()
	var status: Label = hub.get_node("%Status") as Label
	status.text = "before"
	for meal: int in 7:
		_roll(3600.0)
		assert_eq(status.text, "before", "meal %d" % (meal + 1))
	assert_eq(BALANCE.bond_threshold, BALANCE.bond_points_meal * 8, "eight meals make a bond")
	_roll(3600.0)
	assert_eq(status.text, "ada and bea grew close.")
	assert_eq(hub._partner_signs(hub._roster_names())["ada"], "♥ bea")


## Three neighbours at one table reach their eighth meal together: ada and bea are each other's partner and cy's is ada
## (a tie goes to the lower id), so the one meal makes two bonds and the hub says one notice with the other counted.
func test_a_meal_that_makes_several_bonds_says_one_notice_with_the_rest_counted() -> void:
	_housed("ada", HOUSE_A)
	_housed("bea", HOUSE_B)
	_housed("cy", HOUSE_C)
	var hub: Node3D = _hub()
	var status: Label = hub.get_node("%Status") as Label
	status.text = "before"
	for meal: int in 7:
		_roll(3600.0)
		assert_eq(status.text, "before", "meal %d" % (meal + 1))
	assert_eq(_meals()[0]["diners"], ["ada", "bea", "cy"], "one table of three")
	_roll(3600.0)
	assert_eq(status.text, "ada and bea grew close. (+1 more)")


func test_a_meal_redraws_the_roster_only_when_a_partner_sign_changes() -> void:
	_housed("ada", HOUSE_A)
	_housed("bea", HOUSE_B)
	var hub: Node3D = _hub()
	hub._open(&"Forge")
	var roster: ItemList = hub.get_node("%RosterList") as ItemList
	assert_eq(roster.item_count, 2)
	for index: int in roster.item_count:
		roster.set_item_tooltip(index, "MARK")
	for meal: int in 7:
		_roll(3600.0)
		assert_eq(roster.get_item_tooltip(0), "MARK", "meal %d: no sign changed, no redraw" % (meal + 1))
	_roll(3600.0)
	assert_ne(roster.get_item_tooltip(0), "MARK", "the eighth: the bond shows, the rows are drawn again")


func test_a_bond_of_meals_greets_the_body_with_a_meal_line() -> void:
	_housed("ada", HOUSE_A)
	_housed("bea", HOUSE_B)
	var hub: Node3D = _hub()
	var town: TownView = hub.get_node("%Town") as TownView
	assert_true(GameSession.embody_hero("ada"), GameSession.last_action_error)
	for _meal: int in 8:
		_roll(3600.0)
	assert_not_null(town.partner, "eight meals make bea ada's partner")
	assert_eq(town.partner.facts["kinds"][0], "meal")
	assert_false(town.walkers["bea"].is_meeting(), "the body is no figure to sit with")


## ---- helpers

## A town with a House placed and figures shown for ids, all lingering for good on the same free ground.
func _table(ids: Array[String]) -> TownView:
	_house_id = _place(TownRules.HOUSE, TOWN_HOUSE)
	var town: TownView = _town_view()
	var heroes: Array[Hero] = []
	for id: String in ids:
		heroes.append(_add_hero(id))
	town.show_walkers(heroes)
	for id: String in ids:
		town.walkers[id].linger_at(town.free_point(Vector3(-12.0, 0.0, 12.0)), &"Idle_B", NAN, 1.0e6)
	return town


func _town_view() -> TownView:
	var world := Node3D.new()
	var town: TownView = (load("res://hub/town/town.tscn") as PackedScene).instantiate() as TownView
	world.add_child(town)
	add_child_autofree(world)
	town.show_buildings(GameSession.town_buildings)
	return town


func _hub() -> Node3D:
	var hub: Node3D = (load("res://hub/hub.tscn") as PackedScene).instantiate() as Node3D
	add_child_autofree(hub)
	return hub


## The facts of a meal record of ada, bea and cy: the first speaks to the second.
func _facts() -> Dictionary:
	return Lines.meal_facts({"seq": 5, "diners": ["ada", "bea", "cy"]}, {"ada": "Ada", "bea": "Bea", "cy": "Cy"})


func _step_until_seated(walkers: Array[TownWalker]) -> void:
	for _step: int in 1200:
		if walkers.all(func(walker: TownWalker) -> bool: return not walker.is_walking()):
			return
		for walker: TownWalker in walkers:
			walker.step(0.1)
	fail_test("the diners never sat down")


## The live tick's roll, with the shipped table (tick_expeditions passes it too).
func _roll(seconds: float) -> void:
	GameSession._roll_meals(seconds, BALANCE)


func _meals() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for record: Dictionary in GameSession.ledger:
		if record["kind"] == "meal":
			records.append(record)
	return records


func _housed(hero_name: String, hex: Vector2i) -> Hero:
	var hero: Hero = _add_hero(hero_name)
	assert_true(GameSession.assign_home(hero, _place(TownRules.HOUSE, hex)), GameSession.last_action_error)
	return hero


## Placed and finished at once: construction is not what this file tests.
func _place(type: StringName, hex: Vector2i) -> StringName:
	var id := StringName(GameSession.preview_place_building(type, hex)["id"])
	assert_true(GameSession.place_building(type, hex), GameSession.last_action_error)
	GameSession.town_building(id).erase("build_remaining")
	return id


func _add_hero(hero_name: String) -> Hero:
	var hero := Hero.new(hero_name, 7)
	hero.instance_id = hero_name
	hero.def_id = &"knight"
	hero.level = 80
	hero.passions = [&"smithing", &"rites"] as Array[StringName]
	GameSession.add_hero(hero)
	return hero


## {hero id: home id, ...} as the [[id, home], ...] the rule reads, in the dictionary's order.
func _eaters(who: Dictionary) -> Array[Array]:
	var eaters: Array[Array] = []
	for id: Variant in who:
		eaters.append([str(id), str(who[id])])
	return eaters


func _house(id: String, hex: Vector2i) -> Dictionary:
	return {"id": id, "type": "House", "q": hex.x, "r": hex.y}


func _town(extra: Array[Dictionary]) -> Array[Dictionary]:
	var buildings: Array[Dictionary] = TownRules.default_halls()
	buildings.append_array(extra)
	return buildings
