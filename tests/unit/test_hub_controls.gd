extends GutTest


var _original_settings_existed: bool = false
var _original_settings_bytes: PackedByteArray
var _original_save_existed: bool = false
var _original_save_bytes: PackedByteArray


func before_all() -> void:
	_original_save_existed = FileAccess.file_exists(SaveService.SAVE_PATH)
	if _original_save_existed:
		var save_file: FileAccess = FileAccess.open(SaveService.SAVE_PATH, FileAccess.READ)
		assert_not_null(save_file)
		if save_file != null:
			_original_save_bytes = save_file.get_buffer(save_file.get_length())
			save_file.close()
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
	_restore_original_save()
	SaveService.load_blocked = false
	SaveService.load_block_reason = ""
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


func test_tabs_switch_views_without_clearing_shared_roster_selection() -> void:
	var hero := Hero.new("Tab Keeper", 2)
	hero.def_id = &"knight"
	GameSession.add_hero(hero)
	var hub: Node3D = _instantiate_hub()
	var roster: ItemList = hub.get_node("%RosterList") as ItemList
	var teams_tab: Button = hub.get_node("%TeamsTab") as Button
	var armory_tab: Button = hub.get_node("%ArmoryTab") as Button
	var teams_view: Control = hub.get_node("%TeamsView") as Control
	var armory_view: Control = hub.get_node("%ArmoryView") as Control

	teams_tab.pressed.emit()
	roster.select(0)
	roster.multi_selected.emit(0, true)
	armory_tab.pressed.emit()

	assert_false(teams_view.visible)
	assert_true(armory_view.visible)
	assert_eq(roster.get_selected_items(), PackedInt32Array([0]))


func test_dispatch_creates_timed_order_and_does_not_resolve_immediately() -> void:
	var hero := Hero.new("Courier", 2)
	hero.def_id = &"knight"
	GameSession.add_hero(hero)
	var preset_id: String = GameSession.save_team_preset("", "Couriers", [hero.instance_id], "verdant_outskirts")
	assert_ne(preset_id, "")
	var starting_stones: int = GameSession.stones
	var hub: Node3D = _instantiate_hub()
	var presets: ItemList = hub.get_node("%PresetDispatchList") as ItemList
	var dispatch: Button = hub.get_node("%DispatchSelected") as Button
	var confirm: ConfirmationDialog = hub.get_node("%ConfirmDialog") as ConfirmationDialog

	presets.select(0)
	presets.multi_selected.emit(0, true)
	dispatch.pressed.emit()
	assert_true(confirm.visible)
	confirm.confirmed.emit()

	assert_eq(GameSession.expedition_orders.size(), 1)
	assert_eq(GameSession.stones, starting_stones)
	assert_true(GameSession.is_hero_busy(hero))


func test_bulk_dispatch_rejects_overlapping_presets_before_launch() -> void:
	var shared := Hero.new("Shared", 2)
	shared.def_id = &"knight"
	var first := Hero.new("First", 2)
	first.def_id = &"mage"
	var second := Hero.new("Second", 2)
	second.def_id = &"rogue"
	GameSession.add_hero(shared)
	GameSession.add_hero(first)
	GameSession.add_hero(second)
	GameSession.save_team_preset("", "Alpha", [shared.instance_id, first.instance_id], "verdant_outskirts")
	GameSession.save_team_preset("", "Beta", [shared.instance_id, second.instance_id], "verdant_outskirts")
	var hub: Node3D = _instantiate_hub()
	var presets: ItemList = hub.get_node("%PresetDispatchList") as ItemList
	var status: Label = hub.get_node("%Status") as Label

	presets.select(0, false)
	presets.select(1, false)
	presets.multi_selected.emit(1, true)
	(hub.get_node("%DispatchSelected") as Button).pressed.emit()

	assert_true(GameSession.expedition_orders.is_empty())
	assert_true(status.text.contains("overlap"))


func test_roster_selection_survives_refresh_by_stable_instance_id() -> void:
	var hero := Hero.new("Stable", 2)
	hero.def_id = &"knight"
	GameSession.add_hero(hero)
	var hub: Node3D = _instantiate_hub()
	var roster: ItemList = hub.get_node("%RosterList") as ItemList
	roster.select(0)
	roster.multi_selected.emit(0, true)

	GameSession.roster_changed.emit()

	assert_eq(roster.get_selected_items(), PackedInt32Array([0]))
	assert_eq((roster.get_item_metadata(0) as Hero).instance_id, hero.instance_id)


func test_favorite_item_toggle_updates_protection_and_favorites_filter() -> void:
	var item := Item.new(&"ring", 2)
	GameSession.add_item(item)
	var hub: Node3D = _instantiate_hub()
	var inventory: ItemList = hub.get_node("%InventoryList") as ItemList
	var favorite: CheckBox = hub.get_node("%FavoriteItem") as CheckBox
	var protection_filter: OptionButton = hub.get_node("%InventoryProtectionFilter") as OptionButton

	inventory.select(0)
	inventory.multi_selected.emit(0, true)
	assert_false(favorite.disabled)
	favorite.set_pressed_no_signal(true)
	favorite.toggled.emit(true)

	assert_true(item.favorite)
	assert_true(GameSession.is_item_protected(item))
	protection_filter.select(2)
	protection_filter.item_selected.emit(2)
	assert_eq(inventory.item_count, 1)
	assert_string_starts_with(inventory.get_item_text(0), "★ ")
	favorite.set_pressed_no_signal(false)
	favorite.toggled.emit(false)
	assert_false(item.favorite)
	assert_eq(inventory.item_count, 0)


