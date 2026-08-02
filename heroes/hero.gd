class_name Hero
extends RefCounted
## Runtime hero instance.
##
## Phase 1 has no HeroDefinition yet, so a name and a rank is all there is. Once P2-01 lands
## this holds a def_id pointing at a shared HeroDefinition, plus level, xp, and equipment.

const RANK_NAMES: PackedStringArray = ["F", "D", "C", "B", "A", "S", "SS", "SSS"]

var hero_name: String
var rank: int


func _init(p_name: String = "", p_rank: int = 0) -> void:
	hero_name = p_name
	rank = p_rank


func rank_label() -> String:
	return RANK_NAMES[clampi(rank, 0, RANK_NAMES.size() - 1)]


func to_dict() -> Dictionary:
	return {"name": hero_name, "rank": rank}


static func from_dict(data: Dictionary) -> Hero:
	return Hero.new(str(data.get("name", "?")), int(data.get("rank", 0)))
