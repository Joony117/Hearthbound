extends RefCounted

## ig-eek: the stage bot's play, loaded by stage_bot.gd once the autoloads exist. It plays one stage
## (--stage=early|mid, SYSTEMS.md § Stage saves) through public GameSession calls on the live clock,
## sped up, saves with no order in flight, and copies save.json + ledger.jsonl into
## res://tests/fixtures/stages/<stage>/.
## Time passes only through tick_expeditions, STEP seconds at a time. The bot never yields a frame
## mid-run (GameSession._process would advance the battles too); it waits with OS.delay_msec. The
## one private call is _land_battle_checks, the pulse's own landing step, in _wait_for_jobs.
## Every order is fixed-run (1 run), so no dispatch needs a preview; a team comes home after each
## battle and the next pass re-forms it by power.
## ig-0og.1: it keeps what it can house. Workplaces for the staff, then Houses while wood allows, then
## the strongest homeless into beds; the homeless beyond the grace (less the Houses going up) are fed.
## ig-eek.1: a HOUR line each game hour and an ECON line at the end, for the economy's settle table.

const BALANCE: BalanceTable = preload("res://balance.tres")
const STEP: float = 5.0
## Each stage's game clock (SYSTEMS.md § Stage saves). Late is set by the Ledger cap (ig-eek.2).
const STAGE_SECONDS: Dictionary[String, float] = {"early": 7200.0, "mid": 72000.0}
const TEAM_SIZE: int = 5
## Circle, Forge, Sanctum, Training Hall, Reliquary: building_levels indices in SYSTEMS' order.
const HALL_ORDER: Array[int] = [0, 1, 3, 2, 4]
## Staffed to _workers_wanted, the Farm first so food stays above zero.
const PRODUCERS: Array[StringName] = [TownRules.FARM, TownRules.LUMBERMILL, TownRules.MINE]
const OUT_DIR: String = "res://tests/fixtures/stages/%s/"

var _stage: String = "early"
var _stage_seconds: float = 0.0
var _clock: float = 0.0
var _seen: Dictionary[String, bool] = {}
var _battle_seconds: float = 0.0
var _sent_at: Dictionary[String, float] = {}
var _longest_order: float = 0.0
var _underpowered_sends: int = 0
var _refusals: Dictionary[String, int] = {}
var _failed: bool = false
var _casters: Dictionary[String, bool] = {}
var _casters_fed: int = 0
var _pulls: int = 0
var _strike_seconds: float = 0.0
var _homeless_peak: int = 0
## Each dispatched expedition's route (initial_duration_seconds) until it lands; rescues are not here.
var _route_of: Dictionary[String, float] = {}
var _route_seconds: float = 0.0
var _order_seconds: float = 0.0
var _mood_low: float = 100.0
var _mood_low_seconds: float = 0.0
var _food_low: float = INF
## The roster size at each game hour; [0] is the empty start.
var _hour_roster: Array[int] = [0]


