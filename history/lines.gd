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
## Then one "quirk:<id>" kind per Hero.QUIRKS id (ig-m6o.2.2.3), 3 lines each, at most {name}, and no
## {place} or {dead}: a quirk is the partner's own habit, not a fact of the bond.
## "met" (ig-m6o.2.2.4) is what a hero says to another when they meet, and what a partner whose bond is only
## chats says to the body: {name} and {place}, the place being one place_name gives ("the Forge", or "here"),
## so a line uses it after "near", "around" or "in". PROVISIONAL: the five lines are a first pass; settled by
## the owner reading them in play.
## "meal" (ig-m6o.2.2.5) is what the first hero at a table says to the second, and what a partner whose bond is only
## chats and meals says to the body when the last of them was a meal: {name} only, since a table's place is one of the
## Houses and a meal line does not name it. PROVISIONAL like "met".
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
	"met": [
		"Morning, {name}. Quiet around {place} today.",
		"{name}! I was just thinking of you, near {place}.",
		"Good to see you, {name}. Walk with me a moment?",
		"Nothing like a chat in {place}, {name}.",
		"{name}! Tell me the news from around {place}.",
	],
	"meal": [
		"Pass the bread, {name}. And leave me the crust.",
		"Good soup, {name}. Don't tell the cook I said so.",
		"Food tastes better with company. Sit by me, {name}.",
		"{name}, you've got crumbs on your chin. Other side.",
		"Save me a seat at the next meal, {name}.",
	],
	"quirk:hums": [
		"Was I humming again? Tell me if it grates, {name}.",
		"I hum when my hands are busy. Just ignore me.",
		"There's a tune stuck in my head. Want to hear it?",
	],
	"quirk:counts_steps": [
		"Four hundred steps from the well to here. I counted.",
		"Don't talk to me, {name}. I'm counting my steps.",
		"Counting steps helps me think. Twelve to the gate.",
	],
	"quirk:collects_pebbles": [
		"Look, {name}. I found this one by the road. A beauty.",
		"My pockets are full of pebbles again. Don't tell anyone.",
		"I'll keep the round ones. You can have the flat one.",
	],
	"quirk:names_weapon": [
		"My weapon has a name, {name}. I won't say it out loud.",
		"I named my weapon. Don't laugh, {name}. It listens.",
		"Ask my weapon's name, {name}. It likes the attention.",
	],
	"quirk:early_riser": [
		"Up before dawn again. The town is lovely and quiet then.",
		"You slept in, {name}. I've been up since before dawn.",
		"I watched the sun come up over the wall. Try it.",
	],
	"quirk:whittles": [
		"I whittled a little fox. Want it, {name}?",
		"Wood shavings in my pockets again. I can't stop whittling.",
		"Give me a stick and an hour and I'll give you a bird.",
	],
	"quirk:bad_puns": [
		"I'd tell you a pun about swords, but it's pointless.",
		"I tried a pun on the guards. They didn't stand for it.",
		"Don't groan, {name}. I'm only just warming up.",
	],
	"quirk:sweet_tooth": [
		"Got any honey cakes, {name}? Asking for a friend.",
		"I'd trade my best boots for one more honey cake.",
		"I owe the baker a great deal, {name}. Mostly cakes.",
	],
	"quirk:lucky_charm": [
		"I never go out without my lucky charm, {name}. Not once.",
		"This charm has never let me down. Not yet.",
		"Want to borrow my lucky charm? Just bring it back.",
	],
	"quirk:hates_wet_boots": [
		"Puddles. Why are there always puddles, {name}?",
		"Wet boots all day. I'd rather fight three goblins.",
		"Mind the mud, {name}. I only just dried my boots.",
	],
	"quirk:sketches": [
		"Hold still, {name}. I'm drawing you.",
		"I filled a page with faces today. Yours is on it.",
		"Don't move. There. That's your good side, {name}.",
	],
	"quirk:tidies": [
		"Someone left the barrels crooked. I straightened them.",
		"I can't leave a mess, {name}. It itches at me.",
		"Tidy hands, tidy head. That's what I always say.",
	],
	"quirk:cloud_names": [
		"See that cloud, {name}? That's Gerald. Long day for him.",
		"I named the clouds again. The big one is Old Mabel.",
		"Rain soon. Gerald is looking grey, {name}.",
	],
	"quirk:afraid_of_moths": [
		"Was that a moth? Tell me it wasn't a moth, {name}.",
		"I've faced worse than moths. I just don't like them.",
		"Moths follow lanterns. That's why I avoid lanterns.",
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
## them over slots), so a bond's {place} or {dead} never speaks for the dream's. quirks are the partner's
## (Hero.quirks); their kinds come last, and a quirk adds no own entry.
static func greeting_facts(bond: Dictionary, dream: Dictionary, body_id: String, names: Dictionary, quirks: Array[StringName] = []) -> Dictionary:
	if bond.is_empty():
		return {}
	var fact: Dictionary = bond["fact"]
	var kind: String = str(fact["kind"])
	var kinds: Array[String] = [kind]
	var slots: Dictionary = {"name": _name(body_id, names), "place": place_name(str(fact.get("place", ""))) if kind == "met" else Ledger.zone_name(str(fact["zone"]))}
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
	for quirk: StringName in quirks:
		kinds.append("quirk:%s" % quirk)
	var partner: String = str(bond["partner"])
	var facts: Dictionary = {"kinds": kinds, "slots": slots, "start": absi(("%s:%s" % [body_id, partner]).hash())}
	if not own.is_empty():
		facts["own"] = own
	return facts


## What one hero says to the other when they meet (ig-m6o.2.2.4), as facts for line(): the "met" kind, the
## second hero of the record named (the first speaks) and the place of the meeting. The start is the record's
## seq, so meeting after meeting reads the next line. {} for a record that names no two heroes.
static func meeting_facts(record: Dictionary, names: Dictionary) -> Dictionary:
	var heroes: Variant = record.get("heroes")
	if not heroes is Array or (heroes as Array).size() != 2:
		return {}
	var kinds: Array[String] = ["met"]
	return {"kinds": kinds, "slots": {"name": _name(str((heroes as Array)[1]), names), "place": place_name(str(record.get("place", "")))}, "start": int(record.get("seq", 0))}


## What the first diner of a table says to the second when a meal starts (ig-m6o.2.2.5), as facts for line(): the
## "meal" kind and the name of the record's second diner (the first, the lowest id, speaks). The start is the record's
## seq, so meal after meal reads the next line. {} for a record that names fewer than two diners.
static func meal_facts(record: Dictionary, names: Dictionary) -> Dictionary:
	var diners: Variant = record.get("diners")
	if not diners is Array or (diners as Array).size() < 2:
		return {}
	var kinds: Array[String] = ["meal"]
	return {"kinds": kinds, "slots": {"name": _name(str((diners as Array)[1]), names)}, "start": int(record.get("seq", 0))}


## A building's id as a place in a sentence: "the Forge" for a hall, "the House" for "House_3" and "here" for
## an id that names no building (a record written by another version, or none).
static func place_name(id: String) -> String:
	var building := StringName(id)
	var type: StringName = building if TownRules.is_hall(building) else TownRules.type_of(building)
	return "the %s" % String(type).capitalize() if type != &"" else "here"


static func _name(id: String, names: Dictionary) -> String:
	return str(names.get(id, "a hero now forgotten"))