func test_future_save_blocks_main_menu_play_without_changing_canonical_bytes() -> void:
	var future_bytes: PackedByteArray = '{"version":999,"roster":[]}'.to_utf8_buffer()
	var save_file: FileAccess = FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	assert_not_null(save_file)
	if save_file == null:
		return
	save_file.store_buffer(future_bytes)
	save_file.close()

	assert_false(SaveService.load_game())
	assert_push_error("Save is from a newer build")
	var menu: Control = (load("res://ui/main_menu.tscn") as PackedScene).instantiate() as Control
	add_child_autofree(menu)
	var play: Button = menu.get_node("%Play") as Button
	var notice: Label = menu.get_node("%SaveNotice") as Label
	assert_true(play.disabled)
	assert_true(notice.visible)
	assert_string_contains(notice.text, "newer build")
	var unchanged: FileAccess = FileAccess.open(SaveService.SAVE_PATH, FileAccess.READ)
	assert_not_null(unchanged)
	if unchanged != null:
		assert_eq(unchanged.get_buffer(unchanged.get_length()), future_bytes)
		unchanged.close()
	_restore_original_save()
	SaveService.load_blocked = false
	SaveService.load_block_reason = ""


func test_dispatch_confirmation_wraps_full_team_details_and_keeps_actions_visible() -> void:
	var hero := Hero.new("Alexandria Starfall, Warden of the Verdant March", 2)
	hero.def_id = &"knight"
	GameSession.add_hero(hero)
	GameSession.save_team_preset("", "The Extremely Long Verdant Vanguard Company Name", [hero.instance_id], "verdant_outskirts")
	var hub: Node3D = _instantiate_hub()
	var presets: ItemList = hub.get_node("%PresetDispatchList") as ItemList
	presets.select(0)
	presets.multi_selected.emit(0, true)
	(hub.get_node("%DispatchSelected") as Button).pressed.emit()
	var dialog: ConfirmationDialog = hub.get_node("%ConfirmDialog") as ConfirmationDialog
	var body: RichTextLabel = hub.get_node("%DialogBody") as RichTextLabel
	assert_true(dialog.visible)
	assert_eq(dialog.dialog_text, "")
	assert_true(body.scroll_active)
	assert_string_contains(body.text, "The Extremely Long Verdant Vanguard Company Name")
	assert_string_contains(body.text, "Verdant Outskirts")
	assert_string_contains(body.text, "Longest route minimum")
	assert_string_contains(body.text, "Forecast:")
	assert_true(dialog.get_ok_button().visible)
	assert_true(dialog.get_cancel_button().visible)
	assert_true(dialog.size.x <= get_viewport().get_visible_rect().size.x - 64.0)


func test_hall_expedition_pulse_refreshes_recovery_time_without_losing_selection() -> void:
	var cache := LostCache.new("Clock Keeper", &"verdant_outskirts", 0, 0.0)
	GameSession.lost_caches.append(cache)
	var hub: Node3D = _instantiate_hub()
	(hub.get_node("%HallTab") as Button).pressed.emit()
	var caches: ItemList = hub.get_node("%LostCacheList") as ItemList
	caches.select(0)
	var before: String = caches.get_item_text(0)
	GameSession.recovery_clock_seconds = 60.0
	GameSession.expeditions_changed.emit()
	assert_ne(caches.get_item_text(0), before)
	assert_eq(caches.get_selected_items(), PackedInt32Array([0]))


func test_all_retained_reports_have_full_tooltips_and_long_order_title_is_bounded() -> void:
	for report_index: int in 50:
		GameSession.expedition_reports.append({
			"team_name": "Returned Company %02d" % report_index,
			"hero_names": ["Hero A"],
			"outcome": "victory",
			"casualty_names": ["Hero B"] if report_index == 49 else [],
			"stones_earned": 4,
			"items_earned": 2,
			"xp_earned": 8,
			"cumulative_stones": 40,
			"cumulative_items": 20,
			"cumulative_xp": 80,
			"stopped_reason": "requested",
		})
	GameSession.expedition_orders.append({
		"id": "long-order",
		"team_name": "The Forty Eight Character Expedition Company Name",
		"hero_ids": [],
		"zone_id": "verdant_outskirts",
		"initial_duration_seconds": 120.0,
		"remaining_seconds": 60.0,
		"runs_completed": 0,
		"total_runs": 1,
		"stop_requested": false,
	})
	var hub: Node3D = _instantiate_hub()
	var recent: ItemList = hub.get_node("%RecentReturns") as ItemList
	assert_eq(recent.item_count, 50)
	assert_string_contains(recent.get_item_tooltip(0), "Hero B")
	assert_string_contains(recent.get_item_tooltip(0), "Cumulative: 40 stones, 20 items, 80 XP")
	var cards: VBoxContainer = hub.get_node("%OrderCards") as VBoxContainer
	var title: Label = cards.get_child(0).get_node("Box/Head/Title") as Label
	assert_eq(title.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS)
	assert_eq(title.tooltip_text, title.text)


func test_enhance_budget_labels_follow_balance_rank_names() -> void:
	var hub: Node3D = _instantiate_hub()
	var balance: BalanceTable = preload("res://balance.tres")
	for rank_name: String in balance.rank_names:
		var budget: SpinBox = hub.get_node("%%%sBudget" % rank_name) as SpinBox
		assert_not_null(budget)
		assert_eq(budget.prefix, "%s " % rank_name)


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


func _restore_original_save() -> void:
	if not _original_save_existed:
		_remove_file_if_exists(SaveService.SAVE_PATH)
		return
	var save_file: FileAccess = FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	assert_not_null(save_file)
	if save_file == null:
		return
	save_file.store_buffer(_original_save_bytes)
	save_file.close()
