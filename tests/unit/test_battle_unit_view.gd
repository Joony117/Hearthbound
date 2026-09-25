extends GutTest


func test_enemy_that_dies_plays_its_death_clip_and_hides_overlays() -> void:
	var unit: BattleUnitView = _unit({"life": "alive", "effect_state": _live_effects()})
	unit.set_selected(true)
	assert_true(unit._hp_bar.visible, "a hurt enemy shows its HP bar")
	assert_true(unit._elite_ring.visible, "alive elite shows its ring")
	assert_true(unit._guard_bubble.visible, "a damage-reduction status shows the guard bubble")
	assert_eq(unit._animator.assigned_animation, &"Skeletons_Idle")

	unit.set_actor(_actor({"life": "dead", "effect_state": _live_effects()}), true)
	assert_eq(unit._animator.assigned_animation, &"Skeletons_Death")
	assert_lt(unit._animator.current_animation_position, 0.1, "death animates rather than snapping")
	await wait_seconds(0.5)

	_assert_dead_look(unit)


func test_death_clip_holds_its_last_frame() -> void:
	var unit: BattleUnitView = _unit({"life": "alive"})
	unit.set_actor(_actor({"life": "dead"}), false)
	unit._animator.advance(5.0)
	unit._process(0.1)
	assert_eq(unit._animator.assigned_animation, &"Skeletons_Death", "the finished fall is not replaced")
	assert_false(unit._animator.is_playing(), "it stops on the last frame instead of looping")


func test_unit_first_seen_dead_snaps_to_final_pose() -> void:
	var unit: BattleUnitView = _unit({"life": "dead", "effect_state": _live_effects()})
	assert_almost_eq(unit._animator.current_animation_position, unit._animator.current_animation_length, 0.001)
	assert_almost_eq(unit._pivot.position.y, 0.0, 0.001)
	_assert_dead_look(unit)


func test_dead_unit_hides_a_line_telegraph() -> void:
	var line_effects: Dictionary = _live_effects()
	line_effects["telegraph_kind"] = "line"
	line_effects["telegraph_origin"] = [0.0, 0.0]
	var unit: BattleUnitView = _unit({"life": "dead", "effect_state": line_effects})
	_assert_dead_look(unit)


func test_hits_and_skills_do_not_reanimate_a_corpse() -> void:
	var unit: BattleUnitView = _unit({"life": "alive", "effect_state": {"last_hit_tick": 1, "last_skill_tick": 1}})
	unit.set_actor(_actor({"life": "dead", "effect_state": {"last_hit_tick": 2, "last_skill_tick": 2}}), false)
	unit.set_actor(_actor({"life": "dead", "effect_state": {"last_hit_tick": 3, "last_skill_tick": 3, "last_crit_tick": 3}}), false)
	unit.lunge(Vector3(0.0, 0.0, 4.0))
	await wait_process_frames(2)
	assert_eq(unit._animator.assigned_animation, &"Skeletons_Death")


func test_downed_ally_holds_death_b_and_revives_to_idle() -> void:
	var unit: BattleUnitView = _unit({"faction": "ally", "archetype": "knight", "life": "downed"})
	assert_eq(unit._animator.assigned_animation, &"Death_B")
	assert_true(unit._downed_marker.visible)
	assert_false(unit._hp_bar.visible, "downed hides the HP bar")
	unit.set_actor(_actor({"faction": "ally", "archetype": "knight", "life": "alive"}), false)
	assert_eq(unit._animator.assigned_animation, &"Idle_A", "revive goes back to idle")
	assert_false(unit._downed_marker.visible)
	unit.set_actor(_actor({"faction": "ally", "archetype": "knight", "life": "downed"}), false)
	assert_eq(unit._animator.assigned_animation, &"Death_B")
	assert_lt(unit._animator.current_animation_position, 0.1, "a live fall animates")


func test_crit_recoils_further_back_along_facing_then_springs_home() -> void:
	var unit: BattleUnitView = _unit({"hp": 20.0, "effect_state": {"last_hit_tick": 1, "last_crit_tick": 0}})
	unit.set_actor(_actor({"hp": 19.0, "effect_state": {"last_hit_tick": 2, "last_crit_tick": 2}}), false)
	unit._recoil_tween.custom_step(BattleUnitView.RECOIL_OUT_SECONDS)
	assert_almost_eq(_recoil_offset(unit), Vector3(-BattleUnitView.RECOIL_CRIT_DISTANCE, 0.0, 0.0), Vector3.ONE * 0.01, "pushed back along -facing")
	unit._recoil_tween.custom_step(BattleUnitView.RECOIL_BACK_SECONDS)
	assert_almost_eq(_recoil_offset(unit), Vector3.ZERO, Vector3.ONE * 0.01, "springs home")
	assert_almost_eq(unit.global_position, Vector3.ZERO, Vector3.ONE * 0.001, "the unit root never moves")


