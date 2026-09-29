extends GutTest

## ig-vl1.5: the Mage's Rime Wall (SYSTEMS.md § Casters, Walls; DECISIONS.md 2026-09-25, "Casters shape
## the field", items 1, 5-6 and 9). Walking around walls is ig-0qh's (test_walls.gd).

const SIM = preload("res://combat/battle/battle_simulation.gd")
const Compare = preload("res://tests/unit/compare.gd")
const Session = preload("res://systems/game_session.gd")
const Controls = preload("res://tests/unit/test_battle_controls.gd")
## Rime Wall is 1.2 thick: its footprint grows 0.6 + 0.325 each way, and a pushed actor lands WALL_MARGIN past that.
const GROW: float = 0.925
const EDGE: float = 0.926

var WALL: AbilityDefinition = SIM.ABILITIES["mage_rime_wall"]


func before_each() -> void:
	GameSession.set("_save_deferred_depth", 1)
	GameSession.from_dict({"roster": []})
	SaveService.load_blocked = false


func after_each() -> void:
	GameSession.set("_save_deferred_depth", 0)


func test_rime_wall_loads_and_validate_knows_the_wall() -> void:
	assert_eq(WALL.validate(), "")
	assert_eq(WALL.band(), "buff")
	assert_eq([WALL.cooldown_seconds, WALL.range_units, WALL.ai_min_radius, WALL.ai_radius, WALL.ai_offset], [30.0, 8.0, 3.5, 6.0, 2.5])
	assert_eq(WALL.effects, [{"type": "wall", "seconds": 8.0, "length": 6.0, "thickness": 1.2}])
	assert_eq(SIM.BALANCE.battle_wall_cap, 3)
	assert_true(SIM.known_kit("mage", 1).has(WALL), "the Mage knows it at level 1")
	assert_false(SIM.enemy_kit("mage").has(WALL), "heroes only")
	assert_same(SIM.signature_for("mage"), SIM.ABILITIES["mage_burst"], "the signature stays")
	for broken: Array in [
		[{"seconds": 0.0}, "seconds"],
		[{"length": -6.0}, "length"],
		[{"thickness": INF}, "thickness"],
		[{"thickness": "1.2"}, "a string"],
		[{"radius": 3.0}, "an unknown field"],
	]:
		var skill: AbilityDefinition = WALL.duplicate(true)
		var effect: Dictionary = {"type": "wall", "seconds": 8.0, "length": 6.0, "thickness": 1.2}
		effect.merge(broken[0], true)
		skill.effects = [effect]
		assert_ne(skill.validate(), "", str(broken[1]))
	var missing: AbilityDefinition = WALL.duplicate(true)
	missing.effects = [{"type": "wall", "seconds": 8.0, "length": 6.0}]
	assert_ne(missing.validate(), "", "a wall needs its thickness")
	var mixed: AbilityDefinition = WALL.duplicate(true)
	mixed.effects = [{"type": "wall", "seconds": 8.0, "length": 6.0, "thickness": 1.2}, {"type": "damage", "area": "circle", "multiplier": 1.0}]
	assert_ne(mixed.validate(), "", "a wall is its skill's only effect")
	var passive: AbilityDefinition = WALL.duplicate(true)
	passive.kind = "passive"
	passive.ai_rule = "always"
	assert_ne(passive.validate(), "", "only an ability casts a wall")
	for rule: Array in [[3.5, 6.0, 0.0], [6.5, 6.0, 2.5], [3.5, 6.0, 3.5], [3.5, 6.0, -1.0]]:
		var aimed: AbilityDefinition = WALL.duplicate(true)
		aimed.ai_min_radius = rule[0]
		aimed.ai_radius = rule[1]
		aimed.ai_offset = rule[2]
		assert_ne(aimed.validate(), "", "melee_near_back_row %s" % [rule])