## The exit code: 0 when the stage saved and its death check held, 2 when that check or an order in
## flight fails it, 1 when the run broke.
func run(args: PackedStringArray) -> int:
	var seed_value: int = 1
	for arg: String in args:
		if arg.begins_with("--seed=") and arg.get_slice("=", 1).is_valid_int():
			seed_value = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--stage=") and STAGE_SECONDS.has(arg.get_slice("=", 1)):
			_stage = arg.get_slice("=", 1)
		else:
			push_error("stage_bot: unknown arg %s" % arg)
			return 1
	if FileAccess.file_exists(SaveService.SAVE_PATH) or not GameSession.roster.is_empty():
		push_error("stage_bot: user:// already holds a save. Run it with a fresh temp APPDATA.")
		return 1
	_stage_seconds = STAGE_SECONDS[_stage]
	seed(seed_value)
	print("BOT stage=%s seed=%d step=%.1f game_seconds=%.0f" % [_stage, seed_value, STEP, _stage_seconds])
	var started: int = Time.get_ticks_msec()
	while true:
		_note_roster()
		if _clock >= _stage_seconds:
			for order: Dictionary in GameSession.expedition_orders.duplicate():
				GameSession.request_stop_expedition(str(order.get("id", "")))
			if GameSession.expedition_orders.is_empty():
				break
		else:
			# Stop dispatching once an order sent now could still be out at the save.
			_play(_clock + maxf(_longest_order, 600.0) * 1.5 < _stage_seconds)
		_step()
		if _failed:
			return 1
		if fmod(_clock, 3600.0) == 0.0:
			_hour_roster.append(GameSession.roster.size())
			var homeless: int = GameSession.homeless_heroes().size()
			print("HOUR %d wall_s=%.1f roster=%d teams=%d orders=%d pulls=%d stones_earned=%d houses=%d beds=%d/%d homeless=%d mood=%.1f wood=%.1f stone=%.1f food=%.1f building_levels=%s ledger=%d cleared=%s" % [roundi(_clock / 3600.0), (Time.get_ticks_msec() - started) / 1000.0, GameSession.roster.size(), GameSession.team_presets.size(), GameSession.expedition_orders.size(), _pulls, _stones_earned(), _count(TownRules.HOUSE), GameSession.roster.size() - homeless, GameSession.roster.size(), homeless, GameSession.town_mood, float(GameSession.town_resources["wood"]), float(GameSession.town_resources["stone"]), float(GameSession.town_resources["food"]), GameSession.building_levels, GameSession.ledger.size(), GameSession.cleared_zone_ids])
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
		if _ok(GameSession.summon_hero(Summon.roll(GameSession.building_levels[0]), BALANCE), "summon"):
			_pulls += 1
		_note_roster()
	_house()
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
	# ig-0og.1: the homeless beyond the grace, less the Houses going up, are spare, weakest first.
	var surplus: Array[Hero] = []
	var excess: int = GameSession.homeless_heroes().size() - BALANCE.town_mood_homeless_grace - _houses_going_up()
	for index: int in range(pool.size() - 1, -1, -1):
		if surplus.size() < excess and pool[index].home == Hero.NO_HOME:
			surplus.append(pool[index])
			pool.remove_at(index)
	var groups: Array[Array] = []
	var index: int = 0
	while pool.size() - index >= TEAM_SIZE:
		groups.append(pool.slice(index, index + TEAM_SIZE))
		index += TEAM_SIZE
	if groups.is_empty() and out.is_empty() and not pool.is_empty():
		groups.append(pool.duplicate())
		index = pool.size()
	spare.assign(pool.slice(index))
	surplus.reverse()
	spare.append_array(surplus)
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


## ig-0og.1, "keep what you can house" (SYSTEMS.md § Stage saves): the workplaces _workers_wanted needs,
## then Houses while wood allows and beds are fewer than heroes. Free beds go first to the workers
## _workers_wanted still needs (kept empty for _staff's weakest spare heroes: a worker needs a home),
## then to the strongest homeless (director's ruling C, 2026-09-25).
func _house() -> void:
	for type: StringName in PRODUCERS:
		var needed: int = ceili(float(_workers_wanted(type)) / TownRules.worker_slots(type, BALANCE))
		while _count(type) < needed and _place(type):
			pass
	while _count(TownRules.HOUSE) * BALANCE.house_capacity < GameSession.roster.size() and _place(TownRules.HOUSE):
		pass
	var free_beds: int = 0
	for building: Dictionary in GameSession.town_buildings:
		var house_id := StringName(str(building["id"]))
		if str(building["type"]) == String(TownRules.HOUSE) and GameSession.still_building(house_id).is_empty() and GameSession.residents_of(house_id).is_empty():
			free_beds += 1
	var workers_short: int = 0
	for type: StringName in PRODUCERS:
		workers_short += maxi(_workers_wanted(type) - _workers(type), 0)
	var homeless: Array[Hero] = GameSession.homeless_heroes()
	homeless.sort_custom(func(first: Hero, second: Hero) -> bool: return _power(first) > _power(second))
	for hero: Hero in homeless.slice(0, maxi(free_beds - workers_short, 0)):
		_ok(GameSession.assign_home(hero, StringName(_empty_house())), "assign_home")


