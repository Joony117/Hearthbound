class_name LostCache
extends RefCounted
## Gear left behind when a hero dies during an expedition.

var hero_name: String
var zone_id: StringName
var items: Array[Item] = []
## GameSession.turns at the moment of death. A turn is one resolved expedition; the cache's
## deadline is turn_lost + 15 + 5 * reliquary_level, evaluated at the recovery attempt rather
## than frozen here, so a Reliquary upgrade extends caches that already exist (docs/SYSTEMS.md,
## Turns). Nothing reads this until P2-04f.
var turn_lost: int = 0


func _init(p_hero_name: String = "", p_zone_id: StringName = &"", p_turn_lost: int = 0) -> void:
	hero_name = p_hero_name
	zone_id = p_zone_id
	turn_lost = p_turn_lost


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
