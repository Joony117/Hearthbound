extends GutTest


func test_new_actor_emits_nothing() -> void:
	var events: Array[Dictionary] = BattleVfx.events_between({}, [_actor("e1", "enemy", "knight", {"last_hit_tick": 9})])

	assert_eq(events.size(), 0)


func test_hit_carries_rounded_damage() -> void:
	var before: Dictionary = _actor("e1", "enemy", "knight")
	var after: Dictionary = _actor("e1", "enemy", "knight", {"last_hit_tick": 4}, {"hp": 87.6})

	var events: Array[Dictionary] = BattleVfx.events_between({"e1": before}, [after])

	assert_eq(_kinds(events), ["hit"])
	assert_eq(events[0]["damage"], 12)
	assert_eq(events[0]["faction"], "enemy")


func test_hit_is_critical_only_when_the_crit_tick_advances() -> void:
	var before: Dictionary = _actor("e1", "enemy", "knight", {"last_crit_tick": 0})
	var normal: Dictionary = _actor("e1", "enemy", "knight", {"last_hit_tick": 4, "last_crit_tick": 0}, {"hp": 90.0})
	var crit: Dictionary = _actor("e1", "enemy", "knight", {"last_hit_tick": 4, "last_crit_tick": 4}, {"hp": 70.0})

	assert_false(BattleVfx.events_between({"e1": before}, [normal])[0]["critical"])
	assert_true(BattleVfx.events_between({"e1": before}, [crit])[0]["critical"])


func test_folded_hits_show_one_net_number_styled_crit_if_any_was() -> void:
	var before: Dictionary = _actor("a1", "ally", "knight", {"last_crit_tick": 0})
	# Three hits folded into one render: a crit at tick 3, then a normal hit at tick 5.
	var after: Dictionary = _actor("a1", "ally", "knight", {"last_hit_tick": 5, "last_crit_tick": 3}, {"hp": 60.0})

	var events: Array[Dictionary] = BattleVfx.events_between({"a1": before}, [after])

	assert_eq(_kinds(events), ["hit"])
	assert_eq(events[0]["damage"], 40)
	assert_true(events[0]["critical"])


func test_damage_numbers_are_red_on_both_sides_and_crits_pop_yellow() -> void:
	var vfx := BattleVfx.new()
	add_child_autofree(vfx)
	for faction: String in ["ally", "enemy"]:
		vfx.spawn({"kind": "hit", "faction": faction, "position": Vector3.ZERO, "damage": 12})
		var normal: Label3D = _label(vfx)
		assert_eq(normal.text, "12")
		assert_eq(normal.modulate, BattleVfx.DAMAGE_COLOR)
		assert_eq(normal.font_size, BattleVfx.DAMAGE_FONT_SIZE)
		assert_eq(normal.scale, Vector3.ONE)
	vfx.spawn({"kind": "hit", "faction": "enemy", "position": Vector3.ZERO, "damage": 124, "critical": true})
	var crit: Label3D = _label(vfx)
	assert_eq(crit.text, "124!")
	assert_eq(crit.modulate, BattleVfx.CRIT_COLOR)
	assert_eq(crit.outline_modulate, BattleVfx.CRIT_OUTLINE_COLOR)
	assert_eq(crit.font_size, BattleVfx.CRIT_FONT_SIZE)
	assert_gte(float(BattleVfx.CRIT_FONT_SIZE), BattleVfx.DAMAGE_FONT_SIZE * 1.5, "a crit stays clearly bigger")
	assert_almost_eq(crit.scale, Vector3.ONE * 1.8, Vector3.ONE * 0.001, "pop starts large")
	assert_between(crit.position.x, -BattleVfx.CRIT_JITTER, BattleVfx.CRIT_JITTER)
	await wait_seconds(1.0)
	assert_eq(vfx.get_child_count(), 0, "crit effect frees itself")


func test_heal_on_living_actor() -> void:
	var before: Dictionary = _actor("a1", "ally", "knight", {}, {"hp": 40.0})
	var after: Dictionary = _actor("a1", "ally", "knight", {}, {"hp": 65.0})

	var events: Array[Dictionary] = BattleVfx.events_between({"a1": before}, [after])

	assert_eq(_kinds(events), ["heal"])
	assert_eq(events[0]["amount"], 25)


func test_revive_is_not_a_heal() -> void:
	var before: Dictionary = _actor("a1", "ally", "knight", {}, {"hp": 0.0, "life": "downed"})
	var after: Dictionary = _actor("a1", "ally", "knight", {}, {"hp": 30.0})

	assert_eq(BattleVfx.events_between({"a1": before}, [after]).size(), 0)


