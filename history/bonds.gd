class_name Bonds
extends RefCounted

## Bonds and dreams (SYSTEMS.md § Bonds and dreams): pure static readers over the Ledger, like its
## History list. Nothing is saved (DECISIONS.md 2026-09-24 "Bonds stay derived"). The reader keeps
## no state: GameSession holds an index_state() beside the ledger and folds each record in and out.

const SAVES: Array[String] = ["revived", "carried"]
## The fact kinds in the order a record scores them, and the tally keys that count them.
const FACTS: Array[String] = ["hard", "saves", "rescues", "deaths"]
## How each dream ends, in one line: {who} and {zone} are its names, {count} the fade's battles.
const ENDINGS: Dictionary = {
	"life_debt:paid": "Dream fulfilled: repaid {who} at {zone}.",
	"life_debt:lost": "Dream lost: {who} died before the debt was paid.",
	"watch_over:fulfilled": "Dream fulfilled: {who} rose in rank.",
	"watch_over:lost": "Dream lost: {who} died before rising.",
	"carry_name:fulfilled": "Dream fulfilled: {who}'s name carried at {zone}.",
	"carry_name:lost": "Dream lost: {zone} took another friend.",
	"be_worthy:fulfilled": "Dream fulfilled: {who}'s life was worth it.",
	"be_worthy:lost": "Dream lost: carried home before {who}'s life was repaid.",
	"be_worthy:faded": "Dream faded: {count} battles without a hard win.",
}
## How a save is told, by whoever saved and whoever was saved.
const SAVE_LINES: Dictionary = {
	"revived": "{by} revived {saved} at {zone}.",
	"carried": "{by} carried {saved} out at {zone}.",
	"rescued": "{by} rescued {saved} from {zone}.",
}
## The goals dream() reads when it is given no table.
const _SHIPPED: BalanceTable = preload("res://balance.tres")


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


## Every directed pair's tally: {hero_id: {other_id: tally}}, the tally as bond() returns it. A toward
## B and B toward A are separate entries: the same scoring, each with its own fact wording. It keeps
## every hero it saw, living or not; bond_from filters by living when asked. The dream is not in it.
static func index(ledger: Array[Dictionary], balance: BalanceTable) -> Dictionary:
	return index_state(ledger, balance)["pairs"]


## Every record of ledger folded in, oldest first, as one state for fold_in and fold_out to keep
## (DECISIONS.md 2026-09-24 "Bonds stay derived", item 5): {pairs, counts, dead, battles}. pairs is
## index(). counts is hero -> other -> one slot per fact kind in FACTS order, each [count, the latest
## record with it, its wording, the dead]. dead is battle order -> its died records, in fold order.
## battles is battle order -> its battle records. The rebuild and the fold share one set of rules, so
## a kept state's pairs equal a fresh one's. version counts the folds since the build that touched a
## tally, and touched is hero -> the version that last touched its pairs (ig-7sn.16), so a reader of
## pairs can re-read only those heroes; a build starts both at 0 and {}.
static func index_state(ledger: Array[Dictionary], balance: BalanceTable) -> Dictionary:
	var folded: Dictionary = {"pairs": {}, "counts": {}, "dead": {}, "battles": {}, "version": 0, "touched": {}}
	for record: Dictionary in ledger:
		_fold(folded, record)
	# One tally per pair at the end, not one per record.
	var pairs: Dictionary = folded["pairs"]
	var counts: Dictionary = folded["counts"]
	for hero_id: String in counts:
		var tallies: Dictionary = {}
		for other: String in counts[hero_id]:
			tallies[other] = _tally(other, counts[hero_id][other], balance)
		pairs[hero_id] = tallies
	return folded


## Folds one appended record, the newest of its list, into a kept index_state().
static func fold_in(folded: Dictionary, record: Dictionary, balance: BalanceTable) -> void:
	_retally(folded, _fold(folded, record), balance)


