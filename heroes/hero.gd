class_name Hero
extends RefCounted
## Runtime hero instance.
##
## Runtime state points at shared HeroDefinition data by def_id per ARCHITECTURE.md rule 3.

const RANK_NAMES: PackedStringArray = ["F", "D", "C", "B", "A", "S", "SS", "SSS"]
const NO_ARCHETYPE_DEF_ID: StringName = &""

var hero_name: String
var rank: int
var def_id: StringName


func _init(p_name: String = "", p_rank: int = 0) -> void:
	hero_name = p_name
	rank = p_rank


func rank_label() -> String:
	return RANK_NAMES[clampi(rank, 0, RANK_NAMES.size() - 1)]


func to_dict() -> Dictionary:
	return {"name": hero_name, "rank": rank, "def_id": str(def_id)}


static func from_dict(data: Dictionary) -> Hero:
	var hero := Hero.new(str(data.get("name", "?")), int(data.get("rank", 0)))
	# Phase 1 saves predate archetypes; empty preserves that fact for later assignment.
	hero.def_id = StringName(str(data.get("def_id", NO_ARCHETYPE_DEF_ID)))
	return hero