func test_basic_attack_needs_target_hit_in_same_render() -> void:
	var previous: Dictionary = {
		"a1": _actor("a1", "ally", "ranger", {"attack_target_id": "e1"}),
		"e1": _actor("e1", "enemy", "knight", {}, {"position": [4.0, 0.0]}),
	}
	var actors: Array = [
		_actor("a1", "ally", "ranger", {}, {"attack_cooldown": 0.8}),
		_actor("e1", "enemy", "knight", {"last_hit_tick": 3}, {"hp": 90.0, "position": [4.0, 0.0]}),
	]

	var events: Array[Dictionary] = BattleVfx.events_between(previous, actors)
	var attack: Dictionary = _first(events, "basic_attack")

	assert_eq(attack["actor_id"], "a1")
	assert_true(attack["projectile"])
	assert_eq(attack["target_position"], Vector3(4.0, 0.0, 0.0))
	assert_eq(attack["target_id"], "e1")


func test_basic_attack_not_emitted_when_target_clears_without_hit() -> void:
	var previous: Dictionary = {
		"a1": _actor("a1", "ally", "knight", {"attack_target_id": "e1"}),
		"e1": _actor("e1", "enemy", "knight"),
	}
	var actors: Array = [_actor("a1", "ally", "knight", {"stun_remaining": 1.0}), _actor("e1", "enemy", "knight")]

	assert_eq(BattleVfx.events_between(previous, actors).size(), 0)


func test_basic_attack_not_emitted_when_stunned_attackers_target_is_hit_by_someone_else() -> void:
	var previous: Dictionary = {
		"a1": _actor("a1", "ally", "knight", {"attack_target_id": "e1"}),
		"a2": _actor("a2", "ally", "ranger"),
		"e1": _actor("e1", "enemy", "knight"),
	}
	var actors: Array = [
		_actor("a1", "ally", "knight", {"stun_remaining": 1.0}),
		_actor("a2", "ally", "ranger", {}, {"attack_cooldown": 0.8}),
		_actor("e1", "enemy", "knight", {"last_hit_tick": 3}, {"hp": 90.0}),
	]

	var events: Array[Dictionary] = BattleVfx.events_between(previous, actors)

	assert_eq(_kinds(events), ["hit"])


func test_ally_skill_uses_ability_numbers() -> void:
	var before: Dictionary = _actor("a1", "ally", "knight")
	var after: Dictionary = _actor("a1", "ally", "knight", {"last_skill_tick": 7})

	var skill: Dictionary = _first(BattleVfx.events_between({"a1": before}, [after]), "skill")

	assert_eq(skill["archetype"], "knight")
	assert_eq(skill["radius"], BattleSimulation.ABILITIES["knight"].radius_units)


func test_mage_skill_centers_on_hit_enemies_in_range() -> void:
	var previous: Dictionary = {
		"a1": _actor("a1", "ally", "mage"),
		"e1": _actor("e1", "enemy", "knight", {}, {"position": [4.0, 2.0]}),
		"e2": _actor("e2", "enemy", "knight", {}, {"position": [6.0, 0.0]}),
		"e3": _actor("e3", "enemy", "knight", {}, {"position": [40.0, 0.0]}),
	}
	var actors: Array = [
		_actor("a1", "ally", "mage", {"last_skill_tick": 5}),
		_actor("e1", "enemy", "knight", {"last_hit_tick": 5}, {"hp": 80.0, "position": [4.0, 2.0]}),
		_actor("e2", "enemy", "knight", {"last_hit_tick": 5}, {"hp": 80.0, "position": [6.0, 0.0]}),
		_actor("e3", "enemy", "knight", {"last_hit_tick": 5}, {"hp": 80.0, "position": [40.0, 0.0]}),
	]

	var skill: Dictionary = _first(BattleVfx.events_between(previous, actors), "skill")

	assert_eq(skill["center"], Vector3(5.0, 0.0, 1.0))


