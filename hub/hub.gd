extends Node3D

const BALANCE: BalanceTable = preload("res://balance.tres")
const UI_BUILDER := preload("res://hub/hub_ui_builder.gd")
const MAX_TEAM_SIZE: int = 5
## A bonded hero's roster flag and town sign (ig-m6o.2.2.1), with the partner's name.
const PARTNER_SIGN: String = "♥ %s"
const NO_BUILDING: StringName = &""
## What each building opens (GAME_SPEC.md § The town hub). Every node named here is hidden unless
## the open building lists it.
const BUILDING_PANELS: Dictionary = {
	&"SummoningCircle": [&"HallView", &"CircleSection"],
	&"Forge": [&"ArmoryView", &"SharedRosterPanel", &"SelectedHeroPanel", &"KeeperPanel"],
	&"TrainingHall": [&"TeamsView", &"PresetPanel", &"TrainingPanel", &"SharedRosterPanel", &"SelectedHeroPanel", &"KeeperPanel"],
	&"Sanctum": [&"TeamsView", &"AdvancementPanel", &"SharedRosterPanel", &"SelectedHeroPanel", &"KeeperPanel"],
	&"Reliquary": [&"HallView", &"ReliquarySection", &"KeeperPanel"],
	&"TownGate": [&"ExpeditionsView"],
	&"Apothecary": [&"HallView", &"SupplySection", &"KeeperPanel"],
}
## What a placed House or workplace opens; its id is not a BUILDING_PANELS key.
const PLACED_PANEL: StringName = &"PlacedBuildingPanel"
## What a click on a hero in town opens (ig-6m2.6.2): the roster with that hero selected, and its
## detail. Not a building, so it is no BUILDING_PANELS key (those are the 1-7 buttons).
const HERO_VIEW: StringName = &"Hero"
const HERO_PANELS: Array[StringName] = [&"SharedRosterPanel", &"SelectedHeroPanel"]
## The panel-content refreshes a roster change skips while their panel is hidden (ig-7sn.9), with the
## panels they write (any one shown runs them), in the order _open runs the skipped ones: the roster
## first, the hero detail last (it and %EquippedList read the roster's selection).
const PANEL_REFRESHES: Dictionary[StringName, Array] = {
	&"roster": [&"SharedRosterPanel"],
	&"preset_lists": [&"TeamsView", &"ExpeditionsView"],
	&"preset_editor": [&"TeamsView"],
	&"practice": [&"TeamsView"],
	&"recovery": [&"ReliquarySection"],
	&"expeditions": [&"ExpeditionsView"],
	&"equipped": [&"SelectedHeroPanel"],
	&"hero_detail": [&"SelectedHeroPanel"],
}
const EXPEDITION_ZONES: Array[ZoneDefinition] = [
	preload("res://zones/defs/verdant_outskirts.tres"),
	preload("res://zones/defs/ashfall_reaches.tres"),
	preload("res://zones/defs/sundered_vault.tres"),
]

@onready var _roster_list: ItemList = %RosterList
@onready var _roster_rank_filter: OptionButton = %RosterRankFilter
@onready var _roster_exact_rank: CheckBox = %RosterExactRank
@onready var _roster_type_filter: OptionButton = %RosterTypeFilter
@onready var _target_option: OptionButton = %TargetOption
@onready var _essence: Label = %Essence
@onready var _stones: Label = %Stones
@onready var _wood: Label = %Wood
@onready var _turns: Label = %Turns
@onready var _lost_cache_list: ItemList = %LostCacheList
@onready var _recovery_clock_status: Label = %RecoveryClockStatus
@onready var _summon_button: Button = %Summon
@onready var _inventory_list: ItemList = %InventoryList
@onready var _inventory_rank_filter: OptionButton = %InventoryRankFilter
@onready var _inventory_exact_rank: CheckBox = %InventoryExactRank
@onready var _inventory_slot_filter: OptionButton = %InventorySlotFilter
@onready var _parts: Label = %Parts
@onready var _circle_level: Label = %CircleLevel
@onready var _forge_level: Label = %ForgeLevel
@onready var _training_hall_level: Label = %TrainingHallLevel
@onready var _sanctum_level: Label = %SanctumLevel
@onready var _reliquary_level: Label = %ReliquaryLevel
@onready var _convert_rank_option: OptionButton = %ConvertRankOption
@onready var _equipped_list: ItemList = %EquippedList
@onready var _hero_detail: Label = %HeroDetail
@onready var _zone_option: OptionButton = %ZoneOption
@onready var _status: Label = %Status
@onready var _pause_menu: CanvasLayer = %PauseMenu
@onready var _confirm_dialog: ConfirmationDialog = %ConfirmDialog
@onready var _enhance_dialog: ConfirmationDialog = %EnhanceDialog
@onready var _starve_dialog: AcceptDialog = %StarveDialog
@onready var _close_panel: Button = %ClosePanel
@onready var _roster_availability_filter: OptionButton = %RosterAvailabilityFilter
@onready var _roster_favorites_only: CheckBox = %RosterFavoritesOnly
@onready var _favorite_hero: CheckBox = %FavoriteHero
@onready var _hero_availability: Label = %HeroAvailability
@onready var _inventory_protection_filter: OptionButton = %InventoryProtectionFilter
@onready var _favorite_item: CheckBox = %FavoriteItem
@onready var _preset_dispatch_list: ItemList = %PresetDispatchList
@onready var _runs_per_team: SpinBox = %RunsPerTeam
@onready var _repeat_until_stopped: CheckBox = %RepeatUntilStopped
@onready var _dispatch_summary: RichTextLabel = %DispatchSummary
@onready var _dispatch_empty: Label = %DispatchEmpty
@onready var _dispatch_selected: Button = %DispatchSelected
@onready var _expedition_counts: Label = %ExpeditionCounts
@onready var _recovery_warning: Control = %RecoveryWarning
@onready var _order_cards: VBoxContainer = %OrderCards
@onready var _recent_returns: ItemList = %RecentReturns
@onready var _preset_selector: OptionButton = %PresetSelector
@onready var _preset_name: LineEdit = %PresetName
@onready var _preset_members: RichTextLabel = %PresetMembers
@onready var _recovery_team_option: OptionButton = %RecoveryTeamOption
@onready var _practice_preset: OptionButton = %PracticePreset
@onready var _practice_zone: OptionButton = %PracticeZone
@onready var _combine_teams: CheckBox = %CombineTeams
@onready var _combined_zone: OptionButton = %CombinedZone
@onready var _battle_settings: Control = %BattleSettings
@onready var _incident_cards: VBoxContainer = %IncidentCards
@onready var _supply_stock: Label = %SupplyStock
@onready var _supply_kind: OptionButton = %SupplyKind
@onready var _supply_quantity: SpinBox = %SupplyQuantity
@onready var _supply_reserve: SpinBox = %SupplyReserve
@onready var _supply_preview: Label = %SupplyPreview
@onready var _convert_quantity: SpinBox = %ConvertQuantity
@onready var _convert_reserve: SpinBox = %ConvertReserve
@onready var _enhance_target_level: SpinBox = %EnhanceTargetLevel
@onready var _enhance_preview: RichTextLabel = %EnhancePreview
@onready var _enhance_budgets: Array[SpinBox] = [%FBudget, %DBudget, %CBudget, %BBudget, %ABudget, %SBudget, %SSBudget, %SSSBudget]
@onready var _bulk_controls: VBoxContainer = %BulkControls
@onready var _bulk_quantity: SpinBox = %BulkQuantity
@onready var _confirm_body: RichTextLabel = %DialogBody

# Held between the press that asks and the press that confirms. The dialog is exclusive, so no
# second action can be queued while one is pending.
var _pending_action: Callable
var _pending_bulk_plan: Dictionary = {}
var _bulk_kind: String = ""
var _slot_filter: int = -1
var _roster_min_rank: int = -1
var _inventory_min_rank: int = -1
# -1 is an OptionButton index sentinel, so it cannot collide with Hero.NO_ARCHETYPE_DEF_ID (&"").
var _roster_archetype_filter_index: int = -1
var _roster_availability_filter_index: int = 0
var _inventory_protection_filter_index: int = 0
var _selected_hero_ids: Array[String] = []
var _selected_item_ids: Array[String] = []
var _editing_preset_id: String = ""
var _open_building: StringName = NO_BUILDING
## The building being moved while %Town.placing is set, or NO_BUILDING when placing builds.
var _moving: StringName = NO_BUILDING
## The walking hero's bonded partner ("" for none) and what it could say, as Lines facts ({} for
## none), from the last roster refresh. View state, not a tally: _refresh_partner rebuilds it from the
## Ledger on every roster change.
var _partner_id: String = ""
var _partner_facts: Dictionary = {}
## The hub's last look at GameSession.bond_index() (DECISIONS.md 2026-09-24 "Bonds stay derived"):
## the ledger key it saw (array identity and ledger_next_seq), and the tallies that could have been a
## living hero's bond then, pairs-shaped, for the next look's "grew close". View state, never saved.
var _bonds_ledger: Variant = null
var _bonds_seq: int = -1
var _bond_candidates: Dictionary = {}
## ig-7sn.16: the index's pairs, its version (GameSession.bond_changes) and the roster names at that
## look. A look that finds all three the same re-reads only the heroes the folds since touched.
var _bonds_pairs: Variant = null
var _bonds_version: int = 0
var _bonds_living: Dictionary = {}
## Dreams read since the ledger last changed, {hero_id: dream}; emptied on each ledger change.
var _dreams: Dictionary = {}
## History lines read since the ledger last changed, {hero_id: [roster names then, lines]}; emptied
## with _dreams (ig-7sn.9). The lines name heroes by the roster's names, so those are part of the key.
var _histories: Dictionary = {}
## _partner_signs' memo and the roster names it was read for; emptied with _dreams.
var _signs: Dictionary = {}
var _signs_living: Dictionary = {}
## How many dreams were read, for tests.
var dream_reads: int = 0
var _order_structure_key: String = ""
## How many times an order card and the hero detail were refreshed, for tests (ig-7sn.3).
var order_card_updates: int = 0
var detail_refreshes: int = 0
## The PANEL_REFRESHES keys skipped while their panel was hidden; _open runs them once it shows.
var _stale: Dictionary[StringName, bool] = {}
# True while the placed-building picker lists who to take out, false while it lists who to put in.
var _placed_picker_clears: bool = false
var _was_in_revolt: bool = false


func _enter_tree() -> void:
	UI_BUILDER.build($UI/Root, $UI/ConfirmDialog, $UI/EnhanceDialog)


func _ready() -> void:
	_connect_ui_signals()
	GameSession.roster_changed.connect(_refresh_roster)
	GameSession.roster_changed.connect(_refresh_essence)
	GameSession.roster_changed.connect(_refresh_stones)
	GameSession.roster_changed.connect(_refresh_turns)
	GameSession.roster_changed.connect(_refresh_lost_caches)
	GameSession.roster_changed.connect(_refresh_inventory)
	GameSession.roster_changed.connect(_refresh_parts)
	GameSession.roster_changed.connect(_refresh_buildings)
	GameSession.expeditions_changed.connect(_refresh_buildings)
	GameSession.roster_changed.connect(_refresh_equipped)
	# The selected hero's detail refreshes once per roster change, inside _refresh_director_ui (ig-7sn.3).
	GameSession.roster_changed.connect(_refresh_zone_unlocks)
	GameSession.roster_changed.connect(_refresh_director_ui)
	GameSession.roster_changed.connect(_refresh_body)
	GameSession.roster_changed.connect(_refresh_keeper)
	GameSession.expeditions_changed.connect(_refresh_keeper)
	GameSession.roster_changed.connect(_refresh_town)
	GameSession.roster_changed.connect(_refresh_walkers)
	# The live tick emits only expeditions_changed: the build stages and the placed panel move on it.
	GameSession.expeditions_changed.connect(_refresh_town)
	GameSession.roster_changed.connect(_refresh_starvation)
	GameSession.expeditions_changed.connect(_refresh_starvation)
	GameSession.expeditions_changed.connect(_on_expeditions_changed)
	GameSession.roster_changed.connect(_refresh_partner)
	# expeditions_changed fires on every 0.25 s pulse: it only re-checks whether the partner is away.
	GameSession.expeditions_changed.connect(_refresh_walkers)
	GameSession.expeditions_changed.connect(_show_partner)
	GameSession.battle_changed.connect(_on_battle_changed)
	GameSession.preview_forecast_ready.connect(_refresh_dispatch_summary)
	_populate_rank_filter(_roster_rank_filter)
	_populate_rank_filter(_inventory_rank_filter)
	_populate_archetype_filter()
	_populate_slot_filter()
	_populate_availability_filter()
	_populate_protection_filter()
	_refresh_roster()
	_refresh_essence()
	_refresh_stones()
	_refresh_turns()
	_refresh_lost_caches()
	_refresh_inventory()
	_refresh_parts()
	_refresh_buildings()
	_refresh_equipped()
	_refresh_supply_stock()
	_populate_convert_ranks()
	_populate_zones()
	%ConfirmSupply.disabled = true
	_refresh_zone_unlocks()
	_refresh_director_ui()
	_refresh_body()
	_refresh_town()
	_refresh_walkers()
	_refresh_partner()
	_open(NO_BUILDING)
	_status.text = "Send a team on an expedition; downed heroes can be stranded and need rescue."
	# ig-0og.3: the arena line first, and a town notice from while the hub was away joins it.
	var arena_shown: bool = _show_pending_arena_result()
	var notice: String = _town_notice_text(GameSession.take_town_notice())
	if not notice.is_empty():
		_status.text = _status.text + " " + notice if arena_shown else notice
	_refresh_starvation()


