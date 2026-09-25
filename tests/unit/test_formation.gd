extends GutTest
## ig-uu7.1 Formation (SYSTEMS.md § Hero AI on auto): before contact, the back row waits behind the front line.

const BALANCE: BalanceTable = preload("res://balance.tres")
const PARTY: Array[String] = ["knight", "knight", "ranger", "mage", "cleric"]
## Rows, SYSTEMS.md § Archetypes. Kept here too so this file also runs on the code before the rule.
const FRONT_ROW: Array[String] = ["knight", "rogue"]
const BACK_ROW: Array[String] = ["ranger", "mage", "cleric"]
## Tick-by-tick positions from before ig-uu7.1, for squads the rule must leave alone. A legit movement
## change elsewhere moves these too: re-run this file on the old code and paste its printed digests.
## ig-uu7.3 kiting changed the ranger,mage,cleric/advance digest (.agent-results/ig-uu7.3/nokite.log
## shows all 4 old digests come back with kiting off). ig-9gf's reach fix then changed all four on
## purpose: approaches stop inside a reach instead of parking a float32 hair outside it. With the fix
## off, this file printed the previous four (.agent-results/ig-9gf/formation_fix_off.log). ig-el4's
## enemy retune (atk budget 0.04 -> 0.03, hp 1.0 -> 1.15) changed the two three-hero fights on purpose;
## the two party fights kept theirs. ig-36y's knockback (Threadneedle and Arcane Bloom push what they
## hit) changed the same two on purpose; the party fights kept theirs. ig-7sn.13: the sim now reads the
## zone it was handed; before, _update_objectives and _spawn_group re-loaded the disk zone by id, so this
## file's hand-built zone mixed with real verdant's waves and counts. The two three-hero fights changed;
## the party fights kept theirs (.agent-results/ig-7sn.13/formation_zone_off.log prints the previous four).
const UNCHANGED_DIGESTS: Dictionary = {
	"knight,knight,ranger,mage,cleric/defend": "63e17ddd770cd8024451c6076ec5a466",
	"knight,knight,ranger,mage,cleric/protect": "a737f9c6949ac597424114ec073eae52",
	"ranger,mage,cleric/advance": "f385dbf9345d4723baf4eec9fa9bbdcb",
	"ranger,mage,cleric/stay_together": "52258601a2d48f5bc15f67b9832775ce",
}


func test_the_back_row_stays_behind_the_front_line_until_contact() -> void:
	for stance: String in ["advance", "stay_together"]:
		var state: BattleState = _run(PARTY, stance)
		var locked: Array[BattleActor] = []
		var passed_front: bool = false
		for _tick: int in int(60.0 / BALANCE.battle_tick_seconds):
			var before: Dictionary = {}
			for hero: BattleActor in _allies(state):
				if hero.archetype in BACK_ROW and not _in_contact(state, hero) and not _regrouping(state, hero, stance):
					var reference: Vector2 = _reference(state, hero, stance)
					before[hero] = [reference, hero.position.distance_to(reference), _front_distance(state, hero, reference)]
			BattleSimulation.advance(state, BALANCE.battle_tick_seconds)
			for hero: BattleActor in before:
				var reference: Vector2 = before[hero][0]
				var floor_distance: float = float(before[hero][2]) + BALANCE.battle_formation_spacing - 0.001
				# Its own step: where its order sends it. Separation may still nudge a holding hero a hair.
				var goal: float = hero.order_point.distance_to(reference)
				if hero.order_kind != BattleSimulation.COMMAND_HOLD and goal < float(before[hero][1]) and goal < floor_distance:
					passed_front = true
					fail_test("%s: %s was sent to %.3f from its reference, inside %.3f" % [stance, hero.archetype, goal, floor_distance])
				# Where it ends the tick: it never comes closer and ends up in front of the front line, nudge
				# or not. (The spawn row is level, so a hero may start a hair ahead and hold there.)
				var now: float = hero.position.distance_to(reference)
				if now < float(before[hero][1]) and now < _front_distance(state, hero, reference):
					passed_front = true
					fail_test("%s: %s ended at %.3f from its reference, ahead of the front line" % [stance, hero.archetype, now])
			locked = _locked_on(state)
			if passed_front or not locked.is_empty():
				break
		assert_false(locked.is_empty(), stance)
		for hero: BattleActor in locked:
			assert_eq(hero.archetype, "knight", "%s: every first enemy lock-on" % stance)


