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
	"met": ["name", "place"],
	"meal": ["name"],
	"rival": ["name"],
	"collaborator": ["name"],
}

var _ledger: Array[Dictionary] = []


func before_each() -> void:
	_ledger = []


func test_the_bank_fills_every_line_from_only_its_kinds_slots() -> void:
	var slots: Dictionary = _slots()
	assert_eq(Lines.BANK.keys().size(), slots.size())
	var slot := RegEx.create_from_string("\\{(\\w+)\\}")
	# The worst case for length: a 14-letter name, the longest zone name, the fallback dead name.
	var worst: Dictionary = {"name": "Maximilianusss", "place": Ledger.zone_name(ZONE), "dead": "a hero now forgotten", "count": "Twelve"}
	# A "met" line's place is a building's, so its worst case is the longest building name.
	var worst_met: Dictionary = worst.merged({"place": _longest_place()}, true)
	for kind: String in slots:
		var quirk: bool = kind.begins_with("quirk:")
		var lines: Array = Lines.BANK[kind]
		assert_gte(lines.size(), 3 if quirk else 5, kind)
		for text: String in lines:
			var used: Array[String] = []
			for found: RegExMatch in slot.search_all(text):
				used.append(found.get_string(1))
			# A quirk line may name no one: it is the partner's own habit.
			if not quirk:
				assert_false(used.is_empty(), "uses a slot: %s" % text)
			if kind in ["death", "carry_name", "be_worthy"]:
				assert_has(used, "dead", "a %s line names the dead hero: %s" % [kind, text])
			if kind == "carry_name":
				assert_has(used, "place", "a carry_name line names the place: %s" % text)
			for slot_name: String in used:
				assert_has(slots[kind], slot_name, "%s may use {%s}: %s" % [kind, slot_name, text])
			var filled: String = text.format(worst_met if kind == "met" else worst)
			assert_false(filled.contains("{"), filled)
			assert_lte(filled.length(), 72, filled)


func test_the_role_banks_hold_five_lines_that_name_only_the_other_hero() -> void:
	for kind: String in ["rival", "collaborator"]:
		assert_eq((Lines.BANK[kind] as Array).size(), 5, kind)
		for text: String in Lines.BANK[kind]:
			assert_string_contains(text, "{name}")
			assert_lte(text.format({"name": "Maximilianusss"}).length(), 72, text)


func test_a_meeting_reads_the_bank_of_the_kind_it_is_given_and_met_by_default() -> void:
	var record: Dictionary = {"seq": 9, "heroes": [A, B], "place": "Forge", "why": "neighbours"}
	assert_eq(Lines.meeting_facts(record, NAMES), Lines.meeting_facts(record, NAMES, "met"), "the default is the old call")
	assert_eq(Lines.meeting_facts(record, NAMES)["kinds"], _kinds(["met"]))
	for kind: String in ["rival", "collaborator"]:
		var facts: Dictionary = Lines.meeting_facts(record, NAMES, kind)
		assert_eq(facts["kinds"], _kinds([kind]))
		assert_true((Lines.BANK[kind] as Array).has(Lines.line(facts, 0).replace("Bea", "{name}")), "a %s line naming the second hero" % kind)
		assert_string_contains(Lines.line(facts, 0), "Bea")
	assert_eq(Lines.meeting_facts({"heroes": [A]}, NAMES, "rival"), {}, "not a pair: nothing, whatever the kind")