## Takes one evicted record out of a kept index_state(). False when it cannot, and the caller then
## rebuilds: a count left over whose latest record was this one (the one before is unknown), or a
## death whose battle is still in. Under today's eviction tiers neither happens: every scoring record
## is a non-routine battle, those go oldest first, and died records go only after every battle.
static func fold_out(folded: Dictionary, record: Dictionary, balance: BalanceTable) -> bool:
	var touched: Dictionary = {}
	match str(record.get("kind", "")):
		"battle":
			var order: String = str(record.get("order", ""))
			if not _unscore(folded["counts"], record, (folded["dead"] as Dictionary).get(order, []), touched):
				return false
			_drop(folded["battles"], order, record)
		"died":
			if record.has("battle_order"):
				var battle_order: String = str(record["battle_order"])
				if (folded["battles"] as Dictionary).has(battle_order):
					return false
				_drop(folded["dead"], battle_order, record)
	_retally(folded, touched, balance)
	return true


## Folds record in without tallying. Returns the heroes whose pairs it may have changed.
static func _fold(folded: Dictionary, record: Dictionary) -> Dictionary:
	match str(record.get("kind", "")):
		"battle":
			var order: String = str(record.get("order", ""))
			((folded["battles"] as Dictionary).get_or_add(order, []) as Array).append(record)
			return _score(folded["counts"], record, (folded["dead"] as Dictionary).get(order, []))
		"died":
			if record.has("battle_order"):
				return _witness(folded, record)
	return {}


## Counts one battle in as the latest record of its pairs' slots: each fact at most once per pair.
## dead is its order's died records so far (normally none: a hero dies after the battle that stranded
## it). Returns the heroes whose pairs it may have changed.
static func _score(counts: Dictionary, record: Dictionary, dead: Array) -> Dictionary:
	var routine: bool = Ledger.is_routine(record)
	# A routine victory with no death seen scores no fact, so it touches no tally.
	if routine and dead.is_empty():
		return {}
	var team: Dictionary = _id_set(record, "team")
	var rescued: Dictionary = _id_set(record, "rescued")
	var rescuers: Dictionary = _id_set(record, "rescuers")
	# Each kind in its own loop. Only a hero in the team or rescued scores; the other may be any hero
	# in the record.
	var ids: Array = team.keys()
	for hero_id: String in ids:
		var others: Dictionary = _others(counts, hero_id)
		for other: String in ids:
			if other == hero_id:
				continue
			if not routine:
				# The hottest line at the cap, so inline: the hard slot's wording is always "hard".
				var hard: Array = _slots(others, other)[0]
				hard[0] += 1
				hard[1] = record
			for died: Dictionary in dead:
				var id: String = str(died.get("hero", ""))
				if id != hero_id and id != other:
					_count(_slots(others, other)[3], record, "death", id)
					break
	var saves: Dictionary = _saves(record, team, rescued, rescuers)
	for hero_id: String in saves:
		for other: String in saves[hero_id]:
			_count(_slots(_others(counts, hero_id), other)[1], record, saves[hero_id][other], "")
	var rescues: Dictionary = _rescues(team, rescued, rescuers)
	for hero_id: String in rescues:
		for other: String in rescues[hero_id]:
			_count(_slots(_others(counts, hero_id), other)[2], record, "saved" if rescuers.has(hero_id) else "saved_by", "")
	return _heroes(team, rescued, rescuers)


## A died record of a battle order. For each battle of that order, its hero is a death seen together
## for every pair it is the first dead hero outside of; a pair with an earlier such death already
## counted that battle. The slot's fact moves only to a later battle than the one it holds.
static func _witness(folded: Dictionary, record: Dictionary) -> Dictionary:
	var order: String = str(record["battle_order"])
	var dead: Array = (folded["dead"] as Dictionary).get_or_add(order, [])
	var earlier: Array = dead.duplicate()
	dead.append(record)
	var died: String = str(record.get("hero", ""))
	var counts: Dictionary = folded["counts"]
	var touched: Dictionary = {}
	for battle: Dictionary in (folded["battles"] as Dictionary).get(order, []):
		var ids: Array = _id_set(battle, "team").keys()
		for hero_id: String in ids:
			touched[hero_id] = true
			if hero_id == died:
				continue
			for other: String in ids:
				if other == hero_id or other == died or _seen_dying(earlier, hero_id, other):
					continue
				var slot: Array = _slots(_others(counts, hero_id), other)[3]
				slot[0] += 1
				if slot[1] == null or int(battle.get("seq", 0)) > int((slot[1] as Dictionary).get("seq", 0)):
					slot[1] = battle
					slot[2] = "death"
					slot[3] = died
	return touched


