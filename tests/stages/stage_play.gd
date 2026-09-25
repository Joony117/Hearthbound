extends RefCounted

## ig-eek: the stage bot's play, loaded by stage_bot.gd once the autoloads exist. It plays the Early
## stage (SYSTEMS.md § Stage saves) through public GameSession calls on the live clock, sped up, saves
## with no order in flight, and copies save.json + ledger.jsonl into res://tests/fixtures/stages/early/.
## Time passes only through tick_expeditions, STEP seconds at a time. The bot never yields a frame
## mid-run (GameSession._process would advance the battles too); it waits with OS.delay_msec. The
## one private call is _land_battle_checks, the pulse's own landing step, in _wait_for_jobs.
## Every order is fixed-run (1 run), so no dispatch needs a preview; a team comes home after each
## battle and the next pass re-forms it by power.

const BALANCE: BalanceTable = preload("res://balance.tres")
const STEP: float = 5.0
const EARLY_SECONDS: float = 7200.0
const TEAM_SIZE: int = 5
## Circle, Forge, Sanctum, Training Hall, Reliquary: building_levels indices in SYSTEMS' order.
const HALL_ORDER: Array[int] = [0, 1, 3, 2, 4]
## Each producer gets one worker, the Farm first so food stays above zero.
const PRODUCERS: Array[StringName] = [TownRules.FARM, TownRules.LUMBERMILL, TownRules.MINE]
const OUT_DIR: String = "res://tests/fixtures/stages/early/"

var _clock: float = 0.0
var _seen: Dictionary[String, bool] = {}
var _battle_seconds: float = 0.0
var _sent_at: Dictionary[String, float] = {}
var _longest_order: float = 0.0
var _underpowered_sends: int = 0
var _refusals: Dictionary[String, int] = {}
var _failed: bool = false


## The exit code: 0 when the stage saved and its death check held, 2 when that check or an order in
## flight fails it, 1 when the run broke.
func run(args: PackedStringArray) -> int:
	var seed_value: int = 1
	for arg: String in args:
		if arg.begins_with("--seed=") and arg.get_slice("=", 1).is_valid_int():
			seed_value = arg.get_slice("=", 1).to_int()
		else:
			push_error("stage_bot: unknown arg %s" % arg)
			return 1
	if FileAccess.file_exists(SaveService.SAVE_PATH) or not GameSession.roster.is_empty():
		push_error("stage_bot: user:// already holds a save. Run it with a fresh temp APPDATA.")
		return 1
	seed(seed_value)
	print("BOT stage=early seed=%d step=%.1f game_seconds=%.0f" % [seed_value, STEP, EARLY_SECONDS])
	var started: int = Time.get_ticks_msec()
	while true:
		_note_roster()
		if _clock >= EARLY_SECONDS:
			for order: Dictionary in GameSession.expedition_orders.duplicate():
				GameSession.request_stop_expedition(str(order.get("id", "")))
			if GameSession.expedition_orders.is_empty():
				break
		else:
			# Stop dispatching once an order sent now could still be out at the save.
			_play(_clock + maxf(_longest_order, 600.0) * 1.5 < EARLY_SECONDS)
		_step()
		if _failed:
			return 1
	if not SaveService.save():
		push_error("stage_bot: the final save failed: %s" % SaveService.last_write_error)
		return 1
	var wall_seconds: float = (Time.get_ticks_msec() - started) / 1000.0
	var passed: bool = _report(seed_value, wall_seconds)
	_copy_out()
	return 0 if passed else 2


## One pass of the greedy order (SYSTEMS.md § Stage saves).
func _play(dispatching: bool) -> void:
	while GameSession.stones >= BALANCE.summon_pull_cost:
		_ok(GameSession.summon_hero(Summon.roll(GameSession.building_levels[0]), BALANCE), "summon")
		_note_roster()
	var spare: Array[Hero] = []
	var teams: Array[Dictionary] = _form_teams(spare)
	_staff(spare)
	_feed(spare, teams)
	for team: Dictionary in teams:
		_stock_supplies(team["heroes"] as Array[Hero])
	_gear(teams)
	if dispatching:
		teams = _rescue(teams)
		_dispatch(teams)
	_town()


