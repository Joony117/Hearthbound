extends GutTest

## ig-m6o.2.1: bonds and dreams, slice 1 (SYSTEMS.md § Bonds and dreams, slice 1).

const BALANCE: BalanceTable = preload("res://balance.tres")
const ZONE: String = "verdant_outskirts"
const A: String = "hero:a"
const B: String = "hero:b"
const C: String = "hero:c"
const D: String = "hero:d"
const E: String = "hero:e"
const F: String = "hero:f"
const G: String = "hero:g"
const NAMES: Dictionary = {A: "Ada", B: "Bea", C: "Cal"}
## Tables in the one meal time the cost and read checks below take (ig-m6o.2.2.5, ACC 5 and 10).
const MEAL_TABLES: int = 8

var _ledger: Array[Dictionary] = []
## A threshold of 1, so a tally shows for every fact.
var _counting: BalanceTable


func before_each() -> void:
	_ledger = []
	_counting = BALANCE.duplicate() as BalanceTable
	_counting.bond_threshold = 1
	GameSession.set_process(false)
	GameSession.from_dict({"roster": []})


func after_each() -> void:
	_set_key(KEY_W, false)
	SaveService.load_blocked = false
	GameSession.set_process(true)


## ---- the bond reader

func test_each_fact_scores_alone_and_a_routine_victory_scores_nothing() -> void:
	_battle([A, B], "victory")
	assert_eq(_bond(A), {}, "a routine victory scores 0")
	_battle([A, B], "retreated")
	assert_eq([_bond(A)["points"], _bond(A)["hard"]], [1, 1], "a hard battle")
	_ledger = []
	_battle([A, B], "victory", {"moments": [_moment("revived", A, B)]})
	assert_eq([_bond(A)["points"], _bond(A)["saves"], _bond(A)["fact"]["kind"]], [4, 1, "saved_by"], "a save, and its battle is hard")
	assert_eq(_bond(B)["fact"]["kind"], "saved", "either way round")
	_ledger = []
	_battle([A, B], "victory", {"rescued": [B], "rescuers": [A]})
	assert_eq([_bond(B)["points"], _bond(B)["rescues"]], [6, 1], "a rescue plus its hard battle, toward the rescuer (the rescuer's side is under the layers)")
	_ledger = []
	_battle([A, B, C], "stranded", {"order": "order:1"})
	_record("died", {"hero": C, "name": "Cal", "battle_order": "order:1"})
	var witnessed: Dictionary = Bonds.bond(_ledger, A, {A: true, B: true}, _counting)
	assert_eq([witnessed["points"], witnessed["deaths"], witnessed["fact"]["dead"]], [6, 1, C], "a death seen together")


func test_a_fact_counts_once_per_record_for_a_pair() -> void:
	_battle([A, B], "victory", {"moments": [_moment("revived", A, B), _moment("carried", A, B), _moment("revived", B, A)]})
	assert_eq([_bond(A)["points"], _bond(A)["saves"], _bond(A)["saving"]], [5, 1, 1], "hard 1, saved-by 3 and saving 1: each side once, however many moments")


func test_a_pair_at_the_threshold_bonds_and_one_short_does_not() -> void:
	_battle([A, B], "victory", {"moments": [_moment("revived", A, B)]})
	for _index: int in 3:
		_battle([A, B], "retreated")
	assert_eq(Bonds.bond(_ledger, A, _living(), BALANCE), {}, "4 + 3 = 7, one short of 8")
	_battle([A, B], "retreated")
	assert_eq(Bonds.bond(_ledger, A, _living(), BALANCE)["partner"], B, "8 bonds")


func test_a_dead_hero_is_never_a_bond() -> void:
	for _index: int in 3:
		_battle([A, B], "victory", {"moments": [_moment("revived", A, B)]})
	assert_eq(Bonds.bond(_ledger, A, {A: true, C: true}, BALANCE), {}, "B is not on the roster")


func test_ties_go_to_the_more_recent_fact_then_the_lower_id() -> void:
	for _index: int in 2:
		_battle([A, B, C], "victory", {"moments": [_moment("revived", A, B), _moment("revived", A, C)]})
	assert_eq(Bonds.bond(_ledger, A, _living(), BALANCE)["partner"], B, "same points, same last fact: the lower id")
	_ledger = []
	_battle([A, C], "victory", {"moments": [_moment("revived", A, C)]})
	for _index: int in 2:
		_battle([A, B], "victory", {"moments": [_moment("revived", A, B)]})
	_battle([A, C], "victory", {"moments": [_moment("revived", A, C)]})
	assert_eq(Bonds.bond(_ledger, A, _living(), BALANCE)["partner"], C, "C shared the latest fact")


## ---- ig-m6o.2.2.6: the layers and the roles (SYSTEMS.md § Bonds and dreams, Layers and roles)

func test_a_save_and_a_rescue_score_the_saved_more_than_the_saver() -> void:
	_battle([A, B], "victory", {"moments": [_moment("revived", A, B)]})
	assert_eq([_bond(A)["points"], _bond(A)["saves"], _bond(A)["saving"], _bond(A)["fact"]["kind"]], [4, 1, 0, "saved_by"], "A was saved by B: hard 1 + saved-by 3")
	assert_eq([_bond(B)["points"], _bond(B)["saves"], _bond(B)["saving"], _bond(B)["fact"]["kind"]], [2, 0, 1, "saved"], "B saved A: hard 1 + saving 1")
	_ledger = []
	_battle([A, B], "victory", {"rescued": [B], "rescuers": [A]})
	assert_eq([_bond(B)["points"], _bond(B)["rescues"], _bond(B)["rescuing"], _bond(B)["fact"]["kind"]], [6, 1, 0, "saved_by"], "B was rescued by A: hard 1 + rescued-by 5")
	assert_eq([_bond(A)["points"], _bond(A)["rescues"], _bond(A)["rescuing"], _bond(A)["fact"]["kind"]], [3, 0, 1, "saved"], "A rescued B: hard 1 + rescuing 2")


func test_a_save_each_way_in_one_fight_scores_both_sides_and_evicts_exactly() -> void:
	_battle([A, B], "victory", {"moments": [_moment("revived", A, B), _moment("revived", B, A)]})
	for id: String in [A, B]:
		var found: Dictionary = _bond(id)
		assert_eq([found["points"], found["hard"], found["saves"], found["saving"]], [5, 1, 1, 1], "%s: hard 1 + saved-by 3 + saving 1" % id)
	assert_eq(Bonds.bond_line(_bond(A), NAMES, false), "Closest to Bea: 1 hard fight, 2 saves.", "two saves happened")
	var folded: Dictionary = Bonds.index_state(_ledger, _counting)
	assert_true(Bonds.fold_out(folded, _ledger[0], _counting), "the fold takes the record back out")
	assert_eq(_nonempty(folded["pairs"]), _nonempty(Bonds.index([] as Array[Dictionary], _counting)), "and every count with it")
	assert_true(_layers_have_their_facts(folded["counts"]))


func test_a_pair_holding_only_the_saving_or_the_rescuing_side_keeps_it_as_its_fact() -> void:
	# A is in the team and revives B, who is named only in rescuers: no hard pair, no rescue pair, only A's saving (1 point).
	_battle([A], "victory", {"moments": [_moment("revived", B, A)], "rescuers": [B]})
	assert_eq([_bond(A)["points"], _bond(A)["hard"], _bond(A)["saving"], _bond(A)["fact"]["kind"]], [1, 0, 1, "saved"])
	_meeting(A, B)
	assert_eq([_bond(A)["points"], _bond(A)["fact"]["kind"], _bond(A)["fact"]["points"]], [2, "saved", 1], "a newer chat does not displace it")
	_meal([A, B])
	assert_eq([_bond(A)["points"], _bond(A)["fact"]["kind"]], [3, "saved"], "nor a newer meal")
	# A rescues B, who is outside the team: A's rescuing (2 points) is the only battle slot toward B.
	_ledger = []
	_battle([A], "stranded", {"rescued": [B], "rescuers": [A]})
	assert_eq([_bond(A)["points"], _bond(A)["hard"], _bond(A)["rescuing"], _bond(A)["fact"]["kind"]], [2, 0, 1, "saved"])
	_meeting(A, B)
	_meal([A, B])
	assert_eq([_bond(A)["points"], _bond(A)["fact"]["kind"], _bond(A)["fact"]["points"]], [4, "saved", 2], "a chat and a meal do not displace it")
	assert_eq([_bond(B)["points"], _bond(B)["rescues"], _bond(B)["fact"]["kind"]], [7, 1, "saved_by"], "B, rescued, holds the received side: 5 + 1 + 1")


func test_respect_goes_to_the_one_who_outkilled_you_in_a_hard_fight_only() -> void:
	_battle([A, B], "retreated", {"kills": {A: 1, B: 3}})
	assert_eq([_bond(A)["respect"], _bond(B)["respect"]], [1, 0], "A toward B; B toward A nothing")
	assert_eq([_bond(A)["points"], _bond(B)["points"]], [1, 1], "respect adds no affection")
	_battle([A, B], "retreated", {"kills": {A: 2, B: 2}})
	assert_eq([_bond(A)["respect"], _bond(B)["respect"]], [1, 0], "a tie scores nothing")
	_battle([A, B], "victory", {"kills": {A: 0, B: 9}})
	assert_eq([_bond(A)["respect"], _bond(B)["respect"]], [1, 0], "a routine victory scores no respect")
	_battle([A, B], "retreated")
	assert_eq([_bond(A)["respect"], _bond(B)["respect"]], [1, 0], "a record with no kills counts every hero at 0")
	_battle([A, B], "retreated", {"kills": {A: "x", B: 2}})
	assert_eq([_bond(A)["respect"], _bond(B)["respect"]], [2, 0], "a value that is not a number counts 0")
	_battle([A, B], "retreated", {"kills": "lots"})
	assert_eq([_bond(A)["respect"], _bond(B)["respect"]], [2, 0], "and so does kills that is not a dictionary")
	assert_eq(Bonds.bond_line(_bond(A), NAMES, false), "Closest to Bea: 5 hard fights.", "five hard fights (the routine victory is none), and the line names no respect")


func test_kills_read_as_floats_after_a_load_score_the_same() -> void:
	for index: int in 3:
		_battle([A, B], "retreated", {"kills": {A: index, B: 3}})
	var loaded: Array[Dictionary] = []
	loaded.assign(JSON.parse_string(JSON.stringify(_ledger)) as Array)
	assert_eq(Bonds.bond(loaded, A, _living(), _counting)["respect"], 3, "a JSON number is a float")
	assert_eq(Bonds.bond(loaded, A, _living(), _counting), Bonds.bond(_ledger, A, _living(), _counting))
	assert_eq(Bonds.roles(Bonds.index(loaded, BALANCE), A, _living(), BALANCE), Bonds.roles(Bonds.index(_ledger, BALANCE), A, _living(), BALANCE))


func test_a_coworker_meeting_counts_teamwork_both_ways_and_a_neighbour_meeting_does_not() -> void:
	_meeting(A, B, "House_1", "neighbours")
	assert_eq([_bond(A)["teamwork"], _bond(B)["teamwork"], _bond(A)["meetings"]], [0, 0, 1])
	_meeting(A, B, "Forge", "coworkers")
	assert_eq([_bond(A)["teamwork"], _bond(B)["teamwork"], _bond(A)["meetings"], _bond(A)["points"]], [1, 1, 2, 2], "teamwork adds no affection")
	assert_eq(Bonds.bond_line(_bond(A), NAMES, false), "Closest to Bea: 2 chats.", "and is not named")
	_ledger = []
	_meeting(A, C, "Forge", "coworkers")
	assert_eq([_bond(A)["fact"]["kind"], _bond(A)["teamwork"]], ["met", 1], "a pair with only coworker meetings keeps the meeting as its fact")
	_meal([A, C])
	assert_eq(_bond(A)["fact"]["kind"], "meal", "teamwork is not a battle fact: the newer meal takes it, as after a plain chat")
	var folded: Dictionary = Bonds.index_state(_ledger, _counting)
	assert_true(Bonds.fold_out(folded, _ledger[0], _counting))
	assert_eq(folded["counts"][A][C][Bonds.TEAMWORK][0], 0, "evicting the meeting takes its teamwork out")


func test_a_friend_at_the_threshold_and_not_one_under() -> void:
	_battle([A, B], "victory", {"moments": [_moment("revived", A, B)]})
	for _index: int in 3:
		_battle([A, B], "retreated")
	assert_eq(_roles(A)["friends"], [] as Array[String], "4 + 3 = 7")
	_battle([A, B], "retreated")
	assert_eq(_roles(A)["friends"], [B] as Array[String], "8")
	assert_eq(_roles(B)["friends"], [] as Array[String], "B, who saved A, is at 2 + 4 = 6: friendship is directed")


func test_a_rival_needs_respect_at_the_threshold_both_ways() -> void:
	for _index: int in 3:
		_battle([A, B], "retreated", {"kills": {A: 0, B: 2}})
	for _index: int in 2:
		_battle([A, B], "retreated", {"kills": {A: 2, B: 0}})
	assert_eq([_bond(A)["respect"], _bond(B)["respect"]], [3, 2])
	assert_eq([_roles(A)["rivals"], _roles(B)["rivals"]], [[] as Array[String], [] as Array[String]], "3 one way and 2 the other")
	_battle([A, B], "retreated", {"kills": {A: 2, B: 0}})
	assert_eq([_roles(A)["rivals"], _roles(B)["rivals"]], [[B] as Array[String], [A] as Array[String]], "3 and 3")


func test_a_collaborator_needs_four_coworker_meetings() -> void:
	for _index: int in 3:
		_meeting(A, B, "Forge", "coworkers")
	_meeting(A, C, "House_1", "neighbours")
	assert_eq(_roles(A)["collaborators"], [] as Array[String], "3")
	_meeting(A, B, "Forge", "coworkers")
	assert_eq([_roles(A)["collaborators"], _roles(B)["collaborators"]], [[B] as Array[String], [A] as Array[String]], "4, both ways")


func test_one_pair_can_be_friend_rival_and_collaborator_and_a_dead_hero_holds_no_role() -> void:
	for _index: int in 3:
		_battle([A, B], "retreated", {"kills": {A: 0, B: 2}})
		_battle([A, B], "retreated", {"kills": {A: 2, B: 0}})
	for _index: int in 4:
		_meeting(A, B, "Forge", "coworkers")
	var roles: Dictionary = _roles(A)
	assert_eq([roles["friends"], roles["rivals"], roles["collaborators"]], [[B] as Array[String], [B] as Array[String], [B] as Array[String]], "6 fights and 4 chats: affection 10, respect 3 each way, teamwork 4")
	roles = _roles(A, {A: true, C: true})
	assert_eq([roles["friends"], roles["rivals"], roles["collaborators"]], [[] as Array[String], [] as Array[String], [] as Array[String]], "B is not living")


func test_roles_list_the_strongest_first_then_the_latest_fact_then_the_lower_id() -> void:
	var everyone: Dictionary = {A: true, B: true, C: true, D: true, E: true, F: true}
	for _index: int in 9:
		_meal([A, E, F])
	for _index: int in 9:
		_meeting(A, B)
	for _index: int in 10:
		_meeting(A, C)
	for _index: int in 9:
		_meeting(A, D)
	assert_eq(_roles(A, everyone)["friends"], [C, D, B, E, F] as Array[String], "C 10; then 9 by the latest fact: D, B, then E and F, whose last record is the same meal, by id")
	assert_eq(str(Bonds.bond_from(Bonds.index(_ledger, BALANCE), A, everyone, BALANCE)["partner"]), C, "the partner is the first friend")
	_ledger = []
	for _index: int in 3:
		_battle([A, B], "retreated", {"kills": {A: 0, B: 2}})
		_battle([A, B], "retreated", {"kills": {A: 2, B: 0}})
		_battle([A, C], "retreated", {"kills": {A: 0, B: 0, C: 2}})
	for _index: int in 4:
		_battle([A, C], "retreated", {"kills": {A: 2, C: 0}})
	assert_eq(_roles(A, everyone)["rivals"], [C, B] as Array[String], "respect together: C 3 + 4, B 3 + 3")
	_ledger = []
	for _index: int in 4:
		_meeting(A, C, "Forge", "coworkers")
	for _index: int in 5:
		_meeting(A, B, "Forge", "coworkers")
	assert_eq(_roles(A, everyone)["collaborators"], [B, C] as Array[String], "teamwork: B 5, C 4")


func test_bonds_and_roles_are_derived_and_save_nothing() -> void:
	_hero(A, "Ada")
	_hero(B, "Bea")
	for _index: int in 3:
		GameSession._record("battle", {"order": "order:%d" % GameSession.ledger.size(), "zone": ZONE, "team": [A, B], "result": "retreated", "moments": [], "kills": {A: 0, B: 2}})
		GameSession._record("battle", {"order": "order:%d" % GameSession.ledger.size(), "zone": ZONE, "team": [A, B], "result": "retreated", "moments": [], "kills": {A: 2, B: 0}})
	for _index: int in 4:
		GameSession._record("encounter", {"heroes": [A, B], "place": "Forge", "why": "coworkers"})
	var roles: Dictionary = Bonds.roles(GameSession.bond_index(), A, {A: true, B: true}, BALANCE)
	assert_eq(roles["rivals"], [B] as Array[String], "the game holds the layers")
	var saved: String = JSON.stringify(GameSession.to_dict())
	for key: String in ["respect", "teamwork", "rival", "rivals", "friends", "collaborators", "roles", "saving", "rescuing"]:
		assert_false(saved.contains("\"%s\"" % key), "a save carries no \"%s\" key" % key)
	var data: Dictionary = GameSession.to_dict()
	data["ledger"] = JSON.parse_string(JSON.stringify(GameSession.ledger))
	GameSession.from_dict(data)
	assert_eq(Bonds.roles(GameSession.bond_index(), A, {A: true, B: true}, BALANCE), roles, "a load rebuilds the same roles from the ledger (its JSON kills come back whole through Ledger.normalized)")


func test_legacy_records_score_no_rescue_or_witness_points_and_raise_nothing() -> void:
	_battle([A, B], "victory", {"rescued": [B], "order": "order:1"})
	_record("died", {"hero": C, "name": "Cal"})
	_record("died", {"hero": "hero:gone", "name": "Gone", "battle_order": "order:missing"})
	var found: Dictionary = _bond(A)
	assert_eq([found["points"], found["hard"], found["rescues"], found["deaths"]], [1, 1, 0, 0])


func test_the_lines() -> void:
	for _index: int in 2:
		_battle([A, B, C], "stranded", {"order": "order:%d" % _ledger.size(), "rescued": [B], "rescuers": [A]})
	_record("died", {"hero": C, "name": "Cal", "battle_order": "order:0"})
	var found: Dictionary = Bonds.bond(_ledger, A, {A: true, B: true}, BALANCE)
	assert_eq(Bonds.bond_line(found, NAMES, false), "Closest to Bea: 2 hard fights, 2 rescues, 1 death seen together.")
	assert_eq(Bonds.bond_line(found, NAMES, true), "Closest to Bea (away): 2 hard fights, 2 rescues, 1 death seen together.")


## ---- ig-m6o.2.2.4: encounters are bond points

## ACC 5: eight chats are a bond. Its fact is "met" with the place of the latest chat, since the pair has no
## other fact, and either hero's bond names the other.
func test_eight_encounters_make_a_bond_and_the_pair_fact_is_met_with_its_place() -> void:
	for _index: int in 7:
		_meeting(A, B)
	assert_eq(Bonds.bond(_ledger, A, _living(), BALANCE), {}, "7 chats, one short of 8")
	_meeting(A, B, "Forge")
	var found: Dictionary = Bonds.bond(_ledger, A, _living(), BALANCE)
	assert_eq([found["partner"], found["points"], found["meetings"], found["hard"], found["last_seq"]], [B, 8, 8, 0, 8])
	assert_eq(found["fact"], {"kind": "met", "points": 1, "seq": 8, "zone": "", "dead": "", "place": "Forge"})
	assert_eq(Bonds.bond(_ledger, B, _living(), BALANCE)["partner"], A, "either way round")
	assert_eq(Bonds.bond_line(found, NAMES, false), "Closest to Bea: 8 chats.")
	assert_eq(_bond(C), {}, "Cal met no one")


## A chat is 1 point, the same as a hard fight, and it counts toward the points and the last shared fact, but
## a pair with a battle fact keeps it as the fact whichever is newer (SYSTEMS: a battle fact still beats it).
func test_a_chat_never_displaces_a_battle_fact_but_still_counts() -> void:
	_battle([A, B], "retreated")
	_meeting(A, B)
	var found: Dictionary = _bond(A)
	assert_eq([found["points"], found["hard"], found["meetings"], found["last_seq"]], [2, 1, 1, 2], "the chat counts")
	assert_eq([found["fact"]["kind"], found["fact"]["seq"], found["fact"]["place"]], ["hard", 1, ""], "the older hard fight stays the fact")
	_ledger = []
	_meeting(A, B)
	_battle([A, B], "victory", {"moments": [_moment("revived", A, B)]})
	found = _bond(A)
	assert_eq([found["points"], found["fact"]["kind"], found["fact"]["place"]], [5, "saved_by", ""], "a newer save beats an older chat")
	_ledger = []
	for _index: int in 8:
		_battle([A, C], "retreated")
	for _index: int in 8:
		_meeting(A, B)
	assert_eq(Bonds.bond(_ledger, A, _living(), BALANCE)["partner"], B, "8 points each: the pair whose last shared fact is a chat, and newer, wins the tie")


func test_the_bond_line_counts_chats_last() -> void:
	_meeting(A, B)
	assert_eq(Bonds.bond_line(_bond(A), NAMES, false), "Closest to Bea: 1 chat.")
	_battle([A, B], "retreated")
	_battle([A, B], "retreated")
	_meeting(A, B)
	assert_eq(Bonds.bond_line(_bond(A), NAMES, false), "Closest to Bea: 2 hard fights, 2 chats.")


## ACC 5: a load accepts any record with a seq and a kind, so an encounter that does not name two different
## non-empty strings counts nothing: in a build, a fold in and a fold out, by one rule.
func test_a_hand_edited_encounter_counts_nothing_in_a_build_a_fold_in_and_a_fold_out() -> void:
	var bad: Array[Dictionary] = [
		{"heroes": [A, B, C]}, {"heroes": [A]}, {"heroes": []}, {"heroes": [A, A]}, {"heroes": [A, ""]}, {"heroes": [A, 5]},
		{"heroes": [A, null]}, {"heroes": "ab"}, {"heroes": {A: B}}, {"place": "House_1"},
	]
	for fields: Dictionary in bad:
		_record("encounter", fields)
	assert_eq(_nonempty(Bonds.index(_ledger, _counting)), {}, "a build counts none")
	var folded: Dictionary = Bonds.index_state([] as Array[Dictionary], _counting)
	for record: Dictionary in _ledger:
		Bonds.fold_in(folded, record, _counting)
	assert_eq([_nonempty(folded["pairs"]), folded["version"], folded["touched"]], [{}, 0, {}], "a fold in counts none and touches no one")
	for record: Dictionary in _ledger:
		assert_true(Bonds.fold_out(folded, record, _counting), "a fold out takes out what was never counted")
	assert_eq([_nonempty(folded["pairs"]), folded["outs"], folded["out_all"], folded["out_named"]], [{}, bad.size(), 0, {A: 7, B: 1, C: 1, "": 5, "5": 6, "<null>": 7}], "and marks the strings it holds, everyone none")


## Folding encounters in, then out oldest first (as the eviction tiers do), equals a rebuild of what is left at
## every step. A fold in touches both heroes, so the hub's look (ig-7sn.16) re-reads them. Taking out the
## newest of two chats of a pair, which the eviction never does, is refused so the caller rebuilds.
func test_folding_encounters_in_and_out_equals_a_rebuild_and_touches_both_heroes() -> void:
	var folded: Dictionary = Bonds.index_state(_ledger, BALANCE)
	for index: int in 10:
		_meeting(A if index % 3 != 0 else C, B)
		Bonds.fold_in(folded, _ledger.back(), BALANCE)
		assert_eq(_nonempty(folded["pairs"]), _nonempty(Bonds.index(_ledger, BALANCE)), "in %d" % index)
		assert_eq([folded["version"], (folded["touched"] as Dictionary).get(B)], [index + 1, index + 1], "B is touched by every chat")
		assert_eq((folded["touched"] as Dictionary).has(D), false)
	assert_eq(folded["pairs"][B][A]["meetings"], 6, "6 of the 10 were with Ada")
	while not _ledger.is_empty():
		var oldest: Dictionary = _ledger.pop_front()
		assert_true(Bonds.fold_out(folded, oldest, BALANCE))
		assert_eq(_nonempty(folded["pairs"]), _nonempty(Bonds.index(_ledger, BALANCE)), "out %d" % oldest["seq"])
	assert_eq(_nonempty(folded["pairs"]), {}, "every chat is out")
	_meeting(A, B)
	_meeting(A, B)
	folded = Bonds.index_state(_ledger, BALANCE)
	assert_false(Bonds.fold_out(folded, _ledger[1], BALANCE), "the newest of two is the pair's latest, and the one before it is unknown")


## ig-7sn.21's marks, widened by ig-m6o.2.2.10: an encounter marks its two heroes and a meal its diners (welcome_home and
## fight_beside read them); an encounter that carries a name, one that says it rescued someone, and a kind the table does
## not list mark everyone.
func test_folding_out_an_encounter_or_a_meal_marks_its_heroes_and_a_named_one_or_an_unlisted_kind_marks_everyone() -> void:
	_meeting(A, B)
	_record("encounter", {"heroes": [A, C], "name": "odd"})
	_meal([A, B, C])
	_record("gossip", {"heroes": [A, B]})
	var folded: Dictionary = Bonds.index_state(_ledger, _counting)
	Bonds.fold_out(folded, _ledger[0], _counting)
	assert_eq([folded["outs"], folded["out_named"], folded["out_all"]], [1, {A: 1, B: 1}, 0], "an encounter marks its two heroes")
	Bonds.fold_out(folded, _ledger[1], _counting)
	assert_eq([folded["outs"], folded["out_all"]], [2, 2], "an encounter with a name marks everyone")
	Bonds.fold_out(folded, _ledger[2], _counting)
	assert_eq([folded["outs"], folded["out_named"], folded["out_all"]], [3, {A: 3, B: 3, C: 3}, 2], "a meal marks its diners")
	Bonds.fold_out(folded, _ledger[3], _counting)
	assert_eq([folded["outs"], folded["out_all"]], [4, 4], "a kind not listed marks everyone")
	assert_eq(Bonds.OUT_MARKS["encounter"], ["heroes"])
	assert_eq(Bonds.OUT_MARKS["meal"], ["diners"])


## The cover order counts meeting points, as it counts every point of the bond index: a Knight's back row is
## listed by points, most first, and a chatty one goes ahead of a rescued one.
func test_the_cover_order_counts_meeting_points() -> void:
	var knight: Hero = _hero(A, "Ada")
	knight.def_id = &"knight"
	for pair: Array in [[B, "Bea"], [C, "Cal"]]:
		_hero(pair[0], pair[1]).def_id = &"mage"
	_battle_in(GameSession.ledger, [A, B], "victory", {"rescued": [B], "rescuers": [A]})
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1
	for _index: int in 3:
		GameSession._record("encounter", {"heroes": [A, C], "place": "House_1", "why": "neighbours"})
	var team: Array[Hero] = [knight, GameSession.hero_by_id(B), GameSession.hero_by_id(C)]
	assert_eq(GameSession._cover_orders(team, BALANCE)[A], [B, C] as Array[String], "6 points of a rescue and a hard fight, then 3 of chats")
	for _index: int in 8:
		GameSession._record("encounter", {"heroes": [A, C], "place": "House_1", "why": "neighbours"})
	assert_eq(GameSession._cover_orders(team, BALANCE)[A], [C, B] as Array[String], "11 points of chats, and the bond of 8 or more goes first")


## ---- ig-m6o.2.2.5: meals are bond points

## Every diner scores every other diner: a table of three is three pairs, each way round, one meal each. Eight
## meals are a bond, and its fact is "meal" with the host's House of the latest one.
func test_eight_meals_make_a_bond_with_every_tablemate_and_the_pair_fact_is_meal_with_its_house() -> void:
	for _index: int in 7:
		_meal([A, B, C])
	assert_eq(Bonds.bond(_ledger, A, _living(), BALANCE), {}, "7 meals, one short of 8")
	_meal([A, B, C], "House_2")
	var found: Dictionary = Bonds.bond(_ledger, A, _living(), BALANCE)
	assert_eq([found["partner"], found["points"], found["meals"], found["meetings"], found["hard"], found["last_seq"]], [B, 8, 8, 0, 0, 8])
	assert_eq(found["fact"], {"kind": "meal", "points": 1, "seq": 8, "zone": "", "dead": "", "place": "House_2"})
	assert_eq(Bonds.bond(_ledger, C, _living(), BALANCE)["partner"], A, "Cal sat with Ada and Bea alike: the lower id wins the tie")
	assert_eq(Bonds.bond_line(found, NAMES, false), "Closest to Bea: 8 meals.")
	assert_eq(Bonds.index(_ledger, BALANCE)[B][C]["meals"], 8, "and every pair of the table, each way round")


