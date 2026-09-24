extends GutTest

const BALANCE: BalanceTable = preload("res://balance.tres")

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


func test_buildings_switch_panels_without_clearing_shared_roster_selection() -> void:
	var hero := Hero.new("Tab Keeper", 2)
	hero.def_id = &"knight"
	GameSession.add_hero(hero)
	var hub: Node3D = _instantiate_hub()
	var roster: ItemList = hub.get_node("%RosterList") as ItemList
	var town: TownView = hub.get_node("%Town") as TownView
	var teams_view: Control = hub.get_node("%TeamsView") as Control
	var armory_view: Control = hub.get_node("%ArmoryView") as Control

	town.building_selected.emit(&"TrainingHall")
	roster.select(0)
	roster.multi_selected.emit(0, true)
	town.building_selected.emit(&"Forge")

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


func test_a_favorite_that_fails_to_save_says_so_and_unticks() -> void:
	var item := Item.new(&"ring", 2)
	GameSession.add_item(item)
	var hub: Node3D = _instantiate_hub()
	var inventory: ItemList = hub.get_node("%InventoryList") as ItemList
	var favorite: CheckBox = hub.get_node("%FavoriteItem") as CheckBox
	inventory.select(0)
	inventory.multi_selected.emit(0, true)
	assert_true(SaveService.save())
	assert_eq(DirAccess.make_dir_absolute(SaveService.TMP_PATH), OK)
	favorite.set_pressed_no_signal(true)
	favorite.toggled.emit(true)
	assert_push_error("Save failed")
	assert_eq(DirAccess.remove_absolute(SaveService.TMP_PATH), OK)
	assert_false(GameSession.inventory[0].favorite)
	assert_false(favorite.button_pressed, "the box shows the real state")
	assert_ne((hub.get_node("%Status") as Label).text, "")
	assert_eq((hub.get_node("%Status") as Label).text, GameSession.last_action_error)


func test_a_favorite_refused_while_the_load_is_blocked_stays_unticked() -> void:
	var hero := Hero.new("Mira", 2)
	GameSession.add_hero(hero)
	GameSession.add_item(Item.new(&"ring", 2))
	var hub: Node3D = _instantiate_hub()
	var roster: ItemList = hub.get_node("%RosterList") as ItemList
	var inventory: ItemList = hub.get_node("%InventoryList") as ItemList
	roster.select(0)
	roster.multi_selected.emit(0, true)
	inventory.select(0)
	inventory.multi_selected.emit(0, true)
	SaveService.load_blocked = true
	SaveService.load_block_reason = "Blocked for the test."
	for box_name: String in ["FavoriteHero", "FavoriteItem"]:
		var box: CheckBox = hub.get_node("%" + box_name) as CheckBox
		assert_false(box.disabled, box_name)
		box.set_pressed_no_signal(true)
		box.toggled.emit(true)
		assert_false(box.button_pressed, "%s shows the refused state" % box_name)
		assert_eq((hub.get_node("%Status") as Label).text, "Blocked for the test.")
	SaveService.load_blocked = false
	SaveService.load_block_reason = ""
	assert_false(hero.favorite)
	assert_false(GameSession.inventory[0].favorite)


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
	(hub.get_node("%Town") as TownView).building_selected.emit(&"Reliquary")
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


const BUILDING_ACTIONS: Dictionary = {
	&"SummoningCircle": ["Summon", "UpgradeCircle"],
	&"Forge": ["InventoryList", "Equip", "Unequip", "UnequipAll", "Salvage", "Enhance", "Convert", "FavoriteItem", "FavoriteHero", "RosterList", "UpgradeForge", "KeeperName", "AssignKeeper", "UnassignKeeper"],
	&"TrainingHall": ["PresetSelector", "SavePreset", "DeletePreset", "RosterList", "EnterArena", "UpgradeTrainingHall", "KeeperName", "AssignKeeper", "UnassignKeeper"],
	&"Sanctum": ["RosterList", "TargetOption", "Sacrifice", "RankUp", "FavoriteHero", "UpgradeSanctum", "KeeperName", "AssignKeeper", "UnassignKeeper"],
	&"Reliquary": ["LostCacheList", "Recover", "StartRecoveryWindow", "UpgradeReliquary", "KeeperName", "AssignKeeper", "UnassignKeeper"],
	&"TownGate": ["PresetDispatchList", "CombineTeams", "RepeatUntilStopped", "BattleSettingsToggle", "DispatchSelected", "OrderCards", "IncidentCards", "RecentReturns"],
	&"Apothecary": ["SupplyKind", "PreviewSupply", "ConfirmSupply", "KeeperName", "AssignKeeper", "UnassignKeeper"],
}


