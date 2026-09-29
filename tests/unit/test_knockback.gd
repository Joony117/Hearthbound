extends GutTest

## ig-36y: real knockback (SYSTEMS.md § Knockback). A qualifying hit moves its living, non-elite
## target at once, away from the hit, and draws no RNG.

const SIM = preload("res://combat/battle/battle_simulation.gd")
const Compare = preload("res://tests/unit/compare.gd")
const Session = preload("res://systems/game_session.gd")
var PUSH: float = SIM.BALANCE.battle_crit_push_units
var GATE: int = SIM.BALANCE.battle_crit_push_gate_ticks


func before_each() -> void:
	GameSession.set("_save_deferred_depth", 1)
	GameSession.from_dict({"roster": []})
	SaveService.load_blocked = false


func after_each() -> void:
	GameSession.set("_save_deferred_depth", 0)


func test_a_basic_crit_pushes_away_from_the_attacker_and_a_plain_hit_does_not() -> void:
	var state: BattleState = _battle([_unit("hero:k", "knight", "ally", Vector2(0, 0), {"crit_rate": 1.0}), _unit("enemy:1", "knight", "enemy", Vector2(1, 0))])
	var knight: BattleActor = state.actors[0]
	var enemy: BattleActor = state.actors[1]
	state.tick = 20
	SIM._damage(state, knight, enemy, 1.0, _rng(), true)
	assert_almost_eq(enemy.position, Vector2(1.0 + PUSH, 0), Vector2.ONE * 0.0001, "straight back")
	assert_eq(int(enemy.effect_state["last_push_tick"]), 20)
	assert_eq(enemy.effect_state["hit_from"], [1.0, 0.0], "the view's cue: the push direction")

	knight.crit_rate = 0.0
	state.tick = 20 + GATE * 2
	SIM._damage(state, knight, enemy, 1.0, _rng(), true)
	assert_almost_eq(enemy.position, Vector2(1.0 + PUSH, 0), Vector2.ONE * 0.0001, "a plain basic hit never pushes")
	knight.crit_rate = 1.0
	SIM._damage(state, knight, enemy, 1.0, _rng(), false)
	assert_almost_eq(enemy.position, Vector2(1.0 + PUSH, 0), Vector2.ONE * 0.0001, "a crit that is not a basic hit never crit-pushes")


func test_the_crit_gate_needs_the_previous_crit_gate_ticks_old() -> void:
	var state: BattleState = _battle([_unit("hero:k", "knight", "ally", Vector2(0, 0), {"crit_rate": 1.0}), _unit("enemy:1", "knight", "enemy", Vector2(1, 0), {"hp": 1000.0})])
	var knight: BattleActor = state.actors[0]
	var enemy: BattleActor = state.actors[1]
	state.tick = 3
	SIM._damage(state, knight, enemy, 1.0, _rng(), true)
	assert_almost_eq(enemy.position.x, 1.0 + PUSH, 0.0001, "0 is no crit yet, so an early first crit pushes")
	state.tick = 3 + GATE - 1
	var hp: float = enemy.hp
	SIM._damage(state, knight, enemy, 1.0, _rng(), true)
	assert_almost_eq(enemy.position.x, 1.0 + PUSH, 0.0001, "one tick short of the gate: no push")
	assert_lt(enemy.hp, hp, "but it still deals its crit")
	assert_eq(int(enemy.effect_state["last_crit_tick"]), 3 + GATE - 1)
	state.tick = 3 + GATE * 2 - 1
	SIM._damage(state, knight, enemy, 1.0, _rng(), true)
	assert_almost_eq(enemy.position.x, 1.0 + PUSH * 2.0, 0.0001, "the gate's ticks after the gated one: it pushes")


