extends GutTest

## ig-vl1.4: caster zones (SYSTEMS.md § Casters, Zones; DECISIONS.md 2026-09-25, "Casters shape the
## field"). Rime Circle holds enemies down, Hearthward holds a line up.

const SIM = preload("res://combat/battle/battle_simulation.gd")
const Compare = preload("res://tests/unit/compare.gd")
var RIME: AbilityDefinition = SIM.ABILITIES["mage_rime_circle"]
var HEARTH: AbilityDefinition = SIM.ABILITIES["cleric_hearthward"]


func before_each() -> void:
	GameSession.set("_save_deferred_depth", 1)
	GameSession.from_dict({"roster": []})
	SaveService.load_blocked = false


func after_each() -> void:
	GameSession.set("_save_deferred_depth", 0)


func test_both_spells_load_and_validate_knows_the_zone() -> void:
	assert_eq(RIME.validate(), "")
	assert_eq(HEARTH.validate(), "")
	assert_eq(HEARTH.band(), "buff")
	assert_same(SIM.signature_for("mage"), SIM.ABILITIES["mage_burst"], "the signature stays")
	assert_same(SIM.signature_for("cleric"), SIM.ABILITIES["cleric_mend"], "the signature stays")
	var slow: Dictionary = {"type": "status", "status": "speed", "magnitude": -0.3, "seconds": 1.5}
	for broken: Array in [
		[{"side": "everyone"}, "side"],
		[{"seconds": 0.0}, "seconds"],
		[{"pulse": []}, "pulse"],
		[{"pulse": [{"type": "shield", "multiplier": 1.0}]}, "pulse primitive"],
		[{"pulse": [{"type": "damage", "multiplier": 0.3, "area": "circle"}]}, "pulse field"],
		[{"side": "allies"}, "damage on allies"],
		[{"pulse": [{"type": "heal", "multiplier": 0.2}]}, "a heal on opponents"],
		[{"pulse": [{"type": "status", "status": "bleed", "magnitude": 0.5, "seconds": 1.5}]}, "a ticking status"],
		[{"pulse": [{"type": "status", "status": "damage_reduction", "magnitude": -0.2, "seconds": 1.5}]}, "a negative non-stat"],
		[{"pulse": [{"type": "status", "status": "speed", "magnitude": -1.0, "seconds": 1.5}]}, "a stat cut to 0"],
		[{"pulse": [{"type": "status", "status": "speed", "magnitude": -0.3}]}, "a status without seconds"],
	]:
		var skill: AbilityDefinition = RIME.duplicate(true)
		var effect: Dictionary = {"type": "zone", "side": "opponents", "seconds": 6.0, "pulse": [{"type": "damage", "multiplier": 0.3}, slow]}
		effect.merge(broken[0], true)
		skill.effects = [effect]
		assert_ne(skill.validate(), "", str(broken[1]))
	var no_radius: AbilityDefinition = RIME.duplicate(true)
	no_radius.radius_units = 0.0
	assert_ne(no_radius.validate(), "", "a zone needs a radius")


func test_rime_circle_pulses_each_second_on_enemies_inside_and_slows_them() -> void:
	var state: BattleState = _battle([
		_unit("hero:mage", "mage", "ally", Vector2(0, 0)),
		_unit("hero:knight", "knight", "ally", Vector2(5, 1)),
		_unit("enemy:in", "rogue", "enemy", Vector2(5, 0)),
		_unit("enemy:edge", "rogue", "enemy", Vector2(8, 0)),
		_unit("enemy:out", "rogue", "enemy", Vector2(8.5, 0)),
	])
	var mage: BattleActor = state.actors[0]
	_give(mage, ["mage_rime_circle"])
	assert_true(SIM._use_skill(state, mage, RIME, state.actors[2], Vector2(5, 0), _rng()))
	assert_eq(state.field_objects.size(), 1)
	assert_eq(float(state.field_objects[0]["remaining_seconds"]), 6.0, "6 s at pace 1")
	assert_eq(float(mage.skill_cooldowns["mage_rime_circle"]), 20.0)
	for tick: int in 9:
		SIM._update_field_objects(state)
	assert_eq(state.actors[2].hp, 100.0, "no pulse before 1 s")
	SIM._update_field_objects(state)
	assert_eq(state.actors[2].hp, 97.0, "0.3 x the caster's 10 ATK, no DEF, at 1 s")
	assert_eq(state.actors[3].hp, 97.0, "the edge counts as inside")
	assert_eq(state.actors[4].hp, 100.0, "outside")
	assert_eq(state.actors[1].hp, 100.0, "never an ally")
	assert_almost_eq(SIM._stat(state.actors[2], "speed"), 70.0, 0.000001, "SPD -30%")
	assert_eq(SIM._stat(state.actors[4], "speed"), 100.0)
	# A downed caster's zone keeps going.
	mage.life = BattleActor.LIFE_DOWNED
	for tick: int in 50:
		SIM._update_field_objects(state)
	assert_eq(state.actors[2].hp, 82.0, "six pulses in all")
	assert_true(state.field_objects.is_empty(), "it ends at 6 s")
	for tick: int in 15:
		SIM._expire_effects_and_cooldowns(state)
	assert_eq(SIM._stat(state.actors[2], "speed"), 100.0, "the slow ends 1.5 s after the last pulse")