func test_no_panel_is_open_by_default_so_the_town_shows() -> void:
	var hub: Node3D = _instantiate_hub()
	assert_false(hub.has_node("UI/Root/Background"), "no opaque backdrop hides the town")
	for building_id: StringName in BUILDING_ACTIONS:
		for action: String in BUILDING_ACTIONS[building_id]:
			assert_false((hub.get_node("%" + action) as Control).is_visible_in_tree(), "%s is closed" % action)
	assert_true((hub.get_node("%Stones") as Control).is_visible_in_tree(), "currencies stay as a HUD")
	assert_true((hub.get_node("%Status") as Control).is_visible_in_tree(), "status stays as a HUD")


func test_every_building_opens_the_panel_holding_its_actions() -> void:
	var hub: Node3D = _instantiate_hub()
	var town: TownView = hub.get_node("%Town") as TownView
	for building_id: StringName in BUILDING_ACTIONS:
		assert_true(town.has_node(NodePath(building_id)), "%s stands in the town" % building_id)
		town.building_selected.emit(building_id)
		for action: String in BUILDING_ACTIONS[building_id]:
			assert_true((hub.get_node("%" + action) as Control).is_visible_in_tree(), "%s opens %s" % [building_id, action])
	# Each building shows only its own upgrade.
	town.building_selected.emit(&"Forge")
	for other: String in ["UpgradeCircle", "UpgradeTrainingHall", "UpgradeSanctum", "UpgradeReliquary", "Summon", "Sacrifice", "PreviewSupply"]:
		assert_false((hub.get_node("%" + other) as Control).is_visible_in_tree(), "the Forge does not show %s" % other)
	# The Circle and the Gate take no keeper.
	for keeperless: StringName in [&"SummoningCircle", &"TownGate"]:
		town.building_selected.emit(keeperless)
		assert_false((hub.get_node("%AssignKeeper") as Control).is_visible_in_tree(), "%s has no keeper row" % keeperless)


func test_the_keeper_row_assigns_shows_away_and_unassigns() -> void:
	var mira := Hero.new("Mira", 7)
	mira.def_id = &"knight"
	mira.level = 80
	mira.passions = [&"smithing", &"drill"]
	mira.profession_xp[&"smithing"] = 100000.0
	var bo := Hero.new("Bo", 2)
	bo.def_id = &"mage"
	bo.passions = [&"rites", &"alchemy"]
	GameSession.add_hero(mira)
	GameSession.add_hero(bo)
	var skill: int = Hero.profession_skill(mira, &"smithing", BALANCE)
	assert_gt(skill, 0)
	var hub: Node3D = _instantiate_hub()
	(hub.get_node("%Town") as TownView).building_selected.emit(&"Forge")
	var keeper_name: Label = hub.get_node("%KeeperName") as Label
	assert_eq(keeper_name.text, "No keeper")
	assert_true((hub.get_node("%UnassignKeeper") as Button).disabled)

	(hub.get_node("%AssignKeeper") as Button).pressed.emit()
	var picker: PopupMenu = hub.get_node("%KeeperPicker") as PopupMenu
	assert_true(picker.visible, "the roster picker opens")
	assert_eq(picker.item_count, 2)
	assert_eq(picker.get_item_text(0), "Mira — Smithing %d · passion" % skill)
	assert_eq(picker.get_item_text(1), "Bo — Smithing 0")
	picker.index_pressed.emit(0)
	picker.hide()
	assert_eq(GameSession.keeper_for(&"Forge"), mira)
	assert_eq(keeper_name.text, "Mira · Smithing %d · passions Smithing, Drill" % skill, "both passions, the matching one too")
	assert_true(GameSession.station_hero(bo, &"Forge"))
	assert_eq(keeper_name.text, "Bo · Smithing 0 · passions Rites, Alchemy")
	assert_true(GameSession.station_hero(mira, &"Forge"))
	assert_false((hub.get_node("%UnassignKeeper") as Button).disabled)

	var roster_list: ItemList = hub.get_node("%RosterList") as ItemList
	assert_string_contains(roster_list.get_item_text(0), "Keeps the Forge")
	roster_list.select(0)
	roster_list.multi_selected.emit(0, true)
	var detail: String = (hub.get_node("%HeroDetail") as Label).text
	assert_string_contains(detail, "Passions: Smithing, Drill")
	assert_string_contains(detail, "Skills: Smithing %d, Rites 0, Drill 0, Tracking 0, Alchemy 0" % skill)
	assert_string_contains(detail, "Station: Forge")
	assert_string_contains((hub.get_node("%HeroAvailability") as Label).text, "Keeps the Forge")

	assert_ne(GameSession.dispatch_expedition([mira.instance_id], "verdant_outskirts", 1, "Out"), "", GameSession.last_action_error)
	assert_eq(keeper_name.text, "Mira · Away")
	(hub.get_node("%UnassignKeeper") as Button).pressed.emit()
	assert_null(GameSession.keeper_for(&"Forge"))
	assert_eq(keeper_name.text, "No keeper")