func test_stay_together_with_a_back_row_leader_reaches_contact() -> void:
	var state: BattleState = _run(["mage", "knight", "knight", "ranger", "cleric"], "stay_together")
	var locked: Array[BattleActor] = []
	for _tick: int in int(state.max_seconds / BALANCE.battle_tick_seconds):
		BattleSimulation.advance(state, BALANCE.battle_tick_seconds)
		locked = _locked_on(state)
		if not locked.is_empty():
			break
	assert_false(locked.is_empty(), "no stall")
	assert_eq(state.status, "active")


func test_squads_the_rule_leaves_alone_move_exactly_as_before() -> void:
	var digests: Dictionary = {}
	for setup: Array in [[["ranger", "mage", "cleric"], "advance"], [["ranger", "mage", "cleric"], "stay_together"], [PARTY, "defend"], [PARTY, "protect"]]:
		var state: BattleState = _run(setup[0], setup[1])
		# Every position's exact bits, every tick.
		var trace := PackedVector2Array()
		for _tick: int in 400:
			BattleSimulation.advance(state, BALANCE.battle_tick_seconds)
			for actor: BattleActor in state.actors:
				trace.append(actor.position)
		var key: String = "%s/%s" % [",".join(setup[0]), setup[1]]
		var hashing := HashingContext.new()
		hashing.start(HashingContext.HASH_MD5)
		hashing.update(trace.to_byte_array())
		digests[key] = hashing.finish().hex_encode()
	gut.p("UNCHANGED DIGESTS: %s" % JSON.stringify(digests))
	assert_eq(digests, UNCHANGED_DIGESTS)


func test_a_direct_move_on_a_back_row_hero_ignores_the_rule() -> void:
	var state: BattleState = _run(PARTY, "advance")
	var mage: BattleActor = _allies(state)[3]
	var point := Vector2(3.0, -6.0)
	var result: Dictionary = BattleSimulation.issue_command(state, {"kind": BattleSimulation.COMMAND_MOVE, "actor_ids": [mage.id], "point": [point.x, point.y]})
	assert_true(bool(result.get("accepted", false)), str(result))
	for _tick: int in int(10.0 / BALANCE.battle_tick_seconds):
		BattleSimulation.advance(state, BALANCE.battle_tick_seconds)
		if mage.order_kind != BattleSimulation.COMMAND_MOVE or not bool(mage.effect_state.get("direct_order", false)):
			break
	assert_lte(mage.position.distance_to(point), 0.01, "it walked all the way")
	var enemy: BattleActor = BattleSimulation._nearest_actor(state, mage, "enemy", BattleActor.LIFE_ALIVE)
	for knight: BattleActor in _allies(state).slice(0, 2):
		assert_lt(mage.position.distance_to(enemy.position), knight.position.distance_to(enemy.position), "ahead of %s" % knight.id)


## Not a gate (CODING_RULES § Performance): the worst case is frontier_march, 50 heroes against 30,
## on the march, when every back-row hero runs the rule's pass over all 80 actors.
func test_cost_at_frontier_march_50_v_30() -> void:
	var heroes: Array[Dictionary] = []
	var squads: Array[Dictionary] = []
	for squad_index: int in 10:
		var ids: Array[String] = []
		for slot: int in PARTY.size():
			var id: String = "hero:%d:%d" % [squad_index, slot]
			ids.append(id)
			heroes.append({"hero_id": id, "archetype": PARTY[slot], "hp": 400.0, "atk": 50.0, "defense": 20.0, "speed": 100.0,
				"crit_rate": 0.0, "crit_damage": 1.5, "squad_id": "squad:%d" % squad_index})
		squads.append({"id": "squad:%d" % squad_index, "name": "S%d" % squad_index, "hero_ids": ids, "stance": "advance", "guard_target_id": ""})
	var state: BattleState = BattleSimulation.create_run("order:uu71perf", heroes, ZoneDefinition.definition_for(&"frontier_march"), squads, {}, {"healing": 0, "revival": 0}, 11)
	assert_eq(state.actors.size(), 80)
	var runs: Array[int] = []
	for _run: int in 7:
		var started: int = Time.get_ticks_usec()
		BattleSimulation.advance(state, BALANCE.battle_tick_seconds)
		runs.append(Time.get_ticks_usec() - started)
	gut.p("FORMATION TICK COST: frontier_march 50v30, one tick, best %.3f ms, worst %.3f ms of 7" % [runs.min() / 1000.0, runs.max() / 1000.0])


