extends SceneTree

## ig-od3: the balance gate, run by hand, never from tests/unit. The eight ig-544 starter cases
## (Verdant, stay_together, bare/suggested supplies), one line per case: status, seconds, hero
## downings, and hops. Heroes are built by GameSession._team_snapshots, the builder real orders use,
## so they carry their level, skill bar and chains.
##   APPDATA="$(cygpath -w "$(mktemp -d)")" ./tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless -s res://tests/balance/balance_gate.gd -- --pace=6 --seeds=1,2 --kit=real
## Args (all optional; the defaults are shown): --pace=N is create_run's pace. --kit=default erases
## level, skills, chains and cover_order, which leaves the old gate's snapshot (every hero on
## set_default_kit). It never saves; the temp APPDATA is only a guard.

const BALANCE: BalanceTable = preload("res://balance.tres")
const DEFAULT_KIT_ERASES: Array[String] = ["level", "skills", "chains", "cover_order"]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var pace: int = 6
	var seeds: Array[int] = [1, 2]
	var kit: String = "real"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--pace=") and arg.get_slice("=", 1).is_valid_int():
			pace = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--seeds="):
			seeds.clear()
			for part: String in arg.get_slice("=", 1).split(","):
				seeds.append(part.to_int())
		elif arg in ["--kit=real", "--kit=default"]:
			kit = arg.get_slice("=", 1)
		else:
			push_error("balance_gate: unknown arg %s" % arg)
			quit(1)
			return
	print("GATE pace=%d seeds=%s kit=%s" % [pace, seeds, kit])
	var game_session: Node = root.get_node("GameSession")
	var verdant: ZoneDefinition = ZoneDefinition.definition_for(&"verdant_outskirts")
	for battle_case: Array in [["mixed", ["knight", "ranger", "mage", "rogue", "knight"]], ["starter_knights", ["knight", "knight", "knight"]]]:
		var team: Array[Hero] = _starter_team(battle_case[1] as Array)
		var squads: Array[Dictionary] = _squads(team)
		var snapshots: Array[Dictionary] = []
		snapshots.assign(game_session.call("_team_snapshots", team, squads))
		if kit == "default":
			for snapshot: Dictionary in snapshots:
				for key: String in DEFAULT_KIT_ERASES:
					snapshot.erase(key)
		for seed_value: int in seeds:
			for suggested: bool in [false, true]:
				var name: String = "%s%s:%d" % [battle_case[0], "_suggested" if suggested else "", seed_value]
				var supplies: Dictionary = {"healing": snapshots.size(), "revival": 1} if suggested else {"healing": 0, "revival": 0}
				_measure(name, snapshots, verdant, squads, supplies, seed_value, pace)
	quit()


func _measure(name: String, snapshots: Array[Dictionary], zone: ZoneDefinition, squads: Array[Dictionary], supplies: Dictionary, seed_value: int, pace: int) -> void:
	var state: BattleState = BattleSimulation.create_run("golden:%s" % name, snapshots, zone, squads, {}, supplies, seed_value, "normal", pace)
	var was_alive: Dictionary = {}
	var downings: int = 0
	var hops: int = 0
	var outcome: BattleOutcome = BattleSimulation.snapshot_outcome(state)
	while state.status == "active":
		for actor: BattleActor in state.actors:
			if actor.faction == "ally":
				was_alive[actor.id] = actor.life == BattleActor.LIFE_ALIVE
		outcome = BattleSimulation.advance(state, BALANCE.battle_tick_seconds)
		for actor: BattleActor in state.actors:
			if actor.faction != "ally":
				continue
			if bool(was_alive.get(actor.id, false)) and actor.life == BattleActor.LIFE_DOWNED:
				downings += 1
			if int(actor.effect_state.get("kite_ready_tick", -1)) == state.tick + ceili(5.0 / BALANCE.battle_tick_seconds):
				hops += 1
	print("CASE %s status=%s seconds=%.1f downings=%d hops=%d" % [name, outcome.status, outcome.elapsed_seconds, downings, hops])


func _starter_team(archetypes: Array) -> Array[Hero]:
	var team: Array[Hero] = []
	for index: int in archetypes.size():
		var hero := Hero.new("Measure %d" % index, 0)
		hero.def_id = StringName(archetypes[index])
		hero.level = 1
		hero.instance_id = "measure:%d" % index
		team.append(hero)
	return team


func _squads(team: Array[Hero]) -> Array[Dictionary]:
	var ids: Array[String] = []
	for hero: Hero in team:
		ids.append(hero.instance_id)
	return [{"id": "measure:squad", "name": "Measure", "hero_ids": ids, "stance": "stay_together", "guard_target_id": ""}]
