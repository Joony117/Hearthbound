extends GutTest


var _original_settings_existed: bool = false
var _original_settings_bytes: PackedByteArray


func before_all() -> void:
	_original_settings_existed = FileAccess.file_exists(Settings.SETTINGS_PATH)
	if not _original_settings_existed:
		return
	var settings_file: FileAccess = FileAccess.open(Settings.SETTINGS_PATH, FileAccess.READ)
	assert_not_null(settings_file)
	if settings_file == null:
		return
	_original_settings_bytes = settings_file.get_buffer(settings_file.get_length())
	settings_file.close()


func after_all() -> void:
	if not _original_settings_existed:
		_remove_file_if_exists(Settings.SETTINGS_PATH)
		Settings._config = null
		return
	var settings_file: FileAccess = FileAccess.open(Settings.SETTINGS_PATH, FileAccess.WRITE)
	assert_not_null(settings_file)
	if settings_file == null:
		return
	settings_file.store_buffer(_original_settings_bytes)
	settings_file.close()

	settings_file = FileAccess.open(Settings.SETTINGS_PATH, FileAccess.READ)
	assert_not_null(settings_file)
	if settings_file == null:
		return
	var restored_bytes: PackedByteArray = settings_file.get_buffer(settings_file.get_length())
	settings_file.close()
	assert_eq(restored_bytes, _original_settings_bytes)
	Settings._config = null


func before_each() -> void:
	GameSession.from_dict({"roster": []})


func test_roster_exact_rank_signal_filters_to_only_the_selected_rank() -> void:
	var rank_c_hero := Hero.new("C Knight", 2)
	rank_c_hero.def_id = &"knight"
	var rank_b_hero := Hero.new("B Rogue", 3)
	rank_b_hero.def_id = &"rogue"
	GameSession.add_hero(rank_c_hero)
	GameSession.add_hero(rank_b_hero)
	var hub: Node3D = _instantiate_hub()
	var roster_list: ItemList = hub.get_node("%RosterList") as ItemList
	var rank_filter: OptionButton = hub.get_node("%RosterRankFilter") as OptionButton
	var exact_rank: CheckBox = hub.get_node("%RosterExactRank") as CheckBox

	rank_filter.select(3)
	rank_filter.item_selected.emit(3)
	assert_eq(roster_list.item_count, 2)
	exact_rank.set_pressed_no_signal(true)
	exact_rank.toggled.emit(true)

	assert_eq(roster_list.item_count, 1)
	assert_eq(roster_list.get_item_metadata(0), rank_c_hero)


func test_roster_type_filter_signal_limits_rows_to_selected_archetype() -> void:
	var knight := Hero.new("Knight", 2)
	knight.def_id = &"knight"
	var rogue := Hero.new("Rogue", 2)
	rogue.def_id = &"rogue"
	GameSession.add_hero(knight)
	GameSession.add_hero(rogue)
	var hub: Node3D = _instantiate_hub()
	var roster_list: ItemList = hub.get_node("%RosterList") as ItemList
	var type_filter: OptionButton = hub.get_node("%RosterTypeFilter") as OptionButton
	var knight_index: int = _option_index_for_metadata(type_filter, 0)

	type_filter.select(knight_index)
	type_filter.item_selected.emit(knight_index)

	assert_eq(roster_list.item_count, 1)
	assert_eq(roster_list.get_item_metadata(0), knight)


func test_select_all_roster_signal_selects_every_visible_row() -> void:
	var knight := Hero.new("Knight", 2)
	knight.def_id = &"knight"
	var rogue := Hero.new("Rogue", 3)
	rogue.def_id = &"rogue"
	GameSession.add_hero(knight)
	GameSession.add_hero(rogue)
	var hub: Node3D = _instantiate_hub()
	var roster_list: ItemList = hub.get_node("%RosterList") as ItemList
	var select_all: Button = hub.get_node("%SelectAllRoster") as Button
	var status: Label = hub.get_node("%Status") as Label

	select_all.pressed.emit()

	assert_eq(roster_list.get_selected_items().size(), roster_list.item_count)
	assert_eq(status.text, "Selected %d heroes." % roster_list.item_count)


