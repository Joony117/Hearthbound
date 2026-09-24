extends GutTest


class FakeBattleController extends Node:
	signal battle_changed(order_id: String)

	var snapshots: Dictionary[String, Dictionary] = {}
	var commands: Array[Dictionary] = []
	var pause_values: Array[bool] = []
	var heroes: Dictionary[String, Hero] = {}
	var next_command_result: Dictionary = {"accepted": true, "error": "", "sequence": 1}


	func get_battle_snapshot(order_id: String) -> Dictionary:
		return snapshots.get(order_id, {}).duplicate(true)


	func issue_battle_command(order_id: String, command: Dictionary) -> Dictionary:
		commands.append(command.duplicate(true))
		return next_command_result.duplicate(true)


	func set_battle_paused(order_id: String, paused: bool) -> void:
		pause_values.append(paused)


	func hero_by_id(hero_id: String) -> Hero:
		return heroes.get(hero_id)


func test_rts_inputs_are_added_without_rebinding_legacy_arena_actions() -> void:
	assert_eq(_key_for_action(&"rts_pan_left"), KEY_A)
	assert_eq(_key_for_action(&"rts_pan_right"), KEY_D)
	assert_eq(_key_for_action(&"rts_pan_forward"), KEY_W)
	assert_eq(_key_for_action(&"rts_pan_back"), KEY_S)
	assert_eq(_mouse_button_for_action(&"rts_select"), MOUSE_BUTTON_LEFT)
	assert_eq(_mouse_button_for_action(&"rts_context"), MOUSE_BUTTON_RIGHT)
	assert_eq(_key_for_action(&"rts_additive_select"), KEY_SHIFT)
	assert_eq(_key_for_action(&"rts_hold"), KEY_H)
	assert_eq(_key_for_action(&"rts_guard"), KEY_G)
	assert_eq(_key_for_action(&"rts_retreat"), KEY_R)
	assert_eq(_key_for_action(&"rts_pause"), KEY_SPACE)
	assert_eq(_key_for_action(&"rts_squad_0"), KEY_0)
	assert_eq(_key_for_action(&"rts_squad_9"), KEY_9)
	assert_true((InputMap.action_get_events(&"rts_attack_move")[0] as InputEventKey).shift_pressed)
	assert_eq(_mouse_button_for_action(&"attack"), MOUSE_BUTTON_LEFT)
	assert_eq(_mouse_button_for_action(&"heavy_attack"), MOUSE_BUTTON_RIGHT)
	assert_eq(_key_for_action(&"dodge"), KEY_SPACE)


func test_live_view_renders_authored_camera_hud_units_and_objectives() -> void:
	var controller := _make_controller()
	var view := _make_live_view(controller)
	var camera: Camera3D = view.get_node("CameraRig/Camera3D") as Camera3D
	assert_eq(camera.projection, Camera3D.PROJECTION_ORTHOGONAL)
	assert_almost_eq(camera.size, 36.0, 0.001)
	assert_eq(view.get_node("CameraRig").position, Vector3(0.0, 0.0, -2.0))
	assert_eq(camera.position, Vector3(0.0, 32.0, 24.0))
	assert_eq((view.get_node("Ground").mesh as PlaneMesh).size, Vector2(80.0, 80.0))
	var command_panel: Control = view.get_node("HUD/CommandPanel") as Control
	var selected_panel: Control = view.get_node("HUD/SelectedPanel") as Control
	assert_eq(command_panel.size.y, 152.0)
	assert_eq(selected_panel.size.x, 402.0)
	assert_eq(view.get_node("Units").get_child_count(), 2)
	assert_eq(view.get_node("Objectives").get_child_count(), 1)
	assert_false(selected_panel.visible)
	assert_false(view._status_label.text.contains("Tick"))