## Idle heroes who are not workers, strongest first, in 5-hero teams. A remainder of 1-4 is a team
## only while no other team exists (a new game's first pull); otherwise it is spare. Presets no order
## holds are rewritten to match, and extras deleted. Returns [{id, heroes}] for the idle teams.
func _form_teams(spare: Array[Hero]) -> Array[Dictionary]:
	var out: Dictionary[String, bool] = {}
	for order: Dictionary in GameSession.expedition_orders:
		for preset_id: Variant in order.get("preset_ids", []) as Array:
			out[str(preset_id)] = true
	var free_ids: Array[String] = []
	var free_members: Array[Array] = []
	for preset: Dictionary in GameSession.team_presets:
		if not out.has(str(preset.get("id", ""))):
			free_ids.append(str(preset.get("id", "")))
			free_members.append(preset.get("hero_ids", []) as Array)
	var pool: Array[Hero] = []
	for hero: Hero in GameSession.roster:
		if not GameSession.is_hero_busy(hero) and hero.station == Hero.NO_STATION:
			pool.append(hero)
	pool.sort_custom(func(first: Hero, second: Hero) -> bool: return _power(first) > _power(second))
	var groups: Array[Array] = []
	var index: int = 0
	while pool.size() - index >= TEAM_SIZE:
		groups.append(pool.slice(index, index + TEAM_SIZE))
		index += TEAM_SIZE
	if groups.is_empty() and out.is_empty() and not pool.is_empty():
		groups.append(pool.duplicate())
		index = pool.size()
	spare.assign(pool.slice(index))
	var teams: Array[Dictionary] = []
	for group_index: int in groups.size():
		var heroes: Array[Hero] = []
		heroes.assign(groups[group_index])
		var ids: Array[String] = []
		for hero: Hero in heroes:
			ids.append(hero.instance_id)
		var preset_id: String = free_ids[group_index] if group_index < free_ids.size() else ""
		if preset_id.is_empty() or free_members[group_index] != ids:
			preset_id = GameSession.save_team_preset(preset_id, "Team %d" % (group_index + 1), ids, "verdant_outskirts")
			_ok(not preset_id.is_empty(), "save_team_preset")
		if not preset_id.is_empty():
			teams.append({"id": preset_id, "heroes": heroes})
	for extra: int in range(groups.size(), free_ids.size()):
		_ok(GameSession.delete_team_preset(free_ids[extra]), "delete_team_preset")
	return teams


## One worker per producer, taken from the weakest spare hero and housed first. With no empty house,
## one goes up (the first is free), and the next spare hero fills it.
func _staff(spare: Array[Hero]) -> void:
	for type: StringName in PRODUCERS:
		var workplace: String = _finished_building(type)
		if workplace.is_empty() or not GameSession.workers_at(StringName(workplace)).is_empty() or spare.is_empty():
			continue
		var house: String = _empty_house()
		if house.is_empty():
			if not _house_going_up():
				_place(TownRules.HOUSE)
			continue
		var worker: Hero = spare.pop_back()
		_ok(GameSession.assign_home(worker, StringName(house)), "assign_home")
		_ok(GameSession.station_hero(worker, StringName(workplace)), "station_hero")


## Spare heroes are fodder for the strongest idle team hero; then every idle team hero ranks up while
## the essence lasts, strongest first.
func _feed(spare: Array[Hero], teams: Array[Dictionary]) -> void:
	if teams.is_empty():
		return
	var target: Hero = (teams[0]["heroes"] as Array[Hero])[0]
	for fodder: Hero in spare:
		for slot: int in fodder.equipped.keys():
			GameSession.unequip_item(fodder, slot)
		_ok(GameSession.sacrifice_hero(fodder, target, BALANCE), "sacrifice_hero")
	spare.clear()
	for team: Dictionary in teams:
		for hero: Hero in team["heroes"] as Array[Hero]:
			while GameSession.essence >= Hero.compute_rank_up_cost(hero, BALANCE) and GameSession.rank_up_hero(hero, BALANCE):
				pass


## Brews the suggested supplies (hub.gd _on_suggested_allocations_pressed: healing = team size,
## revival = 1) from F parts when the stock is short.
func _stock_supplies(heroes: Array[Hero]) -> void:
	var wanted: Dictionary = _suggested(heroes)
	for kind: String in wanted:
		var short: int = int(wanted[kind]) - int(GameSession.supplies.get(kind, 0))
		if short <= 0:
			continue
		var plan: Dictionary = GameSession.preview_bulk_supplies(kind, short, 0)
		if bool(plan.get("valid", false)):
			_ok(GameSession.commit_bulk_plan(plan), "brew " + kind)


