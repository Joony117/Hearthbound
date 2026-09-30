extends Node
## Persistent player profile. Autoload.
##
## Exists only because the profile must outlive scene changes (menu -> hub -> arena -> hub).
## That is not a licence to grow into a GameManager: game *rules* live in plain functions
## that take what they need as arguments. See docs/ARCHITECTURE.md and docs/CODING_RULES.md.

signal roster_changed
signal expeditions_changed
signal battle_changed(order_id: String)
## ig-7sn.14: a dispatch preview's forecast landed (or its cache was dropped): refresh the preview.
signal preview_forecast_ready

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
var supplies: Dictionary = BattleState.supplies_from({"healing": 3, "revival": 1})
var stranded_incidents: Array[Dictionary] = []
var rescue_clock_seconds: float = 0.0
var recovery_clock_seconds: float = 0.0
var recovery_clock_paused: bool = false
## The roster hero the player walks the town as (ARCHITECTURE.md § The town is the interface). It
## can be geared and ranked up, but never sent out or sacrificed; NO_BODY when there is none.
var embodied_hero_id: String = NO_BODY
## Town buildings, {id: String, type: String, q: int, r: int}: the seven halls (id = type), then the
## placed ones in placing order (DECISIONS.md 2026-09-23, the town builder, items 1-3).
var town_buildings: Array[Dictionary] = TownRules.default_halls()
## The shared stockpile. Wood is a float so a partial unit from the live tick survives a save.
var town_resources: Dictionary = {"wood": preload("res://balance.tres").town_start_wood, "stone": 0.0, "food": preload("res://balance.tres").town_start_food}
## The n in the next placed id "<type>_<n>"; never reused.
var town_next_id: int = 1
## Seconds the town has starved (ig-6m2.5.2); 0 is fed. It stops at each last warning until
## acknowledge_starvation(), and moves on the live tick only.
var town_starving_seconds: float = 0.0
## The last warning at the current stop point was seen, so the clock may run on to the death.
var town_starve_acked: bool = false
## ig-0og.1: the town mood, 0-100 (SYSTEMS.md § Town mood and revolt). The homeless move it on the live
## tick only (TownRules.mood_step); a revolt is derived from it (TownRules.in_revolt), never saved.
var town_mood: float = 100.0
## ig-0og.3: live seconds the town has been in revolt; the first live tick outside one sets it to 0. The
## riot fires at each TownRules.riot_fires crossing. Saved; moves on the live tick only, like town_mood.
var town_revolt_seconds: float = 0.0
## ig-0og.3: what the town did since the hub last took it (take_town_notice): the starved heroes' names,
## and the riot's fires with the wood and stone they burned. Unsaved: from_dict clears it, and a rollback
## puts back its value from before the transaction (_rollback_kept), so an undone death or fire is not said.
var _town_notice: Dictionary = _empty_town_notice()
## The Ledger (DECISIONS.md 2026-09-24): settled events, appended by this script's mutators through
## Ledger.append. The records live in SaveService's side file, not in to_dict(); the main save keeps
## only ledger_next_seq, the high-water mark. seq is never reused.
var ledger: Array[Dictionary] = []
var ledger_next_seq: int = 1
## Ledger.tier() of each record, index for index with ledger, for Ledger.evict().
var _ledger_tiers: Array[int] = []
## The kept bond index (DECISIONS.md 2026-09-24 "Bonds stay derived", items 3 and 5), one for every
## reader: Bonds.index_state() of ledger, folded as records come and go. Unsaved, never in to_dict().
## It mirrors the array _bond_ledger (or null) at ledger_next_seq _bond_seq; anything else rebuilds.
var _bond_state: Dictionary = {}
var _bond_ledger: Variant = null
var _bond_seq: int = -1
## How many times the bond index was rebuilt, for tests.
var bond_builds: int = 0
## How many times a team snapshot was built, for tests (ig-7sn.4).
var team_snapshot_builds: int = 0
## How many battle advances the live pulse ran, for tests (ig-7sn.5): one per active battle a pulse.
var pulse_battle_advances: int = 0
## How many times the pulse decoded a battle, for tests and the perf measure (ig-7sn.15): an active
## battle's, and one whose fight is over (returning, or ended).
var pulse_decodes_active: int = 0
var pulse_decodes_idle: int = 0
var saved_at_unix: float = 0.0
var last_action_error: String = ""

var _save_deferred_depth: int = 0
## Inside a profile mutation, eviction waits for the commit so a rollback can truncate (item 8).
var _ledger_hold_depth: int = 0
var _notification_deferred_depth: int = 0
var _roster_notification_pending: bool = false
var _expeditions_notification_pending: bool = false
var _battle_notifications_pending: Dictionary[String, bool] = {}
var _expedition_pulse_accumulator: float = 0.0
var _periodic_save_accumulator: float = 0.0
## ig-7sn.10: a pulse crossed PERIODIC_SAVE_SECONDS; the next _process call runs the save. Unsaved.
var _periodic_save_due: bool = false
var _paused_battle_orders: Dictionary[String, bool] = {}
## ig-gy0.6: the hero the player pilots in each watched battle, order id -> actor id. View state like the
## tactical pause: unsaved, cleared by _read_profile, restored by a rollback, and never set for a battle no
## view is watching. Each watched advance puts it on the BattleState (_send_battle_advance, _advance_battle).
var _piloted_battle_actors: Dictionary[String, String] = {}
## ig-7sn.15: each battle order's last state, [the battle Dictionary it was written as or decoded from,
## the BattleState], by order id. Unsaved; from_dict clears it. Every writer replaces an order's battle
## Dictionary and never edits it (ig-7sn.5), so while the order still holds that Dictionary the state is
## its exact decode. A BattleState holds nothing unsaved but derived caches (its zone, the corner-graph
## cache), the threading ADR's rule for them (DECISIONS.md 2026-09-25).
var _battle_states: Dictionary[String, Array] = {}
## ig-7sn.15: the real seconds each live battle is owed since its last advance, by order id. Unsaved.
var _battle_owed: Dictionary[String, float] = {}
## ig-7sn.18: each live battle's advance out as a job, by order id, oldest first: the job, the battle
## Dictionary it was sent from, the BattleState it took and the seconds it was sent for. The main thread
## never reads that state before the job is waited on. Unsaved; _cancel_battle_jobs clears it.
var _battle_advances: Dictionary[String, Dictionary] = {}
## Sim jobs out on WorkerThreadPool (ig-7sn.13, DECISIONS.md 2026-09-25 "Battle sim threading").
## Private and unsaved; nothing here is ever written by a job.
var _battle_jobs: Array[BattleJob] = []
## ig-7sn.6: the repeat check out for each "checking" order, by order id: its generation, the battle
## Dictionary it was sent for, the normal and stress jobs, and what the repeat is built from (snapshots,
## squads, zone, duration). Unsaved: a load clears it and the pulse sends the check again; a rollback
## keeps it (ig-7sn.17).
## ig-7sn.12: an order owing catch_up_seconds has an entry here too, with its one "catch_up" job.
var _battle_checks: Dictionary[String, Dictionary] = {}
var _battle_check_generation: int = 0
## ig-7sn.14: the dispatch preview's forecasts, oldest first. Each entry holds its key (the forecast's
## exact inputs, compared with ==), its seed, its normal and stress jobs, and once both land, its
## verdict. Unsaved: _cancel_battle_jobs clears it; an until-stopped dispatch consumes its entry.
var _preview_forecasts: Array[Dictionary] = []
const PREVIEW_FORECAST_CAP: int = 16
var _checkpoint_save_failed: bool = false
var _checkpoint_error: String = ""
var _command_errors: Dictionary[String, String] = {}
var _pending_command_result: Dictionary = {}


func _ready() -> void:
	SaveService.load_game()
	# Connected after the load so from_dict()'s emit doesn't immediately write back.
	roster_changed.connect(SaveService.save)


func _exit_tree() -> void:
	_cancel_battle_jobs()


## work(job) runs on a worker thread and returns the job's plain-data result.
func _submit_battle_job(work: Callable) -> BattleJob:
	var job := BattleJob.new()
	job.task_id = WorkerThreadPool.add_task(func() -> void: job.result = work.call(job))
	_battle_jobs.append(job)
	return job


## Stops every job at its next chunk and waits for it; their results are dropped. Runs on quit and
## before from_dict replaces the session, so no job outlives the state it was sent for.
func _cancel_battle_jobs() -> void:
	for job: BattleJob in _battle_jobs:
		job.cancelled = true
	for job: BattleJob in _battle_jobs:
		WorkerThreadPool.wait_for_task_completion(job.task_id)
	_battle_jobs.clear()
	_battle_checks.clear()
	_battle_advances.clear()
	if not _preview_forecasts.is_empty():
		_preview_forecasts.clear()
		# A preview left on "Checking..." asks again, once the state being replaced is gone.
		preview_forecast_ready.emit.call_deferred()


## ig-7sn.6 (DECISIONS.md 2026-09-25 "Battle sim threading", item 9): sends the repeat check, the
## forecast's normal and stress legs as two jobs, for every "checking" order that has none out. The
## snapshots come from the order's heroes now; each job gets its own deep copy.
func _send_battle_checks() -> void:
	for order: Dictionary in expedition_orders:
		var order_id: String = str(order.get("id", ""))
		if _battle_checks.has(order_id):
			continue
		var owed: float = _catch_up_seconds(order)
		if owed > 0.0:
			# ig-7sn.12: the offline catch-up, advanced in the job's chunks from the battle as saved. The
			# state is built here, on the main thread, from its own deep copy.
			var state := BattleState.from_dict((order.get("battle") as Dictionary).duplicate(true))
			_battle_check_generation += 1
			_battle_checks[order_id] = {"generation": _battle_check_generation, "battle": order.get("battle"), "catch_up": _submit_battle_job(func(job: BattleJob) -> Dictionary: return BattleJob.run_battle(state, owed, job))}
			continue
		if str(order.get("phase", "")) != "checking":
			continue
		var team: Array[Hero] = []
		for hero_id: String in _string_array(order.get("hero_ids")):
			var hero: Hero = hero_by_id(hero_id)
			if hero != null:
				team.append(hero)
		var zone: ZoneDefinition = ZoneDefinition.definition_for(StringName(str(order.get("zone_id", ""))))
		var squads: Array[Dictionary] = []
		for raw_squad: Variant in order.get("squads") as Array:
			if raw_squad is Dictionary:
				squads.append((raw_squad as Dictionary).duplicate(true))
		_battle_check_generation += 1
		var check: Dictionary = {"generation": _battle_check_generation, "battle": order.get("battle"), "squads": squads, "zone": zone}
		_battle_checks[order_id] = check
		if team.size() != _string_array(order.get("hero_ids")).size() or zone == null:
			# Nothing to check: it lands at the next pulse and stops the order.
			check["error"] = "A repeat team member is missing."
			continue
		var snapshots: Array[Dictionary] = _team_snapshots(team, squads)
		check["snapshots"] = snapshots
		check["duration"] = ExpeditionOrders.force_duration_seconds(team, zone, preload("res://balance.tres"))
		var policies: Dictionary = order.get("policies") as Dictionary
		var escrow: Dictionary = order.get("escrow") as Dictionary
		var run_seed: int = Item.int_field(order, "run_seed", 0, "battle order")
		for stress: bool in [false, true]:
			var leg_snapshots: Array[Dictionary] = snapshots.duplicate(true)
			var leg_squads: Array[Dictionary] = squads.duplicate(true)
			var leg_policies: Dictionary = policies.duplicate(true)
			var leg_escrow: Dictionary = escrow.duplicate(true)
			check["stress" if stress else "normal"] = _submit_battle_job(func(job: BattleJob) -> Dictionary: return BattleJob.run_forecast_leg(order_id + ":repeat", leg_snapshots, zone, leg_squads, leg_policies, leg_escrow, run_seed, stress, job))


## Releases every finished job, then commits every check whose two jobs are both in. Nothing else
## removes a job but _cancel_battle_jobs.
func _land_battle_checks() -> void:
	_release_battle_jobs()
	var landed: Dictionary[String, int] = {}
	# ig-7sn.12: the load's catch-ups are one round: none lands until every one is in.
	var catch_ups: Dictionary[String, int] = {}
	var round_in: bool = true
	for order_id: String in _battle_checks:
		var check: Dictionary = _battle_checks[order_id]
		if check.has("catch_up"):
			catch_ups[order_id] = int(check["generation"])
			round_in = round_in and not _battle_jobs.has(check["catch_up"])
		elif not _battle_jobs.has(check.get("normal")) and not _battle_jobs.has(check.get("stress")):
			landed[order_id] = int(check["generation"])
	if round_in:
		landed.merge(catch_ups)
	if not landed.is_empty():
		_commit_profile_mutation(_land_battle_checks_in_memory.bind(landed))


