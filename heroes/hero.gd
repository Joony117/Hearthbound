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

var hero_name: String
var rank: int
var def_id: StringName


func _init(p_name: String = "", p_rank: int = 0) -> void:
	hero_name = p_name
	rank = p_rank


func rank_label(balance: BalanceTable) -> String:
	return balance.rank_names[clampi(rank, 0, balance.rank_names.size() - 1)]


static func compute_final_stats(
	hero: Hero,
	definition: HeroDefinition,
	balance: BalanceTable,
	level: int,
) -> Dictionary[StringName, float]:
	assert(hero != null)
	assert(definition != null)
	assert(balance != null)
	assert(level >= 0)
	assert(not balance.stat_multipliers.is_empty())

	var multiplier := balance.stat_multipliers[
		clampi(hero.rank, 0, balance.stat_multipliers.size() - 1)
	]
	return {
		STAT_HP: (definition.base_hp + definition.hp_growth * level) * multiplier,
		STAT_ATK: (definition.base_atk + definition.atk_growth * level) * multiplier,
		STAT_DEF: (definition.base_def + definition.def_growth * level) * multiplier,
		STAT_SPD: (definition.base_spd + definition.spd_growth * level) * multiplier,
		STAT_CRIT_RATE: definition.crit_rate,
		STAT_CRIT_DMG: definition.crit_dmg,
	}


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
	return {"name": hero_name, "rank": rank, "def_id": str(def_id)}


static func from_dict(data: Dictionary) -> Hero:
	var hero := Hero.new(str(data.get("name", "?")), int(data.get("rank", 0)))
	if not data.has("def_id"):
		# Phase 1 saves predate archetypes; empty preserves that fact for later assignment.
		hero.def_id = NO_ARCHETYPE_DEF_ID
		return hero
	# Save-file fields remain Variant until their types are validated.
	var raw_def_id: Variant = data["def_id"]
	if raw_def_id is String:
		hero.def_id = StringName(raw_def_id as String)
	else:
		push_error("Invalid hero def_id: expected String, got %s." % type_string(typeof(raw_def_id)))
		hero.def_id = NO_ARCHETYPE_DEF_ID
	return hero