func test_a_role_adds_its_lines_after_the_bond_and_the_dream_and_before_the_quirks() -> void:
	_saves()
	var bond: Dictionary = Bonds.bond(_ledger, A, {A: true, B: true}, BALANCE)
	var dream: Dictionary = Bonds.dream(_ledger, B)
	var quirks: Array[StringName] = [&"hums"]
	var plain: Dictionary = Lines.greeting_facts(bond, dream, A, NAMES, quirks)
	assert_eq(Lines.greeting_facts(bond, dream, A, NAMES, quirks, _kinds([])), plain, "no role: the old call")
	var rival: Dictionary = Lines.greeting_facts(bond, dream, A, NAMES, quirks, _kinds(["rival"]))
	assert_eq(rival["kinds"], _kinds(["saved_by", "watch_over", "rival", "quirk:hums"]))
	assert_eq(Lines.candidates(rival).size(), Lines.candidates(plain).size() + 5)
	assert_eq(rival["slots"], plain["slots"], "a role adds no slot")
	assert_eq(rival["start"], plain["start"], "and moves no start")
	var said: Dictionary = {}
	for pick: int in Lines.candidates(rival).size():
		var text: String = Lines.line(rival, pick)
		assert_false(text.contains("{"), text)
		said[text] = true
	for text: String in Lines.BANK["rival"]:
		assert_true(said.has(text.format({"name": "Ada"})), "the partner may say: %s" % text)
	assert_eq(Lines.greeting_facts({}, {}, A, NAMES, quirks, _kinds(["rival"])), {}, "no bond, no words, even for a role")


func test_the_old_greetings_are_each_kinds_first_line() -> void:
	for _index: int in 2:
		_battle([A, B, C], "stranded", {"order": "order:%d" % _ledger.size(), "rescued": [B], "rescuers": [A]})
	_record("died", {"hero": C, "name": "Cal", "battle_order": "order:0"})
	var zone: String = Ledger.zone_name(ZONE)
	assert_eq(_first(A, {A: true, B: true}), "I still think about Cal.", "the death seen together (5) outranks the rescue A gave (2)")
	assert_eq(_first(B, {A: true, B: true}), "I'd come for you again. %s or anywhere." % zone, "B was rescued (5): the latest 5-point fact")
	_ledger = []
	for _index: int in 3:
		_battle([A, B, C], "stranded", {"order": "order:%d" % _ledger.size(), "rescued": [B], "rescuers": [A]})
	assert_eq(_first(A, {A: true, B: true}), "I haven't forgotten %s. I owe you." % zone, "A rescued B and nothing outranks it (3 x 3 = 9 toward B)")
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
	for kinds: Array in [["saved_by"], ["saved"], ["death"], ["hard"], ["saved", "debt"], ["watch_over"], ["carry_name"], ["be_worthy"], ["met"], ["meal"]]:
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


# ig-m6o.2.2.3: the partner's quirk speaks last, after the bond and the dream, and changes nothing else.
func test_the_partners_quirk_kind_comes_last_and_adds_its_three_lines() -> void:
	_saves()
	var bond: Dictionary = Bonds.bond(_ledger, A, {A: true, B: true}, BALANCE)
	var dream: Dictionary = Bonds.dream(_ledger, B)
	var plain: Dictionary = Lines.greeting_facts(bond, dream, A, NAMES)
	var quirky: Dictionary = Lines.greeting_facts(bond, dream, A, NAMES, [&"hums"])
	assert_eq(quirky["kinds"], _kinds(["saved_by", "watch_over", "quirk:hums"]), "the bond's kind first, the dream's, the quirk last")
	assert_eq(Lines.greeting_facts(bond, dream, A, NAMES, [] as Array[StringName]), plain, "no quirks passed: the old result")
	assert_eq(quirky["slots"], plain["slots"], "the slots are the bond's")
	assert_eq(quirky["own"], plain["own"], "a quirk adds no own entry")
	assert_eq(Lines.candidates(quirky).size(), Lines.candidates(plain).size() + 3)
	assert_eq(Lines.candidates(quirky).slice(-3), Lines.candidates({"kinds": _kinds(["quirk:hums"])}), "its 3 lines, after the rest")
	assert_eq(Lines.greeting_facts({}, {}, A, NAMES, [&"hums"]), {}, "no bond, no words, quirk or not")
	for pick: int in Lines.candidates(quirky).size():
		assert_false(Lines.line(quirky, pick).contains("{"), Lines.line(quirky, pick))