## SYSTEMS.md: an enemy melee actor 3.5-6 from a back-row ally gets a wall across their line, 2.5 from the
## ally. The nearest pair decides; ties go to the lower spawn index. No damage.
func test_the_ai_walls_the_nearest_melee_enemy_off_a_back_row_ally() -> void:
	var state: BattleState = _battle([
		_unit("hero:mage", "mage", "ally", Vector2(-3, 0)),
		_unit("hero:ranger", "ranger", "ally", Vector2(0, 0)),
		_unit("hero:knight", "knight", "ally", Vector2(0, -10)),
		_unit("enemy:archer", "ranger", "enemy", Vector2(4, 0)),
		_unit("enemy:a", "knight", "enemy", Vector2(0, 5)),
		_unit("enemy:b", "rogue", "enemy", Vector2(5, 0)),
		_unit("enemy:front", "knight", "enemy", Vector2(0, -12)),
	])
	var mage: BattleActor = state.actors[0]
	_give(mage, ["mage_rime_wall"])
	var hp: Array = state.actors.map(func(actor: BattleActor) -> float: return actor.hp)
	assert_true(SIM._auto_cast(state, mage, null, ["buff"], _rng()), "a and b are 5 from the Ranger; the archer is not melee")
	assert_eq(state.field_objects.size(), 1)
	var wall: Dictionary = state.field_objects[0]
	assert_eq(wall.keys(), ["id", "kind", "skill_id", "owner_actor_id", "faction", "start", "end", "thickness", "remaining_seconds"])
	assert_eq([wall["id"], wall["kind"], wall["skill_id"], wall["owner_actor_id"], wall["faction"], wall["thickness"], wall["remaining_seconds"]], ["field:1", "wall", "mage_rime_wall", mage.id, "ally", 1.2, 8.0])
	assert_almost_eq(_vector(wall["start"]).distance_to(Vector2(-3, 2.5)), 0.0, 0.0001, "a (the lower index) decides: across the Ranger-to-a line, 2.5 from the Ranger")
	assert_almost_eq(_vector(wall["end"]).distance_to(Vector2(3, 2.5)), 0.0, 0.0001)
	assert_eq(float(mage.skill_cooldowns["mage_rime_wall"]), 30.0)
	assert_eq(state.actors.map(func(actor: BattleActor) -> float: return actor.hp), hp, "no damage")

	for miss: Array in [[Vector2(0, 3.4), "under 3.5"], [Vector2(0, 6.1), "over 6"]]:
		var near: BattleState = _battle([_unit("hero:mage", "mage", "ally", Vector2(-2, -4)), _unit("hero:cleric", "cleric", "ally", Vector2(0, 0)), _unit("enemy:a", "knight", "enemy", miss[0])])
		_give(near.actors[0], ["mage_rime_wall"])
		assert_false(SIM._auto_cast(near, near.actors[0], null, ["buff"], _rng()), str(miss[1]))
	var front: BattleState = _battle([_unit("hero:mage", "mage", "ally", Vector2(-2, -4)), _unit("hero:knight", "knight", "ally", Vector2(0, 0)), _unit("enemy:a", "knight", "enemy", Vector2(0, 5))])
	_give(front.actors[0], ["mage_rime_wall"])
	assert_false(SIM._auto_cast(front, front.actors[0], null, ["buff"], _rng()), "a Knight is not back row")
	var far: BattleState = _battle([_unit("hero:mage", "mage", "ally", Vector2(-12, 0)), _unit("hero:ranger", "ranger", "ally", Vector2(0, 0)), _unit("enemy:a", "knight", "enemy", Vector2(5, 0))])
	_give(far.actors[0], ["mage_rime_wall"])
	assert_false(SIM._auto_cast(far, far.actors[0], null, ["buff"], _rng()), "its point is 14.5 away, past range 8")
	far.actors[0].position = Vector2(-5, 0)
	assert_true(SIM._auto_cast(far, far.actors[0], null, ["buff"], _rng()), "7.5 away: in range")
	assert_almost_eq(_vector(far.field_objects[0]["start"]).distance_to(Vector2(2.5, 3)), 0.0, 0.0001)


## ACC 2 and DECISIONS item 6: out across the segment to the side each stood on; one exactly on the line
## goes to the caster's side.
func test_the_cast_push_follows_the_side_rule_and_the_line_goes_to_the_caster_s_side() -> void:
	var state: BattleState = _battle([
		_unit("hero:mage", "mage", "ally", Vector2(-5, 0)),
		_unit("enemy:right", "rogue", "enemy", Vector2(0.3, 1)),
		_unit("enemy:left", "rogue", "enemy", Vector2(-0.2, -1)),
		_unit("enemy:line", "rogue", "enemy", Vector2(0, 0.5)),
		_unit("enemy:end", "rogue", "enemy", Vector2(0.5, 3.5)),
		_unit("enemy:out", "rogue", "enemy", Vector2(1.5, 0)),
	])
	var mage: BattleActor = state.actors[0]
	_give(mage, ["mage_rime_wall"])
	assert_true(SIM._use_skill(state, mage, WALL, null, Vector2.ZERO, _rng(), Vector2.RIGHT))
	assert_almost_eq(_vector(state.field_objects[0]["start"]).distance_to(Vector2(0, 3)), 0.0, 0.0001)
	_assert_at(state.actors[1], Vector2(EDGE, 1), "its own side")
	_assert_at(state.actors[2], Vector2(-EDGE, -1), "its own side")
	_assert_at(state.actors[3], Vector2(-EDGE, 0.5), "on the line: the caster's side")
	_assert_at(state.actors[4], Vector2(EDGE, 3.5), "the end's cap is footprint too; still across")
	_assert_at(state.actors[5], Vector2(1.5, 0), "outside: stays")

	var above: BattleState = _battle([_unit("hero:mage", "mage", "ally", Vector2(0, -5)), _unit("enemy:line", "rogue", "enemy", Vector2(0, 0.5))])
	_give(above.actors[0], ["mage_rime_wall"])
	assert_true(SIM._use_skill(above, above.actors[0], WALL, null, Vector2.ZERO, _rng(), Vector2.RIGHT))
	_assert_at(above.actors[1], Vector2(-EDGE, 0.5), "a caster on the line itself: the side it aimed from")


