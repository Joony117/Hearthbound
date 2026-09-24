extends Node
## Persistent player profile. Autoload.
##
## Exists only because the profile must outlive scene changes (menu -> hub -> arena -> hub).
## That is not a licence to grow into a GameManager: game *rules* live in plain functions
## that take what they need as arguments. See docs/ARCHITECTURE.md and docs/CODING_RULES.md.

signal roster_changed
signal expeditions_changed
signal battle_changed(order_id: String)

## A fresh save must afford at least one pull or the game is unplayable from boot: the roster
## starts empty and only a pull can fill it (docs/SYSTEMS.md, Summon Stones, 3).
const STARTING_STONES: int = 300
const RECOVERY_COMPLETED: StringName = &"completed"
const RECOVERY_NO_CACHE: StringName = &"no_cache"
const RECOVERY_INVALID_TEAM: StringName = &"invalid_team"
const RECOVERY_MISSING_ZONE: StringName = &"missing_zone"
const RECOVERY_INSUFFICIENT_POWER: StringName = &"insufficient_power"
const MAX_EXPEDITION_REPORTS: int = 50
const EXPEDITION_PULSE_SECONDS: float = 0.25
const PERIODIC_SAVE_SECONDS: float = 15.0
## embodied_hero_id when the player walks the town as no one (the overview camera).
const NO_BODY: String = ""
const KNOWN_ZONE_IDS: Array[String] = ["verdant_outskirts", "ashfall_reaches", "sundered_vault", "fallen_citadel", "frontier_march"]

var roster: Array[Hero] = []
var inventory: Array[Item] = []
var parts: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]
var building_levels: Array[int] = [0, 0, 0, 0, 0]
var essence: int = 0
var stones: int = STARTING_STONES
## Historical count of resolved expeditions. Recovery aging uses recovery_clock_seconds instead.
var turns: int = 0
var lost_caches: Array[LostCache] = []
var cleared_zone_ids: Dictionary[StringName, bool] = {}
var team_presets: Array[Dictionary] = []
var expedition_orders: Array[Dictionary] = []
var expedition_reports: Array[Dictionary] = []
var supplies: Dictionary = {"healing": 3, "revival": 1}
var stranded_incidents: Array[Dictionary] = []
var rescue_clock_seconds: float = 0.0
var recovery_clock_seconds: float = 0.0
var recovery_clock_paused: bool = false
## The roster hero the player walks the town as (ARCHITECTURE.md § The town is the interface). It
## can be geared and ranked up, but never sent out or sacrificed; NO_BODY when there is none.
var embodied_hero_id: String = NO_BODY
## Placed town buildings, {id: String, type: String, q: int, r: int}, in placing order. The halls are
## not in it yet (DECISIONS.md 2026-09-23, the town builder, items 1-3).
var town_buildings: Array[Dictionary] = []
## The shared stockpile. Wood is a float so a partial unit from the live tick survives a save.
var town_resources: Dictionary = {"wood": preload("res://balance.tres").town_start_wood}
## The n in the next placed id "<type>_<n>"; never reused.
var town_next_id: int = 1
var saved_at_unix: float = 0.0
var last_action_error: String = ""

var _save_deferred_depth: int = 0
var _notification_deferred_depth: int = 0
var _roster_notification_pending: bool = false
var _expeditions_notification_pending: bool = false
var _battle_notifications_pending: Dictionary[String, bool] = {}
var _expedition_pulse_accumulator: float = 0.0
var _periodic_save_accumulator: float = 0.0
var _paused_battle_orders: Dictionary[String, bool] = {}
var _checkpoint_save_failed: bool = false
var _checkpoint_error: String = ""
var _command_errors: Dictionary[String, String] = {}
var _pending_command_result: Dictionary = {}


func _ready() -> void:
	SaveService.load_game()
	# Connected after the load so from_dict()'s emit doesn't immediately write back.
	roster_changed.connect(SaveService.save)


func _process(delta: float) -> void:
	if SaveService.load_blocked:
		return
	_expedition_pulse_accumulator += delta
	if _expedition_pulse_accumulator < EXPEDITION_PULSE_SECONDS:
		return
	var elapsed_seconds: float = _expedition_pulse_accumulator
	_expedition_pulse_accumulator = 0.0
	if _checkpoint_save_failed:
		_periodic_save_accumulator += elapsed_seconds
		if _periodic_save_accumulator >= PERIODIC_SAVE_SECONDS:
			_periodic_save_accumulator = 0.0
			if SaveService.save():
				var resolved_error: String = _checkpoint_error
				_checkpoint_save_failed = false
				_checkpoint_error = ""
				if last_action_error == resolved_error:
					last_action_error = ""
				for order: Dictionary in expedition_orders:
					if str(order.get("backend", "legacy_v2")) == "battle_v1":
						_notify_battle_changed(str(order.get("id", "")))
				_notify_expeditions_changed()
		return
	tick_expeditions(elapsed_seconds)
	_periodic_save_accumulator += elapsed_seconds
	if _periodic_save_accumulator >= PERIODIC_SAVE_SECONDS:
		_periodic_save_accumulator = 0.0
		if not expedition_orders.is_empty() or not stranded_incidents.is_empty() or (not lost_caches.is_empty() and not recovery_clock_paused) or _lumbermill_workers_home() > 0:
			if not SaveService.save():
				_checkpoint_save_failed = true
				_checkpoint_error = SaveService.last_write_error
				last_action_error = _checkpoint_error
				for order: Dictionary in expedition_orders:
					if str(order.get("backend", "legacy_v2")) == "battle_v1":
						_notify_battle_changed(str(order.get("id", "")))
				_notify_expeditions_changed()


func is_save_deferred() -> bool:
	return _save_deferred_depth > 0


func _notify_roster_changed() -> void:
	if _notification_deferred_depth > 0:
		_roster_notification_pending = true
		return
	roster_changed.emit()


func _notify_expeditions_changed() -> void:
	if _notification_deferred_depth > 0:
		_expeditions_notification_pending = true
		return
	expeditions_changed.emit()


func _notify_battle_changed(order_id: String) -> void:
	if _notification_deferred_depth > 0:
		_battle_notifications_pending[order_id] = true
		return
	battle_changed.emit(order_id)


func _flush_deferred_notifications() -> void:
	# The transaction has already performed its one explicit save. Keep the UI refresh signal from
	# invoking the signal-connected autosave a second time.
	_save_deferred_depth += 1
	if _roster_notification_pending:
		_roster_notification_pending = false
		roster_changed.emit()
	if _expeditions_notification_pending:
		_expeditions_notification_pending = false
		expeditions_changed.emit()
	for order_id: String in _battle_notifications_pending:
		battle_changed.emit(order_id)
	_battle_notifications_pending.clear()
	_save_deferred_depth -= 1


func add_hero(hero: Hero) -> void:
	roster.append(hero)
	_notify_roster_changed()


func summon_hero(hero: Hero, balance: BalanceTable) -> bool:
	if stones < balance.summon_pull_cost:
		return false
	stones -= balance.summon_pull_cost
	roster.append(hero)
	_notify_roster_changed()
	return true


## Called once per expedition that actually runs. An expedition that never reaches a wave
## (OUTCOME_INVALID_TEAM) is not a turn - nothing happened.
func advance_turn(_balance: BalanceTable) -> void:
	turns += 1
	_notify_roster_changed()


func recover_cache(cache: LostCache, team: Array[Hero], balance: BalanceTable) -> StringName:
	last_action_error = ""
	if cache == null or not lost_caches.has(cache):
		return RECOVERY_NO_CACHE
	if team.is_empty() or team.size() > 5:
		return RECOVERY_INVALID_TEAM
	last_action_error = body_refusal(team)
	if not last_action_error.is_empty():
		return RECOVERY_INVALID_TEAM
	for hero: Hero in team:
		if is_hero_busy(hero):
			return RECOVERY_INVALID_TEAM
	var zone: ZoneDefinition = ZoneDefinition.definition_for(cache.zone_id)
	if zone == null:
		return RECOVERY_MISSING_ZONE
	var definitions: Array[HeroDefinition] = []
	var levels: Array[int] = []
	for hero: Hero in team:
		if not roster.has(hero):
			return RECOVERY_INVALID_TEAM
		var definition: HeroDefinition = Hero.definition_for(hero.def_id)
		if definition == null:
			return RECOVERY_INVALID_TEAM
		definitions.append(definition)
		levels.append(Hero.level_for(hero, balance))
	var team_power: float = Hero.compute_team_power(team, definitions, levels, balance)
	if team_power < float(zone.recommended_power) * 0.5:
		return RECOVERY_INSUFFICIENT_POWER
	var reliquary_level: int = clampi(building_levels[4], 0, balance.summoning_circle_level_cap)
	var damage_chance: float = LostCache.compute_damage_chance(
		cache,
		zone.recommended_power,
		team_power,
		recovery_clock_seconds,
		reliquary_level,
		balance,
	)
	for item: Item in cache.items:
		if randf() < damage_chance:
			Item.apply_damaged(item, balance)
		inventory.append(item)
	lost_caches.erase(cache)
	advance_turn(balance)
	return RECOVERY_COMPLETED


func credit_stones(amount: int) -> void:
	stones += amount
	_notify_roster_changed()


func credit_team_xp(
	team: Array[Hero],
	amount: int,
	balance: BalanceTable,
	allow_busy: bool = false,
) -> void:
	if not allow_busy:
		for hero: Hero in team:
			if is_hero_busy(hero):
				return
	var highest_team_rank: int = team[0].rank if not team.is_empty() else 0
	for hero: Hero in team:
		highest_team_rank = maxi(highest_team_rank, hero.rank)
	for hero: Hero in team:
		Hero.grant_xp(hero, amount, balance)
		if not roster.has(hero):
			continue
		var definition: HeroDefinition = Hero.definition_for(hero.def_id)
		Hero.grant_instructor_trait(hero, definition, highest_team_rank, balance)
	_notify_roster_changed()


func add_item(item: Item) -> void:
	inventory.append(item)
	_notify_roster_changed()


## An Item is in `inventory` or on exactly one hero, never both. That is enforced by the caller:
## the only equip path offers items from `inventory` alone, so an already-equipped one is never
## reachable. Calling this with an item from anywhere else duplicates it (docs/TASKS.md P2-05a).
func equip_item(hero: Hero, item: Item) -> void:
	if is_hero_busy(hero) or not roster.has(hero) or not inventory.has(item):
		return
	var definition: EquipmentDefinition = Item.definition_for(item.def_id)
	if definition == null:
		return
	var slot: int = definition.slot
	inventory.erase(item)
	if hero.equipped.has(slot):
		inventory.append(hero.equipped[slot])
	hero.equipped[slot] = item
	_notify_roster_changed()


func unequip_item(hero: Hero, slot: int) -> void:
	if is_hero_busy(hero) or not hero.equipped.has(slot):
		return
	inventory.append(hero.equipped[slot])
	hero.equipped.erase(slot)
	_notify_roster_changed()


## Only the inventory UI offers items to this path, so equipped gear is unreachable.
func salvage_item(item: Item, balance: BalanceTable) -> void:
	if not inventory.has(item) or is_item_protected(item):
		return
	var salvage_yield: int = Item.compute_salvage_yield(item, building_levels[1], balance)
	inventory.erase(item)
	# item.rank arrives from an untrusted save and is never validated by Item.from_dict, so clamp
	# before indexing, same as Item.rank_label and Hero.compute_final_stats. assert() cannot guard
	# this - it is stripped in release, where a corrupt rank would crash after the erase (positive)
	# or credit the wrong rank (negative, since GDScript indexes arrays from the end).
	parts[clampi(item.rank, 0, parts.size() - 1)] += salvage_yield
	_notify_roster_changed()


func enhance_item(item: Item, balance: BalanceTable) -> bool:
	if not inventory.has(item):
		return false
	var enhance_level: int = Item.clamped_enhance_level(item, balance)
	var enhance_cap: int = Item.compute_enhance_cap(building_levels[1], balance)
	if enhance_level >= enhance_cap:
		return false
	var rank_index: int = clampi(item.rank, 0, parts.size() - 1)
	var cost: int = Item.compute_enhance_cost(item, balance)
	if parts[rank_index] < cost:
		return false
	parts[rank_index] -= cost
	item.enhance_level = enhance_level + 1
	_notify_roster_changed()
	return true


func preview_building_upgrade(index: int) -> Dictionary:
	return _building_upgrade_plan(
		index,
		building_levels,
		parts,
		preload("res://balance.tres"),
	)


func upgrade_building(index: int, balance: BalanceTable) -> bool:
	var plan: Dictionary = _building_upgrade_plan(index, building_levels, parts, balance)
	if not bool(plan.get("valid", false)):
		return false
	var rank_index: int = Item.int_field(plan, "part_rank", 0, "building upgrade plan")
	var cost: int = Item.int_field(plan, "part_cost", 0, "building upgrade plan")
	parts[rank_index] -= cost
	building_levels[index] = Item.int_field(plan, "next_level", 0, "building upgrade plan")
	_notify_roster_changed()
	return true


static func _building_upgrade_plan(
	index: int,
	levels: Array[int],
	available_parts: Array[int],
	balance: BalanceTable,
) -> Dictionary:
	var plan: Dictionary = {
		"valid": false,
		"current_level": -1,
		"next_level": -1,
		"part_rank": -1,
		"part_cost": 0,
		"error": "",
	}
	if index < 0 or index >= levels.size():
		plan["error"] = "That building does not exist."
		return plan
	var level: int = clampi(levels[index], 0, balance.summoning_circle_level_cap)
	plan["current_level"] = level
	plan["next_level"] = level
	if level >= balance.summoning_circle_level_cap:
		plan["error"] = "That building is already at the maximum level."
		return plan
	var rank_index: int = clampi(level, 0, available_parts.size() - 1)
	var cost: int = 10 * (level + 2)
	plan["next_level"] = level + 1
	plan["part_rank"] = rank_index
	plan["part_cost"] = cost
	if available_parts[rank_index] < cost:
		plan["error"] = "Need %d rank-%d parts." % [cost, rank_index]
		return plan
	plan["valid"] = true
	return plan


func convert_parts(rank: int) -> bool:
	if rank < 0 or rank >= parts.size() - 1 or parts[rank] < 3:
		return false
	parts[rank] -= 3
	parts[rank + 1] += 1
	_notify_roster_changed()
	return true


func mark_zone_cleared(zone_id: StringName) -> void:
	assert(zone_id != &"")
	if cleared_zone_ids.has(zone_id):
		return
	cleared_zone_ids[zone_id] = true
	_notify_roster_changed()


func sacrifice_hero(fodder: Hero, target: Hero, balance: BalanceTable) -> bool:
	if (
		fodder == target
		or not roster.has(fodder)
		or not roster.has(target)
		or not fodder.equipped.is_empty()
		or is_hero_protected(fodder)
		or is_hero_busy(target)
	):
		return false
	var sanctum_level: int = clampi(building_levels[3], 0, balance.summoning_circle_level_cap)
	essence += Hero.compute_essence_yield(fodder, target, balance, sanctum_level)
	if fodder.def_id == target.def_id and fodder.def_id != Hero.NO_ARCHETYPE_DEF_ID:
		target.resonance += 1
	kill_hero(fodder, &"", balance)
	return true


func rank_up_hero(hero: Hero, balance: BalanceTable) -> bool:
	if is_hero_busy(hero) or hero.rank >= balance.rank_up_essence_costs.size():
		return false
	var cost: int = Hero.compute_rank_up_cost(hero, balance)
	if essence < cost:
		return false
	essence -= cost
	hero.rank += 1
	_notify_roster_changed()
	return true


