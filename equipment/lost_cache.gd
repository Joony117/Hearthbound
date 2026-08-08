class_name LostCache
extends RefCounted
## Gear left behind when a hero dies during an expedition.

const BASE_DECAY_TURNS: int = 15
const BASE_DAMAGE_CHANCE: float = 0.15
const DAMAGE_CHANCE_PER_TURN: float = 0.03
const POWER_DEFICIT_COEFFICIENT: float = 0.2
const MAX_POWER_DEFICIT_PENALTY: float = 0.2

var hero_name: String
var zone_id: StringName
var items: Array[Item] = []
## GameSession.turns at the moment of death. A turn is one resolved expedition; the cache's
## deadline is turn_lost + 15 + 5 * reliquary_level, evaluated at the recovery attempt rather
## than frozen here, so a Reliquary upgrade extends caches that already exist (docs/SYSTEMS.md,
## Turns).
var turn_lost: int = 0


func _init(p_hero_name: String = "", p_zone_id: StringName = &"", p_turn_lost: int = 0) -> void:
	hero_name = p_hero_name
	zone_id = p_zone_id
	turn_lost = p_turn_lost


static func turns_remaining(
	cache: LostCache,
	current_turn: int,
	reliquary_level: int,
	balance: BalanceTable,
) -> int:
	var level: int = clampi(reliquary_level, 0, balance.summoning_circle_level_cap)
	return cache.turn_lost + BASE_DECAY_TURNS + balance.reliquary_decay_turns_bonus * level - current_turn


static func compute_damage_chance(
	cache: LostCache,
	zone_power: int,
	team_power: float,
	current_turn: int,
	reliquary_level: int,
	balance: BalanceTable,
) -> float:
	assert(team_power > 0.0)
	var level: int = clampi(reliquary_level, 0, balance.summoning_circle_level_cap)
	var power_ratio: float = float(zone_power) / team_power
	var power_deficit_penalty: float = clampf(
		POWER_DEFICIT_COEFFICIENT * (power_ratio - 1.0),
		0.0,
		MAX_POWER_DEFICIT_PENALTY,
	)
	var turns_elapsed: int = current_turn - cache.turn_lost
	return clampf(
		BASE_DAMAGE_CHANCE
		+ DAMAGE_CHANCE_PER_TURN * turns_elapsed
		+ power_deficit_penalty
		- balance.reliquary_damage_chance_reduction * level,
		0.0,
		1.0,
	)


func to_dict() -> Dictionary:
	var item_entries: Array[Dictionary] = []
	for item: Item in items:
		item_entries.append(item.to_dict())
	return {
		"hero_name": hero_name,
		"zone_id": str(zone_id),
		"items": item_entries,
		"turn_lost": turn_lost,
	}


static func from_dict(data: Dictionary) -> LostCache:
	var cache := LostCache.new()
	# Save-file fields remain Variant until their types are validated.
	var raw_hero_name: Variant = data.get("hero_name")
	if raw_hero_name is String:
		cache.hero_name = raw_hero_name as String
	else:
		push_error("Invalid lost cache hero_name: expected String, got %s." % type_string(typeof(raw_hero_name)))
	# Save-file fields remain Variant until their types are validated.
	var raw_zone_id: Variant = data.get("zone_id")
	if raw_zone_id is String:
		cache.zone_id = StringName(raw_zone_id as String)
	else:
		push_error("Invalid lost cache zone_id: expected String, got %s." % type_string(typeof(raw_zone_id)))
	# Decoded ahead of items because a malformed items array returns early below, and a cache that
	# lost its gear to a bad save should still know when it was created.
	cache.turn_lost = maxi(Item.int_field(data, "turn_lost", 0, "lost cache"), 0)
	# Save-file fields remain Variant until their types are validated.
	var raw_items: Variant = data.get("items")
	if not raw_items is Array:
		push_error("Invalid lost cache items: expected Array, got %s." % type_string(typeof(raw_items)))
		return cache
	for raw_item: Variant in raw_items as Array:
		if raw_item is Dictionary:
			cache.items.append(Item.from_dict(raw_item as Dictionary))
		else:
			push_error("Invalid lost cache item: expected Dictionary, got %s." % type_string(typeof(raw_item)))
	return cache
