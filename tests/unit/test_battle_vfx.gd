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
		assert_almost_eq(normal.scale, Vector3.ONE * BattleVfx.DAMAGE_POP_SCALE, Vector3.ONE * 0.001, "numbers pop in")
	vfx.spawn({"kind": "hit", "faction": "enemy", "position": Vector3.ZERO, "damage": 124, "critical": true})
	var crit: Label3D = _label(vfx)
	assert_eq(crit.text, "124!")
	assert_eq(crit.modulate, BattleVfx.CRIT_COLOR)
	assert_eq(crit.outline_modulate, BattleVfx.CRIT_OUTLINE_COLOR)
	assert_eq(crit.font_size, BattleVfx.CRIT_FONT_SIZE)
	assert_gte(float(BattleVfx.CRIT_FONT_SIZE), BattleVfx.DAMAGE_FONT_SIZE * 1.5, "a crit stays clearly bigger")
	assert_almost_eq(crit.scale, Vector3.ONE * BattleVfx.CRIT_POP_SCALE, Vector3.ONE * 0.001, "pop starts large")
	assert_gt(BattleVfx.CRIT_POP_SCALE, BattleVfx.DAMAGE_POP_SCALE, "crits pop harder")
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
	assert_eq(skill["radius"], BattleSimulation.ABILITIES["knight_rally"].radius_units)


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
	for kind: String in ["hit", "heal", "basic_attack", "skill", "enemy_skill", "dodge", "landing"]:
		vfx.spawn({"kind": kind, "position": Vector3.ZERO, "damage": 5, "amount": 5, "archetype": "mage", "shape": "circle", "radius": 2.0, "target_position": Vector3.ONE, "facing": Vector3.FORWARD})
	assert_eq(vfx.get_child_count(), 7)
	for index: int in 50:
		vfx.spawn({"kind": "landing", "position": Vector3.ZERO})
	assert_eq(vfx.get_child_count(), BattleVfx.MAX_LIVE_EFFECTS)
	await wait_seconds(0.8)
	assert_eq(vfx.get_child_count(), 0, "every effect frees itself")


func test_death_itself_draws_nothing_the_landing_does() -> void:
	var vfx := BattleVfx.new()
	add_child_autofree(vfx)
	vfx.spawn({"kind": "death", "position": Vector3.ZERO})
	await wait_process_frames(1)
	assert_eq(vfx.get_child_count(), 0, "the dust waits for the body to land")
	var view: BattleView = _view()
	view._on_unit_body_landed(Vector3(1.0, 0.0, 2.0))
	assert_eq(view._vfx.get_child_count(), 1)
	assert_eq(view._vfx.get_child(0).find_children("*", "CPUParticles3D", true, false).size(), 1, "a dust puff")


func test_damage_numbers_settle_at_their_resting_size() -> void:
	var vfx := BattleVfx.new()
	add_child_autofree(vfx)
	vfx.spawn({"kind": "hit", "position": Vector3.ZERO, "damage": 12})
	await wait_seconds(BattleVfx.DAMAGE_POP_SECONDS + 0.05)
	assert_almost_eq(_label(vfx).scale, Vector3.ONE, Vector3.ONE * 0.001)


func test_every_effect_mesh_and_speck_shares_one_material() -> void:
	var vfx := BattleVfx.new()
	add_child_autofree(vfx)
	for archetype: String in ["knight", "ranger", "mage", "rogue"]:
		vfx.spawn({"kind": "skill", "archetype": archetype, "position": Vector3.ZERO, "facing": Vector3.FORWARD, "radius": 2.0, "range": 4.0})
	vfx.spawn({"kind": "hit", "position": Vector3.ZERO, "damage": 5, "critical": true})
	vfx.spawn({"kind": "basic_attack", "faction": "ally", "projectile": true, "position": Vector3.ZERO, "target_position": Vector3.ONE})
	var meshes: Array[Node] = vfx.find_children("*", "MeshInstance3D", true, false)
	assert_gt(meshes.size(), 10)
	for mesh: Node in meshes:
		assert_same((mesh as MeshInstance3D).material_override, BattleVfx._effect_material)
	for particles: Node in vfx.find_children("*", "CPUParticles3D", true, false):
		assert_same((particles as CPUParticles3D).mesh.surface_get_material(0), BattleVfx._speck_material)


