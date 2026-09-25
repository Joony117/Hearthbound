extends GutTest

## ig-0oj: a clicked battle button must not keep focus, or Space (rts_pause, and also ui_accept) presses it
## again instead of pausing. Real pushed clicks at points where the button itself is under the pointer
## (GUT's own panel eats clicks where it overlaps: see test_hub_controls' _reachable/_hovered).

const Controls = preload("res://tests/unit/test_battle_controls.gd")

## GUT's own controls made click-through by _point_on, with their filters, put back after each test.
var _uncovered: Array = []


func after_each() -> void:
	for entry: Array in _uncovered:
		if is_instance_valid(entry[0]):
			(entry[0] as Control).mouse_filter = entry[1]
	_uncovered.clear()


func test_space_pauses_after_a_squad_or_command_click_and_fires_neither_again() -> void:
	var helper: Controls = Controls.new()
	var controller: Controls.FakeBattleController = helper._make_controller()
	helper.free()
	add_child_autofree(controller)
	var view: BattleView = (load("res://combat/battle/battle_view.tscn") as PackedScene).instantiate() as BattleView
	view.configure_live("battle-1", controller)
	add_child_autofree(view)
	await wait_process_frames(2)
	var squad: Button = view._squad_row.get_child(0) as Button
	var presses: Dictionary = {"squad": 0, "skill": 0}
	squad.pressed.connect(func() -> void: presses["squad"] += 1)

	_click(view, _point_on(view, squad))
	assert_eq(presses["squad"], 1, "the squad click lands")
	assert_eq(view._selected_ids, ["hero-1"])
	_press_space(view)
	assert_eq(controller.pause_values, [true], "Space pauses")
	assert_eq(presses["squad"], 1, "and doesn't press the squad button again")
	_press_space(view)
	assert_eq(controller.pause_values, [true, false])

	await wait_process_frames(2)
	var skill: Button = view._selected_ability_button
	assert_true(skill.is_visible_in_tree() and not skill.disabled, "the Skill button is up")
	skill.pressed.connect(func() -> void: presses["skill"] += 1)
	_click(view, _point_on(view, skill))
	assert_eq(presses["skill"], 1, "the command click lands")
	_press_space(view)
	assert_eq(controller.pause_values, [true, false, true], "Space pauses")
	assert_eq(presses["skill"], 1, "and doesn't press the command button again")
	assert_eq(presses["squad"], 1)
	assert_eq(controller.commands.size(), 0, "no command was sent")
	_press_space(view)
	assert_eq(controller.pause_values, [true, false, true, false])

	# The scene's own buttons too: Attack-move, in the bottom row.
	var attack_move: Button = view.get_node("%AttackMoveButton") as Button
	_click(view, _point_on(view, attack_move))
	assert_eq(view._command_mode, "attack_move", "the Attack-move click lands")
	view._command_mode = ""
	_press_space(view)
	assert_eq(controller.pause_values, [true, false, true, false, true], "Space pauses")
	assert_eq(view._command_mode, "", "and doesn't press Attack-move again")
	var focus: Control = view.get_viewport().gui_get_focus_owner()
	assert_false(focus != null and view.is_ancestor_of(focus), "no battle button holds focus")


## A point on the button with the button itself under the pointer (not GUT's panel over it).
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
	# Wholly under GUT's panel: make GUT's controls over its centre click-through until the pointer
	# reaches the button (after_each puts them back). Never one of the battle's own.
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


func _press_space(view: BattleView) -> void:
	for pressed: bool in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_SPACE
		key.physical_keycode = KEY_SPACE
		key.pressed = pressed
		view.get_viewport().push_input(key)