func test_lmb_select_and_rmb_attack_use_the_live_command_bridge() -> void:
	var controller := _make_controller()
	var view := _make_live_view(controller)
	var camera: Camera3D = view.get_node("CameraRig/Camera3D") as Camera3D
	var ally: BattleUnitView = view.get_node("Units/Unit_hero-1") as BattleUnitView
	var enemy: BattleUnitView = view.get_node("Units/Unit_enemy-1") as BattleUnitView
	var ally_screen: Vector2 = camera.unproject_position(ally.global_position)
	var enemy_screen: Vector2 = camera.unproject_position(enemy.global_position)
	_send_mouse_button(view, MOUSE_BUTTON_LEFT, true, ally_screen)
	_send_mouse_button(view, MOUSE_BUTTON_LEFT, false, ally_screen)
	assert_eq(view._selected_ids, ["hero-1"])
	assert_true(view.get_node("HUD/SelectedPanel").visible)
	_send_mouse_button(view, MOUSE_BUTTON_RIGHT, true, enemy_screen)
	assert_eq(controller.commands.size(), 1)
	assert_eq(controller.commands[0]["kind"], "attack")
	assert_eq(controller.commands[0]["actor_ids"], ["hero-1"])
	assert_eq(controller.commands[0]["target_id"], "enemy-1")


func test_rmb_guards_living_ally_carries_downed_ally_and_moves_past_dead_or_hidden_units() -> void:
	var controller := _make_controller()
	controller.snapshots["battle-1"]["actors"].append(_actor("hero-2", "hero-2", "ally", "ranger", [0.0, 2.0]))
	var downed: Dictionary = _actor("body-1", "body-2", "ally", "knight", [2.0, 2.0])
	downed["life"] = BattleActor.LIFE_DOWNED
	controller.snapshots["battle-1"]["actors"].append(downed)
	var dead_enemy: Dictionary = _actor("enemy-dead", "", "enemy", "rogue", [5.0, 2.0])
	dead_enemy["life"] = BattleActor.LIFE_DEAD
	controller.snapshots["battle-1"]["actors"].append(dead_enemy)
	var view := _make_live_view(controller)
	var camera: Camera3D = view.get_node("CameraRig/Camera3D") as Camera3D
	view._selected_ids = ["hero-1"]
	view._issue_context_command(camera.unproject_position(Vector3(0.0, 0.0, 2.0)))
	assert_eq(controller.commands.back()["kind"], "guard")
	assert_eq(controller.commands.back()["target_id"], "hero-2")
	view._issue_context_command(camera.unproject_position(Vector3(2.0, 0.0, 2.0)))
	assert_eq(controller.commands.back()["kind"], "carry")
	assert_eq(controller.commands.back()["target_id"], "body-1")
	var dead_view: BattleUnitView = view._unit_views["enemy-dead"] as BattleUnitView
	view._issue_context_command(camera.unproject_position(dead_view.global_position))
	assert_eq(controller.commands.back()["kind"], "move", "Dead enemy bodies never intercept a ground move")
	var hidden_enemy: BattleUnitView = view._unit_views["enemy-1"] as BattleUnitView
	hidden_enemy.visible = false
	view._issue_context_command(camera.unproject_position(hidden_enemy.global_position))
	assert_eq(controller.commands.back()["kind"], "move", "Hidden actors never intercept a ground move")


func test_attack_move_is_consumed_and_rejected_reason_survives_context_click() -> void:
	var controller := _make_controller()
	var view := _make_live_view(controller)
	view._selected_ids = ["hero-1"]
	view._command_mode = "attack_move"
	controller.next_command_result = {"accepted": false, "error": "No living actors are selected.", "sequence": 0}
	view._issue_context_command(Vector2(640.0, 360.0))
	assert_eq(controller.commands.back()["kind"], "attack_move")
	assert_eq(view._command_mode, "")
	assert_eq(view._command_status.text, "No living actors are selected.")