func test_inventory_exact_rank_signal_filters_to_only_the_selected_rank() -> void:
	var rank_c_item := Item.new(&"ring", 2)
	var rank_b_item := Item.new(&"boots", 3)
	GameSession.add_item(rank_c_item)
	GameSession.add_item(rank_b_item)
	var hub: Node3D = _instantiate_hub()
	var inventory_list: ItemList = hub.get_node("%InventoryList") as ItemList
	var rank_filter: OptionButton = hub.get_node("%InventoryRankFilter") as OptionButton
	var exact_rank: CheckBox = hub.get_node("%InventoryExactRank") as CheckBox

	rank_filter.select(3)
	rank_filter.item_selected.emit(3)
	assert_eq(inventory_list.item_count, 2)
	exact_rank.set_pressed_no_signal(true)
	exact_rank.toggled.emit(true)

	assert_eq(inventory_list.item_count, 1)
	assert_eq(inventory_list.get_item_metadata(0), rank_c_item)


func test_select_all_inventory_signal_selects_every_visible_row() -> void:
	GameSession.add_item(Item.new(&"ring", 2))
	GameSession.add_item(Item.new(&"boots", 3))
	var hub: Node3D = _instantiate_hub()
	var inventory_list: ItemList = hub.get_node("%InventoryList") as ItemList
	var select_all: Button = hub.get_node("%SelectAllInventory") as Button
	var status: Label = hub.get_node("%Status") as Label

	select_all.pressed.emit()

	assert_eq(inventory_list.get_selected_items().size(), inventory_list.item_count)
	assert_eq(status.text, "Selected %d items." % inventory_list.item_count)


func test_unequip_all_signal_clears_the_selected_heros_equipment() -> void:
	var hero := Hero.new("Equipped Knight", 2)
	hero.def_id = &"knight"
	hero.equipped[0] = Item.new(&"main_hand", 2)
	hero.equipped[9] = Item.new(&"ring", 3)
	GameSession.add_hero(hero)
	var hub: Node3D = _instantiate_hub()
	var roster_list: ItemList = hub.get_node("%RosterList") as ItemList
	var unequip_all: Button = hub.get_node("%UnequipAll") as Button
	var status: Label = hub.get_node("%Status") as Label

	roster_list.select(0)
	unequip_all.pressed.emit()

	assert_true(hero.equipped.is_empty())
	assert_eq(status.text, "Unequipped 2 items from Equipped Knight.")


func test_screen_shake_signal_writes_the_setting() -> void:
	var pause_menu_scene: PackedScene = load("res://ui/pause_menu.tscn") as PackedScene
	assert_not_null(pause_menu_scene)
	var pause_menu: CanvasLayer = pause_menu_scene.instantiate() as CanvasLayer
	add_child_autofree(pause_menu)
	var screen_shake: CheckButton = pause_menu.get_node("%ScreenShake") as CheckButton
	var enabled: bool = not Settings.screen_shake_enabled()

	screen_shake.set_pressed_no_signal(enabled)
	screen_shake.toggled.emit(enabled)

	assert_eq(Settings.screen_shake_enabled(), enabled)


func _instantiate_hub() -> Node3D:
	var hub_scene: PackedScene = load("res://hub/hub.tscn") as PackedScene
	assert_not_null(hub_scene)
	var hub: Node3D = hub_scene.instantiate() as Node3D
	add_child_autofree(hub)
	return hub


func _option_index_for_metadata(option: OptionButton, metadata: int) -> int:
	for item_index: int in option.item_count:
		if option.get_item_metadata(item_index) == metadata:
			return item_index
	fail_test("OptionButton did not contain metadata %d." % metadata)
	return -1


func _remove_file_if_exists(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var remove_error: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_eq(remove_error, OK)