## The single place a hero leaves the roster. See docs/ARCHITECTURE.md rule 8 - permadeath
## reachable from more than one call site is how this game rots.
func kill_hero(hero: Hero, zone_id: StringName, balance: BalanceTable) -> void:
	if not hero.equipped.is_empty():
		var cache := LostCache.new(hero.hero_name, zone_id, turns, recovery_clock_seconds)
		for item: Item in hero.equipped.values():
			cache.items.append(item)
		lost_caches.append(cache)
		recovery_clock_paused = true
	hero.equipped.clear()
	roster.erase(hero)
	if hero.instance_id == embodied_hero_id:
		embodied_hero_id = NO_BODY
	if roster.is_empty() and stones < balance.summon_pull_cost:
		stones = balance.summon_pull_cost
	_notify_roster_changed()


func hero_by_id(id: String) -> Hero:
	for hero: Hero in roster:
		if hero.instance_id == id:
			return hero
	return null


func is_embodied(hero: Hero) -> bool:
	return hero != null and hero.instance_id == embodied_hero_id


## Deliberate only: the player picks the body. Refused for a hero not on the roster or away; a
## stationed keeper is allowed (DECISIONS.md 2026-09-23 item 5).
func embody_hero(id: String) -> bool:
	last_action_error = ""
	var hero: Hero = hero_by_id(id)
	if hero == null:
		last_action_error = "That hero is not on the roster."
		return false
	if is_hero_busy(hero):
		last_action_error = "%s is away and cannot walk the town." % hero.hero_name
		return false
	return _commit_profile_mutation(_set_body_in_memory.bind(hero.instance_id))


## False, with last_action_error, when the load is blocked or the save fails (nothing changes then).
func step_out() -> bool:
	last_action_error = ""
	if embodied_hero_id == NO_BODY:
		return true
	return _commit_profile_mutation(_set_body_in_memory.bind(NO_BODY))


## Checked path only: _commit_profile_mutation refuses a blocked load and rolls back a failed save.
func _set_body_in_memory(id: String) -> void:
	embodied_hero_id = id
	_notify_roster_changed()


## Puts hero behind building_id's counter, replacing its keeper and leaving any old station.
## Protected, never busy: a keeper can still be sent out (DECISIONS.md 2026-09-23 item 5).
func station_hero(hero: Hero, building_id: StringName) -> bool:
	last_action_error = ""
	if SaveService.load_blocked:
		last_action_error = SaveService.load_block_reason
		return false
	if hero == null or not roster.has(hero):
		last_action_error = "That hero is not on the roster."
		return false
	var workplace: bool = TownRules.is_workplace_id(building_id) and not town_building(building_id).is_empty()
	if not workplace and not Hero.is_staffable(building_id):
		last_action_error = "That building takes no keeper."
		return false
	if hero.station == building_id:
		return true
	if workplace:
		var place_name: String = String(building_id).capitalize()
		if hero.home == Hero.NO_HOME:
			last_action_error = "%s needs a house before working at the %s." % [hero.hero_name, place_name]
			return false
		if workers_at(building_id).size() >= TownRules.worker_slots(TownRules.type_of(building_id), preload("res://balance.tres")):
			last_action_error = "The %s is full." % place_name
			return false
	return _commit_profile_mutation(_station_in_memory.bind(hero, building_id))


func unstation_hero(hero: Hero) -> bool:
	last_action_error = ""
	if SaveService.load_blocked:
		last_action_error = SaveService.load_block_reason
		return false
	if hero == null or not roster.has(hero):
		last_action_error = "That hero is not on the roster."
		return false
	if hero.station == Hero.NO_STATION:
		return true
	return _commit_profile_mutation(_station_in_memory.bind(hero, Hero.NO_STATION))


func keeper_for(building_id: StringName) -> Hero:
	if building_id == Hero.NO_STATION:
		return null
	for hero: Hero in roster:
		if hero.station == building_id:
			return hero
	return null


## Checked path only (_commit_profile_mutation). Clearing a hall's old keeper keeps one per hall; a
## workplace's slot count was checked by station_hero.
func _station_in_memory(hero: Hero, building_id: StringName) -> void:
	if Hero.is_staffable(building_id):
		var old_keeper: Hero = keeper_for(building_id)
		if old_keeper != null:
			old_keeper.station = Hero.NO_STATION
	hero.station = building_id
	_notify_roster_changed()


## The placed building with this id, or {} when there is none.
func town_building(id: StringName) -> Dictionary:
	for building: Dictionary in town_buildings:
		if building["id"] == String(id):
			return building
	return {}


func workers_at(building_id: StringName) -> Array[Hero]:
	var workers: Array[Hero] = []
	for hero: Hero in roster:
		if hero.station == building_id:
			workers.append(hero)
	return workers


func residents_of(house_id: StringName) -> Array[Hero]:
	var residents: Array[Hero] = []
	for hero: Hero in roster:
		if hero.home == house_id:
			residents.append(hero)
	return residents


## What place_building would do, exactly: {valid, reason, cost, id}.
func preview_place_building(type: StringName, hex: Vector2i) -> Dictionary:
	var plan: Dictionary = TownRules.place_plan(type, hex, town_buildings, float(town_resources["wood"]), town_next_id, preload("res://balance.tres"))
	if SaveService.load_blocked:
		plan["valid"] = false
		plan["reason"] = SaveService.load_block_reason
	return plan


## Spends the cost exactly and takes the next id. A refusal (last_action_error) spends nothing.
func place_building(type: StringName, hex: Vector2i) -> bool:
	last_action_error = ""
	var plan: Dictionary = preview_place_building(type, hex)
	if not bool(plan["valid"]):
		last_action_error = str(plan["reason"])
		return false
	return _commit_profile_mutation(_place_building_in_memory.bind(type, hex, int(plan["cost"])))


## Checked path only (_commit_profile_mutation), after place_plan found the hex free and the wood there.
func _place_building_in_memory(type: StringName, hex: Vector2i, cost: int) -> void:
	town_buildings.append({"id": TownRules.new_id(type, town_next_id), "type": String(type), "q": hex.x, "r": hex.y})
	town_next_id += 1
	town_resources["wood"] = float(town_resources["wood"]) - cost
	_notify_roster_changed()


## Moves hero into house_id, leaving any old house. One hero per house (house_capacity).
func assign_home(hero: Hero, house_id: StringName) -> bool:
	last_action_error = ""
	if SaveService.load_blocked:
		last_action_error = SaveService.load_block_reason
		return false
	if hero == null or not roster.has(hero):
		last_action_error = "That hero is not on the roster."
		return false
	if TownRules.type_of(house_id) != TownRules.HOUSE or town_building(house_id).is_empty():
		last_action_error = "That is not a house."
		return false
	if hero.home == house_id:
		return true
	if residents_of(house_id).size() >= preload("res://balance.tres").house_capacity:
		last_action_error = "%s is full." % String(house_id).capitalize()
		return false
	return _commit_profile_mutation(_set_home_in_memory.bind(hero, house_id))


## A workplace job needs a home, so losing the house also ends one.
func clear_home(hero: Hero) -> bool:
	last_action_error = ""
	if SaveService.load_blocked:
		last_action_error = SaveService.load_block_reason
		return false
	if hero == null or not roster.has(hero):
		last_action_error = "That hero is not on the roster."
		return false
	if hero.home == Hero.NO_HOME:
		return true
	return _commit_profile_mutation(_set_home_in_memory.bind(hero, Hero.NO_HOME))


## Checked path only (_commit_profile_mutation).
func _set_home_in_memory(hero: Hero, house_id: StringName) -> void:
	hero.home = house_id
	if house_id == Hero.NO_HOME and TownRules.is_workplace_id(hero.station):
		hero.station = Hero.NO_STATION
	_notify_roster_changed()


## Lumbermill workers who are home (not away) right now; the live tick pays each of them.
func _lumbermill_workers_home() -> int:
	var working: int = 0
	for hero: Hero in roster:
		if TownRules.type_of(hero.station) == TownRules.LUMBERMILL and not is_hero_busy(hero):
			working += 1
	return working


## The refusal every dispatch entry point shares, naming the body; "" when the party is free of it.
func body_refusal(team: Array[Hero]) -> String:
	for hero: Hero in team:
		if is_embodied(hero):
			return "%s is your body in town. Step out first." % hero.hero_name
	return ""


func is_hero_busy(hero: Hero) -> bool:
	if hero == null:
		return false
	for order: Dictionary in expedition_orders:
		if hero.instance_id in _string_array(order.get("hero_ids")):
			return true
	for incident: Dictionary in stranded_incidents:
		if hero.instance_id in _string_array(incident.get("hero_ids")):
			return true
	return false


func is_hero_protected(hero: Hero) -> bool:
	if hero == null:
		return false
	if hero.favorite or is_hero_busy(hero) or is_embodied(hero) or hero.station != Hero.NO_STATION:
		return true
	for preset: Dictionary in team_presets:
		if hero.instance_id in _string_array(preset.get("hero_ids")):
			return true
	return false


func is_item_protected(item: Item) -> bool:
	if item == null:
		return false
	if item.favorite:
		return true
	for hero: Hero in roster:
		if item in hero.equipped.values():
			return true
	return false


## False, with last_action_error, when the load is blocked, the hero is unknown or the save fails
## (nothing changes then). Favorites guard sacrifice and salvage, so the write is checked.
func set_hero_favorite(hero: Hero, value: bool) -> bool:
	last_action_error = ""
	if SaveService.load_blocked:
		last_action_error = SaveService.load_block_reason
		return false
	if hero == null or not roster.has(hero):
		last_action_error = "That hero is not on the roster."
		return false
	if hero.favorite == value:
		return true
	return _commit_profile_mutation(_set_favorite_in_memory.bind(hero, value))


## Same contract as set_hero_favorite, for an item in the inventory or on a hero.
func set_item_favorite(item: Item, value: bool) -> bool:
	last_action_error = ""
	if SaveService.load_blocked:
		last_action_error = SaveService.load_block_reason
		return false
	var known_item: bool = item != null and inventory.has(item)
	if item != null and not known_item:
		for hero: Hero in roster:
			if item in hero.equipped.values():
				known_item = true
				break
	if not known_item:
		last_action_error = "That item is not in the inventory or on a hero."
		return false
	if item.favorite == value:
		return true
	return _commit_profile_mutation(_set_favorite_in_memory.bind(item, value))


## Checked path only. target is a Hero or an Item; both carry favorite.
func _set_favorite_in_memory(target: Object, value: bool) -> void:
	target.set(&"favorite", value)
	_notify_roster_changed()


func save_team_preset(
	preset_id: String,
	preset_name: String,
	hero_ids: Array[String],
	zone_id: String,
) -> String:
	last_action_error = ""
	if SaveService.load_blocked:
		last_action_error = SaveService.load_block_reason
		return ""
	if preset_name.strip_edges().is_empty():
		last_action_error = "A team preset needs a name."
		return ""
	if not _valid_unique_id_list(hero_ids):
		last_action_error = "A team preset must contain 1 to 5 unique hero IDs."
		return ""
	if ZoneDefinition.definition_for(StringName(zone_id)) == null:
		last_action_error = "The preset destination is invalid."
		return ""
	var resolved_id: String = preset_id
	if resolved_id.is_empty():
		resolved_id = Item.new_instance_id()
	elif _preset_index(resolved_id) < 0:
		last_action_error = "The team preset no longer exists."
		return ""
	var preset: Dictionary = {
		"id": resolved_id,
		"name": preset_name.strip_edges(),
		"hero_ids": hero_ids.duplicate(),
		"zone_id": zone_id,
	}
	if not _commit_profile_mutation(_upsert_preset_in_memory.bind(preset)):
		return ""
	return resolved_id


func delete_team_preset(id: String) -> bool:
	last_action_error = ""
	if SaveService.load_blocked:
		last_action_error = SaveService.load_block_reason
		return false
	var index: int = _preset_index(id)
	if index < 0:
		last_action_error = "The team preset no longer exists."
		return false
	return _commit_profile_mutation(_delete_preset_in_memory.bind(index))


func dispatch_expedition(
	hero_ids: Array[String],
	zone_id: String,
	total_runs: int,
	team_name: String,
	preset_id: String = "",
) -> String:
	var squad: Dictionary = {"id": preset_id if not preset_id.is_empty() else "legacy", "name": team_name, "hero_ids": hero_ids.duplicate(), "stance": "stay_together", "guard_target_id": ""}
	return _dispatch_force_data([squad], zone_id, total_runs, {}, {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0})


func preview_force(preset_ids: Array[String], zone_id: String, total_runs: int, policies: Dictionary, loadout: Dictionary) -> Dictionary:
	var squads: Array[Dictionary] = []
	for preset_id: String in preset_ids:
		var index: int = _preset_index(preset_id)
		if index < 0:
			return _force_preview_error("A selected team preset no longer exists.")
		var preset: Dictionary = team_presets[index]
		squads.append({"id": preset_id, "name": str(preset.get("name", "Team")), "hero_ids": _string_array(preset.get("hero_ids")), "stance": str(policies.get("default_stance", "stay_together")), "guard_target_id": ""})
	return _preview_force_data(squads, zone_id, total_runs, policies, loadout)


func dispatch_force(preset_ids: Array[String], zone_id: String, total_runs: int, policies: Dictionary, loadout: Dictionary) -> String:
	var squads: Array[Dictionary] = []
	for preset_id: String in preset_ids:
		var index: int = _preset_index(preset_id)
		if index < 0:
			last_action_error = "A selected team preset no longer exists."
			return ""
		var preset: Dictionary = team_presets[index]
		squads.append({"id": preset_id, "name": str(preset.get("name", "Team")), "hero_ids": _string_array(preset.get("hero_ids")), "stance": str(policies.get("default_stance", "stay_together")), "guard_target_id": ""})
	return _dispatch_force_data(squads, zone_id, total_runs, policies, loadout)


func get_battle_snapshot(order_id: String) -> Dictionary:
	var index: int = _order_index(order_id)
	if index < 0 or not expedition_orders[index].get("battle") is Dictionary:
		return {}
	var order: Dictionary = expedition_orders[index]
	var snapshot: Dictionary = (order.get("battle") as Dictionary).duplicate(true)
	snapshot["phase"] = str(order.get("phase", "fighting"))
	snapshot["route_remaining_seconds"] = maxf(Item.float_field(order, "remaining_seconds", 0.0, "expedition order"), 0.0)
	snapshot["team_name"] = str(order.get("team_name", ""))
	snapshot["paused"] = _paused_battle_orders.has(order_id)
	snapshot["last_command_error"] = str(_command_errors.get(order_id, order.get("last_command_error", "")))
	snapshot["checkpoint_error"] = _checkpoint_error if _checkpoint_save_failed else str(order.get("checkpoint_error", ""))
	return snapshot


func issue_battle_command(order_id: String, command: Dictionary) -> Dictionary:
	var index: int = _order_index(order_id)
	if index < 0:
		return {"accepted": false, "error": "That battle no longer exists.", "sequence": 0}
	if _checkpoint_save_failed:
		return {"accepted": false, "error": _checkpoint_error, "sequence": Item.int_field(expedition_orders[index].get("battle") as Dictionary, "command_sequence", 0, "battle checkpoint")}
	_pending_command_result = {}
	if not _commit_profile_mutation(_issue_battle_command_in_memory.bind(order_id, command.duplicate(true))):
		var rejection: String = last_action_error
		_command_errors[order_id] = rejection
		return {"accepted": false, "error": rejection, "sequence": Item.int_field(expedition_orders[index].get("battle") as Dictionary, "command_sequence", 0, "battle checkpoint")}
	_command_errors.erase(order_id)
	return _pending_command_result.duplicate(true)