## ACC 11h: alive, downed and elite actors all go, through _wall_face (not _push, which skips the downed and
## elites); a carried body rides with its carrier; the dead and extracted stay.
func test_the_cast_push_moves_downed_and_elite_actors_and_carried_bodies_ride() -> void:
	var state: BattleState = _battle([
		_unit("hero:mage", "mage", "ally", Vector2(-5, 0)),
		_unit("hero:down", "knight", "ally", Vector2(0.4, -2), {"current_hp": 0.0, "life": "downed"}),
		_unit("hero:carrier", "knight", "ally", Vector2(-0.4, 2)),
		_unit("hero:carried", "rogue", "ally", Vector2(-0.4, 2), {"current_hp": 0.0, "life": "downed"}),
		_unit("hero:gone", "ranger", "ally", Vector2(0.2, 0)),
		_unit("enemy:elite", "knight", "enemy", Vector2(0.5, 1)),
		_unit("enemy:dead", "rogue", "enemy", Vector2(0.5, -1)),
	])
	state.actors[1].life = BattleActor.LIFE_DOWNED
	state.actors[3].life = BattleActor.LIFE_DOWNED
	state.actors[2].carrying_id = state.actors[3].id
	state.actors[3].carried_by_id = state.actors[2].id
	state.actors[4].life = BattleActor.LIFE_EXTRACTED
	state.actors[5].effect_state["elite"] = true
	state.actors[6].life = BattleActor.LIFE_DEAD
	var mage: BattleActor = state.actors[0]
	_give(mage, ["mage_rime_wall"])
	assert_true(SIM._use_skill(state, mage, WALL, null, Vector2.ZERO, _rng(), Vector2.RIGHT))
	_assert_at(state.actors[1], Vector2(EDGE, -2), "a downed body is pushed")
	_assert_at(state.actors[2], Vector2(-EDGE, 2), "the carrier")
	_assert_at(state.actors[3], Vector2(-EDGE, 2), "its body rides with it")
	_assert_at(state.actors[4], Vector2(0.2, 0), "extracted: stays")
	_assert_at(state.actors[5], Vector2(EDGE, 1), "an elite is pushed")
	_assert_at(state.actors[6], Vector2(0.5, -1), "dead: stays")


## ACC 2 (director 2026-09-25) and 11e: the AI skips a placement whose push would leave anyone in another
## wall's footprint or out of bounds, spending nothing, and tries again next tick. At the field's edge the
## push takes the far face.
func test_a_placement_that_would_leave_someone_inside_another_wall_is_skipped() -> void:
	var state: BattleState = _battle([
		_unit("hero:mage", "mage", "ally", Vector2(-3, 0)),
		_unit("hero:ranger", "ranger", "ally", Vector2(-2.5, 0)),
		_unit("enemy:a", "knight", "enemy", Vector2(2, 0)),
		_unit("enemy:b", "rogue", "enemy", Vector2(0.3, 1)),
	])
	var mage: BattleActor = state.actors[0]
	_give(mage, ["mage_rime_wall"])
	_wall(state, Vector2(1.5, -3), Vector2(1.5, 3))
	var before: Dictionary = state.to_dict()
	assert_false(SIM._auto_cast(state, mage, null, ["buff"], _rng()), "b would land at x 0.926, inside the older wall")
	assert_eq(Compare.first_difference(state.to_dict(), before), "", "nothing changed: no wall, no cooldown, no push")
	state.actors[3].position = Vector2(-0.3, 1)
	assert_true(SIM._auto_cast(state, mage, null, ["buff"], _rng()), "the next tick, b on the near side: cast")
	_assert_at(state.actors[3], Vector2(-EDGE, 1), "pushed to its own side")
	assert_eq(state.field_objects.size(), 2)

	var edge: BattleState = _battle([_unit("hero:mage", "mage", "ally", Vector2(14, 0)), _unit("enemy:a", "rogue", "enemy", Vector2(19.8, 1))])
	_give(edge.actors[0], ["mage_rime_wall"])
	assert_true(SIM._use_skill(edge, edge.actors[0], WALL, null, Vector2(19.5, 0), _rng(), Vector2.RIGHT))
	_assert_at(edge.actors[1], Vector2(19.5 - EDGE, 1), "its own face is past the bounds: the far one")
	assert_eq(SIM.validate_snapshot(edge.to_dict()), "", "and the checkpoint validates")

	var boxed: BattleState = _battle([_unit("hero:mage", "mage", "ally", Vector2(14, 0)), _unit("enemy:a", "rogue", "enemy", Vector2(19.8, 1))])
	_give(boxed.actors[0], ["mage_rime_wall"])
	_wall(boxed, Vector2(18.0, -3), Vector2(18.0, 3))
	assert_false(SIM._use_skill(boxed, boxed.actors[0], WALL, null, Vector2(19.5, 0), _rng(), Vector2.RIGHT), "no face works: refused")
	assert_eq(boxed.field_objects.size(), 1)
	assert_eq(float(boxed.actors[0].skill_cooldowns["mage_rime_wall"]), 0.0)


