extends Node
## Persistent player profile. Autoload.
##
## Exists only because the profile must outlive scene changes (menu -> hub -> arena -> hub).
## That is not a licence to grow into a GameManager: game *rules* live in plain functions
## that take what they need as arguments. See docs/ARCHITECTURE.md and docs/CODING_RULES.md.

signal roster_changed

var roster: Array[Hero] = []
var inventory: Array[Item] = []
var parts: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]
var lost_caches: Array[LostCache] = []
var cleared_zone_ids: Dictionary[StringName, bool] = {}


func _ready() -> void:
	SaveService.load_game()
	# Connected after the load so from_dict()'s emit doesn't immediately write back.
	roster_changed.connect(SaveService.save)


func add_hero(hero: Hero) -> void:
	roster.append(hero)
	roster_changed.emit()


func add_item(item: Item) -> void:
	inventory.append(item)
	roster_changed.emit()


## An Item is in `inventory` or on exactly one hero, never both. That is enforced by the caller:
## the only equip path offers items from `inventory` alone, so an already-equipped one is never
## reachable. Calling this with an item from anywhere else duplicates it (docs/TASKS.md P2-05a).
func equip_item(hero: Hero, item: Item) -> void:
	var definition: EquipmentDefinition = Item.definition_for(item.def_id)
	if definition == null:
		return
	var slot: int = definition.slot
	inventory.erase(item)
	if hero.equipped.has(slot):
		inventory.append(hero.equipped[slot])
	hero.equipped[slot] = item
	roster_changed.emit()


func unequip_item(hero: Hero, slot: int) -> void:
	if not hero.equipped.has(slot):
		return
	inventory.append(hero.equipped[slot])
	hero.equipped.erase(slot)
	roster_changed.emit()


## Only the inventory UI offers items to this path, so equipped gear is unreachable.
func salvage_item(item: Item) -> void:
	if not inventory.has(item):
		return
	inventory.erase(item)
	# item.rank arrives from an untrusted save and is never validated by Item.from_dict, so clamp
	# before indexing, same as Item.rank_label and Hero.compute_final_stats. assert() cannot guard
	# this - it is stripped in release, where a corrupt rank would crash after the erase (positive)
	# or credit the wrong rank (negative, since GDScript indexes arrays from the end).
	parts[clampi(item.rank, 0, parts.size() - 1)] += 3
	roster_changed.emit()


func convert_parts(rank: int) -> bool:
	if rank < 0 or rank >= parts.size() - 1 or parts[rank] < 3:
		return false
	parts[rank] -= 3
	parts[rank + 1] += 1
	roster_changed.emit()
	return true


func mark_zone_cleared(zone_id: StringName) -> void:
	assert(zone_id != &"")
	if cleared_zone_ids.has(zone_id):
		return
	cleared_zone_ids[zone_id] = true
	roster_changed.emit()


## The single place a hero leaves the roster. See docs/ARCHITECTURE.md rule 8 - permadeath
## reachable from more than one call site is how this game rots.
func kill_hero(hero: Hero, zone_id: StringName) -> void:
	if not hero.equipped.is_empty():
		var cache := LostCache.new(hero.hero_name, zone_id)
		for item: Item in hero.equipped.values():
			cache.items.append(item)
		lost_caches.append(cache)
	hero.equipped.clear()
	roster.erase(hero)
	roster_changed.emit()


func to_dict() -> Dictionary:
	var entries: Array[Dictionary] = []
	for hero: Hero in roster:
		entries.append(hero.to_dict())
	var inventory_entries: Array[Dictionary] = []
	for item: Item in inventory:
		inventory_entries.append(item.to_dict())
	var lost_cache_entries: Array[Dictionary] = []
	for cache: LostCache in lost_caches:
		lost_cache_entries.append(cache.to_dict())
	var cleared_entries: Array[String] = []
	for zone_id: StringName in cleared_zone_ids:
		cleared_entries.append(str(zone_id))
	cleared_entries.sort()
	return {
		"roster": entries,
		"inventory": inventory_entries,
		"parts": parts.duplicate(),
		"lost_caches": lost_cache_entries,
		"cleared_zone_ids": cleared_entries,
	}


func from_dict(data: Dictionary) -> void:
	roster.clear()
	inventory.clear()
	parts.fill(0)
	lost_caches.clear()
	cleared_zone_ids.clear()
	for entry: Variant in _array_field(data, "roster"):
		if entry is Dictionary:
			roster.append(Hero.from_dict(entry))
	for entry: Variant in _array_field(data, "inventory"):
		if entry is Dictionary:
			inventory.append(Item.from_dict(entry))
	var saved_parts: Array = _array_field(data, "parts")
	for rank_index: int in mini(saved_parts.size(), parts.size()):
		# Variant is required while validating untrusted save entries.
		var saved_count: Variant = saved_parts[rank_index]
		var count: int = -1
		if saved_count is int:
			count = saved_count as int
		elif saved_count is float:
			var float_count: float = saved_count as float
			if is_finite(float_count) and float_count == floorf(float_count):
				count = int(float_count)
		if count < 0:
			push_error("Invalid parts count at rank %d: expected a non-negative integer, got '%s'." % [rank_index, saved_count])
			continue
		parts[rank_index] = count
	for entry: Variant in _array_field(data, "lost_caches"):
		if entry is Dictionary:
			lost_caches.append(LostCache.from_dict(entry))
	for zone_id: Variant in _array_field(data, "cleared_zone_ids"):
		if zone_id is String:
			cleared_zone_ids[StringName(zone_id as String)] = true
	roster_changed.emit()


## Dictionary.get()'s default only applies to a *missing* key, so an explicit "roster": null
## in a hand-edited or corrupt save reaches the loop as Nil and errors out. Coerce here rather
## than at each call site - all persisted collection fields have the same untrusted shape.
static func _array_field(data: Dictionary, key: String) -> Array:
	# Variant is required while validating untrusted save entries.
	var value: Variant = data.get(key)
	return value if value is Array else []