func set_battle_paused(order_id: String, paused: bool) -> void:
	if _order_index(order_id) < 0:
		return
	if paused:
		_paused_battle_orders[order_id] = true
	else:
		_paused_battle_orders.erase(order_id)
	_notify_battle_changed(order_id)


func _preview_force_data(squads: Array[Dictionary], zone_id: String, total_runs: int, policies: Dictionary, loadout: Dictionary) -> Dictionary:
	if squads.is_empty():
		return _force_preview_error("Select at least one team preset.")
	if total_runs < 0 or total_runs > 999:
		return _force_preview_error("Run count must be 0 or 1 to 999.")
	var zone: ZoneDefinition = ZoneDefinition.definition_for(StringName(zone_id))
	if zone == null or not ExpeditionOrders.is_zone_unlocked(StringName(zone_id), cleared_zone_ids):
		return _force_preview_error("That destination is not unlocked.")
	var squad_cap: int = _zone_squad_cap(zone)
	if squads.size() > squad_cap:
		return _force_preview_error("This mission allows at most %d squads." % squad_cap, 0, zone.hero_cap, squads.size())
	var team: Array[Hero] = []
	var seen: Dictionary[String, bool] = {}
	for squad: Dictionary in squads:
		var ids: Array[String] = _string_array(squad.get("hero_ids"))
		if not _valid_unique_id_list(ids):
			return _force_preview_error("Every squad needs 1 to 5 unique heroes.")
		for hero_id: String in ids:
			if seen.has(hero_id):
				return _force_preview_error("A hero cannot appear in more than one squad.")
			seen[hero_id] = true
			var hero: Hero = hero_by_id(hero_id)
			if hero == null or is_hero_busy(hero):
				return _force_preview_error("A selected hero is missing or already away.")
			team.append(hero)
	var body_error: String = body_refusal(team)
	if not body_error.is_empty():
		return _force_preview_error(body_error)
	if team.size() > zone.hero_cap:
		return _force_preview_error("This force exceeds the mission capacity.", team.size(), zone.hero_cap, squads.size())
	var policies_error: String = _validate_battle_policies(policies, seen)
	if not policies_error.is_empty():
		return _force_preview_error(policies_error, team.size(), zone.hero_cap, squads.size())
	var loadout_error: String = _validate_loadout(loadout)
	if not loadout_error.is_empty():
		return _force_preview_error(loadout_error, team.size(), zone.hero_cap, squads.size())
	for kind: String in ["healing", "revival"]:
		var allocation: int = Item.int_field(loadout, kind, 0, "battle loadout")
		var keep: int = Item.int_field(loadout, "keep_" + kind, 0, "battle loadout")
		if allocation > int(supplies.get(kind, 0)) - keep:
			return _force_preview_error("The %s allocation would spend the stockpile reserve." % kind, team.size(), zone.hero_cap, squads.size())
	var route_seconds: float = ExpeditionOrders.force_duration_seconds(team, zone, preload("res://balance.tres"))
	if route_seconds <= 0.0:
		return _force_preview_error("The selected force cannot make progress in that zone.", team.size(), zone.hero_cap, squads.size())
	var seed: int = _new_run_seed()
	var forecast: Dictionary = BattleSimulation.forecast("forecast", _team_snapshots(team, squads), zone, squads, policies, {"healing": Item.int_field(loadout, "healing", 0, "battle loadout"), "revival": Item.int_field(loadout, "revival", 0, "battle loadout")}, seed)
	var safe: bool = bool(forecast.get("safe", false))
	var valid: bool = total_runs != 0 or safe
	return {"valid": valid, "error": "" if valid else "Until-stopped dispatch requires a Safe forecast.", "safe": safe, "reason": str(forecast.get("reason", "")), "hero_count": team.size(), "capacity": zone.hero_cap, "squad_count": squads.size(), "route_seconds": route_seconds}


func _dispatch_force_data(squads: Array[Dictionary], zone_id: String, total_runs: int, policies: Dictionary, loadout: Dictionary) -> String:
	last_action_error = ""
	if SaveService.load_blocked:
		last_action_error = SaveService.load_block_reason
		return ""
	var preview: Dictionary = _preview_force_data(squads, zone_id, total_runs, policies, loadout)
	if not bool(preview.get("valid", false)):
		last_action_error = str(preview.get("error", "The force is invalid."))
		return ""
	var hero_ids: Array[String] = []
	var team: Array[Hero] = []
	for squad: Dictionary in squads:
		for hero_id: String in _string_array(squad.get("hero_ids")):
			hero_ids.append(hero_id)
			team.append(hero_by_id(hero_id))
	var zone: ZoneDefinition = ZoneDefinition.definition_for(StringName(zone_id))
	var order_id: String = Item.new_instance_id()
	var seed: int = _new_run_seed()
	var escrow: Dictionary = {"healing": Item.int_field(loadout, "healing", 0, "battle loadout"), "revival": Item.int_field(loadout, "revival", 0, "battle loadout")}
	if total_runs == 0:
		var actual_forecast: Dictionary = BattleSimulation.forecast(order_id + ":forecast", _team_snapshots(team, squads), zone, squads, policies, escrow, seed)
		if not bool(actual_forecast.get("safe", false)):
			last_action_error = "Until-stopped dispatch requires a Safe forecast: %s" % str(actual_forecast.get("reason", ""))
			return ""
	var state: BattleState = BattleSimulation.create_run(order_id, _team_snapshots(team, squads), zone, squads, policies, escrow, seed)
	var names: PackedStringArray = []
	for squad: Dictionary in squads:
		names.append(str(squad.get("name", "Team")))
	var order: Dictionary = {
		"id": order_id, "backend": "battle_v1", "team_name": " + ".join(names), "preset_id": str(squads[0].get("id", "")),
		"preset_ids": _squad_ids(squads), "hero_ids": hero_ids, "squads": squads.duplicate(true), "zone_id": zone_id,
		"total_runs": total_runs, "runs_completed": 0, "stop_requested": false, "run_seed": seed,
		"initial_duration_seconds": float(preview.get("route_seconds", 0.0)), "remaining_seconds": float(preview.get("route_seconds", 0.0)),
		"cumulative_stones": 0, "cumulative_xp": 0, "cumulative_items": 0, "battle": state.to_dict(), "phase": "fighting",
		"loadout": loadout.duplicate(true), "policies": state.policies.duplicate(true), "escrow": escrow.duplicate(true), "last_command_error": "", "checkpoint_error": "", "incident_id": "",
	}
	if not _commit_profile_mutation(_append_battle_order_in_memory.bind(order)):
		return ""
	return order_id


func _append_battle_order_in_memory(order: Dictionary) -> bool:
	var escrow: Dictionary = order.get("escrow") as Dictionary
	for kind: String in ["healing", "revival"]:
		var amount: int = Item.int_field(escrow, kind, 0, "battle escrow")
		if amount > int(supplies.get(kind, 0)):
			last_action_error = "Battle supplies changed before dispatch."
			return false
		supplies[kind] = int(supplies.get(kind, 0)) - amount
	_append_order_in_memory(order)
	return true


func _issue_battle_command_in_memory(order_id: String, command: Dictionary) -> bool:
	var index: int = _order_index(order_id)
	if index < 0:
		last_action_error = "That battle no longer exists."
		return false
	var state := BattleState.from_dict(expedition_orders[index].get("battle") as Dictionary)
	_pending_command_result = BattleSimulation.issue_command(state, command)
	expedition_orders[index]["last_command_error"] = str(_pending_command_result.get("error", ""))
	if not bool(_pending_command_result.get("accepted", false)):
		last_action_error = str(_pending_command_result.get("error", ""))
		return false
	expedition_orders[index]["battle"] = state.to_dict()
	expedition_orders[index]["policies"] = state.policies.duplicate(true)
	expedition_orders[index]["squads"] = state.squads.duplicate(true)
	_notify_battle_changed(order_id)
	_notify_expeditions_changed()
	return true


static func _force_preview_error(error: String, heroes: int = 0, capacity: int = 0, squads: int = 0) -> Dictionary:
	return {"valid": false, "error": error, "safe": false, "reason": error, "hero_count": heroes, "capacity": capacity, "squad_count": squads, "route_seconds": 0.0}


static func _validate_loadout(loadout: Dictionary) -> String:
	var allowed: Array[String] = ["healing", "revival", "keep_healing", "keep_revival"]
	if loadout.size() != allowed.size():
		return "Battle loadout must contain healing, revival and both reserve fields."
	for raw_key: Variant in loadout.keys():
		if not raw_key is String or not (raw_key as String) in allowed:
			return "Battle loadout contains an unknown field."
	for key: String in ["healing", "revival", "keep_healing", "keep_revival"]:
		if not _is_nonnegative_integer(loadout.get(key, 0)):
			return "Battle loadout quantities must be non-negative integers."
	if float(loadout.get("healing", 0)) > 100.0 or float(loadout.get("revival", 0)) > 100.0:
		return "Battle allocations are capped at 100 per supply."
	if float(loadout.get("keep_healing", 0)) > 2147483647.0 or float(loadout.get("keep_revival", 0)) > 2147483647.0:
		return "Battle supply reserves cannot exceed 2147483647."
	return ""


static func _validate_battle_policies(policies: Dictionary, deployed_hero_ids: Dictionary[String, bool]) -> String:
	var allowed: Array[String] = ["auto_battle", "default_stance", "ability_auto", "auto_heal", "auto_revive", "heal_below", "reserve_last_revival", "retreat_when_supplies_empty"]
	for raw_key: Variant in policies.keys():
		if not raw_key is String or not (raw_key as String) in allowed:
			return "Battle policies contain an unknown setting."
	for key: String in ["auto_battle", "auto_heal", "auto_revive", "reserve_last_revival", "retreat_when_supplies_empty"]:
		if policies.has(key) and not policies.get(key) is bool:
			return "Battle policy %s must be a bool." % key
	if policies.has("default_stance") and (not policies.get("default_stance") is String or not str(policies.get("default_stance")) in BattleSimulation.STANCES):
		return "Battle policy default_stance is invalid."
	if policies.has("heal_below"):
		var threshold: Variant = policies.get("heal_below")
		if not (threshold is int or threshold is float) or not is_finite(float(threshold)) or float(threshold) < 0.0 or float(threshold) > 1.0:
			return "Battle policy heal_below must be between 0 and 1."
	if policies.has("ability_auto"):
		var raw_auto: Variant = policies.get("ability_auto")
		if not raw_auto is Dictionary:
			return "Battle policy ability_auto must be a Dictionary."
		for raw_hero_id: Variant in (raw_auto as Dictionary).keys():
			if not raw_hero_id is String or not deployed_hero_ids.has(raw_hero_id as String) or not (raw_auto as Dictionary).get(raw_hero_id) is bool:
				return "Battle policy ability_auto must contain deployed hero IDs with bool values."
	return ""


func _team_snapshots(team: Array[Hero], squads: Array[Dictionary] = []) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var balance: BalanceTable = preload("res://balance.tres")
	for hero: Hero in team:
		var definition: HeroDefinition = Hero.definition_for(hero.def_id)
		var level: int = Hero.level_for(hero, balance)
		var stats: Dictionary[StringName, float] = Hero.compute_final_stats(hero, definition, balance, level)
		result.append({"hero_id": hero.instance_id, "archetype": str(hero.def_id), "hp": stats[Hero.STAT_HP], "atk": stats[Hero.STAT_ATK], "defense": stats[Hero.STAT_DEF], "speed": stats[Hero.STAT_SPD], "crit_rate": stats[Hero.STAT_CRIT_RATE], "crit_damage": stats[Hero.STAT_CRIT_DMG], "squad_id": _squad_for_hero(hero.instance_id, squads)})
	return result


func _squad_for_hero(hero_id: String, squads: Array[Dictionary] = []) -> String:
	var search_squads: Array[Dictionary] = squads if not squads.is_empty() else team_presets
	for preset: Dictionary in search_squads:
		if hero_id in _string_array(preset.get("hero_ids")):
			return str(preset.get("id", ""))
	return "legacy"


static func _squad_ids(squads: Array[Dictionary]) -> Array[String]:
	var ids: Array[String] = []
	for squad: Dictionary in squads:
		ids.append(str(squad.get("id", "")))
	return ids


func request_stop_expedition(order_id: String) -> void:
	last_action_error = ""
	if SaveService.load_blocked:
		last_action_error = SaveService.load_block_reason
		return
	var index: int = _order_index(order_id)
	if index < 0:
		last_action_error = "The expedition order no longer exists."
		return
	if bool(expedition_orders[index].get("stop_requested", false)):
		return
	_commit_profile_mutation(_request_stop_in_memory.bind(index))


func acknowledge_recovery_losses() -> void:
	if not recovery_clock_paused or lost_caches.is_empty() or SaveService.load_blocked:
		return
	recovery_clock_paused = false
	_notify_roster_changed()
	_notify_expeditions_changed()


func get_stranded_incidents() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for incident: Dictionary in stranded_incidents:
		var copy: Dictionary = incident.duplicate(true)
		copy["remaining_seconds"] = _incident_remaining_seconds(incident)
		result.append(copy)
	return result


func start_rescue_window(id: String) -> bool:
	last_action_error = ""
	var index: int = _incident_index(id)
	if index < 0:
		last_action_error = "That stranded incident no longer exists."
		return false
	if not bool(stranded_incidents[index].get("paused", true)):
		return true
	return _commit_profile_mutation(_start_rescue_window_in_memory.bind(index))


func dispatch_rescue(incident_id: String, preset_id: String, loadout: Dictionary) -> String:
	last_action_error = ""
	var incident_index: int = _incident_index(incident_id)
	var preset_index: int = _preset_index(preset_id)
	if incident_index < 0 or preset_index < 0:
		last_action_error = "The incident or rescue team no longer exists."
		return ""
	var incident: Dictionary = stranded_incidents[incident_index]
	if not str(incident.get("active_rescue_order_id", "")).is_empty() or _incident_remaining_seconds(incident) <= 0.0:
		last_action_error = "That incident cannot accept another rescue attempt."
		return ""
	var preset: Dictionary = team_presets[preset_index]
	var hero_ids: Array[String] = _string_array(preset.get("hero_ids"))
	if not _valid_unique_id_list(hero_ids):
		last_action_error = "A rescue needs 1 to 5 unique heroes."
		return ""
	var team: Array[Hero] = []
	for hero_id: String in hero_ids:
		var hero: Hero = hero_by_id(hero_id)
		if hero == null or is_hero_busy(hero):
			last_action_error = "A rescue hero is missing or already away."
			return ""
		team.append(hero)
	last_action_error = body_refusal(team)
	if not last_action_error.is_empty():
		return ""
	var loadout_error: String = _validate_loadout(loadout)
	if not loadout_error.is_empty():
		last_action_error = loadout_error
		return ""
	for kind: String in ["healing", "revival"]:
		if Item.int_field(loadout, kind, 0, "rescue loadout") > int(supplies.get(kind, 0)) - Item.int_field(loadout, "keep_" + kind, 0, "rescue loadout"):
			last_action_error = "The rescue allocation would spend the stockpile reserve."
			return ""
	var zone: ZoneDefinition = ZoneDefinition.definition_for(StringName(str(incident.get("zone_id", ""))))
	if zone == null:
		last_action_error = "The incident destination is missing."
		return ""
	var order_id: String = Item.new_instance_id()
	var seed: int = _new_run_seed()
	var squad: Dictionary = {"id": preset_id, "name": str(preset.get("name", "Rescue")), "hero_ids": hero_ids, "stance": "stay_together", "guard_target_id": ""}
	var snapshots: Array[Dictionary] = []
	var preserved: Dictionary = incident.get("battle_snapshot") as Dictionary
	for actor_data: Variant in preserved.get("actors", []) as Array:
		if actor_data is Dictionary:
			snapshots.append((actor_data as Dictionary).duplicate(true))
	for rescuer: Dictionary in _team_snapshots(team, [squad]):
		rescuer["squad_id"] = preset_id
		snapshots.append(rescuer)
	var escrow: Dictionary = {"healing": Item.int_field(loadout, "healing", 0, "rescue loadout"), "revival": Item.int_field(loadout, "revival", 0, "rescue loadout")}
	var state: BattleState = BattleSimulation.create_run(order_id, snapshots, zone, [squad], {}, escrow, seed, "rescue")
	var order: Dictionary = {"id": order_id, "backend": "battle_v1", "team_name": str(preset.get("name", "Rescue")), "preset_id": preset_id, "preset_ids": [preset_id], "hero_ids": hero_ids, "squads": [squad], "zone_id": str(zone.zone_id), "total_runs": 1, "runs_completed": 0, "stop_requested": false, "run_seed": seed, "initial_duration_seconds": 0.0, "remaining_seconds": 0.0, "cumulative_stones": 0, "cumulative_xp": 0, "cumulative_items": 0, "battle": state.to_dict(), "phase": "rescuing", "loadout": loadout.duplicate(true), "policies": state.policies.duplicate(true), "escrow": escrow, "last_command_error": "", "checkpoint_error": "", "incident_id": incident_id}
	if not _commit_profile_mutation(_append_rescue_order_in_memory.bind(order, incident_index)):
		return ""
	return order_id