## ACC 11g: a wall's ends are pulled in along it to the bounds; it gets shorter and never turns.
func test_a_wall_by_the_side_edge_is_pulled_in_and_its_checkpoint_validates() -> void:
	var state: BattleState = _battle([
		_unit("hero:mage", "mage", "ally", Vector2(14, -6)),
		_unit("hero:ranger", "ranger", "ally", Vector2(19, -10)),
		_unit("enemy:a", "knight", "enemy", Vector2(17.6, -14.8)),
	])
	_give(state.actors[0], ["mage_rime_wall"])
	assert_true(SIM._auto_cast(state, state.actors[0], null, ["buff"], _rng()))
	var start: Vector2 = _vector(state.field_objects[0]["start"])
	var finish: Vector2 = _vector(state.field_objects[0]["end"])
	var way: Vector2 = (Vector2(17.6, -14.8) - Vector2(19, -10)).normalized()
	var center: Vector2 = Vector2(19, -10) + way * 2.5
	var along := Vector2(way.y, -way.x)
	assert_almost_eq(finish.distance_to(center + along * 3.0), 0.0, 0.0001, "the end inside is as cast")
	assert_almost_eq(start.x, 20.0, 0.0001, "the end past the side edge comes in to it")
	assert_almost_eq(absf((start - center).normalized().dot(along)), 1.0, 0.00001, "along the segment: the wall never turns")
	assert_lt(start.distance_to(finish), 6.0, "so it is shorter")
	assert_eq(SIM.validate_snapshot(state.to_dict()), "", "the checkpoint validates")


## ACC 11d: a cut move stops WALL_MARGIN outside a footprint; one within WALL_MARGIN of the bounds would put
## the mover outside them, so the cut is clamped.
func test_a_cut_at_the_bounds_stays_inside_them() -> void:
	var state: BattleState = _battle([
		_unit("hero:k", "knight", "ally", Vector2(-10, 0)),
		_unit("enemy:a", "rogue", "enemy", Vector2(19.9998, 0)),
	])
	# Its footprint's long edge sits at x 19.9995, so the cut's face is at 20.0005.
	_wall(state, Vector2(19.0745, -3), Vector2(19.0745, 3))
	var enemy: BattleActor = state.actors[1]
	SIM._push(state, enemy, Vector2.LEFT, Vector2.RIGHT, 3.0)
	assert_lte(enemy.position.x, 20.0, "inside the bounds")
	assert_gt(enemy.position.x, 19.99, "stopped at the wall's edge")
	assert_eq(SIM.validate_snapshot(state.to_dict()), "", "the state validates")


## ACC 11e: an actor inside a footprint (a legacy checkpoint) walks out across its own side, unless that face
## is out of bounds: then the far one.
func test_one_inside_a_wall_at_the_field_s_edge_walks_out_the_far_side() -> void:
	var state: BattleState = _battle([
		_unit("hero:k", "knight", "ally", Vector2(19.8, 0)),
		_unit("enemy:far", "rogue", "enemy", Vector2(-15, 15)),
	])
	_wall(state, Vector2(19.5, -3), Vector2(19.5, 3))
	var knight: BattleActor = state.actors[0]
	knight.order_kind = SIM.COMMAND_MOVE
	knight.order_point = Vector2(19.8, 10)
	var lowest: float = INF
	for tick: int in 100:
		SIM._move_actors(state)
		lowest = minf(lowest, knight.position.x)
		assert_lte(knight.position.x, 20.0)
	assert_lt(lowest, 19.5 - GROW, "out through the far face")
	assert_false(absf(knight.position.x - 19.5) < GROW and absf(knight.position.y) < 3.0 + GROW, "and outside the footprint at %s" % knight.position)


## ACC 3: a wall keeps two actors on its two faces 1.852 apart, past the 1.6 melee reach, so neither's basic
## melee attack reaches; a ranged attack goes over, and an area skill reaches across (the ADR's item 2).
func test_across_a_wall_melee_can_t_reach_but_ranged_and_area_skills_do() -> void:
	var state: BattleState = _battle([
		_unit("hero:mage", "mage", "ally", Vector2(-5, 0)),
		_unit("hero:k", "knight", "ally", Vector2(-0.3, 0)),
		_unit("hero:ranger", "ranger", "ally", Vector2(-6, 1)),
		_unit("enemy:a", "rogue", "enemy", Vector2(0.3, 0)),
	])
	_give(state.actors[0], ["mage_rime_wall"])
	var knight: BattleActor = state.actors[1]
	var ranger: BattleActor = state.actors[2]
	var enemy: BattleActor = state.actors[3]
	assert_true(SIM._use_skill(state, state.actors[0], WALL, null, Vector2.ZERO, _rng(), Vector2.RIGHT))
	assert_almost_eq(knight.position.distance_to(enemy.position), 2.0 * EDGE, 0.0001)
	for pair: Array in [[knight, enemy], [enemy, knight]]:
		(pair[0] as BattleActor).order_kind = SIM.COMMAND_ATTACK
		(pair[0] as BattleActor).order_target_id = (pair[1] as BattleActor).id
		assert_gt((pair[0] as BattleActor).position.distance_to((pair[1] as BattleActor).position), SIM.BALANCE.battle_melee_range)
		assert_null(SIM._in_range_target(state, pair[0]), "%s can't swing through it" % (pair[0] as BattleActor).id)
	ranger.order_kind = SIM.COMMAND_ATTACK
	ranger.order_target_id = enemy.id
	assert_same(SIM._in_range_target(state, ranger), enemy, "a ranged attack goes over")
	_give(knight, ["knight_ground_slam"])
	knight.effect_state["last_skill_id"] = "knight_charge"
	knight.effect_state["last_skill_tick"] = state.tick
	var hp: float = enemy.hp
	assert_true(SIM._use_skill(state, knight, SIM.ABILITIES["knight_ground_slam"], enemy, knight.position, _rng()))
	assert_lt(enemy.hp, hp, "Ground Slam's 2.5 radius reaches across")


