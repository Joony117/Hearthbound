class_name SkillPanel
extends PanelContainer
## One hero's skill bar (GAME_SPEC.md § Skills, "The bar"): every skill it knows in bar order, each
## with its mode and Up/Down to reorder, then the class skills still locked with the level that opens
## them. No slot limit: the list scrolls. Below the bar, the hero's chains (ig-gy0.5): a trigger skill and
## the steps that follow it. Every change goes through GameSession.set_skill_bar or set_skill_chains.

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
	_add_learning(hero)
	_add_chains(hero)


## What the hero can still learn (ig-gy0.7): each class skill it has not opened yet, with Teach (the Training Hall,
## for F parts); its class's book when one is owned; then the general skills, each with Teach and Use book. A
## refused button is disabled and its tooltip is GameSession's reason.
func _add_learning(hero: Hero) -> void:
	var level: int = Hero.skill_level(Hero.level_for(hero, BALANCE))
	var known: Array[AbilityDefinition] = Hero.known_skills(hero, BALANCE)
	var general: Array[AbilityDefinition] = []
	for skill: AbilityDefinition in BattleSimulation.ABILITIES.values():
		if skill in known:
			continue
		if skill.archetype == "general":
			general.append(skill)
		elif skill.archetype != str(hero.def_id):
			continue
		elif skill.book_only:
			if int(GameSession.skill_books.get(skill.skill_id, 0)) > 0:
				var row := HBoxContainer.new()
				row.name = "ClassBook_%s" % skill.skill_id
				row.add_child(_label("%s · class book" % skill.display_name, true))
				row.add_child(_book_button(hero, skill))
				_rows.add_child(row)
		elif skill.unlock_level > level:
			var locked := Label.new()
			locked.name = "Locked_%s" % skill.skill_id
			locked.theme_type_variation = &"MutedLabel"
			locked.text = "%s · opens at level %d" % [skill.display_name, skill.unlock_level]
			_rows.add_child(locked)
			_rows.add_child(_teach_button(hero, skill, "Teach_%s" % skill.skill_id))
	if general.is_empty():
		return
	_rows.add_child(_label("GENERAL · any class may learn these", false, "GeneralTitle"))
	for skill: AbilityDefinition in general:
		var row := HBoxContainer.new()
		row.name = "General_%s" % skill.skill_id
		row.add_child(_label("%s · tier %d" % [skill.display_name, skill.tier], true))
		row.add_child(_teach_button(hero, skill, "Teach"))
		row.add_child(_book_button(hero, skill))
		_rows.add_child(row)


func _label(text: String, expand: bool, node_name: String = "") -> Label:
	var label := Label.new()
	label.text = text
	if not node_name.is_empty():
		label.name = node_name
	if expand:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		label.theme_type_variation = &"MutedLabel"
	return label


func _teach_button(hero: Hero, skill: AbilityDefinition, node_name: String) -> Button:
	var plan: Dictionary = GameSession.preview_lesson(hero, skill.skill_id)
	var button: Button = _button(node_name, "Teach · %d F parts" % int(plan["cost"]), _on_learn.bind(skill.skill_id, false), not str(plan["refusal"]).is_empty())
	button.tooltip_text = str(plan["refusal"])
	return button


func _book_button(hero: Hero, skill: AbilityDefinition) -> Button:
	var refusal: String = GameSession.book_refusal(hero, skill.skill_id)
	var button: Button = _button("Book", "Use book (%d)" % int(GameSession.skill_books.get(skill.skill_id, 0)), _on_learn.bind(skill.skill_id, true), not refusal.is_empty())
	button.tooltip_text = refusal
	return button


## A failed save rolls the profile back (and replaces the Hero objects), so the hero is re-read by id.
func _on_learn(skill_id: String, from_book: bool) -> void:
	var learned: bool = GameSession.use_skill_book(_hero(), skill_id) if from_book else GameSession.teach_skill(_hero(), skill_id)
	_error.text = "" if learned else GameSession.last_action_error
	refresh()


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


## The chains under the bar: when the trigger fires, its steps follow in order; a step that cannot fire in
## skill_chain_step_timeout_seconds is skipped. One chain per trigger; a passive is neither.
func _add_chains(hero: Hero) -> void:
	var title := Label.new()
	title.name = "ChainsTitle"
	title.theme_type_variation = &"MutedLabel"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.text = "CHAINS · when the trigger fires, its steps follow in order. A step that cannot fire within %s s is skipped." % String.num(BALANCE.skill_chain_step_timeout_seconds)
	_rows.add_child(title)
	for index: int in hero.skill_chains.size():
		_rows.add_child(_chain_block(hero, index))
	_rows.add_child(_button("NewChain", "New chain", _on_chain_added, _free_trigger(hero) == null))


