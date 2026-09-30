extends GutTest

## ig-m6o.2.2.4: neighbours and coworkers meet. Who may meet is a pure rule (TownRules.meeting_pairs), from saved
## state only: homes, stations and the buildings. The live tick rolls it once a minute and writes one "encounter"
## record per meeting (GameSession._roll_encounters). The disk cases and the tiers are in
## test_ledger.gd, the bond in test_bonds.gd, the lines in test_lines.gd.

const BALANCE: BalanceTable = preload("res://balance.tres")
const NO_HOME: StringName = Hero.NO_HOME
const NO_STATION: StringName = Hero.NO_STATION
const HOUSE_A: Vector2i = Vector2i(0, 2)
const HOUSE_B: Vector2i = Vector2i(1, 2)
const HOUSE_C: Vector2i = Vector2i(2, 2)
const HOUSE_FAR: Vector2i = Vector2i(3, 2)
## The town tests: south of the halls' row, a House and a Lumbermill with a hall between them.
const TOWN_HOUSE: Vector2i = Vector2i(1, -2)
const TOWN_MILL: Vector2i = Vector2i(0, 2)


var _balance: BalanceTable = BALANCE


## ---- who may meet (the pure rule)

func test_neighbours_are_the_same_house_and_houses_two_apart_and_never_three() -> void:
	var town: Array[Dictionary] = _town([_house("House_1", HOUSE_A), _house("House_2", HOUSE_B), _house("House_3", HOUSE_C), _house("House_4", HOUSE_FAR)])
	var same: Array[Dictionary] = TownRules.meeting_pairs([_hero("a", &"House_1"), _hero("b", &"House_1")], town, BALANCE)
	assert_eq(same.size(), 1, "the same House")
	assert_eq([same[0]["a"], same[0]["b"], same[0]["why"], same[0]["place"], same[0]["key"]], ["a", "b", "neighbours", "House_1", "a|b"])
	assert_eq(TownRules.meeting_pairs([_hero("a", &"House_1"), _hero("b", &"House_2")], town, BALANCE).size(), 1, "one apart")
	assert_eq(TownRules.meeting_pairs([_hero("a", &"House_1"), _hero("b", &"House_3")], town, BALANCE).size(), 1, "two apart is the reach (encounter_neighbour_hexes)")
	assert_eq(BALANCE.encounter_neighbour_hexes, 2)
	assert_eq(TownRules.meeting_pairs([_hero("a", &"House_1"), _hero("b", &"House_4")], town, BALANCE), [] as Array[Dictionary], "three apart never")


func test_coworkers_are_the_same_building_and_adjoining_halls_and_never_two_apart() -> void:
	var town: Array[Dictionary] = _town([])
	# The halls stand in a row: SummoningCircle, Forge, TrainingHall, Sanctum, Reliquary; TownGate and the Apothecary above.
	var adjoining: Array[Dictionary] = TownRules.meeting_pairs([_hero("a", NO_HOME, &"Forge"), _hero("b", NO_HOME, &"TrainingHall")], town, BALANCE)
	assert_eq(adjoining.size(), 1, "Forge and TrainingHall adjoin")
	assert_eq([adjoining[0]["why"], adjoining[0]["place"]], ["coworkers", "Forge"], "the place is a's station")
	assert_eq(BALANCE.encounter_coworker_hexes, 1)
	assert_eq(TownRules.meeting_pairs([_hero("a", NO_HOME, &"Forge"), _hero("b", NO_HOME, &"Sanctum")], town, BALANCE), [] as Array[Dictionary], "two apart never")
	assert_eq(TownRules.meeting_pairs([_hero("a", NO_HOME, &"Forge"), _hero("b", NO_HOME, &"Reliquary")], town, BALANCE), [] as Array[Dictionary], "four apart never")
	# TownGate and the Apothecary are 2 hexes from the nearest hall, so their keepers are never coworkers.
	assert_eq(TownRules.meeting_pairs([_hero("a", NO_HOME, &"TownGate"), _hero("b", NO_HOME, &"TrainingHall")], town, BALANCE), [] as Array[Dictionary], "TownGate")
	assert_eq(TownRules.meeting_pairs([_hero("a", NO_HOME, &"Apothecary"), _hero("b", NO_HOME, &"Reliquary")], town, BALANCE), [] as Array[Dictionary], "Apothecary")
	var lumbermill: Dictionary = {"id": "Lumbermill_1", "type": "Lumbermill", "q": -1, "r": 2}
	var workers: Array[Dictionary] = TownRules.meeting_pairs([_hero("a", NO_HOME, &"Lumbermill_1"), _hero("b", NO_HOME, &"Lumbermill_1")], _town([lumbermill]), BALANCE)
	assert_eq([workers.size(), workers[0]["why"], workers[0]["place"]], [1, "coworkers", "Lumbermill_1"], "the same workplace")