func abandon_stranded(id: String) -> bool:
	last_action_error = ""
	var index: int = _incident_index(id)
	if index < 0:
		last_action_error = "That stranded incident no longer exists."
		return false
	if not str(stranded_incidents[index].get("active_rescue_order_id", "")).is_empty():
		last_action_error = "Resolve the active rescue before abandoning this incident."
		return false
	return _commit_profile_mutation(_abandon_incident_in_memory.bind(index))


func _start_rescue_window_in_memory(index: int) -> void:
	stranded_incidents[index]["paused"] = false
	stranded_incidents[index]["created_recovery_seconds"] = rescue_clock_seconds
	_notify_expeditions_changed()


func _append_rescue_order_in_memory(order: Dictionary, incident_index: int) -> bool:
	if not _append_battle_order_in_memory(order):
		return false
	if bool(stranded_incidents[incident_index].get("paused", true)):
		stranded_incidents[incident_index]["created_recovery_seconds"] = rescue_clock_seconds
	stranded_incidents[incident_index]["paused"] = false
	stranded_incidents[incident_index]["active_rescue_order_id"] = str(order.get("id", ""))
	_notify_expeditions_changed()
	return true


func _abandon_incident_in_memory(index: int) -> void:
	var incident: Dictionary = stranded_incidents[index]
	Expedition.finalize_permanent_losses(_string_array(incident.get("hero_ids")), StringName(str(incident.get("zone_id", ""))))
	stranded_incidents.remove_at(index)
	_notify_expeditions_changed()


func _incident_remaining_seconds(incident: Dictionary) -> float:
	var balance: BalanceTable = preload("res://balance.tres")
	var level: int = clampi(building_levels[4], 0, balance.summoning_circle_level_cap)
	var lifetime: float = balance.recovery_base_duration_seconds + balance.recovery_duration_seconds_per_level * float(level)
	if bool(incident.get("paused", true)):
		return lifetime
	return maxf(lifetime - (rescue_clock_seconds - Item.float_field(incident, "created_recovery_seconds", rescue_clock_seconds, "stranded incident")), 0.0)


func _incident_index(id: String) -> int:
	for index: int in stranded_incidents.size():
		if str(stranded_incidents[index].get("id", "")) == id:
			return index
	return -1


func preview_bulk_salvage(item_ids: Array[String], quantity: int) -> Dictionary:
	var balance: BalanceTable = preload("res://balance.tres")
	return BulkOperations.preview_salvage(
		item_ids,
		quantity,
		_all_item_map(),
		_item_name_map(),
		_item_protection_reasons(),
		building_levels[1],
		balance,
	)


func preview_bulk_sacrifice(
	hero_ids: Array[String],
	target_id: String,
	quantity: int,
) -> Dictionary:
	var target: Hero = hero_by_id(target_id)
	var balance: BalanceTable = preload("res://balance.tres")
	var sanctum_level: int = clampi(
		building_levels[3],
		0,
		balance.summoning_circle_level_cap,
	)
	var plan: Dictionary = BulkOperations.preview_sacrifice(
		hero_ids,
		target,
		quantity,
		_hero_map(),
		_hero_protection_reasons(),
		sanctum_level,
		balance,
	)
	if target != null and is_hero_busy(target):
		plan["valid"] = false
		plan["error"] = "The sacrifice recipient is away on an expedition."
	return plan


func preview_bulk_enhance(
	item_ids: Array[String],
	target_level: int,
	budget_parts: Array[int],
) -> Dictionary:
	return BulkOperations.preview_enhance(
		item_ids,
		target_level,
		budget_parts,
		_inventory_item_map(),
		_item_name_map(),
		parts,
		building_levels[1],
		preload("res://balance.tres"),
	)


func preview_bulk_conversion(rank: int, quantity: int, reserve: int) -> Dictionary:
	return BulkOperations.preview_conversion(parts, rank, quantity, reserve)


func preview_bulk_supplies(kind: String, quantity: int, reserve: int) -> Dictionary:
	return BulkOperations.preview_supplies(kind, quantity, reserve, parts, supplies, preload("res://balance.tres"))


func commit_bulk_plan(plan: Dictionary) -> bool:
	last_action_error = ""
	if SaveService.load_blocked:
		last_action_error = SaveService.load_block_reason
		return false
	if not bool(plan.get("valid", false)):
		last_action_error = str(plan.get("error", "The bulk plan is invalid."))
		return false
	var rebuilt: Dictionary = _rebuild_bulk_plan(plan)
	if not bool(rebuilt.get("valid", false)) or rebuilt != plan:
		last_action_error = "The bulk preview is stale. Review the current selection and resources before committing."
		return false
	return _commit_profile_mutation(_apply_bulk_plan_in_memory.bind(plan))


func _rebuild_bulk_plan(plan: Dictionary) -> Dictionary:
	var parameters: Dictionary = plan.get("parameters", {}) as Dictionary
	match str(plan.get("kind", "")):
		"salvage":
			return preview_bulk_salvage(
				_string_array(parameters.get("item_ids")),
				Item.int_field(parameters, "quantity", 0, "bulk plan"),
			)
		"sacrifice":
			return preview_bulk_sacrifice(
				_string_array(parameters.get("hero_ids")),
				str(parameters.get("target_id", "")),
				Item.int_field(parameters, "quantity", 0, "bulk plan"),
			)
		"enhance":
			return preview_bulk_enhance(
				_string_array(parameters.get("item_ids")),
				Item.int_field(parameters, "target_level", 0, "bulk plan"),
				_int_array(parameters.get("budget_parts")),
			)
		"conversion":
			return preview_bulk_conversion(
				Item.int_field(parameters, "rank", -1, "bulk plan"),
				Item.int_field(parameters, "quantity", 0, "bulk plan"),
				Item.int_field(parameters, "reserve", 0, "bulk plan"),
			)
		"supplies":
			return preview_bulk_supplies(
				str(parameters.get("supply_kind", "")),
				Item.int_field(parameters, "quantity", 0, "bulk plan"),
				Item.int_field(parameters, "reserve", 0, "bulk plan"),
			)
	return {}


func _apply_bulk_plan_in_memory(plan: Dictionary) -> bool:
	var entries: Array = plan.get("entries", []) as Array
	match str(plan.get("kind", "")):
		"salvage":
			for raw_entry: Variant in entries:
				var entry: Dictionary = raw_entry as Dictionary
				var item: Item = item_by_id(str(entry.get("id", "")))
				if item == null or not inventory.has(item):
					last_action_error = "A salvage item became unavailable."
					return false
				inventory.erase(item)
				parts[Item.int_field(entry, "rank", 0, "bulk entry")] += Item.int_field(entry, "gain", 0, "bulk entry")
		"sacrifice":
			var parameters: Dictionary = plan.get("parameters", {}) as Dictionary
			var target: Hero = hero_by_id(str(parameters.get("target_id", "")))
			for raw_entry: Variant in entries:
				var entry: Dictionary = raw_entry as Dictionary
				var fodder: Hero = hero_by_id(str(entry.get("id", "")))
				if not sacrifice_hero(fodder, target, preload("res://balance.tres")):
					last_action_error = "A sacrifice participant became unavailable."
					return false
		"enhance":
			for raw_entry: Variant in entries:
				var entry: Dictionary = raw_entry as Dictionary
				var item: Item = item_by_id(str(entry.get("id", "")))
				if item == null:
					last_action_error = "An enhancement item became unavailable."
					return false
				var target_level: int = Item.int_field(entry, "after_level", 0, "bulk entry")
				while item.enhance_level < target_level:
					if not enhance_item(item, preload("res://balance.tres")):
						last_action_error = "Enhancement rules changed while applying the plan."
						return false
		"conversion":
			var entry: Dictionary = entries[0] as Dictionary
			var rank: int = Item.int_field(entry, "source_rank", 0, "bulk entry")
			parts[rank] -= Item.int_field(entry, "spend", 0, "bulk entry")
			parts[rank + 1] += Item.int_field(entry, "gain", 0, "bulk entry")
		"supplies":
			var entry: Dictionary = entries[0] as Dictionary
			var supply_kind: String = str(entry.get("supply_kind", ""))
			parts[0] -= Item.int_field(entry, "spend", 0, "bulk entry")
			supplies[supply_kind] = int(supplies.get(supply_kind, 0)) + Item.int_field(entry, "gain", 0, "bulk entry")
	_notify_roster_changed()
	return true


func _inventory_item_map() -> Dictionary[String, Item]:
	var items: Dictionary[String, Item] = {}
	for item: Item in inventory:
		items[item.instance_id] = item
	return items


func _all_item_map() -> Dictionary[String, Item]:
	var items: Dictionary[String, Item] = _inventory_item_map()
	for hero: Hero in roster:
		for item: Item in hero.equipped.values():
			items[item.instance_id] = item
	for cache: LostCache in lost_caches:
		for item: Item in cache.items:
			items[item.instance_id] = item
	return items


func _item_name_map() -> Dictionary[String, String]:
	var names: Dictionary[String, String] = {}
	for item: Item in _all_item_map().values():
		var definition: EquipmentDefinition = Item.definition_for(item.def_id)
		names[item.instance_id] = definition.display_name if definition != null else str(item.def_id)
	return names


func _item_protection_reasons() -> Dictionary[String, String]:
	var reasons: Dictionary[String, String] = {}
	for item: Item in _all_item_map().values():
		if item.favorite:
			reasons[item.instance_id] = "favorite"
		elif not inventory.has(item):
			reasons[item.instance_id] = "equipped" if _is_item_equipped(item) else "unavailable"
	return reasons


func _is_item_equipped(item: Item) -> bool:
	for hero: Hero in roster:
		if item in hero.equipped.values():
			return true
	return false


func _hero_map() -> Dictionary[String, Hero]:
	var heroes: Dictionary[String, Hero] = {}
	for hero: Hero in roster:
		heroes[hero.instance_id] = hero
	return heroes


func _hero_protection_reasons() -> Dictionary[String, String]:
	var reasons: Dictionary[String, String] = {}
	for hero: Hero in roster:
		if is_embodied(hero):
			reasons[hero.instance_id] = "town body"
		elif TownRules.is_workplace_id(hero.station):
			reasons[hero.instance_id] = "Works at the %s" % str(hero.station).capitalize()
		elif hero.station != Hero.NO_STATION:
			reasons[hero.instance_id] = "Keeps the %s" % str(hero.station).capitalize()
		elif hero.favorite:
			reasons[hero.instance_id] = "favorite"
		elif is_hero_busy(hero):
			reasons[hero.instance_id] = "away"
		elif not hero.equipped.is_empty():
			reasons[hero.instance_id] = "equipped"
		else:
			for preset: Dictionary in team_presets:
				if hero.instance_id in _string_array(preset.get("hero_ids")):
					reasons[hero.instance_id] = "preset_member"
					break
	return reasons


func tick_expeditions(delta_seconds: float) -> void:
	if delta_seconds <= 0.0 or SaveService.load_blocked or _checkpoint_save_failed:
		return
	var has_due_order: bool = false
	for order: Dictionary in expedition_orders:
		var route_due: bool = Item.float_field(order, "remaining_seconds", 0.0, "expedition order") - delta_seconds <= 0.0
		if str(order.get("backend", "legacy_v2")) != "battle_v1":
			if route_due:
				has_due_order = true
				break
			continue
		var order_id: String = str(order.get("id", ""))
		var current_state := BattleState.from_dict(order.get("battle") as Dictionary)
		if current_state.status != "active":
			if route_due or _battle_has_no_secured_allies(current_state):
				has_due_order = true
				break
		elif not _paused_battle_orders.has(order_id):
			var preview_state := BattleState.from_dict(order.get("battle") as Dictionary)
			BattleSimulation.advance(preview_state, delta_seconds)
			if preview_state.status != "active" and (route_due or _battle_has_no_secured_allies(preview_state)):
				has_due_order = true
				break
	var has_expiring_cache: bool = false
	if not recovery_clock_paused:
		var next_clock: float = recovery_clock_seconds + delta_seconds
		var reliquary_level: int = clampi(building_levels[4], 0, preload("res://balance.tres").summoning_circle_level_cap)
		for cache: LostCache in lost_caches:
			if LostCache.seconds_remaining(cache, next_clock, reliquary_level, preload("res://balance.tres")) < 0.0:
				has_expiring_cache = true
				break
	var has_expiring_incident: bool = false
	for incident: Dictionary in stranded_incidents:
		if bool(incident.get("paused", true)) or _incident_remaining_seconds(incident) > delta_seconds:
			continue
		var active_rescue: bool = not str(incident.get("active_rescue_order_id", "")).is_empty()
		if not active_rescue or not bool(incident.get("expiry_pending", false)):
			has_expiring_incident = true
			break
	if has_due_order or has_expiring_cache or has_expiring_incident:
		_commit_profile_mutation(_advance_time_in_memory.bind(delta_seconds))
	else:
		_advance_clocks_in_memory(delta_seconds)
		_notify_expeditions_changed()


func apply_offline_expedition_progress(now_unix: float) -> void:
	if SaveService.load_blocked or not is_finite(now_unix) or now_unix < 0.0:
		return
	var elapsed_seconds: float = maxf(now_unix - saved_at_unix, 0.0)
	if elapsed_seconds <= 0.0 or expedition_orders.is_empty():
		return
	# Recovery deliberately does not use offline time. Only already-dispatched current runs advance.
	_commit_profile_mutation(_advance_orders_in_memory.bind(elapsed_seconds))