func test_elites_and_hits_that_down_or_kill_are_not_pushed() -> void:
	var state: BattleState = _battle([_unit("hero:k", "knight", "ally", Vector2(0, 0), {"crit_rate": 1.0}), _unit("enemy:1", "knight", "enemy", Vector2(1, 0)), _unit("enemy:2", "knight", "enemy", Vector2(0, 1), {"hp": 1.0})])
	var knight: BattleActor = state.actors[0]
	var elite: BattleActor = state.actors[1]
	var weak: BattleActor = state.actors[2]
	elite.effect_state["elite"] = true
	state.tick = 20
	SIM._damage(state, knight, elite, 1.0, _rng(), true)
	assert_eq(elite.position, Vector2(1, 0), "elites are immune")
	assert_false(elite.effect_state.has("last_push_tick"))
	SIM._damage(state, knight, weak, 1.0, _rng(), true)
	assert_eq(weak.life, BattleActor.LIFE_DEAD)
	assert_eq(weak.position, Vector2(0, 1), "a killing hit leaves the body where it fell")
	assert_eq(weak.effect_state["hit_from"], [0.0, 1.0], "the fling still knows where the hit came from")

	var downing: BattleState = _battle([_unit("hero:k", "knight", "ally", Vector2(0, 0), {"hp": 1.0}), _unit("enemy:1", "knight", "enemy", Vector2(1, 0))])
	downing.policies["force_enemy_crit"] = true
	downing.tick = 20
	SIM._damage(downing, downing.actors[1], downing.actors[0], 1.0, _rng(), true)
	assert_eq(downing.actors[0].life, BattleActor.LIFE_DOWNED)
	assert_eq(downing.actors[0].position, Vector2(0, 0), "a downing hit leaves the body for revive and carry")


func test_a_push_clamps_to_the_bounds_and_coinciding_actors_push_along_facing() -> void:
	var bounds: float = 20.0
	var state: BattleState = _battle([_unit("hero:k", "knight", "ally", Vector2(bounds - 1.0, 0), {"crit_rate": 1.0}), _unit("enemy:1", "knight", "enemy", Vector2(bounds - 0.3, 0)), _unit("enemy:2", "knight", "enemy", Vector2(bounds - 1.0, 0))])
	state.objective_state["bounds"] = bounds
	var knight: BattleActor = state.actors[0]
	state.tick = 20
	SIM._damage(state, knight, state.actors[1], 1.0, _rng(), true)
	assert_almost_eq(state.actors[1].position, Vector2(bounds, 0), Vector2.ONE * 0.0001, "the wall shortens the push")
	knight.facing = Vector2(0, -1)
	SIM._damage(state, knight, state.actors[2], 1.0, _rng(), true)
	assert_almost_eq(state.actors[2].position, Vector2(bounds - 1.0, -PUSH), Vector2.ONE * 0.0001, "same spot: along the attacker's facing")
	assert_eq(SIM._push_direction(Vector2.ZERO, Vector2.ZERO), Vector2.RIGHT, "a saved zero facing still pushes the full distance")


func test_a_pushed_carrier_takes_its_body_and_a_channel_pauses_out_of_range() -> void:
	var state: BattleState = _battle([_unit("hero:c", "cleric", "ally", Vector2(0, 0)), _unit("hero:d", "knight", "ally", Vector2(0, 0)), _unit("enemy:1", "knight", "enemy", Vector2(-1, 0))])
	state.policies["force_enemy_crit"] = true
	var carrier: BattleActor = state.actors[0]
	var body: BattleActor = state.actors[1]
	var enemy: BattleActor = state.actors[2]
	body.life = BattleActor.LIFE_DOWNED
	carrier.carrying_id = body.id
	body.carried_by_id = carrier.id
	state.tick = 20
	SIM._damage(state, enemy, carrier, 1.0, _rng(), true)
	assert_almost_eq(carrier.position, Vector2(PUSH, 0), Vector2.ONE * 0.0001)
	assert_eq(body.position, carrier.position, "the body comes along")

	# A carrier still channeling: pushed past the carry range, it keeps its progress and resumes.
	var channel: BattleState = _battle([_unit("hero:c", "cleric", "ally", Vector2(1, 0)), _unit("hero:d", "knight", "ally", Vector2(0, 0)), _unit("enemy:1", "knight", "enemy", Vector2(0, 0))])
	var helper: BattleActor = channel.actors[0]
	var downed: BattleActor = channel.actors[1]
	downed.life = BattleActor.LIFE_DOWNED
	helper.order_kind = SIM.COMMAND_CARRY
	helper.order_target_id = downed.id
	helper.effect_state["carry_progress"] = 0.5
	SIM._push(channel, helper, Vector2(1, 0), Vector2.RIGHT, 1.0)
	SIM._update_carry(channel, helper)
	assert_almost_eq(float(helper.effect_state["carry_progress"]), 0.5, 0.0001, "paused, not restarted")
	helper.position = Vector2(1, 0)
	SIM._update_carry(channel, helper)
	assert_almost_eq(float(helper.effect_state["carry_progress"]), 0.5 + SIM.BALANCE.battle_tick_seconds, 0.0001, "resumes back in range")