## ig-36y: the recoil and the fling follow the sim's hit_from; a real push plays no recoil (the slide is it).
func test_recoil_and_fling_follow_the_hit_and_a_pushed_hit_does_not_recoil() -> void:
	var unit: BattleUnitView = _unit({"hp": 20.0, "effect_state": {"last_hit_tick": 1, "last_crit_tick": 0}})
	unit.set_actor(_actor({"hp": 19.0, "effect_state": {"last_hit_tick": 2, "last_crit_tick": 2, "hit_from": [0.0, 1.0]}}), false)
	unit._recoil_tween.custom_step(BattleUnitView.RECOIL_OUT_SECONDS)
	assert_almost_eq(_recoil_offset(unit), Vector3(0.0, 0.0, BattleUnitView.RECOIL_CRIT_DISTANCE), Vector3.ONE * 0.01, "along the hit, not -facing")

	var pushed: BattleUnitView = _unit({"hp": 20.0, "effect_state": {"last_hit_tick": 1, "last_crit_tick": 0, "last_push_tick": 0}})
	pushed.set_actor(_actor({"hp": 19.0, "effect_state": {"last_hit_tick": 2, "last_crit_tick": 2, "last_push_tick": 2, "hit_from": [0.0, 1.0]}}), false)
	assert_null(pushed._recoil_tween, "the real slide is the recoil")
	assert_eq(pushed._animator.assigned_animation, &"Hit_B", "the crit still reads")

	var first_push: BattleUnitView = _unit({"hp": 20.0, "effect_state": {"last_hit_tick": 1, "last_crit_tick": 0}})
	first_push.set_actor(_actor({"hp": 19.0, "effect_state": {"last_hit_tick": 2, "last_crit_tick": 2, "last_push_tick": 2}}), false)
	assert_null(first_push._recoil_tween, "a first push, the key new since the last render, also skips it")

	var later_hit: BattleUnitView = _unit({"hp": 20.0, "effect_state": {"last_hit_tick": 1, "last_crit_tick": 0, "last_push_tick": 0}})
	later_hit.set_actor(_actor({"hp": 19.0, "effect_state": {"last_hit_tick": 12, "last_crit_tick": 12, "last_push_tick": 11}}), false)
	assert_not_null(later_hit._recoil_tween, "a push, then a later gated crit in the same render: that crit recoils")

	var killed: BattleUnitView = _unit({"hp": 20.0, "effect_state": {"last_hit_tick": 1, "last_crit_tick": 0}})
	killed.set_actor(_actor({"hp": 0.0, "life": "dead", "effect_state": {"last_hit_tick": 2, "last_crit_tick": 0, "hit_from": [0.0, -1.0]}}), false)
	await wait_seconds(BattleUnitView.DEAD_TWEEN_SECONDS + 0.2)
	assert_almost_eq(_pivot_offset(killed), Vector3(0.0, 0.0, -BattleUnitView.FLING_DISTANCE), Vector3.ONE * 0.01, "the corpse flies along the hit")


func test_heavy_hit_recoils_and_light_hit_does_not() -> void:
	var heavy: BattleUnitView = _unit({"hp": 20.0, "effect_state": {"last_hit_tick": 1}})
	heavy.set_actor(_actor({"hp": 15.0, "effect_state": {"last_hit_tick": 2}}), false)
	heavy._recoil_tween.custom_step(BattleUnitView.RECOIL_OUT_SECONDS)
	assert_almost_eq(_recoil_offset(heavy), Vector3(-BattleUnitView.RECOIL_DISTANCE, 0.0, 0.0), Vector3.ONE * 0.01)

	var light: BattleUnitView = _unit({"hp": 20.0, "effect_state": {"last_hit_tick": 1}})
	light.set_actor(_actor({"hp": 18.0, "effect_state": {"last_hit_tick": 2}}), false)
	assert_null(light._recoil_tween, "a 10% hit does not recoil")


func test_killing_crit_skips_recoil_and_in_flight_recoil_does_not_fight_death() -> void:
	var killed: BattleUnitView = _unit({"hp": 20.0, "effect_state": {"last_hit_tick": 1, "last_crit_tick": 0}})
	killed.set_actor(_actor({"hp": 0.0, "life": "dead", "effect_state": {"last_hit_tick": 2, "last_crit_tick": 2}}), false)
	assert_null(killed._recoil_tween, "the death tween wins")

	var staggered: BattleUnitView = _unit({"hp": 20.0, "effect_state": {"last_hit_tick": 1, "last_crit_tick": 0}})
	staggered.set_actor(_actor({"hp": 19.0, "effect_state": {"last_hit_tick": 2, "last_crit_tick": 2}}), false)
	staggered.set_actor(_actor({"hp": 0.0, "life": "dead", "effect_state": {"last_hit_tick": 3, "last_crit_tick": 2}}), false)
	await wait_seconds(0.5)
	assert_almost_eq(staggered._recoil_offset, Vector3.ZERO, Vector3.ONE * 0.01, "the recoil springs home under the death fling")
	assert_eq(staggered._animator.assigned_animation, &"Skeletons_Death")
	assert_almost_eq(staggered._pivot.position.y, 0.0, 0.01)


func test_hit_plays_hit_a_and_crit_plays_hit_b_then_back_to_idle() -> void:
	var hit: BattleUnitView = _unit({"hp": 20.0, "effect_state": {"last_hit_tick": 1}})
	hit.set_actor(_actor({"hp": 19.0, "effect_state": {"last_hit_tick": 2}}), false)
	assert_eq(hit._animator.assigned_animation, &"Hit_A")
	hit._animator.advance(1.0)
	hit._process(0.01)
	assert_eq(hit._animator.assigned_animation, &"Skeletons_Idle", "the hit plays once")

	var crit: BattleUnitView = _unit({"hp": 20.0, "effect_state": {"last_hit_tick": 1, "last_crit_tick": 0}})
	crit.set_actor(_actor({"hp": 19.0, "effect_state": {"last_hit_tick": 2, "last_crit_tick": 2}}), false)
	assert_eq(crit._animator.assigned_animation, &"Hit_B")

	var idle: BattleUnitView = _unit({"hp": 20.0, "effect_state": {"last_hit_tick": 1}})
	idle.set_actor(_actor({"hp": 20.0, "effect_state": {"last_hit_tick": 1}}), false)
	assert_eq(idle._animator.assigned_animation, &"Skeletons_Idle", "no hit, no hit clip")


