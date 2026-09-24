class_name HubUiBuilder
extends RefCounted

const INK: Color = Color("101917")
const BALANCE: BalanceTable = preload("res://balance.tres")


static func build(root: Control, confirm_dialog: ConfirmationDialog, enhance_dialog: ConfirmationDialog) -> void:
	if root.has_node("Background"):
		return
	var background := ColorRect.new()
	_add(root, background, "Background")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = INK
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_header(root)
	_build_nav(root)
	var content := Control.new()
	_add(root, content, "Content")
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 20.0
	content.offset_top = 112.0
	content.offset_right = -20.0
	content.offset_bottom = -70.0
	_build_expeditions(content)
	_build_shared_roster(content)
	_build_teams(content)
	_build_armory(content)
	_build_selected_hero(content)
	_build_hall(content)
	_build_footer(root)
	_build_confirm_dialog(confirm_dialog)
	_build_enhance_dialog(enhance_dialog)


static func _build_confirm_dialog(dialog: ConfirmationDialog) -> void:
	var content := _vbox(dialog, "DialogContent")
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 12.0
	content.offset_top = 44.0
	content.offset_right = -12.0
	content.offset_bottom = -52.0
	var bulk_controls := _vbox(content, "BulkControls", true)
	bulk_controls.visible = false
	var quantity := _add_spin(bulk_controls, "BulkQuantity", 0, 9999, 0)
	quantity.prefix = "Quantity (0 = all) "
	var body := RichTextLabel.new()
	_add(content, body, "DialogBody", true)
	body.custom_minimum_size = Vector2(680.0, 260.0)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.scroll_active = true
	body.selection_enabled = true


static func _build_header(root: Control) -> void:
	var header := HBoxContainer.new()
	_add(root, header, "Header")
	_anchor_top(header, 20.0, 16.0, -20.0, 52.0)
	header.add_theme_constant_override("separation", 10)
	var title := _label(header, "MERCENARY HALL", "HallTitle")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("CBA76A"))
	var title_font := SystemFont.new()
	title_font.font_names = PackedStringArray(["Georgia", "Times New Roman"])
	title.add_theme_font_override("font", title_font)
	var stones := _label(header, "Summon Stones: 0", "Stones", true)
	stones.theme_type_variation = &"SectionHeading"
	var separator := _label(header, "·", "CurrencySeparator")
	separator.theme_type_variation = &"SectionHeading"
	var essence := _label(header, "Essence: 0", "Essence", true)
	essence.theme_type_variation = &"SectionHeading"


static func _build_nav(root: Control) -> void:
	var nav := HBoxContainer.new()
	_add(root, nav, "Nav")
	_anchor_top(nav, 20.0, 60.0, -20.0, 98.0)
	nav.add_theme_constant_override("separation", 8)
	for data: Array in [["ExpeditionsTab", "Expeditions"], ["TeamsTab", "Teams"], ["ArmoryTab", "Armory"], ["HallTab", "Hall"]]:
		var button := _button(nav, data[1], data[0], true)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.theme_type_variation = &"ActiveNavButton" if data[0] == "ExpeditionsTab" else &""