func test_crits_add_two_rings_and_hits_throw_more_bigger_sparks() -> void:
	var vfx := BattleVfx.new()
	add_child_autofree(vfx)
	vfx.spawn({"kind": "hit", "position": Vector3.ZERO, "damage": 5})
	vfx.spawn({"kind": "hit", "position": Vector3.ZERO, "damage": 5, "critical": true})
	var plain: Node = vfx.get_child(0)
	var crit: Node = vfx.get_child(1)
	var sparks: CPUParticles3D = plain.find_children("*", "CPUParticles3D", true, false)[0] as CPUParticles3D
	assert_eq(sparks.amount, BattleVfx.HIT_SPARK_COUNT)
	assert_gte(BattleVfx.HIT_SPARK_COUNT, 28, "twice the old 14")
	assert_gt(BattleVfx.HIT_SPARK_SIZE, 0.08, "bigger than the old specks")
	assert_eq(_rings(plain), 0, "an ordinary hit has no ring")
	assert_eq(_rings(crit), 2, "a crit gets a second, larger ring")


func test_projectile_impacts_burst_at_the_target_after_the_flight() -> void:
	var vfx := BattleVfx.new()
	add_child_autofree(vfx)
	vfx.spawn({"kind": "basic_attack", "faction": "enemy", "projectile": true, "position": Vector3.ZERO, "target_position": Vector3(3.0, 0.0, 0.0)})
	var burst: CPUParticles3D = vfx.get_child(0).find_children("*", "CPUParticles3D", true, false)[0] as CPUParticles3D
	assert_almost_eq(burst.position, Vector3(3.0, 0.9, 0.0), Vector3.ONE * 0.001)
	assert_false(burst.emitting, "it waits for the projectile to arrive")
	await wait_seconds(BattleVfx.PROJECTILE_SECONDS + 0.05)
	assert_true(burst.emitting)


func test_every_skill_signature_flashes_rings_and_bursts_in_its_color() -> void:
	var vfx := BattleVfx.new()
	add_child_autofree(vfx)
	var colors: Dictionary = {"knight": BattleVfx.KNIGHT_SKILL_COLOR, "ranger": BattleVfx.RANGER_SKILL_COLOR, "mage": BattleVfx.MAGE_SKILL_COLOR, "rogue": BattleVfx.ROGUE_SKILL_COLOR}
	var events: Array[Dictionary] = []
	for archetype: String in colors:
		for faction: String in ["ally", "enemy"]:
			events.append({"kind": "skill", "faction": faction, "archetype": archetype, "position": Vector3.ZERO, "previous_position": Vector3.ONE, "facing": Vector3.FORWARD, "radius": 2.0, "range": 4.0, "center": Vector3(0.0, 0.0, -2.0)})
	for shape: String in ["circle", "line"]:
		events.append({"kind": "enemy_skill", "shape": shape, "origin": Vector3.ZERO, "point": Vector3(0.0, 0.0, 3.0), "radius": 2.0})
	for event: Dictionary in events:
		vfx.spawn(event)
	for index: int in events.size():
		var event: Dictionary = events[index]
		var effect: Node = vfx.get_child(index)
		var spheres: int = 0
		var tints: Array[Color] = []
		for mesh: Node in effect.find_children("*", "MeshInstance3D", true, false):
			if (mesh as MeshInstance3D).mesh is SphereMesh:
				spheres += 1
			tints.append((mesh as MeshInstance3D).get_instance_shader_parameter(&"tint"))
		var label: String = "%s %s" % [event.get("faction", "enemy"), event.get("archetype", event.get("shape"))]
		var showpiece: bool = event.get("archetype", "") == "mage" or event.get("shape", "") == "circle"
		assert_eq(spheres, 2 if showpiece else 1, "%s: a cast flash, plus the expanding sphere on a burst" % label)
		assert_gte(_rings(effect), 1, "%s: a ground shockwave" % label)
		assert_eq(effect.find_children("*", "CPUParticles3D", true, false).size(), 1, "%s: an impact burst" % label)
		var impact: CPUParticles3D = effect.find_children("*", "CPUParticles3D", true, false)[0] as CPUParticles3D
		assert_eq(impact.amount, BattleVfx.SKILL_IMPACT_COUNT, "%s: larger than a hit" % label)
		var expected: Color = BattleVfx.ENEMY_SKILL_COLOR if event["kind"] == "enemy_skill" or event["faction"] == "enemy" else colors[event["archetype"]]
		assert_eq(impact.color, expected, "%s: the impact burns in its color" % label)
		assert_true(tints.any(func(tint: Color) -> bool: return tint.is_equal_approx(expected)), "%s: the shockwave shares it" % label)


