extends Node3D

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
		_roster_list.add_item("[%s]  %s" % [hero.rank_label(), hero.hero_name])

	if previous >= 0 and previous < _roster_list.item_count:
		_roster_list.select(previous)


func _on_summon_pressed() -> void:
	var hero := Summon.roll()
	GameSession.add_hero(hero)
	_status.text = "Summoned %s, rank %s." % [hero.hero_name, hero.rank_label()]


func _on_expedition_pressed() -> void:
	var selected := _roster_list.get_selected_items()
	if selected.is_empty():
		_status.text = "Select a hero first."
		return

	var hero: Hero = GameSession.roster[selected[0]]
	if Expedition.survives():
		_status.text = "%s came back." % hero.hero_name
	else:
		_status.text = "%s did not come back. Gone for good." % hero.hero_name
		GameSession.kill_hero(hero)