## ACC 12, the hand rule: across the caster-to-aim line, centered on the aim; a clicked unit ends on the far
## side; a cast the AI would skip is refused and spends no cooldown.
func test_a_hand_cast_walls_off_a_clicked_unit_or_centers_on_the_ground_point() -> void:
	var state: BattleState = _battle([
		_unit("hero:mage", "mage", "ally", Vector2(-5, 0)),
		_unit("enemy:a", "knight", "enemy", Vector2(1, 0)),
	])
	var mage: BattleActor = state.actors[0]
	var enemy: BattleActor = state.actors[1]
	_give(mage, ["mage_rime_wall"])
	var result: Dictionary = SIM.issue_command(state, {"kind": SIM.COMMAND_ABILITY, "actor_ids": [mage.id], "target_id": enemy.id})
	assert_true(bool(result["accepted"]), str(result))
	var wall: Dictionary = state.field_objects[0]
	var middle: Vector2 = (_vector(wall["start"]) + _vector(wall["end"])) * 0.5
	assert_almost_eq(middle.distance_to(Vector2(1.0 - EDGE, 0)), 0.0, 0.0001, "the clicked unit's point, moved 0.926 toward the caster")
	assert_almost_eq(absf(_vector(wall["start"]).x - _vector(wall["end"]).x), 0.0, 0.0001, "across the caster-to-unit line")
	assert_gt(enemy.position.x, middle.x + GROW, "the enemy is on the far side")
	assert_eq(enemy.position, Vector2(1, 0), "not pushed")
	assert_lt(mage.position.x, middle.x, "the caster on the near side")
	assert_eq(float(mage.skill_cooldowns["mage_rime_wall"]), 30.0)

	mage.skill_cooldowns["mage_rime_wall"] = 0.0
	mage.ability_lock = 0.0
	result = SIM.issue_command(state, {"kind": SIM.COMMAND_ABILITY, "actor_ids": [mage.id], "point": [-5.0, 6.0]})
	assert_true(bool(result["accepted"]), str(result))
	wall = state.field_objects[1]
	assert_almost_eq(((_vector(wall["start"]) + _vector(wall["end"])) * 0.5).distance_to(Vector2(-5, 6)), 0.0, 0.0001, "a ground cast centers on the point")
	assert_almost_eq(absf(_vector(wall["start"]).y - _vector(wall["end"]).y), 0.0, 0.0001, "across the caster-to-point line")

	mage.skill_cooldowns["mage_rime_wall"] = 0.0
	mage.ability_lock = 0.0
	mage.facing = Vector2.UP
	result = SIM.issue_command(state, {"kind": SIM.COMMAND_ABILITY, "actor_ids": [mage.id], "target_id": mage.id})
	assert_true(bool(result["accepted"]), str(result))
	wall = state.field_objects[2]
	assert_almost_eq(((_vector(wall["start"]) + _vector(wall["end"])) * 0.5).distance_to(Vector2(-5, 0)), 0.0, 0.0001, "an aim on itself: at its feet")
	assert_almost_eq(absf(_vector(wall["start"]).y - _vector(wall["end"]).y), 0.0, 0.0001, "across its facing")
	assert_almost_eq(mage.position.distance_to(Vector2(-5, EDGE)), 0.0, 0.0001, "the caster on its line goes back, away from its facing")

	mage.skill_cooldowns["mage_rime_wall"] = 0.0
	mage.ability_lock = 0.0
	var before: Dictionary = state.to_dict()
	result = SIM.issue_command(state, {"kind": SIM.COMMAND_ABILITY, "actor_ids": [mage.id], "point": [-5.0, 1.5]})
	assert_false(bool(result["accepted"]), "the caster would be pushed into its own last wall: refused")
	assert_eq(Compare.first_difference(state.to_dict(), before), "", "no cooldown spent, nothing moved")
	result = SIM.issue_command(state, {"kind": SIM.COMMAND_ABILITY, "actor_ids": [mage.id], "point": [5.0, 0.0]})
	assert_false(bool(result["accepted"]), "10 away: out of range")


