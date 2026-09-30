extends GutTest

## ig-gy0.6, boundary #2 (the scene <-> script seam): Take Control, the hotbar, the 1-0 keys and the aim click of the
## piloted hero. The watched view is driven through a fake controller that, like GameSession, records set_battle_piloted,
## puts it in the snapshot and says the battle changed.

const Controls = preload("res://tests/unit/test_battle_controls.gd")
const FRAME: float = 1.0 / 60.0


class PilotController extends Node:
	signal battle_changed(order_id: String)

	var snapshots: Dictionary[String, Dictionary] = {}
	var commands: Array[Dictionary] = []
	var pause_values: Array[bool] = []
	var pilots: Array[String] = []
	var expedition_reports: Array[Dictionary] = []


	func get_battle_snapshot(order_id: String) -> Dictionary:
		return snapshots.get(order_id, {}).duplicate(true)


	func issue_battle_command(_order_id: String, command: Dictionary) -> Dictionary:
		commands.append(command.duplicate(true))
		return {"accepted": true, "error": "", "sequence": 1}


	func set_battle_paused(_order_id: String, paused: bool) -> void:
		pause_values.append(paused)


	func set_battle_piloted(order_id: String, actor_id: String) -> void:
		pilots.append(actor_id)
		if not snapshots.has(order_id):
			return  # a finished order, as in GameSession: nothing to tell
		snapshots[order_id]["piloted"] = actor_id
		battle_changed.emit(order_id)


	func hero_by_id(_hero_id: String) -> Hero:
		return null


## GUT's own controls made click-through by _point_on, with their filters, put back after each test.
var _uncovered: Array = []


func after_each() -> void:
	for entry: Array in _uncovered:
		if is_instance_valid(entry[0]):
			(entry[0] as Control).mouse_filter = entry[1]
	_uncovered.clear()


func test_take_control_selects_the_pilot_and_pressing_it_again_or_the_key_hands_the_hero_back() -> void:
	var controller: PilotController = _controller()
	var view: BattleView = _live_view(controller)
	view._on_take_control_pressed()
	assert_eq(controller.pilots, [], "nobody selected: nothing to take")
	assert_eq(view._command_status.text, "Select a hero to take control of")
	assert_false(view._pilot_bar.visible)

	view._selected_ids = ["hero-1"]
	view._on_take_control_pressed()
	assert_eq(controller.pilots, ["hero-1"])
	assert_eq(view._piloted_id, "hero-1")
	assert_eq(view._selected_ids, ["hero-1"], "the pilot is the selection")
	assert_true(view._pilot_bar.visible, "the hotbar is up")
	assert_eq(view._take_control_button.text, "Release Control (T)")
	view._on_take_control_pressed()
	assert_eq(controller.pilots, ["hero-1", ""], "again: given back")
	assert_eq(view._piloted_id, "")
	assert_false(view._pilot_bar.visible)
	assert_eq(view._take_control_button.text, "Take Control (T)")

	# The key does what the button does; a second hero picked while piloting switches.
	view._selected_ids = ["hero-1"]
	_press(view, KEY_T)
	assert_eq(controller.pilots, ["hero-1", "", "hero-1"], "T takes control")
	view._selected_ids = ["hero-2"]
	_press(view, KEY_T)
	assert_eq(controller.pilots, ["hero-1", "", "hero-1", "hero-2"], "another hero picked: switched, not released")
	assert_eq(view._selected_ids, ["hero-2"])
	_press(view, KEY_T)
	assert_eq(controller.pilots.back(), "", "the pick is the pilot: T gives it back")
	assert_eq(controller.commands.size(), 0, "no command was sent")


