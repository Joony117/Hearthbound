extends SceneTree

## ig-vl1.6: the caster presence test (SYSTEMS.md § Casters, "Presence, as the sim measures it"), run by
## hand, never from tests/unit. Presence is the hardest fight the team still wins: its "break". The
## balance gate's mixed team with its Mage slot filled; everyone else at the point's rank and level.
## Seeds 1-8, bare supplies (supplies heal, which would mask a Cleric), the live battle_pace.
##   APPDATA="$(cygpath -w "$(mktemp -d)")" ./tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless -s res://tests/balance/presence_check.gd -- --offsets=0 --points=F1_verdant
## Args (optional; the defaults are shown): --offsets=0 (a,b,..) and --points=F1_verdant,B30_ashfall.
## The zone's enemy power is scaled by m (a duplicate with recommended_power x m; every enemy's HP, ATK
## and DEF follow the budget). Per seed, a geometric bisection finds the largest m the team wins
## ("victory"; anything else is a loss). The slot's break is the median of the seeds.
## Lines: INFO (team power against RP, and the m = 1 fight: seconds, hp, wins), BREAK per slot,
## TIMEOUT when most of a slot's losses are timeouts, EQUIV per point and offset (the casters' Knight-
## rank equivalent, UNRESOLVED when the Knights' gap is under two search steps), and one PICK.
## It sets caster_rank_offset on the loaded balance.tres at runtime (the instance
## GameSession._team_snapshots reads) and never saves; the temp APPDATA is only a guard.

## A var, not a const: the offset is set on it (the same cached instance GameSession reads).
var _balance: BalanceTable = preload("res://balance.tres")
const TEAM: Array[String] = ["knight", "ranger", "mage", "rogue", "knight"]
const SLOT: int = 2
const SEEDS: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8]
## [label, zone, rank, level]. The Knight is measured at rank + 1 and rank + 2.
const POINTS: Array = [["F1_verdant", &"verdant_outskirts", 0, 1], ["B30_ashfall", &"ashfall_reaches", 3, 30]]
## The search: [0.5, 2.0], widened x2 up to 8 or halved down to 0.125, then 6 halvings (about +-1.1%).
const SEARCH_LOW: float = 0.5
const SEARCH_HIGH: float = 2.0
const SEARCH_MAX: float = 8.0
const SEARCH_MIN: float = 0.125
const HALVINGS: int = 6
## Two search steps: a Knight gap under this can't place a caster between the Knights.
const MIN_GAP: float = 1.044


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var offsets: Array[float] = [0.0]
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
	print("PRESENCE pace=%d seeds=%s offsets=%s points=%s" % [_balance.battle_pace, SEEDS, offsets, labels])
	_print_scale_check(game_session)
	var passing: Array[float] = offsets.duplicate()
	for point: Array in POINTS:
		if not labels.has(point[0]):
			continue
		var zone: ZoneDefinition = ZoneDefinition.definition_for(point[1] as StringName)
		var rank: int = point[2]
		var near: Dictionary = _slot(game_session, point, zone, "knight", rank + 1, -1.0)
		var far: Dictionary = _slot(game_session, point, zone, "knight", rank + 2, -1.0)
		var gap: float = far["m"] / near["m"]
		for offset: float in offsets:
			_balance.caster_rank_offset = offset
			var mage: Dictionary = _slot(game_session, point, zone, "mage", rank, offset)
			var cleric: Dictionary = _slot(game_session, point, zone, "cleric", rank, offset)
			var resolved: bool = gap >= MIN_GAP
			print("EQUIV point=%s offset=%.2f mage=%s cleric=%s gap=%.1f%%%s" % [point[0], offset,
				_equivalent(mage["m"], near["m"], far["m"]), _equivalent(cleric["m"], near["m"], far["m"]),
				(gap - 1.0) * 100.0, "" if resolved else " UNRESOLVED"])
			var fits: bool = resolved
			for caster: Dictionary in [mage, cleric]:
				fits = fits and caster["m"] >= near["m"] and caster["m"] <= far["m"]
			if not fits:
				passing.erase(offset)
	print("PICK offset=%s" % (str(passing.min()) if not passing.is_empty() else "none"))
	quit()


