class_name SkillPanel
extends PanelContainer
## One hero's skill bar (GAME_SPEC.md § Skills, "The bar"): every skill it knows in bar order, each
## with its mode and Up/Down to reorder, then the class skills still locked with the level that opens
## them. No slot limit: the list scrolls. Every change goes through GameSession.set_skill_bar.

const BALANCE: BalanceTable = preload("res://balance.tres")
const MODES: Array[String] = ["auto", "manual", "off"]
const MODE_TEXT: Array[String] = ["Auto", "Manual", "Off"]
const KIND_TEXT: Dictionary = {"passive": "Passive", "weaponskill": "Weaponskill", "ability": "Ability"}

var hero_id: String = ""
var _title: Label
var _error: Label
var _rows: VBoxContainer


func _init() -> void:
	var box := VBoxContainer.new()
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close := Button.new()
	close.name = "Close"
	close.text = "Close"
	close.pressed.connect(hide)
	head.add_child(close)
	_error = Label.new()
	_error.name = "Error"
	_error.theme_type_variation = &"MutedLabel"
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_error)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)


## Shows hero's bar, or hides the panel for null.
func show_hero(hero: Hero) -> void:
	hero_id = hero.instance_id if hero != null else ""
	_error.text = ""
	visible = hero != null
	refresh()


func refresh() -> void:
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var hero: Hero = _hero()
	if hero == null:
		hide()
		return
	_title.text = "SKILLS · %s" % hero.hero_name
	var bar: Array[Dictionary] = Hero.bar_for(hero, BALANCE)
	for index: int in bar.size():
		_rows.add_child(_row(bar, index))
	var level: int = maxi(Hero.level_for(hero, BALANCE), 1)
	for skill: AbilityDefinition in BattleSimulation.ABILITIES.values():
		if skill.archetype == str(hero.def_id) and not skill.book_only and skill.unlock_level > level:
			var locked := Label.new()
			locked.name = "Locked_%s" % skill.skill_id
			locked.theme_type_variation = &"MutedLabel"
			locked.text = "%s · opens at level %d" % [skill.display_name, skill.unlock_level]
			_rows.add_child(locked)


func _row(bar: Array[Dictionary], index: int) -> HBoxContainer:
	var skill: AbilityDefinition = BattleSimulation.ABILITIES[bar[index]["id"]]
	var row := HBoxContainer.new()
	row.name = "Skill_%s" % skill.skill_id
	var label := Label.new()
	label.text = "%d. %s (%s)" % [index + 1, skill.display_name, KIND_TEXT.get(skill.kind, skill.kind)]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	if skill.kind == "passive":
		var always := Label.new()
		always.name = "Mode"
		always.text = "Always on"
		always.theme_type_variation = &"MutedLabel"
		row.add_child(always)
	else:
		var mode := OptionButton.new()
		mode.name = "Mode"
		for text: String in MODE_TEXT:
			mode.add_item(text)
		mode.select(MODES.find(str(bar[index]["mode"])))
		mode.item_selected.connect(_on_mode_selected.bind(index))
		row.add_child(mode)
	for step: int in [-1, 1]:
		var move := Button.new()
		move.name = "Up" if step < 0 else "Down"
		move.text = "▲" if step < 0 else "▼"
		move.tooltip_text = "Higher priority" if step < 0 else "Lower priority"
		move.disabled = index + step < 0 or index + step >= bar.size()
		move.pressed.connect(_on_move_pressed.bind(index, step))
		row.add_child(move)
	return row


func _on_mode_selected(mode_index: int, index: int) -> void:
	var bar: Array[Dictionary] = Hero.bar_for(_hero(), BALANCE)
	bar[index]["mode"] = MODES[mode_index]
	_commit(bar)


func _on_move_pressed(index: int, step: int) -> void:
	var bar: Array[Dictionary] = Hero.bar_for(_hero(), BALANCE)
	var moved: Dictionary = bar[index]
	bar[index] = bar[index + step]
	bar[index + step] = moved
	_commit(bar)


## A failed save rolls the profile back (and replaces the Hero objects), so the bar is re-read by id.
func _commit(bar: Array[Dictionary]) -> void:
	_error.text = "" if GameSession.set_skill_bar(_hero(), bar) else GameSession.last_action_error
	refresh()


func _hero() -> Hero:
	for hero: Hero in GameSession.roster:
		if hero.instance_id == hero_id:
			return hero
	return null