## A meal is 1 point, the same as a hard fight, and it counts toward the points and the last shared fact, but a pair
## with a battle fact keeps that as the fact whichever is newer, and so with a chat.
func test_a_meal_never_displaces_a_battle_fact_but_still_counts() -> void:
	_battle([A, B], "retreated")
	_meal([A, B])
	_meal([A, B])
	_meeting(A, B)
	_meal([A, B])
	var found: Dictionary = _bond(A)
	assert_eq([found["points"], found["hard"], found["meals"], found["meetings"], found["last_seq"]], [5, 1, 3, 1, 5], "the meals and the chat count")
	assert_eq([found["fact"]["kind"], found["fact"]["seq"], found["fact"]["place"]], ["hard", 1, ""], "the older hard fight stays the fact, though every meal is newer")
	_ledger = []
	_meal([A, B])
	_battle([A, B], "victory", {"moments": [_moment("revived", A, B)]})
	assert_eq(_bond(A)["fact"]["kind"], "saved_by", "a newer save beats an older meal")


## A pair with only chats and meals picks its fact by the ordinary rule: the most points, else the later record.
func test_a_pair_with_only_chats_and_meals_picks_its_fact_by_the_ordinary_rule() -> void:
	_meeting(A, B)
	_meal([A, B])
	assert_eq(_bond(A)["fact"]["kind"], "meal", "same points: the later record")
	_ledger = []
	_meal([A, B])
	_meeting(A, B)
	assert_eq(_bond(A)["fact"]["kind"], "met", "the later record, the other way round")
	var dear: BalanceTable = _counting.duplicate() as BalanceTable
	dear.bond_points_meal = 2
	_ledger = []
	_meal([A, B])
	_meeting(A, B)
	var found: Dictionary = Bonds.bond(_ledger, A, _living(), dear)
	assert_eq([found["points"], found["fact"]["kind"], found["fact"]["points"]], [3, "meal", 2], "more points beat a later record")
	dear.bond_points_meal = 1
	dear.bond_points_encounter = 2
	assert_eq(Bonds.bond(_ledger, A, _living(), dear)["fact"]["kind"], "met", "and the other way round")


func test_the_bond_line_counts_meals_after_chats() -> void:
	_meal([A, B])
	assert_eq(Bonds.bond_line(_bond(A), NAMES, false), "Closest to Bea: 1 meal.")
	_battle([A, B], "retreated")
	_battle([A, B], "retreated")
	_meeting(A, B)
	_meal([A, B])
	assert_eq(Bonds.bond_line(_bond(A), NAMES, false), "Closest to Bea: 2 hard fights, 1 chat, 2 meals.")


## A load accepts any record with a seq and a kind, so a meal that does not name 2 to MAX_DINERS different non-empty
## strings counts nothing: in a build, a fold in and a fold out, by one rule. The largest table still counts.
func test_a_hand_edited_meal_counts_nothing_in_a_build_a_fold_in_and_a_fold_out() -> void:
	var crowd: Array = []
	for index: int in Bonds.MAX_DINERS + 1:
		crowd.append("hero:%d" % index)
	var bad: Array[Dictionary] = [
		{"diners": [A]}, {"diners": []}, {"diners": [A, A]}, {"diners": [A, ""]}, {"diners": [A, 5]}, {"diners": [A, null]},
		{"diners": [A, B, A]}, {"diners": "ab"}, {"diners": {A: B}}, {"heroes": [A, B]}, {"place": "House_1"}, {"diners": crowd},
	]
	for fields: Dictionary in bad:
		_record("meal", fields)
	assert_eq(_nonempty(Bonds.index(_ledger, _counting)), {}, "a build counts none")
	var folded: Dictionary = Bonds.index_state([] as Array[Dictionary], _counting)
	for record: Dictionary in _ledger:
		Bonds.fold_in(folded, record, _counting)
	assert_eq([_nonempty(folded["pairs"]), folded["version"], folded["touched"]], [{}, 0, {}], "a fold in counts none and touches no one")
	for record: Dictionary in _ledger:
		assert_true(Bonds.fold_out(folded, record, _counting), "a fold out takes out what was never counted")
	var named: Dictionary = {A: 7, B: 7, "": 4, "5": 5, "<null>": 6}
	for id: String in crowd:
		named[id] = bad.size()
	assert_eq([_nonempty(folded["pairs"]), folded["outs"], folded["out_all"], folded["out_named"]], [{}, bad.size(), 0, named], "and marks the strings it holds, everyone none")
	_ledger = []
	_record("meal", {"diners": crowd.slice(0, Bonds.MAX_DINERS), "place": "House_1"})
	var pairs: Dictionary = Bonds.index(_ledger, _counting)
	assert_eq([pairs.size(), (pairs["hero:0"] as Dictionary).size()], [Bonds.MAX_DINERS, Bonds.MAX_DINERS - 1], "the largest table counts")
	assert_lte(BALANCE.meal_table_size, Bonds.MAX_DINERS, "the shipped table fits the largest the reader counts")


## Folding meals in, then out oldest first (as the eviction tiers do), equals a rebuild of what is left at every step.
## A fold in touches every diner, so the hub's look (ig-7sn.16) re-reads them, and no one else. Taking out the newest of
## two meals of a pair, which the eviction never does, is refused so the caller rebuilds.
func test_folding_meals_in_and_out_equals_a_rebuild_and_touches_every_diner() -> void:
	var folded: Dictionary = Bonds.index_state(_ledger, BALANCE)
	var tables: Array = [[A, B, C], [A, B], [B, C, D], [A, C, D, E]]
	for index: int in 10:
		_meal(tables[index % 4])
		Bonds.fold_in(folded, _ledger.back(), BALANCE)
		assert_eq(_nonempty(folded["pairs"]), _nonempty(Bonds.index(_ledger, BALANCE)), "in %d" % index)
		assert_eq(folded["version"], index + 1)
		for id: String in tables[index % 4]:
			assert_eq((folded["touched"] as Dictionary).get(id), index + 1, "%s sat down at meal %d" % [id, index])
	assert_false((folded["touched"] as Dictionary).has(F), "Fay sat nowhere")
	assert_eq(folded["pairs"][A][B]["meals"], 6, "6 of the 10 tables had Ada and Bea")
	var oldest: Dictionary = _ledger.pop_front()
	assert_true(Bonds.fold_out(folded, oldest, BALANCE))
	assert_eq([folded["version"], folded["touched"][A], folded["touched"][B], folded["touched"][C], folded["touched"][D]], [11, 11, 11, 11, 8], "the take-out stamps the table it took out, and only it (Dov last sat at meal 7)")
	assert_eq(_nonempty(folded["pairs"]), _nonempty(Bonds.index(_ledger, BALANCE)), "out 1")
	while not _ledger.is_empty():
		oldest = _ledger.pop_front()
		assert_true(Bonds.fold_out(folded, oldest, BALANCE))
		assert_eq(_nonempty(folded["pairs"]), _nonempty(Bonds.index(_ledger, BALANCE)), "out %d" % oldest["seq"])
	assert_eq(_nonempty(folded["pairs"]), {}, "every meal is out")
	_meal([A, B])
	_meal([A, B])
	folded = Bonds.index_state(_ledger, BALANCE)
	assert_false(Bonds.fold_out(folded, _ledger[1], BALANCE), "the newest of two is the pair's latest, and the one before it is unknown")


## The cover order counts meal points, as it counts every point of the bond index.
func test_the_cover_order_counts_meal_points() -> void:
	var knight: Hero = _hero(A, "Ada")
	knight.def_id = &"knight"
	for pair: Array in [[B, "Bea"], [C, "Cal"]]:
		_hero(pair[0], pair[1]).def_id = &"mage"
	_battle_in(GameSession.ledger, [A, B], "victory", {"rescued": [B], "rescuers": [A]})
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1
	for _index: int in 3:
		GameSession._record("meal", {"diners": [A, C], "place": "House_1"})
	var team: Array[Hero] = [knight, GameSession.hero_by_id(B), GameSession.hero_by_id(C)]
	assert_eq(GameSession._cover_orders(team, BALANCE)[A], [B, C] as Array[String], "6 points of a rescue and a hard fight, then 3 of meals")
	for _index: int in 8:
		GameSession._record("meal", {"diners": [A, C], "place": "House_1"})
	assert_eq(GameSession._cover_orders(team, BALANCE)[A], [C, B] as Array[String], "11 points of meals, and the bond of 8 or more goes first")


## ---- the dream

func test_the_dream_opens_advances_is_paid_and_opens_again() -> void:
	_battle([A, B], "victory")
	assert_eq(Bonds.dream(_ledger, A), {}, "no save, no dream")
	assert_eq(Bonds.dream_lines({}, A, NAMES, BALANCE), [] as Array[String])
	_battle([A, B], "victory", {"moments": [_moment("carried", A, B)]})
	var zone: String = Ledger.zone_name(ZONE)
	assert_eq(Bonds.dream(_ledger, A), {"dream": "life_debt", "state": "open", "owed": B, "what": "carried", "zone": ZONE, "fights": 0}, "the opening battle is not a fight after it")
	_battle([A, B], "victory")
	_battle([A, C], "victory")
	assert_eq(Bonds.dream_lines(Bonds.dream(_ledger, A), A, NAMES, BALANCE), [
		"Dream: repay Bea.",
		"  [x] Bea carried Ada out at %s." % zone,
		"  [ ] Fight beside Bea again (1/3).",
		"  [ ] Save Bea.",
	] as Array[String])
	for _index: int in 3:
		_battle([A, B], "victory")
	assert_string_contains(Bonds.dream_lines(Bonds.dream(_ledger, A), A, NAMES, BALANCE)[2], "[x] Fight beside Bea again (3/3).")
	_battle([A, C], "victory", {"moments": [_moment("revived", C, A)]})
	assert_eq(Bonds.dream(_ledger, A)["state"], "open", "saving someone else pays nothing")
	_battle([A, B], "victory", {"moments": [_moment("revived", B, A)]})
	assert_eq(Bonds.dream_lines(Bonds.dream(_ledger, A), A, NAMES, BALANCE), ["Dream fulfilled: repaid Bea at %s." % zone] as Array[String])
	_battle([A, C], "victory", {"rescued": [A], "rescuers": [C, B]})
	assert_eq(Bonds.dream(_ledger, A)["owed"], C, "the next save opens a new debt, to the first rescuer")
	assert_eq(Bonds.dream(_ledger, A)["what"], "rescued")


func test_the_owed_heros_death_loses_the_dream() -> void:
	_battle([A, B], "victory", {"moments": [_moment("revived", A, B)]})
	_record("died", {"hero": B, "name": "Bea"})
	assert_eq(Bonds.dream_lines(Bonds.dream(_ledger, A), A, NAMES, BALANCE), ["Dream lost: Bea died before the debt was paid."] as Array[String])
	_battle([A, C], "victory", {"moments": [_moment("revived", A, "enemy:goblin"), _moment("revived", A, C)]})
	assert_eq(Bonds.dream(_ledger, A)["owed"], C, "an enemy is never owed")


## ---- ig-m6o.2.2.7: the dream catalogue (SYSTEMS.md § The dream catalogue)

func test_watch_over_opens_counts_battles_beside_and_is_fulfilled_by_a_rank_up() -> void:
	var zone: String = Ledger.zone_name(ZONE)
	_battle([A, B], "victory", {"moments": [_moment("revived", B, A)]})
	assert_eq(Bonds.dream(_ledger, A), {"dream": "watch_over", "state": "open", "who": B, "what": "revived", "zone": ZONE, "count": 0}, "Ada revived Bea")
	assert_eq(Bonds.dream(_ledger, B)["dream"], "life_debt", "and Bea owes Ada")
	_battle([A, B], "victory")
	_battle([A, C], "victory")
	_battle([B, C], "victory")
	assert_eq(Bonds.dream(_ledger, A)["count"], 1, "a routine battle beside Bea counts; the opening one, and ones without her, do not")
	assert_eq(Bonds.dream_lines(Bonds.dream(_ledger, A), A, NAMES, BALANCE), [
		"Dream: watch over Bea.",
		"  [x] Ada revived Bea at %s." % zone,
		"  [ ] Fight beside Bea again (1/3).",
		"  [ ] See Bea rank up.",
	] as Array[String])
	for _index: int in 3:
		_battle([A, B], "victory")
	assert_string_contains(Bonds.dream_lines(Bonds.dream(_ledger, A), A, NAMES, BALANCE)[2], "[x] Fight beside Bea again (3/3).")
	_record("ranked_up", {"hero": C, "from": 0, "to": 1, "via": "essence"})
	assert_eq(Bonds.dream(_ledger, A)["state"], "open", "someone else ranking up pays nothing")
	_record("ranked_up", {"hero": B, "from": 0, "to": 1, "via": "essence"})
	assert_eq(Bonds.dream(_ledger, A), {"dream": "watch_over", "state": "fulfilled", "who": B})
	assert_eq(Bonds.dream_lines(Bonds.dream(_ledger, A), A, NAMES, BALANCE), ["Dream fulfilled: Bea rose in rank."] as Array[String])


func test_watch_over_opens_on_a_rescue_is_fulfilled_before_the_count_and_lost_to_a_death() -> void:
	_battle([A, B, C], "victory", {"rescued": [B, C], "rescuers": [A]})
	var open: Dictionary = Bonds.dream(_ledger, A)
	assert_eq([open["dream"], open["who"], open["what"]], ["watch_over", B, "rescued"], "the first one rescued")
	var before: Array[Dictionary] = _ledger.duplicate()
	_record("ranked_up", {"hero": B, "from": 0, "to": 1, "via": "essence"})
	assert_eq(Bonds.dream(_ledger, A), {"dream": "watch_over", "state": "fulfilled", "who": B}, "a rank-up ends it at count 0")
	_ledger = before
	_record("died", {"hero": B, "name": "Bea", "cause": "starvation"})
	assert_eq(Bonds.dream(_ledger, A), {"dream": "watch_over", "state": "lost", "who": B})
	assert_eq(Bonds.dream_lines(Bonds.dream(_ledger, A), A, NAMES, BALANCE), ["Dream lost: Bea died before rising."] as Array[String])


func test_carry_name_opens_on_a_witnessed_death_counts_victories_there_and_is_fulfilled() -> void:
	var zone: String = Ledger.zone_name(ZONE)
	_battle([A, B, C], "stranded", {"order": "order:x"})
	_record("died", {"hero": C, "name": "Cal", "cause": "expedition", "zone": ZONE, "battle_order": "order:x"})
	assert_eq(Bonds.dream(_ledger, A), {"dream": "carry_name", "state": "open", "who": C, "zone": ZONE, "count": 0})
	assert_eq(Bonds.dream(_ledger, B)["dream"], "carry_name", "Bea was there too")
	assert_eq(Bonds.dream(_ledger, D), {}, "Dov was not")
	_battle([A, B], "victory", {"zone": "frontier_march"})
	_battle([A, B], "retreated")
	_battle([B, C], "victory")
	assert_eq(Bonds.dream(_ledger, A)["count"], 0, "a win elsewhere, a loss here, a win without Ada: nothing")
	_battle([A], "victory")
	assert_eq(Bonds.dream_lines(Bonds.dream(_ledger, A), A, NAMES, BALANCE), [
		"Dream: carry Cal's name.",
		"  [x] Ada saw Cal fall at %s." % zone,
		"  [ ] Win at %s (1/3)." % zone,
		"  [ ] Carry Cal's name.",
	] as Array[String], "any victory with Ada in the team counts, routine too")
	_battle([A, D], "victory")
	assert_eq(Bonds.dream(_ledger, A)["state"], "open")
	_battle([A, B], "victory")
	assert_eq(Bonds.dream(_ledger, A), {"dream": "carry_name", "state": "fulfilled", "who": C, "zone": ZONE})
	assert_eq(Bonds.dream_lines(Bonds.dream(_ledger, A), A, NAMES, BALANCE), ["Dream fulfilled: Cal's name carried at %s." % zone] as Array[String])


func test_carry_name_is_lost_only_to_a_second_witnessed_death_at_its_zone() -> void:
	_battle([A, B, C], "stranded", {"order": "order:x"})
	_record("died", {"hero": C, "name": "Cal", "cause": "expedition", "zone": ZONE, "battle_order": "order:x"})
	_record("died", {"hero": D, "name": "Dov", "cause": "expedition", "zone": ZONE, "battle_order": "order:nobody"})
	_battle([A, B, D], "stranded", {"order": "order:y", "zone": "frontier_march"})
	_record("died", {"hero": D, "name": "Dov", "cause": "expedition", "zone": "frontier_march", "battle_order": "order:y"})
	_record("died", {"hero": E, "name": "Eve", "cause": "expedition", "zone": ZONE})
	_record("died", {"hero": F, "name": "Fay", "cause": "starvation", "zone": ZONE, "battle_order": "order:x"})
	assert_eq(Bonds.dream(_ledger, A)["state"], "open", "unwitnessed at the zone, witnessed elsewhere, no order, no expedition: nothing")
	_record("died", {"cause": "expedition", "zone": ZONE, "battle_order": "order:x"})
	assert_eq(Bonds.dream(_ledger, A), {"dream": "carry_name", "state": "open", "who": C, "zone": ZONE, "count": 0}, "a death with no hero, even at a witnessed order, is no one's: still open, count unchanged")
	_battle([A, E], "stranded", {"order": "order:z"})
	_record("died", {"hero": E, "name": "Eve", "cause": "expedition", "zone": ZONE, "battle_order": "order:z"})
	assert_eq(Bonds.dream(_ledger, A), {"dream": "carry_name", "state": "lost", "who": C, "zone": ZONE})
	assert_eq(Bonds.dream_lines(Bonds.dream(_ledger, A), A, NAMES, BALANCE), ["Dream lost: %s took another friend." % Ledger.zone_name(ZONE)] as Array[String])


func test_carry_name_never_opens_from_a_death_whose_battles_are_gone() -> void:
	_battle([A, B, C], "stranded", {"order": "order:x"})
	_record("died", {"hero": C, "name": "Cal", "cause": "expedition", "zone": ZONE, "battle_order": "order:x"})
	assert_eq(Bonds.dream(_ledger, A)["dream"], "carry_name")
	_ledger.remove_at(0)
	assert_eq(Bonds.dream(_ledger, A), {}, "the cap evicted the battle: no one is known to have been there")


func test_be_worthy_opens_on_a_sacrifice_for_the_owner_and_counts_hard_victories() -> void:
	_record("died", {"hero": C, "name": "Cal", "cause": "sacrifice", "by": A})
	assert_eq(Bonds.dream(_ledger, A), {"dream": "be_worthy", "state": "open", "who": C, "count": 0})
	assert_eq(Bonds.dream(_ledger, B), {}, "a life given for Ada is Ada's")
	_battle([A, B], "victory")
	_battle([A, B], "retreated", {"moments": [_moment("downed", A, "enemy:goblin")]})
	_battle([B, D], "victory", {"moments": [_moment("downed", B, "enemy:goblin")]})
	assert_eq(Bonds.dream(_ledger, A)["count"], 0, "a routine win, a retreat, a hard win without Ada: nothing")
	_battle([A, B], "victory", {"moments": [_moment("downed", B, "enemy:goblin")]})
	assert_eq(Bonds.dream_lines(Bonds.dream(_ledger, A), A, NAMES, BALANCE), [
		"Dream: be worth Cal's life.",
		"  [x] Cal was given up for Ada.",
		"  [ ] Win hard fights (1/2).",
		"  [ ] Repay Cal's life.",
	] as Array[String])
	_battle([A, B], "victory", {"moments": [_moment("downed", A, "enemy:goblin")]})
	assert_eq(Bonds.dream(_ledger, A), {"dream": "be_worthy", "state": "fulfilled", "who": C})
	assert_eq(Bonds.dream_lines(Bonds.dream(_ledger, A), A, NAMES, BALANCE), ["Dream fulfilled: Cal's life was worth it."] as Array[String])


func test_be_worthy_is_lost_to_a_rescue_even_when_that_rescue_would_have_won_it() -> void:
	_record("died", {"hero": C, "name": "Cal", "cause": "sacrifice", "by": A})
	_battle([A, B], "victory", {"moments": [_moment("downed", B, "enemy:goblin")]})
	assert_eq(Bonds.dream(_ledger, A)["count"], 1, "one hard win short")
	_battle([A, B, D], "victory", {"rescued": [A], "rescuers": [B]})
	assert_eq(Bonds.dream(_ledger, A), {"dream": "be_worthy", "state": "lost", "who": C}, "a hard victory, but Ada was carried home: lost first")
	assert_eq(Bonds.dream_lines(Bonds.dream(_ledger, A), A, NAMES, BALANCE), ["Dream lost: carried home before Cal's life was repaid."] as Array[String])


func test_be_worthy_fades_after_a_run_without_a_hard_win_and_a_hard_win_restarts_the_run() -> void:
	var run: int = BALANCE.dream_worthy_fade_battles
	_record("died", {"hero": C, "name": "Cal", "cause": "sacrifice", "by": A})
	for _index: int in run - 1:
		_battle([A, B], "victory")
	_battle([B, D], "victory")
	_battle([D], "retreated")
	assert_eq(Bonds.dream(_ledger, A)["state"], "open", "one short; battles without Ada are not in the run")
	_battle([A, B], "victory", {"moments": [_moment("downed", B, "enemy:goblin")]})
	for _index: int in run - 1:
		_battle([A, B], "retreated")
	assert_eq(Bonds.dream(_ledger, A), {"dream": "be_worthy", "state": "open", "who": C, "count": 1}, "the hard win restarted the run; a loss counts in it")
	_battle([A, B], "victory")
	assert_eq(Bonds.dream(_ledger, A), {"dream": "be_worthy", "state": "faded", "who": C})
	assert_eq(Bonds.dream_lines(Bonds.dream(_ledger, A), A, NAMES, BALANCE), ["Dream faded: %d battles without a hard win." % run] as Array[String])
	_battle([A, B], "victory", {"moments": [_moment("revived", A, B)]})
	assert_eq(Bonds.dream(_ledger, A)["dream"], "life_debt", "a faded dream frees the slot")


func test_a_battle_that_saves_the_owner_and_has_it_save_someone_opens_the_life_debt() -> void:
	_battle([A, B, C], "victory", {"moments": [_moment("revived", C, A), _moment("revived", A, B)]})
	var found: Dictionary = Bonds.dream(_ledger, A)
	assert_eq([found["dream"], found["owed"]], ["life_debt", B], "Bea saved Ada; Ada saved Cal; the debt wins")


func test_the_record_that_ends_a_dream_never_opens_the_next() -> void:
	_battle([A, B], "victory", {"moments": [_moment("revived", B, A)]})
	_battle([A, B, C], "stranded", {"order": "order:x"})
	_record("died", {"hero": B, "name": "Bea", "cause": "expedition", "zone": ZONE, "battle_order": "order:x"})
	assert_eq(Bonds.dream(_ledger, A), {"dream": "watch_over", "state": "lost", "who": B}, "Bea's witnessed death loses Watch over and does not open Carry their name")
	_battle([A, C, D], "stranded", {"order": "order:y"})
	_record("died", {"hero": D, "name": "Dov", "cause": "expedition", "zone": ZONE, "battle_order": "order:y"})
	assert_eq(Bonds.dream(_ledger, A)["dream"], "carry_name", "the next formative record after the end opens one")
	_ledger = []
	_battle([A, B], "victory", {"moments": [_moment("revived", B, A)]})
	_record("died", {"hero": B, "name": "Bea", "cause": "sacrifice", "by": A})
	assert_eq(Bonds.dream(_ledger, A), {"dream": "watch_over", "state": "lost", "who": B}, "Bea given up for Ada loses Watch over and does not open Be worth it")
	_record("died", {"hero": C, "name": "Cal", "cause": "sacrifice", "by": A})
	assert_eq(Bonds.dream(_ledger, A)["dream"], "be_worthy")
	_ledger = []
	_battle([A, B], "victory", {"moments": [_moment("revived", A, B)]})
	_record("died", {"hero": B, "name": "Bea", "cause": "sacrifice", "by": C})
	assert_eq(Bonds.dream(_ledger, A), {"dream": "life_debt", "state": "lost", "owed": B}, "and the life debt ends the same way")


func test_three_sacrifices_in_one_rank_up_open_be_worthy_on_the_first() -> void:
	for id: String in [B, C, D]:
		_record("died", {"hero": id, "name": "X", "cause": "sacrifice", "by": A})
	assert_eq(Bonds.dream(_ledger, A), {"dream": "be_worthy", "state": "open", "who": B, "count": 0}, "the others add nothing")


## ---- ig-m6o.2.2.10: the two dreams on meal and meeting records (SYSTEMS.md § The dream catalogue)

func test_welcome_home_opens_on_a_rescue_that_names_the_owner_nowhere_when_the_freed_heros_last_meal_was_at_the_owners_table() -> void:
	_meal([A, B, C])
	_battle([D, B], "victory", {"rescued": [B], "rescuers": [D]})
	var found: Dictionary = {"dream": "welcome_home", "state": "open", "who": B, "zone": ZONE, "count": 0}
	assert_eq(Bonds.dream(_ledger, A), found, "under the default read, which drops a battle that names no one")
	assert_eq(Bonds.dream(_ledger, A, null, false), found, "and reading every record")
	assert_eq(Bonds.dream(_ledger, C), found, "Cal sat at that table too")
	assert_eq(Bonds.dream(_ledger, D)["dream"], "watch_over", "the rescuer watches over Bea, and welcomes no one home")
	assert_eq(Bonds.dream(_ledger, B)["dream"], "life_debt", "the rescued owes the rescuer")
	assert_eq(Bonds.dream_lines(found, A, NAMES, BALANCE), [
		"Dream: welcome Bea home.",
		"  [x] Bea was carried home from %s." % Ledger.zone_name(ZONE),
		"  [ ] Eat with Bea again (0/3).",
	] as Array[String], "three lines: the dream ends at its count")


func test_welcome_home_does_not_open_when_the_owner_is_named_or_the_last_meal_was_elsewhere_or_there_was_none() -> void:
	_meal([A, B])
	_battle([A, B], "stranded", {"rescued": [A, B]})
	assert_eq(Bonds.dream(_ledger, A), {}, "the owner was stranded with Bea, even in a record with no rescuers")
	_ledger = []
	_meal([A, B])
	_battle([A, D, B], "victory", {"rescued": [B], "rescuers": [D]})
	assert_eq(Bonds.dream(_ledger, A), {}, "the owner fought in it")
	_battle([A, B], "victory", {"rescued": [B], "rescuers": [A]})
	assert_eq(Bonds.dream(_ledger, A)["dream"], "watch_over", "the owner among the rescuers watches over, and welcomes no one")
	_ledger = []
	_meal([A, B])
	_meal([B, C])
	_battle([D, B], "victory", {"rescued": [B], "rescuers": [D]})
	assert_eq(Bonds.dream(_ledger, A), {}, "Bea's latest meal was at another table, though an older one seated them")
	assert_eq(Bonds.dream(_ledger, C)["who"], B, "and Cal, who sat at it, does welcome her home")
	assert_eq(Bonds.dream(_ledger, E), {}, "a hero who never ate with Bea")
	_ledger = []
	_battle([D, B], "victory", {"rescued": [B], "rescuers": [D]})
	assert_eq(Bonds.dream(_ledger, A), {}, "Bea never dined")
	_meal([A, B])
	assert_eq(Bonds.dream(_ledger, A), {}, "a meal after the rescue is not the meal before it")


func test_welcome_home_names_the_first_freed_hero_whose_last_meal_was_at_the_owners_table() -> void:
	_meal([A, B, C])
	_battle([D, B, C], "victory", {"rescued": [B, C], "rescuers": [D]})
	assert_eq(Bonds.dream(_ledger, A)["who"], B, "the first in rescued")
	_ledger = []
	_meal([A, C])
	_meal([B, D])
	_battle([D, B, C], "victory", {"rescued": [B, C], "rescuers": [D]})
	assert_eq(Bonds.dream(_ledger, A)["who"], C, "Bea ate elsewhere, so the next one")


func test_welcome_home_counts_meals_seating_both_after_the_rescue_and_is_fulfilled_at_the_count() -> void:
	_meal([A, B, C])
	_battle([D, B], "victory", {"rescued": [B], "rescuers": [D]})
	_meal([A, C, D])
	_meal([B, C, D])
	_meal([A, D])
	assert_eq(Bonds.dream(_ledger, A)["count"], 0, "a meal seating only one of them adds nothing")
	_meal([A, B])
	_meal([D, B, A])
	assert_eq(Bonds.dream(_ledger, A)["count"], 2)
	assert_eq(Bonds.dream_lines(Bonds.dream(_ledger, A), A, NAMES, BALANCE)[2], "  [ ] Eat with Bea again (2/3).")
	var short: Array[Dictionary] = _ledger.duplicate()
	_record("died", {"hero": B, "name": "Bea", "cause": "starvation"})
	assert_eq(Bonds.dream(_ledger, A), {"dream": "welcome_home", "state": "lost", "who": B}, "Bea dies before the third meal")
	assert_eq(Bonds.dream_lines(Bonds.dream(_ledger, A), A, NAMES, BALANCE), ["Dream lost: Bea died before coming back to the table."] as Array[String])
	_ledger = short
	_meal([B, A, C])
	assert_eq(Bonds.dream(_ledger, A), {"dream": "welcome_home", "state": "fulfilled", "who": B})
	assert_eq(Bonds.dream_lines(Bonds.dream(_ledger, A), A, NAMES, BALANCE), ["Dream fulfilled: Bea is back at the table."] as Array[String])
	assert_eq(Bonds.dream(_ledger, A, null, false), Bonds.dream(_ledger, A), "the skip changes nothing")