static func _build_expeditions(content: Control) -> void:
	var view := HBoxContainer.new()
	_add(content, view, "ExpeditionsView", true)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.add_theme_constant_override("separation", 16)
	var dispatch := _panel(view, "DispatchPanel")
	dispatch.custom_minimum_size.x = 310.0
	var left := _vbox(dispatch, "VBox")
	_heading(left, "SAVED TEAMS")
	var empty := _label(left, "Save a team to start an expedition.", "DispatchEmpty", true)
	empty.theme_type_variation = &"MutedLabel"
	empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var presets := ItemList.new()
	_add(left, presets, "PresetDispatchList", true)
	presets.size_flags_vertical = Control.SIZE_EXPAND_FILL
	presets.select_mode = ItemList.SELECT_MULTI
	var runs_row := HBoxContainer.new()
	_add(left, runs_row, "RunsRow")
	var runs_label := _label(runs_row, "Runs per team", "Label")
	runs_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var runs := SpinBox.new()
	_add(runs_row, runs, "RunsPerTeam", true)
	runs.custom_minimum_size.x = 92.0
	runs.min_value = 1
	runs.max_value = 999
	runs.value = 1
	_button(left, "Combine selected teams", "CombineTeams", true, true)
	_add_option(left, "CombinedZone")
	_button(left, "Repeat until stopped", "RepeatUntilStopped", true, true)
	_button(left, "Battle settings", "BattleSettingsToggle", true)
	var settings := _panel(left, "BattleSettings", true)
	settings.visible = false
	var settings_scroll := ScrollContainer.new()
	_add(settings, settings_scroll, "SettingsScroll")
	settings_scroll.custom_minimum_size.y = 190.0
	settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var settings_box := _vbox(settings_scroll, "SettingsBox")
	_heading(settings_box, "BATTLE POLICIES")
	_add_option(settings_box, "BattleStance")
	_button(settings_box, "Auto battle", "AutoBattle", true, true)
	_button(settings_box, "Auto heal", "AutoHeal", true, true)
	_button(settings_box, "Auto revive", "AutoRevive", true, true)
	_button(settings_box, "Reserve last revival", "ReserveLastRevival", true, true)
	_button(settings_box, "Retreat if empty", "RetreatIfEmpty", true, true)
	var threshold := _add_spin(settings_box, "HealThreshold", 0, 100, 50)
	threshold.prefix = "Heal below % "
	var healing := _add_spin(settings_box, "HealingAllocation", 0, 100, 0)
	healing.prefix = "Healing allocation % "
	var healing_floor := _add_spin(settings_box, "HealingFloor", 0, 9999, 0)
	healing_floor.prefix = "Keep healing "
	var revival := _add_spin(settings_box, "RevivalAllocation", 0, 100, 0)
	revival.prefix = "Revival allocation % "
	var revival_floor := _add_spin(settings_box, "RevivalFloor", 0, 9999, 0)
	revival_floor.prefix = "Keep revival "
	_button(settings_box, "Fill suggested allocations", "SuggestedAllocations", true)
	var summary := RichTextLabel.new()
	_add(left, summary, "DispatchSummary", true)
	summary.custom_minimum_size.y = 108.0
	_button(left, "Dispatch selected teams", "DispatchSelected", true).theme_type_variation = &"PrimaryButton"
	_button(left, "Manage teams", "ManageTeams", true)
	_button(left, "Go to Hall", "GoToHall", true)
	var activity := _panel(view, "ActivityPanel")
	activity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var right := _vbox(activity, "VBox")
	var head := HBoxContainer.new()
	_add(right, head, "Header")
	var heading := _heading(head, "EXPEDITIONS")
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var counts := _label(head, "0 active · 0 heroes away", "ExpeditionCounts", true)
	counts.theme_type_variation = &"MutedLabel"
	var warning := HBoxContainer.new()
	_add(right, warning, "RecoveryWarning", true)
	warning.visible = false
	var warning_text := _label(warning, "Lost gear is waiting for review. Its recovery clock is paused.", "Text")
	warning_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	warning_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning_text.add_theme_color_override("font_color", Color("E8AAA0"))
	_button(warning, "Review losses", "ReviewLosses", true)
	var orders_scroll := ScrollContainer.new()
	_add(right, orders_scroll, "OrdersScroll")
	orders_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	orders_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var cards := _vbox(orders_scroll, "OrderCards", true)
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_heading(right, "STRANDED INCIDENTS")
	var incidents_scroll := ScrollContainer.new()
	_add(right, incidents_scroll, "IncidentsScroll", true)
	incidents_scroll.custom_minimum_size.y = 110.0
	incidents_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var incidents := _vbox(incidents_scroll, "IncidentCards", true)
	incidents.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_heading(right, "RECENT RETURNS")
	var returns := ItemList.new()
	_add(right, returns, "RecentReturns", true)
	returns.custom_minimum_size.y = 112.0


