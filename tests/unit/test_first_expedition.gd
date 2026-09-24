extends GutTest

# ig-4pr: the way to battle is visible. The Gate shows one next step, and the team editor names new
# teams and says how to pick several heroes.

const BALANCE: BalanceTable = preload("res://balance.tres")
const PICK_HINT: String = "Click a hero in the roster to add it. Ctrl- or Shift-click adds more, up to 5."
const MORE_HINT: String = "Ctrl- or Shift-click the roster to add more (up to 5)."


func before_each() -> void:
	GameSession.from_dict({"roster": []})


func after_all() -> void:
	GameSession.from_dict({"roster": []})


func test_a_fresh_roster_walks_from_the_gate_to_a_dispatched_team() -> void:
	GameSession.stones = BALANCE.summon_pull_cost * 2
	var hub: Node3D = _instantiate_hub()
	var gate_button: Button = hub.get_node("%TownGateButton") as Button
	var go_to_hall: Button = hub.get_node("%GoToHall") as Button
	var manage: Button = hub.get_node("%ManageTeams") as Button
	var dispatch: Button = hub.get_node("%DispatchSelected") as Button

	gate_button.pressed.emit()
	assert_eq(gate_button.text, "6 · Expeditions")
	assert_true(go_to_hall.is_visible_in_tree(), "no heroes: the next step is the Circle")
	assert_eq(go_to_hall.theme_type_variation, &"PrimaryButton")
	assert_false(manage.is_visible_in_tree())
	assert_false(dispatch.is_visible_in_tree(), "no dispatch without a team")
	assert_false((hub.get_node("%CombineTeams") as Control).is_visible_in_tree())

	go_to_hall.pressed.emit()
	(hub.get_node("%Summon") as Button).pressed.emit()
	(hub.get_node("%Summon") as Button).pressed.emit()
	assert_eq(GameSession.roster.size(), 2)

	gate_button.pressed.emit()
	assert_true(manage.is_visible_in_tree(), "heroes, no team: the next step is a team")
	assert_eq(manage.text, "Make a team")
	assert_eq(manage.theme_type_variation, &"PrimaryButton")
	assert_false(go_to_hall.is_visible_in_tree())
	assert_false(dispatch.is_visible_in_tree())
	assert_eq((hub.get_node("%DispatchEmpty") as Label).text, "Make a team first: pick heroes at the Training Hall, then send them out from here.")

	manage.pressed.emit()
	assert_true((hub.get_node("%TeamsView") as Control).is_visible_in_tree(), "the Training Hall is open")
	assert_eq((hub.get_node("%TrainingHallButton") as Button).text, "3 · Teams")
	assert_eq((hub.get_node("%PresetName") as LineEdit).text, "Team 1")

	var roster: ItemList = hub.get_node("%RosterList") as ItemList
	roster.select(0)
	roster.select(1, false)
	roster.multi_selected.emit(1, true)
	(hub.get_node("%SaveAndGo") as Button).pressed.emit()
	assert_eq(GameSession.team_presets.size(), 1)
	assert_eq(str(GameSession.team_presets[0]["name"]), "Team 1")
	assert_eq((GameSession.team_presets[0]["hero_ids"] as Array).size(), 2)
	assert_false(GameSession.expedition_orders.size() > 0, "Save and go never dispatches")
	assert_true((hub.get_node("%ExpeditionsView") as Control).is_visible_in_tree(), "the Town Gate is open")
	assert_eq((hub.get_node("%PresetDispatchList") as ItemList).get_selected_items(), PackedInt32Array([0]))
	assert_true(dispatch.is_visible_in_tree())
	assert_false(dispatch.disabled)
	assert_true(dispatch.has_focus(), "Dispatch is the next step and has focus")
	assert_eq(manage.text, "Manage teams")
	assert_eq(manage.theme_type_variation, &"", "one primary per state: Dispatch")

	dispatch.pressed.emit()
	(hub.get_node("%ConfirmDialog") as ConfirmationDialog).confirmed.emit()
	assert_eq(GameSession.expedition_orders.size(), 1)
	for hero: Hero in GameSession.roster:
		assert_true(GameSession.is_hero_busy(hero), "%s is out" % hero.hero_name)