func test_a_rejected_meal_an_encounter_with_no_heroes_and_a_rescue_with_no_rescued_read_as_nothing() -> void:
	_record("meal", {"diners": [A], "place": "House_1"})
	_record("meal", {"diners": [A, B, B], "place": "House_1"})
	_record("meal", {"diners": [A, B, ""], "place": "House_1"})
	_record("meal", {"place": "House_1"})
	_record("encounter", {"place": "House_1"})
	_record("encounter", {"heroes": [A], "place": "House_1", "why": "neighbours"})
	_record("encounter", {"heroes": [A, A], "place": "House_1", "why": "neighbours"})
	_record("encounter", {"heroes": [A, B, C], "place": "House_1", "why": "neighbours"})
	_battle([D, B], "victory", {"rescuers": [D]})
	assert_eq(Bonds.dream(_ledger, A), {}, "no diners seated Bea at Ada's table, and a rescue that freed no one welcomes no one")
	assert_eq(Bonds.dream(_ledger, A, null, false), {})
	for _index: int in 6:
		_record("encounter", {"heroes": [A, A], "place": "House_1", "why": "neighbours"})
		_record("encounter", {"heroes": [A], "place": "House_1", "why": "neighbours"})
	assert_eq(Bonds.dream(_ledger, A), {}, "and no meeting counts toward fight_beside")
	_battle([D, B], "victory", {"rescued": [B], "rescuers": [D]})
	assert_eq(Bonds.dream(_ledger, A), {}, "a rejected meal sets no table")


func test_fight_beside_opens_on_the_fourth_meeting_when_they_never_fought_together() -> void:
	_meetings(A, B, 3)
	assert_eq(Bonds.dream(_ledger, A), {}, "three meetings: not yet")
	_meeting(B, A)
	var found: Dictionary = {"dream": "fight_beside", "state": "open", "who": B, "count": 0, "chats": 4}
	assert_eq(Bonds.dream(_ledger, A), found, "the fourth, whichever of them is first in the record")
	assert_eq(Bonds.dream(_ledger, B), {"dream": "fight_beside", "state": "open", "who": A, "count": 0, "chats": 4}, "and Bea wants the same")
	assert_eq(Bonds.dream(_ledger, C), {}, "Cal is no part of it")
	assert_eq(Bonds.dream_lines(found, A, NAMES, BALANCE), [
		"Dream: fight beside Bea.",
		"  [x] Got to know Bea in town (4 chats).",
		"  [ ] Fight beside Bea (0/3).",
	] as Array[String], "three lines: the dream ends at its count")
	_meeting(A, C)
	_meeting(C, B)
	assert_eq(Bonds.dream(_ledger, A), found, "meetings with others change nothing")


func test_fight_beside_counts_battles_with_both_in_the_team_routine_too_and_is_fulfilled_without_opening_a_life_debt() -> void:
	_meetings(A, B, 4)
	_battle([A, C], "victory")
	_battle([B, C], "victory")
	assert_eq(Bonds.dream(_ledger, A)["count"], 0, "a battle with only one of them adds nothing")
	_battle([A, B], "victory")
	_battle([A, B, C], "retreated")
	assert_eq(Bonds.dream_lines(Bonds.dream(_ledger, A), A, NAMES, BALANCE)[2], "  [ ] Fight beside Bea (2/3).")
	_battle([A, B], "victory", {"moments": [_moment("revived", A, C)]})
	assert_eq(Bonds.dream(_ledger, A), {"dream": "fight_beside", "state": "fulfilled", "who": B}, "the third; the battle that fulfils it opens no life debt though Cal saved Ada in it")
	assert_eq(Bonds.dream_lines(Bonds.dream(_ledger, A), A, NAMES, BALANCE), ["Dream fulfilled: fought beside Bea."] as Array[String])
	_battle([A, C], "victory", {"moments": [_moment("revived", A, C)]})
	assert_eq(Bonds.dream(_ledger, A)["dream"], "life_debt", "the next formative record does")


func test_fight_beside_is_lost_to_the_deaths_of_the_other_hero() -> void:
	_meetings(A, B, 4)
	_record("died", {"hero": B, "name": "Bea", "cause": "starvation"})
	assert_eq(Bonds.dream(_ledger, A), {"dream": "fight_beside", "state": "lost", "who": B})
	assert_eq(Bonds.dream_lines(Bonds.dream(_ledger, A), A, NAMES, BALANCE), ["Dream lost: Bea died before they fought together."] as Array[String])


func test_fight_beside_fades_after_more_meetings_with_no_battle_together_and_a_faded_pair_is_not_reopened() -> void:
	_meetings(A, B, 4)
	_meetings(A, B, 3)
	assert_eq(Bonds.dream(_ledger, A), {"dream": "fight_beside", "state": "open", "who": B, "count": 0, "chats": 4}, "seven meetings: three since the opening")
	var before: Array[Dictionary] = _ledger.duplicate()
	_meeting(A, B)
	var faded: Dictionary = {"dream": "fight_beside", "state": "faded", "who": B}
	assert_eq(Bonds.dream(_ledger, A), faded, "the eighth is dream_along_meetings after the fourth")
	assert_eq(Bonds.dream_lines(faded, A, NAMES, BALANCE), ["Dream faded: never fought beside Bea."] as Array[String])
	_meetings(A, B, 3)
	assert_eq(Bonds.dream(_ledger, A), faded, "no meeting after it reopens it")
	_ledger = before
	_battle([A, B], "victory")
	_meetings(A, B, 8)
	assert_eq(Bonds.dream(_ledger, A), {"dream": "fight_beside", "state": "open", "who": B, "count": 1, "chats": 4}, "one battle together and it never fades")


func test_a_pair_that_fought_together_never_opens_fight_beside_and_a_new_one_does() -> void:
	_battle([A, B, C], "victory")
	_meetings(A, B, 5)
	assert_eq(Bonds.dream(_ledger, A), {}, "Ada fought beside Bea earlier")
	_meetings(A, C, 5)
	assert_eq(Bonds.dream(_ledger, A), {}, "and beside Cal")
	_meetings(A, D, 4)
	assert_eq(Bonds.dream(_ledger, A), {"dream": "fight_beside", "state": "open", "who": D, "count": 0, "chats": 4})
	assert_eq(Bonds.dream(_ledger, A, null, false), Bonds.dream(_ledger, A), "the skip changes nothing")


func test_meetings_held_while_another_dream_is_open_count_and_the_pair_opens_it_when_the_slot_frees_until_the_seventh() -> void:
	for free_after: int in [3, 6, 7]:
		_ledger = []
		_battle([A, C], "victory", {"moments": [_moment("revived", A, C)]})
		_meetings(A, B, free_after)
		assert_eq(Bonds.dream(_ledger, A)["dream"], "life_debt", "the slot is held")
		_battle([A, C], "victory", {"moments": [_moment("revived", C, A)]})
		assert_eq(Bonds.dream(_ledger, A)["state"], "paid")
		_meeting(A, B)
		var found: Dictionary = Bonds.dream(_ledger, A)
		if free_after == 7:
			assert_eq(found["dream"], "life_debt", "the eighth meeting is past the window: the chance is gone")
			_meeting(A, B)
			assert_eq(Bonds.dream(_ledger, A)["dream"], "life_debt", "and it stays gone")
		else:
			assert_eq([found["dream"], found["who"], found["chats"]], ["fight_beside", B, free_after + 1], "opened at meeting %d, the first once the slot freed" % (free_after + 1))
	_ledger = []
	_meetings(A, B, 4)
	_battle([A, C], "victory", {"moments": [_moment("revived", A, C)]})
	assert_eq(Bonds.dream(_ledger, A)["dream"], "fight_beside", "an open fight_beside keeps the slot from a life debt")
	_meal([A, C])
	_battle([D, C], "victory", {"rescued": [C], "rescuers": [D]})
	assert_eq(Bonds.dream(_ledger, A)["dream"], "fight_beside", "and from welcome_home")


func test_a_death_that_loses_welcome_home_does_not_open_carry_name() -> void:
	_meal([A, B])
	_battle([D, B], "victory", {"rescued": [B], "rescuers": [D]})
	assert_eq(Bonds.dream(_ledger, A)["dream"], "welcome_home")
	_battle([A, B], "stranded", {"order": "order:x"})
	_record("died", {"hero": B, "name": "Bea", "cause": "expedition", "zone": ZONE, "battle_order": "order:x"})
	assert_eq(Bonds.dream(_ledger, A), {"dream": "welcome_home", "state": "lost", "who": B}, "Bea's witnessed death loses it and does not open Carry their name")
	_battle([A, C, D], "stranded", {"order": "order:y"})
	_record("died", {"hero": D, "name": "Dov", "cause": "expedition", "zone": ZONE, "battle_order": "order:y"})
	assert_eq(Bonds.dream(_ledger, A)["dream"], "carry_name", "the next formative record after the end opens one")


func test_the_dreams_on_meals_and_meetings_read_the_same_with_or_without_the_skip() -> void:
	_meal([A, B, C])
	_meetings(A, C, 5)
	_battle([D, B], "victory", {"rescued": [B], "rescuers": [D]})
	_battle([E, D], "victory")
	_battle([A, C], "victory")
	_meal([A, B])
	for id: String in [A, B, C, D, E]:
		assert_eq(Bonds.dream(_ledger, id), Bonds.dream(_ledger, id, null, false), "%s: the default read equals reading every record" % id)


func test_legacy_records_open_no_catalogue_dream_and_change_none() -> void:
	_battle([A, B], "stranded")
	_record("died", {"hero": C, "name": "Cal"})
	_record("died", {"hero": C, "name": "Cal", "cause": "expedition", "zone": ZONE})
	_record("died", {"hero": C, "name": "Cal", "cause": "expedition", "battle_order": "order:0"})
	_record("died", {"hero": C, "name": "Cal", "cause": "sacrifice"})
	_record("died", {"cause": "expedition", "zone": ZONE, "battle_order": "order:0"})
	_record("died", {"cause": "sacrifice", "by": A})
	_record("ranked_up", {})
	Ledger.append(_ledger, _ledger.size() + 1, 0, "battle", {"team": [A]})
	Ledger.append(_ledger, _ledger.size() + 1, 0, "battle", {})
	assert_eq(Bonds.dream(_ledger, A), {}, "no cause, by, order, zone, hero, team, moments or rescue: nothing opens")
	_battle([A, B], "victory", {"moments": [_moment("revived", B, A)]})
	_record("died", {"cause": "expedition"})
	_record("ranked_up", {})
	Ledger.append(_ledger, _ledger.size() + 1, 0, "battle", {"team": [A, B]})
	assert_eq(Bonds.dream(_ledger, A), {"dream": "watch_over", "state": "open", "who": B, "what": "revived", "zone": ZONE, "count": 1}, "and none of them ends or counts on an open one but the bare battle beside Bea")


func test_a_dead_hero_keeps_its_name_in_the_dream_lines() -> void:
	_battle([A, B, C], "stranded", {"order": "order:x"})
	_record("died", {"hero": C, "name": "Cal", "cause": "expedition", "zone": ZONE, "battle_order": "order:x"})
	var found: Dictionary = Bonds.dream(_ledger, A)
	assert_string_contains(Bonds.dream_lines(found, A, Ledger.known_names(_ledger, {A: "Ada"}), BALANCE)[1], "Ada saw Cal fall")
	assert_string_contains(Bonds.dream_lines(found, A, {A: "Ada"}, BALANCE)[1], "a hero now forgotten", "a name nobody knows")


func test_no_dream_is_saved_and_a_disk_round_trip_gives_the_same_dreams() -> void:
	_hero(A, "Ada")
	var owners: Array[String] = [A, B, D, F, "hero:m", "hero:q"]
	GameSession._record("battle", {"order": "order:1", "zone": ZONE, "team": [A, B], "result": "victory", "moments": [_moment("revived", A, B)]})
	GameSession._record("battle", {"order": "order:2", "zone": ZONE, "team": [D, E], "result": "stranded", "moments": []})
	GameSession._record("died", {"hero": E, "name": "Eve", "cause": "expedition", "zone": ZONE, "battle_order": "order:2"})
	GameSession._record("died", {"hero": C, "name": "Cal", "cause": "sacrifice", "by": F})
	# ig-m6o.2.2.10: a meal then a rescue that names hero:m nowhere (welcome_home), and four chats of two who never fought together.
	GameSession._record("meal", {"diners": ["hero:m", "hero:n", "hero:o"], "place": "House_1"})
	GameSession._record("battle", {"order": "order:3", "zone": ZONE, "team": ["hero:o", "hero:p"], "result": "victory", "moments": [], "rescued": ["hero:n"], "rescuers": ["hero:p"]})
	for _index: int in 4:
		GameSession._record("encounter", {"heroes": ["hero:q", "hero:r"], "place": "House_1", "why": "neighbours"})
	var before: Dictionary = {}
	for id: String in owners:
		before[id] = Bonds.dream(GameSession.ledger, id)
	assert_eq([before[A]["dream"], before[B]["dream"], before[D]["dream"], before[F]["dream"], before["hero:m"]["dream"], before["hero:q"]["dream"]], ["life_debt", "watch_over", "carry_name", "be_worthy", "welcome_home", "fight_beside"])
	for key: String in GameSession.to_dict():
		assert_false(key.contains("dream"), "no saved dream: %s" % key)
	assert_true(SaveService.save(), SaveService.last_write_error)
	var files: Dictionary = {SaveService.SAVE_PATH: FileAccess.get_file_as_bytes(SaveService.SAVE_PATH), SaveService.LEDGER_PATH: FileAccess.get_file_as_bytes(SaveService.LEDGER_PATH)}
	for path: String in files:
		assert_false((files[path] as PackedByteArray).get_string_from_utf8().contains("dream"), "and none on disk: %s" % path)
	# The reset saves the empty state over both files (roster_changed), so put the two files back.
	GameSession.from_dict({"roster": []})
	for path: String in files:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_buffer(files[path])
		file.close()
	assert_true(SaveService.load_game(), SaveService.load_block_reason)
	for id: String in owners:
		assert_eq(Bonds.dream(GameSession.ledger, id), before[id], "%s's dream after the round trip" % id)


## One bond and dream read for one hero at the cap. A measurement for ig-m6o.2.2, not a gate. The
## ledger also holds a formative record for each dream of the catalogue (ig-m6o.2.2.7): three owners
## at the cap that each hold their own, checked, and the timed hero's mix of saves and rescues.
func test_read_cost_at_the_cap() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var heroes: Array[String] = []
	for index: int in 40:
		heroes.append("hero:%d" % index)
	var scripted: Dictionary = {
		2500: ["battle", {"order": "order:2500", "zone": ZONE, "team": ["own:watch", "own:x"], "result": "victory", "moments": [_moment("revived", "own:x", "own:watch")]}],
		5000: ["battle", {"order": "order:5000", "zone": ZONE, "team": ["own:carry", "own:y"], "result": "stranded", "moments": []}],
		5001: ["died", {"hero": "own:y", "name": "Y", "cause": "expedition", "zone": ZONE, "battle_order": "order:5000"}],
		7500: ["died", {"hero": "own:z", "name": "Z", "cause": "sacrifice", "by": "own:worthy"}],
		6000: ["meal", {"diners": ["own:m", "own:n", "own:o"], "place": "House_1"}],
		6001: ["battle", {"order": "order:6001", "zone": ZONE, "team": ["own:o", "own:p"], "result": "victory", "moments": [], "rescued": ["own:n"], "rescuers": ["own:p"]}],
		8000: ["encounter", {"heroes": ["own:f", "own:g"], "place": "House_1", "why": "neighbours"}],
		8001: ["encounter", {"heroes": ["own:f", "own:g"], "place": "House_1", "why": "neighbours"}],
		8002: ["encounter", {"heroes": ["own:f", "own:g"], "place": "House_1", "why": "neighbours"}],
		8003: ["encounter", {"heroes": ["own:f", "own:g"], "place": "House_1", "why": "neighbours"}],
	}
	for index: int in BALANCE.ledger_max_records:
		var team: Array[String] = []
		for _slot: int in 4:
			team.append(heroes[rng.randi_range(0, heroes.size() - 1)])
		if scripted.has(index):
			_record(scripted[index][0], scripted[index][1])
			continue
		if index % 3 == 0:
			# A third of the ledger is chats and meals, alternating, as the perf seed's is (ig-m6o.2.2.10: the dream reads them now).
			var table: Array[String] = _team(rng, heroes, 2 if index % 6 == 0 else 4)
			table.sort()
			if index % 6 == 0:
				_record("encounter", {"heroes": table, "place": "House_1", "why": "neighbours"})
			else:
				_record("meal", {"diners": table, "place": "House_1"})
			continue
		var roll: int = rng.randi_range(0, 9)
		var fields: Dictionary = {"order": "order:%d" % index, "zone": ZONE, "team": team, "result": "victory", "moments": []}
		if roll >= 6:
			fields["result"] = "retreated"
			fields["moments"] = [_moment("downed", team[0], "enemy:goblin"), _moment("revived", team[0], team[1])]
		if roll == 9:
			fields["rescued"] = [team[2]]
			fields["rescuers"] = [team[3]]
		_record("battle", fields)
	var living: Dictionary = {}
	for id: String in heroes:
		living[id] = true
	var best_usec: int = 1 << 62
	var best_dream_usec: int = 1 << 62
	for _run: int in 7:
		var started: int = Time.get_ticks_usec()
		Bonds.bond(_ledger, heroes[0], living, BALANCE)
		var midway: int = Time.get_ticks_usec()
		Bonds.dream(_ledger, heroes[0])
		var ended: int = Time.get_ticks_usec()
		best_usec = mini(best_usec, ended - started)
		best_dream_usec = mini(best_dream_usec, ended - midway)
	gut.p("BOND READ COST: %d records, one bond and dream read, best of 7: %.2f ms" % [_ledger.size(), best_usec / 1000.0])
	gut.p("DREAM READ COST: %d records, one hero's dream (%s), best of 7: %.2f ms" % [_ledger.size(), Bonds.dream(_ledger, heroes[0]).get("dream", "none"), best_dream_usec / 1000.0])
	assert_eq(_ledger.size(), BALANCE.ledger_max_records)
	assert_eq(Bonds.dream(_ledger, "own:watch")["dream"], "watch_over")
	assert_eq(Bonds.dream(_ledger, "own:carry")["dream"], "carry_name")
	assert_eq(Bonds.dream(_ledger, "own:worthy")["dream"], "be_worthy")
	assert_eq(Bonds.dream(_ledger, "own:m")["dream"], "welcome_home")
	assert_eq(Bonds.dream(_ledger, "own:f")["dream"], "fight_beside")
	var worst_usec: int = 0
	for hero_id: String in heroes.slice(0, 8):
		var started: int = Time.get_ticks_usec()
		Bonds.dream(_ledger, hero_id)
		worst_usec = maxi(worst_usec, Time.get_ticks_usec() - started)
	gut.p("DREAM READ COST: the slowest of eight heroes' full reads at the cap: %.2f ms" % [worst_usec / 1000.0])


## ig-m6o.2.2.10: the notice that marks two shown heroes at once (the selected one and the partner) costs two full reads
## if both are read on the notice's frame; deferred they are one a frame. A measurement, not a gate: two heroes' full
## reads at the real cap over the same mixed ledger, worst of 7.
func test_two_full_dream_reads_at_the_cap_are_a_measurement() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var heroes: Array[String] = []
	for index: int in 40:
		heroes.append("hero:%d" % index)
	for index: int in BALANCE.ledger_max_records:
		if index % 3 == 0:
			var table: Array[String] = _team(rng, heroes, 2 if index % 6 == 0 else 4)
			table.sort()
			if index % 6 == 0:
				_record("encounter", {"heroes": table, "place": "House_1", "why": "neighbours"})
			else:
				_record("meal", {"diners": table, "place": "House_1"})
		else:
			var team: Array[String] = _team(rng, heroes, 5)
			_battle_in(_ledger, team, "victory", _mix(rng, index, team))
	var runs: Array[int] = []
	for run: int in 7:
		var started: int = Time.get_ticks_usec()
		Bonds.dream_fold(_ledger, heroes[run])
		Bonds.dream_fold(_ledger, heroes[run + 1])
		runs.append(Time.get_ticks_usec() - started)
	gut.p("DREAM READ COST: %d records, two full reads in one notice (the selected hero and the partner), best %.2f ms, worst %.2f ms of 7" % [_ledger.size(), runs.min() / 1000.0, runs.max() / 1000.0])
	assert_eq(_ledger.size(), BALANCE.ledger_max_records)


## ---- the hub

func test_the_detail_panel_shows_the_bond_and_dream_above_history() -> void:
	var ada: Hero = _hero(A, "Ada")
	_hero(B, "Bea")
	for _index: int in 2:
		_battle_in(GameSession.ledger, [A, B], "victory", {"moments": [_moment("revived", A, B)]})
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1
	var hub: Node3D = _hub()
	hub._open(&"Forge")
	var roster: ItemList = hub.get_node("%RosterList") as ItemList
	for index: int in roster.item_count:
		if roster.get_item_text(index).contains("  Ada — "):
			roster.select(index)
			roster.multi_selected.emit(index, true)
	await _dreams_read(hub)
	var text: String = (hub.get_node("%HeroDetail") as Label).text
	assert_string_contains(text, "Closest to Bea: 2 hard fights, 2 saves.\nFriends: Bea.\n\nDream: repay Bea.\n  [x] Bea revived Ada at")
	assert_string_contains(text, "  [ ] Fight beside Bea again (1/3).\n  [ ] Save Bea.\n\nHistory:\n")
	assert_true(GameSession.roster.has(ada))


## ---- ig-m6o.2.2.6: the roles on the panel, in a meeting and in the partner's greeting

func test_the_panel_shows_the_roles_line_under_closest_to_and_none_when_no_role_is_held() -> void:
	_hero(A, "Ada")
	_hero(B, "Bea")
	_hero(C, "Cal")
	_hero(D, "Dov")
	var eve: Hero = _hero(E, "Eve")
	_hero(F, "Fay")
	for _index: int in 8:
		_battle_in(GameSession.ledger, [A, B], "retreated")
	for _index: int in 3:
		_battle_in(GameSession.ledger, [A, C], "retreated", {"kills": {A: 0, C: 2}})
		_battle_in(GameSession.ledger, [A, C], "retreated", {"kills": {A: 2, C: 0}})
	for who: String in [D, D, D, D, D, E, E, E, E]:
		Ledger.append(GameSession.ledger, GameSession.ledger.size() + 1, 0, "encounter", {"heroes": [A, who], "place": "Forge", "why": "coworkers"})
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1
	assert_ne(GameSession.dispatch_expedition([eve.instance_id], ZONE, 1, "Out"), "", GameSession.last_action_error)
	var hub: Node3D = _hub()
	hub._open(&"Forge")
	var detail: Label = hub.get_node("%HeroDetail") as Label
	_select(hub, "Ada")
	assert_string_contains(detail.text, "Closest to Bea: 8 hard fights.\nFriends: Bea. Rival: Cal. Works well with: Dov, Eve (away).\n\n")
	_select(hub, "Cal")
	assert_true(detail.text.contains("Rival: Ada.\n\n") and not detail.text.contains("Closest to"), "a role and no partner: the line alone")
	_select(hub, "Fay")
	for said: String in ["Friends:", "Rival:", "Works well with:", "Closest to"]:
		assert_false(detail.text.contains(said), "no bond, no role, no line: %s" % said)


func test_the_panel_lists_three_names_a_role_and_leaves_out_a_role_nobody_holds() -> void:
	_hero(A, "Ada")
	var names: Array[String] = [B, C, D, E, F]
	for id: String in names:
		_hero(id, id.substr(5).to_upper())
	for index: int in names.size():
		for _meeting_count: int in 8 + index:
			Ledger.append(GameSession.ledger, GameSession.ledger.size() + 1, 0, "encounter", {"heroes": [A, names[index]], "place": "House_1", "why": "neighbours"})
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1
	var hub: Node3D = _hub()
	hub._open(&"Forge")
	_select(hub, "Ada")
	assert_string_contains((hub.get_node("%HeroDetail") as Label).text, "Closest to F: 12 chats.\nFriends: F, E, D.\n\n")
	assert_false((hub.get_node("%HeroDetail") as Label).text.contains("Rival"), "a role nobody holds has no words")


func test_a_meeting_says_a_rival_line_else_a_collaborator_line_else_a_chat() -> void:
	for id: String in [A, B, C, D, E, F]:
		_hero(id, id.substr(5).to_upper())
	for _index: int in 3:
		_battle_in(GameSession.ledger, [A, B], "retreated", {"kills": {A: 0, B: 2}})
		_battle_in(GameSession.ledger, [A, B], "retreated", {"kills": {A: 2, B: 0}})
	for pair: Array in [[A, B], [C, D]]:
		for _index: int in 4:
			Ledger.append(GameSession.ledger, GameSession.ledger.size() + 1, 0, "encounter", {"heroes": pair, "place": "Forge", "why": "coworkers"})
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1
	var hub: Node3D = _hub()
	var town: TownView = hub.get_node("%Town") as TownView
	for expected: Array in [[A, B, "rival", "rivals and collaborators too: one bank, the rival's"], [C, D, "collaborator", "collaborators"], [E, F, "met", "no role"]]:
		var record: Dictionary = GameSession._record("encounter", {"heroes": [expected[0], expected[1]], "place": "Forge", "why": "neighbours"})
		var records: Array[Dictionary] = [record]
		GameSession._notify_social_recorded(records)
		var walker: TownWalker = town.walkers[expected[0]] as TownWalker
		assert_true(walker.is_meeting(), "the town played it: %s" % expected[3])
		assert_eq((walker.get("_chat_facts") as Dictionary)["kinds"], _kinds([expected[2]]), expected[3])


## A greeting's kinds without the partner's quirk kind (a hero's quirk comes from its id, and comes last).
func _no_quirks(facts: Dictionary) -> Array[String]:
	var kinds: Array[String] = []
	for kind: String in facts["kinds"]:
		if not kind.begins_with("quirk:"):
			kinds.append(kind)
	return kinds


func test_the_partners_greeting_adds_one_role_rival_first() -> void:
	_hero(A, "Ada")
	_hero(B, "Bea")
	_hero(C, "Cal")
	_hero(D, "Dov")
	for index: int in 4:
		_battle_in(GameSession.ledger, [A, B], "retreated", {"kills": {A: 0, B: 2}})
		_battle_in(GameSession.ledger, [A, B], "retreated", {"kills": {A: 2, B: 0}})
	for _index: int in 4:
		Ledger.append(GameSession.ledger, GameSession.ledger.size() + 1, 0, "encounter", {"heroes": [A, B], "place": "Forge", "why": "coworkers"})
	for _index: int in 8:
		Ledger.append(GameSession.ledger, GameSession.ledger.size() + 1, 0, "encounter", {"heroes": [C, D], "place": "Forge", "why": "coworkers"})
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1
	var hub: Node3D = _hub()
	assert_true(GameSession.embody_hero(A))
	assert_eq(hub._partner_id, B)
	assert_eq(_no_quirks(hub._partner_facts), _kinds(["hard", "rival"]), "a rival and a collaborator: the rival only")
	GameSession.step_out()
	assert_true(GameSession.embody_hero(C))
	assert_eq(hub._partner_id, D)
	assert_eq(_no_quirks(hub._partner_facts), _kinds(["met", "collaborator"]), "a collaborator alone")
	GameSession.step_out()
	assert_true(GameSession.embody_hero(B))
	assert_eq(_no_quirks(hub._partner_facts), _kinds(["hard", "rival"]), "the role is the pair's: Bea's partner is Ada, her rival too")


