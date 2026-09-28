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
	assert_eq([_bond(A)["points"], _bond(A)["rescues"]], [6, 1], "a rescue plus its hard battle")
	_ledger = []
	_battle([A, B, C], "stranded", {"order": "order:1"})
	_record("died", {"hero": C, "name": "Cal", "battle_order": "order:1"})
	var witnessed: Dictionary = Bonds.bond(_ledger, A, {A: true, B: true}, _counting)
	assert_eq([witnessed["points"], witnessed["deaths"], witnessed["fact"]["dead"]], [6, 1, C], "a death seen together")


func test_a_fact_counts_once_per_record_for_a_pair() -> void:
	_battle([A, B], "victory", {"moments": [_moment("revived", A, B), _moment("carried", A, B), _moment("revived", B, A)]})
	assert_eq([_bond(A)["points"], _bond(A)["saves"]], [4, 1])


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


## ---- the dream

func test_the_dream_opens_advances_is_paid_and_opens_again() -> void:
	_battle([A, B], "victory")
	assert_eq(Bonds.dream(_ledger, A), {}, "no save, no dream")
	assert_eq(Bonds.dream_lines({}, A, NAMES, BALANCE), [] as Array[String])
	_battle([A, B], "victory", {"moments": [_moment("carried", A, B)]})
	var zone: String = Ledger.zone_name(ZONE)
	assert_eq(Bonds.dream(_ledger, A), {"state": "open", "owed": B, "what": "carried", "zone": ZONE, "fights": 0}, "the opening battle is not a fight after it")
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


## One bond and dream read for one hero at the cap. A measurement for ig-m6o.2.2, not a gate.
func test_read_cost_at_the_cap() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var heroes: Array[String] = []
	for index: int in 40:
		heroes.append("hero:%d" % index)
	for index: int in BALANCE.ledger_max_records:
		var team: Array[String] = []
		for _slot: int in 4:
			team.append(heroes[rng.randi_range(0, heroes.size() - 1)])
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
	for _run: int in 7:
		var started: int = Time.get_ticks_usec()
		Bonds.bond(_ledger, heroes[0], living, BALANCE)
		Bonds.dream(_ledger, heroes[0])
		best_usec = mini(best_usec, Time.get_ticks_usec() - started)
	gut.p("BOND READ COST: %d records, one bond and dream read, best of 7: %.2f ms" % [_ledger.size(), best_usec / 1000.0])
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
	var text: String = (hub.get_node("%HeroDetail") as Label).text
	assert_string_contains(text, "Closest to Bea: 2 hard fights, 2 saves.\n\nDream: repay Bea.\n  [x] Bea revived Ada at")
	assert_string_contains(text, "  [ ] Fight beside Bea again (1/3).\n  [ ] Save Bea.\n\nHistory:\n")
	assert_true(GameSession.roster.has(ada))


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
	assert_eq(town.partner.facts["kinds"], Lines.greeting_facts(Bonds.bond(GameSession.ledger, A, {A: true, B: true}, BALANCE), {}, A, {}).get("kinds"), "saved_by, from Ada's bond")
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
	for _index: int in 2:
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
	for _index: int in 2:
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
	var town: TownView = _bonded_town()
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
	_battle_in(GameSession.ledger, [A, B], "victory", {"moments": [_moment("revived", A, B)]})
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
	battle["moments"] = [_moment("revived", A, B)]
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
	assert_eq(status.text, "Ada and Dov grew close.", "Ada moves to Dov (12 over 8) and Dov gets Ada")
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
	assert_eq(status.text, "Eve and Fay grew close. (+1 more)", "and Gil grew close to Fay, who ties to Eve on the lower id")


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
		var started: int = Time.get_ticks_usec()
		GameSession._record("battle", {"order": "order:more%d" % run, "zone": ZONE, "team": _team(rng, heroes, 5), "result": "retreated", "moments": []})
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
			Bonds.fold_in(folded, ledger.back(), BALANCE)
			if _nonempty(folded["pairs"]) != _nonempty(Bonds.index(ledger, BALANCE)):
				fail_test("seed %d: appending seq %d" % [seed_value, seq])
				return
			for record: Dictionary in Ledger.evict(ledger, tiers, 20):
				if not Bonds.fold_out(folded, record, BALANCE):
					refused += 1
					folded = Bonds.index_state(ledger, BALANCE)
			if _nonempty(folded["pairs"]) != _nonempty(Bonds.index(ledger, BALANCE)):
				fail_test("seed %d: evicting after seq %d" % [seed_value, seq])
				return
	# The mix has deaths of routine wins and deaths before their battle, which today's game never
	# writes, so some take-outs are refused and rebuild; the count only shows the path ran.
	gut.p("FOLD PROPERTY: 1,200 appends under a cap of 20, %d take-outs refused and rebuilt" % refused)
	assert_gt(refused, 0)


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
					var dropped: Array = _random_record(rng, heroes, GameSession.ledger_next_seq)
					GameSession._record(dropped[0], dropped[1])
				return false
			assert_false(GameSession._commit_profile_mutation(mutation))
		var made: Array = _random_record(rng, heroes, GameSession.ledger_next_seq)
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