func test_ranger_skill_aims_at_what_it_hit_and_falls_back_to_facing() -> void:
	var previous: Dictionary = {
		"a1": _actor("a1", "ally", "ranger"),
		"e1": _actor("e1", "enemy", "knight", {}, {"position": [0.0, 5.0]}),
	}
	var hit: Array = [
		_actor("a1", "ally", "ranger", {"last_skill_tick": 5}),
		_actor("e1", "enemy", "knight", {"last_hit_tick": 5}, {"hp": 80.0, "position": [0.0, 5.0]}),
	]
	var missed: Array = [_actor("a1", "ally", "ranger", {"last_skill_tick": 5}), previous["e1"]]

	assert_eq(_first(BattleVfx.events_between(previous, hit), "skill")["facing"], Vector3(0.0, 0.0, 1.0))
	assert_eq(_first(BattleVfx.events_between(previous, missed), "skill")["facing"], Vector3(1.0, 0.0, 0.0))


func test_rogue_skill_carries_both_positions_for_either_faction() -> void:
	var before: Dictionary = _actor("e1", "enemy", "rogue", {}, {"position": [1.0, 1.0]})
	var after: Dictionary = _actor("e1", "enemy", "rogue", {"last_skill_tick": 2}, {"position": [3.0, 1.0]})

	var skill: Dictionary = _first(BattleVfx.events_between({"e1": before}, [after]), "skill")

	assert_eq(skill["previous_position"], Vector3(1.0, 0.0, 1.0))
	assert_eq(skill["position"], Vector3(3.0, 0.0, 1.0))


func test_enemy_mage_skill_start_is_not_a_skill_event() -> void:
	var before: Dictionary = _actor("e1", "enemy", "mage")
	var after: Dictionary = _actor("e1", "enemy", "mage", {"last_skill_tick": 2, "telegraph_kind": "circle", "telegraph_remaining": 1.0})

	assert_eq(BattleVfx.events_between({"e1": before}, [after]).size(), 0)


func test_enemy_telegraph_resolve_uses_previous_shape() -> void:
	var before: Dictionary = _actor("e1", "enemy", "ranger", {"telegraph_kind": "line", "telegraph_origin": [0.0, 0.0], "telegraph_point": [10.0, 0.0], "telegraph_radius": 1.0})
	var after: Dictionary = _actor("e1", "enemy", "ranger")

	var events: Array[Dictionary] = BattleVfx.events_between({"e1": before}, [after])

	assert_eq(_kinds(events), ["enemy_skill"])
	assert_eq(events[0]["shape"], "line")
	assert_eq(events[0]["point"], Vector3(10.0, 0.0, 0.0))


func test_stun_cancelled_telegraph_is_not_a_resolve() -> void:
	var before: Dictionary = _actor("e1", "enemy", "mage", {"telegraph_kind": "circle", "telegraph_radius": 2.5})
	var after: Dictionary = _actor("e1", "enemy", "mage", {"stun_remaining": 1.2})

	assert_eq(BattleVfx.events_between({"e1": before}, [after]).size(), 0)


func test_dodge_when_evade_point_appears() -> void:
	var before: Dictionary = _actor("a1", "ally", "knight", {}, {"position": [2.0, 3.0]})
	var after: Dictionary = _actor("a1", "ally", "knight", {"evade_point": [5.0, 3.0]}, {"position": [2.5, 3.0]})

	var events: Array[Dictionary] = BattleVfx.events_between({"a1": before}, [after])

	assert_eq(_kinds(events), ["dodge"])
	assert_eq(events[0]["position"], Vector3(2.0, 0.0, 3.0))


func test_enemy_death() -> void:
	var before: Dictionary = _actor("e1", "enemy", "knight", {}, {"hp": 5.0})
	var after: Dictionary = _actor("e1", "enemy", "knight", {"last_hit_tick": 8}, {"hp": 0.0, "life": "dead"})

	assert_eq(_kinds(BattleVfx.events_between({"e1": before}, [after])), ["hit", "death"])


func test_spawn_builds_every_kind_and_respects_cap() -> void:
	var vfx := BattleVfx.new()
	add_child_autofree(vfx)
	for kind: String in ["hit", "heal", "basic_attack", "skill", "enemy_skill", "dodge", "death"]:
		vfx.spawn({"kind": kind, "position": Vector3.ZERO, "damage": 5, "amount": 5, "archetype": "mage", "shape": "circle", "radius": 2.0, "target_position": Vector3.ONE, "facing": Vector3.FORWARD})
	assert_eq(vfx.get_child_count(), 7)
	for index: int in 50:
		vfx.spawn({"kind": "death", "position": Vector3.ZERO})
	assert_eq(vfx.get_child_count(), BattleVfx.MAX_LIVE_EFFECTS)
	await wait_seconds(0.8)
	assert_eq(vfx.get_child_count(), 0, "every effect frees itself")