func test_a_zone_kill_is_the_caster_s_and_a_slow_meets_a_raise() -> void:
	var state: BattleState = _battle([
		_unit("hero:mage", "mage", "ally", Vector2(0, 0)),
		_unit("enemy:low", "rogue", "enemy", Vector2(5, 0), {"current_hp": 2.0}),
		_unit("enemy:hasted", "rogue", "enemy", Vector2(5, 1)),
	])
	var enemy: BattleActor = state.actors[1]
	SIM._add_status(state.actors[2], "test_haste", "speed", "", 10.0, 0.5)
	assert_true(SIM._use_skill(state, state.actors[0], RIME, enemy, enemy.position, _rng()))
	for tick: int in 10:
		SIM._update_field_objects(state)
	assert_eq(enemy.life, BattleActor.LIFE_DEAD)
	assert_eq(int(state.kills.get("hero:mage", 0)), 1)
	assert_almost_eq(SIM._stat(state.actors[2], "speed"), 120.0, 0.000001, "the strongest raise and the strongest cut both apply")


func test_hearthward_heals_with_grace_and_guards_allies_only() -> void:
	var state: BattleState = _battle([
		_unit("hero:cleric", "cleric", "ally", Vector2(0, 0)),
		_unit("hero:hurt", "knight", "ally", Vector2(4, 0), {"current_hp": 50.0}),
		_unit("hero:guard", "knight", "ally", Vector2(4, 1)),
		_unit("enemy:near", "rogue", "enemy", Vector2(4, -1), {"current_hp": 50.0}),
	])
	var cleric: BattleActor = state.actors[0]
	var guard: BattleActor = state.actors[2]
	_give(cleric, ["cleric_grace", "cleric_hearthward"])
	SIM._add_status(guard, "knight_stand_fast", "damage_reduction", "", 30.0, 0.3)
	assert_true(SIM._use_skill(state, cleric, HEARTH, state.actors[1], Vector2(4, 0), _rng()))
	assert_eq(float(state.field_objects[0]["heal_scale"]), 1.2, "Grace, taken at the cast")
	for tick: int in 10:
		SIM._update_field_objects(state)
	assert_almost_eq(state.actors[1].hp, 51.8, 0.000001, "0.15 x 10 ATK x 1.2")
	assert_eq(SIM._status_value(state.actors[1], "damage_reduction"), 0.2)
	assert_eq(SIM._status_value(guard, "damage_reduction"), 0.3, "the strongest applies")
	assert_eq(state.actors[3].hp, 50.0, "never an enemy")
	assert_false(SIM._has_status(state.actors[3], "damage_reduction"))
	assert_false(SIM._has_status(cleric, "damage_reduction"), "the caster stands outside it")


func test_overlapping_zones_of_one_skill_land_once_per_actor_per_pulse() -> void:
	var state: BattleState = _battle([
		_unit("hero:c1", "cleric", "ally", Vector2(0, 0)),
		_unit("hero:c2", "cleric", "ally", Vector2(0, 1)),
		_unit("hero:hurt", "knight", "ally", Vector2(3, 0), {"current_hp": 50.0}),
	])
	for index: int in 2:
		_give(state.actors[index], ["cleric_hearthward"])
		assert_true(SIM._use_skill(state, state.actors[index], HEARTH, state.actors[2], Vector2(3, 0), _rng()))
	for tick: int in 10:
		SIM._update_field_objects(state)
	assert_almost_eq(state.actors[2].hp, 51.5, 0.000001, "one heal, not two")