## Releases every finished job (the wait frees its task; the only other waiter is _cancel_battle_jobs),
## then lands the preview forecasts whose two jobs are in. A preview changes no saved state, so it lands
## without a commit, and _process runs this even while the pulse is stalled (a blocked load, a failed
## checkpoint save), so no preview waits on "Checking..." for the stall (ig-7sn.14).
func _release_battle_jobs() -> void:
	for job: BattleJob in _battle_jobs.duplicate():
		_battle_job_done(job)
	var previewed: bool = false
	for entry: Dictionary in _preview_forecasts.duplicate():
		if entry.has("verdict") or _battle_jobs.has(entry["normal"]) or _battle_jobs.has(entry["stress"]):
			continue
		previewed = true
		var normal: Dictionary = (entry["normal"] as BattleJob).result
		var stress: Dictionary = (entry["stress"] as BattleJob).result
		if bool(normal.get("cancelled", true)) or bool(stress.get("cancelled", true)):
			_preview_forecasts.erase(entry)
			continue
		var verdict: Dictionary = BattleSimulation.forecast_verdict(normal["leg"], stress["leg"])
		entry["verdict"] = {"safe": bool(verdict["safe"]), "reason": str(verdict["reason"])}
	if previewed:
		preview_forecast_ready.emit()


## True once job's task has finished. The first call after that waits on it, which frees the task, and
## takes it off _battle_jobs.
func _battle_job_done(job: BattleJob) -> bool:
	if _battle_jobs.has(job):
		if not WorkerThreadPool.is_task_completed(job.task_id):
			return false
		WorkerThreadPool.wait_for_task_completion(job.task_id)
		_battle_jobs.erase(job)
	return true


## landed: generation by order id. Each order in its place in expedition_orders, never completion
## order. A check commits only onto the order it was sent for: same generation, still "checking",
## still holding that battle Dictionary. Anything else is dropped.
func _land_battle_checks_in_memory(landed: Dictionary[String, int]) -> void:
	var caught_up: bool = false
	for order: Dictionary in expedition_orders.duplicate():
		var order_id: String = str(order.get("id", ""))
		if not landed.has(order_id) or not _battle_checks.has(order_id):
			continue
		var check: Dictionary = _battle_checks[order_id]
		if int(check["generation"]) != landed[order_id]:
			continue
		_battle_checks.erase(order_id)
		if check.has("catch_up"):
			# ig-7sn.12: what the offline advance did at load before, now with the job's battle.
			var result: Dictionary = (check["catch_up"] as BattleJob).result
			if _catch_up_seconds(order) <= 0.0 or not is_same(order.get("battle"), check["battle"]) or bool(result.get("cancelled", true)):
				continue
			var caught_up_state := BattleState.from_dict(result["battle"] as Dictionary)
			order["battle"] = result["battle"]
			order.erase("catch_up_seconds")
			if caught_up_state.status != "active":
				order["phase"] = "returning"
				if _battle_has_no_secured_allies(caught_up_state):
					_capture_stranded_incident(order, caught_up_state)
			caught_up = true
			_notify_battle_changed(order_id)
			continue
		if str(order.get("phase", "")) != "checking" or not is_same(order.get("battle"), check["battle"]):
			continue
		if check.has("error"):
			_end_battle_check_in_memory(order_id, str(check["error"]))
			continue
		var normal: Dictionary = (check["normal"] as BattleJob).result
		var stress: Dictionary = (check["stress"] as BattleJob).result
		if bool(normal.get("cancelled", true)) or bool(stress.get("cancelled", true)):
			continue
		if not bool(BattleSimulation.forecast_verdict(normal["leg"], stress["leg"]).get("safe", false)):
			_end_battle_check_in_memory(order_id, "unsafe_repeat")
			continue
		var state: BattleState = BattleSimulation.create_run(order_id, check["snapshots"], check["zone"], check["squads"], order.get("policies") as Dictionary, order.get("escrow") as Dictionary, Item.int_field(order, "run_seed", 0, "battle order"))
		order["battle"] = state.to_dict()
		order["phase"] = "fighting"
		order["initial_duration_seconds"] = check["duration"]
		order["remaining_seconds"] = check["duration"]
		order["incident_id"] = ""
		_notify_battle_changed(order_id)
	# An entry whose order is gone lands with nothing to commit onto.
	for order_id: String in landed:
		if _battle_checks.has(order_id) and int(_battle_checks[order_id]["generation"]) == landed[order_id]:
			_battle_checks.erase(order_id)
	if caught_up:
		_resolve_due_orders_in_memory()
	_notify_roster_changed()
	_notify_expeditions_changed()


## Ends a "checking" order now: refunds the escrow its repeat spent and writes reason onto that settle's
## report (the order's newest). A check still out for it is dropped when it lands.
func _end_battle_check_in_memory(order_id: String, reason: String) -> void:
	var index: int = _order_index(order_id)
	if index < 0:
		return
	var order: Dictionary = expedition_orders[index]
	_refund_battle_supplies(order.get("escrow") as Dictionary)
	for report_index: int in range(expedition_reports.size() - 1, -1, -1):
		if str(expedition_reports[report_index].get("order_id", "")) == order_id:
			expedition_reports[report_index]["stopped_reason"] = reason
			break
	var check: Dictionary = _battle_checks.get(order_id, {})
	for leg: String in ["normal", "stress"]:
		if check.get(leg) is BattleJob:
			(check[leg] as BattleJob).cancelled = true
	_battle_checks.erase(order_id)
	expedition_orders.remove_at(index)
	_notify_roster_changed()
	_notify_expeditions_changed()


func _process(delta: float) -> void:
	if SaveService.load_blocked:
		_release_battle_jobs()
		return
	_expedition_pulse_accumulator += delta
	var pulse_frame: bool = _expedition_pulse_accumulator >= EXPEDITION_PULSE_SECONDS
	# ig-7sn.10: the periodic save a pulse made due runs on the next frame, alone: each live battle is owed
	# the frame's time and none advances. Below 4 fps every frame is a pulse's, so there it runs at the
	# frame's start and the pulse follows; still no battle advances on it (ig-7sn.18).
	var save_frame: bool = _periodic_save_due
	if _periodic_save_due:
		_periodic_save_due = false
		if not pulse_frame:
			if not _checkpoint_save_failed:
				_owe_battles(delta, false)
			_periodic_save()
			return
		_periodic_save()
	# No battle moves during a stall (a failed checkpoint save), on the save's frame, nor on the pulse's own
	# frame unless the frame is itself a pulse long (below 4 fps every frame is a pulse's, and the battles
	# must still move).
	if not _checkpoint_save_failed:
		_owe_battles(delta, not save_frame and (not pulse_frame or delta >= EXPEDITION_PULSE_SECONDS))
	if not pulse_frame:
		return
	var elapsed_seconds: float = _expedition_pulse_accumulator
	_expedition_pulse_accumulator = 0.0
	if _checkpoint_save_failed:
		_periodic_save_accumulator += elapsed_seconds
		if _periodic_save_accumulator >= PERIODIC_SAVE_SECONDS:
			_periodic_save_accumulator = 0.0
			_periodic_save_due = true
		_release_battle_jobs()
		return
	_pulse(elapsed_seconds)
	_periodic_save_accumulator += elapsed_seconds
	if _periodic_save_accumulator >= PERIODIC_SAVE_SECONDS:
		_periodic_save_accumulator = 0.0
		if not expedition_orders.is_empty() or not stranded_incidents.is_empty() or (not lost_caches.is_empty() and not recovery_clock_paused) or _workers_home(TownRules.LUMBERMILL) + _workers_home(TownRules.MINE) + _workers_home(TownRules.FARM) > 0 or not food_eaters().is_empty() or not _working_keepers().is_empty() or town_buildings.any(_is_building):
			_periodic_save_due = true


## The 15 s save a pulse made due (ig-7sn.10: on the frame after it). After a failed checkpoint it is the
## retry: a save that lands ends the stall. Otherwise a save that fails starts one.
func _periodic_save() -> void:
	if _checkpoint_save_failed:
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
	if not SaveService.save():
		_checkpoint_save_failed = true
		_checkpoint_error = SaveService.last_write_error
		last_action_error = _checkpoint_error
		# ig-7sn.18: no battle moves during the stall. Each job out is dropped and its seconds owed again.
		for order_id: String in _battle_advances.keys():
			_drop_battle_advance(order_id, true)
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


## False, with last_action_error, when stones are short, the load is blocked or the save fails;
## nothing changes then. The caller reveals hero only on true, so a failed save can't be re-rolled.
func summon_hero(hero: Hero, balance: BalanceTable) -> bool:
	last_action_error = ""
	if stones < balance.summon_pull_cost:
		last_action_error = "Need %d Summon Stones, have %d." % [balance.summon_pull_cost, stones]
		return false
	return _commit_profile_mutation(_summon_in_memory.bind(hero, balance.summon_pull_cost))


## Checked path only (_commit_profile_mutation).
func _summon_in_memory(hero: Hero, cost: int) -> void:
	stones -= cost
	roster.append(hero)
	_record("summoned", {"hero": hero.instance_id, "name": hero.hero_name, "rank": hero.rank, "archetype": str(hero.def_id)})
	_notify_roster_changed()


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
func salvage_item(item: Item, _balance: BalanceTable) -> void:
	if not inventory.has(item) or is_item_protected(item):
		return
	var gain: int = salvage_yield(item)
	inventory.erase(item)
	# item.rank arrives from an untrusted save and is never validated by Item.from_dict, so clamp
	# before indexing, same as Item.rank_label and Hero.compute_final_stats. assert() cannot guard
	# this - it is stripped in release, where a corrupt rank would crash after the erase (positive)
	# or credit the wrong rank (negative, since GDScript indexes arrays from the end).
	parts[clampi(item.rank, 0, parts.size() - 1)] += gain
	_notify_roster_changed()


func enhance_item(item: Item, balance: BalanceTable) -> bool:
	if not inventory.has(item):
		return false
	var enhance_level: int = Item.clamped_enhance_level(item, balance)
	if enhance_level >= enhance_cap(balance):
		return false
	var rank_index: int = clampi(item.rank, 0, parts.size() - 1)
	var cost: int = Item.compute_enhance_cost(item, balance)
	if parts[rank_index] < cost:
		return false
	parts[rank_index] -= cost
	item.enhance_level = enhance_level + 1
	_notify_roster_changed()
	return true


## What upgrade_building would do, exactly: {valid, current_level, next_level, part_rank, part_cost,
## wood_cost, stone_cost, error}.
func preview_building_upgrade(index: int) -> Dictionary:
	var plan: Dictionary = _building_upgrade_plan(index, building_levels, parts, town_resources, preload("res://balance.tres"))
	if SaveService.load_blocked:
		plan["valid"] = false
		plan["error"] = SaveService.load_block_reason
	return plan


## Spends the parts, wood and stone, or nothing. A refusal (last_action_error) spends nothing.
func upgrade_building(index: int, balance: BalanceTable) -> bool:
	last_action_error = ""
	# Before the plan, so a blocked load says so even when something is short, as the preview does.
	if SaveService.load_blocked:
		last_action_error = SaveService.load_block_reason
		return false
	var plan: Dictionary = _building_upgrade_plan(index, building_levels, parts, town_resources, balance)
	if not bool(plan["valid"]):
		last_action_error = str(plan["error"])
		return false
	return _commit_profile_mutation(_upgrade_building_in_memory.bind(index, plan))


## Checked path only (_commit_profile_mutation), after _building_upgrade_plan found everything there.
func _upgrade_building_in_memory(index: int, plan: Dictionary) -> void:
	parts[int(plan["part_rank"])] -= int(plan["part_cost"])
	town_resources["wood"] = float(town_resources["wood"]) - int(plan["wood_cost"])
	town_resources["stone"] = float(town_resources["stone"]) - int(plan["stone_cost"])
	building_levels[index] = int(plan["next_level"])
	_notify_roster_changed()