func test_a_pair_that_are_neighbours_and_coworkers_record_coworkers() -> void:
	var town: Array[Dictionary] = _town([_house("House_1", HOUSE_A)])
	var pairs: Array[Dictionary] = TownRules.meeting_pairs([_hero("a", &"House_1", &"Forge"), _hero("b", &"House_1", &"TrainingHall")], town, BALANCE)
	assert_eq([pairs.size(), pairs[0]["why"], pairs[0]["place"]], [1, "coworkers", "Forge"], "work goes first, and the place is a's station")
	var neighbours: Array[Dictionary] = TownRules.meeting_pairs([_hero("a", &"House_1", &"Forge"), _hero("b", &"House_1", &"Sanctum")], town, BALANCE)
	assert_eq([neighbours[0]["why"], neighbours[0]["place"]], ["neighbours", "House_1"], "stations two apart fall back to the Houses, and the place is a's House")


func test_a_hero_with_no_built_house_or_station_never_meets() -> void:
	var building: Dictionary = _house("House_2", HOUSE_B)
	building["build_remaining"] = 30.0
	var town: Array[Dictionary] = _town([_house("House_1", HOUSE_A), building])
	assert_eq(TownRules.meeting_pairs([_hero("a", &"House_1"), _hero("b", NO_HOME)], town, BALANCE), [] as Array[Dictionary], "unhoused")
	assert_eq(TownRules.meeting_pairs([_hero("a", &"House_1"), _hero("b", &"House_2")], town, BALANCE), [] as Array[Dictionary], "a House still going up")
	assert_eq(TownRules.meeting_pairs([_hero("a", &"House_1"), _hero("b", &"House_9")], town, BALANCE), [] as Array[Dictionary], "a home id that names no building")
	assert_eq(TownRules.meeting_pairs([_hero("a", NO_HOME, &"Forge"), _hero("b", NO_HOME, &"Nowhere")], town, BALANCE), [] as Array[Dictionary], "a station that names no building")
	assert_eq(TownRules.meeting_pairs([_hero("a", &"House_1")], town, BALANCE), [] as Array[Dictionary], "one hero")
	assert_eq(TownRules.meeting_pairs([], town, BALANCE), [] as Array[Dictionary], "none")


func test_the_pairs_come_sorted_by_key_whatever_the_order_they_were_handed_in() -> void:
	var town: Array[Dictionary] = _town([_house("House_1", HOUSE_A)])
	var heroes: Array[Hero] = [_hero("c", &"House_1"), _hero("a", &"House_1"), _hero("b", &"House_1")]
	var keys: Array = TownRules.meeting_pairs(heroes, town, BALANCE).map(func(pair: Dictionary) -> String: return pair["key"])
	assert_eq(keys, ["a|b", "a|c", "b|c"])
	assert_eq(TownRules.meeting_pairs(heroes, town, BALANCE)[2]["a"], "b", "a is the lower id")


func test_meeting_of_reads_hexes_and_the_none_hex_never_meets() -> void:
	var none: Vector2i = TownRules.NO_HEX
	assert_eq(TownRules.meeting_of(none, Vector2i(0, 0), none, Vector2i(1, 0), BALANCE), "coworkers")
	assert_eq(TownRules.meeting_of(none, Vector2i(0, 0), none, Vector2i(2, 0), BALANCE), "", "two apart")
	assert_eq(TownRules.meeting_of(Vector2i(0, 0), none, Vector2i(2, 0), none, BALANCE), "neighbours")
	assert_eq(TownRules.meeting_of(Vector2i(0, 0), none, Vector2i(3, 0), none, BALANCE), "")
	assert_eq(TownRules.meeting_of(none, none, none, none, BALANCE), "", "no hex is not the same place")
	assert_eq(TownRules.meeting_of(Vector2i(0, 0), none, none, Vector2i(0, 0), BALANCE), "", "one housed and one stationed")


func test_building_hexes_holds_finished_buildings_only() -> void:
	var building: Dictionary = _house("House_2", HOUSE_B)
	building["build_remaining"] = 5.0
	var hexes: Dictionary[StringName, Vector2i] = TownRules.building_hexes(_town([_house("House_1", HOUSE_A), building]))
	assert_eq(hexes[&"House_1"], HOUSE_A)
	assert_eq(hexes[&"Forge"], TownRules.HALL_HEXES[&"Forge"])
	assert_false(hexes.has(&"House_2"), "still going up")
	assert_eq(hexes.size(), TownRules.HALL_HEXES.size() + 1)


func test_the_pair_scan_costs_little_at_a_hundred_heroes() -> void:
	var houses: Array[Dictionary] = []
	for index: int in 40:
		houses.append(_house("House_%d" % (index + 1), Vector2i(index % 10 - 5, 2 + floori(index / 10.0))))
	var town: Array[Dictionary] = _town(houses)
	var stations: Array[StringName] = [&"Forge", &"TrainingHall", &"Sanctum", &"SummoningCircle", &"Reliquary"]
	var heroes: Array[Hero] = []
	for index: int in 100:
		heroes.append(_hero("h%03d" % index, StringName("House_%d" % (index % 40 + 1)), stations[index % 5] if index % 3 == 0 else NO_HOME))
	var runs: Array[int] = []
	var pairs: int = 0
	for _run: int in 7:
		var start: int = Time.get_ticks_usec()
		pairs = TownRules.meeting_pairs(heroes, town, BALANCE).size()
		runs.append(Time.get_ticks_usec() - start)
	gut.p("ENCOUNTER SCAN: 100 heroes, %d pairs, best %.2f ms, worst %.2f ms of 7" % [pairs, runs.min() / 1000.0, runs.max() / 1000.0])
	assert_gt(pairs, 0)
	assert_lt(runs.min() / 1000.0, 16.7, "one scan fits a frame")


