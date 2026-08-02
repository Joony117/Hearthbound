class_name Hero
extends RefCounted
## Runtime hero instance.
##
## Runtime state points at shared HeroDefinition data by def_id per ARCHITECTURE.md rule 3.

const NO_ARCHETYPE_DEF_ID: StringName = &""

var hero_name: String
var rank: int
var def_id: StringName


func _init(p_name: String = "", p_rank: int = 0) -> void:
	hero_name = p_name
	rank = p_rank


func rank_label(balance: BalanceTable) -> String:
	return balance.rank_names[clampi(rank, 0, balance.rank_names.size() - 1)]


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
