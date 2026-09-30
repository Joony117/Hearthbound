extends SceneTree

## ig-7sn.2: the performance baseline, one measure per run, windowed at 1920x1080 with vsync off, on
## a copy of the save tests/perf/seed_perf.gd made. It refuses a save without the seed's marker, so it
## never runs on the owner's, nor without perf_throwaway.txt in its user:// (see seed_perf.gd). Copy
## the seeded APPDATA first: a measure changes its save.
##   APPDATA="$(cygpath -w <copy>)" ./tools/godot/Godot_v4.7.1-stable_win64_console.exe --windowed -s res://tests/perf/perf_baseline.gd -- <measure> <commit>
## Measures (the ig-7sn.2 list): pulse1, pulse5, hub, battle_citadel, battle_frontier, roster, town, load;
## preview (ig-7sn.14).
## Since ig-7sn.6: settle1, settle5 (the pulse that settles a leg, split). Since ig-7sn.16 they time
## _pulse on the game's path, each handler inside it and the game work on a twin, in three cases; load
## names the jobs in each slow frame and splits the catch-up round's landing the same way.
## Since ig-7sn.15: pulse_split (the pulse's "other", split; each battle's decode, advance and encode by zone).
## Since ig-vl1.5: battle_frontier_nowall is battle_frontier with every Mage's Rime Wall set to Off (the
## same fight, no walls; ACC 7's pair). Every battle measure prints the force's Mages, the most walls up,
## and the frame that advances the battle (_owe_battles'; the pulse's own frame advances none).
## Since ig-7sn.18: the watched run finds the advance frame by pulse_battle_advances, reports the pulse's and
## the advance's whole frames and the frames that run neither (the floor), and splits an advance into ticks,
## to_dict, snapshot copy and render.
## Since ig-7sn.19: it splits the render into the set_actor loop and events_between (each done again on the
## same snapshot) and the rest (the view's two copies, gone since, were a line of their own in the before), and
## splits the floor frames by what ran in them (the view's own poll re-render, an effect spawn, neither), and
## the idle ones into process step, draw and rest.
## Since ig-7sn.9: roster times the action with no building open and with the Forge open and a hero
## selected, and splits _refresh_roster and _refresh_director_ui.
## Since ig-7sn.10: roster and pulse5 print SPLIT lines (each battle's bytes, actors by faction and life,
## field objects and dead-enemy share; the three text forms' stringify, parse and bytes; _load_refusal by
## battle), and pulse5 prints SAVEFRAME: the frame the periodic save ran on, and that whole frame's time.
## Since ig-7sn.21: the SETTLE and COMMIT lines print the hub's dream_reads and dream_resumes since the last
## pulse, and the header line the display server's name. settle1 also runs --headless (CPU only: no draw, so
## a whole-frame row is not the windowed one; tests/perf/run_measure.sh MODE=headless).
## Since ig-7sn.20: battle_frontier and battle_frontier_nowall are also read headless (the advance row, the advance
## split and the render's CPU side mean something there; the whole-frame, floor and draw rows do not), and
## frontier_march runs end with a "wall split": the walls' work in an advance, replayed on a twin (_wall_replay).
## Since ig-m6o.2.2.4: encounter (the pulse a neighbours' chat lands on, the Sanctum open and its hero's detail drawn,
## the Ledger at its cap; tests/perf/seed_perf.gd puts chats in the Ledger). Read it headless (MODE=headless).
## Since ig-m6o.2.2.5: meal (the pulse a meal time lands on: every table of the seeded town sits and one record is written
## per table, the hub plays them; the Ledger at its cap, meals in it beside the chats). Read it headless too.
## Frames: 5 s of warm-up, then 30 s recorded: p50, p99, the worst frame, and frames over 33 ms.
## Timings are in ms. Nothing here changes game code: phases are timed by doing each phase's work
## again on copies of the same battles.

const ZONES: Array[String] = ["verdant_outskirts", "ashfall_reaches", "sundered_vault", "fallen_citadel", "frontier_march"]
const WARM_SECONDS: float = 5.0
const RECORD_SECONDS: float = 30.0
const PULSE: float = 0.25
const SAMPLES: int = 40

var session: Node
var saves: Node


func _initialize() -> void:
	# Never the owner's profile. Guessing it by path spelling misses aliases and links, so a throwaway
	# opts in instead: perf_throwaway.txt in user:// itself, the folder every save here goes to.
	if not FileAccess.file_exists("user://perf_throwaway.txt"):
		_refuse("No perf_throwaway.txt in %s; refusing. Run only on a throwaway APPDATA that has it." % ProjectSettings.globalize_path("user://"))
		return
	# Checked here, before the autoloads join the tree: GameSession._ready loads the save (and an
	# offline catch-up saves it), so a check any later would already have touched this APPDATA.
	if not FileAccess.file_exists("user://perf_seed.txt"):
		_refuse("No perf seed marker in %s; refusing. Seed a throwaway APPDATA first." % ProjectSettings.globalize_path("user://"))
		return
	create_timer(900.0).timeout.connect(quit.bind(2))
	_run.call_deferred()


## Frees the autoloads before they enter the tree, so none of them loads or saves this APPDATA.
func _refuse(reason: String) -> void:
	var session_ready: bool = root.get_node("GameSession").is_node_ready()
	for child: Node in root.get_children():
		root.remove_child(child)
		child.free()
	push_error("%s (GameSession ready: %s)" % [reason, session_ready])
	quit(1)


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var measure: String = args[0] if args.size() > 0 else ""
	session = root.get_node("GameSession")
	saves = root.get_node("SaveService")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	print("MEASURE %s at commit %s" % [measure, args[1] if args.size() > 1 else "?"])
	print("APPDATA %s | user:// %s" % [OS.get_environment("APPDATA"), ProjectSettings.globalize_path("user://")])
	print("CPU %s | GPU %s | display %s | window %s | vsync %d | max_fps %d" % [OS.get_processor_name(), RenderingServer.get_video_adapter_name(), DisplayServer.get_name(), DisplayServer.window_get_size(), DisplayServer.window_get_vsync_mode(), Engine.max_fps])
	print("SAVE %d heroes, %d records, %d buildings, %d orders" % [session.roster.size(), session.ledger.size(), session.town_buildings.size(), session.expedition_orders.size()])
	match measure:
		"pulse1":
			await _measure_pulse(1)
		"pulse5":
			await _measure_pulse(5)
		"pulse_split":
			await _measure_pulse_split()
		"settle1":
			await _measure_settle(1)
		"settle5":
			await _measure_settle(5)
		"hub":
			await _measure_hub()
		"battle_citadel":
			await _measure_battle("fallen_citadel")
		"battle_frontier":
			await _measure_battle("frontier_march")
		"battle_frontier_nowall":
			_rime_wall_off()
			await _measure_battle("frontier_march")
		"roster":
			await _measure_roster()
		"actions":
			await _measure_actions()
		"dreams":
			diagnose = true
			await _measure_actions()
		"encounter":
			await _measure_encounter()
		"meal":
			await _measure_meal()
		"town":
			await _measure_town()
		"load":
			await _measure_load()
		"preview":
			await _measure_preview()
		_:
			push_error("Unknown measure '%s'." % measure)
			quit(1)
			return
	print("DONE")
	quit(0)


## ---- 1. The 0.25 s pulse with the hub shown: one battle, or all five dispatched together (a
## measure each, so both start fresh). The phases come first, while every battle is still active
## (verdant's run ends first, at about 12 s); the frames group each pulse by its active battles.

func _measure_pulse(count: int) -> void:
	await _open_hub()
	for zone_id: String in ZONES.slice(0, count):
		_dispatch(zone_id, _cap(zone_id))
	_print_orders()
	_pulse_phases("%d battle(s)" % count)
	_print_orders()
	await _pulse_frames("pulse, %d battle(s), hub shown" % count)
	# ig-7sn.10 (a)-(c) again, on battles 40 s in: the dead enemies of the cleared waves are in them now.
	if count == 5:
		_print_orders()
		_save_split("pulse, 5 battle(s), after the frames", session.to_dict())


## Frames with GameSession's own _process driving the pulse, called from here so each pulse is timed.
func _pulse_frames(label: String) -> void:
	session.set_process(false)
	# Keyed by the battles active when the pulse began; -1 holds the pulses that settled a leg, -2 the
	# ones that ran the 15 s periodic save (ig-7sn.10).
	var pulses: Dictionary[int, Array] = {}
	# ig-7sn.10 (d): a frame whose _process ran a save (saved_at_unix moved) and no leg settled is the
	# periodic save's, pulse frame or not. Its whole frame is the next frame's delta.
	var saved: Dictionary = {"last": false, "lines": []}
	var frames: Array[float] = await _frames(func(delta: float, recording: bool) -> void:
		if saved["last"]:
			(saved["lines"] as Array).append("%s, whole frame %.2f ms" % [(saved["lines"] as Array).pop_back(), delta * 1000.0])
			saved["last"] = false
		var reports: int = session.expedition_reports.size()
		var active: int = _active()
		var saved_at: float = session.saved_at_unix
		var battles: Array[Dictionary] = _battles()
		var started: int = Time.get_ticks_usec()
		session._process(delta)
		var process_ms: float = _since(started)
		if recording and session.saved_at_unix != saved_at and session.expedition_reports.size() == reports:
			var advanced: int = 0
			var now: Array[Dictionary] = _battles()
			for index: int in mini(battles.size(), now.size()):
				advanced += 0 if is_same(battles[index], now[index]) else 1
			(saved["lines"] as Array).append("SAVEFRAME %s: the periodic save's frame: pulse ran %s, battles advanced %d, %d active, _process %.2f ms" % [label, session._expedition_pulse_accumulator == 0.0, advanced, active, process_ms])
			saved["last"] = true
		if recording and session._expedition_pulse_accumulator == 0.0:
			# A pulse that settles a leg (a new report) commits: roster_changed, its handlers, a save.
			var key: int = -1 if session.expedition_reports.size() != reports else -2 if session.saved_at_unix != saved_at else active
			if not pulses.has(key):
				pulses[key] = []
			pulses[key].append(_since(started)))
	session.set_process(true)
	_report_frames(label, frames)
	for line: String in saved["lines"]:
		print(line)
	var keys: Array[int] = pulses.keys()
	keys.sort()
	for key: int in keys:
		var samples: Array[float] = []
		samples.assign(pulses[key])
		_report("%s: whole pulse (GameSession._process), %s" % [label, "that settled a leg" if key == -1 else "that ran the periodic save" if key == -2 else "%d active, no leg settled" % key], samples)


## SAMPLES pulses split into phases. Each phase's work is done again, on copies of the same battles,
## just before the real tick_expeditions; "rest" is the tick minus the phases (signals, town, keepers).
## Since ig-7sn.5 the tick's look ahead decodes and advances once and the pulse keeps that, so there is
## no separate preview phase (the ig-7sn.2 baseline had one: 44 ms at five battles).
func _pulse_phases(label: String) -> void:
	session.set_process(false)
	var phases: Dictionary[String, Array] = {"decode": [], "advance": [], "encode": [], "tick": [], "rest": [], "commit pulse": []}
	var fewest: int = _active()
	for _pulse: int in SAMPLES:
		fewest = mini(fewest, _active())
		var battles: Array[Dictionary] = []
		for order: Dictionary in session.expedition_orders:
			if order.get("battle") is Dictionary:
				battles.append(order["battle"] as Dictionary)
		var started: int = Time.get_ticks_usec()
		var states: Array[BattleState] = []
		for battle: Dictionary in battles:
			states.append(BattleState.from_dict(battle))
		var decode_ms: float = _since(started)
		started = Time.get_ticks_usec()
		for state: BattleState in states:
			if state.status == "active":
				BattleSimulation.advance(state, minf(PULSE, maxf(state.max_seconds - state.elapsed_seconds, 0.0)))
		var advance_ms: float = _since(started)
		started = Time.get_ticks_usec()
		for state: BattleState in states:
			state.to_dict()
		var encode_ms: float = _since(started)
		var reports: int = session.expedition_reports.size()
		started = Time.get_ticks_usec()
		session.tick_expeditions(PULSE)
		var tick_ms: float = _since(started)
		for pair: Array in [["decode", decode_ms], ["advance", advance_ms], ["encode", encode_ms], ["tick", tick_ms], ["rest", tick_ms - decode_ms - advance_ms - encode_ms]]:
			phases[pair[0]].append(pair[1])
		if session.expedition_reports.size() != reports:
			phases["commit pulse"].append(tick_ms)
	session.set_process(true)
	for phase: String in phases:
		var samples: Array[float] = []
		samples.assign(phases[phase])
		_report("pulse phases, %s, at least %d active: %s" % [label, fewest, phase], samples)