## Each producer staffed to _workers_wanted from the weakest spare heroes with a bed; a homeless one
## takes a free bed first, or waits.
func _staff(spare: Array[Hero]) -> void:
	for type: StringName in PRODUCERS:
		for _slot: int in maxi(_workers_wanted(type) - _workers(type), 0):
			var workplace: String = _open_workplace(type)
			var worker: Hero = _bedded_worker(spare)
			if workplace.is_empty() or worker == null:
				break
			_ok(GameSession.station_hero(worker, StringName(workplace)), "station_hero")


## ig-0og.1: ceil(heroes x 0.2) farmers (a farmer makes what five eat), max(1, heroes / 5) woodcutters,
## and the Mine's 1.
func _workers_wanted(type: StringName) -> int:
	var heroes: int = GameSession.roster.size()
	if type == TownRules.FARM:
		return ceili(heroes * BALANCE.food_per_hero_minute / BALANCE.food_per_worker_minute)
	if type == TownRules.LUMBERMILL:
		return maxi(1, floori(heroes / float(TEAM_SIZE)))
	return 1


## The weakest spare hero with a bed, or the weakest homeless one put in a free bed; null with neither.
func _bedded_worker(spare: Array[Hero]) -> Hero:
	for index: int in range(spare.size() - 1, -1, -1):
		if spare[index].home != Hero.NO_HOME:
			return spare.pop_at(index)
	var house: String = _empty_house()
	if spare.is_empty() or house.is_empty():
		return null
	var worker: Hero = spare.pop_back()
	_ok(GameSession.assign_home(worker, StringName(house)), "assign_home")
	return worker


## The homeless beyond the grace are fodder for the strongest idle team hero (else the strongest hero
## at home); then every idle team hero ranks up while the essence lasts, strongest first.
func _feed(spare: Array[Hero], teams: Array[Dictionary]) -> void:
	# ig-eek.1 (ACC 8): only the homeless beyond the grace, less the Houses going up, are fodder, team
	# home or not (SYSTEMS § Stage saves). Housed spare heroes wait for the next team.
	var fodders: Array[Hero] = []
	var excess: int = GameSession.homeless_heroes().size() - BALANCE.town_mood_homeless_grace - _houses_going_up()
	for index: int in range(spare.size() - 1, -1, -1):
		if fodders.size() < excess and spare[index].home == Hero.NO_HOME:
			fodders.append(spare[index])
	var target: Hero = null
	if not teams.is_empty():
		target = (teams[0]["heroes"] as Array[Hero])[0]
	else:
		for hero: Hero in GameSession.roster:
			if not fodders.has(hero) and not GameSession.is_hero_busy(hero) and (target == null or _power(hero) > _power(target)):
				target = hero
	if target == null:
		return
	for fodder: Hero in fodders:
		if _casters.has(fodder.instance_id):
			_casters_fed += 1
		for slot: int in fodder.equipped.keys():
			GameSession.unequip_item(fodder, slot)
		_ok(GameSession.sacrifice_hero(fodder, target, BALANCE), "sacrifice_hero")
		spare.erase(fodder)
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
		var underpowered: bool = zone_id.is_empty()
		if underpowered:
			zone_id = "verdant_outskirts"
		# A first send to a zone has no order measured yet, so the route estimate stands in: a force
		# zone's route alone can outlast the stage.
		var route: float = ExpeditionOrders.force_duration_seconds(heroes, ZoneDefinition.definition_for(StringName(zone_id)), BALANCE)
		if _clock + maxf(route, _longest_order) * 1.5 >= _stage_seconds:
			continue
		if underpowered:
			_underpowered_sends += 1
		var preset_ids: Array[String] = [str(team["id"])]
		var order_id: String = GameSession.dispatch_force(preset_ids, zone_id, 1, {}, _loadout(heroes))
		if _ok(not order_id.is_empty(), "dispatch_force"):
			_sent_at[order_id] = _clock
			for order: Dictionary in GameSession.expedition_orders:
				if str(order.get("id", "")) == order_id:
					_route_of[order_id] = float(order.get("initial_duration_seconds", 0.0))


