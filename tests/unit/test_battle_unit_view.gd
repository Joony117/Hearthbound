extends GutTest


func test_enemy_that_dies_tips_over_greys_out_and_hides_overlays() -> void:
	var unit: BattleUnitView = _unit({"life": "alive", "effect_state": _live_effects()})
	unit.set_selected(true)
	assert_true(unit._hp_bar.visible, "a hurt enemy shows its HP bar")
	assert_true(unit._elite_ring.visible, "alive elite shows its ring")
	assert_eq(unit._pivot.rotation.z, 0.0)

	unit.set_actor(_actor({"life": "dead", "effect_state": _live_effects()}), true)
	assert_lt(unit._pivot.rotation.z, 0.1, "death animates rather than snapping")
	await wait_seconds(0.5)

	assert_almost_eq(unit._pivot.rotation.z, BattleUnitView.DEAD_TILT, 0.01)
	_assert_dead_look(unit)


func test_unit_first_seen_dead_snaps_to_final_pose() -> void:
	var unit: BattleUnitView = _unit({"life": "dead", "effect_state": _live_effects()})
	assert_almost_eq(unit._pivot.rotation.z, BattleUnitView.DEAD_TILT, 0.001)
	assert_almost_eq(unit._pivot.position.y, BattleUnitView.DEAD_LIFT, 0.001)
	_assert_dead_look(unit)


func test_dead_unit_hides_a_line_telegraph() -> void:
	var line_effects: Dictionary = _live_effects()
	line_effects["telegraph_kind"] = "line"
	line_effects["telegraph_origin"] = [0.0, 0.0]
	var unit: BattleUnitView = _unit({"life": "dead", "effect_state": line_effects})
	_assert_dead_look(unit)


func test_hit_and_skill_flash_do_not_repaint_a_corpse() -> void:
	var unit: BattleUnitView = _unit({"life": "alive", "effect_state": {"last_hit_tick": 1, "last_skill_tick": 1}})
	unit.set_actor(_actor({"life": "dead", "effect_state": {"last_hit_tick": 2, "last_skill_tick": 2}}), false)
	await wait_process_frames(2)
	assert_eq((unit._body.material_override as StandardMaterial3D).albedo_color, BattleUnitView.DEAD_COLOR)
	assert_eq((unit._head.material_override as StandardMaterial3D).albedo_color, BattleUnitView.DEAD_COLOR)


func test_downed_ally_keeps_its_downed_look() -> void:
	var unit: BattleUnitView = _unit({"faction": "ally", "archetype": "knight", "life": "downed"})
	assert_eq(unit._pivot.rotation.z, 0.0)
	assert_true(unit._downed_marker.visible)
	assert_false(unit._head.visible)
	assert_false(unit._hp_bar.visible, "downed hides the HP bar")
	assert_ne((unit._body.material_override as StandardMaterial3D).albedo_color, BattleUnitView.DEAD_COLOR)


func test_crit_recoils_further_back_along_facing_then_springs_home() -> void:
	var unit: BattleUnitView = _unit({"hp": 20.0, "effect_state": {"last_hit_tick": 1, "last_crit_tick": 0}})
	unit.set_actor(_actor({"hp": 19.0, "effect_state": {"last_hit_tick": 2, "last_crit_tick": 2}}), false)
	unit._recoil_tween.custom_step(BattleUnitView.RECOIL_OUT_SECONDS)
	assert_almost_eq(_recoil_offset(unit), Vector3(-BattleUnitView.RECOIL_CRIT_DISTANCE, 0.0, 0.0), Vector3.ONE * 0.01, "pushed back along -facing")
	unit._recoil_tween.custom_step(BattleUnitView.RECOIL_BACK_SECONDS)
	assert_almost_eq(_recoil_offset(unit), Vector3.ZERO, Vector3.ONE * 0.01, "springs home")
	assert_almost_eq(unit.global_position, Vector3.ZERO, Vector3.ONE * 0.001, "the unit root never moves")


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
	assert_almost_eq(staggered._pivot.rotation.z, BattleUnitView.DEAD_TILT, 0.01)
	assert_almost_eq(staggered._pivot.position.y, BattleUnitView.DEAD_LIFT, 0.01)


func test_hit_squashes_and_crit_squashes_harder() -> void:
	var hit: BattleUnitView = _unit({"hp": 20.0, "effect_state": {"last_hit_tick": 1}})
	hit.set_actor(_actor({"hp": 19.0, "effect_state": {"last_hit_tick": 2}}), false)
	assert_almost_eq(hit._pivot.scale, BattleUnitView.SQUASH_SCALE, Vector3.ONE * 0.001)
	hit._squash_tween.custom_step(BattleUnitView.SQUASH_SECONDS)
	assert_almost_eq(hit._pivot.scale, Vector3.ONE, Vector3.ONE * 0.001, "springs back")

	var crit: BattleUnitView = _unit({"hp": 20.0, "effect_state": {"last_hit_tick": 1, "last_crit_tick": 0}})
	crit.set_actor(_actor({"hp": 19.0, "effect_state": {"last_hit_tick": 2, "last_crit_tick": 2}}), false)
	assert_almost_eq(crit._pivot.scale, BattleUnitView.SQUASH_CRIT_SCALE, Vector3.ONE * 0.001)

	var idle: BattleUnitView = _unit({"hp": 20.0, "effect_state": {"last_hit_tick": 1}})
	idle.set_actor(_actor({"hp": 20.0, "effect_state": {"last_hit_tick": 1}}), false)
	assert_null(idle._squash_tween, "no hit, no squash")