func test_a_pick_after_a_roster_rollback_stations_the_live_hero() -> void:
	var mira := Hero.new("Mira", 2)
	mira.def_id = &"knight"
	var bo := Hero.new("Bo", 2)
	bo.def_id = &"mage"
	GameSession.add_hero(mira)
	GameSession.add_hero(bo)
	var hub: Node3D = _instantiate_hub()
	(hub.get_node("%Town") as TownView).building_selected.emit(&"Forge")
	(hub.get_node("%AssignKeeper") as Button).pressed.emit()
	var picker: PopupMenu = hub.get_node("%KeeperPicker") as PopupMenu
	assert_true(picker.visible)
	# A failed save while the picker is open rebuilds every Hero from the snapshot.
	assert_true(SaveService.save())
	assert_eq(DirAccess.make_dir_absolute(SaveService.TMP_PATH), OK)
	assert_false(GameSession.station_hero(bo, &"Sanctum"))
	assert_push_error("Save failed")
	assert_eq(DirAccess.remove_absolute(SaveService.TMP_PATH), OK)
	assert_false(GameSession.roster.has(mira), "the old Mira object is gone")
	picker.index_pressed.emit(0)
	picker.hide()
	var keeper: Hero = GameSession.keeper_for(&"Forge")
	assert_not_null(keeper, (hub.get_node("%Status") as Label).text)
	if keeper != null:
		assert_eq(keeper.instance_id, mira.instance_id)


func test_the_dispatch_summary_names_the_counters_a_force_leaves_empty() -> void:
	var mira := Hero.new("Mira", 2)
	mira.def_id = &"knight"
	GameSession.add_hero(mira)
	assert_true(GameSession.station_hero(mira, &"Forge"))
	assert_ne(GameSession.save_team_preset("", "Couriers", [mira.instance_id], "verdant_outskirts"), "")
	var hub: Node3D = _instantiate_hub()
	var presets: ItemList = hub.get_node("%PresetDispatchList") as ItemList
	presets.select(0)
	presets.multi_selected.emit(0, true)
	var summary: String = (hub.get_node("%DispatchSummary") as RichTextLabel).text
	assert_string_contains(summary, "Runs without its keeper while away: Forge (Mira)")
	assert_false((hub.get_node("%DispatchSelected") as Button).disabled, "a warning, not a block")


func test_building_list_and_number_keys_open_the_same_panels() -> void:
	var hub: Node3D = _instantiate_hub()
	var ids: Array = BUILDING_ACTIONS.keys()
	for index: int in ids.size():
		var building_id: StringName = ids[index]
		var action: Control = hub.get_node("%" + str(BUILDING_ACTIONS[building_id][0])) as Control
		(hub.get_node("%%%sButton" % building_id) as Button).pressed.emit()
		assert_true(action.is_visible_in_tree(), "the %s list entry opens it" % building_id)
		(hub.get_node("%ClosePanel") as Button).pressed.emit()
		assert_false(action.is_visible_in_tree(), "Close shuts %s" % building_id)
		var key := InputEventKey.new()
		key.keycode = (KEY_1 + index) as Key
		key.physical_keycode = key.keycode
		key.pressed = true
		hub.get_viewport().push_input(key)
		assert_true(action.is_visible_in_tree(), "key %d opens %s" % [index + 1, building_id])