func migrate_v2_orders(now_unix: float) -> bool:
	var elapsed: float = maxf(now_unix - saved_at_unix, 0.0) if is_finite(now_unix) else 0.0
	for order: Dictionary in expedition_orders:
		if str(order.get("backend", "")).is_empty():
			var team: Array[Hero] = []
			for hero_id: String in _string_array(order.get("hero_ids")):
				var hero: Hero = hero_by_id(hero_id)
				if hero == null:
					return false
				team.append(hero)
			var zone: ZoneDefinition = ZoneDefinition.definition_for(StringName(str(order.get("zone_id", ""))))
			if zone == null or team.is_empty():
				return false
			var squad_id: String = str(order.get("preset_id", "legacy"))
			if squad_id.is_empty():
				squad_id = "legacy"
			var squad: Dictionary = {"id": squad_id, "name": str(order.get("team_name", "Team")), "hero_ids": _string_array(order.get("hero_ids")), "stance": "stay_together", "guard_target_id": ""}
			var seed: int = Item.int_field(order, "run_seed", _new_run_seed(), "legacy order")
			var state: BattleState = BattleSimulation.create_run(str(order.get("id")), _team_snapshots(team, [squad]), zone, [squad], {}, {"healing": 0, "revival": 0}, seed)
			order["backend"] = "battle_v1"
			order["preset_ids"] = [squad_id]
			order["squads"] = [squad]
			order["battle"] = state.to_dict()
			order["phase"] = "fighting"
			order["loadout"] = {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0}
			order["policies"] = state.policies.duplicate(true)
			order["escrow"] = {"healing": 0, "revival": 0}
			order["last_command_error"] = ""
			order["checkpoint_error"] = ""
			order["incident_id"] = ""
			order["remaining_seconds"] = maxf(Item.float_field(order, "remaining_seconds", 0.0, "legacy order") - elapsed, 0.0)
	return true


func _advance_time_in_memory(delta_seconds: float) -> void:
	_advance_clocks_in_memory(delta_seconds)
	_resolve_due_orders_in_memory()
	_expire_recovery_caches_in_memory()
	_expire_stranded_incidents_in_memory()
	_notify_roster_changed()
	_notify_expeditions_changed()


func _advance_orders_in_memory(delta_seconds: float) -> void:
	for order: Dictionary in expedition_orders:
		order["remaining_seconds"] = maxf(Item.float_field(order, "remaining_seconds", 0.0, "expedition order") - delta_seconds, 0.0)
		if str(order.get("backend", "legacy_v2")) == "battle_v1":
			var state := BattleState.from_dict(order.get("battle") as Dictionary)
			if state.status == "active":
				BattleSimulation.advance(state, minf(delta_seconds, maxf(state.max_seconds - state.elapsed_seconds, 0.0)))
				order["battle"] = state.to_dict()
				if state.status != "active":
					order["phase"] = "returning"
					if _battle_has_no_secured_allies(state):
						_capture_stranded_incident(order, state)
	_resolve_due_orders_in_memory()
	_notify_roster_changed()
	_notify_expeditions_changed()


func _advance_clocks_in_memory(delta_seconds: float) -> void:
	for order: Dictionary in expedition_orders:
		order["remaining_seconds"] = maxf(Item.float_field(order, "remaining_seconds", 0.0, "expedition order") - delta_seconds, 0.0)
		if str(order.get("backend", "legacy_v2")) == "battle_v1" and not _paused_battle_orders.has(str(order.get("id", ""))):
			var state := BattleState.from_dict(order.get("battle") as Dictionary)
			if state.status == "active":
				BattleSimulation.advance(state, minf(delta_seconds, maxf(state.max_seconds - state.elapsed_seconds, 0.0)))
				order["battle"] = state.to_dict()
				if state.status != "active":
					order["phase"] = "returning"
					if _battle_has_no_secured_allies(state):
						_capture_stranded_incident(order, state)
			_notify_battle_changed(str(order.get("id", "")))
	if not recovery_clock_paused and not lost_caches.is_empty():
		recovery_clock_seconds += delta_seconds
	# Live tick only: _advance_orders_in_memory (the offline catch-up) makes nothing (GAME_SPEC.md § Hard constraints).
	town_resources["wood"] = float(town_resources["wood"]) + TownRules.wood_made(_lumbermill_workers_home(), delta_seconds, preload("res://balance.tres"))
	for incident: Dictionary in stranded_incidents:
		if not bool(incident.get("paused", true)):
			rescue_clock_seconds += delta_seconds
			break


func _resolve_due_orders_in_memory() -> void:
	var due_orders: Array[Dictionary] = []
	for order: Dictionary in expedition_orders:
		var ready: bool = Item.float_field(order, "remaining_seconds", 0.0, "expedition order") <= 0.0
		if str(order.get("backend", "legacy_v2")) == "battle_v1":
			var state := BattleState.from_dict(order.get("battle") as Dictionary)
			ready = state.status != "active" and (ready or _battle_has_no_secured_allies(state))
		if ready:
			due_orders.append(order)
	due_orders.sort_custom(_due_order_before)
	for due_order: Dictionary in due_orders:
		_complete_order_in_memory(str(due_order.get("id", "")))


func _battle_has_no_secured_allies(state: BattleState) -> bool:
	return BattleSimulation.snapshot_outcome(state).secured_hero_ids.is_empty()


static func _due_order_before(first: Dictionary, second: Dictionary) -> bool:
	var first_remaining: float = Item.float_field(first, "remaining_seconds", 0.0, "expedition order")
	var second_remaining: float = Item.float_field(second, "remaining_seconds", 0.0, "expedition order")
	if first_remaining != second_remaining:
		return first_remaining < second_remaining
	return str(first.get("id", "")) < str(second.get("id", ""))


func _complete_order_in_memory(order_id: String) -> void:
	var order_index: int = _order_index(order_id)
	if order_index < 0:
		return
	var order: Dictionary = expedition_orders[order_index]
	if str(order.get("backend", "legacy_v2")) == "battle_v1":
		_settle_battle_order(order_index)
		return
	var hero_ids: Array[String] = _string_array(order.get("hero_ids"))
	var team: Array[Hero] = []
	var hero_names: Array[String] = []
	for hero_id: String in hero_ids:
		var hero: Hero = hero_by_id(hero_id)
		if hero == null:
			_append_terminal_report(order, hero_names, [], Expedition.OUTCOME_INVALID_TEAM, 0, 0, 0, "incomplete_team")
			expedition_orders.remove_at(order_index)
			return
		team.append(hero)
		hero_names.append(hero.hero_name)
	var zone: ZoneDefinition = ZoneDefinition.definition_for(StringName(str(order.get("zone_id", ""))))
	if zone == null:
		_append_terminal_report(order, hero_names, [], Expedition.OUTCOME_INVALID_TEAM, 0, 0, 0, "incomplete_team")
		expedition_orders.remove_at(order_index)
		return

	var stones_before: int = stones
	var inventory_before: int = inventory.size()
	var xp_before: int = _team_total_xp(team)
	var expedition := Expedition.new()
	var outcome: StringName = expedition.resolve_seeded(
		team,
		zone,
		Item.int_field(order, "run_seed", 0, "expedition order"),
	)
	var casualty_names: Array[String] = []
	for hero: Hero in team:
		if not roster.has(hero):
			casualty_names.append(hero.hero_name)
	var stones_earned: int = maxi(stones - stones_before, 0)
	var items_earned: int = maxi(inventory.size() - inventory_before, 0)
	var xp_earned: int = maxi(_team_total_xp(team) - xp_before, 0)
	order["runs_completed"] = Item.int_field(order, "runs_completed", 0, "expedition order") + 1
	order["cumulative_stones"] = Item.int_field(order, "cumulative_stones", 0, "expedition order") + stones_earned
	order["cumulative_xp"] = Item.int_field(order, "cumulative_xp", 0, "expedition order") + xp_earned
	order["cumulative_items"] = Item.int_field(order, "cumulative_items", 0, "expedition order") + items_earned

	var stopped_reason: String = ""
	if not casualty_names.is_empty():
		stopped_reason = "casualty"
	elif outcome != Expedition.OUTCOME_COMPLETED:
		stopped_reason = str(outcome)
	elif bool(order.get("stop_requested", false)):
		stopped_reason = "requested"
	else:
		var total_runs: int = Item.int_field(order, "total_runs", 1, "expedition order")
		if total_runs > 0 and Item.int_field(order, "runs_completed", 0, "expedition order") >= total_runs:
			stopped_reason = "completed"

	if stopped_reason.is_empty():
		var current_team: Array[Hero] = []
		for hero_id: String in hero_ids:
			var current_hero: Hero = hero_by_id(hero_id)
			if current_hero == null:
				stopped_reason = "incomplete_team"
				break
			current_team.append(current_hero)
		if stopped_reason.is_empty() and Item.int_field(order, "total_runs", 1, "expedition order") == 0:
			var forecast: Dictionary = ExpeditionOrders.safety_forecast(current_team, zone, preload("res://balance.tres"))
			if not bool(forecast.get("safe", false)):
				stopped_reason = "unsafe_repeat"
		if stopped_reason.is_empty():
			var next_duration: float = ExpeditionOrders.duration_seconds(current_team, zone, preload("res://balance.tres"))
			if next_duration <= 0.0:
				stopped_reason = "incomplete_team"
			else:
				order["run_seed"] = _new_run_seed()
				order["initial_duration_seconds"] = next_duration
				order["remaining_seconds"] = next_duration

	_append_report(
		order,
		hero_names,
		casualty_names,
		outcome,
		stones_earned,
		xp_earned,
		items_earned,
		stopped_reason,
	)
	if not stopped_reason.is_empty():
		expedition_orders.remove_at(_order_index(order_id))


func _capture_stranded_incident(order: Dictionary, state: BattleState) -> void:
	if state.kind != "normal" or not str(order.get("incident_id", "")).is_empty():
		return
	var outcome: BattleOutcome = BattleSimulation.snapshot_outcome(state)
	if outcome.stranded_hero_ids.is_empty():
		return
	var incident_id: String = Item.new_instance_id()
	var snapshot: Dictionary = _incident_snapshot(state, outcome.stranded_hero_ids)
	stranded_incidents.append({"id": incident_id, "source_order_id": str(order.get("id", "")), "zone_id": state.zone_id, "hero_ids": outcome.stranded_hero_ids.duplicate(), "battle_snapshot": snapshot, "created_recovery_seconds": rescue_clock_seconds, "paused": true, "expiry_pending": false, "active_rescue_order_id": ""})
	order["incident_id"] = incident_id
	_notify_expeditions_changed()


func _settle_battle_order(order_index: int) -> void:
	var order: Dictionary = expedition_orders[order_index]
	var state := BattleState.from_dict(order.get("battle") as Dictionary)
	var outcome: BattleOutcome = BattleSimulation.snapshot_outcome(state)
	_capture_stranded_incident(order, state)
	_refund_battle_supplies(state.supplies_remaining)
	if state.kind == "rescue":
		_settle_rescue_order(order, state, outcome)
		expedition_orders.remove_at(order_index)
		return
	var zone: ZoneDefinition = ZoneDefinition.definition_for(StringName(state.zone_id))
	var secured: Array[Hero] = []
	for hero_id: String in outcome.secured_hero_ids:
		var hero: Hero = hero_by_id(hero_id)
		if hero != null:
			secured.append(hero)
	var balance: BalanceTable = preload("res://balance.tres")
	var xp_multiplier: float = 1.0 + balance.training_hall_xp_bonus * float(clampi(building_levels[2], 0, balance.summoning_circle_level_cap))
	var xp_amount: int = roundi(float(balance.xp_per_wave * outcome.completed_waves) * xp_multiplier)
	var stones_earned: int = 0
	var items_earned: int = 0
	if outcome.status == "victory" and zone != null:
		xp_amount = roundi(float(balance.xp_per_wave * outcome.completed_waves + zone.xp_reward) * xp_multiplier)
		stones_earned = zone.stone_reward
		stones += stones_earned
		inventory.append(Expedition.roll_loot(zone, balance, Item.int_field(order, "run_seed", 0, "battle order")))
		items_earned = 1
		cleared_zone_ids[zone.zone_id] = true
	if not secured.is_empty() and xp_amount > 0:
		credit_team_xp(secured, xp_amount, balance, true)
	turns += 1
	order["runs_completed"] = Item.int_field(order, "runs_completed", 0, "battle order") + 1
	order["cumulative_stones"] = Item.int_field(order, "cumulative_stones", 0, "battle order") + stones_earned
	order["cumulative_xp"] = Item.int_field(order, "cumulative_xp", 0, "battle order") + xp_amount * secured.size()
	order["cumulative_items"] = Item.int_field(order, "cumulative_items", 0, "battle order") + items_earned
	var stopped_reason: String = _battle_stop_reason(order, state, outcome)
	if stopped_reason.is_empty() and not _start_battle_repeat(order, zone):
		stopped_reason = last_action_error if not last_action_error.is_empty() else "unsafe_repeat"
	_append_report(order, _hero_names(_string_array(order.get("hero_ids"))), _hero_names(outcome.stranded_hero_ids), StringName(outcome.status), stones_earned, xp_amount * secured.size(), items_earned, stopped_reason)
	if not stopped_reason.is_empty():
		expedition_orders.remove_at(order_index)


func _battle_stop_reason(order: Dictionary, state: BattleState, outcome: BattleOutcome) -> String:
	if outcome.status != "victory":
		return outcome.status
	if not state.downed_ever_ids.is_empty():
		return "downed"
	if bool(order.get("stop_requested", false)):
		return "requested"
	var total_runs: int = Item.int_field(order, "total_runs", 1, "battle order")
	if total_runs > 0 and Item.int_field(order, "runs_completed", 0, "battle order") >= total_runs:
		return "completed"
	return ""


func _start_battle_repeat(order: Dictionary, zone: ZoneDefinition) -> bool:
	var team: Array[Hero] = []
	for hero_id: String in _string_array(order.get("hero_ids")):
		var hero: Hero = hero_by_id(hero_id)
		if hero == null:
			last_action_error = "A repeat team member is missing."
			return false
		team.append(hero)
	var loadout: Dictionary = order.get("loadout") as Dictionary
	for kind: String in ["healing", "revival"]:
		var amount: int = Item.int_field(loadout, kind, 0, "battle loadout")
		var keep: int = Item.int_field(loadout, "keep_" + kind, 0, "battle loadout")
		if amount > int(supplies.get(kind, 0)) - keep:
			last_action_error = "insufficient_refill"
			return false
	var seed: int = _new_run_seed()
	var escrow: Dictionary = {"healing": Item.int_field(loadout, "healing", 0, "battle loadout"), "revival": Item.int_field(loadout, "revival", 0, "battle loadout")}
	var squads: Array[Dictionary] = []
	for raw_squad: Variant in order.get("squads") as Array:
		if raw_squad is Dictionary:
			squads.append((raw_squad as Dictionary).duplicate(true))
	var forecast: Dictionary = BattleSimulation.forecast(str(order.get("id")) + ":repeat", _team_snapshots(team, squads), zone, squads, order.get("policies") as Dictionary, escrow, seed)
	if not bool(forecast.get("safe", false)):
		last_action_error = "unsafe_repeat"
		return false
	for kind: String in ["healing", "revival"]:
		supplies[kind] = int(supplies.get(kind, 0)) - int(escrow.get(kind, 0))
	var state: BattleState = BattleSimulation.create_run(str(order.get("id")), _team_snapshots(team, squads), zone, squads, order.get("policies") as Dictionary, escrow, seed)
	var duration: float = ExpeditionOrders.force_duration_seconds(team, zone, preload("res://balance.tres"))
	order["run_seed"] = seed
	order["battle"] = state.to_dict()
	order["escrow"] = escrow
	order["phase"] = "fighting"
	order["initial_duration_seconds"] = duration
	order["remaining_seconds"] = duration
	order["incident_id"] = ""
	return true


