extends Node3D

const BALANCE: BalanceTable = preload("res://balance.tres")
const MAX_TEAM_SIZE: int = 5
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
@onready var _turns: Label = %Turns
@onready var _lost_cache_list: ItemList = %LostCacheList
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

# Held between the press that asks and the press that confirms. The dialog is exclusive, so no
# second action can be queued while one is pending.
var _pending_action: Callable
var _slot_filter: int = -1
var _roster_min_rank: int = -1
var _inventory_min_rank: int = -1
# -1 is an OptionButton index sentinel, so it cannot collide with Hero.NO_ARCHETYPE_DEF_ID (&"").
var _roster_archetype_filter_index: int = -1


func _ready() -> void:
	GameSession.roster_changed.connect(_refresh_roster)
	GameSession.roster_changed.connect(_refresh_essence)
	GameSession.roster_changed.connect(_refresh_stones)
	GameSession.roster_changed.connect(_refresh_turns)
	GameSession.roster_changed.connect(_refresh_lost_caches)
	GameSession.roster_changed.connect(_refresh_inventory)
	GameSession.roster_changed.connect(_refresh_parts)
	GameSession.roster_changed.connect(_refresh_buildings)
	GameSession.roster_changed.connect(_refresh_equipped)
	GameSession.roster_changed.connect(_refresh_hero_detail)
	GameSession.roster_changed.connect(_refresh_zone_unlocks)
	_populate_rank_filter(_roster_rank_filter)
	_populate_rank_filter(_inventory_rank_filter)
	_populate_archetype_filter()
	_populate_slot_filter()
	_refresh_roster()
	_refresh_essence()
	_refresh_stones()
	_refresh_turns()
	_refresh_lost_caches()
	_refresh_inventory()
	_refresh_parts()
	_refresh_buildings()
	_refresh_equipped()
	_refresh_hero_detail()
	_populate_convert_ranks()
	_populate_zones()
	_refresh_zone_unlocks()
	_status.text = "Summon a hero, then send it out. It might not come back."
	_show_pending_arena_result()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_pause_menu.visible = not _pause_menu.visible
		get_viewport().set_input_as_handled()


func _refresh_roster() -> void:
	_refresh_hero_list(_roster_list)
	_refresh_hero_option(_target_option)


## Re-select by identity after the clear, so a hero that left the roster drops out of the selection
## instead of the row under it taking its place.
func _refresh_hero_list(list: ItemList) -> void:
	var selected_heroes: Array[Hero] = []
	for selected_index: int in list.get_selected_items():
		var selected_hero: Hero = list.get_item_metadata(selected_index) as Hero
		if selected_hero != null:
			selected_heroes.append(selected_hero)
	list.clear()
	for hero: Hero in GameSession.roster:
		if _roster_min_rank != -1 and (
			hero.rank != _roster_min_rank if _roster_exact_rank.button_pressed else hero.rank < _roster_min_rank
		):
			continue
		if _roster_archetype_filter_index != -1 and hero.def_id != StringName(Summon.ARCHETYPE_DEF_IDS[_roster_archetype_filter_index]):
			continue
		var archetype_name: String = Summon.archetype_label_for(hero.def_id)
		list.add_item("[%s]  %s — %s" % [hero.rank_label(BALANCE), hero.hero_name, archetype_name])
		var item_index: int = list.item_count - 1
		list.set_item_metadata(item_index, hero)
		list.set_item_tooltip(item_index, _hero_detail_text(hero))
		if selected_heroes.has(hero):
			list.select(item_index, false)


func _refresh_hero_option(option: OptionButton) -> void:
	var selected_hero: Hero = option.get_selected_metadata() as Hero if option.selected >= 0 else null
	option.clear()
	for hero: Hero in GameSession.roster:
		var archetype_name: String = Summon.archetype_label_for(hero.def_id)
		option.add_item("[%s]  %s — %s" % [hero.rank_label(BALANCE), hero.hero_name, archetype_name])
		option.set_item_metadata(option.item_count - 1, hero)
	# Only TargetOption auto-selects index 0 on a cleared button. Re-selecting by identity after
	# the loop is what stops a sacrificed hero's target silently retargeting whoever took its place.
	option.select(GameSession.roster.find(selected_hero))