## The only place a hall upgrade's cost is derived (SYSTEMS.md § Hall upgrades cost wood and stone).
static func _building_upgrade_plan(
	index: int,
	levels: Array[int],
	available_parts: Array[int],
	resources: Dictionary,
	balance: BalanceTable,
) -> Dictionary:
	var plan: Dictionary = {
		"valid": false,
		"current_level": -1,
		"next_level": -1,
		"part_rank": -1,
		"part_cost": 0,
		"wood_cost": 0,
		"stone_cost": 0,
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
	plan["next_level"] = level + 1
	plan["part_rank"] = rank_index
	plan["part_cost"] = 10 * (level + 2)
	plan["wood_cost"] = balance.hall_upgrade_wood_per_level * (level + 1)
	plan["stone_cost"] = balance.hall_upgrade_stone_per_level * (level + 1)
	var short: PackedStringArray = []
	if available_parts[rank_index] < int(plan["part_cost"]):
		short.append("%d %s parts (have %d)" % [plan["part_cost"], balance.rank_names[rank_index], available_parts[rank_index]])
	for resource: String in ["wood", "stone"]:
		var have: float = float(resources.get(resource, 0.0))
		if have < int(plan[resource + "_cost"]):
			short.append("%d %s (have %d)" % [plan[resource + "_cost"], resource, floori(have)])
	if short.is_empty():
		plan["valid"] = true
	elif short.size() == 1:
		plan["error"] = "Need %s." % short[0]
	else:
		plan["error"] = "Need %s and %s." % [", ".join(short.slice(0, short.size() - 1)), short[short.size() - 1]]
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
	essence += Hero.compute_essence_yield(fodder, target, balance, sanctum_level, keeper_skill(&"Sanctum"))
	if fodder.def_id == target.def_id and fodder.def_id != Hero.NO_ARCHETYPE_DEF_ID:
		target.resonance += 1
	kill_hero(fodder, &"", balance, "sacrifice", target.instance_id)
	return true


## False when the rank-up is not allowed, or, with last_action_error, when the load is blocked or
## the save fails; nothing changes then. A rollback rebuilds the roster, so re-find heroes by id.
func rank_up_hero(hero: Hero, balance: BalanceTable) -> bool:
	last_action_error = ""
	if hero == null or not roster.has(hero):
		last_action_error = "That hero is not on the roster."
		return false
	if is_hero_busy(hero) or hero.rank >= balance.rank_up_essence_costs.size():
		return false
	# The last rank-up, SS->SSS, needs a master priest home at the Sanctum; the target may be the priest
	# (SYSTEMS.md § Keepers and professions). A hero already at SSS is never re-checked.
	if hero.rank == balance.rank_names.size() - 2 and not keeper_is_master(&"Sanctum"):
		last_action_error = "SS->SSS needs a born master priest working here."
		return false
	var cost: int = Hero.compute_rank_up_cost(hero, balance)
	if essence < cost:
		return false
	return _commit_profile_mutation(_rank_up_in_memory.bind(hero, cost))


## Checked path only (_commit_profile_mutation).
func _rank_up_in_memory(hero: Hero, cost: int) -> void:
	essence -= cost
	hero.rank += 1
	_record("ranked_up", {"hero": hero.instance_id, "from": hero.rank - 1, "to": hero.rank, "via": "essence"})
	_notify_roster_changed()


## The single place a hero leaves the roster. See docs/ARCHITECTURE.md rule 8 - permadeath
## reachable from more than one call site is how this game rots. It is also the only writer of the
## Ledger's died record: cause is expedition, sacrifice or starvation; by is the keeper of a
## sacrifice; battle_order is the order whose battle stranded an expedition death.
func kill_hero(hero: Hero, zone_id: StringName, balance: BalanceTable, cause: String = "expedition", by: String = "", battle_order: String = "") -> void:
	var died: Dictionary = {"hero": hero.instance_id, "name": hero.hero_name, "rank": hero.rank, "cause": cause}
	for key: String in ["zone", "by", "battle_order"]:
		var value: String = {"zone": str(zone_id), "by": by, "battle_order": battle_order}[key]
		if not value.is_empty():
			died[key] = value
	_record("died", died)
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
		var building: String = still_building(building_id)
		if not building.is_empty():
			last_action_error = building
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


## The skill of the building's keeper in its profession; 0 with no keeper, a busy keeper, or a building
## that takes none (SYSTEMS.md § Keepers and professions). Every bonus and its preview read this.
func keeper_skill(building_id: StringName) -> int:
	var keeper: Hero = _home_keeper(building_id)
	return 0 if keeper == null else Hero.profession_skill(keeper, Hero.profession_for_building(building_id), preload("res://balance.tres"))


## A keeper who is home and a master of the building's profession (a passion, at the top skill).
func keeper_is_master(building_id: StringName) -> bool:
	var keeper: Hero = _home_keeper(building_id)
	return keeper != null and Hero.is_profession_master(keeper, Hero.profession_for_building(building_id), preload("res://balance.tres"))


func _home_keeper(building_id: StringName) -> Hero:
	if not Hero.is_staffable(building_id):
		return null
	var keeper: Hero = keeper_for(building_id)
	return null if keeper == null or is_hero_busy(keeper) else keeper


## The highest level enhancing may reach now; the single and bulk enhance and every preview read this.
func enhance_cap(balance: BalanceTable) -> int:
	return Item.compute_enhance_cap(building_levels[1], keeper_is_master(&"Forge"), balance)


## Parts salvaging item pays now; the salvage and every preview of it read this.
func salvage_yield(item: Item) -> int:
	return Item.compute_salvage_yield(item, building_levels[1], keeper_skill(&"Forge"), preload("res://balance.tres"))


## Expedition XP multiplier from the Training Hall and its Drill keeper.
func training_xp_multiplier() -> float:
	var balance: BalanceTable = preload("res://balance.tres")
	var level: int = clampi(building_levels[2], 0, balance.summoning_circle_level_cap)
	return 1.0 + balance.training_hall_xp_bonus * (level + balance.keeper_skill_bonus_levels * keeper_skill(&"TrainingHall"))


## A cache's or rescue window's lifetime now, from the Reliquary and its Tracking keeper. A running
## one never gets shorter than the longest it has had (cache_seconds_remaining, _incident_remaining_seconds).
func recovery_lifetime_seconds() -> float:
	return LostCache.lifetime_for(building_levels[4], keeper_skill(&"Reliquary"), preload("res://balance.tres"))


## The cache's remaining active time at clock_seconds; the expiry checks and the hub timers read this.
func cache_seconds_remaining(cache: LostCache, clock_seconds: float) -> float:
	return LostCache.seconds_remaining(cache, clock_seconds, building_levels[4], keeper_skill(&"Reliquary"), preload("res://balance.tres"))


## Every home keeper as [keeper, profession]: who earns XP on the live tick.
func _working_keepers() -> Array[Array]:
	var working: Array[Array] = []
	for profession: StringName in Hero.PROFESSIONS:
		var keeper: Hero = _home_keeper(Hero.PROFESSIONS[profession])
		if keeper != null:
			working.append([keeper, profession])
	return working


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


## "House 3 is still being built (0:42 left)." while building_id is under construction (ig-6m2.3.2),
## else "". Under construction = the building has build_remaining; it does nothing until it is gone.
func still_building(building_id: StringName) -> String:
	var building: Dictionary = town_building(building_id)
	if not _is_building(building):
		return ""
	var left: int = ceili(float(building["build_remaining"]))
	@warning_ignore("integer_division")
	return "%s is still being built (%d:%02d left)." % [String(building_id).capitalize(), left / 60, left % 60]


static func _is_building(building: Dictionary) -> bool:
	return building.has("build_remaining")


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
	var building: Dictionary = {"id": TownRules.new_id(type, town_next_id), "type": String(type), "q": hex.x, "r": hex.y}
	var build_seconds: float = TownRules.build_seconds(type, preload("res://balance.tres"))
	if build_seconds > 0.0:
		building["build_remaining"] = build_seconds
	town_buildings.append(building)
	town_next_id += 1
	town_resources["wood"] = float(town_resources["wood"]) - cost
	_notify_roster_changed()


## Moves a hall or a placed building to a free hex. Its id stays, so its keeper, workers, residents
## and level follow it and nothing is re-bound.
## ponytail: free in this slice (PROVISIONAL, ig-6m2.2); a cost comes with its own ruling.
func move_building(id: StringName, hex: Vector2i) -> bool:
	last_action_error = ""
	if SaveService.load_blocked:
		last_action_error = SaveService.load_block_reason
		return false
	var reason: String = TownRules.move_refusal(id, hex, town_buildings, preload("res://balance.tres"))
	if not reason.is_empty():
		last_action_error = reason
		return false
	return _commit_profile_mutation(_move_building_in_memory.bind(id, hex))


## Checked path only (_commit_profile_mutation), after move_refusal found the hex free.
func _move_building_in_memory(id: StringName, hex: Vector2i) -> void:
	var building: Dictionary = town_building(id)
	building["q"] = hex.x
	building["r"] = hex.y
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
	var building: String = still_building(house_id)
	if not building.is_empty():
		last_action_error = building
		return false
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


## Workers at a workplace of this type who are home (not away) right now; the live tick pays each of them.
func _workers_home(type: StringName) -> int:
	var working: int = 0
	for hero: Hero in roster:
		if TownRules.type_of(hero.station) == type and not is_hero_busy(hero):
			working += 1
	return working


## The clock sits at a stop point, unacknowledged: the last warning is up and nobody can die yet.
func is_starvation_stopped() -> bool:
	return town_starving_seconds > 0.0 and not town_starve_acked and town_starving_seconds >= TownRules.starve_stop_seconds(town_starving_seconds, preload("res://balance.tres"))


## The player saw the last warning, so the clock runs on to the death. A no-op (false) unless stopped.
func acknowledge_starvation() -> bool:
	last_action_error = ""
	if not is_starvation_stopped():
		return false
	return _commit_profile_mutation(_acknowledge_starvation_in_memory)


## Checked path only (_commit_profile_mutation).
func _acknowledge_starvation_in_memory() -> void:
	town_starve_acked = true
	_notify_expeditions_changed()


## The death the live tick brings when the clock reaches a due point (never offline, one per tick).
## Gear goes to inventory first, so kill_hero leaves no Lost Cache; kill_hero is still the only removal.
## candidates are starvation_candidates(): only a hero at home can starve (ig-0og.1).
func _starve_in_memory(candidates: Array[Hero], balance: BalanceTable) -> void:
	var victim: Hero = hero_by_id(TownRules.starvation_victim(candidates))
	if victim == null:
		return
	for slot: int in victim.equipped.keys():
		unequip_item(victim, slot)
	kill_hero(victim, &"", balance, "starvation")
	(_town_notice["starved"] as Array).append(victim.hero_name)


## The heroes who eat: every hero, wherever it is: housed or not, home, away on an order or stranded
## (ig-0og.1). Roster order, which starvation_victim reads.
func food_eaters() -> Array[Hero]:
	return roster.duplicate()


## The eaters who can starve: those at home, not on an order or stranded (ig-0og.1). With none, the
## starvation clock holds at the stop point, so kill_hero never runs on a busy hero (boundary #3).
func starvation_candidates() -> Array[Hero]:
	var candidates: Array[Hero] = []
	candidates.assign(roster.filter(func(hero: Hero) -> bool: return not is_hero_busy(hero)))
	return candidates


## ig-0og.1: the heroes with no bed, wherever they are.
func homeless_heroes() -> Array[Hero]:
	var homeless: Array[Hero] = []
	homeless.assign(roster.filter(func(hero: Hero) -> bool: return hero.home == Hero.NO_HOME))
	return homeless


## ig-0og.1: the one revolt check, TownRules.in_revolt on this town. The strike reads it, and so does
## the riot (ig-0og.3).
func is_in_revolt() -> bool:
	return TownRules.in_revolt(town_mood, homeless_heroes().size(), preload("res://balance.tres"))


## ig-0og.3: the town's notice since the last take, and clears it (SaveService.take_load_notice's pattern),
## so the hub says each death or fire once, after any scene change. {starved: Array of names, fires: int,
## wood: float, stone: float}.
func take_town_notice() -> Dictionary:
	var notice: Dictionary = _town_notice
	_town_notice = _empty_town_notice()
	return notice


static func _empty_town_notice() -> Dictionary:
	return {"starved": [], "fires": 0, "wood": 0.0, "stone": 0.0}


## ig-0og.3, the riot: fires burns, one after another, of the spare wood (over the next House's price)
## and the town stone. Food, Summon Stones, buildings and heroes never burn.
## One pass per fire, so a long step burns as its fires would one by one. A live pulse crosses one at most.
func _riot_in_memory(fires: int, balance: BalanceTable) -> void:
	var house_price: int = TownRules.wood_cost(TownRules.HOUSE, town_buildings, balance)
	for _fire: int in fires:
		var burn: Dictionary = TownRules.riot_burn(float(town_resources["wood"]), float(town_resources["stone"]), house_price, balance)
		town_resources["wood"] = burn["wood"]
		town_resources["stone"] = burn["stone"]
		_town_notice["wood"] = float(_town_notice["wood"]) + float(burn["burned_wood"])
		_town_notice["stone"] = float(_town_notice["stone"]) + float(burn["burned_stone"])
	_town_notice["fires"] = int(_town_notice["fires"]) + fires


## ig-0og.1, the strike: why no new order or repeat may go out, or "" when the town isn't in revolt.
## Rescues never ask.
func strike_refusal() -> String:
	if not is_in_revolt():
		return ""
	return "The town is in revolt: %d heroes have no bed. House them, or sacrifice some, to send orders again." % homeless_heroes().size()


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


## The hero's whole skill bar in priority order (GAME_SPEC.md § Skills, "The bar"): every skill it
## knows, once each, with a mode that skill can take. Same contract as set_hero_favorite. A dispatch
## fixes the bar into the team snapshot, so an away hero's change counts from its next expedition.
func set_skill_bar(hero: Hero, bar: Array[Dictionary]) -> bool:
	last_action_error = ""
	if SaveService.load_blocked:
		last_action_error = SaveService.load_block_reason
		return false
	if hero == null or not roster.has(hero):
		last_action_error = "That hero is not on the roster."
		return false
	var known: Array[AbilityDefinition] = Hero.known_skills(hero, preload("res://balance.tres"))
	var clean: Array[Dictionary] = []
	for entry: Dictionary in bar:
		var skill: AbilityDefinition = BattleSimulation.ABILITIES.get(str(entry.get("id", ""))) as AbilityDefinition
		if skill == null or not skill in known or not Hero.valid_mode(skill, str(entry.get("mode", ""))) or clean.any(func(kept: Dictionary) -> bool: return kept["id"] == str(skill.skill_id)):
			last_action_error = "A skill bar lists each skill the hero knows once, with a mode it can take."
			return false
		clean.append({"id": str(skill.skill_id), "mode": str(entry["mode"])})
	if clean.size() != known.size():
		last_action_error = "A skill bar lists each skill the hero knows once, with a mode it can take."
		return false
	return _commit_profile_mutation(_set_skill_bar_in_memory.bind(hero, clean))


func _set_skill_bar_in_memory(hero: Hero, bar: Array[Dictionary]) -> void:
	hero.skill_bar = bar


## The hero's whole chain list (GAME_SPEC.md § Skills, "Chains", SYSTEMS.md § Skills): one chain per
## trigger, each a known non-passive trigger with 1 to skill_chain_max_steps known non-passive steps.
## Refuses what the hero load would drop or cut, and changes nothing then. Same contract as set_skill_bar:
## a dispatch fixes the chains into the team snapshot, so an edit counts from the hero's next expedition.
func set_skill_chains(hero: Hero, chains: Array[Dictionary]) -> bool:
	last_action_error = ""
	if SaveService.load_blocked:
		last_action_error = SaveService.load_block_reason
		return false
	if hero == null or not roster.has(hero):
		last_action_error = "That hero is not on the roster."
		return false
	var balance: BalanceTable = preload("res://balance.tres")
	var known: Array[AbilityDefinition] = Hero.known_skills(hero, balance)
	var clean: Array[Dictionary] = []
	for chain: Dictionary in chains:
		var problem: String = Hero.chain_problem(chain, known)
		if problem.is_empty() and clean.any(func(kept: Dictionary) -> bool: return kept["trigger"] == str(chain["trigger"])):
			problem = "a second chain on the same trigger"
		elif problem.is_empty() and (chain["then"] as Array).size() > balance.skill_chain_max_steps:
			problem = "at most %d steps after the trigger" % balance.skill_chain_max_steps
		if not problem.is_empty():
			last_action_error = "That chain cannot be set: %s." % problem
			return false
		clean.append({"trigger": str(chain["trigger"]), "then": (chain["then"] as Array).map(func(id: Variant) -> String: return str(id))})
	return _commit_profile_mutation(_set_skill_chains_in_memory.bind(hero, clean))


func _set_skill_chains_in_memory(hero: Hero, chains: Array[Dictionary]) -> void:
	hero.skill_chains = chains


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
	return _dispatch_force_data([squad], zone_id, total_runs, {}, _empty_loadout())


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
	snapshot["piloted"] = _piloted_battle_actors.get(order_id, "")
	snapshot["catching_up"] = _catch_up_seconds(order) > 0.0
	snapshot["last_command_error"] = str(_command_errors.get(order_id, order.get("last_command_error", "")))
	snapshot["checkpoint_error"] = _checkpoint_error if _checkpoint_save_failed else str(order.get("checkpoint_error", ""))
	return snapshot


func issue_battle_command(order_id: String, command: Dictionary) -> Dictionary:
	var index: int = _order_index(order_id)
	if index < 0:
		return {"accepted": false, "error": "That battle no longer exists.", "sequence": 0}
	if _checkpoint_save_failed:
		return {"accepted": false, "error": _checkpoint_error, "sequence": Item.int_field(expedition_orders[index].get("battle") as Dictionary, "command_sequence", 0, "battle checkpoint")}
	# ig-7sn.12: refused before the commit, whose rollback would cancel the catch-up round.
	if _catch_up_seconds(expedition_orders[index]) > 0.0:
		return {"accepted": false, "error": "catching_up", "sequence": Item.int_field(expedition_orders[index].get("battle") as Dictionary, "command_sequence", 0, "battle checkpoint")}
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
		# ig-7sn.18: its job is dropped, as its owed time is. Un-paused, it sends again from its Dictionary.
		_drop_battle_advance(order_id, false)
	else:
		_paused_battle_orders.erase(order_id)
	_notify_battle_changed(order_id)


## ig-gy0.6: the player takes control of actor_id in a watched battle ("" hands it back to the AI). One pilot
## per battle, so a second call switches. The job out was sent for the old pilot: it is dropped and its seconds
## owed again, so the battle keeps its time (set_battle_paused drops its job too).
func set_battle_piloted(order_id: String, actor_id: String) -> void:
	var gone: bool = _order_index(order_id) < 0
	if gone and actor_id.is_empty():
		# Settlement removes the order, not its entry: handing the hero back still clears it. No job, nobody to tell.
		_piloted_battle_actors.erase(order_id)
		return
	if gone or str(_piloted_battle_actors.get(order_id, "")) == actor_id:
		return
	if actor_id.is_empty():
		_piloted_battle_actors.erase(order_id)
	else:
		_piloted_battle_actors[order_id] = actor_id
	_drop_battle_advance(order_id, true)
	_notify_battle_changed(order_id)


## snapshots, when given, receives the team snapshots the forecast used, so a dispatch can reuse them.
## forecast false skips the forecast (a fixed-run dispatch needs none): checking and safe read false.
func _preview_force_data(squads: Array[Dictionary], zone_id: String, total_runs: int, policies: Dictionary, loadout: Dictionary, snapshots: Array[Dictionary] = [], forecast: bool = true) -> Dictionary:
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
	# ig-0og.1: before the forecast, so a strike spends no forecast job.
	var strike: String = strike_refusal()
	if not strike.is_empty():
		return _force_preview_error(strike, 0, zone.hero_cap, squads.size())
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
	var reserve_kind: String = _loadout_spends_reserve(loadout)
	if not reserve_kind.is_empty():
		return _force_preview_error("The %s allocation would spend the stockpile reserve." % reserve_kind, team.size(), zone.hero_cap, squads.size())
	var route_seconds: float = ExpeditionOrders.force_duration_seconds(team, zone, preload("res://balance.tres"))
	if route_seconds <= 0.0:
		return _force_preview_error("The selected force cannot make progress in that zone.", team.size(), zone.hero_cap, squads.size())
	snapshots.assign(_team_snapshots(team, squads))
	# ig-7sn.14: the forecast runs as jobs; until it lands the preview is "checking".
	var entry: Dictionary = _preview_forecast(snapshots, zone, squads, policies, _loadout_escrow(loadout)) if forecast else {}
	var checking: bool = forecast and not entry.has("verdict")
	var safe: bool = entry.has("verdict") and bool(entry["verdict"]["safe"])
	var valid: bool = total_runs != 0 or safe
	var error: String = ""
	if not valid:
		error = "Until-stopped dispatch waits for the forecast." if checking else "Until-stopped dispatch requires a Safe forecast."
	# ig-ncz (in ig-0og.1): what a clear here pays of the full reward, for the summary.
	var pay_percent: int = roundi(100.0 * ExpeditionOrders.route_pay_factor(zone, route_seconds, team.size(), preload("res://balance.tres").battle_pace))
	return {"valid": valid, "error": error, "safe": safe, "checking": checking, "reason": "Checking..." if checking else str((entry.get("verdict", {}) as Dictionary).get("reason", "")), "hero_count": team.size(), "capacity": zone.hero_cap, "squad_count": squads.size(), "route_seconds": route_seconds, "pay_percent": pay_percent}


## The cached preview forecast for these exact inputs. A miss draws a seed, adds the entry and sends
## the normal and stress legs as jobs, each with its own deep copy; past the cap the oldest is dropped.
func _preview_forecast(snapshots: Array[Dictionary], zone: ZoneDefinition, squads: Array[Dictionary], policies: Dictionary, escrow: Dictionary) -> Dictionary:
	var key: Array = [snapshots, str(zone.zone_id), squads, policies, escrow]
	var index: int = _preview_forecast_index(key)
	if index >= 0:
		return _preview_forecasts[index]
	var run_seed: int = _new_run_seed()
	var entry: Dictionary = {"key": key.duplicate(true), "seed": run_seed}
	for stress: bool in [false, true]:
		var leg_snapshots: Array[Dictionary] = snapshots.duplicate(true)
		var leg_squads: Array[Dictionary] = squads.duplicate(true)
		var leg_policies: Dictionary = policies.duplicate(true)
		var leg_escrow: Dictionary = escrow.duplicate(true)
		entry["stress" if stress else "normal"] = _submit_battle_job(func(job: BattleJob) -> Dictionary: return BattleJob.run_forecast_leg("forecast", leg_snapshots, zone, leg_squads, leg_policies, leg_escrow, run_seed, stress, job))
	_preview_forecasts.append(entry)
	if _preview_forecasts.size() > PREVIEW_FORECAST_CAP:
		var dropped: Dictionary = _preview_forecasts.pop_front()
		(dropped["normal"] as BattleJob).cancelled = true
		(dropped["stress"] as BattleJob).cancelled = true
	return entry


func _preview_forecast_index(key: Array) -> int:
	for index: int in _preview_forecasts.size():
		if _preview_forecasts[index]["key"] == key:
			return index
	return -1


func _dispatch_force_data(squads: Array[Dictionary], zone_id: String, total_runs: int, policies: Dictionary, loadout: Dictionary) -> String:
	last_action_error = ""
	if SaveService.load_blocked:
		last_action_error = SaveService.load_block_reason
		return ""
	# One team snapshot per launch (ig-7sn.4): the preview's forecast key and the run both use it. Nothing
	# between them changes a hero or the ledger, and the simulation only reads snapshots.
	var snapshots: Array[Dictionary] = []
	var preview: Dictionary = _preview_force_data(squads, zone_id, total_runs, policies, loadout, snapshots, total_runs == 0)
	if not bool(preview.get("valid", false)):
		last_action_error = str(preview.get("error", "The force is invalid."))
		return ""
	var hero_ids: Array[String] = []
	for squad: Dictionary in squads:
		hero_ids.append_array(_string_array(squad.get("hero_ids")))
	var zone: ZoneDefinition = ZoneDefinition.definition_for(StringName(zone_id))
	var order_id: String = Item.new_instance_id()
	var run_seed: int = _new_run_seed()
	var escrow: Dictionary = _loadout_escrow(loadout)
	if total_runs == 0:
		# ig-7sn.14: valid means the preview's entry for these exact inputs landed Safe. The run starts
		# from its seed (the snapshots are == its key's) and no forecast runs here. The entry is consumed,
		# so its seed never starts a second run.
		var index: int = _preview_forecast_index([snapshots, zone_id, squads, policies, escrow])
		if index < 0:
			last_action_error = "Until-stopped dispatch waits for the forecast."
			return ""
		run_seed = int(_preview_forecasts[index]["seed"])
		_preview_forecasts.remove_at(index)
	var state: BattleState = BattleSimulation.create_run(order_id, snapshots, zone, squads, policies, escrow, run_seed)
	var names: PackedStringArray = []
	for squad: Dictionary in squads:
		names.append(str(squad.get("name", "Team")))
	var order: Dictionary = {
		"id": order_id, "backend": "battle_v1", "team_name": " + ".join(names), "preset_id": str(squads[0].get("id", "")),
		"preset_ids": _squad_ids(squads), "hero_ids": hero_ids, "squads": squads.duplicate(true), "zone_id": zone_id,
		"total_runs": total_runs, "runs_completed": 0, "stop_requested": false, "run_seed": run_seed,
		"initial_duration_seconds": float(preview.get("route_seconds", 0.0)), "remaining_seconds": float(preview.get("route_seconds", 0.0)),
		"cumulative_stones": 0, "cumulative_xp": 0, "cumulative_items": 0, "battle": state.to_dict(), "phase": "fighting",
		"loadout": loadout.duplicate(true), "policies": state.policies.duplicate(true), "escrow": escrow.duplicate(true), "last_command_error": "", "checkpoint_error": "", "incident_id": "",
	}
	if not _commit_profile_mutation(_append_battle_order_in_memory.bind(order)):
		return ""
	return order_id


func _append_battle_order_in_memory(order: Dictionary) -> bool:
	var escrow: Dictionary = order.get("escrow") as Dictionary
	for kind: String in BattleState.SUPPLY_KINDS:
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


## An allocation and a reserve ("keep_" + kind) per supply kind. The masterwork pairs are optional, so a
## loadout saved before them still loads; a missing field reads as 0 (DECISIONS.md 2026-09-23).
static func _validate_loadout(loadout: Dictionary) -> String:
	for raw_key: Variant in loadout.keys():
		if not raw_key is String or not (raw_key as String).trim_prefix("keep_") in BattleState.SUPPLY_KINDS:
			return "Battle loadout contains an unknown field."
	for kind: String in BattleState.SUPPLY_KINDS:
		for key: String in [kind, "keep_" + kind]:
			if not loadout.has(key):
				if kind.ends_with(BattleState.MASTERWORK_SUFFIX):
					continue
				return "Battle loadout must contain healing, revival and both reserve fields."
			if not _is_nonnegative_integer(loadout.get(key)):
				return "Battle loadout quantities must be non-negative integers."
		if float(loadout.get(kind, 0)) > 100.0:
			return "Battle allocations are capped at 100 per supply."
		if float(loadout.get("keep_" + kind, 0)) > 2147483647.0:
			return "Battle supply reserves cannot exceed 2147483647."
	return ""


## Every supply kind's allocation and reserve at 0.
static func _empty_loadout() -> Dictionary:
	var loadout: Dictionary = {}
	for kind: String in BattleState.SUPPLY_KINDS:
		loadout[kind] = 0
		loadout["keep_" + kind] = 0
	return loadout


## The stock a loadout takes into battle, every kind present.
static func _loadout_escrow(loadout: Dictionary) -> Dictionary:
	var escrow: Dictionary = {}
	for kind: String in BattleState.SUPPLY_KINDS:
		escrow[kind] = Item.int_field(loadout, kind, 0, "battle loadout")
	return escrow


## The first supply kind whose allocation would dip into its stockpile reserve, or "".
func _loadout_spends_reserve(loadout: Dictionary) -> String:
	for kind: String in BattleState.SUPPLY_KINDS:
		if Item.int_field(loadout, kind, 0, "battle loadout") > int(supplies.get(kind, 0)) - Item.int_field(loadout, "keep_" + kind, 0, "battle loadout"):
			return kind
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
	team_snapshot_builds += 1
	var result: Array[Dictionary] = []
	var balance: BalanceTable = preload("res://balance.tres")
	var cover_orders: Dictionary = _cover_orders(team, balance)
	for hero: Hero in team:
		var definition: HeroDefinition = Hero.definition_for(hero.def_id)
		var level: int = Hero.level_for(hero, balance)
		var stats: Dictionary[StringName, float] = Hero.compute_final_stats(hero, definition, balance, level)
		var snapshot: Dictionary = {"hero_id": hero.instance_id, "archetype": str(hero.def_id), "hp": stats[Hero.STAT_HP], "atk": stats[Hero.STAT_ATK], "defense": stats[Hero.STAT_DEF], "speed": stats[Hero.STAT_SPD], "crit_rate": stats[Hero.STAT_CRIT_RATE], "crit_damage": stats[Hero.STAT_CRIT_DMG], "level": level, "squad_id": _squad_for_hero(hero.instance_id, squads), "skills": Hero.bar_for(hero, balance), "chains": hero.skill_chains.duplicate(true)}
		if hero.def_id == &"knight":
			snapshot["cover_order"] = cover_orders.get(hero.instance_id, [])
		result.append(snapshot)
	return result


## ig-uu7.4: each Knight's cover order by hero id, from the kept bond index: its bond partner first
## when that is a back-row teammate, then the other back-row teammates it has bond points with, most
## first, ties in team order. Derived for one battle like stats; bonds stay unsaved. {} without a
## Knight or a back-row hero, and then the index is not read.
func _cover_orders(team: Array[Hero], balance: BalanceTable) -> Dictionary:
	var knights: Array[String] = []
	var back_row: Array[String] = []
	for hero: Hero in team:
		if hero.def_id == &"knight":
			knights.append(hero.instance_id)
		elif str(hero.def_id) in BattleSimulation.BACK_ROW:
			back_row.append(hero.instance_id)
	var orders: Dictionary = {}
	if knights.is_empty() or back_row.is_empty():
		return orders
	var pairs: Dictionary = bond_index()
	var living: Dictionary = {}
	for hero: Hero in roster:
		living[hero.instance_id] = true
	for knight_id: String in knights:
		var tallies: Dictionary = pairs.get(knight_id, {})
		var order: Array[String] = []
		for hero_id: String in back_row:
			if int((tallies.get(hero_id, {}) as Dictionary).get("points", 0)) > 0:
				order.append(hero_id)
		order.sort_custom(func(a: String, b: String) -> bool:
			var a_points: int = int(tallies[a]["points"])
			var b_points: int = int(tallies[b]["points"])
			return a_points > b_points or (a_points == b_points and back_row.find(a) < back_row.find(b)))
		var partner: String = str(Bonds.bond_from(pairs, knight_id, living, balance).get("partner", ""))
		if partner in order:
			order.erase(partner)
			order.push_front(partner)
		orders[knight_id] = order
	return orders


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
	if str(expedition_orders[index].get("phase", "")) == "checking":
		_commit_profile_mutation(_end_battle_check_in_memory.bind(order_id, "requested"))
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
	if not _loadout_spends_reserve(loadout).is_empty():
		last_action_error = "The rescue allocation would spend the stockpile reserve."
		return ""
	var zone: ZoneDefinition = ZoneDefinition.definition_for(StringName(str(incident.get("zone_id", ""))))
	if zone == null:
		last_action_error = "The incident destination is missing."
		return ""
	var order_id: String = Item.new_instance_id()
	var run_seed: int = _new_run_seed()
	var squad: Dictionary = {"id": preset_id, "name": str(preset.get("name", "Rescue")), "hero_ids": hero_ids, "stance": "stay_together", "guard_target_id": ""}
	var snapshots: Array[Dictionary] = []
	var preserved: Dictionary = incident.get("battle_snapshot") as Dictionary
	for actor_data: Variant in preserved.get("actors", []) as Array:
		if actor_data is Dictionary:
			snapshots.append((actor_data as Dictionary).duplicate(true))
	for rescuer: Dictionary in _team_snapshots(team, [squad]):
		rescuer["squad_id"] = preset_id
		snapshots.append(rescuer)
	var escrow: Dictionary = _loadout_escrow(loadout)
	# ig-1jw: the rescue fights at its incident's pace; a snapshot without one is pace 1.
	var state: BattleState = BattleSimulation.create_run(order_id, snapshots, zone, [squad], {}, escrow, run_seed, "rescue", int(preserved.get("pace", 1)))
	var order: Dictionary = {"id": order_id, "backend": "battle_v1", "team_name": str(preset.get("name", "Rescue")), "preset_id": preset_id, "preset_ids": [preset_id], "hero_ids": hero_ids, "squads": [squad], "zone_id": str(zone.zone_id), "total_runs": 1, "runs_completed": 0, "stop_requested": false, "run_seed": run_seed, "initial_duration_seconds": 0.0, "remaining_seconds": 0.0, "cumulative_stones": 0, "cumulative_xp": 0, "cumulative_items": 0, "battle": state.to_dict(), "phase": "rescuing", "loadout": loadout.duplicate(true), "policies": state.policies.duplicate(true), "escrow": escrow, "last_command_error": "", "checkpoint_error": "", "incident_id": incident_id}
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
	_raise_incident_lifetime(stranded_incidents[index])
	stranded_incidents[index]["paused"] = false
	stranded_incidents[index]["created_recovery_seconds"] = rescue_clock_seconds
	_notify_expeditions_changed()


func _append_rescue_order_in_memory(order: Dictionary, incident_index: int) -> bool:
	# First: the Tracker may be on the rescue team, and the order makes it busy.
	_raise_incident_lifetime(stranded_incidents[incident_index])
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
	Expedition.finalize_permanent_losses(incident, _string_array(incident.get("hero_ids")))
	stranded_incidents.remove_at(index)
	_notify_expeditions_changed()


## Every read (the settle, the expiry checks, the dispatch check, the hub) comes here. A running
## window uses the longest lifetime it has had (director ruling 2026-09-24, ig-wgj.10), so a Tracker
## who leaves never cuts it; a save from before the mark reads the live lifetime.
func _incident_remaining_seconds(incident: Dictionary) -> float:
	var lifetime: float = _incident_lifetime(incident)
	if bool(incident.get("paused", true)):
		return lifetime
	return maxf(lifetime - (rescue_clock_seconds - Item.float_field(incident, "created_recovery_seconds", rescue_clock_seconds, "stranded incident")), 0.0)


func _incident_lifetime(incident: Dictionary) -> float:
	return maxf(Item.float_field(incident, "lifetime_seconds", 0.0, "stranded incident"), recovery_lifetime_seconds())


## Raises a window's high-water mark to the live lifetime. The live tick calls it on every running
## window, and a window's start before its rescue order makes the Tracker busy.
func _raise_incident_lifetime(incident: Dictionary) -> void:
	incident["lifetime_seconds"] = _incident_lifetime(incident)


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
		keeper_skill(&"Forge"),
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
		keeper_skill(&"Sanctum"),
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
		keeper_is_master(&"Forge"),
		preload("res://balance.tres"),
	)


