extends Node3D

const BALANCE: BalanceTable = preload("res://balance.tres")
const EXPEDITION_ZONE: ZoneDefinition = preload("res://zones/defs/verdant_outskirts.tres")

@onready var _roster_list: ItemList = %RosterList
@onready var _status: Label = %Status
@onready var _pause_menu: CanvasLayer = %PauseMenu


func _ready() -> void:
	GameSession.roster_changed.connect(_refresh_roster)
	_refresh_roster()
	_status.text = "Summon a hero, then send it out. It might not come back."


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_pause_menu.visible = not _pause_menu.visible
		get_viewport().set_input_as_handled()


func _refresh_roster() -> void:
	var selected := _roster_list.get_selected_items()
	var previous := selected[0] if not selected.is_empty() else -1

	_roster_list.clear()
	for hero: Hero in GameSession.roster:
		var archetype_name: String = Summon.archetype_label_for(hero.def_id)
		_roster_list.add_item("[%s]  %s — %s" % [hero.rank_label(BALANCE), hero.hero_name, archetype_name])
		_roster_list.set_item_metadata(_roster_list.item_count - 1, hero)

	if previous >= 0 and previous < _roster_list.item_count:
		_roster_list.select(previous)


func _on_summon_pressed() -> void:
	var hero := Summon.roll()
	GameSession.add_hero(hero)
	_status.text = "Summoned %s, rank %s." % [hero.hero_name, hero.rank_label(BALANCE)]


func _on_expedition_pressed() -> void:
	var selected := _roster_list.get_selected_items()
	if selected.is_empty():
		_status.text = "Select a hero first."
		return

	var hero := _roster_list.get_item_metadata(selected[0]) as Hero
	assert(hero != null)
	var team: Array[Hero] = [hero]
	var outcome := Expedition.new().resolve(team, EXPEDITION_ZONE)
	match outcome:
		Expedition.OUTCOME_COMPLETED:
			_status.text = "%s cleared Verdant Outskirts." % hero.hero_name
		Expedition.OUTCOME_RETREATED:
			_status.text = "%s retreated from Verdant Outskirts." % hero.hero_name
		Expedition.OUTCOME_DEFEATED:
			_status.text = "%s did not come back. Gone for good." % hero.hero_name