## The best item per slot goes on the strongest idle team heroes first, enhanced up to the Forge cap;
## an equipped item is enhanced too when the cap allows. What is left is salvaged for parts.
## ponytail: gear no idle hero wants is salvaged even if a hero who is out would want it.
func _gear(teams: Array[Dictionary]) -> void:
	var heroes: Array[Hero] = []
	for team: Dictionary in teams:
		heroes.append_array(team["heroes"] as Array[Hero])
	heroes.sort_custom(func(first: Hero, second: Hero) -> bool: return _power(first) > _power(second))
	for hero: Hero in heroes:
		for slot: int in hero.equipped.keys():
			var worn: Item = hero.equipped[slot]
			if worn.enhance_level < GameSession.enhance_cap(BALANCE) and GameSession.parts[clampi(worn.rank, 0, 7)] >= Item.compute_enhance_cost(worn, BALANCE):
				GameSession.unequip_item(hero, slot)
				_enhance(worn)
				GameSession.equip_item(hero, worn)
		var best: Dictionary[int, Item] = {}
		for item: Item in GameSession.inventory:
			var definition: EquipmentDefinition = Item.definition_for(item.def_id)
			if definition != null and not item.favorite and (not best.has(definition.slot) or _worth(item) > _worth(best[definition.slot])):
				best[definition.slot] = item
		for slot: int in best:
			if not hero.equipped.has(slot) or _worth(best[slot]) > _worth(hero.equipped[slot]):
				_enhance(best[slot])
				GameSession.equip_item(hero, best[slot])
	for item: Item in GameSession.inventory.duplicate():
		if not item.favorite:
			GameSession.salvage_item(item, BALANCE)


## Every stranded incident gets its window started, and a rescue from an idle team when one is free.
## Returns the teams still idle.
func _rescue(teams: Array[Dictionary]) -> Array[Dictionary]:
	var idle: Array[Dictionary] = teams.duplicate()
	for incident: Dictionary in GameSession.get_stranded_incidents():
		var incident_id: String = str(incident.get("id", ""))
		if bool(incident.get("paused", true)):
			_ok(GameSession.start_rescue_window(incident_id), "start_rescue_window")
		if idle.is_empty() or not str(incident.get("active_rescue_order_id", "")).is_empty() or float(incident.get("remaining_seconds", 0.0)) <= 0.0:
			continue
		var team: Dictionary = idle.pop_front()
		var order_id: String = GameSession.dispatch_rescue(incident_id, str(team["id"]), _loadout(team["heroes"] as Array[Hero]))
		if _ok(not order_id.is_empty(), "dispatch_rescue"):
			_sent_at[order_id] = _clock
	return idle


## Every idle team goes, one run, to the hardest unlocked zone where its power is at least 90% of the
## zone's recommended power as listed. Not scaled down to the team: a force zone scales its route back
## up (x reference_force_size / team size), so a 5-hero team would take about 15 h at Frontier March.
## None qualifying falls back to Verdant, counted as underpowered.
func _dispatch(teams: Array[Dictionary]) -> void:
	for team: Dictionary in teams:
		var heroes: Array[Hero] = team["heroes"] as Array[Hero]
		var zone_id: String = ""
		var hardest: int = -1
		for known: String in GameSession.KNOWN_ZONE_IDS:
			var zone: ZoneDefinition = ZoneDefinition.definition_for(StringName(known))
			if zone == null or heroes.size() > zone.hero_cap or not ExpeditionOrders.is_zone_unlocked(zone.zone_id, GameSession.cleared_zone_ids):
				continue
			if _team_power(heroes) >= 0.9 * zone.recommended_power and zone.recommended_power > hardest:
				hardest = zone.recommended_power
				zone_id = known
		if zone_id.is_empty():
			zone_id = "verdant_outskirts"
			_underpowered_sends += 1
		var preset_ids: Array[String] = [str(team["id"])]
		var order_id: String = GameSession.dispatch_force(preset_ids, zone_id, 1, {}, _loadout(heroes))
		if _ok(not order_id.is_empty(), "dispatch_force"):
			_sent_at[order_id] = _clock


## Free first producers, then one hall upgrade when affordable, the lowest level first in SYSTEMS'
## order. Houses for workers go up in _staff.
func _town() -> void:
	for type: StringName in [TownRules.FARM, TownRules.HOUSE, TownRules.LUMBERMILL, TownRules.MINE]:
		if not _has_building(type):
			_place(type)
	var pick: int = -1
	for index: int in HALL_ORDER:
		if pick < 0 or GameSession.building_levels[index] < GameSession.building_levels[pick]:
			pick = index
	if bool(GameSession.preview_building_upgrade(pick).get("valid", false)):
		_ok(GameSession.upgrade_building(pick, BALANCE), "upgrade_building")