func _refresh_essence() -> void:
	_essence.text = "Essence: %d" % GameSession.essence


func _refresh_stones() -> void:
	_stones.text = "Summon Stones: %d" % GameSession.stones
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
	for cache: LostCache in GameSession.lost_caches:
		var zone: ZoneDefinition = ZoneDefinition.definition_for(cache.zone_id)
		var zone_name: String = (
			zone.display_name
			if zone != null
			else "[Missing definition: %s]" % cache.zone_id
		)
		var turns_remaining: int = LostCache.turns_remaining(
			cache,
			GameSession.turns,
			reliquary_level,
			BALANCE,
		)
		_lost_cache_list.add_item("%s — %s — %d items — %d turns remaining" % [
			cache.hero_name,
			zone_name,
			cache.items.size(),
			turns_remaining,
		])
		var item_index: int = _lost_cache_list.item_count - 1
		_lost_cache_list.set_item_metadata(item_index, cache)
		if cache == selected_cache:
			_lost_cache_list.select(item_index)


func _refresh_inventory() -> void:
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
		var enhance_suffix: String = " +%d" % item.enhance_level if item.enhance_level != 0 else ""
		if definition == null:
			_inventory_list.add_item("%s [Missing definition: %s]%s" % [item.rank_label(BALANCE), item.def_id, enhance_suffix])
		else:
			_inventory_list.add_item("%s %s%s" % [item.rank_label(BALANCE), definition.display_name, enhance_suffix])
		var item_index: int = _inventory_list.item_count - 1
		_inventory_list.set_item_metadata(item_index, item)
		_inventory_list.set_item_tooltip(item_index, _inventory_tooltip_text(item, definition))


func _inventory_tooltip_text(item: Item, definition: EquipmentDefinition) -> String:
	var forge_level: int = GameSession.building_levels[1]
	var enhance_level: int = Item.clamped_enhance_level(item, BALANCE)
	var enhance_cap: int = Item.compute_enhance_cap(forge_level, BALANCE)
	var salvage_yield: int = Item.compute_salvage_yield(item, forge_level, BALANCE)
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
	_circle_level.text = "Summoning Circle — Lv %d" % GameSession.building_levels[0]
	_forge_level.text = "Forge — Lv %d" % GameSession.building_levels[1]
	_training_hall_level.text = "Training Hall — Lv %d" % GameSession.building_levels[2]
	_sanctum_level.text = "Sanctum — Lv %d" % GameSession.building_levels[3]
	_reliquary_level.text = "Reliquary — Lv %d" % GameSession.building_levels[4]


func _refresh_equipped() -> void:
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
	var hero: Hero = _selected_hero()
	_hero_detail.text = "" if hero == null else _hero_detail_text(hero)


func _hero_detail_text(hero: Hero) -> String:
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


func _selected_hero() -> Hero:
	var selected: PackedInt32Array = _roster_list.get_selected_items()
	if selected.size() != 1:
		return null
	var hero: Hero = _roster_list.get_item_metadata(selected[0]) as Hero
	assert(hero != null)
	return hero


func _populate_zones() -> void:
	_zone_option.clear()
	for zone: ZoneDefinition in EXPEDITION_ZONES:
		_zone_option.add_item(zone.display_name)
		_zone_option.set_item_metadata(_zone_option.item_count - 1, zone)


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


func _refresh_zone_unlocks() -> void:
	for zone_index: int in _zone_option.item_count:
		var zone: ZoneDefinition = _zone_option.get_item_metadata(zone_index) as ZoneDefinition
		assert(zone != null)
		_zone_option.set_item_disabled(
			zone_index,
			not is_zone_unlocked(zone.zone_id, GameSession.cleared_zone_ids),
		)


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