func test_save_and_go_with_nobody_picked_stays_in_the_training_hall() -> void:
	_add_heroes(1)
	var hub: Node3D = _instantiate_hub()
	(hub.get_node("%TrainingHallButton") as Button).pressed.emit()
	(hub.get_node("%SaveAndGo") as Button).pressed.emit()
	assert_eq((hub.get_node("%Status") as Label).text, "A team preset must contain 1 to 5 unique hero IDs.")
	assert_true(GameSession.team_presets.is_empty())
	assert_true((hub.get_node("%TeamsView") as Control).is_visible_in_tree())
	assert_false((hub.get_node("%ExpeditionsView") as Control).is_visible_in_tree())


func test_a_new_team_takes_the_lowest_free_team_number() -> void:
	var heroes: Array[Hero] = _add_heroes(1)
	for team_name: String in ["Team 1", "Team 3"]:
		assert_ne(GameSession.save_team_preset("", team_name, [heroes[0].instance_id], "verdant_outskirts"), "")
	var hub: Node3D = _instantiate_hub()
	var preset_name: LineEdit = hub.get_node("%PresetName") as LineEdit
	(hub.get_node("%TrainingHallButton") as Button).pressed.emit()
	assert_eq(preset_name.text, "Team 2", "the first open")
	preset_name.text = "Scouts"
	var selector: OptionButton = hub.get_node("%PresetSelector") as OptionButton
	selector.select(1)
	selector.item_selected.emit(1)
	assert_eq(preset_name.text, "Team 1", "a saved team shows its own name")
	selector.select(0)
	selector.item_selected.emit(0)
	assert_eq(preset_name.text, "Team 2", "choosing New team")


func test_with_every_hero_dead_the_gate_says_summon_even_with_a_saved_team() -> void:
	var heroes: Array[Hero] = _add_heroes(1)
	assert_ne(GameSession.save_team_preset("", "Team 1", [heroes[0].instance_id], "verdant_outskirts"), "")
	GameSession.kill_hero(heroes[0], &"verdant_outskirts", BALANCE)
	assert_true(GameSession.roster.is_empty())
	assert_eq(GameSession.team_presets.size(), 1, "the team outlives its member")
	var hub: Node3D = _instantiate_hub()
	(hub.get_node("%TownGateButton") as Button).pressed.emit()
	var go_to_hall: Button = hub.get_node("%GoToHall") as Button
	assert_true(go_to_hall.is_visible_in_tree())
	assert_eq(go_to_hall.theme_type_variation, &"PrimaryButton")
	assert_false((hub.get_node("%DispatchSelected") as Control).is_visible_in_tree(), "the only primary is the summon step")
	assert_false((hub.get_node("%ManageTeams") as Control).is_visible_in_tree())
	assert_true((hub.get_node("%DispatchEmpty") as Control).is_visible_in_tree())


func test_when_every_team_lost_its_members_the_next_step_is_fixing_one() -> void:
	var heroes: Array[Hero] = _add_heroes(1)
	assert_ne(GameSession.save_team_preset("", "Team 1", [heroes[0].instance_id], "verdant_outskirts"), "")
	GameSession.kill_hero(heroes[0], &"verdant_outskirts", BALANCE)
	_add_heroes(1)
	var hub: Node3D = _instantiate_hub()
	(hub.get_node("%TownGateButton") as Button).pressed.emit()
	var manage: Button = hub.get_node("%ManageTeams") as Button
	var dispatch: Button = hub.get_node("%DispatchSelected") as Button
	assert_true(manage.is_visible_in_tree())
	assert_eq(manage.text, "Fix a team")
	assert_eq(manage.theme_type_variation, &"PrimaryButton")
	assert_eq(dispatch.theme_type_variation, &"", "a Dispatch that cannot fire is not the next step")


func test_a_team_that_is_away_keeps_dispatch_as_the_next_step() -> void:
	var heroes: Array[Hero] = _add_heroes(2)
	for index: int in 2:
		assert_ne(GameSession.save_team_preset("", "Team %d" % (index + 1), [heroes[index].instance_id], "verdant_outskirts"), "")
	var hub: Node3D = _instantiate_hub()
	(hub.get_node("%TownGateButton") as Button).pressed.emit()
	var presets: ItemList = hub.get_node("%PresetDispatchList") as ItemList
	presets.select(0)
	presets.multi_selected.emit(0, true)
	(hub.get_node("%DispatchSelected") as Button).pressed.emit()
	(hub.get_node("%ConfirmDialog") as ConfirmationDialog).confirmed.emit()
	assert_true(GameSession.is_hero_busy(heroes[0]), "Team 1 is Away")
	GameSession.kill_hero(heroes[1], &"verdant_outskirts", BALANCE)
	assert_false(GameSession.roster.is_empty())
	var manage: Button = hub.get_node("%ManageTeams") as Button
	assert_eq(manage.text, "Manage teams", "Away and Missing, none Ready: waiting is the answer")
	assert_eq(manage.theme_type_variation, &"")
	assert_eq((hub.get_node("%DispatchSelected") as Button).theme_type_variation, &"PrimaryButton")


