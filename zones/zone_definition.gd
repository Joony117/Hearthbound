class_name ZoneDefinition
extends Resource

const DEF_PATH_TEMPLATE: String = "res://zones/defs/%s.tres"

@export var zone_id: StringName = &""
@export var display_name: String = ""
@export var recommended_power: int = 0
@export var trash_wave_count: int = 0
@export var trash_wave_start_fraction: float = 0.0
@export var trash_wave_end_fraction: float = 0.0
@export var boss_fraction: float = 0.0
@export var loot_emphasis: String = ""
@export var stone_reward: int = 0
@export var xp_reward: int = 0
@export var loot_rank_min: int = 0
@export var loot_rank_max: int = 0
@export var unlock_condition: String = ""


static func definition_for(p_zone_id: StringName) -> ZoneDefinition:
	var path: String = DEF_PATH_TEMPLATE % str(p_zone_id)
	if not ResourceLoader.exists(path):
		push_error("Missing ZoneDefinition for zone_id '%s' at %s." % [p_zone_id, path])
		return null
	var definition: ZoneDefinition = ResourceLoader.load(path) as ZoneDefinition
	if definition == null:
		push_error("Resource for zone_id '%s' is not a ZoneDefinition: %s." % [p_zone_id, path])
	return definition