## Takes out exactly what _score put in for record, its deaths read from dead as they stand. False
## when a count is left whose latest record is this one. touched gains the heroes it changed.
static func _unscore(counts: Dictionary, record: Dictionary, dead: Array, touched: Dictionary) -> bool:
	var routine: bool = Ledger.is_routine(record)
	if routine and dead.is_empty():
		return true
	var team: Dictionary = _id_set(record, "team")
	var rescued: Dictionary = _id_set(record, "rescued")
	var rescuers: Dictionary = _id_set(record, "rescuers")
	touched.merge(_heroes(team, rescued, rescuers))
	var ids: Array = team.keys()
	for hero_id: String in ids:
		for other: String in ids:
			if other == hero_id:
				continue
			if not routine and not _uncount(counts[hero_id][other][0], record):
				return false
			if _seen_dying(dead, hero_id, other) and not _uncount(counts[hero_id][other][3], record):
				return false
	var saves: Dictionary = _saves(record, team, rescued, rescuers)
	for hero_id: String in saves:
		for other: String in saves[hero_id]:
			if not _uncount(counts[hero_id][other][1], record):
				return false
	var rescues: Dictionary = _rescues(team, rescued, rescuers)
	for hero_id: String in rescues:
		for other: String in rescues[hero_id]:
			if not _uncount(counts[hero_id][other][2], record):
				return false
	return true


## Hero -> {other: "saved_by" or "saved"}: every pair record scores a save for, worded by the first
## save between them in it.
static func _saves(record: Dictionary, team: Dictionary, rescued: Dictionary, rescuers: Dictionary) -> Dictionary:
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
	var scored: Dictionary = {}
	for hero_id: String in saved_with:
		if not (team.has(hero_id) or rescued.has(hero_id)):
			continue
		var mine: Dictionary = saved_with[hero_id]
		for other: String in mine:
			if other != hero_id and (team.has(other) or rescued.has(other) or rescuers.has(other)):
				(scored.get_or_add(hero_id, {}) as Dictionary)[other] = mine[other]
	return scored


## A rescuer and a rescued hero, either way round, once per pair: hero -> {other: true}.
static func _rescues(team: Dictionary, rescued: Dictionary, rescuers: Dictionary) -> Dictionary:
	var rescues: Dictionary = {}
	for rescuer: String in rescuers:
		for saved: String in rescued:
			if rescuer != saved:
				if team.has(rescuer) or rescued.has(rescuer):
					(rescues.get_or_add(rescuer, {}) as Dictionary)[saved] = true
				(rescues.get_or_add(saved, {}) as Dictionary)[rescuer] = true
	return rescues


static func _heroes(team: Dictionary, rescued: Dictionary, rescuers: Dictionary) -> Dictionary:
	var heroes: Dictionary = team.duplicate()
	heroes.merge(rescued)
	heroes.merge(rescuers)
	return heroes


## Whether any of the died records is a hero other than the pair.
static func _seen_dying(dead: Array, hero_id: String, other: String) -> bool:
	for died: Dictionary in dead:
		var id: String = str(died.get("hero", ""))
		if id != hero_id and id != other:
			return true
	return false


## Removes record from lists[key], and the key once its list is empty.
static func _drop(lists: Dictionary, key: String, record: Dictionary) -> void:
	var list: Array = lists.get(key, [])
	list.erase(record)
	if list.is_empty():
		lists.erase(key)


## Retallies every counted pair between two touched heroes. A pair with no count left goes. Only the
## touched heroes' pairs change, so they are stamped with a new version.
static func _retally(folded: Dictionary, touched: Dictionary, balance: BalanceTable) -> void:
	if not touched.is_empty():
		folded["version"] += 1
		for hero_id: String in touched:
			folded["touched"][hero_id] = folded["version"]
	var counts: Dictionary = folded["counts"]
	var pairs: Dictionary = folded["pairs"]
	for hero_id: String in touched:
		var others: Dictionary = counts.get(hero_id, {})
		if others.is_empty():
			continue
		var tallies: Dictionary = pairs.get_or_add(hero_id, {})
		for other: String in touched:
			if not others.has(other):
				continue
			var slots: Array = others[other]
			if slots[0][0] + slots[1][0] + slots[2][0] + slots[3][0] == 0:
				others.erase(other)
				tallies.erase(other)
			else:
				tallies[other] = _tally(other, slots, balance)


static func _others(counts: Dictionary, hero_id: String) -> Dictionary:
	if not counts.has(hero_id):
		counts[hero_id] = {}
	return counts[hero_id]