func _on_summon_pressed() -> void:
	var hero: Hero = Summon.roll(GameSession.building_levels[0])
	if GameSession.summon_hero(hero, BALANCE):
		_status.text = "Summoned %s, rank %s." % [hero.hero_name, hero.rank_label(BALANCE)]
	else:
		_status.text = "Need %d Summon Stones, have %d." % [BALANCE.summon_pull_cost, GameSession.stones]


func _ask(prompt: String, action: Callable) -> void:
	_pending_action = action
	_confirm_dialog.dialog_text = prompt
	_confirm_dialog.popup_centered()


func _on_confirm_dialog_confirmed() -> void:
	var action: Callable = _pending_action
	_pending_action = Callable()
	if action.is_valid():
		action.call()


func _on_sacrifice_pressed() -> void:
	var fodders: Array[Hero] = []
	for selected_index: int in _roster_list.get_selected_items():
		var fodder: Hero = _roster_list.get_item_metadata(selected_index) as Hero
		if fodder != null:
			fodders.append(fodder)
	var target: Hero = _target_option.get_selected_metadata() as Hero if _target_option.selected >= 0 else null
	if fodders.is_empty() or target == null:
		_status.text = "Select both a fodder hero and a target hero."
		return
	var sanctum_level: int = clampi(GameSession.building_levels[3], 0, BALANCE.summoning_circle_level_cap)
	var essence_yield: int = 0
	var fodder_names: PackedStringArray = []
	for fodder: Hero in fodders:
		if fodder == target:
			_status.text = "A hero cannot be sacrificed into itself."
			return
		if not GameSession.roster.has(fodder):
			_status.text = "Cannot sacrifice: %s is no longer in the roster." % fodder.hero_name
			return
		if not fodder.equipped.is_empty():
			_status.text = "Unequip %s before sacrificing it." % fodder.hero_name
			return
		essence_yield += Hero.compute_essence_yield(fodder, target, BALANCE, sanctum_level)
		fodder_names.append("[%s] %s" % [fodder.rank_label(BALANCE), fodder.hero_name])
	var fodder_text: String = ", ".join(fodder_names)
	var destruction_text: String = fodders[0].hero_name if fodders.size() == 1 else "%d heroes" % fodders.size()
	_ask(
		"Sacrifice %s into [%s] %s for %d essence?\n\n%s %s destroyed permanently." % [
			fodder_text,
			target.rank_label(BALANCE),
			target.hero_name,
			essence_yield,
			destruction_text,
			"is" if fodders.size() == 1 else "are",
		],
		_do_sacrifice.bind(fodders, target),
	)


func _do_sacrifice(fodders: Array[Hero], target: Hero) -> void:
	var sanctum_level: int = clampi(GameSession.building_levels[3], 0, BALANCE.summoning_circle_level_cap)
	var sacrificed_count: int = 0
	var credited_essence: int = 0
	for fodder: Hero in fodders:
		var essence_yield: int = Hero.compute_essence_yield(fodder, target, BALANCE, sanctum_level)
		if GameSession.sacrifice_hero(fodder, target, BALANCE):
			sacrificed_count += 1
			credited_essence += essence_yield
	if fodders.size() == 1 and sacrificed_count == 1:
		_status.text = "Sacrificed %s for %d essence." % [fodders[0].hero_name, credited_essence]
	elif sacrificed_count == fodders.size():
		_status.text = "Sacrificed %d heroes for %d essence." % [sacrificed_count, credited_essence]
	else:
		_status.text = "Sacrificed %d of %d heroes for %d essence." % [sacrificed_count, fodders.size(), credited_essence]


func _on_rank_up_pressed() -> void:
	var hero: Hero = _selected_hero()
	if hero == null:
		_status.text = "Select exactly one hero to rank up."
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
	else:
		_status.text = "Cannot rank up the selected hero."


func _on_roster_list_multi_selected(_index: int, _selected: bool) -> void:
	_refresh_equipped()
	_refresh_hero_detail()


func _on_select_all_roster_pressed() -> void:
	for item_index: int in _roster_list.item_count:
		_roster_list.select(item_index, false)
	_refresh_equipped()
	_refresh_hero_detail()
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