func test_the_partner_stands_in_town_greets_once_per_approach_and_leaves_with_an_order() -> void:
	var ada: Hero = _hero(A, "Ada")
	var bea: Hero = _hero(B, "Bea")
	_hero(C, "Cal")
	for _index: int in 2:
		_battle_in(GameSession.ledger, [A, B], "victory", {"moments": [_moment("revived", A, B)]})
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1
	var hub: Node3D = _hub()
	var town: TownView = hub.get_node("%Town") as TownView
	assert_true(GameSession.embody_hero(ada.instance_id))
	assert_not_null(town.partner, "Bea stands in town")
	assert_eq(town.partner.hero_id, B)
	assert_eq(town.partner, town.walkers.get(B), "Bea is her own walker, wherever her role takes her")
	await _frames(2)
	assert_eq(town.partner.greetings, 0, "no greeting on arrival")
	town.body.global_position = town.partner.global_position + Vector3(0.0, 0.0, 6.0)
	await _frames(2)
	town.body.global_position = town.partner.global_position + Vector3(-1.5, 0.0, 0.0)
	await _frames(2)
	assert_eq(town.partner.greetings, 1)
	assert_true(town.partner.is_showing_line())
	assert_eq((town.partner.get_node("Line") as Label3D).text, Lines.line(town.partner.facts, 0), "the first approach shows the pair's first line")
	assert_eq(town.partner.facts["kinds"], Lines.greeting_facts(Bonds.bond(GameSession.ledger, A, {A: true, B: true}, BALANCE), Bonds.dream(GameSession.ledger, B), A, {}, bea.quirks).get("kinds"), "saved_by, from Ada's bond, Bea's dream and Bea's quirk")
	assert_eq(town.partner.facts["kinds"], _kinds(["saved_by", "watch_over", "quirk:%s" % bea.quirks[0]]), "Bea revived Ada, so Bea watches over Ada, who is the one she says it to; her quirk comes last")
	assert_eq(town.partner.facts["own"], {"watch_over": {"place": Ledger.zone_name(ZONE)}}, "and the dream's own place")
	await _frames(5)
	assert_eq(town.partner.greetings, 1, "once per approach")
	GameSession.roster_changed.emit()
	await _frames(2)
	assert_eq(town.partner.greetings, 1, "a refresh keeps the figure and does not replay it")
	town.body.global_position = town.partner.global_position + Vector3(0.0, 0.0, 6.0)
	await _frames(2)
	town.body.global_position = town.partner.global_position + Vector3(-1.5, 0.0, 0.0)
	await _frames(2)
	assert_eq(town.partner.greetings, 2, "walking away re-arms it")
	GameSession.roster_changed.emit()
	await _frames(2)
	town.body.global_position = town.partner.global_position + Vector3(0.0, 0.0, 6.0)
	await _frames(2)
	town.body.global_position = town.partner.global_position + Vector3(-1.5, 0.0, 0.0)
	await _frames(2)
	assert_eq(town.partner.greetings, 3)
	assert_eq((town.partner.get_node("Line") as Label3D).text, Lines.line(town.partner.facts, 2), "a refresh with the same facts keeps the count: the third line, not the first again")
	assert_ne(GameSession.dispatch_expedition([bea.instance_id], ZONE, 1, "Out"), "", GameSession.last_action_error)
	assert_null(town.partner, "sent on an order, Bea leaves the town")
	GameSession.step_out()
	assert_true(GameSession.embody_hero(C))
	assert_null(town.partner, "Cal has no bond, so no one stands")


func test_the_expedition_pulse_never_reads_the_ledger() -> void:
	var hub: Node3D = _hub()
	assert_true(GameSession.roster_changed.is_connected(hub._refresh_partner))
	assert_false(GameSession.expeditions_changed.is_connected(hub._refresh_partner), "expeditions_changed fires every 0.25 s")
	assert_true(GameSession.expeditions_changed.is_connected(hub._show_partner))


func test_a_new_walker_gets_its_own_greeting() -> void:
	var ada: Hero = _hero(A, "Ada")
	_hero(B, "Bea")
	_hero(D, "Dov")
	for _index: int in 2:
		_battle_in(GameSession.ledger, [A, B, D], "victory", {"moments": [_moment("revived", A, B), _moment("revived", D, B)]})
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1
	var hub: Node3D = _hub()
	var town: TownView = hub.get_node("%Town") as TownView
	assert_true(GameSession.embody_hero(ada.instance_id))
	town.body.global_position = town.partner.global_position + Vector3(0.0, 0.0, 6.0)
	await _frames(2)
	town.body.global_position = town.partner.global_position + Vector3(-1.5, 0.0, 0.0)
	await _frames(2)
	assert_eq(town.partner.greetings, 1)
	assert_true(GameSession.embody_hero(D), "switch straight to Dov, who is also bonded to Bea")
	assert_eq(town.partner.hero_id, B, "the same figure stays")
	await _frames(2)
	assert_eq(town.partner.greetings, 2, "Dov, standing where Ada stood, is greeted too")


func test_a_walk_reaches_a_partner_at_its_house() -> void:
	var ada: Hero = _hero(A, "Ada")
	var bea: Hero = _hero(B, "Bea")
	for _index: int in 2:
		_battle_in(GameSession.ledger, [A, B], "victory", {"moments": [_moment("revived", A, B)]})
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1
	var hub: Node3D = _hub()
	var town: TownView = hub.get_node("%Town") as TownView
	var placed: bool = false
	for hex: Vector2i in [Vector2i(-2, 2), Vector2i(2, 1), Vector2i(-3, 3), Vector2i(1, 2)]:
		if GameSession.place_building(TownRules.HOUSE, hex):
			placed = true
			break
	assert_true(placed, GameSession.last_action_error)
	var house_id: StringName = StringName(str(GameSession.town_buildings.back()["id"]))
	GameSession.town_building(house_id).erase("build_remaining")
	assert_true(GameSession.assign_home(bea, house_id), GameSession.last_action_error)
	assert_true(GameSession.embody_hero(ada.instance_id))
	# Bea wanders now (ig-6m2.6.2); hold her at her door, the far corner the walk has to reach.
	town.partner.linger_at(town.work_spot(house_id), &"Idle_A", 0.0, 1.0e6)
	await get_tree().physics_frame
	# Start 7 m out on the camera side and walk in with W, as a player would.
	town.body.global_position = town.partner.global_position + Vector3(0.0, 0.0, 7.0)
	await get_tree().physics_frame
	_set_key(KEY_W, true)
	for _tick: int in 240:
		if town.partner.greetings > 0:
			break
		await get_tree().physics_frame
	_set_key(KEY_W, false)
	assert_eq(town.partner.greetings, 1, "the walk reaches her")


# ig-6m2.6.2: the partner is an ordinary walker. The greeting stops its walk, and the walk goes on.
func test_the_partner_stops_walking_to_greet_and_walks_on() -> void:
	var town: TownView = _bonded_town()
	var bea: TownWalker = town.partner
	var start: Vector3 = town.free_point(Vector3(-12.0, 0.0, 12.0))
	bea.linger_at(start, &"Idle_B", NAN, 1.0e6)
	bea.wander(PackedVector3Array([start + Vector3(12.0, 0.0, 0.0)]), &"Idle_B", NAN)
	town.body.global_position = town.to_global(start + Vector3(0.0, 0.0, 8.0))
	bea.step(0.1)
	town.body.global_position = town.to_global(bea.position + Vector3(0.0, 0.0, 2.0))
	bea.step(0.1)
	assert_eq(bea.greetings, 1, "within MEET_DISTANCE: it greets")
	assert_true(bea.is_showing_line())
	var stopped: Vector3 = bea.position
	for _step: int in 39:
		bea.step(0.1)
	assert_eq(bea.position, stopped, "it stands while the line shows")
	for _step: int in 3:
		bea.step(0.1)
	assert_ne(bea.position, stopped, "then walks on")
	assert_eq(bea.clip(), &"Walking_A")
	assert_false(bea.is_showing_line())
	for _step: int in 40:
		bea.step(0.1)
	assert_eq(bea.greetings, 1, "the body stayed: no second greeting")
	town.body.global_position = town.to_global(bea.position + Vector3(0.0, 0.0, 1.0))
	bea.step(0.1)
	assert_eq(bea.greetings, 2, "past REARM_DISTANCE and back: again")


# A load that puts the body beside its partner never fires the greeting at once.
func test_a_partner_inside_rearm_distance_at_the_start_waits() -> void:
	var town: TownView = _bonded_town(false)
	var bea: TownWalker = town.walkers[B]
	bea.linger_at(TownView.BODY_SPAWN + Vector3(1.5, 0.0, 0.0), &"Idle_B", NAN, 1.0e6)
	assert_true(GameSession.embody_hero(A))
	assert_eq(town.partner, bea)
	for _step: int in 5:
		bea.step(0.1)
	assert_eq(bea.greetings, 0, "it starts disarmed")
	town.body.global_position = town.to_global(bea.position + Vector3(0.0, 0.0, 6.0))
	bea.step(0.1)
	town.body.global_position = town.to_global(bea.position + Vector3(0.0, 0.0, 1.5))
	bea.step(0.1)
	assert_eq(bea.greetings, 1, "the body came back: now it greets")


# The ig-6m2.2 case: the old fixed spot sat in hex (1, 0). With the Sanctum moved off it and a House
# on it, the partner still never stands or walks inside a box.
func test_a_house_on_the_old_partner_spot_never_swallows_the_partner() -> void:
	GameSession.town_resources["wood"] = 1000.0
	var sanctum: Dictionary = GameSession.town_building(&"Sanctum")
	assert_eq(Vector2i(sanctum["q"], sanctum["r"]), Vector2i(1, 0), "the Sanctum starts on the old spot")
	var moved: bool = false
	for hex: Vector2i in [Vector2i(3, -3), Vector2i(-3, 3), Vector2i(2, 2), Vector2i(-2, -2)]:
		if GameSession.move_building(&"Sanctum", hex):
			moved = true
			break
	assert_true(moved, GameSession.last_action_error)
	assert_true(GameSession.place_building(TownRules.HOUSE, Vector2i(1, 0)), GameSession.last_action_error)
	var town: TownView = _bonded_town()
	var bea: TownWalker = town.partner
	var boxes: Array[Rect2] = _boxes(town)
	for _step: int in 600:
		bea.step(0.1)
		for box: Rect2 in boxes:
			if box.has_point(Vector2(bea.position.x, bea.position.z)):
				fail_test("the partner is inside a box at %s" % bea.position)
				return
	assert_eq(_walker_figures(town, B), 1)


## ---- ig-m6o.2.2.1: one pass for every pair, kept by the hub, shown on the roster and in town

func test_one_pass_answers_every_hero_as_the_per_hero_reader_did() -> void:
	# Every fact type and the legacy gaps, by hand.
	_battle([A, B, C], "retreated", {"order": "order:x", "moments": [_moment("revived", A, B), _moment("carried", B, A), _moment("revived", C, "enemy:goblin"), _moment("revived", C, C)]})
	_record("died", {"hero": D, "name": "Dov", "battle_order": "order:x"})
	_battle([A, B, D], "stranded", {"order": "order:y", "rescued": [B], "rescuers": [C]})
	_record("died", {"hero": A, "name": "Ada", "battle_order": "order:y"})
	_battle([B, C], "victory", {"rescued": [C], "order": "order:z"})
	_record("died", {"hero": C, "name": "Cal"})
	_battle([B, C], "victory")
	_assert_same_answers([A, B, C, D, "hero:none"])
	# And a seeded mess of them.
	_ledger = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var heroes: Array[String] = []
	for index: int in 9:
		heroes.append("hero:%d" % index)
	for index: int in 400:
		var team: Array[String] = []
		for _slot: int in rng.randi_range(1, 5):
			team.append(heroes[rng.randi_range(0, heroes.size() - 1)])
		var moments: Array = []
		for _moment_index: int in rng.randi_range(0, 3):
			var by: String = ["enemy:goblin", "", heroes[rng.randi_range(0, heroes.size() - 1)]][rng.randi_range(0, 2)]
			moments.append(_moment(["revived", "carried", "downed"][rng.randi_range(0, 2)], team[rng.randi_range(0, team.size() - 1)], by))
		var fields: Dictionary = {"order": "order:%d" % index, "result": ["victory", "retreated", "stranded"][rng.randi_range(0, 2)], "moments": moments}
		if rng.randi_range(0, 4) == 0:
			fields["rescued"] = [team[0]]
			if rng.randi_range(0, 1) == 0:
				fields["rescuers"] = [heroes[rng.randi_range(0, heroes.size() - 1)], heroes[rng.randi_range(0, heroes.size() - 1)]]
		_battle(team, str(fields["result"]), fields)
		if rng.randi_range(0, 9) == 0:
			var died: Dictionary = {"hero": team[team.size() - 1], "name": "X"}
			if rng.randi_range(0, 1) == 0:
				died["battle_order"] = "order:%d" % index
			_record("died", died)
	_assert_same_answers(heroes)


func test_a_rescuer_from_outside_the_team_is_the_rescued_heros_partner() -> void:
	# The review's case: Cal is only in rescuers. Bea scores the rescues toward Cal; Cal, in
	# neither team nor rescued, scores nothing, as in slice 1.
	_battle([B], "stranded", {"rescued": [B], "rescuers": [C]})
	_battle([B], "stranded", {"rescued": [B], "rescuers": [C]})
	var living: Dictionary = {B: true, C: true}
	var bond: Dictionary = Bonds.bond(_ledger, B, living, BALANCE)
	assert_eq(bond.get("partner"), C)
	assert_eq(bond.get("rescues"), 2)
	assert_eq(bond, _slice1_bond(_ledger, B, living, BALANCE))
	assert_true(Bonds.bond(_ledger, C, living, BALANCE).is_empty())
	_assert_same_answers([B, C])


func test_the_index_rebuilds_only_on_a_load_or_a_dropped_append() -> void:
	_hero(A, "Ada")
	_hero(B, "Bea")
	_hero(C, "Cal")
	for _index: int in 2:
		_battle_in(GameSession.ledger, [A, B], "victory", {"moments": [_moment("revived", A, B)]})
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1
	var builds: int = GameSession.bond_builds
	var hub: Node3D = _hub()
	assert_eq(GameSession.bond_builds - builds, 1, "the first refresh builds it")
	GameSession.roster_changed.emit()
	_select(hub, "Ada")
	for _pulse: int in 3:
		GameSession.expeditions_changed.emit()
	assert_true(GameSession.embody_hero(A))
	assert_eq(GameSession.bond_builds - builds, 1, "refreshes, a selection, pulses and walking rebuild nothing")
	GameSession._record("battle", {"order": "order:new", "zone": ZONE, "team": [A, C], "result": "retreated", "moments": []})
	GameSession.roster_changed.emit()
	GameSession.expeditions_changed.emit()
	assert_eq(GameSession.bond_builds - builds, 1, "an appended record folds in and rebuilds nothing")
	_assert_index_is_a_rebuild("after an append")
	var data: Dictionary = GameSession.to_dict()
	data["ledger"] = GameSession.ledger.duplicate(true)
	GameSession.from_dict(data)
	GameSession.roster_changed.emit()
	GameSession.roster_changed.emit()
	assert_eq(GameSession.bond_builds - builds, 2, "a load (a new array) rebuilds once")
	# A mutation that rolls back with no append: the same array and next seq, so the index holds.
	assert_false(GameSession._commit_profile_mutation(func() -> bool: return false))
	GameSession.roster_changed.emit()
	assert_eq(GameSession.bond_builds - builds, 2, "a rollback with no append rebuilds nothing")
	# One that appends and rolls back: the same array, cut back, with its old next seq.
	var seq: int = GameSession.ledger_next_seq
	var mutation := func() -> bool:
		for _index: int in 2:
			GameSession._record("battle", {"order": "order:gone", "zone": ZONE, "team": [A, C], "result": "victory", "moments": [_moment("revived", C, A)]})
		return false
	assert_false(GameSession._commit_profile_mutation(mutation))
	assert_eq(GameSession.ledger_next_seq, seq)
	GameSession.roster_changed.emit()
	assert_eq(GameSession.bond_builds - builds, 3, "a rolled-back append rebuilds once")
	var living: Dictionary = {A: true, B: true, C: true}
	for id: String in living:
		assert_eq(Bonds.bond_from(hub._bond_index(), id, living, BALANCE), Bonds.bond(GameSession.ledger, id, living, BALANCE), id)
	assert_eq(str(Bonds.bond(GameSession.ledger, C, living, BALANCE).get("partner", "")), "", "Cal's rolled-back saves are gone")


# No hub here: nothing asks for the index between the rollback and the appends.
func test_appends_after_a_rolled_back_append_never_read_a_stale_index() -> void:
	for _index: int in 2:
		GameSession._record("battle", {"order": "order:before", "zone": ZONE, "team": [A, B], "result": "retreated", "moments": []})
	GameSession.bond_index()
	var mutation := func() -> bool:
		for _index: int in 2:
			GameSession._record("battle", {"order": "order:gone", "zone": ZONE, "team": [A, C], "result": "victory", "moments": [_moment("revived", C, A)]})
		return false
	assert_false(GameSession._commit_profile_mutation(mutation))
	# As many new records as were dropped: the next seq lines up with the kept index's again, but the
	# index still holds the dropped ones.
	for _index: int in 2:
		GameSession._record("battle", {"order": "order:after", "zone": ZONE, "team": [A, B], "result": "retreated", "moments": []})
	_assert_index_is_a_rebuild("appends after a rollback")


func test_a_bonded_row_shows_its_partner_and_keeps_it_while_the_partner_is_away() -> void:
	var ada: Hero = _hero(A, "Ada")
	var bea: Hero = _hero(B, "Bea")
	_hero(C, "Cal")
	ada.favorite = true
	# Four saves: Ada, saved, reaches 8 in two (4 each); Bea, who saves, in four (2 each).
	for _index: int in 4:
		_battle_in(GameSession.ledger, [A, B, C], "victory", {"moments": [_moment("revived", A, B)]})
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1
	var hub: Node3D = _hub()
	hub._open(&"Forge")
	assert_string_contains(_row(hub, "Ada"), " · ★, ♥ Bea")
	assert_string_contains(_row(hub, "Bea"), " · ♥ Ada")
	assert_false(_row(hub, "Cal").contains("♥"), "an unbonded hero has no sign")
	assert_ne(GameSession.dispatch_expedition([bea.instance_id], ZONE, 1, "Out"), "", GameSession.last_action_error)
	assert_string_contains(_row(hub, "Ada"), "♥ Bea", "the flag stays while Bea is away")
	assert_string_contains(_row(hub, "Bea"), " · ♥ Ada, Away", "after the heart, before Away")


## ig-7sn.9: the hub reads every hero's sign once per ledger change and roster names, for the rows
## and the walkers both; a new bond, and a renamed partner with no record, still reach both.
func test_the_kept_partner_signs_follow_a_new_record_and_a_rename() -> void:
	_hero(A, "Ada")
	var bea: Hero = _hero(B, "Bea")
	_hero(C, "Cal")
	var hub: Node3D = _hub()
	hub._open(&"Forge")
	var town: TownView = hub.get_node("%Town") as TownView
	assert_false(_row(hub, "Ada").contains("♥"), "no bond yet")
	GameSession.roster_changed.emit()
	assert_false(_row(hub, "Ada").contains("♥"), "a roster change with no record keeps none")
	for _index: int in 2:
		GameSession._record("battle", {"order": "order:ab", "zone": ZONE, "team": [A, B], "result": "victory", "moments": [_moment("revived", A, B)]})
	GameSession.roster_changed.emit()
	assert_string_contains(_row(hub, "Ada"), "♥ Bea", "a new record: read again")
	assert_eq(_sign(town.walkers[A]), "♥ Bea", "the walker too")
	bea.hero_name = "Bee"
	GameSession.roster_changed.emit()
	assert_string_contains(_row(hub, "Ada"), "♥ Bee", "a rename writes no record, and still reads again")
	assert_eq(_sign(town.walkers[A]), "♥ Bee")


func test_bonded_walkers_carry_their_partner_signs_in_town() -> void:
	_hero(A, "Ada")
	var bea: Hero = _hero(B, "Bea")
	_hero(C, "Cal")
	for _index: int in 4:
		_battle_in(GameSession.ledger, [A, B, C], "victory", {"moments": [_moment("revived", A, B)]})
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1
	var town: TownView = _hub().get_node("%Town") as TownView
	assert_eq(_sign(town.walkers[A]), "♥ Bea")
	assert_eq(_sign(town.walkers[B]), "♥ Ada")
	assert_eq(_sign(town.walkers[C]), "", "Cal has no visible sign")
	assert_ne(GameSession.dispatch_expedition([bea.instance_id], ZONE, 1, "Out"), "", GameSession.last_action_error)
	assert_false(town.walkers.has(B), "Bea left the town, and her sign with her")
	assert_eq(_sign(town.walkers[A]), "♥ Bea", "Ada keeps hers")


func test_the_body_shows_its_sign_and_a_walker_hides_its_sign_while_it_greets() -> void:
	var town: TownView = _bonded_town(true, 4)
	assert_eq(_sign(town.body), "♥ Bea", "the body")
	var bea: TownWalker = town.partner
	assert_eq(_sign(bea), "♥ Ada")
	var start: Vector3 = town.free_point(Vector3(-12.0, 0.0, 12.0))
	bea.linger_at(start, &"Idle_B", NAN, 1.0e6)
	town.body.global_position = town.to_global(start + Vector3(0.0, 0.0, 8.0))
	bea.step(0.1)
	town.body.global_position = town.to_global(start + Vector3(0.0, 0.0, 2.0))
	bea.step(0.1)
	assert_true(bea.is_showing_line())
	assert_eq(_sign(bea), "", "the line shows, so the sign hides")
	GameSession.expeditions_changed.emit()
	assert_eq(_sign(bea), "", "a pulse keeps it hidden")
	for _step: int in 41:
		bea.step(0.1)
	assert_false(bea.is_showing_line())
	assert_eq(_sign(bea), "♥ Ada", "back when the line is gone")


func test_a_settled_battle_that_crosses_the_threshold_says_who_grew_close() -> void:
	var ada: Hero = _hero(A, "Ada")
	var bea: Hero = _hero(B, "Bea")
	_battle_in(GameSession.ledger, [A, B], "victory", {"moments": [_moment("revived", A, B), _moment("revived", B, A)]})
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1
	var hub: Node3D = _hub()
	var status: Label = hub.get_node("%Status") as Label
	status.text = "before"
	GameSession.roster_changed.emit()
	GameSession.expeditions_changed.emit()
	assert_eq(status.text, "before", "no ledger change, no notice")
	var order_id: String = GameSession.dispatch_expedition([ada.instance_id, bea.instance_id], ZONE, 1, "Out")
	assert_ne(order_id, "", GameSession.last_action_error)
	status.text = "before"
	var order: Dictionary = GameSession.expedition_orders[0]
	var battle: Dictionary = order["battle"] as Dictionary
	battle["status"] = "victory"
	battle["moments"] = [_moment("revived", A, B), _moment("revived", B, A)]
	order["phase"] = "returning"
	order["remaining_seconds"] = 0.0
	GameSession.tick_expeditions(0.1)
	assert_eq(GameSession.ledger.back()["kind"], "battle", "the settle wrote its record")
	assert_eq(status.text, "Ada and Bea grew close.")
	status.text = "before"
	GameSession.roster_changed.emit()
	assert_eq(status.text, "before", "said once")


func test_one_way_and_several_bonds_at_once_and_a_load_says_nothing() -> void:
	_hero(A, "Ada")
	_hero(B, "Bea")
	_hero(C, "Cal")
	_hero(D, "Dov")
	_hero(E, "Eve")
	_hero(F, "Fay")
	_hero(G, "Gil")
	for _index: int in 3:
		_battle_in(GameSession.ledger, [B, C], "victory", {"moments": [_moment("revived", B, C)]})
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1
	var hub: Node3D = _hub()
	var status: Label = hub.get_node("%Status") as Label
	for _index: int in 2:
		GameSession._record("battle", {"order": "order:ab", "zone": ZONE, "team": [A, B], "result": "victory", "moments": [_moment("revived", A, B)]})
	GameSession.roster_changed.emit()
	assert_eq(status.text, "Ada grew close to Bea.", "Bea stays closest to Cal")
	GameSession._record("battle", {"order": "order:cd", "zone": ZONE, "team": [A, D], "result": "victory", "moments": [_moment("revived", A, D), _moment("revived", A, D)]})
	GameSession._record("battle", {"order": "order:cd2", "zone": ZONE, "team": [A, D], "result": "victory", "moments": [_moment("revived", A, D)]})
	GameSession._record("battle", {"order": "order:cd3", "zone": ZONE, "team": [A, D], "result": "victory", "moments": [_moment("revived", A, D)]})
	GameSession.roster_changed.emit()
	assert_eq(status.text, "Ada grew close to Dov.", "Ada moves to Dov (12 over 8); Dov, who saved her, is at 6 and gets no one")
	status.text = "before"
	var data: Dictionary = GameSession.to_dict()
	var ledger: Array[Dictionary] = GameSession.ledger.duplicate(true)
	for _index: int in 3:
		ledger.append({"seq": ledger.back()["seq"] + 1, "at": 0, "kind": "battle", "order": "order:x", "zone": ZONE, "team": [C, D], "result": "retreated", "moments": [_moment("revived", C, D)]})
	data["ledger"] = ledger
	GameSession.from_dict(data)
	GameSession.roster_changed.emit()
	assert_eq(status.text, "before", "bonds that formed before a load say nothing")
	for _index: int in 2:
		GameSession._record("battle", {"order": "order:efg", "zone": ZONE, "team": [E, F, G], "result": "victory", "moments": [_moment("revived", E, F), _moment("revived", G, F)]})
	GameSession.roster_changed.emit()
	assert_eq(status.text, "Eve grew close to Fay. (+1 more)", "and Gil grew close to Fay, who is at 4 toward each and gets no one: Eve first, on the lower id")


## ADR item 5: a full all-pairs rebuild and the end-to-end roster refresh at the cap, with the
## largest preset team, best and worst of seven. A measurement for this bead, not a gate.
func test_rebuild_and_refresh_cost_at_the_cap() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var heroes: Array[String] = []
	for index: int in 50:
		heroes.append(_hero("hero:%d" % index, "H%d" % index).instance_id)
	for index: int in BALANCE.ledger_max_records:
		var team: Array[String] = _team(rng, heroes, 5)
		_battle_in(GameSession.ledger, team, "victory", _mix(rng, index, team))
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1
	var runs: Array[int] = []
	for _run: int in 7:
		var started: int = Time.get_ticks_usec()
		Bonds.index(GameSession.ledger, BALANCE)
		runs.append(Time.get_ticks_usec() - started)
	_print_cost("all-pairs rebuild (a load)", runs)
	var builds: int = GameSession.bond_builds
	var hub: Node3D = _hub()
	_select(hub, "H0")
	var folds: Array[int] = []
	var changed: Array[int] = []
	var quiet: Array[int] = []
	var pulse: Array[int] = []
	for run: int in 7:
		var team: Array[String] = _team(rng, heroes, 5)
		var started: int = Time.get_ticks_usec()
		GameSession._record("battle", {"order": "order:more%d" % run, "zone": ZONE, "team": team, "result": "retreated", "moments": [], "kills": _kills_for(run, team)})
		folds.append(Time.get_ticks_usec() - started)
		started = Time.get_ticks_usec()
		GameSession.roster_changed.emit()
		changed.append(Time.get_ticks_usec() - started)
		started = Time.get_ticks_usec()
		GameSession.roster_changed.emit()
		quiet.append(Time.get_ticks_usec() - started)
		started = Time.get_ticks_usec()
		GameSession.expeditions_changed.emit()
		pulse.append(Time.get_ticks_usec() - started)
	_print_cost("one record in: append, fold in, evict, fold out", folds)
	_print_cost("roster refresh after a new record (no rebuild, one dream read)", changed)
	_print_cost("roster refresh with no ledger change", quiet)
	_print_cost("0.25 s pulse", pulse)
	assert_eq(GameSession.ledger.size(), BALANCE.ledger_max_records)
	assert_eq(GameSession.bond_builds - builds, 1, "the first build; each new record folds in")
	assert_lt(folds.min() / 1000.0, 16.7, "one record folds in within a frame (the ADR's item 5; the worst of seven is printed)")


## ig-uu7.4: the cover-order build for a 50-hero launch at the cap, best and worst of seven. 25
## Knights and 25 back-row heroes, the most work a launch can ask of it. The index is kept (in step);
## the first read after a load is the rebuild above. A measurement for this bead, not a gate.
func test_cover_order_cost_for_a_50_hero_launch_at_the_cap() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var heroes: Array[String] = []
	var team: Array[Hero] = []
	for index: int in 50:
		var hero: Hero = _hero("hero:%d" % index, "H%d" % index)
		hero.def_id = &"knight" if index % 2 == 0 else &"mage"
		heroes.append(hero.instance_id)
		team.append(hero)
	for index: int in BALANCE.ledger_max_records:
		var members: Array[String] = _team(rng, heroes, 5)
		_battle_in(GameSession.ledger, members, "victory", _mix(rng, index, members))
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1
	GameSession.bond_index()
	var orders: Array[int] = []
	var snapshots: Array[int] = []
	var listed: int = 0
	for _run: int in 7:
		var started: int = Time.get_ticks_usec()
		var built: Dictionary = GameSession._cover_orders(team, BALANCE)
		orders.append(Time.get_ticks_usec() - started)
		listed = 0
		for order: Array in built.values():
			listed += order.size()
		started = Time.get_ticks_usec()
		GameSession._team_snapshots(team)
		snapshots.append(Time.get_ticks_usec() - started)
	_print_cost("cover orders, 25 Knights x 25 back row (%d listed)" % listed, orders)
	_print_cost("the whole 50-hero team snapshot, cover orders included", snapshots)
	assert_gt(listed, 0, "the Knights have bonds to list")


## ---- ig-m6o.2.2.9: the kept index folds each record in and out instead of rebuilding