## One pair's slots, one per kind in FACTS order.
static func _slots(others: Dictionary, other: String) -> Array:
	if not others.has(other):
		others[other] = [[0, null, "hard", ""], [0, null, "", ""], [0, null, "", ""], [0, null, "", ""]]
	return others[other]


static func _count(slot: Array, record: Dictionary, wording: String, dead: String) -> void:
	slot[0] += 1
	slot[1] = record
	slot[2] = wording
	slot[3] = dead


## One count of record out of slot. False when others are left and record was their latest.
static func _uncount(slot: Array, record: Dictionary) -> bool:
	slot[0] -= 1
	if slot[0] > 0:
		return int((slot[1] as Dictionary).get("seq", 0)) != int(record.get("seq", 0))
	slot[1] = null
	return true


## One pair's counted slots as the tally bond() returns. The strongest fact is the last one with the
## most points, as an oldest-first running best with >= keeps it: a later record wins a tie, and
## within one record the later kind in FACTS order does.
static func _tally(other: String, slots: Array, balance: BalanceTable) -> Dictionary:
	var points: Array[int] = [balance.bond_points_hard_battle, balance.bond_points_saved, balance.bond_points_rescued, balance.bond_points_death_witnessed]
	var tally: Dictionary = {"partner": other, "points": 0, "last_seq": 0}
	var best: int = -1
	var best_seq: int = 0
	for kind: int in FACTS.size():
		var slot: Array = slots[kind]
		tally[FACTS[kind]] = slot[0]
		if slot[0] == 0:
			continue
		tally["points"] += slot[0] * points[kind]
		var seq: int = int((slot[1] as Dictionary).get("seq", 0))
		tally["last_seq"] = maxi(tally["last_seq"], seq)
		if best < 0 or points[kind] > points[best] or points[kind] == points[best] and seq >= best_seq:
			best = kind
			best_seq = seq
	var record: Dictionary = slots[best][1]
	tally["fact"] = {"kind": slots[best][2], "points": points[best], "seq": best_seq, "zone": str(record.get("zone", "")), "dead": slots[best][3]}
	return tally


static func _ahead(tally: Dictionary, chosen: Dictionary) -> bool:
	if tally["points"] != chosen["points"]:
		return tally["points"] > chosen["points"]
	if tally["last_seq"] != chosen["last_seq"]:
		return tally["last_seq"] > chosen["last_seq"]
	return str(tally["partner"]) < str(chosen["partner"])


## hero_id's dream, read oldest first: {} before the first formative record, else the one dream the
## hero holds, {dream, state, ...}, dream naming its id (SYSTEMS.md § The dream catalogue):
## - life_debt: X saved the owner. open adds owed, what, zone, fights; paid adds zone; lost is X's death.
## - watch_over: the owner saved X. open adds who, what, zone, count (battles beside X since); X
##   ranking up is fulfilled, X's death lost.
## - carry_name: X died an expedition death the owner was there for, at zone. open adds who, zone,
##   count (victories at zone since); fulfilled at dream_name_victories, lost on a second such death there.
## - be_worthy: X was sacrificed for the owner. open adds who and count (hard victories since);
##   fulfilled at dream_worthy_hard_victories, lost when the owner is carried home in a rescue,
##   faded after dream_worthy_fade_battles battles in a row without a hard win.
## One dream is open at a time; the record that ends one never opens the next. balance is the
## table for the goals, the shipped one when null (hub.gd asks with two arguments).
## A battle naming hero_id in none of team, rescued and rescuers is skipped (ig-7sn.16): every
## dream reads only battles that name its owner, since a moment's hero and by are actors in its
## fight and team is every allied actor, downed or not (_record_battle). Dropping allies from team
## would break this. skip false reads every record: the exactness test's reference.
## The skip reads the three keys inline: three _array calls per record doubled the dream's cost.
static func dream(ledger: Array[Dictionary], hero_id: String, balance: BalanceTable = null, skip: bool = true) -> Dictionary:
	var rules: BalanceTable = balance if balance != null else _SHIPPED
	var current: Dictionary = {}
	var fought: Dictionary = {}
	for record: Dictionary in ledger:
		var kind: String = str(record.get("kind", ""))
		if kind == "battle":
			var team: Variant = record.get("team")
			if team is Array and (team as Array).has(hero_id):
				fought[str(record.get("order", ""))] = true
			elif skip:
				var rescued: Variant = record.get("rescued")
				var rescuers: Variant = record.get("rescuers")
				if not (rescued is Array and (rescued as Array).has(hero_id) or rescuers is Array and (rescuers as Array).has(hero_id)):
					continue
		if current.get("state", "") == "open":
			current = _advance(current, record, kind, hero_id, rules, fought)
		else:
			var opened: Dictionary = _open(record, kind, hero_id, fought)
			if not opened.is_empty():
				current = opened
	current.erase("quiet")
	return current


