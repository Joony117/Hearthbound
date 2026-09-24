extends GutTest

## ig-m6o.2.1: bonds and dreams, slice 1 (SYSTEMS.md § Bonds and dreams, slice 1).

const BALANCE: BalanceTable = preload("res://balance.tres")
const ZONE: String = "verdant_outskirts"
const A: String = "hero:a"
const B: String = "hero:b"
const C: String = "hero:c"
const D: String = "hero:d"
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
	var zone: String = Ledger.zone_name(ZONE)
	assert_eq(Bonds.greeting(found, NAMES), "I haven't forgotten %s. I owe you." % zone, "the latest 5-point fact: A rescued B")
	assert_eq(Bonds.greeting(Bonds.bond(_ledger, B, {A: true, B: true}, BALANCE), NAMES), "I'd come for you again. %s or anywhere." % zone)
	_ledger = []
	_battle([A, B, C], "stranded", {"order": "order:1"})
	_record("died", {"hero": C, "name": "Cal", "battle_order": "order:1"})
	for _index: int in 2:
		_battle([A, B], "retreated")
	assert_eq(Bonds.greeting(Bonds.bond(_ledger, A, {A: true, B: true}, BALANCE), NAMES), "I still think about Cal.")
	_ledger = []
	for _index: int in 8:
		_battle([A, B], "retreated")
	assert_eq(Bonds.greeting(Bonds.bond(_ledger, A, _living(), BALANCE), NAMES), "Eight hard fights, and we're both still standing.")


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
		if roster.get_item_text(index).contains("Ada"):
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
	assert_eq(town.partner.position, TownView.BODY_SPAWN + TownView.PARTNER_SPAWN_OFFSET, "no House: beside the spawn")
	await _frames(2)
	assert_eq(town.partner.greetings, 0, "the spawn is out of reach")
	town.body.global_position = town.partner.global_position + Vector3(-1.5, 0.0, 0.0)
	await _frames(2)
	assert_eq(town.partner.greetings, 1)
	assert_true(town.partner.is_showing_line())
	assert_eq((town.partner.get_node("Line") as Label3D).text, "I'd come for you again. %s or anywhere." % Ledger.zone_name(ZONE))
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
	assert_true(GameSession.assign_home(bea, house_id), GameSession.last_action_error)
	assert_true(GameSession.embody_hero(ada.instance_id))
	var house: Node3D = town.get_node(NodePath(house_id)) as Node3D
	assert_eq(town.partner.position, house.position + TownView.PARTNER_DOOR_OFFSET, "Bea stands at her door")
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


## ---- helpers

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
