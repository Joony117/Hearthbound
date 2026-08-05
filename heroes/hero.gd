class_name Hero
extends RefCounted
## Runtime hero instance.
##
## Runtime state points at shared HeroDefinition data by def_id per ARCHITECTURE.md rule 3.

const NO_ARCHETYPE_DEF_ID: StringName = &""
const STAT_HP: StringName = &"hp"
const STAT_ATK: StringName = &"atk"
const STAT_DEF: StringName = &"def"
const STAT_SPD: StringName = &"spd"
const STAT_CRIT_RATE: StringName = &"crit_rate"
const STAT_CRIT_DMG: StringName = &"crit_dmg"
const STAT_NAMES: Array[StringName] = [STAT_HP, STAT_ATK, STAT_DEF, STAT_SPD, STAT_CRIT_RATE, STAT_CRIT_DMG]
const DEF_PATH_TEMPLATE: String = "res://heroes/defs/%s.tres"

var hero_name: String
var rank: int
var def_id: StringName
var equipped: Dictionary[int, Item] = {}


func _init(p_name: String = "", p_rank: int = 0) -> void:
	hero_name = p_name
	rank = p_rank


func rank_label(balance: BalanceTable) -> String:
	return balance.rank_names[clampi(rank, 0, balance.rank_names.size() - 1)]


static func definition_for(p_def_id: StringName) -> HeroDefinition:
	var path: String = DEF_PATH_TEMPLATE % str(p_def_id)
	if not ResourceLoader.exists(path):
		push_error("Missing HeroDefinition for def_id '%s' at %s." % [p_def_id, path])
		return null
	var definition: HeroDefinition = ResourceLoader.load(path) as HeroDefinition
	if definition == null:
		push_error("Resource for def_id '%s' is not a HeroDefinition: %s." % [p_def_id, path])
	return definition


static func compute_final_stats(
	hero: Hero,
	definition: HeroDefinition,
	balance: BalanceTable,
	level: int,
) -> Dictionary[StringName, float]:
	assert(hero != null)
	assert(balance != null)
	assert(level >= 0)
	assert(not balance.stat_multipliers.is_empty())
	assert(not balance.equip_pct_per_rank.is_empty())
	assert(not balance.equip_crit_pct_per_rank.is_empty())
	if definition == null:
		push_error("Cannot compute final stats for hero '%s' without a HeroDefinition." % hero.hero_name)
		return {}

	var multiplier := balance.stat_multipliers[
		clampi(hero.rank, 0, balance.stat_multipliers.size() - 1)
	]
	var final_stats: Dictionary[StringName, float] = {
		STAT_HP: (definition.base_hp + definition.hp_growth * level) * multiplier,
		STAT_ATK: (definition.base_atk + definition.atk_growth * level) * multiplier,
		STAT_DEF: (definition.base_def + definition.def_growth * level) * multiplier,
		STAT_SPD: (definition.base_spd + definition.spd_growth * level) * multiplier,
		STAT_CRIT_RATE: definition.crit_rate,
		STAT_CRIT_DMG: definition.crit_dmg,
	}
	# SYSTEMS.md "Primary stat magnitude": eight slots feed a per-stat equip_pct that sums before a
	# single multiply; necklace/ring add flat to the two crit stats and skip equip_pct entirely.
	# Indexed by PrimaryStat ordinal, which STAT_NAMES mirrors positionally - reordering either enum
	# routes gear to the wrong stat, and only tests/unit/test_equipment.gd would notice.
	var equip_pct: Array[float] = [0.0, 0.0, 0.0, 0.0]
	for item: Item in hero.equipped.values():
		var equipment_definition: EquipmentDefinition = Item.definition_for(item.def_id)
		if equipment_definition == null:
			continue
		var primary_stat: int = equipment_definition.primary_stat
		if primary_stat < EquipmentDefinition.PrimaryStat.CRIT_RATE:
			var pct_index: int = clampi(item.rank, 0, balance.equip_pct_per_rank.size() - 1)
			equip_pct[primary_stat] += balance.equip_pct_per_rank[pct_index]
		else:
			var crit_pct_index: int = clampi(item.rank, 0, balance.equip_crit_pct_per_rank.size() - 1)
			var crit_pct: float = balance.equip_crit_pct_per_rank[crit_pct_index]
			if primary_stat == EquipmentDefinition.PrimaryStat.CRIT_RATE:
				final_stats[STAT_CRIT_RATE] += crit_pct
			else:
				final_stats[STAT_CRIT_DMG] += crit_pct
	for index: int in equip_pct.size():
		final_stats[STAT_NAMES[index]] *= 1.0 + equip_pct[index]
	final_stats[STAT_CRIT_RATE] = minf(final_stats[STAT_CRIT_RATE], balance.equip_crit_rate_cap)
	return final_stats