func test_a_folded_index_equals_a_rebuild_after_every_append_and_eviction() -> void:
	var heroes: Array[String] = []
	for index: int in 8:
		heroes.append("hero:%d" % index)
	var refused: int = 0
	var respect_seen: bool = false
	var teamwork_seen: bool = false
	# Each seed twice: with encounters, which the cap evicts first (tier 0), and without, so the other kinds
	# still reach the evictions that can be refused.
	for with_chats: bool in [true, false]:
		for seed_value: int in [1, 2, 3]:
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value
			var ledger: Array[Dictionary] = []
			var tiers: Array[int] = []
			var folded: Dictionary = Bonds.index_state(ledger, BALANCE)
			for seq: int in range(1, 401):
				var made: Array = _random_record(rng, heroes, seq, false, with_chats)
				Ledger.append(ledger, seq, 0, made[0], made[1])
				tiers.append(Ledger.tier(ledger.back()))
				Bonds.fold_in(folded, ledger.back(), BALANCE)
				if _nonempty(folded["pairs"]) != _nonempty(Bonds.index(ledger, BALANCE)):
					fail_test("seed %d, chats %s: appending seq %d" % [seed_value, with_chats, seq])
					return
				if not _layers_have_their_facts(folded["counts"]):
					fail_test("seed %d, chats %s: a layer without its fact after appending seq %d" % [seed_value, with_chats, seq])
					return
				respect_seen = respect_seen or _any_count(folded["counts"], Bonds.RESPECT)
				teamwork_seen = teamwork_seen or _any_count(folded["counts"], Bonds.TEAMWORK)
				for record: Dictionary in Ledger.evict(ledger, tiers, 20):
					if not Bonds.fold_out(folded, record, BALANCE):
						refused += 1
						folded = Bonds.index_state(ledger, BALANCE)
				if _nonempty(folded["pairs"]) != _nonempty(Bonds.index(ledger, BALANCE)):
					fail_test("seed %d, chats %s: evicting after seq %d" % [seed_value, with_chats, seq])
					return
				if not _layers_have_their_facts(folded["counts"]):
					fail_test("seed %d, chats %s: a layer without its fact after evicting at seq %d" % [seed_value, with_chats, seq])
					return
	# The mix has deaths of routine wins and deaths before their battle, which today's game never
	# writes, so some take-outs are refused and rebuild; the count only shows the path ran.
	gut.p("FOLD PROPERTY: 2,400 appends under a cap of 20, %d take-outs refused and rebuilt" % refused)
	assert_gt(refused, 0)
	assert_true(respect_seen and teamwork_seen, "the mix really counts respect and teamwork, so the layer checks are not empty")


func test_the_kept_index_matches_a_rebuild_through_a_load_and_a_rollback() -> void:
	_fill_to_cap(20)
	var heroes: Array[String] = []
	for index: int in 8:
		heroes.append("hero:%d" % index)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for step: int in 200:
		if step == 70:
			var data: Dictionary = GameSession.to_dict()
			data["ledger"] = GameSession.ledger.duplicate(true)
			GameSession.from_dict(data)
		if step == 140:
			var mutation := func() -> bool:
				for _index: int in 3:
					var dropped: Array = _random_record(rng, heroes, GameSession.ledger_next_seq, false, true)
					GameSession._record(dropped[0], dropped[1])
				return false
			assert_false(GameSession._commit_profile_mutation(mutation))
		var made: Array = _random_record(rng, heroes, GameSession.ledger_next_seq, false, true)
		GameSession._record(made[0], made[1])
		if _nonempty(GameSession.bond_index()) != _nonempty(Bonds.index(GameSession.ledger, BALANCE)):
			fail_test("step %d" % step)
			break
	assert_eq(GameSession.ledger.size(), BALANCE.ledger_max_records)


func test_an_eviction_the_fold_cannot_take_out_rebuilds() -> void:
	_fill_to_cap(4)
	GameSession._record("battle", {"order": "order:1", "zone": ZONE, "team": [A, B, C], "result": "stranded", "moments": []})
	GameSession._record("died", {"hero": C, "name": "Cal", "battle_order": "order:1"})
	GameSession._record("battle", {"order": "order:2", "zone": ZONE, "team": [A, B], "result": "retreated", "moments": []})
	GameSession._record("summoned", {"hero": D, "name": "Dov", "rank": 0})
	assert_eq(int(GameSession.bond_index()[A][B]["deaths"]), 1)
	var builds: int = GameSession.bond_builds
	# A test tier list that evicts the death first while its battle stays.
	GameSession._ledger_tiers = Ledger.tiers(GameSession.ledger)
	GameSession._ledger_tiers[-3] = 0
	GameSession._record("ranked_up", {"hero": A, "from": 0, "to": 1})
	assert_eq(GameSession.ledger.size(), BALANCE.ledger_max_records)
	assert_false(GameSession.ledger.any(func(record: Dictionary) -> bool: return record["kind"] == "died"))
	assert_eq(int(GameSession.bond_index()[A][B]["deaths"]), 0, "the death seen together went with its record")
	assert_eq(GameSession.bond_builds - builds, 1, "the refused take-out rebuilt once")
	_assert_index_is_a_rebuild("after the rebuild")


## ACC 4 and ACC 10 at the real cap: a new record evicts an encounter before any routine battle or filler,
## oldest first. Taking one out is a fold out (no rebuild) and marks its two heroes (ig-m6o.2.2.10), so the hub reads their dreams in full.
func test_encounters_go_first_at_the_cap_and_evicting_them_rebuilds_nothing_and_marks_their_heroes() -> void:
	_fill_to_cap(20)
	_hero(A, "Ada")
	_hero(B, "Bea")
	for _index: int in 20:
		GameSession._record("encounter", {"heroes": [A, B], "place": "House_1", "why": "neighbours"})
	assert_eq(GameSession.ledger.size(), BALANCE.ledger_max_records)
	assert_eq(int(GameSession.bond_index()[A][B]["meetings"]), 20)
	var hub: Node3D = _hub()
	hub._dream(A)
	var builds: int = GameSession.bond_builds
	var reads: int = hub.dream_reads
	var first_chat: int = int(GameSession.ledger[BALANCE.ledger_max_records - 20]["seq"])
	for step: int in 20:
		GameSession._record("battle", {"order": "order:new%d" % step, "zone": ZONE, "team": [A, B], "result": "victory", "moments": []})
		var oldest: int = -1
		for record: Dictionary in GameSession.ledger:
			if record["kind"] == "encounter":
				oldest = int(record["seq"])
				break
		assert_eq(oldest, first_chat + step + 1 if step < 19 else -1, "step %d: the oldest chat went, the fillers stayed" % step)
		assert_eq(int(GameSession.ledger[0]["seq"]), 1, "step %d: no filler was evicted" % step)
		assert_eq(GameSession.ledger.size(), BALANCE.ledger_max_records)
		if step == 9:
			assert_eq(int(GameSession.bond_index()[A][B]["meetings"]), 10, "the index took each chat out")
			_assert_index_is_a_rebuild("halfway")
	assert_eq(GameSession.ledger.filter(func(record: Dictionary) -> bool: return record["kind"] == "battle").size(), 20, "every new battle stayed")
	assert_eq(GameSession.ledger.filter(func(record: Dictionary) -> bool: return record["kind"] == "encounter").size(), 0)
	assert_eq(GameSession.bond_builds, builds, "nothing rebuilt")
	_assert_index_is_a_rebuild("after")
	assert_eq(hub._dream(A), Bonds.dream(GameSession.ledger, A, null, false), "the dream is what a full read says")
	assert_eq(hub.dream_reads, reads + 1, "an eviction of Ada's chats marked her, so it was read in full, once")
	assert_eq(hub._dream(B), Bonds.dream(GameSession.ledger, B, null, false), "and Bea's too")
	assert_eq(hub.dream_reads, reads + 2)


## ig-m6o.2.2.4: one encounter in at the cap of a ledger a third of encounters, as the perf seed's is: append,
## fold in, evict the oldest encounter, fold it out. Best and worst of seven. A measurement, and the best must fit a frame.
func test_an_encounter_in_at_the_cap_costs_under_a_frame() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var heroes: Array[String] = []
	for index: int in 50:
		heroes.append("hero:%d" % index)
	for index: int in BALANCE.ledger_max_records:
		if index % 3 == 0:
			var pair: Array[String] = _team(rng, heroes, 2)
			pair.sort()
			Ledger.append(GameSession.ledger, index + 1, 0, "encounter", {"heroes": pair, "place": "House_1", "why": "coworkers" if index % 2 == 0 else "neighbours"})
		else:
			var team: Array[String] = _team(rng, heroes, 5)
			_battle_in(GameSession.ledger, team, "victory", _mix(rng, index, team))
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1
	GameSession.bond_index()
	var runs: Array[int] = []
	for run: int in 7:
		var chatting: Array[String] = _team(rng, heroes, 2)
		chatting.sort()
		var started: int = Time.get_ticks_usec()
		GameSession._record("encounter", {"heroes": chatting, "place": "House_1", "why": "coworkers" if run % 2 == 0 else "neighbours"})
		runs.append(Time.get_ticks_usec() - started)
	_print_cost("one encounter in: append, fold in, evict the oldest encounter, fold it out", runs)
	assert_eq(GameSession.ledger.size(), BALANCE.ledger_max_records)
	assert_lt(runs.min() / 1000.0, 16.7, "one meeting fits a frame")


## ig-m6o.2.2.5: one meal time in at the cap of a ledger a third of chats and meals, alternating, as the perf seed's
## is: eight tables of four (the ACC fixture's), each one append, fold in (12 pair counts), evict the oldest tier-0
## record, fold it out. Each of seven runs times one whole meal time, and must write eight records, keep the ledger at
## the cap and rebuild nothing. Best and worst of seven: a measurement, and the best must fit a frame. Then seven
## rebuilds of that ledger (a load), printed and not gated.
func test_a_meal_time_in_at_the_cap_costs_under_a_frame() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var heroes: Array[String] = []
	for index: int in 50:
		heroes.append("hero:%d" % index)
	for index: int in BALANCE.ledger_max_records:
		if index % 3 == 0:
			var pair: Array[String] = _team(rng, heroes, 2 if index % 6 == 0 else 4)
			pair.sort()
			if index % 6 == 0:
				Ledger.append(GameSession.ledger, index + 1, 0, "encounter", {"heroes": pair, "place": "House_1", "why": "neighbours"})
			else:
				Ledger.append(GameSession.ledger, index + 1, 0, "meal", {"diners": pair, "place": "House_1"})
		else:
			var team: Array[String] = _team(rng, heroes, 5)
			_battle_in(GameSession.ledger, team, "victory", _mix(rng, index, team))
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1
	GameSession.bond_index()
	var builds: int = GameSession.bond_builds
	var runs: Array[int] = []
	for run: int in 7:
		var meal_time: Array[Array] = []
		for _table: int in MEAL_TABLES:
			var sitting: Array[String] = _team(rng, heroes, 4)
			sitting.sort()
			meal_time.append(sitting)
		var seq: int = GameSession.ledger_next_seq
		var started: int = Time.get_ticks_usec()
		for table: Array in meal_time:
			GameSession._record("meal", {"diners": table, "place": "House_1"})
		runs.append(Time.get_ticks_usec() - started)
		assert_eq(GameSession.ledger_next_seq, seq + MEAL_TABLES, "run %d wrote one record a table" % (run + 1))
		assert_eq(GameSession.ledger.size(), BALANCE.ledger_max_records, "and stayed at the cap")
	assert_eq(GameSession.bond_builds, builds, "no run rebuilt the index")
	_print_cost("one meal time in (%d tables of 4): append, fold in, evict the oldest chat or meal, fold it out" % MEAL_TABLES, runs)
	assert_lt(runs.min() / 1000.0, 16.7, "one meal time fits a frame")
	var rebuilds: Array[int] = []
	for _run: int in 7:
		var started: int = Time.get_ticks_usec()
		Bonds.index(GameSession.ledger, BALANCE)
		rebuilds.append(Time.get_ticks_usec() - started)
	gut.p("BOND COST: all-pairs rebuild with chats and meals (a load), %d records, best %.2f ms, worst %.2f ms of 7" % [GameSession.ledger.size(), rebuilds.min() / 1000.0, rebuilds.max() / 1000.0])


## ACC 10 with meals, as ig-m6o.2.2.10 changes it: at the real cap, one meal time (eight tables) evicts the eight oldest
## meals as folds out, and each marks its diners (welcome_home and fight_beside read a meal). Ada sat at the first table, so
## she is marked: the hub's look after it draws her panel from the dream it kept and reads no dream in full on that frame;
## the next frame reads hers once, and what it reads is what a full read of every record says.
func test_a_meal_time_at_the_cap_marks_its_diners_and_the_hubs_look_reads_the_selected_one_a_frame_later() -> void:
	_fill_to_cap(40)
	_hero(A, "Ada")
	_hero(B, "Bea")
	var tables: Array[Array] = _meal_time()
	for index: int in 40:
		GameSession._record("meal", {"diners": tables[index % MEAL_TABLES], "place": "House_1"})
	assert_eq(GameSession.ledger.size(), BALANCE.ledger_max_records)
	var first_meal: int = int(GameSession.ledger[BALANCE.ledger_max_records - 40]["seq"])
	var hub: Node3D = _hub()
	hub._open(&"Forge")
	_select(hub, "Ada")
	await _dreams_read(hub)
	var builds: int = GameSession.bond_builds
	var reads: int = hub.dream_reads
	var records: Array[Dictionary] = []
	for table: Array in tables:
		records.append(GameSession._record("meal", {"diners": table, "place": "House_1"}))
	assert_eq(GameSession.ledger.size(), BALANCE.ledger_max_records)
	assert_eq(int(GameSession.ledger[BALANCE.ledger_max_records - 40]["seq"]), first_meal + MEAL_TABLES, "the eight oldest meals went")
	assert_eq(int(GameSession.ledger[0]["seq"]), 1, "no filler went")
	assert_eq(GameSession.bond_builds, builds, "eight take-outs rebuilt nothing")
	_assert_index_is_a_rebuild("after the meal time")
	GameSession._notify_social_recorded(records)
	assert_eq(hub.dream_reads, reads, "the notice's frame read no dream in full: Ada is marked and keeps hers")
	assert_eq(hub._marked_queue, [A] as Array[String], "and queued her once")
	assert_true(hub.is_processing())
	await _frames(2)
	assert_eq(hub.dream_reads, reads + 1, "the frame after read it once")
	assert_eq(hub._dream(A), Bonds.dream(GameSession.ledger, A, null, false), "and it is what a full read says")
	assert_eq(hub.dream_reads, reads + 1, "asking again read none")
	assert_true(hub._marked_queue.is_empty())
	assert_false(hub.is_processing(), "the process is off again")
	assert_eq(GameSession.bond_builds, builds, "nothing rebuilt")


## ig-m6o.2.2.10 (b): the reads a notice marked wait for later frames. Ada walks and Bea is her partner; Dov is the
## selected hero. Two notices in one frame, each evicting an old meal that seated Bea and Dov, mark both twice. Neither
## notice reads a dream; each hero is queued once however many notices marked it; the next frame reads one of them in
## full and the frame after it the other (at most one a frame), and each is what a full read says. Then nothing more.
func test_a_notices_marked_dreams_are_read_once_each_and_one_a_frame() -> void:
	_hero(A, "Ada")
	_hero(B, "Bea")
	_hero(D, "Dov")
	_fill_to_cap(8 + 2)
	for _index: int in 4:
		_battle_in(GameSession.ledger, [A, B], "retreated", {"kills": {A: 0, B: 2}})
		_battle_in(GameSession.ledger, [A, B], "retreated", {"kills": {A: 2, B: 0}})
	Ledger.append(GameSession.ledger, GameSession.ledger.size() + 1, 0, "meal", {"diners": [B, D, "hero:g", "hero:h"], "place": "House_1"})
	Ledger.append(GameSession.ledger, GameSession.ledger.size() + 1, 0, "meal", {"diners": [B, D, "hero:g", "hero:h"], "place": "House_1"})
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1
	assert_eq(GameSession.ledger.size(), BALANCE.ledger_max_records)
	var hub: Node3D = _hub()
	assert_true(GameSession.embody_hero(A))
	assert_eq(hub._partner_id, B)
	hub._open(&"Forge")
	_select(hub, "Dov")
	await _dreams_read(hub)
	var reads: int = hub.dream_reads
	for table: Array in [[B, D, "hero:i", "hero:j"], [B, D, "hero:k", "hero:l"]]:
		var records: Array[Dictionary] = [GameSession._record("meal", {"diners": table, "place": "House_1"})]
		GameSession._notify_social_recorded(records)
	assert_eq(hub.dream_reads, reads, "neither notice read a dream in full")
	assert_eq(hub._marked_queue.size(), 2, "Bea and Dov are queued once each, though two notices marked both")
	assert_true(hub._marked_queue.has(B) and hub._marked_queue.has(D))
	await _frames(2)
	assert_eq(hub.dream_reads, reads + 1, "the next frame read one hero in full")
	await _frames(1)
	assert_eq(hub.dream_reads, reads + 2, "and the one after it the other")
	await _frames(3)
	assert_eq(hub.dream_reads, reads + 2, "then no more: each marked hero was read once")
	assert_false(hub.is_processing())
	for id: String in [B, D]:
		assert_eq(hub._dream(id), Bonds.dream(GameSession.ledger, id, null, false), "%s's dream is what a full read says" % id)
	assert_eq(hub.dream_reads, reads + 2, "asking read none")


## A queued hero that is neither the selected one nor the partner any more is dropped without a read (ig-m6o.2.2.10: a
## pick queues a hero who was never read too, so picking Ada queues her, and picking Bea queues Bea).
func test_a_queued_hero_who_is_no_longer_shown_is_dropped_without_a_read() -> void:
	_hero(A, "Ada")
	_hero(B, "Bea")
	_fill_to_cap(1)
	Ledger.append(GameSession.ledger, GameSession.ledger.size() + 1, 0, "meal", {"diners": [A, B, C, D], "place": "House_1"})
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1
	var hub: Node3D = _hub()
	hub._open(&"Forge")
	var reads: int = hub.dream_reads
	_select(hub, "Ada")
	assert_eq(hub._marked_queue, [A] as Array[String], "picking Ada queued her")
	_select(hub, "Bea")
	assert_eq(hub._selected_hero().instance_id, B)
	assert_eq(hub._marked_queue, [A, B] as Array[String], "and picking Bea queued her too")
	assert_eq(hub.dream_reads, reads, "neither pick read a dream in full")
	await _frames(4)
	assert_eq(hub.dream_reads, reads + 1, "Bea, who is on show, was read once; Ada is not on show any more, so she never was")
	assert_true(hub._marked_queue.is_empty())
	assert_false(hub.is_processing())
	assert_eq(hub._dream(B), Bonds.dream(GameSession.ledger, B, null, false))


## ig-m6o.2.2.10 (R7): a view redraw never reads a dream in full on its own frame. A pick of a hero the hub never read
## draws the panel without the dream; the next frame reads it once and the panel then says what a full read says.
func test_picking_a_never_read_hero_reads_no_dream_on_its_frame_and_shows_it_the_next() -> void:
	_hero(A, "Ada")
	_hero(B, "Bea")
	for _index: int in 2:
		_battle_in(GameSession.ledger, [A, B], "victory", {"moments": [_moment("revived", A, B)]})
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1
	var hub: Node3D = _hub()
	hub._open(&"Forge")
	var label: Label = hub.get_node("%HeroDetail") as Label
	var reads: int = hub.dream_reads
	_select(hub, "Ada")
	assert_eq(hub.dream_reads, reads, "no dream was read in full on the pick's frame")
	assert_string_contains(label.text, "Closest to Bea")
	assert_false(label.text.contains("Dream:"), "the panel shows no dream yet")
	assert_eq(hub._marked_queue, [A] as Array[String], "and Ada is queued")
	assert_true(hub.is_processing())
	await _frames(2)
	assert_eq(hub.dream_reads, reads + 1, "the frame after read it once")
	assert_string_contains(label.text, "Dream: repay Bea.")
	assert_eq(hub._dream(A), Bonds.dream(GameSession.ledger, A, null, false), "and it is what a full read says")
	var shown: String = label.text
	hub._refresh_hero_detail()
	assert_eq(label.text, shown, "a redraw from the dream it read draws the same panel")
	assert_eq(hub.dream_reads, reads + 1)
	assert_true(hub._marked_queue.is_empty())
	assert_false(hub.is_processing())


## R7: a settle at the cap whose eviction marked the walking hero's partner, who is the selected hero too. The redraws of
## the greeting and of the panel draw the dream the hub kept, nothing is read in full on the settle's frame, the partner
## is queued once for both views, and the frame after reads it once and redraws both.
func test_a_settle_that_marks_the_partner_reads_no_dream_on_its_frame() -> void:
	_hero(A, "Ada")
	_hero(B, "Bea")
	_fill_to_cap(8 + 1)
	for _index: int in 4:
		_battle_in(GameSession.ledger, [A, B], "retreated", {"kills": {A: 0, B: 2}})
		_battle_in(GameSession.ledger, [A, B], "retreated", {"kills": {A: 2, B: 0}})
	Ledger.append(GameSession.ledger, GameSession.ledger.size() + 1, 0, "encounter", {"heroes": [B, "hero:g"], "place": "House_1", "why": "neighbours"})
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1
	assert_eq(GameSession.ledger.size(), BALANCE.ledger_max_records)
	var hub: Node3D = _hub()
	assert_true(GameSession.embody_hero(A))
	assert_eq(hub._partner_id, B)
	hub._open(&"Forge")
	_select(hub, "Bea")
	await _dreams_read(hub)
	var reads: int = hub.dream_reads
	var facts: Dictionary = hub._partner_facts.duplicate(true)
	var panel: String = (hub.get_node("%HeroDetail") as Label).text
	GameSession._record("summoned", {"hero": "hero:h", "name": "Hal", "rank": 0})
	assert_false(GameSession.ledger.any(func(record: Dictionary) -> bool: return record["kind"] == "encounter"), "Bea's chat went")
	GameSession.roster_changed.emit()
	assert_eq(hub.dream_reads, reads, "the settle's frame read no dream in full")
	assert_eq(hub._marked_queue, [B] as Array[String], "Bea is queued once, for the greeting and the panel")
	assert_eq(hub._partner_facts, facts, "the greeting was drawn again from the kept dream")
	assert_eq((hub.get_node("%HeroDetail") as Label).text, panel, "and so was the panel")
	await _frames(2)
	assert_eq(hub.dream_reads, reads + 1, "the frame after read her once")
	assert_eq(hub._dream(B), Bonds.dream(GameSession.ledger, B, null, false), "what a full read says")
	assert_true(hub._marked_queue.is_empty())
	assert_false(hub.is_processing())


## R7: a settle that hands the walker a partner the hub never read (Cal's saves pass Bea's) draws the greeting without
## Cal's dream and reads nothing in full on its frame; the next frame reads it once and the greeting then carries it.
func test_a_settle_that_gives_the_walker_a_never_read_partner_reads_no_dream_on_its_frame() -> void:
	_hero(A, "Ada")
	_hero(B, "Bea")
	_hero(C, "Cal")
	for _index: int in 2:
		_battle_in(GameSession.ledger, [A, B], "victory", {"moments": [_moment("revived", A, B)]})
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1
	var hub: Node3D = _hub()
	assert_true(GameSession.embody_hero(A))
	assert_eq(hub._partner_id, B)
	await _dreams_read(hub)
	var reads: int = hub.dream_reads
	for step: int in 4:
		GameSession._record("battle", {"order": "order:c%d" % step, "zone": ZONE, "team": [A, C], "result": "victory", "moments": [_moment("revived", C, A)]})
	GameSession.roster_changed.emit()
	assert_eq(hub._partner_id, C, "Cal's four saves pass Bea's two")
	assert_eq(hub.dream_reads, reads, "the settle's frame read no dream in full")
	assert_eq(hub._marked_queue, [C] as Array[String])
	assert_false((hub._partner_facts["kinds"] as Array).has("debt"), "the greeting has no dream of Cal's yet")
	await _frames(2)
	assert_eq(hub.dream_reads, reads + 1, "the frame after read Cal once")
	assert_true((hub._partner_facts["kinds"] as Array).has("debt"), "and the greeting carries Cal's open dream, which owes Ada")
	assert_eq(hub._dream(C), Bonds.dream(GameSession.ledger, C, null, false), "what a full read says")
	assert_true(hub._marked_queue.is_empty())
	assert_false(hub.is_processing())


## ig-m6o.2.2.10: a notice that touches the walking hero's partner but not the walking hero redraws the greeting too (a
## partner's dream can now change on a meal or a chat). One that touches neither does not.
func test_a_notice_that_touches_the_partner_redraws_the_greeting_and_one_that_touches_neither_does_not() -> void:
	_hero(A, "Ada")
	_hero(B, "Bea")
	_hero(C, "Cal")
	for _index: int in 4:
		_battle_in(GameSession.ledger, [A, B], "retreated", {"kills": {A: 0, B: 2}})
		_battle_in(GameSession.ledger, [A, B], "retreated", {"kills": {A: 2, B: 0}})
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1
	var hub: Node3D = _hub()
	assert_true(GameSession.embody_hero(A))
	assert_eq(hub._partner_id, B)
	hub._partner_facts = {"sentinel": true}
	var records: Array[Dictionary] = [GameSession._record("meal", {"diners": [C, "hero:g", "hero:h", "hero:i"], "place": "House_1"})]
	GameSession._notify_social_recorded(records)
	assert_eq(hub._partner_facts, {"sentinel": true}, "a meal that seats neither of them leaves the greeting")
	records = [GameSession._record("meal", {"diners": [B, C, "hero:g", "hero:h"], "place": "House_1"})]
	GameSession._notify_social_recorded(records)
	assert_ne(hub._partner_facts, {"sentinel": true}, "a meal that seats the partner alone draws it again")
	assert_true((hub._partner_facts as Dictionary).has("kinds"))


## ig-m6o.2.2.10 (R8): a hero queued on one frame and asked for again on the next is not read in full on that next frame.
## Ada is queued on the pick's frame; a redraw asks for her again on the frame after, ahead of the hub's _process (an
## awaited frame resumes before the nodes' _process, as GameSession's own _process does), so her read waits one more.
func test_a_hero_queued_a_frame_ago_and_asked_again_is_not_read_on_that_frame() -> void:
	_hero(A, "Ada")
	_hero(B, "Bea")
	for _index: int in 2:
		_battle_in(GameSession.ledger, [A, B], "victory", {"moments": [_moment("revived", A, B)]})
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1
	var hub: Node3D = _hub()
	hub._open(&"Forge")
	var reads: int = hub.dream_reads
	_select(hub, "Ada")
	assert_eq(hub._marked_queue, [A] as Array[String], "the pick queued Ada")
	await _frames(1)
	hub._refresh_hero_detail()
	assert_eq(hub._marked_queue, [A] as Array[String], "asking again queued her no second time")
	await _frames(1)
	assert_eq(hub.dream_reads, reads, "the frame she was asked on read no dream in full")
	await _frames(1)
	assert_eq(hub.dream_reads, reads + 1, "the frame after read her once")
	assert_string_contains((hub.get_node("%HeroDetail") as Label).text, "Dream: repay Bea.")
	assert_true(hub._marked_queue.is_empty())


## R8: a frame that carries a notice the hub redraws on reads no queued hero in full, whatever the notice touches. Ada is
## queued on the pick's frame and the notice comes on the next one; it does not touch her, so nothing asks for her again,
## and her read still waits a frame.
func _assert_a_notice_defers_the_read(what: String, notice: Callable) -> void:
	_hero(A, "Ada")
	_hero(B, "Bea")
	_hero(C, "Cal")
	for _index: int in 2:
		_battle_in(GameSession.ledger, [A, B], "victory", {"moments": [_moment("revived", A, B)]})
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1
	var hub: Node3D = _hub()
	hub._open(&"Forge")
	var reads: int = hub.dream_reads
	_select(hub, "Ada")
	assert_eq(hub._marked_queue, [A] as Array[String], "%s: the pick queued Ada" % what)
	await _frames(1)
	notice.call()
	await _frames(1)
	assert_eq(hub.dream_reads, reads, "%s: the notice's frame read no dream in full" % what)
	await _frames(1)
	assert_eq(hub.dream_reads, reads + 1, "%s: the frame after read her once" % what)
	assert_true(hub._marked_queue.is_empty())


func test_a_pulse_on_the_frame_after_a_pick_defers_the_read_a_frame() -> void:
	await _assert_a_notice_defers_the_read("a pulse", func() -> void: GameSession.expeditions_changed.emit())


func test_a_settle_on_the_frame_after_a_pick_defers_the_read_a_frame() -> void:
	await _assert_a_notice_defers_the_read("a settle", func() -> void: GameSession.roster_changed.emit())


func test_a_meal_of_others_on_the_frame_after_a_pick_defers_the_read_a_frame() -> void:
	await _assert_a_notice_defers_the_read("a meal of others", _meal_of_others)


## A meal that seats neither Ada nor Bea (Cal and three heroes who are not on the roster), told to the hub.
func _meal_of_others() -> void:
	var records: Array[Dictionary] = [GameSession._record("meal", {"diners": [C, "hero:g", "hero:h", "hero:i"], "place": "House_1"})]
	GameSession._notify_social_recorded(records)