func test_killing_hit_plays_the_death_clip_not_a_hit() -> void:
	var killed: BattleUnitView = _unit({"hp": 20.0, "effect_state": {"last_hit_tick": 1}})
	killed.set_actor(_actor({"hp": 0.0, "life": "dead", "effect_state": {"last_hit_tick": 2}}), false)
	assert_eq(killed._animator.assigned_animation, &"Skeletons_Death")
	killed.set_actor(_actor({"hp": 0.0, "life": "dead", "effect_state": {"last_hit_tick": 3}}), false)
	assert_eq(killed._animator.assigned_animation, &"Skeletons_Death")


func test_crit_kill_flings_the_corpse_further_and_it_lands_at_rest() -> void:
	var crit: BattleUnitView = _unit({"hp": 20.0, "effect_state": {"last_hit_tick": 1, "last_crit_tick": 0}})
	crit.set_actor(_actor({"hp": 0.0, "life": "dead", "effect_state": {"last_hit_tick": 2, "last_crit_tick": 2}}), false)
	var plain: BattleUnitView = _unit({"hp": 20.0, "effect_state": {"last_hit_tick": 1, "last_crit_tick": 0}})
	plain.set_actor(_actor({"hp": 0.0, "life": "dead", "effect_state": {"last_hit_tick": 2, "last_crit_tick": 0}}), false)
	await wait_seconds(BattleUnitView.DEAD_TWEEN_SECONDS * 0.5)
	assert_gt(crit._fling_arc, 0.1, "the corpse arcs up mid-fling")
	await wait_seconds(0.4)
	# Facing is +x, so the fling slides the corpse along -x.
	assert_almost_eq(_pivot_offset(crit), Vector3(-BattleUnitView.FLING_CRIT_DISTANCE, 0.0, 0.0), Vector3.ONE * 0.01)
	assert_almost_eq(_pivot_offset(plain), Vector3(-BattleUnitView.FLING_DISTANCE, 0.0, 0.0), Vector3.ONE * 0.01)
	assert_almost_eq(crit._fling_arc, 0.0, 0.001, "the arc lands")
	assert_almost_eq(crit._pivot.position.y, 0.0, 0.01)


func test_unit_first_seen_dead_is_not_flung() -> void:
	var unit: BattleUnitView = _unit({"life": "dead", "effect_state": {"last_hit_tick": 3, "last_crit_tick": 3}})
	assert_eq(unit._fling_offset, Vector3.ZERO)
	assert_almost_eq(_pivot_offset(unit), Vector3.ZERO, Vector3.ONE * 0.001)


func test_lunge_moves_toward_the_target_and_returns() -> void:
	var unit: BattleUnitView = _unit({"hp": 20.0})
	unit.lunge(Vector3(0.0, 0.0, 4.0))
	assert_eq(unit._animator.assigned_animation, &"Melee_1H_Attack_Chop", "the lunge plays the attack clip")
	unit._lunge_tween.custom_step(BattleUnitView.LUNGE_OUT_SECONDS)
	assert_almost_eq(_pivot_offset(unit), Vector3(0.0, 0.0, BattleUnitView.LUNGE_DISTANCE), Vector3.ONE * 0.01)
	unit._lunge_tween.custom_step(BattleUnitView.LUNGE_BACK_SECONDS)
	assert_almost_eq(_pivot_offset(unit), Vector3.ZERO, Vector3.ONE * 0.01)


func test_recoil_during_a_lunge_sums_and_both_end_at_zero() -> void:
	var unit: BattleUnitView = _unit({"hp": 20.0, "effect_state": {"last_hit_tick": 1, "last_crit_tick": 0}})
	unit.lunge(Vector3(0.0, 0.0, 4.0))
	unit._lunge_tween.custom_step(BattleUnitView.LUNGE_OUT_SECONDS)
	unit.set_actor(_actor({"hp": 19.0, "effect_state": {"last_hit_tick": 2, "last_crit_tick": 2}}), false)
	unit._recoil_tween.custom_step(BattleUnitView.RECOIL_OUT_SECONDS)
	assert_almost_eq(_pivot_offset(unit), unit._lunge_offset + Vector3(-BattleUnitView.RECOIL_CRIT_DISTANCE, 0.0, 0.0), Vector3.ONE * 0.01, "both offsets show at once")
	unit._recoil_tween.custom_step(BattleUnitView.RECOIL_BACK_SECONDS)
	unit._lunge_tween.custom_step(BattleUnitView.LUNGE_BACK_SECONDS)
	assert_almost_eq(_pivot_offset(unit), Vector3.ZERO, Vector3.ONE * 0.01)


func test_hit_stop_freezes_tweens_and_lerp_then_releases() -> void:
	var unit: BattleUnitView = _unit({"hp": 20.0})
	unit.lunge(Vector3(0.0, 0.0, 4.0))
	unit.hit_stop()
	unit._lunge_tween.custom_step(0.03)
	assert_eq(unit._lunge_offset, Vector3.ZERO, "tweens freeze")
	unit.set_actor(_actor({"hp": 20.0, "position": [5.0, 0.0]}), false, 0.25)
	unit._process(0.03)
	assert_eq(unit.global_position, Vector3.ZERO, "the glide freezes")
	unit._process(BattleUnitView.HIT_STOP_SECONDS)
	unit._lunge_tween.custom_step(BattleUnitView.LUNGE_OUT_SECONDS)
	assert_almost_eq(unit._lunge_offset.length(), BattleUnitView.LUNGE_DISTANCE, 0.01, "tweens resume")
	unit._process(0.05)
	assert_gt(unit.global_position.x, 0.0, "the glide resumes")