## ---- the live tick rolls it (GameSession._roll_encounters)

func before_each() -> void:
	GameSession.set_process(false)
	SaveService.load_blocked = false
	SaveService.load_block_reason = ""
	GameSession.from_dict({"roster": []})
	GameSession.town_resources["wood"] = 1000.0
	GameSession.town_resources["food"] = 100000.0
	GameSession._encounter_rng.seed = 7
	_chance(1.0)


func after_each() -> void:
	GameSession.set_process(true)


func test_two_neighbours_meet_at_the_minute_and_the_record_says_who_where_and_why() -> void:
	var ada: Hero = _housed("ada", HOUSE_A)
	_housed("bea", HOUSE_B)
	_roll(59.0)
	assert_eq(_encounters().size(), 0, "not yet a minute")
	_roll(1.0)
	var records: Array[Dictionary] = _encounters()
	assert_eq(records.size(), 1)
	assert_eq([records[0]["heroes"], str(records[0]["place"]), records[0]["why"]], [["ada", "bea"], str(ada.home), "neighbours"], "a is the lower id; the place is a's House")
	assert_true(records[0].has("seq") and records[0].has("time"))


## The one test that goes through the live tick itself, so the wiring is proved: the shipped chance and reach, the
## seeded stream, a minute a tick, until the first meeting.
func test_the_live_tick_rolls_a_meeting_with_the_shipped_balance() -> void:
	var ada: Hero = _housed("ada", HOUSE_A)
	_housed("bea", HOUSE_B)
	watch_signals(GameSession)
	var ticks: int = 0
	while _encounters().is_empty() and ticks < 200:
		GameSession.tick_expeditions(60.0)
		ticks += 1
	assert_lt(ticks, 200, "a chance of %s a minute meets long before 200 minutes" % BALANCE.encounter_chance_per_minute)
	var records: Array[Dictionary] = _encounters()
	assert_eq(records.size(), 1)
	assert_eq([records[0]["heroes"], str(records[0]["place"]), records[0]["why"]], [["ada", "bea"], str(ada.home), "neighbours"])
	assert_signal_emit_count(GameSession, "social_recorded", 1)
	assert_signal_not_emitted(GameSession, "roster_changed", "a chat runs no roster cascade")


func test_two_coworkers_meet_at_the_first_ones_station_and_coworkers_beat_neighbours() -> void:
	_stationed("ada", &"Forge", HOUSE_A)
	_stationed("bea", &"TrainingHall", HOUSE_B)
	_roll(60.0)
	var records: Array[Dictionary] = _encounters()
	assert_eq(records.size(), 1)
	assert_eq([records[0]["heroes"], records[0]["place"], records[0]["why"]], [["ada", "bea"], "Forge", "coworkers"], "they are neighbours too: work goes first")


func test_a_hero_who_is_away_never_meets_and_the_body_does() -> void:
	_housed("ada", HOUSE_A)
	var bea: Hero = _housed("bea", HOUSE_B)
	assert_ne(GameSession.dispatch_expedition([bea.instance_id], "verdant_outskirts", 1, "Out"), "", GameSession.last_action_error)
	_roll(600.0)
	assert_eq(_encounters().size(), 0, "ten minutes with one of them away")
	var cy: Hero = _housed("cy", HOUSE_C)
	assert_true(GameSession.embody_hero(cy.instance_id), GameSession.last_action_error)
	_roll(60.0)
	var records: Array[Dictionary] = _encounters()
	assert_eq(records.size(), 1, "the body is in town")
	assert_eq(records[0]["heroes"], ["ada", "cy"], "and bea, away, is not drawn")


func test_houses_three_apart_never_meet_however_long_the_wait() -> void:
	_housed("ada", HOUSE_A)
	_housed("bea", HOUSE_FAR)
	_roll(36000.0)
	assert_eq(_encounters().size(), 0, "600 minutes at a sure chance")


func test_a_pair_meets_once_an_hour_at_a_sure_chance_and_three_heroes_make_three_pairs() -> void:
	_housed("ada", HOUSE_A)
	_housed("bea", HOUSE_B)
	_roll(60.0)
	assert_eq(_encounters().size(), 1, "minute 1")
	_roll(59.0 * 60.0)
	assert_eq(_encounters().size(), 1, "minutes 2 to 60: the pair is resting")
	_roll(60.0)
	assert_eq(_encounters().size(), 2, "minute 61: an hour after the first (encounter_pair_cooldown_minutes)")
	assert_eq(BALANCE.encounter_pair_cooldown_minutes, 60)
	_housed("cy", HOUSE_C)
	_roll(60.0)
	_roll(60.0)
	var keys: Array = _encounters().slice(2).map(func(record: Dictionary) -> String: return "|".join(record["heroes"]))
	keys.sort()
	assert_eq(keys, ["ada|cy", "bea|cy"], "cy is new: the two pairs with cy meet, one a minute, and the resting pair does not")
	_roll(60.0)
	assert_eq(_encounters().size(), 4, "every pair is resting now")