func test_the_detail_panel_reads_a_dream_once_per_ledger_change() -> void:
	_hero(A, "Ada")
	_hero(B, "Bea")
	for _index: int in 2:
		_battle_in(GameSession.ledger, [A, B], "victory", {"moments": [_moment("revived", A, B)]})
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1
	var hub: Node3D = _hub()
	hub._open(&"Forge")
	_select(hub, "Ada")
	var reads: int = hub.dream_reads
	hub._refresh_hero_detail()
	hub._refresh_hero_detail()
	assert_eq(hub.dream_reads, reads, "no ledger change: the kept dream")
	GameSession._record("battle", {"order": "order:new", "zone": ZONE, "team": [A, B], "result": "retreated", "moments": []})
	hub._refresh_hero_detail()
	hub._refresh_hero_detail()
	assert_eq(hub.dream_reads, reads + 1, "an append: read once more")
	assert_string_contains((hub.get_node("%HeroDetail") as Label).text, "Fight beside Bea again (2/3).")


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
	var town: TownView = _bonded_town(false)
	assert_true(GameSession.embody_hero(B), "Bea is the body; Ada, whom she saved, is the partner")
	assert_eq(town.partner.hero_id, A)
	var facts: Dictionary = town.partner.facts
	assert_eq(facts["kinds"].size(), 2)
	assert_eq([facts["kinds"][0], facts["kinds"][1]], ["saved", "debt"], "Ada's open dream owes Bea")
	assert_eq(facts["slots"]["name"], "Bea")
	assert_eq(Lines.candidates(facts).size(), 10)


## ---- ig-7sn.16: the settle's readers, exact after the speed-ups

## ACC 3: the dream that skips battles without the hero equals the one that read every record, for
## every hero of the perf seed's ledger, and at every 50th record of seeded ledgers the game could
## write (a moment's hero and by are in the team), which open, pay and lose dreams.
func test_the_dream_that_skips_equals_the_dream_that_read_every_record() -> void:
	var heroes: Array[String] = []
	for index: int in 100:
		heroes.append("perf:%d" % index)
	var seeded: Array[Dictionary] = _perf_ledger(heroes)
	for hero_id: String in heroes:
		if Bonds.dream(seeded, hero_id) != _dream_before(seeded, hero_id):
			fail_test("the perf seed's %s" % hero_id)
			return
	var eight: Array[String] = heroes.slice(0, 8)
	var states: Dictionary = {}
	for seed_value: int in [1, 2, 3]:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var ledger: Array[Dictionary] = []
		for seq: int in range(1, 801):
			var made: Array = _random_record(rng, eight, seq, true)
			Ledger.append(ledger, seq, 0, made[0], made[1])
			if seq % 50 == 0:
				for hero_id: String in eight:
					var dream: Dictionary = Bonds.dream(ledger, hero_id)
					if dream != _dream_before(ledger, hero_id):
						fail_test("seed %d, %s at seq %d" % [seed_value, hero_id, seq])
						return
					states[dream.get("state", "none")] = true
	assert_eq(states.keys().filter(func(state: String) -> bool: return state in ["open", "paid", "lost"]).size(), 3, "every state compared: %s" % [states.keys()])


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
	gut.p("HUB LOOKS: %s" % looks)
	assert_true(looks["quiet"] > 0 and looks["partial"] > 0 and looks["said"] > 0, "quiet looks, looks at a few heroes, and news: %s" % looks)
	assert_eq(GameSession.ledger.size(), BALANCE.ledger_max_records, "the second half evicted")


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