func _settle_rescue_order(order: Dictionary, state: BattleState, outcome: BattleOutcome) -> void:
	var incident_index: int = _incident_index(str(order.get("incident_id", "")))
	if incident_index < 0:
		return
	var incident: Dictionary = stranded_incidents[incident_index]
	var remaining: Array[String] = _string_array(incident.get("hero_ids"))
	for secured_id: String in outcome.secured_hero_ids:
		remaining.erase(secured_id)
	for stranded_id: String in outcome.stranded_hero_ids:
		if hero_by_id(stranded_id) != null and not remaining.has(stranded_id):
			remaining.append(stranded_id)
	incident["hero_ids"] = remaining
	incident["active_rescue_order_id"] = ""
	incident["battle_snapshot"] = _incident_snapshot(state, remaining)
	if remaining.is_empty():
		stranded_incidents.remove_at(incident_index)
	elif bool(incident.get("expiry_pending", false)) or _incident_remaining_seconds(incident) <= 0.0:
		Expedition.finalize_permanent_losses(remaining, StringName(str(incident.get("zone_id", ""))))
		stranded_incidents.remove_at(incident_index)
	_notify_expeditions_changed()


func _incident_snapshot(state: BattleState, stranded_ids: Array[String]) -> Dictionary:
	var snapshot: Dictionary = state.to_dict()
	var kept: Array[Dictionary] = []
	var kept_actor_ids: Dictionary[String, bool] = {}
	for actor: BattleActor in state.actors:
		if actor.faction == "enemy" or actor.hero_id in stranded_ids:
			var data: Dictionary = actor.to_dict()
			if actor.faction == "ally":
				data["squad_id"] = ""
			kept.append(data)
			kept_actor_ids[actor.id] = true
	for actor_data: Dictionary in kept:
		for key: String in ["carried_by_id", "carrying_id", "order_target_id", "guard_target_id"]:
			if not str(actor_data.get(key, "")).is_empty() and not kept_actor_ids.has(str(actor_data.get(key))):
				actor_data[key] = ""
		var effect_state: Dictionary = actor_data.get("effect_state", {}) as Dictionary
		if not str(effect_state.get("attack_target_id", "")).is_empty() and not kept_actor_ids.has(str(effect_state.get("attack_target_id"))):
			effect_state["attack_target_id"] = ""
	snapshot["actors"] = kept
	snapshot["squads"] = []
	snapshot["status"] = "stranded"
	snapshot["downed_ever_ids"] = stranded_ids.duplicate()
	snapshot["extracted_ids"] = []
	return snapshot


func _refund_battle_supplies(remainder: Dictionary) -> void:
	for kind: String in ["healing", "revival"]:
		supplies[kind] = int(supplies.get(kind, 0)) + Item.int_field(remainder, kind, 0, "battle remainder")


func _hero_names(hero_ids: Array[String]) -> Array[String]:
	var names: Array[String] = []
	for hero_id: String in hero_ids:
		var hero: Hero = hero_by_id(hero_id)
		names.append(hero.hero_name if hero != null else hero_id)
	return names


func _append_terminal_report(
	order: Dictionary,
	hero_names: Array[String],
	casualty_names: Array[String],
	outcome: StringName,
	stones_earned: int,
	xp_earned: int,
	items_earned: int,
	stopped_reason: String,
) -> void:
	_append_report(order, hero_names, casualty_names, outcome, stones_earned, xp_earned, items_earned, stopped_reason)


func _append_report(
	order: Dictionary,
	hero_names: Array[String],
	casualty_names: Array[String],
	outcome: StringName,
	stones_earned: int,
	xp_earned: int,
	items_earned: int,
	stopped_reason: String,
) -> void:
	expedition_reports.append({
		"id": Item.new_instance_id(),
		"order_id": str(order.get("id", "")),
		"team_name": str(order.get("team_name", "")),
		"hero_ids": _string_array(order.get("hero_ids")),
		"hero_names": hero_names.duplicate(),
		"zone_id": str(order.get("zone_id", "")),
		"outcome": str(outcome),
		"casualty_names": casualty_names.duplicate(),
		"stones_earned": stones_earned,
		"xp_earned": xp_earned,
		"items_earned": items_earned,
		"cumulative_stones": Item.int_field(order, "cumulative_stones", 0, "expedition order"),
		"cumulative_xp": Item.int_field(order, "cumulative_xp", 0, "expedition order"),
		"cumulative_items": Item.int_field(order, "cumulative_items", 0, "expedition order"),
		"runs_completed": Item.int_field(order, "runs_completed", 0, "expedition order"),
		"total_runs": Item.int_field(order, "total_runs", 1, "expedition order"),
		"stopped_reason": stopped_reason,
	})
	while expedition_reports.size() > MAX_EXPEDITION_REPORTS:
		expedition_reports.pop_front()


func _expire_recovery_caches_in_memory() -> void:
	if recovery_clock_paused:
		return
	var balance: BalanceTable = preload("res://balance.tres")
	var reliquary_level: int = clampi(building_levels[4], 0, balance.summoning_circle_level_cap)
	for cache_index: int in range(lost_caches.size() - 1, -1, -1):
		if LostCache.seconds_remaining(lost_caches[cache_index], recovery_clock_seconds, reliquary_level, balance) < 0.0:
			lost_caches.remove_at(cache_index)


func _expire_stranded_incidents_in_memory() -> void:
	for index: int in range(stranded_incidents.size() - 1, -1, -1):
		var incident: Dictionary = stranded_incidents[index]
		if bool(incident.get("paused", true)) or _incident_remaining_seconds(incident) > 0.0:
			continue
		if not str(incident.get("active_rescue_order_id", "")).is_empty():
			incident["expiry_pending"] = true
			continue
		Expedition.finalize_permanent_losses(_string_array(incident.get("hero_ids")), StringName(str(incident.get("zone_id", ""))))
		stranded_incidents.remove_at(index)


func _team_total_xp(team: Array[Hero]) -> int:
	var total_xp: int = 0
	var balance: BalanceTable = preload("res://balance.tres")
	for hero: Hero in team:
		total_xp += hero.xp
		for level: int in hero.level:
			total_xp += Hero.xp_to_next_level(level, balance)
	return total_xp


func _commit_profile_mutation(mutation: Callable) -> bool:
	if SaveService.load_blocked:
		last_action_error = SaveService.load_block_reason
		return false
	var snapshot: Dictionary = to_dict()
	var paused_snapshot: Dictionary[String, bool] = _paused_battle_orders.duplicate()
	var checkpoint_failed_snapshot: bool = _checkpoint_save_failed
	var checkpoint_error_snapshot: String = _checkpoint_error
	var command_errors_snapshot: Dictionary[String, String] = _command_errors.duplicate()
	snapshot["version"] = SaveService.SAVE_VERSION
	_save_deferred_depth += 1
	_notification_deferred_depth += 1
	# Variant is required because most mutations return void while fallible bulk application returns bool.
	var mutation_result: Variant = mutation.call()
	_save_deferred_depth -= 1
	if mutation_result is bool and not (mutation_result as bool):
		_save_deferred_depth += 1
		from_dict(snapshot)
		_paused_battle_orders = paused_snapshot
		_checkpoint_save_failed = checkpoint_failed_snapshot
		_checkpoint_error = checkpoint_error_snapshot
		_command_errors = command_errors_snapshot
		_save_deferred_depth -= 1
		_notification_deferred_depth -= 1
		_flush_deferred_notifications()
		if last_action_error.is_empty():
			last_action_error = "The profile changed while the operation was being applied."
		return false
	if SaveService.save():
		_notification_deferred_depth -= 1
		_flush_deferred_notifications()
		return true
	_save_deferred_depth += 1
	from_dict(snapshot)
	_paused_battle_orders = paused_snapshot
	_checkpoint_save_failed = checkpoint_failed_snapshot
	_checkpoint_error = checkpoint_error_snapshot
	_command_errors = command_errors_snapshot
	_save_deferred_depth -= 1
	_notification_deferred_depth -= 1
	_flush_deferred_notifications()
	last_action_error = SaveService.last_write_error
	return false


func _upsert_preset_in_memory(preset: Dictionary) -> void:
	var index: int = _preset_index(str(preset.get("id", "")))
	if index >= 0:
		team_presets[index] = preset
	else:
		team_presets.append(preset)
	_notify_roster_changed()


func _delete_preset_in_memory(index: int) -> void:
	team_presets.remove_at(index)
	_notify_roster_changed()


func _append_order_in_memory(order: Dictionary) -> void:
	expedition_orders.append(order)
	_notify_roster_changed()
	_notify_expeditions_changed()


func _request_stop_in_memory(index: int) -> void:
	expedition_orders[index]["stop_requested"] = true
	_notify_roster_changed()
	_notify_expeditions_changed()


func _preset_index(id: String) -> int:
	for index: int in team_presets.size():
		if str(team_presets[index].get("id", "")) == id:
			return index
	return -1


func _order_index(id: String) -> int:
	for index: int in expedition_orders.size():
		if str(expedition_orders[index].get("id", "")) == id:
			return index
	return -1


func item_by_id(id: String) -> Item:
	for item: Item in inventory:
		if item.instance_id == id:
			return item
	for hero: Hero in roster:
		for item: Item in hero.equipped.values():
			if item.instance_id == id:
				return item
	for cache: LostCache in lost_caches:
		for item: Item in cache.items:
			if item.instance_id == id:
				return item
	return null


static func _new_run_seed() -> int:
	return Crypto.new().generate_random_bytes(4).decode_u32(0)


static func _valid_unique_id_list(ids: Array[String]) -> bool:
	if ids.is_empty() or ids.size() > 5:
		return false
	var seen: Dictionary[String, bool] = {}
	for id: String in ids:
		if id.is_empty() or seen.has(id):
			return false
		seen[id] = true
	return true


## Variant is required while validating collection values decoded from JSON.
static func _string_array(value: Variant) -> Array[String]:
	var strings: Array[String] = []
	if not value is Array:
		return strings
	for entry: Variant in value as Array:
		if entry is String:
			strings.append(entry as String)
	return strings


## Variant is required while rebuilding a preview from its serialized-like parameters.
static func _int_array(value: Variant) -> Array[int]:
	var integers: Array[int] = []
	if not value is Array:
		return integers
	for entry: Variant in value as Array:
		if entry is int:
			integers.append(entry as int)
		elif entry is float and is_finite(entry as float) and (entry as float) == floorf(entry as float):
			integers.append(int(entry as float))
	return integers


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
		"version": SaveService.SAVE_VERSION,
		"roster": entries,
		"inventory": inventory_entries,
		"parts": parts.duplicate(),
		"building_levels": building_levels.duplicate(),
		"essence": essence,
		"stones": stones,
		"turns": turns,
		"lost_caches": lost_cache_entries,
		"cleared_zone_ids": cleared_entries,
		"team_presets": team_presets.duplicate(true),
		"expedition_orders": expedition_orders.duplicate(true),
		"expedition_reports": expedition_reports.duplicate(true),
		"supplies": supplies.duplicate(true),
		"stranded_incidents": stranded_incidents.duplicate(true),
		"rescue_clock_seconds": rescue_clock_seconds,
		"recovery_clock_seconds": recovery_clock_seconds,
		"recovery_clock_paused": recovery_clock_paused,
		"saved_at_unix": saved_at_unix,
		"embodied_hero_id": embodied_hero_id,
		"town_buildings": town_buildings.duplicate(true),
		"town_resources": town_resources.duplicate(),
		"town_next_id": town_next_id,
	}


func from_dict(data: Dictionary) -> void:
	roster.clear()
	inventory.clear()
	parts.fill(0)
	building_levels.fill(0)
	essence = 0
	stones = STARTING_STONES
	turns = 0
	lost_caches.clear()
	cleared_zone_ids.clear()
	team_presets.clear()
	expedition_orders.clear()
	expedition_reports.clear()
	supplies = {"healing": 3, "revival": 1}
	stranded_incidents.clear()
	rescue_clock_seconds = 0.0
	_paused_battle_orders.clear()
	_checkpoint_save_failed = false
	_checkpoint_error = ""
	_command_errors.clear()
	recovery_clock_seconds = 0.0
	recovery_clock_paused = false
	saved_at_unix = 0.0
	for entry: Variant in _array_field(data, "roster"):
		if entry is Dictionary:
			roster.append(Hero.from_dict(entry))
	_read_town(data)
	_clear_bad_town_claims()
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
	stones = maxi(Item.int_field(data, "stones", STARTING_STONES, "game session"), 0)
	turns = maxi(Item.int_field(data, "turns", 0, "game session"), 0)
	for entry: Variant in _array_field(data, "lost_caches"):
		if entry is Dictionary:
			lost_caches.append(LostCache.from_dict(entry))
	for zone_id: Variant in _array_field(data, "cleared_zone_ids"):
		if zone_id is String:
			cleared_zone_ids[StringName(zone_id as String)] = true
	var save_version: int = Item.int_field(data, "version", 1, "game session")
	for entry: Variant in _array_field(data, "team_presets"):
		if entry is Dictionary:
			team_presets.append((entry as Dictionary).duplicate(true))
	for entry: Variant in _array_field(data, "expedition_orders"):
		if entry is Dictionary:
			expedition_orders.append((entry as Dictionary).duplicate(true))
	for entry: Variant in _array_field(data, "expedition_reports"):
		if entry is Dictionary:
			expedition_reports.append((entry as Dictionary).duplicate(true))
	while expedition_reports.size() > MAX_EXPEDITION_REPORTS:
		expedition_reports.pop_front()
	if save_version >= 2:
		recovery_clock_seconds = maxf(Item.float_field(data, "recovery_clock_seconds", 0.0, "game session"), 0.0)
		var raw_recovery_paused: Variant = data.get("recovery_clock_paused")
		if raw_recovery_paused is bool:
			recovery_clock_paused = raw_recovery_paused as bool
		saved_at_unix = maxf(Item.float_field(data, "saved_at_unix", 0.0, "game session"), 0.0)
	else:
		# One legacy expedition turn becomes one elapsed active recovery minute. Keeping both the
		# global clock and each cache's creation point preserves its effective remaining window.
		recovery_clock_seconds = float(turns) * 60.0
		for cache: LostCache in lost_caches:
			cache.recovery_created_at = float(cache.turn_lost) * 60.0
		recovery_clock_paused = not lost_caches.is_empty()
	if save_version >= 3:
		var saved_supplies: Variant = data.get("supplies")
		if saved_supplies is Dictionary:
			supplies = {"healing": Item.int_field(saved_supplies as Dictionary, "healing", 0, "profile supplies"), "revival": Item.int_field(saved_supplies as Dictionary, "revival", 0, "profile supplies")}
		for entry: Variant in _array_field(data, "stranded_incidents"):
			if entry is Dictionary:
				stranded_incidents.append((entry as Dictionary).duplicate(true))
		rescue_clock_seconds = maxf(Item.float_field(data, "rescue_clock_seconds", 0.0, "game session"), 0.0)
	# Additive key. Missing, stale or away loads as no body: the town is then the overview.
	var raw_body: Variant = data.get("embodied_hero_id")
	var body: Hero = hero_by_id(raw_body as String) if raw_body is String else null
	embodied_hero_id = body.instance_id if body != null and not is_hero_busy(body) else NO_BODY
	_notify_roster_changed()
	_notify_expeditions_changed()