## Ada walking, bonded to Bea (Ada's partner), the ledger holding records ([kind, fields] pairs, oldest first). at_cap puts a
## chat of Cal and Dov before them, the oldest tier-0 record, which the next append evicts (it names neither of the two),
## and pads the ledger to the real cap with summons after them. Returns the hub, Bea's dream read once.
func _walker_with_partner(records: Array, at_cap: bool) -> Node3D:
	_hero(A, "Ada")
	_hero(B, "Bea")
	_hero(C, "Cal")
	var seq: int = 0
	var seeded: Array = []
	if at_cap:
		seeded.append(["encounter", {"heroes": [C, D], "place": "House_1", "why": "neighbours"}])
	seeded.append_array(records)
	for entry: Array in seeded:
		seq += 1
		Ledger.append(GameSession.ledger, seq, 0, entry[0], entry[1])
	while at_cap and GameSession.ledger.size() < BALANCE.ledger_max_records:
		seq += 1
		Ledger.append(GameSession.ledger, seq, 0, "summoned", {"hero": "filler:%d" % seq, "name": "F", "rank": 0})
	GameSession.ledger_next_seq = seq + 1
	var hub: Node3D = _hub()
	assert_true(GameSession.embody_hero(A))
	assert_eq(hub._partner_id, B, "Bea is Ada's partner")
	await _dreams_read(hub)
	return hub


## What a tick that changes the partner's dream does to the greeting (ACC 6, through social_recorded and no roster_changed):
## the lines of `kind` are in the greeting's candidates or not, the refresh resumed her kept dream and read none in full,
## and her dream is what a full read says.
func _assert_greeting_moved(hub: Node3D, kind: String, gained: bool, reads: int, resumes: int, before: Array[String]) -> void:
	assert_signal_not_emitted(GameSession, "roster_changed")
	var after: Array[String] = Lines.candidates(hub._partner_facts)
	assert_eq((hub._partner_facts["kinds"] as Array).has(kind), gained, "%s is in the greeting's kinds: %s" % [kind, gained])
	var lines: Array = Lines.BANK[kind]
	assert_eq(after.size(), before.size() + (lines.size() if gained else -lines.size()), "the candidates moved by %s's lines" % kind)
	for line: String in lines:
		assert_eq(after.has(line), gained, "%s's line is in the candidates: %s" % [kind, gained])
	assert_eq(hub.dream_reads, reads, "the refresh read no dream in full")
	assert_eq(hub.dream_resumes, resumes + 1, "it resumed Bea's kept dream once")
	assert_eq(hub._dream(B), Bonds.dream(GameSession.ledger, B, null, false), "and the dream is what a full read says")


## A chat that is the fourth of Ada and Bea (the bond is at the threshold from three chats and five meals) opens Bea's
## fight_beside toward Ada, and her greeting gains its lines.
func _assert_a_meeting_opens_fight_beside(at_cap: bool) -> void:
	var records: Array = []
	for _index: int in 3:
		records.append(["encounter", {"heroes": [A, B], "place": "House_1", "why": "neighbours"}])
	for _index: int in 5:
		records.append(["meal", {"diners": [A, B], "place": "House_1"}])
	var hub: Node3D = await _walker_with_partner(records, at_cap)
	assert_false((hub._partner_facts["kinds"] as Array).has("fight_beside"), "three chats: no dream yet")
	var before: Array[String] = Lines.candidates(hub._partner_facts)
	var reads: int = hub.dream_reads
	var resumes: int = hub.dream_resumes
	watch_signals(GameSession)
	var tick: Array[Dictionary] = [GameSession._record("encounter", {"heroes": [A, B], "place": "House_1", "why": "neighbours"})]
	assert_eq(GameSession.ledger.size() == BALANCE.ledger_max_records and int(GameSession.ledger[0]["seq"]) == 2, at_cap, "at the cap the tick evicted Cal and Dov's chat")
	GameSession._notify_social_recorded(tick)
	_assert_greeting_moved(hub, "fight_beside", true, reads, resumes, before)


func test_a_meeting_that_opens_the_partners_fight_beside_adds_its_lines_to_the_greeting() -> void:
	await _assert_a_meeting_opens_fight_beside(false)


func test_a_meeting_at_the_cap_that_opens_the_partners_fight_beside_resumes_her_dream() -> void:
	await _assert_a_meeting_opens_fight_beside(true)


## A meal that is the third at Ada's table since Ada was carried home fulfils Bea's welcome_home, and her greeting drops
## its lines. The rescue names Bea nowhere (Cal carried Ada home), and Ada's latest meal before it was at Bea's table.
func _assert_a_meal_fulfils_welcome_home(at_cap: bool) -> void:
	var records: Array = []
	for _index: int in 3:
		records.append(["encounter", {"heroes": [A, B], "place": "House_1", "why": "neighbours"}])
	for _index: int in 4:
		records.append(["meal", {"diners": [A, B], "place": "House_1"}])
	records.append(["battle", {"order": "order:rescue", "zone": ZONE, "team": [A, C], "result": "victory", "moments": [], "rescued": [A], "rescuers": [C]}])
	for _index: int in 2:
		records.append(["meal", {"diners": [A, B], "place": "House_1"}])
	var hub: Node3D = await _walker_with_partner(records, at_cap)
	assert_eq(hub._dream(B)["dream"], "welcome_home", "Bea's dream is to welcome Ada home")
	assert_true((hub._partner_facts["kinds"] as Array).has("welcome_home"))
	var before: Array[String] = Lines.candidates(hub._partner_facts)
	var reads: int = hub.dream_reads
	var resumes: int = hub.dream_resumes
	watch_signals(GameSession)
	var tick: Array[Dictionary] = [GameSession._record("meal", {"diners": [A, B], "place": "House_1"})]
	assert_eq(GameSession.ledger.size() == BALANCE.ledger_max_records and int(GameSession.ledger[0]["seq"]) == 2, at_cap, "at the cap the tick evicted Cal and Dov's chat")
	GameSession._notify_social_recorded(tick)
	assert_eq(hub._dream(B)["state"], "fulfilled", "the third meal fulfilled it")
	_assert_greeting_moved(hub, "welcome_home", false, reads, resumes, before)


func test_a_meal_that_fulfils_the_partners_welcome_home_drops_its_lines_from_the_greeting() -> void:
	await _assert_a_meal_fulfils_welcome_home(false)


func test_a_meal_at_the_cap_that_fulfils_the_partners_welcome_home_resumes_her_dream() -> void:
	await _assert_a_meal_fulfils_welcome_home(true)


## The premise of ig-m6o.2.2.10's meal marks (Bonds.OUT_MARKS): Ledger.evict takes meals oldest first, so an evicted meal
## is the oldest meal the ledger holds. Over a random mix of every kind at a small cap, each meal that goes is older than
## every meal that stays.
func test_evicting_takes_meals_oldest_first() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var kinds: Array[String] = ["meal", "meal", "encounter", "battle", "battle", "summoned", "died", "ranked_up"]
	var ledger: Array[Dictionary] = []
	var tier_list: Array[int] = []
	var meals_evicted: int = 0
	for seq: int in range(1, 601):
		var kind: String = kinds[rng.randi() % kinds.size()]
		var fields: Dictionary = {"hero": A, "team": [A, B], "result": "victory", "moments": [], "name": "x"}
		if kind == "meal":
			fields = {"diners": [A, B], "place": "House_1"}
		elif kind == "encounter":
			fields = {"heroes": [A, B], "place": "House_1"}
		Ledger.append(ledger, seq, 0, kind, fields)
		tier_list.append(Ledger.tier(ledger.back()))
		for gone: Dictionary in Ledger.evict(ledger, tier_list, 30):
			if gone["kind"] != "meal":
				continue
			meals_evicted += 1
			for kept: Dictionary in ledger:
				if kept["kind"] == "meal":
					assert_gt(int(kept["seq"]), int(gone["seq"]), "meal %d went while the older meal %d stayed" % [int(gone["seq"]), int(kept["seq"])])
	assert_gt(meals_evicted, 20, "the run evicted meals")


## A meal taken out marks its diners; every other owner's kept dream stays what a full read of what is left says.
## Ada sat at Bea's latest meal, which is the oldest meal too: taking it out un-sets her flag, so a rescue of Bea
## that follows opens a welcome home for Ada on her kept read and not on a full one, which is why Ada is marked. Dov's
## flag for Bea was false (Bea's latest meal did not seat him), and stays false without a mark.
func test_a_meal_taken_out_marks_its_diners_and_leaves_the_others_kept_dreams_as_a_full_read_says() -> void:
	_meal([A, B])
	_meal([C, D])
	var kept_ada: Dictionary = Bonds.dream_fold(_ledger, A)
	var kept_dov: Dictionary = Bonds.dream_fold(_ledger, D)
	_battle([C, B], "victory", {"rescued": [B], "rescuers": [C]})
	var gone: Array[Dictionary] = Ledger.evict(_ledger, Ledger.tiers(_ledger), _ledger.size() - 1)
	assert_eq(gone.size(), 1, "a cap one short took one record out")
	assert_eq(gone[0]["diners"], [A, B], "the oldest meal")
	var state: Dictionary = Bonds.index_state(gone, _counting)
	Bonds.fold_out(state, gone[0], _counting)
	assert_eq(state["out_named"].keys(), [A, B], "the meal marks its two diners and no one else")
	var full_ada: Dictionary = Bonds.dream(_ledger, A, null, false)
	var resumed_ada: Dictionary = Bonds.dream_of(Bonds.dream_fold(_ledger, A, kept_ada))
	assert_eq(full_ada, {}, "Ada, read in full without the meal, has no dream")
	assert_eq(resumed_ada["dream"], "welcome_home", "and her kept read would say one")
	assert_eq(Bonds.dream_of(Bonds.dream_fold(_ledger, D, kept_dov)), Bonds.dream(_ledger, D, null, false), "Dov's kept read is as a full one")
	_ledger = []
	_meal([A, B])
	_meal([B, D])
	kept_dov = Bonds.dream_fold(_ledger, D)
	_battle([C, B], "victory", {"rescued": [B], "rescuers": [C]})
	assert_eq(Ledger.evict(_ledger, Ledger.tiers(_ledger), _ledger.size() - 1)[0]["diners"], [A, B], "the oldest meal went")
	var found: Dictionary = Bonds.dream(_ledger, D, null, false)
	assert_eq(found["dream"], "welcome_home", "Dov sat at Bea's latest meal, which stays")
	assert_eq(Bonds.dream_of(Bonds.dream_fold(_ledger, D, kept_dov)), found, "and his kept read is the same without a mark")


## The panel names an ended dream (a dream that ended says so instead of its goals), which failed with a typed-array
## error before ig-m6o.2.2.10 fixed Bonds.dream_lines' return.
func test_the_panel_says_an_ended_dream() -> void:
	_hero(A, "Ada")
	_hero(B, "Bea")
	GameSession._record("battle", {"order": "order:1", "zone": ZONE, "team": [A, B], "result": "victory", "moments": [_moment("revived", A, B)]})
	GameSession._record("died", {"hero": B, "name": "Bea", "cause": "expedition", "zone": ZONE})
	var hub: Node3D = _hub()
	hub._open(&"Forge")
	_select(hub, "Ada")
	await _dreams_read(hub)
	assert_string_contains((hub.get_node("%HeroDetail") as Label).text, "Dream lost: Bea died before the debt was paid.")