## Free first producers, then one hall upgrade when affordable, the lowest level first in SYSTEMS'
## order. Houses go up in _house, and come first: no hall upgrade while anyone is homeless (ig-0og.1).
func _town() -> void:
	for type: StringName in [TownRules.FARM, TownRules.HOUSE, TownRules.LUMBERMILL, TownRules.MINE]:
		if not _has_building(type):
			_place(type)
	if not GameSession.homeless_heroes().is_empty():
		return
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
	# Ruling C: the bot closes the last starvation warning on the first step it is up, as a player would.
	if GameSession.is_starvation_stopped():
		_ok(GameSession.acknowledge_starvation(), "acknowledge_starvation")
	if GameSession.is_in_revolt():
		_strike_seconds += STEP
	_homeless_peak = maxi(_homeless_peak, GameSession.homeless_heroes().size())
	_wait_for_jobs()
	_mood_low = minf(_mood_low, GameSession.town_mood)
	if GameSession.town_mood < 100.0:
		_mood_low_seconds += STEP
	_food_low = minf(_food_low, float(GameSession.town_resources["food"]))
	var live: Dictionary[String, bool] = {}
	for order: Dictionary in GameSession.expedition_orders:
		live[str(order.get("id", ""))] = true
	for order_id: String in _sent_at.keys():
		if not live.has(order_id):
			_longest_order = maxf(_longest_order, _clock - _sent_at[order_id])
			if _route_of.has(order_id):
				_route_seconds += _route_of[order_id]
				_order_seconds += _clock - _sent_at[order_id]
				_route_of.erase(order_id)
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
	var teams: int = GameSession.team_presets.size()
	if _stage == "early":
		_check("verdant_cleared", GameSession.cleared_zone_ids.has(&"verdant_outskirts"), GameSession.cleared_zone_ids.has(&"verdant_outskirts"))
		_check("heroes 8-20", roster.size(), roster.size() >= 8 and roster.size() <= 20)
		_check("teams 1-2", teams, teams >= 1 and teams <= 2)
		_check("free first producers placed", types, free_placed)
		_check("no hall above level 1", GameSession.building_levels, top_hall <= 1)
		print("INFO ledger_records=%d (SYSTEMS: about 30) ledger_next_seq=%d" % [GameSession.ledger.size(), GameSession.ledger_next_seq])
	else:
		_check("ashfall_cleared", GameSession.cleared_zone_ids.has(&"ashfall_reaches"), GameSession.cleared_zone_ids.has(&"ashfall_reaches"))
		# ig-eek.1: the row re-set from seed 1 (director's ruling); halls, deaths and rescues are INFO.
		_check("heroes 25-34", roster.size(), roster.size() >= 25 and roster.size() <= 34)
		var best: Array[String] = _best_team_ranks()
		var a_or_better: int = best.filter(func(rank: String) -> bool: return BALANCE.rank_names.find(rank) >= BALANCE.rank_names.find("A")).size()
		_check("best team A or better (3+ of 5)", best, best.size() == TEAM_SIZE and a_or_better >= 3)
		_check("teams 2-4", teams, teams >= 2 and teams <= 4)
		var deaths: int = GameSession.ledger.filter(func(record: Dictionary) -> bool: return str(record.get("kind", "")) == "died" and not str(record.get("cause", "")) in ["sacrifice", "starvation"]).size()
		var rescues: int = GameSession.ledger.filter(func(record: Dictionary) -> bool: return str(record.get("kind", "")) == "battle" and str(record.get("battle_kind", "")) == "rescue").size()
		print("INFO halls=%s deaths=%d rescues=%d" % [GameSession.building_levels, deaths, rescues])
		_check("a bond", GameSession.bond_index().size(), GameSession.bond_index().size() >= 1)
		# ig-eek.1: the roster grows no faster in game hours 11-20 than in hours 1-10.
		if _hour_roster.size() > 20:
			var first: int = _hour_roster[10] - _hour_roster[0]
			var second: int = _hour_roster[20] - _hour_roster[10]
			_check("growth linear (added h1-10, h11-20)", [first, second], second <= first)
		else:
			_check("growth linear (added h1-10, h11-20)", _hour_roster, false)
		print("INFO ledger_records=%d (SYSTEMS: about 600) ledger_next_seq=%d" % [GameSession.ledger.size(), GameSession.ledger_next_seq])
	# ig-0og.1: a player who houses or feeds everyone beyond the grace never strikes, and never starves.
	var starved: int = GameSession.ledger.filter(func(record: Dictionary) -> bool: return str(record.get("kind", "")) == "died" and str(record.get("cause", "")) == "starvation").size()
	_check("strike minutes 0", _strike_seconds / 60.0, _strike_seconds == 0.0)
	_check("starvation deaths 0", starved, starved == 0)
	var game_h: float = _stage_seconds / 3600.0
	var sacrificed: int = GameSession.ledger.filter(func(record: Dictionary) -> bool: return str(record.get("kind", "")) == "died" and str(record.get("cause", "")) == "sacrifice").size()
	print("ECON pulls=%d pulls_per_h=%.1f stones_earned=%d stones_per_h=%.1f route_s=%.0f order_s=%.0f stones_per_team_out_h=%.1f sacrificed=%d houses=%d next_house_wood=%d homeless_peak=%d mood_low=%.1f mood_under_100_min=%.1f strike_min=%.1f starvation_deaths=%d food_low=%.1f farmers=%d woodcutters=%d miners=%d" % [_pulls, _pulls / game_h, _stones_earned(), _stones_earned() / game_h, _route_seconds, _order_seconds, _stones_earned() / maxf(_order_seconds / 3600.0, 0.001), sacrificed, _count(TownRules.HOUSE), TownRules.wood_cost(TownRules.HOUSE, GameSession.town_buildings, BALANCE), _homeless_peak, _mood_low, _mood_low_seconds / 60.0, _strike_seconds / 60.0, starved, _food_low, _workers(TownRules.FARM), _workers(TownRules.LUMBERMILL), _workers(TownRules.MINE)])
	print("TOWN pulls=%d houses=%d next_house_wood=%d homeless_peak=%d homeless=%d mood=%.1f food=%.1f" % [_pulls, _count(TownRules.HOUSE), TownRules.wood_cost(TownRules.HOUSE, GameSession.town_buildings, BALANCE), _homeless_peak, GameSession.homeless_heroes().size(), GameSession.town_mood, float(GameSession.town_resources["food"])])
	var casters_kept: int = roster.filter(func(hero: Hero) -> bool: return _casters.has(hero.instance_id)).size()
	print("INFO casters pulled=%d fed=%d kept=%d" % [_casters.size(), _casters_fed, casters_kept])
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
	print("COST wall_s=%.1f game_s=%.0f wall_s_per_game_h=%.1f battle_s=%.0f battle_s_per_wall_s=%.1f" % [wall_seconds, _clock, wall_seconds / game_hours, _battle_seconds, _battle_seconds / wall_seconds])
	print("RUN roster=%d building_levels=%s ledger=%d orders=%d jobs=%d incidents=%d stones=%d essence=%d parts=%s supplies=%s town=%s underpowered_sends=%d longest_order_s=%.0f refusals=%s" % [roster.size(), GameSession.building_levels, GameSession.ledger.size(), GameSession.expedition_orders.size(), GameSession._battle_jobs.size(), GameSession.stranded_incidents.size(), GameSession.stones, GameSession.essence, GameSession.parts, GameSession.supplies, GameSession.town_resources, _underpowered_sends, _longest_order, _refusals])
	print("README seed=%d step=%.1f wall_s=%.1f game_clock_s=%.0f" % [seed_value, STEP, wall_seconds, _clock])
	for hero: Hero in roster:
		print("HERO %s %s %s lvl=%d power=%.0f station=%s" % [hero.instance_id, hero.hero_name, BALANCE.rank_names[hero.rank], hero.level, _power(hero), hero.station])
	return unexplained.is_empty() and GameSession.expedition_orders.is_empty()