# ig-m6o.2.2.4: a meeting speaks the "met" kind. Its place is a building's, said as a place.
func test_place_name_says_each_hall_and_type_as_a_place_and_an_unknown_id_as_here() -> void:
	assert_eq(Lines.place_name("SummoningCircle"), "the Summoning Circle")
	assert_eq(Lines.place_name("Forge"), "the Forge")
	assert_eq(Lines.place_name("TrainingHall"), "the Training Hall")
	assert_eq(Lines.place_name("Sanctum"), "the Sanctum")
	assert_eq(Lines.place_name("Reliquary"), "the Reliquary")
	assert_eq(Lines.place_name("TownGate"), "the Town Gate")
	assert_eq(Lines.place_name("Apothecary"), "the Apothecary")
	assert_eq(Lines.place_name("House_3"), "the House")
	assert_eq(Lines.place_name("Lumbermill_12"), "the Lumbermill")
	assert_eq(Lines.place_name("Mine_1"), "the Mine")
	assert_eq(Lines.place_name("Farm_2"), "the Farm")
	for unknown: String in ["", "Nowhere", "House_0", "House_x", "House_01", "House"]:
		assert_eq(Lines.place_name(unknown), "here", "'%s' names no building" % unknown)


func test_a_bond_that_is_only_chats_speaks_the_met_kind_at_the_place_of_the_last_chat() -> void:
	for _index: int in 8:
		_record("encounter", {"heroes": [A, B], "place": "Forge", "why": "coworkers"})
	_record("encounter", {"heroes": [A, B], "place": "House_2", "why": "neighbours"})
	var bond: Dictionary = Bonds.bond(_ledger, A, {A: true, B: true}, BALANCE)
	assert_eq(bond["fact"]["kind"], "met")
	var facts: Dictionary = Lines.greeting_facts(bond, Bonds.dream(_ledger, B), A, NAMES)
	assert_eq(facts["kinds"], _kinds(["met"]), "no dream, no quirk: the bond's own kind")
	assert_eq(facts["slots"], {"name": "Ada", "place": "the House"}, "the place of the latest chat, not a zone")
	assert_eq(Lines.candidates(facts).size(), 5)
	for pick: int in 5:
		var said: String = Lines.line(facts, pick)
		assert_false(said.contains("{"), said)
		assert_false(said.contains(Ledger.zone_name(ZONE)), "a zone is not where they met: %s" % said)
	assert_true(Lines.line(facts, 0).contains("Ada") or Lines.line(facts, 2).contains("Ada"))
	# A record from another version with no place still speaks, "here".
	assert_eq(Lines.greeting_facts({"partner": B, "hard": 0, "fact": {"kind": "met", "zone": ""}}, {}, A, NAMES)["slots"]["place"], "here")


func test_meeting_facts_name_the_second_hero_and_the_place_and_start_at_the_seq() -> void:
	var record: Dictionary = {"seq": 41, "time": 0, "kind": "encounter", "heroes": [A, B], "place": "SummoningCircle", "why": "coworkers"}
	var facts: Dictionary = Lines.meeting_facts(record, NAMES)
	assert_eq(facts["kinds"], _kinds(["met"]))
	assert_eq(facts["slots"], {"name": "Bea", "place": "the Summoning Circle"}, "the first hero speaks to the second")
	assert_eq(facts["start"], 41)
	var lines: Dictionary = {}
	for pick: int in 5:
		var said: String = Lines.line(facts, pick)
		assert_false(said.contains("{"), said)
		lines[said] = true
	assert_eq(lines.size(), 5, "five different lines")
	var next: Dictionary = Lines.meeting_facts({"seq": 42, "heroes": [A, B], "place": "SummoningCircle"}, NAMES)
	assert_ne(Lines.line(facts, 0), Lines.line(next, 0), "the next meeting reads the next line")
	assert_eq(Lines.meeting_facts({"heroes": [A]}, NAMES), {}, "one hero")
	assert_eq(Lines.meeting_facts({"heroes": "ab"}, NAMES), {}, "not a list")
	assert_eq(Lines.meeting_facts({}, NAMES), {}, "no heroes")
	assert_eq(Lines.meeting_facts({"seq": 3, "heroes": [A, "hero:gone"]}, NAMES)["slots"]["name"], "a hero now forgotten")