## ---- 1c. ig-7sn.15: all five dispatched, the hub shown, the pulse split for RECORD_SECONDS of pulses.
## Just before each real tick_expeditions, each part is timed on the side: each battle's decode, and an
## active one's advance and encode, by zone; the tick's scans (lost caches, incidents, starve_step,
## finishes_build); the battle_changed handlers (every battle order) and the expeditions_changed ones.
## Just after it, the idle _release_battle_jobs, _land_battle_checks and _send_battle_checks (nothing out,
## as on most pulses). "rest" is the tick less the side parts: _advance_clocks' town work, the signals
## and a second decode where the tick makes one. Decodes a pulse are GameSession's counters. A pulse
## that settles a leg is left out (ig-7sn.16 owns it).
func _measure_pulse_split() -> void:
	await _open_hub()
	for zone_id: String in ZONES:
		_dispatch(zone_id, _cap(zone_id))
	_print_orders()
	session.set_process(false)
	var parts: Dictionary[String, Array] = {}
	var balance: BalanceTable = preload("res://balance.tres")
	for _pulse: int in int(RECORD_SECONDS / PULSE):
		var side: Dictionary[String, float] = {}
		var active: int = 0
		for order: Dictionary in session.expedition_orders:
			if not order.get("battle") is Dictionary:
				continue
			var zone: String = str((order["battle"] as Dictionary).get("zone_id", "?"))
			var started: int = Time.get_ticks_usec()
			var state := BattleState.from_dict(order["battle"] as Dictionary)
			side["decode " + zone] = _since(started)
			if state.status != "active":
				continue
			active += 1
			started = Time.get_ticks_usec()
			BattleSimulation.advance(state, minf(PULSE, maxf(state.max_seconds - state.elapsed_seconds, 0.0)))
			side["advance " + zone] = _since(started)
			started = Time.get_ticks_usec()
			state.to_dict()
			side["encode " + zone] = _since(started)
		var started_scan: int = Time.get_ticks_usec()
		for cache: LostCache in session.lost_caches:
			session.cache_seconds_remaining(cache, session.recovery_clock_seconds + PULSE)
		side["scan lost caches"] = _since(started_scan)
		started_scan = Time.get_ticks_usec()
		for incident: Dictionary in session.stranded_incidents:
			session._incident_remaining_seconds(incident)
		side["scan incidents"] = _since(started_scan)
		started_scan = Time.get_ticks_usec()
		TownRules.starve_step(float(session.town_resources["food"]), session.town_starving_seconds, session.town_starve_acked, session._work_home(TownRules.FARM), session.food_eaters().size(), not session.starvation_candidates().is_empty(), PULSE, balance)
		side["scan starve_step"] = _since(started_scan)
		started_scan = Time.get_ticks_usec()
		session.town_buildings.any(func(building: Dictionary) -> bool: return session._is_building(building) and float(building["build_remaining"]) <= PULSE)
		side["scan finishes_build"] = _since(started_scan)
		started_scan = Time.get_ticks_usec()
		for order: Dictionary in session.expedition_orders:
			if str(order.get("backend", "")) == "battle_v1":
				session.battle_changed.emit(str(order.get("id", "")))
		side["battle_changed handlers"] = _since(started_scan)
		started_scan = Time.get_ticks_usec()
		session.expeditions_changed.emit()
		side["expeditions_changed handlers"] = _since(started_scan)
		var reports: int = session.expedition_reports.size()
		var decodes: Array[int] = [session.pulse_decodes_active, session.pulse_decodes_idle]
		var started_tick: int = Time.get_ticks_usec()
		session.tick_expeditions(PULSE)
		var tick_ms: float = _since(started_tick)
		var decoded: Array[int] = [session.pulse_decodes_active - decodes[0], session.pulse_decodes_idle - decodes[1]]
		started_scan = Time.get_ticks_usec()
		session._release_battle_jobs()
		session._land_battle_checks()
		session._send_battle_checks()
		side["idle release/land/send checks"] = _since(started_scan)
		if session.expedition_reports.size() != reports:
			continue
		var side_total: float = 0.0
		for part: String in side:
			if not parts.has(part):
				parts[part] = []
			parts[part].append(side[part])
			side_total += side[part]
		for pair: Array in [["tick (whole)", tick_ms], ["rest", tick_ms - side_total], ["decodes of active battles, %d active" % active, float(decoded[0])], ["decodes of battles not active", float(decoded[1])]]:
			if not parts.has(pair[0]):
				parts[pair[0]] = []
			parts[pair[0]].append(pair[1])
	session.set_process(true)
	var names: Array[String] = parts.keys()
	names.sort()
	for part: String in names:
		_report("pulse split, 5 dispatched: %s" % part, parts[part])
	_print_orders()


## ---- 1b. The pulse that settles a leg (ig-7sn.6), on the game's own path since ig-7sn.16: one battle
## or all five, 99-run orders, the hub shown. Two frames a pulse: the first advances every live battle by
## a pulse (untimed; the game spreads these over the frames between pulses), the second runs
## GameSession._pulse(PULSE) alone, timed, as _process does on a pulse frame; its whole frame runs to the
## next frame's start. Every roster_changed, expeditions_changed and battle_changed handler runs in a
## timing wrapper (_wrap_handlers), so each handler's time is its own, inside the real pulse. Before a
## pulse that settles, its game work is split on the side on a twin (_settle_split). A pulse that lands a
## repeat check commits too (create_run, a save, every roster_changed handler), so it is reported beside
## the settles. SETTLES settles in each case: no building open; the Forge open with a hero selected;
## walking the town as a bonded hero (hub.gd _refresh_partner). The first two walk as no one. Each case
## starts at the town mood the measure began with: the seed's homeless heroes wear it down, and a town
## in revolt sends no order (a case runs 700 s or more of live time).
const SETTLES: int = 5
const SETTLE_CASES: Array[String] = ["no building open", "Forge open, one hero selected", "walking as a bonded hero"]


func _measure_settle(count: int) -> void:
	var hub: Node = await _open_hub()
	for zone_id: String in ZONES.slice(0, count):
		_dispatch(zone_id, _cap(zone_id))
	session.set_process(false)
	var spent: Dictionary = {}
	var mood: float = session.town_mood
	for case: String in SETTLE_CASES:
		session.town_mood = mood
		if await _settle_case(hub, case):
			_wrap_handlers(spent)
			await _settle_pulses("settle%d, %s" % [count, case], count, spent)
			_unwrap_handlers()
	_signs_split(hub, "settle%d" % count)
	session.set_process(true)


## The hub's look at a changed ledger, split (what the first roster_changed handler to ask pays after a
## settle): the index's size, a full look (_say_new_bonds and _living_candidates over every hero: every
## look before ig-7sn.16, now a load, a rebuilt index or a roster change), a quiet look (a record that
## touched no tally), the partner signs' rebuild, and _refresh_walkers with every memo warm. The ledger
## key is set stale by hand each rep.
func _signs_split(hub: Node, label: String) -> void:
	var pairs: Dictionary = session.bond_index()
	var tallies: int = 0
	var over: int = 0
	for hero_id: String in pairs:
		for tally: Dictionary in (pairs[hero_id] as Dictionary).values():
			tallies += 1
			over += 1 if tally["points"] >= preload("res://balance.tres").bond_threshold else 0
	print("SIGNS %s: %d heroes in the index, %d tallies, %d at or over the threshold" % [label, pairs.size(), tallies, over])
	var full: Callable = func() -> void:
		hub._bonds_seq = -1
		hub._bonds_pairs = null
		hub._bond_index()
	_report("%s: SIGNS a full look (_say_new_bonds, _living_candidates)" % label, _time(full, 5))
	var quiet: Callable = func() -> void:
		hub._bonds_seq = -1
		hub._bond_index()
	_report("%s: SIGNS a quiet look (no tally touched)" % label, _time(quiet, 5))
	_report("%s: SIGNS _living_candidates alone" % label, _time(hub._living_candidates.bind(pairs, hub._roster_names()), 5))
	var rebuild: Callable = func() -> void:
		hub._signs = {}
		hub._partner_signs(hub._roster_names())
	_report("%s: SIGNS the partner signs' rebuild" % label, _time(rebuild, 5))
	_report("%s: SIGNS _refresh_walkers, memos warm" % label, _time(hub._refresh_walkers, 5))


## Sets one case up; false, saying why, when it can't be.
func _settle_case(hub: Node, case: String) -> bool:
	if not case.begins_with("walking") and not session.step_out():
		print("SETTLE CASE %s: not run, can't step out (%s)" % [case, session.last_action_error])
		return false
	hub._open(&"Forge" if case.begins_with("Forge") else &"Sanctum" if case.begins_with("Sanctum") else &"")
	if case.begins_with("Forge") or case.begins_with("Sanctum"):
		var roster_list: ItemList = hub.get_node("%RosterList") as ItemList
		var row: int = 0
		if case.begins_with("Sanctum"):
			# The first row with a bond (ig-bnq): the Sanctum's actions are on the selected hero.
			var bonded: Dictionary = hub._roster_names()
			for index: int in range(roster_list.item_count - 1, -1, -1):
				var member: Hero = roster_list.get_item_metadata(index) as Hero
				if member != null and not Bonds.bond_from(session.bond_index(), member.instance_id, bonded, preload("res://balance.tres")).is_empty():
					row = index
		roster_list.deselect_all()
		roster_list.select(row)
		roster_list.multi_selected.emit(row, true)
	elif case.begins_with("walking"):
		var living: Dictionary = hub._roster_names()
		var walker: Hero = null
		for hero: Hero in session.roster:
			if walker == null and not session.is_hero_busy(hero) and not Bonds.bond_from(session.bond_index(), hero.instance_id, living, preload("res://balance.tres")).is_empty():
				walker = hero
		if walker == null or not session.embody_hero(walker.instance_id):
			print("SETTLE CASE %s: not run, no free bonded hero to walk as (%s)" % [case, session.last_action_error])
			return false
	await _wait(5)
	var shown: Hero = hub._selected_hero()
	var body: Hero = session.hero_by_id(session.embodied_hero_id)
	var partner: Hero = session.hero_by_id(hub._partner_id)
	print("SETTLE CASE %s: the roster's selected hero %s; walking as %s, partner %s" % [case, shown.hero_name if shown != null else "none", body.hero_name if body != null else "no one", partner.hero_name if partner != null else "none"])
	return true


## Pulses until SETTLES pulses settle a leg (at most 4000 pulses). A zone whose order stopped is sent
## again first, so each keeps one. Prints each commit's pulse, then the case's TIME lines. death (ig-bnq):
## stage an expedition death (_strand_one) in each pulse that settles a leg.
func _settle_pulses(label: String, count: int, spent: Dictionary, death: bool = false) -> void:
	var samples: Dictionary = {}
	var settles: int = 0
	var pulses: int = 0
	var deaths: PackedStringArray = []
	while settles < SETTLES and pulses < 4000:
		pulses += 1
		for zone_id: String in ZONES.slice(0, count):
			if not session.expedition_orders.any(func(order: Dictionary) -> bool: return str(order.get("zone_id", "")) == zone_id):
				_dispatch(zone_id, _cap(zone_id))
		for order: Dictionary in session.expedition_orders:
			if session._battle_live(order):
				session._advance_battle(order, PULSE)
		var due: Dictionary = _due_order()
		var parts: Dictionary = {} if due.is_empty() else _settle_split(due)
		await process_frame
		var last_report: String = _last_report_id()
		var checking: int = _checking()
		var active: int = _active()
		var saved_at: float = session.saved_at_unix
		var decodes: Array[int] = [session.pulse_decodes_active, session.pulse_decodes_idle]
		var dreams: Array[int] = [_hub_counter("dream_reads"), _hub_counter("dream_resumes")]
		var roster_before: int = session.roster.size()
		var stranded: String = _strand_one() if death and not due.is_empty() else ""
		if not stranded.is_empty():
			deaths.append(stranded)
		var probe: Dictionary = _dream_probe_before()
		spent.clear()
		var started: int = Time.get_ticks_usec()
		session._pulse(PULSE)
		var pulse_ms: float = _since(started)
		var handlers: Dictionary = spent.duplicate()
		await process_frame
		var frame_ms: float = _since(started)
		var settled: int = _new_reports(last_report)
		var kind: String = "no commit"
		if settled > 0:
			kind = "settled a leg"
			settles += 1
		elif _checking() < checking:
			kind = "landed a repeat check"
		elif session.saved_at_unix != saved_at:
			kind = "another commit"
		_dream_probe("%s: %s (settle %d, pulse %d)" % [label, kind, settles, pulses], probe)
		var head: String = "%s: %s:" % [label, kind]
		_add(samples, head + " whole pulse (_pulse)", pulse_ms)
		_add(samples, head + " whole frame", frame_ms)
		if kind == "no commit":
			continue
		var keys: Array = handlers.keys()
		keys.sort_custom(func(a: String, b: String) -> bool: return float(handlers[a]) > float(handlers[b]))
		var handler_ms: float = 0.0
		var top: PackedStringArray = []
		for key: String in keys:
			handler_ms += float(handlers[key])
			_add(samples, "%s handler %s" % [head, key], float(handlers[key]))
			if float(handlers[key]) >= 0.5:
				top.append("%s %.1f" % [key, float(handlers[key])])
		_add(samples, head + " handlers, all", handler_ms)
		var zone: String = str(session.expedition_reports.back().get("zone_id", "?")) if settled > 0 else kind
		var line: String = "%s %s, %s (%d active, %d checking before; %d leg(s)): pulse %.1f ms, whole frame %.1f ms, decodes %d active/%d idle, dream_reads %d, dream_resumes %d; handlers %.1f ms (%s)" % ["SETTLE" if settled > 0 else "COMMIT", label, zone, active, checking, settled, pulse_ms, frame_ms, session.pulse_decodes_active - decodes[0], session.pulse_decodes_idle - decodes[1], _hub_counter("dream_reads") - dreams[0], _hub_counter("dream_resumes") - dreams[1], handler_ms, ", ".join(top)]
		if not stranded.is_empty():
			line += "; expedition death of %s (roster %d -> %d)" % [stranded, roster_before, session.roster.size()]
		if settled > 0 and not parts.is_empty():
			var rest: float = pulse_ms - handler_ms
			var side: PackedStringArray = []
			for part: String in parts:
				side.append("%s %.1f" % [part, float(parts[part])])
				_add(samples, "%s %s %s" % [head, "side (twin, no staged death)" if death else "side", part], float(parts[part]))
				if not part.begins_with("its decode alone") and not part.begins_with("of which"):
					rest -= float(parts[part])
			_add(samples, head + " rest (the pulse less its handlers and the side parts)", rest)
			line += "; side (%s): %s; rest %.1f ms" % ["twin, no staged death" if death else "twin", ", ".join(side), rest]
		elif settled > 0:
			line += "; no side split (not due by its route: a wipe)"
		print(line)
	var labels: Array = samples.keys()
	labels.sort()
	for key: String in labels:
		_report(key, samples[key])
	print("%s: %d pulses, %d that settled" % [label, pulses, settles])
	if death:
		print("%s: %d expedition death(s) staged (%s)" % [label, deaths.size(), ", ".join(deaths)])


