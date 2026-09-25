extends SceneTree

## ig-7sn.2: the performance baseline, one measure per run, windowed at 1920x1080 with vsync off, on
## a copy of the save tests/perf/seed_perf.gd made. It refuses a save without the seed's marker, so it
## never runs on the owner's, nor without perf_throwaway.txt in its user:// (see seed_perf.gd). Copy
## the seeded APPDATA first: a measure changes its save.
##   APPDATA="$(cygpath -w <copy>)" ./tools/godot/Godot_v4.7.1-stable_win64_console.exe --windowed -s res://tests/perf/perf_baseline.gd -- <measure> <commit>
## Measures (the ig-7sn.2 list): pulse1, pulse5, hub, battle_citadel, battle_frontier, roster, town, load.
## Since ig-7sn.6: settle1, settle5 (the pulse that settles a leg, split).
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
	print("CPU %s | GPU %s | window %s | vsync %d | max_fps %d" % [OS.get_processor_name(), RenderingServer.get_video_adapter_name(), DisplayServer.window_get_size(), DisplayServer.window_get_vsync_mode(), Engine.max_fps])
	print("SAVE %d heroes, %d records, %d buildings, %d orders" % [session.roster.size(), session.ledger.size(), session.town_buildings.size(), session.expedition_orders.size()])
	match measure:
		"pulse1":
			await _measure_pulse(1)
		"pulse5":
			await _measure_pulse(5)
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
		"roster":
			await _measure_roster()
		"town":
			await _measure_town()
		"load":
			_measure_load()
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


## Frames with GameSession's own _process driving the pulse, called from here so each pulse is timed.
func _pulse_frames(label: String) -> void:
	session.set_process(false)
	# Keyed by the battles active when the pulse began; -1 holds the pulses that settled a leg.
	var pulses: Dictionary[int, Array] = {}
	var frames: Array[float] = await _frames(func(delta: float, recording: bool) -> void:
		var reports: int = session.expedition_reports.size()
		var active: int = _active()
		var started: int = Time.get_ticks_usec()
		session._process(delta)
		if recording and session._expedition_pulse_accumulator == 0.0:
			# A pulse that settles a leg (a new report) commits: roster_changed, its handlers, a save.
			var key: int = -1 if session.expedition_reports.size() != reports else active
			if not pulses.has(key):
				pulses[key] = []
			pulses[key].append(_since(started)))
	session.set_process(true)
	_report_frames(label, frames)
	var keys: Array[int] = pulses.keys()
	keys.sort()
	for key: int in keys:
		var samples: Array[float] = []
		samples.assign(pulses[key])
		_report("%s: whole pulse (GameSession._process), %s" % [label, "that settled a leg" if key == -1 else "%d active, no leg settled" % key], samples)


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


## ---- 1b. The pulse that settles a leg, split (ig-7sn.6). One battle or all five, 99-run orders,
## pulsed with the hub shown until SETTLES legs settle. Before each settling pulse, each part's work is
## done again on the side: the repeat's forecast (its team snapshot apart), the profile to_dict (the
## commit's snapshot), a save, and each signal's handlers. "rest" is the pulse minus those (the other
## battles' advance, the report, the Ledger record and bond fold, the save's own to_dict).
const SETTLES: int = 5


func _measure_settle(count: int) -> void:
	await _open_hub()
	for zone_id: String in ZONES.slice(0, count):
		_dispatch(zone_id, _cap(zone_id))
	session.set_process(false)
	var settles: int = 0
	var pulses: int = 0
	while settles < SETTLES and pulses < 20000:
		pulses += 1
		var due: Dictionary = {}
		for order: Dictionary in session.expedition_orders:
			if str((order["battle"] as Dictionary).get("status", "")) != "active" and float(order.get("remaining_seconds", 0.0)) <= PULSE:
				due = order
		var parts: Dictionary = {}
		if not due.is_empty():
			parts = _settle_parts(due)
		var active: int = _active()
		var reports: int = session.expedition_reports.size()
		var started: int = Time.get_ticks_usec()
		session.tick_expeditions(PULSE)
		var whole: float = _since(started)
		if session.expedition_reports.size() != reports and not parts.is_empty():
			settles += 1
			var line: String = "SETTLE %s (%d active before): whole pulse %.1f" % [due.get("zone_id", "?"), active, whole]
			var rest: float = whole
			for part: String in parts:
				line += ", %s %.1f" % [part, parts[part]]
				if part != "team snapshot":
					rest -= float(parts[part])
			print("%s, rest %.1f ms" % [line, rest])
		await process_frame
	session.set_process(true)


