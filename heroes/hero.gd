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
var level: int = 0
var xp: int = 0
var def_id: StringName
var resonance: int = 0
var taught_traits: Array[StringName] = []
var equipped: Dictionary[int, Item] = {}
var instance_id: String
var favorite: bool = false


func _init(p_name: String = "", p_rank: int = 0) -> void:
	hero_name = p_name
	rank = p_rank
	instance_id = Item.new_instance_id()


func rank_label(balance: BalanceTable) -> String:
	return balance.rank_names[clampi(rank, 0, balance.rank_names.size() - 1)]


static func level_for(hero: Hero, balance: BalanceTable) -> int:
	return clampi(
		hero.level,
		0,
		balance.level_caps[clampi(hero.rank, 0, balance.level_caps.size() - 1)],
	)


static func xp_to_next_level(level: int, balance: BalanceTable) -> int:
	return balance.xp_coefficient * (level + 1)


static func grant_xp(hero: Hero, amount: int, balance: BalanceTable) -> void:
	var level_cap: int = balance.level_caps[clampi(hero.rank, 0, balance.level_caps.size() - 1)]
	hero.xp += amount
	while hero.level < level_cap and hero.xp >= xp_to_next_level(hero.level, balance):
		hero.xp -= xp_to_next_level(hero.level, balance)
		hero.level += 1
	if hero.level >= level_cap:
		hero.xp = 0


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
			equip_pct[primary_stat] += Item.compute_stat_magnitude(item, equipment_definition, balance)
		else:
			var crit_pct: float = Item.compute_stat_magnitude(item, equipment_definition, balance)
			if primary_stat == EquipmentDefinition.PrimaryStat.CRIT_RATE:
				final_stats[STAT_CRIT_RATE] += crit_pct
			else:
				final_stats[STAT_CRIT_DMG] += crit_pct
	# SYSTEMS.md § Traits: non-crit traits join gear's additive accumulator; crit traits add flat.
	var traits: Array[TraitDefinition] = active_resonance_traits(hero, definition, balance)
	traits.append_array(active_taught_traits(hero, definition))
	for trait_definition: TraitDefinition in traits:
		if trait_definition.stat < EquipmentDefinition.PrimaryStat.CRIT_RATE:
			equip_pct[trait_definition.stat] += trait_definition.magnitude
		elif trait_definition.stat == EquipmentDefinition.PrimaryStat.CRIT_RATE:
			final_stats[STAT_CRIT_RATE] += trait_definition.magnitude
		else:
			final_stats[STAT_CRIT_DMG] += trait_definition.magnitude
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


static func compute_essence_yield(
	fodder: Hero,
	target: Hero,
	balance: BalanceTable,
	sanctum_level: int,
) -> int:
	var essence_yield: float = balance.essence_bases[
		clampi(fodder.rank, 0, balance.essence_bases.size() - 1)
	]
	# SYSTEMS.md "Sacrifice -> rank up": a fodder at its rank's cap yields double. Float division on
	# purpose - int division floors to 0 below the cap and 1 at it, which kills the whole bonus.
	var level_cap: int = maxi(balance.level_caps[clampi(fodder.rank, 0, balance.level_caps.size() - 1)], 1)
	essence_yield *= 1.0 + float(level_for(fodder, balance)) / float(level_cap)
	if fodder.def_id == target.def_id and fodder.def_id != NO_ARCHETYPE_DEF_ID:
		essence_yield *= 3.0
	return roundi(essence_yield * (1.0 + balance.sanctum_essence_yield_bonus * sanctum_level))


static func compute_rank_up_cost(hero: Hero, balance: BalanceTable) -> int:
	return balance.rank_up_essence_costs[
		clampi(hero.rank, 0, balance.rank_up_essence_costs.size() - 1)
	]


static func active_resonance_traits(hero: Hero, definition: HeroDefinition, balance: BalanceTable) -> Array[TraitDefinition]:
	assert(hero != null)
	assert(balance != null)
	if definition == null:
		push_error("Cannot get resonance traits for hero '%s' without a HeroDefinition." % hero.hero_name)
		return []
	var unlocked_count: int = 0
	for threshold: int in balance.resonance_trait_thresholds:
		if hero.resonance >= threshold:
			unlocked_count += 1
	return definition.resonance_trait_pool.slice(0, mini(unlocked_count, definition.resonance_trait_pool.size()))