## The ceiling: a stall of S seconds draws S / 60 times inside one tick and writes at most one record per
## pair per hour, so a ten-hour stall with one pair writes ten. The clock is not clamped (ruled in ig-m6o.2.2.4).
func test_a_ten_hour_stall_writes_a_meeting_an_hour_and_leaves_the_clock_under_a_minute() -> void:
	_housed("ada", HOUSE_A)
	_housed("bea", HOUSE_B)
	GameSession._encounter_clock = 33.0
	_roll(36000.0)
	assert_eq(_encounters().size(), 10)
	assert_almost_eq(GameSession._encounter_clock, 33.0, 0.001, "36,000 s is whole minutes: the remainder stays")


func test_one_long_tick_draws_exactly_as_the_same_seconds_in_one_second_ticks() -> void:
	_housed("ada", HOUSE_A)
	_housed("bea", HOUSE_B)
	_housed("cy", HOUSE_C)
	_housed("dot", HOUSE_FAR)
	_chance(0.5)
	GameSession._encounter_rng.seed = 11
	_roll(3600.0)
	var one: Array = _shapes()
	assert_gt(one.size(), 2, "the draw made some meetings, or this proves nothing")
	GameSession.ledger.clear()
	GameSession._ledger_tiers.clear()
	GameSession._encounter_cooldowns = {}
	GameSession._encounter_clock = 0.0
	GameSession._encounter_rng.seed = 11
	for _second: int in 3600:
		_roll(1.0)
	assert_eq(_shapes(), one)


func test_a_minute_with_nobody_in_reach_takes_no_number_from_the_stream() -> void:
	_housed("ada", HOUSE_A)
	_housed("bea", HOUSE_FAR)
	GameSession._encounter_rng.seed = 9
	_roll(3600.0)
	var untouched := RandomNumberGenerator.new()
	untouched.seed = 9
	assert_eq(GameSession._encounter_rng.state, untouched.state, "nobody in reach: no draw")


func test_a_minute_with_every_pair_resting_takes_no_number_from_the_stream() -> void:
	_housed("ada", HOUSE_A)
	_housed("bea", HOUSE_B)
	_housed("dot", Vector2i(4, 2))
	GameSession._encounter_rng.seed = 9
	_roll(60.0)
	assert_eq(_encounters().size(), 1)
	var untouched := RandomNumberGenerator.new()
	untouched.seed = 9
	untouched.randf()
	untouched.randi()
	_roll(59.0 * 60.0)
	assert_eq(GameSession._encounter_rng.state, untouched.state, "the meeting drew a chance and a pair; the resting hour drew nothing")


func test_a_chance_of_nothing_never_meets() -> void:
	_housed("ada", HOUSE_A)
	_housed("bea", HOUSE_B)
	_chance(0.0)
	_roll(36000.0)
	assert_eq(_encounters().size(), 0)


func test_the_offline_catch_up_makes_no_meeting() -> void:
	_housed("ada", HOUSE_A)
	_housed("bea", HOUSE_B)
	var away: Hero = _housed("cy", HOUSE_C)
	assert_ne(GameSession.dispatch_expedition([away.instance_id], "verdant_outskirts", 1, "Out"), "", GameSession.last_action_error)
	GameSession.saved_at_unix = 1000.0
	GameSession.apply_offline_expedition_progress(1000.0 + 36000.0)
	assert_eq(_encounters().size(), 0, "ten hours away")
	assert_eq(GameSession._encounter_clock, 0.0, "and no minutes spent")


func test_a_meeting_is_said_once_after_the_commit_and_says_only_that() -> void:
	_housed("ada", HOUSE_A)
	_housed("bea", HOUSE_B)
	watch_signals(GameSession)
	var mutation := func() -> void:
		_roll(60.0)
		assert_signal_not_emitted(GameSession, "social_recorded", "not before the commit")
	assert_true(GameSession._commit_profile_mutation(mutation), GameSession.last_action_error)
	assert_signal_emit_count(GameSession, "social_recorded", 1)
	var said: Array = get_signal_parameters(GameSession, "social_recorded", 0)[0]
	assert_eq(said.size(), 1)
	assert_eq(said[0]["seq"], _encounters()[0]["seq"])
	assert_signal_not_emitted(GameSession, "roster_changed", "a chat changes no roster")