## The dream record opens for hero_id, or {}. A battle opens life_debt (the owner was saved) before
## watch_over (the owner saved someone); a died record opens carry_name or be_worthy, at most one.
static func _open(record: Dictionary, kind: String, hero_id: String, fought: Dictionary) -> Dictionary:
	var zone: String = str(record.get("zone", ""))
	if kind == "battle":
		var saved_by: Dictionary = _save(record, hero_id, "")
		if not saved_by.is_empty():
			return {"dream": "life_debt", "state": "open", "owed": saved_by["by"], "what": saved_by["what"], "zone": zone, "fights": 0}
		var saved: Dictionary = _saved(record, hero_id)
		if not saved.is_empty():
			return {"dream": "watch_over", "state": "open", "who": saved["who"], "what": saved["what"], "zone": zone, "count": 0}
	elif kind == "died" and str(record.get("hero", "")) != hero_id and not str(record.get("hero", "")).is_empty():
		if not zone.is_empty() and _witnessed(record, fought):
			return {"dream": "carry_name", "state": "open", "who": str(record["hero"]), "zone": zone, "count": 0}
		if str(record.get("cause", "")) == "sacrifice" and str(record.get("by", "")) == hero_id:
			return {"dream": "be_worthy", "state": "open", "who": str(record["hero"]), "count": 0, "quiet": 0}
	return {}


## current, an open dream, after record: the same dict counted on, or a new one that ends it.
static func _advance(current: Dictionary, record: Dictionary, kind: String, hero_id: String, rules: BalanceTable, fought: Dictionary) -> Dictionary:
	var dream_id: String = current["dream"]
	var who: String = str(current.get("who", current.get("owed", "")))
	var hero: String = str(record.get("hero", ""))
	var zone: String = str(record.get("zone", ""))
	var beside: bool = false
	var won: bool = false
	if kind == "battle":
		var team: Array = _array(record, "team")
		beside = team.has(hero_id) and team.has(who)
		won = team.has(hero_id) and str(record.get("result", "")) == "victory"
	match dream_id:
		"life_debt":
			if kind == "died" and hero == who:
				return {"dream": dream_id, "state": "lost", "owed": who}
			if kind == "battle" and not _save(record, who, hero_id).is_empty():
				return {"dream": dream_id, "state": "paid", "owed": who, "zone": zone}
			if beside:
				current["fights"] += 1
		"watch_over":
			if kind == "died" and hero == who:
				return {"dream": dream_id, "state": "lost", "who": who}
			if kind == "ranked_up" and hero == who:
				return {"dream": dream_id, "state": "fulfilled", "who": who}
			if beside:
				current["count"] += 1
		"carry_name":
			if won and zone == current["zone"]:
				current["count"] += 1
				if current["count"] >= rules.dream_name_victories:
					return {"dream": dream_id, "state": "fulfilled", "who": who, "zone": zone}
			elif kind == "died" and zone == current["zone"] and hero != hero_id and _witnessed(record, fought):
				return {"dream": dream_id, "state": "lost", "who": who, "zone": zone}
		"be_worthy":
			if kind == "battle" and _array(record, "rescued").has(hero_id):
				return {"dream": dream_id, "state": "lost", "who": who}
			if won and not Ledger.is_routine(record):
				current["count"] += 1
				current["quiet"] = 0
				if current["count"] >= rules.dream_worthy_hard_victories:
					return {"dream": dream_id, "state": "fulfilled", "who": who}
			elif kind == "battle" and _array(record, "team").has(hero_id):
				current["quiet"] += 1
				if current["quiet"] >= rules.dream_worthy_fade_battles:
					return {"dream": dream_id, "state": "faded", "who": who}
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