func preview_bulk_conversion(rank: int, quantity: int, reserve: int) -> Dictionary:
	return BulkOperations.preview_conversion(parts, rank, quantity, reserve)


func preview_bulk_supplies(kind: String, quantity: int, reserve: int) -> Dictionary:
	return BulkOperations.preview_supplies(kind, quantity, reserve, parts, supplies, keeper_skill(&"Apothecary"), keeper_is_master(&"Apothecary"), preload("res://balance.tres"))


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
			if supply_kind.ends_with(BattleState.MASTERWORK_SUFFIX) and not keeper_is_master(&"Apothecary"):
				last_action_error = "Only a master alchemist at home brews masterwork draughts."
				return false
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


## One pulse with its battles: each live battle advances by delta_seconds, then the pulse runs.
func tick_expeditions(delta_seconds: float) -> void:
	if delta_seconds <= 0.0 or SaveService.load_blocked or _checkpoint_save_failed:
		return
	for order: Dictionary in expedition_orders:
		if _battle_live(order):
			_advance_battle(order, delta_seconds)
	_pulse(delta_seconds)


## ig-7sn.15: each live battle is owed the frame's time. ig-7sn.18 (the threading ADR, item 7): its advance
## runs as a job. On a frame that may advance, one finished job lands, then every live battle owed at least a
## whole pulse with no job out sends one for all it is owed. So no frame lands two, and at a low frame rate
## none starves: the oldest finished job lands first, and a battle that lands sends again behind every job
## already out. The sim carries tick_remainder, so the battle runs the same ticks as advancing at the pulse
## did, up to the sim's TICK_EPSILON rounding at a chunk's edge (the pulse's own chunks varied the same way).
## A battle that ends turns home at the next pulse, at most a pulse later.
func _owe_battles(delta: float, may_advance: bool) -> void:
	var owed: Dictionary[String, float] = {}
	for order: Dictionary in expedition_orders:
		if _battle_live(order):
			var order_id: String = str(order.get("id", ""))
			owed[order_id] = float(_battle_owed.get(order_id, 0.0)) + delta
	_battle_owed = owed
	if not may_advance:
		return
	_land_battle_advance()
	for order: Dictionary in expedition_orders:
		var order_id: String = str(order.get("id", ""))
		if float(_battle_owed.get(order_id, 0.0)) >= EXPEDITION_PULSE_SECONDS and not _battle_advances.has(order_id) and _battle_live(order):
			_send_battle_advance(order, _battle_owed[order_id])
			_battle_owed.erase(order_id)


