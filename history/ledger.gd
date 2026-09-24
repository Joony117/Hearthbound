class_name Ledger
extends RefCounted

## The Ledger's rules (DECISIONS.md 2026-09-24 "The Ledger"): pure static functions over the list
## GameSession owns. GameSession's mutators are the only callers of append().

## Eviction tiers, first evicted first (item 8). A routine battle is tier 0.
const TIER_BY_KIND: Dictionary = {"battle": 1, "ranked_up": 2, "summoned": 3, "died": 4}
const RESULT_TEXT: Dictionary = {
	"victory": "Won a battle at %s",
	"retreated": "Retreated from %s",
	"stranded": "Stranded at %s",
	"timeout": "Ran out of time at %s",
}


## Appends {seq, time, kind, ...fields}, then evicts over the cap. Returns the next seq.
static func append(ledger: Array[Dictionary], next_seq: int, time: int, kind: String, fields: Dictionary, max_records: int) -> int:
	var record: Dictionary = {"seq": next_seq, "time": time, "kind": kind}
	record.merge(fields)
	ledger.append(record)
	while ledger.size() > max_records:
		ledger.remove_at(_eviction_index(ledger))
	return next_seq + 1


## Oldest record of the lowest tier present.
static func _eviction_index(ledger: Array[Dictionary]) -> int:
	var best_index: int = 0
	var best_tier: int = _tier(ledger[0])
	for index: int in range(1, ledger.size()):
		var tier: int = _tier(ledger[index])
		if tier < best_tier:
			best_index = index
			best_tier = tier
	return best_index


static func _tier(record: Dictionary) -> int:
	if is_routine(record):
		return 0
	return int(TIER_BY_KIND.get(str(record.get("kind", "")), 1))


## A victory battle with no moments and no rescued heroes.
static func is_routine(record: Dictionary) -> bool:
	return (
		str(record.get("kind", "")) == "battle"
		and str(record.get("result", "")) == "victory"
		and _array(record, "moments").is_empty()
		and _array(record, "rescued").is_empty()
	)


