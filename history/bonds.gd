class_name Bonds
extends RefCounted

## Bonds and dreams (SYSTEMS.md § Bonds and dreams): pure static readers over the Ledger, like its
## History list. Nothing is saved (DECISIONS.md 2026-09-24 "Bonds stay derived"). The reader keeps
## no state: whoever needs every hero's bond holds index() until the ledger changes (hub.gd).

const SAVES: Array[String] = ["revived", "carried"]
## The fact kinds in the order a record scores them, and the tally keys that count them.
const FACTS: Array[String] = ["hard", "saves", "rescues", "deaths"]
const NUMBER_WORDS: Array[String] = ["No", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Eleven", "Twelve"]


## hero_id's bond: the living hero (a key of living) with the most points, at or over
## bond_threshold. Ties go to the more recent last shared fact, then the lower instance_id. {} for
## none. Otherwise {partner, points, hard, saves, rescues, deaths, last_seq, fact}; fact is the
## strongest single fact {kind, points, seq, zone, dead}, kind "saved_by" (the partner saved or
## rescued hero_id), "saved" (the reverse), "death" or "hard". Builds a whole index for one answer:
## a caller asking for several heroes keeps index() and asks bond_from.
static func bond(ledger: Array[Dictionary], hero_id: String, living: Dictionary, balance: BalanceTable) -> Dictionary:
	return bond_from(index(ledger, balance), hero_id, living, balance)


## bond() answered from a kept index().
static func bond_from(pairs: Dictionary, hero_id: String, living: Dictionary, balance: BalanceTable) -> Dictionary:
	var chosen: Dictionary = {}
	for tally: Dictionary in (pairs.get(hero_id, {}) as Dictionary).values():
		if not living.has(tally["partner"]) or tally["points"] < balance.bond_threshold:
			continue
		if chosen.is_empty() or _ahead(tally, chosen):
			chosen = tally
	return chosen.duplicate(true)


## Every directed pair's tally in one oldest-first pass: {hero_id: {other_id: tally}}, the tally as
## bond() returns it. A toward B and B toward A are separate entries: the same scoring, each with
## its own fact wording. It keeps every hero it saw, living or not; bond_from filters by living
## when asked. The dream is not in it.
static func index(ledger: Array[Dictionary], balance: BalanceTable) -> Dictionary:
	var dead_by_order: Dictionary = {}
	for record: Dictionary in ledger:
		if str(record.get("kind", "")) == "died" and record.has("battle_order"):
			var order: String = str(record["battle_order"])
			if not dead_by_order.has(order):
				dead_by_order[order] = []
			(dead_by_order[order] as Array).append(str(record.get("hero", "")))
	# The pass only counts: hero -> other -> one slot per fact kind (FACTS order), each
	# [count, index of the last record with it, its wording, the dead]. _tally turns them into tallies.
	var counts: Dictionary = {}
	for at: int in ledger.size():
		var record: Dictionary = ledger[at]
		if str(record.get("kind", "")) != "battle":
			continue
		var routine: bool = Ledger.is_routine(record)
		var dead: Array = dead_by_order.get(str(record.get("order", "")), [])
		# A routine victory with no death seen scores no fact, so it touches no tally.
		if routine and dead.is_empty():
			continue
		var team: Dictionary = _id_set(record, "team")
		var rescued: Dictionary = _id_set(record, "rescued")
		var rescuers: Dictionary = _id_set(record, "rescuers")
		# Hero -> {other: "saved_by" or "saved"}: the first save between them in this record.
		var saved_with: Dictionary = {}
		for raw_moment: Variant in _array(record, "moments"):
			var moment: Dictionary = raw_moment as Dictionary if raw_moment is Dictionary else {}
			if not str(moment.get("what", "")) in SAVES:
				continue
			var saved: String = str(moment.get("hero", ""))
			var by: String = str(moment.get("by", ""))
			if not (saved_with.get_or_add(saved, {}) as Dictionary).has(by):
				saved_with[saved][by] = "saved_by"
			if by != saved and not (saved_with.get_or_add(by, {}) as Dictionary).has(saved):
				saved_with[by][saved] = "saved"
		# Each kind in its own loop, at most once per record for a pair. Only a hero in the team or
		# rescued scores; the other may be any hero in the record.
		var ids: Array = team.keys()
		for hero_id: String in ids:
			var others: Dictionary = _others(counts, hero_id)
			for other: String in ids:
				if other == hero_id:
					continue
				var slots: Array = _slots(others, other)
				if not routine:
					# The hottest line at the cap, so inline: the hard slot's wording is always "hard".
					var hard: Array = slots[0]
					hard[0] += 1
					hard[1] = at
				for id: String in dead:
					if id != hero_id and id != other:
						_count(slots[3], at, "death", id)
						break
		for hero_id: String in saved_with:
			if not (team.has(hero_id) or rescued.has(hero_id)):
				continue
			var mine: Dictionary = saved_with[hero_id]
			for other: String in mine:
				if other != hero_id and (team.has(other) or rescued.has(other) or rescuers.has(other)):
					_count(_slots(_others(counts, hero_id), other)[1], at, mine[other], "")
		# A rescuer and a rescued hero, either way round, once per pair.
		var rescues: Dictionary = {}
		for rescuer: String in rescuers:
			for saved: String in rescued:
				if rescuer != saved:
					if team.has(rescuer) or rescued.has(rescuer):
						(rescues.get_or_add(rescuer, {}) as Dictionary)[saved] = true
					(rescues.get_or_add(saved, {}) as Dictionary)[rescuer] = true
		for hero_id: String in rescues:
			for other: String in rescues[hero_id]:
				_count(_slots(_others(counts, hero_id), other)[2], at, "saved" if rescuers.has(hero_id) else "saved_by", "")
	var pairs: Dictionary = {}
	for hero_id: String in counts:
		var tallies: Dictionary = {}
		for other: String in counts[hero_id]:
			tallies[other] = _tally(other, counts[hero_id][other], ledger, balance)
		pairs[hero_id] = tallies
	return pairs


static func _others(counts: Dictionary, hero_id: String) -> Dictionary:
	if not counts.has(hero_id):
		counts[hero_id] = {}
	return counts[hero_id]


## One pair's slots, one per kind in FACTS order.
static func _slots(others: Dictionary, other: String) -> Array:
	if not others.has(other):
		others[other] = [[0, -1, "hard", ""], [0, -1, "", ""], [0, -1, "", ""], [0, -1, "", ""]]
	return others[other]


static func _count(slot: Array, at: int, wording: String, dead: String) -> void:
	slot[0] += 1
	slot[1] = at
	slot[2] = wording
	slot[3] = dead


## One pair's counted slots as the tally bond() returns. The strongest fact is the last one with the
## most points, as an oldest-first running best with >= keeps it: a later record wins a tie, and
## within one record the later kind in FACTS order does.
static func _tally(other: String, slots: Array, ledger: Array[Dictionary], balance: BalanceTable) -> Dictionary:
	var points: Array[int] = [balance.bond_points_hard_battle, balance.bond_points_saved, balance.bond_points_rescued, balance.bond_points_death_witnessed]
	var tally: Dictionary = {"partner": other, "points": 0, "last_seq": 0}
	var last: int = -1
	var best: int = -1
	for kind: int in FACTS.size():
		var slot: Array = slots[kind]
		tally[FACTS[kind]] = slot[0]
		if slot[0] == 0:
			continue
		tally["points"] += slot[0] * points[kind]
		last = maxi(last, slot[1])
		if best < 0 or points[kind] > points[best] or points[kind] == points[best] and slot[1] >= slots[best][1]:
			best = kind
	var record: Dictionary = ledger[slots[best][1]]
	tally["last_seq"] = int(ledger[last].get("seq", 0))
	tally["fact"] = {"kind": slots[best][2], "points": points[best], "seq": int(record.get("seq", 0)), "zone": str(record.get("zone", "")), "dead": slots[best][3]}
	return tally


static func _ahead(tally: Dictionary, chosen: Dictionary) -> bool:
	if tally["points"] != chosen["points"]:
		return tally["points"] > chosen["points"]
	if tally["last_seq"] != chosen["last_seq"]:
		return tally["last_seq"] > chosen["last_seq"]
	return str(tally["partner"]) < str(chosen["partner"])


## hero_id's dream, "repay a life debt", read oldest first. {} before the first save. Otherwise
## {state, owed, ...}: "open" adds what, zone and fights; "paid" adds zone; "lost" is the owed
## hero's death. Only one debt is open at a time; after it ends, the next save opens a new one.
static func dream(ledger: Array[Dictionary], hero_id: String) -> Dictionary:
	var current: Dictionary = {}
	for record: Dictionary in ledger:
		var kind: String = str(record.get("kind", ""))
		if current.get("state", "") == "open":
			var owed: String = current["owed"]
			if kind == "died" and str(record.get("hero", "")) == owed:
				current = {"state": "lost", "owed": owed}
			elif kind == "battle" and not _save(record, owed, hero_id).is_empty():
				current = {"state": "paid", "owed": owed, "zone": str(record.get("zone", ""))}
			elif kind == "battle" and _array(record, "team").has(hero_id) and _array(record, "team").has(owed):
				current["fights"] += 1
			continue
		if kind != "battle":
			continue
		var opened: Dictionary = _save(record, hero_id, "")
		if not opened.is_empty():
			current = {"state": "open", "owed": opened["by"], "what": opened["what"], "zone": str(record.get("zone", "")), "fights": 0}
	return current


## Who saved saved in record, and how: {by, what}, or {} for no one. by limits it to one saver.
## A rescue with rescuers is owed to the first listed; otherwise the first revive or carry by a hero.
static func _save(record: Dictionary, saved: String, by: String) -> Dictionary:
	var rescuers: Array = _array(record, "rescuers")
	if _array(record, "rescued").has(saved) and not rescuers.is_empty():
		for rescuer: Variant in rescuers:
			if str(rescuer) != saved and (by.is_empty() or str(rescuer) == by):
				return {"by": str(rescuer), "what": "rescued"}
	for raw_moment: Variant in _array(record, "moments"):
		var moment: Dictionary = raw_moment as Dictionary if raw_moment is Dictionary else {}
		var saver: String = str(moment.get("by", ""))
		if str(moment.get("what", "")) in SAVES and str(moment.get("hero", "")) == saved and not saver.is_empty() and not saver.begins_with("enemy:") and saver != saved and (by.is_empty() or saver == by):
			return {"by": saver, "what": str(moment["what"])}
	return {}


## "Closest to Mara: 4 hard fights, 1 rescue, 1 death seen together." names holds display names.
static func bond_line(found: Dictionary, names: Dictionary, away: bool) -> String:
	var parts: PackedStringArray = []
	for key: String in ["hard", "saves", "rescues", "deaths"]:
		var count: int = found[key]
		if count > 0:
			var noun: String = {"hard": "hard fight", "saves": "save", "rescues": "rescue", "deaths": "death"}[key]
			parts.append("%d %s%s%s" % [count, noun, "" if count == 1 else "s", " seen together" if key == "deaths" else ""])
	return "Closest to %s%s: %s." % [_name(found["partner"], names), " (away)" if away else "", ", ".join(parts)]


## The dream as detail lines: a headline, then three milestones while the debt is open.
static func dream_lines(found: Dictionary, hero_id: String, names: Dictionary, balance: BalanceTable) -> Array[String]:
	if found.is_empty():
		return []
	var owed: String = _name(found["owed"], names)
	match str(found["state"]):
		"paid":
			return ["Dream fulfilled: repaid %s at %s." % [owed, Ledger.zone_name(found["zone"])]]
		"lost":
			return ["Dream lost: %s died before the debt was paid." % owed]
	var hero: String = _name(hero_id, names)
	var zone: String = Ledger.zone_name(found["zone"])
	var opened: String = {
		"revived": "%s revived %s at %s." % [owed, hero, zone],
		"carried": "%s carried %s out at %s." % [owed, hero, zone],
		"rescued": "%s rescued %s from %s." % [owed, hero, zone],
	}[found["what"]]
	var goal: int = balance.dream_fight_beside_battles
	var fights: int = mini(int(found["fights"]), goal)
	return [
		"Dream: repay %s." % owed,
		"  [x] %s" % opened,
		"  [%s] Fight beside %s again (%d/%d)." % ["x" if fights >= goal else " ", owed, fights, goal],
		"  [ ] Save %s." % owed,
	]


## What the partner says on meeting hero_id in town, from their strongest shared fact.
static func greeting(found: Dictionary, names: Dictionary) -> String:
	var fact: Dictionary = found["fact"]
	match str(fact["kind"]):
		"saved_by":
			return "I'd come for you again. %s or anywhere." % Ledger.zone_name(fact["zone"])
		"saved":
			return "I haven't forgotten %s. I owe you." % Ledger.zone_name(fact["zone"])
		"death":
			return "I still think about %s." % _name(fact["dead"], names)
	var hard: int = found["hard"]
	return "%s hard fights, and we're both still standing." % (NUMBER_WORDS[hard] if hard < NUMBER_WORDS.size() else str(hard))


static func _name(id: String, names: Dictionary) -> String:
	return str(names.get(id, "a hero now forgotten"))


static func _array(record: Dictionary, key: String) -> Array:
	var value: Variant = record.get(key)
	return value as Array if value is Array else []


## The ids under key as a set of strings, in list order.
static func _id_set(record: Dictionary, key: String) -> Dictionary:
	var ids: Dictionary = {}
	for id: Variant in _array(record, key):
		ids[str(id)] = true
	return ids