## Whom saver saved in record, and how: {who, what}, or {} for no one. The other side of _save: a
## rescue with saver among the rescuers saves the first hero rescued, else the first hero saver
## revived or carried.
static func _saved(record: Dictionary, saver: String) -> Dictionary:
	if _array(record, "rescuers").has(saver):
		for rescued: Variant in _array(record, "rescued"):
			if str(rescued) != saver:
				return {"who": str(rescued), "what": "rescued"}
	for raw_moment: Variant in _array(record, "moments"):
		var moment: Dictionary = raw_moment as Dictionary if raw_moment is Dictionary else {}
		var saved: String = str(moment.get("hero", ""))
		if str(moment.get("what", "")) in SAVES and str(moment.get("by", "")) == saver and not saved.is_empty() and not saved.begins_with("enemy:") and saved != saver:
			return {"who": saved, "what": str(moment["what"])}
	return {}


## Whether record, a died record, is an expedition death of a named hero in a battle the owner was in
## the team of, fought being the order ids of those battles read so far. A record with no hero (a
## legacy or hand-edited one) is nobody's death, so it neither opens nor ends carry_name.
static func _witnessed(record: Dictionary, fought: Dictionary) -> bool:
	var order: String = str(record.get("battle_order", ""))
	return str(record.get("cause", "")) == "expedition" and not str(record.get("hero", "")).is_empty() and not order.is_empty() and fought.has(order)


## "Closest to Mara: 4 hard fights, 1 rescue, 1 death seen together." names holds display names.
static func bond_line(found: Dictionary, names: Dictionary, away: bool) -> String:
	var parts: PackedStringArray = []
	for key: String in ["hard", "saves", "rescues", "deaths"]:
		var count: int = found[key]
		if count > 0:
			var noun: String = {"hard": "hard fight", "saves": "save", "rescues": "rescue", "deaths": "death"}[key]
			parts.append("%d %s%s%s" % [count, noun, "" if count == 1 else "s", " seen together" if key == "deaths" else ""])
	return "Closest to %s%s: %s." % [_name(found["partner"], names), " (away)" if away else "", ", ".join(parts)]


## The dream as detail lines: while it is open, a headline then three milestones (the opening done,
## the count at n/goal, the last one to do); once it has ended, one line.
static func dream_lines(found: Dictionary, hero_id: String, names: Dictionary, balance: BalanceTable) -> Array[String]:
	if found.is_empty():
		return []
	var dream_id: String = str(found.get("dream", ""))
	var who: String = _name(str(found.get("who", found.get("owed", ""))), names)
	var hero: String = _name(hero_id, names)
	var zone: String = Ledger.zone_name(str(found.get("zone", "")))
	if found["state"] != "open":
		var ending: String = str(ENDINGS.get("%s:%s" % [dream_id, found["state"]], ""))
		return [ending.format({"who": who, "zone": zone, "count": balance.dream_worthy_fade_battles})] if not ending.is_empty() else []
	match dream_id:
		"life_debt":
			var told: String = str(SAVE_LINES[found["what"]]).format({"by": who, "saved": hero, "zone": zone})
			return _milestones("Dream: repay %s." % who, told, "Fight beside %s again" % who, found["fights"], balance.dream_fight_beside_battles, "Save %s." % who)
		"watch_over":
			var told: String = str(SAVE_LINES[found["what"]]).format({"by": hero, "saved": who, "zone": zone})
			return _milestones("Dream: watch over %s." % who, told, "Fight beside %s again" % who, found["count"], balance.dream_fight_beside_battles, "See %s rank up." % who)
		"carry_name":
			return _milestones("Dream: carry %s's name." % who, "%s saw %s fall at %s." % [hero, who, zone], "Win at %s" % zone, found["count"], balance.dream_name_victories, "Carry %s's name." % who)
		"be_worthy":
			return _milestones("Dream: be worth %s's life." % who, "%s was given up for %s." % [who, hero], "Win hard fights", found["count"], balance.dream_worthy_hard_victories, "Repay %s's life." % who)
	return []


static func _milestones(headline: String, opened: String, counted: String, count: int, goal: int, last: String) -> Array[String]:
	var shown: int = mini(count, goal)
	return [
		headline,
		"  [x] %s" % opened,
		"  [%s] %s (%d/%d)." % ["x" if shown >= goal else " ", counted, shown, goal],
		"  [ ] %s" % last,
	]


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