static func compute_team_power(
	team: Array[Hero],
	definitions: Array[HeroDefinition],
	levels: Array[int],
	balance: BalanceTable,
) -> float:
	assert(team.size() == definitions.size())
	assert(team.size() == levels.size())

	var total := 0.0
	for index: int in team.size():
		var stats := compute_final_stats(team[index], definitions[index], balance, levels[index])
		total += stats[STAT_ATK] + stats[STAT_DEF] + stats[STAT_HP] / 10.0 + stats[STAT_SPD]
	return total


func to_dict() -> Dictionary:
	var equipped_slots: Array[int] = []
	for slot: int in equipped:
		equipped_slots.append(slot)
	equipped_slots.sort()
	var equipped_entries: Array[Dictionary] = []
	for slot: int in equipped_slots:
		equipped_entries.append({"slot": slot, "item": equipped[slot].to_dict()})
	return {
		"name": hero_name,
		"rank": rank,
		"def_id": str(def_id),
		"equipped": equipped_entries,
	}


static func from_dict(data: Dictionary) -> Hero:
	var hero := Hero.new(str(data.get("name", "?")), int(data.get("rank", 0)))
	if not data.has("def_id"):
		# Phase 1 saves predate archetypes; empty preserves that fact for later assignment.
		hero.def_id = NO_ARCHETYPE_DEF_ID
	else:
		# Save-file fields remain Variant until their types are validated.
		var raw_def_id: Variant = data["def_id"]
		if raw_def_id is String:
			hero.def_id = StringName(raw_def_id as String)
		else:
			push_error("Invalid hero def_id: expected String, got %s." % type_string(typeof(raw_def_id)))
			hero.def_id = NO_ARCHETYPE_DEF_ID

	# Dictionary.get() does not replace an explicit null from a hand-edited or corrupt save.
	# Save-file fields remain Variant until their types are validated.
	var raw_equipped: Variant = data.get("equipped")
	if raw_equipped == null:
		return hero
	if not raw_equipped is Array:
		push_error("Invalid hero equipped: expected Array, got %s." % type_string(typeof(raw_equipped)))
		return hero

	var equipped_entries: Array = raw_equipped as Array
	for raw_entry: Variant in equipped_entries:
		if not raw_entry is Dictionary:
			push_error("Invalid equipped entry: expected Dictionary, got %s." % type_string(typeof(raw_entry)))
			continue
		var entry: Dictionary = raw_entry as Dictionary
		# Save-file fields remain Variant until their types are validated.
		var raw_slot: Variant = entry.get("slot")
		var slot: int = -1
		if raw_slot is int:
			slot = raw_slot as int
		elif raw_slot is float:
			# JSON has no int type - a slot written as int decodes off disk as float.
			var float_slot: float = raw_slot as float
			if is_finite(float_slot) and float_slot == floorf(float_slot):
				slot = int(float_slot)
		if slot < 0 or slot >= EquipmentDefinition.Slot.size():
			push_error("Invalid equipped slot: expected an integer from 0 to %d, got '%s'." % [EquipmentDefinition.Slot.size() - 1, raw_slot])
			continue
		# Save-file fields remain Variant until their types are validated.
		var raw_item: Variant = entry.get("item")
		if not raw_item is Dictionary:
			push_error("Invalid equipped item for slot %d: expected Dictionary, got %s." % [slot, type_string(typeof(raw_item))])
			continue
		if hero.equipped.has(slot):
			push_error("Duplicate equipped slot %d; keeping the last entry." % slot)
		hero.equipped[slot] = Item.from_dict(raw_item as Dictionary)
	return hero
