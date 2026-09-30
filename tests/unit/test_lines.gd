extends GutTest

## ig-m6o.2.2.2: the line bank. Lines.line and Lines.greeting_facts are pure, so these read a local
## ledger and never GameSession. The town side is in test_bonds.gd.

const BALANCE: BalanceTable = preload("res://balance.tres")
const ZONE: String = "verdant_outskirts"
const A: String = "hero:a"
const B: String = "hero:b"
const C: String = "hero:c"
const NAMES: Dictionary = {A: "Ada", B: "Bea", C: "Cal"}
## The slots each kind always gives (the bead's table).
const SLOTS: Dictionary = {
	"saved_by": ["name", "place"],
	"saved": ["name", "place"],
	"death": ["name", "place", "dead"],
	"hard": ["name", "place", "count"],
	"debt": ["name"],
	"watch_over": ["name", "place"],
	"carry_name": ["name", "place", "dead"],
	"be_worthy": ["name", "dead"],
}

var _ledger: Array[Dictionary] = []


func before_each() -> void:
	_ledger = []


func test_the_bank_fills_every_line_from_only_its_kinds_slots() -> void:
	assert_eq(Lines.BANK.keys().size(), SLOTS.size())
	var slot := RegEx.create_from_string("\\{(\\w+)\\}")
	# The worst case for length: a 14-letter name, the longest zone name, the fallback dead name.
	var worst: Dictionary = {"name": "Maximilianusss", "place": Ledger.zone_name(ZONE), "dead": "a hero now forgotten", "count": "Twelve"}
	for kind: String in SLOTS:
		var lines: Array = Lines.BANK[kind]
		assert_gte(lines.size(), 5, kind)
		for text: String in lines:
			var used: Array[String] = []
			for found: RegExMatch in slot.search_all(text):
				used.append(found.get_string(1))
			assert_false(used.is_empty(), "uses a slot: %s" % text)
			if kind in ["death", "carry_name", "be_worthy"]:
				assert_has(used, "dead", "a %s line names the dead hero: %s" % [kind, text])
			if kind == "carry_name":
				assert_has(used, "place", "a carry_name line names the place: %s" % text)
			for slot_name: String in used:
				assert_has(SLOTS[kind], slot_name, "%s may use {%s}: %s" % [kind, slot_name, text])
			var filled: String = text.format(worst)
			assert_false(filled.contains("{"), filled)
			assert_lte(filled.length(), 72, filled)


func test_the_old_greetings_are_each_kinds_first_line() -> void:
	for _index: int in 2:
		_battle([A, B, C], "stranded", {"order": "order:%d" % _ledger.size(), "rescued": [B], "rescuers": [A]})
	_record("died", {"hero": C, "name": "Cal", "battle_order": "order:0"})
	var zone: String = Ledger.zone_name(ZONE)
	assert_eq(_first(A, {A: true, B: true}), "I haven't forgotten %s. I owe you." % zone, "the latest 5-point fact: A rescued B")
	assert_eq(_first(B, {A: true, B: true}), "I'd come for you again. %s or anywhere." % zone)
	_ledger = []
	_battle([A, B, C], "stranded", {"order": "order:1"})
	_record("died", {"hero": C, "name": "Cal", "battle_order": "order:1"})
	for _index: int in 2:
		_battle([A, B], "retreated")
	assert_eq(_first(A, {A: true, B: true}), "I still think about Cal.")
	_ledger = []
	for _index: int in 8:
		_battle([A, B], "retreated")
	assert_eq(_first(A, {A: true, B: true, C: true}), "Eight hard fights, and we're both still standing.")


func test_a_death_line_names_the_dead_hero_or_the_fallback() -> void:
	_battle([A, B, C], "stranded", {"order": "order:1"})
	_record("died", {"hero": C, "name": "Cal", "battle_order": "order:1"})
	for _index: int in 2:
		_battle([A, B], "retreated")
	var facts: Dictionary = _facts(A, B)
	assert_eq(facts["kinds"], _kinds(["death"]))
	assert_eq(facts["slots"], {"name": "Ada", "place": Ledger.zone_name(ZONE), "dead": "Cal"})
	var unnamed: Dictionary = Lines.greeting_facts(Bonds.bond(_ledger, A, {A: true, B: true}, BALANCE), {}, A, {A: "Ada"})
	assert_eq(unnamed["slots"]["dead"], "a hero now forgotten", "a died record with no name")


func test_two_picks_in_a_row_differ_and_the_pick_wraps() -> void:
	for kinds: Array in [["saved_by"], ["saved"], ["death"], ["hard"], ["saved", "debt"], ["watch_over"], ["carry_name"], ["be_worthy"]]:
		var facts: Dictionary = {"kinds": _kinds(kinds), "slots": {"name": "Ada", "place": "Here", "dead": "Cal", "count": "Two"}, "start": 7}
		var size: int = Lines.candidates(facts).size()
		for pick: int in size:
			assert_ne(Lines.line(facts, pick), Lines.line(facts, pick + 1), "%s pick %d" % [kinds, pick])
		assert_eq(Lines.line(facts, size), Lines.line(facts, 0), "wraps: %s" % [kinds])
	assert_eq(Lines.line({}, 0), "", "no facts, no line")
	assert_eq(Lines.greeting_facts({}, {}, A, NAMES), {}, "no bond, no facts")


