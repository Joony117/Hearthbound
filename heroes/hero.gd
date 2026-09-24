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
const NO_STATION: StringName = &""
const NO_HOME: StringName = &""
## Every profession a hero can have a passion for: the five halls in PROFESSIONS order, then the town
## workplaces (DECISIONS.md 2026-09-23, the town builder, item 12). The passion roll indexes this
## list, so reordering it changes every hero's passions.
const ALL_PROFESSIONS: Array[StringName] = [&"smithing", &"rites", &"drill", &"tracking", &"alchemy", &"woodcutting", &"mining", &"farming"]
## Hall profession -> the town building it works in (hub/town/town.tscn node names, a save id since
## DECISIONS.md 2026-09-23). Station validation reads it, so it holds the five halls only.
const PROFESSIONS: Dictionary[StringName, StringName] = {
	&"smithing": &"Forge",
	&"rites": &"Sanctum",
	&"drill": &"TrainingHall",
	&"tracking": &"Reliquary",
	&"alchemy": &"Apothecary",
}

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
## Born with two different ALL_PROFESSIONS: the ones this hero learns fastest and the only ones it
## can make masterwork in.
var passions: Array[StringName] = []
## Plain XP seconds per profession. The passion multiplier is applied when XP is earned, not here.
var profession_xp: Dictionary[StringName, float] = {}
## The town building this hero keeps (a PROFESSIONS value), or NO_STATION. It leaves with the hero,
## so permadeath needs no station cleanup (DECISIONS.md 2026-09-23 item 5).
var station: StringName = NO_STATION
## The placed House this hero lives in, or NO_HOME. A workplace job needs one (DECISIONS.md
## 2026-09-23, the town builder, item 5). Like station, it leaves with the hero.
var home: StringName = NO_HOME


func _init(p_name: String = "", p_rank: int = 0) -> void:
	hero_name = p_name
	rank = p_rank
	instance_id = Item.new_instance_id()
	passions = passions_for(instance_id)


## Stable per hero and uniform (instance_id is 16 random bytes); no summon RNG draw, so seeded
## summons do not shift.
static func passions_for(p_instance_id: String) -> Array[StringName]:
	var first: StringName = ALL_PROFESSIONS[posmod(p_instance_id.hash(), ALL_PROFESSIONS.size())]
	return [first, _second_passion(p_instance_id, first)]


## A second hash over the seven professions left after first.
static func _second_passion(p_instance_id: String, first: StringName) -> StringName:
	var others: Array[StringName] = []
	for profession: StringName in ALL_PROFESSIONS:
		if profession != first:
			others.append(profession)
	return others[posmod((p_instance_id + "#2").hash(), others.size())]


## Skill 0..profession_skill_cap from plain XP. The scale is the same for every hero and profession.
static func profession_skill(hero: Hero, profession: StringName, balance: BalanceTable) -> int:
	var minutes: float = hero.profession_xp.get(profession, 0.0) / 60.0
	var skill: int = 0
	while skill < balance.profession_skill_cap and minutes >= balance.profession_xp_minutes_per_level * (skill + 1):
		minutes -= balance.profession_xp_minutes_per_level * (skill + 1)
		skill += 1
	return skill


## Work in either passion earns passion_xp_multiplier times the XP; the saved total stays plain XP.
static func add_profession_xp(hero: Hero, profession: StringName, work_seconds: float, balance: BalanceTable) -> void:
	if not is_finite(work_seconds) or work_seconds < 0.0:
		push_error("add_profession_xp: bad work_seconds %s" % work_seconds)
		return
	var rate: float = balance.passion_xp_multiplier if profession in hero.passions else 1.0
	hero.profession_xp[profession] = hero.profession_xp.get(profession, 0.0) + work_seconds * rate


## The profession a building's keeper works in; &"" for a building that takes no keeper.
static func profession_for_building(building_id: StringName) -> StringName:
	for profession: StringName in PROFESSIONS:
		if PROFESSIONS[profession] == building_id:
			return profession
	return &""


static func is_staffable(building_id: StringName) -> bool:
	return building_id != NO_STATION and profession_for_building(building_id) != &""


## Only a born master makes masterwork: a passion, at the top skill. Both passions can be mastered.
static func is_profession_master(hero: Hero, profession: StringName, balance: BalanceTable) -> bool:
	return profession in hero.passions and profession_skill(hero, profession, balance) >= balance.profession_skill_cap


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
	var professions: Array = profession_xp.keys()
	professions.sort_custom(func(a: StringName, b: StringName) -> bool: return str(a) < str(b))
	var xp_by_profession: Dictionary = {}
	for profession: StringName in professions:
		xp_by_profession[str(profession)] = profession_xp[profession]
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
		"passions": passions.map(func(profession: StringName) -> String: return str(profession)),
		"profession_xp": xp_by_profession,
		"station": str(station),
		"home": str(home),
	}