static func _build_shared_roster(content: Control) -> void:
	var panel := _panel(content, "SharedRosterPanel", true)
	panel.visible = false
	panel.anchor_bottom = 1.0
	panel.offset_right = 300.0
	var box := _vbox(panel, "VBox")
	_heading(box, "ROSTER")
	_add_option(box, "RosterRankFilter")
	_button(box, "Exact rank", "RosterExactRank", true, true)
	_add_option(box, "RosterTypeFilter")
	_add_option(box, "RosterAvailabilityFilter")
	_button(box, "Favorites only", "RosterFavoritesOnly", true, true)
	var list := ItemList.new()
	_add(box, list, "RosterList", true)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.select_mode = ItemList.SELECT_MULTI
	_button(box, "Select all visible", "SelectAllRoster", true)


static func _build_teams(content: Control) -> void:
	var view := VBoxContainer.new()
	_add(content, view, "TeamsView", true)
	view.visible = false
	_anchor_fill(view, 316.0, 0.0, -412.0, 0.0)
	view.add_theme_constant_override("separation", 12)
	var preset_panel := _panel(view, "PresetPanel")
	preset_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box := _vbox(preset_panel, "VBox")
	_heading(box, "TEAM PRESETS")
	_add_option(box, "PresetSelector")
	var name := LineEdit.new()
	_add(box, name, "PresetName", true)
	name.placeholder_text = "Team name"
	name.max_length = 48
	_add_option(box, "ZoneOption")
	var members := RichTextLabel.new()
	_add(box, members, "PresetMembers", true)
	members.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var buttons := HBoxContainer.new()
	_add(box, buttons, "PresetButtons")
	var save := _button(buttons, "Save team", "SavePreset", true)
	save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save.theme_type_variation = &"PrimaryButton"
	var delete := _button(buttons, "Delete preset", "DeletePreset", true)
	delete.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var advance := _panel(view, "AdvancementPanel")
	var lower := _vbox(advance, "VBox")
	_heading(lower, "HERO ADVANCEMENT")
	_add_option(lower, "TargetOption")
	var actions := HBoxContainer.new()
	_add(lower, actions, "Buttons")
	var sacrifice := _button(actions, "Sacrifice selected", "Sacrifice", true)
	sacrifice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sacrifice.theme_type_variation = &"DangerButton"
	var rank_up := _button(actions, "Rank up selected", "RankUp", true)
	rank_up.size_flags_horizontal = Control.SIZE_EXPAND_FILL


static func _build_armory(content: Control) -> void:
	var view := _panel(content, "ArmoryView", true)
	view.visible = false
	_anchor_fill(view, 316.0, 0.0, -412.0, 0.0)
	var box := _vbox(view, "Inventory")
	_heading(box, "ARMORY")
	_add_option(box, "InventoryRankFilter")
	_button(box, "Exact rank", "InventoryExactRank", true, true)
	_add_option(box, "InventorySlotFilter")
	_add_option(box, "InventoryProtectionFilter")
	_button(box, "Favorite item", "FavoriteItem", true, true)
	var list := ItemList.new()
	_add(box, list, "InventoryList", true)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.select_mode = ItemList.SELECT_MULTI
	_button(box, "Select all visible", "SelectAllInventory", true)
	var actions := HBoxContainer.new()
	_add(box, actions, "Actions")
	for data: Array in [["Equip", "Equip"], ["Salvage", "Salvage"], ["Enhance", "Enhance"]]:
		var button := _button(actions, data[1], data[0], true)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button_by_name(actions, "Equip").theme_type_variation = &"PrimaryButton"
	button_by_name(actions, "Salvage").theme_type_variation = &"DangerButton"
	var parts := _label(box, "Parts", "Parts", true)
	parts.theme_type_variation = &"MutedLabel"
	parts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var conversion := HBoxContainer.new()
	_add(box, conversion, "ConvertRow")
	_add_option(conversion, "ConvertRankOption").size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_spin(conversion, "ConvertQuantity", 1, 9999, 1)
	var reserve := _add_spin(conversion, "ConvertReserve", 0, 999999, 0)
	reserve.prefix = "Keep "
	_button(conversion, "Max", "ConvertMax", true)
	_button(conversion, "Convert", "Convert", true)