func _on_select_all_inventory_pressed() -> void:
	for item_index: int in _inventory_list.item_count:
		_inventory_list.select(item_index, false)
	_status.text = "Selected %d items." % _inventory_list.item_count


func _on_equip_pressed() -> void:
	var hero: Hero = _selected_hero()
	if hero == null:
		_status.text = "Select exactly one hero first."
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
	var selected: PackedInt32Array = _inventory_list.get_selected_items()
	if selected.size() < 1:
		_status.text = "Select at least one inventory item."
		return
	var items: Array[Item] = []
	var parts_by_rank: Array[int] = []
	parts_by_rank.resize(BALANCE.rank_names.size())
	for selected_index: int in selected:
		var item: Item = _inventory_list.get_item_metadata(selected_index) as Item
		if item == null:
			continue
		items.append(item)
		var rank_index: int = clampi(item.rank, 0, parts_by_rank.size() - 1)
		parts_by_rank[rank_index] += Item.compute_salvage_yield(item, GameSession.building_levels[1], BALANCE)
	var parts_text: PackedStringArray = []
	for rank_index: int in parts_by_rank.size():
		if parts_by_rank[rank_index] > 0:
			parts_text.append("%d %s parts" % [parts_by_rank[rank_index], BALANCE.rank_names[rank_index]])
	assert(not items.is_empty())
	_ask(
		"Salvage %d %s into %s?\n\n%s %s destroyed." % [
			items.size(), "item" if items.size() == 1 else "items", ", ".join(parts_text),
			"The item" if items.size() == 1 else "The items", "is" if items.size() == 1 else "are",
		], _do_salvage.bind(items, parts_by_rank),
	)


func _do_salvage(items: Array[Item], parts_by_rank: Array[int]) -> void:
	for item: Item in items:
		GameSession.salvage_item(item, BALANCE)
	var parts_text: PackedStringArray = []
	for rank_index: int in parts_by_rank.size():
		if parts_by_rank[rank_index] > 0:
			parts_text.append("%d %s parts" % [parts_by_rank[rank_index], BALANCE.rank_names[rank_index]])
	if items.size() == 1:
		var rank_index: int = clampi(items[0].rank, 0, BALANCE.rank_names.size() - 1)
		_status.text = "Salvaged %s item into %s." % [BALANCE.rank_names[rank_index], parts_text[0]]
	else:
		_status.text = "Salvaged %d items into %s." % [items.size(), ", ".join(parts_text)]


func _on_enhance_pressed() -> void:
	var selected: PackedInt32Array = _inventory_list.get_selected_items()
	if selected.size() != 1:
		_status.text = "Select exactly one inventory item."
		return
	var item: Item = _inventory_list.get_item_metadata(selected[0]) as Item
	assert(item != null)
	if not GameSession.inventory.has(item):
		_status.text = "Cannot enhance: item is no longer in inventory."
		return
	var enhance_level: int = clampi(item.enhance_level, 0, BALANCE.forge_enhance_cap_max)
	var forge_level: int = clampi(GameSession.building_levels[1], 0, BALANCE.summoning_circle_level_cap)
	var enhance_cap: int = mini(BALANCE.forge_enhance_cap_max, forge_level * BALANCE.forge_enhance_cap_per_level)
	if enhance_cap <= 0:
		_status.text = "Cannot enhance: build the Forge first."
		return
	if enhance_level >= enhance_cap:
		_status.text = "Cannot enhance: item is already at the +%d cap." % enhance_cap
		return
	var rank_index: int = clampi(item.rank, 0, GameSession.parts.size() - 1)
	var cost: int = 2 + enhance_level
	var rank_label: String = BALANCE.rank_names[rank_index]
	if GameSession.parts[rank_index] < cost:
		_status.text = "Cannot enhance: need %d %s parts." % [cost, rank_label]
		return
	GameSession.enhance_item(item, BALANCE)
	var definition: EquipmentDefinition = Item.definition_for(item.def_id)
	var item_name: String = definition.display_name if definition != null else str(item.def_id)
	_status.text = "Enhanced %s to +%d for %d %s parts." % [item_name, item.enhance_level, cost, rank_label]