func test_deleting_a_team_starts_the_next_one_with_a_fresh_name() -> void:
	var heroes: Array[Hero] = _add_heroes(1)
	for team_name: String in ["Team 1", "Scouts"]:
		assert_ne(GameSession.save_team_preset("", team_name, [heroes[0].instance_id], "verdant_outskirts"), "")
	var hub: Node3D = _instantiate_hub()
	(hub.get_node("%TrainingHallButton") as Button).pressed.emit()
	var selector: OptionButton = hub.get_node("%PresetSelector") as OptionButton
	selector.select(2)
	selector.item_selected.emit(2)
	assert_eq((hub.get_node("%PresetName") as LineEdit).text, "Scouts")
	(hub.get_node("%DeletePreset") as Button).pressed.emit()
	(hub.get_node("%ConfirmDialog") as ConfirmationDialog).confirmed.emit()
	assert_eq(GameSession.team_presets.size(), 1)
	assert_eq((hub.get_node("%PresetName") as LineEdit).text, "Team 2", "not the deleted name")
	(hub.get_node("%ClosePanel") as Button).pressed.emit()
	(hub.get_node("%TrainingHallButton") as Button).pressed.emit()
	assert_eq((hub.get_node("%PresetName") as LineEdit).text, "Team 2")


func test_the_team_editor_says_how_to_pick_several_heroes() -> void:
	_add_heroes(5)
	var hub: Node3D = _instantiate_hub()
	(hub.get_node("%TrainingHallButton") as Button).pressed.emit()
	var members: RichTextLabel = hub.get_node("%PresetMembers") as RichTextLabel
	var roster: ItemList = hub.get_node("%RosterList") as ItemList
	assert_eq(members.text, PICK_HINT, "nobody picked")
	for count: int in range(1, 6):
		roster.select(count - 1, count == 1)
		roster.multi_selected.emit(count - 1, true)
		var lines: PackedStringArray = members.text.split("\n")
		assert_false(members.text.contains(PICK_HINT), "%d picked" % count)
		if count < 5:
			assert_eq(lines[lines.size() - 1], MORE_HINT, "%d picked: the add-more line is last" % count)
		else:
			assert_false(members.text.contains(MORE_HINT), "a full team gets no add-more line")


func test_the_pick_hint_is_on_screen_at_720() -> void:
	_add_heroes(2)
	var hub: Node3D = _instantiate_hub()
	(hub.get_node("%TrainingHallButton") as Button).pressed.emit()
	var members: RichTextLabel = hub.get_node("%PresetMembers") as RichTextLabel
	var roster: ItemList = hub.get_node("%RosterList") as ItemList
	for count: int in [0, 1, 2]:
		if count > 0:
			roster.select(count - 1, count == 1)
			roster.multi_selected.emit(count - 1, true)
		await wait_process_frames(2)
		assert_eq(get_viewport().get_visible_rect().size, Vector2(1280, 720))
		assert_gt(members.get_content_height(), 0)
		assert_true(members.get_content_height() <= members.size.y, "%d picked: every line fits, the hint included (%d > %d)" % [count, members.get_content_height(), members.size.y])
	# The Gate after Save and go: one team's whole forecast is on screen, its last line included.
	roster.select(0, true)
	roster.multi_selected.emit(0, true)
	(hub.get_node("%SaveAndGo") as Button).pressed.emit()
	await wait_process_frames(2)
	var summary: RichTextLabel = hub.get_node("%DispatchSummary") as RichTextLabel
	assert_true(summary.get_content_height() <= summary.size.y, "one team's summary fits (%d > %d)" % [summary.get_content_height(), summary.size.y])


func _add_heroes(count: int) -> Array[Hero]:
	var heroes: Array[Hero] = []
	for index: int in count:
		var hero := Hero.new("Hero %d" % index, 2)
		hero.def_id = &"knight"
		GameSession.add_hero(hero)
		heroes.append(hero)
	return heroes


func _instantiate_hub() -> Node3D:
	var hub: Node3D = (load("res://hub/hub.tscn") as PackedScene).instantiate() as Node3D
	add_child_autofree(hub)
	return hub
