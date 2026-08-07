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
var building_levels: Array[int] = [0, 0, 0, 0, 0]
var essence: int = 0
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
func salvage_item(item: Item, balance: BalanceTable) -> void:
	if not inventory.has(item):
		return
	inventory.erase(item)
	# item.rank arrives from an untrusted save and is never validated by Item.from_dict, so clamp
	# before indexing, same as Item.rank_label and Hero.compute_final_stats. assert() cannot guard
	# this - it is stripped in release, where a corrupt rank would crash after the erase (positive)
	# or credit the wrong rank (negative, since GDScript indexes arrays from the end).
	var enhance_level: int = clampi(item.enhance_level, 0, balance.forge_enhance_cap_max)
	parts[clampi(item.rank, 0, parts.size() - 1)] += 3 + enhance_level
	roster_changed.emit()


func enhance_item(item: Item, balance: BalanceTable) -> bool:
	if not inventory.has(item):
		return false
	var enhance_level: int = clampi(item.enhance_level, 0, balance.forge_enhance_cap_max)
	if enhance_level >= balance.forge_enhance_cap_max:
		return false
	var rank_index: int = clampi(item.rank, 0, parts.size() - 1)
	var cost: int = 2 + enhance_level
	if parts[rank_index] < cost:
		return false
	parts[rank_index] -= cost
	item.enhance_level = enhance_level + 1
	roster_changed.emit()
	return true


func upgrade_building(index: int, balance: BalanceTable) -> bool:
	if index < 0 or index >= building_levels.size():
		return false
	var level: int = clampi(building_levels[index], 0, balance.summoning_circle_level_cap)
	if level >= balance.summoning_circle_level_cap:
		return false
	var rank_index: int = clampi(level, 0, parts.size() - 1)
	var cost: int = 10 * (level + 2)
	if parts[rank_index] < cost:
		return false
	parts[rank_index] -= cost
	building_levels[index] = level + 1
	roster_changed.emit()
	return true


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


func sacrifice_hero(fodder: Hero, target: Hero, balance: BalanceTable) -> bool:
	if fodder == target or not roster.has(fodder) or not fodder.equipped.is_empty():
		return false
	essence += Hero.compute_essence_yield(fodder, target, balance)
	if fodder.def_id == target.def_id and fodder.def_id != Hero.NO_ARCHETYPE_DEF_ID:
		target.resonance += 1
	kill_hero(fodder, &"")
	return true


func rank_up_hero(hero: Hero, balance: BalanceTable) -> bool:
	if hero.rank >= balance.rank_up_essence_costs.size():
		return false
	var cost: int = Hero.compute_rank_up_cost(hero, balance)
	if essence < cost:
		return false
	essence -= cost
	hero.rank += 1
	roster_changed.emit()
	return true


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
		"building_levels": building_levels.duplicate(),
		"essence": essence,
		"lost_caches": lost_cache_entries,
		"cleared_zone_ids": cleared_entries,
	}


func from_dict(data: Dictionary) -> void:
	roster.clear()
	inventory.clear()
	parts.fill(0)
	building_levels.fill(0)
	essence = 0
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
	var saved_building_levels: Array = _array_field(data, "building_levels")
	for building_index: int in mini(saved_building_levels.size(), building_levels.size()):
		# Variant is required while validating untrusted save entries.
		var saved_level: Variant = saved_building_levels[building_index]
		var level: int = -1
		if saved_level is int:
			level = saved_level as int
		elif saved_level is float:
			var float_level: float = saved_level as float
			if is_finite(float_level) and float_level == floorf(float_level):
				level = int(float_level)
		if level < 0:
			push_error("Invalid building level at index %d: expected a non-negative integer, got '%s'." % [building_index, saved_level])
			continue
		building_levels[building_index] = level
	essence = maxi(Item.int_field(data, "essence", 0, "game session"), 0)
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