## Bonds.dream before ig-7sn.16, reading every record: the exactness test's reference.
static func _dream_before(ledger: Array[Dictionary], hero_id: String) -> Dictionary:
	var current: Dictionary = {}
	for record: Dictionary in ledger:
		var kind: String = str(record.get("kind", ""))
		if current.get("state", "") == "open":
			var owed: String = current["owed"]
			if kind == "died" and str(record.get("hero", "")) == owed:
				current = {"state": "lost", "owed": owed}
			elif kind == "battle" and not Bonds._save(record, owed, hero_id).is_empty():
				current = {"state": "paid", "owed": owed, "zone": str(record.get("zone", ""))}
			elif kind == "battle" and Bonds._array(record, "team").has(hero_id) and Bonds._array(record, "team").has(owed):
				current["fights"] += 1
			continue
		if kind != "battle":
			continue
		var opened: Dictionary = Bonds._save(record, hero_id, "")
		if not opened.is_empty():
			current = {"state": "open", "owed": opened["by"], "what": opened["what"], "zone": str(record.get("zone", "")), "fights": 0}
	return current


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
	for living: Dictionary in livings:
		for id: String in heroes:
			for balance: BalanceTable in [BALANCE, _counting]:
				assert_eq(Bonds.bond(_ledger, id, living, balance), _slice1_bond(_ledger, id, living, balance), "%s among %s" % [id, living.keys()])
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


## The read-cost mix of test_read_cost_at_the_cap: 6 in 10 routine wins, the rest hard with a
## revive, one in 10 a rescue.
func _mix(rng: RandomNumberGenerator, index: int, team: Array[String]) -> Dictionary:
	var roll: int = rng.randi_range(0, 9)
	var fields: Dictionary = {"order": "order:%d" % index}
	if roll >= 6:
		fields.merge({"result": "retreated", "moments": [_moment("downed", team[0], "enemy:goblin"), _moment("revived", team[0], team[1])]})
	if roll == 9:
		fields.merge({"rescued": [team[2]], "rescuers": [team[3]]})
	return fields


## ig-m6o.2.2.9: one seeded record, [kind, fields], of every kind the fold reads: hard fights, saves,
## rescues, routine wins, deaths (mostly of a battle a few records back, sometimes of none or of the
## next one), summons and rank-ups. A battle's order is "order:<its seq>". A moment's by is an enemy,
## no one or any hero; with by_in_team, a teammate instead of any hero, as a real fight writes it.
func _random_record(rng: RandomNumberGenerator, heroes: Array[String], seq: int, by_in_team: bool = false) -> Array:
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
	return ["battle", fields]


## Summons of no one on the roster up to short of the cap, straight into GameSession's ledger: they
## score nothing, so a rebuild stays cheap. GameSession's cap is folded in when it compiles, so a
## test cannot shrink it.
func _fill_to_cap(short: int) -> void:
	for seq: int in range(1, BALANCE.ledger_max_records - short + 1):
		Ledger.append(GameSession.ledger, seq, 0, "summoned", {"hero": "filler:%d" % seq, "name": "F", "rank": 0})
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1


func _assert_index_is_a_rebuild(what: String) -> void:
	assert_eq(_nonempty(GameSession.bond_index()), _nonempty(Bonds.index(GameSession.ledger, BALANCE)), what)