## Every record that names hero_id, oldest first.
static func records_for_hero(ledger: Array[Dictionary], hero_id: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for record: Dictionary in ledger:
		if str(record.get("hero", "")) == hero_id or _array(record, "team").has(hero_id) or _array(record, "rescued").has(hero_id):
			found.append(record)
	return found


## The hero-detail History list, newest first, at most max_lines. Routine victories in a row at
## one zone collapse into one line. names maps hero ids to display names; the ledger's own
## summoned/died records fill the gaps.
static func history_lines(ledger: Array[Dictionary], hero_id: String, names: Dictionary, rank_names: PackedStringArray, max_lines: int) -> Array[String]:
	var all_names: Dictionary = {}
	for record: Dictionary in ledger:
		if record.has("name"):
			all_names[str(record.get("hero", ""))] = str(record.get("name"))
	all_names.merge(names, true)
	var records: Array[Dictionary] = records_for_hero(ledger, hero_id)
	var lines: Array[String] = []
	var routine_zone: String = ""
	var routine_count: int = 0
	var arrived: bool = false
	for index: int in range(records.size() - 1, -1, -1):
		var record: Dictionary = records[index]
		var kind: String = str(record.get("kind", ""))
		arrived = arrived or kind == "summoned"
		if is_routine(record) and _array(record, "team").has(hero_id) and str(record.get("zone", "")) == routine_zone:
			routine_count += 1
			lines[lines.size() - 1] = "Won %d battles at %s." % [routine_count, _zone_name(routine_zone)]
			continue
		if lines.size() >= max_lines:
			break
		routine_zone = str(record.get("zone", "")) if is_routine(record) and _array(record, "team").has(hero_id) else ""
		routine_count = 1
		lines.append(_line(record, hero_id, all_names, rank_names))
	if not arrived and lines.size() < max_lines:
		lines.append("Arrived before the records begin.")
	return lines


static func _line(record: Dictionary, hero_id: String, names: Dictionary, rank_names: PackedStringArray) -> String:
	match str(record.get("kind", "")):
		"summoned":
			return "Summoned at %s rank." % _rank(record.get("rank"), rank_names)
		"ranked_up":
			return "Ranked up from %s to %s." % [_rank(record.get("from"), rank_names), _rank(record.get("to"), rank_names)]
		"died":
			match str(record.get("cause", "")):
				"sacrifice":
					return "Given up as Essence to %s." % _who(str(record.get("by", "")), names)
				"starvation":
					return "Starved."
			return "Died at %s." % _zone_name(str(record.get("zone", "")))
		"battle":
			return _battle_line(record, hero_id, names)
	return "%s." % str(record.get("kind", "Something")).capitalize()


static func _battle_line(record: Dictionary, hero_id: String, names: Dictionary) -> String:
	var zone: String = _zone_name(str(record.get("zone", "")))
	var rescued: Array = _array(record, "rescued")
	var rescuers: Array = _array(record, "rescuers")
	if rescued.has(hero_id):
		return "Rescued from %s by %s." % [zone, _who_list(rescuers, names)] if not rescuers.is_empty() else "Rescued from %s." % zone
	var parts: Array[String] = []
	if rescuers.has(hero_id) and not rescued.is_empty():
		parts.append("Rescued %s at %s" % [_who_list(rescued, names), zone])
	elif not rescued.is_empty():
		parts.append("Was there when %s %s rescued at %s" % [_who_list(rescued, names), "was" if rescued.size() == 1 else "were", zone])
	else:
		parts.append(str(RESULT_TEXT.get(str(record.get("result", "")), "Fought at %s")) % zone)
	for raw_moment: Variant in _array(record, "moments"):
		if not raw_moment is Dictionary:
			continue
		var moment: Dictionary = raw_moment as Dictionary
		var what: String = str(moment.get("what", ""))
		var by: String = str(moment.get("by", ""))
		if str(moment.get("hero", "")) == hero_id:
			parts.append("%s by %s" % [{"downed": "downed", "revived": "revived", "carried": "carried out"}.get(what, what), _who(by, names)])
		elif by == hero_id and what != "downed":
			parts.append("%s %s" % [{"revived": "revived", "carried": "carried out"}.get(what, what), _who(str(moment.get("hero", "")), names)])
	return "; ".join(parts) + "."


static func _who(id: String, names: Dictionary) -> String:
	if id.begins_with("enemy:"):
		return "an enemy %s" % id.trim_prefix("enemy:").capitalize()
	return str(names.get(id, "a hero now forgotten"))


static func _who_list(ids: Array, names: Dictionary) -> String:
	var parts: Array[String] = []
	for id: Variant in ids:
		parts.append(_who(str(id), names))
	return ", ".join(parts)


static func _zone_name(zone_id: String) -> String:
	var zone: ZoneDefinition = ZoneDefinition.definition_for(StringName(zone_id)) if not zone_id.is_empty() else null
	return zone.display_name if zone != null else "an unknown place"


static func _rank(raw_rank: Variant, rank_names: PackedStringArray) -> String:
	return rank_names[clampi(int(raw_rank), 0, rank_names.size() - 1)]


static func _array(record: Dictionary, key: String) -> Array:
	var value: Variant = record.get(key)
	return value as Array if value is Array else []


## JSON hands every number back as a float. Every Ledger number is a whole number, so a loaded
## record is turned back into ints; the next save then writes the same bytes.
static func normalized(value: Variant) -> Variant:
	if value is float:
		var number: float = value
		return int(number) if is_finite(number) and number == floorf(number) else number
	if value is Array:
		var out: Array = []
		for entry: Variant in value as Array:
			out.append(normalized(entry))
		return out
	if value is Dictionary:
		var out_dict: Dictionary = {}
		for key: Variant in value as Dictionary:
			out_dict[key] = normalized((value as Dictionary)[key])
		return out_dict
	return value