func test_the_ninth_zone_ends_the_oldest() -> void:
	var state: BattleState = _battle([
		_unit("hero:mage", "mage", "ally", Vector2(0, 0)),
		_unit("enemy:a", "rogue", "enemy", Vector2(5, 0)),
	])
	var mage: BattleActor = state.actors[0]
	_give(mage, ["mage_rime_circle"])
	for cast: int in SIM.BALANCE.battle_field_object_cap + 1:
		mage.skill_cooldowns.clear()
		mage.ability_lock = 0.0
		assert_true(SIM._use_skill(state, mage, RIME, state.actors[1], Vector2(5, 0), _rng()))
	assert_eq(state.field_objects.size(), SIM.BALANCE.battle_field_object_cap)
	assert_eq(str(state.field_objects[0]["id"]), "field:2")
	assert_eq(str(state.field_objects[-1]["id"]), "field:%d" % (SIM.BALANCE.battle_field_object_cap + 1))


func test_at_pace_six_the_lifetime_and_cooldown_grow_and_the_pulse_does_not() -> void:
	var state: BattleState = _battle([
		_unit("hero:mage", "mage", "ally", Vector2(0, 0)),
		_unit("enemy:a", "rogue", "enemy", Vector2(5, 0)),
	], 6)
	var mage: BattleActor = state.actors[0]
	_give(mage, ["mage_rime_circle"])
	assert_true(SIM._use_skill(state, mage, RIME, state.actors[1], Vector2(5, 0), _rng()))
	assert_eq(float(state.field_objects[0]["remaining_seconds"]), 36.0)
	assert_eq(float(mage.skill_cooldowns["mage_rime_circle"]), 120.0)
	var hp: float = state.actors[1].hp
	for tick: int in 10:
		SIM._update_field_objects(state)
	assert_eq(state.actors[1].hp, hp - 3.0, "0.3 x ATK a second at any pace")


func test_hearthward_s_rule_wants_a_pressed_group_and_takes_its_lowest() -> void:
	var state: BattleState = _battle([
		_unit("hero:cleric", "cleric", "ally", Vector2(0, 0)),
		_unit("hero:a", "knight", "ally", Vector2(4, 0), {"current_hp": 80.0}),
		_unit("hero:b", "knight", "ally", Vector2(4, 1), {"current_hp": 65.0}),
		_unit("hero:c", "knight", "ally", Vector2(4, -1), {"current_hp": 90.0}),
		_unit("hero:far", "knight", "ally", Vector2(-20, 0), {"current_hp": 10.0}),
		_unit("enemy:e", "rogue", "enemy", Vector2(20, 0)),
	])
	var cleric: BattleActor = state.actors[0]
	assert_same(SIM._rule_aim(state, cleric, HEARTH, null, "buff"), state.actors[2], "b is below 70%: the group's lowest")
	state.actors[2].hp = 75.0
	assert_null(SIM._rule_aim(state, cleric, HEARTH, null, "buff"), "no one below 70% and no telegraph")
	var enemy: BattleActor = state.actors[5]
	enemy.effect_state["telegraph_kind"] = "circle"
	enemy.effect_state["telegraph_point"] = [4.0, -1.0]
	enemy.effect_state["telegraph_radius"] = 0.5
	assert_same(SIM._rule_aim(state, cleric, HEARTH, null, "buff"), state.actors[2], "c stands in a telegraph")
	state.actors[3].position = Vector2(12, 0)
	assert_null(SIM._rule_aim(state, cleric, HEARTH, null, "buff"), "only two left together")