func test_threadneedle_pushes_each_target_along_the_shot_and_bloom_from_its_center() -> void:
	var state: BattleState = _battle([_unit("hero:r", "ranger", "ally", Vector2(0, 0)), _unit("enemy:1", "knight", "enemy", Vector2(3, 0)), _unit("enemy:2", "knight", "enemy", Vector2(5, 0.2))])
	var ranger: BattleActor = state.actors[0]
	_give(ranger, ["ranger_piercing_shot"])
	assert_true(SIM._use_skill(state, ranger, SIM.ABILITIES["ranger_piercing_shot"], state.actors[1], state.actors[1].position, null))
	assert_almost_eq(state.actors[1].position, Vector2(4, 0), Vector2.ONE * 0.0001, "1.0 along the line")
	assert_almost_eq(state.actors[2].position, Vector2(6, 0.2), Vector2.ONE * 0.0001, "every target on it, the same way")

	var burst: BattleState = _battle([_unit("hero:m", "mage", "ally", Vector2(0, 0)), _unit("enemy:1", "knight", "enemy", Vector2(5, 0)), _unit("enemy:2", "knight", "enemy", Vector2(5, 1))])
	var mage: BattleActor = burst.actors[0]
	mage.facing = Vector2(1, 0)
	_give(mage, ["mage_burst"])
	assert_true(SIM._use_skill(burst, mage, SIM.ABILITIES["mage_burst"], burst.actors[1], burst.actors[1].position, null))
	assert_almost_eq(burst.actors[1].position, Vector2(6.5, 0), Vector2.ONE * 0.0001, "at the center: along the caster's facing")
	assert_almost_eq(burst.actors[2].position, Vector2(5, 2.5), Vector2.ONE * 0.0001, "1.5 out from the center")

	var killing: BattleState = _battle([_unit("hero:m", "mage", "ally", Vector2(0, 0)), _unit("enemy:1", "knight", "enemy", Vector2(5, 0)), _unit("enemy:2", "knight", "enemy", Vector2(4, 0), {"hp": 1.0})])
	_give(killing.actors[0], ["mage_burst"])
	assert_true(SIM._use_skill(killing, killing.actors[0], SIM.ABILITIES["mage_burst"], killing.actors[1], killing.actors[1].position, null))
	assert_eq(killing.actors[2].life, BattleActor.LIFE_DEAD)
	assert_eq(killing.actors[2].position, Vector2(4, 0), "the body stays")
	assert_eq(killing.actors[2].effect_state["hit_from"], [-1.0, 0.0], "and flings away from the burst, not the caster")


