extends GutTest

## ig-gy0.3: a hero's skill bar is profile state (DECISIONS.md 2026-09-23 "Skills", items 3 and 4):
## saved on the Hero, derived when absent, fixed into the team snapshot at dispatch, and edited in
## the hub's skill panel.

const BALANCE: BalanceTable = preload("res://balance.tres")
const SIM = preload("res://combat/battle/battle_simulation.gd")
const KEPT: Array[String] = [SaveService.SAVE_PATH, SaveService.LEDGER_PATH]
const KNIGHT_1: Array[String] = ["knight_bulwark", "knight_rally", "knight_iron_cut", "knight_charge", "knight_ground_slam"]

var _originals: Dictionary = {}


func before_all() -> void:
	for path: String in KEPT:
		if FileAccess.file_exists(path):
			_originals[path] = FileAccess.get_file_as_bytes(path)


func after_all() -> void:
	SaveService.load_blocked = false
	GameSession.set("_save_deferred_depth", 0)
	for path: String in KEPT:
		if _originals.has(path):
			FileAccess.open(path, FileAccess.WRITE).store_buffer(_originals[path])
		elif FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func before_each() -> void:
	SaveService.load_blocked = false
	GameSession.set("_save_deferred_depth", 1)
	GameSession.from_dict({"roster": []})
	GameSession.set("_save_deferred_depth", 0)


func after_each() -> void:
	var gut_layer: CanvasLayer = get_tree().root.find_child("GutLayer", true, false) as CanvasLayer
	if gut_layer != null:
		gut_layer.visible = true


func test_a_legacy_hero_without_the_keys_gets_the_derived_default_bar() -> void:
	var hero: Hero = Hero.from_dict({"instance_id": "hero:old", "name": "Old", "rank": 0, "level": 1, "def_id": "knight"})
	assert_eq(hero.skill_bar, [] as Array[Dictionary])
	assert_eq(Hero.bar_for(hero, BALANCE), _bar(KNIGHT_1, "auto"), "every known skill, auto, kit order")
	var again: Hero = Hero.from_dict(hero.to_dict())
	assert_eq(Hero.bar_for(again, BALANCE), _bar(KNIGHT_1, "auto"))
	assert_push_warning_count(0)


## Boundary #1: bar order and modes go to disk and come back; a legacy save without the keys loads.
func test_bar_order_and_modes_survive_a_real_disk_round_trip_and_a_legacy_save_loads() -> void:
	var hero: Hero = _knight("hero:k", 5)
	GameSession.add_hero(hero)
	var bar: Array[Dictionary] = [
		{"id": "knight_buckler_blow", "mode": "manual"}, {"id": "knight_follow_through", "mode": "off"},
		{"id": "knight_iron_cut", "mode": "auto"}, {"id": "knight_rally", "mode": "off"}, {"id": "knight_bulwark", "mode": "auto"},
		{"id": "knight_charge", "mode": "auto"}, {"id": "knight_ground_slam", "mode": "auto"},
	]
	assert_true(GameSession.set_skill_bar(hero, bar), GameSession.last_action_error)
	assert_string_contains(FileAccess.get_file_as_string(SaveService.SAVE_PATH), "knight_buckler_blow")
	_reload()
	assert_eq(Hero.bar_for(GameSession.roster[0], BALANCE), bar)

	var payload: Dictionary = GameSession.to_dict()
	for key: String in ["learned_skills", "skill_bar", "skill_chains"]:
		(payload["roster"][0] as Dictionary).erase(key)
	payload["version"] = SaveService.SAVE_VERSION
	FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE).store_string(JSON.stringify(payload))
	_reload()
	assert_false(SaveService.load_blocked, SaveService.load_block_reason)
	var ids: Array[String] = ["knight_bulwark", "knight_rally", "knight_iron_cut", "knight_follow_through", "knight_buckler_blow", "knight_charge", "knight_ground_slam"]
	assert_eq(Hero.bar_for(GameSession.roster[0], BALANCE), _bar(ids, "auto"), "the derived default")