func _connect_ui_signals() -> void:
	%Town.building_selected.connect(_open)
	%Town.hero_selected.connect(_open_hero)
	%Town.hex_selected.connect(_on_hex_selected)
	(%Build as MenuButton).get_popup().index_pressed.connect(_on_build_picked)
	%PlacedAssign.pressed.connect(_on_placed_assign_pressed)
	%PlacedClear.pressed.connect(_on_placed_clear_pressed)
	%PlacedPicker.index_pressed.connect(_on_placed_picked)
	for building_id: StringName in BUILDING_PANELS:
		_building_button(building_id).pressed.connect(_open.bind(building_id))
	_close_panel.pressed.connect(_open.bind(NO_BUILDING))
	%MoveBuilding.pressed.connect(_on_move_pressed)
	_pause_menu.visibility_changed.connect(_on_pause_menu_visibility_changed)
	_roster_list.multi_selected.connect(_on_roster_list_multi_selected)
	_roster_list.gui_input.connect(_on_roster_list_gui_input)
	_roster_rank_filter.item_selected.connect(_on_roster_rank_filter_item_selected)
	_roster_exact_rank.toggled.connect(_on_roster_exact_rank_toggled)
	_roster_type_filter.item_selected.connect(_on_roster_type_filter_item_selected)
	%SelectAllRoster.pressed.connect(_on_select_all_roster_pressed)
	_inventory_rank_filter.item_selected.connect(_on_inventory_rank_filter_item_selected)
	_inventory_exact_rank.toggled.connect(_on_inventory_exact_rank_toggled)
	_inventory_slot_filter.item_selected.connect(_on_inventory_slot_filter_item_selected)
	_inventory_list.multi_selected.connect(_on_inventory_list_multi_selected)
	_favorite_item.toggled.connect(_on_favorite_item_toggled)
	%SelectAllInventory.pressed.connect(_on_select_all_inventory_pressed)
	%Equip.pressed.connect(_on_equip_pressed)
	%Salvage.pressed.connect(_on_salvage_pressed)
	%Enhance.pressed.connect(_on_enhance_pressed)
	%Convert.pressed.connect(_on_convert_pressed)
	%ConvertMax.pressed.connect(_on_convert_max_pressed)
	%Unequip.pressed.connect(_on_unequip_pressed)
	%UnequipAll.pressed.connect(_on_unequip_all_pressed)
	%Sacrifice.pressed.connect(_on_sacrifice_pressed)
	%RankUp.pressed.connect(_on_rank_up_pressed)
	%HeroSkills.pressed.connect(func() -> void: (%SkillPanel as SkillPanel).show_hero(_selected_hero()))
	%UpgradeCircle.pressed.connect(_on_upgrade_circle_pressed)
	%UpgradeForge.pressed.connect(_on_upgrade_forge_pressed)
	%UpgradeTrainingHall.pressed.connect(_on_upgrade_training_hall_pressed)
	%UpgradeSanctum.pressed.connect(_on_upgrade_sanctum_pressed)
	%UpgradeReliquary.pressed.connect(_on_upgrade_reliquary_pressed)
	%Summon.pressed.connect(_on_summon_pressed)
	%Recover.pressed.connect(_on_recover_pressed)
	%EnterArena.pressed.connect(_on_enter_arena_pressed)
	%ManageTeams.pressed.connect(_open.bind(&"TrainingHall"))
	%GoToHall.pressed.connect(_open.bind(&"SummoningCircle"))
	%ReviewLosses.pressed.connect(_open.bind(&"Reliquary"))
	%DispatchSelected.pressed.connect(_on_dispatch_selected_pressed)
	_preset_dispatch_list.multi_selected.connect(_on_dispatch_selection_changed)
	_combine_teams.toggled.connect(_on_combine_teams_toggled)
	for setting_name: String in ["AutoBattle", "AutoHeal", "AutoRevive", "ReserveLastRevival", "RetreatIfEmpty"]:
		var check: CheckBox = get_node("%%%s" % setting_name) as CheckBox
		check.toggled.connect(_on_battle_policy_changed)
	var spin_names: Array[String] = ["HealThreshold"]
	for kind: String in BattleState.SUPPLY_KINDS:
		spin_names.append_array([kind.to_pascal_case() + "Allocation", kind.to_pascal_case() + "Floor"])
	for setting_name: String in spin_names:
		var spin: SpinBox = get_node("%%%s" % setting_name) as SpinBox
		spin.value_changed.connect(_on_battle_policy_value_changed)
	var stance: OptionButton = %BattleStance
	stance.item_selected.connect(_on_battle_stance_changed)
	%BattleSettingsToggle.pressed.connect(_on_battle_settings_toggle_pressed)
	%SuggestedAllocations.pressed.connect(_on_suggested_allocations_pressed)
	%PreviewSupply.pressed.connect(_on_preview_supply_pressed)
	%ConfirmSupply.pressed.connect(_on_confirm_supply_pressed)
	_supply_kind.item_selected.connect(_on_supply_input_changed)
	_supply_quantity.value_changed.connect(_on_supply_quantity_changed)
	_supply_reserve.value_changed.connect(_on_supply_quantity_changed)
	_repeat_until_stopped.toggled.connect(_on_dispatch_options_changed)
	_runs_per_team.value_changed.connect(_on_runs_per_team_changed)
	_preset_selector.item_selected.connect(_on_preset_selector_selected)
	%SavePreset.pressed.connect(_on_save_preset_pressed)
	%SaveAndGo.pressed.connect(_on_save_and_go_pressed)
	%DeletePreset.pressed.connect(_on_delete_preset_pressed)
	_roster_availability_filter.item_selected.connect(_on_availability_filter_selected)
	_roster_favorites_only.toggled.connect(_on_favorites_only_toggled)
	_inventory_protection_filter.item_selected.connect(_on_protection_filter_selected)
	_favorite_hero.toggled.connect(_on_favorite_hero_toggled)
	%WalkAsHero.pressed.connect(_on_walk_as_hero_pressed)
	%StepOut.pressed.connect(_on_step_out_pressed)
	%AssignKeeper.pressed.connect(_on_assign_keeper_pressed)
	%UnassignKeeper.pressed.connect(_on_unassign_keeper_pressed)
	%KeeperPicker.index_pressed.connect(_on_keeper_picked)
	%StartRecoveryWindow.pressed.connect(_on_start_recovery_window_pressed)
	for index: int in BattleState.SUPPLY_KINDS.size():
		_supply_kind.add_item(BattleState.supply_name(BattleState.SUPPLY_KINDS[index]), index)
		_supply_kind.set_item_metadata(index, BattleState.SUPPLY_KINDS[index])
	for data: Array in [["Stay together", "stay_together"], ["Advance", "advance"], ["Defend", "defend"], ["Protect", "protect"]]:
		stance.add_item(str(data[0]))
		stance.set_item_metadata(stance.item_count - 1, str(data[1]))
	stance.select(0)
	%AutoBattle.button_pressed = true
	%AutoHeal.button_pressed = true
	%AutoRevive.button_pressed = true
	%HealThreshold.value = 35
	_populate_practice_zones()
	%UseAvailableParts.pressed.connect(_on_use_available_parts_pressed)
	_enhance_target_level.value_changed.connect(_on_enhance_preview_changed)
	for budget: SpinBox in _enhance_budgets:
		budget.value_changed.connect(_on_enhance_preview_changed)
	_enhance_dialog.confirmed.connect(_on_enhance_dialog_confirmed)
	_bulk_quantity.value_changed.connect(_on_bulk_quantity_changed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		# Esc stops placing or moving, then closes the open building; only an empty town opens the pause menu.
		if %Town.placing != &"" and not _pause_menu.visible:
			%Town.placing = &""
			_status.text = "Stopped moving." if _moving != NO_BUILDING else "Stopped building."
			_moving = NO_BUILDING
		elif _open_building != NO_BUILDING and not _pause_menu.visible:
			_open(NO_BUILDING)
		else:
			_pause_menu.visible = not _pause_menu.visible
		get_viewport().set_input_as_handled()


## TargetOption (Sanctum) and the practice options (Training Hall) only show beside the roster, so
## its gate covers them.
func _refresh_roster() -> void:
	if _skip_hidden(&"roster"):
		return
	_refresh_hero_list(_roster_list)
	_refresh_hero_option(_target_option)
	_refresh_practice_options()


## Re-select by identity after the clear, so a hero that left the roster drops out of the selection
## instead of the row under it taking its place.
func _refresh_hero_list(list: ItemList) -> void:
	var selected_ids: Array[String] = _selected_hero_ids.duplicate()
	var visible_ids: Array[String] = []
	for selected_index: int in list.get_selected_items():
		var selected_hero: Hero = list.get_item_metadata(selected_index) as Hero
		if selected_hero != null and not selected_ids.has(selected_hero.instance_id):
			selected_ids.append(selected_hero.instance_id)
	list.clear()
	var living: Dictionary = _roster_names()
	var signs: Dictionary = _partner_signs(living)
	for hero: Hero in GameSession.roster:
		if _roster_min_rank != -1 and (
			hero.rank != _roster_min_rank if _roster_exact_rank.button_pressed else hero.rank < _roster_min_rank
		):
			continue
		if _roster_archetype_filter_index != -1 and hero.def_id != StringName(Summon.ARCHETYPE_DEF_IDS[_roster_archetype_filter_index]):
			continue
		var busy: bool = GameSession.is_hero_busy(hero)
		var protected: bool = GameSession.is_hero_protected(hero)
		if _roster_availability_filter_index == 1 and (busy or protected):
			continue
		if _roster_availability_filter_index == 2 and not busy:
			continue
		if _roster_availability_filter_index == 3 and (not protected or busy):
			continue
		if _roster_favorites_only.button_pressed and not hero.favorite:
			continue
		var archetype_name: String = Summon.archetype_label_for(hero.def_id)
		var flags: PackedStringArray = []
		if hero.favorite:
			flags.append("★")
		var partner_sign: String = signs.get(hero.instance_id, "")
		if not partner_sign.is_empty():
			flags.append(partner_sign)
		if busy:
			flags.append("Away")
		elif GameSession.is_embodied(hero):
			flags.append("In town")
		elif hero.station != Hero.NO_STATION:
			flags.append("Keeps the %s" % str(hero.station).capitalize())
		elif protected:
			flags.append("Preset")
		var suffix: String = " · %s" % ", ".join(flags) if not flags.is_empty() else ""
		list.add_item("[%s]  %s — %s%s" % [hero.rank_label(BALANCE), hero.hero_name, archetype_name, suffix])
		var item_index: int = list.item_count - 1
		visible_ids.append(hero.instance_id)
		list.set_item_metadata(item_index, hero)
		if selected_ids.has(hero.instance_id):
			list.select(item_index, false)
	_selected_hero_ids.clear()
	for selected_id: String in selected_ids:
		if visible_ids.has(selected_id):
			_selected_hero_ids.append(selected_id)


func _refresh_hero_option(option: OptionButton) -> void:
	var selected_id: String = ""
	var selected_hero: Hero = option.get_selected_metadata() as Hero if option.selected >= 0 else null
	if selected_hero != null:
		selected_id = selected_hero.instance_id
	option.clear()
	for hero: Hero in GameSession.roster:
		var archetype_name: String = Summon.archetype_label_for(hero.def_id)
		option.add_item("[%s]  %s — %s" % [hero.rank_label(BALANCE), hero.hero_name, archetype_name])
		option.set_item_metadata(option.item_count - 1, hero)
	# Only TargetOption auto-selects index 0 on a cleared button. Re-selecting by identity after
	# the loop is what stops a sacrificed hero's target silently retargeting whoever took its place.
	var selected_index: int = -1
	for index: int in option.item_count:
		var hero: Hero = option.get_item_metadata(index) as Hero
		if hero != null and hero.instance_id == selected_id:
			selected_index = index
			break
	option.select(selected_index)


func _refresh_available_hero_option(option: OptionButton) -> void:
	var selected_id: String = ""
	if option.selected >= 0:
		var selected: Hero = option.get_selected_metadata() as Hero
		selected_id = selected.instance_id if selected != null else ""
	option.clear()
	for hero: Hero in GameSession.roster:
		if GameSession.is_hero_busy(hero):
			continue
		option.add_item("[%s] %s" % [hero.rank_label(BALANCE), hero.hero_name])
		option.set_item_metadata(option.item_count - 1, hero)
		if hero.instance_id == selected_id:
			option.select(option.item_count - 1)


func _refresh_essence() -> void:
	_essence.text = "Essence: %d" % GameSession.essence


func _refresh_stones() -> void:
	_stones.text = "Summon Stones: %d" % GameSession.stones
	_summon_button.text = "Summon hero · %d stones" % BALANCE.summon_pull_cost
	_summon_button.disabled = GameSession.stones < BALANCE.summon_pull_cost


func _refresh_turns() -> void:
	_turns.text = "Turn %d" % GameSession.turns


func _refresh_lost_caches() -> void:
	var selected_cache: LostCache = null
	var selected: PackedInt32Array = _lost_cache_list.get_selected_items()
	if selected.size() == 1:
		selected_cache = _lost_cache_list.get_item_metadata(selected[0]) as LostCache
	_lost_cache_list.clear()
	var reliquary_level: int = clampi(
		GameSession.building_levels[4],
		0,
		BALANCE.summoning_circle_level_cap,
	)
	# The live bonus from the level and the Tracking keeper; a running cache keeps its longest lifetime.
	var reliquary_bonus: float = GameSession.recovery_lifetime_seconds() - BALANCE.recovery_base_duration_seconds * BALANCE.battle_pace
	if GameSession.lost_caches.is_empty():
		_recovery_clock_status.text = "No lost gear is waiting."
	elif GameSession.recovery_clock_paused:
		var first_remaining: float = GameSession.cache_seconds_remaining(GameSession.lost_caches[0], GameSession.recovery_clock_seconds)
		_recovery_clock_status.text = "Clock paused for review · %s active time remains · Reliquary +%s" % [
			_format_duration(first_remaining), _format_duration(reliquary_bonus)
		]
	else:
		_recovery_clock_status.text = "Recovery clock active · Reliquary +%s per cache" % _format_duration(reliquary_bonus)
	for cache: LostCache in GameSession.lost_caches:
		var zone: ZoneDefinition = ZoneDefinition.definition_for(cache.zone_id)
		var zone_name: String = (
			zone.display_name
			if zone != null
			else "[Missing definition: %s]" % cache.zone_id
		)
		var seconds_remaining: float = GameSession.cache_seconds_remaining(cache, GameSession.recovery_clock_seconds)
		var time_text: String = "Paused until reviewed" if GameSession.recovery_clock_paused else "%s active remaining" % _format_duration(seconds_remaining)
		_lost_cache_list.add_item("%s — %s — %s" % [
			cache.hero_name,
			zone_name,
			time_text,
		])
		_lost_cache_list.set_item_tooltip(_lost_cache_list.item_count - 1, "%d lost item(s) · %s · Reliquary Lv %d and its keeper add %s." % [cache.items.size(), time_text, reliquary_level, _format_duration(reliquary_bonus)])
		var item_index: int = _lost_cache_list.item_count - 1
		_lost_cache_list.set_item_metadata(item_index, cache)
		if cache == selected_cache:
			_lost_cache_list.select(item_index)
	%StartRecoveryWindow.disabled = not GameSession.recovery_clock_paused or GameSession.lost_caches.is_empty()
	%StartRecoveryWindow.tooltip_text = "A new gear loss pauses the recovery clock for review." if %StartRecoveryWindow.disabled else "Review every loss before starting the active timer."


func _refresh_inventory() -> void:
	var selected_ids: Array[String] = _selected_item_ids.duplicate()
	var visible_ids: Array[String] = []
	for selected_index: int in _inventory_list.get_selected_items():
		var selected_item: Item = _inventory_list.get_item_metadata(selected_index) as Item
		if selected_item != null and not selected_ids.has(selected_item.instance_id):
			selected_ids.append(selected_item.instance_id)
	_inventory_list.clear()
	var items: Array[Item] = GameSession.inventory.duplicate()
	items.sort_custom(_sort_inventory_items)
	for item: Item in items:
		var definition: EquipmentDefinition = Item.definition_for(item.def_id)
		if _inventory_min_rank != -1 and (
			item.rank != _inventory_min_rank if _inventory_exact_rank.button_pressed else item.rank < _inventory_min_rank
		):
			continue
		if _slot_filter != -1 and (definition == null or definition.slot != _slot_filter):
			continue
		var protected: bool = GameSession.is_item_protected(item)
		if _inventory_protection_filter_index == 1 and protected:
			continue
		if _inventory_protection_filter_index == 2 and not item.favorite:
			continue
		var enhance_suffix: String = " +%d" % item.enhance_level if item.enhance_level != 0 else ""
		var favorite_prefix: String = "★ " if item.favorite else ""
		if definition == null:
			_inventory_list.add_item("%s%s [Missing definition: %s]%s" % [favorite_prefix, item.rank_label(BALANCE), item.def_id, enhance_suffix])
		else:
			_inventory_list.add_item("%s%s %s%s" % [favorite_prefix, item.rank_label(BALANCE), definition.display_name, enhance_suffix])
		var item_index: int = _inventory_list.item_count - 1
		visible_ids.append(item.instance_id)
		_inventory_list.set_item_metadata(item_index, item)
		_inventory_list.set_item_tooltip(item_index, _inventory_tooltip_text(item, definition))
		if selected_ids.has(item.instance_id):
			_inventory_list.select(item_index, false)
	_selected_item_ids.clear()
	for selected_id: String in selected_ids:
		if visible_ids.has(selected_id):
			_selected_item_ids.append(selected_id)
	_refresh_favorite_item_control()


func _refresh_favorite_item_control() -> void:
	var selected: PackedInt32Array = _inventory_list.get_selected_items()
	var item: Item = _inventory_list.get_item_metadata(selected[0]) as Item if selected.size() == 1 else null
	_favorite_item.disabled = item == null
	_favorite_item.set_pressed_no_signal(item.favorite if item != null else false)
	_favorite_item.tooltip_text = "Select exactly one inventory item." if item == null else "Favorite items are protected from salvage."


func _inventory_tooltip_text(item: Item, definition: EquipmentDefinition) -> String:
	var enhance_level: int = Item.clamped_enhance_level(item, BALANCE)
	var enhance_cap: int = GameSession.enhance_cap(BALANCE)
	var salvage_yield: int = GameSession.salvage_yield(item)
	if definition == null:
		return "Definition: Missing (%s)\nEnhance: +%d / %d\nSalvage: %d %s parts" % [
			item.def_id,
			enhance_level,
			enhance_cap,
			salvage_yield,
			item.rank_label(BALANCE),
		]
	var slot_name: String = (EquipmentDefinition.Slot.keys()[definition.slot] as String).capitalize()
	var stat_name: String = EquipmentDefinition.PrimaryStat.keys()[definition.primary_stat] as String
	var magnitude: float = Item.compute_stat_magnitude(item, definition, BALANCE) * 100.0
	return "Slot: %s\n%s: +%.1f%%\nEnhance: +%d / %d\nSalvage: %d %s parts" % [
		slot_name,
		stat_name,
		magnitude,
		enhance_level,
		enhance_cap,
		salvage_yield,
		item.rank_label(BALANCE),
	]


static func _sort_inventory_items(first: Item, second: Item) -> bool:
	if first.rank != second.rank:
		return first.rank > second.rank
	if first.enhance_level != second.enhance_level:
		return first.enhance_level > second.enhance_level
	# def_id, not display_name: Item.definition_for() push_errors on a miss, and a comparator runs
	# it O(n log n) times. All ten authored display names are the title-cased def_id, so the order
	# is identical without the lookup.
	return str(first.def_id) < str(second.def_id)


func _refresh_parts() -> void:
	var entries: PackedStringArray = []
	for rank_index: int in GameSession.parts.size():
		entries.append("%s: %d" % [BALANCE.rank_names[rank_index], GameSession.parts[rank_index]])
	_parts.text = "Parts  " + " | ".join(entries)


func _refresh_buildings() -> void:
	_circle_level.text = _building_level_text("Summoning Circle", 0)
	_forge_level.text = _building_level_text("Forge", 1)
	_training_hall_level.text = _building_level_text("Training Hall", 2)
	_sanctum_level.text = _building_level_text("Sanctum", 3)
	_reliquary_level.text = _building_level_text("Reliquary", 4)
	# The mutators hold both masterwork gates; these only say why (ig-wgj.12).
	_forge_level.tooltip_text = _masterwork_note()
	%Enhance.tooltip_text = _masterwork_note()
	%RankUp.tooltip_text = "" if GameSession.keeper_is_master(&"Sanctum") else "SS->SSS needs a born master priest working here."


## Why the enhance cap stops short of what this Forge level allows; "" when it does not.
func _masterwork_note() -> String:
	if GameSession.enhance_cap(BALANCE) >= Item.compute_enhance_cap(GameSession.building_levels[1], true, BALANCE):
		return ""
	return "Masterwork (+13 to +15) needs a born smith at skill 5 working here."


func _building_level_text(building_name: String, index: int) -> String:
	var preview: Dictionary = GameSession.preview_building_upgrade(index)
	var current_level: int = int(preview.get("current_level", 0))
	var next_level: int = int(preview.get("next_level", current_level))
	var part_rank: int = int(preview.get("part_rank", -1))
	var part_cost: int = int(preview.get("part_cost", 0))
	if next_level == current_level or part_rank < 0 or part_rank >= BALANCE.rank_names.size():
		return "%s — Lv %d · MAX" % [building_name, current_level]
	return "%s — Lv %d · Next %d %s parts · %d wood · %d stone" % [building_name, current_level, part_cost, BALANCE.rank_names[part_rank], int(preview["wood_cost"]), int(preview["stone_cost"])]


## Gated with the hero detail: it reads the roster's selection, which is stale while the roster hides.
func _refresh_equipped() -> void:
	if _skip_hidden(&"equipped"):
		return
	var selected_slot: int = -1
	var selected: PackedInt32Array = _equipped_list.get_selected_items()
	if selected.size() == 1:
		selected_slot = _equipped_list.get_item_metadata(selected[0]) as int
	_equipped_list.clear()
	var hero: Hero = _selected_hero()
	if hero == null:
		return
	for slot: int in EquipmentDefinition.Slot.size():
		var slot_name: String = (EquipmentDefinition.Slot.keys()[slot] as String).capitalize()
		var item: Item = hero.equipped.get(slot) as Item
		if item == null:
			_equipped_list.add_item("%s — (empty)" % slot_name)
			_equipped_list.set_item_metadata(_equipped_list.item_count - 1, slot)
			if slot == selected_slot:
				_equipped_list.select(_equipped_list.item_count - 1)
			continue
		var definition: EquipmentDefinition = Item.definition_for(item.def_id)
		var enhance_suffix: String = " +%d" % item.enhance_level if item.enhance_level != 0 else ""
		if definition == null:
			_equipped_list.add_item("%s %s [Missing definition: %s]%s" % [slot_name, item.rank_label(BALANCE), item.def_id, enhance_suffix])
		else:
			_equipped_list.add_item("%s %s %s%s" % [slot_name, item.rank_label(BALANCE), definition.display_name, enhance_suffix])
		_equipped_list.set_item_metadata(_equipped_list.item_count - 1, slot)
		if slot == selected_slot:
			_equipped_list.select(_equipped_list.item_count - 1)


func _refresh_hero_detail() -> void:
	detail_refreshes += 1
	var hero: Hero = _selected_hero()
	_hero_detail.text = "" if hero == null else "%s\n\n%sHistory:\n%s" % [_hero_detail_text(hero), _bond_text(hero), "\n".join(_history_lines(hero))]
	_hero_availability.text = "Select exactly one hero." if hero == null else _hero_state_text(hero)
	_favorite_hero.disabled = hero == null
	_favorite_hero.set_pressed_no_signal(hero.favorite if hero != null else false)
	%WalkAsHero.disabled = hero == null or GameSession.is_hero_busy(hero) or GameSession.is_embodied(hero)
	%HeroSkills.disabled = hero == null
	var skill_panel := %SkillPanel as SkillPanel
	if skill_panel.visible and (hero == null or hero.instance_id != skill_panel.hero_id):
		skill_panel.show_hero(hero)
	elif skill_panel.visible:
		skill_panel.refresh() # the same hero may have levelled; refresh keeps the error text
	var unavailable: bool = hero == null or GameSession.is_hero_busy(hero)
	%Unequip.disabled = unavailable
	%UnequipAll.disabled = unavailable
	if unavailable and hero != null:
		%Unequip.tooltip_text = "Unavailable while this hero is away."
		%UnequipAll.tooltip_text = "Unavailable while this hero is away."
	else:
		%Unequip.tooltip_text = ""
		%UnequipAll.tooltip_text = ""


func _hero_state_text(hero: Hero) -> String:
	if GameSession.is_hero_busy(hero):
		return "Away on expedition. Equipment and advancement are locked."
	if GameSession.is_embodied(hero):
		return "Your body in town. Gear and rank-up are open; expeditions and sacrifice are not."
	if hero.station != Hero.NO_STATION:
		return "Keeps the %s. Gear, rank-up and expeditions are open; sacrifice is not." % str(hero.station).capitalize()
	if GameSession.is_hero_protected(hero):
		return "Protected by favorite or team preset."
	return "Ready"


## The Ledger's reader (SYSTEMS.md § The Ledger): newest first, at most 10 lines.
## Read at most once per ledger change and roster names: the look at the index comes first, so a
## changed ledger has already emptied the memo. Over 10,000 records it is most of a detail refresh.
func _history_lines(hero: Hero) -> Array[String]:
	_bond_index()
	var names: Dictionary = _roster_names()
	var kept: Array = _histories.get(hero.instance_id, [])
	if kept.is_empty() or kept[0] != names:
		kept = [names, Ledger.history_lines(GameSession.ledger, hero.instance_id, names, BALANCE.rank_names, 10)]
		_histories[hero.instance_id] = kept
	return kept[1]


## The bond and dream lines above History (SYSTEMS.md § Bonds and dreams, slice 1), each block
## followed by a blank line; "" when the hero has neither. The bond comes from the kept index; the
## dream is still read for the selected hero only, on refresh, never per row.
func _bond_text(hero: Hero) -> String:
	var living: Dictionary = _roster_names()
	var names: Dictionary = Ledger.known_names(GameSession.ledger, living)
	var text: String = ""
	var bond: Dictionary = Bonds.bond_from(_bond_index(), hero.instance_id, living, BALANCE)
	if not bond.is_empty():
		text += "%s\n\n" % Bonds.bond_line(bond, names, GameSession.is_hero_busy(GameSession.hero_by_id(bond["partner"])))
	var dream: Array[String] = Bonds.dream_lines(_dream(hero.instance_id), hero.instance_id, names, BALANCE)
	if not dream.is_empty():
		text += "%s\n\n" % "\n".join(dream)
	return text


## The walking hero's bonded partner and greeting facts, from the kept index and the partner's
## dream memo on roster_changed only (every settle that writes a record also changes the roster);
## never per frame or per pulse.
func _refresh_partner() -> void:
	var old_partner: String = _partner_id
	_partner_id = ""
	_partner_facts = {}
	var walker: Hero = GameSession.hero_by_id(GameSession.embodied_hero_id)
	if walker != null:
		var living: Dictionary = _roster_names()
		var bond: Dictionary = Bonds.bond_from(_bond_index(), walker.instance_id, living, BALANCE)
		if not bond.is_empty():
			_partner_id = bond["partner"]
			_partner_facts = Lines.greeting_facts(bond, _dream(_partner_id), walker.instance_id, Ledger.known_names(GameSession.ledger, living))
	_show_partner()
	# The walkers ran first on this roster_changed, against the old partner, who may have been cut by
	# the wanderer cap.
	if _partner_id != old_partner:
		_refresh_walkers()


## Every hero in town walks (ig-6m2.6): on the roster, not away, and not the body. In pick order, so
## the wanderer cap keeps the same heroes each visit: keepers and workers, the partner, then
## favorites, higher rank, lower instance_id. Runs on the 0.25 s pulse too: TownView keeps unchanged
## figures, so a quiet pulse changes nothing. Each hero at home (the body too) gets its partner
## sign from the kept index: a pulse with no ledger change rebuilds nothing, and asking it walks
## each hero's own pairs, at most one per other hero on the roster.
func _refresh_walkers() -> void:
	var living: Dictionary = _roster_names()
	var heroes: Array[Hero] = []
	var signs: Dictionary = {}
	var partner_signs: Dictionary = _partner_signs(living)
	for hero: Hero in GameSession.roster:
		if GameSession.is_hero_busy(hero):
			continue
		if not GameSession.is_embodied(hero):
			heroes.append(hero)
		var partner_sign: String = partner_signs.get(hero.instance_id, "")
		if not partner_sign.is_empty():
			signs[hero.instance_id] = partner_sign
	heroes.sort_custom(_walks_before)
	%Town.show_walkers(heroes, signs)


## Every living hero's _partner_sign, {hero_id: sign}, read at most once per ledger change and roster
## names (ig-7sn.9): the roster rows and the walkers each ask for every hero on every roster change,
## and the picks over 100 heroes' tallies were most of both. The look at the index comes first, so a
## changed ledger has already dropped the heroes whose tallies changed (every hero after a full look).
func _partner_signs(living: Dictionary) -> Dictionary:
	_bond_index()
	if _signs_living != living:
		_signs = {}
		_signs_living = living
	if _signs.size() != living.size():
		# Only the heroes the look dropped (ig-7sn.16), or every hero after a full look.
		for hero_id: String in living:
			if not _signs.has(hero_id):
				_signs[hero_id] = _partner_sign(hero_id, living)
	return _signs


## "♥ Mara" for a hero bonded to Mara (a key of living), or "" for none. Stays while Mara is away.
func _partner_sign(hero_id: String, living: Dictionary) -> String:
	var partner: String = str(Bonds.bond_from(_bond_index(), hero_id, living, BALANCE).get("partner", ""))
	return "" if partner.is_empty() else PARTNER_SIGN % living[partner]


## The hub's one way to the bond index (GameSession keeps it). A look that finds the ledger key
## changed since the last one says the new bonds and forgets the dreams and histories read. When the
## index and the roster names are the ones the last look saw, it reads only the heroes whose tallies
## a fold touched since (ig-7sn.16; a routine win touches none). A load, a rebuilt index or a roster
## change reads every hero.
func _bond_index() -> Dictionary:
	var pairs: Dictionary = GameSession.bond_index()
	var ledger: Array[Dictionary] = GameSession.ledger
	if is_same(ledger, _bonds_ledger) and GameSession.ledger_next_seq == _bonds_seq:
		return pairs
	var living: Dictionary = _roster_names()
	var changes: Dictionary = GameSession.bond_changes()
	if is_same(ledger, _bonds_ledger) and is_same(pairs, _bonds_pairs) and living == _bonds_living:
		var touched: Dictionary = {}
		for id: String in changes["touched"]:
			if int(changes["touched"][id]) > _bonds_version and living.has(id):
				touched[id] = true
		_say_new_bonds(_bond_candidates, pairs, touched)
		for id: String in touched:
			_bond_candidates[id] = _candidates_of(pairs, id, living)
			_signs.erase(id)
	else:
		# The first look and a load (a new array) say nothing: those bonds formed before this session saw them.
		if is_same(ledger, _bonds_ledger):
			_say_new_bonds(_bond_candidates, pairs, living)
		_bond_candidates = _living_candidates(pairs, living)
		_signs = {}
	_bonds_ledger = ledger
	_bonds_seq = GameSession.ledger_next_seq
	_bonds_pairs = pairs
	_bonds_version = int(changes["version"])
	_bonds_living = living
	_dreams.clear()
	_histories.clear()
	return pairs


## Each living hero's _candidates_of, pairs-shaped: all the last look's bond_from could pick from.
func _living_candidates(pairs: Dictionary, living: Dictionary) -> Dictionary:
	var kept: Dictionary = {}
	for id: String in living:
		kept[id] = _candidates_of(pairs, id, living)
	return kept


## hero_id's tallies at or over the threshold toward a living hero. The fold replaces a tally rather
## than changing it, so they stay as they were.
func _candidates_of(pairs: Dictionary, hero_id: String, living: Dictionary) -> Dictionary:
	var mine: Dictionary = {}
	for tally: Dictionary in (pairs.get(hero_id, {}) as Dictionary).values():
		if living.has(tally["partner"]) and tally["points"] >= BALANCE.bond_threshold:
			mine[tally["partner"]] = tally
	return mine


## hero_id's dream, read at most once per ledger change: the look at the index comes first, so a
## changed ledger has already emptied the memo.
func _dream(hero_id: String) -> Dictionary:
	_bond_index()
	if not _dreams.has(hero_id):
		_dreams[hero_id] = Bonds.dream(GameSession.ledger, hero_id)
		dream_reads += 1
	return _dreams[hero_id]


## "Mara and Dunn grew close." for a new mutual pair, "Dunn grew close to Mara." for a one-way one,
## on the status line; several at once say the first and " (+N more)". A bond that ends says nothing.
## Only the heroes in ids (living ones) can have a new partner: the rest kept their tallies since the
## last look (ig-7sn.16), so they are asked only as someone's partner.
func _say_new_bonds(before: Dictionary, after: Dictionary, ids: Dictionary) -> void:
	if ids.is_empty():
		return
	var living: Dictionary = _roster_names()
	var partners: Dictionary = {}
	for id: String in ids:
		partners[id] = str(Bonds.bond_from(after, id, living, BALANCE).get("partner", ""))
	var news: PackedStringArray = []
	var said: Dictionary = {}
	for id: String in living:
		if not ids.has(id):
			continue
		var partner: String = partners[id]
		if partner.is_empty() or said.has(id) or partner == str(Bonds.bond_from(before, id, living, BALANCE).get("partner", "")):
			continue
		if not partners.has(partner):
			partners[partner] = str(Bonds.bond_from(after, partner, living, BALANCE).get("partner", ""))
		if partners[partner] == id:
			news.append("%s and %s grew close." % [living[id], living[partner]])
			said[partner] = true
		else:
			news.append("%s grew close to %s." % [living[id], living[partner]])
	if not news.is_empty():
		_status.text = news[0] + ("" if news.size() == 1 else " (+%d more)" % (news.size() - 1))


func _walks_before(a: Hero, b: Hero) -> bool:
	var a_works: bool = a.station != Hero.NO_STATION
	if a_works != (b.station != Hero.NO_STATION):
		return a_works
	if (a.instance_id == _partner_id) != (b.instance_id == _partner_id):
		return a.instance_id == _partner_id
	if a.favorite != b.favorite:
		return a.favorite
	if a.rank != b.rank:
		return a.rank > b.rank
	return a.instance_id < b.instance_id


## The partner stands in town while not away. No Ledger read; TownView never reads GameSession.
func _show_partner() -> void:
	var partner: Hero = GameSession.hero_by_id(_partner_id)
	if partner != null and GameSession.is_hero_busy(partner):
		partner = null
	%Town.show_partner(partner, _partner_facts)


## Roster hero id -> display name.
func _roster_names() -> Dictionary:
	var names: Dictionary = {}
	for member: Hero in GameSession.roster:
		names[member.instance_id] = member.hero_name
	return names


## The roster tooltip, and the head of the selected-hero detail (which adds the History below it).
func _hero_detail_text(hero: Hero) -> String:
	return "%s\n%s" % [_hero_stats_text(hero), _profession_text(hero)]


func _hero_stats_text(hero: Hero) -> String:
	if hero.def_id == Hero.NO_ARCHETYPE_DEF_ID:
		return "Rank: %s\nArchetype: No archetype" % hero.rank_label(BALANCE)
	var definition: HeroDefinition = Hero.definition_for(hero.def_id)
	if definition == null:
		return "Rank: %s\nArchetype: Missing archetype (%s)" % [hero.rank_label(BALANCE), hero.def_id]
	var level: int = Hero.level_for(hero, BALANCE)
	var stats: Dictionary[StringName, float] = Hero.compute_final_stats(
		hero,
		definition,
		BALANCE,
		level,
	)
	var level_cap: int = BALANCE.level_caps[clampi(hero.rank, 0, BALANCE.level_caps.size() - 1)]
	var level_text: String = "Lv %d (max)" % level if level >= level_cap else "Level: %d (%d/%d XP)" % [level, hero.xp, Hero.xp_to_next_level(level, BALANCE)]
	var traits: PackedStringArray = []
	for trait_definition: TraitDefinition in Hero.active_resonance_traits(hero, definition, BALANCE):
		traits.append(trait_definition.display_name)
	for trait_definition: TraitDefinition in Hero.active_taught_traits(hero, definition):
		traits.append("%s (taught)" % trait_definition.display_name)
	# Keyed off the pool being empty, not off resonance: a definition with no authored pool would
	# otherwise print "Traits: " with nothing after it.
	var trait_text: String = "none" if traits.is_empty() else ", ".join(traits)
	return "Rank: %s\n%s\nHP: %d\nATK: %d\nDEF: %d\nSPD: %d\nCRIT_RATE: %.1f%%\nCRIT_DMG: %.1f%%\nResonance: %d\nTraits: %s" % [
		hero.rank_label(BALANCE),
		level_text,
		roundi(stats[Hero.STAT_HP]),
		roundi(stats[Hero.STAT_ATK]),
		roundi(stats[Hero.STAT_DEF]),
		roundi(stats[Hero.STAT_SPD]),
		stats[Hero.STAT_CRIT_RATE] * 100.0,
		stats[Hero.STAT_CRIT_DMG] * 100.0,
		hero.resonance,
		trait_text,
	]


## Passions, every profession skill and the station (GAME_SPEC.md § Heroes staff the buildings).
func _profession_text(hero: Hero) -> String:
	var skills: PackedStringArray = []
	for profession: StringName in Hero.PROFESSIONS:
		skills.append("%s %d" % [str(profession).capitalize(), Hero.profession_skill(hero, profession, BALANCE)])
	var station: String = "none" if hero.station == Hero.NO_STATION else str(hero.station).capitalize()
	var home: String = "none" if hero.home == Hero.NO_HOME else str(hero.home).capitalize()
	return "Passions: %s\nSkills: %s\nStation: %s\nHome: %s" % [_passions_text(hero), ", ".join(skills), station, home]


func _passions_text(hero: Hero) -> String:
	return ", ".join(PackedStringArray(hero.passions.map(func(profession: StringName) -> String: return str(profession).capitalize())))


## Null while the roster waits on a skipped refresh (ig-7sn.9): its rows may hold a hero who has died.
func _selected_hero() -> Hero:
	if _stale.has(&"roster"):
		return null
	var selected: PackedInt32Array = _roster_list.get_selected_items()
	if selected.size() != 1:
		return null
	var hero: Hero = _roster_list.get_item_metadata(selected[0]) as Hero
	assert(hero != null)
	return hero


func _populate_zones() -> void:
	_zone_option.clear()
	_combined_zone.clear()
	_practice_zone.clear()
	for zone: ZoneDefinition in EXPEDITION_ZONES:
		_zone_option.add_item(zone.display_name)
		_zone_option.set_item_metadata(_zone_option.item_count - 1, zone)
		_combined_zone.add_item(zone.display_name)
		_combined_zone.set_item_metadata(_combined_zone.item_count - 1, zone)
		_practice_zone.add_item(zone.display_name)
		_practice_zone.set_item_metadata(_practice_zone.item_count - 1, zone)
	if _combined_zone.item_count > 0:
		_combined_zone.select(0)
		_practice_zone.select(0)
	_combined_zone.visible = false


func _populate_practice_zones() -> void:
	# The standard unlocked-zone list is populated by _populate_zones.
	_refresh_practice_options()


func _refresh_practice_options() -> void:
	_practice_preset.clear()
	for preset: Dictionary in GameSession.team_presets:
		if _preset_status(preset) != "Ready":
			continue
		_practice_preset.add_item(str(preset.get("name", "Unnamed team")))
		_practice_preset.set_item_metadata(_practice_preset.item_count - 1, preset)
	%EnterArena.disabled = _practice_preset.item_count == 0


func _populate_convert_ranks() -> void:
	_convert_rank_option.clear()
	for rank_index: int in GameSession.parts.size() - 1:
		_convert_rank_option.add_item("%s -> %s" % [BALANCE.rank_names[rank_index], BALANCE.rank_names[rank_index + 1]])
		_convert_rank_option.set_item_metadata(_convert_rank_option.item_count - 1, rank_index)


func _populate_rank_filter(option: OptionButton) -> void:
	option.clear()
	option.add_item("Any")
	option.set_item_metadata(0, -1)
	for rank_index: int in BALANCE.rank_names.size():
		option.add_item(BALANCE.rank_names[rank_index])
		option.set_item_metadata(option.item_count - 1, rank_index)


func _populate_archetype_filter() -> void:
	_roster_type_filter.clear()
	_roster_type_filter.add_item("Any type")
	_roster_type_filter.set_item_metadata(0, -1)
	for archetype_index: int in Summon.ARCHETYPE_DEF_IDS.size():
		var def_id: StringName = StringName(Summon.ARCHETYPE_DEF_IDS[archetype_index])
		_roster_type_filter.add_item(Summon.archetype_label_for(def_id))
		_roster_type_filter.set_item_metadata(_roster_type_filter.item_count - 1, archetype_index)


func _populate_slot_filter() -> void:
	_inventory_slot_filter.clear()
	_inventory_slot_filter.add_item("All slots")
	_inventory_slot_filter.set_item_metadata(0, -1)
	for slot: int in EquipmentDefinition.Slot.size():
		_inventory_slot_filter.add_item((EquipmentDefinition.Slot.keys()[slot] as String).capitalize())
		_inventory_slot_filter.set_item_metadata(_inventory_slot_filter.item_count - 1, slot)


func _populate_availability_filter() -> void:
	_roster_availability_filter.clear()
	for label: String in ["Any availability", "Ready", "Away", "Protected"]:
		_roster_availability_filter.add_item(label)


func _populate_protection_filter() -> void:
	_inventory_protection_filter.clear()
	for label: String in ["All items", "Unprotected", "Favorites"]:
		_inventory_protection_filter.add_item(label)


## Opens one building's panel, or none (NO_BUILDING) so the town shows.
func _open(building_id: StringName) -> void:
	var closing: StringName = _open_building
	%Town.placing = &""
	_moving = NO_BUILDING
	_open_building = building_id if BUILDING_PANELS.has(building_id) or _is_placed(building_id) or building_id == HERO_VIEW else NO_BUILDING
	var shown: Array = BUILDING_PANELS.get(_open_building, [PLACED_PANEL] if _is_placed(_open_building) else HERO_PANELS if _open_building == HERO_VIEW else [])
	for panels: Array in BUILDING_PANELS.values():
		for panel_name: StringName in panels:
			(get_node("%%%s" % panel_name) as Control).visible = shown.has(panel_name)
	(get_node("%%%s" % PLACED_PANEL) as Control).visible = shown.has(PLACED_PANEL)
	(%SkillPanel as SkillPanel).hide()
	for other: StringName in BUILDING_PANELS:
		_building_button(other).theme_type_variation = &"ActiveNavButton" if other == _open_building else &""
	_close_panel.visible = _open_building != NO_BUILDING
	%MoveBuilding.visible = _open_building != NO_BUILDING and _open_building != HERO_VIEW
	# An open building owns the whole screen: a click in a gap between its panels must not pick
	# the building behind it. Children still get their clicks first.
	($UI/Root as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE if _open_building == NO_BUILDING else Control.MOUSE_FILTER_STOP
	# Focus stays on the building list, so every panel is reachable without a mouse.
	var focus: StringName = _open_building if _open_building != NO_BUILDING else closing
	if BUILDING_PANELS.has(focus):
		_building_button(focus).grab_focus()
	_sync_town_walk()
	_refresh_keeper()
	_refresh_placed_panel()
	_refresh_stale()
	# %SupplyStock sits outside ExpeditionsView, whose gated refresh also writes it (ig-7sn.9).
	if _open_building == &"Apothecary":
		_refresh_supply_stock()
	if _open_building == &"TrainingHall" and _editing_preset_id.is_empty() and _preset_name.text.strip_edges().is_empty():
		_preset_name.text = _next_team_name()
	if _open_building == &"Reliquary":
		_refresh_lost_caches()


## True while every panel the refresh writes is hidden, and records it for _open (ig-7sn.9). It reads
## each panel's own visible flag, which only _open sets, so a skipped refresh always meets the _open
## that runs it.
func _skip_hidden(refresh: StringName) -> bool:
	for panel_name: StringName in PANEL_REFRESHES[refresh]:
		if (get_node("%%%s" % panel_name) as Control).visible:
			return false
	_stale[refresh] = true
	return true


## Runs the skipped refreshes whose panel now shows, in PANEL_REFRESHES order: the roster first, the
## hero detail last. The load-blocked lockout goes back on after them, as in _refresh_director_ui.
func _refresh_stale() -> void:
	var ran: bool = false
	for refresh: StringName in PANEL_REFRESHES:
		if not _stale.has(refresh):
			continue
		_stale.erase(refresh)
		if _skip_hidden(refresh):
			continue
		ran = true
		match refresh:
			&"roster":
				_refresh_roster()
			&"preset_lists":
				_refresh_preset_lists()
			&"preset_editor":
				_refresh_preset_editor()
			&"practice":
				_refresh_practice_options()
			&"recovery":
				_refresh_recovery_team_options()
			&"expeditions":
				_refresh_expeditions(true)
			&"equipped":
				_refresh_equipped()
			&"hero_detail":
				_refresh_hero_detail()
	if ran and SaveService.load_blocked:
		_disable_mutating_controls()


## A click on a hero in town: the roster with only that hero selected, and its detail. A roster
## filter that hides the hero is cleared, so the click always lands on it.
func _open_hero(hero_id: String) -> void:
	if GameSession.hero_by_id(hero_id) == null:
		return
	_open(HERO_VIEW)
	_roster_list.deselect_all()
	_selected_hero_ids.assign([hero_id])
	_refresh_roster()
	if _selected_hero() == null:
		_roster_min_rank = -1
		_roster_rank_filter.select(0)
		_roster_archetype_filter_index = -1
		_roster_type_filter.select(0)
		_roster_availability_filter_index = 0
		_roster_availability_filter.select(0)
		_roster_favorites_only.set_pressed_no_signal(false)
		_selected_hero_ids.assign([hero_id])
		_refresh_roster()
	_on_roster_list_multi_selected(-1, true)


## The body walks only in the bare town: never behind an open building or the pause menu.
func _sync_town_walk() -> void:
	%Town.input_enabled = _open_building == NO_BUILDING and not _pause_menu.visible


## The town follows GameSession's body: its hero walks, or the overview camera shows.
func _refresh_body() -> void:
	var body: Hero = GameSession.hero_by_id(GameSession.embodied_hero_id)
	%Town.embody(body)
	%StepOut.visible = body != null
	%Hint.text = "WASD · Walk   Wheel · Zoom   1–7 · Buildings   Esc · Close / Pause" if body != null else "1–7 · Buildings   Esc · Close / Pause"


func _is_placed(building_id: StringName) -> bool:
	return TownRules.type_of(building_id) != &"" and not GameSession.town_building(building_id).is_empty()


func _refresh_town() -> void:
	%Town.show_buildings(GameSession.town_buildings, GameSession.building_levels)
	var menu: PopupMenu = (%Build as MenuButton).get_popup()
	for index: int in menu.item_count:
		var type: StringName = menu.get_item_metadata(index)
		menu.set_item_text(index, "%s · %d wood" % [type, TownRules.wood_cost(type, GameSession.town_buildings, BALANCE)])
	_refresh_wood()
	_refresh_placed_panel()


func _refresh_wood() -> void:
	var resources: Dictionary = GameSession.town_resources
	_wood.text = "Wood: %d   Stone: %d   Food: %d" % [floori(float(resources["wood"])), floori(float(resources["stone"])), floori(float(resources["food"]))]
	# ig-0og.2: beds on the line, and a finished House's empty bed, so a forgotten one is on screen.
	var housed: int = GameSession.roster.size() - GameSession.homeless_heroes().size()
	_wood.text += "   Beds: %d/%d" % [housed, GameSession.roster.size()]
	var finished: Dictionary[StringName, bool] = {}
	for building: Dictionary in GameSession.town_buildings:
		# "build_remaining" is the going-up mark (GameSession._is_building); still_building would re-find it.
		if str(building["type"]) == String(TownRules.HOUSE) and not building.has("build_remaining"):
			finished[StringName(str(building["id"]))] = true
	var empty_beds: int = finished.size() * BALANCE.house_capacity
	for hero: Hero in GameSession.roster:
		empty_beds -= 1 if finished.has(hero.home) else 0
	if empty_beds > 0:
		_wood.text += ", %d free" % empty_beds


## The starvation ladder (ig-6m2.5.2), and the town notice once: "<name> starved." per death, and the
## riot's fires (ig-0og.3).
func _refresh_starvation() -> void:
	var notice: String = _town_notice_text(GameSession.take_town_notice())
	if not notice.is_empty():
		_status.text = notice
	var eaters: Array[Hero] = GameSession.food_eaters()
	var clock: float = GameSession.town_starving_seconds
	var food: float = GameSession.town_resources["food"]
	# ig-0og.1: only a hero at home can starve, so the warning names one of them.
	var victim: Hero = GameSession.hero_by_id(TownRules.starvation_victim(GameSession.starvation_candidates()))
	var text: String = ""
	if clock > 0.0 and victim != null:
		var when: String = _format_duration(TownRules.starve_due_seconds(clock, BALANCE) - clock)
		if GameSession.is_starvation_stopped():
			text = "Last warning: %s starves in %s unless the town is fed. The clock waits for you." % [victim.hero_name, when]
		else:
			text = "Starving: work runs at %d%% speed. %s starves in %s unless the town is fed." % [roundi(BALANCE.starving_work_multiplier * 100.0), victim.hero_name, when]
	elif not eaters.is_empty() and food < TownRules.food_low_line(eaters.size(), BALANCE):
		text = "Food low: %d left, and the town eats %.1f a minute." % [floori(food), eaters.size() * BALANCE.food_per_hero_minute]
	var mood: String = _mood_line()
	if not mood.is_empty():
		text = mood if text.is_empty() else text + "\n" + mood
	%StarveText.text = text
	%StarveWarning.visible = not text.is_empty()
	# ig-0og.2: the last warning is a dialog the player must close; any close is the ack. ig-0og.1:
	# with nobody home there is no one to name, so it waits. One exclusive child per window: it also
	# waits while another dialog is open, and pops at the first refresh after that one closes.
	if GameSession.is_starvation_stopped() and victim != null and not _starve_dialog.visible and not _confirm_dialog.visible and not _enhance_dialog.visible:
		_starve_dialog.dialog_text = "%s starves in %s unless the town is fed. The clock waits until you close this." % [victim.hero_name, _format_duration(TownRules.starve_due_seconds(clock, BALANCE) - clock)]
		_starve_dialog.popup_centered(Vector2i(560, 0))


## ig-0og.3: a take_town_notice() as one line, deaths first; "" when nothing happened. The fires since the
## last take are one total, rounded down.
static func _town_notice_text(notice: Dictionary) -> String:
	var lines: Array[String] = []
	for hero_name: Variant in notice.get("starved", []):
		lines.append("%s starved." % hero_name)
	if int(notice.get("fires", 0)) > 0:
		var wood: int = floori(float(notice["wood"]))
		var stone: int = floori(float(notice["stone"]))
		if wood == 0 and stone == 0:
			lines.append("Rioters found nothing spare to burn.")
		else:
			lines.append("Rioters burned %d wood and %d stone." % [wood, stone])
	return " ".join(lines)


## ig-0og.1: the town mood's line under the food line, while the mood is under 100 or more than the
## grace are homeless; "" otherwise.
func _mood_line() -> String:
	var homeless: int = GameSession.homeless_heroes().size()
	var mood: float = GameSession.town_mood
	var grace: int = BALANCE.town_mood_homeless_grace
	if GameSession.is_in_revolt():
		# ig-0og.3: before the riot, when it comes; in it, when the next fire is.
		var clock: float = GameSession.town_revolt_seconds
		var next_fire: String = _format_duration(TownRules.riot_seconds_to_next_fire(clock, BALANCE))
		if clock < BALANCE.town_riot_after_minutes * 60.0:
			return "Revolt: no order or repeat goes out until at most %d heroes are homeless. Riot in %s." % [grace, next_fire]
		return "Riot: a tenth of the spare wood and the stone burns every %d minutes (next in %s). No order goes out until at most %d heroes are homeless." % [roundi(BALANCE.town_riot_burn_minutes), next_fire, grace]
	if homeless > grace:
		var per_minute: float = minf((homeless - grace) * BALANCE.town_mood_fall_per_homeless_minute, BALANCE.town_mood_fall_max_per_minute)
		return "%d heroes have no bed. Town mood %d: revolt in about %s." % [homeless, ceili(mood), _format_duration(mood / per_minute * 60.0)]
	if mood < 100.0:
		return "Town mood %d, recovering." % floori(mood)
	return ""


func _on_starve_ack_pressed() -> void:
	if not GameSession.acknowledge_starvation() and not GameSession.last_action_error.is_empty():
		_status.text = GameSession.last_action_error
	_refresh_starvation()


## Placing starts from the bare town; the next hex click places or says why not.
func _on_build_picked(index: int) -> void:
	var type: StringName = (%Build as MenuButton).get_popup().get_item_metadata(index)
	_open(NO_BUILDING)
	%Town.placing = type
	_status.text = "Click a free hex for the %s (%d wood). Esc cancels." % [type, TownRules.wood_cost(type, GameSession.town_buildings, BALANCE)]


## Moving starts from the open building's Move button; the next hex click moves it or says why not.
func _on_move_pressed() -> void:
	var id: StringName = _open_building
	_open(NO_BUILDING)
	_moving = id
	%Town.placing = StringName(GameSession.town_building(id).get("type", String(id)))
	_status.text = "Click a free hex for the %s. Esc cancels." % String(id).capitalize()


func _on_hex_selected(hex: Vector2i) -> void:
	if _moving != NO_BUILDING:
		if GameSession.move_building(_moving, hex):
			%Town.placing = &""
			_status.text = "Moved the %s." % String(_moving).capitalize()
			_moving = NO_BUILDING
		else:
			_status.text = "%s Esc cancels." % GameSession.last_action_error
		return
	var type: StringName = %Town.placing
	var plan: Dictionary = GameSession.preview_place_building(type, hex)
	if GameSession.place_building(type, hex):
		%Town.placing = &""
		_status.text = "Built %s for %d wood." % [str(plan["id"]).capitalize(), int(plan["cost"])]
		# ig-0og.2: after a House the tool stays armed while every House placed (finished or going up,
		# an empty one counts as a bed) is fewer beds than heroes, and wood covers the next one.
		var next_cost: int = TownRules.wood_cost(TownRules.HOUSE, GameSession.town_buildings, BALANCE)
		var houses: int = GameSession.town_buildings.filter(func(building: Dictionary) -> bool: return str(building["type"]) == String(TownRules.HOUSE)).size()
		if type == TownRules.HOUSE and houses * BALANCE.house_capacity < GameSession.roster.size() and float(GameSession.town_resources["wood"]) >= next_cost:
			%Town.placing = type
			_status.text += " Click a free hex for the next House (%d wood). Esc stops." % next_cost
	else:
		_status.text = "%s Esc cancels." % GameSession.last_action_error


## The open House's resident or workplace's workers, "Away" for one who is out, and what it makes a minute.
func _refresh_placed_panel() -> void:
	if not _is_placed(_open_building):
		return
	var type: StringName = TownRules.type_of(_open_building)
	var house: bool = type == TownRules.HOUSE
	var people: Array[Hero] = _placed_people()
	var names: PackedStringArray = []
	var work: float = 0.0
	for hero: Hero in people:
		var away: bool = GameSession.is_hero_busy(hero)
		var label: String = hero.hero_name
		if not house:
			var profession: StringName = TownRules.JOB_PROFESSIONS[type]
			label += " (%s %d%s)" % [str(profession).capitalize(), Hero.profession_skill(hero, profession, BALANCE), ", passion" if profession in hero.passions else ""]
			work += 0.0 if away else TownRules.worker_work(hero, type, BALANCE)
		names.append("%s · Away" % label if away else label)
	work *= TownRules.work_multiplier(GameSession.town_starving_seconds, BALANCE)  # What the tick pays: starving halves it.
	var who: String = "none" if names.is_empty() else ", ".join(names)
	%PlacedTitle.text = str(_open_building).capitalize().to_upper()
	if house:
		%PlacedInfo.text = "Resident %d/%d: %s" % [people.size(), BALANCE.house_capacity, who]
	else:
		var made: String = "%.1f wood" % TownRules.wood_made(work, 60.0, BALANCE)
		match type:
			TownRules.MINE:
				made = "%.1f stone" % TownRules.stone_made(work, 60.0, BALANCE)
			TownRules.FARM:
				made = "%.1f food" % TownRules.food_made(work, 60.0, BALANCE)
		%PlacedInfo.text = "Workers %d/%d: %s\nMakes %s a minute" % [people.size(), TownRules.worker_slots(type, BALANCE), who, made]
	var building: Dictionary = GameSession.town_building(_open_building)
	if building.has("build_remaining"):
		%PlacedInfo.text = "Under construction: %s left\n%s" % [_format_duration(float(building["build_remaining"])), %PlacedInfo.text]
	%PlacedAssign.text = "Assign resident" if house else "Assign worker"
	%PlacedClear.text = "Move out" if house else "Unassign"
	%PlacedAssign.disabled = SaveService.load_blocked or building.has("build_remaining")
	%PlacedClear.disabled = people.is_empty() or SaveService.load_blocked


func _placed_people() -> Array[Hero]:
	if TownRules.type_of(_open_building) == TownRules.HOUSE:
		return GameSession.residents_of(_open_building)
	return GameSession.workers_at(_open_building)


## The shared roster picker: every hero, with where it lives and works. Rows hold ids (a failed save
## rebuilds the roster while the popup is open). A workplace's picker shows each hero's skill in its job and
## lists the passion heroes first, each group in roster order; a House's is as it was.
func _on_placed_assign_pressed() -> void:
	var picker: PopupMenu = %PlacedPicker
	picker.clear()
	var profession: StringName = TownRules.JOB_PROFESSIONS.get(TownRules.type_of(_open_building), &"")
	for passion_first: bool in [true, false]:
		for hero: Hero in GameSession.roster:
			if (profession in hero.passions) != passion_first:
				continue
			var marks: String = ""
			if profession != &"":
				marks = " — %s %d%s" % [str(profession).capitalize(), Hero.profession_skill(hero, profession, BALANCE), " · passion" if passion_first else ""]
			if hero.home != Hero.NO_HOME:
				marks += " · lives in %s" % str(hero.home).capitalize()
			if hero.station != Hero.NO_STATION:
				marks += " · works at %s" % str(hero.station).capitalize()
			picker.add_item("%s%s" % [hero.hero_name, marks])
			picker.set_item_metadata(picker.item_count - 1, hero.instance_id)
	_placed_picker_clears = false
	if picker.item_count == 0:
		_status.text = "No heroes to assign."
		return
	picker.popup_centered()


## One person here is taken out at once; more open the picker to choose.
func _on_placed_clear_pressed() -> void:
	var people: Array[Hero] = _placed_people()
	_placed_picker_clears = true
	if people.size() == 1:
		_apply_placed_pick(people[0])
		return
	var picker: PopupMenu = %PlacedPicker
	picker.clear()
	for hero: Hero in people:
		picker.add_item(hero.hero_name)
		picker.set_item_metadata(picker.item_count - 1, hero.instance_id)
	picker.popup_centered()


func _on_placed_picked(index: int) -> void:
	_apply_placed_pick(GameSession.hero_by_id(str(%PlacedPicker.get_item_metadata(index))))


func _apply_placed_pick(hero: Hero) -> void:
	var place: String = str(_open_building).capitalize()
	var house: bool = TownRules.type_of(_open_building) == TownRules.HOUSE
	var done: bool
	if house:
		done = GameSession.clear_home(hero) if _placed_picker_clears else GameSession.assign_home(hero, _open_building)
	else:
		done = GameSession.unstation_hero(hero) if _placed_picker_clears else GameSession.station_hero(hero, _open_building)
	if not done:
		_status.text = GameSession.last_action_error
	elif house:
		_status.text = ("%s moved out of %s." if _placed_picker_clears else "%s moved into %s.") % [hero.hero_name, place]
	else:
		_status.text = ("%s left the %s." if _placed_picker_clears else "%s works at the %s.") % [hero.hero_name, place]


func _on_step_out_pressed() -> void:
	if not GameSession.step_out():
		_status.text = GameSession.last_action_error


## The open building's keeper row: name, skill here and passions, or Away while it is out.
func _refresh_keeper() -> void:
	var profession: StringName = Hero.profession_for_building(_open_building)
	if profession == &"":
		return
	var keeper: Hero = GameSession.keeper_for(_open_building)
	%AssignKeeper.disabled = SaveService.load_blocked
	%UnassignKeeper.disabled = keeper == null or SaveService.load_blocked
	%KeeperBonus.text = ""
	if keeper == null:
		%KeeperName.text = "No keeper"
	elif GameSession.is_hero_busy(keeper):
		%KeeperName.text = "%s · Away" % keeper.hero_name
		%KeeperBonus.text = "Away: no bonus and no XP until home"
	else:
		# Short enough for the row; a long name trims, and the tooltip keeps the whole line.
		%KeeperName.text = "%s · %s %d · %s" % [
			keeper.hero_name,
			str(profession).capitalize(),
			Hero.profession_skill(keeper, profession, BALANCE),
			"passions %s" % _passions_text(keeper),
		]
		var to_next: float = Hero.profession_xp_to_next(keeper, profession, BALANCE)
		%KeeperBonus.text = "%s: %s · %s%s" % [
			keeper.hero_name,
			_keeper_bonus_text(_open_building, GameSession.keeper_skill(_open_building)),
			"max skill" if to_next <= 0.0 else "%d XP min to %s %d" % [ceili(to_next / 60.0), str(profession).capitalize(), Hero.profession_skill(keeper, profession, BALANCE) + 1],
			" · MASTER" if GameSession.keeper_is_master(_open_building) else "",
		]
	%KeeperName.tooltip_text = %KeeperName.text
	%KeeperBonus.tooltip_text = %KeeperBonus.text


## What a keeper at this skill adds to its building (SYSTEMS.md § Keepers and professions).
func _keeper_bonus_text(building_id: StringName, skill: int) -> String:
	var levels: float = BALANCE.keeper_skill_bonus_levels * skill
	match building_id:
		&"Forge":
			return "salvage +%s%%" % String.num(BALANCE.forge_salvage_yield_bonus * levels * 100.0, 1).trim_suffix(".0")
		&"Sanctum":
			return "essence +%s%%" % String.num(BALANCE.sanctum_essence_yield_bonus * levels * 100.0, 1).trim_suffix(".0")
		&"TrainingHall":
			return "expedition XP +%s%%" % String.num(BALANCE.training_hall_xp_bonus * levels * 100.0, 1).trim_suffix(".0")
		&"Reliquary":
			return "cache and rescue time +%s" % _format_duration(BALANCE.recovery_duration_seconds_per_level * BALANCE.battle_pace * levels)
		&"Apothecary":
			var costs: PackedStringArray = []
			for kind: String in BattleState.SUPPLY_KINDS:
				costs.append(str(BulkOperations.supply_parts_cost(kind, skill, BALANCE)))
			return "draughts %s F parts" % "/".join(costs)
	return ""


## The shared roster picker: every hero with its skill here, a passion for it marked. Rows hold ids, not
## Heroes: a failed save rebuilds the roster while the popup is open, and a held Hero goes stale.
func _on_assign_keeper_pressed() -> void:
	var profession: StringName = Hero.profession_for_building(_open_building)
	var picker: PopupMenu = %KeeperPicker
	picker.clear()
	for hero: Hero in GameSession.roster:
		var marks: String = " · passion" if profession in hero.passions else ""
		if hero.station == _open_building:
			marks += " · keeper"
		elif hero.station != Hero.NO_STATION:
			marks += " · keeps the %s" % str(hero.station).capitalize()
		picker.add_item("%s — %s %d%s" % [hero.hero_name, str(profession).capitalize(), Hero.profession_skill(hero, profession, BALANCE), marks])
		picker.set_item_metadata(picker.item_count - 1, hero.instance_id)
	if picker.item_count == 0:
		_status.text = "No heroes to keep the %s." % str(_open_building).capitalize()
		return
	picker.popup_centered()


func _on_keeper_picked(index: int) -> void:
	var hero: Hero = GameSession.hero_by_id(str(%KeeperPicker.get_item_metadata(index)))
	if GameSession.station_hero(hero, _open_building):
		_status.text = "%s keeps the %s." % [hero.hero_name, str(_open_building).capitalize()]
	else:
		_status.text = GameSession.last_action_error


func _on_unassign_keeper_pressed() -> void:
	var keeper: Hero = GameSession.keeper_for(_open_building)
	if keeper == null:
		return
	var keeper_name: String = keeper.hero_name
	if GameSession.unstation_hero(keeper):
		_status.text = "%s left the %s." % [keeper_name, str(_open_building).capitalize()]
	else:
		_status.text = GameSession.last_action_error


## Walking is what the button is for, so the building closes and the town shows the body.
func _on_walk_as_hero_pressed() -> void:
	var hero: Hero = _selected_hero()
	if hero == null:
		return
	if GameSession.embody_hero(hero.instance_id):
		_open(NO_BUILDING)
		_status.text = "You walk the town as %s." % hero.hero_name
	else:
		_status.text = GameSession.last_action_error


## The pause dim stops clicks; the building list's number keys are shortcuts, so they are disabled too.
func _on_pause_menu_visibility_changed() -> void:
	for building_id: StringName in BUILDING_PANELS:
		_building_button(building_id).disabled = _pause_menu.visible
	_sync_town_walk()


func _building_button(building_id: StringName) -> Button:
	return get_node("%%%sButton" % building_id) as Button


func _refresh_zone_unlocks() -> void:
	for option: OptionButton in [_zone_option, _combined_zone, _practice_zone]:
		for zone_index: int in option.item_count:
			var zone: ZoneDefinition = option.get_item_metadata(zone_index) as ZoneDefinition
			assert(zone != null)
			option.set_item_disabled(zone_index, not is_zone_unlocked(zone.zone_id, GameSession.cleared_zone_ids))


static func is_zone_unlocked(
	zone_id: StringName,
	cleared_zone_ids: Dictionary[StringName, bool],
) -> bool:
	match zone_id:
		&"verdant_outskirts":
			return true
		&"ashfall_reaches":
			return cleared_zone_ids.has(&"verdant_outskirts")
		&"sundered_vault":
			return cleared_zone_ids.has(&"ashfall_reaches")
		_:
			return false


## The pull is shown only after its commit lands. A failed save shows only the reason, so locking the
## save file can't be used to peek at a pull and take it back.
func _on_summon_pressed() -> void:
	var hero: Hero = Summon.roll(GameSession.building_levels[0])
	if GameSession.summon_hero(hero, BALANCE):
		_status.text = "Summoned %s, rank %s." % [hero.hero_name, hero.rank_label(BALANCE)]
	else:
		_status.text = GameSession.last_action_error


func _ask(prompt: String, action: Callable) -> void:
	_bulk_controls.visible = false
	_pending_bulk_plan.clear()
	_pending_action = action
	_confirm_dialog.dialog_text = ""
	_confirm_body.text = prompt
	_confirm_body.scroll_to_line(0)
	_popup_confirm_dialog(560)


func _popup_confirm_dialog(preferred_height: int) -> void:
	var viewport_size: Vector2i = Vector2i(get_viewport().get_visible_rect().size)
	var dialog_size := Vector2i(
		mini(760, maxi(viewport_size.x - 64, 320)),
		mini(preferred_height, maxi(viewport_size.y - 84, 300)),
	)
	_confirm_dialog.popup_centered(dialog_size)


func _on_confirm_dialog_confirmed() -> void:
	var action: Callable = _pending_action
	_pending_action = Callable()
	if action.is_valid():
		action.call()


func _on_sacrifice_pressed() -> void:
	var target: Hero = _target_option.get_selected_metadata() as Hero if _target_option.selected >= 0 else null
	if _selected_hero_ids.is_empty() or target == null:
		_status.text = "Select both a fodder hero and a target hero."
		return
	_bulk_kind = "sacrifice"
	_bulk_quantity.value = 0
	_open_bulk_dialog("Sacrifice selected heroes", "Sacrifice")


func _on_rank_up_pressed() -> void:
	var hero: Hero = _selected_hero()
	if hero == null:
		_status.text = "Select exactly one hero to rank up."
		return
	if GameSession.is_hero_busy(hero):
		_status.text = "Cannot rank up %s while that hero is away." % hero.hero_name
		return
	if hero.rank >= BALANCE.rank_up_essence_costs.size():
		_status.text = "%s is already at the highest rank." % hero.hero_name
		return
	var cost: int = Hero.compute_rank_up_cost(hero, BALANCE)
	if GameSession.essence < cost:
		_status.text = "Cannot rank up %s: need %d essence." % [hero.hero_name, cost]
		return
	var hero_name: String = hero.hero_name
	if GameSession.rank_up_hero(hero, BALANCE):
		_status.text = "Ranked %s up to %s for %d essence." % [hero_name, hero.rank_label(BALANCE), cost]
	elif not GameSession.last_action_error.is_empty():
		_status.text = GameSession.last_action_error
	else:
		_status.text = "Cannot rank up the selected hero."


func _on_roster_list_multi_selected(_index: int, _selected: bool) -> void:
	_selected_hero_ids.clear()
	for selected_index: int in _roster_list.get_selected_items():
		var selected_hero: Hero = _roster_list.get_item_metadata(selected_index) as Hero
		if selected_hero != null:
			_selected_hero_ids.append(selected_hero.instance_id)
	_refresh_equipped()
	_refresh_hero_detail()
	_refresh_preset_editor()


## A roster row's tooltip is its hero's detail head, set on the row under the mouse only (ig-7sn.9):
## every roster change built one per row, 100 details nobody reads. A tooltip waits about 0.5 s, so
## the row has it before it shows; the next rebuild clears it.
func _on_roster_list_gui_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion == null:
		return
	var index: int = _roster_list.get_item_at_position(motion.position, true)
	if index < 0 or not _roster_list.get_item_tooltip(index).is_empty():
		return
	var hero: Hero = _roster_list.get_item_metadata(index) as Hero
	if hero != null:
		_roster_list.set_item_tooltip(index, _hero_detail_text(hero))


func _on_select_all_roster_pressed() -> void:
	for item_index: int in _roster_list.item_count:
		_roster_list.select(item_index, false)
	_refresh_equipped()
	_refresh_hero_detail()
	_on_roster_list_multi_selected(-1, true)
	_status.text = "Selected %d heroes." % _roster_list.item_count


func _on_roster_rank_filter_item_selected(index: int) -> void:
	_roster_min_rank = _roster_rank_filter.get_item_metadata(index) as int
	_refresh_roster()
	_refresh_equipped()
	_refresh_hero_detail()


func _on_roster_exact_rank_toggled(_toggled_on: bool) -> void:
	_refresh_roster()
	_refresh_equipped()
	_refresh_hero_detail()


func _on_roster_type_filter_item_selected(index: int) -> void:
	_roster_archetype_filter_index = _roster_type_filter.get_item_metadata(index) as int
	_refresh_roster()
	_refresh_equipped()
	_refresh_hero_detail()


func _on_inventory_rank_filter_item_selected(index: int) -> void:
	_inventory_min_rank = _inventory_rank_filter.get_item_metadata(index) as int
	_refresh_inventory()


func _on_inventory_exact_rank_toggled(_toggled_on: bool) -> void:
	_refresh_inventory()


func _on_inventory_slot_filter_item_selected(index: int) -> void:
	_slot_filter = _inventory_slot_filter.get_item_metadata(index) as int
	_refresh_inventory()


func _on_inventory_list_multi_selected(_index: int, _selected: bool) -> void:
	_selected_item_ids.clear()
	for selected_index: int in _inventory_list.get_selected_items():
		var item: Item = _inventory_list.get_item_metadata(selected_index) as Item
		if item != null:
			_selected_item_ids.append(item.instance_id)
	_refresh_favorite_item_control()


func _on_select_all_inventory_pressed() -> void:
	for item_index: int in _inventory_list.item_count:
		_inventory_list.select(item_index, false)
	_selected_item_ids.clear()
	for selected_index: int in _inventory_list.get_selected_items():
		var item: Item = _inventory_list.get_item_metadata(selected_index) as Item
		if item != null:
			_selected_item_ids.append(item.instance_id)
	_status.text = "Selected %d items." % _inventory_list.item_count


func _on_equip_pressed() -> void:
	var hero: Hero = _selected_hero()
	if hero == null:
		_status.text = "Select exactly one hero first."
		return
	if GameSession.is_hero_busy(hero):
		_status.text = "Cannot equip gear while that hero is away."
		return
	var selected: PackedInt32Array = _inventory_list.get_selected_items()
	if selected.size() != 1:
		_status.text = "Select exactly one inventory item."
		return
	var item: Item = _inventory_list.get_item_metadata(selected[0]) as Item
	assert(item != null)
	var definition: EquipmentDefinition = Item.definition_for(item.def_id)
	if definition == null:
		_status.text = "Cannot equip item: its definition is missing."
		return
	GameSession.equip_item(hero, item)
	_status.text = "Equipped %s %s on %s." % [item.rank_label(BALANCE), definition.display_name, hero.hero_name]


func _on_salvage_pressed() -> void:
	if _selected_item_ids.is_empty():
		_status.text = "Select at least one inventory item."
		return
	_bulk_kind = "salvage"
	_bulk_quantity.value = 0
	_open_bulk_dialog("Salvage selected items", "Salvage")


func _on_enhance_pressed() -> void:
	if _selected_item_ids.is_empty():
		_status.text = "Select at least one inventory item."
		return
	var enhance_cap: int = GameSession.enhance_cap(BALANCE)
	if enhance_cap <= 0:
		_status.text = "Cannot enhance: build the Forge first."
		return
	_enhance_target_level.max_value = enhance_cap
	_enhance_target_level.value = enhance_cap
	for budget: SpinBox in _enhance_budgets:
		budget.value = 0
	_update_enhance_preview()
	var viewport_size: Vector2i = Vector2i(get_viewport().get_visible_rect().size)
	_enhance_dialog.popup_centered(Vector2i(
		mini(760, maxi(viewport_size.x - 64, 400)),
		mini(620, maxi(viewport_size.y - 84, 420)),
	))


func _on_convert_pressed() -> void:
	var selected_rank: int = _convert_rank_option.get_item_metadata(_convert_rank_option.selected) as int
	var plan: Dictionary = GameSession.preview_bulk_conversion(selected_rank, int(_convert_quantity.value), int(_convert_reserve.value))
	if not bool(plan.get("valid", false)):
		_status.text = str(plan.get("error", "Conversion is not available."))
		return
	_ask("Convert parts?\n\n%s" % _format_bulk_plan(plan), _commit_bulk_plan.bind(plan))


func _on_convert_max_pressed() -> void:
	var selected_rank: int = _convert_rank_option.get_item_metadata(_convert_rank_option.selected) as int
	var plan: Dictionary = GameSession.preview_bulk_conversion(selected_rank, 0, int(_convert_reserve.value))
	if not bool(plan.get("valid", false)):
		_status.text = str(plan.get("error", "No parts are available above the reserve."))
		return
	_ask("Convert the maximum without chaining ranks?\n\n%s" % _format_bulk_plan(plan), _commit_bulk_plan.bind(plan))


func _open_bulk_dialog(title: String, confirm_text: String) -> void:
	_bulk_controls.visible = true
	_confirm_dialog.title = title
	_confirm_dialog.ok_button_text = confirm_text
	_confirm_dialog.dialog_text = ""
	_pending_action = _commit_current_bulk_plan
	_update_bulk_preview()
	_popup_confirm_dialog(580)


func _on_bulk_quantity_changed(_value: float) -> void:
	if _bulk_controls.visible:
		_update_bulk_preview()


func _update_bulk_preview() -> void:
	var quantity: int = int(_bulk_quantity.value)
	if _bulk_kind == "salvage":
		_pending_bulk_plan = GameSession.preview_bulk_salvage(_selected_item_ids.duplicate(), quantity)
	elif _bulk_kind == "sacrifice":
		var target: Hero = _target_option.get_selected_metadata() as Hero if _target_option.selected >= 0 else null
		_pending_bulk_plan = GameSession.preview_bulk_sacrifice(_selected_hero_ids.duplicate(), target.instance_id if target != null else "", quantity)
	else:
		_pending_bulk_plan = {}
	var preview_text: String = _format_bulk_plan(_pending_bulk_plan)
	if _bulk_kind == "sacrifice":
		var target: Hero = _target_option.get_selected_metadata() as Hero if _target_option.selected >= 0 else null
		var output_text: String = "%d essence" % int(_pending_bulk_plan.get("essence_gain", 0))
		var resonance_gain: int = int(_pending_bulk_plan.get("resonance_gain", 0))
		output_text += " · %d resonance" % resonance_gain
		preview_text = "Recipient: %s\nTotal output: %s\n\n%s" % [target.hero_name if target != null else "Missing", output_text, preview_text]
	_confirm_body.text = "Review the exact eligible and skipped entries before confirming.\n\n%s" % preview_text
	_confirm_body.scroll_to_line(0)
	_confirm_dialog.get_ok_button().disabled = not bool(_pending_bulk_plan.get("valid", false))


func _commit_current_bulk_plan() -> void:
	_commit_bulk_plan(_pending_bulk_plan)
	_bulk_controls.visible = false


func _commit_bulk_plan(plan: Dictionary) -> void:
	if SaveService.load_blocked:
		_status.text = SaveService.load_block_reason
		return
	if GameSession.commit_bulk_plan(plan):
		_status.text = "%s completed." % str(plan.get("kind", "Bulk action")).capitalize()
	else:
		_status.text = GameSession.last_action_error


func _format_bulk_plan(plan: Dictionary) -> String:
	if plan.is_empty():
		return "No preview available."
	var lines: PackedStringArray = []
	if not bool(plan.get("valid", false)):
		lines.append(str(plan.get("error", "This action is not available.")))
	for entry: Variant in plan.get("entries", []) as Array:
		if not entry is Dictionary:
			continue
		var data: Dictionary = entry as Dictionary
		var detail: String = ""
		match str(plan.get("kind", "")):
			"supplies":
				detail = "%d units · spend %d F-parts · %s" % [int(data.get("units", 0)), int(data.get("spend", 0)), str(data.get("supply_kind", "supply"))]
			"enhance":
				detail = "+%d → +%d; spend %s" % [int(data.get("before_level", 0)), int(data.get("after_level", 0)), str(data.get("spend", 0))]
			"salvage":
				detail = "+%s parts" % str(data.get("gain", 0))
			"sacrifice":
				detail = "+%d essence%s" % [int(data.get("essence_gain", 0)), " · +%d resonance" % int(data.get("resonance_gain", 0)) if int(data.get("resonance_gain", 0)) > 0 else ""]
			"conversion":
				detail = "%d units · spend %d · gain %d" % [int(data.get("units", 0)), int(data.get("spend", 0)), int(data.get("gain", 0))]
		var rank_index: int = int(data.get("rank", -1))
		var rank_label: String = BALANCE.rank_names[rank_index] if rank_index >= 0 and rank_index < BALANCE.rank_names.size() else "?"
		if str(plan.get("kind", "")) == "enhance":
			lines.append("• %s → +%d; spend %s %s parts" % [str(data.get("name", "Entry")), int(data.get("after_level", 0)), str(data.get("spend", 0)), rank_label])
			continue
		if str(plan.get("kind", "")) == "supplies":
			lines.append("• %s — %s" % [str(data.get("name", "Supply")), detail])
			continue
		lines.append("• %s [%s] — %s" % [str(data.get("name", "Entry")), rank_label, detail])
	var excluded: Array = plan.get("excluded", []) as Array
	if not excluded.is_empty():
		lines.append("Skipped %d protected/ineligible:" % excluded.size())
		for excluded_entry: Variant in excluded:
			if excluded_entry is Dictionary:
				var data: Dictionary = excluded_entry as Dictionary
				lines.append("• %s — %s" % [str(data.get("name", "Entry")), str(data.get("reason", "ineligible"))])
	if lines.is_empty():
		lines.append("Nothing eligible for this action.")
	return "\n".join(lines)


func _on_use_available_parts_pressed() -> void:
	for index: int in _enhance_budgets.size():
		_enhance_budgets[index].value = GameSession.parts[index]
	_update_enhance_preview()


func _on_enhance_preview_changed(_value: float) -> void:
	if _enhance_dialog.visible:
		_update_enhance_preview()


func _update_enhance_preview() -> void:
	var budgets: Array[int] = []
	for budget: SpinBox in _enhance_budgets:
		budgets.append(int(budget.value))
	_pending_bulk_plan = GameSession.preview_bulk_enhance(_selected_item_ids.duplicate(), int(_enhance_target_level.value), budgets)
	_enhance_preview.text = _format_bulk_plan(_pending_bulk_plan)
	if not _masterwork_note().is_empty():
		_enhance_preview.text = _masterwork_note() + "\n\n" + _enhance_preview.text
	_enhance_dialog.get_ok_button().disabled = not bool(_pending_bulk_plan.get("valid", false))


func _on_enhance_dialog_confirmed() -> void:
	_commit_bulk_plan(_pending_bulk_plan)


func _on_upgrade_circle_pressed() -> void:
	_upgrade_building(0, "Summoning Circle")


func _on_upgrade_forge_pressed() -> void:
	_upgrade_building(1, "Forge")


func _on_upgrade_training_hall_pressed() -> void:
	_upgrade_building(2, "Training Hall")


func _on_upgrade_sanctum_pressed() -> void:
	_upgrade_building(3, "Sanctum")


func _on_upgrade_reliquary_pressed() -> void:
	_upgrade_building(4, "Reliquary")


## The costs come from the preview, which is the plan upgrade_building spends.
func _upgrade_building(index: int, building_name: String) -> void:
	var plan: Dictionary = GameSession.preview_building_upgrade(index)
	if not GameSession.upgrade_building(index, BALANCE):
		_status.text = "Cannot upgrade %s. %s" % [building_name, GameSession.last_action_error]
		return
	_status.text = "Upgraded %s to Lv %d for %d %s parts, %d wood and %d stone." % [building_name, plan["next_level"], plan["part_cost"], BALANCE.rank_names[int(plan["part_rank"])], plan["wood_cost"], plan["stone_cost"]]


func _on_unequip_pressed() -> void:
	var hero: Hero = _selected_hero()
	if hero == null:
		_status.text = "Select exactly one hero first."
		return
	if GameSession.is_hero_busy(hero):
		_status.text = "Cannot unequip gear while that hero is away."
		return
	var selected: PackedInt32Array = _equipped_list.get_selected_items()
	if selected.size() != 1:
		_status.text = "Select exactly one equipped item."
		return
	var slot: int = _equipped_list.get_item_metadata(selected[0]) as int
	var item: Item = hero.equipped.get(slot) as Item
	if item == null:
		_status.text = "That slot is empty."
		return
	var definition: EquipmentDefinition = Item.definition_for(item.def_id)
	GameSession.unequip_item(hero, slot)
	if definition == null:
		_status.text = "Unequipped item from %s." % hero.hero_name
	else:
		_status.text = "Unequipped %s %s from %s." % [item.rank_label(BALANCE), definition.display_name, hero.hero_name]


func _on_unequip_all_pressed() -> void:
	var hero: Hero = _selected_hero()
	if hero == null:
		_status.text = "Select exactly one hero first."
		return
	if GameSession.is_hero_busy(hero):
		_status.text = "Cannot unequip gear while that hero is away."
		return
	var occupied_slots: Array[int] = []
	for slot: int in hero.equipped.keys():
		occupied_slots.append(slot)
	if occupied_slots.is_empty():
		_status.text = "%s has nothing equipped." % hero.hero_name
		return
	for slot: int in occupied_slots:
		GameSession.unequip_item(hero, slot)
	_status.text = "Unequipped %d items from %s." % [occupied_slots.size(), hero.hero_name]


func _on_expedition_pressed() -> void:
	_on_dispatch_selected_pressed()


func _hero_names(team: Array[Hero]) -> PackedStringArray:
	var names: PackedStringArray = []
	for hero: Hero in team:
		names.append("[%s] %s" % [hero.rank_label(BALANCE), hero.hero_name])
	return names


func _on_enter_arena_pressed() -> void:
	if _practice_preset.selected < 0:
		_status.text = "Choose a ready saved team for RTS practice."
		return
	var preset: Dictionary = _practice_preset.get_selected_metadata() as Dictionary
	if preset.is_empty() or _preset_status(preset) != "Ready":
		_status.text = "Choose a ready saved team for RTS practice."
		return
	var team: Array[Hero] = _heroes_for_ids(_string_array(preset.get("hero_ids", [])))
	if team.is_empty() or team.size() > MAX_TEAM_SIZE or team.size() != _string_array(preset.get("hero_ids", [])).size():
		_status.text = "Practice requires a complete saved team of 1–5 heroes."
		return
	var zone: ZoneDefinition = _practice_zone.get_selected_metadata() as ZoneDefinition if _practice_zone.selected >= 0 else null
	if zone == null or not is_zone_unlocked(zone.zone_id, GameSession.cleared_zone_ids):
		_status.text = "Choose an unlocked standard zone for practice."
		return
	SceneRouter.prepare_battle_practice(team, zone)
	SceneRouter.go_to(SceneRouter.BATTLE)


## Writes the arena's result to %Status; false when there was none.
func _show_pending_arena_result() -> bool:
	var result: CombatResult = SceneRouter.take_arena_result()
	if result == null:
		return false
	if not result.survivors.is_empty():
		var survivor: Hero = result.survivors[0]
		_status.text = "Arena victory: %s survived with %d/%d HP." % [
			survivor.hero_name,
			roundi(result.hp_after[survivor]),
			roundi(result.maximum_hp[survivor]),
		]
		return true
	assert(result.dead_heroes.size() == 1)
	# The legacy arena result is display-only, so its prototype "death" remains isolated from permadeath.
	_status.text = "Arena defeat: %s went down. Practice only, nothing lost." % result.dead_heroes[0].hero_name
	return true


## Each call skips while the panel it writes is hidden (ig-7sn.9); _open runs it. The lockout doesn't.
func _refresh_director_ui() -> void:
	if not _skip_hidden(&"preset_lists"):
		_refresh_preset_lists()
	if not _skip_hidden(&"preset_editor"):
		_refresh_preset_editor()
	if not _skip_hidden(&"recovery"):
		_refresh_recovery_team_options()
	if not _skip_hidden(&"practice"):
		_refresh_practice_options()
	if not _skip_hidden(&"expeditions"):
		_refresh_expeditions(true)
	if not _skip_hidden(&"hero_detail"):
		_refresh_hero_detail()
	if SaveService.load_blocked:
		_status.text = SaveService.load_block_reason
		_disable_mutating_controls()


func _disable_mutating_controls() -> void:
	for control: BaseButton in [%AssignKeeper, %UnassignKeeper, %DispatchSelected, %SavePreset, %SaveAndGo, %DeletePreset, %Sacrifice, %RankUp, %Equip, %Salvage, %Enhance, %Convert, %Summon, %Recover, %StartRecoveryWindow, %UpgradeCircle, %UpgradeForge, %UpgradeTrainingHall, %UpgradeSanctum, %UpgradeReliquary]:
		control.disabled = true
		control.tooltip_text = SaveService.load_block_reason


func _refresh_preset_lists() -> void:
	var selected_ids: Array[String] = []
	for index: int in _preset_dispatch_list.get_selected_items():
		var preset: Dictionary = _preset_dispatch_list.get_item_metadata(index) as Dictionary
		selected_ids.append(str(preset.get("id", "")))
	_preset_dispatch_list.clear()
	_preset_selector.clear()
	_preset_selector.add_item("New team")
	_preset_selector.set_item_metadata(0, "")
	for preset: Dictionary in GameSession.team_presets:
		var status: String = _preset_status(preset)
		_preset_dispatch_list.add_item("[%s] %s" % [status, str(preset.get("name", "Unnamed team"))])
		var row: int = _preset_dispatch_list.item_count - 1
		_preset_dispatch_list.set_item_metadata(row, preset)
		_preset_dispatch_list.set_item_tooltip(row, _preset_tooltip(preset))
		if selected_ids.has(str(preset.get("id", ""))):
			_preset_dispatch_list.select(row, false)
		_preset_selector.add_item(str(preset.get("name", "Unnamed team")))
		_preset_selector.set_item_metadata(_preset_selector.item_count - 1, str(preset.get("id", "")))
		if str(preset.get("id", "")) == _editing_preset_id:
			_preset_selector.select(_preset_selector.item_count - 1)
	# One primary button per state, the next step: summon, make a team, or dispatch. No heroes means
	# summon even when saved teams outlived their members: nothing on the list could go out.
	var no_heroes: bool = GameSession.roster.is_empty()
	var no_team: bool = GameSession.team_presets.is_empty()
	_dispatch_empty.text = "Summon heroes at the Summoning Circle to form your first team." if no_heroes else "Make a team first: pick heroes at the Training Hall, then send them out from here."
	_dispatch_empty.visible = no_team or no_heroes
	%DispatchBlock.visible = not no_team and not no_heroes
	%GoToHall.visible = no_heroes
	# Every saved team lost its members (permadeath, then a new summon): fixing a team is the next step,
	# not a Dispatch that cannot fire. A team Away or In town only needs waiting, so it keeps Dispatch.
	var needs_fix: bool = not no_heroes and not no_team
	for preset: Dictionary in GameSession.team_presets:
		if _preset_status(preset) != "Missing" and not _string_array(preset.get("hero_ids", [])).is_empty():
			needs_fix = false
	%ManageTeams.visible = not no_heroes
	%ManageTeams.text = "Make a team" if no_team else "Fix a team" if needs_fix else "Manage teams"
	%ManageTeams.theme_type_variation = &"PrimaryButton" if no_team or needs_fix else &""
	_dispatch_selected.theme_type_variation = &"" if needs_fix else &"PrimaryButton"
	_dispatch_selected.disabled = GameSession.team_presets.is_empty() or SaveService.load_blocked
	_refresh_dispatch_summary()


func _preset_status(preset: Dictionary) -> String:
	var missing: bool = false
	var away: bool = false
	var body: String = ""
	for hero_id: String in _string_array(preset.get("hero_ids", [])):
		var hero: Hero = GameSession.hero_by_id(hero_id)
		if hero == null:
			missing = true
		elif GameSession.is_hero_busy(hero):
			away = true
		elif GameSession.is_embodied(hero):
			body = hero.hero_name
	if missing:
		return "Missing"
	if away:
		return "Away"
	if not body.is_empty():
		return "In town: %s" % body
	return "Ready"


func _preset_tooltip(preset: Dictionary) -> String:
	var lines: PackedStringArray = [str(preset.get("name", "Unnamed team")), "State: %s" % _preset_status(preset)]
	for hero_id: String in _string_array(preset.get("hero_ids", [])):
		var hero: Hero = GameSession.hero_by_id(hero_id)
		lines.append("• Missing (%s)" % hero_id if hero == null else "• %s" % hero.hero_name)
	return "\n".join(lines)


func _refresh_preset_editor() -> void:
	var lines: PackedStringArray = []
	for hero_id: String in _selected_hero_ids:
		var hero: Hero = GameSession.hero_by_id(hero_id)
		lines.append("• Missing (%s)" % hero_id if hero == null else "• %s — %s" % [hero.hero_name, _hero_state_text(hero)])
	if lines.is_empty():
		lines.append("Click a hero in the roster to add it. Ctrl- or Shift-click adds more, up to 5.")
	var zone: ZoneDefinition = _zone_option.get_selected_metadata() as ZoneDefinition if _zone_option.selected >= 0 else null
	var team: Array[Hero] = _heroes_for_ids(_selected_hero_ids)
	var valid_definitions: bool = true
	for hero: Hero in team:
		if hero.def_id == Hero.NO_ARCHETYPE_DEF_ID:
			valid_definitions = false
			break
	if not team.is_empty() and team.size() == _selected_hero_ids.size() and zone != null and valid_definitions:
		var duration: float = ExpeditionOrders.duration_seconds(team, zone, BALANCE)
		var forecast: Dictionary = ExpeditionOrders.safety_forecast(team, zone, BALANCE)
		lines.append("Power forecast: %s · ETA %s" % [str(forecast.get("reason", "Unknown")), _format_duration(duration)])
	if not _selected_hero_ids.is_empty() and _selected_hero_ids.size() < MAX_TEAM_SIZE:
		lines.append("Ctrl- or Shift-click the roster to add more (up to 5).")
	_preset_members.text = "\n".join(lines)


func _on_preset_selector_selected(index: int) -> void:
	_editing_preset_id = str(_preset_selector.get_item_metadata(index))
	if _editing_preset_id.is_empty():
		_preset_name.text = _next_team_name()
		_selected_hero_ids.clear()
		_roster_list.deselect_all()
		_refresh_preset_editor()
		return
	var preset: Dictionary = _preset_by_id(_editing_preset_id)
	_preset_name.text = str(preset.get("name", ""))
	_selected_hero_ids = _string_array(preset.get("hero_ids", []))
	for zone_index: int in _zone_option.item_count:
		var zone: ZoneDefinition = _zone_option.get_item_metadata(zone_index) as ZoneDefinition
		if zone != null and str(zone.zone_id) == str(preset.get("zone_id", "")):
			_zone_option.select(zone_index)
			break
	_refresh_roster()
	_refresh_preset_editor()


## The lowest "Team N" (N >= 1) that no saved team uses, so a new team never starts nameless.
func _next_team_name() -> String:
	var taken: Dictionary[String, bool] = {}
	for preset: Dictionary in GameSession.team_presets:
		taken[str(preset.get("name", ""))] = true
	var number: int = 1
	while taken.has("Team %d" % number):
		number += 1
	return "Team %d" % number


## Returns whether the team saved; a refusal goes on the status line.
func _on_save_preset_pressed() -> bool:
	if SaveService.load_blocked:
		_status.text = SaveService.load_block_reason
		return false
	var zone: ZoneDefinition = _zone_option.get_selected_metadata() as ZoneDefinition if _zone_option.selected >= 0 else null
	if zone == null:
		_status.text = "Choose a valid preferred zone."
		return false
	var result_id: String = GameSession.save_team_preset(_editing_preset_id, _preset_name.text.strip_edges(), _selected_hero_ids.duplicate(), str(zone.zone_id))
	if result_id.is_empty():
		_status.text = GameSession.last_action_error
		return false
	_editing_preset_id = result_id
	_status.text = "Saved team %s." % _preset_name.text.strip_edges()
	return true


## Saves, then opens the Gate with only that team picked. It never dispatches: the player still
## sees the runs, policies and forecast, and presses Dispatch.
func _on_save_and_go_pressed() -> void:
	if not _on_save_preset_pressed():
		return
	_open(&"TownGate")
	_preset_dispatch_list.deselect_all()
	for row: int in _preset_dispatch_list.item_count:
		if str((_preset_dispatch_list.get_item_metadata(row) as Dictionary).get("id", "")) == _editing_preset_id:
			_preset_dispatch_list.select(row, false)
	_refresh_dispatch_summary()
	_dispatch_selected.grab_focus()


func _on_delete_preset_pressed() -> void:
	if _editing_preset_id.is_empty():
		_status.text = "Choose a saved preset to delete."
		return
	var preset: Dictionary = _preset_by_id(_editing_preset_id)
	_ask("Delete team preset %s? Active expeditions will continue." % str(preset.get("name", "this team")), _do_delete_preset.bind(_editing_preset_id))


func _do_delete_preset(preset_id: String) -> void:
	if GameSession.delete_team_preset(preset_id):
		_editing_preset_id = ""
		_preset_name.text = _next_team_name()
		_status.text = "Deleted team preset."
	else:
		_status.text = GameSession.last_action_error


func _on_dispatch_selection_changed(_index: int, _selected: bool) -> void:
	_refresh_dispatch_summary()


func _on_dispatch_options_changed(_enabled: bool) -> void:
	_refresh_dispatch_summary()


func _on_runs_per_team_changed(_value: float) -> void:
	_refresh_dispatch_summary()


func _refresh_dispatch_summary() -> void:
	var preview: Dictionary = _selected_force_preview()
	var selected_count: int = _preset_dispatch_list.get_selected_items().size()
	var count_label: String = "force" if _combine_teams.button_pressed else "order(s)"
	var summary: String = "%d team(s) selected · %d %s" % [selected_count, 1 if _combine_teams.button_pressed else selected_count, count_label]
	if preview.is_empty():
		_dispatch_summary.text = summary + "\nSelect ready, non-overlapping teams."
	elif preview.has("orders_preview"):
		var detail_lines: PackedStringArray = [summary]
		var total_heroes: int = 0
		var total_capacity: int = 0
		var total_squads: int = 0
		var safe_forecast: bool = true
		var checking: bool = false
		var raw_previews: Variant = preview.get("orders_preview", [])
		for entry_value: Variant in raw_previews as Array:
			if not entry_value is Dictionary:
				continue
			var entry: Dictionary = entry_value as Dictionary
			total_heroes += int(entry.get("hero_count", 0))
			total_capacity += int(entry.get("capacity", 0))
			total_squads += int(entry.get("squad_count", 0))
			safe_forecast = safe_forecast and bool(entry.get("safe", false))
			checking = checking or bool(entry.get("checking", false))
			detail_lines.append("• %s · %d/cap %d · %s min · %s" % [str(entry.get("name", "Team")), int(entry.get("hero_count", 0)), int(entry.get("capacity", 0)), _format_duration(float(entry.get("route_seconds", 0.0))), str(entry.get("reason", ""))])
			var pay_line: String = _pay_line(entry)
			if not pay_line.is_empty():
				detail_lines.append("  " + pay_line)
		detail_lines.append("Total %d heroes / %d per-order capacity · %d squads · forecast %s (never guaranteed safe)" % [total_heroes, total_capacity, total_squads, "checking" if checking else ("safe" if safe_forecast else "not safe")])
		_dispatch_summary.text = "\n".join(detail_lines)
	else:
		_dispatch_summary.text = "%s\n%d heroes / cap %d · %d squad(s) · route minimum %s\nForecast: %s · %s" % [
			summary,
			int(preview.get("hero_count", 0)),
			int(preview.get("capacity", 0)),
			int(preview.get("squad_count", 0)),
			_format_duration(float(preview.get("route_seconds", 0.0))),
			"checking" if bool(preview.get("checking", false)) else ("forecast only; safety is not guaranteed" if bool(preview.get("safe", false)) else "not forecast safe"),
			str(preview.get("reason", "")),
		]
		var pay_line: String = _pay_line(preview)
		if not pay_line.is_empty():
			_dispatch_summary.text += "\n" + pay_line
	var keepers: String = _absent_keepers_text()
	if not keepers.is_empty():
		_dispatch_summary.text += "\n" + keepers
	_repeat_until_stopped.disabled = preview.is_empty()
	_dispatch_selected.disabled = preview.is_empty() or not bool(preview.get("valid", false)) or SaveService.load_blocked
	_combined_zone.visible = _combine_teams.button_pressed
	%BattleSettingsToggle.text = "Battle settings · allocation per %s" % ("force/order" if _combine_teams.button_pressed else "team/order")


## ig-ncz (in ig-0og.1): the preview's pay cut, said out loud so it never reads as a bug; "" at 100%.
func _pay_line(preview: Dictionary) -> String:
	var percent: int = int(preview.get("pay_percent", 100))
	if percent >= 100:
		return ""
	return "Pays %d%% a clear here: this team is over-strong, so it earns the same per hour." % percent


## Keepers and workers can be sent out; this only says which counters stand empty and which
## workplaces run short meanwhile. Not a modal.
func _absent_keepers_text() -> String:
	var absent: PackedStringArray = []
	var short: Dictionary[StringName, Array] = {}
	for row: int in _preset_dispatch_list.get_selected_items():
		var preset: Dictionary = _preset_dispatch_list.get_item_metadata(row) as Dictionary
		for hero_id: Variant in preset.get("hero_ids", []) as Array:
			var hero: Hero = GameSession.hero_by_id(str(hero_id))
			if hero == null or hero.station == Hero.NO_STATION:
				continue
			if TownRules.is_workplace_id(hero.station):
				short.get_or_add(hero.station, []).append(hero.hero_name)
			else:
				absent.append("%s (%s)" % [str(hero.station).capitalize(), hero.hero_name])
	var lines: PackedStringArray = []
	if not absent.is_empty():
		lines.append("Runs without its keeper while away: %s" % ", ".join(absent))
	for workplace: StringName in short:
		lines.append("%s runs short while away (%s)" % [str(workplace).capitalize(), ", ".join(PackedStringArray(short[workplace]))])
	return "\n".join(lines)


func _on_battle_settings_toggle_pressed() -> void:
	_battle_settings.visible = not _battle_settings.visible


func _on_combine_teams_toggled(_enabled: bool) -> void:
	_refresh_dispatch_summary()


func _on_battle_policy_changed(_enabled: bool) -> void:
	_refresh_dispatch_summary()


func _on_battle_policy_value_changed(_value: float) -> void:
	_refresh_dispatch_summary()


func _on_battle_stance_changed(_index: int) -> void:
	_refresh_dispatch_summary()


func _selected_force_preview() -> Dictionary:
	var selected: PackedInt32Array = _preset_dispatch_list.get_selected_items()
	if selected.is_empty():
		return {}
	var preset_ids: Array[String] = []
	for row: int in selected:
		var preset: Dictionary = _preset_dispatch_list.get_item_metadata(row) as Dictionary
		if _preset_status(preset) != "Ready":
			return {}
		preset_ids.append(str(preset.get("id", "")))
	var zone_id: String = ""
	if _combine_teams.button_pressed:
		var zone: ZoneDefinition = _combined_zone.get_selected_metadata() as ZoneDefinition if _combined_zone.selected >= 0 else null
		if zone == null or not is_zone_unlocked(zone.zone_id, GameSession.cleared_zone_ids):
			return {}
		zone_id = str(zone.zone_id)
	else:
		# Per-team mode still previews each order independently, using its saved preferred zone.
		var order_previews: Array[Dictionary] = []
		var all_valid: bool = true
		var total_heroes: int = 0
		var total_capacity: int = 0
		var total_squads: int = 0
		var longest_route: float = 0.0
		var all_safe: bool = true
		var reasons: PackedStringArray = []
		for row: int in selected:
			var preset: Dictionary = _preset_dispatch_list.get_item_metadata(row) as Dictionary
			var own_zone: String = str(preset.get("zone_id", ""))
			var order_preview: Dictionary = GameSession.preview_force([str(preset.get("id", ""))], own_zone, _total_runs(), _battle_policies(), _battle_loadout())
			order_preview["name"] = str(preset.get("name", "Unnamed team"))
			order_previews.append(order_preview)
			all_valid = all_valid and bool(order_preview.get("valid", false))
			all_safe = all_safe and bool(order_preview.get("safe", false))
			total_heroes += int(order_preview.get("hero_count", 0))
			total_capacity += int(order_preview.get("capacity", 0))
			total_squads += int(order_preview.get("squad_count", 0))
			longest_route = maxf(longest_route, float(order_preview.get("route_seconds", 0.0)))
			var reason_text: String = str(order_preview.get("reason", ""))
			if reason_text.is_empty():
				reason_text = str(order_preview.get("error", "No forecast"))
			reasons.append("%s: %s" % [str(preset.get("name", "Team")), reason_text])
		return {"valid": all_valid, "safe": all_safe, "reason": "; ".join(reasons), "hero_count": total_heroes, "capacity": total_capacity, "squad_count": total_squads, "route_seconds": longest_route, "orders_preview": order_previews}
	return GameSession.preview_force(preset_ids, zone_id, _total_runs(), _battle_policies(), _battle_loadout())


func _total_runs() -> int:
	return 0 if _repeat_until_stopped.button_pressed else int(_runs_per_team.value)


func _battle_policies() -> Dictionary:
	var stance: OptionButton = %BattleStance
	return {
		"auto_battle": %AutoBattle.button_pressed,
		"default_stance": str(stance.get_selected_metadata()) if stance.selected >= 0 else "stay_together",
		"auto_heal": %AutoHeal.button_pressed,
		"auto_revive": %AutoRevive.button_pressed,
		"heal_below": float(%HealThreshold.value) / 100.0,
		"reserve_last_revival": %ReserveLastRevival.button_pressed,
		"retreat_when_supplies_empty": %RetreatIfEmpty.button_pressed,
	}


func _battle_loadout() -> Dictionary:
	var loadout: Dictionary = {}
	for kind: String in BattleState.SUPPLY_KINDS:
		loadout[kind] = int((get_node("%" + kind.to_pascal_case() + "Allocation") as SpinBox).value)
		loadout["keep_" + kind] = int((get_node("%" + kind.to_pascal_case() + "Floor") as SpinBox).value)
	return loadout


func _on_suggested_allocations_pressed() -> void:
	var heroes: int = 0
	var squads: int = 0
	for row: int in _preset_dispatch_list.get_selected_items():
		var preset: Dictionary = _preset_dispatch_list.get_item_metadata(row) as Dictionary
		var members: Array[String] = _string_array(preset.get("hero_ids", []))
		heroes += members.size()
		squads += 1
	if _combine_teams.button_pressed:
		%HealingAllocation.value = heroes
		%RevivalAllocation.value = squads
	else:
		var largest: int = 0
		for row: int in _preset_dispatch_list.get_selected_items():
			var preset: Dictionary = _preset_dispatch_list.get_item_metadata(row) as Dictionary
			largest = maxi(largest, _string_array(preset.get("hero_ids", [])).size())
		%HealingAllocation.value = largest
		%RevivalAllocation.value = 1
	_refresh_dispatch_summary()


func _on_dispatch_selected_pressed() -> void:
	var selected: PackedInt32Array = _preset_dispatch_list.get_selected_items()
	if selected.is_empty():
		_status.text = "Select at least one ready team."
		return
	var presets: Array[Dictionary] = []
	var used_heroes: Dictionary[String, bool] = {}
	for row: int in selected:
		var preset: Dictionary = _preset_dispatch_list.get_item_metadata(row) as Dictionary
		if _preset_status(preset) != "Ready":
			_status.text = "%s is not ready; Missing and Away members are never substituted." % str(preset.get("name", "A team"))
			return
		for hero_id: String in _string_array(preset.get("hero_ids", [])):
			if used_heroes.has(hero_id):
				_status.text = "Selected teams overlap on a hero. Choose non-overlapping teams."
				return
			used_heroes[hero_id] = true
		presets.append(preset)
	var preview: Dictionary = _selected_force_preview()
	if not bool(preview.get("valid", false)):
		_status.text = str(preview.get("error", "The selected force cannot be dispatched."))
		return
	var zone_id: String = ""
	if _combine_teams.button_pressed:
		var selected_zone: ZoneDefinition = _combined_zone.get_selected_metadata() as ZoneDefinition
		zone_id = str(selected_zone.zone_id)
	var warning: String = "\n\nHeroes may be downed and stranded; rescue is required before any permanent loss decision."
	var run_text: String = "Repeat until stopped" if _total_runs() == 0 else "%d run(s) per order" % _total_runs()
	var team_lines: PackedStringArray = []
	for preset: Dictionary in presets:
		var team_zone_id: String = zone_id if _combine_teams.button_pressed else str(preset.get("zone_id", ""))
		var team_zone: ZoneDefinition = ZoneDefinition.definition_for(StringName(team_zone_id))
		team_lines.append("%s → %s" % [str(preset.get("name", "Unnamed team")), team_zone.display_name if team_zone != null else "Unknown zone"])
	var route_label: String = "Route minimum" if _combine_teams.button_pressed else "Longest route minimum"
	_ask("Dispatch %d hero(es) in %d %s?\n%s\n%s: %s\nForecast: %s\n%s%s" % [
		int(preview.get("hero_count", 0)), 1 if _combine_teams.button_pressed else presets.size(),
		"force" if _combine_teams.button_pressed else "order(s)",
		"\n".join(team_lines), route_label, _format_duration(float(preview.get("route_seconds", 0.0))), str(preview.get("reason", "Forecast unavailable.")), run_text, warning,
	], _do_dispatch_presets.bind(presets, _total_runs(), _combine_teams.button_pressed, zone_id, _battle_policies(), _battle_loadout()))


func _do_dispatch_presets(presets: Array[Dictionary], total_runs: int, combined: bool, combined_zone_id: String, policies: Dictionary, loadout: Dictionary) -> void:
	var successful: int = 0
	var failed: int = 0
	if combined:
		var preset_ids: Array[String] = []
		for preset: Dictionary in presets:
			preset_ids.append(str(preset.get("id", "")))
		if GameSession.dispatch_force(preset_ids, combined_zone_id, total_runs, policies, loadout).is_empty():
			failed = 1
		else:
			successful = 1
	else:
		for preset: Dictionary in presets:
			var order_id: String = GameSession.dispatch_force([str(preset.get("id", ""))], str(preset.get("zone_id", "")), total_runs, policies, loadout)
			if order_id.is_empty():
				failed += 1
			else:
				successful += 1
	_status.text = "Dispatched %d order(s); %d failed%s" % [successful, failed, ": %s" % GameSession.last_action_error if failed > 0 else "."]


func _on_expeditions_changed() -> void:
	_refresh_expeditions(false)
	_refresh_practice_options()
	# ig-0og.1: a live tick can start or end a revolt, and the Dispatch preview reads it.
	var in_revolt: bool = GameSession.is_in_revolt()
	if in_revolt != _was_in_revolt:
		_was_in_revolt = in_revolt
		_refresh_dispatch_summary()
	if _open_building == &"Reliquary":
		_refresh_lost_caches()


func _on_battle_changed(order_id: String) -> void:
	# Frequent battle pulses update that order's live status without rebuilding order structure.
	for child: Node in _order_cards.get_children():
		if str(child.get_meta("order_id", "")) == order_id:
			_update_order_card(child)
			return


func _refresh_supply_stock() -> void:
	var stock: Dictionary = GameSession.supplies
	_supply_stock.text = BattleState.supplies_text(stock)


func _refresh_incident_cards() -> void:
	var live_incident_ids: Array[String] = []
	for incident: Dictionary in GameSession.get_stranded_incidents():
		var incident_id: String = str(incident.get("id", ""))
		if incident_id.is_empty():
			continue
		live_incident_ids.append(incident_id)
		var panel: PanelContainer = _incident_panel(incident_id)
		if panel == null:
			panel = PanelContainer.new()
			panel.name = "Incident_%s" % incident_id.validate_node_name()
			panel.set_meta("incident_id", incident_id)
			panel.custom_minimum_size.y = 92.0
			_incident_cards.add_child(panel)
			var card_box := VBoxContainer.new()
			card_box.name = "Box"
			card_box.add_theme_constant_override("separation", 2)
			panel.add_child(card_box)
			var card_label := Label.new()
			card_label.name = "IncidentLabel"
			card_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			card_label.add_theme_color_override("font_color", Color("E8AAA0"))
			card_box.add_child(card_label)
			var card_actions := HBoxContainer.new()
			card_actions.name = "Actions"
			card_box.add_child(card_actions)
			var card_start := Button.new()
			card_start.name = "StartWindow"
			card_start.text = "Start rescue window"
			card_start.pressed.connect(_on_start_stranded_window_pressed.bind(incident_id))
			card_actions.add_child(card_start)
			var card_preset := OptionButton.new()
			card_preset.name = "RescueTeam"
			card_preset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			card_actions.add_child(card_preset)
			var card_dispatch := Button.new()
			card_dispatch.name = "DispatchRescue"
			card_dispatch.text = "Dispatch rescue"
			card_dispatch.pressed.connect(_on_dispatch_rescue_pressed.bind(incident_id, card_preset))
			card_actions.add_child(card_dispatch)
			var card_watch := Button.new()
			card_watch.name = "WatchRescue"
			card_watch.text = "Watch rescue"
			card_watch.pressed.connect(_on_watch_incident_rescue_pressed.bind(incident_id))
			card_actions.add_child(card_watch)
			var card_abandon := Button.new()
			card_abandon.name = "Abandon"
			card_abandon.text = "Abandon"
			card_abandon.pressed.connect(_on_abandon_incident_pressed.bind(incident_id))
			card_actions.add_child(card_abandon)
		var box: VBoxContainer = panel.get_node("Box") as VBoxContainer
		var hero_names: PackedStringArray = []
		for hero_id: String in _string_array(incident.get("hero_ids", [])):
			var hero: Hero = GameSession.hero_by_id(hero_id)
			hero_names.append(hero.hero_name if hero != null else hero_id)
		var zone: ZoneDefinition = ZoneDefinition.definition_for(StringName(str(incident.get("zone_id", ""))))
		var label: Label = box.get_node("IncidentLabel") as Label
		var window_status: String = "paused · awaiting review" if bool(incident.get("paused", false)) else "window %s remaining" % _format_duration(float(incident.get("remaining_seconds", 0.0)))
		if bool(incident.get("expiry_pending", false)):
			window_status = "window ended · current rescue may finish"
		label.text = "%s · %d heroes stranded · %s\n%s" % [zone.display_name if zone != null else "Unknown zone", hero_names.size(), window_status, ", ".join(hero_names)]
		var actions: HBoxContainer = box.get_node("Actions") as HBoxContainer
		var rescue_order_id: String = str(incident.get("active_rescue_order_id", ""))
		var active_rescue: bool = not rescue_order_id.is_empty()
		var start: Button = actions.get_node("StartWindow") as Button
		start.disabled = active_rescue or not bool(incident.get("paused", false))
		var preset_option: OptionButton = actions.get_node("RescueTeam") as OptionButton
		var ready_presets: Array[Dictionary] = []
		var signature_parts: PackedStringArray = []
		for preset: Dictionary in GameSession.team_presets:
			if _preset_status(preset) == "Ready":
				ready_presets.append(preset)
				signature_parts.append("%s:%s" % [str(preset.get("id", "")), str(preset.get("name", "Unnamed team"))])
		var ready_signature: String = "|".join(signature_parts)
		if str(preset_option.get_meta("ready_signature", "")) != ready_signature:
			var selected_preset_id: String = ""
			if preset_option.selected >= 0:
				var prior_preset: Dictionary = preset_option.get_item_metadata(preset_option.selected) as Dictionary
				selected_preset_id = str(prior_preset.get("id", ""))
			preset_option.clear()
			var restored_index: int = -1
			for preset: Dictionary in ready_presets:
				preset_option.add_item(str(preset.get("name", "Unnamed team")))
				preset_option.set_item_metadata(preset_option.item_count - 1, preset)
				if str(preset.get("id", "")) == selected_preset_id:
					restored_index = preset_option.item_count - 1
			preset_option.set_meta("ready_signature", ready_signature)
			if restored_index >= 0:
				preset_option.select(restored_index)
			elif preset_option.item_count > 0:
				preset_option.select(0)
		var dispatch: Button = actions.get_node("DispatchRescue") as Button
		var expired: bool = not bool(incident.get("paused", false)) and float(incident.get("remaining_seconds", 0.0)) <= 0.0
		dispatch.disabled = active_rescue or preset_option.item_count == 0 or expired or bool(incident.get("expiry_pending", false))
		var watch: Button = actions.get_node("WatchRescue") as Button
		watch.visible = active_rescue
		if active_rescue:
			watch.set_meta("order_id", rescue_order_id)
		var abandon: Button = actions.get_node("Abandon") as Button
		abandon.disabled = active_rescue
		abandon.set_meta("hero_names", ", ".join(hero_names))
	for child: Node in _incident_cards.get_children():
		if str(child.get_meta("incident_id", "")) not in live_incident_ids:
			child.queue_free()


func _incident_panel(incident_id: String) -> PanelContainer:
	for child: Node in _incident_cards.get_children():
		if str(child.get_meta("incident_id", "")) == incident_id:
			return child as PanelContainer
	return null


func _on_watch_incident_rescue_pressed(incident_id: String) -> void:
	for incident: Dictionary in GameSession.get_stranded_incidents():
		if str(incident.get("id", "")) == incident_id:
			var order_id: String = str(incident.get("active_rescue_order_id", ""))
			if not order_id.is_empty():
				_on_watch_battle_pressed(order_id)
			return


func _on_abandon_incident_pressed(incident_id: String) -> void:
	for incident: Dictionary in GameSession.get_stranded_incidents():
		if str(incident.get("id", "")) == incident_id:
			var hero_names: PackedStringArray = []
			for hero_id: String in _string_array(incident.get("hero_ids", [])):
				var hero: Hero = GameSession.hero_by_id(hero_id)
				hero_names.append(hero.hero_name if hero != null else hero_id)
			_on_abandon_stranded_pressed(incident_id, ", ".join(hero_names))
			return


func _on_start_stranded_window_pressed(incident_id: String) -> void:
	if GameSession.start_rescue_window(incident_id):
		_status.text = "Rescue window started."
	else:
		_status.text = GameSession.last_action_error
	_refresh_incident_cards()


func _on_dispatch_rescue_pressed(incident_id: String, preset_option: OptionButton) -> void:
	if preset_option.selected < 0:
		_status.text = "Choose a ready rescue team."
		return
	var preset: Dictionary = preset_option.get_selected_metadata() as Dictionary
	var order_id: String = GameSession.dispatch_rescue(incident_id, str(preset.get("id", "")), _battle_loadout())
	_status.text = "Rescue dispatched." if not order_id.is_empty() else GameSession.last_action_error
	_refresh_incident_cards()


func _on_abandon_stranded_pressed(incident_id: String, hero_names: String) -> void:
	_ask("Abandon %s? This permanently kills these heroes and loses their gear." % hero_names, _do_abandon_stranded.bind(incident_id))


func _do_abandon_stranded(incident_id: String) -> void:
	_status.text = "Incident abandoned." if GameSession.abandon_stranded(incident_id) else GameSession.last_action_error
	_refresh_incident_cards()


func _on_watch_battle_pressed(order_id: String) -> void:
	SceneRouter.prepare_battle(order_id)
	SceneRouter.go_to(SceneRouter.BATTLE)


func _on_preview_supply_pressed() -> void:
	var kind: String = str(_supply_kind.get_selected_metadata()) if _supply_kind.selected >= 0 else BattleState.SUPPLY_KINDS[0]
	_pending_bulk_plan = GameSession.preview_bulk_supplies(kind, int(_supply_quantity.value), int(_supply_reserve.value))
	_supply_preview.text = _format_bulk_plan(_pending_bulk_plan)
	%ConfirmSupply.disabled = not bool(_pending_bulk_plan.get("valid", false))


func _on_supply_input_changed(_index: int) -> void:
	_invalidate_supply_preview()


func _on_supply_quantity_changed(_value: float) -> void:
	_invalidate_supply_preview()


func _invalidate_supply_preview() -> void:
	_pending_bulk_plan.clear()
	_supply_preview.text = ""
	%ConfirmSupply.disabled = true


func _on_confirm_supply_pressed() -> void:
	if _pending_bulk_plan.is_empty() or not bool(_pending_bulk_plan.get("valid", false)):
		_status.text = "Preview a valid supply craft first."
		return
	_status.text = "Supply craft completed." if GameSession.commit_bulk_plan(_pending_bulk_plan) else GameSession.last_action_error
	_pending_bulk_plan.clear()
	_supply_preview.text = ""
	_refresh_supply_stock()


func _refresh_expeditions(force_rebuild: bool) -> void:
	var structure_parts: PackedStringArray = []
	var away_ids: Dictionary[String, bool] = {}
	for order: Dictionary in GameSession.expedition_orders:
		structure_parts.append("%s:%s:%s" % [str(order.get("id", "")), str(order.get("stop_requested", false)), str(order.get("phase", ""))])
		for hero_id: String in _string_array(order.get("hero_ids", [])):
			away_ids[hero_id] = true
	var structure_key: String = "|".join(structure_parts)
	if force_rebuild or structure_key != _order_structure_key:
		_order_structure_key = structure_key
		_rebuild_order_cards()
		_refresh_recent_returns()
	_update_order_cards()
	_refresh_incident_cards()
	_refresh_supply_stock()
	_expedition_counts.text = "%d active · %d heroes away" % [GameSession.expedition_orders.size(), away_ids.size()]
	_recovery_warning.visible = GameSession.recovery_clock_paused and not GameSession.lost_caches.is_empty()


func _rebuild_order_cards() -> void:
	# Out of the list now, not at the frame's end: a battle_changed before then must find the new card.
	for child: Node in _order_cards.get_children():
		_order_cards.remove_child(child)
		child.queue_free()
	for order: Dictionary in GameSession.expedition_orders:
		var panel := PanelContainer.new()
		panel.custom_minimum_size.y = 118.0
		panel.set_meta("order_id", str(order.get("id", "")))
		_order_cards.add_child(panel)
		var box := VBoxContainer.new()
		box.name = "Box"
		box.add_theme_constant_override("separation", 2)
		panel.add_child(box)
		var head := HBoxContainer.new()
		head.name = "Head"
		box.add_child(head)
		var title := Label.new()
		title.name = "Title"
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		title.clip_text = true
		title.add_theme_font_size_override("font_size", 18)
		head.add_child(title)
		var eta := Label.new()
		eta.name = "ETA"
		eta.add_theme_font_size_override("font_size", 22)
		eta.add_theme_color_override("font_color", Color("CBA76A"))
		head.add_child(eta)
		var zone := Label.new()
		zone.name = "Zone"
		zone.theme_type_variation = &"MutedLabel"
		box.add_child(zone)
		var progress := ProgressBar.new()
		progress.name = "Progress"
		progress.custom_minimum_size.y = 5.0
		progress.show_percentage = false
		var progress_fill := StyleBoxFlat.new()
		progress_fill.bg_color = Color("879B83")
		progress_fill.corner_radius_top_left = 2
		progress_fill.corner_radius_top_right = 2
		progress_fill.corner_radius_bottom_left = 2
		progress_fill.corner_radius_bottom_right = 2
		progress.add_theme_stylebox_override("fill", progress_fill)
		box.add_child(progress)
		var bottom := HBoxContainer.new()
		bottom.name = "Bottom"
		box.add_child(bottom)
		var details := Label.new()
		details.name = "Details"
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bottom.add_child(details)
		var stop := Button.new()
		stop.name = "Stop"
		stop.custom_minimum_size.x = 180.0
		stop.pressed.connect(_on_stop_order_pressed.bind(str(order.get("id", ""))))
		bottom.add_child(stop)
		var watch := Button.new()
		watch.name = "Watch"
		watch.text = "Watch"
		watch.pressed.connect(_on_watch_battle_pressed.bind(str(order.get("id", ""))))
		bottom.add_child(watch)


func _update_order_cards() -> void:
	for child: Node in _order_cards.get_children():
		_update_order_card(child)


func _update_order_card(child: Node) -> void:
	order_card_updates += 1
	var order: Dictionary = _order_by_id(str(child.get_meta("order_id", "")))
	if order.is_empty():
		return
	var box: VBoxContainer = child.get_node("Box") as VBoxContainer
	var title: Label = box.get_node("Head/Title") as Label
	var eta: Label = box.get_node("Head/ETA") as Label
	var zone_label: Label = box.get_node("Zone") as Label
	var progress: ProgressBar = box.get_node("Progress") as ProgressBar
	var details: Label = box.get_node("Bottom/Details") as Label
	var stop: Button = box.get_node("Bottom/Stop") as Button
	var watch: Button = box.get_node("Bottom/Watch") as Button
	title.text = str(order.get("team_name", "Unnamed team"))
	title.tooltip_text = title.text
	var zone: ZoneDefinition = ZoneDefinition.definition_for(StringName(str(order.get("zone_id", ""))))
	zone_label.text = zone.display_name if zone != null else "Missing zone"
	var remaining: float = float(order.get("remaining_seconds", 0.0))
	var duration: float = maxf(float(order.get("initial_duration_seconds", 1.0)), 0.001)
	eta.text = _format_duration(remaining)
	progress.value = clampf((duration - remaining) / duration * 100.0, 0.0, 100.0)
	var completed: int = int(order.get("runs_completed", 0))
	var total: int = int(order.get("total_runs", 0))
	var snapshot: Dictionary = GameSession.get_battle_snapshot(str(order.get("id", "")))
	var phase: String = str(snapshot.get("phase", ""))
	var route_minimum: float = float(snapshot.get("route_remaining_seconds", remaining))
	var alive_count: int = 0
	var downed_count: int = 0
	# Detached battle snapshots use a JSON-compatible Array of Dictionary actor rows.
	for actor_value: Variant in snapshot.get("actors", []) as Array:
		if not actor_value is Dictionary:
			continue
		var actor: Dictionary = actor_value as Dictionary
		if str(actor.get("faction", "")) != "ally":
			continue
		if str(actor.get("life", "")) == BattleActor.LIFE_ALIVE:
			alive_count += 1
		elif str(actor.get("life", "")) == BattleActor.LIFE_DOWNED:
			downed_count += 1
	var checkpoint_error: String = str(snapshot.get("checkpoint_error", ""))
	var command_error: String = str(snapshot.get("last_command_error", ""))
	var battle_status: String = "%s · %d alive · %d downed · route min %s" % [phase.capitalize(), alive_count, downed_count, _format_duration(route_minimum)] if not phase.is_empty() else ""
	if str(snapshot.get("status", "")) == "victory" and route_minimum > 0.0:
		battle_status = "Won · heading home · rewards in %s" % _format_duration(route_minimum)
	elif phase == "checking":
		battle_status = "Checking the next run"
	elif bool(snapshot.get("catching_up", false)):
		battle_status = "Catching up"
	var pending_error: String = checkpoint_error if not checkpoint_error.is_empty() else command_error
	details.text = "%s · %d stones · %d items · %d XP%s%s" % ["Run %d • repeating" % (completed + 1) if total == 0 else "Run %d of %d" % [mini(completed + 1, total), total], int(order.get("cumulative_stones", 0)), int(order.get("cumulative_items", 0)), int(order.get("cumulative_xp", 0)), "\n" + battle_status if not battle_status.is_empty() else "", "\nError: " + pending_error if not pending_error.is_empty() else ""]
	var stopping: bool = bool(order.get("stop_requested", false))
	stop.text = "Stopping after return" if stopping else "Stop after this run"
	stop.disabled = stopping
	watch.visible = phase == "fighting" or phase == "rescuing"
	watch.text = "Command" if phase == "fighting" or phase == "rescuing" else "Watch"


func _refresh_recent_returns() -> void:
	_recent_returns.clear()
	for index: int in range(GameSession.expedition_reports.size() - 1, -1, -1):
		var report: Dictionary = GameSession.expedition_reports[index]
		var casualties: Array[String] = _string_array(report.get("casualty_names", []))
		var casualty_text: String = " · Lost: %s" % ", ".join(casualties) if not casualties.is_empty() else ""
		_recent_returns.add_item("%s · %s · +%d stones, %d items, %d XP%s" % [str(report.get("team_name", "Team")), str(report.get("outcome", "returned")), int(report.get("stones_earned", 0)), int(report.get("items_earned", 0)), int(report.get("xp_earned", 0)), casualty_text])
		var hero_names: Array[String] = _string_array(report.get("hero_names", []))
		_recent_returns.set_item_tooltip(_recent_returns.item_count - 1, "%s\nOutcome: %s\nHeroes: %s\nRewards: %d stones, %d items, %d XP\nCasualties: %s\nStopped: %s\nCumulative: %d stones, %d items, %d XP\nRewards are already banked." % [
			str(report.get("team_name", "Team")), str(report.get("outcome", "returned")), ", ".join(hero_names) if not hero_names.is_empty() else "Unknown", int(report.get("stones_earned", 0)), int(report.get("items_earned", 0)), int(report.get("xp_earned", 0)), ", ".join(casualties) if not casualties.is_empty() else "None", str(report.get("stopped_reason", "completed")), int(report.get("cumulative_stones", 0)), int(report.get("cumulative_items", 0)), int(report.get("cumulative_xp", 0)),
		])


func _on_stop_order_pressed(order_id: String) -> void:
	GameSession.request_stop_expedition(order_id)
	_status.text = GameSession.last_action_error if not GameSession.last_action_error.is_empty() else "The team will stop after its current run."


func _refresh_recovery_team_options() -> void:
	_recovery_team_option.clear()
	for preset: Dictionary in GameSession.team_presets:
		if _preset_status(preset) != "Ready":
			continue
		_recovery_team_option.add_item(str(preset.get("name", "Unnamed team")))
		_recovery_team_option.set_item_metadata(_recovery_team_option.item_count - 1, preset)
	%Recover.disabled = _recovery_team_option.item_count == 0 or GameSession.lost_caches.is_empty()
	%Recover.tooltip_text = "Choose a ready saved team and one cache." if %Recover.disabled else ""
	_refresh_practice_options()


func _on_availability_filter_selected(index: int) -> void:
	_roster_availability_filter_index = index
	_refresh_roster()


func _on_favorites_only_toggled(_enabled: bool) -> void:
	_refresh_roster()


func _on_protection_filter_selected(index: int) -> void:
	_inventory_protection_filter_index = index
	_refresh_inventory()


func _on_favorite_item_toggled(enabled: bool) -> void:
	var selected: PackedInt32Array = _inventory_list.get_selected_items()
	if selected.size() != 1:
		return
	var item: Item = _inventory_list.get_item_metadata(selected[0]) as Item
	if item == null:
		return
	if not GameSession.set_item_favorite(item, enabled):
		_status.text = GameSession.last_action_error
		# An early refusal fires no roster refresh, so the box is put back to the live item here.
		_refresh_favorite_item_control()


func _on_favorite_hero_toggled(enabled: bool) -> void:
	var hero: Hero = _selected_hero()
	if hero == null:
		return
	if not GameSession.set_hero_favorite(hero, enabled):
		_status.text = GameSession.last_action_error
		_refresh_hero_detail()


func _on_start_recovery_window_pressed() -> void:
	if not GameSession.recovery_clock_paused:
		_status.text = "The recovery window is already running."
		return
	var minutes: int = ceili(GameSession.recovery_clock_seconds / 60.0)
	_ask("Review the listed losses, then start the recovery window?\n\nEach cache has about %d active minute(s), including the Reliquary effect." % minutes, _do_start_recovery_window)


func _do_start_recovery_window() -> void:
	GameSession.acknowledge_recovery_losses()
	_status.text = GameSession.last_action_error if GameSession.recovery_clock_paused else "Recovery clock started."


func _preset_by_id(preset_id: String) -> Dictionary:
	for preset: Dictionary in GameSession.team_presets:
		if str(preset.get("id", "")) == preset_id:
			return preset
	return {}


func _order_by_id(order_id: String) -> Dictionary:
	for order: Dictionary in GameSession.expedition_orders:
		if str(order.get("id", "")) == order_id:
			return order
	return {}


func _heroes_for_ids(hero_ids: Array[String]) -> Array[Hero]:
	var heroes: Array[Hero] = []
	for hero_id: String in hero_ids:
		var hero: Hero = GameSession.hero_by_id(hero_id)
		if hero != null:
			heroes.append(hero)
	return heroes


static func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for entry: Variant in value as Array:
			if entry is String:
				result.append(entry as String)
	return result


static func _format_duration(seconds: float) -> String:
	var total: int = maxi(ceili(seconds), 0)
	@warning_ignore("integer_division")
	return "%d:%02d" % [total / 60, total % 60]


func _on_recover_pressed() -> void:
	var selected_caches: PackedInt32Array = _lost_cache_list.get_selected_items()
	var cache: LostCache = null
	if selected_caches.size() == 1:
		cache = _lost_cache_list.get_item_metadata(selected_caches[0]) as LostCache
	var preset: Dictionary = _recovery_team_option.get_selected_metadata() as Dictionary if _recovery_team_option.selected >= 0 else {}
	var team: Array[Hero] = _heroes_for_ids(_string_array(preset.get("hero_ids", [])))
	# Recovery is the one action with no dry run — `recover_cache()` validates and mutates in the
	# same call. Its cheap refusals are re-checked here so a misclick still reports itself instead
	# of opening a dialog; the zone and power legs are deliberately left to `recover_cache()`, since
	# re-deriving team power here is how a preview and a payout start disagreeing.
	if cache == null:
		_status.text = "Select one lost cache to recover."
		return
	if team.is_empty():
		_status.text = "Choose an available saved team for recovery."
		return
	if team.size() > MAX_TEAM_SIZE:
		_status.text = "Select no more than 5 heroes for recovery."
		return
	var body_error: String = GameSession.body_refusal(team)
	if not body_error.is_empty():
		_status.text = body_error
		return
	for hero: Hero in team:
		if GameSession.is_hero_busy(hero):
			_status.text = "Recovery cannot start while a team member is away."
			return
		if Hero.definition_for(hero.def_id) == null:
			_status.text = "Recovery cannot start: every hero needs a valid archetype."
			return
	_ask(
		"Send %d hero(es) to recover %d item(s) from %s's cache?\n\n%s\n\nThis costs a turn, and recovered items can come back damaged." % [
			team.size(),
			cache.items.size(),
			cache.hero_name,
			", ".join(_hero_names(team)),
		],
		_do_recover.bind(cache, team),
	)


func _do_recover(cache: LostCache, team: Array[Hero]) -> void:
	var outcome: StringName = GameSession.recover_cache(cache, team, BALANCE)
	match outcome:
		GameSession.RECOVERY_COMPLETED:
			_status.text = "Recovered %d items from %s's cache." % [cache.items.size(), cache.hero_name]
		GameSession.RECOVERY_NO_CACHE:
			_status.text = "Select one lost cache to recover."
		GameSession.RECOVERY_INVALID_TEAM:
			if not GameSession.last_action_error.is_empty():
				_status.text = GameSession.last_action_error
			elif team.is_empty():
				_status.text = "Select at least one hero for recovery."
			elif team.size() > MAX_TEAM_SIZE:
				_status.text = "Select no more than 5 heroes for recovery."
			else:
				_status.text = "Recovery cannot start: every hero needs a valid archetype."
		GameSession.RECOVERY_MISSING_ZONE:
			_status.text = "Cannot recover cache: its zone definition is missing."
		GameSession.RECOVERY_INSUFFICIENT_POWER:
			_status.text = "Cannot recover cache: team power is below 50% of the zone recommendation."
