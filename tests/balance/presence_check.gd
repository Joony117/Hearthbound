extends SceneTree

## ig-vl1.3: the caster presence test (SYSTEMS.md § Casters, "Presence, as the sim measures it"), run by
## hand, never from tests/unit. The balance gate's mixed team with its Mage slot swapped; everyone else
## at the slot's rank and level. Seeds 1-8, bare supplies (supplies heal, which would mask a Cleric),
## the live battle_pace. SYSTEMS re-runs it after zones and walls, so it stays.
##   APPDATA="$(cygpath -w "$(mktemp -d)")" ./tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless -s res://tests/balance/presence_check.gd -- --offsets=0.5,0.75,1.0 --points=F1_verdant
## Args (optional; the defaults are the full sweep): --offsets=a,b,.. and --points=label,.. (a POINTS label).
## Mage: seconds to victory (not won = the zone's max_seconds). Cleric: the team's HP at victory
## (downed = 0, not won = 0). One ROW line per point and slot (medians, wins out of 8), then one
## PICK line: the smallest offset where every lower bound holds and no upper bound breaks.
## It sets caster_rank_offset on the loaded balance.tres at runtime (the instance
## GameSession._team_snapshots reads) and never saves; the temp APPDATA is only a guard.

## A var, not a const: the offset is set on it (the same cached instance GameSession reads).
var _balance: BalanceTable = preload("res://balance.tres")
const TEAM: Array[String] = ["knight", "ranger", "mage", "rogue", "knight"]
const SLOT: int = 2
const SEEDS: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8]
## [label, zone, rank, level]. The Knight is measured at rank + 1 and rank + 2.
const POINTS: Array = [["F1_verdant", &"verdant_outskirts", 0, 1], ["C30_sundered", &"sundered_vault", 2, 30]]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var offsets: Array[float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5]
	var labels: Array[String] = []
	for point: Array in POINTS:
		labels.append(point[0])
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--offsets="):
			offsets.clear()
			for part: String in arg.get_slice("=", 1).split(","):
				offsets.append(part.to_float())
		elif arg.begins_with("--points="):
			labels.assign(arg.get_slice("=", 1).split(","))
		else:
			push_error("presence_check: unknown arg %s" % arg)
			quit(1)
			return
	var game_session: Node = root.get_node("GameSession")
	print("PRESENCE pace=%d seeds=%s offsets=%s" % [_balance.battle_pace, SEEDS, offsets])
	var passing: Array[float] = offsets.duplicate()
	for point: Array in POINTS:
		if not labels.has(point[0]):
			continue
		var zone: ZoneDefinition = ZoneDefinition.definition_for(point[1] as StringName)
		var rank: int = point[2]
		var level: int = point[3]
		var near: Dictionary = _measure(game_session, point, zone, "knight", rank + 1, level, -1.0)
		var far: Dictionary = _measure(game_session, point, zone, "knight", rank + 2, level, -1.0)
		for offset: float in offsets:
			_balance.caster_rank_offset = offset
			var mage: Dictionary = _measure(game_session, point, zone, "mage", rank, level, offset)
			var cleric: Dictionary = _measure(game_session, point, zone, "cleric", rank, level, offset)
			# Faster is less time; the Mage lands between the near Knight's time and the far one's. A row
			# with no win has only capped times and zero HP, which would pass every bound, so it fails.
			var fits: bool = near["wins"] > 0 and far["wins"] > 0 and mage["wins"] > 0 and cleric["wins"] > 0 \
				and mage["seconds"] <= near["seconds"] and mage["seconds"] >= far["seconds"] \
				and cleric["hp"] >= near["hp"] and cleric["hp"] <= far["hp"]
			print("FIT point=%s offset=%.2f fits=%s mage_low=%s mage_high=%s cleric_low=%s cleric_high=%s" % [point[0], offset, fits,
				mage["seconds"] <= near["seconds"], mage["seconds"] >= far["seconds"], cleric["hp"] >= near["hp"], cleric["hp"] <= far["hp"]])
			if not fits:
				passing.erase(offset)
	print("PICK offset=%s" % (str(passing.min()) if not passing.is_empty() else "none"))
	quit()


func _measure(game_session: Node, point: Array, zone: ZoneDefinition, archetype: String, rank: int, level: int, offset: float) -> Dictionary:
	var team: Array[Hero] = []
	for index: int in TEAM.size():
		var hero := Hero.new("Presence %d" % index, rank if index == SLOT else int(point[2]))
		hero.def_id = StringName(archetype if index == SLOT else TEAM[index])
		hero.level = level
		hero.instance_id = "presence:%d" % index
		team.append(hero)
	var ids: Array[String] = []
	for hero: Hero in team:
		ids.append(hero.instance_id)
	var squads: Array[Dictionary] = [{"id": "presence:squad", "name": "Presence", "hero_ids": ids, "stance": "stay_together", "guard_target_id": ""}]
	var snapshots: Array[Dictionary] = []
	snapshots.assign(game_session.call("_team_snapshots", team, squads))
	var seconds: Array[float] = []
	var hp: Array[float] = []
	var wins: int = 0
	var ends: Dictionary = {}
	for seed_value: int in SEEDS:
		var state: BattleState = BattleSimulation.create_run("presence:%s" % archetype, snapshots, zone, squads, {}, {"healing": 0, "revival": 0}, seed_value)
		var outcome: BattleOutcome = BattleSimulation.snapshot_outcome(state)
		while state.status == "active":
			outcome = BattleSimulation.advance(state, _balance.battle_tick_seconds)
		var team_hp: float = 0.0
		for actor: BattleActor in state.actors:
			if actor.faction == "ally" and actor.life == BattleActor.LIFE_ALIVE:
				team_hp += actor.hp
		var won: bool = outcome.status == "victory"
		wins += int(won)
		ends[outcome.status] = int(ends.get(outcome.status, 0)) + 1
		seconds.append(outcome.elapsed_seconds if won else state.max_seconds)
		hp.append(team_hp if won else 0.0)
	var result: Dictionary = {"seconds": _median(seconds), "hp": _median(hp), "wins": wins}
	print("ROW point=%s slot=%s_%s offset=%s seconds=%.1f hp=%.1f wins=%d/%d ends=%s" % [point[0], archetype,
		_balance.rank_names[rank], "-" if offset < 0.0 else "%.2f" % offset, result["seconds"], result["hp"], wins, SEEDS.size(), ends])
	return result


func _median(values: Array[float]) -> float:
	values.sort()
	var middle: int = values.size() >> 1
	return values[middle] if values.size() % 2 == 1 else (values[middle - 1] + values[middle]) / 2.0