func test_a_skill_push_needs_a_line_or_circle_and_a_positive_number() -> void:
	var skill: AbilityDefinition = (SIM.ABILITIES["ranger_piercing_shot"] as AbilityDefinition).duplicate(true)
	for push: Variant in [0.0, -1.0, INF, [], "1"]:
		skill.effects = [{"type": "damage", "area": "line", "multiplier": 1.8, "push": push}]
		assert_string_contains(skill.validate(), "a push needs", "push %s" % str(push))
	skill.effects = [{"type": "damage", "area": "near_target", "multiplier": 1.8, "count": 2, "push": 1.0}]
	assert_string_contains(skill.validate(), "a push needs")
	skill.effects = [{"type": "damage", "area": "line", "multiplier": 1.8, "push": 1}]
	assert_eq(skill.validate(), "", "a whole number is a distance too")


## Bulwark cuts damage near a living ally. Enemy 1 comes first in actor order and would be pushed out
## of Bulwark's 3.0 before Enemy 2 is hit; resolve-then-push keeps Enemy 2's cut.
func test_an_area_hit_lands_every_hit_before_any_push() -> void:
	var state: BattleState = _battle([_unit("hero:m", "mage", "ally", Vector2(0, 0)), _unit("enemy:1", "knight", "enemy", Vector2(5, 0.5)), _unit("enemy:2", "knight", "enemy", Vector2(5, -2.2))])
	_give(state.actors[2], ["knight_bulwark"])
	SIM._apply_effects(state, state.actors[0], SIM.ABILITIES["mage_burst"], state.actors[1], Vector2(5, 0), null, false, false)
	assert_almost_eq(state.actors[1].position, Vector2(5, 2.0), Vector2.ONE * 0.0001, "pushed after the hits")
	assert_almost_eq(state.actors[2].hp, 100.0 - 15.0 * 0.9, 0.0001, "hit while its ally was still near")


## An enemy's telegraphed Bloom pushes too, from its marked circle.
func test_a_telegraphed_bloom_pushes_from_its_marked_center() -> void:
	var state: BattleState = _battle([_unit("hero:k", "knight", "ally", Vector2(1, 0)), _unit("enemy:1", "mage", "enemy", Vector2(-5, 0))])
	var enemy: BattleActor = state.actors[1]
	_give(enemy, ["mage_burst"])
	SIM._start_telegraph(state, enemy, SIM.ABILITIES["mage_burst"], Vector2(0, 0), 1.0)
	SIM._resolve_telegraph(state, enemy, null)
	assert_almost_eq(state.actors[0].position, Vector2(2.5, 0), Vector2.ONE * 0.0001)