func test_load_drops_bad_ids_and_modes_and_keeps_a_general_skill_on_any_class() -> void:
	var hero: Hero = Hero.from_dict({
		"instance_id": "hero:k", "name": "K", "rank": 0, "level": 1, "def_id": "knight",
		"learned_skills": ["general_brace", "mage_ember_bolt", "nope", "general_brace"],
		"skill_bar": [
			{"id": "mage_ember_bolt", "mode": "auto"}, {"id": "nope", "mode": "auto"}, {"id": "knight_buckler_blow", "mode": "auto"},
			{"id": "knight_rally", "mode": "sometimes"}, {"id": "knight_bulwark", "mode": "manual"}, "junk",
			{"id": "knight_iron_cut", "mode": "off"}, {"id": "knight_iron_cut", "mode": "auto"}, {"id": "general_brace", "mode": "manual"},
		],
		"skill_chains": [{"trigger": "knight_iron_cut", "then": ["knight_rally"]}, {"trigger": "knight_buckler_blow", "then": []}, {"trigger": "knight_iron_cut", "then": []}, "junk"],
	})
	assert_eq(hero.learned_skills, ["general_brace"] as Array[String])
	assert_eq(hero.skill_bar, [{"id": "knight_iron_cut", "mode": "off"}, {"id": "general_brace", "mode": "manual"}] as Array[Dictionary])
	assert_eq(hero.skill_chains, [{"trigger": "knight_iron_cut", "then": ["knight_rally"]}] as Array[Dictionary])
	assert_push_warning_count(13, "one per dropped entry: 3 learned, 7 bar, 3 chains (one known but empty)")
	assert_eq(Hero.bar_for(hero, BALANCE), [
		{"id": "knight_iron_cut", "mode": "off"}, {"id": "general_brace", "mode": "manual"},
		{"id": "knight_bulwark", "mode": "auto"}, {"id": "knight_rally", "mode": "auto"},
		{"id": "knight_charge", "mode": "auto"}, {"id": "knight_ground_slam", "mode": "auto"},
	] as Array[Dictionary])
	var mage: Hero = Hero.from_dict({"instance_id": "hero:m", "name": "M", "level": 1, "def_id": "mage", "learned_skills": ["general_brace"], "skill_bar": [{"id": "general_brace", "mode": "off"}]})
	assert_eq(mage.skill_bar, [{"id": "general_brace", "mode": "off"}] as Array[Dictionary], "a general skill is valid on every class")


func test_a_hero_levelling_past_5_gains_the_level_5_skills_at_the_end_of_its_bar() -> void:
	var hero: Hero = _knight("hero:k", 1)
	GameSession.add_hero(hero)
	var bar: Array[Dictionary] = [{"id": "knight_iron_cut", "mode": "manual"}, {"id": "knight_rally", "mode": "off"}, {"id": "knight_bulwark", "mode": "auto"}, {"id": "knight_charge", "mode": "auto"}, {"id": "knight_ground_slam", "mode": "auto"}]
	assert_true(GameSession.set_skill_bar(hero, bar))
	hero.level = 6
	var expected: Array[Dictionary] = bar.duplicate(true)
	expected.append_array([{"id": "knight_follow_through", "mode": "auto"}, {"id": "knight_buckler_blow", "mode": "auto"}])
	assert_eq(Hero.bar_for(hero, BALANCE), expected, "appended in kit order, auto")
	assert_eq(hero.skill_bar, bar, "no save change")


func test_set_skill_bar_takes_only_a_whole_bar_with_legal_modes() -> void:
	var hero: Hero = _knight("hero:k", 1)
	GameSession.add_hero(hero)
	var auto: Array[Dictionary] = _bar(KNIGHT_1, "auto")
	for raw_bad: Array in [
		auto.slice(0, 2),
		auto + [{"id": "knight_rally", "mode": "auto"}],
		[{"id": "knight_bulwark", "mode": "manual"}, auto[1], auto[2]],
		[auto[0], {"id": "knight_rally", "mode": "sometimes"}, auto[2]],
		[auto[0], auto[1], {"id": "knight_buckler_blow", "mode": "auto"}],
	]:
		var bad: Array[Dictionary] = []
		bad.assign(raw_bad)
		assert_false(GameSession.set_skill_bar(hero, bad), str(bad))
		assert_ne(GameSession.last_action_error, "")
	assert_eq(hero.skill_bar, [] as Array[Dictionary], "nothing changed")
	assert_false(GameSession.set_skill_bar(Hero.new("Stranger", 0), auto), "not on the roster")


func test_the_dispatch_snapshot_carries_the_bar_and_chains() -> void:
	var hero: Hero = _knight("hero:k", 5)
	hero.skill_chains = [{"trigger": "knight_iron_cut", "then": ["knight_follow_through"]}]
	GameSession.add_hero(hero)
	var bar: Array[Dictionary] = [{"id": "knight_rally", "mode": "manual"}, {"id": "knight_iron_cut", "mode": "off"}]
	hero.skill_bar = bar
	var snapshot: Dictionary = GameSession._team_snapshots([hero])[0]
	assert_eq(snapshot["skills"], Hero.bar_for(hero, BALANCE))
	assert_eq((snapshot["skills"] as Array).slice(0, 2), bar, "bar order, with modes")
	assert_eq(snapshot["chains"], hero.skill_chains)
	var actor: BattleActor = SIM._actor_from_team_snapshot(snapshot, 0, ZoneDefinition.definition_for(&"verdant_outskirts"))
	assert_eq(actor.skills, Hero.bar_for(hero, BALANCE), "the battle actor takes the bar as it is")