func test_camera_shakes_only_on_crits_and_skills() -> void:
	assert_eq(BattleVfx.shake_for({"kind": "hit", "critical": false}), 0.0, "an ordinary hit never shakes")
	assert_eq(BattleVfx.shake_for({"kind": "basic_attack", "critical": true}), 0.0, "a crit shakes once, on its hit")
	for kind: String in ["heal", "dodge", "death", "landing"]:
		assert_eq(BattleVfx.shake_for({"kind": kind}), 0.0, kind)
	assert_gt(BattleVfx.shake_for({"kind": "hit", "critical": true}), 0.0)
	var mage: float = BattleVfx.shake_for({"kind": "skill", "archetype": "mage"})
	for archetype: String in ["knight", "ranger", "rogue"]:
		var shake: float = BattleVfx.shake_for({"kind": "skill", "archetype": archetype})
		assert_gt(shake, 0.0, archetype)
		assert_lt(shake, mage, "%s shakes less than the mage burst" % archetype)
	assert_eq(BattleVfx.shake_for({"kind": "enemy_skill", "shape": "circle"}), mage)
	assert_gt(BattleVfx.shake_for({"kind": "enemy_skill", "shape": "line"}), 0.0)
	var view: BattleView = _view()
	view._play_event({"kind": "hit", "position": Vector3.ZERO, "damage": 5})
	assert_eq(view._shake_trauma, 0.0)
	view._play_event({"kind": "hit", "position": Vector3.ZERO, "damage": 5, "critical": true})
	assert_almost_eq(view._shake_trauma, BattleVfx.SHAKE_CRIT, 0.0001)


func test_camera_shake_runs_in_view_time_and_holds_while_paused() -> void:
	var view: BattleView = _view()
	view._shake_trauma = 1.0
	view._pause_requested = true
	view._update_shake(0.1)
	assert_eq(view._shake_trauma, 1.0, "paused, the shake does not decay")
	assert_eq(Vector2(view._camera.h_offset, view._camera.v_offset), Vector2.ZERO, "and the camera holds still")
	view._pause_requested = false
	view._set_view_time_scale(BattleView.SLOW_MO_SCALE)
	view._update_shake(0.1)
	assert_almost_eq(view._shake_trauma, 1.0 - BattleView.SHAKE_DECAY_PER_SECOND * 0.1 * BattleView.SLOW_MO_SCALE, 0.0001, "slow-mo slows the decay")
	assert_ne(Vector2(view._camera.h_offset, view._camera.v_offset), Vector2.ZERO)
	view._set_view_time_scale(1.0)
	view._update_shake(10.0)
	assert_eq(view._shake_trauma, 0.0)
	assert_eq(Vector2(view._camera.h_offset, view._camera.v_offset), Vector2.ZERO, "a spent shake leaves the camera centered")


