extends Node3D

const BALANCE: BalanceTable = preload("res://balance.tres")
const MAX_TEAM_SIZE: int = 5
const EXPEDITION_ZONES: Array[ZoneDefinition] = [
	preload("res://zones/defs/verdant_outskirts.tres"),
	preload("res://zones/defs/ashfall_reaches.tres"),
	preload("res://zones/defs/sundered_vault.tres"),
]

@onready var _roster_list: ItemList = %RosterList
@onready var _zone_option: OptionButton = %ZoneOption
@onready var _status: Label = %Status
@onready var _pause_menu: CanvasLayer = %PauseMenu


func _ready() -> void:
	GameSession.roster_changed.connect(_refresh_roster)
	GameSession.roster_changed.connect(_refresh_zone_unlocks)
	_refresh_roster()
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
	var outcome: StringName = Expedition.new().resolve(team, zone)
	match outcome:
		Expedition.OUTCOME_COMPLETED:
			_status.text = "%d-hero team cleared %s." % [team.size(), zone.display_name]
		Expedition.OUTCOME_RETREATED:
			_status.text = "%d-hero team retreated from %s." % [team.size(), zone.display_name]
		Expedition.OUTCOME_DEFEATED:
			_status.text = "The expedition to %s lost heroes. Gone for good." % zone.display_name
		Expedition.OUTCOME_INVALID_TEAM:
			_status.text = "Expedition cannot start: every hero needs an archetype."