## ig-7sn.18: sends a live battle's advance by seconds (its leg's rest at most) as a job. The job takes the
## kept BattleState itself: the main thread lets go of it, and a read before the landing decodes the order's
## Dictionary, as _battle_state does on a miss.
func _send_battle_advance(order: Dictionary, seconds: float) -> void:
	var order_id: String = str(order.get("id", ""))
	var state: BattleState = _battle_state(order)
	state.piloted_id = str(_piloted_battle_actors.get(order_id, ""))
	_battle_states.erase(order_id)
	var step: float = minf(seconds, maxf(state.max_seconds - state.elapsed_seconds, 0.0))
	_battle_advances[order_id] = {"battle": order.get("battle"), "state": state, "seconds": seconds, "job": _submit_battle_job(func(job: BattleJob) -> Dictionary: return BattleJob.run_battle(state, step, job))}


## ig-7sn.18: lands the oldest finished job whose order still holds the battle Dictionary it was sent from
## and is still live (a load has cleared the table first). Each finished job before it that fails that is
## dropped, its seconds owed again while its order is live (a command replaced the Dictionary).
func _land_battle_advance() -> void:
	for order_id: String in _battle_advances.keys():
		var entry: Dictionary = _battle_advances[order_id]
		if not _battle_job_done(entry["job"]):
			continue
		var index: int = _order_index(order_id)
		var result: Dictionary = (entry["job"] as BattleJob).result
		if index >= 0 and is_same(expedition_orders[index].get("battle"), entry["battle"]) and _battle_live(expedition_orders[index]) and not bool(result.get("cancelled", true)):
			_battle_advances.erase(order_id)
			_land_battle(expedition_orders[index], result["battle"], entry["state"])
			return
		_drop_battle_advance(order_id, index >= 0 and _battle_live(expedition_orders[index]))