## ig-bnq: the roster actions that write a Ledger record (rank up, summon, sacrifice) with the hub shown,
## in the two cases of ACTION_CASES; then a settle with an expedition death. Each action runs ACTION_REPS
## times a case. The commit's handlers run inside the call (the flush is synchronous), so the whole action
## holds them, and its own save; the save alone is timed beside it. The look's kind is read off the hub:
## a new _bond_candidates dictionary is a full look, the same one with the roster's size changed a
## membership look, else quiet. Currencies are topped up here, never the roster: a sacrifice goes through
## kill_hero.
const ACTION_REPS: int = 5
const ACTION_CASES: Array[String] = ["Sanctum open, one bonded hero selected", "walking as a bonded hero"]
const ACTIONS: Array[String] = ["rank up", "summon", "sacrifice"]


func _measure_actions() -> void:
	var hub: Node = await _open_hub()
	session.set_process(false)
	var spent: Dictionary = {}
	var mood: float = session.town_mood
	for case: String in ACTION_CASES:
		if await _settle_case(hub, case):
			_wrap_handlers(spent)
			for action: String in ACTIONS:
				await _action_reps(hub, "actions, %s, %s" % [case, action], action, spent)
			_unwrap_handlers()
	_dispatch(ZONES[0], _cap(ZONES[0]))
	session.town_mood = mood
	if await _settle_case(hub, ACTION_CASES[0]):
		_wrap_handlers(spent)
		await _settle_pulses("settle1 with an expedition death, %s" % ACTION_CASES[0], 1, spent, true)
		_unwrap_handlers()
	session.set_process(true)


func _action_reps(hub: Node, label: String, action: String, spent: Dictionary) -> void:
	var balance: BalanceTable = preload("res://balance.tres")
	var samples: Dictionary = {}
	var kinds: Dictionary = {"quiet": 0, "membership": 0, "full": 0}
	var over: int = 0
	var failed: int = 0
	for rep: int in ACTION_REPS:
		var target: Hero = session.hero_by_id(session.embodied_hero_id)
		if target == null:
			target = hub._selected_hero()
		var partners: Dictionary = _partner_ids(hub, balance)
		var hero: Hero = _action_hero(hub, action, target, partners, balance)
		if hero == null and action != "summon":
			print("ACTION %s: not run, no hero for it" % label)
			return
		var pulled: Hero = Summon.roll(session.building_levels[0]) if action == "summon" else null
		var who: String = hero.hero_name if hero != null else pulled.hero_name
		session.essence = 100000
		session.stones = 300
		var kept: Dictionary = hub._bond_candidates
		var members: int = hub._bonds_living.size()
		var probe: Dictionary = _dream_probe_before()
		spent.clear()
		var done: bool = false
		var started: int = Time.get_ticks_usec()
		match action:
			"rank up":
				done = session.rank_up_hero(hero, balance)
			"summon":
				done = session.summon_hero(pulled, balance)
			"sacrifice":
				done = session.sacrifice_hero(hero, target, balance)
		var whole_ms: float = _since(started)
		var handlers: Dictionary = spent.duplicate()
		await process_frame
		_dream_probe("%s: rep %d, %s" % [label, rep + 1, action], probe)
		if not done:
			# A refused action is no sample: left out of the stats and the look counts.
			failed += 1
			print("ACTION %s: rep %d, %s, NOT DONE (%s): left out of the stats" % [label, rep + 1, who, session.last_action_error])
			continue
		var kind: String = "quiet"
		if not is_same(hub._bond_candidates, kept):
			kind = "full"
		elif hub._bonds_living.size() != members:
			kind = "membership"
		kinds[kind] = int(kinds[kind]) + 1
		var keys: Array = handlers.keys()
		keys.sort_custom(func(a: String, b: String) -> bool: return float(handlers[a]) > float(handlers[b]))
		var handler_ms: float = 0.0
		var top: PackedStringArray = []
		for key: String in keys:
			handler_ms += float(handlers[key])
			_add(samples, "%s: handler %s" % [label, key], float(handlers[key]))
			if float(handlers[key]) >= 0.5:
				top.append("%s %.1f" % [key, float(handlers[key])])
		_add(samples, label + ": whole action", whole_ms)
		_add(samples, label + ": handlers, all", handler_ms)
		over += 1 if whole_ms > 33.0 else 0
		var partner_of: String = ""
		if hero != null and action == "sacrifice":
			partner_of = " (someone's partner)" if partners.has(hero.instance_id) else " (no one's partner: the fallback fodder)"
		elif hero != null and partners.has(hero.instance_id):
			partner_of = " (someone's partner)"
		print("ACTION %s: rep %d, %s%s, done %s: look: %s; whole action %.1f ms%s, handlers %.1f ms (%s)" % [label, rep + 1, who, partner_of, done, kind, whole_ms, " OVER 33" if whole_ms > 33.0 else "", handler_ms, ", ".join(top)])
	var keys_out: Array = samples.keys()
	keys_out.sort()
	for key: String in keys_out:
		_report(key, samples[key])
	_report(label + ": save alone (SaveService.save)", _time(saves.save, 5))
	print("ACTION SUMMARY %s: %d reps, %d not done (left out); %d over 33 ms; look: %d quiet, %d membership, %d full" % [label, ACTION_REPS, failed, over, kinds["quiet"], kinds["membership"], kinds["full"]])


## The hero an action acts on: the shown or walking hero (target) for a rank up, else the first free one
## under SS (the last rank-up has its own gate); for a sacrifice the first unprotected, unequipped hero
## that is someone's partner (the re-signing case), else any. null for none. A summon has none.
func _action_hero(hub: Node, action: String, target: Hero, partners: Dictionary, balance: BalanceTable) -> Hero:
	var fallback: Hero = null
	var shown: Hero = hub._selected_hero()
	var candidates: Array[Hero] = []
	if action == "rank up" and target != null:
		candidates.append(target)
	candidates.append_array(session.roster)
	for hero: Hero in candidates:
		if action == "rank up" and not session.is_hero_busy(hero) and hero.rank < balance.rank_names.size() - 2:
			return hero
		if action == "sacrifice" and hero != target and hero != shown and hero.equipped.is_empty() and not session.is_hero_protected(hero):
			if partners.has(hero.instance_id):
				return hero
			fallback = fallback if fallback != null else hero
	return fallback


## Every hero id that is some living hero's partner (Bonds.bond_from), as keys.
func _partner_ids(hub: Node, balance: BalanceTable) -> Dictionary:
	var living: Dictionary = hub._roster_names()
	var partners: Dictionary = {}
	for id: String in living:
		var partner: String = str(Bonds.bond_from(session.bond_index(), id, living, balance).get("partner", ""))
		if not partner.is_empty():
			partners[partner] = true
	return partners


## ig-m6o.2.2.4: the frame a chat lands on. The Sanctum open with a hero selected (its detail panel drawn) and the
## Ledger at its cap. Each rep makes one chat that names that hero (every other pair on cooldown) and times
## GameSession._roll_encounters(PULSE, a copy of the table with the chance at 1, the minute clock a hair short), alone,
## with the hub's social handler inside it (the signal is said at once outside a commit); its whole frame runs to
## the next frame's start. The game's own pulse rolls at the shipped 0.2 and takes no table from outside, so the pulse
## a chat lands on is derived: a pulse that rolls nothing (GameSession._pulse with the minute clock at 0, timed
## beside it) plus that roll. Also timed: the pair scan alone and the hub's social handler done again on the same
## record (a repeat look is quiet). The chat is written and, at the cap, evicted at once (tier 0), so a rep is also
## the eviction's cost. A rep counts only when the named hero is the one selected and exactly one encounter was written
## (one seq spent and the drawn pair's cooldown set); any other rep is VOID, left out of the stats, and an error.
const ENCOUNTER_REPS: int = 5


func _measure_encounter() -> void:
	var hub: Node = await _open_hub()
	session.set_process(false)
	if not await _settle_case(hub, ACTION_CASES[0]):
		return
	var balance: BalanceTable = (preload("res://balance.tres") as BalanceTable).duplicate()
	balance.encounter_chance_per_minute = 1.0
	var roster_list: ItemList = hub.get_node("%RosterList") as ItemList
	var samples: Dictionary = {}
	var void_reps: int = 0
	for rep: int in ENCOUNTER_REPS:
		var in_town: Array[Hero] = []
		for hero: Hero in session.roster:
			if not session.is_hero_busy(hero):
				in_town.append(hero)
		var pairs: Array[Dictionary] = TownRules.meeting_pairs(in_town, session.town_buildings, balance)
		if pairs.is_empty():
			print("ENCOUNTER: not run, no pair could meet")
			return
		var pair: Dictionary = pairs[rep % pairs.size()]
		session._encounter_cooldowns.clear()
		for other: Dictionary in pairs:
			if other["key"] != pair["key"]:
				session._encounter_cooldowns[other["key"]] = 3600.0
		for row: int in roster_list.item_count:
			var member: Hero = roster_list.get_item_metadata(row) as Hero
			if member != null and member.instance_id == pair["a"]:
				roster_list.deselect_all()
				roster_list.select(row)
				roster_list.multi_selected.emit(row, true)
		await _wait(5)
		var shown: Hero = hub._selected_hero()
		session._encounter_clock = 0.0
		var started: int = Time.get_ticks_usec()
		session._pulse(PULSE)
		var quiet_ms: float = _since(started)
		await process_frame
		var seq: int = session.ledger_next_seq
		var reads: int = _hub_counter("dream_reads")
		session._encounter_clock = 60.0 - PULSE / 2.0
		started = Time.get_ticks_usec()
		session._roll_encounters(PULSE, balance)
		var roll_ms: float = _since(started)
		await process_frame
		var frame_ms: float = _since(started)
		var wrote: int = session.ledger_next_seq - seq
		var chose_them: bool = float(session._encounter_cooldowns.get(pair["key"], 0.0)) == 3600.0
		var selected_named: bool = shown != null and shown.instance_id == pair["a"]
		if wrote != 1 or not chose_them or not selected_named:
			void_reps += 1
			print("ENCOUNTER rep %d: VOID, left out of the stats (%s selected, named hero selected %s, %d record(s) written, drawn pair is the named one %s)" % [rep + 1, shown.hero_name if shown != null else "no one", selected_named, wrote, chose_them])
			continue
		var record: Dictionary = {"heroes": [pair["a"], pair["b"]], "place": pair["place"], "why": pair["why"]}
		var records: Array[Dictionary] = [record]
		var handler_ms: float = _time(hub._on_social_recorded.bind(records), 1)[0]
		var scan_ms: float = _time(TownRules.meeting_pairs.bind(in_town, session.town_buildings, balance), 1)[0]
		_add(samples, "ENCOUNTER: a pulse that rolls nothing (_pulse)", quiet_ms)
		_add(samples, "ENCOUNTER: the roll a chat lands on (_roll_encounters, the hub's handler inside)", roll_ms)
		_add(samples, "ENCOUNTER: derived, that pulse plus the roll", quiet_ms + roll_ms)
		_add(samples, "ENCOUNTER: whole frame of the roll", frame_ms)
		_add(samples, "ENCOUNTER: the hub's social handler, again", handler_ms)
		_add(samples, "ENCOUNTER: the pair scan alone (TownRules.meeting_pairs)", scan_ms)
		print("ENCOUNTER rep %d: %d pairs, %s selected and named, 1 record written, dream_reads %d: roll %.1f ms, a pulse that rolls nothing %.1f (derived pulse %.1f), whole frame of the roll %.1f ms, handler again %.1f ms, scan %.1f ms" % [rep + 1, pairs.size(), shown.hero_name, _hub_counter("dream_reads") - reads, roll_ms, quiet_ms, quiet_ms + roll_ms, frame_ms, handler_ms, scan_ms])
	var labels: Array = samples.keys()
	labels.sort()
	for key: String in labels:
		_report(key, samples[key])
	if void_reps > 0:
		push_error("ENCOUNTER: %d of %d reps were void; the stats are of the rest" % [void_reps, ENCOUNTER_REPS])
	session.set_process(true)


## ig-m6o.2.2.5: the frame a meal time lands on. The Sanctum open with a diner of the first table selected (its detail
## panel drawn) and the Ledger at its cap. Each rep sets the meal clock a hair short of the interval and times
## GameSession._roll_meals(PULSE, the shipped table) alone, with the hub's social handler inside it (the signal is said
## at once outside a commit), then the whole frame to the next frame's start: every table of the town sits down (one
## "meal" record each) and the first diner of each shown table speaks. The game's own pulse rolls nothing until the
## meal time, so the pulse a meal time lands on is derived: a pulse that rolls nothing (GameSession._pulse with the
## clocks at 0, timed beside it) plus that roll. Also timed: the table scan alone and the hub's social handler done
## again on the same records (they are seated, so a repeat look is quiet). A rep counts only when one record was
## written per table the scan found (and at least one); any other rep is VOID, left out of the stats, and an error.
const MEAL_REPS: int = 5