func test_time_scale_reaches_live_tweens() -> void:
	var unit: BattleUnitView = _unit({"hp": 20.0})
	unit.lunge(Vector3(0.0, 0.0, 4.0))
	unit.set_time_scale(0.35)
	unit._lunge_tween.custom_step(BattleUnitView.LUNGE_OUT_SECONDS)
	assert_between(unit._lunge_offset.length(), 0.05, BattleUnitView.LUNGE_DISTANCE * 0.5, "a slowed lunge covers well under full distance")


func test_clip_speed_follows_time_scale_and_hit_stop() -> void:
	var unit: BattleUnitView = BattleUnitView.new()
	unit.set_actor(_actor({}), false)
	unit.set_time_scale(0.25)
	add_child_autofree(unit)
	assert_almost_eq(unit._animator.speed_scale, 0.25, 0.001, "a scale set before the model exists still reaches it")
	unit.hit_stop()
	assert_eq(unit._animator.speed_scale, 0.0, "hit-stop freezes the clip")
	unit._process(BattleUnitView.HIT_STOP_SECONDS)
	assert_almost_eq(unit._animator.speed_scale, 0.25, 0.001)


func test_hp_bar_shows_when_hurt_or_selected_and_hides_at_full_or_dead() -> void:
	var full: BattleUnitView = _unit({"hp": 20.0})
	assert_false(full._hp_bar.visible, "full HP hides the bar")
	full.set_selected(true)
	full._update_status()
	assert_true(full._hp_bar.visible, "selected shows it at full HP")
	var hurt: BattleUnitView = _unit({"hp": 5.0})
	assert_true(hurt._hp_bar.visible)
	assert_almost_eq((hurt._hp_fill.mesh as QuadMesh).size.x, BattleUnitView.BAR_WIDTH * 0.25, 0.001)
	var elite: BattleUnitView = _unit({"hp": 5.0, "effect_state": {"elite": true}})
	assert_almost_eq((elite._hp_back.mesh as QuadMesh).size.x, BattleUnitView.BAR_ELITE_WIDTH, 0.001)
	var ally: BattleUnitView = _unit({"faction": "ally", "archetype": "knight", "hp": 5.0})
	assert_eq((ally._hp_fill.material_override as StandardMaterial3D).albedo_color, BattleUnitView.BAR_ALLY_COLOR)


func test_chip_trails_damage_and_snaps_on_heal() -> void:
	var unit: BattleUnitView = _unit({"hp": 20.0})
	unit.set_actor(_actor({"hp": 10.0}), false)
	assert_almost_eq((unit._hp_fill.mesh as QuadMesh).size.x, BattleUnitView.BAR_WIDTH * 0.5, 0.001, "fill drops at once")
	assert_almost_eq(unit._chip_fraction, 1.0, 0.001, "chip still at the old HP")
	unit._chip_tween.custom_step(BattleUnitView.BAR_CHIP_SECONDS * 0.5)
	assert_between(unit._chip_fraction, 0.5, 1.0, "chip is on its way down")
	unit._chip_tween.custom_step(BattleUnitView.BAR_CHIP_SECONDS)
	assert_almost_eq(unit._chip_fraction, 0.5, 0.001)

	unit.set_actor(_actor({"hp": 5.0}), false)
	unit.set_actor(_actor({"hp": 15.0}), false)
	assert_almost_eq(unit._chip_fraction, 0.75, 0.001, "a heal snaps the chip")
	assert_almost_eq((unit._hp_fill.mesh as QuadMesh).size.x, BattleUnitView.BAR_WIDTH * 0.75, 0.001, "fill rises at once")


func test_hit_reaction_does_not_resize_telegraphs() -> void:
	var unit: BattleUnitView = _unit({"hp": 20.0, "effect_state": _hit_effects(1)})
	unit.set_actor(_actor({"hp": 19.0, "effect_state": _hit_effects(2)}), false)
	assert_eq(unit._animator.assigned_animation, &"Hit_A", "the hit is in flight")
	assert_eq(unit._telegraph_ring.get_parent(), unit)
	assert_almost_eq(unit._telegraph_ring.global_basis.get_scale(), Vector3.ONE, Vector3.ONE * 0.001)
	assert_almost_eq(unit._telegraph_line.global_basis.get_scale(), Vector3.ONE, Vector3.ONE * 0.001)


func test_extracted_unit_hides_its_hp_bar() -> void:
	var unit: BattleUnitView = _unit({"faction": "ally", "archetype": "knight", "hp": 5.0, "life": "extracted"})
	assert_false(unit._hp_bar.visible)


func test_bar_layers_share_one_priority_and_sort_inside_the_bar() -> void:
	var first: BattleUnitView = _unit({"hp": 5.0})
	var second: BattleUnitView = _unit({"hp": 5.0})
	var layers: Array[MeshInstance3D] = [first._hp_back, first._hp_chip, first._hp_fill]
	for index: int in layers.size():
		assert_eq((layers[index].material_override as StandardMaterial3D).render_priority, BattleUnitView.BAR_RENDER_PRIORITY)
		assert_false(layers[index].sorting_use_aabb_center)
		assert_almost_eq(layers[index].sorting_offset, 0.01 * index, 0.0001)
	assert_same(first._hp_fill.material_override, second._hp_fill.material_override, "bar materials are shared")