static func _build_selected_hero(content: Control) -> void:
	var panel := _panel(content, "SelectedHeroPanel", true)
	panel.visible = false
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -396.0
	var box := _vbox(panel, "VBox")
	_heading(box, "SELECTED HERO")
	var availability := _label(box, "", "HeroAvailability", true)
	availability.theme_type_variation = &"MutedLabel"
	availability.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button(box, "Favorite hero", "FavoriteHero", true, true)
	var equipped := ItemList.new()
	_add(box, equipped, "EquippedList", true)
	equipped.size_flags_vertical = Control.SIZE_EXPAND_FILL
	equipped.select_mode = ItemList.SELECT_SINGLE
	var actions := HBoxContainer.new()
	_add(box, actions, "GearButtons")
	var unequip := _button(actions, "Unequip", "Unequip", true)
	unequip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var all := _button(actions, "Unequip all", "UnequipAll", true)
	all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var detail := _label(box, "", "HeroDetail", true)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


static func _build_hall(content: Control) -> void:
	var view := HBoxContainer.new()
	_add(content, view, "HallView", true)
	view.visible = false
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.add_theme_constant_override("separation", 16)
	var upgrades_scroll := ScrollContainer.new()
	_add(view, upgrades_scroll, "UpgradesScroll")
	upgrades_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	upgrades_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var buildings := _panel(upgrades_scroll, "BuildingsPanel")
	buildings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := _vbox(buildings, "VBox")
	_heading(box, "HALL UPGRADES")
	var turns := _label(box, "Turn 0", "Turns", true)
	turns.theme_type_variation = &"MutedLabel"
	for data: Array in [["CircleLevel", "Summoning Circle", "UpgradeCircle"], ["ForgeLevel", "Forge", "UpgradeForge"], ["TrainingHallLevel", "Training Hall", "UpgradeTrainingHall"], ["SanctumLevel", "Sanctum", "UpgradeSanctum"], ["ReliquaryLevel", "Reliquary", "UpgradeReliquary"]]:
		_label(box, "%s — Lv 0" % data[1], data[0], true)
		_button(box, "Upgrade %s" % data[1], data[2], true)
	var hall_scroll := ScrollContainer.new()
	_add(view, hall_scroll, "HallRight")
	hall_scroll.custom_minimum_size.x = 396.0
	hall_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var right := _vbox(hall_scroll, "VBox")
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_heading(right, "SUMMONING")
	_button(right, "Summon hero", "Summon", true).theme_type_variation = &"PrimaryButton"
	_heading(right, "RECOVERY")
	var recovery_status := _label(right, "No lost gear is waiting.", "RecoveryClockStatus", true)
	recovery_status.theme_type_variation = &"MutedLabel"
	recovery_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var caches := ItemList.new()
	_add(right, caches, "LostCacheList", true)
	caches.custom_minimum_size.y = 132.0
	caches.select_mode = ItemList.SELECT_SINGLE
	_add_option(right, "RecoveryTeamOption")
	_button(right, "Recover selected cache", "Recover", true)
	_button(right, "Start recovery window", "StartRecoveryWindow", true)
	_heading(right, "PRACTICE")
	_add_option(right, "PracticePreset")
	_add_option(right, "PracticeZone")
	_button(right, "Practice RTS battle", "EnterArena", true)
	_heading(right, "SUPPLY STOCK")
	var stock := _label(right, "Healing 0 · Revival 0", "SupplyStock", true)
	stock.theme_type_variation = &"MutedLabel"
	_add_option(right, "SupplyKind")
	var supply_quantity := _add_spin(right, "SupplyQuantity", 0, 9999, 0)
	supply_quantity.prefix = "Quantity (0 = max) "
	var supply_reserve := _add_spin(right, "SupplyReserve", 0, 9999, 0)
	supply_reserve.prefix = "Keep F-parts "
	_button(right, "Preview craft", "PreviewSupply", true)
	_button(right, "Confirm craft", "ConfirmSupply", true)
	var supply_preview := _label(right, "", "SupplyPreview", true)
	supply_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