## Additive keys (no SAVE_VERSION bump). A present "passions" loads as saved when valid, else
## re-derives from instance_id with a warning. Absent, a legacy "calling" (the build before passions)
## stays the first passion and the second comes from the hash, and with neither both come from
## instance_id, so a legacy hero keeps them across every load until it is saved. The next save writes
## "passions" and drops "calling".
static func _read_professions(hero: Hero, data: Dictionary) -> void:
	hero.passions = passions_for(hero.instance_id)
	# Save-file fields remain Variant until their types are validated.
	if data.has("passions"):
		var saved: Array[StringName] = _valid_passions(data["passions"])
		if saved.is_empty():
			push_warning("Invalid hero passions %s; re-derived." % str(data["passions"]))
		else:
			hero.passions = saved
	else:
		var raw_calling: Variant = data.get("calling")
		if raw_calling is String and PROFESSIONS.has(StringName(raw_calling as String)):
			var first := StringName(raw_calling as String)
			hero.passions = [first, _second_passion(hero.instance_id, first)]
		elif raw_calling != null:
			push_warning("Unknown hero calling '%s'; derived passions %s instead." % [raw_calling, str(hero.passions)])
	var raw_xp: Variant = data.get("profession_xp")
	if raw_xp == null:
		return
	if not raw_xp is Dictionary:
		push_error("Invalid hero profession_xp: expected Dictionary, got %s." % type_string(typeof(raw_xp)))
		return
	for raw_profession: Variant in raw_xp as Dictionary:
		var profession := StringName(str(raw_profession))
		if not profession in ALL_PROFESSIONS:
			push_warning("Unknown profession '%s' in hero profession_xp; dropped." % raw_profession)
			continue
		var raw_seconds: Variant = (raw_xp as Dictionary)[raw_profession]
		var seconds: float = 0.0
		if (raw_seconds is float or raw_seconds is int) and is_finite(float(raw_seconds)) and float(raw_seconds) >= 0.0:
			seconds = float(raw_seconds)
		else:
			push_error("Invalid %s XP: expected a non-negative number, got '%s'; loading 0." % [profession, raw_seconds])
		hero.profession_xp[profession] = seconds


## Two different known professions, or empty.
static func _valid_passions(raw: Variant) -> Array[StringName]:
	var result: Array[StringName] = []
	if not raw is Array or (raw as Array).size() != 2:
		return result
	for raw_profession: Variant in raw as Array:
		if not raw_profession is String or not ALL_PROFESSIONS.has(StringName(raw_profession as String)):
			result.clear()
			return result
		result.append(StringName(raw_profession as String))
	if result[0] == result[1]:
		result.clear()
	return result


## Missing means no station. A hall id or a placed workplace id's shape is kept here; whether that
## building exists and has room is GameSession.from_dict's check (it sees the roster and the town).
## Read on its own: a save may carry a station without any profession_xp.
static func _read_station(hero: Hero, data: Dictionary) -> void:
	var raw_station: Variant = data.get("station")
	if raw_station is String and (is_staffable(StringName(raw_station as String)) or TownRules.is_workplace_id(StringName(raw_station as String))):
		hero.station = StringName(raw_station as String)
	elif raw_station != null and not (raw_station is String and (raw_station as String).is_empty()):
		push_warning("Unknown station '%s' on hero %s; cleared." % [raw_station, hero.instance_id])
	# Additive key. Missing means no house; GameSession.from_dict checks the house exists and has room.
	var raw_home: Variant = data.get("home")
	if raw_home is String and TownRules.type_of(StringName(raw_home as String)) == TownRules.HOUSE:
		hero.home = StringName(raw_home as String)
	elif raw_home != null and not (raw_home is String and (raw_home as String).is_empty()):
		push_warning("Unknown home '%s' on hero %s; cleared." % [raw_home, hero.instance_id])


static func from_dict(data: Dictionary) -> Hero:
	var hero := Hero.new(str(data.get("name", "?")), maxi(Item.int_field(data, "rank", 0, "hero"), 0))
	var raw_instance_id: Variant = data.get("instance_id")
	if raw_instance_id is String and not (raw_instance_id as String).is_empty():
		hero.instance_id = raw_instance_id as String
	elif raw_instance_id != null:
		push_error("Invalid hero instance_id: expected a non-empty String.")
	_read_professions(hero, data)
	_read_station(hero, data)
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