## Additive keys (no SAVE_VERSION bump). A save without town_resources gets town_start_wood once.
## A building that is malformed, off the map, on a hall or on another building is dropped.
func _read_town(data: Dictionary) -> void:
	var balance: BalanceTable = preload("res://balance.tres")
	town_buildings.clear()
	town_resources = {"wood": balance.town_start_wood}
	var raw_resources: Variant = data.get("town_resources")
	if raw_resources is Dictionary:
		town_resources["wood"] = maxf(Item.float_field(raw_resources as Dictionary, "wood", 0.0, "town resources"), 0.0)
	elif raw_resources != null:
		push_error("Invalid town_resources: expected Dictionary, got %s." % type_string(typeof(raw_resources)))
		town_resources["wood"] = 0.0
	var highest: int = 0
	for entry: Variant in _array_field(data, "town_buildings"):
		var building: Dictionary = _read_town_building(entry)
		if building.is_empty():
			push_warning("Invalid town building %s; dropped." % str(entry))
			continue
		town_buildings.append(building)
		highest = maxi(highest, String(building["id"]).get_slice("_", 1).to_int())
	town_next_id = maxi(Item.int_field(data, "town_next_id", 1, "game session"), highest + 1)


## {} unless entry is a well-formed building on a free hex with an unused id.
func _read_town_building(entry: Variant) -> Dictionary:
	if not entry is Dictionary:
		return {}
	var raw: Dictionary = entry as Dictionary
	var raw_id: Variant = raw.get("id")
	var raw_type: Variant = raw.get("type")
	if not raw_id is String or not raw_type is String or TownRules.type_of(StringName(raw_id as String)) != StringName(raw_type as String):
		return {}
	if not town_building(StringName(raw_id as String)).is_empty():
		return {}
	var hex := Vector2i.ZERO
	for axis: int in 2:
		var value: Variant = raw.get(["q", "r"][axis])
		if value is float and is_finite(value as float) and (value as float) == floorf(value as float):
			value = int(value as float)
		if not value is int:
			return {}
		hex[axis] = value as int
	if not TownRules.hex_refusal(hex, town_buildings, preload("res://balance.tres")).is_empty():
		return {}
	return {"id": raw_id as String, "type": raw_type as String, "q": hex.x, "r": hex.y}


## One keeper per hall; a house or workplace keeps at most its capacity, the first in roster order.
## A job or home at a building that is gone is cleared, and so is a workplace job without a home.
func _clear_bad_town_claims() -> void:
	var balance: BalanceTable = preload("res://balance.tres")
	var claims: Dictionary[StringName, int] = {}
	for hero: Hero in roster:
		if hero.home != Hero.NO_HOME:
			var house_name: String = String(hero.home).capitalize()
			if town_building(hero.home).is_empty():
				push_warning("%s's house, %s, is gone; its home was cleared." % [hero.hero_name, house_name])
				hero.home = Hero.NO_HOME
			elif claims.get(hero.home, 0) >= balance.house_capacity:
				push_warning("%s is full; %s's home was cleared." % [house_name, hero.hero_name])
				hero.home = Hero.NO_HOME
			else:
				claims[hero.home] = claims.get(hero.home, 0) + 1
		if hero.station == Hero.NO_STATION:
			continue
		var place_name: String = String(hero.station).capitalize()
		var capacity: int = 1
		if not Hero.is_staffable(hero.station):
			capacity = TownRules.worker_slots(TownRules.type_of(hero.station), balance)
			if town_building(hero.station).is_empty():
				push_warning("%s's workplace, the %s, is gone; its job was cleared." % [hero.hero_name, place_name])
				hero.station = Hero.NO_STATION
				continue
			if hero.home == Hero.NO_HOME:
				push_warning("%s has no house, so it left the %s." % [hero.hero_name, place_name])
				hero.station = Hero.NO_STATION
				continue
		if claims.get(hero.station, 0) < capacity:
			claims[hero.station] = claims.get(hero.station, 0) + 1
		elif capacity == 1 and Hero.is_staffable(hero.station):
			push_warning("%s also claimed the %s; its station was cleared." % [hero.hero_name, hero.station])
			hero.station = Hero.NO_STATION
		else:
			push_warning("The %s is full; %s's job was cleared." % [place_name, hero.hero_name])
			hero.station = Hero.NO_STATION


## Dictionary.get()'s default only applies to a *missing* key, so an explicit "roster": null
## in a hand-edited or corrupt save reaches the loop as Nil and errors out. Coerce here rather
## than at each call site - all persisted collection fields have the same untrusted shape.
static func _array_field(data: Dictionary, key: String) -> Array:
	# Variant is required while validating untrusted save entries.
	var value: Variant = data.get(key)
	return value if value is Array else []


## A rescue dispatched before ig-4zi carried its stranded actors' timestamps from their old battle,
## ahead of the rescue's own tick, and that save could no longer load. Clamps them in place.
static func repair_rescue_timestamps(data: Dictionary) -> void:
	var battles: Array = []
	if data.get("expedition_orders") is Array:
		for order: Variant in data.get("expedition_orders") as Array:
			if order is Dictionary:
				battles.append((order as Dictionary).get("battle"))
	# A rescue that settles with heroes still stranded rebuilds its incident from the rescue state.
	if data.get("stranded_incidents") is Array:
		for incident: Variant in data.get("stranded_incidents") as Array:
			if incident is Dictionary:
				battles.append((incident as Dictionary).get("battle_snapshot"))
	for raw_battle: Variant in battles:
		if raw_battle is not Dictionary:
			continue
		var battle: Dictionary = raw_battle as Dictionary
		if str(battle.get("kind", "")) != "rescue" or not _is_nonnegative_integer(battle.get("tick")) or battle.get("actors") is not Array:
			continue
		var tick: int = int(battle["tick"])
		for raw_actor: Variant in battle["actors"]:
			if raw_actor is Dictionary and (raw_actor as Dictionary).get("effect_state") is Dictionary:
				var effects: Dictionary = (raw_actor as Dictionary)["effect_state"]
				for key: String in ["last_hit_tick", "last_skill_tick", "last_crit_tick"]:
					if _is_nonnegative_integer(effects.get(key)) and int(effects[key]) > tick:
						effects[key] = tick


static func validate_saved_state(data: Dictionary, version: int) -> String:
	if version < 2:
		return ""
	if version >= 3:
		if not data.get("supplies") is Dictionary or not data.get("stranded_incidents") is Array:
			return "v3 supplies must be a Dictionary and stranded_incidents an Array."
		if not _is_nonnegative_number(data.get("rescue_clock_seconds")):
			return "rescue_clock_seconds must be finite and non-negative."
		var saved_supplies: Dictionary = data.get("supplies") as Dictionary
		if saved_supplies.size() != 2 or not _is_nonnegative_integer(saved_supplies.get("healing")) or not _is_nonnegative_integer(saved_supplies.get("revival")):
			return "Profile supplies must contain exactly non-negative healing and revival integers."
	for key: String in ["roster", "inventory", "lost_caches", "cleared_zone_ids", "team_presets", "expedition_orders", "expedition_reports"]:
		if not data.get(key) is Array:
			return "%s must be an Array." % key
	if not data.get("recovery_clock_paused") is bool:
		return "recovery_clock_paused must be a bool."
	if not _is_nonnegative_number(data.get("recovery_clock_seconds")):
		return "recovery_clock_seconds must be finite and non-negative."
	if not _is_nonnegative_number(data.get("saved_at_unix")):
		return "saved_at_unix must be finite and non-negative."
	var recovery_clock: float = float(data.get("recovery_clock_seconds"))
	var object_ids: Dictionary[String, bool] = {}
	var live_hero_ids: Dictionary[String, bool] = {}

	for raw_hero: Variant in data.get("roster") as Array:
		if not raw_hero is Dictionary:
			return "Every roster entry must be a Dictionary."
		var hero_data: Dictionary = raw_hero as Dictionary
		var hero_id: String = _serialized_id(hero_data, "hero")
		if hero_id.is_empty() or object_ids.has(hero_id):
			return "Hero instance IDs must be non-empty and globally unique."
		if not hero_data.get("favorite") is bool:
			return "Hero favorite must be a bool."
		object_ids[hero_id] = true
		live_hero_ids[hero_id] = true
		if not hero_data.get("equipped") is Array:
			return "Hero equipped must be an Array."
		for raw_equipped: Variant in hero_data.get("equipped") as Array:
			if not raw_equipped is Dictionary or not (raw_equipped as Dictionary).get("item") is Dictionary:
				return "Every equipped entry must contain an item Dictionary."
			var item_error: String = _validate_serialized_item(
				(raw_equipped as Dictionary).get("item") as Dictionary,
				object_ids,
		)
			if not item_error.is_empty():
				return item_error

	for raw_item: Variant in data.get("inventory") as Array:
		if not raw_item is Dictionary:
			return "Every inventory entry must be a Dictionary."
		var item_error: String = _validate_serialized_item(raw_item as Dictionary, object_ids)
		if not item_error.is_empty():
			return item_error

	for raw_cache: Variant in data.get("lost_caches") as Array:
		if not raw_cache is Dictionary:
			return "Every lost cache entry must be a Dictionary."
		var cache_data: Dictionary = raw_cache as Dictionary
		if not _is_nonnegative_number(cache_data.get("recovery_created_at")):
			return "Lost-cache recovery_created_at must be finite and non-negative."
		if float(cache_data.get("recovery_created_at")) > recovery_clock:
			return "Lost-cache recovery_created_at cannot be ahead of the recovery clock."
		if not cache_data.get("items") is Array:
			return "Lost-cache items must be an Array."
		for raw_item: Variant in cache_data.get("items") as Array:
			if not raw_item is Dictionary:
				return "Every lost-cache item must be a Dictionary."
			var item_error: String = _validate_serialized_item(raw_item as Dictionary, object_ids)
			if not item_error.is_empty():
				return item_error

	var cleared_ids: Dictionary[String, bool] = {}
	for raw_zone_id: Variant in data.get("cleared_zone_ids") as Array:
		if not raw_zone_id is String or not (raw_zone_id as String) in KNOWN_ZONE_IDS:
			return "cleared_zone_ids contains an unknown zone."
		cleared_ids[raw_zone_id as String] = true

	var preset_ids: Dictionary[String, bool] = {}
	for raw_preset: Variant in data.get("team_presets") as Array:
		if not raw_preset is Dictionary:
			return "Every team preset must be a Dictionary."
		var preset: Dictionary = raw_preset as Dictionary
		var preset_id: String = _serialized_id(preset, "preset")
		if preset_id.is_empty() or preset_ids.has(preset_id):
			return "Preset IDs must be non-empty and unique."
		if not preset.get("name") is String or (preset.get("name") as String).strip_edges().is_empty():
			return "Every team preset needs a name."
		var preset_hero_error: String = _validate_saved_id_array(preset.get("hero_ids"))
		if not preset_hero_error.is_empty():
			return "Invalid preset hero_ids: %s" % preset_hero_error
		if not preset.get("zone_id") is String or not (preset.get("zone_id") as String) in KNOWN_ZONE_IDS:
			return "Every team preset needs a known zone_id."
		preset_ids[preset_id] = true

	var order_ids: Dictionary[String, bool] = {}
	var orders_by_id: Dictionary[String, Dictionary] = {}
	var busy_hero_ids: Dictionary[String, bool] = {}
	for raw_order: Variant in data.get("expedition_orders") as Array:
		if not raw_order is Dictionary:
			return "Every expedition order must be a Dictionary."
		var order: Dictionary = raw_order as Dictionary
		var order_id: String = _serialized_id(order, "order")
		if order_id.is_empty() or order_ids.has(order_id):
			return "Expedition order IDs must be non-empty and unique."
		var order_hero_error: String = _validate_saved_force_id_array(order.get("hero_ids")) if version >= 3 else _validate_saved_id_array(order.get("hero_ids"))
		if not order_hero_error.is_empty():
			return "Invalid expedition hero_ids: %s" % order_hero_error
		for hero_id: String in _string_array(order.get("hero_ids")):
			if not live_hero_ids.has(hero_id):
				return "An active expedition references a missing hero."
			if busy_hero_ids.has(hero_id):
				return "A hero appears in more than one active expedition."
			busy_hero_ids[hero_id] = true
		if not order.get("zone_id") is String:
			return "An expedition zone_id must be a String."
		var order_zone_id: String = order.get("zone_id") as String
		if not _serialized_zone_unlocked(order_zone_id, cleared_ids):
			return "An active expedition targets an unknown or locked zone."
		for string_key: String in ["team_name", "preset_id"]:
			if not order.get(string_key) is String:
				return "Expedition %s must be a String." % string_key
		for int_key: String in ["total_runs", "runs_completed", "run_seed", "cumulative_stones", "cumulative_xp", "cumulative_items"]:
			if not _is_nonnegative_integer(order.get(int_key)):
				return "Expedition %s must be a non-negative integer." % int_key
		var total_runs: int = int(order.get("total_runs"))
		var runs_completed: int = int(order.get("runs_completed"))
		if total_runs > 999 or (total_runs > 0 and runs_completed >= total_runs):
			return "Active expedition run counts are invalid."
		if not order.get("stop_requested") is bool:
			return "Expedition stop_requested must be a bool."
		var saved_rescue: bool = version >= 3 and order.get("battle") is Dictionary and str((order.get("battle") as Dictionary).get("kind", "")) == "rescue"
		if saved_rescue:
			if not _is_nonnegative_number(order.get("initial_duration_seconds")) or float(order.get("initial_duration_seconds")) != 0.0:
				return "Rescue initial_duration_seconds must be zero."
		elif not _is_positive_number(order.get("initial_duration_seconds")):
			return "Expedition initial_duration_seconds must be finite and positive."
		if not _is_nonnegative_number(order.get("remaining_seconds")):
			return "Expedition remaining_seconds must be finite and non-negative."
		if float(order.get("remaining_seconds")) > float(order.get("initial_duration_seconds")):
			return "Expedition remaining_seconds cannot exceed initial_duration_seconds."
		if saved_rescue and float(order.get("remaining_seconds")) != 0.0:
			return "Rescue remaining_seconds must be zero."
		if version >= 3:
			for key: String in ["backend", "phase"]:
				if not order.get(key) is String:
					return "Battle order %s must be a String." % key
			if str(order.get("backend")) != "battle_v1" or not str(order.get("phase")) in ["fighting", "rescuing", "returning"]:
				return "Battle order backend or phase is invalid."
			if not order.get("battle") is Dictionary:
				return "Battle order checkpoint must be a Dictionary."
			var battle_error: String = BattleSimulation.validate_snapshot(order.get("battle") as Dictionary)
			if not battle_error.is_empty():
				return battle_error
			var order_contract_error: String = _validate_saved_battle_order(order, order_id, order_zone_id)
			if not order_contract_error.is_empty():
				return order_contract_error
		order_ids[order_id] = true
		orders_by_id[order_id] = order
	if version >= 3:
		var incident_ids: Dictionary[String, bool] = {}
		var incident_heroes: Dictionary[String, bool] = {}
		var linked_rescue_order_ids: Dictionary[String, bool] = {}
		for raw_incident: Variant in data.get("stranded_incidents") as Array:
			if not raw_incident is Dictionary:
				return "Every stranded incident must be a Dictionary."
			var incident: Dictionary = raw_incident as Dictionary
			for key: String in ["id", "source_order_id", "zone_id", "active_rescue_order_id"]:
				if not incident.get(key) is String:
					return "Stranded incident %s must be a String." % key
			var incident_id: String = str(incident.get("id"))
			if incident_id.is_empty() or incident_ids.has(incident_id):
				return "Stranded incident IDs must be unique and non-empty."
			if str(incident.get("source_order_id", "")).is_empty():
				return "A stranded incident needs its source order ID."
			incident_ids[incident_id] = true
			if not incident.get("paused") is bool or not incident.get("expiry_pending") is bool or not _is_nonnegative_number(incident.get("created_recovery_seconds")):
				return "Stranded incident timer state is invalid."
			if float(incident.get("created_recovery_seconds")) > float(data.get("rescue_clock_seconds")):
				return "Stranded incident age cannot begin ahead of the rescue clock."
			if not str(incident.get("zone_id")) in KNOWN_ZONE_IDS:
				return "A stranded incident references an unknown zone."
			var incident_hero_error: String = _validate_saved_incident_id_array(incident.get("hero_ids"))
			if not incident_hero_error.is_empty():
				return "Invalid stranded hero_ids: %s" % incident_hero_error
			for hero_id: String in _string_array(incident.get("hero_ids")):
				if not live_hero_ids.has(hero_id) or incident_heroes.has(hero_id):
					return "Stranded heroes must exist and belong to one incident."
				incident_heroes[hero_id] = true
			if not incident.get("battle_snapshot") is Dictionary:
				return "Stranded incident battle_snapshot must be a Dictionary."
			var incident_snapshot: Dictionary = incident.get("battle_snapshot") as Dictionary
			var incident_battle_error: String = BattleSimulation.validate_snapshot(incident_snapshot)
			if not incident_battle_error.is_empty():
				return "Invalid stranded incident checkpoint: %s" % incident_battle_error
			if str(incident_snapshot.get("zone_id", "")) != str(incident.get("zone_id", "")) or str(incident_snapshot.get("status", "")) != "stranded":
				return "Stranded incident checkpoint identity is invalid."
			var snapshot_heroes: Dictionary[String, bool] = {}
			for raw_actor: Variant in incident_snapshot.get("actors") as Array:
				if raw_actor is Dictionary and str((raw_actor as Dictionary).get("faction", "")) == "ally":
					snapshot_heroes[str((raw_actor as Dictionary).get("hero_id", ""))] = true
			for hero_id: String in _string_array(incident.get("hero_ids")):
				if not snapshot_heroes.has(hero_id):
					return "Every stranded hero must exist in its incident checkpoint."
			if snapshot_heroes.size() != _string_array(incident.get("hero_ids")).size():
				return "Incident checkpoints cannot retain already secured heroes."
			var source_order_id: String = str(incident.get("source_order_id", ""))
			if order_ids.has(source_order_id) and str(orders_by_id[source_order_id].get("incident_id", "")) != incident_id:
				return "A stranded incident source-order reference is incoherent."
			var active_rescue_id: String = str(incident.get("active_rescue_order_id", ""))
			if (bool(incident.get("expiry_pending", false)) and active_rescue_id.is_empty()) or (not active_rescue_id.is_empty() and bool(incident.get("paused", true))):
				return "A stranded incident rescue timer state is incoherent."
			if not active_rescue_id.is_empty():
				if not order_ids.has(active_rescue_id):
					return "A stranded incident references a missing active rescue."
				if linked_rescue_order_ids.has(active_rescue_id):
					return "An active rescue order cannot belong to multiple stranded incidents."
				var active_order: Dictionary = orders_by_id[active_rescue_id]
				if str(active_order.get("incident_id", "")) != incident_id or not str(active_order.get("phase", "")) in ["rescuing", "returning"]:
					return "A stranded incident active rescue reference is incoherent."
				if str(active_order.get("zone_id", "")) != str(incident.get("zone_id", "")):
					return "An active rescue order and its stranded incident must use the same zone."
				linked_rescue_order_ids[active_rescue_id] = true
				var active_battle: Dictionary = active_order.get("battle") as Dictionary
				var active_ally_ids: Dictionary[String, bool] = _battle_ally_hero_ids(active_battle)
				var expected_active_ids: Dictionary[String, bool] = {}
				for hero_id: String in _string_array(active_order.get("hero_ids")):
					expected_active_ids[hero_id] = true
				for hero_id: String in _string_array(incident.get("hero_ids")):
					expected_active_ids[hero_id] = true
				if active_ally_ids != expected_active_ids:
					return "A rescue checkpoint must contain exactly its rescuers and incident heroes."
		for order_id: String in orders_by_id:
			var saved_order: Dictionary = orders_by_id[order_id]
			var saved_battle: Dictionary = saved_order.get("battle") as Dictionary
			if str(saved_battle.get("kind", "")) == "rescue" and not linked_rescue_order_ids.has(order_id):
				return "Every active rescue order must have one matching stranded incident backlink."

	var reports: Array = data.get("expedition_reports") as Array
	if reports.size() > MAX_EXPEDITION_REPORTS:
		return "No more than %d expedition reports may be saved." % MAX_EXPEDITION_REPORTS
	var report_ids: Dictionary[String, bool] = {}
	for raw_report: Variant in reports:
		if not raw_report is Dictionary:
			return "Every expedition report must be a Dictionary."
		var report: Dictionary = raw_report as Dictionary
		var report_id: String = _serialized_id(report, "report")
		if report_id.is_empty() or report_ids.has(report_id):
			return "Expedition report IDs must be non-empty and unique."
		for count_key: String in ["stones_earned", "xp_earned", "items_earned", "cumulative_stones", "cumulative_xp", "cumulative_items", "runs_completed", "total_runs"]:
			if not _is_nonnegative_integer(report.get(count_key)):
				return "Expedition report %s must be a non-negative integer." % count_key
		report_ids[report_id] = true
	return ""