func test_a_tick_that_rolls_back_says_nothing_and_spends_no_minutes() -> void:
	_housed("ada", HOUSE_A)
	_housed("bea", HOUSE_B)
	_roll(30.0)
	watch_signals(GameSession)
	var mutation := func() -> bool:
		_roll(45.0)
		return false
	assert_false(GameSession._commit_profile_mutation(mutation))
	assert_eq(_encounters().size(), 0)
	assert_signal_not_emitted(GameSession, "social_recorded")
	assert_eq(GameSession._encounter_clock, 30.0, "the undone tick's minutes are not spent")
	assert_true(GameSession._encounter_cooldowns.is_empty(), "and it set no cooldown")
	_roll(30.0)
	assert_eq(_encounters().size(), 1, "the same pair meets on the tick that stands")


func test_at_the_cap_a_meeting_is_still_said_but_is_not_kept() -> void:
	_housed("ada", HOUSE_A)
	_housed("bea", HOUSE_B)
	for seq: int in range(1, BALANCE.ledger_max_records + 1):
		Ledger.append(GameSession.ledger, seq, 0, "summoned", {"hero": "filler:%d" % seq, "name": "F", "rank": 0})
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1
	watch_signals(GameSession)
	_roll(60.0)
	assert_eq(GameSession.ledger.size(), BALANCE.ledger_max_records)
	assert_eq(_encounters().size(), 0, "an encounter is the first record to go")
	assert_signal_emit_count(GameSession, "social_recorded", 1)
	var said: Array = get_signal_parameters(GameSession, "social_recorded", 0)[0]
	assert_eq(said[0]["heroes"], ["ada", "bea"], "the town still plays it")


func test_a_load_clears_the_clock_the_rests_and_what_was_waiting_to_be_said() -> void:
	_housed("ada", HOUSE_A)
	_housed("bea", HOUSE_B)
	_roll(90.0)
	assert_false(GameSession._encounter_cooldowns.is_empty())
	assert_eq(GameSession._encounter_clock, 30.0)
	GameSession._social_pending = [{"seq": 1}] as Array[Dictionary]
	var state: int = GameSession._encounter_rng.state
	GameSession.from_dict({"roster": []})
	assert_eq([GameSession._encounter_clock, GameSession._encounter_cooldowns.size(), GameSession._social_pending.size()], [0.0, 0, 0])
	assert_eq(GameSession._encounter_rng.state, state, "a load does not re-seed the stream")


## ---- the town plays it (TownView.play_meeting, TownWalker.meet)

func test_a_meeting_walks_the_first_to_the_second_who_waits_and_the_first_says_its_line() -> void:
	var town: TownView = _town_view()
	var pair: Array[TownWalker] = _two_wanderers(town, Vector3(9.0, 0.0, 0.0))
	var a: TownWalker = pair[0]
	var b: TownWalker = pair[1]
	assert_true(town.play_meeting("ada", "bea", _facts()))
	assert_true(a.is_walking() and a.is_meeting() and b.is_meeting())
	_step_until_met(a, b)
	assert_eq([a.chats, b.chats], [1, 1])
	assert_true(a.is_showing_line())
	assert_eq((a.get_node("Line") as Label3D).text, "Morning, Bea. Quiet around the Forge today.", "the first speaks, naming the second")
	assert_false(b.is_showing_line(), "the one who waited says nothing")
	assert_lt(a.position.distance_to(b.position), TownWalker.CHAT_DISTANCE + 0.3, "it stops within reach and does not walk into the other")
	var stopped: Vector3 = a.position
	for _step: int in 39:
		a.step(0.1)
	assert_eq(a.position, stopped, "it stands while the line shows")
	assert_false(a.is_meeting() or b.is_meeting(), "a one-shot")
	assert_eq([a.greetings, b.greetings], [0, 0], "a chat is no greeting of the body")


func test_two_figures_a_metre_apart_still_meet() -> void:
	var town: TownView = _town_view()
	var pair: Array[TownWalker] = _two_wanderers(town, Vector3(1.0, 0.0, 0.0))
	assert_true(town.play_meeting("ada", "bea", _facts()))
	pair[0].step(0.1)
	pair[1].step(0.1)
	assert_eq([pair[0].chats, pair[1].chats], [1, 1], "no REARM_DISTANCE to wait for: two neighbours at one door start nearer than that")


func test_a_meeting_is_refused_for_a_figure_not_shown_the_body_one_already_meeting_and_itself() -> void:
	var town: TownView = _town_view()
	_two_wanderers(town, Vector3(9.0, 0.0, 0.0))
	var body: Hero = _add_hero("body")
	town.embody(body)
	assert_false(town.play_meeting("ada", "nobody", _facts()), "not shown")
	assert_false(town.play_meeting("body", "ada", _facts()), "the body is no walker")
	assert_false(town.play_meeting("ada", "ada", _facts()), "itself")
	assert_true(town.play_meeting("ada", "bea", _facts()))
	assert_false(town.play_meeting("ada", "bea", _facts()), "already meeting")
	assert_false(town.play_meeting("bea", "ada", _facts()), "the other way round too")