func test_keys_1_to_0_fire_hotbar_slots_only_while_piloting_and_select_squads_otherwise() -> void:
	var controller: PilotController = _controller()
	var view: BattleView = _live_view(controller)
	view._selected_ids.clear()
	_press(view, KEY_1)
	assert_eq(view._selected_ids, ["hero-1"], "no pilot: 1 selects squad 1 as ever")
	assert_eq(controller.commands.size(), 0)

	view._selected_ids.clear()
	view._set_piloted("hero-1")
	_press(view, KEY_1)
	assert_true(view._selected_ids.is_empty(), "piloting: 1 selects no squad")
	assert_eq(controller.commands.size(), 1)
	assert_eq(controller.commands[0], {"kind": "use_skill", "actor_ids": ["hero-1"], "skill_id": "knight_iron_cut"}, "it fires slot 1")
	_press(view, KEY_2)
	assert_eq(controller.commands[1], {"kind": "use_skill", "actor_ids": ["hero-1"], "skill_id": "knight_rally"}, "slot 2, in bar order")
	_press(view, KEY_4)
	_press(view, KEY_0)
	assert_eq(controller.commands.size(), 2, "a slot with no skill (the passive is not on the bar) fires nothing")

	# An area skill waits for the click: a unit clicked is its target, the ground its point.
	_press(view, KEY_3)
	assert_eq(view._pilot_aim_skill, "mage_burst")
	assert_eq(controller.commands.size(), 2, "not sent yet")
	assert_string_contains(view._command_status.text, "Arcane Bloom")
	var camera: Camera3D = view.get_node("CameraRig/Camera3D") as Camera3D
	var enemy: BattleUnitView = view.get_node("Units/Unit_enemy-1") as BattleUnitView
	view._issue_context_command(camera.unproject_position(enemy.global_position))
	assert_eq(controller.commands.size(), 3)
	assert_eq(controller.commands[2]["skill_id"], "mage_burst")
	assert_eq(controller.commands[2]["target_id"], "enemy-1", "a unit clicked")
	assert_eq(view._pilot_aim_skill, "", "the aim is spent")
	_press(view, KEY_3)
	view._issue_context_command(camera.unproject_position(Vector3(0.0, 0.0, 8.0)))
	assert_eq(controller.commands.size(), 4)
	assert_true(controller.commands[3].has("point") and not controller.commands[3].has("target_id"), "or the ground")
	assert_almost_eq(float(controller.commands[3]["point"][1]), 8.0, 0.05)

	# Given back, the keys are the squads' again.
	view._set_piloted("")
	view._selected_ids.clear()
	_press(view, KEY_1)
	assert_eq(view._selected_ids, ["hero-1"])
	assert_eq(controller.commands.size(), 4)


func test_the_hotbar_and_the_keys_act_on_the_pilot_whatever_is_selected_and_right_clicks_go_to_the_selection() -> void:
	var controller: PilotController = _controller()
	var view: BattleView = _live_view(controller)
	view._selected_ids = ["hero-1"]
	view._on_take_control_pressed()
	view._selected_ids = ["hero-2"]
	_press(view, KEY_1)
	assert_eq(controller.commands.back()["actor_ids"], ["hero-1"], "the skill is the pilot's, the selection notwithstanding")
	var camera: Camera3D = view.get_node("CameraRig/Camera3D") as Camera3D
	var enemy: BattleUnitView = view.get_node("Units/Unit_enemy-1") as BattleUnitView
	view._issue_context_command(camera.unproject_position(enemy.global_position))
	assert_eq(controller.commands.back()["kind"], "attack")
	assert_eq(controller.commands.back()["actor_ids"], ["hero-2"], "a right-click orders the selection")
	_press(view, KEY_3)
	view._selected_ids.clear()
	view._issue_context_command(camera.unproject_position(enemy.global_position))
	assert_eq(controller.commands.back()["kind"], "use_skill", "an aim click needs no selection")
	assert_eq(controller.commands.back()["actor_ids"], ["hero-1"])