func _hit_effects(tick: int) -> Dictionary:
	var effects: Dictionary = _live_effects()
	effects["last_hit_tick"] = tick
	return effects


func test_a_new_unit_appears_where_it_stands_instead_of_flying_in() -> void:
	var unit: BattleUnitView = _unit({"position": [3.0, -2.0]})
	assert_eq(unit.position, Vector3(3.0, 0.0, -2.0))
	unit._process(0.1)
	assert_eq(unit.position, Vector3(3.0, 0.0, -2.0))


func test_glide_moves_at_a_steady_speed_and_keeps_moving_when_retargeted() -> void:
	var unit: BattleUnitView = _unit({})
	unit.set_actor(_actor({"position": [4.0, 0.0]}), false, 0.25)
	assert_eq(unit.position, Vector3.ZERO, "one render behind: it starts from where it is drawn")
	unit._process(0.125)
	assert_almost_eq(unit.position, Vector3(2.0, 0.0, 0.0), Vector3.ONE * 0.001, "linear, not a dash that eases out")
	unit.set_actor(_actor({"position": [8.0, 0.0]}), false, 0.25)
	unit._process(0.125)
	assert_almost_eq(unit.position, Vector3(5.0, 0.0, 0.0), Vector3.ONE * 0.001, "the next render continues from the drawn spot")
	unit._process(0.2)
	assert_almost_eq(unit.position, Vector3(8.0, 0.0, 0.0), Vector3.ONE * 0.001)
	unit.set_actor(_actor({"position": [8.0, 0.0]}), false, 0.25)
	unit._process(0.1)
	assert_almost_eq(unit.position, Vector3(8.0, 0.0, 0.0), Vector3.ONE * 0.001, "an unchanged render does not restart the glide")


func test_gliding_plays_the_move_clip_and_arriving_plays_idle() -> void:
	var ally: BattleUnitView = _unit({"faction": "ally", "archetype": "mage"})
	ally.set_actor(_actor({"faction": "ally", "archetype": "mage", "position": [4.0, 0.0]}), false, 0.25)
	ally._process(0.1)
	assert_eq(ally._animator.assigned_animation, &"Running_A")
	ally._process(0.2)
	assert_eq(ally._animator.assigned_animation, &"Idle_A")
	var enemy: BattleUnitView = _unit({})
	enemy.set_actor(_actor({"position": [4.0, 0.0]}), false, 0.25)
	enemy._process(0.1)
	assert_eq(enemy._animator.assigned_animation, &"Skeletons_Walking")


func test_zero_glide_snaps() -> void:
	var unit: BattleUnitView = _unit({})
	unit.set_actor(_actor({"position": [4.0, 0.0]}), false, 0.0)
	assert_eq(unit.position, Vector3(4.0, 0.0, 0.0))


func test_delayed_reaction_waits_then_flinches_and_a_delayed_kill_tips_over_after_it() -> void:
	var unit: BattleUnitView = _unit({"hp": 20.0, "effect_state": {"last_hit_tick": 1, "last_crit_tick": 0}})
	unit.set_actor(_actor({"hp": 19.0, "effect_state": {"last_hit_tick": 2, "last_crit_tick": 2}}), false, 0.25, 0.1)
	assert_null(unit._recoil_tween, "no recoil before its tick")
	assert_eq(unit._animator.assigned_animation, &"Skeletons_Idle", "no hit clip before its tick")
	unit._process(0.1)
	assert_not_null(unit._recoil_tween, "the crit recoils on its tick")
	assert_eq(unit._animator.assigned_animation, &"Hit_B")

	var killed: BattleUnitView = _unit({"hp": 20.0, "effect_state": {"last_hit_tick": 1}})
	killed.set_actor(_actor({"hp": 0.0, "life": "dead", "effect_state": {"last_hit_tick": 2}}), false, 0.25, 0.1)
	assert_false(killed._dead_posed, "the corpse waits for its killing hit")
	killed._process(0.1)
	assert_true(killed._dead_posed)


func test_each_archetype_wears_its_model_weapons_and_attack_clip() -> void:
	var expected: Array = [
		["ally", "knight", "Knight", {"handslot.r": "sword_1handed", "handslot.l": "shield_round"}, &"Melee_1H_Attack_Chop"],
		["ally", "mage", "Mage", {"handslot.r": "staff"}, &"Ranged_Magic_Shoot"],
		["ally", "ranger", "Ranger", {"handslot.l": "bow_withString"}, &"Ranged_Bow_Release"],
		["ally", "rogue", "Rogue", {"handslot.r": "dagger", "handslot.l": "dagger"}, &"Melee_Dualwield_Attack_Stab"],
		["ally", "cleric", "Mage", {"handslot.r": "wand"}, &"Ranged_Magic_Shoot"],
		["enemy", "knight", "Skeleton_Warrior", {"handslot.r": "Skeleton_Blade", "handslot.l": "Skeleton_Shield_Small_A"}, &"Melee_1H_Attack_Chop"],
		["enemy", "rogue", "Skeleton_Rogue", {"handslot.r": "Skeleton_Blade"}, &"Melee_Dualwield_Attack_Stab"],
		["enemy", "mage", "Skeleton_Mage", {"handslot.r": "Skeleton_Staff"}, &"Ranged_Magic_Shoot"],
		["enemy", "ranger", "Skeleton_Rogue", {"handslot.r": "Skeleton_Crossbow"}, &"Ranged_1H_Shoot"],
	]
	for row: Array in expected:
		var unit: BattleUnitView = _unit({"faction": row[0], "archetype": row[1], "hp": 20.0})
		var model: Node3D = unit._animator.get_parent() as Node3D
		assert_eq(model.scene_file_path, "%scharacters/%s.glb" % [HeroModel.MODEL_DIR, row[2]], "%s %s model" % [row[0], row[1]])
		var held: Dictionary = {}
		for slot: Node in model.find_children("*", "BoneAttachment3D", true, false):
			var weapon: Node = slot.get_child(0) if slot.get_child_count() > 0 else null
			if weapon != null and not weapon.scene_file_path.is_empty():
				assert_gt((slot as BoneAttachment3D).bone_idx, -1, "%s %s %s resolves to a real bone" % [row[0], row[1], (slot as BoneAttachment3D).bone_name])
				held[(slot as BoneAttachment3D).bone_name] = weapon.scene_file_path.get_file().get_basename()
		var weapons: Dictionary = row[3]
		for bone: String in weapons:
			assert_eq(held.get(bone, ""), weapons[bone], "%s %s holds %s in %s" % [row[0], row[1], weapons[bone], bone])
		assert_eq(held.size(), weapons.size(), "%s %s holds nothing else" % [row[0], row[1]])
		unit.lunge(Vector3(0.0, 0.0, 4.0))
		assert_eq(unit._animator.assigned_animation, row[4], "%s %s attack clip" % [row[0], row[1]])