func test_a_keeper_a_worker_and_a_worker_mid_walk_go_back_to_work_after_a_meeting() -> void:
	var town: TownView = _town_view()
	var house: StringName = _place(TownRules.HOUSE, TOWN_HOUSE)
	var mill: StringName = _place(TownRules.LUMBERMILL, TOWN_MILL)
	town.show_buildings(GameSession.town_buildings)
	var keeper: Hero = _add_hero("kay")
	assert_true(GameSession.station_hero(keeper, &"Forge"), GameSession.last_action_error)
	var worker: Hero = _add_hero("wren")
	assert_true(GameSession.assign_home(worker, house), GameSession.last_action_error)
	assert_true(GameSession.station_hero(worker, mill), GameSession.last_action_error)
	var walker: Hero = _add_hero("walt")
	assert_true(GameSession.assign_home(walker, _place(TownRules.HOUSE, Vector2i(-3, 2))), GameSession.last_action_error)
	assert_true(GameSession.station_hero(walker, mill), GameSession.last_action_error)
	var visitor: Hero = _add_hero("vi")
	town.show_buildings(GameSession.town_buildings)
	town.show_walkers([keeper, worker, walker, visitor])
	var kay: TownWalker = town.walkers["kay"]
	var wren: TownWalker = town.walkers["wren"]
	var walt: TownWalker = town.walkers["walt"]
	var vi: TownWalker = town.walkers["vi"]
	# walt is on its way home when the meeting starts.
	walt.step(25.0)
	walt.step(0.5)
	assert_true(walt.is_walking(), "walt is between its work and its House")
	for pair: Array in [[kay, &"Forge"], [wren, mill], [walt, mill]]:
		var other: TownWalker = pair[0]
		vi.linger_at(town.free_point(Vector3(-12.0, 0.0, 12.0)), &"Idle_B", NAN, 1.0e6)
		assert_true(town.play_meeting("vi", other.hero_id, _facts()), other.hero_id)
		_step_until_met(vi, other)
		var trips: int = vi.trips
		_step_until_working(town, other, pair[1])
		assert_eq(other.activity, TownWalker.WORK, "%s is back at work" % other.hero_id)
		for _step: int in 400:
			vi.step(0.1)
			if vi.trips > trips:
				break
		assert_gt(vi.trips, trips, "and the visitor goes back to its own trips")


func test_a_meeting_not_reached_in_thirty_seconds_is_dropped_and_both_go_back_to_their_plans() -> void:
	var town: TownView = _town_view()
	var pair: Array[TownWalker] = _two_wanderers(town, Vector3(9.0, 0.0, 0.0))
	assert_true(town.play_meeting("ada", "bea", _facts()))
	var trips: int = pair[1].trips
	pair[0].step(TownWalker.MEETING_SECONDS + 1.0)
	pair[1].step(TownWalker.MEETING_SECONDS + 1.0)
	assert_eq([pair[0].chats, pair[1].chats], [0, 0], "they never came together")
	assert_false(pair[0].is_meeting() or pair[1].is_meeting())
	assert_eq(pair[1].trips, trips + 1, "the one who waited goes on to its next trip")
	assert_true(town.play_meeting("ada", "bea", _facts()), "and may meet again")


## A partner's greeting of the body is its own: a meeting leaves its facts and its next pick alone.
func test_a_meeting_leaves_the_partners_greeting_of_the_body_as_it_was() -> void:
	var town: TownView = _town_view()
	var pair: Array[TownWalker] = _two_wanderers(town, Vector3(9.0, 0.0, 0.0))
	var body := Node3D.new()
	town.add_child(body)
	body.position = pair[0].position + Vector3(12.0, 0.0, 0.0)
	var facts: Dictionary = {"kinds": ["met"] as Array[String], "slots": {"name": "Ada", "place": "here"}, "start": 0}
	pair[0].facts = facts
	pair[0].follow(body)
	body.position = pair[0].position + Vector3(2.0, 0.0, 0.0)
	pair[0].step(0.1)
	assert_eq(pair[0].greetings, 1)
	var said: String = (pair[0].get_node("Line") as Label3D).text
	for _step: int in 45:
		pair[0].step(0.1)
	body.position = pair[0].position + Vector3(20.0, 0.0, 0.0)
	pair[0].step(0.1)
	assert_true(town.play_meeting("ada", "bea", _facts()))
	_step_until_met(pair[0], pair[1])
	assert_eq(pair[0].greetings, 1, "the meeting was no greeting")
	assert_eq(pair[0].facts, facts, "its facts are the body's")
	assert_eq(pair[0]._meetings, 1, "its next pick is still the second line")
	assert_eq((pair[0].get_node("Line") as Label3D).text, "Morning, Bea. Quiet around the Forge today.", "and the line it says now is the meeting's")
	assert_ne(said, "Morning, Bea. Quiet around the Forge today.")


## ---- the hub hears it (Hub._on_social_recorded)