func test_escape_closes_the_open_building_before_it_pauses() -> void:
	var hub: Node3D = _instantiate_hub()
	var pause_menu: CanvasLayer = hub.get_node("%PauseMenu") as CanvasLayer
	var armory: Control = hub.get_node("%ArmoryView") as Control
	(hub.get_node("%ForgeButton") as Button).pressed.emit()
	_press_key(hub, KEY_ESCAPE)
	assert_false(armory.visible)
	assert_false(pause_menu.visible, "the first Esc only closed the Forge")
	_press_key(hub, KEY_ESCAPE)
	assert_true(pause_menu.visible, "Esc with no panel open pauses")
	_press_key(hub, KEY_ESCAPE)
	assert_false(pause_menu.visible, "Esc again resumes")


func test_a_click_on_a_building_opens_it_and_a_click_on_a_panel_does_not_fall_through() -> void:
	var hub: Node3D = _instantiate_hub()
	var town: TownView = hub.get_node("%Town") as TownView
	await get_tree().physics_frame
	await get_tree().physics_frame
	var camera: Camera3D = hub.get_viewport().get_camera_3d()
	var forge_at: Vector2 = camera.unproject_position((town.get_node("Forge") as Node3D).global_position)
	var hall_at: Vector2 = camera.unproject_position((town.get_node("TrainingHall") as Node3D).global_position)
	assert_eq(town.building_at(hall_at), &"TrainingHall")
	_click(hub, forge_at)
	var armory: Control = hub.get_node("%ArmoryView") as Control
	assert_true(armory.visible, "clicking the Forge opened it")
	assert_true(armory.get_global_rect().has_point(hall_at), "the Forge panel covers the Training Hall")
	_click(hub, hall_at)
	assert_true(armory.visible, "the click stayed on the panel")
	assert_false((hub.get_node("%TeamsView") as Control).visible, "and never reached the Training Hall")


func test_clicks_on_an_open_building_never_reach_the_town_behind_it() -> void:
	var hub: Node3D = _instantiate_hub()
	await get_tree().physics_frame
	await get_tree().physics_frame
	# The two layout roots the builder turned from PASS containers into click stoppers.
	for case: Array in [[&"TownGate", &"ExpeditionsView"], [&"TrainingHall", &"TeamsView"]]:
		hub._open(case[0])
		var view: Control = hub.get_node("%" + str(case[1])) as Control
		# The view itself is what the pointer is on, so only its own filter can stop the click.
		var behind: Vector2 = _town_point(hub, case[0], func(at: Vector2) -> bool:
			return view.get_global_rect().has_point(at) and _hovered(hub, at) == view)
		assert_ne(behind, Vector2(-1, -1), "a building shows behind %s" % case[1])
		_click(hub, behind)
		assert_eq(hub._open_building, case[0], "a click on %s stayed on it" % case[1])


func test_a_click_in_a_gap_between_panels_does_not_open_the_building_behind() -> void:
	var hub: Node3D = _instantiate_hub()
	await get_tree().physics_frame
	await get_tree().physics_frame
	hub._open(&"Forge")
	var shown: Array[Control] = []
	for panel_name: StringName in hub.BUILDING_PANELS[&"Forge"]:
		shown.append(hub.get_node("%" + str(panel_name)) as Control)
	var content: Control = hub.get_node("UI/Root/Content") as Control
	var gap: Vector2 = _town_point(hub, &"Forge", func(at: Vector2) -> bool:
		return content.get_global_rect().has_point(at) and shown.all(func(panel: Control) -> bool: return not panel.get_global_rect().has_point(at)))
	assert_ne(gap, Vector2(-1, -1), "the Forge layout has a gap over another building")
	_click(hub, gap)
	assert_eq(hub._open_building, &"Forge")


func test_while_paused_the_town_ignores_clicks_and_number_keys() -> void:
	var hub: Node3D = _instantiate_hub()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var camera: Camera3D = hub.get_viewport().get_camera_3d()
	var forge_at: Vector2 = camera.unproject_position((hub.get_node("%Town/Forge") as Node3D).global_position)
	_press_key(hub, KEY_ESCAPE)
	assert_true((hub.get_node("%PauseMenu") as CanvasLayer).visible)
	_click(hub, forge_at)
	assert_eq(hub._open_building, hub.NO_BUILDING, "a town click does nothing while paused")
	_press_key(hub, KEY_2)
	assert_eq(hub._open_building, hub.NO_BUILDING, "a number key does nothing while paused")
	_press_key(hub, KEY_ESCAPE)
	_press_key(hub, KEY_2)
	assert_eq(hub._open_building, &"Forge", "unpaused, the key works again")


