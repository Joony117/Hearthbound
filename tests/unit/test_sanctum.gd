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
	var fodder_option: OptionButton = hub.get_node("%FodderOption") as OptionButton
	var target_option: OptionButton = hub.get_node("%TargetOption") as OptionButton
	var sacrifice_button: Button = hub.get_node("UI/Root/RosterPanel/VBox/SacrificeButtons/Sacrifice") as Button
	var status: Label = hub.get_node("%Status") as Label
	var essence_before: int = GameSession.essence

	fodder_option.select(0)
	target_option.select(1)
	sacrifice_button.pressed.emit()

	assert_eq(status.text, "Sacrificed Fodder for 98 essence.")
	assert_eq(GameSession.essence - essence_before, 98)
