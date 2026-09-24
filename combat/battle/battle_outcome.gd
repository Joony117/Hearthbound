class_name BattleOutcome
extends RefCounted

var status: String = "active"
var secured_hero_ids: Array[String] = []
var stranded_hero_ids: Array[String] = []
var enemy_dead_ids: Array[String] = []
var supplies_remaining: Dictionary = BattleState.supplies_from({})
var completed_waves: int = 0
var elapsed_seconds: float = 0.0
var moments: Array[Dictionary] = []
var moments_truncated: bool = false
var kills: Dictionary = {}


func to_dict() -> Dictionary:
	return {
		"status": status,
		"secured_hero_ids": secured_hero_ids.duplicate(),
		"stranded_hero_ids": stranded_hero_ids.duplicate(),
		"enemy_dead_ids": enemy_dead_ids.duplicate(),
		"supplies_remaining": supplies_remaining.duplicate(true),
		"completed_waves": completed_waves,
		"elapsed_seconds": elapsed_seconds,
		"moments": moments.duplicate(true),
		"moments_truncated": moments_truncated,
		"kills": kills.duplicate(),
	}