## ACC 11a: at a cast the oldest wall ends while there are battle_wall_cap, then the oldest object while
## there are battle_field_object_cap.
func test_a_fourth_wall_ends_the_oldest_wall_and_a_full_field_its_oldest_object() -> void:
	var state: BattleState = _battle([
		_unit("hero:mage", "mage", "ally", Vector2(-5, 0)),
		_unit("enemy:a", "rogue", "enemy", Vector2(15, 15)),
	])
	var mage: BattleActor = state.actors[0]
	_give(mage, ["mage_rime_wall", "mage_rime_circle"])
	for kind: String in ["zone", "zone", "zone", "zone", "zone", "zone", "wall", "wall"]:
		_cast(state, mage, kind)
	assert_eq(state.field_objects.size(), SIM.BALANCE.battle_field_object_cap)
	_cast(state, mage, "wall")
	var zones: Array = ["field:2 zone", "field:3 zone", "field:4 zone", "field:5 zone", "field:6 zone"]
	assert_eq(_ids(state), zones + ["field:7 wall", "field:8 wall", "field:9 wall"], "two walls and a full field: the oldest object ends")
	_cast(state, mage, "wall")
	assert_eq(_ids(state), zones + ["field:8 wall", "field:9 wall", "field:10 wall"], "three walls: the oldest wall ends, not a zone")


## ACC 10 and 11a: over the caps on load, walls first then the total, oldest first, instead of rejecting the
## checkpoint. The ids still sit at or below field_sequence.
func test_a_checkpoint_over_the_caps_loads_trimmed_walls_first() -> void:
	var state: BattleState = _battle([
		_unit("hero:mage", "mage", "ally", Vector2(-5, 0)),
		_unit("enemy:a", "rogue", "enemy", Vector2(15, 15)),
	])
	var data: Dictionary = state.to_dict()
	var fields: Array = []
	var names: Array[String] = ["Z1", "W1", "W2", "W3", "W4", "Z2", "Z3", "Z4", "Z5"]
	for index: int in names.size():
		fields.append(_field(names[index], index + 1, state.actors[0].id))
	data["field_objects"] = fields
	data["field_sequence"] = fields.size()
	assert_eq(SIM.validate_snapshot(Compare.json_round_trip(data)), "", "over the caps is not an error")
	assert_eq(_names(BattleState.from_dict(Compare.json_round_trip(data)), names), ["Z1", "W2", "W3", "W4", "Z2", "Z3", "Z4", "Z5"], "only W1 goes: walls first")

	var zones: Array = []
	names.clear()
	for index: int in SIM.BALANCE.battle_field_object_cap + 1:
		names.append("Z%d" % (index + 1))
		zones.append(_field(names[index], index + 1, state.actors[0].id))
	data["field_objects"] = zones
	data["field_sequence"] = zones.size()
	assert_eq(SIM.validate_snapshot(Compare.json_round_trip(data)), "", "cap + 1 zones load")
	assert_eq(_names(BattleState.from_dict(Compare.json_round_trip(data)), names), ["Z2", "Z3", "Z4", "Z5", "Z6", "Z7", "Z8", "Z9"], "the newest cap of them")
	data["field_sequence"] = zones.size() - 1
	assert_ne(SIM.validate_snapshot(Compare.json_round_trip(data)), "", "an id past field_sequence is still rejected")
	data["field_sequence"] = zones.size()
	(zones[0] as Dictionary)["radius"] = 41.0
	assert_ne(SIM.validate_snapshot(Compare.json_round_trip(data)), "", "a zone radius over 2 x the bounds is rejected (the view's float32 ring)")
	(zones[0] as Dictionary)["radius"] = 40.0
	assert_eq(SIM.validate_snapshot(Compare.json_round_trip(data)), "", "2 x the bounds loads")


## ACC 4: Rime Wall's lifetime counts down in ig-85w's tick-exact form: 8 s x pace 6 = 48 s ends on tick 480.
func test_at_pace_six_the_wall_lasts_48_s_to_the_tick_and_its_cooldown_180_s() -> void:
	var state: BattleState = _battle([
		_unit("hero:mage", "mage", "ally", Vector2(-5, 0)),
		_unit("enemy:a", "rogue", "enemy", Vector2(15, 15)),
	], 6)
	var mage: BattleActor = state.actors[0]
	_give(mage, ["mage_rime_wall"])
	assert_true(SIM._use_skill(state, mage, WALL, null, Vector2.ZERO, _rng(), Vector2.RIGHT))
	assert_eq(float(state.field_objects[0]["remaining_seconds"]), 48.0)
	assert_eq(float(mage.skill_cooldowns["mage_rime_wall"]), 180.0)
	for tick: int in 479:
		SIM._update_field_objects(state)
	assert_eq(state.field_objects.size(), 1, "up through tick 479")
	SIM._update_field_objects(state)
	assert_true(state.field_objects.is_empty(), "ends on tick 480")