## The settling pulse's parts for due, each timed once on the side (ms).
func _settle_parts(due: Dictionary) -> Dictionary:
	var parts: Dictionary = {}
	var team: Array[Hero] = []
	for hero_id: String in session._string_array(due["hero_ids"]):
		team.append(session.hero_by_id(hero_id))
	var squads: Array[Dictionary] = []
	for squad: Dictionary in due["squads"]:
		squads.append(squad.duplicate(true))
	var zone: ZoneDefinition = ZoneDefinition.definition_for(StringName(str(due["zone_id"])))
	var started: int = Time.get_ticks_usec()
	var snapshots: Array[Dictionary] = session._team_snapshots(team, squads)
	parts["team snapshot"] = _since(started)
	started = Time.get_ticks_usec()
	BattleSimulation.forecast(str(due["id"]) + ":repeat", snapshots, zone, squads, due["policies"] as Dictionary, session._loadout_escrow(due["loadout"] as Dictionary), 1)
	parts["forecast (with its snapshot)"] = _since(started) + float(parts["team snapshot"])
	started = Time.get_ticks_usec()
	session.to_dict()
	parts["profile to_dict"] = _since(started)
	started = Time.get_ticks_usec()
	saves.save()
	parts["save"] = _since(started)
	for changed: Signal in [session.roster_changed, session.expeditions_changed]:
		started = Time.get_ticks_usec()
		for connection: Dictionary in changed.get_connections():
			(connection["callable"] as Callable).call()
		parts[changed.get_name() + " handlers"] = _since(started)
	started = Time.get_ticks_usec()
	for connection: Dictionary in session.battle_changed.get_connections():
		(connection["callable"] as Callable).call(str(due["id"]))
	parts["battle_changed handlers"] = _since(started)
	return parts


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
	var live: Array[float] = []
	var spawn_frames: Array[float] = []
	var quiet_frames: Array[float] = []
	# [live effects at the last frame's start, the pulse ms inside that frame, most particle nodes]
	var last: Array[float] = [float(vfx.get_child_count()), 0.0, 0.0]
	var per_frame: Callable = func(delta: float, recording: bool) -> void:
		# A frame's time less the pulse inside it (all its other work); an effect spawned in it if the
		# live count went up. Warm-up frames are left out, as in the frame report.
		var count: float = vfx.get_child_count()
		if recording:
			(spawn_frames if count > last[0] else quiet_frames).append(delta * 1000.0 - last[1])
			live.append(count)
		last[0] = count
		# A tree scan costs time itself, so particles are counted once every 60 frames only.
		if recording and live.size() % 60 == 0:
			last[2] = maxf(last[2], _find_class(vfx, "GPUParticles3D").size() + _find_class(vfx, "CPUParticles3D").size())
		var started: int = Time.get_ticks_usec()
		session._process(delta)
		last[1] = 0.0
		if session._expedition_pulse_accumulator == 0.0:
			last[1] = _since(started)
			if recording:
				pulses.append(last[1])
	var ended: Callable = func() -> bool: return not is_instance_valid(vfx) or str(session.get_battle_snapshot(order_id).get("status", "")) != "active"
	var frames: Array[float] = await _frames(per_frame, ended)
	session.set_process(true)
	var label: String = "watched %s (%d heroes)" % [zone_id, _cap(zone_id)]
	_print_orders()
	_report_frames("%s, until the battle ends" % label, frames)
	_report("%s: whole pulse, sim + the view's battle_changed render" % label, pulses)
	_report("%s: live effects per frame (cap 40), most particle nodes %d" % [label, int(last[2])], live)
	_report("%s: frames where the live effect count rose, less the pulse (all other work)" % label, spawn_frames)
	_report("%s: frames where it did not, less the pulse" % label, quiet_frames)
	# The split, outside the recorded frames, on a battle still running: a fresh one if this one ended.
	if not is_instance_valid(view) or session.get_battle_snapshot(order_id).get("status", "") != "active":
		order_id = _dispatch(zone_id, _cap(zone_id))
		if order_id.is_empty():
			print("%s: split not taken, too few free heroes for a second battle" % label)
			return
		view = await _watch(order_id)
	session.battle_changed.disconnect(view._on_battle_changed)
	session.set_process(false)
	var sim: Array[float] = []
	var copy: Array[float] = []
	var render: Array[float] = []
	for _pulse: int in SAMPLES:
		var started: int = Time.get_ticks_usec()
		session.tick_expeditions(PULSE)
		sim.append(_since(started))
		started = Time.get_ticks_usec()
		var snapshot: Dictionary = session.get_battle_snapshot(order_id)
		copy.append(_since(started))
		if snapshot.is_empty():
			break
		started = Time.get_ticks_usec()
		view._render_snapshot(snapshot)
		render.append(_since(started))
		await process_frame
	_report("%s: sim (tick_expeditions, view unhooked)" % label, sim)
	_report("%s: snapshot copy (get_battle_snapshot)" % label, copy)
	_report("%s: snapshot render (_render_snapshot)" % label, render)
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
	roster_list.select(0)
	roster_list.item_selected.emit(0)
	await _wait(5)
	for orders: int in [0, 5]:
		for zone_id: String in ZONES.slice(session.expedition_orders.size(), orders):
			_dispatch(zone_id, _cap(zone_id))
		var label: String = "roster, %d orders" % orders
		var whole: Array[float] = []
		for _rep: int in 10:
			started = Time.get_ticks_usec()
			session.set_hero_favorite(hero, not hero.favorite)
			whole.append(_since(started))
			await process_frame
		_report("%s: a roster action (set_hero_favorite), whole" % label, whole)
		session.roster_changed.disconnect(saves.save)
		var handlers: Array[float] = []
		for _rep: int in 10:
			started = Time.get_ticks_usec()
			session.roster_changed.emit()
			handlers.append(_since(started))
		session.roster_changed.connect(saves.save)
		_report("%s: roster_changed handlers (the save unhooked)" % label, handlers)
		_report_handlers(label, session.roster_changed)
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
		_report("%s: save stage JSON.stringify" % label, _time(func() -> void: stage["text"] = JSON.stringify(stage["payload"], "\t"), 10))
		_report("%s: save stage JSON.parse_string" % label, _time(func() -> void: stage["parsed"] = JSON.parse_string(stage["text"]), 10))
		_report("%s: save stage _load_refusal" % label, _time(func() -> void: saves._load_refusal(stage["parsed"] as Dictionary, saves.SAVE_VERSION), 10))
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


