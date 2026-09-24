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
## Historical expedition count at death, retained for legacy saves and player history. Recovery
## timing uses recovery_created_at on GameSession's active recovery clock.
var turn_lost: int = 0
var recovery_created_at: float = 0.0
## The longest lifetime this cache has had (ig-wgj.10: a window never shrinks when the Tracking keeper
## leaves). GameSession raises it on every live tick; 0 until then, and in a save from before it.
var lifetime_seconds: float = 0.0


func _init(
	p_hero_name: String = "",
	p_zone_id: StringName = &"",
	p_turn_lost: int = 0,
	p_recovery_created_at: float = 0.0,
) -> void:
	hero_name = p_hero_name
	zone_id = p_zone_id
	turn_lost = p_turn_lost
	recovery_created_at = p_recovery_created_at


## A cache's and a rescue window's lifetime now. keeper_skill is the Reliquary keeper's Tracking
## (GameSession.keeper_skill); it stacks past the level cap.
static func lifetime_for(reliquary_level: int, keeper_skill: int, balance: BalanceTable) -> float:
	var level: int = clampi(reliquary_level, 0, balance.summoning_circle_level_cap)
	return balance.recovery_base_duration_seconds + balance.recovery_duration_seconds_per_level * (level + balance.keeper_skill_bonus_levels * keeper_skill)


## Uses the longest of the cache's own lifetime and the live one, so it never shrinks.
static func seconds_remaining(
	cache: LostCache,
	current_clock_seconds: float,
	reliquary_level: int,
	keeper_skill: int,
	balance: BalanceTable,
) -> float:
	var lifetime: float = maxf(cache.lifetime_seconds, lifetime_for(reliquary_level, keeper_skill, balance))
	return cache.recovery_created_at + lifetime - current_clock_seconds


static func compute_damage_chance(
	cache: LostCache,
	zone_power: int,
	team_power: float,
	current_clock_seconds: float,
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
	var active_minutes_elapsed: float = maxf(
		(current_clock_seconds - cache.recovery_created_at) / 60.0,
		0.0,
	)
	return clampf(
		BASE_DAMAGE_CHANCE
		+ DAMAGE_CHANCE_PER_TURN * active_minutes_elapsed
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
		"recovery_created_at": recovery_created_at,
		"lifetime_seconds": lifetime_seconds,
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
	cache.recovery_created_at = maxf(
		Item.float_field(data, "recovery_created_at", 0.0, "lost cache"),
		0.0,
	)
	# Additive (ig-wgj.10): absent in an older save, which reads the live lifetime until the next tick.
	cache.lifetime_seconds = maxf(Item.float_field(data, "lifetime_seconds", 0.0, "lost cache"), 0.0)
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