func test_view_drops_all_units_when_a_retried_run_restarts_the_tick() -> void:
	SceneRouter.clear_battle_payload()
	var view: BattleView = (load("res://combat/battle/battle_view.tscn") as PackedScene).instantiate() as BattleView
	add_child_autofree(view)
	var dead_enemy: Dictionary = _actor("enemy:o:0:1", "enemy", "knight", {}, {"hp": 0.0, "life": "dead"})
	view._render_snapshot({"tick": 500, "actors": [_actor("a1", "ally", "knight", {}, {"hp": 30.0}), dead_enemy]})
	var corpse: BattleUnitView = view._unit_views["enemy:o:0:1"]
	assert_almost_eq(corpse._pivot.rotation.z, BattleUnitView.DEAD_TILT, 0.001)

	view._render_snapshot({"tick": 2, "actors": [_actor("a1", "ally", "knight"), _actor("enemy:o:0:1", "enemy", "knight")]})

	var fresh: BattleUnitView = view._unit_views["enemy:o:0:1"]
	assert_ne(fresh, corpse, "retried run gets a fresh unit view")
	assert_eq(fresh._pivot.rotation.z, 0.0)
	assert_eq(view._vfx.get_child_count(), 0, "no heal or other effect diffs across runs")
	await wait_process_frames(1)
	assert_false(is_instance_valid(corpse), "dropped unit views are freed, not orphaned")


func test_crit_basic_attack_freezes_attacker_and_target_and_melee_lunges() -> void:
	var view: BattleView = _view()
	_attack_renders(view, "knight", 2)
	var attacker: BattleUnitView = view._unit_views["a1"]
	var target: BattleUnitView = view._unit_views["e1"]
	assert_gt(target._freeze_remaining, 0.0, "the crit target freezes")
	assert_gt(attacker._freeze_remaining, 0.0, "the attacker that landed the crit freezes too")
	assert_not_null(attacker._lunge_tween, "melee lunges")


func test_plain_hit_does_not_freeze_and_ranged_does_not_lunge() -> void:
	var view: BattleView = _view()
	_attack_renders(view, "ranger", 0)
	assert_eq(view._unit_views["e1"]._freeze_remaining, 0.0)
	assert_eq(view._unit_views["a1"]._freeze_remaining, 0.0)
	assert_null(view._unit_views["a1"]._lunge_tween, "ranged attacks do not lunge")


func test_last_enemy_dying_slows_the_view_and_it_recovers() -> void:
	var view: BattleView = _view()
	view._render_snapshot({"tick": 1, "actors": [_actor("a1", "ally", "knight"), _actor("e1", "enemy", "knight")]})
	assert_eq(view._view_time_scale, 1.0)
	view._render_snapshot({"tick": 2, "actors": [_actor("a1", "ally", "knight"), _actor("e1", "enemy", "knight", {}, {"hp": 0.0, "life": "dead"})]})
	assert_almost_eq(view._view_time_scale, BattleView.SLOW_MO_SCALE, 0.001)
	assert_almost_eq(view._unit_views["a1"]._view_time_scale, BattleView.SLOW_MO_SCALE, 0.001, "units slow with the view")
	assert_almost_eq(view._vfx._time_scale, BattleView.SLOW_MO_SCALE, 0.001, "effects slow with the view")
	assert_eq(Engine.time_scale, 1.0, "the engine clock is never touched")
	view._process(BattleView.SLOW_MO_SECONDS)
	assert_eq(view._view_time_scale, 1.0)
	assert_eq(view._unit_views["a1"]._view_time_scale, 1.0)


func test_wave_clear_slows_even_when_the_next_wave_spawns_in_the_same_render() -> void:
	var view: BattleView = _view()
	view._render_snapshot({"tick": 1, "actors": [_actor("e1", "enemy", "knight")]})
	view._render_snapshot({"tick": 2, "actors": [_actor("e1", "enemy", "knight", {}, {"hp": 0.0, "life": "dead"}), _actor("e2", "enemy", "knight")]})
	assert_almost_eq(view._view_time_scale, BattleView.SLOW_MO_SCALE, 0.001)


func test_damage_numbers_draw_over_hp_bars() -> void:
	var vfx := BattleVfx.new()
	add_child_autofree(vfx)
	vfx.spawn({"kind": "hit", "position": Vector3.ZERO, "damage": 5})
	var label: Label3D = _label(vfx)
	assert_eq(label.render_priority, 4)
	assert_eq(label.outline_render_priority, 3)
	assert_gt(label.outline_render_priority, BattleUnitView.BAR_RENDER_PRIORITY)