func _measure_meal() -> void:
	var hub: Node = await _open_hub()
	session.set_process(false)
	if not await _settle_case(hub, ACTION_CASES[0]):
		return
	var balance: BalanceTable = preload("res://balance.tres")
	var interval: float = balance.meal_interval_minutes * 60.0
	var roster_list: ItemList = hub.get_node("%RosterList") as ItemList
	var samples: Dictionary = {}
	var void_reps: int = 0
	for rep: int in MEAL_REPS:
		var eaters: Array[Array] = []
		for hero: Hero in session.starvation_candidates():
			eaters.append([hero.instance_id, String(hero.home)])
		var scan_started: int = Time.get_ticks_usec()
		var tables: Array[Dictionary] = TownRules.meal_tables(eaters, session.town_buildings, balance.meal_house_hexes, balance.meal_table_size)
		var scan_ms: float = _since(scan_started)
		if tables.is_empty():
			print("MEAL: not run, no table could sit")
			return
		var named: String = str(tables[0]["diners"][0])
		for row: int in roster_list.item_count:
			var member: Hero = roster_list.get_item_metadata(row) as Hero
			if member != null and member.instance_id == named:
				roster_list.deselect_all()
				roster_list.select(row)
				roster_list.multi_selected.emit(row, true)
		await _wait(5)
		var shown: Hero = hub._selected_hero()
		session._encounter_clock = 0.0
		session._meal_clock = 0.0
		var started: int = Time.get_ticks_usec()
		session._pulse(PULSE)
		var quiet_ms: float = _since(started)
		await process_frame
		var seq: int = session.ledger_next_seq
		session._meal_clock = interval - PULSE / 2.0
		started = Time.get_ticks_usec()
		session._roll_meals(PULSE, balance)
		var roll_ms: float = _since(started)
		await process_frame
		var frame_ms: float = _since(started)
		var wrote: int = session.ledger_next_seq - seq
		if wrote != tables.size():
			void_reps += 1
			print("MEAL rep %d: VOID, left out of the stats (%d record(s) written, %d tables found)" % [rep + 1, wrote, tables.size()])
			continue
		var records: Array[Dictionary] = []
		records.assign(session.ledger.slice(session.ledger.size() - wrote))
		var handler_ms: float = _time(hub._on_social_recorded.bind(records), 1)[0]
		_add(samples, "MEAL: a pulse that rolls nothing (_pulse)", quiet_ms)
		_add(samples, "MEAL: the roll a meal time lands on (_roll_meals, the hub's handler inside)", roll_ms)
		_add(samples, "MEAL: derived, that pulse plus the roll", quiet_ms + roll_ms)
		_add(samples, "MEAL: whole frame of the roll", frame_ms)
		_add(samples, "MEAL: the hub's social handler, again", handler_ms)
		_add(samples, "MEAL: the table scan alone (TownRules.meal_tables)", scan_ms)
		print("MEAL rep %d: %d eaters, %d tables, %s selected: roll %.1f ms, a pulse that rolls nothing %.1f (derived pulse %.1f), whole frame of the roll %.1f ms, handler again %.1f ms, scan %.1f ms" % [rep + 1, eaters.size(), tables.size(), shown.hero_name if shown != null else "no one", roll_ms, quiet_ms, quiet_ms + roll_ms, frame_ms, handler_ms, scan_ms])
	var labels: Array = samples.keys()
	labels.sort()
	for key: String in labels:
		_report(key, samples[key])
	if void_reps > 0:
		push_error("MEAL: %d of %d reps were void; the stats are of the rest" % [void_reps, MEAL_REPS])
	session.set_process(true)


## ig-bnq: one stranded incident for a free bonded hero, not the shown one, that expires on the next pulse:
## the expedition death of a settle. Only the setup is staged here; the removal is the pulse's own
## (_expire_stranded_incidents_in_memory -> kill_hero). Returns the hero's name, "" for none.
func _strand_one() -> String:
	var hub: Node = current_scene
	var shown: Hero = hub._selected_hero()
	var living: Dictionary = hub._roster_names()
	for hero: Hero in session.roster:
		if hero != shown and not session.is_hero_busy(hero) and not session.is_embodied(hero) and not Bonds.bond_from(session.bond_index(), hero.instance_id, living, preload("res://balance.tres")).is_empty():
			session.stranded_incidents.append({"id": "perf_%s" % hero.instance_id, "source_order_id": "perf", "zone_id": ZONES[0], "hero_ids": [hero.instance_id], "paused": false, "created_recovery_seconds": session.rescue_clock_seconds - 1000000.0, "active_rescue_order_id": "", "expiry_pending": false})
			return hero.hero_name
	return ""


## ig-bnq diagnostic (the "dreams" measure: the actions measure with diagnose on; a diagnostic run, not a
## window, since it copies the ledger around each timed call): when a call made the hub read a hero's dream
## in full, one DREAM line says which mark moved (the rule of Hub._dream) and which evicted records moved it.
var diagnose: bool = false


func _dream_probe_before() -> Dictionary:
	if not diagnose:
		return {}
	var marks: Dictionary = session.bond_changes()
	return {"memos": (current_scene._dreams as Dictionary).duplicate(), "out_all": int(marks["out_all"]), "out_named": (marks["out_named"] as Dictionary).duplicate(), "ledger": session.ledger.duplicate()}


func _dream_probe(what: String, before: Dictionary) -> void:
	if before.is_empty():
		return
	var marks: Dictionary = session.bond_changes()
	var kept: Dictionary = {}
	for record: Dictionary in session.ledger:
		kept[int(record.get("seq", 0))] = true
	var gone: Array[Dictionary] = []
	var kinds: Dictionary = {}
	for record: Dictionary in before["ledger"]:
		if not kept.has(int(record.get("seq", 0))):
			gone.append(record)
			kinds[str(record.get("kind", "?"))] = int(kinds.get(str(record.get("kind", "?")), 0)) + 1
	var memos: Dictionary = before["memos"]
	var roster: Dictionary = current_scene._roster_names()
	for id: String in current_scene._dreams:
		if is_same(current_scene._dreams[id], memos.get(id)):
			continue
		var read_at: int = int((memos.get(id, {}) as Dictionary).get("outs", -1))
		var causes: PackedStringArray = []
		var all_kinds: PackedStringArray = []
		var naming: PackedStringArray = []
		if read_at < 0:
			causes.append("no memo yet")
		if read_at >= 0 and int(marks["out_all"]) > read_at:
			causes.append("out_all %d (was %d, read at %d)" % [marks["out_all"], before["out_all"], read_at])
		if read_at >= 0 and int((marks["out_named"] as Dictionary).get(id, 0)) > read_at:
			causes.append("out_named[hero] %d (was %d, read at %d)" % [(marks["out_named"] as Dictionary).get(id, 0), (before["out_named"] as Dictionary).get(id, 0), read_at])
		for record: Dictionary in gone:
			if str(record.get("kind", "")) != "battle" or record.has("name"):
				all_kinds.append("#%d %s%s" % [int(record.get("seq", 0)), record.get("kind", "?"), " with a name" if record.has("name") else ""])
				continue
			for key: String in ["team", "rescued", "rescuers"]:
				if Ledger._array(record, key).has(id):
					naming.append("#%d %s battle (%s)" % [int(record.get("seq", 0)), "routine" if Ledger.is_routine(record) else "non-routine", key])
					break
		print("DREAM %s: %s (%s) read in full; cause: %s; evicted %d (%s); evicted that mark out_all: %s; evicted that name the hero: %s" % [what, roster.get(id, "?"), id, "; ".join(causes) if not causes.is_empty() else "none of the marks", gone.size(), ", ".join(PackedStringArray(kinds.keys().map(func(kind: String) -> String: return "%s %d" % [kind, kinds[kind]]))), ", ".join(all_kinds) if not all_kinds.is_empty() else "none", ", ".join(naming) if not naming.is_empty() else "none"])


## One of the hub's dream counters (dream_resumes is ig-7sn.21's: 0 before the hub has it).
func _hub_counter(counter: String) -> int:
	var value: Variant = current_scene.get(counter)
	return int(value) if value is int else 0


## The order the next pulse settles by its route (its fight over and its route home done, as _pulse
## reads it), or {}. A wipe, due at once with nobody to walk home, is not looked for: it settles unsplit.
func _due_order() -> Dictionary:
	for order: Dictionary in session.expedition_orders:
		if str(order.get("phase", "")) != "checking" and order.get("battle") is Dictionary and str((order["battle"] as Dictionary).get("status", "active")) != "active" and float(order.get("remaining_seconds", 0.0)) <= PULSE:
			return order
	return {}


## ig-7sn.16 (c): the settle's game work, split on the side on a twin: a GameSession built from this state
## (to_dict and the ledger, the bond index and each battle's decode warmed as the real session keeps
## them), which runs the pulse's commit step by step as _commit_profile_mutation does and is then freed.
## The real session keeps its objects and caches for the timed pulse. The twin's signals have no handlers
## (the wrappers time those inside the real pulse), and it saves nothing: the save part is
## SaveService.save on the real session a pulse early (the same state less the settle's record and
## report). Parts in ms, in the commit's order.
func _settle_split(due: Dictionary) -> Dictionary:
	var profile: Dictionary = session.to_dict()
	profile["version"] = saves.SAVE_VERSION
	profile["ledger"] = session.ledger
	var twin: Node = _twin(profile, session._bond_in_step())
	var parts: Dictionary = {}
	var started: int = Time.get_ticks_usec()
	BattleState.from_dict(due["battle"] as Dictionary)
	parts["its decode alone (fix 1; inside the due orders)"] = _since(started)
	_twin_commit_head(twin, parts)
	started = Time.get_ticks_usec()
	twin._advance_clocks_in_memory(PULSE)
	parts["clocks and town"] = _since(started)
	started = Time.get_ticks_usec()
	twin._resolve_due_orders_in_memory()
	parts["the due orders (decode, outcome, record, rewards, check, report)"] = _since(started)
	started = Time.get_ticks_usec()
	twin._expire_recovery_caches_in_memory()
	twin._expire_stranded_incidents_in_memory()
	parts["expiries"] = _since(started)
	_twin_commit_tail(twin, parts)
	return parts


## A GameSession built from profile, off the tree (no _ready: no load, no autosave connection), its
## decoded battles and, when warm is true, its bond index warmed.
func _twin(profile: Dictionary, warm: bool) -> Node:
	var twin: Node = (session.get_script() as GDScript).new()
	twin.from_dict(profile)
	if warm:
		twin.bond_index()
	for order: Dictionary in twin.expedition_orders:
		if order.get("battle") is Dictionary:
			twin._battle_state(order)
	return twin


## The commit's head on a twin, timed into parts (its snapshot and what a rollback keeps), then the
## mutation's depths, as _commit_profile_mutation sets them.
func _twin_commit_head(twin: Node, parts: Dictionary) -> void:
	var started: int = Time.get_ticks_usec()
	twin.to_dict()
	parts["commit snapshot (to_dict)"] = _since(started)
	started = Time.get_ticks_usec()
	twin._rollback_kept()
	parts["_rollback_kept"] = _since(started)
	twin._save_deferred_depth += 1
	twin._notification_deferred_depth += 1
	twin._ledger_hold_depth += 1


## The commit's tail on a twin, timed into parts: the save (the real session's), the ledger eviction,
## the checks sent after it; then the twin's jobs are cancelled and it is freed. The flush is left out:
## the real pulse's handlers are timed where they run.
func _twin_commit_tail(twin: Node, parts: Dictionary) -> void:
	twin._save_deferred_depth -= 1
	var started: int = Time.get_ticks_usec()
	saves.save()
	parts["save (the real session's, a pulse early)"] = _since(started)
	twin._ledger_hold_depth -= 1
	started = Time.get_ticks_usec()
	twin._evict_ledger()
	parts["_evict_ledger"] = _since(started)
	twin._notification_deferred_depth -= 1
	var builds: int = twin.bond_builds
	started = Time.get_ticks_usec()
	twin._send_battle_checks()
	parts["send the repeat checks (team snapshots, two jobs each)"] = _since(started)
	if twin.bond_builds > builds:
		# A cold index (after a load) is rebuilt inside the checks: _cover_orders reads it.
		started = Time.get_ticks_usec()
		Bonds.index_state(twin.ledger, preload("res://balance.tres"))
		parts["of which the bond index rebuild, timed again alone"] = _since(started)
	twin._cancel_battle_jobs()
	twin.free()


## ig-7sn.16 (b): each connection of the three refresh signals swapped for a wrapper that calls it and adds
## its time to spent ("<signal> <script>.<method>" -> ms), in the same order with the same flags, so a
## flush still runs each handler once, in its place. Wrapper -> the handler it wraps.
var _wrappers: Dictionary = {}


func _refresh_signals() -> Array[Signal]:
	return [session.roster_changed, session.expeditions_changed, session.battle_changed]


func _wrap_handlers(spent: Dictionary) -> void:
	for changed: Signal in _refresh_signals():
		var connections: Array = changed.get_connections()
		for connection: Dictionary in connections:
			changed.disconnect(connection["callable"])
		for connection: Dictionary in connections:
			var handler: Callable = connection["callable"]
			changed.connect(handler if _wrappers.has(handler) else _wrapper(changed, handler, spent), connection["flags"])


func _wrapper(changed: Signal, handler: Callable, spent: Dictionary) -> Callable:
	var target: Object = handler.get_object()
	var source: Script = target.get_script() as Script if target != null else null
	var key: String = "%s %s.%s" % [changed.get_name(), source.resource_path.get_file() if source != null else "?", handler.get_method()]
	var wrapper: Callable
	if changed.get_name() == "battle_changed":
		wrapper = func(order_id: String) -> void:
			var started: int = Time.get_ticks_usec()
			handler.call(order_id)
			spent[key] = float(spent.get(key, 0.0)) + _since(started)
	else:
		wrapper = func() -> void:
			var started: int = Time.get_ticks_usec()
			handler.call()
			spent[key] = float(spent.get(key, 0.0)) + _since(started)
	_wrappers[wrapper] = handler
	return wrapper


func _unwrap_handlers() -> void:
	for changed: Signal in _refresh_signals():
		var connections: Array = changed.get_connections()
		for connection: Dictionary in connections:
			changed.disconnect(connection["callable"])
		for connection: Dictionary in connections:
			changed.connect(_wrappers.get(connection["callable"], connection["callable"]) as Callable, connection["flags"])
	_wrappers.clear()


## ---- 2. The hub's battle_changed and expeditions_changed handlers as the order count grows.

func _measure_hub() -> void:
	var hub: Node = await _open_hub()
	session.set_process(false)
	var small: Array[String] = ["verdant_outskirts", "ashfall_reaches", "sundered_vault"]
	for count: int in [1, 3, 5, 10]:
		while session.expedition_orders.size() < count:
			if _dispatch(small[session.expedition_orders.size() % small.size()], 5).is_empty():
				return
		var battle_ms: Array[float] = []
		var pulse_ms: Array[float] = []
		var cards: int = 0
		for _rep: int in 20:
			var before: int = hub.order_card_updates
			var pulse_started: int = Time.get_ticks_usec()
			for order: Dictionary in session.expedition_orders.duplicate():
				var started: int = Time.get_ticks_usec()
				session.battle_changed.emit(str(order["id"]))
				battle_ms.append(_since(started))
			session.expeditions_changed.emit()
			pulse_ms.append(_since(pulse_started))
			cards = hub.order_card_updates - before
		_report("hub, %d orders: one battle_changed" % count, battle_ms)
		_report("hub, %d orders: a pulse's signals (%d battle_changed + expeditions_changed), %d card updates = snapshot copies" % [count, count, cards], pulse_ms)
		var changed_ms: Array[float] = []
		for _rep: int in 20:
			var started: int = Time.get_ticks_usec()
			session.expeditions_changed.emit()
			changed_ms.append(_since(started))
		_report("hub, %d orders: expeditions_changed alone" % count, changed_ms)
		if count == 5:
			_report_handlers("hub, 5 orders", session.expeditions_changed)
	session.set_process(true)