static func active_taught_traits(hero: Hero, definition: HeroDefinition) -> Array[TraitDefinition]:
	assert(hero != null)
	if definition == null:
		push_error("Cannot get taught traits for hero '%s' without a HeroDefinition." % hero.hero_name)
		return []
	var active_traits: Array[TraitDefinition] = []
	for trait_id: StringName in hero.taught_traits:
		var matched_trait: TraitDefinition = null
		for trait_definition: TraitDefinition in definition.instructor_trait_pool:
			if trait_definition.id == trait_id:
				matched_trait = trait_definition
				break
		if matched_trait == null:
			push_error("Unknown taught trait '%s' for hero '%s'." % [trait_id, hero.hero_name])
			continue
		active_traits.append(matched_trait)
	return active_traits


static func grant_instructor_trait(
	hero: Hero,
	definition: HeroDefinition,
	highest_team_rank: int,
	balance: BalanceTable,
) -> void:
	assert(hero != null)
	assert(balance != null)
	if definition == null:
		push_error("Cannot grant taught trait to hero '%s' without a HeroDefinition." % hero.hero_name)
		return
	var rank_index: int = clampi(hero.rank, 0, balance.level_caps.size() - 1)
	if Hero.level_for(hero, balance) < balance.level_caps[rank_index]:
		return
	if highest_team_rank <= hero.rank:
		return
	if rank_index >= definition.instructor_trait_pool.size():
		return
	var trait_id: StringName = definition.instructor_trait_pool[rank_index].id
	if trait_id in hero.taught_traits:
		return
	hero.taught_traits.append(trait_id)


func to_dict() -> Dictionary:
	var taught_trait_ids: Array[String] = []
	for trait_id: StringName in taught_traits:
		taught_trait_ids.append(str(trait_id))
	taught_trait_ids.sort()
	var equipped_slots: Array[int] = []
	for slot: int in equipped:
		equipped_slots.append(slot)
	equipped_slots.sort()
	var equipped_entries: Array[Dictionary] = []
	for slot: int in equipped_slots:
		equipped_entries.append({"slot": slot, "item": equipped[slot].to_dict()})
	return {
		"instance_id": instance_id,
		"favorite": favorite,
		"name": hero_name,
		"rank": rank,
		"level": level,
		"xp": xp,
		"def_id": str(def_id),
		"resonance": resonance,
		"taught_traits": taught_trait_ids,
		"equipped": equipped_entries,
	}


static func from_dict(data: Dictionary) -> Hero:
	var hero := Hero.new(str(data.get("name", "?")), maxi(Item.int_field(data, "rank", 0, "hero"), 0))
	var raw_instance_id: Variant = data.get("instance_id")
	if raw_instance_id is String and not (raw_instance_id as String).is_empty():
		hero.instance_id = raw_instance_id as String
	elif raw_instance_id != null:
		push_error("Invalid hero instance_id: expected a non-empty String.")
	var raw_favorite: Variant = data.get("favorite")
	if raw_favorite is bool:
		hero.favorite = raw_favorite as bool
	elif raw_favorite != null:
		push_error("Invalid hero favorite: expected bool, got %s." % type_string(typeof(raw_favorite)))
	hero.level = maxi(Item.int_field(data, "level", 0, "hero"), 0)
	hero.xp = maxi(Item.int_field(data, "xp", 0, "hero"), 0)
	hero.resonance = maxi(Item.int_field(data, "resonance", 0, "hero"), 0)
	# Dictionary.get() does not replace an explicit null from a hand-edited or corrupt save.
	# Save-file fields remain Variant until their types are validated.
	var raw_taught_traits: Variant = data.get("taught_traits")
	if raw_taught_traits != null:
		if not raw_taught_traits is Array:
			push_error("Invalid hero taught_traits: expected Array, got %s." % type_string(typeof(raw_taught_traits)))
		else:
			for raw_trait_id: Variant in raw_taught_traits as Array:
				if not raw_trait_id is String:
					push_error("Invalid taught trait ID: expected String, got %s." % type_string(typeof(raw_trait_id)))
					continue
				var trait_id := StringName(raw_trait_id as String)
				# to_dict() cannot write a duplicate, so one here is a hand-edited or corrupt save.
				# Keeping it would apply the magnitude twice in compute_final_stats, silently.
				if trait_id in hero.taught_traits:
					push_error("Duplicate taught trait '%s'; keeping one." % trait_id)
					continue
				hero.taught_traits.append(trait_id)
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