func test_the_start_is_the_pair_so_each_pair_opens_on_its_own_line() -> void:
	_saves()
	assert_eq(_facts(A, B)["start"], absi(("%s:%s" % [A, B]).hash()))
	assert_eq(_facts(B, A)["start"], absi(("%s:%s" % [B, A]).hash()))


# The partner speaks: debt lines while the partner's own dream owes the body, and not after.
func test_a_debt_shows_while_the_dream_is_open_and_not_after_it_is_paid_or_lost() -> void:
	_saves()
	assert_eq(_facts(B, A)["kinds"], _kinds(["saved", "debt"]), "Bea saved Ada: Ada owes Bea")
	assert_eq(_facts(A, B)["kinds"], _kinds(["saved_by", "watch_over"]), "Bea owes Ada nothing; she watches over her")
	var open: Array[Dictionary] = _ledger.duplicate()
	_battle([A, B], "victory", {"moments": [_moment("revived", B, A)]})
	assert_false(_facts(B, A)["kinds"].has("debt"), "paid")
	_ledger = open
	_record("died", {"hero": B, "name": "Bea"})
	assert_false(_facts(B, A)["kinds"].has("debt"), "lost")


# The catalogue's kinds (ig-m6o.2.2.7): the partner's own dream, open, adds its lines.
func test_watch_over_speaks_only_to_the_hero_watched_and_only_while_open() -> void:
	_saves()
	var facts: Dictionary = _facts(A, B)
	assert_eq(facts["kinds"], _kinds(["saved_by", "watch_over"]), "Bea watches over Ada, and says so to Ada")
	assert_eq(Lines.candidates(facts).size(), 10)
	for pick: int in 10:
		assert_false(Lines.line(facts, pick).contains("{"), Lines.line(facts, pick))
	assert_eq(Lines.greeting_facts(Bonds.bond(_ledger, C, {A: true, B: true, C: true}, BALANCE), Bonds.dream(_ledger, B), C, NAMES), {}, "no bond, no words")
	var open: Array[Dictionary] = _ledger.duplicate()
	_record("ranked_up", {"hero": A, "from": 0, "to": 1, "via": "essence"})
	assert_eq(_facts(A, B)["kinds"], _kinds(["saved_by"]), "fulfilled: quiet")
	_ledger = open
	var bond: Dictionary = Bonds.bond(_ledger, B, {A: true, B: true}, BALANCE)
	assert_eq(Lines.greeting_facts(bond, Bonds.dream(_ledger, A), B, NAMES)["kinds"], _kinds(["saved", "debt"]), "Ada's is the life debt")
	assert_false(Lines.greeting_facts(bond, {"dream": "watch_over", "state": "open", "who": C, "zone": ZONE, "count": 0}, B, NAMES)["kinds"].has("watch_over"), "she watches over Cal, not Bea")


func test_a_dream_kind_fills_its_own_place_and_dead_not_the_bonds() -> void:
	var elsewhere: String = Ledger.zone_name("frontier_march")
	_battle([A, B, C], "stranded", {"order": "order:x"})
	_record("died", {"hero": C, "name": "Cal", "battle_order": "order:x"})
	for _index: int in 2:
		_battle([A, B], "retreated")
	var bond: Dictionary = Bonds.bond(_ledger, A, {A: true, B: true}, BALANCE)
	assert_eq([bond["fact"]["kind"], bond["fact"]["dead"]], ["death", C], "the bond is the death seen together: Cal, at the first zone")
	var names: Dictionary = NAMES.duplicate()
	names["hero:d"] = "Dov"
	var dream: Dictionary = {"dream": "carry_name", "state": "open", "who": "hero:d", "zone": "frontier_march", "count": 0}
	var facts: Dictionary = Lines.greeting_facts(bond, dream, A, names)
	assert_eq(facts["kinds"], _kinds(["death", "carry_name"]), "any listener: Ada was not at Dov's fall")
	assert_eq(facts["own"], {"carry_name": {"place": elsewhere, "dead": "Dov"}})
	assert_eq(facts["slots"]["dead"], "Cal", "the bond's slots are kept as they were")
	facts["start"] = 0
	var deaths: int = (Lines.BANK["death"] as Array).size()
	for pick: int in deaths + (Lines.BANK["carry_name"] as Array).size():
		var said: String = Lines.line(facts, pick)
		assert_false(said.contains("{"), said)
		assert_eq(said.contains("Dov"), pick >= deaths, "Dov only in the dream's lines: %s" % said)
		assert_false(pick < deaths and said.contains(elsewhere), "the death's place is the bond's: %s" % said)
	var worthy: Dictionary = Lines.greeting_facts(bond, {"dream": "be_worthy", "state": "open", "who": C, "count": 0}, A, NAMES)
	assert_eq(worthy["kinds"], _kinds(["death", "be_worthy"]))
	assert_eq(worthy["own"], {"be_worthy": {"dead": "Cal"}})
	assert_eq(Lines.greeting_facts(bond, {"dream": "be_worthy", "state": "fulfilled", "who": C}, A, NAMES)["kinds"], _kinds(["death"]), "ended: quiet")
	assert_eq(Lines.greeting_facts(bond, {"dream": "be_worthy", "state": "open", "who": "hero:gone", "count": 0}, A, NAMES)["own"], {"be_worthy": {"dead": "a hero now forgotten"}})