static func _validate_saved_battle_order(order: Dictionary, order_id: String, zone_id: String) -> String:
	for key: String in ["loadout", "policies", "escrow"]:
		if not order.get(key) is Dictionary:
			return "Battle order %s must be a Dictionary." % key
	var loadout_error: String = _validate_loadout(order.get("loadout") as Dictionary)
	if not loadout_error.is_empty():
		return loadout_error
	var hero_ids: Array[String] = _string_array(order.get("hero_ids"))
	var deployed: Dictionary[String, bool] = {}
	for hero_id: String in hero_ids:
		deployed[hero_id] = true
	var escrow: Dictionary = order.get("escrow") as Dictionary
	if escrow.size() != 2 or not _is_nonnegative_integer(escrow.get("healing")) or not _is_nonnegative_integer(escrow.get("revival")):
		return "Battle escrow must contain exactly non-negative healing and revival integers."
	var battle: Dictionary = order.get("battle") as Dictionary
	if str(battle.get("order_id", "")) != order_id or str(battle.get("zone_id", "")) != zone_id:
		return "Battle order and checkpoint identities do not match."
	if (battle.get("policies") as Dictionary) != (order.get("policies") as Dictionary):
		return "Battle order and checkpoint policies do not match."
	var remaining_supplies: Dictionary = battle.get("supplies_remaining") as Dictionary
	for kind: String in ["healing", "revival"]:
		if int(remaining_supplies.get(kind, 0)) > int(escrow.get(kind, 0)):
			return "Battle checkpoint supplies cannot exceed escrow."
	var preset_ids_error: String = _validate_saved_squad_id_array(order.get("preset_ids"))
	if not preset_ids_error.is_empty():
		return "Invalid battle preset_ids: %s" % preset_ids_error
	if not order.get("squads") is Array:
		return "Battle order squads must be an Array."
	var squads: Array = order.get("squads") as Array
	var preset_ids: Array[String] = _string_array(order.get("preset_ids"))
	if squads.size() != preset_ids.size() or squads.size() > 10:
		return "Battle squads must match selected preset IDs."
	var squad_heroes: Dictionary[String, bool] = {}
	for squad_index: int in squads.size():
		if not squads[squad_index] is Dictionary:
			return "Every battle squad must be a Dictionary."
		var squad: Dictionary = squads[squad_index] as Dictionary
		if str(squad.get("id", "")) != preset_ids[squad_index] or not squad.get("name") is String or not squad.get("stance") is String or not str(squad.get("stance")) in BattleSimulation.STANCES or not squad.get("guard_target_id") is String:
			return "Battle squad identity or stance is invalid."
		var squad_ids_error: String = _validate_saved_id_array(squad.get("hero_ids"))
		if not squad_ids_error.is_empty():
			return "Invalid battle squad hero_ids: %s" % squad_ids_error
		for hero_id: String in _string_array(squad.get("hero_ids")):
			if squad_heroes.has(hero_id):
				return "A hero cannot belong to multiple battle squads."
			squad_heroes[hero_id] = true
	if squad_heroes != deployed:
		return "Battle squad membership must match the order hero IDs."
	var kind: String = str(battle.get("kind", ""))
	var incident_id: Variant = order.get("incident_id")
	if not incident_id is String or (kind == "rescue" and (incident_id as String).is_empty()) or (kind == "normal" and not (incident_id as String).is_empty()) or kind not in ["normal", "rescue"]:
		return "Battle kind and incident reference are incoherent."
	var ally_hero_ids: Dictionary[String, bool] = _battle_ally_hero_ids(battle)
	var policy_hero_ids: Dictionary[String, bool] = ally_hero_ids if kind == "rescue" else deployed
	var policies_error: String = _validate_battle_policies(order.get("policies") as Dictionary, policy_hero_ids)
	if not policies_error.is_empty():
		return policies_error
	if kind == "normal":
		var zone: ZoneDefinition = ZoneDefinition.definition_for(StringName(zone_id))
		if zone == null or hero_ids.size() > zone.hero_cap:
			return "A normal battle force exceeds its authored zone capacity."
		if squads.size() > _zone_squad_cap(zone):
			return "A normal battle force exceeds its authored squad capacity."
		if ally_hero_ids != deployed:
			return "A normal battle checkpoint must contain exactly its order heroes."
	else:
		if hero_ids.size() > 5:
			return "A rescue attempt may deploy at most five rescuers."
		for hero_id: String in hero_ids:
			if not ally_hero_ids.has(hero_id):
				return "Every rescue order hero must exist in its checkpoint."
	var battle_squads: Dictionary[String, Dictionary] = {}
	for raw_squad: Variant in battle.get("squads") as Array:
		var battle_squad: Dictionary = raw_squad as Dictionary
		battle_squads[str(battle_squad.get("id", ""))] = battle_squad
	for order_squad: Variant in squads:
		var saved_squad: Dictionary = order_squad as Dictionary
		var squad_id: String = str(saved_squad.get("id", ""))
		if not battle_squads.has(squad_id):
			return "Battle checkpoint squads must match the order composition."
		var state_squad: Dictionary = battle_squads[squad_id]
		if _string_array(state_squad.get("hero_ids")) != _string_array(saved_squad.get("hero_ids")) or str(state_squad.get("stance", "")) != str(saved_squad.get("stance", "")) or str(state_squad.get("guard_target_id", "")) != str(saved_squad.get("guard_target_id", "")):
			return "Battle checkpoint squad policy must match its order."
	var status: String = str(battle.get("status", ""))
	var phase: String = str(order.get("phase", ""))
	if (phase in ["fighting", "rescuing"] and status != "active") or (phase == "returning" and status == "active"):
		return "Battle phase does not match checkpoint status."
	return ""


static func _zone_squad_cap(zone: ZoneDefinition) -> int:
	match zone.battle_kind:
		"raid":
			return 6
		"region":
			return 10
		_:
			return 1


static func _battle_ally_hero_ids(battle: Dictionary) -> Dictionary[String, bool]:
	var result: Dictionary[String, bool] = {}
	for raw_actor: Variant in battle.get("actors") as Array:
		if raw_actor is Dictionary and str((raw_actor as Dictionary).get("faction", "")) == "ally":
			result[str((raw_actor as Dictionary).get("hero_id", ""))] = true
	return result


static func _validate_serialized_item(item_data: Dictionary, object_ids: Dictionary[String, bool]) -> String:
	var item_id: String = _serialized_id(item_data, "item")
	if item_id.is_empty() or object_ids.has(item_id):
		return "Item instance IDs must be non-empty and globally unique."
	if not item_data.get("favorite") is bool:
		return "Item favorite must be a bool."
	object_ids[item_id] = true
	return ""


static func _serialized_id(data: Dictionary, subject: String) -> String:
	# Variant is required while validating untrusted save fields.
	var raw_id: Variant = data.get("instance_id" if subject == "hero" or subject == "item" else "id")
	return raw_id as String if raw_id is String and not (raw_id as String).is_empty() else ""


## Variant is required because the value comes directly from decoded JSON.
static func _validate_saved_id_array(value: Variant) -> String:
	if not value is Array:
		return "expected an Array"
	var raw_ids: Array = value as Array
	if raw_ids.is_empty() or raw_ids.size() > 5:
		return "expected 1 to 5 IDs"
	var seen: Dictionary[String, bool] = {}
	for raw_id: Variant in raw_ids:
		if not raw_id is String or (raw_id as String).is_empty() or seen.has(raw_id as String):
			return "IDs must be non-empty unique Strings"
		seen[raw_id as String] = true
	return ""


static func _validate_saved_force_id_array(value: Variant) -> String:
	if not value is Array:
		return "expected an Array"
	var raw_ids: Array = value as Array
	if raw_ids.is_empty() or raw_ids.size() > 50:
		return "expected 1 to 50 IDs"
	var seen: Dictionary[String, bool] = {}
	for raw_id: Variant in raw_ids:
		if not raw_id is String or (raw_id as String).is_empty() or seen.has(raw_id as String):
			return "IDs must be non-empty unique Strings"
		seen[raw_id as String] = true
	return ""


static func _validate_saved_squad_id_array(value: Variant) -> String:
	if not value is Array:
		return "expected an Array"
	var raw_ids: Array = value as Array
	if raw_ids.is_empty() or raw_ids.size() > 10:
		return "expected 1 to 10 IDs"
	var seen: Dictionary[String, bool] = {}
	for raw_id: Variant in raw_ids:
		if not raw_id is String or (raw_id as String).is_empty() or seen.has(raw_id as String):
			return "IDs must be non-empty unique Strings"
		seen[raw_id as String] = true
	return ""


static func _validate_saved_incident_id_array(value: Variant) -> String:
	if not value is Array or (value as Array).is_empty():
		return "expected a non-empty Array"
	var seen: Dictionary[String, bool] = {}
	for raw_id: Variant in value as Array:
		if not raw_id is String or (raw_id as String).is_empty() or seen.has(raw_id as String):
			return "IDs must be non-empty unique Strings"
		seen[raw_id as String] = true
	return ""


## Variant is required because the value comes directly from decoded JSON.
static func _is_nonnegative_integer(value: Variant) -> bool:
	if value is int:
		return value as int >= 0
	if value is float:
		var number: float = value as float
		return is_finite(number) and number == floorf(number) and number >= 0.0
	return false


## Variant is required because the value comes directly from decoded JSON.
static func _is_nonnegative_number(value: Variant) -> bool:
	if not (value is int or value is float):
		return false
	var number: float = float(value)
	return is_finite(number) and number >= 0.0


## Variant is required because the value comes directly from decoded JSON.
static func _is_positive_number(value: Variant) -> bool:
	return _is_nonnegative_number(value) and float(value) > 0.0


static func _serialized_zone_unlocked(zone_id: String, cleared_ids: Dictionary[String, bool]) -> bool:
	match zone_id:
		"verdant_outskirts":
			return true
		"ashfall_reaches":
			return cleared_ids.has("verdant_outskirts")
		"sundered_vault":
			return cleared_ids.has("ashfall_reaches")
		"fallen_citadel", "frontier_march":
			return cleared_ids.has("ashfall_reaches")
	return false