func test_the_hotbar_lists_the_bar_in_order_with_off_skills_cooldowns_the_next_swing_and_a_scroll() -> void:
	var controller: PilotController = _controller()
	var view: BattleView = _live_view(controller)
	view._selected_ids = ["hero-1"]
	view._on_take_control_pressed()
	assert_eq(view._pilot_buttons.size(), 3, "abilities and weaponskills, the passive off the bar")
	assert_true(view._pilot_buttons[0].text.begins_with("1  Iron Cut"))
	assert_true(view._pilot_buttons[1].text.begins_with("2  Stand Fast"))
	assert_true(view._pilot_buttons[2].text.begins_with("3  Arcane Bloom"), "an Off skill is there: the player fires it in any mode")
	assert_true(view._pilot_slots.get_parent() is ScrollContainer, "and the bar scrolls")
	for button: Button in view._pilot_buttons:
		assert_eq(button.focus_mode, Control.FOCUS_NONE)
		assert_false(button.disabled)
	assert_eq(view._take_control_button.focus_mode, Control.FOCUS_NONE)

	var hero: Dictionary = controller.snapshots["battle-1"]["actors"][0]
	hero["skill_cooldowns"]["knight_rally"] = 5.0
	hero["effect_state"]["next_swing_skill"] = "knight_iron_cut"
	controller.battle_changed.emit("battle-1")
	assert_true(view._pilot_buttons[1].disabled, "cooling")
	assert_string_contains(view._pilot_buttons[1].text, "5.0s")
	assert_string_contains(view._pilot_buttons[0].text, "next swing")

	# A clickable button per skill, however many: past the tenth there is no key, only the button.
	var ids: Array[String] = []
	for skill: AbilityDefinition in BattleSimulation.ABILITIES.values():
		if skill.kind != "passive" and ids.size() < 12:
			ids.append(str(skill.skill_id))
	var bar: Array = []
	for id: String in ids:
		bar.append({"id": id, "mode": "auto"})
	hero["skills"] = bar
	controller.battle_changed.emit("battle-1")
	assert_eq(view._pilot_buttons.size(), 12)
	assert_false(view._pilot_buttons[11].text.begins_with("1"), "no key label past the tenth")
	var before: int = controller.commands.size()
	view._pilot_buttons[11].pressed.emit()
	var skill: AbilityDefinition = BattleSimulation.ABILITIES[ids[11]]
	assert_true(controller.commands.size() == before + 1 or view._pilot_aim_skill == ids[11], "the twelfth is clickable: %s fired or aimed" % skill.display_name)


func test_editable_text_focus_suppresses_the_pilot_keys() -> void:
	var controller: PilotController = _controller()
	var view: BattleView = _live_view(controller)
	view._selected_ids = ["hero-1"]
	var field := LineEdit.new()
	add_child_autofree(field)
	field.grab_focus()
	assert_true(field.has_focus(), "setup: the field holds the focus")
	_press(view, KEY_T)
	assert_eq(view._piloted_id, "", "typing a T takes no control")
	view._set_piloted("hero-1")
	_press(view, KEY_1)
	assert_eq(controller.commands.size(), 0, "typing a 1 fires no skill")
	field.release_focus()
	_press(view, KEY_1)
	assert_eq(controller.commands.size(), 1, "with the field let go it does")


func test_space_pauses_after_a_hotbar_click_and_fires_nothing_again() -> void:
	var controller: PilotController = _controller()
	var view: BattleView = _live_view(controller)
	view._selected_ids = ["hero-1"]
	view._on_take_control_pressed()
	await wait_process_frames(2)
	var button: Button = view._pilot_buttons[0]
	assert_true(button.is_visible_in_tree(), "the hotbar is on screen")
	_click(view, _point_on(view, button))
	assert_eq(controller.commands.size(), 1, "the click fires the skill")
	_press(view, KEY_SPACE)
	assert_eq(controller.pause_values, [true], "Space pauses")
	assert_eq(controller.commands.size(), 1, "and doesn't press the button again")
	var focus: Control = view.get_viewport().gui_get_focus_owner()
	assert_false(focus != null and view.is_ancestor_of(focus), "no battle button holds focus")


func test_leaving_the_view_gives_the_hero_back_and_a_pilot_that_falls_is_released() -> void:
	var controller: PilotController = _controller()
	var view: BattleView = _live_view(controller)
	view._selected_ids = ["hero-1"]
	view._on_take_control_pressed()
	view.free()
	assert_eq(controller.pilots, ["hero-1", ""], "leaving the view gives the hero back")
	assert_eq(controller.snapshots["battle-1"]["piloted"], "")

	var second_controller: PilotController = _controller()
	var second: BattleView = _live_view(second_controller)
	second._selected_ids = ["hero-1"]
	second._on_take_control_pressed()
	assert_true(second._pilot_bar.visible)
	second_controller.snapshots["battle-1"]["actors"][0]["life"] = BattleActor.LIFE_DOWNED
	second_controller.battle_changed.emit("battle-1")
	assert_eq(second._piloted_id, "", "a pilot that is not alive is released")
	assert_eq(second_controller.pilots, ["hero-1", ""])
	assert_false(second._pilot_bar.visible)


## F2: the battle is over (the controller has no snapshot for it any more): the view gives the hero back, so the
## session's entry is cleared and the hotbar goes, as on leaving.
func test_a_battle_that_ends_gives_the_hero_back_and_the_hotbar_goes() -> void:
	var controller: PilotController = _controller()
	var view: BattleView = _live_view(controller)
	view._selected_ids = ["hero-1"]
	view._on_take_control_pressed()
	assert_true(view._pilot_bar.visible)
	controller.snapshots.erase("battle-1")
	controller.battle_changed.emit("battle-1")
	assert_true(view._battle_ended, "setup: the view saw the battle end")
	assert_eq(view._piloted_id, "")
	assert_eq(controller.pilots, ["hero-1", ""], "the session was told to let go")
	assert_false(view._pilot_bar.visible)
	view.free()
	assert_eq(controller.pilots, ["hero-1", ""], "and leaving the view says nothing more")