func test_empty_live_snapshot_reports_end_disables_commands_and_keeps_last_display() -> void:
	var controller := _make_controller()
	var view := _make_live_view(controller)
	var old_actor_count: int = view._unit_views.size()
	controller.snapshots["battle-1"] = {}
	view._refresh_live_snapshot()
	assert_string_contains(view._status_label.text, "Battle ended · Return to hub for results")
	assert_eq(view._unit_views.size(), old_actor_count)
	assert_true(view._pause_button.disabled)
	assert_true(view._auto_battle.disabled)
	assert_true(view._selected_ability_button.disabled)
	assert_false(view._exit_button.disabled)
	var old_command_count: int = controller.commands.size()
	view._selected_ids = ["hero-1"]
	view._send_command({"kind": "hold", "actor_ids": ["hero-1"]})
	view._issue_context_command(Vector2(320.0, 180.0))
	view._set_paused(true)
	assert_eq(controller.commands.size(), old_command_count, "Ended battles reject commands through non-button input paths")
	assert_eq(controller.pause_values, [], "Ended battles reject pause changes")


func test_removing_paused_live_view_resumes_previous_order_and_preserves_unrelated_payload() -> void:
	var controller := _make_controller()
	var view := _make_live_view(controller)
	view._set_paused(true)
	assert_eq(controller.pause_values, [true])
	SceneRouter.prepare_battle("newly-prepared-order")
	view.free()
	assert_eq(controller.pause_values, [true, false], "Scene teardown always resumes its previous watched order")
	assert_false(controller.is_connected("battle_changed", Callable(view, "_on_battle_changed")))
	assert_eq(SceneRouter.battle_order_id, "newly-prepared-order", "Old view teardown cannot erase a newer router payload")
	SceneRouter.clear_battle_payload()


func test_manual_skill_waits_for_target_and_submits_one_ability_command() -> void:
	var controller := _make_controller()
	var view := _make_live_view(controller)
	var camera: Camera3D = view.get_node("CameraRig/Camera3D") as Camera3D
	var ally: BattleUnitView = view.get_node("Units/Unit_hero-1") as BattleUnitView
	var enemy: BattleUnitView = view.get_node("Units/Unit_enemy-1") as BattleUnitView
	view._selected_ids = ["hero-1"]
	view._on_selected_command_pressed("ability")
	view._issue_context_command(camera.unproject_position(enemy.global_position))
	assert_eq(controller.commands.size(), 1)
	assert_eq(controller.commands[0]["kind"], "ability")
	assert_eq(controller.commands[0]["actor_ids"], ["hero-1"])
	assert_eq(controller.commands[0]["target_id"], "enemy-1")


func test_inspector_controls_persist_and_show_signature_cooldown_and_item_policies() -> void:
	var hero := Hero.new("Inspector Knight", 0)
	hero.instance_id = "hero-1"
	hero.def_id = &"knight"
	GameSession.add_hero(hero)
	var controller := _make_controller()
	controller.heroes[hero.instance_id] = hero
	var view := _make_live_view(controller)
	view._selected_ids = ["hero-1"]
	view._render_snapshot(controller.snapshots["battle-1"])
	var skill_button: Button = view._selected_ability_button
	var squad_button: Button = view._squad_row.get_child(0) as Button
	assert_string_contains(view._selected_label.text, "Inspector Knight")
	assert_string_contains(skill_button.text, "Stand Fast")
	controller.snapshots["battle-1"]["actors"][0]["skill_cooldowns"]["knight_rally"] = 2.0
	view._render_snapshot(controller.snapshots["battle-1"])
	assert_eq(view._selected_ability_button, skill_button)
	assert_true(skill_button.disabled)
	assert_string_contains(skill_button.tooltip_text, "2.0 seconds")
	assert_eq(view._squad_row.get_child(0), squad_button)
	assert_eq(view._skills_row.get_child_count(), 2)
	view._on_auto_heal_toggled(false)
	assert_eq(controller.commands.back()["value"], {"auto_heal": false, "auto_revive": true})
	view._on_auto_revive_toggled(false)
	assert_eq(controller.commands.back()["value"], {"auto_heal": true, "auto_revive": false})