## ig-7sn.18: drops an order's job. It stops at its next chunk, and its state is thrown away: the job
## advanced it in place, so kept beside the old Dictionary it would run ahead of it. owe: its seconds are
## owed again.
func _drop_battle_advance(order_id: String, owe: bool) -> void:
	var entry: Dictionary = _battle_advances.get(order_id, {})
	if entry.is_empty():
		return
	(entry["job"] as BattleJob).cancelled = true
	_battle_advances.erase(order_id)
	if owe:
		_battle_owed[order_id] = float(_battle_owed.get(order_id, 0.0)) + float(entry["seconds"])


## The pulse without the battles' advances: the route clocks, the due orders, the town, the checks.
## _process runs it every EXPEDITION_PULSE_SECONDS, its battles advancing on the frames between.
func _pulse(delta_seconds: float) -> void:
	var has_due_order: bool = false
	for order: Dictionary in expedition_orders:
		var route_due: bool = Item.float_field(order, "remaining_seconds", 0.0, "expedition order") - delta_seconds <= 0.0
		if str(order.get("backend", "legacy_v2")) != "battle_v1":
			if route_due:
				has_due_order = true
				break
			continue
		if str(order.get("phase", "")) == "checking":
			continue
		if _battle_order_due(order, route_due):
			has_due_order = true
			break
	for order_id: String in _battle_states.keys():
		if _order_index(order_id) < 0:
			_battle_states.erase(order_id)
	var has_expiring_cache: bool = false
	if not recovery_clock_paused:
		var next_clock: float = recovery_clock_seconds + delta_seconds
		for cache: LostCache in lost_caches:
			if cache_seconds_remaining(cache, next_clock) < 0.0:
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
	var farm: int = _workers_home(TownRules.FARM)
	var starve_death: bool = TownRules.starve_step(float(town_resources["food"]), town_starving_seconds, town_starve_acked, farm, food_eaters().size(), not starvation_candidates().is_empty(), delta_seconds, preload("res://balance.tres"))["death"]
	# A building that finishes is saved at once: with no other clock running, the periodic save would
	# never write it, and every reload would build it again.
	var finishes_build: bool = town_buildings.any(func(building: Dictionary) -> bool: return _is_building(building) and float(building["build_remaining"]) <= delta_seconds)
	if has_due_order or has_expiring_cache or has_expiring_incident or starve_death or finishes_build:
		_commit_profile_mutation(_advance_time_in_memory.bind(delta_seconds))
	else:
		_advance_clocks_in_memory(delta_seconds)
		_notify_expeditions_changed()
	# ig-7sn.6: the repeat checks land and go out at the pulse, never inside load_game.
	_land_battle_checks()
	_send_battle_checks()


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
			var run_seed: int = Item.int_field(order, "run_seed", _new_run_seed(), "legacy order")
			var state: BattleState = BattleSimulation.create_run(str(order.get("id")), _team_snapshots(team, [squad]), zone, [squad], {}, {}, run_seed)
			order["backend"] = "battle_v1"
			order["preset_ids"] = [squad_id]
			order["squads"] = [squad]
			order["battle"] = state.to_dict()
			order["phase"] = "fighting"
			order["loadout"] = _empty_loadout()
			order["policies"] = state.policies.duplicate(true)
			order["escrow"] = _loadout_escrow({})
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


## ig-7sn.12 (DECISIONS.md 2026-09-25 "Battle sim threading", item 8): runs no sim. An active battle owes
## the offline seconds, capped at the rest of its leg, as catch_up_seconds; the pulse sends the job
## and the round's landing does what the advance here did.
func _advance_orders_in_memory(delta_seconds: float) -> void:
	for order: Dictionary in expedition_orders:
		order["remaining_seconds"] = maxf(Item.float_field(order, "remaining_seconds", 0.0, "expedition order") - delta_seconds, 0.0)
		if str(order.get("backend", "legacy_v2")) == "battle_v1":
			var battle: Dictionary = order.get("battle") as Dictionary
			if str(battle.get("status", "")) == "active":
				var rest: float = maxf(Item.float_field(battle, "max_seconds", 180.0, "battle checkpoint") - Item.float_field(battle, "elapsed_seconds", 0.0, "battle checkpoint"), 0.0)
				# Whole microseconds: the value survives the save's JSON exactly, so a reloaded catch-up
				# runs the same seconds. Under the sim's TICK_EPSILON, it never changes a tick count.
				var owed: float = roundi(minf(_catch_up_seconds(order) + delta_seconds, rest) * 1000000.0) / 1000000.0
				if owed > 0.0:
					order["catch_up_seconds"] = owed
	_resolve_due_orders_in_memory()
	_notify_roster_changed()
	_notify_expeditions_changed()


## The pulse's clocks. No live battle advances here (_land_battle writes each advance, and says so); one
## whose fight ended since the last pulse turns home here, and leaves an incident if nobody can.
func _advance_clocks_in_memory(delta_seconds: float) -> void:
	for order: Dictionary in expedition_orders:
		order["remaining_seconds"] = maxf(Item.float_field(order, "remaining_seconds", 0.0, "expedition order") - delta_seconds, 0.0)
		if str(order.get("backend", "legacy_v2")) == "battle_v1" and not _battle_clock_stopped(order):
			if _battle_live(order):
				continue
			if not str(order.get("phase", "")) in ["returning", "checking"]:
				var state: BattleState = _battle_state(order)
				order["phase"] = "returning"
				if _battle_has_no_secured_allies(state):
					_capture_stranded_incident(order, state)
			_notify_battle_changed(str(order.get("id", "")))
	if not recovery_clock_paused and not lost_caches.is_empty():
		recovery_clock_seconds += delta_seconds
	# Live tick only: _advance_orders_in_memory (the offline catch-up) makes nothing (GAME_SPEC.md § Hard constraints).
	var balance: BalanceTable = preload("res://balance.tres")
	var work: float = TownRules.work_multiplier(town_starving_seconds, balance)
	town_resources["wood"] = float(town_resources["wood"]) + TownRules.wood_made(_workers_home(TownRules.LUMBERMILL), delta_seconds, balance) * work
	town_resources["stone"] = float(town_resources["stone"]) + TownRules.stone_made(_workers_home(TownRules.MINE), delta_seconds, balance) * work
	# Construction moves on the live tick only too (SYSTEMS.md § Stone and construction). At 0 it is finished.
	for building: Dictionary in town_buildings:
		if _is_building(building):
			building["build_remaining"] = maxf(float(building["build_remaining"]) - delta_seconds, 0.0)
			if float(building["build_remaining"]) <= 0.0:
				building.erase("build_remaining")
	var candidates: Array[Hero] = starvation_candidates()
	var step: Dictionary = TownRules.starve_step(float(town_resources["food"]), town_starving_seconds, town_starve_acked, _workers_home(TownRules.FARM), food_eaters().size(), not candidates.is_empty(), delta_seconds, balance)
	town_resources["food"] = step["food"]
	town_starving_seconds = step["clock"]
	town_starve_acked = step["acked"]
	if step["death"]:
		_starve_in_memory(candidates, balance)
	town_mood = TownRules.mood_step(town_mood, homeless_heroes().size(), delta_seconds, balance)
	# ig-0og.3, the riot: the same revolt check as the strike, read after the mood step.
	if is_in_revolt():
		var revolt_before: float = town_revolt_seconds
		town_revolt_seconds += delta_seconds
		var fires: int = TownRules.riot_fires(revolt_before, town_revolt_seconds, balance)
		if fires > 0:
			_riot_in_memory(fires, balance)
	else:
		town_revolt_seconds = 0.0
	for incident: Dictionary in stranded_incidents:
		if not bool(incident.get("paused", true)):
			rescue_clock_seconds += delta_seconds
			break
	# A window never shrinks: every running one keeps the longest lifetime it has had (ig-wgj.10).
	var lifetime: float = recovery_lifetime_seconds()
	for cache: LostCache in lost_caches:
		cache.lifetime_seconds = maxf(cache.lifetime_seconds, lifetime)
	for incident: Dictionary in stranded_incidents:
		if not bool(incident.get("paused", true)):
			_raise_incident_lifetime(incident)
	# Live tick only, like the wood: home keepers learn by working (SYSTEMS.md § Keepers and professions).
	for working: Array in _working_keepers():
		Hero.add_profession_xp(working[0] as Hero, working[1] as StringName, delta_seconds, preload("res://balance.tres"))


func _resolve_due_orders_in_memory() -> void:
	var due_orders: Array[Dictionary] = []
	for order: Dictionary in expedition_orders:
		var is_due: bool = Item.float_field(order, "remaining_seconds", 0.0, "expedition order") <= 0.0
		if str(order.get("backend", "legacy_v2")) == "battle_v1":
			# A "checking" order is settled already; its check lands at the pulse (ig-7sn.6).
			if str(order.get("phase", "")) == "checking":
				continue
			is_due = _battle_order_due(order, is_due)
		if is_due:
			due_orders.append(order)
	due_orders.sort_custom(_due_order_before)
	for due_order: Dictionary in due_orders:
		_complete_order_in_memory(str(due_order.get("id", "")))


## Offline battle-seconds the order still owes (ig-7sn.12). from_dict drops a bad value.
static func _catch_up_seconds(order: Dictionary) -> float:
	return Item.float_field(order, "catch_up_seconds", 0.0, "expedition order")


## A battle that advances: a battle order past its check, fighting, its clock running. The status is read
## off the Dictionary, the value from_dict would read, so asking decodes nothing (ig-7sn.15).
func _battle_live(order: Dictionary) -> bool:
	return str(order.get("backend", "legacy_v2")) == "battle_v1" and str(order.get("phase", "")) != "checking" and not _battle_clock_stopped(order) and str((order.get("battle") as Dictionary).get("status", "active")) == "active"


## Due once its fight is over and its route home is done, or at once when nobody is left to walk home.
func _battle_order_due(order: Dictionary, route_due: bool) -> bool:
	if str((order.get("battle") as Dictionary).get("status", "active")) == "active":
		return false
	return route_due or _battle_has_no_secured_allies(_battle_state(order))


## Advances a live battle by seconds (its leg's rest at most) on the main thread, for tick_expeditions
## (ig-7sn.15; the frames send jobs since ig-7sn.18).
func _advance_battle(order: Dictionary, seconds: float) -> void:
	var state: BattleState = _battle_state(order)
	state.piloted_id = str(_piloted_battle_actors.get(str(order.get("id", "")), ""))
	BattleSimulation.advance(state, minf(seconds, maxf(state.max_seconds - state.elapsed_seconds, 0.0)))
	_land_battle(order, state.to_dict(), state)


## An advance's write-back, the one place an advanced battle lands: the order takes the new Dictionary, the
## state it came from is kept beside it, and the battle says so.
func _land_battle(order: Dictionary, battle: Dictionary, state: BattleState) -> void:
	var order_id: String = str(order.get("id", ""))
	order["battle"] = battle
	_battle_states[order_id] = [battle, state]
	pulse_battle_advances += 1
	_notify_battle_changed(order_id)


## The order's battle as a BattleState: the kept one while the order still holds its Dictionary, else a
## decode, kept. _advance_battle advances it; _send_battle_advance hands it to a job. Others only read it.
func _battle_state(order: Dictionary) -> BattleState:
	var order_id: String = str(order.get("id", ""))
	var battle: Dictionary = order.get("battle") as Dictionary
	var kept: Array = _battle_states.get(order_id, [])
	if not kept.is_empty() and is_same(kept[0], battle):
		return kept[1] as BattleState
	var state := BattleState.from_dict(battle)
	_count_pulse_decode(state)
	_battle_states[order_id] = [battle, state]
	return state


func _count_pulse_decode(state: BattleState) -> void:
	if state.status == "active":
		pulse_decodes_active += 1
	else:
		pulse_decodes_idle += 1