## ig-eek.1 (extra's definition): summons are the only spend; the empty-roster refill counts as earned.
func _stones_earned() -> int:
	return GameSession.stones + _pulls * BALANCE.summon_pull_cost - GameSession.STARTING_STONES


## The rank names of the strongest saved 5-hero team by _team_power; [] with none.
func _best_team_ranks() -> Array[String]:
	var best: Array[Hero] = []
	for preset: Dictionary in GameSession.team_presets:
		var heroes: Array[Hero] = []
		for hero_id: Variant in preset.get("hero_ids", []) as Array:
			var hero: Hero = GameSession.hero_by_id(str(hero_id))
			if hero != null:
				heroes.append(hero)
		if heroes.size() == TEAM_SIZE and (best.is_empty() or _team_power(heroes) > _team_power(best)):
			best = heroes
	var ranks: Array[String] = []
	for hero: Hero in best:
		ranks.append(BALANCE.rank_names[hero.rank])
	return ranks


func _check(label: String, value: Variant, passed: bool) -> void:
	print("CHECK %s value=%s %s" % [label, value, "pass" if passed else "MISS"])


func _copy_out() -> void:
	var out: String = ProjectSettings.globalize_path(OUT_DIR % _stage)
	DirAccess.make_dir_recursive_absolute(out)
	for path: String in [SaveService.SAVE_PATH, SaveService.LEDGER_PATH]:
		var error: Error = DirAccess.copy_absolute(ProjectSettings.globalize_path(path), out.path_join(path.get_file()))
		if error != OK:
			push_error("stage_bot: copying %s failed: %s" % [path, error_string(error)])
	print("OUT %s" % out)