## ---- 6. The load: offline catch-up of all five battles after a long close.

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
	var file := FileAccess.open("user://save.json", FileAccess.READ)
	var text: String = file.get_as_text()
	file.close()
	var at: RegEx = RegEx.create_from_string("\"saved_at_unix\": [0-9.e+]+")
	text = at.sub(text, "\"saved_at_unix\": %.3f" % (Time.get_unix_time_from_system() - hours * 3600.0))
	file = FileAccess.open("user://save.json", FileAccess.WRITE)
	file.store_string(text)
	file.close()
	var started_away: int = Time.get_ticks_usec()
	saves.load_game()
	print("load: load_game after %.0f h away (offline catch-up of every battle, then its save): %.1f ms, load_blocked %s" % [hours, _since(started_away), saves.load_blocked])
	_print_orders()


## ---- Helpers

func _open_hub() -> Node:
	change_scene_to_file("res://hub/hub.tscn")
	await _wait(30)
	return current_scene


## Dispatches the first free heroes to zone_id the way the hub does: saved 5-hero presets, 99 runs.
func _dispatch(zone_id: String, heroes: int) -> String:
	var ids: Array[String] = []
	for hero: Hero in session.roster:
		if ids.size() < heroes and not session.is_hero_busy(hero) and not session.is_embodied(hero):
			ids.append(hero.instance_id)
	var presets: Array[String] = []
	for start: int in range(0, ids.size(), 5):
		presets.append(session.save_team_preset("", "Perf %d" % session.team_presets.size(), ids.slice(start, start + 5), zone_id))
	var order_id: String = session.dispatch_force(presets, zone_id, 99, {}, {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0})
	if order_id.is_empty():
		push_error("dispatch %s (%d heroes) failed: %s" % [zone_id, ids.size(), session.last_action_error])
	return order_id


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
