extends Node3D

const BALANCE: BalanceTable = preload("res://balance.tres")
const MAX_TEAM_SIZE: int = 5
const EXPEDITION_ZONES: Array[ZoneDefinition] = [
	preload("res://zones/defs/verdant_outskirts.tres"),
	preload("res://zones/defs/ashfall_reaches.tres"),
	preload("res://zones/defs/sundered_vault.tres"),
]

@onready var _roster_list: ItemList = %RosterList
@onready var _inventory_list: ItemList = %InventoryList
@onready var _parts: Label = %Parts
@onready var _equipped_list: ItemList = %EquippedList
@onready var _zone_option: OptionButton = %ZoneOption
@onready var _status: Label = %Status
@onready var _pause_menu: CanvasLayer = %PauseMenu


func _ready() -> void:
	GameSession.roster_changed.connect(_refresh_roster)
	GameSession.roster_changed.connect(_refresh_inventory)
	GameSession.roster_changed.connect(_refresh_parts)
	GameSession.roster_changed.connect(_refresh_equipped)
	GameSession.roster_changed.connect(_refresh_zone_unlocks)
	_refresh_roster()
	_refresh_inventory()
	_refresh_parts()
	_refresh_equipped()
	_populate_zones()
	_refresh_zone_unlocks()
	_status.text = "Summon a hero, then send it out. It might not come back."


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_pause_menu.visible = not _pause_menu.visible
		get_viewport().set_input_as_handled()


func _refresh_roster() -> void:
	var selected_heroes: Array[Hero] = []
	for selected_index: int in _roster_list.get_selected_items():
		var selected_hero: Hero = _roster_list.get_item_metadata(selected_index) as Hero
		if selected_hero != null:
			selected_heroes.append(selected_hero)

	_roster_list.clear()
	for hero: Hero in GameSession.roster:
		var archetype_name: String = Summon.archetype_label_for(hero.def_id)
		_roster_list.add_item("[%s]  %s — %s" % [hero.rank_label(BALANCE), hero.hero_name, archetype_name])
		var item_index: int = _roster_list.item_count - 1
		_roster_list.set_item_metadata(item_index, hero)
		if selected_heroes.has(hero):
			_roster_list.select(item_index, false)


func _refresh_inventory() -> void:
	_inventory_list.clear()
	for item: Item in GameSession.inventory:
		var definition: EquipmentDefinition = Item.definition_for(item.def_id)
		if definition == null:
			_inventory_list.add_item("%s [Missing definition: %s]" % [item.rank_label(BALANCE), item.def_id])
		else:
			_inventory_list.add_item("%s %s" % [item.rank_label(BALANCE), definition.display_name])
		_inventory_list.set_item_metadata(_inventory_list.item_count - 1, item)


func _refresh_parts() -> void:
	var entries: PackedStringArray = []
	for rank_index: int in GameSession.parts.size():
		entries.append("%s: %d" % [BALANCE.rank_names[rank_index], GameSession.parts[rank_index]])
	_parts.text = "Parts  " + " | ".join(entries)


func _refresh_equipped() -> void:
	_equipped_list.clear()
	var hero: Hero = _selected_hero()
	if hero == null:
		return
	for slot: int in hero.equipped:
		assert(slot >= 0 and slot < EquipmentDefinition.Slot.size())
		var item: Item = hero.equipped[slot]
		assert(item != null)
		var slot_name: String = (EquipmentDefinition.Slot.keys()[slot] as String).capitalize()
		var definition: EquipmentDefinition = Item.definition_for(item.def_id)
		if definition == null:
			_equipped_list.add_item("%s %s [Missing definition: %s]" % [slot_name, item.rank_label(BALANCE), item.def_id])
		else:
			_equipped_list.add_item("%s %s %s" % [slot_name, item.rank_label(BALANCE), definition.display_name])
		_equipped_list.set_item_metadata(_equipped_list.item_count - 1, slot)


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
	var hero := Summon.roll()
	GameSession.add_hero(hero)
	_status.text = "Summoned %s, rank %s." % [hero.hero_name, hero.rank_label(BALANCE)]


func _on_roster_list_multi_selected(_index: int, _selected: bool) -> void:
	_refresh_equipped()


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
	if selected.size() != 1:
		_status.text = "Select exactly one inventory item."
		return
	var item: Item = _inventory_list.get_item_metadata(selected[0]) as Item
	assert(item != null)
	var rank_label: String = item.rank_label(BALANCE)
	GameSession.salvage_item(item)
	_status.text = "Salvaged %s item into 3 %s parts." % [rank_label, rank_label]


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
		_status.text = "Selected equipped item is no longer available."
		return
	var definition: EquipmentDefinition = Item.definition_for(item.def_id)
	GameSession.unequip_item(hero, slot)
	if definition == null:
		_status.text = "Unequipped item from %s." % hero.hero_name
	else:
		_status.text = "Unequipped %s %s from %s." % [item.rank_label(BALANCE), definition.display_name, hero.hero_name]


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