# ig-wgj.11: one draught button per tier; the masterwork one sends its tier with the target.
func test_the_inspector_shows_and_sends_both_draught_tiers() -> void:
	var controller := _make_controller()
	controller.snapshots["battle-1"]["supplies_remaining"] = {"healing": 0, "revival": 1, "healing_masterwork": 2, "revival_masterwork": 0}
	var view := _make_live_view(controller)
	var camera: Camera3D = view.get_node("CameraRig/Camera3D") as Camera3D
	var ally: BattleUnitView = view.get_node("Units/Unit_hero-1") as BattleUnitView
	view._selected_ids = ["hero-1"]
	view._render_snapshot(controller.snapshots["battle-1"])
	assert_eq(view._supply_label.text, "Healing 0 · Revival 1 · Masterwork healing 2 · Masterwork revival 0")
	assert_eq(view._item_buttons.keys(), BattleState.SUPPLY_KINDS)
	for supply_kind: String in view._item_buttons:
		var stocked: bool = int(controller.snapshots["battle-1"]["supplies_remaining"][supply_kind]) > 0
		assert_eq(view._item_buttons[supply_kind].disabled, not stocked, supply_kind)
	view._item_buttons["healing_masterwork"].pressed.emit()
	view._issue_context_command(camera.unproject_position(ally.global_position))
	assert_eq(controller.commands.back(), {"kind": "item_healing", "actor_ids": ["hero-1"], "target_id": "hero-1", "masterwork": true})
	view._item_buttons["revival"].pressed.emit()
	view._issue_context_command(camera.unproject_position(ally.global_position))
	assert_eq(controller.commands.back(), {"kind": "item_revival", "actor_ids": ["hero-1"], "target_id": "hero-1"}, "a regular draught names no tier")


func test_practice_view_uses_local_state_and_does_not_attach_live_controller() -> void:
	var hero := Hero.new("Practice Knight", 0)
	hero.def_id = &"knight"
	var zone: ZoneDefinition = load("res://zones/defs/verdant_outskirts.tres") as ZoneDefinition
	var profile_before: Dictionary = GameSession.to_dict()
	var view := load("res://combat/battle/battle_view.tscn").instantiate() as BattleView
	view.configure_practice([hero], zone)
	add_child_autofree(view)
	assert_eq(view._mode, "practice")
	assert_null(view._controller)
	assert_eq(view._practice_state.kind, "practice")
	assert_eq(GameSession.to_dict(), profile_before)


func test_practice_rejected_item_feedback_survives_local_snapshot_render() -> void:
	var hero := Hero.new("Feedback Knight", 0)
	hero.def_id = &"knight"
	var zone: ZoneDefinition = load("res://zones/defs/verdant_outskirts.tres") as ZoneDefinition
	var view: BattleView = (load("res://combat/battle/battle_view.tscn") as PackedScene).instantiate() as BattleView
	view.configure_practice([hero], zone)
	add_child_autofree(view)
	view._set_paused(true)
	view._practice_state.supplies_remaining["healing"] = 1
	var ally: BattleActor
	var enemy: BattleActor
	for actor: BattleActor in view._practice_state.actors:
		if actor.faction == "ally":
			ally = actor
		elif enemy == null:
			enemy = actor
	view._send_command({"kind": "item_healing", "actor_ids": [ally.id], "target_id": enemy.id})
	assert_eq(view._command_status.text, "Healing cannot resolve against that target now.")
	view._render_snapshot(view._practice_state.to_dict())
	assert_eq(view._command_status.text, "Healing cannot resolve against that target now.", "The local practice snapshot redraw must not erase rejected-command feedback")
	assert_eq(view._status_label.text, "Practice · Active")


func test_unprepared_battle_scene_shows_actionable_unavailable_state() -> void:
	SceneRouter.clear_battle_payload()
	var view: BattleView = (load("res://combat/battle/battle_view.tscn") as PackedScene).instantiate() as BattleView
	add_child_autofree(view)
	assert_eq(view._header_label.text, "Battle unavailable")
	assert_string_contains(view._status_label.text, "Return to the hub")
	assert_true(view._pause_button.disabled)
	assert_eq(view._exit_button.text, "Return to hub")