func _note_roster() -> void:
	for hero: Hero in GameSession.roster:
		_seen[hero.instance_id] = true
		var definition: HeroDefinition = Hero.definition_for(hero.def_id)
		if definition != null and definition.caster:
			_casters[hero.instance_id] = true


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


func _count(type: StringName) -> int:
	return GameSession.town_buildings.filter(func(building: Dictionary) -> bool: return str(building["type"]) == String(type)).size()


func _workers(type: StringName) -> int:
	var workers: int = 0
	for building: Dictionary in GameSession.town_buildings:
		if str(building["type"]) == String(type):
			workers += GameSession.workers_at(StringName(str(building["id"]))).size()
	return workers


## A finished workplace of the type with a free slot, or "".
func _open_workplace(type: StringName) -> String:
	for building: Dictionary in GameSession.town_buildings:
		var id := StringName(str(building["id"]))
		if str(building["type"]) == String(type) and GameSession.still_building(id).is_empty() and GameSession.workers_at(id).size() < TownRules.worker_slots(type, BALANCE):
			return String(id)
	return ""


func _empty_house() -> String:
	for building: Dictionary in GameSession.town_buildings:
		var house_id := StringName(str(building["id"]))
		if str(building["type"]) == String(TownRules.HOUSE) and GameSession.still_building(house_id).is_empty() and GameSession.residents_of(house_id).is_empty():
			return String(house_id)
	return ""


func _houses_going_up() -> int:
	return GameSession.town_buildings.filter(func(building: Dictionary) -> bool: return str(building["type"]) == String(TownRules.HOUSE) and building.has("build_remaining")).size()


## The free hex nearest the town centre that place_building would take; false when none (no wood).
func _place(type: StringName) -> bool:
	var hexes: Array[Vector2i] = TownRules.map_hexes(BALANCE)
	hexes.sort_custom(func(first: Vector2i, second: Vector2i) -> bool: return TownRules.ring_distance(first) < TownRules.ring_distance(second))
	for hex: Vector2i in hexes:
		if bool(GameSession.preview_place_building(type, hex).get("valid", false)):
			return _ok(GameSession.place_building(type, hex), "place " + String(type))
	return false