func test_killing_hit_and_corpse_hits_do_not_squash() -> void:
	var killed: BattleUnitView = _unit({"hp": 20.0, "effect_state": {"last_hit_tick": 1}})
	killed.set_actor(_actor({"hp": 0.0, "life": "dead", "effect_state": {"last_hit_tick": 2}}), false)
	assert_null(killed._squash_tween)
	killed.set_actor(_actor({"hp": 0.0, "life": "dead", "effect_state": {"last_hit_tick": 3}}), false)
	assert_null(killed._squash_tween)
	assert_eq(killed._pivot.scale, Vector3.ONE)


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
	assert_almost_eq(crit._pivot.position.y, BattleUnitView.DEAD_LIFT, 0.01)


func test_unit_first_seen_dead_is_not_flung() -> void:
	var unit: BattleUnitView = _unit({"life": "dead", "effect_state": {"last_hit_tick": 3, "last_crit_tick": 3}})
	assert_eq(unit._fling_offset, Vector3.ZERO)
	assert_almost_eq(_pivot_offset(unit), Vector3.ZERO, Vector3.ONE * 0.001)


func test_lunge_moves_toward_the_target_and_returns() -> void:
	var unit: BattleUnitView = _unit({"hp": 20.0})
	unit.lunge(Vector3(0.0, 0.0, 4.0))
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


func test_squash_does_not_resize_telegraphs() -> void:
	var unit: BattleUnitView = _unit({"hp": 20.0, "effect_state": _hit_effects(1)})
	unit.set_actor(_actor({"hp": 19.0, "effect_state": _hit_effects(2)}), false)
	assert_ne(unit._pivot.scale, Vector3.ONE, "squash is in flight")
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


func test_zero_glide_snaps() -> void:
	var unit: BattleUnitView = _unit({})
	unit.set_actor(_actor({"position": [4.0, 0.0]}), false, 0.0)
	assert_eq(unit.position, Vector3(4.0, 0.0, 0.0))


func test_delayed_reaction_waits_then_flinches_and_a_delayed_kill_tips_over_after_it() -> void:
	var unit: BattleUnitView = _unit({"hp": 20.0, "effect_state": {"last_hit_tick": 1, "last_crit_tick": 0}})
	unit.set_actor(_actor({"hp": 19.0, "effect_state": {"last_hit_tick": 2, "last_crit_tick": 2}}), false, 0.25, 0.1)
	assert_null(unit._recoil_tween, "no recoil before its tick")
	assert_eq(unit._hit_flash_remaining, 0.0)
	unit._process(0.1)
	assert_not_null(unit._recoil_tween, "the crit recoils on its tick")

	var killed: BattleUnitView = _unit({"hp": 20.0, "effect_state": {"last_hit_tick": 1}})
	killed.set_actor(_actor({"hp": 0.0, "life": "dead", "effect_state": {"last_hit_tick": 2}}), false, 0.25, 0.1)
	assert_false(killed._dead_posed, "the corpse waits for its killing hit")
	killed._process(0.1)
	assert_true(killed._dead_posed)


func _pivot_offset(unit: BattleUnitView) -> Vector3:
	var offset: Vector3 = unit._pivot.global_position - unit.global_position
	offset.y = 0.0
	return offset


func _recoil_offset(unit: BattleUnitView) -> Vector3:
	var offset: Vector3 = unit._pivot.global_position - unit.global_position
	offset.y = 0.0
	return offset


func _assert_dead_look(unit: BattleUnitView) -> void:
	for part: MeshInstance3D in unit._body_parts:
		assert_eq((part.material_override as StandardMaterial3D).albedo_color, BattleUnitView.DEAD_COLOR)
	assert_false(unit._hp_bar.visible, "HP bar hidden")
	assert_false(unit._elite_ring.visible, "elite ring hidden")
	assert_false(unit._state_label.visible, "state label hidden")
	assert_false(unit._guard_bubble.visible, "guard bubble hidden")
	assert_false(unit._telegraph_ring.visible, "telegraph ring hidden")
	assert_false(unit._telegraph_line.visible, "telegraph line hidden")
	assert_false(unit._selection_ring.visible, "selection ring hidden")
	assert_false(unit._downed_marker.visible, "downed marker hidden")


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
		"life": "alive",
		"hp": 10.0,
		"max_hp": 20.0,
		"position": [0.0, 0.0],
		"facing": [1.0, 0.0],
	}
	actor.merge(overrides, true)
	return actor


func _live_effects() -> Dictionary:
	return {
		"elite": true,
		"guard_remaining": 1.0,
		"attack_windup_remaining": 0.5,
		"telegraph_kind": "circle",
		"telegraph_remaining": 1.0,
		"telegraph_point": [1.0, 1.0],
		"telegraph_radius": 2.0,
	}