func test_town_buildings_list_and_panels_name_the_same_ids() -> void:
	var in_town: Array = TownRules.HALL_HEXES.keys()
	for hall: StringName in in_town:
		assert_true(TownView.SCENES.has(hall), "%s has a scene" % hall)
	var in_list: Array = HubUiBuilder.BUILDINGS.map(func(entry: Array) -> StringName: return entry[0])
	var in_panels: Array = (load("res://hub/hub.gd") as GDScript).get_script_constant_map()["BUILDING_PANELS"].keys()
	for ids: Array in [in_town, in_list, in_panels]:
		ids.sort_custom(func(a: StringName, b: StringName) -> bool: return str(a) < str(b))
	assert_eq(in_town.size(), 7)
	assert_eq(in_list, in_town, "the building list matches the halls")
	assert_eq(in_panels, in_town, "BUILDING_PANELS matches the halls")


func test_only_the_towns_own_bodies_can_name_a_building() -> void:
	var hub: Node3D = _instantiate_hub()
	var town: TownView = hub.get_node("%Town") as TownView
	var forge: Node3D = town.get_node("Forge") as Node3D
	var camera: Camera3D = hub.get_viewport().get_camera_3d()
	# A body on the default layer, standing between the camera and the Forge (the avatar, later).
	var blocker := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(4, 4, 4)
	blocker.add_child(shape)
	hub.add_child(blocker)
	blocker.global_position = forge.global_position.lerp(camera.global_position, 0.3)
	# A foreign body on the pick layer, standing where no building is.
	var stray := StaticBody3D.new()
	stray.collision_layer = TownView.PICK_LAYER
	stray.add_child(shape.duplicate())
	hub.add_child(stray)
	stray.global_position = Vector3(0, 1.5, 6)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(town.building_at(camera.unproject_position(forge.global_position)), &"Forge", "the ray passes the blocker")
	assert_eq(town.building_at(camera.unproject_position(stray.global_position)), &"", "a body outside the town names nothing")


func test_opening_every_building_does_not_change_the_save() -> void:
	var before: Dictionary = GameSession.to_dict()
	var hub: Node3D = _instantiate_hub()
	for building_id: StringName in BUILDING_ACTIONS:
		(hub.get_node("%Town") as TownView).building_selected.emit(building_id)
	(hub.get_node("%ClosePanel") as Button).pressed.emit()
	assert_eq(JSON.stringify(GameSession.to_dict(), "", true), JSON.stringify(before, "", true))


func _click(hub: Node3D, at: Vector2) -> void:
	for pressed: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = at
		click.global_position = at
		click.pressed = pressed
		# In viewport coordinates: the headless window is smaller than the viewport it stretches.
		hub.get_viewport().push_input(click, true)


## A screen point over a building other than `open`, that `where` accepts; (-1, -1) if none.
func _town_point(hub: Node3D, open: StringName, where: Callable) -> Vector2:
	var town: TownView = hub.get_node("%Town") as TownView
	var size: Vector2 = hub.get_viewport().get_visible_rect().size
	for y: int in range(0, int(size.y), 16):
		for x: int in range(0, int(size.x), 16):
			var at := Vector2(x, y)
			var building: StringName = town.building_at(at)
			if building != &"" and building != open and where.call(at) and _reachable(hub, at):
				return at
	return Vector2(-1, -1)


## GUT's own output panel overlays part of the viewport and eats clicks there, which would pass
## a no-fall-through test for the wrong reason; a usable point is under the hub or nothing.
func _reachable(hub: Node3D, at: Vector2) -> bool:
	var hovered: Control = _hovered(hub, at)
	return hovered == null or hub.is_ancestor_of(hovered)


func _hovered(hub: Node3D, at: Vector2) -> Control:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	hub.get_viewport().push_input(motion, true)
	return hub.get_viewport().gui_get_hovered_control()


func _press_key(hub: Node3D, keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var key := InputEventKey.new()
		key.keycode = keycode
		key.physical_keycode = keycode
		key.pressed = pressed
		hub.get_viewport().push_input(key)


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