func _chain_block(hero: Hero, index: int) -> VBoxContainer:
	var chain: Dictionary = hero.skill_chains[index]
	var skills: Array[AbilityDefinition] = _chain_skills(hero)
	var block := VBoxContainer.new()
	block.name = "Chain_%s" % chain["trigger"]
	var head := HBoxContainer.new()
	head.name = "Head"
	block.add_child(head)
	var when := Label.new()
	when.text = "When"
	head.add_child(when)
	head.add_child(_skill_menu("Trigger", skills, chain["trigger"], _on_trigger_selected.bind(index)))
	head.add_child(_button("RemoveChain", "Remove chain", _on_chain_removed.bind(index)))
	var steps: Array = chain["then"]
	for step: int in steps.size():
		var row := HBoxContainer.new()
		row.name = "Step_%d" % step
		block.add_child(row)
		var then := Label.new()
		then.text = "Then %d" % (step + 1)
		row.add_child(then)
		row.add_child(_skill_menu("Skill", skills, steps[step], _on_step_selected.bind(index, step)))
		row.add_child(_button("Up", "▲", _on_step_moved.bind(index, step, -1), step == 0))
		row.add_child(_button("Down", "▼", _on_step_moved.bind(index, step, 1), step == steps.size() - 1))
		row.add_child(_button("Remove", "Remove", _on_step_removed.bind(index, step), steps.size() == 1))
	block.add_child(_button("AddStep", "Add step", _on_step_added.bind(index), steps.size() >= BALANCE.skill_chain_max_steps))
	return block


func _button(node_name: String, text: String, on_pressed: Callable, disabled: bool = false) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.disabled = disabled
	button.pressed.connect(on_pressed)
	return button


func _skill_menu(node_name: String, skills: Array[AbilityDefinition], current: String, on_selected: Callable) -> OptionButton:
	var menu := OptionButton.new()
	menu.name = node_name
	for index: int in skills.size():
		menu.add_item(skills[index].display_name)
		if str(skills[index].skill_id) == current:
			menu.select(index)
	menu.item_selected.connect(on_selected)
	return menu


## What a chain may use: every skill the hero knows but the passives.
func _chain_skills(hero: Hero) -> Array[AbilityDefinition]:
	var skills: Array[AbilityDefinition] = []
	for skill: AbilityDefinition in Hero.known_skills(hero, BALANCE):
		if skill.kind != "passive":
			skills.append(skill)
	return skills


## The first skill that triggers no chain yet, or null.
func _free_trigger(hero: Hero) -> AbilityDefinition:
	for skill: AbilityDefinition in _chain_skills(hero):
		if not hero.skill_chains.any(func(chain: Dictionary) -> bool: return chain["trigger"] == str(skill.skill_id)):
			return skill
	return null


func _chains() -> Array[Dictionary]:
	var chains: Array[Dictionary] = []
	for chain: Dictionary in _hero().skill_chains:
		chains.append({"trigger": chain["trigger"], "then": (chain["then"] as Array).duplicate()})
	return chains


func _skill_id_at(item: int) -> String:
	return str(_chain_skills(_hero())[item].skill_id)


func _on_chain_added() -> void:
	var hero: Hero = _hero()
	var trigger: AbilityDefinition = _free_trigger(hero)
	var step: AbilityDefinition = trigger
	for skill: AbilityDefinition in _chain_skills(hero):
		if skill != trigger:
			step = skill
			break
	var chains: Array[Dictionary] = _chains()
	chains.append({"trigger": str(trigger.skill_id), "then": [str(step.skill_id)]})
	_commit_chains(chains)


func _on_chain_removed(index: int) -> void:
	var chains: Array[Dictionary] = _chains()
	chains.remove_at(index)
	_commit_chains(chains)


func _on_trigger_selected(item: int, index: int) -> void:
	var chains: Array[Dictionary] = _chains()
	chains[index]["trigger"] = _skill_id_at(item)
	_commit_chains(chains)


func _on_step_selected(item: int, index: int, step: int) -> void:
	var chains: Array[Dictionary] = _chains()
	chains[index]["then"][step] = _skill_id_at(item)
	_commit_chains(chains)


func _on_step_moved(index: int, step: int, direction: int) -> void:
	var chains: Array[Dictionary] = _chains()
	var steps: Array = chains[index]["then"]
	var moved: Variant = steps[step]
	steps[step] = steps[step + direction]
	steps[step + direction] = moved
	_commit_chains(chains)


func _on_step_removed(index: int, step: int) -> void:
	var chains: Array[Dictionary] = _chains()
	(chains[index]["then"] as Array).remove_at(step)
	_commit_chains(chains)


func _on_step_added(index: int) -> void:
	var chains: Array[Dictionary] = _chains()
	(chains[index]["then"] as Array).append(str(_chain_skills(_hero())[0].skill_id))
	_commit_chains(chains)


## A failed save rolls the profile back, as for the bar: the chains are re-read by id.
func _commit_chains(chains: Array[Dictionary]) -> void:
	_error.text = "" if GameSession.set_skill_chains(_hero(), chains) else GameSession.last_action_error
	refresh()