func test_a_meeting_between_two_shown_figures_is_played_in_the_town_and_changes_no_roster() -> void:
	_housed("ada", HOUSE_A)
	_housed("bea", HOUSE_B)
	var hub: Node3D = _hub()
	var town: TownView = hub.get_node("%Town") as TownView
	watch_signals(GameSession)
	_roll(60.0)
	assert_eq(_encounters().size(), 1)
	assert_true(town.walkers["ada"].is_meeting() and town.walkers["bea"].is_meeting(), "both figures are told")
	assert_signal_not_emitted(GameSession, "roster_changed", "a chat runs no roster cascade")


func test_the_eighth_meeting_says_who_grew_close_once_and_none_before_it() -> void:
	_housed("ada", HOUSE_A)
	_housed("bea", HOUSE_B)
	var hub: Node3D = _hub()
	var status: Label = hub.get_node("%Status") as Label
	status.text = "before"
	for meeting: int in 7:
		_roll(3600.0)
		assert_eq(status.text, "before", "meeting %d" % (meeting + 1))
	assert_eq(BALANCE.bond_threshold, BALANCE.bond_points_encounter * 8, "eight chats make a bond")
	_roll(3600.0)
	assert_eq(status.text, "ada and bea grew close.")
	assert_eq(hub._partner_signs(hub._roster_names())["ada"], "♥ bea")
	status.text = "before"
	_roll(3600.0)
	assert_eq(status.text, "before", "said once")


func test_a_meeting_redraws_the_roster_only_when_a_partner_sign_changes() -> void:
	_housed("ada", HOUSE_A)
	_housed("bea", HOUSE_B)
	var hub: Node3D = _hub()
	hub._open(&"Forge")
	var roster: ItemList = hub.get_node("%RosterList") as ItemList
	assert_eq(roster.item_count, 2)
	for index: int in roster.item_count:
		roster.set_item_tooltip(index, "MARK")
	for meeting: int in 7:
		_roll(3600.0)
		assert_eq(roster.get_item_tooltip(0), "MARK", "meeting %d: no sign changed, no redraw" % (meeting + 1))
	_roll(3600.0)
	assert_ne(roster.get_item_tooltip(0), "MARK", "the eighth: the bond shows, the rows are drawn again")
	assert_string_contains(roster.get_item_text(0), "♥ bea")


func test_a_meeting_redraws_the_open_detail_only_of_the_hero_it_names() -> void:
	_housed("ada", HOUSE_A)
	_housed("bea", HOUSE_B)
	_housed("cy", Vector2i(4, 2))
	var hub: Node3D = _hub()
	hub._open(&"Forge")
	_select_hero(hub, "cy")
	var refreshes: int = hub.detail_refreshes
	_roll(60.0)
	assert_eq(_encounters().size(), 1)
	assert_eq(hub.detail_refreshes, refreshes, "cy is not named")
	_select_hero(hub, "ada")
	refreshes = hub.detail_refreshes
	_roll(3600.0)
	assert_eq(_encounters().size(), 2)
	assert_eq(hub.detail_refreshes, refreshes + 1, "ada is named: one redraw")


func test_a_meeting_that_names_the_body_gives_its_new_partner_the_met_greeting_and_no_walk_to_it() -> void:
	_housed("ada", HOUSE_A)
	_housed("bea", HOUSE_B)
	var hub: Node3D = _hub()
	var town: TownView = hub.get_node("%Town") as TownView
	assert_true(GameSession.embody_hero("ada"), GameSession.last_action_error)
	assert_null(town.partner)
	for _meeting: int in 8:
		_roll(3600.0)
	assert_not_null(town.partner, "eight chats make bea ada's partner")
	assert_eq(town.partner.hero_id, "bea")
	assert_eq(town.partner.facts["kinds"][0], "met", "a bond of chats greets with a chat (then the quirk)")
	assert_false(town.walkers["bea"].is_meeting(), "the body is no figure to walk to")


## Ruling of Sol's r1 (F1): a new chat at the cap evicts the oldest one, and that can end a bond between two heroes
## the new records do not name. The hub redraws by the heroes its look re-read, not by the heroes the records name.
func test_a_chat_that_evicts_the_oldest_one_at_the_cap_ends_another_pairs_bond_and_the_hub_redraws_it() -> void:
	_housed("ada", HOUSE_A)
	_housed("bea", HOUSE_B)
	_add_hero("cy")
	_add_hero("dot")
	for _meeting: int in 8:
		GameSession._record("encounter", {"heroes": ["cy", "dot"], "place": "House_1", "why": "neighbours"})
	var seq: int = GameSession.ledger_next_seq
	while GameSession.ledger.size() < BALANCE.ledger_max_records:
		Ledger.append(GameSession.ledger, seq, 0, "summoned", {"hero": "filler:%d" % seq, "name": "F", "rank": 0})
		seq += 1
	GameSession.ledger_next_seq = seq
	assert_eq(GameSession.ledger.size(), BALANCE.ledger_max_records, "the real cap")
	assert_eq(BALANCE.bond_threshold, BALANCE.bond_points_encounter * 8, "eight chats is exactly a bond")
	var hub: Node3D = _hub()
	hub._open(&"Forge")
	assert_true(GameSession.embody_hero("cy"), GameSession.last_action_error)
	_select_hero(hub, "cy")
	var roster: ItemList = hub.get_node("%RosterList") as ItemList
	assert_eq(hub._partner_id, "dot", "cy the body and dot are a bond of exactly eight chats")
	assert_true(hub._partner_signs(hub._roster_names())["cy"].contains("dot"))
	var refreshes: int = hub.detail_refreshes
	_roll(60.0)
	assert_eq(_encounters().size(), 8, "ada and bea met and the oldest of cy and dot's eight went")
	assert_eq(hub._partner_id, "", "cy's partner is gone: the body's greeting was redrawn")
	assert_eq(hub._partner_signs(hub._roster_names()).get("cy", ""), "", "cy's sign is gone")
	for index: int in roster.item_count:
		if (roster.get_item_metadata(index) as Hero).instance_id == "cy":
			assert_false(roster.get_item_text(index).contains("dot"), "cy's roster row was drawn again")
	assert_gt(hub.detail_refreshes, refreshes, "cy's open detail was drawn again")