func _on_convert_pressed() -> void:
	var selected_rank: int = _convert_rank_option.get_item_metadata(_convert_rank_option.selected) as int
	var rank_label: String = BALANCE.rank_names[selected_rank]
	if GameSession.convert_parts(selected_rank):
		_status.text = "Converted 3 %s parts into 1 %s part." % [rank_label, BALANCE.rank_names[selected_rank + 1]]
	else:
		_status.text = "Need 3 %s parts to convert." % rank_label


func _on_upgrade_circle_pressed() -> void:
	_upgrade_building(0, "Summoning Circle", GameSession.upgrade_building(0, BALANCE))


func _on_upgrade_forge_pressed() -> void:
	_upgrade_building(1, "Forge", GameSession.upgrade_building(1, BALANCE))


func _on_upgrade_training_hall_pressed() -> void:
	_upgrade_building(2, "Training Hall", GameSession.upgrade_building(2, BALANCE))


func _on_upgrade_sanctum_pressed() -> void:
	_upgrade_building(3, "Sanctum", GameSession.upgrade_building(3, BALANCE))


func _on_upgrade_reliquary_pressed() -> void:
	_upgrade_building(4, "Reliquary", GameSession.upgrade_building(4, BALANCE))


func _upgrade_building(index: int, building_name: String, upgraded: bool) -> void:
	var level: int = clampi(GameSession.building_levels[index], 0, BALANCE.summoning_circle_level_cap)
	if upgraded:
		_status.text = "Upgraded %s to Lv %d for %d %s parts." % [building_name, level, 10 * (level + 1), BALANCE.rank_names[clampi(level - 1, 0, GameSession.parts.size() - 1)]]
		return
	if level >= BALANCE.summoning_circle_level_cap:
		_status.text = "%s is already at the Lv %d cap." % [building_name, BALANCE.summoning_circle_level_cap]
		return
	var rank_index: int = clampi(level, 0, GameSession.parts.size() - 1)
	var cost: int = 10 * (level + 2)
	_status.text = "Cannot upgrade %s: need %d %s parts." % [building_name, cost, BALANCE.rank_names[rank_index]]


func _on_unequip_pressed() -> void:
	var hero: Hero = _selected_hero()
	if hero == null:
		_status.text = "Select exactly one hero first."
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
	var selected: PackedInt32Array = _roster_list.get_selected_items()
	if selected.is_empty():
		_status.text = "Select a hero first."
		return
	if selected.size() > MAX_TEAM_SIZE:
		_status.text = "Select no more than 5 heroes."
		return

	var team: Array[Hero] = []
	for selected_index: int in selected:
		var hero: Hero = _roster_list.get_item_metadata(selected_index) as Hero
		assert(hero != null)
		team.append(hero)
	var zone: ZoneDefinition = _zone_option.get_item_metadata(_zone_option.selected) as ZoneDefinition
	assert(zone != null)
	assert(is_zone_unlocked(zone.zone_id, GameSession.cleared_zone_ids))
	_ask(
		"Send %d hero(es) to %s?\n\n%s\n\nHeroes that fall are gone for good." % [
			team.size(),
			zone.display_name,
			", ".join(_hero_names(team)),
		],
		_do_expedition.bind(team, zone),
	)


func _hero_names(team: Array[Hero]) -> PackedStringArray:
	var names: PackedStringArray = []
	for hero: Hero in team:
		names.append("[%s] %s" % [hero.rank_label(BALANCE), hero.hero_name])
	return names


func _do_expedition(team: Array[Hero], zone: ZoneDefinition) -> void:
	var expedition := Expedition.new()
	var outcome: StringName = expedition.resolve(team, zone)
	match outcome:
		Expedition.OUTCOME_COMPLETED:
			var definition: EquipmentDefinition = Item.definition_for(expedition.loot.def_id)
			if definition == null:
				_status.text = "%d-hero team cleared %s, but its item definition is missing." % [team.size(), zone.display_name]
			else:
				_status.text = "%d-hero team cleared %s. Found %s %s." % [
					team.size(), zone.display_name, expedition.loot.rank_label(BALANCE), definition.display_name,
				]
		Expedition.OUTCOME_RETREATED:
			_status.text = "%d-hero team retreated from %s." % [team.size(), zone.display_name]
		Expedition.OUTCOME_DEFEATED:
			_status.text = "The expedition to %s lost heroes. Gone for good." % zone.display_name
		Expedition.OUTCOME_INVALID_TEAM:
			_status.text = "Expedition cannot start: every hero needs an archetype."