func test_a_projectile_attacker_plays_its_attack_when_its_cooldown_restarts() -> void:
	var ranger: BattleUnitView = _unit({"faction": "ally", "archetype": "ranger", "hp": 20.0, "attack_cooldown": 0.0})
	ranger.set_actor(_actor({"faction": "ally", "archetype": "ranger", "hp": 20.0, "attack_cooldown": 0.7}), false)
	assert_eq(ranger._animator.assigned_animation, &"Ranged_Bow_Release")
	var knight: BattleUnitView = _unit({"faction": "ally", "archetype": "knight", "hp": 20.0, "attack_cooldown": 0.0})
	knight.set_actor(_actor({"faction": "ally", "archetype": "knight", "hp": 20.0, "attack_cooldown": 0.7}), false)
	assert_eq(knight._animator.assigned_animation, &"Idle_A", "melee attacks wait for the lunge")


func test_units_share_one_clip_library_with_loops_set_and_root_motion_pinned() -> void:
	var source: Node = (load(HeroModel.MODEL_DIR + "animations/Rig_Medium_Special.glb") as PackedScene).instantiate()
	var source_player: AnimationPlayer = source.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	assert_gt(source_player.get_animation(&"Skeletons_Death").find_track(NodePath("Rig_Medium/Skeleton3D:root"), Animation.TYPE_POSITION_3D), -1, "the source clip has the root track the pin removes")
	source.free()
	var first: BattleUnitView = _unit({})
	var second: BattleUnitView = _unit({"faction": "ally", "archetype": "rogue"})
	assert_same(first._animator.get_animation_library(&""), second._animator.get_animation_library(&""))
	var library: AnimationLibrary = first._animator.get_animation_library(&"")
	for clip: String in HeroModel.CLIP_FILES:
		var animation: Animation = library.get_animation(clip)
		assert_eq(animation.loop_mode == Animation.LOOP_LINEAR, clip in HeroModel.LOOPED_CLIPS, "%s loop mode" % clip)
		assert_eq(animation.find_track(NodePath("Rig_Medium/Skeleton3D:root"), Animation.TYPE_POSITION_3D), -1, "%s root is pinned" % clip)


func test_the_falls_drop_in_place_with_the_hips_pinned_on_the_ground() -> void:
	var source: Node = (load(HeroModel.MODEL_DIR + "animations/Rig_Medium_Special.glb") as PackedScene).instantiate()
	var raw: Animation = (source.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer).get_animation(&"Skeletons_Death")
	var raw_track: int = raw.find_track(HeroModel.HIPS_POSITION_TRACK, Animation.TYPE_POSITION_3D)
	var raw_start: Vector3 = raw.track_get_key_value(raw_track, 0)
	var raw_end: Vector3 = raw.track_get_key_value(raw_track, raw.track_get_key_count(raw_track) - 1)
	assert_gt(Vector2(raw_end.x - raw_start.x, raw_end.z - raw_start.z).length(), 1.0, "the source fall drifts, so the pin matters")
	source.free()
	var library: AnimationLibrary = HeroModel.shared_clips()
	assert_eq(HeroModel.FALL_CLIPS, ["Death_A", "Death_B", "Skeletons_Death"] as Array[String])
	for clip: String in HeroModel.FALL_CLIPS:
		var animation: Animation = library.get_animation(clip)
		var track: int = animation.find_track(HeroModel.HIPS_POSITION_TRACK, Animation.TYPE_POSITION_3D)
		assert_gt(track, -1, "%s keeps its hips track" % clip)
		var first: Vector3 = animation.track_get_key_value(track, 0)
		for key: int in animation.track_get_key_count(track):
			var value: Vector3 = animation.track_get_key_value(track, key)
			assert_almost_eq(Vector2(value.x, value.z), Vector2(first.x, first.z), Vector2(1e-4, 1e-4), "%s key %d stays on its spot" % [clip, key])
		var last: Vector3 = animation.track_get_key_value(track, animation.track_get_key_count(track) - 1)
		assert_lt(last.y, first.y, "%s still drops" % clip)