## A player's tactical pause, or a catch-up still owed: either stops the battle's clock. They are kept
## apart so un-pausing (the battle view does it on leave) never frees an order mid catch-up.
func _battle_clock_stopped(order: Dictionary) -> bool:
	return _paused_battle_orders.has(str(order.get("id", ""))) or _catch_up_seconds(order) > 0.0


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
	if state.kind != "rescue":
		_record_battle(order, state, outcome, {})
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
	var xp_multiplier: float = training_xp_multiplier()
	# ig-1jw: rewards read the battle's own pace: XP and stones xP, P loot rolls.
	var xp_amount: int = roundi(float(balance.xp_per_wave * outcome.completed_waves * state.pace) * xp_multiplier)
	var stones_earned: int = 0
	var items_earned: int = 0
	if outcome.status == "victory" and zone != null:
		xp_amount = roundi(float((balance.xp_per_wave * outcome.completed_waves + zone.xp_reward) * state.pace) * xp_multiplier)
		# ig-0og.1: rate B, times ig-ncz's factor from this run's own route and team size.
		var route: float = Item.float_field(order, "initial_duration_seconds", 0.0, "battle order")
		var factor: float = ExpeditionOrders.route_pay_factor(zone, route, _string_array(order.get("hero_ids")).size(), state.pace)
		stones_earned = ExpeditionOrders.stone_payout(zone, state.pace, balance, factor)
		stones += stones_earned
		var run_seed: int = Item.int_field(order, "run_seed", 0, "battle order")
		for roll: int in state.pace:
			inventory.append(Expedition.roll_loot(zone, balance, run_seed + roll))
		items_earned = state.pace
		cleared_zone_ids[zone.zone_id] = true
	if not secured.is_empty() and xp_amount > 0:
		credit_team_xp(secured, xp_amount, balance, true)
	turns += 1
	order["runs_completed"] = Item.int_field(order, "runs_completed", 0, "battle order") + 1
	order["cumulative_stones"] = Item.int_field(order, "cumulative_stones", 0, "battle order") + stones_earned
	order["cumulative_xp"] = Item.int_field(order, "cumulative_xp", 0, "battle order") + xp_amount * secured.size()
	order["cumulative_items"] = Item.int_field(order, "cumulative_items", 0, "battle order") + items_earned
	var stopped_reason: String = _battle_stop_reason(order, state, outcome)
	if stopped_reason.is_empty() and not _begin_battle_check(order):
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


## ig-7sn.6: a due repeat spends its escrow and draws its seed now, then waits in "checking" for its
## forecast, which runs as two jobs off the settle pulse (_send_battle_checks). Only the phase is new in
## the save: run_seed and escrow are the repeat's own keys.
func _begin_battle_check(order: Dictionary) -> bool:
	# ig-0og.1: a town in revolt sends no repeat; the order stops with stopped_reason "revolt".
	if not strike_refusal().is_empty():
		last_action_error = "revolt"
		return false
	for hero_id: String in _string_array(order.get("hero_ids")):
		if hero_by_id(hero_id) == null:
			last_action_error = "A repeat team member is missing."
			return false
	var loadout: Dictionary = order.get("loadout") as Dictionary
	if not _loadout_spends_reserve(loadout).is_empty():
		last_action_error = "insufficient_refill"
		return false
	var escrow: Dictionary = _loadout_escrow(loadout)
	for kind: String in BattleState.SUPPLY_KINDS:
		supplies[kind] = int(supplies.get(kind, 0)) - int(escrow.get(kind, 0))
	order["run_seed"] = _new_run_seed()
	order["escrow"] = escrow
	order["phase"] = "checking"
	return true


func _settle_rescue_order(order: Dictionary, state: BattleState, outcome: BattleOutcome) -> void:
	var incident_index: int = _incident_index(str(order.get("incident_id", "")))
	var rescued: Array[String] = []
	if incident_index >= 0:
		for hero_id: String in _string_array(stranded_incidents[incident_index].get("hero_ids")):
			if hero_id in outcome.secured_hero_ids:
				rescued.append(hero_id)
	_record_battle(order, state, outcome, {"rescued": rescued, "rescuers": _string_array(order.get("hero_ids"))})
	if incident_index < 0:
		return
	var incident: Dictionary = stranded_incidents[incident_index]
	var remaining: Array[String] = _string_array(incident.get("hero_ids"))
	for secured_id: String in outcome.secured_hero_ids:
		remaining.erase(secured_id)
	# battle_orders holds only the exceptions to source_order_id: a rescuer this rescue stranded
	# links to the rescue (DECISIONS.md 2026-09-24 item 5). Heroes who left the incident drop out.
	var battle_orders: Dictionary = {}
	var saved_links: Variant = incident.get("battle_orders")
	if saved_links is Dictionary:
		battle_orders = (saved_links as Dictionary).duplicate()
	for stranded_id: String in outcome.stranded_hero_ids:
		if hero_by_id(stranded_id) != null and not remaining.has(stranded_id):
			remaining.append(stranded_id)
			battle_orders[stranded_id] = str(order.get("id", ""))
	for hero_id: Variant in battle_orders.keys():
		if not remaining.has(str(hero_id)):
			battle_orders.erase(hero_id)
	incident["hero_ids"] = remaining
	incident["battle_orders"] = battle_orders
	incident["active_rescue_order_id"] = ""
	incident["battle_snapshot"] = _incident_snapshot(state, remaining)
	if remaining.is_empty():
		stranded_incidents.remove_at(incident_index)
	elif bool(incident.get("expiry_pending", false)) or _incident_remaining_seconds(incident) <= 0.0:
		Expedition.finalize_permanent_losses(incident, remaining)
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
		# A chain's target may not be kept, and its ticks are this battle's (ig-gy0.5): the stranded start none.
		for key: String in BattleActor.CHAIN_KEYS:
			effect_state.erase(key)
		effect_state.erase("next_swing_skill")
	snapshot["actors"] = kept
	snapshot["squads"] = []
	snapshot["status"] = "stranded"
	snapshot["downed_ever_ids"] = stranded_ids.duplicate()
	snapshot["extracted_ids"] = []
	snapshot["moments"] = []
	snapshot["moments_truncated"] = false
	snapshot["kills"] = {}
	return snapshot


func _refund_battle_supplies(remainder: Dictionary) -> void:
	for kind: String in BattleState.SUPPLY_KINDS:
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
	for cache_index: int in range(lost_caches.size() - 1, -1, -1):
		if cache_seconds_remaining(lost_caches[cache_index], recovery_clock_seconds) < 0.0:
			lost_caches.remove_at(cache_index)


func _expire_stranded_incidents_in_memory() -> void:
	for index: int in range(stranded_incidents.size() - 1, -1, -1):
		var incident: Dictionary = stranded_incidents[index]
		if bool(incident.get("paused", true)) or _incident_remaining_seconds(incident) > 0.0:
			continue
		if not str(incident.get("active_rescue_order_id", "")).is_empty():
			incident["expiry_pending"] = true
			continue
		Expedition.finalize_permanent_losses(incident, _string_array(incident.get("hero_ids")))
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
	snapshot["version"] = SaveService.SAVE_VERSION
	var kept: Dictionary = _rollback_kept()
	_save_deferred_depth += 1
	_notification_deferred_depth += 1
	_ledger_hold_depth += 1
	# Variant is required because most mutations return void while fallible bulk application returns bool.
	var mutation_result: Variant = mutation.call()
	_save_deferred_depth -= 1
	if mutation_result is bool and not (mutation_result as bool):
		_ledger_hold_depth -= 1
		_roll_back(snapshot, kept)
		if last_action_error.is_empty():
			last_action_error = "The profile changed while the operation was being applied."
		return false
	var saved: bool = SaveService.save()
	_ledger_hold_depth -= 1
	if saved:
		if _ledger_hold_depth == 0:
			_evict_ledger()
		_notification_deferred_depth -= 1
		_flush_deferred_notifications()
		return true
	_roll_back(snapshot, kept)
	last_action_error = SaveService.last_write_error
	return false


## What a rollback restores that the snapshot does not hold. The records are not in the snapshot: a
## rollback truncates the list back instead (item 8). The checks are kept too (ig-7sn.17): every job out
## was sent for this pre-mutation state, so each check still holding its order's battle stays current.
func _rollback_kept() -> Dictionary:
	var checks: Dictionary[String, Dictionary] = {}
	var current: Array[String] = []
	for order_id: String in _battle_checks:
		checks[order_id] = _battle_checks[order_id].duplicate()
		var index: int = _order_index(order_id)
		if index >= 0 and is_same(expedition_orders[index].get("battle"), _battle_checks[order_id]["battle"]):
			current.append(order_id)
	return {
		"ledger": ledger, "tiers": _ledger_tiers, "ledger_size": ledger.size(),
		"paused": _paused_battle_orders.duplicate(), "piloted": _piloted_battle_actors.duplicate(), "owed": _battle_owed.duplicate(),
		"checkpoint_failed": _checkpoint_save_failed, "checkpoint_error": _checkpoint_error,
		"command_errors": _command_errors.duplicate(), "checks": checks, "current": current,
		"town_notice": _town_notice.duplicate(true),
	}


## Undoes a refused or failed transaction: the snapshot by value, then what _rollback_kept kept. It is not
## a load, so it cancels no job (the threading ADR, item 5: only quit and a load do): each check that was
## current is re-pointed at its restored order's battle, which from_dict rebuilt with the same value.
func _roll_back(snapshot: Dictionary, kept: Dictionary) -> void:
	_save_deferred_depth += 1
	_read_profile(snapshot)
	ledger = kept["ledger"]
	ledger.resize(int(kept["ledger_size"]))
	_ledger_tiers = kept["tiers"]
	_ledger_tiers.resize(int(kept["ledger_size"]))
	_paused_battle_orders = kept["paused"]
	_piloted_battle_actors = kept["piloted"]
	# ig-7sn.15: the battles keep the time they are owed.
	_battle_owed = kept["owed"]
	_checkpoint_save_failed = bool(kept["checkpoint_failed"])
	_checkpoint_error = str(kept["checkpoint_error"])
	_command_errors = kept["command_errors"]
	# ig-0og.3: before the flush below, or its refresh would take the undone death or fire.
	_town_notice = kept["town_notice"]
	_battle_checks = kept["checks"]
	for order_id: String in _battle_checks.keys():
		# A check the mutation ended (its jobs cancelled) stays ended: a job that finished first still holds
		# a result, which must not land. The order is checking again, so the pulse sends a fresh check.
		if _battle_checks[order_id].values().any(func(value: Variant) -> bool: return value is BattleJob and (value as BattleJob).cancelled):
			_battle_checks.erase(order_id)
	for order_id: String in kept["current"]:
		var index: int = _order_index(order_id)
		if index >= 0 and _battle_checks.has(order_id):
			_battle_checks[order_id]["battle"] = expedition_orders[index].get("battle")
	_save_deferred_depth -= 1
	_notification_deferred_depth -= 1
	_flush_deferred_notifications()


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
		"town_starving_seconds": town_starving_seconds,
		"town_starve_acked": town_starve_acked,
		"town_mood": town_mood,
		"town_revolt_seconds": town_revolt_seconds,
		"ledger_next_seq": ledger_next_seq,
	}


## A load: stops every sim job, then reads data (ig-7sn.17: a rollback reads without the stop).
func from_dict(data: Dictionary) -> void:
	_cancel_battle_jobs()
	_town_notice = _empty_town_notice()
	_read_profile(data)


func _read_profile(data: Dictionary) -> void:
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
	supplies = BattleState.supplies_from({"healing": 3, "revival": 1})
	stranded_incidents.clear()
	rescue_clock_seconds = 0.0
	_paused_battle_orders.clear()
	_piloted_battle_actors.clear()
	_battle_states.clear()
	_battle_owed.clear()
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
	_read_ledger(data)
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
			var order: Dictionary = (entry as Dictionary).duplicate(true)
			# ig-7sn.12: optional; missing is 0, and a bad value loads as 0. Only an active battle can
			# owe: one already over (a settled or "checking" leg) must never be caught up and settled again.
			if order.has("catch_up_seconds"):
				var owed: Variant = order["catch_up_seconds"]
				var battle: Variant = order.get("battle")
				if not (owed is int or owed is float) or not is_finite(float(owed)) or float(owed) < 0.0 or not battle is Dictionary or str((battle as Dictionary).get("status", "")) != "active":
					push_warning("Expedition order catch_up_seconds '%s' is invalid; it loads as 0." % str(owed))
					order.erase("catch_up_seconds")
			expedition_orders.append(order)
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
			supplies = BattleState.supplies_from(saved_supplies as Dictionary)
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