func _on_enter_arena_pressed() -> void:
	var selected: PackedInt32Array = _roster_list.get_selected_items()
	if selected.is_empty():
		_status.text = "Select a hero first."
		return
	if selected.size() > 1:
		_status.text = "Select exactly one hero for the arena."
		return
	var hero: Hero = _roster_list.get_item_metadata(selected[0]) as Hero
	assert(hero != null)
	if Hero.definition_for(hero.def_id) == null:
		_status.text = "Arena cannot start: the selected hero needs a valid archetype."
		return
	var zone: ZoneDefinition = _zone_option.get_item_metadata(_zone_option.selected) as ZoneDefinition
	assert(zone != null)
	assert(is_zone_unlocked(zone.zone_id, GameSession.cleared_zone_ids))
	var team: Array[Hero] = [hero]
	var wave: Wave = Wave.from_zone(zone, 0)
	SceneRouter.prepare_arena(team, wave)
	SceneRouter.go_to(SceneRouter.ARENA)


func _show_pending_arena_result() -> void:
	var result: CombatResult = SceneRouter.take_arena_result()
	if result == null:
		return
	if not result.survivors.is_empty():
		var survivor: Hero = result.survivors[0]
		_status.text = "Arena victory: %s survived with %d/%d HP." % [
			survivor.hero_name,
			roundi(result.hp_after[survivor]),
			roundi(result.maximum_hp[survivor]),
		]
		return
	assert(result.dead_heroes.size() == 1)
	# The arena is a feel prototype and its CombatResult is display-only, so a "dead" hero here is
	# still on the roster - Expedition is the sole permadeath writer (docs/DECISIONS.md 2026-08-11).
	_status.text = "Arena defeat: %s went down. Practice only, nothing lost." % result.dead_heroes[0].hero_name


func _on_recover_pressed() -> void:
	var selected_caches: PackedInt32Array = _lost_cache_list.get_selected_items()
	var cache: LostCache = null
	if selected_caches.size() == 1:
		cache = _lost_cache_list.get_item_metadata(selected_caches[0]) as LostCache
	var selected_heroes: PackedInt32Array = _roster_list.get_selected_items()
	var team: Array[Hero] = []
	for selected_index: int in selected_heroes:
		var hero: Hero = _roster_list.get_item_metadata(selected_index) as Hero
		if hero != null:
			team.append(hero)
	# Recovery is the one action with no dry run — `recover_cache()` validates and mutates in the
	# same call. Its cheap refusals are re-checked here so a misclick still reports itself instead
	# of opening a dialog; the zone and power legs are deliberately left to `recover_cache()`, since
	# re-deriving team power here is how a preview and a payout start disagreeing.
	if cache == null:
		_status.text = "Select one lost cache to recover."
		return
	if team.is_empty():
		_status.text = "Select at least one hero for recovery."
		return
	if team.size() > MAX_TEAM_SIZE:
		_status.text = "Select no more than 5 heroes for recovery."
		return
	for hero: Hero in team:
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
			if team.is_empty():
				_status.text = "Select at least one hero for recovery."
			elif team.size() > MAX_TEAM_SIZE:
				_status.text = "Select no more than 5 heroes for recovery."
			else:
				_status.text = "Recovery cannot start: every hero needs a valid archetype."
		GameSession.RECOVERY_MISSING_ZONE:
			_status.text = "Cannot recover cache: its zone definition is missing."
		GameSession.RECOVERY_INSUFFICIENT_POWER:
			_status.text = "Cannot recover cache: team power is below 50% of the zone recommendation."