## The two dreams of ig-m6o.2.2.10 on the panel, and a ledger change below the cap resumes each (a read of the records
## since, not a read in full).
func test_the_panel_shows_fight_beside_and_a_refresh_resumes_it() -> void:
	_hero(A, "Ada")
	_hero(B, "Bea")
	for _index: int in 4:
		GameSession._record("encounter", {"heroes": [A, B], "place": "House_1", "why": "neighbours"})
	var hub: Node3D = _hub()
	hub._open(&"Forge")
	_select(hub, "Ada")
	await _dreams_read(hub)
	var label: Label = hub.get_node("%HeroDetail") as Label
	assert_string_contains(label.text, "Dream: fight beside Bea.
  [x] Got to know Bea in town (4 chats).
  [ ] Fight beside Bea (0/3).")
	var reads: int = hub.dream_reads
	var resumes: int = hub.dream_resumes
	GameSession._record("battle", {"order": "order:1", "zone": ZONE, "team": [A, B], "result": "victory", "moments": []})
	GameSession.roster_changed.emit() # a battle settles with a roster change
	assert_string_contains(label.text, "  [ ] Fight beside Bea (1/3).")
	assert_eq([hub.dream_reads, hub.dream_resumes], [reads, resumes + 1], "the refresh resumed and read nothing in full")


func test_the_panel_shows_welcome_home_and_a_meal_tick_resumes_it() -> void:
	_hero(A, "Ada")
	_hero(B, "Bea")
	_hero(C, "Cal")
	GameSession._record("meal", {"diners": [A, B, C], "place": "House_1"})
	GameSession._record("battle", {"order": "order:2", "zone": ZONE, "team": [C, B], "result": "victory", "moments": [], "rescued": [B], "rescuers": [C]})
	var hub: Node3D = _hub()
	hub._open(&"Forge")
	_select(hub, "Ada")
	await _dreams_read(hub)
	var label: Label = hub.get_node("%HeroDetail") as Label
	assert_string_contains(label.text, "Dream: welcome Bea home.
  [x] Bea was carried home from %s.
  [ ] Eat with Bea again (0/3)." % Ledger.zone_name(ZONE))
	var reads: int = hub.dream_reads
	var resumes: int = hub.dream_resumes
	var tick: Array[Dictionary] = [GameSession._record("meal", {"diners": [A, B, C], "place": "House_1"})]
	watch_signals(GameSession)
	GameSession._notify_social_recorded(tick) # a meal is no roster change: the notice alone redraws the panel
	assert_signal_not_emitted(GameSession, "roster_changed")
	assert_string_contains(label.text, "  [ ] Eat with Bea again (1/3).")
	assert_eq([hub.dream_reads, hub.dream_resumes], [reads, resumes + 1], "the refresh resumed and read nothing in full")


## ig-7sn.24: pick is bond_from's choice by the one order (points, then the later fact, then the lower id) over candidates
## that are already the living ones at the threshold; it hands back the candidate itself and {} for none.
func test_pick_takes_the_points_then_the_later_fact_then_the_lower_id() -> void:
	assert_eq(Bonds.pick({}), {}, "no candidates, no pick")
	var one: Dictionary = {"partner": "hero:b", "points": 9, "last_seq": 4}
	var two: Dictionary = {"partner": "hero:c", "points": 9, "last_seq": 6}
	var three: Dictionary = {"partner": "hero:d", "points": 8, "last_seq": 9}
	var candidates: Dictionary = {"hero:d": three, "hero:c": two, "hero:b": one}
	assert_eq(Bonds.pick(candidates)["partner"], "hero:c", "more points, then the later fact")
	two["last_seq"] = 4
	assert_eq(Bonds.pick(candidates)["partner"], "hero:b", "the same points and fact: the lower id")
	one["points"] = 8
	assert_eq(Bonds.pick(candidates)["partner"], "hero:c", "a tally with fewer points is behind")
	assert_true(is_same(Bonds.pick(candidates), two), "the candidate itself, not a copy")


## ig-7sn.24 ACC 7: the hub keeps each hero's partner beside its candidates and reads that, not the tallies again, after
## a meal time. One meal time at the real cap, two tables, the two oldest records (Cal and Dov's meals) evicted in the
## same roll: a meal's +1 lifts Ada and Bea to the threshold (a new bond, said); a meal's +1 ties Eve's partner Fay on
## points and wins on last_seq (Fay's id is the lower, so only the fact's seq decides it); the eviction drops Cal and Dov
## under the threshold (a bond that ends says nothing). The look is a full look's: candidates, kept partners, signs, notice.
func test_a_meal_time_at_the_cap_that_makes_a_bond_wins_a_tie_and_ends_one_is_a_full_look() -> void:
	var names: Dictionary = {A: "Ada", B: "Bea", C: "Cal", D: "Dov", E: "Eve", F: "Fay", G: "Gus"}
	for id: String in names:
		_hero(id, names[id])
	var earlier: Array[Array] = [[[C, D], 8], [[A, B], 7], [[E, F], 8], [[E, G], 7]]
	var seq: int = 0
	for entry: Array in earlier:
		for _count: int in entry[1]:
			seq += 1
			Ledger.append(GameSession.ledger, seq, 0, "meal", {"diners": entry[0], "place": "House_1"})
	while GameSession.ledger.size() < BALANCE.ledger_max_records:
		seq += 1
		Ledger.append(GameSession.ledger, seq, 0, "summoned", {"hero": "filler:%d" % seq, "name": "F", "rank": 0})
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1
	var hub: Node3D = _hub()
	var living: Dictionary = hub._roster_names()
	var signs: Dictionary = hub._partner_signs(living)
	assert_eq([signs[A], signs[C], signs[D], signs[E], signs[F], signs[G]], ["", "♥ Dov", "♥ Cal", "♥ Fay", "♥ Eve", ""], "the bonds before the meal time")
	var builds: int = GameSession.bond_builds
	var reads: int = hub.dream_reads
	var before: Dictionary = hub._bond_candidates.duplicate(true)
	var status: Label = hub.get_node("%Status") as Label
	status.text = ""
	var records: Array[Dictionary] = []
	records.append(GameSession._record("meal", {"diners": [A, B], "place": "House_1"}))
	records.append(GameSession._record("meal", {"diners": [E, G], "place": "House_1"}))
	assert_eq(GameSession.ledger.size(), BALANCE.ledger_max_records, "still at the cap")
	assert_eq(int(GameSession.ledger[0]["seq"]), 3, "Cal and Dov's two oldest meals went in the roll")
	var pairs: Dictionary = GameSession.bond_index()
	assert_eq(pairs[A][B]["points"], BALANCE.bond_threshold, "a meal's +1 lifts Ada and Bea to the threshold")
	assert_eq([pairs[E][G]["points"], pairs[E][F]["points"]], [BALANCE.bond_threshold, BALANCE.bond_threshold], "Gus ties Fay for Eve on points")
	assert_gt(pairs[E][G]["last_seq"], pairs[E][F]["last_seq"], "and his fact is the later")
	assert_true(F < G, "so the ids alone would have kept Fay")
	assert_lt(pairs[C][D]["points"], BALANCE.bond_threshold, "the eviction took Cal and Dov under it")
	GameSession._notify_social_recorded(records)
	assert_eq(status.text, "Ada and Bea grew close. (+1 more)", "the two new bonds, the ended one unsaid")
	assert_eq([hub._bond_partners[A], hub._bond_partners[E], hub._bond_partners[F], hub._bond_partners[G]], [B, G, E, E], "Eve's partner is Gus now, Fay's still Eve")
	assert_eq([hub._bond_partners[C], hub._bond_partners[D]], ["", ""], "Cal and Dov have no partner")
	signs = hub._partner_signs(living)
	assert_eq([signs[A], signs[C], signs[E], signs[F], signs[G]], ["♥ Bea", "", "♥ Gus", "♥ Eve", "♥ Eve"])
	_assert_look_is_exact(hub, before, "a meal time at the cap")
	assert_eq(GameSession.bond_builds, builds, "no rebuild")
	assert_eq(hub.dream_reads, reads, "and no dream read")


func test_the_detail_panel_reads_a_dream_once_and_resumes_it_on_a_ledger_change() -> void:
	_hero(A, "Ada")
	_hero(B, "Bea")
	for _index: int in 2:
		_battle_in(GameSession.ledger, [A, B], "victory", {"moments": [_moment("revived", A, B)]})
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1
	var hub: Node3D = _hub()
	hub._open(&"Forge")
	var reads: int = hub.dream_reads
	_select(hub, "Ada")
	assert_eq(hub.dream_reads, reads, "picking Ada read no dream in full")
	await _dreams_read(hub)
	assert_eq(hub.dream_reads, reads + 1, "the frame after read it once")
	var resumes: int = hub.dream_resumes
	hub._refresh_hero_detail()
	hub._refresh_hero_detail()
	assert_eq([hub.dream_reads, hub.dream_resumes], [reads + 1, resumes], "no ledger change: the kept dream")
	GameSession._record("battle", {"order": "order:new", "zone": ZONE, "team": [A, B], "result": "retreated", "moments": []})
	hub._refresh_hero_detail()
	hub._refresh_hero_detail()
	assert_eq([hub.dream_reads, hub.dream_resumes], [reads + 1, resumes + 1], "an append: the kept dream resumes once, no read in full (ig-7sn.21)")
	assert_string_contains((hub.get_node("%HeroDetail") as Label).text, "Fight beside Bea again (2/3).")


func test_the_detail_panel_names_a_fallen_hero_from_its_died_record() -> void:
	_hero(A, "Ada")
	_hero(B, "Bea")
	_battle_in(GameSession.ledger, [A, B, C], "stranded", {"order": "order:x"})
	Ledger.append(GameSession.ledger, GameSession.ledger.size() + 1, 0, "died", {"hero": C, "name": "Cal", "cause": "expedition", "zone": ZONE, "battle_order": "order:x"})
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1
	var hub: Node3D = _hub()
	hub._open(&"Forge")
	_select(hub, "Ada")
	await _dreams_read(hub)
	var text: String = (hub.get_node("%HeroDetail") as Label).text
	var zone: String = Ledger.zone_name(ZONE)
	for line: String in ["Dream: carry Cal's name.", "  [x] Ada saw Cal fall at %s." % zone, "  [ ] Win at %s (0/3)." % zone]:
		assert_string_contains(text, line)
	assert_false(text.contains("a hero now forgotten"), "Cal is not on the roster, but his died record has his name")


## ---- ig-m6o.2.2.2: the partner greets from the line bank

func test_three_approaches_in_a_row_show_three_different_lines() -> void:
	var town: TownView = _bonded_town()
	var bea: TownWalker = town.partner
	bea.linger_at(town.free_point(Vector3(-12.0, 0.0, 12.0)), &"Idle_B", NAN, 1.0e6)
	var said: Array[String] = []
	for _approach: int in 3:
		said.append(_approach_once(town, bea))
	assert_eq(bea.greetings, 3)
	assert_eq(said[0], Lines.line(bea.facts, 0), "the first approach: the pair's first pick")
	assert_ne(said[0], said[1])
	assert_ne(said[1], said[2])
	assert_ne(said[0], said[2])


func test_a_walker_that_stops_being_the_partner_starts_its_lines_over() -> void:
	_hero(C, "Cal")
	var town: TownView = _bonded_town()
	var bea: TownWalker = town.partner
	var facts: Dictionary = bea.facts
	bea.linger_at(town.free_point(Vector3(-12.0, 0.0, 12.0)), &"Idle_B", NAN, 1.0e6)
	var first: String = _approach_once(town, bea)
	var second: String = _approach_once(town, bea)
	assert_eq(second, Lines.line(facts, 1))
	town.show_partner(GameSession.hero_by_id(C), {"kinds": ["hard"], "slots": {"name": "Ada", "place": "Here", "count": "Two"}, "start": 0})
	assert_eq(bea.facts, {}, "no longer the partner: nothing to say")
	assert_eq(town.walkers[C].facts["start"], 0, "Cal has the facts now")
	town.show_partner(GameSession.hero_by_id(B), facts)
	assert_eq(_approach_once(town, bea), first, "the partner again: its lines start over")


func test_the_hub_gives_the_partner_its_debt_lines() -> void:
	var town: TownView = _bonded_town(false, 4)
	assert_true(GameSession.embody_hero(B), "Bea is the body; Ada, whom she saved four times, is the partner")
	assert_eq(town.partner.hero_id, A)
	await _dreams_read(town.owner)
	var facts: Dictionary = town.partner.facts
	assert_eq(facts["kinds"].size(), 3)
	assert_eq([facts["kinds"][0], facts["kinds"][1]], ["saved", "debt"], "Ada's open dream owes Bea")
	assert_eq(facts["kinds"][2], "quirk:%s" % GameSession.hero_by_id(A).quirks[0], "and Ada's own quirk, last")
	assert_eq(facts["slots"]["name"], "Bea")
	assert_eq(Lines.candidates(facts).size(), 13, "5 + 5 + 3")


## ---- ig-7sn.16: the settle's readers, exact after the speed-ups

## ACC 3: the dream that skips battles without the hero equals the one that read every record (skip
## false), for every hero of the perf seed's ledger, and at every 50th record of seeded ledgers the
## game could write (a moment's hero and by are in the team, a death has its cause, zone and by),
## which open, end and count every dream of the catalogue (ig-m6o.2.2.7).
func test_the_dream_that_skips_equals_the_dream_that_read_every_record() -> void:
	var heroes: Array[String] = []
	for index: int in 100:
		heroes.append("perf:%d" % index)
	var seeded: Array[Dictionary] = _perf_ledger(heroes)
	for hero_id: String in heroes:
		if Bonds.dream(seeded, hero_id) != Bonds.dream(seeded, hero_id, null, false):
			fail_test("the perf seed's %s" % hero_id)
			return
	var eight: Array[String] = heroes.slice(0, 8)
	var states: Dictionary = {}
	for seed_value: int in [1, 2, 3]:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var ledger: Array[Dictionary] = []
		for seq: int in range(1, 801):
			var made: Array = _random_record(rng, eight, seq, true, true)
			Ledger.append(ledger, seq, 0, made[0], made[1])
			if seq % 50 == 0:
				for hero_id: String in eight:
					var dream: Dictionary = Bonds.dream(ledger, hero_id)
					if dream != Bonds.dream(ledger, hero_id, null, false):
						fail_test("seed %d, %s at seq %d" % [seed_value, hero_id, seq])
						return
					states["%s:%s" % [dream.get("dream", "none"), dream.get("state", "none")]] = true
	# fight_beside:open is not among them: a random ledger of eight heroes puts a pair in a fight together before its fourth chat.
	for opened: String in ["life_debt:open", "watch_over:open", "carry_name:open", "be_worthy:open", "welcome_home:open"]:
		assert_has(states, opened, "every dream compared: %s" % [states.keys()])
	assert_gte(states.keys().filter(func(state: String) -> bool: return not state.ends_with(":open") and not state.begins_with("none")).size(), 3, "and some ended: %s" % [states.keys()])


## ACC 4: History read from the newest end equals the full read, for every hero of the perf seed's
## ledger and of seeded ledgers with summons, rank-ups, deaths and rescues; a hero with few records
## still says it arrived before them, and a run of routine wins crossing the tenth line still counts on.
func test_history_from_the_newest_end_equals_the_full_read() -> void:
	var heroes: Array[String] = []
	var names: Dictionary = {}
	for index: int in 100:
		heroes.append("perf:%d" % index)
		names[heroes.back()] = "Perf %d" % index
	var seeded: Array[Dictionary] = _perf_ledger(heroes)
	for hero_id: String in heroes:
		if Ledger.history_lines(seeded, hero_id, names, BALANCE.rank_names, 10) != _history_before(seeded, hero_id, names, BALANCE.rank_names, 10):
			fail_test("the perf seed's %s" % hero_id)
			return
	var eight: Array[String] = heroes.slice(0, 8)
	for seed_value: int in [1, 2]:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var ledger: Array[Dictionary] = []
		for seq: int in range(1, 601):
			var made: Array = _random_record(rng, eight, seq)
			Ledger.append(ledger, seq, 0, made[0], made[1])
			if seq % 50 == 0:
				for hero_id: String in eight:
					for max_lines: int in [1, 3, 10]:
						if Ledger.history_lines(ledger, hero_id, names, BALANCE.rank_names, max_lines) != _history_before(ledger, hero_id, names, BALANCE.rank_names, max_lines):
							fail_test("seed %d, %s at seq %d, %d lines" % [seed_value, hero_id, seq, max_lines])
							return
	var few: Array[Dictionary] = []
	for index: int in 3:
		_battle_in(few, [A, B], "retreated")
	assert_eq(Ledger.history_lines(few, A, NAMES, BALANCE.rank_names, 10).back(), "Arrived before the records begin.")
	assert_eq(Ledger.history_lines(few, A, NAMES, BALANCE.rank_names, 10), _history_before(few, A, NAMES, BALANCE.rank_names, 10))
	var run: Array[Dictionary] = []
	for index: int in 6:
		_battle_in(run, [A, B], "victory")
	for index: int in 9:
		_battle_in(run, [A, B], "retreated")
	var lines: Array[String] = Ledger.history_lines(run, A, NAMES, BALANCE.rank_names, 10)
	assert_eq(lines.back(), "Won 6 battles at %s." % Ledger.zone_name(ZONE), "the tenth line keeps counting")
	assert_eq(lines, _history_before(run, A, NAMES, BALANCE.rank_names, 10))


## Fix A, the index: a fold stamps every hero whose pairs it changed with a new version, and a fold
## that changes none (a routine win) stamps no one.
func test_a_fold_stamps_every_hero_whose_pairs_it_changes() -> void:
	var heroes: Array[String] = []
	for index: int in 8:
		heroes.append("hero:%d" % index)
	var quiet: int = 0
	for seed_value: int in [1, 2, 3]:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var ledger: Array[Dictionary] = []
		var tiers: Array[int] = []
		var folded: Dictionary = Bonds.index_state(ledger, BALANCE)
		for seq: int in range(1, 401):
			var made: Array = _random_record(rng, heroes, seq)
			Ledger.append(ledger, seq, 0, made[0], made[1])
			tiers.append(Ledger.tier(ledger.back()))
			var before: Dictionary = (folded["pairs"] as Dictionary).duplicate(true)
			var version: int = folded["version"]
			Bonds.fold_in(folded, ledger.back(), BALANCE)
			quiet += 1 if folded["version"] == version else 0
			if not _stamped_all_changes(folded, before, version):
				fail_test("seed %d: appending seq %d" % [seed_value, seq])
				return
			for record: Dictionary in Ledger.evict(ledger, tiers, 20):
				before = (folded["pairs"] as Dictionary).duplicate(true)
				version = folded["version"]
				if not Bonds.fold_out(folded, record, BALANCE):
					folded = Bonds.index_state(ledger, BALANCE)
				elif not _stamped_all_changes(folded, before, version):
					fail_test("seed %d: evicting after seq %d" % [seed_value, seq])
					return
	var routine: Dictionary = Bonds.index_state(_ledger, BALANCE)
	_battle([A, B], "victory")
	Bonds.fold_in(routine, _ledger.back(), BALANCE)
	assert_eq([routine["version"], routine["touched"]], [0, {}], "a routine win stamps no one")
	assert_gt(quiet, 0, "some folds changed no pairs")


## Fix A, the hub: a look that reads only the touched heroes says, keeps and signs what a full look
## would, after every record of a seeded run that reaches the cap halfway (then each record evicts the
## oldest battle, which folds out), through a rename and a summon (which read every hero). A cap
## that bites sooner would evict every battle before any pair grew close.
func test_the_hubs_look_at_the_touched_heroes_equals_a_full_look() -> void:
	_fill_to_cap(150)
	var heroes: Array[String] = []
	for index: int in 8:
		heroes.append(_hero("hero:%d" % index, "H%d" % index).instance_id)
	var hub: Node3D = _hub()
	var status: Label = hub.get_node("%Status") as Label
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var looks: Dictionary = {"full": 0, "quiet": 0, "partial": 0, "said": 0}
	for seq: int in range(1, 301):
		if seq == 100:
			GameSession.hero_by_id(heroes[0]).hero_name = "Renamed"
		if seq == 200:
			heroes.append(_hero("hero:new", "New").instance_id)
		var made: Array = _random_record(rng, heroes, seq)
		GameSession._record(made[0], made[1])
		var before: Dictionary = hub._bond_candidates.duplicate()
		var version: int = hub._bonds_version
		# The look reads only the touched heroes when the index and the names are the last look's.
		var partial: bool = is_same(GameSession.bond_index(), hub._bonds_pairs) and hub._roster_names() == hub._bonds_living
		status.text = ""
		var living: Dictionary = hub._roster_names()
		var signs: Dictionary = hub._partner_signs(living).duplicate()
		var told: String = status.text
		var pairs: Dictionary = GameSession.bond_index()
		var touched: int = (GameSession.bond_changes()["touched"] as Dictionary).values().filter(func(stamp: int) -> bool: return stamp > version).size()
		if not partial:
			looks["full"] += 1
		elif touched == 0:
			looks["quiet"] += 1
		else:
			looks["partial"] += 1
		looks["said"] += 0 if told.is_empty() else 1
		status.text = ""
		hub._say_new_bonds(before, pairs, living)
		var full_signs: Dictionary = {}
		for id: String in living:
			full_signs[id] = hub._partner_sign(id, living)
		if told != status.text or hub._bond_candidates != hub._living_candidates(pairs, living) or signs != full_signs:
			fail_test("record %d (%s): said %s, a full look says %s" % [seq, made[0], told, status.text])
			return
		if hub._bond_partners != _full_partners(pairs, living):
			fail_test("record %d (%s): the kept partners %s are not a full read's" % [seq, made[0], hub._bond_partners])
			return
	gut.p("HUB LOOKS: %s" % looks)
	assert_true(looks["quiet"] > 0 and looks["partial"] > 0 and looks["said"] > 0, "quiet looks, looks at a few heroes, and news: %s" % looks)
	assert_eq(GameSession.ledger.size(), BALANCE.ledger_max_records, "the second half evicted")


## ---- ig-7sn.21: the kept dreams and names

## ACC 3, the marks: folding out a battle marks its team, rescued and rescuers and no one else, a chat its two and a
## meal its diners (OUT_MARKS); any other kind, and a battle that rescued someone, marks everyone (it can change any hero's
## dream). They are stamped even when the fold refuses the take-out, because a refusal rebuilds the index and starts them over.
func test_folding_out_marks_the_heroes_a_record_names_and_everyone_for_any_other_kind_or_a_rescue() -> void:
	_battle([A, B], "victory", {"rescuers": [D]})
	_battle([E], "victory")
	_record("ranked_up", {"hero": A, "from": 0, "to": 1})
	_record("died", {"hero": B, "name": "Bea"})
	_record("summoned", {"hero": F, "name": "Fay", "rank": 0})
	_meal([A, B])
	_battle([A, B], "victory", {"rescued": [C], "rescuers": [D]})
	var folded: Dictionary = Bonds.index_state(_ledger, BALANCE)
	assert_eq([folded["outs"], folded["out_named"], folded["out_all"]], [0, {}, 0], "a build starts them over")
	Bonds.fold_out(folded, _ledger[0], BALANCE)
	assert_eq([folded["outs"], folded["out_named"], folded["out_all"]], [1, {A: 1, B: 1, D: 1}, 0], "a battle marks its team and rescuers")
	Bonds.fold_out(folded, _ledger[1], BALANCE)
	assert_eq([folded["outs"], folded["out_named"], folded["out_all"]], [2, {A: 1, B: 1, D: 1, E: 2}, 0], "a routine win marks its team")
	for at: int in range(2, 5):
		Bonds.fold_out(folded, _ledger[at], BALANCE)
		assert_eq([folded["outs"], folded["out_all"]], [at + 1, at + 1], "a %s record marks everyone" % _ledger[at]["kind"])
	assert_eq((folded["out_named"] as Dictionary).size(), 4, "and no one in particular")
	Bonds.fold_out(folded, _ledger[5], BALANCE)
	assert_eq([folded["outs"], folded["out_all"], folded["out_named"]], [6, 5, {A: 6, B: 6, D: 1, E: 2}], "a meal marks its diners")
	Bonds.fold_out(folded, _ledger[6], BALANCE)
	assert_eq([folded["outs"], folded["out_all"]], [7, 7], "a battle that rescued someone marks everyone (welcome_home reads it)")


## Ledger.first_after: the index of the first record past a seq, through gaps the evictions leave.
func test_first_after_finds_the_first_record_past_a_seq() -> void:
	var ledger: Array[Dictionary] = []
	assert_eq([Ledger.first_after(ledger, 0), Ledger.first_after(ledger, 5)], [0, 0], "an empty list")
	for seq: int in [2, 3, 7, 8]:
		Ledger.append(ledger, seq, 0, "summoned", {"hero": A, "name": "Ada", "rank": 0})
	assert_eq([-5, 0, 1, 2, 3, 5, 7, 8, 9].map(func(seq: int) -> int: return Ledger.first_after(ledger, seq)), [0, 0, 0, 1, 2, 2, 3, 4, 4])


## ACC 3: a dream_fold resumed after the records appended since equals the dream read in full (skip
## false): for every hero of the perf seed's ledger split at its 9,000th record, and for twelve heroes of
## seeded ledgers kept through appends and evictions under a cap of 300, every 5th record, a hero
## resuming unless an eviction marked it (out_named, or out_all) since it was read, as the hub tells.
func test_a_resumed_dream_equals_the_dream_read_in_full() -> void:
	var heroes: Array[String] = []
	for index: int in 100:
		heroes.append("perf:%d" % index)
	var seeded: Array[Dictionary] = _perf_ledger(heroes)
	var prefix: Array[Dictionary] = seeded.slice(0, 9000)
	for hero_id: String in heroes:
		var resumed: Dictionary = Bonds.dream_fold(seeded, hero_id, Bonds.dream_fold(prefix, hero_id))
		if Bonds.dream_of(resumed) != Bonds.dream(seeded, hero_id, null, false):
			fail_test("the perf seed's %s" % hero_id)
			return
	var twelve: Array[String] = heroes.slice(0, 12)
	var counts: Dictionary = {"full": 0, "resumed": 0}
	var states: Dictionary = {}
	for seed_value: int in [1, 2, 3]:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var ledger: Array[Dictionary] = []
		var tiers: Array[int] = []
		var folded: Dictionary = Bonds.index_state(ledger, BALANCE)
		var kept: Dictionary = {}
		var read_at: Dictionary = {}
		for seq: int in range(1, 601):
			var made: Array = _random_record(rng, twelve, seq, true, true)
			Ledger.append(ledger, seq, 0, made[0], made[1])
			tiers.append(Ledger.tier(ledger.back()))
			Bonds.fold_in(folded, ledger.back(), BALANCE)
			for record: Dictionary in Ledger.evict(ledger, tiers, 300):
				if not Bonds.fold_out(folded, record, BALANCE):
					folded = Bonds.index_state(ledger, BALANCE)
					kept = {}
					read_at = {}
			if seq % 5 != 0:
				continue
			for hero_id: String in twelve:
				var seen: int = int(read_at.get(hero_id, -1))
				var resumes: bool = kept.has(hero_id) and int(folded["out_all"]) <= seen and int((folded["out_named"] as Dictionary).get(hero_id, 0)) <= seen
				if not resumes:
					read_at[hero_id] = int(folded["outs"])
				counts["resumed" if resumes else "full"] += 1
				kept[hero_id] = Bonds.dream_fold(ledger, hero_id, kept[hero_id] if resumes else {})
				var dream: Dictionary = Bonds.dream_of(kept[hero_id])
				if dream != Bonds.dream(ledger, hero_id, null, false):
					fail_test("seed %d, %s at seq %d (resumed: %s)" % [seed_value, hero_id, seq, resumes])
					return
				states["%s:%s" % [dream.get("dream", "none"), dream.get("state", "none")]] = true
	gut.p("KEPT DREAMS: %s; %s" % [counts, states.keys()])
	assert_gt(counts["resumed"], 100, "many resumed")
	assert_gt(counts["full"], 100, "many read again in full")
	for reached: String in ["welcome_home:open", "welcome_home:fulfilled", "welcome_home:lost"]:
		assert_has(states, reached, "meals and chats reach welcome_home, and the kept read equals a full one: %s" % [states.keys()])
	assert_gte(states.keys().filter(func(state: String) -> bool: return not state.ends_with(":open") and not state.begins_with("none")).size(), 3, "and some ended: %s" % [states.keys()])


## ACC 3, through the hub: after appends the shown hero's dream resumes, and an eviction that names a hero
## in a battle's team, rescued or rescuers reads its dream in full once; a hero it does not name resumes.
## Every answer equals a full read.
func test_an_eviction_that_names_the_hero_reads_its_dream_in_full_once() -> void:
	_fill_to_cap(6)
	_hero(A, "Ada")
	_hero(B, "Bea")
	_battle_in(GameSession.ledger, [A, B], "victory", {"moments": [_moment("revived", A, B)]})
	_battle_in(GameSession.ledger, [A, B], "victory")
	_battle_in(GameSession.ledger, [C, D], "victory")
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1
	var hub: Node3D = _hub()
	for hero_id: String in [A, B, C, D]:
		assert_eq(hub._dream(hero_id), Bonds.dream(GameSession.ledger, hero_id), "read in full: %s" % hero_id)
	assert_eq(hub._dream(A)["dream"], "life_debt")
	var reads: int = hub.dream_reads
	var resumes: int = hub.dream_resumes
	for step: int in 3:
		GameSession._record("battle", {"order": "order:new%d" % step, "zone": ZONE, "team": [A, B], "result": "retreated", "moments": []})
		assert_eq(hub._dream(A), Bonds.dream(GameSession.ledger, A), "append %d" % step)
		assert_eq(hub._dream(C), Bonds.dream(GameSession.ledger, C), "append %d, one it does not name" % step)
	assert_eq([hub.dream_reads, hub.dream_resumes], [reads, resumes + 6], "under the cap: every look after an append resumes")
	assert_eq(GameSession.ledger.size(), BALANCE.ledger_max_records)
	var evicted_seq: int = BALANCE.ledger_max_records - 4
	assert_true(GameSession.ledger.any(func(record: Dictionary) -> bool: return record["seq"] == evicted_seq), "the routine win that names Ada and Bea is in")
	GameSession._record("battle", {"order": "order:new3", "zone": ZONE, "team": [A, B], "result": "retreated", "moments": []})
	assert_eq(GameSession.ledger.size(), BALANCE.ledger_max_records, "the fourth append evicted the oldest routine win")
	assert_false(GameSession.ledger.any(func(record: Dictionary) -> bool: return record["seq"] == evicted_seq), "the win that named Ada and Bea")
	reads = hub.dream_reads
	resumes = hub.dream_resumes
	assert_eq(hub._dream(A), Bonds.dream(GameSession.ledger, A))
	assert_eq(hub._dream(B), Bonds.dream(GameSession.ledger, B))
	assert_eq([hub.dream_reads, hub.dream_resumes], [reads + 2, resumes], "the named heroes read in full")
	assert_eq(hub._dream(C), Bonds.dream(GameSession.ledger, C))
	assert_eq([hub.dream_reads, hub.dream_resumes], [reads + 2, resumes + 1], "the hero it does not name resumes")
	assert_eq(hub._dream(A), Bonds.dream(GameSession.ledger, A))
	assert_eq(hub._dream(B), Bonds.dream(GameSession.ledger, B))
	assert_eq([hub.dream_reads, hub.dream_resumes], [reads + 2, resumes + 1], "once: no read after it")


## ACC 3: a load (a new array) and a rollback that dropped an append each read the dream in full; the
## append after them resumes; a death of the owed hero appended later resumes to "lost".
func test_a_load_and_a_rollback_that_dropped_an_append_each_read_the_dream_in_full() -> void:
	_hero(A, "Ada")
	_hero(B, "Bea")
	for _index: int in 2:
		_battle_in(GameSession.ledger, [A, B], "victory", {"moments": [_moment("revived", A, B)]})
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1
	var hub: Node3D = _hub()
	assert_eq(hub._dream(A)["state"], "open")
	var reads: int = hub.dream_reads
	var resumes: int = hub.dream_resumes
	var data: Dictionary = GameSession.to_dict()
	data["ledger"] = GameSession.ledger.duplicate(true)
	GameSession.from_dict(data)
	assert_eq(hub._dream(A), Bonds.dream(GameSession.ledger, A))
	assert_eq([hub.dream_reads, hub.dream_resumes], [reads + 1, resumes], "a load reads in full")
	var dropped := func() -> bool:
		GameSession._record("battle", {"order": "order:dropped", "zone": ZONE, "team": [A, B], "result": "retreated", "moments": []})
		return false
	assert_false(GameSession._commit_profile_mutation(dropped))
	assert_eq(hub._dream(A), Bonds.dream(GameSession.ledger, A))
	assert_eq([hub.dream_reads, hub.dream_resumes], [reads + 2, resumes], "a rollback that dropped an append reads in full")
	GameSession._record("battle", {"order": "order:kept", "zone": ZONE, "team": [A, B], "result": "retreated", "moments": []})
	assert_eq(hub._dream(A), Bonds.dream(GameSession.ledger, A))
	assert_eq([hub.dream_reads, hub.dream_resumes], [reads + 2, resumes + 1], "the append after it resumes")
	assert_eq(hub._dream(B), Bonds.dream(GameSession.ledger, B))
	assert_true(hub._dreams.has(B), "Bea's dream is kept while she is on the roster")
	GameSession.kill_hero(GameSession.hero_by_id(B), StringName(ZONE), BALANCE)
	assert_eq(hub._dream(A)["state"], "lost", "the owed hero's death")
	assert_eq(hub._dream(A), Bonds.dream(GameSession.ledger, A))
	assert_eq([hub.dream_reads, hub.dream_resumes], [reads + 3, resumes + 2], "a death appended resumes")
	assert_false(hub._dreams.has(B), "a hero that left the roster keeps no dream")
	assert_true(hub._dreams.has(A))


## ACC 3 (the names): the hub's kept known names equal Ledger.known_names after appends, after an
## eviction of a summoned record, after an eviction of a died record (the oldest filler goes, and its
## name with it) and after a load. Appends fold into the kept names; an eviction of another kind than a
## battle, or a load, reads them again in full.
func test_the_kept_names_equal_known_names_when_a_summoned_record_is_evicted() -> void:
	_assert_kept_names_through("summoned")


func test_the_kept_names_equal_known_names_when_a_died_record_is_evicted() -> void:
	_assert_kept_names_through("died")


## Sol's case: a load accepts a battle record that carries a name, and Ledger.known_names reads every
## record that has one, so evicting that battle takes its name out (the kept names read again in full).
func test_the_kept_names_equal_known_names_when_a_battle_that_carries_a_name_is_evicted() -> void:
	_fill_to_cap(1)
	_battle_in(GameSession.ledger, [A, B], "victory", {"hero": "gone", "name": "Mara"})
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1
	var hub: Node3D = _hub()
	var living: Dictionary = hub._roster_names()
	assert_eq(hub._known_names(living), Ledger.known_names(GameSession.ledger, living), "at entry")
	assert_eq(hub._known_names(living)["gone"], "Mara")
	GameSession._record("summoned", {"hero": "new", "name": "New", "rank": 0})
	assert_false(GameSession.ledger.any(func(record: Dictionary) -> bool: return record["kind"] == "battle"), "the routine battle was evicted")
	assert_eq(hub._known_names(living), Ledger.known_names(GameSession.ledger, living), "after the eviction")
	assert_false(hub._known_names(living).has("gone"), "its name went")


## ACC 3 (the names): History given the kept names equals History that reads them, for every hero of the
## perf seed and of seeded ledgers with summons and deaths, the kept names resumed record by record.
func test_history_lines_with_the_kept_names_equal_those_without() -> void:
	var heroes: Array[String] = []
	var names: Dictionary = {}
	for index: int in 100:
		heroes.append("perf:%d" % index)
		names[heroes.back()] = "Perf %d" % index
	var seeded: Array[Dictionary] = _perf_ledger(heroes)
	var known: Dictionary = Ledger.known_names(seeded, names)
	for hero_id: String in heroes:
		if Ledger.history_lines(seeded, hero_id, names, BALANCE.rank_names, 10, known) != Ledger.history_lines(seeded, hero_id, names, BALANCE.rank_names, 10):
			fail_test("the perf seed's %s" % hero_id)
			return
	var eight: Array[String] = heroes.slice(0, 8)
	for seed_value: int in [1, 2]:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var ledger: Array[Dictionary] = []
		var kept: Dictionary = {}
		for seq: int in range(1, 601):
			var made: Array = _random_record(rng, eight, seq)
			Ledger.append(ledger, seq, 0, made[0], made[1])
			kept = Ledger.record_names(ledger, kept)
			if seq % 50 != 0:
				continue
			known = (kept["names"] as Dictionary).duplicate()
			known.merge(names, true)
			assert_eq(known, Ledger.known_names(ledger, names), "seed %d: the kept names at seq %d" % [seed_value, seq])
			for hero_id: String in eight:
				if Ledger.history_lines(ledger, hero_id, names, BALANCE.rank_names, 10, known) != Ledger.history_lines(ledger, hero_id, names, BALANCE.rank_names, 10):
					fail_test("seed %d, %s at seq %d" % [seed_value, hero_id, seq])
					return


## ACC 3: the hub's kept dreams and names equal a full read for every hero of a seeded run that reaches the
## cap halfway (each record then evicts one), through a load and a rollback that dropped three appends.
func test_the_hubs_kept_dreams_and_names_equal_a_full_read_through_evictions_a_load_and_a_rollback() -> void:
	_fill_to_cap(150)
	var heroes: Array[String] = []
	for index: int in 8:
		heroes.append(_hero("hero:%d" % index, "H%d" % index).instance_id)
	var hub: Node3D = _hub()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for step: int in range(1, 301):
		if step == 100:
			var data: Dictionary = GameSession.to_dict()
			data["ledger"] = GameSession.ledger.duplicate(true)
			GameSession.from_dict(data)
		if step == 200:
			var mutation := func() -> bool:
				for _index: int in 3:
					var dropped: Array = _random_record(rng, heroes, GameSession.ledger_next_seq, true, true)
					GameSession._record(dropped[0], dropped[1])
				return false
			assert_false(GameSession._commit_profile_mutation(mutation))
		var made: Array = _random_record(rng, heroes, GameSession.ledger_next_seq, true, true)
		GameSession._record(made[0], made[1])
		if step % 3 != 0:
			continue
		for hero_id: String in heroes:
			if hub._dream(hero_id) != Bonds.dream(GameSession.ledger, hero_id, null, false):
				fail_test("step %d (%s): %s's dream" % [step, made[0], hero_id])
				return
		var living: Dictionary = hub._roster_names()
		if hub._known_names(living) != Ledger.known_names(GameSession.ledger, living):
			fail_test("step %d (%s): the known names" % [step, made[0]])
			return
	gut.p("HUB DREAMS: %d read in full, %d resumed" % [hub.dream_reads, hub.dream_resumes])
	assert_gt(hub.dream_resumes, 100, "most looks resumed")
	assert_gt(hub.dream_reads, heroes.size() * 2, "some read in full (the load, the rollback, evictions)")
	assert_eq(GameSession.ledger.size(), BALANCE.ledger_max_records, "the second half evicted")


## ---- ig-bnq: the hub's look when only the roster's membership changed

## ACC 3: a summon, a sacrifice or an expedition death changes who is on the roster and nothing else. The hub's
## look then edits its memos in place (the candidates dictionary is the same one; a sentinel sign on a hero
## the change cannot touch survives) and the memos, the signs and the notice equal a full look's.
func test_a_summon_takes_the_hubs_look_in_place_and_equals_a_full_look() -> void:
	var hub: Node3D = _membership_hub()
	var kept: Dictionary = hub._bond_candidates
	hub._signs[D] = "SENTINEL"
	GameSession.stones = 1000
	var before: Dictionary = hub._bond_candidates.duplicate(true)
	assert_true(GameSession.summon_hero(_new_hero(F, "Fay"), BALANCE), GameSession.last_action_error)
	assert_true(is_same(hub._bond_candidates, kept), "the look edited the memos in place")
	assert_eq(hub._signs[D], "SENTINEL", "no one the summon cannot touch was re-signed")
	hub._signs.erase(D)
	_assert_look_is_exact(hub, before, "a summon")


func test_a_sacrifice_of_someones_partner_moves_that_sign_to_the_next_partner_and_equals_a_full_look() -> void:
	var hub: Node3D = _membership_hub()
	var kept: Dictionary = hub._bond_candidates
	assert_eq(hub._signs[A], "♥ Bea")
	var before: Dictionary = hub._bond_candidates.duplicate(true)
	assert_true(GameSession.sacrifice_hero(GameSession.hero_by_id(B), GameSession.hero_by_id(E), BALANCE))
	assert_true(is_same(hub._bond_candidates, kept), "the look edited the memos in place")
	assert_eq(hub._partner_signs(hub._roster_names())[A], "♥ Cal", "Bea is gone; Cal is Ada's next")
	assert_false(hub._signs.has(B) or hub._bond_candidates.has(B) or hub._dreams.has(B), "nothing of Bea is kept")
	_assert_look_is_exact(hub, before, "a sacrifice of a partner")


func test_a_sacrifice_of_a_second_best_partner_re_signs_no_one() -> void:
	var hub: Node3D = _membership_hub()
	var kept: Dictionary = hub._bond_candidates
	hub._signs[A] = "SENTINEL"
	var before: Dictionary = hub._bond_candidates.duplicate(true)
	assert_true(GameSession.sacrifice_hero(GameSession.hero_by_id(C), GameSession.hero_by_id(E), BALANCE))
	assert_true(is_same(hub._bond_candidates, kept), "the look edited the memos in place")
	assert_eq(hub._signs[A], "SENTINEL", "Bea is still Ada's closest, so her sign was not read again")
	assert_false((hub._bond_candidates[A] as Dictionary).has(C), "Cal is gone from Ada's candidates")
	hub._signs.erase(A)
	_assert_look_is_exact(hub, before, "a sacrifice of a second-best partner")


## Three battles that stranded Ada, Bea and Cal are only three hard battles: no bond. Cal's death, of the
## order that stranded them, is a death Ada and Bea saw together: they cross the threshold in the same look
## that drops Cal. The look reads the touched heroes (a death with tallies), not only who joined.
func test_an_expedition_death_that_touches_tallies_says_the_new_bond_and_equals_a_full_look() -> void:
	for pair: Array in [[A, "Ada"], [B, "Bea"], [C, "Cal"], [D, "Dov"]]:
		_hero(pair[0], pair[1])
	for _index: int in 3:
		_battle_in(GameSession.ledger, [A, B, C], "stranded", {"order": "o"})
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1
	var hub: Node3D = _hub()
	assert_eq(hub._partner_signs(hub._roster_names())[A], "", "three hard battles are no bond")
	var status: Label = hub.get_node("%Status") as Label
	status.text = ""
	var kept: Dictionary = hub._bond_candidates
	var before: Dictionary = hub._bond_candidates.duplicate(true)
	GameSession.kill_hero(GameSession.hero_by_id(C), StringName(ZONE), BALANCE, "expedition", "", "o")
	assert_eq(status.text, "Ada and Bea grew close.", "the death they saw together")
	assert_true(is_same(hub._bond_candidates, kept), "the look edited the memos in place")
	assert_false(hub._bond_candidates.has(C), "Cal is gone")
	assert_eq(hub._partner_signs(hub._roster_names())[A], "♥ Bea")
	_assert_look_is_exact(hub, before, "an expedition death that touches tallies")


## Ada, Bea, Cal and Dov saw three hard fights with Eve, who was stranded; Eve's death, of that order, is a
## death all four saw together: six pairs cross the threshold in the look that drops Eve. Ada and Bea are
## a mutual pair; Cal and Dov each grow close to Ada (the lowest id on a tie). Three news: the first, and
## "(+2 more)", as a full look over every hero says them.
func test_a_membership_look_with_several_new_bonds_says_the_first_and_how_many_more() -> void:
	for pair: Array in [[A, "Ada"], [B, "Bea"], [C, "Cal"], [D, "Dov"], [E, "Eve"]]:
		_hero(pair[0], pair[1])
	for _index: int in 3:
		_battle_in(GameSession.ledger, [A, B, C, D, E], "stranded", {"order": "o"})
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1
	var hub: Node3D = _hub()
	assert_eq(hub._partner_signs(hub._roster_names())[A], "", "three hard battles are no bond")
	var status: Label = hub.get_node("%Status") as Label
	status.text = ""
	var kept: Dictionary = hub._bond_candidates
	var before: Dictionary = hub._bond_candidates.duplicate(true)
	GameSession.kill_hero(GameSession.hero_by_id(E), StringName(ZONE), BALANCE, "expedition", "", "o")
	assert_true(is_same(hub._bond_candidates, kept), "the look edited the memos in place")
	assert_eq(status.text, "Ada and Bea grew close. (+2 more)")
	_assert_look_is_exact(hub, before, "an expedition death with several new bonds")


## A roster change with no record (add_hero: only tests do it) skips the look, which is keyed on the ledger.
## The next action that writes a record is a look against the older roster: it reads the hero that came
## in, says the delayed news and is exact.
func test_a_roster_change_with_no_record_is_caught_up_at_the_next_look() -> void:
	_hero(A, "Ada")
	_hero(D, "Dov")
	_saves_between(A, "hero:n", 2)
	var hub: Node3D = _hub()
	assert_eq(hub._partner_signs(hub._roster_names())[A], "", "Nia is not here yet")
	var status: Label = hub.get_node("%Status") as Label
	status.text = ""
	var kept: Dictionary = hub._bond_candidates
	var before: Dictionary = hub._bond_candidates.duplicate(true)
	GameSession.add_hero(_new_hero("hero:n", "Nia"))
	assert_eq(hub._bonds_living.size(), 2, "no record, no look")
	assert_eq(status.text, "", "nothing said yet")
	# ig-7sn.24: the signs asked for now are a full read of the new roster (the kept partners are the last look's, and
	# know no Nia), and the ask changes nothing the look keeps.
	var living_now: Dictionary = hub._roster_names()
	var partners_before: Dictionary = hub._bond_partners.duplicate()
	var between: Dictionary = hub._partner_signs(living_now).duplicate()
	var full_between: Dictionary = {}
	for id: String in living_now:
		full_between[id] = hub._partner_sign(id, living_now)
	assert_eq(between, full_between, "no record, no look: the signs are a full read of the roster")
	assert_eq(between[A], "♥ Nia", "and the kept partners did not answer it")
	assert_eq(hub._bonds_living.size(), 2, "still no look")
	assert_eq([hub._bond_partners, hub._bond_candidates], [partners_before, before], "the ask left the kept partners and candidates alone")
	GameSession.stones = 1000
	assert_true(GameSession.summon_hero(_new_hero(F, "Fay"), BALANCE), GameSession.last_action_error)
	assert_eq(hub._bonds_living.size(), 4, "the look saw both new heroes")
	assert_eq(status.text, "Ada grew close to Nia.", "the delayed news")
	assert_true(is_same(hub._bond_candidates, kept), "the look edited the memos in place")
	assert_eq(hub._partner_signs(hub._roster_names())[A], "♥ Nia")
	_assert_look_is_exact(hub, before, "a roster change with no record")


## A hero the ledger knows from before (a rollback's or a load's past) joins the roster: every hero with a
## tally toward it is read again, and the news is said in the look that adds it.
func test_a_hero_that_joins_with_tallies_says_the_bond_and_equals_a_full_look() -> void:
	_hero(A, "Ada")
	_hero(D, "Dov")
	_saves_between(A, "hero:n", 2)
	var hub: Node3D = _hub()
	assert_eq(hub._partner_signs(hub._roster_names())[A], "", "Nia is not here yet")
	var status: Label = hub.get_node("%Status") as Label
	status.text = ""
	var kept: Dictionary = hub._bond_candidates
	var before: Dictionary = hub._bond_candidates.duplicate(true)
	GameSession.stones = 1000
	assert_true(GameSession.summon_hero(_new_hero("hero:n", "Nia"), BALANCE), GameSession.last_action_error)
	assert_eq(status.text, "Ada grew close to Nia.")
	assert_true(is_same(hub._bond_candidates, kept), "the look edited the memos in place")
	assert_eq(hub._partner_signs(hub._roster_names())[A], "♥ Nia")
	_assert_look_is_exact(hub, before, "a hero that joins with tallies")


## A failed save takes an action back after the hub looked at the half-done roster: the hero is on the
## roster again and the memos are a full look's. (The rebuilt index takes the full look here.) The notice is
## measured from what the hub last saw, the half-done roster, so Ada and Bea "grow close" again, as they
## always did after a rollback.
func test_a_rollback_that_puts_a_hero_back_equals_a_full_look() -> void:
	var hub: Node3D = _membership_hub()
	var seen: Dictionary = {}
	var mutation := func() -> bool:
		GameSession.kill_hero(GameSession.hero_by_id(B), &"", BALANCE, "expedition", "", "")
		GameSession.roster_changed.emit()
		seen["candidates"] = hub._bond_candidates.duplicate(true)
		return false
	assert_false(GameSession._commit_profile_mutation(mutation))
	assert_not_null(GameSession.hero_by_id(B), "the rollback put Bea back")
	assert_eq(hub._partner_signs(hub._roster_names())[A], "♥ Bea")
	_assert_look_is_exact(hub, seen["candidates"], "a rollback")


## A kept hero that was renamed, and a load, are not a membership look: nothing keeps a name apart from the
## roster, so they take the full one.
func test_a_rename_with_a_membership_change_and_a_load_take_the_full_look() -> void:
	var hub: Node3D = _membership_hub()
	var kept: Dictionary = hub._bond_candidates
	var before: Dictionary = hub._bond_candidates.duplicate(true)
	GameSession.hero_by_id(B).hero_name = "Bee"
	GameSession.stones = 1000
	assert_true(GameSession.summon_hero(_new_hero(F, "Fay"), BALANCE), GameSession.last_action_error)
	assert_false(is_same(hub._bond_candidates, kept), "a rename takes the full look")
	assert_eq(hub._partner_signs(hub._roster_names())[A], "♥ Bee")
	_assert_look_is_exact(hub, before, "a rename with a summon")
	before = hub._bond_candidates.duplicate(true)
	var data: Dictionary = GameSession.to_dict()
	data["ledger"] = GameSession.ledger.duplicate(true)
	GameSession.from_dict(data)
	GameSession.roster_changed.emit()
	_assert_look_is_exact(hub, before, "a load")


## ---- helpers

## The perf seed's ledger (tests/perf/seed_perf.gd: its rng, 5-hero teams and mix) at the cap.
func _perf_ledger(heroes: Array[String]) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var ledger: Array[Dictionary] = []
	for index: int in BALANCE.ledger_max_records:
		var team: Array[String] = _team(rng, heroes, 5)
		_battle_in(ledger, team, "victory", _mix(rng, index, team))
	return ledger


## Whether every hero whose pairs differ from before carries a stamp past version.
func _stamped_all_changes(folded: Dictionary, before: Dictionary, version: int) -> bool:
	var pairs: Dictionary = folded["pairs"]
	for hero_id: String in _merged_keys(pairs, before):
		if pairs.get(hero_id, {}) != before.get(hero_id, {}) and int((folded["touched"] as Dictionary).get(hero_id, 0)) <= version:
			return false
	return true


func _merged_keys(one: Dictionary, other: Dictionary) -> Array:
	var keys: Dictionary = one.duplicate()
	keys.merge(other)
	return keys.keys()


## Ledger.history_lines before ig-7sn.16, gathering the hero's records first: the test's reference.
static func _history_before(ledger: Array[Dictionary], hero_id: String, names: Dictionary, rank_names: PackedStringArray, max_lines: int) -> Array[String]:
	var all_names: Dictionary = Ledger.known_names(ledger, names)
	var records: Array[Dictionary] = Ledger.records_for_hero(ledger, hero_id)
	var lines: Array[String] = []
	var routine_zone: String = ""
	var routine_count: int = 0
	var arrived: bool = false
	for index: int in range(records.size() - 1, -1, -1):
		var record: Dictionary = records[index]
		var kind: String = str(record.get("kind", ""))
		arrived = arrived or kind == "summoned"
		if Ledger.is_routine(record) and Ledger._array(record, "team").has(hero_id) and str(record.get("zone", "")) == routine_zone:
			routine_count += 1
			lines[lines.size() - 1] = "Won %d battles at %s." % [routine_count, Ledger.zone_name(routine_zone)]
			continue
		if lines.size() >= max_lines:
			break
		routine_zone = str(record.get("zone", "")) if Ledger.is_routine(record) and Ledger._array(record, "team").has(hero_id) else ""
		routine_count = 1
		lines.append(Ledger._line(record, hero_id, all_names, rank_names))
	if not arrived and lines.size() < max_lines:
		lines.append("Arrived before the records begin.")
	return lines

## Walks the body out past REARM_DISTANCE and back in to bea, one step each, and returns its line.
func _approach_once(town: TownView, bea: TownWalker) -> String:
	var greeted: int = bea.greetings
	town.body.global_position = town.to_global(bea.position + Vector3(0.0, 0.0, 8.0))
	bea.step(0.1)
	town.body.global_position = town.to_global(bea.position + Vector3(0.0, 0.0, 1.5))
	bea.step(0.1)
	assert_eq(bea.greetings, greeted + 1, "the approach greets")
	return (bea.get_node("Line") as Label3D).text


func _assert_same_answers(heroes: Array) -> void:
	var livings: Array[Dictionary] = [{}, {D: true}]
	var everyone: Dictionary = {}
	for id: String in heroes:
		everyone[id] = true
	livings.append(everyone)
	var some: Dictionary = everyone.duplicate()
	some.erase(heroes[0])
	livings.append(some)
	var pairs: Dictionary = Bonds.index(_ledger, _counting)
	var shipped_pairs: Dictionary = Bonds.index(_ledger, BALANCE)
	for living: Dictionary in livings:
		for id: String in heroes:
			for balance: BalanceTable in [BALANCE, _counting]:
				assert_eq(Bonds.bond(_ledger, id, living, balance), _slice1_bond(_ledger, id, living, balance), "%s among %s" % [id, living.keys()])
				var kept: Dictionary = shipped_pairs if balance == BALANCE else pairs
				var friends: Array = Bonds.roles(kept, id, living, balance)["friends"]
				assert_eq(str(Bonds.bond_from(kept, id, living, balance).get("partner", "")), str(friends[0]) if not friends.is_empty() else "", "the partner is the first friend: %s, threshold %d" % [id, balance.bond_threshold])
			assert_eq(Bonds.bond_from(pairs, id, living, _counting), _slice1_bond(_ledger, id, living, _counting), "a kept index: %s" % id)


func _select(hub: Node3D, hero_name: String) -> void:
	var roster: ItemList = hub.get_node("%RosterList") as ItemList
	for index: int in roster.item_count:
		if roster.get_item_text(index).contains("  %s — " % hero_name):
			roster.select(index)
			roster.multi_selected.emit(index, true)


func _row(hub: Node3D, hero_name: String) -> String:
	var roster: ItemList = hub.get_node("%RosterList") as ItemList
	for index: int in roster.item_count:
		if roster.get_item_text(index).contains("  %s — " % hero_name):
			return roster.get_item_text(index)
	return ""


## A figure's partner sign as seen: its text while visible, else "".
func _sign(figure: Node3D) -> String:
	var label: Label3D = figure.get_node("Sign") as Label3D
	return label.text if label.visible else ""


func _team(rng: RandomNumberGenerator, heroes: Array[String], size: int) -> Array[String]:
	var team: Array[String] = []
	while team.size() < size:
		var id: String = heroes[rng.randi_range(0, heroes.size() - 1)]
		if not team.has(id):
			team.append(id)
	return team


## Kills for a team as _record_battle writes them (hero id -> a small count), from a number and no rng: three values in
## turn, so some heroes tie and some outkill others (ig-m6o.2.2.6's respect).
func _kills_for(index: int, team: Array[String]) -> Dictionary:
	var kills: Dictionary = {}
	for slot: int in team.size():
		kills[team[slot]] = (index + slot * 2) % 3
	return kills


## The read-cost mix of test_read_cost_at_the_cap: 6 in 10 routine wins, the rest hard with a
## revive, one in 10 a rescue.
func _mix(rng: RandomNumberGenerator, index: int, team: Array[String]) -> Dictionary:
	var roll: int = rng.randi_range(0, 9)
	var fields: Dictionary = {"order": "order:%d" % index, "kills": _kills_for(index, team)}
	if roll >= 6:
		fields.merge({"result": "retreated", "moments": [_moment("downed", team[0], "enemy:goblin"), _moment("revived", team[0], team[1])]})
	if roll == 9:
		fields.merge({"rescued": [team[2]], "rescuers": [team[3]]})
	return fields


## ig-m6o.2.2.9: one seeded record, [kind, fields], of every kind the fold reads: hard fights, saves,
## rescues, routine wins, deaths (mostly of a battle a few records back, sometimes of none or of the
## next one), summons and rank-ups. A battle's order is "order:<its seq>". A moment's by is an enemy,
## no one or any hero; with by_in_team, a teammate instead of any hero, as a real fight writes it, and
## a death has a cause (with a zone or a by, from the seq, so no rng draw differs) as kill_hero writes it.
## ig-m6o.2.2.4: with encounters, one record in five is a meeting of two different heroes (drawn first, so a
## seed without them makes the records it always made). ig-m6o.2.2.5: half of those are a meal of two to four instead.
## ig-m6o.2.2.6: a meeting's why alternates "coworkers" and "neighbours" by its seq, and every battle carries kills for its
## team (_kills_for), both without a draw, so the records are the ones a seed always made.
func _random_record(rng: RandomNumberGenerator, heroes: Array[String], seq: int, by_in_team: bool = false, with_encounters: bool = false) -> Array:
	if with_encounters and rng.randi_range(0, 4) == 0:
		if rng.randi_range(0, 1) == 0:
			var table: Array[String] = _team(rng, heroes, rng.randi_range(2, mini(4, heroes.size())))
			table.sort()
			return ["meal", {"diners": table, "place": "House_%d" % (seq % 3 + 1)}]
		var first: int = rng.randi_range(0, heroes.size() - 1)
		var second: int = (first + rng.randi_range(1, heroes.size() - 1)) % heroes.size()
		var pair: Array[String] = [heroes[first], heroes[second]]
		pair.sort()
		return ["encounter", {"heroes": pair, "place": "House_%d" % (seq % 3 + 1), "why": "coworkers" if seq % 2 == 0 else "neighbours"}]
	var roll: int = rng.randi_range(0, 19)
	var hero: String = heroes[rng.randi_range(0, heroes.size() - 1)]
	if roll < 2:
		return ["summoned", {"hero": hero, "name": "X", "rank": 0}]
	if roll < 4:
		return ["ranked_up", {"hero": hero, "from": 0, "to": 1}]
	if roll < 7:
		var died: Dictionary = {"hero": hero, "name": "X"}
		if roll < 6:
			died["battle_order"] = "order:%d" % (seq - rng.randi_range(-1, 6))
		if by_in_team:
			died["cause"] = ["expedition", "sacrifice", "starvation"][seq % 3]
			if seq % 3 == 0:
				died["zone"] = [ZONE, "frontier_march"][seq % 2]
			elif seq % 3 == 1:
				died["by"] = heroes[(seq * 7) % heroes.size()]
		return ["died", died]
	var team: Array[String] = _team(rng, heroes, rng.randi_range(1, 5))
	var moments: Array = []
	var savers: Array[String] = team if by_in_team else heroes
	for _index: int in rng.randi_range(0, 3) if rng.randi_range(0, 1) == 0 else 0:
		var by: String = ["enemy:goblin", "", savers[rng.randi_range(0, savers.size() - 1)]][rng.randi_range(0, 2)]
		moments.append(_moment(["revived", "carried", "downed"][rng.randi_range(0, 2)], team[rng.randi_range(0, team.size() - 1)], by))
	var fields: Dictionary = {"order": "order:%d" % seq, "zone": [ZONE, "frontier_march"][rng.randi_range(0, 1)], "team": team,
		"result": ["victory", "victory", "retreated", "stranded"][rng.randi_range(0, 3)], "moments": moments}
	if rng.randi_range(0, 4) == 0:
		fields["rescued"] = [team[0]]
		fields["rescuers"] = [heroes[rng.randi_range(0, heroes.size() - 1)], heroes[rng.randi_range(0, heroes.size() - 1)]]
	fields["kills"] = _kills_for(seq, team)
	return ["battle", fields]


## Summons (or records of another kind) of no one on the roster up to short of the cap, straight into
## GameSession's ledger: they score nothing, so a rebuild stays cheap. GameSession's cap is folded in when it compiles, so a
## test cannot shrink it.
func _fill_to_cap(short: int, kind: String = "summoned") -> void:
	for seq: int in range(1, BALANCE.ledger_max_records - short + 1):
		Ledger.append(GameSession.ledger, seq, 0, kind, {"hero": "filler:%d" % seq, "name": "F", "rank": 0})
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1


func _assert_kept_names_through(kind: String) -> void:
	_fill_to_cap(3, kind)
	_hero(A, "Ada")
	var hub: Node3D = _hub()
	var living: Dictionary = hub._roster_names()
	assert_eq(hub._known_names(living), Ledger.known_names(GameSession.ledger, living), "%s: at entry" % kind)
	var kept: Dictionary = hub._record_names
	assert_true((kept["names"] as Dictionary).has("filler:1"))
	for step: int in 3:
		GameSession._record(kind, {"hero": "new:%d" % step, "name": "N%d" % step, "rank": 0})
		assert_eq(hub._known_names(living), Ledger.known_names(GameSession.ledger, living), "%s: append %d" % [kind, step])
		assert_true(is_same(hub._record_names, kept), "%s: append %d folded into the kept names" % [kind, step])
	assert_eq(GameSession.ledger.size(), BALANCE.ledger_max_records)
	GameSession._record(kind, {"hero": "new:3", "name": "N3", "rank": 0})
	assert_false(GameSession.ledger.any(func(record: Dictionary) -> bool: return record["hero"] == "filler:1"), "%s: the oldest filler was evicted" % kind)
	assert_eq(hub._known_names(living), Ledger.known_names(GameSession.ledger, living), "%s: after the eviction" % kind)
	assert_false((hub._record_names["names"] as Dictionary).has("filler:1"), "%s: its name went" % kind)
	assert_false(is_same(hub._record_names, kept), "%s: read again in full" % kind)
	kept = hub._record_names
	assert_eq(hub._known_names(living), Ledger.known_names(GameSession.ledger, living))
	assert_true(is_same(hub._record_names, kept), "%s: once" % kind)
	var data: Dictionary = GameSession.to_dict()
	data["ledger"] = GameSession.ledger.duplicate(true)
	GameSession.from_dict(data)
	living = hub._roster_names()
	assert_eq(hub._known_names(living), Ledger.known_names(GameSession.ledger, living), "%s: after a load" % kind)
	assert_false(is_same(hub._record_names, kept), "%s: a load reads again in full" % kind)


func _assert_index_is_a_rebuild(what: String) -> void:
	assert_eq(_nonempty(GameSession.bond_index()), _nonempty(Bonds.index(GameSession.ledger, BALANCE)), what)


## ig-m6o.2.2.6, D4: a pair's respect never outnumbers its hard fights and its teamwork never its meetings, so a pair that
## holds a layer always holds a slot _tally can pick as its fact (a layer is never the fact).
func _layers_have_their_facts(counts: Dictionary) -> bool:
	for hero_id: String in counts:
		for other: String in counts[hero_id]:
			var slots: Array = counts[hero_id][other]
			if slots[Bonds.RESPECT][0] > slots[0][0] or slots[Bonds.TEAMWORK][0] > slots[Bonds.MEETINGS][0]:
				return false
	return true


## True when some pair holds a count in slot.
func _any_count(counts: Dictionary, slot: int) -> bool:
	for hero_id: String in counts:
		for other: String in counts[hero_id]:
			if counts[hero_id][other][slot][0] > 0:
				return true
	return false


## pairs without its heroes that have no pairs: a fold may keep them as {}, a rebuild never makes them.
func _nonempty(pairs: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for hero_id: String in pairs:
		if not (pairs[hero_id] as Dictionary).is_empty():
			out[hero_id] = pairs[hero_id]
	return out


## One meal time of the ACC fixture: eight tables of four. The first is A, B, C and D; the others are made-up ids.
func _meal_time() -> Array[Array]:
	var tables: Array[Array] = []
	for table: int in MEAL_TABLES:
		var sitting: Array = [A, B, C, D] if table == 0 else ["hero:t%d_0" % table, "hero:t%d_1" % table, "hero:t%d_2" % table, "hero:t%d_3" % table]
		tables.append(sitting)
	return tables


func _print_cost(what: String, runs: Array[int]) -> void:
	gut.p("BOND COST: %s, %d records, best %.2f ms, worst %.2f ms of 7" % [what, GameSession.ledger.size(), runs.min() / 1000.0, runs.max() / 1000.0])


## ig-m6o.2.1's per-hero reader, kept as the answer the one-pass index must give. It reads battles
## and deaths only, so it covers a ledger with no encounter, meal or kills in it; the constants ig-m6o.2.2.4 and .5 added
## ("meetings" 0, "meals" 0 and the fact's "place" "") and .6's ("respect" 0, "teamwork" 0) are the tally's new fields
## for such a ledger. ig-m6o.2.2.6 moved it to the layered rule: a save or rescue scores the side that was saved in
## full and the side that saved less ("saving", "rescuing"), one count per side per record.
static func _slice1_bond(ledger: Array[Dictionary], hero_id: String, living: Dictionary, balance: BalanceTable) -> Dictionary:
	var dead_by_order: Dictionary = {}
	for record: Dictionary in ledger:
		if str(record.get("kind", "")) == "died" and record.has("battle_order"):
			var order: String = str(record["battle_order"])
			if not dead_by_order.has(order):
				dead_by_order[order] = []
			(dead_by_order[order] as Array).append(str(record.get("hero", "")))
	var tallies: Dictionary = {}
	for record: Dictionary in ledger:
		if str(record.get("kind", "")) != "battle":
			continue
		var team: Array = Bonds._array(record, "team")
		var rescued: Array = Bonds._array(record, "rescued")
		var rescuers: Array = Bonds._array(record, "rescuers")
		if not (team.has(hero_id) or rescued.has(hero_id)):
			continue
		var seq: int = int(record.get("seq", 0))
		var zone: String = str(record.get("zone", ""))
		var hard: bool = team.has(hero_id) and not Ledger.is_routine(record)
		var dead: Array = dead_by_order.get(str(record.get("order", "")), [])
		# ig-m6o.2.2.6: each side once per record: hero_id was saved by the other, and hero_id saved the other.
		var received: Dictionary = {}
		var given: Dictionary = {}
		for raw_moment: Variant in Bonds._array(record, "moments"):
			var moment: Dictionary = raw_moment as Dictionary if raw_moment is Dictionary else {}
			if not str(moment.get("what", "")) in Bonds.SAVES:
				continue
			if str(moment.get("hero", "")) == hero_id:
				received[str(moment.get("by", ""))] = true
			if str(moment.get("by", "")) == hero_id:
				given[str(moment.get("hero", ""))] = true
		var others: Dictionary = {}
		for id: Variant in team + rescued + rescuers:
			if str(id) != hero_id and living.has(str(id)):
				others[str(id)] = true
		for other: String in others:
			var facts: Array[Dictionary] = []
			if hard and team.has(other):
				facts.append({"kind": "hard", "points": balance.bond_points_hard_battle})
			if received.has(other):
				facts.append({"kind": "saved_by", "points": balance.bond_points_saved, "count": "saves"})
			if rescuers.has(other) and rescued.has(hero_id):
				facts.append({"kind": "saved_by", "points": balance.bond_points_rescued, "count": "rescues"})
			var witnessed: Array = dead.filter(func(id: String) -> bool: return id != hero_id and id != other)
			if not witnessed.is_empty() and team.has(hero_id) and team.has(other):
				facts.append({"kind": "death", "points": balance.bond_points_death_witnessed, "count": "deaths", "dead": witnessed[0]})
			if given.has(other):
				facts.append({"kind": "saved", "points": balance.bond_points_saving, "count": "saving"})
			if rescuers.has(hero_id) and rescued.has(other):
				facts.append({"kind": "saved", "points": balance.bond_points_rescuing, "count": "rescuing"})
			if facts.is_empty():
				continue
			if not tallies.has(other):
				tallies[other] = {"partner": other, "points": 0, "hard": 0, "saves": 0, "rescues": 0, "deaths": 0, "meetings": 0, "meals": 0, "respect": 0, "teamwork": 0, "saving": 0, "rescuing": 0, "last_seq": 0, "fact": {}}
			var tally: Dictionary = tallies[other]
			tally["last_seq"] = seq
			for fact: Dictionary in facts:
				tally["points"] += fact["points"]
				var count: String = fact.get("count", "hard")
				tally[count] += 1
				var best: Dictionary = tally["fact"]
				if best.is_empty() or fact["points"] >= best["points"]:
					tally["fact"] = {"kind": fact["kind"], "points": fact["points"], "seq": seq, "zone": zone, "dead": fact.get("dead", ""), "place": ""}
	var chosen: Dictionary = {}
	for tally: Dictionary in tallies.values():
		if tally["points"] < balance.bond_threshold:
			continue
		if chosen.is_empty() or Bonds._ahead(tally, chosen):
			chosen = tally
	return chosen


## A hub with Ada and Bea bonded and, unless embody is false, Ada as the body.
func _bonded_town(embody: bool = true, battles: int = 2) -> TownView:
	_hero(A, "Ada")
	_hero(B, "Bea")
	for _index: int in battles:
		_battle_in(GameSession.ledger, [A, B], "victory", {"moments": [_moment("revived", A, B)]})
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1
	var town: TownView = _hub().get_node("%Town") as TownView
	if embody:
		assert_true(GameSession.embody_hero(A))
		assert_not_null(town.partner)
	return town


func _walker_figures(town: TownView, hero_id: String) -> int:
	var count: int = 0
	for child: Node in town.get_children():
		if child is TownWalker and (child as TownWalker).hero_id == hero_id:
			count += 1
	return count


## Every placed building's pick box grown by 0.3 m, as town-space x/z (as test_town_walkers does).
func _boxes(town: TownView) -> Array[Rect2]:
	var boxes: Array[Rect2] = []
	for building: Dictionary in GameSession.town_buildings:
		var node: Node3D = town.get_node(NodePath(str(building["id"])))
		var pick: Node3D = node.get_node("Pick") as Node3D
		var shape: CollisionShape3D = pick.find_children("*", "CollisionShape3D", false, false)[0] as CollisionShape3D
		var size: Vector3 = (shape.shape as BoxShape3D).size
		var centre: Vector3 = node.transform * pick.transform * shape.position
		boxes.append(Rect2(centre.x - size.x / 2.0, centre.z - size.z / 2.0, size.x, size.z).grow(0.3))
	return boxes


func _battle(team: Array, result: String, extra: Dictionary = {}) -> void:
	_battle_in(_ledger, team, result, extra)


func _battle_in(ledger: Array[Dictionary], team: Array, result: String, extra: Dictionary = {}) -> void:
	var fields: Dictionary = {"order": "order:%d" % ledger.size(), "zone": ZONE, "team": team, "result": result, "moments": []}
	fields.merge(extra, true)
	Ledger.append(ledger, ledger.size() + 1, 0, "battle", fields)


func _record(kind: String, fields: Dictionary) -> void:
	Ledger.append(_ledger, _ledger.size() + 1, 0, kind, fields)


## One encounter record of GameSession's shape, the pair as given.
func _meeting(one: String, other: String, place: String = "House_1", why: String = "neighbours") -> void:
	_record("encounter", {"heroes": [one, other], "place": place, "why": why})


## count meetings of the same pair.
func _meetings(one: String, other: String, count: int) -> void:
	for _index: int in count:
		_meeting(one, other)


## hero_id's roles over the whole ledger, among living (everyone, A to C, when it is null).
func _roles(hero_id: String, living: Variant = null) -> Dictionary:
	return Bonds.roles(Bonds.index(_ledger, BALANCE), hero_id, _living() if living == null else living as Dictionary, BALANCE)


## One meal record of GameSession's shape, the diners as given and sorted, as the roll writes them.
func _meal(diners: Array, place: String = "House_1") -> void:
	var sitting: Array = diners.duplicate()
	sitting.sort()
	_record("meal", {"diners": sitting, "place": place})


func _moment(what: String, hero: String, by: String) -> Dictionary:
	return {"tick": 1, "what": what, "hero": hero, "by": by}


func _kinds(kinds: Array) -> Array[String]:
	var typed: Array[String] = []
	typed.assign(kinds)
	return typed


func _bond(hero_id: String) -> Dictionary:
	return Bonds.bond(_ledger, hero_id, _living(), _counting)


func _living() -> Dictionary:
	return {A: true, B: true, C: true}


## Ada, Bea, Cal, Dov and Eve on the roster. Bea is Ada's closest (three saves, 12 points) and Cal her
## next (two, the threshold); Dov and Eve have no bond. The hub has looked once, holds the warm signs and a
## dream of Bea, and its status line is empty.
func _membership_hub() -> Node3D:
	for pair: Array in [[A, "Ada"], [B, "Bea"], [C, "Cal"], [D, "Dov"], [E, "Eve"]]:
		_hero(pair[0], pair[1])
	_saves_between(A, B, 3)
	_saves_between(A, C, 2)
	var hub: Node3D = _hub()
	assert_eq(hub._partner_signs(hub._roster_names())[A], "♥ Bea")
	hub._dream(B)
	(hub.get_node("%Status") as Label).text = ""
	return hub


## count battles of one and other, each with one save: 4 points a battle, so two reach the threshold (8).
func _saves_between(one: String, other: String, count: int) -> void:
	for _index: int in count:
		_battle_in(GameSession.ledger, [one, other], "victory", {"moments": [_moment("revived", one, other)]})
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1


## ig-bnq: after an action's look, the hub's memos are a full look's. before is the candidates, deep-copied
## before the action. The candidates equal _living_candidates, every sign equals a fresh _partner_sign (and
## there is no other), no hero that left keeps a dream, and the notice the action's look said is the one a
## full look over every hero says. ig-7sn.24: and the kept partners are bond_from's for exactly the living heroes.
func _assert_look_is_exact(hub: Node3D, before: Dictionary, what: String) -> void:
	var status: Label = hub.get_node("%Status") as Label
	var told: String = status.text
	var living: Dictionary = hub._roster_names()
	var pairs: Dictionary = GameSession.bond_index()
	var signs: Dictionary = hub._partner_signs(living)
	var fresh: Dictionary = {}
	for id: String in living:
		fresh[id] = hub._partner_sign(id, living)
	assert_eq(hub._bond_candidates, hub._living_candidates(pairs, living), "%s: the candidates" % what)
	assert_eq(hub._bond_partners, _full_partners(pairs, living), "%s: the kept partners" % what)
	assert_eq(signs, fresh, "%s: the signs" % what)
	for id: String in hub._dreams:
		assert_true(living.has(id), "%s: %s left and kept a dream" % [what, id])
	status.text = ""
	hub._say_new_bonds(before, pairs, living)
	assert_eq(told, status.text, "%s: the notice" % what)


## ig-7sn.24: {hero_id: partner id or ""} for every living hero, each a full bond_from over the index: what the hub's kept
## partners must equal, keys and all.
func _full_partners(pairs: Dictionary, living: Dictionary) -> Dictionary:
	var partners: Dictionary = {}
	for id: String in living:
		partners[id] = str(Bonds.bond_from(pairs, id, living, BALANCE).get("partner", ""))
	return partners


func _hero(id: String, hero_name: String) -> Hero:
	var hero: Hero = _new_hero(id, hero_name)
	GameSession.add_hero(hero)
	return hero


## A hero that is not on the roster yet (a summon adds it).
func _new_hero(id: String, hero_name: String) -> Hero:
	var hero := Hero.new(hero_name, 7)
	hero.def_id = &"knight"
	hero.instance_id = id
	hero.level = 80
	return hero


func _hub() -> Node3D:
	var hub: Node3D = (load("res://hub/hub.tscn") as PackedScene).instantiate() as Node3D
	add_child_autofree(hub)
	return hub


func _set_key(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _frames(count: int) -> void:
	for _frame: int in count:
		await get_tree().process_frame


## Lets the hub's deferred dream reads run, one a frame, until none is queued (ig-m6o.2.2.10): a view redraw shows the
## kept dream, or none, on its own frame, and the frames after show what a full read says.
func _dreams_read(hub: Node) -> void:
	for _frame: int in 12:
		if hub._marked_queue.is_empty():
			return
		await get_tree().process_frame