func test_a_kill_that_leaves_enemies_alive_is_not_slowed() -> void:
	var view: BattleView = _view()
	view._render_snapshot({"tick": 1, "actors": [_actor("e1", "enemy", "knight"), _actor("e2", "enemy", "knight")]})
	view._render_snapshot({"tick": 2, "actors": [_actor("e1", "enemy", "knight", {}, {"hp": 0.0, "life": "dead"}), _actor("e2", "enemy", "knight")]})
	assert_eq(view._view_time_scale, 1.0)
	var fresh: BattleView = _view()
	fresh._render_snapshot({"tick": 1, "actors": [_actor("e1", "enemy", "knight", {}, {"hp": 0.0, "life": "dead"})]})
	assert_eq(fresh._view_time_scale, 1.0, "a battle first seen already cleared is not a clear")


func test_slow_mo_leaves_the_practice_sim_delta_alone() -> void:
	var hero := Hero.new("Slow Knight", 0)
	hero.def_id = &"knight"
	var zone: ZoneDefinition = load("res://zones/defs/verdant_outskirts.tres") as ZoneDefinition
	var view: BattleView = (load("res://combat/battle/battle_view.tscn") as PackedScene).instantiate() as BattleView
	view.configure_practice([hero], zone)
	add_child_autofree(view)
	view._set_paused(true)
	view._slow_mo_remaining = 10.0
	view._set_view_time_scale(BattleView.SLOW_MO_SCALE)
	view._set_paused(false)
	var elapsed_before: float = view._practice_state.elapsed_seconds
	view._process(0.3)
	assert_almost_eq(view._practice_state.elapsed_seconds - elapsed_before, 0.3, 0.001, "the sim advances by real delta")
	assert_eq(Engine.time_scale, 1.0)


func test_events_carry_the_tick_they_happened_on() -> void:
	var previous: Dictionary = {
		"a1": _actor("a1", "ally", "knight", {"attack_target_id": "e1"}),
		"e1": _actor("e1", "enemy", "knight", {"last_crit_tick": 0}),
	}
	var actors: Array = [
		_actor("a1", "ally", "knight", {"last_skill_tick": 12}, {"attack_cooldown": 0.8}),
		_actor("e1", "enemy", "knight", {"last_hit_tick": 13, "last_crit_tick": 13}, {"hp": 0.0, "life": "dead"}),
	]
	var events: Array[Dictionary] = BattleVfx.events_between(previous, actors)
	assert_eq(_first(events, "hit")["tick"], 13)
	assert_eq(_first(events, "death")["tick"], 13, "a death plays with its killing hit")
	assert_eq(_first(events, "skill")["tick"], 12)
	var attack: Dictionary = _first(events, "basic_attack")
	assert_eq(attack["tick"], 13, "a swing lands on its target's hit tick")
	assert_true(attack["critical"], "and knows the target was crit")


func test_live_render_spreads_its_ticks_out_instead_of_one_frame() -> void:
	var view: BattleView = _view()
	view._render_snapshot({"tick": 10, "actors": [_actor("e1", "enemy", "knight"), _actor("e2", "enemy", "knight")]})
	view._render_snapshot({"tick": 13, "actors": [
		_actor("e1", "enemy", "knight", {"last_hit_tick": 11}, {"hp": 90.0}),
		_actor("e2", "enemy", "knight", {"last_hit_tick": 13}, {"hp": 90.0}),
	]})
	var step: float = BattleView.tick_step(3, BattleView.BATTLE_PULSE_SECONDS)
	assert_eq(view._vfx.get_child_count(), 1, "the first tick's hit plays with the render")
	assert_eq(view._pending_events.size(), 1, "the last tick's hit waits for its own moment")
	var late: BattleUnitView = view._unit_views["e2"]
	assert_null(late._squash_tween, "its unit has not flinched yet")
	view._process(step * 2.0 - 0.01)
	assert_eq(view._vfx.get_child_count(), 1)
	view._process(0.02)
	assert_eq(view._vfx.get_child_count(), 2, "it plays two ticks in")
	late._process(step * 2.0)
	assert_not_null(late._squash_tween, "and the unit flinches with it")


