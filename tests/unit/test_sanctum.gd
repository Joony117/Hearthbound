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
	var roster_list: ItemList = hub.get_node("%RosterList") as ItemList
	var target_option: OptionButton = hub.get_node("%TargetOption") as OptionButton
	var sacrifice_button: Button = hub.get_node("UI/Root/RosterPanel/VBox/SacrificeButtons/Sacrifice") as Button
	var confirm_dialog: ConfirmationDialog = hub.get_node("%ConfirmDialog") as ConfirmationDialog
	var status: Label = hub.get_node("%Status") as Label
	var essence_before: int = GameSession.essence

	roster_list.select(0)
	target_option.select(1)
	sacrifice_button.pressed.emit()

	# The press only asks. Nothing may die until the dialog is confirmed.
	assert_true(GameSession.roster.has(fodder))
	assert_eq(GameSession.essence, essence_before)
	assert_string_contains(confirm_dialog.dialog_text, "Sacrifice [C] Fodder into [F] Target for 98 essence?")

	confirm_dialog.confirmed.emit()

	assert_eq(status.text, "Sacrificed Fodder for 98 essence.")
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
	var roster_list: ItemList = hub.get_node("%RosterList") as ItemList
	var target_option: OptionButton = hub.get_node("%TargetOption") as OptionButton
	var sacrifice_button: Button = hub.get_node("UI/Root/RosterPanel/VBox/SacrificeButtons/Sacrifice") as Button
	var confirm_dialog: ConfirmationDialog = hub.get_node("%ConfirmDialog") as ConfirmationDialog
	var status: Label = hub.get_node("%Status") as Label
	var essence_before: int = GameSession.essence

	for fodder_index: int in range(1, 4):
		roster_list.select(fodder_index, false)
	target_option.select(0)
	sacrifice_button.pressed.emit()

	assert_eq(GameSession.roster.size(), 4)
	assert_eq(GameSession.essence, essence_before)
	assert_string_contains(confirm_dialog.dialog_text, "Fodder 1")
	assert_string_contains(confirm_dialog.dialog_text, "Fodder 2")
	assert_string_contains(confirm_dialog.dialog_text, "Fodder 3")
	assert_string_contains(confirm_dialog.dialog_text, "879 essence")
	confirm_dialog.confirmed.emit()

	assert_eq(GameSession.roster.size(), 1)
	assert_eq(GameSession.essence - essence_before, 879)
	assert_eq(status.text, "Sacrificed 3 heroes for 879 essence.")