## ACC 4: a real save mid-wall, through disk, reloads exactly and fights on as the unbroken run; a legacy
## checkpoint loads.
func test_a_mid_wall_save_through_disk_reloads_exactly_and_fights_on_as_the_unbroken_run() -> void:
	GameSession.cleared_zone_ids[&"verdant_outskirts"] = true
	var ids: Array[String] = []
	for archetype: StringName in [&"knight", &"mage", &"ranger", &"mage", &"cleric"]:
		var hero := Hero.new("Rimer %d" % ids.size(), 7)
		hero.def_id = archetype
		hero.level = 20
		hero.instance_id = "hero:rime:%d" % ids.size()
		GameSession.roster.append(hero)
		ids.append(hero.instance_id)
	var preset_id: String = GameSession.save_team_preset("", "Rime", ids, "ashfall_reaches")
	var order_id: String = GameSession.dispatch_force([preset_id], "ashfall_reaches", 1, {}, {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0})
	assert_ne(order_id, "", GameSession.last_action_error)
	var seeded: Dictionary = Compare.json_round_trip(GameSession.to_dict())
	_battle_of(seeded)["rng_state"] = "1"
	GameSession.from_dict(seeded)
	var waited: int = 0
	while not _has_rime_wall(GameSession.get_battle_snapshot(order_id)) and waited < 240:
		GameSession.tick_expeditions(1.0)
		waited += 1
	assert_true(_has_rime_wall(GameSession.get_battle_snapshot(order_id)), "the AI cast a Rime Wall by %d s" % waited)
	assert_eq(str(GameSession.get_battle_snapshot(order_id)["status"]), "active")
	_save_to_disk()
	var first: Dictionary = GameSession.to_dict()
	var want: Dictionary = Compare.json_round_trip(first)
	for _second: int in 8:
		GameSession.tick_expeditions(1.0)
	var straight: Array = _where(GameSession.get_battle_snapshot(order_id))

	GameSession.from_dict({"roster": []})
	assert_true(SaveService.load_game(), SaveService.load_block_reason)
	var got: Dictionary = GameSession.to_dict()
	got.erase("saved_at_unix")
	want.erase("saved_at_unix")
	assert_eq(Compare.first_difference(got, want), "", "the reload is the round trip")
	for _second: int in 8:
		GameSession.tick_expeditions(1.0)
	assert_eq(Compare.mismatch(_where(GameSession.get_battle_snapshot(order_id)), straight), "", "and fights on as the unbroken run")

	var legacy: Dictionary = Compare.json_round_trip(first)
	_battle_of(legacy).erase("field_objects")
	_battle_of(legacy).erase("field_sequence")
	assert_eq(Session.validate_saved_state(legacy, 3), "", "a checkpoint from before walls loads")
	assert_true(BattleState.from_dict(_battle_of(legacy)).field_objects.is_empty(), "with none")


## ACC 11b: the view draws a wall by its kind, a box over its segment from its own keys, never its skill
## (a known skill and an unknown one both draw), and drops it when the wall ends.
func test_the_view_draws_each_wall_as_a_box_at_its_midpoint_known_skill_or_not() -> void:
	var helper: Controls = Controls.new()
	var controller: Controls.FakeBattleController = helper._make_controller()
	helper.free()
	controller.snapshots["battle-1"]["field_objects"] = [
		{"id": "field:1", "kind": "wall", "skill_id": "mage_rime_wall", "owner_actor_id": "hero-1", "faction": "ally", "start": [0.0, -3.0], "end": [0.0, 3.0], "thickness": 1.2, "remaining_seconds": 5.0},
		{"id": "field:2", "kind": "wall", "skill_id": "mage_meteor_wall", "owner_actor_id": "hero-1", "faction": "ally", "start": [2.0, 4.0], "end": [8.0, 4.0], "thickness": 1.2, "remaining_seconds": 5.0},
	]
	controller.snapshots["battle-1"]["field_sequence"] = 2
	add_child_autofree(controller)
	var view: BattleView = (load("res://combat/battle/battle_view.tscn") as PackedScene).instantiate() as BattleView
	view.configure_live("battle-1", controller)
	add_child_autofree(view)
	await wait_process_frames(2)
	assert_eq(view._field_views.keys(), ["field:1", "field:2"])
	for check: Array in [["field:1", Vector3(0.0, 0.0, 0.0)], ["field:2", Vector3(5.0, 0.0, 4.0)]]:
		var shape: MeshInstance3D = view._field_views[check[0]]
		assert_true(shape.mesh is BoxMesh, "%s draws a box, not a ring" % check[0])
		assert_almost_eq(Vector2(shape.position.x, shape.position.z).distance_to(Vector2(check[1].x, check[1].z)), 0.0, 0.0001, "%s at its midpoint" % check[0])
		assert_almost_eq((shape.mesh as BoxMesh).size.x, 6.0, 0.0001, "its length")
		assert_almost_eq((shape.mesh as BoxMesh).size.z, 1.2, 0.0001, "its thickness")
	var along: Vector3 = view._field_views["field:1"].global_transform.basis.x.normalized()
	assert_almost_eq(absf(along.z), 1.0, 0.0001, "turned to its segment (sim y is the view's z)")
	view._snapshot["field_objects"] = [view._snapshot["field_objects"][1]]
	view._update_field_views()
	assert_eq(view._field_views.keys(), ["field:2"], "an ended wall is dropped")


func _cast(state: BattleState, mage: BattleActor, kind: String) -> void:
	mage.skill_cooldowns.clear()
	mage.ability_lock = 0.0
	if kind == "wall":
		assert_true(SIM._use_skill(state, mage, WALL, null, Vector2(-5, 5), _rng(), Vector2.UP))
	else:
		assert_true(SIM._use_skill(state, mage, SIM.ABILITIES["mage_rime_circle"], state.actors[1], Vector2(-1, 0), _rng()))


func _ids(state: BattleState) -> Array:
	return state.field_objects.map(func(field: Dictionary) -> String: return "%s %s" % [field["id"], field["kind"]])