## Manual is never auto-fired and Off is never fired, weaponskills included. The same fight with the
## kit on Auto shows the check can see a cast.
func test_manual_is_never_auto_fired_and_off_is_never_fired() -> void:
	for modes: Array in [["auto", "auto"], ["manual", "off"], ["off", "manual"]]:
		var cast: Dictionary = _duel(modes[0], modes[1])
		if modes[0] == "auto":
			assert_true(cast["ability"] and cast["weaponskill"], "the Auto control casts both kinds")
		else:
			assert_false(cast["ability"], "abilities %s never fire" % modes[0])
			assert_false(cast["weaponskill"], "weaponskills %s never fire" % modes[1])


## A manual cast fires the first ability not set to Off; the Skill Auto toggle leaves Off alone.
func test_a_manual_cast_skips_off_and_the_auto_toggle_leaves_off_alone() -> void:
	var state: BattleState = _duel_state([{"id": "mage_burst", "mode": "off"}, {"id": "mage_frost_bind", "mode": "manual"}])
	var mage: BattleActor = state.actors[0]
	var command: Dictionary = {"kind": SIM.COMMAND_SET_ABILITY_AUTO, "actor_ids": [mage.id], "value": true}
	assert_true(SIM.issue_command(state, command)["accepted"])
	assert_eq(mage.skills[0]["mode"], "off")
	assert_eq(mage.skills[1]["mode"], "auto")
	assert_false(state.policies.has("ability_auto"), "a new order never writes the policy (ig-28b)")
	assert_eq(BattleSimulation.validate_snapshot(state.to_dict()), "", "a checkpoint without the policy still loads")
	SIM.advance(state, 0.5)
	assert_eq(mage.skill_cooldowns["mage_burst"], 0.0, "off never fires")


func test_death_takes_the_bar_with_the_hero() -> void:
	var hero: Hero = _knight("hero:k", 1)
	GameSession.add_hero(hero)
	assert_true(GameSession.set_skill_bar(hero, _bar(KNIGHT_1, "manual")))
	GameSession.kill_hero(hero, &"", BALANCE, "starvation")
	assert_false(JSON.stringify(GameSession.to_dict()).contains("skill_bar\":[{"), "nothing of the bar stays behind")


## The panel from the hero's roster entry: Skills opens it, Down reorders, a mode sticks, locked
## skills name their level, Close hides it. Every change is saved.
func test_the_skill_panel_reorders_sets_modes_and_shows_locked_skills() -> void:
	GameSession.add_hero(_knight("hero:k", 1))
	# GUT's own window covers the selected-hero column in a headless run and eats clicks there
	# (bd memory: headless GUT click tests), so its layer is hidden for this test; _click still
	# checks that the mouse reaches each target.
	var gut_layer: CanvasLayer = get_tree().root.find_child("GutLayer", true, false) as CanvasLayer
	if gut_layer != null:
		gut_layer.visible = false
	var hub: Node3D = load("res://hub/hub.tscn").instantiate() as Node3D
	add_child_autofree(hub)
	await get_tree().physics_frame
	await get_tree().physics_frame
	hub._open(&"Forge")
	var roster: ItemList = hub.get_node("%RosterList") as ItemList
	roster.select(0)
	roster.multi_selected.emit(0, true)
	var panel: SkillPanel = hub.get_node("%SkillPanel") as SkillPanel
	assert_false(panel.visible)
	await _click(hub, hub.get_node("%HeroSkills") as Control)
	assert_true(panel.visible, "Skills opens the panel")
	var rows: Node = panel.find_child("Rows", true, false)
	assert_eq(rows.get_children().filter(func(row: Node) -> bool: return row.name.begins_with("Skill_")).map(func(row: Node) -> String: return str(row.name)), ["Skill_knight_bulwark", "Skill_knight_rally", "Skill_knight_iron_cut", "Skill_knight_charge", "Skill_knight_ground_slam"])
	var locked: Label = rows.get_node("Locked_knight_buckler_blow") as Label
	assert_string_contains(locked.text, "opens at level 5")
	await _click(hub, rows.get_node("Skill_knight_bulwark/Down") as Control)
	var hero: Hero = GameSession.roster[0]
	assert_eq(hero.skill_bar.map(func(entry: Dictionary) -> String: return entry["id"]), ["knight_rally", "knight_bulwark", "knight_iron_cut", "knight_charge", "knight_ground_slam"])
	var mode: OptionButton = rows.get_node("Skill_knight_iron_cut/Mode") as OptionButton
	mode.select(2)
	mode.item_selected.emit(2)
	assert_eq(GameSession.roster[0].skill_bar[2], {"id": "knight_iron_cut", "mode": "off"})
	assert_string_contains(FileAccess.get_file_as_string(SaveService.SAVE_PATH), "\"off\"", "saved")
	assert_true((rows.get_node("Skill_knight_rally/Up") as Button).disabled, "the top row cannot go up")
	GameSession.roster[0].level = 6
	hub._refresh_hero_detail()
	assert_true(rows.has_node("Skill_knight_buckler_blow"), "the open panel follows the same hero levelling")
	assert_false(rows.has_node("Locked_knight_buckler_blow"))
	await _click(hub, panel.find_child("Close", true, false) as Control)
	assert_false(panel.visible)