## Proves the scaled copy reaches the fight: the first enemy's max_hp at m = 1 and m = 2.
func _print_scale_check(game_session: Node) -> void:
	var zone: ZoneDefinition = ZoneDefinition.definition_for(POINTS[0][1] as StringName)
	var built: Dictionary = _build(game_session, POINTS[0], "mage", int(POINTS[0][2]))
	var hp: Array[float] = []
	for m: float in [1.0, 2.0]:
		var state: BattleState = BattleSimulation.create_run("presence:scale", built["snapshots"], _scaled(zone, m), built["squads"], {}, {"healing": 0, "revival": 0}, 1)
		while state.status == "active" and not state.actors.any(func(actor: BattleActor) -> bool: return actor.faction == "enemy"):
			BattleSimulation.advance(state, _balance.battle_tick_seconds)
		for actor: BattleActor in state.actors:
			if actor.faction == "enemy":
				hp.append(actor.max_hp)
				break
	print("INFO scale zone=%s enemy_max_hp m1=%.1f m2=%.1f ratio=%.3f" % [zone.zone_id, hp[0], hp[1], hp[1] / hp[0]])


func _scaled(zone: ZoneDefinition, m: float) -> ZoneDefinition:
	var hard: ZoneDefinition = zone.duplicate()
	hard.recommended_power = roundi(zone.recommended_power * m)
	return hard


## The Knight-rank equivalent as the caster's rank offset: R+1 + ln(b / b_near) / ln(b_far / b_near),
## minus R. So +1.0 is the near Knight, +2.0 the far one.
func _equivalent(value: float, near: float, far: float) -> String:
	if far <= near:
		return "n/a"
	return "%+.2f" % (1.0 + log(value / near) / log(far / near))


## The mixed team with the slot filled: its snapshots (through the game's own builder), squads and power.
func _build(game_session: Node, point: Array, archetype: String, rank: int) -> Dictionary:
	var team: Array[Hero] = []
	var definitions: Array[HeroDefinition] = []
	var levels: Array[int] = []
	var ids: Array[String] = []
	for index: int in TEAM.size():
		var hero := Hero.new("Presence %d" % index, rank if index == SLOT else int(point[2]))
		hero.def_id = StringName(archetype if index == SLOT else TEAM[index])
		hero.level = int(point[3])
		hero.instance_id = "presence:%d" % index
		team.append(hero)
		definitions.append(Hero.definition_for(hero.def_id))
		levels.append(Hero.level_for(hero, _balance))
		ids.append(hero.instance_id)
	var squads: Array[Dictionary] = [{"id": "presence:squad", "name": "Presence", "hero_ids": ids, "stance": "stay_together", "guard_target_id": ""}]
	var snapshots: Array[Dictionary] = []
	snapshots.assign(game_session.call("_team_snapshots", team, squads))
	return {"snapshots": snapshots, "squads": squads, "power": Hero.compute_team_power(team, definitions, levels, _balance)}