static func _build_footer(root: Control) -> void:
	var footer := HBoxContainer.new()
	_add(root, footer, "Footer")
	footer.anchor_top = 1.0
	footer.anchor_right = 1.0
	footer.anchor_bottom = 1.0
	footer.offset_left = 20.0
	footer.offset_top = -58.0
	footer.offset_right = -20.0
	footer.offset_bottom = -18.0
	var status := _label(footer, "...", "Status", true)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.theme_type_variation = &"MutedLabel"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var hint := _label(footer, "Esc · Pause", "Hint")
	hint.theme_type_variation = &"MutedLabel"


static func _build_enhance_dialog(dialog: ConfirmationDialog) -> void:
	var box := _vbox(dialog, "VBox")
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 12.0
	box.offset_top = 44.0
	box.offset_right = -12.0
	box.offset_bottom = -52.0
	var target := _add_spin(box, "EnhanceTargetLevel", 1, 1, 1)
	target.prefix = "Target +"
	_button(box, "Use available parts", "UseAvailableParts", true)
	var budgets := GridContainer.new()
	_add(box, budgets, "Budgets")
	budgets.columns = 4
	for rank_name: String in BALANCE.rank_names:
		var budget := _add_spin(budgets, "%sBudget" % rank_name, 0, 999999, 0)
		budget.prefix = "%s " % rank_name
	var preview := RichTextLabel.new()
	_add(box, preview, "EnhancePreview", true)
	preview.custom_minimum_size.y = 240.0
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.scroll_active = true
	preview.selection_enabled = true


static func _add(parent: Node, child: Node, node_name: String, unique: bool = false) -> void:
	child.name = node_name
	parent.add_child(child)
	child.owner = parent.owner
	child.unique_name_in_owner = unique


static func _label(parent: Node, text: String, node_name: String, unique: bool = false) -> Label:
	var label := Label.new()
	_add(parent, label, node_name, unique)
	label.text = text
	return label


static func _heading(parent: Node, text: String) -> Label:
	var label := _label(parent, text, "Heading")
	label.theme_type_variation = &"SectionHeading"
	return label


static func _button(parent: Node, text: String, node_name: String, unique: bool = false, checkable: bool = false) -> Button:
	var button: Button = CheckBox.new() if checkable else Button.new()
	_add(parent, button, node_name, unique)
	button.text = text
	return button


static func _panel(parent: Node, node_name: String, unique: bool = false) -> PanelContainer:
	var panel := PanelContainer.new()
	_add(parent, panel, node_name, unique)
	return panel


static func _vbox(parent: Node, node_name: String, unique: bool = false) -> VBoxContainer:
	var box := VBoxContainer.new()
	_add(parent, box, node_name, unique)
	box.add_theme_constant_override("separation", 6)
	return box


static func _add_option(parent: Node, node_name: String) -> OptionButton:
	var option := OptionButton.new()
	_add(parent, option, node_name, true)
	option.fit_to_longest_item = false
	option.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return option


static func _add_spin(parent: Node, node_name: String, minimum: float, maximum: float, value: float) -> SpinBox:
	var spin := SpinBox.new()
	_add(parent, spin, node_name, true)
	spin.min_value = minimum
	spin.max_value = maximum
	spin.value = value
	spin.custom_minimum_size.x = 78.0
	return spin


static func _anchor_top(control: Control, left: float, top: float, right: float, bottom: float) -> void:
	control.anchor_right = 1.0
	control.offset_left = left
	control.offset_top = top
	control.offset_right = right
	control.offset_bottom = bottom


static func _anchor_fill(control: Control, left: float, top: float, right: float, bottom: float) -> void:
	control.anchor_right = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = left
	control.offset_top = top
	control.offset_right = right
	control.offset_bottom = bottom


static func button_by_name(parent: Node, node_name: String) -> Button:
	return parent.get_node(node_name) as Button