func test_a_mid_zone_save_through_disk_reloads_exactly_and_fights_on_as_the_unbroken_run() -> void:
	GameSession.cleared_zone_ids[&"verdant_outskirts"] = true
	var ids: Array[String] = []
	for archetype: StringName in [&"mage", &"cleric", &"knight", &"mage", &"cleric"]:
		var hero := Hero.new("Zoner %d" % ids.size(), 7)
		hero.def_id = archetype
		hero.level = 20
		hero.instance_id = "hero:zone:%d" % ids.size()
		GameSession.roster.append(hero)
		ids.append(hero.instance_id)
	var preset_id: String = GameSession.save_team_preset("", "Zones", ids, "ashfall_reaches")
	var order_id: String = GameSession.dispatch_force([preset_id], "ashfall_reaches", 1, {}, {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0})
	assert_ne(order_id, "", GameSession.last_action_error)
	var seeded: Dictionary = Compare.json_round_trip(GameSession.to_dict())
	((seeded["expedition_orders"] as Array)[0] as Dictionary)["battle"]["rng_state"] = "1"
	GameSession.from_dict(seeded)
	var waited: int = 0
	while (GameSession.get_battle_snapshot(order_id).get("field_objects", []) as Array).is_empty() and waited < 120:
		GameSession.tick_expeditions(1.0)
		waited += 1
	assert_false((GameSession.get_battle_snapshot(order_id)["field_objects"] as Array).is_empty(), "a zone is up by %d s" % waited)
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

	var profile: Dictionary = Compare.json_round_trip(first)
	var legacy: Dictionary = profile.duplicate(true)
	_battle_of(legacy).erase("field_objects")
	_battle_of(legacy).erase("field_sequence")
	assert_eq(GameSession.validate_saved_state(legacy, 3), "", "a checkpoint from before zones loads")
	assert_true(BattleState.from_dict(_battle_of(legacy)).field_objects.is_empty(), "with none")
	for bad: Array in [["center", [999.0, 0.0]], ["center", [1.0]], ["radius", 0.0], ["radius", -1.0], ["remaining_seconds", 0.0], ["atk", NAN], ["kind", "wall"], ["owner_actor_id", "nobody"], ["faction", "neutral"], ["extra", 1]]:
		var broken: Dictionary = profile.duplicate(true)
		(_battle_of(broken)["field_objects"] as Array)[0][bad[0]] = bad[1]
		assert_ne(GameSession.validate_saved_state(broken, 3), "", "%s %s is rejected" % bad)
	# Sol: an id at or past the sequence would be cast again; more than the cap would outrun its cost bound.
	for bad_id: String in ["field:0", "field:%d" % (int(_battle_of(profile)["field_sequence"]) + 1), "zone:1", "field:01", "field:x"]:
		var reused: Dictionary = profile.duplicate(true)
		(_battle_of(reused)["field_objects"] as Array)[0]["id"] = bad_id
		assert_ne(GameSession.validate_saved_state(reused, 3), "", "id %s is rejected" % bad_id)
	var behind: Dictionary = profile.duplicate(true)
	_battle_of(behind)["field_sequence"] = 0
	assert_ne(GameSession.validate_saved_state(behind, 3), "", "a sequence behind its live ids is rejected")
	var crowded: Dictionary = profile.duplicate(true)
	var crowd: Array = _battle_of(crowded)["field_objects"] as Array
	var template: Dictionary = crowd[0]
	crowd.clear()
	for number: int in SIM.BALANCE.battle_field_object_cap + 1:
		var copy: Dictionary = template.duplicate(true)
		copy["id"] = "field:%d" % (number + 1)
		crowd.append(copy)
	_battle_of(crowded)["field_sequence"] = crowd.size()
	assert_ne(GameSession.validate_saved_state(crowded, 3), "", "more zones than the cap are rejected")
	crowd.pop_back()
	assert_eq(GameSession.validate_saved_state(crowded, 3), "", "the cap itself loads")
	var unknown: Dictionary = profile.duplicate(true)
	var fields: Array = _battle_of(unknown)["field_objects"] as Array
	fields[0]["skill_id"] = "mage_meteor"
	assert_eq(GameSession.validate_saved_state(unknown, 3), "", "an unknown skill doesn't reject the checkpoint")
	assert_eq(BattleState.from_dict(_battle_of(unknown)).field_objects.size(), fields.size() - 1, "it drops that zone")
	assert_push_warning("mage_meteor")


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


## The exact facts first (zones included), then each actor's floats.
func _where(snapshot: Dictionary) -> Array:
	var result: Array = []
	var zones: String = str((snapshot["field_objects"] as Array).map(func(field: Dictionary) -> String: return "%s %s" % [field["id"], field["skill_id"]]))
	for actor: Dictionary in snapshot["actors"]:
		result.append(["%s %s %s %d %s" % [snapshot["rng_state"], actor["id"], actor["life"], int(snapshot["tick"]), zones], float(actor["hp"]), float(actor["position"][0]), float(actor["position"][1])])
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
	var state: BattleState = SIM.create_run("zones:1", snapshots, ZoneDefinition.definition_for(&"verdant_outskirts"), squads, {"auto_battle": false}, {"healing": 0, "revival": 0}, 7, "rescue", pace)
	for actor: BattleActor in state.actors:
		_give(actor, [])
	return state


func _give(actor: BattleActor, skill_ids: Array) -> void:
	actor.skills.clear()
	actor.skill_cooldowns.clear()
	for skill_id: String in skill_ids:
		actor.add_skill(SIM.ABILITIES[skill_id])