# The owner's case (ig-m6o.2.1's seeded save, rebuilt): Dunn has at least 10 lines for Mara.
func test_the_owners_case_gives_dunn_ten_lines_for_mara() -> void:
	var mara: String = "hero:mara"
	var dunn: String = "hero:dunn"
	var aldo: String = "hero:aldo"
	var wren: String = "hero:wren"
	var names: Dictionary = {mara: "Mara", dunn: "Dunn", wren: "Wren"}
	for hero: Array in [[mara, "Mara", 2], [dunn, "Dunn", 1], [aldo, "Aldo", 1], [wren, "Wren", 1]]:
		_record("summoned", {"hero": hero[0], "name": hero[1], "rank": hero[2], "archetype": "knight"})
	for index: int in 5:
		_seeded("seed:routine:%d" % index, "verdant_outskirts", "victory", [mara, dunn, aldo, wren], [])
	_seeded("seed:1", "verdant_outskirts", "victory", [mara, dunn, aldo, wren], [_moment("downed", dunn, "enemy:goblin"), _moment("revived", dunn, mara)])
	_seeded("seed:2", "ashfall_reaches", "stranded", [mara, dunn, aldo], [_moment("downed", aldo, "enemy:skeleton"), _moment("downed", dunn, "enemy:skeleton")])
	_record("died", {"hero": aldo, "name": "Aldo", "rank": 1, "cause": "expedition", "zone": "ashfall_reaches", "battle_order": "seed:2"})
	_seeded("seed:3", "ashfall_reaches", "victory", [mara, wren, dunn], [], {"rescued": [dunn], "rescuers": [mara, wren]})
	var living: Dictionary = names.duplicate()
	var bond: Dictionary = Bonds.bond(_ledger, mara, living, BALANCE)
	assert_eq(bond["partner"], dunn, "Mara's partner is Dunn")
	var facts: Dictionary = Lines.greeting_facts(bond, Bonds.dream(_ledger, dunn), mara, Ledger.known_names(_ledger, living))
	assert_eq(facts["kinds"], _kinds(["saved", "debt"]))
	var said: Dictionary = {}
	for pick: int in Lines.candidates(facts).size():
		said[Lines.line(facts, pick)] = true
	assert_gte(said.size(), 10, str(said.keys()))


## ---- helpers

## Two battles where Bea revives Ada: a bond, and Ada's dream owes Bea.
func _saves() -> void:
	for _index: int in 2:
		_battle([A, B], "victory", {"moments": [_moment("revived", A, B)]})


## What partner says to body, from a local-ledger bond and the partner's dream.
func _facts(body: String, partner: String) -> Dictionary:
	var bond: Dictionary = Bonds.bond(_ledger, body, {A: true, B: true}, BALANCE)
	assert_eq(bond.get("partner", ""), partner, "%s's partner" % body)
	return Lines.greeting_facts(bond, Bonds.dream(_ledger, partner), body, NAMES)


## The first line of hero_id's greeting with the start at 0 and no debt: the old greeting.
func _first(hero_id: String, living: Dictionary) -> String:
	var facts: Dictionary = Lines.greeting_facts(Bonds.bond(_ledger, hero_id, living, BALANCE), {}, hero_id, NAMES)
	facts["start"] = 0
	return Lines.line(facts, 0)


func _kinds(kinds: Array) -> Array[String]:
	var typed: Array[String] = []
	typed.assign(kinds)
	return typed


func _battle(team: Array, result: String, extra: Dictionary = {}) -> void:
	var fields: Dictionary = {"order": "order:%d" % _ledger.size(), "zone": ZONE, "team": team, "result": result, "moments": []}
	fields.merge(extra, true)
	_record("battle", fields)


## A battle record as ig-m6o.2.1's seed_save.gd writes it.
func _seeded(order: String, zone: String, result: String, team: Array, moments: Array, extra: Dictionary = {}) -> void:
	var fields: Dictionary = {"order": order, "zone": zone, "battle_kind": "rescue" if extra.has("rescued") else "expedition", "result": result, "team": team, "kills": {}, "moments": moments}
	fields.merge(extra)
	_record("battle", fields)


func _record(kind: String, fields: Dictionary) -> void:
	Ledger.append(_ledger, _ledger.size() + 1, 0, kind, fields)


func _moment(what: String, hero: String, by: String) -> Dictionary:
	return {"tick": 10, "what": what, "hero": hero, "by": by}