# ig-m6o.2.2.5: a bond that is only meals speaks the "meal" kind, and its lines name no place.
func test_a_bond_that_is_only_meals_speaks_the_meal_kind() -> void:
	for _index: int in 8:
		_record("meal", {"diners": [A, B, C], "place": "House_2"})
	var bond: Dictionary = Bonds.bond(_ledger, A, {A: true, B: true, C: true}, BALANCE)
	assert_eq(bond["fact"]["kind"], "meal")
	var facts: Dictionary = Lines.greeting_facts(bond, Bonds.dream(_ledger, B), A, NAMES)
	assert_eq(facts["kinds"], _kinds(["meal"]), "no dream, no quirk: the bond's own kind")
	assert_eq(facts["slots"]["name"], "Ada")
	assert_eq(Lines.candidates(facts).size(), 5)
	for pick: int in 5:
		var said: String = Lines.line(facts, pick)
		assert_false(said.contains("{"), said)
		assert_false(said.contains("an unknown place"), "a meal line names no place: %s" % said)


func test_meal_facts_name_the_second_diner_and_start_at_the_seq() -> void:
	var record: Dictionary = {"seq": 41, "time": 0, "kind": "meal", "diners": [A, B, C], "place": "House_1"}
	var facts: Dictionary = Lines.meal_facts(record, NAMES)
	assert_eq(facts["kinds"], _kinds(["meal"]))
	assert_eq(facts["slots"], {"name": "Bea"}, "the first diner speaks to the second")
	assert_eq(facts["start"], 41)
	var lines: Dictionary = {}
	for pick: int in 5:
		var said: String = Lines.line(facts, pick)
		assert_false(said.contains("{"), said)
		lines[said] = true
	assert_eq(lines.size(), 5, "five different lines")
	var next: Dictionary = Lines.meal_facts({"seq": 42, "diners": [A, B]}, NAMES)
	assert_ne(Lines.line(facts, 0), Lines.line(next, 0), "the next meal reads the next line")
	assert_eq(Lines.meal_facts({"diners": [A]}, NAMES), {}, "one diner")
	assert_eq(Lines.meal_facts({"diners": "ab"}, NAMES), {}, "not a list")
	assert_eq(Lines.meal_facts({}, NAMES), {}, "no diners")
	assert_eq(Lines.meal_facts({"seq": 3, "diners": [A, "hero:gone"]}, NAMES)["slots"]["name"], "a hero now forgotten")


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
	assert_eq(facts["kinds"], _kinds(["death", "debt"]), "Aldo's fall (5) outranks the rescue Mara gave (2): it was 5 all before ig-m6o.2.2.6")
	var said: Dictionary = {}
	for pick: int in Lines.candidates(facts).size():
		said[Lines.line(facts, pick)] = true
	assert_gte(said.size(), 10, str(said.keys()))


## ---- helpers

## The longest place_name of any hall or building type, for the "met" lines' worst case.
func _longest_place() -> String:
	var longest: String = ""
	var ids: Array[String] = []
	for hall: StringName in TownRules.HALL_HEXES:
		ids.append(String(hall))
	for type: StringName in TownRules.TYPES:
		ids.append("%s_1" % type)
	for id: String in ids:
		var said: String = Lines.place_name(id)
		if said.length() > longest.length():
			longest = said
	return longest


## SLOTS plus every quirk kind (ig-m6o.2.2.3), which may use {name} and nothing else.
func _slots() -> Dictionary:
	var slots: Dictionary = SLOTS.duplicate()
	for quirk: StringName in Hero.QUIRKS:
		slots["quirk:%s" % quirk] = ["name"]
	return slots


## Four battles where Bea revives Ada: a bond each way (Ada 4 a fight, Bea 2), and Ada's dream owes Bea.
func _saves() -> void:
	for _index: int in 4:
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