## ---- helpers

func _knight(id: String, level: int) -> Hero:
	var hero := Hero.new("Knight", 0)
	hero.def_id = &"knight"
	hero.instance_id = id
	hero.level = level
	return hero


func _bar(ids: Array, mode: String) -> Array[Dictionary]:
	var bar: Array[Dictionary] = []
	for id: String in ids:
		bar.append({"id": id, "mode": "auto" if SIM.ABILITIES[id].kind == "passive" else mode})
	return bar


func _reload() -> void:
	GameSession.set("_save_deferred_depth", 1)
	GameSession.from_dict({"roster": []})
	GameSession.set("_save_deferred_depth", 0)
	assert_true(SaveService.load_game(), SaveService.load_block_reason)


## Whether a solo level-25 Mage with its class kit (abilities in ability_mode, weaponskills in
## weaponskill_mode) ever casts an ability or lands a weaponskill in 60 s against tough Knights.
func _duel(ability_mode: String, weaponskill_mode: String) -> Dictionary:
	var kit: Array[Dictionary] = []
	for skill: AbilityDefinition in SIM.known_kit("mage", 25):
		kit.append({"id": str(skill.skill_id), "mode": ability_mode if skill.kind == "ability" else weaponskill_mode if skill.kind == "weaponskill" else "auto"})
	var state: BattleState = _duel_state(kit)
	var mage: BattleActor = state.actors[0]
	var cast: Dictionary = {"ability": false, "weaponskill": false}
	for step: int in 600:
		SIM.advance(state, BALANCE.battle_tick_seconds)
		cast["ability"] = cast["ability"] or mage.skill_cooldowns.values().any(func(left: float) -> bool: return left > 0.0)
		cast["weaponskill"] = cast["weaponskill"] or mage.combo_skill != ""
	return cast


func _duel_state(kit: Array[Dictionary]) -> BattleState:
	var snapshots: Array[Dictionary] = [{"hero_id": "hero:mage", "archetype": "mage", "faction": "ally", "squad_id": "s", "hp": 100000.0, "atk": 40.0, "defense": 50.0, "speed": 100.0, "crit_rate": 0.0, "crit_damage": 1.5, "position": [0.0, -16.0], "skills": kit}]
	for index: int in 4:
		snapshots.append({"id": "enemy:%d" % index, "archetype": "knight", "faction": "enemy", "squad_id": "", "hp": 50000.0, "atk": 1.0, "defense": 0.0, "speed": 100.0, "crit_rate": 0.0, "crit_damage": 1.5, "position": [-2.0 + index * 1.2, -12.0]})
	var squads: Array[Dictionary] = [{"id": "s", "name": "S", "hero_ids": ["hero:mage"], "stance": "advance", "guard_target_id": ""}]
	return SIM.create_run("bar:1", snapshots, ZoneDefinition.definition_for(&"verdant_outskirts"), squads, {}, {"healing": 0, "revival": 0}, 11)


## A real click on a point of the control that the mouse reaches: GUT's own output panel covers part
## of the viewport and eats clicks there (bd memory: headless GUT click tests).
func _click(hub: Node3D, control: Control) -> void:
	await get_tree().process_frame
	var rect: Rect2 = control.get_global_rect()
	var at := Vector2(-1, -1)
	for y: float in range(int(rect.position.y) + 2, int(rect.end.y) - 1, 4):
		for x: float in range(int(rect.position.x) + 2, int(rect.end.x) - 1, 6):
			var motion := InputEventMouseMotion.new()
			motion.position = Vector2(x, y)
			motion.global_position = Vector2(x, y)
			hub.get_viewport().push_input(motion, true)
			var hovered: Control = hub.get_viewport().gui_get_hovered_control()
			if hovered == control or (hovered != null and control.is_ancestor_of(hovered)):
				at = Vector2(x, y)
				break
		if at.x >= 0.0:
			break
	assert_true(at.x >= 0.0, "some point of %s is reachable" % control.name)
	for pressed: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = at
		click.global_position = at
		click.pressed = pressed
		hub.get_viewport().push_input(click, true)
	await get_tree().process_frame