func _select_hero(hub: Node3D, hero_id: String) -> void:
	var roster: ItemList = hub.get_node("%RosterList") as ItemList
	for index: int in roster.item_count:
		if (roster.get_item_metadata(index) as Hero).instance_id == hero_id:
			roster.select(index)
			roster.multi_selected.emit(index, true)


func _hub() -> Node3D:
	var hub: Node3D = (load("res://hub/hub.tscn") as PackedScene).instantiate() as Node3D
	add_child_autofree(hub)
	return hub


func _facts() -> Dictionary:
	return Lines.meeting_facts({"seq": 0, "heroes": ["ada", "bea"], "place": "Forge"}, {"ada": "Ada", "bea": "Bea"})


## Ada and Bea standing on free ground, Bea offset from Ada, both lingering for good.
func _two_wanderers(town: TownView, offset: Vector3) -> Array[TownWalker]:
	var ada: Hero = _add_hero("ada")
	var bea: Hero = _add_hero("bea")
	town.show_walkers([ada, bea])
	var a: TownWalker = town.walkers["ada"]
	var b: TownWalker = town.walkers["bea"]
	var start: Vector3 = town.free_point(Vector3(-12.0, 0.0, 12.0))
	a.linger_at(start, &"Idle_B", NAN, 1.0e6)
	b.linger_at(town.free_point(start + offset) if offset.length() > 2.0 else start + offset, &"Idle_B", NAN, 1.0e6)
	return [a, b]


func _step_until_met(a: TownWalker, b: TownWalker) -> void:
	for _step: int in 1200:
		if a.chats > 0 and b.chats > 0:
			return
		a.step(0.1)
		b.step(0.1)
	fail_test("%s and %s never met" % [a.hero_id, b.hero_id])


func _step_until_working(town: TownView, walker: TownWalker, post: StringName) -> void:
	for _step: int in 3000:
		walker.step(0.1)
		if walker.activity == TownWalker.WORK and walker.position.distance_to(town.work_spot(post)) < 0.1:
			return
	fail_test("%s never got back to work" % walker.hero_id)


func _town_view() -> TownView:
	var world := Node3D.new()
	var town: TownView = (load("res://hub/town/town.tscn") as PackedScene).instantiate() as TownView
	world.add_child(town)
	add_child_autofree(world)
	town.show_buildings(GameSession.town_buildings)
	return town


func _encounters() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for record: Dictionary in GameSession.ledger:
		if record["kind"] == "encounter":
			records.append(record)
	return records


func _shapes() -> Array:
	return _encounters().map(func(record: Dictionary) -> Array: return [record["heroes"], record["place"], record["why"]])


## The roll's table: a copy of the shipped one with its own chance, never a change to the shared balance.tres.
func _chance(chance: float) -> void:
	_balance = BALANCE.duplicate() as BalanceTable
	_balance.encounter_chance_per_minute = chance


## The live tick's roll, with this test's table (tick_expeditions passes the shipped one).
func _roll(seconds: float) -> void:
	GameSession._roll_encounters(seconds, _balance)


func _housed(hero_name: String, hex: Vector2i) -> Hero:
	var hero: Hero = _add_hero(hero_name)
	assert_true(GameSession.assign_home(hero, _place(TownRules.HOUSE, hex)), GameSession.last_action_error)
	return hero


func _stationed(hero_name: String, hall: StringName, hex: Vector2i) -> Hero:
	var hero: Hero = _housed(hero_name, hex)
	assert_true(GameSession.station_hero(hero, hall), GameSession.last_action_error)
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


func _hero(id: String, home: StringName = NO_HOME, station: StringName = NO_STATION) -> Hero:
	var hero := Hero.new(id, 0)
	hero.instance_id = id
	hero.home = home
	hero.station = station
	return hero


func _house(id: String, hex: Vector2i) -> Dictionary:
	return {"id": id, "type": "House", "q": hex.x, "r": hex.y}


func _town(extra: Array[Dictionary]) -> Array[Dictionary]:
	var buildings: Array[Dictionary] = TownRules.default_halls()
	buildings.append_array(extra)
	return buildings