func test_tick_offsets_fit_inside_one_render_interval() -> void:
	var tick_seconds: float = preload("res://balance.tres").battle_tick_seconds
	assert_almost_eq(BattleView.tick_step(2, BattleView.BATTLE_PULSE_SECONDS), tick_seconds, 0.0001, "two ticks play a tick apart")
	assert_almost_eq(BattleView.tick_step(1, tick_seconds), tick_seconds, 0.0001, "practice renders a tick at a time")
	var hitch: float = BattleView.tick_step(10, BattleView.BATTLE_PULSE_SECONDS)
	assert_lt(BattleView.tick_delay(19, 10, hitch), BattleView.BATTLE_PULSE_SECONDS, "a hitch squeezes its ticks into the interval")
	assert_almost_eq(BattleView.tick_delay(13, 11, tick_seconds), tick_seconds * 2.0, 0.0001)
	assert_eq(BattleView.tick_delay(4, 11, tick_seconds), 0.0, "an older tick plays at once")


func test_wave_clear_slow_mo_waits_for_the_killing_blow() -> void:
	var view: BattleView = _view()
	view._render_snapshot({"tick": 10, "actors": [_actor("e1", "enemy", "knight")]})
	view._render_snapshot({"tick": 12, "actors": [_actor("e1", "enemy", "knight", {"last_hit_tick": 12}, {"hp": 0.0, "life": "dead"})]})
	assert_eq(view._view_time_scale, 1.0)
	view._process(BattleView.tick_step(2, BattleView.BATTLE_PULSE_SECONDS))
	assert_almost_eq(view._view_time_scale, BattleView.SLOW_MO_SCALE, 0.001)


func test_practice_units_glide_over_one_tick() -> void:
	var hero := Hero.new("Glide Knight", 0)
	hero.def_id = &"knight"
	var view: BattleView = (load("res://combat/battle/battle_view.tscn") as PackedScene).instantiate() as BattleView
	view.configure_practice([hero], load("res://zones/defs/verdant_outskirts.tres") as ZoneDefinition)
	add_child_autofree(view)
	view._process(0.3)
	var gliding: Array = view._unit_views.values().filter(func(unit: BattleUnitView) -> bool: return unit._glide_seconds > 0.0)
	assert_false(gliding.is_empty(), "someone moved")
	for unit: BattleUnitView in gliding:
		assert_almost_eq(unit._glide_seconds, preload("res://balance.tres").battle_tick_seconds, 0.0001, "practice glides one tick, not a live pulse")


func _view() -> BattleView:
	SceneRouter.clear_battle_payload()
	var view: BattleView = (load("res://combat/battle/battle_view.tscn") as PackedScene).instantiate() as BattleView
	add_child_autofree(view)
	return view


func _attack_renders(view: BattleView, archetype: String, crit_tick: int) -> void:
	view._render_snapshot({"tick": 1, "actors": [
		_actor("a1", "ally", archetype, {"attack_target_id": "e1"}),
		_actor("e1", "enemy", "knight", {"last_crit_tick": 0}, {"position": [2.0, 0.0]}),
	]})
	view._render_snapshot({"tick": 2, "actors": [
		_actor("a1", "ally", archetype, {}, {"attack_cooldown": 0.8}),
		_actor("e1", "enemy", "knight", {"last_hit_tick": 2, "last_crit_tick": crit_tick}, {"hp": 90.0, "position": [2.0, 0.0]}),
	]})


func _actor(id: String, faction: String, archetype: String, effects: Dictionary = {}, fields: Dictionary = {}) -> Dictionary:
	var effect_state: Dictionary = {"last_hit_tick": 1, "last_skill_tick": 1, "attack_target_id": "", "telegraph_kind": "", "stun_remaining": 0.0}
	effect_state.merge(effects, true)
	var actor: Dictionary = {"id": id, "faction": faction, "archetype": archetype, "life": "alive", "hp": 100.0, "max_hp": 100.0, "attack_cooldown": 0.0, "position": [0.0, 0.0], "facing": [1.0, 0.0], "effect_state": effect_state}
	actor.merge(fields, true)
	return actor


func _label(vfx: BattleVfx) -> Label3D:
	var effect: Node = vfx.get_child(vfx.get_child_count() - 1)
	return effect.find_children("*", "Label3D", true, false)[0] as Label3D


func _kinds(events: Array[Dictionary]) -> Array:
	return events.map(func(event: Dictionary) -> String: return str(event["kind"]))


func _first(events: Array[Dictionary], kind: String) -> Dictionary:
	for event: Dictionary in events:
		if event["kind"] == kind:
			return event
	fail_test("no %s event in %s" % [kind, events])
	return {}