func test_rescue_watch_status_does_not_show_route_minimum() -> void:
	var controller := _make_controller()
	controller.snapshots["battle-1"]["kind"] = "rescue"
	controller.snapshots["battle-1"]["phase"] = "rescuing"
	controller.snapshots["battle-1"]["route_remaining_seconds"] = 0.0
	var view := _make_live_view(controller)
	assert_eq(view._status_label.text, "Rescue · Active")
	assert_false(view._status_label.text.contains("Route"))


func test_early_victory_status_explains_the_route_clock() -> void:
	var controller := _make_controller()
	controller.snapshots["battle-1"]["status"] = "victory"
	controller.snapshots["battle-1"]["route_remaining_seconds"] = 151.0
	var view := _make_live_view(controller)
	assert_eq(view._status_label.text, "Victory! Heading home · rewards in 02:31")
	controller.snapshots["battle-1"]["route_remaining_seconds"] = 0.0
	view._render_snapshot(controller.snapshots["battle-1"])
	assert_eq(view._status_label.text, "Victory   ·   Route minimum 00:00")


func test_selection_box_adds_multiple_allies_without_changing_saved_squads() -> void:
	var controller := _make_controller()
	controller.snapshots["battle-1"]["actors"].append(_actor("hero-2", "hero-2", "ally", "ranger", [-3.0, 0.0]))
	var view := _make_live_view(controller)
	var camera: Camera3D = view.get_node("CameraRig/Camera3D") as Camera3D
	var first: Vector2 = camera.unproject_position(Vector3(-3.0, 0.0, 0.0))
	var second: Vector2 = camera.unproject_position(Vector3(3.0, 0.0, 0.0))
	view._drag_start = first - Vector2(30.0, 30.0)
	view._drag_current = second + Vector2(30.0, 30.0)
	view._select_at_mouse(second, false)
	assert_eq(view._selected_ids.size(), 2)
	assert_eq(controller.snapshots["battle-1"]["squads"][0]["hero_ids"], ["hero-1"])


func test_zone_camera_presets_resize_apron_and_keep_perimeter_in_world() -> void:
	var controller := _make_controller()
	var view := _make_live_view(controller)
	var camera: Camera3D = view.get_node("CameraRig/Camera3D") as Camera3D
	var world_environment: WorldEnvironment = view.get_node("BattleWorldEnvironment") as WorldEnvironment
	assert_eq(world_environment.environment.background_mode, Environment.BG_COLOR)
	assert_eq(world_environment.environment.background_color, Color("18251f"))
	controller.snapshots["battle-1"]["zone_id"] = "fallen_citadel"
	view._render_snapshot(controller.snapshots["battle-1"])
	assert_almost_eq(camera.size, 44.0, 0.001)
	assert_eq((view.get_node("Ground").mesh as PlaneMesh).size, Vector2(140.0, 140.0))
	assert_eq((view.get_node("Boundary_0") as MeshInstance3D).position.z, -35.0)
	controller.snapshots["battle-1"]["zone_id"] = "frontier_march"
	view._render_snapshot(controller.snapshots["battle-1"])
	assert_almost_eq(camera.size, 60.0, 0.001)
	assert_eq((view.get_node("Ground").mesh as PlaneMesh).size, Vector2(200.0, 200.0))
	assert_eq((view.get_node("Boundary_0") as MeshInstance3D).position.z, -50.0)


func test_paused_practice_selection_refreshes_inspector_without_advancing_battle() -> void:
	var hero := Hero.new("Paused Practice Knight", 0)
	hero.def_id = &"knight"
	var zone: ZoneDefinition = load("res://zones/defs/verdant_outskirts.tres") as ZoneDefinition
	var view: BattleView = (load("res://combat/battle/battle_view.tscn") as PackedScene).instantiate() as BattleView
	view.configure_practice([hero], zone)
	add_child_autofree(view)
	view._set_paused(true)
	var tick_before: int = view._practice_state.tick
	var ally: BattleUnitView = view._unit_views.values()[0] as BattleUnitView
	var camera: Camera3D = view.get_node("CameraRig/Camera3D") as Camera3D
	view._select_at_mouse(camera.unproject_position(ally.global_position), false)
	assert_eq(view._practice_state.tick, tick_before)
	assert_true(view.get_node("HUD/SelectedPanel").visible)
	assert_string_contains(view._selected_label.text, "Paused Practice Knight")
	assert_string_contains(view._selected_label.text, "HP")
	assert_string_contains(view._selected_ability_button.text, "Stand Fast")
	assert_true(view._selected_auto_heal.visible)
	assert_true(view._selected_auto_revive.visible)
	assert_almost_eq(camera.size, 36.0, 0.001)