func test_a_cleric_has_no_hat_and_wears_a_shared_halo_until_it_dies() -> void:
	var cleric_model: Node3D = HeroModel.build("ally", "cleric")
	var mage_model: Node3D = HeroModel.build("ally", "mage")
	assert_null(cleric_model.find_child("Mage_Hat", true, false), "the cleric's hat is off")
	assert_not_null(mage_model.find_child("Mage_Hat", true, false), "the mage keeps its hat")
	cleric_model.free()
	mage_model.free()
	var cleric: BattleUnitView = _unit({"faction": "ally", "archetype": "cleric", "id": "ally-1"})
	var other: BattleUnitView = _unit({"faction": "ally", "archetype": "cleric", "id": "ally-2", "life": "downed"})
	var mage: BattleUnitView = _unit({"faction": "ally", "archetype": "mage", "id": "ally-3"})
	assert_null(mage._halo, "a mage has no halo")
	assert_eq((cleric._halo.get_parent() as BoneAttachment3D).bone_name, "head")
	assert_gt((cleric._halo.get_parent() as BoneAttachment3D).bone_idx, -1, "the head bone resolves")
	assert_same(cleric._halo.mesh, BattleUnitView._halo_mesh)
	assert_same(other._halo.mesh, BattleUnitView._halo_mesh, "one halo mesh")
	assert_same(cleric._halo.material_override, BattleUnitView._halo_material)
	assert_same(other._halo.material_override, BattleUnitView._halo_material, "one halo material")
	assert_ne(BattleUnitView.HALO_COLOR, BattleUnitView.ALLY_COLOR)
	assert_true(cleric._halo.visible)
	assert_true(other._halo.visible, "a downed cleric keeps its halo")
	assert_false(cleric._halo in cleric._flash_meshes, "the halo never flashes or dims")
	cleric.set_actor(_actor({"faction": "ally", "archetype": "cleric", "id": "ally-1", "hp": 0.0, "life": "dead"}), false)
	await wait_seconds(0.5)
	assert_false(cleric._halo.visible, "a dead cleric loses its halo")


func test_clips_drive_the_skeleton() -> void:
	var unit: BattleUnitView = _unit({"faction": "ally", "archetype": "knight", "hp": 20.0})
	var skeleton: Skeleton3D = unit._animator.get_parent().get_node("Rig_Medium/Skeleton3D") as Skeleton3D
	var spine: int = skeleton.find_bone("spine")
	unit.lunge(Vector3(0.0, 0.0, 4.0))
	# Frame-sized steps: one 0.4 s jump lands on the pending seek and barely moves the pose.
	for step: int in 4:
		unit._animator.advance(0.1)
	var rest: Quaternion = skeleton.get_bone_rest(spine).basis.get_rotation_quaternion()
	assert_gt(skeleton.get_bone_pose_rotation(spine).angle_to(rest), 0.1, "the chop twists the spine away from the rest pose")


func test_telegraph_line_points_along_its_aim() -> void:
	for facing: Array in [[1.0, 0.0], [0.6, 0.8]]:
		var effects: Dictionary = _live_effects()
		effects["telegraph_kind"] = "line"
		effects["telegraph_origin"] = [0.0, 0.0]
		effects["telegraph_point"] = [4.0, 4.0]
		var unit: BattleUnitView = _unit({"facing": facing, "effect_state": effects})
		var aim: Vector3 = Vector3(4.0, 0.0, 4.0).normalized()
		assert_true(unit._telegraph_line.visible)
		assert_almost_eq(absf(unit._telegraph_line.global_basis.z.normalized().dot(aim)), 1.0, 0.001, "facing %s" % str(facing))


func test_hit_flash_shares_one_overlay_and_crits_flash_brighter_and_longer() -> void:
	var plain: BattleUnitView = _unit({"archetype": "knight"})
	var crit: BattleUnitView = _unit({"archetype": "mage", "id": "enemy-2"})
	plain._react({"hit": true, "skill": false, "critical": false, "heavy": false})
	crit._react({"hit": true, "skill": false, "critical": true, "heavy": false})
	assert_gt(plain._flash_meshes.size(), 1)
	for unit: BattleUnitView in [plain, crit]:
		for mesh: MeshInstance3D in unit._flash_meshes:
			assert_same(mesh.material_overlay, BattleUnitView._flash_material, "one overlay for the whole battle")
	assert_gt(float(crit._flash_meshes[0].get_instance_shader_parameter(&"flash")), float(plain._flash_meshes[0].get_instance_shader_parameter(&"flash")), "crits flash brighter")
	plain._flash_tween.custom_step(BattleUnitView.HIT_FLASH_SECONDS + 0.01)
	crit._flash_tween.custom_step(BattleUnitView.HIT_FLASH_SECONDS + 0.01)
	assert_null(plain._flash_meshes[0].material_overlay, "the overlay comes off when the flash ends")
	assert_same(crit._flash_meshes[0].material_overlay, BattleUnitView._flash_material, "crits flash longer")


func test_every_unit_stands_on_a_shared_faction_ring_until_it_dies() -> void:
	var ally: BattleUnitView = _unit({"faction": "ally", "archetype": "knight", "id": "ally-1"})
	var other_ally: BattleUnitView = _unit({"faction": "ally", "archetype": "mage", "id": "ally-2", "life": "downed"})
	var enemy: BattleUnitView = _unit({})
	for unit: BattleUnitView in [ally, other_ally, enemy]:
		assert_true(unit._faction_ring.visible, "%s %s shows its ring" % [unit.faction, unit.life])
		assert_same(unit._faction_ring.mesh, BattleUnitView._faction_ring_mesh, "one ring mesh for the battle")
	assert_same(ally._faction_ring.material_override, BattleUnitView._ally_ring_material)
	assert_same(other_ally._faction_ring.material_override, BattleUnitView._ally_ring_material)
	assert_same(enemy._faction_ring.material_override, BattleUnitView._enemy_ring_material)
	assert_ne(BattleUnitView.ALLY_COLOR, BattleUnitView.ENEMY_COLOR)
	for mesh: MeshInstance3D in enemy._flash_meshes:
		assert_null(mesh.material_overlay, "the living are not dimmed")