## Advances the game STEP seconds, with no job out and no order checking before and after.
func _step() -> void:
	_wait_for_jobs()
	if _failed:
		return
	for order: Dictionary in GameSession.expedition_orders:
		if str((order.get("battle", {}) as Dictionary).get("status", "")) == "active" and str(order.get("phase", "")) in ["fighting", "rescuing"]:
			_battle_seconds += STEP
	GameSession.tick_expeditions(STEP)
	_clock += STEP
	_wait_for_jobs()
	var live: Dictionary[String, bool] = {}
	for order: Dictionary in GameSession.expedition_orders:
		live[str(order.get("id", ""))] = true
	for order_id: String in _sent_at.keys():
		if not live.has(order_id):
			_longest_order = maxf(_longest_order, _clock - _sent_at[order_id])
			_sent_at.erase(order_id)


func _wait_for_jobs() -> void:
	var deadline: int = Time.get_ticks_msec() + 120000
	while not _settled():
		if Time.get_ticks_msec() > deadline:
			push_error("stage_bot: jobs did not land in 120 s")
			_failed = true
			return
		OS.delay_msec(1)
		GameSession._land_battle_checks()


func _settled() -> bool:
	if not GameSession._battle_jobs.is_empty():
		return false
	return not GameSession.expedition_orders.any(func(order: Dictionary) -> bool: return str(order.get("phase", "")) == "checking")


## The run log: each SYSTEMS check with its value and pass or miss, the death check, the cost gate.
func _report(seed_value: int, wall_seconds: float) -> bool:
	var roster: Array[Hero] = GameSession.roster
	var top_rank: int = 0
	for hero: Hero in roster:
		top_rank = maxi(top_rank, hero.rank)
	var types: Array[String] = []
	for building: Dictionary in GameSession.town_buildings:
		if not TownRules.is_hall(StringName(str(building["id"]))) and not str(building["type"]) in types:
			types.append(str(building["type"]))
	types.sort()
	var top_hall: int = 0
	for level: int in GameSession.building_levels:
		top_hall = maxi(top_hall, level)
	var free_placed: bool = TownRules.FREE_FIRST.all(func(type: StringName) -> bool: return String(type) in types)
	_check("verdant_cleared", GameSession.cleared_zone_ids.has(&"verdant_outskirts"), GameSession.cleared_zone_ids.has(&"verdant_outskirts"))
	_check("heroes 5-10", roster.size(), roster.size() >= 5 and roster.size() <= 10)
	_check("none above D", BALANCE.rank_names[top_rank], top_rank <= 1)
	_check("one team", GameSession.team_presets.size(), GameSession.team_presets.size() == 1)
	_check("free first producers placed", types, free_placed)
	_check("no hall above level 1", GameSession.building_levels, top_hall <= 1)
	print("INFO ledger_records=%d (SYSTEMS: about 20 at pace 6) ledger_next_seq=%d" % [GameSession.ledger.size(), GameSession.ledger_next_seq])
	var died: Dictionary[String, bool] = {}
	for record: Dictionary in GameSession.ledger:
		if str(record.get("kind", "")) == "died":
			died[str(record.get("hero", ""))] = true
	var in_roster: Dictionary[String, bool] = {}
	for hero: Hero in roster:
		in_roster[hero.instance_id] = true
	var unexplained: Array[String] = []
	var missing: int = 0
	for hero_id: String in _seen:
		if not in_roster.has(hero_id):
			missing += 1
			if not died.has(hero_id):
				unexplained.append(hero_id)
	print("DEATHS seen=%d missing=%d died_records=%d unexplained=%s %s" % [_seen.size(), missing, died.size(), unexplained, "pass" if unexplained.is_empty() else "MISS"])
	var game_hours: float = _clock / 3600.0
	print("COST wall_s=%.1f game_s=%.0f wall_s_per_game_h=%.1f battle_s=%.0f battle_s_per_wall_s=%.1f mid_20h_projected_wall_s=%.0f" % [wall_seconds, _clock, wall_seconds / game_hours, _battle_seconds, _battle_seconds / wall_seconds, wall_seconds / game_hours * 20.0])
	print("RUN roster=%d building_levels=%s ledger=%d orders=%d jobs=%d incidents=%d stones=%d essence=%d parts=%s supplies=%s town=%s underpowered_sends=%d longest_order_s=%.0f refusals=%s" % [roster.size(), GameSession.building_levels, GameSession.ledger.size(), GameSession.expedition_orders.size(), GameSession._battle_jobs.size(), GameSession.stranded_incidents.size(), GameSession.stones, GameSession.essence, GameSession.parts, GameSession.supplies, GameSession.town_resources, _underpowered_sends, _longest_order, _refusals])
	print("README seed=%d step=%.1f wall_s=%.1f game_clock_s=%.0f" % [seed_value, STEP, wall_seconds, _clock])
	for hero: Hero in roster:
		print("HERO %s %s %s lvl=%d power=%.0f station=%s" % [hero.instance_id, hero.hero_name, BALANCE.rank_names[hero.rank], hero.level, _power(hero), hero.station])
	return unexplained.is_empty() and GameSession.expedition_orders.is_empty()