## pairs without its heroes that have no pairs: a fold may keep them as {}, a rebuild never makes them.
func _nonempty(pairs: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for hero_id: String in pairs:
		if not (pairs[hero_id] as Dictionary).is_empty():
			out[hero_id] = pairs[hero_id]
	return out


func _print_cost(what: String, runs: Array[int]) -> void:
	gut.p("BOND COST: %s, %d records, best %.2f ms, worst %.2f ms of 7" % [what, GameSession.ledger.size(), runs.min() / 1000.0, runs.max() / 1000.0])


## ig-m6o.2.1's per-hero reader, kept verbatim as the answer the one-pass index must give.
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
		var saved_with: Dictionary = {}
		for raw_moment: Variant in Bonds._array(record, "moments"):
			var moment: Dictionary = raw_moment as Dictionary if raw_moment is Dictionary else {}
			if not str(moment.get("what", "")) in Bonds.SAVES:
				continue
			if str(moment.get("hero", "")) == hero_id and not saved_with.has(str(moment.get("by", ""))):
				saved_with[str(moment.get("by", ""))] = "saved_by"
			elif str(moment.get("by", "")) == hero_id and not saved_with.has(str(moment.get("hero", ""))):
				saved_with[str(moment.get("hero", ""))] = "saved"
		var others: Dictionary = {}
		for id: Variant in team + rescued + rescuers:
			if str(id) != hero_id and living.has(str(id)):
				others[str(id)] = true
		for other: String in others:
			var facts: Array[Dictionary] = []
			if hard and team.has(other):
				facts.append({"kind": "hard", "points": balance.bond_points_hard_battle})
			if saved_with.has(other):
				facts.append({"kind": saved_with[other], "points": balance.bond_points_saved, "count": "saves"})
			if rescuers.has(hero_id) and rescued.has(other) or rescuers.has(other) and rescued.has(hero_id):
				facts.append({"kind": "saved" if rescuers.has(hero_id) else "saved_by", "points": balance.bond_points_rescued, "count": "rescues"})
			var witnessed: Array = dead.filter(func(id: String) -> bool: return id != hero_id and id != other)
			if not witnessed.is_empty() and team.has(hero_id) and team.has(other):
				facts.append({"kind": "death", "points": balance.bond_points_death_witnessed, "count": "deaths", "dead": witnessed[0]})
			if facts.is_empty():
				continue
			if not tallies.has(other):
				tallies[other] = {"partner": other, "points": 0, "hard": 0, "saves": 0, "rescues": 0, "deaths": 0, "last_seq": 0, "fact": {}}
			var tally: Dictionary = tallies[other]
			tally["last_seq"] = seq
			for fact: Dictionary in facts:
				tally["points"] += fact["points"]
				var count: String = fact.get("count", "hard")
				tally[count] += 1
				var best: Dictionary = tally["fact"]
				if best.is_empty() or fact["points"] >= best["points"]:
					tally["fact"] = {"kind": fact["kind"], "points": fact["points"], "seq": seq, "zone": zone, "dead": fact.get("dead", "")}
	var chosen: Dictionary = {}
	for tally: Dictionary in tallies.values():
		if tally["points"] < balance.bond_threshold:
			continue
		if chosen.is_empty() or Bonds._ahead(tally, chosen):
			chosen = tally
	return chosen


## A hub with Ada and Bea bonded and, unless embody is false, Ada as the body.
func _bonded_town(embody: bool = true) -> TownView:
	_hero(A, "Ada")
	_hero(B, "Bea")
	for _index: int in 2:
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


func _moment(what: String, hero: String, by: String) -> Dictionary:
	return {"tick": 1, "what": what, "hero": hero, "by": by}


func _bond(hero_id: String) -> Dictionary:
	return Bonds.bond(_ledger, hero_id, _living(), _counting)


func _living() -> Dictionary:
	return {A: true, B: true, C: true}


func _hero(id: String, hero_name: String) -> Hero:
	var hero := Hero.new(hero_name, 7)
	hero.def_id = &"knight"
	hero.instance_id = id
	hero.level = 80
	GameSession.add_hero(hero)
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