func _slot(game_session: Node, point: Array, zone: ZoneDefinition, archetype: String, rank: int, offset: float) -> Dictionary:
	var started: int = Time.get_ticks_msec()
	var built: Dictionary = _build(game_session, point, archetype, rank)
	var snapshots: Array[Dictionary] = []
	snapshots.assign(built["snapshots"])
	var squads: Array[Dictionary] = []
	squads.assign(built["squads"])
	var slot: String = "%s_%s" % [archetype, _balance.rank_names[rank]]
	var shown_offset: String = "-" if offset < 0.0 else "%.2f" % offset
	var power: float = built["power"]
	print("INFO power point=%s slot=%s offset=%s power=%.0f rp=%d pct=%.0f%%" % [point[0], slot, shown_offset, power, zone.recommended_power, power / zone.recommended_power * 100.0])
	# The m = 1 fight: the slot's role profile, not judged.
	var seconds: Array[float] = []
	var hp: Array[float] = []
	var wins: int = 0
	for seed_value: int in SEEDS:
		var state: BattleState = _fight(snapshots, zone, squads, seed_value)
		var team_hp: float = 0.0
		for actor: BattleActor in state.actors:
			if actor.faction == "ally" and actor.life == BattleActor.LIFE_ALIVE:
				team_hp += actor.hp
		var won: bool = state.status == "victory"
		wins += int(won)
		seconds.append(state.elapsed_seconds if won else state.max_seconds)
		hp.append(team_hp if won else 0.0)
	print("INFO row point=%s slot=%s offset=%s seconds=%.1f hp=%.1f wins=%d/%d" % [point[0], slot, shown_offset, _median(seconds), _median(hp), wins, SEEDS.size()])
	# The break.
	var losses: Dictionary = {"defeat": 0, "timeout": 0}
	var breaks: Array[float] = []
	for seed_value: int in SEEDS:
		breaks.append(_break(snapshots, zone, squads, seed_value, losses))
	var sorted: Array[float] = breaks.duplicate()
	sorted.sort()
	var median: float = _median(breaks)
	var seed_text: PackedStringArray = []
	for value: float in breaks:
		seed_text.append("%.3f" % value)
	print("BREAK point=%s slot=%s offset=%s m=%.3f seeds=[%s] min=%.3f max=%.3f losses={defeat:%d,timeout:%d} wall_s=%.1f" % [point[0], slot, shown_offset,
		median, ", ".join(seed_text), sorted[0], sorted[sorted.size() - 1], losses["defeat"], losses["timeout"], (Time.get_ticks_msec() - started) / 1000.0])
	if losses["timeout"] > losses["defeat"]:
		print("TIMEOUT point=%s slot=%s offset=%s timeouts=%d defeats=%d" % [point[0], slot, shown_offset, losses["timeout"], losses["defeat"]])
	return {"m": median}


## The largest m this seed wins, to within one search step: sqrt(lo * hi) of the last bracket.
## ponytail: assumes a win at m means a win below m; a seed that wins above a loss just lands in one bracket.
func _break(snapshots: Array[Dictionary], zone: ZoneDefinition, squads: Array[Dictionary], seed_value: int, losses: Dictionary) -> float:
	var low: float = SEARCH_LOW
	var high: float = SEARCH_HIGH
	if _wins(snapshots, zone, squads, seed_value, high, losses):
		low = high
		while high < SEARCH_MAX:
			high *= 2.0
			if not _wins(snapshots, zone, squads, seed_value, high, losses):
				break
			low = high
		if low >= SEARCH_MAX:
			return SEARCH_MAX
	elif not _wins(snapshots, zone, squads, seed_value, low, losses):
		high = low
		while low > SEARCH_MIN:
			low /= 2.0
			if _wins(snapshots, zone, squads, seed_value, low, losses):
				break
			high = low
		if high <= SEARCH_MIN:
			return SEARCH_MIN
	for _halving: int in HALVINGS:
		var middle: float = sqrt(low * high)
		if _wins(snapshots, zone, squads, seed_value, middle, losses):
			low = middle
		else:
			high = middle
	return sqrt(low * high)


func _wins(snapshots: Array[Dictionary], zone: ZoneDefinition, squads: Array[Dictionary], seed_value: int, m: float, losses: Dictionary) -> bool:
	var status: String = _fight(snapshots, _scaled(zone, m), squads, seed_value).status
	if status == "victory":
		return true
	losses["timeout" if status == "timeout" else "defeat"] += 1
	return false


func _fight(snapshots: Array[Dictionary], zone: ZoneDefinition, squads: Array[Dictionary], seed_value: int) -> BattleState:
	var state: BattleState = BattleSimulation.create_run("presence:fight", snapshots, zone, squads, {}, {"healing": 0, "revival": 0}, seed_value)
	while state.status == "active":
		BattleSimulation.advance(state, _balance.battle_tick_seconds)
	return state


func _median(values: Array[float]) -> float:
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	var middle: int = sorted.size() >> 1
	return sorted[middle] if sorted.size() % 2 == 1 else (sorted[middle - 1] + sorted[middle]) / 2.0