func _make_controller() -> FakeBattleController:
	var controller := FakeBattleController.new()
	controller.snapshots["battle-1"] = {
		"simulation_version": 1,
		"order_id": "battle-1",
		"zone_id": "verdant_outskirts",
		"kind": "normal",
		"status": "active",
		"tick": 0,
		"paused": false,
		"route_remaining_seconds": 90.0,
		"team_name": "Test Team",
		"actors": [
			_actor("hero-1", "hero-1", "ally", "knight", [-3.0, 0.0]),
			_actor("enemy-1", "", "enemy", "knight", [3.0, 0.0]),
		],
		"squads": [{"id": "squad-1", "name": "Test Squad", "hero_ids": ["hero-1"], "stance": "stay_together", "guard_target_id": ""}],
		"objective_state": {"markers": [{"id": "exit", "kind": "exit", "label": "Extraction", "position": [0.0, -16.0], "radius": 2.0, "progress": 0.0, "active": true, "complete": false}]},
		"supplies_remaining": {"healing": 1, "revival": 1},
		"policies": {"auto_battle": true, "auto_heal": true, "auto_revive": true},
	}
	return controller


func _make_live_view(controller: FakeBattleController) -> BattleView:
	add_child_autofree(controller)
	var packed: PackedScene = load("res://combat/battle/battle_view.tscn") as PackedScene
	var view: BattleView = packed.instantiate() as BattleView
	view.configure_live("battle-1", controller)
	add_child_autofree(view)
	for unit: BattleUnitView in view._unit_views.values():
		unit.global_position = unit.target_position
	return view


func _actor(actor_id: String, hero_id: String, faction: String, archetype: String, point: Array[float]) -> Dictionary:
	var kit := BattleActor.new()
	kit.archetype = archetype
	kit.set_default_kit()
	return {
		"id": actor_id,
		"hero_id": hero_id,
		"archetype": archetype,
		"faction": faction,
		"spawn_index": 0 if faction == "ally" else 1,
		"squad_id": "squad-1" if faction == "ally" else "",
		"position": point,
		"facing": [1.0, 0.0] if faction == "ally" else [-1.0, 0.0],
		"hp": 100.0,
		"max_hp": 100.0,
		"atk": 10.0,
		"defense": 10.0,
		"speed": 20.0,
		"crit_rate": 0.05,
		"crit_damage": 1.5,
		"life": "alive",
		"attack_range": 1.6,
		"move_speed": 2.0,
		"attack_cooldown": 0.0,
		"item_cooldown": 0.0,
		"order_kind": "",
		"order_target_id": "",
		"order_point": [0.0, 0.0],
		"carried_by_id": "",
		"carrying_id": "",
		"guard_target_id": "",
		"skills": kit.skills,
		"skill_cooldowns": kit.skill_cooldowns,
		"effect_state": {},
	}


func _send_mouse_button(view: BattleView, button: int, pressed: bool, point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = point
	view._unhandled_input(event)


func _key_for_action(action: StringName) -> int:
	var events: Array[InputEvent] = InputMap.action_get_events(action)
	assert_eq(events.size(), 1, "Expected one configured key for %s" % action)
	var key_event: InputEventKey = events[0] as InputEventKey
	assert_not_null(key_event)
	return key_event.physical_keycode


func _mouse_button_for_action(action: StringName) -> int:
	var events: Array[InputEvent] = InputMap.action_get_events(action)
	assert_eq(events.size(), 1, "Expected one configured mouse button for %s" % action)
	var mouse_event: InputEventMouseButton = events[0] as InputEventMouseButton
	assert_not_null(mouse_event)
	return mouse_event.button_index