## ---- 3. The watched battle: the real worst case, zone at its hero cap.

func _measure_battle(zone_id: String) -> void:
	var order_id: String = _dispatch(zone_id, _cap(zone_id))
	if order_id.is_empty():
		return
	var view: Node = await _watch(order_id)
	var vfx: Node = _find_script(view, "battle_vfx.gd")[0]
	session.set_process(false)
	var pulses: Array[float] = []
	var advances: Array[float] = []
	var pulse_frames: Array[float] = []
	var advance_frames: Array[float] = []
	var floor_frames: Array[float] = []
	var live: Array[float] = []
	var spawn_frames: Array[float] = []
	var quiet_frames: Array[float] = []
	# ig-7sn.19 ACC 1: the floor split by what ran in it: the view's own 0.25 s poll re-rendering
	# (battle_view._process -> _refresh_live_snapshot), an effect spawning, or neither; for neither, the frame's
	# process step, its draw and the rest, by the engine's frame signals.
	var floor_poll: Array[float] = []
	var floor_spawn: Array[float] = []
	var floor_idle: Array[float] = []
	var idle_process: Array[float] = []
	var idle_draw: Array[float] = []
	var idle_other: Array[float] = []
	var floor_draw_cpu: Array[float] = []
	var floor_draw_gpu: Array[float] = []
	# ig-7sn.19: each advance frame as [whole, GameSession._process, process step, draw, effects spawned], and each
	# frame that ran the periodic save as [whole, process step, draw]: the top frames, by what ran in them.
	var advance_rows: Array[Array] = []
	var save_rows: Array[Array] = []
	# [this frame's start, its frame_pre_draw, its frame_post_draw (usec)]
	var marks: Array[float] = [0.0, 0.0, 0.0]
	# The snapshot the view held once this frame's landing (if any) was done.
	var seen: Array[Dictionary] = [{}]
	var on_pre_draw: Callable = func() -> void: marks[1] = Time.get_ticks_usec()
	var on_post_draw: Callable = func() -> void: marks[2] = Time.get_ticks_usec()
	RenderingServer.frame_pre_draw.connect(on_pre_draw)
	RenderingServer.frame_post_draw.connect(on_post_draw)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var mages: int = session.roster.filter(func(hero: Hero) -> bool: return hero.def_id == &"mage" and session.is_hero_busy(hero)).size()
	# [live effects at the last frame's start, the pulse ms inside that frame, most particle nodes, most walls,
	# what the last call ran: 1 the pulse, 2 an advance, 0 neither, the advance's GameSession._process ms,
	# 1 if the last call ran the periodic save]
	var last: Array[float] = [float(vfx.get_child_count()), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var per_frame: Callable = func(delta: float, recording: bool) -> void:
		# A frame's time less the pulse inside it (all its other work); an effect spawned in it if the
		# live count went up. Warm-up frames are left out, as in the frame report.
		var count: float = vfx.get_child_count()
		if recording:
			(spawn_frames if count > last[0] else quiet_frames).append(delta * 1000.0 - last[1])
			live.append(count)
			var split: bool = marks[0] > 0.0 and marks[1] >= marks[0] and marks[2] >= marks[1]
			if last[6] == 1.0 and split:
				save_rows.append([delta * 1000.0, (marks[1] - marks[0]) / 1000.0, (marks[2] - marks[1]) / 1000.0])
			# ig-7sn.18 ACC 1: delta is the whole frame that ran the last call's work.
			if last[4] == 1.0:
				pulse_frames.append(delta * 1000.0)
			elif last[4] == 2.0:
				advance_frames.append(delta * 1000.0)
				if split:
					advance_rows.append([delta * 1000.0, last[5], (marks[1] - marks[0]) / 1000.0, (marks[2] - marks[1]) / 1000.0, count - last[0]])
			else:
				floor_frames.append(delta * 1000.0)
				floor_draw_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
				floor_draw_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
				# The view holds a snapshot no landing handed it: it re-rendered on its own (its poll).
				if not is_same(view._snapshot, seen[0]):
					floor_poll.append(delta * 1000.0)
				elif count > last[0]:
					floor_spawn.append(delta * 1000.0)
				else:
					floor_idle.append(delta * 1000.0)
					if marks[0] > 0.0 and marks[1] >= marks[0] and marks[2] >= marks[1]:
						idle_process.append((marks[1] - marks[0]) / 1000.0)
						idle_draw.append((marks[2] - marks[1]) / 1000.0)
						idle_other.append((Time.get_ticks_usec() - marks[2]) / 1000.0)
		marks[0] = Time.get_ticks_usec()
		last[0] = count
		# A tree scan costs time itself, so particles are counted once every 60 frames only.
		if recording and live.size() % 60 == 0:
			last[2] = maxf(last[2], _find_class(vfx, "GPUParticles3D").size() + _find_class(vfx, "CPUParticles3D").size())
		var advanced: int = session.pulse_battle_advances
		last[6] = 1.0 if session._periodic_save_due else 0.0
		var started: int = Time.get_ticks_usec()
		session._process(delta)
		var spent: float = _since(started)
		last[1] = 0.0
		last[4] = 0.0
		if session._expedition_pulse_accumulator == 0.0:
			last[1] = spent
			last[4] = 1.0
			if recording:
				pulses.append(last[1])
			last[3] = maxf(last[3], _walls())
		elif session.pulse_battle_advances > advanced:
			# ig-7sn.18 ACC 1 (ig-vl1.5 ACC 7 before it): this frame advanced the battle.
			last[4] = 2.0
			last[5] = spent
			if recording:
				advances.append(spent)
		seen[0] = view._snapshot
	var ended: Callable = func() -> bool: return not is_instance_valid(vfx) or str(session.get_battle_snapshot(order_id).get("status", "")) != "active"
	var frames: Array[float] = await _frames(per_frame, ended)
	RenderingServer.frame_pre_draw.disconnect(on_pre_draw)
	RenderingServer.frame_post_draw.disconnect(on_post_draw)
	session.set_process(true)
	var label: String = "watched %s (%d heroes)" % [zone_id, _cap(zone_id)]
	_print_orders()
	print("%s: %d Mages in the force, most walls up at once %d" % [label, mages, int(last[3])])
	_report_frames("%s, until the battle ends" % label, frames)
	_report("%s: the pulse's own frame, GameSession._process (_pulse; no advance since ig-7sn.15)" % label, pulses)
	_report("%s: the pulse's own frame, whole" % label, pulse_frames)
	_report("%s: the frame that advances it (GameSession._process on _owe_battles' frame)" % label, advances)
	_report("%s: the frame that advances it, whole" % label, advance_frames)
	_report("%s: frames that run neither, whole (the floor: the view and the engine's draw)" % label, floor_frames)
	_report("%s: the floor, frames where the view's own 0.25 s poll re-rendered (battle_view._process), whole" % label, floor_poll)
	_report("%s: the floor, frames where an effect spawned (no poll), whole" % label, floor_spawn)
	_report("%s: the floor, frames with neither, whole" % label, floor_idle)
	_report("%s: the floor with neither: the process step (frame start to frame_pre_draw)" % label, idle_process)
	_report("%s: the floor with neither: the draw (frame_pre_draw to frame_post_draw)" % label, idle_draw)
	_report("%s: the floor with neither: the rest (to the next frame's start: physics, input, the loop)" % label, idle_other)
	_report("%s: the floor's draw, CPU (the viewport's measured render time)" % label, floor_draw_cpu)
	_report("%s: the floor's draw, GPU" % label, floor_draw_gpu)
	_report("%s: live effects per frame (cap 40), most particle nodes %d" % [label, int(last[2])], live)
	_report("%s: frames where the live effect count rose, less the pulse (all other work)" % label, spawn_frames)
	_report("%s: frames where it did not, less the pulse" % label, quiet_frames)
	advance_rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for row: Array in advance_rows.slice(0, 5):
		print("%s: a top advance frame: whole %.2f, GameSession._process %.2f, process step %.2f, draw %.2f, effects spawned %d" % [label, row[0], row[1], row[2], row[3], int(row[4])])
	for row: Array in save_rows:
		print("%s: a frame that ran the periodic save: whole %.2f, process step %.2f, draw %.2f" % [label, row[0], row[1], row[2]])
	# The split, outside the recorded frames, on a battle still running: a fresh one if this one ended.
	if not is_instance_valid(view) or session.get_battle_snapshot(order_id).get("status", "") != "active":
		order_id = _dispatch(zone_id, _cap(zone_id))
		if order_id.is_empty():
			print("%s: split not taken, too few free heroes for a second battle" % label)
			return
		view = await _watch(order_id)
	session.battle_changed.disconnect(view._on_battle_changed)
	session.set_process(false)
	# ig-7sn.18 ACC 1: an advance by a pulse, one part at a time, as _advance_battle (game_session.gd) does it:
	# the ticks and to_dict, then the view's battle_changed work, the snapshot copy and its render.
	var ticks: Array[float] = []
	var encode: Array[float] = []
	var copy: Array[float] = []
	var render: Array[float] = []
	# ig-7sn.19 ACC 1: the render's parts, each done again right after it on the same snapshot.
	var set_actors: Array[float] = []
	var events: Array[float] = []
	var rest: Array[float] = []
	var spawn_renders: Array[float] = []
	var still_renders: Array[float] = []
	# ig-7sn.20: the battle before its first advance and the ticks each advance ran, for the wall split's replay.
	var replay_start: Dictionary = {}
	var replay_ticks: Array[int] = []
	var replay_end: BattleState = null
	for _pulse: int in SAMPLES:
		var index: int = session._order_index(order_id)
		if index < 0 or not session._battle_live(session.expedition_orders[index]):
			break
		var order: Dictionary = session.expedition_orders[index]
		var state: BattleState = session._battle_state(order)
		if replay_start.is_empty():
			replay_start = state.to_dict().duplicate(true)
		var ticks_before: int = state.tick
		var started: int = Time.get_ticks_usec()
		BattleSimulation.advance(state, minf(PULSE, maxf(state.max_seconds - state.elapsed_seconds, 0.0)))
		ticks.append(_since(started))
		replay_ticks.append(state.tick - ticks_before)
		replay_end = state
		started = Time.get_ticks_usec()
		var battle: Dictionary = state.to_dict()
		encode.append(_since(started))
		order["battle"] = battle
		session._battle_states[order_id] = [battle, state]
		started = Time.get_ticks_usec()
		var snapshot: Dictionary = session.get_battle_snapshot(order_id)
		copy.append(_since(started))
		var previous_actors: Dictionary = view._previous_actors
		var views_before: int = view._unit_views.size()
		started = Time.get_ticks_usec()
		view._render_snapshot(snapshot)
		var whole: float = _since(started)
		render.append(whole)
		(spawn_renders if view._unit_views.size() > views_before else still_renders).append(whole)
		var actors: Array = view._snapshot.get("actors", []) as Array
		started = Time.get_ticks_usec()
		for actor: Dictionary in actors:
			var unit: Node = view._unit_views.get(str(actor.get("id", "")))
			if unit != null:
				unit.set_actor(actor, str(actor.get("id", "")) in view._selected_ids, PULSE)
		var set_ms: float = _since(started)
		started = Time.get_ticks_usec()
		var _events: Array[Dictionary] = BattleVfx.events_between(previous_actors, actors)
		var events_ms: float = _since(started)
		set_actors.append(set_ms)
		events.append(events_ms)
		rest.append(whole - set_ms - events_ms)
		await process_frame
	_report("%s: advance split, ticks (BattleSimulation.advance by a pulse)" % label, ticks)
	_report("%s: advance split, to_dict" % label, encode)
	_report("%s: advance split, snapshot copy (get_battle_snapshot)" % label, copy)
	_report("%s: advance split, snapshot render (_render_snapshot)" % label, render)
	_report("%s: render split, the set_actor loop over every unit view (done again)" % label, set_actors)
	_report("%s: render split, BattleVfx.events_between (done again)" % label, events)
	_report("%s: render split, the rest (the render less those: labels, panels, new unit views, objectives, field views)" % label, rest)
	_report("%s: renders that made new unit views, whole" % label, spawn_renders)
	_report("%s: renders that made none, whole" % label, still_renders)
	var units: Array[Node] = _find_script(view, "battle_unit_view.gd")
	for unit: Node in units:
		unit.set_process(false)
	var unit_ms: Array[float] = []
	var previous: int = Time.get_ticks_usec()
	for _frame: int in 120:
		await process_frame
		var delta: float = (Time.get_ticks_usec() - previous) / 1000000.0
		previous = Time.get_ticks_usec()
		var started: int = Time.get_ticks_usec()
		for unit: Node in units:
			if is_instance_valid(unit):
				unit._process(delta)
		unit_ms.append(_since(started))
	_report("%s: unit views' _process per frame (%d views)" % [label, units.size()], unit_ms)
	if zone_id == "frontier_march" and replay_end != null:
		_wall_replay(label, replay_start, replay_ticks, replay_end)


## ig-7sn.20: where the walls' cost goes in an advance, on a twin decoded from the battle before its first advance
## and run through the same ticks (the sim is deterministic: the twin ends where the battle did, or the last line
## says it did not). Each tick is _tick's body, with the parts timed where they run; whatever a timing has to
## change is done on a copy, so the twin's own run stays the battle's. Every row is per advance unless it says per
## tick. It runs on the walls run and on the no-wall run (W1 and the graph then read 0: the comparison).
##   W1 the Rime Wall scan: _back_row_threat for every Mage with the skill on Auto and off cooldown (an upper
##      bound: the tick's turn may not reach the rule), the threats it found, and the placements _use_skill
##      refused (_cast_wall false and the rest of its checks) on a copy.
##   W2+W3 _move_actors with the walls as they stand, then with an empty WallPaths stamped like the real one (so
##      walled is false), each on its own copy of the tick's state, in an order that flips each tick. The
##      difference is the corner search, the straight checks and separation's wall cut.
##   W4 the graph: rebuilds (a miss after the first build) and what a rebuild with a wall up cost.
##   W5 alive, moved and (walls run) blocked actors per tick: blocked is those whose straight line to the point
##      or target of their order crosses a wall, approximately the ones the corner search runs for.
func _wall_replay(label: String, start: Dictionary, per_advance: Array[int], battle: BattleState) -> void:
	var twin: BattleState = BattleState.from_dict(start.duplicate(true))
	var rng := RandomNumberGenerator.new()
	rng.state = twin.rng_state.to_int()
	var rows: Dictionary = {}
	for key: String in ["scan", "calls", "found", "refused", "real", "bare", "gap", "misses", "rebuild", "rebuild_each", "ticks", "alive", "moved", "blocked"]:
		var column: Array[float] = []
		rows[key] = column
	for count: int in per_advance:
		var spent: Dictionary = {"scan": 0.0, "calls": 0.0, "found": 0.0, "refused": 0.0, "real": 0.0, "bare": 0.0, "misses": 0.0, "rebuild": 0.0, "ticks": 0.0}
		for _n: int in count:
			if twin.status != "active":
				break
			spent["ticks"] += 1.0
			twin.tick += 1
			twin.elapsed_seconds = minf(twin.elapsed_seconds + BattleSimulation.BALANCE.battle_tick_seconds, twin.max_seconds)
			BattleSimulation._expire_effects_and_cooldowns(twin)
			BattleSimulation._update_field_objects(twin)
			BattleSimulation._answer_telegraphs(twin, rng)
			BattleSimulation._choose_intentions(twin)
			var kept: BattleSimulation.WallPaths = twin.wall_paths
			var started: int = Time.get_ticks_usec()
			var paths: BattleSimulation.WallPaths = BattleSimulation._wall_paths(twin)
			if paths != kept:
				var built: float = _since(started)
				spent["misses"] += 1.0 if kept != null else 0.0
				if not paths.centers.is_empty():
					spent["rebuild"] += built
					rows["rebuild_each"].append(built)
			var frozen: Dictionary = twin.to_dict()
			var first_walled: bool = twin.tick % 2 == 0
			var one: Array[float] = _move_time(frozen, first_walled)
			var two: Array[float] = _move_time(frozen, not first_walled)
			var real: Array[float] = one if first_walled else two
			var bare: Array[float] = two if first_walled else one
			spent["real"] += real[0]
			spent["bare"] += bare[0]
			rows["alive"].append(real[1])
			rows["moved"].append(real[2])
			rows["blocked"].append(real[3])
			BattleSimulation._move_actors(twin)
			var copy: BattleState = null
			for actor: BattleActor in twin.actors:
				if actor.life != BattleActor.LIFE_ALIVE or actor.ability_lock > 0.0 or float(actor.effect_state.get("stun_remaining", 0.0)) > 0.0 or BattleSimulation._has_status(actor, "silence"):
					continue
				for entry: Dictionary in actor.skills:
					var skill: AbilityDefinition = BattleSimulation.ABILITIES[entry["id"]]
					if skill.ai_rule != "melee_near_back_row" or str(entry["mode"]) != "auto" or float(actor.skill_cooldowns.get(entry["id"], 0.0)) > 0.0 or not skill.is_ability():
						continue
					started = Time.get_ticks_usec()
					var threat: Array = BattleSimulation._back_row_threat(twin, actor, skill)
					spent["scan"] += _since(started)
					spent["calls"] += 1.0
					if threat.is_empty():
						continue
					spent["found"] += 1.0
					if copy == null:
						copy = BattleState.from_dict(twin.to_dict().duplicate(true))
					var caster: BattleActor = BattleSimulation._actor_by_id(copy, actor.id)
					var ally: BattleActor = BattleSimulation._actor_by_id(copy, (threat[0] as BattleActor).id)
					var enemy: BattleActor = BattleSimulation._actor_by_id(copy, (threat[1] as BattleActor).id)
					var spare := RandomNumberGenerator.new()
					spare.state = rng.state
					if BattleSimulation._use_skill(copy, caster, skill, enemy, BattleSimulation._threat_point(ally, enemy, skill), spare, enemy.position - ally.position):
						copy = null
					else:
						spent["refused"] += 1.0
			BattleSimulation._support_actions(twin)
			BattleSimulation._offensive_actions(twin, rng)
			BattleSimulation._update_objectives(twin)
			BattleSimulation._evaluate_terminal(twin)
		if twin.status == "active" and twin.elapsed_seconds + BattleSimulation.TICK_EPSILON >= twin.max_seconds:
			BattleSimulation._finish_timeout(twin)
		spent["gap"] = spent["real"] - spent["bare"]
		for key: String in ["scan", "calls", "found", "refused", "real", "bare", "gap", "misses", "rebuild", "ticks"]:
			rows[key].append(spent[key])
	twin.rng_state = str(rng.state)
	_report("%s: wall split, ticks per advance (count)" % label, rows["ticks"])
	_report("%s: wall split, W1 the Rime Wall scan, _back_row_threat over ready Auto Mages (ms; an upper bound)" % label, rows["scan"])
	_report("%s: wall split, W1 scans run (count)" % label, rows["calls"])
	_report("%s: wall split, W1 scans that found a threat (count)" % label, rows["found"])
	_report("%s: wall split, W1 placements refused (count)" % label, rows["refused"])
	_report("%s: wall split, W2+W3 _move_actors, walls as they stand (ms)" % label, rows["real"])
	_report("%s: wall split, W2+W3 _move_actors, no walls: an empty WallPaths (ms)" % label, rows["bare"])
	_report("%s: wall split, W2+W3 the difference (ms)" % label, rows["gap"])
	_report("%s: wall split, W4 graph rebuilds after the first build (count)" % label, rows["misses"])
	_report("%s: wall split, W4 rebuild time with a wall up, per advance (ms)" % label, rows["rebuild"])
	_report("%s: wall split, W4 one rebuild with a wall up (ms)" % label, rows["rebuild_each"])
	_report("%s: wall split, W5 alive actors per tick (count)" % label, rows["alive"])
	_report("%s: wall split, W5 actors that moved per tick (count)" % label, rows["moved"])
	_report("%s: wall split, W5 actors whose straight line to their order is blocked per tick (count)" % label, rows["blocked"])
	print("%s: wall split, the twin ended %s the battle (tick %d vs %d, rng %s)" % [label, "with" if twin.tick == battle.tick and twin.rng_state == battle.rng_state else "AGAINST", twin.tick, battle.tick, "same" if twin.rng_state == battle.rng_state else "different"])


## One _move_actors on a copy of frozen, walled or with an empty WallPaths stamped like the real one:
## [its ms, alive actors, actors that moved, actors whose straight line to their order crosses a wall].
func _move_time(frozen: Dictionary, walled: bool) -> Array[float]:
	var copy: BattleState = BattleState.from_dict(frozen.duplicate(true))
	var paths: BattleSimulation.WallPaths = BattleSimulation._wall_paths(copy)
	if not walled:
		paths = BattleSimulation.WallPaths.new()
		paths.sequence = copy.field_sequence
		paths.count = copy.field_objects.size()
		paths.bounds = float(copy.objective_state.get("bounds", 20.0))
		copy.wall_paths = paths
	var before: Dictionary = {}
	var blocked: int = 0
	for actor: BattleActor in copy.actors:
		if actor.life != BattleActor.LIFE_ALIVE:
			continue
		before[actor.id] = actor.position
		if walled and not actor.order_kind.is_empty():
			var target: BattleActor = BattleSimulation._actor_by_id(copy, actor.order_target_id)
			var goal: Vector2 = target.position if target != null and target.life == BattleActor.LIFE_ALIVE else actor.order_point
			blocked += 1 if BattleSimulation._wall_blocked(paths, actor.position, goal) else 0
	var started: int = Time.get_ticks_usec()
	BattleSimulation._move_actors(copy)
	var spent: float = _since(started)
	var moved: int = 0
	for actor: BattleActor in copy.actors:
		if before.has(actor.id) and actor.position != before[actor.id]:
			moved += 1
	return [spent, float(before.size()), float(moved), float(blocked)]


## Opens the live battle view on order_id as the current scene, the way the ig-rog check does.
func _watch(order_id: String) -> Node:
	if current_scene != null:
		current_scene.queue_free()
	var view: Node = (load("res://combat/battle/battle_view.tscn") as PackedScene).instantiate()
	view.configure_live(order_id, session)
	root.add_child(view)
	current_scene = view
	await _wait(10)
	return view


## ---- 4. A roster action: its handlers, the Ledger readers, the save's stages, and the periodic save.

func _measure_roster() -> void:
	var started: int = Time.get_ticks_usec()
	var builds: int = session.bond_builds
	session.bond_index()
	print("bond index on first read after load: %.2f ms (%d rebuild(s))" % [_since(started), session.bond_builds - builds])
	var hub: Node = await _open_hub()
	var hero: Hero = session.roster[0]
	var roster_list: ItemList = hub.get_node("%RosterList") as ItemList
	# ig-7sn.9: select the way a click does, with the Forge open (the list is SELECT_MULTI, so the hub
	# listens to multi_selected; item_selected ran no hub handler). The selection outlives _open.
	hub._open(&"Forge")
	roster_list.deselect_all()
	roster_list.select(0)
	roster_list.multi_selected.emit(0, true)
	await _wait(5)
	for orders: int in [0, 5]:
		for zone_id: String in ZONES.slice(session.expedition_orders.size(), orders):
			_dispatch(zone_id, _cap(zone_id))
		# ig-7sn.9 (c): the whole action and its handlers with no building open, then with the Forge open
		# and the hero selected (the favorite toggle's real case).
		for building: StringName in [&"", &"Forge"]:
			hub._open(building)
			await _wait(2)
			var case: String = "roster, %d orders, %s" % [orders, "Forge open, one hero selected" if building == &"Forge" else "no building open"]
			var whole: Array[float] = []
			for _rep: int in 10:
				started = Time.get_ticks_usec()
				session.set_hero_favorite(hero, not hero.favorite)
				whole.append(_since(started))
				await process_frame
			_report("%s: a roster action (set_hero_favorite), whole" % case, whole)
			session.roster_changed.disconnect(saves.save)
			var handlers: Array[float] = []
			for _rep: int in 10:
				started = Time.get_ticks_usec()
				session.roster_changed.emit()
				handlers.append(_since(started))
			session.roster_changed.connect(saves.save)
			_report("%s: roster_changed handlers (the save unhooked)" % case, handlers)
			_report_handlers(case, session.roster_changed)
			var shown: Hero = hub._selected_hero()
			print("%s: the roster's selected hero %s" % [case, shown.hero_name if shown != null else "none"])
		var label: String = "roster, %d orders" % orders
		_roster_split(hub, label)
		var living: Dictionary = {}
		for member: Hero in session.roster:
			living[member.instance_id] = member.hero_name
		var readers: Dictionary[String, Callable] = {
			"hero detail refresh (all readers)": hub._refresh_hero_detail,
			"history_lines": func() -> void: Ledger.history_lines(session.ledger, hero.instance_id, hub._roster_names(), preload("res://balance.tres").rank_names, 10),
			"known_names": func() -> void: Ledger.known_names(session.ledger, living),
			"bond (kept index)": func() -> void: Bonds.bond_from(session.bond_index(), hero.instance_id, living, preload("res://balance.tres")),
			"dream": func() -> void: Bonds.dream(session.ledger, hero.instance_id),
			"order cards rebuild (_refresh_expeditions(true))": hub._refresh_expeditions.bind(true),
		}
		for reader: String in readers:
			_report("%s: %s" % [label, reader], _time(readers[reader], 10))
		# Lambdas cannot reassign a captured local, so each stage's output goes through one dictionary.
		var stage: Dictionary = {}
		_report("%s: save stage GameSession.to_dict" % label, _time(func() -> void: stage["payload"] = session.to_dict(), 10))
		_report("%s: save stage JSON.stringify (pre-7sn.10 pretty form)" % label, _time(func() -> void: stage["text"] = JSON.stringify(stage["payload"], "\t", true, true), 10))
		_report("%s: save stage JSON.parse_string (pre-7sn.10 pretty form)" % label, _time(func() -> void: stage["parsed"] = JSON.parse_string(stage["text"]), 10))
		_report("%s: save stage _load_refusal" % label, _time(func() -> void: saves._load_refusal(stage["parsed"] as Dictionary, saves.SAVE_VERSION), 10))
		_save_split(label, stage["payload"] as Dictionary)
		var disk_write: Callable = func() -> void:
			var file := FileAccess.open("user://perf_disk_probe.json", FileAccess.WRITE)
			file.store_string(stage["text"])
			file.flush()
			file.close()
		_report("%s: a disk write proxy (the save text to a scratch file, flushed; not the save's own files)" % label, _time(disk_write, 10))
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://perf_disk_probe.json"))
		_report("%s: SaveService.save whole (the periodic save's cost with these orders)" % label, _time(saves.save, 10))
		# The Ledger's share of a save: a save that appends one record (at the cap, one is evicted) vs one
		# that appends none, alternated. The record's bond fold happens in _record, outside the timing.
		var plain: Array[float] = []
		var appended: Array[float] = []
		var ledger_team: Array[String] = []
		for member: Hero in session.roster.slice(0, 5):
			ledger_team.append(member.instance_id)
		for index: int in 10:
			started = Time.get_ticks_usec()
			saves.save()
			plain.append(_since(started))
			session._record("battle", {"order": "perf:ledger:%d" % index, "zone": "verdant_outskirts", "battle_kind": "expedition", "result": "victory", "team": ledger_team, "kills": {}, "moments": []})
			started = Time.get_ticks_usec()
			saves.save()
			appended.append(_since(started))
		_report("%s: SaveService.save, no new record" % label, plain)
		_report("%s: SaveService.save that appends one Ledger record" % label, appended)
		print("%s: save.json %d bytes, ledger.jsonl %d bytes" % [label, _bytes("user://save.json"), _bytes("user://ledger.jsonl")])


## ig-7sn.10 (a)-(c): each battle's checkpoint (bytes, actors by faction and life, field objects, the
## dead enemies' share), the three text forms on the same payload, and _load_refusal split by battle.
## Bytes are UTF-8. "rest" is the whole check less each battle's validate_snapshot.
func _save_split(label: String, payload: Dictionary) -> void:
	for order: Dictionary in session.expedition_orders:
		if not order.get("battle") is Dictionary:
			continue
		var battle: Dictionary = order["battle"] as Dictionary
		var counts: Dictionary = {}
		var dead_enemy_bytes: int = 0
		for actor: Dictionary in battle.get("actors", []):
			var key: String = "%s %s" % [actor.get("faction", "?"), actor.get("life", "?")]
			counts[key] = int(counts.get(key, 0)) + 1
			if actor.get("faction") == "enemy" and actor.get("life") == "dead":
				dead_enemy_bytes += JSON.stringify(actor, "", false, true).to_utf8_buffer().size() + 1
		var pretty: int = JSON.stringify(battle, "\t", true, true).to_utf8_buffer().size()
		var compact: int = JSON.stringify(battle, "", false, true).to_utf8_buffer().size()
		print("%s: SPLIT battle %s: %d actors %s, %d field objects; checkpoint %d bytes pretty, %d compact; dead enemies %d bytes compact (%.1f%% of it)" % [label, battle.get("zone_id", "?"), (battle.get("actors", []) as Array).size(), counts, (battle.get("field_objects", []) as Array).size(), pretty, compact, dead_enemy_bytes, 100.0 * dead_enemy_bytes / maxf(compact, 1.0)])
	# Lambdas cannot reassign a captured local, so each form's text goes through one dictionary.
	var texts: Dictionary = {}
	var forms: Dictionary[String, Array] = {"pretty (\"\\t\", sorted)": ["\t", true], "compact sorted (\"\")": ["", true], "compact unsorted (\"\", sort_keys false)": ["", false]}
	for form: String in forms:
		_report("%s: SPLIT JSON.stringify, %s" % [label, form], _time(func() -> void: texts[form] = JSON.stringify(payload, forms[form][0], forms[form][1], true), 10))
		_report("%s: SPLIT JSON.parse_string, %s" % [label, form], _time(func() -> void: texts["parsed"] = JSON.parse_string(texts[form]), 10))
		print("%s: SPLIT bytes, %s: %d; parses back equal to the pretty form's: %s" % [label, form, (texts[form] as String).to_utf8_buffer().size(), JSON.parse_string(texts[form]) == JSON.parse_string(texts.get(forms.keys()[0], texts[form]))])
	var parsed: Dictionary = JSON.parse_string(texts[forms.keys()[0]]) as Dictionary
	var whole: Array[float] = _time(func() -> void: saves._load_refusal(parsed, saves.SAVE_VERSION), 10)
	_report("%s: SPLIT _load_refusal whole" % label, whole)
	var battle_sum: Array[float] = []
	battle_sum.resize(whole.size())
	battle_sum.fill(0.0)
	var checkpoints: Array[Dictionary] = []
	for order: Variant in parsed.get("expedition_orders", []):
		if order is Dictionary and (order as Dictionary).get("battle") is Dictionary:
			checkpoints.append((order as Dictionary)["battle"] as Dictionary)
	for incident: Variant in parsed.get("stranded_incidents", []):
		if incident is Dictionary and (incident as Dictionary).get("battle_snapshot") is Dictionary:
			checkpoints.append((incident as Dictionary)["battle_snapshot"] as Dictionary)
	for checkpoint: Dictionary in checkpoints:
		var times: Array[float] = _time(func() -> void: BattleSimulation.validate_snapshot(checkpoint), 10)
		_report("%s: SPLIT _load_refusal part validate_snapshot %s (%s)" % [label, checkpoint.get("zone_id", "?"), checkpoint.get("status", "?")], times)
		for index: int in times.size():
			battle_sum[index] += times[index]
	var rest: Array[float] = []
	for index: int in whole.size():
		rest.append(whole[index] - battle_sum[index])
	_report("%s: SPLIT _load_refusal part every battle's validate_snapshot" % label, battle_sum)
	_report("%s: SPLIT _load_refusal part heroes and the rest (whole less the battles, per sample)" % label, rest)
	_report("%s: SPLIT SaveService.save whole, 30 samples" % label, _time(saves.save, 30))


## ig-7sn.9: _refresh_roster's parts and _refresh_director_ui's six calls, each timed on the side and
## called straight (no gate), whatever shows. The per-row parts loop the whole roster, as
## _refresh_hero_list does with no filter; add_item goes to a scratch list beside %RosterList.
func _roster_split(hub: Node, label: String) -> void:
	var living: Dictionary = hub._roster_names()
	var roster_list: ItemList = hub.get_node("%RosterList") as ItemList
	var scratch := ItemList.new()
	roster_list.get_parent().add_child(scratch)
	var tooltips: Callable = func() -> void:
		for member: Hero in session.roster:
			hub._hero_detail_text(member)
	var signs: Callable = func() -> void:
		for member: Hero in session.roster:
			hub._partner_sign(member.instance_id, living)
	# bond_from's pick without its duplicate(true): what the copy costs across the rows.
	var picks: Callable = func() -> void:
		var pairs: Dictionary = session.bond_index()
		var threshold: int = preload("res://balance.tres").bond_threshold
		for member: Hero in session.roster:
			var chosen: Dictionary = {}
			for tally: Dictionary in (pairs.get(member.instance_id, {}) as Dictionary).values():
				if not living.has(tally["partner"]) or tally["points"] < threshold:
					continue
				if chosen.is_empty() or Bonds._ahead(tally, chosen):
					chosen = tally
	var checks: Callable = func() -> void:
		for member: Hero in session.roster:
			session.is_hero_busy(member)
			session.is_hero_protected(member)
	var rows: Callable = func() -> void:
		scratch.clear()
		for member: Hero in session.roster:
			scratch.add_item("[%s]  %s — %s" % [member.rank_label(preload("res://balance.tres")), member.hero_name, Summon.archetype_label_for(member.def_id)])
			scratch.set_item_metadata(scratch.item_count - 1, member)
	var parts: Dictionary[String, Callable] = {
		"the per-row tooltip (_hero_detail_text), all rows": tooltips,
		"_partner_sign, all rows": signs,
		"bond_from's pick without its duplicate(true), all rows": picks,
		"is_hero_busy + is_hero_protected, all rows": checks,
		"add_item + set_item_metadata, all rows (a scratch list)": rows,
		"_refresh_hero_option(TargetOption)": hub._refresh_hero_option.bind(hub.get_node("%TargetOption")),
		"_refresh_practice_options": hub._refresh_practice_options,
	}
	for part: String in parts:
		_report("%s: _refresh_roster part %s" % [label, part], _time(parts[part], 10))
	scratch.free()
	var calls: Dictionary[String, Callable] = {
		"_refresh_preset_lists": hub._refresh_preset_lists,
		"_refresh_preset_editor": hub._refresh_preset_editor,
		"_refresh_recovery_team_options": hub._refresh_recovery_team_options,
		"_refresh_practice_options": hub._refresh_practice_options,
		"_refresh_expeditions(true)": hub._refresh_expeditions.bind(true),
		"_refresh_hero_detail": hub._refresh_hero_detail,
	}
	for call_name: String in calls:
		_report("%s: _refresh_director_ui call %s" % [label, call_name], _time(calls[call_name], 10))


## ---- 5. The full town: every figure out, then one building change.

func _measure_town() -> void:
	var hub: Node = await _open_hub()
	var town: Node = hub.get_node("%Town")
	var walkers: int = _find_script(town, "town_walker.gd").size()
	_report_frames("town, %d walker figures, %d buildings" % [walkers, session.town_buildings.size()], await _frames())
	var free: Array[Vector2i] = []
	var taken: Dictionary = {}
	for building: Dictionary in session.town_buildings:
		taken[Vector2i(int(building["q"]), int(building["r"]))] = true
	var radius: int = preload("res://balance.tres").town_map_radius
	for q: int in range(-radius, radius + 1):
		for r: int in range(-radius, radius + 1):
			if TownRules.ring_distance(Vector2i(q, r)) <= radius and not taken.has(Vector2i(q, r)):
				free.append(Vector2i(q, r))
	var calls: Array[float] = []
	var next_frames: Array[float] = []
	for index: int in 5:
		await _wait(30)
		var started: int = Time.get_ticks_usec()
		if not session.place_building(TownRules.HOUSE, free[index]):
			push_error("place failed: " + session.last_action_error)
		calls.append(_since(started))
		await process_frame
		started = Time.get_ticks_usec()
		await process_frame
		next_frames.append(_since(started))
	_report("town: one building change (place_building: save, handlers, graph, replan), the call", calls)
	_report("town: the frame after it", next_frames)
	var graph: Array[float] = []
	for _rep: int in 10:
		(town.get("_occupied") as Dictionary).clear()
		var started: int = Time.get_ticks_usec()
		town.show_buildings(session.town_buildings)
		graph.append(_since(started))
	_report("town: show_buildings with the graph forced to rebuild (occupancy scan and walker replan)", graph)


## ---- 6. The load after a long close with all five battles out. The load owes their catch-up; it
## runs as jobs after (ig-7sn.12), timed here from the load until its round lands. Since ig-7sn.16 each
## slow frame names the jobs _process ran in it, and the landing is split as a settle is (_landing_split).

func _measure_load() -> void:
	for zone_id: String in ZONES:
		_dispatch(zone_id, _cap(zone_id))
	_print_orders()
	var hours: float = 8.0
	for battle: Dictionary in _battles():
		var copy := BattleState.from_dict(battle)
		var started: int = Time.get_ticks_usec()
		BattleSimulation.advance(copy, minf(hours * 3600.0, maxf(copy.max_seconds - copy.elapsed_seconds, 0.0)))
		print("load: catch-up of %s alone: %.1f ms (%.0f battle s, %s)" % [copy.zone_id, _since(started), copy.elapsed_seconds, copy.status])
	saves.save()
	var started_plain: int = Time.get_ticks_usec()
	saves.load_game()
	print("load: load_game, no time away: %.1f ms" % _since(started_plain))
	# The control for the frames below: the same watch after a load that owes next to nothing.
	await _frames_after_load("1.5 s from the no-time-away load", started_plain, func() -> bool: return _since(started_plain) < 1500.0)
	var file := FileAccess.open("user://save.json", FileAccess.READ)
	var text: String = file.get_as_text()
	file.close()
	var at: RegEx = RegEx.create_from_string("\"saved_at_unix\": ?[0-9.e+]+")
	text = at.sub(text, "\"saved_at_unix\":%.3f" % (Time.get_unix_time_from_system() - hours * 3600.0))
	file = FileAccess.open("user://save.json", FileAccess.WRITE)
	file.store_string(text)
	file.close()
	var started_away: int = Time.get_ticks_usec()
	saves.load_game()
	print("load: load_game after %.0f h away (owes every battle's catch-up, then its save): %.1f ms, load_blocked %s" % [hours, _since(started_away), saves.load_blocked])
	# As in the game, the hub opens on the load. Its first look rebuilds the bond index (hub.gd _ready ->
	# _refresh_walkers), so the landing's repeat checks find it warm, and the landing runs the hub's handlers.
	var builds: int = session.bond_builds
	var started_hub: int = Time.get_ticks_usec()
	await _open_hub()
	print("load: the hub opened on the load: %.1f ms over its 30 frames, %d bond index rebuild(s)" % [_since(started_hub), session.bond_builds - builds])
	var owing: Callable = func() -> bool: return _owing() > 0
	var landing: Dictionary = {}
	var spent: Dictionary = {}
	_wrap_handlers(spent)
	var frames: Array[float] = await _frames_after_load("until the catch-up landed (the last is the landing)", started_away, owing, landing, spent)
	_unwrap_handlers()
	# The last frame holds the round's commit, a settle pulse (the Dispatched battles row, ig-7sn.6).
	var landing_ms: float = 0.0
	if not frames.is_empty():
		landing_ms = frames.pop_back()
	var worst: float = 0.0
	for frame: float in frames:
		worst = maxf(worst, frame)
	print("load: catch-up landed %.1f s after the load began, %d frames, worst frame while it ran %.1f ms, landing frame %.1f ms" % [_since(started_away) / 1000.0, frames.size() + 1, worst, landing_ms])
	if not landing.is_empty():
		var parts: Dictionary = _landing_split(landing)
		var side: PackedStringArray = []
		var total: float = 0.0
		for part: String in parts:
			side.append("%s %.1f" % [part, float(parts[part])])
			if not part.begins_with("each landed") and not part.begins_with("of which"):
				total += float(parts[part])
		print("load: LANDING SPLIT (twin, ms): %s; the commit's parts together %.1f" % [", ".join(side), total])
		var handler_ms: float = 0.0
		var top: PackedStringArray = []
		for key: String in spent:
			handler_ms += float(spent[key])
			if float(spent[key]) >= 0.5:
				top.append("%s %.1f" % [key, float(spent[key])])
		print("load: LANDING HANDLERS (the real frame's, ms): %.1f (%s)" % [handler_ms, ", ".join(top)])
	_print_orders()


## ---- 7. The dispatch preview (ig-7sn.14): GameSession.preview_force for one force at each zone's cap
## (5 / 5 / 5 / 30 / 50 heroes in 5-hero presets), then one hub dispatch-summary refresh with those
## presets selected, per-team (each preset previewed in its own zone) and combined (one force).
const PREVIEW_REPS: int = 3


func _measure_preview() -> void:
	var hub: Node = await _open_hub()
	var loadout: Dictionary = {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0}
	for zone_id: String in ZONES:
		var presets: Array[String] = _presets(zone_id, _cap(zone_id))
		_report("preview: preview_force %s, %d heroes" % [zone_id, _cap(zone_id)], _time(func() -> void: session.preview_force(presets, zone_id, 99, {}, loadout), PREVIEW_REPS))
		hub._refresh_preset_lists()
		var list: ItemList = hub._preset_dispatch_list
		list.deselect_all()
		for row: int in list.item_count:
			if str((list.get_item_metadata(row) as Dictionary).get("id", "")) in presets:
				list.select(row, false)
		# The combined picker lists only the hub's EXPEDITION_ZONES; a zone outside it is per-team only.
		var modes: Array[bool] = [false]
		for row: int in hub._combined_zone.item_count:
			if str((hub._combined_zone.get_item_metadata(row) as ZoneDefinition).zone_id) == zone_id:
				hub._combined_zone.select(row)
				modes.append(true)
		for combined: bool in modes:
			hub._combine_teams.set_pressed_no_signal(combined)
			_report("preview: hub _refresh_dispatch_summary %s, %d heroes, %s" % [zone_id, _cap(zone_id), "combined" if combined else "per-team"], _time(hub._refresh_dispatch_summary, PREVIEW_REPS))
		hub._combine_teams.set_pressed_no_signal(false)


## ---- Helpers

## Frame times (ms) from now while running() holds, with GameSession._process driven from here so each
## frame's jobs are named (ig-7sn.16 ACC 8, _process_jobs). Prints the frames over 16.7 ms with their
## time since started (usec, the load's start) and those jobs. When landing is given, the catch-up
## round's inputs go into it once every catch-up job is in, before the pulse that lands them, and spent (the
## wrapped handlers' times) starts over there.
func _frames_after_load(label: String, started: int, running: Callable, landing: Dictionary = {}, spent: Dictionary = {}) -> Array[float]:
	session.set_process(false)
	var frames: Array[float] = []
	var slow: Array[String] = []
	var delta: float = 0.0
	var last: int = Time.get_ticks_usec()
	while running.call() and _since(started) < 600000.0:
		var taken: String = ""
		if landing.is_empty() and _catch_ups_in():
			var before: int = Time.get_ticks_usec()
			landing.merge(_landing_inputs())
			spent.clear()
			taken = "; the harness took the round's inputs here, %.1f ms" % _since(before)
		var jobs: String = _process_jobs(delta) + taken
		await process_frame
		frames.append(_since(last))
		last = Time.get_ticks_usec()
		delta = frames.back() / 1000.0
		if frames.back() > 16.7:
			slow.append("%.1f ms at %.2f s (%s)" % [frames.back(), _since(started) / 1000.0, jobs])
	session.set_process(true)
	print("load: %s, frames over 16.7 ms: %s" % [label, ", ".join(slow)])
	return frames


## Runs GameSession._process(delta) and names what it ran: the pulse, each battle advance, the periodic
## save (it was due), a settle (a new report), the catch-up round's landing (catch_up_seconds cleared), a
## repeat check's landing, any save; then _process's own time.
func _process_jobs(delta: float) -> String:
	var pulse: bool = not saves.load_blocked and session._expedition_pulse_accumulator + delta >= PULSE
	var advances: int = session.pulse_battle_advances
	var save_due: bool = session._periodic_save_due
	var last_report: String = _last_report_id()
	var owing: int = _owing()
	var checking: int = _checking()
	var saved_at: float = session.saved_at_unix
	var started: int = Time.get_ticks_usec()
	session._process(delta)
	var spent: float = _since(started)
	var jobs: PackedStringArray = []
	if pulse:
		jobs.append("pulse")
	if session.pulse_battle_advances > advances:
		jobs.append("%d battle advance(s)" % (session.pulse_battle_advances - advances))
	if save_due and not session._periodic_save_due:
		jobs.append("the periodic save")
	if _new_reports(last_report) > 0:
		jobs.append("%d settle(s)" % _new_reports(last_report))
	if _owing() < owing:
		jobs.append("the catch-up round landed")
	if _checking() < checking:
		jobs.append("a repeat check landed")
	if session.saved_at_unix != saved_at:
		jobs.append("a save")
	return "%s; _process %.1f ms" % [", ".join(jobs) if not jobs.is_empty() else "no job", spent]


## True once the load's catch-up round is out and each of its jobs is done (the next pulse lands it). A
## job the game has waited on already has left _battle_jobs; its task id is gone then, so it isn't asked.
func _catch_ups_in() -> bool:
	var found: bool = false
	for check: Dictionary in session._battle_checks.values():
		if check.has("catch_up"):
			var job: BattleJob = check["catch_up"] as BattleJob
			if session._battle_jobs.has(job) and not WorkerThreadPool.is_task_completed(job.task_id):
				return false
			found = true
	return found


## The catch-up round's inputs before the pulse that lands it: the profile, the ledger (its own list;
## records are never changed in place), whether the bond index is in step, and each catch-up's
## [generation, job]. Their results are read after the landing, once the game has waited on each job.
func _landing_inputs() -> Dictionary:
	var jobs: Dictionary = {}
	for order_id: String in session._battle_checks:
		var check: Dictionary = session._battle_checks[order_id]
		if check.has("catch_up"):
			jobs[order_id] = [int(check["generation"]), check["catch_up"]]
	var profile: Dictionary = session.to_dict()
	profile["version"] = saves.SAVE_VERSION
	profile["ledger"] = session.ledger.duplicate()
	return {"profile": profile, "warm": session._bond_in_step(), "jobs": jobs}


## ig-7sn.16 ACC 8: the catch-up landing, split as a settle is (_settle_split): a twin from the round's
## inputs lands the same results through _land_battle_checks_in_memory (each catch-up applied, then the
## legs that ended settled), inside the commit's steps. Parts in ms.
func _landing_split(inputs: Dictionary) -> Dictionary:
	var twin: Node = _twin(inputs["profile"] as Dictionary, bool(inputs["warm"]))
	var parts: Dictionary = {}
	var landed: Dictionary[String, int] = {}
	var decode: float = 0.0
	for order_id: String in inputs["jobs"]:
		var entry: Array = inputs["jobs"][order_id]
		var job := BattleJob.new()
		job.result = (entry[1] as BattleJob).result.duplicate(true)
		twin._battle_checks[order_id] = {"generation": int(entry[0]), "battle": twin.expedition_orders[twin._order_index(order_id)].get("battle"), "catch_up": job}
		landed[order_id] = int(entry[0])
		if job.result.get("battle") is Dictionary:
			var started: int = Time.get_ticks_usec()
			BattleState.from_dict(job.result["battle"] as Dictionary)
			decode += _since(started)
	parts["each landed battle's decode alone, together (fix 1's kind)"] = decode
	_twin_commit_head(twin, parts)
	var started_round: int = Time.get_ticks_usec()
	twin._land_battle_checks_in_memory(landed)
	parts["the round in memory (each catch-up applied, the ended legs settled)"] = _since(started_round)
	_twin_commit_tail(twin, parts)
	return parts


func _last_report_id() -> String:
	return "" if session.expedition_reports.is_empty() else str(session.expedition_reports.back().get("id", ""))


## Reports added since the one whose id is last_id (every report when it is gone or was "").
func _new_reports(last_id: String) -> int:
	var reports: Array = session.expedition_reports
	for index: int in range(reports.size() - 1, -1, -1):
		if str((reports[index] as Dictionary).get("id", "")) == last_id:
			return reports.size() - 1 - index
	return reports.size()


func _checking() -> int:
	return session.expedition_orders.filter(func(order: Dictionary) -> bool: return str(order.get("phase", "")) == "checking").size()


func _owing() -> int:
	return session.expedition_orders.filter(func(order: Dictionary) -> bool: return order.has("catch_up_seconds")).size()


func _add(samples: Dictionary, key: String, value: float) -> void:
	if not samples.has(key):
		samples[key] = []
	(samples[key] as Array).append(value)


func _open_hub() -> Node:
	change_scene_to_file("res://hub/hub.tscn")
	await _wait(30)
	return current_scene


## Dispatches the first free heroes to zone_id the way the hub does: saved 5-hero presets, 99 runs.
func _dispatch(zone_id: String, heroes: int) -> String:
	var presets: Array[String] = _presets(zone_id, heroes)
	var order_id: String = session.dispatch_force(presets, zone_id, 99, {}, {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0})
	if order_id.is_empty():
		push_error("dispatch %s (%d heroes) failed: %s" % [zone_id, heroes, session.last_action_error])
	return order_id


## Saves the first free heroes as 5-hero presets for zone_id; returns their ids.
func _presets(zone_id: String, heroes: int) -> Array[String]:
	var ids: Array[String] = []
	for hero: Hero in session.roster:
		if ids.size() < heroes and not session.is_hero_busy(hero) and not session.is_embodied(hero):
			ids.append(hero.instance_id)
	var presets: Array[String] = []
	for start: int in range(0, ids.size(), 5):
		presets.append(session.save_team_preset("", "Perf %d" % session.team_presets.size(), ids.slice(start, start + 5), zone_id))
	return presets


func _cap(zone_id: String) -> int:
	return ZoneDefinition.definition_for(StringName(zone_id)).hero_cap


func _battles() -> Array[Dictionary]:
	var battles: Array[Dictionary] = []
	for order: Dictionary in session.expedition_orders:
		if order.get("battle") is Dictionary:
			battles.append(order["battle"] as Dictionary)
	return battles


func _active() -> int:
	var active: int = 0
	for battle: Dictionary in _battles():
		if str(battle.get("status", "")) == "active":
			active += 1
	return active


## Rime Walls up across every battle's saved state (read after the pulse, outside its timing).
func _walls() -> int:
	var walls: int = 0
	for battle: Dictionary in _battles():
		for field: Dictionary in battle.get("field_objects", []):
			walls += 1 if str(field.get("kind", "")) == "wall" else 0
	return walls


## ig-vl1.5 ACC 7's no-wall run: every Mage's Rime Wall set to Off through the player's own bar
## setter, before the dispatch fixes the bar into the team snapshot.
func _rime_wall_off() -> void:
	for hero: Hero in session.roster:
		var bar: Array[Dictionary] = Hero.bar_for(hero, preload("res://balance.tres"))
		var found: bool = false
		for entry: Dictionary in bar:
			if entry["id"] == "mage_rime_wall":
				entry["mode"] = "off"
				found = true
		if found and not session.set_skill_bar(hero, bar):
			push_error("Rime Wall off failed for %s: %s" % [hero.hero_name, session.last_action_error])


func _print_orders() -> void:
	for battle: Dictionary in _battles():
		var alive: Dictionary = {}
		for actor: Dictionary in battle.get("actors", []):
			var key: String = "%s %s" % [actor.get("faction", "?"), actor.get("life", "?")]
			alive[key] = int(alive.get(key, 0)) + 1
		print("ORDER %s: %s at %.1f s, actors %s" % [battle.get("zone_id", "?"), battle.get("status", "?"), float(battle.get("elapsed_seconds", 0.0)), alive])


## Frame times (ms) after WARM_SECONDS, for RECORD_SECONDS. per_frame(delta) runs at each frame's start.
## Stops early once ended() is true.
func _frames(per_frame: Callable = Callable(), ended: Callable = Callable()) -> Array[float]:
	var times: Array[float] = []
	var start: int = Time.get_ticks_usec()
	var last: int = start
	while Time.get_ticks_usec() - start < int((WARM_SECONDS + RECORD_SECONDS) * 1000000.0) and not (ended.is_valid() and ended.call()):
		await process_frame
		var now: int = Time.get_ticks_usec()
		var delta: float = (now - last) / 1000000.0
		last = now
		if now - start > int(WARM_SECONDS * 1000000.0):
			times.append(delta * 1000.0)
		if per_frame.is_valid():
			per_frame.call(delta, now - start > int(WARM_SECONDS * 1000000.0))
	return times


func _wait(count: int) -> void:
	for _frame: int in count:
		await process_frame


func _time(work: Callable, reps: int) -> Array[float]:
	var times: Array[float] = []
	for _rep: int in reps:
		var started: int = Time.get_ticks_usec()
		work.call()
		times.append(_since(started))
	return times


func _since(started: int) -> float:
	return (Time.get_ticks_usec() - started) / 1000.0


func _bytes(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_length() if file != null else -1


## Each handler connected to a no-argument signal, called on its own.
func _report_handlers(label: String, changed: Signal) -> void:
	for connection: Dictionary in changed.get_connections():
		var handler: Callable = connection["callable"]
		_report("%s: %s handler %s.%s" % [label, changed.get_name(), handler.get_object().get_class() if handler.get_object() != null else "?", handler.get_method()], _time(handler, 5))


func _report_frames(label: String, times: Array[float]) -> void:
	var sorted: Array[float] = times.duplicate()
	sorted.sort()
	if sorted.is_empty():
		print("FRAMES %s: none" % label)
		return
	var over: int = sorted.filter(func(time: float) -> bool: return time > 33.0).size()
	print("FRAMES %s: n=%d p50=%.2f p99=%.2f worst=%.2f over33=%d" % [label, sorted.size(), _at(sorted, 0.5), _at(sorted, 0.99), sorted.back(), over])


func _report(label: String, samples: Array) -> void:
	var sorted: Array[float] = []
	sorted.assign(samples)
	sorted.sort()
	if sorted.is_empty():
		print("TIME %s: none" % label)
		return
	var total: float = 0.0
	for sample: float in sorted:
		total += sample
	print("TIME %s: n=%d mean=%.2f p50=%.2f p99=%.2f max=%.2f" % [label, sorted.size(), total / sorted.size(), _at(sorted, 0.5), _at(sorted, 0.99), sorted.back()])


func _at(sorted: Array[float], fraction: float) -> float:
	return sorted[mini(int(fraction * sorted.size()), sorted.size() - 1)]


func _find_script(node: Node, file: String) -> Array[Node]:
	var found: Array[Node] = []
	var script: Script = node.get_script() as Script
	if script != null and script.resource_path.ends_with(file):
		found.append(node)
	for child: Node in node.get_children():
		found.append_array(_find_script(child, file))
	return found


func _find_class(node: Node, type: String) -> Array[Node]:
	return node.find_children("*", type, true, false)
