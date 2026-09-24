class_name Bonds
extends RefCounted

## Bonds and dreams, slice 1 (SYSTEMS.md § Bonds and dreams, slice 1): pure static readers over the
## Ledger, like its History list. Nothing is saved and nothing outlives one read (DECISIONS.md
## 2026-09-24 "The Ledger", item 9 and "Rejected: saved tallies").
## ponytail: every read walks the whole ledger, so callers read on refresh only, never per frame.
## ig-m6o.2.2's derived-or-stored ADR settles whether that holds up.

const SAVES: Array[String] = ["revived", "carried"]
const NUMBER_WORDS: Array[String] = ["No", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Eleven", "Twelve"]


## hero_id's bond: the living hero (a key of living) with the most points, at or over
## bond_threshold. Ties go to the more recent last shared fact, then the lower instance_id. {} for
## none. Otherwise {partner, points, hard, saves, rescues, deaths, last_seq, fact}; fact is the
## strongest single fact {kind, points, seq, zone, dead}, kind "saved_by" (the partner saved or
## rescued hero_id), "saved" (the reverse), "death" or "hard".
static func bond(ledger: Array[Dictionary], hero_id: String, living: Dictionary, balance: BalanceTable) -> Dictionary:
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
		var team: Array = _array(record, "team")
		var rescued: Array = _array(record, "rescued")
		var rescuers: Array = _array(record, "rescuers")
		if not (team.has(hero_id) or rescued.has(hero_id)):
			continue
		var seq: int = int(record.get("seq", 0))
		var zone: String = str(record.get("zone", ""))
		var hard: bool = team.has(hero_id) and not Ledger.is_routine(record)
		var dead: Array = dead_by_order.get(str(record.get("order", "")), [])
		var saved_with: Dictionary = {}
		for raw_moment: Variant in _array(record, "moments"):
			var moment: Dictionary = raw_moment as Dictionary if raw_moment is Dictionary else {}
			if not str(moment.get("what", "")) in SAVES:
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
				# Oldest first, so an equal fact later on is the more recent one.
				if best.is_empty() or fact["points"] >= best["points"]:
					tally["fact"] = {"kind": fact["kind"], "points": fact["points"], "seq": seq, "zone": zone, "dead": fact.get("dead", "")}
	var chosen: Dictionary = {}
	for tally: Dictionary in tallies.values():
		if tally["points"] < balance.bond_threshold:
			continue
		if chosen.is_empty() or _ahead(tally, chosen):
			chosen = tally
	return chosen


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