func _check(label: String, value: Variant, passed: bool) -> void:
	print("CHECK %s value=%s %s" % [label, value, "pass" if passed else "MISS"])


func _copy_out() -> void:
	var out: String = ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out)
	for path: String in [SaveService.SAVE_PATH, SaveService.LEDGER_PATH]:
		var error: Error = DirAccess.copy_absolute(ProjectSettings.globalize_path(path), out.path_join(path.get_file()))
		if error != OK:
			push_error("stage_bot: copying %s failed: %s" % [path, error_string(error)])
	print("OUT %s" % out)


func _note_roster() -> void:
	for hero: Hero in GameSession.roster:
		_seen[hero.instance_id] = true


## Counts refused calls by name; a player would just see the message and move on.
func _ok(done: bool, what: String) -> bool:
	if not done:
		_refusals[what] = _refusals.get(what, 0) + 1
	return done


func _enhance(item: Item) -> void:
	while GameSession.enhance_item(item, BALANCE):
		pass


func _suggested(heroes: Array[Hero]) -> Dictionary:
	return {"healing": heroes.size(), "revival": 1}


func _loadout(heroes: Array[Hero]) -> Dictionary:
	var wanted: Dictionary = _suggested(heroes)
	var loadout: Dictionary = {}
	for kind: String in BattleState.SUPPLY_KINDS:
		loadout[kind] = mini(int(wanted.get(kind, 0)), int(GameSession.supplies.get(kind, 0)))
		loadout["keep_" + kind] = 0
	return loadout


func _power(hero: Hero) -> float:
	var team: Array[Hero] = [hero]
	return _team_power(team)


func _team_power(heroes: Array[Hero]) -> float:
	var definitions: Array[HeroDefinition] = []
	var levels: Array[int] = []
	for hero: Hero in heroes:
		var definition: HeroDefinition = Hero.definition_for(hero.def_id)
		if definition == null:
			return 0.0
		definitions.append(definition)
		levels.append(Hero.level_for(hero, BALANCE))
	return Hero.compute_team_power(heroes, definitions, levels, BALANCE)


func _worth(item: Item) -> float:
	var definition: EquipmentDefinition = Item.definition_for(item.def_id)
	return Item.compute_stat_magnitude(item, definition, BALANCE) if definition != null else 0.0


func _has_building(type: StringName) -> bool:
	return GameSession.town_buildings.any(func(building: Dictionary) -> bool: return str(building["type"]) == String(type))


func _finished_building(type: StringName) -> String:
	for building: Dictionary in GameSession.town_buildings:
		if str(building["type"]) == String(type) and GameSession.still_building(StringName(str(building["id"]))).is_empty():
			return str(building["id"])
	return ""


func _empty_house() -> String:
	for building: Dictionary in GameSession.town_buildings:
		var house_id := StringName(str(building["id"]))
		if str(building["type"]) == String(TownRules.HOUSE) and GameSession.still_building(house_id).is_empty() and GameSession.residents_of(house_id).is_empty():
			return String(house_id)
	return ""


func _house_going_up() -> bool:
	return GameSession.town_buildings.any(func(building: Dictionary) -> bool: return str(building["type"]) == String(TownRules.HOUSE) and building.has("build_remaining"))


## The free hex nearest the town centre that place_building would take.
func _place(type: StringName) -> void:
	var hexes: Array[Vector2i] = TownRules.map_hexes(BALANCE)
	hexes.sort_custom(func(first: Vector2i, second: Vector2i) -> bool: return TownRules.ring_distance(first) < TownRules.ring_distance(second))
	for hex: Vector2i in hexes:
		if bool(GameSession.preview_place_building(type, hex).get("valid", false)):
			_ok(GameSession.place_building(type, hex), "place " + String(type))
			return
