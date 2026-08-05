extends Node
## Persistent player profile. Autoload.
##
## Exists only because the profile must outlive scene changes (menu -> hub -> arena -> hub).
## That is not a licence to grow into a GameManager: game *rules* live in plain functions
## that take what they need as arguments. See docs/ARCHITECTURE.md and docs/CODING_RULES.md.

signal roster_changed

var roster: Array[Hero] = []
var inventory: Array[Item] = []
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


func mark_zone_cleared(zone_id: StringName) -> void:
	assert(zone_id != &"")
	if cleared_zone_ids.has(zone_id):
		return
	cleared_zone_ids[zone_id] = true
	roster_changed.emit()


## The single place a hero leaves the roster. See docs/ARCHITECTURE.md rule 8 - permadeath
## reachable from more than one call site is how this game rots.
func kill_hero(hero: Hero) -> void:
	roster.erase(hero)
	roster_changed.emit()


func to_dict() -> Dictionary:
	var entries: Array[Dictionary] = []
	for hero: Hero in roster:
		entries.append(hero.to_dict())
	var inventory_entries: Array[Dictionary] = []
	for item: Item in inventory:
		inventory_entries.append(item.to_dict())
	var cleared_entries: Array[String] = []
	for zone_id: StringName in cleared_zone_ids:
		cleared_entries.append(str(zone_id))
	cleared_entries.sort()
	return {
		"roster": entries,
		"inventory": inventory_entries,
		"cleared_zone_ids": cleared_entries,
	}


func from_dict(data: Dictionary) -> void:
	roster.clear()
	inventory.clear()
	cleared_zone_ids.clear()
	for entry: Variant in _array_field(data, "roster"):
		if entry is Dictionary:
			roster.append(Hero.from_dict(entry))
	for entry: Variant in _array_field(data, "inventory"):
		if entry is Dictionary:
			inventory.append(Item.from_dict(entry))
	for zone_id: Variant in _array_field(data, "cleared_zone_ids"):
		if zone_id is String:
			cleared_zone_ids[StringName(zone_id as String)] = true
	roster_changed.emit()


## Dictionary.get()'s default only applies to a *missing* key, so an explicit "roster": null
## in a hand-edited or corrupt save reaches the loop as Nil and errors out. Coerce here rather
## than at each call site - all three fields have the same untrusted shape.
static func _array_field(data: Dictionary, key: String) -> Array:
	# Variant is required while validating untrusted save entries.
	var value: Variant = data.get(key)
	return value if value is Array else []