## A saved field object, id field:<number>: a wall for a name "W...", else a zone.
func _field(field_name: String, number: int, owner_id: String) -> Dictionary:
	if field_name.begins_with("W"):
		return {"id": "field:%d" % number, "kind": "wall", "skill_id": "mage_rime_wall", "owner_actor_id": owner_id, "faction": "ally", "start": [float(number), -3.0], "end": [float(number), 3.0], "thickness": 1.2, "remaining_seconds": float(number)}
	return {"id": "field:%d" % number, "kind": "zone", "skill_id": "mage_rime_circle", "owner_actor_id": owner_id, "faction": "ally", "center": [0.0, 0.0], "radius": 3.0, "remaining_seconds": float(number), "atk": 10.0, "heal_scale": 1.0}


## The names the kept objects were built with (field:<n> is names[n - 1]).
func _names(state: BattleState, names: Array[String]) -> Array:
	return state.field_objects.map(func(field: Dictionary) -> String: return names[str(field["id"]).trim_prefix("field:").to_int() - 1])


func _has_rime_wall(snapshot: Dictionary) -> bool:
	for field: Dictionary in snapshot.get("field_objects", []):
		if str(field["skill_id"]) == "mage_rime_wall":
			return true
	return false


func _assert_at(actor: BattleActor, want: Vector2, why: String) -> void:
	assert_almost_eq(actor.position.distance_to(want), 0.0, 0.0001, "%s: %s at %s" % [actor.id, why, actor.position])


func _wall(state: BattleState, start: Vector2, finish: Vector2, seconds: float = 60.0) -> void:
	state.field_sequence += 1
	state.field_objects.append({
		"id": "field:%d" % state.field_sequence,
		"kind": "wall",
		"skill_id": "test_wall",
		"owner_actor_id": state.actors[0].id,
		"faction": "ally",
		"start": [start.x, start.y],
		"end": [finish.x, finish.y],
		"thickness": 1.2,
		"remaining_seconds": seconds,
	})


func _vector(value: Variant) -> Vector2:
	return Vector2(float((value as Array)[0]), float((value as Array)[1]))


## A real SaveService write, stamped ahead so the reload adds no offline time.
func _save_to_disk() -> void:
	GameSession.set("_save_deferred_depth", 0)
	var saved: bool = SaveService.save()
	GameSession.set("_save_deferred_depth", 1)
	assert_true(saved, SaveService.last_write_error)
	var on_disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveService.SAVE_PATH)) as Dictionary
	on_disk["saved_at_unix"] = Time.get_unix_time_from_system() + 3600.0
	var file: FileAccess = FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(on_disk, "	", true, true))
	file.close()


func _battle_of(profile: Dictionary) -> Dictionary:
	return ((profile["expedition_orders"] as Array)[0] as Dictionary)["battle"] as Dictionary


## The exact facts first (walls included), then each actor's floats.
func _where(snapshot: Dictionary) -> Array:
	var result: Array = []
	var fields: String = str((snapshot["field_objects"] as Array).map(func(field: Dictionary) -> String: return "%s %s" % [field["id"], field["skill_id"]]))
	for actor: Dictionary in snapshot["actors"]:
		result.append(["%s %s %s %d %s" % [snapshot["rng_state"], actor["id"], actor["life"], int(snapshot["tick"]), fields], float(actor["hp"]), float(actor["position"][0]), float(actor["position"][1])])
	return result


func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	return rng


func _unit(id: String, archetype: String, faction: String, position: Vector2, extra: Dictionary = {}) -> Dictionary:
	var snapshot: Dictionary = {"archetype": archetype, "faction": faction, "hp": 100.0, "atk": 10.0, "defense": 0.0, "speed": 100.0, "crit_rate": 0.0, "crit_damage": 1.5, "position": [position.x, position.y]}
	if faction == "ally":
		snapshot["hero_id"] = id
		snapshot["squad_id"] = "s"
	else:
		snapshot["id"] = id
		snapshot["squad_id"] = ""
	snapshot.merge(extra, true)
	return snapshot


## No zone spawns (the enemies come in the list), Auto Battle off, empty kits.
func _battle(snapshots: Array[Dictionary], pace: int = 1) -> BattleState:
	var hero_ids: Array = snapshots.filter(func(snapshot: Dictionary) -> bool: return snapshot["faction"] == "ally").map(func(snapshot: Dictionary) -> String: return snapshot["hero_id"])
	var squads: Array[Dictionary] = [{"id": "s", "name": "S", "hero_ids": hero_ids, "stance": "stay_together", "guard_target_id": ""}]
	var state: BattleState = SIM.create_run("rime:1", snapshots, ZoneDefinition.definition_for(&"verdant_outskirts"), squads, {"auto_battle": false}, {"healing": 0, "revival": 0}, 7, "rescue", pace)
	for actor: BattleActor in state.actors:
		_give(actor, [])
	return state


func _give(actor: BattleActor, skill_ids: Array) -> void:
	actor.skills.clear()
	actor.skill_cooldowns.clear()
	for skill_id: String in skill_ids:
		actor.add_skill(SIM.ABILITIES[skill_id])