## Boundary #1: a fight saved mid-fight pushes after the reload as the fight that never stopped, from
## the real SaveService file too (full precision; a reload lands within 1 ulp, ig-85w), the cues survive
## the file, a save from before the cues loads, and broken cues are rejected.
func test_a_mid_fight_save_and_reload_reproduces_the_pushes_and_legacy_saves_load() -> void:
	GameSession.cleared_zone_ids[&"verdant_outskirts"] = true
	var ids: Array[String] = []
	for archetype: StringName in [&"ranger", &"mage", &"ranger", &"mage", &"knight"]:
		var hero := Hero.new("Pusher %d" % ids.size(), 7)
		hero.def_id = archetype
		hero.level = 20
		hero.instance_id = "hero:push:%d" % ids.size()
		GameSession.roster.append(hero)
		ids.append(hero.instance_id)
	var preset_id: String = GameSession.save_team_preset("", "Push", ids, "ashfall_reaches")
	var order_id: String = GameSession.dispatch_force([preset_id], "ashfall_reaches", 1, {}, {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0})
	assert_ne(order_id, "", GameSession.last_action_error)
	# A fixed fight, so pushes surely fall after the save: dispatch picks a fresh seed each run.
	var seeded: Dictionary = JSON.parse_string(JSON.stringify(GameSession.to_dict(), "", true, true)) as Dictionary
	((seeded["expedition_orders"] as Array)[0] as Dictionary)["battle"]["rng_state"] = "1"
	GameSession.from_dict(seeded)
	GameSession.tick_expeditions(2.0)
	assert_eq(str(GameSession.get_battle_snapshot(order_id)["status"]), "active")
	_save_to_disk()
	var exact: String = JSON.stringify(GameSession.to_dict(), "", true, true)
	var pushes_at_save: int = _pushes(GameSession.get_battle_snapshot(order_id))

	for _second: int in 12:
		GameSession.tick_expeditions(1.0)
	var straight: Array = _where(GameSession.get_battle_snapshot(order_id))
	assert_gt(_pushes(GameSession.get_battle_snapshot(order_id)), pushes_at_save, "the fight pushed after the save")
	GameSession.from_dict(JSON.parse_string(exact) as Dictionary)
	for _second: int in 12:
		GameSession.tick_expeditions(1.0)
	assert_eq(Compare.mismatch(_where(GameSession.get_battle_snapshot(order_id)), straight), "", "the saved state pushes as the unbroken fight")

	# ig-85w: the file holds full-precision floats, so the disk path is held to the unbroken fight too.
	# Within Compare.mismatch's tolerance: the parser misrounds some 17-digit numbers by 1 ulp.
	GameSession.from_dict({"roster": []})
	assert_true(SaveService.load_game(), SaveService.load_block_reason)
	for _second: int in 12:
		GameSession.tick_expeditions(1.0)
	assert_eq(Compare.mismatch(_where(GameSession.get_battle_snapshot(order_id)), straight), "", "the save on disk pushes as the unbroken fight")
	assert_gt(_pushes(GameSession.get_battle_snapshot(order_id)), pushes_at_save, "and it pushed after the reload")

	# The cues themselves through disk: saved after the pushes, loaded back as they were.
	# As the file reads back: full precision, parsed.
	var pushed: Array = _where(JSON.parse_string(JSON.stringify(GameSession.get_battle_snapshot(order_id), "", true, true)) as Dictionary)
	_save_to_disk()
	var profile: Dictionary = JSON.parse_string(JSON.stringify(GameSession.to_dict())) as Dictionary
	GameSession.from_dict({"roster": []})
	assert_true(SaveService.load_game(), SaveService.load_block_reason)
	assert_eq(Compare.mismatch(_where(GameSession.get_battle_snapshot(order_id)), pushed), "", "hit_from and last_push_tick survive the file")

	var legacy: Dictionary = profile.duplicate(true)
	for actor: Dictionary in _actors(legacy):
		(actor["effect_state"] as Dictionary).erase("hit_from")
		(actor["effect_state"] as Dictionary).erase("last_push_tick")
	assert_eq(Session.validate_saved_state(legacy, 3), "", "a save from before knockback loads")
	var legacy_file: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveService.SAVE_PATH)) as Dictionary
	for actor: Dictionary in _actors(legacy_file):
		(actor["effect_state"] as Dictionary).erase("hit_from")
		(actor["effect_state"] as Dictionary).erase("last_push_tick")
	_write_save(legacy_file)
	GameSession.from_dict({"roster": []})
	assert_true(SaveService.load_game(), SaveService.load_block_reason)
	assert_true(_actors(GameSession.to_dict()).all(func(actor: Dictionary) -> bool: return not (actor["effect_state"] as Dictionary).has("hit_from")), "loaded from disk without the cues")
	var tick: int = int(GameSession.get_battle_snapshot(order_id)["tick"])
	GameSession.tick_expeditions(1.0)
	assert_gt(int(GameSession.get_battle_snapshot(order_id)["tick"]), tick, "and advances")

	var battle_tick: int = int(((profile["expedition_orders"] as Array)[0] as Dictionary)["battle"]["tick"])
	for cue: Array in [["hit_from", [1.0]], ["hit_from", "left"], ["hit_from", [null, 1.0]], ["last_push_tick", -1], ["last_push_tick", 1.5], ["last_push_tick", battle_tick + 1]]:
		var broken: Dictionary = profile.duplicate(true)
		(_actors(broken)[0]["effect_state"] as Dictionary)[cue[0]] = cue[1]
		assert_ne(Session.validate_saved_state(broken, 3), "", "%s %s is rejected" % [cue[0], str(cue[1])])