## The rule's reference point, as SYSTEMS.md states it: the attack target, else the objective.
func _reference(state: BattleState, hero: BattleActor, stance: String) -> Vector2:
	var target: BattleActor = null
	if stance == "advance":
		target = BattleSimulation._nearest_actor(state, hero, "enemy", BattleActor.LIFE_ALIVE)
	else:
		var leader: BattleActor = BattleSimulation._squad_leader(state, hero.squad_id)
		target = BattleSimulation._nearest_enemy_near_point(state, hero.position, leader.position, BALANCE.battle_cohesion_wait_distance)
	return target.position if target != null else Vector2(0.0, 8.0)


## Stay Together's regroup walk to its leader comes before the rule and is exempt by design (ig-uu7.1 design, WHERE).
func _regrouping(state: BattleState, hero: BattleActor, stance: String) -> bool:
	var leader: BattleActor = BattleSimulation._squad_leader(state, hero.squad_id)
	return stance == "stay_together" and hero != leader and hero.position.distance_to(leader.position) > BALANCE.battle_cohesion_regroup_distance


func _front_distance(state: BattleState, hero: BattleActor, reference: Vector2) -> float:
	var nearest: float = INF
	for ally: BattleActor in _allies(state):
		if ally.life == BattleActor.LIFE_ALIVE and ally.archetype in FRONT_ROW:
			nearest = minf(nearest, ally.position.distance_to(reference))
	return nearest


func _in_contact(state: BattleState, hero: BattleActor) -> bool:
	for actor: BattleActor in state.actors:
		if actor.faction == "enemy" and actor.life == BattleActor.LIFE_ALIVE and actor.position.distance_to(hero.position) <= maxf(BALANCE.battle_detection_range, hero.attack_range):
			return true
	return false


## Every hero an enemy has locked onto.
func _locked_on(state: BattleState) -> Array[BattleActor]:
	var locked: Array[BattleActor] = []
	for actor: BattleActor in state.actors:
		if actor.faction == "enemy" and not actor.order_target_id.is_empty():
			locked.append(BattleSimulation._actor_by_id(state, actor.order_target_id))
	return locked


## Front row slow, back row fast: without the rule the back row arrives first.
func _run(archetypes: Array, stance: String) -> BattleState:
	var heroes: Array[Dictionary] = []
	var ids: Array[String] = []
	for index: int in archetypes.size():
		var id: String = "hero:%d" % index
		ids.append(id)
		var speed: float = 20.0 if archetypes[index] in FRONT_ROW else 200.0
		heroes.append({"hero_id": id, "archetype": archetypes[index], "hp": 400.0, "atk": 50.0, "defense": 20.0, "speed": speed,
			"crit_rate": 0.0, "crit_damage": 1.5, "squad_id": "squad:0"})
	var squads: Array[Dictionary] = [{"id": "squad:0", "name": "Alpha", "hero_ids": ids, "stance": stance, "guard_target_id": ""}]
	return BattleSimulation.create_run("order:uu71", heroes, _zone(), squads, {}, {"healing": 0, "revival": 0}, 11)


func _allies(state: BattleState) -> Array[BattleActor]:
	var allies: Array[BattleActor] = []
	for actor: BattleActor in state.actors:
		if actor.faction == "ally":
			allies.append(actor)
	return allies


func _zone() -> ZoneDefinition:
	var zone := ZoneDefinition.new()
	zone.zone_id = &"verdant_outskirts"
	zone.recommended_power = 20
	zone.trash_wave_count = 1
	zone.trash_wave_start_fraction = 0.9
	zone.trash_wave_end_fraction = 0.9
	zone.boss_fraction = 1.0
	zone.reference_force_size = 1
	zone.trash_enemy_count = 3
	zone.max_battle_seconds = 120.0
	zone.exit_position = Vector2(0, -16)
	return zone
