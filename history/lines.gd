class_name Lines
extends RefCounted

## The line bank (ig-m6o.2.2.2): authored lines with slots for names and places, filled from Ledger
## facts. line() is the whole seam: facts in, one line out. Pure static, reads no GameSession, so
## TownView may call it. A line says only what its kind's facts hold.

const NUMBER_WORDS: Array[String] = ["No", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Eleven", "Twelve"]
## Spoken by the partner to the body. Each kind's lines use only the slots it always gives:
## saved_by, saved {name} {place}; death {name} {place} {dead}; hard {name} {place} {count}; debt
## {name}; watch_over {name} {place}; carry_name {name} {place} {dead}; be_worthy {name} {dead}. The
## first line of the first four kinds is the old one-line greeting, word for word. The last three
## are the partner's dream (ig-m6o.2.2.7): their {place} and {dead} are the dream's, not the bond's.
const BANK: Dictionary = {
	"saved_by": [
		"I'd come for you again. {place} or anywhere.",
		"Not after {place}. You don't fall alone, {name}.",
		"Whatever it takes, {name}. Same as {place}.",
		"You'd have done the same for me at {place}. I know it.",
		"Keep your head down out there, {name}.",
	],
	"saved": [
		"I haven't forgotten {place}. I owe you.",
		"You came for me at {place}, {name}. I won't forget it.",
		"If not for you at {place}, I wouldn't be here.",
		"Every day since {place} is a day you gave me.",
		"{name}! You're the one who got me through {place}.",
	],
	"death": [
		"I still think about {dead}.",
		"Some days I still look for {dead} in the crowd.",
		"We both saw what happened to {dead}. I'm glad you're here.",
		"{name}, {dead} would have liked this quiet.",
		"Do you ever dream about {dead}, {name}? I do.",
	],
	"hard": [
		"{count} hard fights, and we're both still standing.",
		"{count} hard fights, {name}. Who else would I trust?",
		"That last one at {place} was close. Glad you were there.",
		"Ready for the next one, {name}? I'm right behind you.",
		"{count} close calls together. Let's not make it one more.",
	],
	"debt": [
		"One day I'll pay you back, {name}. I mean it.",
		"Next time it's my turn to save you, {name}.",
		"I haven't evened the score yet, {name}. I will.",
		"Put me beside you out there, {name}. I owe you one.",
		"I keep count, {name}. I still owe you a life.",
	],
	"watch_over": [
		"I'll keep watch over you, {name}. Since {place}.",
		"You're not alone, {name}. Not after {place}.",
		"I mean to see you rise, {name}. I'll be there.",
		"Stay close, {name}. I'm not done watching your back.",
		"I got you through {place}. Now I want to see you rise.",
	],
	"carry_name": [
		"We go back to {place} for {dead}.",
		"{place} took {dead}. I mean to beat it.",
		"I carry {dead}'s name into {place}.",
		"Win at {place} with me. For {dead}.",
		"{dead} fell at {place}. I won't let that stand.",
	],
	"be_worthy": [
		"{dead} gave everything for me. I won't waste it.",
		"I think about {dead} every fight, {name}.",
		"I have to be worth {dead}'s life, {name}.",
		"{dead} paid for me to stand here, {name}.",
		"Win one hard fight for {dead}, {name}.",
	],
}


## The pick-th candidate for facts, wrapping, with its slots filled; "" for none. facts is
## {kinds: Array[String], slots: {slot: text}, start: int}; the candidates are every BANK line under
## each kind, in kinds order.
static func line(facts: Dictionary, pick: int) -> String:
	var lines: Array[String] = candidates(facts)
	if lines.is_empty():
		return ""
	var index: int = (int(facts.get("start", 0)) + pick) % lines.size()
	var slots: Dictionary = facts.get("slots", {})
	var own: Dictionary = (facts.get("own", {}) as Dictionary).get(_kind_at(facts, index), {})
	return lines[index].format(slots.merged(own, true))


## The kind whose lines hold candidates()' index-th line.
static func _kind_at(facts: Dictionary, index: int) -> String:
	for kind: Variant in facts.get("kinds", []):
		var count: int = (BANK.get(str(kind), []) as Array).size()
		if index < count:
			return str(kind)
		index -= count
	return ""


static func candidates(facts: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	for kind: Variant in facts.get("kinds", []):
		lines.append_array(BANK.get(str(kind), []))
	return lines


## What the partner says to the body, as facts: bond is the body's bond (Bonds.bond_from, toward the
## partner), dream the partner's (Bonds.dream), names hero ids to display names. {} for no bond.
## own holds, for the dream kinds only, the slots that kind's lines fill from the dream (line() lays
## them over slots), so a bond's {place} or {dead} never speaks for the dream's.
static func greeting_facts(bond: Dictionary, dream: Dictionary, body_id: String, names: Dictionary) -> Dictionary:
	if bond.is_empty():
		return {}
	var fact: Dictionary = bond["fact"]
	var kind: String = str(fact["kind"])
	var kinds: Array[String] = [kind]
	var slots: Dictionary = {"name": _name(body_id, names), "place": Ledger.zone_name(str(fact["zone"]))}
	if kind == "death":
		slots["dead"] = _name(str(fact["dead"]), names)
	elif kind == "hard":
		var hard: int = bond["hard"]
		slots["count"] = NUMBER_WORDS[hard] if hard < NUMBER_WORDS.size() else str(hard)
	var own: Dictionary = {}
	if dream.get("state", "") == "open":
		var dream_id: String = str(dream.get("dream", ""))
		var who: String = str(dream.get("who", ""))
		var place: String = Ledger.zone_name(str(dream.get("zone", "")))
		if dream_id == "life_debt" and dream.get("owed", "") == body_id:
			kinds.append("debt")
		elif dream_id == "watch_over" and who == body_id:
			kinds.append(dream_id)
			own[dream_id] = {"place": place}
		elif dream_id == "carry_name":
			kinds.append(dream_id)
			own[dream_id] = {"place": place, "dead": _name(who, names)}
		elif dream_id == "be_worthy":
			kinds.append(dream_id)
			own[dream_id] = {"dead": _name(who, names)}
	var partner: String = str(bond["partner"])
	var facts: Dictionary = {"kinds": kinds, "slots": slots, "start": absi(("%s:%s" % [body_id, partner]).hash())}
	if not own.is_empty():
		facts["own"] = own
	return facts


static func _name(id: String, names: Dictionary) -> String:
	return str(names.get(id, "a hero now forgotten"))