## Additive keys (ig-6m2.5.2). Repairs, never refusals, so a save never skips a warning: a clock that
## is missing or null reads 0; not finite or below 0 reads 0 with a warning; past its stop point
## unacknowledged it reads the stop point. acked that is missing or not a bool reads false, and so
## does acked true with the clock below its stop point (it only ever means "this warning was seen").
func _read_starvation(data: Dictionary, balance: BalanceTable) -> void:
	town_starving_seconds = 0.0
	var raw_clock: Variant = data.get("town_starving_seconds")
	if (raw_clock is int or raw_clock is float) and is_finite(float(raw_clock)) and float(raw_clock) >= 0.0:
		town_starving_seconds = float(raw_clock)
	elif raw_clock != null:
		push_warning("Invalid town_starving_seconds '%s': the town reads as fed." % raw_clock)
	var raw_acked: Variant = data.get("town_starve_acked")
	town_starve_acked = raw_acked is bool and raw_acked as bool
	var stop: float = TownRules.starve_stop_seconds(town_starving_seconds, balance)
	if not town_starve_acked:
		town_starving_seconds = minf(town_starving_seconds, stop)
	elif town_starving_seconds < stop:
		town_starve_acked = false
	# ig-0og.1: town_mood, additive. Missing or null reads 100 (a legacy town starts calm); not a finite
	# number reads 100 with a warning; outside 0-100 is clamped with a warning.
	town_mood = 100.0
	var raw_mood: Variant = data.get("town_mood")
	if (raw_mood is int or raw_mood is float) and is_finite(float(raw_mood)):
		town_mood = clampf(float(raw_mood), 0.0, 100.0)
		if town_mood != float(raw_mood):
			push_warning("town_mood %s is outside 0-100: it reads %s." % [raw_mood, town_mood])
	elif raw_mood != null:
		push_warning("Invalid town_mood '%s': the town reads calm (100)." % raw_mood)
	# ig-0og.3: town_revolt_seconds, additive. Missing or null reads 0; not a finite number, or under 0,
	# reads 0 with a warning.
	town_revolt_seconds = 0.0
	var raw_revolt: Variant = data.get("town_revolt_seconds")
	if (raw_revolt is int or raw_revolt is float) and is_finite(float(raw_revolt)) and float(raw_revolt) >= 0.0:
		town_revolt_seconds = float(raw_revolt)
	elif raw_revolt != null:
		push_warning("Invalid town_revolt_seconds '%s': the riot clock reads 0." % raw_revolt)


## Additive keys (no SAVE_VERSION bump). A save without town_resources gets town_start_wood once;
## stone has no start stock, so a save without it (every save before ig-6m2.3.1) reads 0. Food is
## different: a save without the food key gets town_start_food once, even inside an existing (or
## broken) town_resources, because every save before ig-6m2.5.1 has town_resources and no food.
## A building that is malformed, off the map or on another building is dropped. A hall the save
## never names (every ig-6m2.1-era save names none) stands on its default hex before anything is
## read, so a building there is dropped, as it was when the halls were authored. A hall the save
## names but that is dropped goes on the nearest free hex to its default; on a full map the last
## placed building is dropped to make room.
func _read_town(data: Dictionary) -> void:
	var balance: BalanceTable = preload("res://balance.tres")
	town_buildings.clear()
	town_resources = {"wood": balance.town_start_wood, "stone": 0.0, "food": balance.town_start_food}
	var raw_resources: Variant = data.get("town_resources")
	if raw_resources is Dictionary:
		town_resources["wood"] = maxf(Item.float_field(raw_resources as Dictionary, "wood", 0.0, "town resources"), 0.0)
		town_resources["stone"] = maxf(Item.float_field(raw_resources as Dictionary, "stone", 0.0, "town resources"), 0.0)
		town_resources["food"] = maxf(Item.float_field(raw_resources as Dictionary, "food", balance.town_start_food, "town resources"), 0.0)
	elif raw_resources != null:
		push_error("Invalid town_resources: expected Dictionary, got %s." % type_string(typeof(raw_resources)))
		town_resources["wood"] = 0.0
	_read_starvation(data, balance)
	var entries: Array = _array_field(data, "town_buildings")
	var named: Array = entries.map(func(entry: Variant) -> Variant: return (entry as Dictionary).get("id") if entry is Dictionary else null)
	for hall: Dictionary in TownRules.default_halls():
		if not named.has(hall["id"]):
			town_buildings.append(hall)
	var highest: int = 0
	for entry: Variant in entries:
		var building: Dictionary = _read_town_building(entry)
		if building.is_empty():
			push_warning("Invalid town building %s; dropped." % str(entry))
			continue
		town_buildings.append(building)
		highest = maxi(highest, String(building["id"]).get_slice("_", 1).to_int())
	town_next_id = maxi(Item.int_field(data, "town_next_id", 1, "game session"), highest + 1)
	for hall: Dictionary in TownRules.default_halls():
		if not town_building(StringName(hall["id"])).is_empty():
			continue
		var hex := Vector2i(hall["q"], hall["r"])
		var free: Array[Vector2i] = TownRules.map_hexes(balance).filter(func(other: Vector2i) -> bool: return TownRules.hex_refusal(other, town_buildings, balance).is_empty())
		free.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return TownRules.ring_distance(a - hex) < TownRules.ring_distance(b - hex))
		if free.is_empty():
			# A hall always stands: on a full map the last placed building makes room.
			var last: int = town_buildings.rfind_custom(func(building: Dictionary) -> bool: return not TownRules.is_hall(building["id"]))
			var evicted: Dictionary = town_buildings[last]
			town_buildings.remove_at(last)
			push_warning("The map is full; %s was dropped to make room for the %s." % [String(evicted["id"]).capitalize(), String(hall["id"]).capitalize()])
			free = [Vector2i(evicted["q"], evicted["r"])]
		push_warning("The %s was dropped; it stands at %s." % [String(hall["id"]).capitalize(), free[0]])
		hall["q"] = free[0].x
		hall["r"] = free[0].y
		town_buildings.append(hall)


## Additive keys (ig-m6o.1). A save without them loads an empty ledger; nothing is backfilled. A
## record without a String kind or an increasing int seq is dropped. SaveService.load_game() hands
## the side file's committed records in as "ledger"; a legacy save still embeds them. Always a new
## list, never cleared in place: a rollback puts the old one back (_commit_profile_mutation).
func _read_ledger(data: Dictionary) -> void:
	var fresh: Array[Dictionary] = []
	ledger = fresh
	var last_seq: int = 0
	for entry: Variant in _array_field(data, "ledger"):
		var record: Variant = Ledger.normalized(entry)
		if not record is Dictionary or not (record as Dictionary).get("seq") is int or int((record as Dictionary)["seq"]) <= last_seq or not (record as Dictionary).get("kind") is String:
			push_warning("Invalid ledger record %s; dropped." % str(entry))
			continue
		ledger.append(record as Dictionary)
		last_seq = int((record as Dictionary)["seq"])
	ledger_next_seq = maxi(Item.int_field(data, "ledger_next_seq", 1, "game session"), last_seq + 1)
	_ledger_tiers = Ledger.tiers(ledger)
	_evict_ledger()


## Appends one Ledger record, stamped now. Outside a profile mutation nothing can roll it back, so it
## evicts at once; inside one, _commit_profile_mutation evicts after the commit.
func _record(kind: String, fields: Dictionary) -> void:
	var in_step: bool = _bond_in_step()
	ledger_next_seq = Ledger.append(ledger, ledger_next_seq, int(Time.get_unix_time_from_system()), kind, fields)
	_ledger_tiers.append(Ledger.tier(ledger.back()))
	if in_step:
		Bonds.fold_in(_bond_state, ledger.back(), preload("res://balance.tres"))
		_bond_seq = ledger_next_seq
	else:
		# A rollback puts seqs back, so an index out of step could look in step after this append.
		_bond_ledger = null
	if _ledger_hold_depth == 0:
		_evict_ledger()


func _evict_ledger() -> void:
	if _ledger_tiers.size() != ledger.size():
		_ledger_tiers = Ledger.tiers(ledger)
	for record: Dictionary in Ledger.evict(ledger, _ledger_tiers, preload("res://balance.tres").ledger_max_records):
		if _bond_in_step() and not Bonds.fold_out(_bond_state, record, preload("res://balance.tres")):
			_bond_ledger = null


## Every hero's bond tallies (Bonds.index() of the ledger) for Bonds.bond_from; callers never change
## it. An append folds in and an eviction folds out; a load (a new array) or a rollback that dropped an
## append rebuilds once, on the next ask.
func bond_index() -> Dictionary:
	if not _bond_in_step():
		_bond_state = Bonds.index_state(ledger, preload("res://balance.tres"))
		_bond_ledger = ledger
		_bond_seq = ledger_next_seq
		bond_builds += 1
	return _bond_state["pairs"]


## The kept index's {version, touched} (Bonds.index_state): which heroes' tallies each fold since
## bond_index()'s pairs were built touched (ig-7sn.16). A rebuild makes new pairs and starts these over.
## Callers never change it.
func bond_changes() -> Dictionary:
	bond_index()
	return {"version": _bond_state["version"], "touched": _bond_state["touched"]}


func _bond_in_step() -> bool:
	return is_same(ledger, _bond_ledger) and ledger_next_seq == _bond_seq


## One battle record per settled battle; team is every allied actor in the fight, downed or not
## (a rescue's stranded heroes included).
func _record_battle(order: Dictionary, state: BattleState, outcome: BattleOutcome, extra: Dictionary) -> void:
	var team: Array[String] = []
	team.assign(_battle_ally_hero_ids(order.get("battle") as Dictionary).keys())
	var record: Dictionary = {"order": str(order.get("id", "")), "zone": state.zone_id, "battle_kind": state.kind, "result": outcome.status, "team": team, "kills": outcome.kills.duplicate(), "moments": outcome.moments.duplicate(true)}
	if outcome.moments_truncated:
		record["moments_truncated"] = true
	record.merge(extra)
	_record("battle", record)


## {} unless entry is a well-formed building on a free hex with an unused id.
func _read_town_building(entry: Variant) -> Dictionary:
	if not entry is Dictionary:
		return {}
	var raw: Dictionary = entry as Dictionary
	var raw_id: Variant = raw.get("id")
	var raw_type: Variant = raw.get("type")
	if not raw_id is String or not raw_type is String:
		return {}
	var id := StringName(raw_id as String)
	if (TownRules.type_of(id) if not TownRules.is_hall(id) else id) != StringName(raw_type as String):
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
	var building: Dictionary = {"id": raw_id as String, "type": raw_type as String, "q": hex.x, "r": hex.y}
	# Additive (ig-6m2.3.2): a missing key, 0 or less, or a bad value loads finished. Clamped to the
	# type's build time, so a lower tuned time never leaves a longer wait, and a hall (0 s) loads finished.
	# A repair, never a refusal: a written save always loads.
	if raw.has("build_remaining"):
		var remaining: Variant = raw["build_remaining"]
		if (remaining is float or remaining is int) and is_finite(float(remaining)) and float(remaining) > 0.0:
			var left: float = minf(float(remaining), TownRules.build_seconds(StringName(raw_type as String), preload("res://balance.tres")))
			if left > 0.0:
				building["build_remaining"] = left
		else:
			push_warning("%s has a bad build_remaining %s; it loads finished." % [String(id).capitalize(), str(remaining)])
	return building


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
			elif _is_building(town_building(hero.home)):
				push_warning("%s is still being built; %s's home was cleared." % [house_name, hero.hero_name])
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
			if _is_building(town_building(hero.station)):
				push_warning("The %s is still being built; %s's job was cleared." % [place_name, hero.hero_name])
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
		var supplies_error: String = BattleSimulation.supplies_shape_error(saved_supplies)
		if not supplies_error.is_empty():
			return "Profile supplies: %s" % supplies_error
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
		# Additive (ig-wgj.10): absent on an older cache.
		if cache_data.has("lifetime_seconds") and not _is_nonnegative_number(cache_data.get("lifetime_seconds")):
			return "Lost-cache lifetime_seconds must be finite and non-negative."
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
			if str(order.get("backend")) != "battle_v1" or not str(order.get("phase")) in ["fighting", "rescuing", "returning", "checking"]:
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
			# Additive (ig-wgj.10): absent on an older incident.
			if incident.has("lifetime_seconds") and not _is_nonnegative_number(incident.get("lifetime_seconds")):
				return "Stranded incident lifetime_seconds must be finite and non-negative."
			if not str(incident.get("zone_id")) in KNOWN_ZONE_IDS:
				return "A stranded incident references an unknown zone."
			# Additive (ig-m6o.1): absent on legacy incidents.
			if incident.has("battle_orders"):
				if not incident.get("battle_orders") is Dictionary:
					return "Stranded incident battle_orders must be a Dictionary."
				for link_hero: Variant in incident.get("battle_orders") as Dictionary:
					var link: Variant = (incident.get("battle_orders") as Dictionary)[link_hero]
					if not link_hero is String or not link is String or (link as String).is_empty():
						return "Stranded incident battle_orders must map hero IDs to order IDs."
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
	var escrow_error: String = BattleSimulation.supplies_shape_error(escrow)
	if not escrow_error.is_empty():
		return "Battle escrow: %s" % escrow_error
	var battle: Dictionary = order.get("battle") as Dictionary
	if str(battle.get("order_id", "")) != order_id or str(battle.get("zone_id", "")) != zone_id:
		return "Battle order and checkpoint identities do not match."
	if (battle.get("policies") as Dictionary) != (order.get("policies") as Dictionary):
		return "Battle order and checkpoint policies do not match."
	var remaining_supplies: Dictionary = battle.get("supplies_remaining") as Dictionary
	for kind: String in BattleState.SUPPLY_KINDS:
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
	if (phase in ["fighting", "rescuing"] and status != "active") or (phase in ["returning", "checking"] and status == "active") or (phase == "checking" and kind != "normal"):
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