func test_the_killing_hit_flashes_before_the_corpse_dims() -> void:
	var unit: BattleUnitView = _unit({"effect_state": {"last_hit_tick": 1}})
	unit.set_actor(_actor({"hp": 0.0, "life": "dead", "effect_state": {"last_hit_tick": 2}}), false)
	assert_same(unit._flash_meshes[0].material_overlay, BattleUnitView._flash_material, "the blow still flashes")
	unit._flash_tween.custom_step(BattleUnitView.HIT_FLASH_SECONDS + 0.01)
	assert_same(unit._flash_meshes[0].material_overlay, BattleUnitView._corpse_material, "then the corpse dims")


func test_no_flash_without_a_landed_hit() -> void:
	var unit: BattleUnitView = _unit({})
	unit._react({"hit": false, "skill": true, "critical": false, "heavy": false})
	assert_null(unit._flash_meshes[0].material_overlay)


func test_an_animated_fall_lands_once_and_a_corpse_seen_dead_never_does() -> void:
	var falling: BattleUnitView = _unit({"effect_state": {"last_hit_tick": 1}})
	watch_signals(falling)
	falling.set_actor(_actor({"hp": 0.0, "life": "dead", "effect_state": {"last_hit_tick": 2}}), false)
	falling._on_clip_finished(&"Hit_A")
	assert_signal_not_emitted(falling, "body_landed", "a hit clip ending is not the landing")
	falling._on_clip_finished(&"Skeletons_Death")
	falling._on_clip_finished(&"Skeletons_Death")
	assert_signal_emit_count(falling, "body_landed", 1)
	var corpse: BattleUnitView = _unit({"hp": 0.0, "life": "dead"})
	watch_signals(corpse)
	corpse._on_clip_finished(&"Skeletons_Death")
	assert_signal_not_emitted(corpse, "body_landed")


func _pivot_offset(unit: BattleUnitView) -> Vector3:
	var offset: Vector3 = unit._pivot.global_position - unit.global_position
	offset.y = 0.0
	return offset


func _recoil_offset(unit: BattleUnitView) -> Vector3:
	var offset: Vector3 = unit._pivot.global_position - unit.global_position
	offset.y = 0.0
	return offset


func _assert_dead_look(unit: BattleUnitView) -> void:
	assert_eq(unit._animator.assigned_animation, &"Skeletons_Death")
	assert_false(unit._hp_bar.visible, "HP bar hidden")
	assert_false(unit._elite_ring.visible, "elite ring hidden")
	assert_false(unit._state_label.visible, "state label hidden")
	assert_false(unit._guard_bubble.visible, "guard bubble hidden")
	assert_false(unit._telegraph_ring.visible, "telegraph ring hidden")
	assert_false(unit._telegraph_line.visible, "telegraph line hidden")
	assert_false(unit._selection_ring.visible, "selection ring hidden")
	assert_false(unit._downed_marker.visible, "downed marker hidden")
	assert_false(unit._faction_ring.visible, "faction ring hidden")
	for mesh: MeshInstance3D in unit._flash_meshes:
		assert_same(mesh.material_overlay, BattleUnitView._corpse_material, "the corpse is dimmed")


func test_a_hero_that_answers_a_telegraph_names_its_counter() -> void:
	var unit: BattleUnitView = _unit({"faction": "ally", "effect_state": {"last_skill_tick": 3, "last_skill_id": "knight_rally"}})
	assert_eq(unit._counter_label.modulate.a, 0.0, "a skill cast before the view saw it is no answer")
	unit.set_actor(_actor({"faction": "ally", "effect_state": {"last_skill_tick": 9, "last_skill_id": "knight_buckler_blow", "last_counter_tick": 9}}), false)
	assert_eq(unit._counter_label.text, "Buckler Blow!")
	assert_eq(unit._counter_label.modulate.a, 1.0)
	unit.set_actor(_actor({"faction": "ally", "effect_state": {"last_skill_tick": 12, "last_skill_id": "knight_rally", "last_counter_tick": 9}}), false)
	assert_eq(unit._counter_label.text, "Buckler Blow!", "a picked skill is not an answer")


# Mirrors battle_view: set_actor runs before the node enters the tree.
func _unit(overrides: Dictionary) -> BattleUnitView:
	var unit := BattleUnitView.new()
	unit.set_actor(_actor(overrides), false)
	add_child_autofree(unit)
	return unit


func _actor(overrides: Dictionary) -> Dictionary:
	var actor: Dictionary = {
		"id": "enemy-1",
		"faction": "enemy",
		"archetype": "knight",
		"life": "alive",
		"hp": 10.0,
		"max_hp": 20.0,
		"position": [0.0, 0.0],
		"facing": [1.0, 0.0],
		"statuses": [{"id": "knight_rally", "kind": "damage_reduction", "source": "", "remaining": 1.0, "magnitude": 0.3}],
	}
	actor.merge(overrides, true)
	return actor


func _live_effects() -> Dictionary:
	return {
		"elite": true,
		"attack_windup_remaining": 0.5,
		"telegraph_kind": "circle",
		"telegraph_remaining": 1.0,
		"telegraph_point": [1.0, 1.0],
		"telegraph_radius": 2.0,
	}