func test_practice_mode_pilots_its_local_state_and_never_a_controller() -> void:
	var hero := Hero.new("Practice Pilot", 0)
	hero.def_id = &"knight"
	var zone: ZoneDefinition = load("res://zones/defs/verdant_outskirts.tres") as ZoneDefinition
	var view: BattleView = (load("res://combat/battle/battle_view.tscn") as PackedScene).instantiate() as BattleView
	view.configure_practice([hero], zone)
	add_child_autofree(view)
	var ally_id: String = ""
	for actor: BattleActor in view._practice_state.actors:
		if actor.faction == "ally":
			ally_id = actor.id
	view._selected_ids = [ally_id]
	view._on_take_control_pressed()
	assert_eq(view._piloted_id, ally_id)
	assert_eq(view._practice_state.piloted_id, ally_id)
	view._process(FRAME)
	assert_eq(view._practice_state.piloted_id, ally_id, "the practice advance carries it")
	assert_true(view._pilot_bar.visible)
	view._on_take_control_pressed()
	assert_eq(view._practice_state.piloted_id, "")
	assert_null(view._controller)


func _controller() -> PilotController:
	var helper: Controls = Controls.new()
	var source: Controls.FakeBattleController = helper._make_controller()
	var controller := PilotController.new()
	var snapshot: Dictionary = source.snapshots["battle-1"]
	var hero: Dictionary = (snapshot["actors"] as Array)[0]
	hero["skills"] = [
		{"id": "knight_iron_cut", "mode": "auto"},
		{"id": "knight_rally", "mode": "auto"},
		{"id": "mage_burst", "mode": "off"},
		{"id": "knight_bulwark", "mode": "auto"},
	]
	hero["skill_cooldowns"] = {"knight_rally": 0.0, "mage_burst": 0.0}
	(snapshot["actors"] as Array).append(helper._actor("hero-2", "hero-2", "ally", "ranger", [0.0, 2.0]))
	snapshot["piloted"] = ""
	controller.snapshots["battle-1"] = snapshot
	source.free()
	helper.free()
	return controller


func _live_view(controller: PilotController) -> BattleView:
	add_child_autofree(controller)
	var view: BattleView = (load("res://combat/battle/battle_view.tscn") as PackedScene).instantiate() as BattleView
	view.configure_live("battle-1", controller)
	add_child_autofree(view)
	for unit: BattleUnitView in view._unit_views.values():
		unit.global_position = unit.target_position
	return view


func _press(view: BattleView, keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var key := InputEventKey.new()
		key.keycode = keycode
		key.physical_keycode = keycode
		key.pressed = pressed
		view.get_viewport().push_input(key)


## A point on the button with the button itself under the pointer (not GUT's panel over it; see test_battle_focus).
func _point_on(view: BattleView, button: Button) -> Vector2:
	var rect: Rect2 = button.get_global_rect()
	for y: int in range(int(rect.position.y) + 2, int(rect.end.y) - 1, 2):
		for x: int in range(int(rect.position.x) + 2, int(rect.end.x) - 1, 2):
			var motion := InputEventMouseMotion.new()
			motion.position = Vector2(x, y)
			motion.global_position = motion.position
			view.get_viewport().push_input(motion, true)
			if view.get_viewport().gui_get_hovered_control() == button:
				return motion.position
	var at: Vector2 = rect.get_center()
	for _layer: int in 8:
		var motion := InputEventMouseMotion.new()
		motion.position = at
		motion.global_position = at
		view.get_viewport().push_input(motion, true)
		var hovered: Control = view.get_viewport().gui_get_hovered_control()
		if hovered == button:
			return at
		if hovered == null or view.is_ancestor_of(hovered):
			break
		_uncovered.append([hovered, hovered.mouse_filter])
		hovered.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fail_test("no point on %s at %s is reachable" % [button.text, rect])
	return at


func _click(view: BattleView, at: Vector2) -> void:
	for pressed: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = at
		click.global_position = at
		click.pressed = pressed
		view.get_viewport().push_input(click, true)