func test_a_new_battle_starts_without_the_last_one_s_cues() -> void:
	var first: BattleState = _battle([_unit("hero:k", "knight", "ally", Vector2(0, 0))])
	first.actors[0].effect_state["hit_from"] = [1.0, 0.0]
	first.actors[0].effect_state["last_push_tick"] = 50
	var carried: Dictionary = first.actors[0].to_dict()
	carried["faction"] = "ally"
	carried["squad_id"] = "s"
	var next: BattleState = SIM.create_run("kits:2", [carried], ZoneDefinition.definition_for(&"verdant_outskirts"), [{"id": "s", "name": "S", "hero_ids": ["hero:k"], "stance": "stay_together", "guard_target_id": ""}], {}, {"healing": 0, "revival": 0}, 7, "rescue")
	assert_false(next.actors[0].effect_state.has("hit_from"))
	assert_false(next.actors[0].effect_state.has("last_push_tick"))


## A real SaveService write, stamped ahead so the reload adds no offline time.
func _save_to_disk() -> void:
	GameSession.set("_save_deferred_depth", 0)
	var saved: bool = SaveService.save()
	GameSession.set("_save_deferred_depth", 1)
	assert_true(saved, SaveService.last_write_error)
	var on_disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveService.SAVE_PATH)) as Dictionary
	on_disk["saved_at_unix"] = Time.get_unix_time_from_system() + 3600.0
	_write_save(on_disk)


func _write_save(data: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "	", true, true))
	file.close()


func _actors(profile: Dictionary) -> Array:
	return (((profile["expedition_orders"] as Array)[0] as Dictionary)["battle"] as Dictionary)["actors"] as Array


## What the pushes decide: the exact facts first, then the floats. A reload reads 43 back as 43.0.
func _where(snapshot: Dictionary) -> Array:
	var result: Array = []
	for actor: Dictionary in snapshot["actors"]:
		var effects: Dictionary = actor["effect_state"]
		var from: Array = effects.get("hit_from", [0.0, 0.0])
		result.append(["%s %s %s %d %d" % [snapshot["rng_state"], actor["id"], actor["life"], int(snapshot["tick"]), int(effects.get("last_push_tick", 0))], float(actor["hp"]), float(actor["position"][0]), float(actor["position"][1]), float(from[0]), float(from[1])])
	return result


func _pushes(snapshot: Dictionary) -> int:
	var total: int = 0
	for actor: Dictionary in snapshot.get("actors", []):
		total += int((actor["effect_state"] as Dictionary).get("last_push_tick", 0))
	return total


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


## No zone spawns (the enemies come in the list), Auto Battle off, empty kits. Pace 1: the authored
## numbers (test_battle_pace covers xP).
func _battle(snapshots: Array[Dictionary]) -> BattleState:
	var hero_ids: Array = snapshots.filter(func(snapshot: Dictionary) -> bool: return snapshot["faction"] == "ally").map(func(snapshot: Dictionary) -> String: return snapshot["hero_id"])
	var squads: Array[Dictionary] = [{"id": "s", "name": "S", "hero_ids": hero_ids, "stance": "stay_together", "guard_target_id": ""}]
	var state: BattleState = SIM.create_run("kits:1", snapshots, ZoneDefinition.definition_for(&"verdant_outskirts"), squads, {"auto_battle": false}, {"healing": 0, "revival": 0}, 7, "rescue", 1)
	for actor: BattleActor in state.actors:
		_give(actor, [])
	return state


func _give(actor: BattleActor, skill_ids: Array) -> void:
	actor.skills.clear()
	actor.skill_cooldowns.clear()
	for skill_id: String in skill_ids:
		actor.add_skill(SIM.ABILITIES[skill_id])