func test_view_drops_all_units_when_a_retried_run_restarts_the_tick() -> void:
	SceneRouter.clear_battle_payload()
	var view: BattleView = (load("res://combat/battle/battle_view.tscn") as PackedScene).instantiate() as BattleView
	add_child_autofree(view)
	var dead_enemy: Dictionary = _actor("enemy:o:0:1", "enemy", "knight", {}, {"hp": 0.0, "life": "dead"})
	view._render_snapshot({"tick": 500, "actors": [_actor("a1", "ally", "knight", {}, {"hp": 30.0}), dead_enemy]})
	var corpse: BattleUnitView = view._unit_views["enemy:o:0:1"]
	assert_eq(corpse._animator.assigned_animation, &"Skeletons_Death")

	view._render_snapshot({"tick": 2, "actors": [_actor("a1", "ally", "knight"), _actor("enemy:o:0:1", "enemy", "knight")]})

	var fresh: BattleUnitView = view._unit_views["enemy:o:0:1"]
	assert_ne(fresh, corpse, "retried run gets a fresh unit view")
	assert_eq(fresh._animator.assigned_animation, &"Skeletons_Idle")
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
	assert_ne(late._animator.assigned_animation, &"Hit_A", "its unit has not flinched yet")
	view._process(step * 2.0 - 0.01)
	assert_eq(view._vfx.get_child_count(), 1)
	view._process(0.02)
	assert_eq(view._vfx.get_child_count(), 2, "it plays two ticks in")
	late._process(step * 2.0)
	assert_eq(late._animator.assigned_animation, &"Hit_A", "and the unit flinches with it")


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


func test_cleric_mend_lands_on_the_healed_ally_in_heal_color_without_a_shockwave() -> void:
	var previous: Dictionary = {
		"a1": _actor("a1", "ally", "cleric"),
		"a2": _actor("a2", "ally", "knight", {}, {"hp": 40.0, "position": [3.0, 1.0]}),
		"a3": _actor("a3", "ally", "rogue", {}, {"hp": 40.0, "position": [30.0, 0.0]}),
	}
	var actors: Array = [
		_actor("a1", "ally", "cleric", {"last_skill_tick": 5}),
		_actor("a2", "ally", "knight", {}, {"hp": 97.6, "position": [3.0, 1.0]}),
		_actor("a3", "ally", "rogue", {}, {"hp": 99.0, "position": [30.0, 0.0]}),
	]
	var skill: Dictionary = _first(BattleVfx.events_between(previous, actors), "skill")
	assert_eq(skill["center"], Vector3(3.0, 0.0, 1.0), "the healed ally in Mend's range, not one out of it")

	var vfx := BattleVfx.new()
	add_child_autofree(vfx)
	vfx.spawn(skill)
	var effect: Node = vfx.get_child(0)
	assert_eq(_rings(effect), 0, "a single-target heal has no shockwave")
	var impact: CPUParticles3D = effect.find_children("*", "CPUParticles3D", true, false)[0] as CPUParticles3D
	assert_eq(impact.color, BattleVfx.HEAL_COLOR, "not the enemy red")
	assert_almost_eq(impact.position.x, 3.0, 0.001)
	assert_eq(BattleVfx.shake_for(skill), 0.0)


func _actor(id: String, faction: String, archetype: String, effects: Dictionary = {}, fields: Dictionary = {}) -> Dictionary:
	var effect_state: Dictionary = {"last_hit_tick": 1, "last_skill_tick": 1, "attack_target_id": "", "telegraph_kind": "", "stun_remaining": 0.0}
	effect_state.merge(effects, true)
	var actor: Dictionary = {"id": id, "faction": faction, "archetype": archetype, "life": "alive", "hp": 100.0, "max_hp": 100.0, "attack_cooldown": 0.0, "position": [0.0, 0.0], "facing": [1.0, 0.0], "effect_state": effect_state}
	actor.merge(fields, true)
	return actor


func _rings(effect: Node) -> int:
	return effect.find_children("*", "MeshInstance3D", true, false).filter(func(mesh: Node) -> bool: return (mesh as MeshInstance3D).mesh is TorusMesh).size()


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
