extends GutTest


func before_each() -> void:
	GameSession.from_dict({"roster": []})


func test_sacrifice_preview_matches_sanctum_bonused_payout() -> void:
	GameSession.building_levels[3] = 999
	var fodder := Hero.new("Fodder", 2)
	var target := Hero.new("Target", 0)
	fodder.def_id = &"rogue"
	target.def_id = &"mage"
	GameSession.add_hero(fodder)
	GameSession.add_hero(target)
	var hub_scene: PackedScene = load("res://hub/hub.tscn") as PackedScene
	assert_not_null(hub_scene)
	var hub: Node3D = hub_scene.instantiate() as Node3D
	add_child_autofree(hub)
	hub._open(&"Sanctum")
	var roster_list: ItemList = hub.get_node("%RosterList") as ItemList
	var target_option: OptionButton = hub.get_node("%TargetOption") as OptionButton
	var sacrifice_button: Button = hub.get_node("%Sacrifice") as Button
	var confirm_dialog: ConfirmationDialog = hub.get_node("%ConfirmDialog") as ConfirmationDialog
	var status: Label = hub.get_node("%Status") as Label
	var bulk_preview: RichTextLabel = hub.get_node("%DialogBody") as RichTextLabel
	var essence_before: int = GameSession.essence

	roster_list.select(0)
	roster_list.multi_selected.emit(0, true)
	target_option.select(1)
	sacrifice_button.pressed.emit()

	# The press only asks. Nothing may die until the dialog is confirmed.
	assert_true(GameSession.roster.has(fodder))
	assert_eq(GameSession.essence, essence_before)
	assert_string_contains(bulk_preview.text, "Fodder")
	assert_string_contains(bulk_preview.text, "Recipient: Target")
	assert_string_contains(bulk_preview.text, "Total output: 98 essence · 0 resonance")
	assert_string_contains(bulk_preview.text, "+98 essence")

	confirm_dialog.confirmed.emit()

	assert_eq(status.text, "Sacrifice completed.")
	assert_eq(GameSession.essence - essence_before, 98)


func test_batch_sacrifice_waits_for_confirm_and_sums_three_dupes() -> void:
	GameSession.building_levels[3] = 999
	var target := Hero.new("Target", 0)
	target.def_id = &"mage"
	GameSession.add_hero(target)
	for hero_index: int in 3:
		var fodder := Hero.new("Fodder %d" % (hero_index + 1), 2)
		fodder.def_id = &"mage"
		GameSession.add_hero(fodder)
	var hub_scene: PackedScene = load("res://hub/hub.tscn") as PackedScene
	var hub: Node3D = hub_scene.instantiate() as Node3D
	add_child_autofree(hub)
	hub._open(&"Sanctum")
	var roster_list: ItemList = hub.get_node("%RosterList") as ItemList
	var target_option: OptionButton = hub.get_node("%TargetOption") as OptionButton
	var sacrifice_button: Button = hub.get_node("%Sacrifice") as Button
	var confirm_dialog: ConfirmationDialog = hub.get_node("%ConfirmDialog") as ConfirmationDialog
	var status: Label = hub.get_node("%Status") as Label
	var bulk_preview: RichTextLabel = hub.get_node("%DialogBody") as RichTextLabel
	var essence_before: int = GameSession.essence

	for fodder_index: int in range(1, 4):
		roster_list.select(fodder_index, false)
	roster_list.multi_selected.emit(3, true)
	target_option.select(0)
	sacrifice_button.pressed.emit()

	assert_eq(GameSession.roster.size(), 4)
	assert_eq(GameSession.essence, essence_before)
	assert_string_contains(bulk_preview.text, "Fodder 1")
	assert_string_contains(bulk_preview.text, "Fodder 2")
	assert_string_contains(bulk_preview.text, "Fodder 3")
	assert_string_contains(bulk_preview.text, "Recipient: Target")
	assert_string_contains(bulk_preview.text, "Total output: 879 essence · 3 resonance")
	assert_string_contains(bulk_preview.text, "+293 essence")
	confirm_dialog.confirmed.emit()

	assert_eq(GameSession.roster.size(), 1)
	assert_eq(GameSession.essence - essence_before, 879)
	assert_eq(status.text, "Sacrifice completed.")


## The one that matters: a hero the rank filter hides must leave the selection, because the press
## that follows is permanent.
func test_rank_filter_drops_a_hidden_fodder_before_sacrifice_can_kill_it() -> void:
	var target := Hero.new("Target", 0)
	var low_fodder := Hero.new("Low", 1)
	var high_fodder := Hero.new("High", 3)
	for hero: Hero in [target, low_fodder, high_fodder]:
		hero.def_id = &"mage"
		GameSession.add_hero(hero)
	var hub: Node3D = (load("res://hub/hub.tscn") as PackedScene).instantiate() as Node3D
	add_child_autofree(hub)
	hub._open(&"Sanctum")
	var roster_list: ItemList = hub.get_node("%RosterList") as ItemList
	var rank_filter: OptionButton = hub.get_node("%RosterRankFilter") as OptionButton
	var target_option: OptionButton = hub.get_node("%TargetOption") as OptionButton
	var sacrifice_button: Button = hub.get_node("%Sacrifice") as Button
	var confirm_dialog: ConfirmationDialog = hub.get_node("%ConfirmDialog") as ConfirmationDialog

	roster_list.select(1, false)
	roster_list.select(2, false)
	roster_list.multi_selected.emit(2, true)
	# Minimum rank B. Low is now invisible, and so is Target — but TargetOption is not a filtered
	# view, so the sacrifice still has somewhere to go.
	rank_filter.select(4)
	rank_filter.item_selected.emit(4)
	target_option.select(0)

	assert_eq(roster_list.item_count, 1)
	assert_eq(roster_list.get_selected_items(), PackedInt32Array([0]))
	assert_eq(roster_list.get_item_metadata(0), high_fodder)

	sacrifice_button.pressed.emit()
	var bulk_preview: RichTextLabel = hub.get_node("%DialogBody") as RichTextLabel
	assert_string_contains(bulk_preview.text, "High")
	assert_false(bulk_preview.text.contains("Low"))
	confirm_dialog.confirmed.emit()

	assert_true(GameSession.roster.has(low_fodder), "A hidden hero is not a selected hero.")
	assert_false(GameSession.roster.has(high_fodder))
