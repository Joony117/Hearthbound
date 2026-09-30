extends GutTest

## ig-gy0.6: take control of one hero (SYSTEMS.md § Hero AI on auto, "The piloted hero"; DECISIONS.md 2026-09-23
## "Skills" item 9). The simulation skips the piloted hero's own choices and fires what the player commands
## (use_skill); the pilot is view state, set by GameSession for a watched advance and never saved.

const BALANCE: BalanceTable = preload("res://balance.tres")
const SIM = preload("res://combat/battle/battle_simulation.gd")
const Compare = preload("res://tests/unit/compare.gd")
const KEPT: Array[String] = [SaveService.SAVE_PATH, SaveService.LEDGER_PATH]
const LOADOUT: Dictionary = {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0}
const FRAME: float = 1.0 / 60.0
var RALLY: AbilityDefinition = SIM.ABILITIES["knight_rally"]
var HEARTEN: AbilityDefinition = SIM.ABILITIES["general_hearten"]
var BRACE: AbilityDefinition = SIM.ABILITIES["general_brace"]
var BUCKLER: AbilityDefinition = SIM.ABILITIES["knight_buckler_blow"]
var TICK: float = BALANCE.battle_tick_seconds

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
	GameSession.set_process(false)
	SaveService.load_blocked = false
	GameSession.set("_save_deferred_depth", 1)
	GameSession.from_dict({"roster": []})
	GameSession.set("_save_deferred_depth", 0)


func after_each() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(SaveService.TMP_PATH)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveService.TMP_PATH))
	GameSession.set("_save_deferred_depth", 0)
	GameSession.set("_checkpoint_save_failed", false)
	GameSession.set("_checkpoint_error", "")
	GameSession.set_process(true)
	var gut_layer: CanvasLayer = get_tree().root.find_child("GutLayer", true, false) as CanvasLayer
	if gut_layer != null:
		gut_layer.visible = true


## ---- ACC 1: what the simulation no longer chooses for the piloted hero

func test_a_piloted_hero_picks_no_skill_and_no_target_where_an_auto_hero_does() -> void:
	var seen: Array = []
	for piloted: bool in [false, true]:
		var state: BattleState = _run([["knight", Vector2(0, 0)]], 20)
		var hero: BattleActor = state.actors[0]
		var enemy: BattleActor = _lock(_enemies(state)[0], Vector2(0, 2.0), hero)
		if piloted:
			state.piloted_id = hero.id
		for _tick: int in 40:
			SIM.advance(state, TICK)
		seen.append([hero.order_target_id == enemy.id, enemy.hp < enemy.max_hp, hero.position.distance_to(Vector2.ZERO) < 1.0, hero.effect_state.has("last_skill_id")])
	assert_true(seen[0][0] and seen[0][1], "control: the auto hero picked the enemy and struck it: %s" % [seen[0]])
	assert_eq(seen[1], [false, false, true, false], "piloted: no target, no swing, no step, no skill")


func test_a_piloted_hero_auto_attacks_the_target_the_player_gave_it() -> void:
	var state: BattleState = _run([["knight", Vector2(0, 0)]], 20)
	var hero: BattleActor = state.actors[0]
	var enemy: BattleActor = _lock(_enemies(state)[0], Vector2(0, 2.0), hero)
	state.piloted_id = hero.id
	assert_true(SIM.issue_command(state, {"kind": SIM.COMMAND_ATTACK, "actor_ids": [hero.id], "target_id": enemy.id})["accepted"])
	for _tick: int in 40:
		SIM.advance(state, TICK)
	assert_eq(hero.order_target_id, enemy.id, "the order stands")
	assert_lt(enemy.hp, enemy.max_hp, "and the hero swings at it")


func test_a_piloted_hero_stays_in_a_telegraph_and_claims_nothing_and_the_next_hero_answers() -> void:
	for piloted: bool in [false, true]:
		var state: BattleState = _crushing_blow_on_two_knights()
		var first: BattleActor = state.actors[0]
		var second: BattleActor = state.actors[2]
		var caster: BattleActor = state.actors[1]
		if piloted:
			state.piloted_id = first.id
		SIM.advance(state, 0.3)
		var claimed_by: String = str(caster.effect_state["telegraph_claimed_by"])
		if piloted:
			assert_eq(first.skill_cooldowns["knight_buckler_blow"], 0.0, "and makes no counter")
			assert_eq(claimed_by, second.id, "the next hero with a counter claims it")
			assert_gt(second.skill_cooldowns["knight_buckler_blow"], 0.0)
		else:
			assert_eq(claimed_by, first.id, "control: the first knight answers")


func test_a_piloted_hero_does_not_walk_out_of_a_telegraph_on_auto() -> void:
	# A telegraph nobody answers (no counters in any bar): the auto hero evades, the piloted one stays.
	var moved: Array[bool] = []
	for piloted: bool in [false, true]:
		var state: BattleState = _crushing_blow_on_two_knights()
		state.policies["auto_battle"] = true
		for actor: BattleActor in state.actors:
			if actor.faction == "ally":
				actor.skills.clear()
				actor.skill_cooldowns.clear()
		var hero: BattleActor = state.actors[0]
		if piloted:
			state.piloted_id = hero.id
		SIM.advance(state, 0.3)
		moved.append(hero.effect_state.get("evade_point") is Array)
	assert_eq(moved, [true, false], "auto evades, piloted stays")


func test_a_piloted_ranger_does_not_hop() -> void:
	for piloted: bool in [false, true]:
		var state: BattleState = _run([["knight", Vector2(2, -4)], ["ranger", Vector2(0, 0)]], 1)
		var ranger: BattleActor = state.actors[1]
		_lock(_melee(state)[0], Vector2(0, 2.5), ranger)
		if piloted:
			state.piloted_id = ranger.id
		var hopped: bool = false
		for _tick: int in 60:
			SIM.advance(state, TICK)
			hopped = hopped or ranger.effect_state.has("kite_point")
		assert_eq(hopped, not piloted, "hop (piloted %s)" % piloted)
		if piloted:
			assert_eq(ranger.order_kind, "", "it takes no automatic order")
			assert_lt(ranger.position.distance_to(Vector2.ZERO), 0.6, "and stays where it stood")


func test_a_piloted_hero_whose_target_dies_stands_where_an_auto_hero_picks_the_next() -> void:
	var picks: Array[String] = []
	for piloted: bool in [false, true]:
		var state: BattleState = _run([["knight", Vector2(0, 0)]], 20)
		var hero: BattleActor = state.actors[0]
		var doomed: BattleActor = _lock(_enemies(state)[0], Vector2(0, 1.4), hero)
		doomed.max_hp = 1.0
		doomed.hp = 1.0
		var next: BattleActor = _lock(_enemies(state)[1], Vector2(0, 3.0), hero)
		if piloted:
			state.piloted_id = hero.id
		assert_true(SIM.issue_command(state, {"kind": SIM.COMMAND_ATTACK, "actor_ids": [hero.id], "target_id": doomed.id})["accepted"])
		for _tick: int in 60:
			SIM.advance(state, TICK)
		assert_ne(doomed.life, BattleActor.LIFE_ALIVE, "setup: the target fell")
		picks.append(hero.order_target_id)
		if piloted:
			assert_eq(hero.order_kind, "", "it stands: no new order")
			assert_eq(next.hp, next.max_hp, "and never hit the next enemy")
			assert_false(bool(hero.effect_state.get("direct_order", false)))
	assert_ne(picks[0], "", "control: the auto hero took the next enemy")
	assert_eq(picks[1], "", "the piloted hero took no one")


func test_a_piloted_hero_uses_no_auto_item() -> void:
	var left: Array[int] = []
	for piloted: bool in [false, true]:
		var state: BattleState = _run([["knight", Vector2(0, 0)]], 5, {"healing": 3, "revival": 0})
		var hero: BattleActor = state.actors[0]
		hero.hp = hero.max_hp * 0.2
		if piloted:
			state.piloted_id = hero.id
		for _tick: int in 20:
			SIM.advance(state, TICK)
		left.append(int(state.supplies_remaining["healing"]))
	assert_eq(left, [2, 3], "the auto hero drank a draught, the piloted one kept it")


func test_a_piloted_hero_skips_the_supplies_retreat_like_a_direct_order() -> void:
	var state: BattleState = _run([["knight", Vector2(0, 0)], ["knight", Vector2(4, 0)]], 5, {"healing": 0, "revival": 0}, {"retreat_when_supplies_empty": true})
	state.piloted_id = state.actors[0].id
	SIM.advance(state, TICK)
	assert_eq(state.actors[0].order_kind, "", "the piloted hero is not sent home")
	assert_eq(state.actors[1].order_kind, SIM.COMMAND_RETREAT, "the other still goes")


func test_a_back_row_ally_forms_up_behind_a_piloted_knight_as_behind_a_held_one() -> void:
	var walked: Array = []
	for piloted: bool in [false, true]:
		var state: BattleState = _run([["knight", Vector2(0, 0)], ["ranger", Vector2(0, -6)]], 5)
		var knight: BattleActor = state.actors[0]
		if piloted:
			state.piloted_id = knight.id
		else:
			assert_true(SIM.issue_command(state, {"kind": SIM.COMMAND_HOLD, "actor_ids": [knight.id]})["accepted"])
		var path: Array = []
		for _tick: int in 60:
			SIM.advance(state, TICK)
			path.append(state.actors[1].position)
		walked.append(path)
	assert_eq(walked[1], walked[0], "the ranger forms up on a piloted knight exactly as on a held one")


func test_a_piloted_knights_target_keeps_an_auto_knight_off_it() -> void:
	var state: BattleState = _run([["knight", Vector2(-2, 0)], ["knight", Vector2(2, 0)], ["mage", Vector2(0, 6)], ["ranger", Vector2(-8, 0)]], 1)
	var auto_knight: BattleActor = state.actors[0]
	var piloted: BattleActor = state.actors[1]
	var enemies: Array[BattleActor] = _enemies(state)
	var threat: BattleActor = _lock(enemies[0], Vector2(0, 9), state.actors[2])
	var other_threat: BattleActor = _lock(enemies[1], Vector2(-8, 3), state.actors[3])
	for knight: BattleActor in [auto_knight, piloted]:
		knight.move_speed = 0.0
	state.piloted_id = piloted.id
	auto_knight.order_kind = SIM.COMMAND_ATTACK
	auto_knight.order_target_id = threat.id
	assert_true(SIM.issue_command(state, {"kind": SIM.COMMAND_ATTACK, "actor_ids": [piloted.id], "target_id": threat.id})["accepted"])
	for _tick: int in int(2.0 / TICK):
		SIM.advance(state, TICK)
		assert_eq(piloted.order_target_id, threat.id, "the piloted knight keeps the player's target")
		assert_eq(auto_knight.order_target_id, other_threat.id, "tick %d: the second knight covers the other threat" % state.tick)


func test_a_hero_is_on_auto_the_tick_after_its_pilot_ends() -> void:
	var state: BattleState = _run([["knight", Vector2(0, 0)]], 20)
	var hero: BattleActor = state.actors[0]
	_lock(_enemies(state)[0], Vector2(0, 4.0), hero)
	state.piloted_id = hero.id
	for _tick: int in 5:
		SIM.advance(state, TICK)
		assert_eq(hero.order_kind, "", "piloted: nothing decides for it")
	state.piloted_id = ""
	SIM.advance(state, TICK)
	assert_ne(hero.order_kind, "", "the next tick it is on auto")


## ---- ACC 2: use_skill, checked like an ability today and refused in its own words

const KNIGHT_KIT: Dictionary = {"knight_charge": "auto", "knight_ground_slam": "auto", "knight_gauntlet_toss": "auto", "knight_bulwark": "auto", "knight_iron_cut": "auto", "general_field_dressing": "auto"}


func test_use_skill_is_refused_each_case_in_its_own_words_and_changes_nothing() -> void:
	var state: BattleState = _knight_scene()
	_refused(state, "knight_charge", {"target_id": "enemy:t"}, "That is too close.")
	_refused(state, "knight_charge", {"target_id": "enemy:far"}, "That is out of range.")
	_refused(state, "mage_burst", {"target_id": "enemy:mid"}, "That skill is not on this hero's bar.")
	_refused(state, "no_such_skill", {}, "That skill is not on this hero's bar.")
	_refused(state, "knight_bulwark", {}, "A passive is always on and is never fired.")
	_refused(state, "knight_gauntlet_toss", {"target_id": "hero:k2"}, "That skill needs a living enemy as its target.")
	_refused(state, "knight_gauntlet_toss", {"point": [3.0, 0.0]}, "That skill needs a living enemy as its target.")
	_refused(state, "knight_gauntlet_toss", {"target_id": "enemy:nope"}, "That target is not in the battle.")
	_refused(state, "knight_gauntlet_toss", {"point": [NAN, 0.0]}, "That command needs a finite ground point.")
	_refused(state, "general_field_dressing", {"target_id": "hero:h"}, "That skill needs a hurt ally as its target.")
	_refused(state, "general_field_dressing", {"target_id": "enemy:t"}, "That skill needs a hurt ally as its target.")
	_refused(state, "knight_charge", {"actor_ids": ["hero:h", "hero:k2"], "target_id": "enemy:mid"}, "use_skill needs exactly one hero.")
	_refused(state, "knight_charge", {"actor_ids": ["enemy:t"], "target_id": "enemy:mid"}, "Every commanded actor must be a current living ally.")
	var afflictions: Dictionary = {
		"cooling": "That skill is still on cooldown.",
		"locked": "Another ability was just used; the ability lock holds.",
		"stunned": "The hero is stunned.",
		"silenced": "The hero is silenced.",
		"rooted": "The hero is rooted.",
	}
	for kind: String in afflictions:
		var afflicted: BattleState = _knight_scene()
		_afflict(_hero(afflicted), kind)
		_refused(afflicted, "knight_charge", {"target_id": "enemy:mid"}, str(afflictions[kind]), kind)
	var gagged: BattleState = _knight_scene()
	_afflict(_hero(gagged), "silenced")
	_refused(gagged, "knight_iron_cut", {}, "The hero is silenced.", "a weaponskill too")
	var idle: BattleState = _knight_scene()
	_hero(idle).order_target_id = ""
	_refused(idle, "knight_iron_cut", {}, "That skill needs a living enemy as its target.", "no target to swing at")

	var cleric: BattleState = _scene({"cleric_sheltering_word": "auto", "cleric_hearthcall": "auto"}, [], "cleric", _reach())
	_refused(cleric, "cleric_sheltering_word", {"target_id": "enemy:t"}, "That skill needs a living ally as its target.")
	_refused(cleric, "cleric_hearthcall", {}, "Nobody is in reach.", "a revive with nobody downed")
	_refused(cleric, "cleric_hearthcall", {"target_id": "hero:k2"}, "Nobody is in reach.", "a revive on a standing ally")


func test_a_refused_cast_leaves_the_running_chain_and_the_order_as_they_were() -> void:
	var state: BattleState = _scene({"knight_rally": "auto", "general_hearten": "auto", "knight_gauntlet_toss": "auto"}, [_chain(RALLY, ["general_hearten"])], "knight", _reach())
	var hero: BattleActor = _hero(state)
	hero.skill_cooldowns["general_hearten"] = 30.0
	hero.skill_cooldowns["knight_gauntlet_toss"] = 5.0
	SIM._start_chain(state, hero, RALLY, true)
	var keys: Array = _keys(hero)
	_refused(state, "knight_gauntlet_toss", {"target_id": "enemy:u"}, "That skill is still on cooldown.")
	assert_eq(_keys(hero), keys)
	assert_eq(hero.order_target_id, "enemy:t", "aimed at another enemy, but refused: no new target")


func test_use_skill_fires_a_skill_set_to_off_that_the_ai_never_picks() -> void:
	var braced: Array[bool] = []
	for mode: String in ["auto", "off"]:
		var state: BattleState = _scene({"general_brace": mode}, [])
		state.policies["auto_battle"] = true
		_hero(state).hp = _hero(state).max_hp * 0.2
		for _tick: int in 30:
			SIM.advance(state, TICK)
		braced.append(_hero(state).skill_cooldowns["general_brace"] > 0.0)
	assert_eq(braced, [true, false], "control: at 20 percent HP an auto hero braces, an Off one never does")
	var by_hand: BattleState = _scene({"general_brace": "off"}, [])
	assert_true(_use(by_hand, "general_brace")["accepted"])
	assert_gt(_hero(by_hand).skill_cooldowns["general_brace"], 0.0, "the player fires it in any mode")


func test_a_trigger_fired_by_hand_starts_its_chain_and_replaces_a_running_one() -> void:
	var state: BattleState = _scene({"knight_rally": "auto", "general_hearten": "auto", "general_brace": "auto"}, [_chain(RALLY, ["general_hearten"]), _chain(BRACE, ["general_hearten"])])
	var hero: BattleActor = _hero(state)
	SIM._start_chain(state, hero, BRACE, false)
	assert_eq(_keys(hero)[0], "general_brace")
	state.tick = 7
	assert_true(_use(state, "knight_rally")["accepted"])
	assert_eq(_keys(hero), ["knight_rally", 0, 37, "enemy:t"], "the hand-fired trigger's chain, from step 0 with a fresh deadline")


func test_a_hand_cast_that_is_not_a_trigger_keeps_the_running_chain_unless_it_lands_on_another_enemy_that_lives() -> void:
	var kit: Dictionary = {"knight_rally": "auto", "general_hearten": "auto", "knight_gauntlet_toss": "auto", "general_field_dressing": "auto"}
	var aims: Array = [
		["the chain's own target", "knight_gauntlet_toss", {"target_id": "enemy:t"}],
		["itself", "general_field_dressing", {"target_id": "hero:h"}],
		["an ally", "general_field_dressing", {"target_id": "hero:k2"}],
	]
	for aim: Array in aims:
		var state: BattleState = _scene(kit, [_chain(RALLY, ["general_hearten"])], "knight", _reach())
		var hero: BattleActor = _hero(state)
		hero.hp = hero.max_hp * 0.5
		SIM._actor_by_id(state, "hero:k2").hp = 20.0
		hero.skill_cooldowns["general_hearten"] = 30.0
		SIM._start_chain(state, hero, RALLY, true)
		var keys: Array = _keys(hero)
		assert_true(_use(state, str(aim[1]), aim[2])["accepted"], str(aim[0]))
		assert_gt(hero.skill_cooldowns[str(aim[1])], 0.0, "%s: it fired" % aim[0])
		SIM.advance(state, TICK)
		assert_eq(_keys(hero), keys, "aimed at %s: the chain runs on" % aim[0])

	var retarget: BattleState = _scene(kit, [_chain(RALLY, ["general_hearten"])], "knight", _reach())
	var caster: BattleActor = _hero(retarget)
	caster.skill_cooldowns["general_hearten"] = 30.0
	SIM._start_chain(retarget, caster, RALLY, true)
	assert_true(_use(retarget, "knight_gauntlet_toss", {"target_id": "enemy:u"})["accepted"])
	assert_eq(caster.order_target_id, "enemy:u", "it lands on another enemy, so the hero takes it as a right-click would")
	SIM.advance(retarget, TICK)
	assert_eq(_keys(caster), [null, null, null, null], "and the chain ends on the next tick")

	var mage: BattleState = _scene({"mage_rime_wall": "auto", "knight_rally": "auto", "general_hearten": "auto"}, [_chain(RALLY, ["general_hearten"])], "mage")
	_hero(mage).skill_cooldowns["general_hearten"] = 30.0
	SIM._start_chain(mage, _hero(mage), RALLY, true)
	var mage_keys: Array = _keys(_hero(mage))
	assert_true(_use(mage, "mage_rime_wall", {"point": [5.0, 0.0]})["accepted"])
	SIM.advance(mage, TICK)
	assert_eq(_keys(_hero(mage)), mage_keys, "aimed at the ground: the chain runs on")


## Director R1 as amended: a cast that kills the enemy it was aimed at retargets nothing. Buckler Blow (a strike at
## 1.6) on enemy:u, which has 1 HP, while the hero is on enemy:t; the controls give it 100000 HP and it retargets.
func _lethal_scene(chains: Array = []) -> BattleState:
	var state: BattleState = _scene({"knight_rally": "auto", "knight_gauntlet_toss": "auto", "knight_buckler_blow": "auto"}, chains)
	_foe(state, "enemy:u").hp = 1.0
	return state


func test_a_hand_cast_that_kills_its_aim_keeps_the_attack_where_it_was_and_one_that_spares_it_retargets() -> void:
	var state: BattleState = _lethal_scene()
	assert_true(_use(state, "knight_buckler_blow", {"target_id": "enemy:u"})["accepted"])
	assert_ne(_foe(state, "enemy:u").life, BattleActor.LIFE_ALIVE, "setup: the cast killed it")
	assert_eq([_hero(state).order_kind, _hero(state).order_target_id], [SIM.COMMAND_ATTACK, "enemy:t"], "the hero goes on attacking enemy:t")
	var spared: BattleState = _lethal_scene()
	_foe(spared, "enemy:u").hp = 100000.0
	assert_true(_use(spared, "knight_buckler_blow", {"target_id": "enemy:u"})["accepted"])
	assert_eq(_hero(spared).order_target_id, "enemy:u", "control: the same cast on a survivor retargets")


func test_a_lethal_hand_cast_that_is_not_a_trigger_leaves_the_running_chain_and_its_next_step_fires_at_the_old_target() -> void:
	var state: BattleState = _lethal_scene([_chain(RALLY, ["knight_gauntlet_toss"])])
	var hero: BattleActor = _hero(state)
	SIM._start_chain(state, hero, RALLY, true)
	var keys: Array = _keys(hero)
	assert_eq(keys[3], "enemy:t", "setup: the chain is on enemy:t")
	assert_true(_use(state, "knight_buckler_blow", {"target_id": "enemy:u"})["accepted"])
	assert_ne(_foe(state, "enemy:u").life, BattleActor.LIFE_ALIVE, "setup: the cast killed it")
	assert_eq(_keys(hero), keys, "the chain keys are as they were")
	var taunted: Callable = func() -> bool: return _foe(state).statuses.any(func(status: Dictionary) -> bool: return status["kind"] == "taunt" and status["id"] == "knight_gauntlet_toss")
	for _tick: int in 60:
		if taunted.call():
			break
		SIM.advance(state, TICK)
	assert_true(taunted.call(), "the step fired at enemy:t once the ability lock cleared")


func test_a_lethal_trigger_fired_by_hand_starts_its_chain_on_the_hero_target() -> void:
	var state: BattleState = _lethal_scene([_chain(BUCKLER, ["knight_gauntlet_toss"])])
	state.tick = 7
	assert_true(_use(state, "knight_buckler_blow", {"target_id": "enemy:u"})["accepted"])
	assert_ne(_foe(state, "enemy:u").life, BattleActor.LIFE_ALIVE, "setup: the cast killed it")
	assert_eq(_keys(_hero(state)), ["knight_buckler_blow", 0, 37, "enemy:t"], "on the target it had, not the dead one")
	assert_eq(_hero(state).order_target_id, "enemy:t")


func test_a_lethal_hand_cast_leaves_a_move_order() -> void:
	var state: BattleState = _lethal_scene()
	assert_true(SIM.issue_command(state, {"kind": SIM.COMMAND_MOVE, "actor_ids": ["hero:h"], "point": [-4.0, 0.0]})["accepted"])
	var hero: BattleActor = _hero(state)
	var point: Vector2 = hero.order_point
	assert_true(_use(state, "knight_buckler_blow", {"target_id": "enemy:u"})["accepted"])
	assert_ne(_foe(state, "enemy:u").life, BattleActor.LIFE_ALIVE, "setup: the cast killed it")
	assert_eq([hero.order_kind, hero.order_target_id, hero.order_point], [SIM.COMMAND_MOVE, "", point], "still walking to the point")


func test_a_weaponskill_by_hand_is_set_for_the_next_swing_used_and_cleared_there_and_a_second_press_replaces_it() -> void:
	var kit: Dictionary = {"knight_iron_cut": "off", "knight_sweeping_blow": "off", "knight_follow_through": "off"}
	var state: BattleState = _scene(kit, [])
	var hero: BattleActor = _hero(state)
	assert_true(_use(state, "knight_iron_cut")["accepted"])
	assert_eq(hero.effect_state["next_swing_skill"], "knight_iron_cut")
	assert_eq(hero.ability_lock, 0.0, "a weaponskill rides the swing: no lock")
	assert_false(hero.skill_cooldowns.has("knight_iron_cut"), "and no cooldown")
	assert_true(_use(state, "knight_sweeping_blow")["accepted"])
	assert_eq(hero.effect_state["next_swing_skill"], "knight_sweeping_blow", "a second press replaces it")
	_swing(state)
	assert_eq(hero.combo_skill, "knight_sweeping_blow", "the next swing used it")
	assert_false(hero.effect_state.has("next_swing_skill"), "and cleared it")

	# Silenced at the swing: a plain hit, and the key is spent.
	var gagged: BattleState = _scene(kit, [])
	assert_true(_use(gagged, "knight_iron_cut")["accepted"])
	SIM._add_status(_hero(gagged), "gag", "silence", "enemy:t", 5.0, 0.0)
	var foe: BattleActor = _foe(gagged)
	_swing(gagged)
	assert_lt(foe.hp, foe.max_hp, "the swing landed")
	assert_eq(_hero(gagged).combo_skill, "", "as a plain hit")
	assert_false(_hero(gagged).effect_state.has("next_swing_skill"))

	# The hand one wins over a chain's waiting weaponskill step, which stays waiting.
	var chained: BattleState = _scene({"knight_iron_cut": "off", "knight_follow_through": "auto", "knight_rally": "auto"}, [_chain(RALLY, ["knight_follow_through"])])
	SIM._start_chain(chained, _hero(chained), RALLY, true)
	assert_true(_use(chained, "knight_iron_cut")["accepted"])
	_swing(chained)
	assert_eq(_hero(chained).combo_skill, "knight_iron_cut", "the swing used the one the player set")
	assert_eq(_keys(_hero(chained))[1], 0, "the chain still waits at its weaponskill step")


func test_a_weaponskill_by_hand_aimed_at_another_enemy_takes_it_as_a_right_click_does() -> void:
	var state: BattleState = _scene({"knight_iron_cut": "auto"}, [])
	assert_true(_use(state, "knight_iron_cut", {"target_id": "enemy:u"})["accepted"])
	assert_eq(_hero(state).order_target_id, "enemy:u")
	assert_eq(_hero(state).effect_state["next_swing_skill"], "knight_iron_cut")


func test_use_skill_with_no_aim_aims_like_a_chain_step_and_a_click_overrides_it() -> void:
	var state: BattleState = _knight_scene()
	assert_true(_use(state, "knight_gauntlet_toss")["accepted"])
	assert_true(SIM._has_status(_foe(state), "taunt"), "no target and no point: the hero's own enemy")
	assert_false(SIM._has_status(_foe(state, "enemy:u"), "taunt"))
	var clicked: BattleState = _knight_scene()
	assert_true(_use(clicked, "knight_gauntlet_toss", {"target_id": "enemy:u"})["accepted"])
	assert_true(SIM._has_status(_foe(clicked, "enemy:u"), "taunt"), "a clicked unit is where it lands")
	assert_false(SIM._has_status(_foe(clicked), "taunt"))
	var idle: BattleState = _knight_scene()
	_hero(idle).order_target_id = ""
	_refused(idle, "knight_gauntlet_toss", {}, "That skill needs a living enemy as its target.", "nothing to aim at")


func test_a_cast_that_finds_nobody_in_reach_is_refused_and_spends_no_cooldown() -> void:
	var state: BattleState = _knight_scene()
	SIM._actor_by_id(state, "enemy:t").position = Vector2(5, 0)
	SIM._actor_by_id(state, "enemy:u").position = Vector2(0, 2.6)
	_refused(state, "knight_ground_slam", {}, "Nobody is in reach.", "Ground Slam with nobody within 2.5")
	assert_eq(_hero(state).skill_cooldowns["knight_ground_slam"], 0.0)
	SIM._actor_by_id(state, "enemy:u").position = Vector2(0, 2.4)
	assert_true(_use(state, "knight_ground_slam")["accepted"], "by hand it fires whenever an opponent is within 2.5")
	assert_gt(_hero(state).skill_cooldowns["knight_ground_slam"], 0.0)


func test_a_downed_ally_is_raised_by_hearthcall_with_no_aim() -> void:
	var state: BattleState = _scene({"cleric_hearthcall": "auto"}, [], "cleric", _reach())
	var fallen: BattleActor = SIM._actor_by_id(state, "hero:k2")
	fallen.life = BattleActor.LIFE_DOWNED
	fallen.hp = 0.0
	assert_true(_use(state, "cleric_hearthcall")["accepted"])
	assert_eq(fallen.life, BattleActor.LIFE_ALIVE)
	assert_gt(fallen.hp, 0.0)


func test_a_second_cast_waits_for_the_ability_lock_until_battle_time_runs() -> void:
	var state: BattleState = _knight_scene()
	assert_true(_use(state, "knight_gauntlet_toss")["accepted"])
	_refused(state, "knight_ground_slam", {}, "Another ability was just used; the ability lock holds.", "no time has run")
	for _tick: int in int(ceilf(BALANCE.skill_ability_lock_seconds / TICK)) + 1:
		SIM.advance(state, TICK)
	SIM._actor_by_id(state, "enemy:u").position = Vector2(0, 2.0)
	assert_true(_use(state, "knight_ground_slam")["accepted"], "once the lock has run out")


func test_rime_wall_by_a_ground_click_lands_across_the_line_centered_on_the_point_or_has_no_room() -> void:
	var state: BattleState = _scene({"mage_rime_wall": "auto"}, [], "mage")
	assert_true(_use(state, "mage_rime_wall", {"point": [5.0, 0.0]})["accepted"])
	var start: Vector2 = _vector(state.field_objects[0]["start"])
	var finish: Vector2 = _vector(state.field_objects[0]["end"])
	assert_almost_eq(start.x, 5.0, 0.0001, "across the line from the caster to the point")
	assert_almost_eq(finish.x, 5.0, 0.0001)
	assert_almost_eq(start.distance_to(finish), 6.0, 0.0001, "6 long")
	assert_almost_eq((start.y + finish.y) * 0.5, 0.0, 0.0001, "centered on the point")
	assert_gt(_hero(state).skill_cooldowns["mage_rime_wall"], 0.0)

	var edge: BattleState = _scene({"mage_rime_wall": "auto"}, [], "mage")
	_hero(edge).position = Vector2(18, 0)
	_refused(edge, "mage_rime_wall", {"point": [23.0, 0.0]}, "There is no room for the wall.")
	assert_eq(_hero(edge).skill_cooldowns["mage_rime_wall"], 0.0, "no cooldown spent")


## ---- ACC 3: the weaponskill set for the next swing rides the battle save; piloting itself never does

func test_next_swing_skill_saves_in_json_validates_and_plays_on_identically_and_the_pilot_is_never_saved() -> void:
	var state: BattleState = _scene({"knight_iron_cut": "auto", "knight_follow_through": "auto"}, [])
	assert_true(_use(state, "knight_follow_through")["accepted"])
	state.piloted_id = "hero:h"
	var saved: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict(), "", true, true)) as Dictionary
	assert_eq(SIM.validate_snapshot(saved), "")
	var text: String = JSON.stringify(saved)
	assert_false(text.contains("piloted_id") or text.contains("\"piloted\""), "a checkpoint written while piloting carries no pilot")
	var loaded := BattleState.from_dict(saved)
	assert_eq(loaded.piloted_id, "", "a reload leaves nobody piloted")
	assert_eq(_hero(loaded).effect_state["next_swing_skill"], "knight_follow_through", "the weaponskill came back")
	state.piloted_id = ""
	_swing(state)
	_swing(loaded)
	assert_eq(_hero(loaded).combo_skill, "knight_follow_through")
	assert_eq(_hero(loaded).combo_skill, _hero(state).combo_skill, "and the reload swung as the unbroken fight did")
	assert_almost_eq(_foe(loaded).hp, _foe(state).hp, 0.000001)
	assert_false(_hero(loaded).effect_state.has("next_swing_skill"))

	# The validator: an ally's weaponskill on its bar, and nothing else. A checkpoint from before it has no key.
	var fresh: BattleState = _scene({"knight_iron_cut": "auto", "knight_charge": "auto"}, [])
	assert_true(_use(fresh, "knight_iron_cut")["accepted"])
	var data: Dictionary = JSON.parse_string(JSON.stringify(fresh.to_dict(), "", true, true)) as Dictionary
	assert_eq(SIM.validate_snapshot(data), "")
	var effects: Dictionary = _actor_dict(data, "hero:h")["effect_state"]
	effects["next_swing_skill"] = "knight_charge"
	assert_string_contains(SIM.validate_snapshot(data), "next_swing_skill", "an ability is no weaponskill")
	effects["next_swing_skill"] = "knight_sweeping_blow"
	assert_string_contains(SIM.validate_snapshot(data), "next_swing_skill", "a weaponskill that is not on the bar")
	effects["next_swing_skill"] = "knight_iron_cut"
	assert_eq(SIM.validate_snapshot(data), "")
	(_actor_dict(data, "enemy:t")["effect_state"] as Dictionary)["next_swing_skill"] = "knight_iron_cut"
	assert_string_contains(SIM.validate_snapshot(data), "next_swing_skill", "an enemy's")
	(_actor_dict(data, "enemy:t")["effect_state"] as Dictionary).erase("next_swing_skill")
	effects.erase("next_swing_skill")
	assert_eq(SIM.validate_snapshot(data), "", "legacy: a checkpoint with no key loads")


func test_the_weaponskill_set_for_the_swing_goes_with_a_downed_or_extracted_hero_a_leg_carry_and_an_incident_but_not_with_its_chain() -> void:
	var kit: Dictionary = {"knight_iron_cut": "auto", "knight_rally": "auto", "general_hearten": "auto"}
	var chains: Array = [_chain(RALLY, ["general_hearten"])]
	var state: BattleState = _scene(kit, chains)
	var hero: BattleActor = _hero(state)
	hero.skill_cooldowns["general_hearten"] = 30.0
	SIM._start_chain(state, hero, RALLY, true)
	assert_true(_use(state, "knight_iron_cut")["accepted"])
	hero.end_chain()
	assert_eq(hero.effect_state.get("next_swing_skill"), "knight_iron_cut", "the chain ending leaves it")
	SIM._take_damage(state, _foe(state), hero, 1000000.0)
	assert_eq(hero.life, BattleActor.LIFE_DOWNED)
	assert_false(hero.effect_state.has("next_swing_skill"), "downed: gone")
	hero.effect_state["next_swing_skill"] = "knight_iron_cut"
	SIM.advance(state, TICK)
	assert_false(hero.effect_state.has("next_swing_skill"), "a stale one on a downed body goes on the next tick")

	var away: BattleState = _scene(kit, chains)
	assert_true(_use(away, "knight_iron_cut")["accepted"])
	SIM._extract_actor(away, _hero(away))
	assert_false(_hero(away).effect_state.has("next_swing_skill"), "extracted: gone")

	var leg: BattleState = _scene(kit, chains)
	assert_true(_use(leg, "knight_iron_cut")["accepted"])
	var carried_in: Array[Dictionary] = []
	for actor: BattleActor in leg.actors:
		carried_in.append(actor.to_dict())
	assert_true((carried_in[0]["effect_state"] as Dictionary).has("next_swing_skill"), "setup: it was in the snapshot")
	assert_false(_hero(_battle(carried_in)).effect_state.has("next_swing_skill"), "a leg carry drops it, as it drops the chain")
	var incident: Dictionary = GameSession._incident_snapshot(leg, ["h"] as Array[String])
	assert_eq(SIM.validate_snapshot(incident), "")
	for actor: Dictionary in incident["actors"]:
		assert_false((actor["effect_state"] as Dictionary).has("next_swing_skill"), "%s: none in a rescue's snapshot" % actor["id"])


## ---- helpers

func _actor_dict(data: Dictionary, actor_id: String) -> Dictionary:
	return (data["actors"] as Array).filter(func(entry: Dictionary) -> bool: return entry["id"] == actor_id)[0]


func _use(state: BattleState, skill_id: String, extra: Dictionary = {}) -> Dictionary:
	var command: Dictionary = {"kind": SIM.COMMAND_USE_SKILL, "actor_ids": ["hero:h"], "skill_id": skill_id}
	command.merge(extra, true)
	return SIM.issue_command(state, command)


## The command is refused with exactly message, and the battle is the same after it.
func _refused(state: BattleState, skill_id: String, extra: Dictionary, message: String, label: String = "") -> void:
	var before: Dictionary = state.to_dict()
	var result: Dictionary = _use(state, skill_id, extra)
	assert_false(result["accepted"], "%s %s: refused" % [skill_id, label])
	assert_eq(result["error"], message, "%s %s" % [skill_id, label])
	assert_eq(Compare.first_difference(state.to_dict(), before), "", "%s %s: nothing changed" % [skill_id, label])


## enemy:mid 8 away (Charge's band), enemy:far 18 away (out of it), and a second knight beside the hero.
func _reach() -> Array:
	return [
		_unit("enemy:mid", "knight", "enemy", Vector2(8, 0), {"hp": 100000.0, "atk": 1.0}),
		_unit("enemy:far", "knight", "enemy", Vector2(18, 0), {"hp": 100000.0, "atk": 1.0}),
		_unit("k2", "knight", "ally", Vector2(-1, 0)),
	]


func _knight_scene() -> BattleState:
	return _scene(KNIGHT_KIT, [], "knight", _reach())


func _afflict(hero: BattleActor, kind: String) -> void:
	match kind:
		"cooling":
			hero.skill_cooldowns["knight_charge"] = 5.0
		"locked":
			hero.ability_lock = 1.0
		"stunned":
			hero.effect_state["stun_remaining"] = 1.0
		"silenced":
			SIM._add_status(hero, "gag", "silence", "enemy:t", 5.0, 0.0)
		"rooted":
			SIM._add_status(hero, "mud", "root", "enemy:t", 5.0, 0.0)


## Advances until the hero has swung once (its target lost hit points), at most 400 ticks.
func _swing(state: BattleState) -> void:
	var foe: BattleActor = _foe(state)
	for _tick: int in 400:
		SIM.advance(state, TICK)
		if foe.hp < foe.max_hp:
			return
	fail_test("the hero never swung")


func _vector(value: Variant) -> Vector2:
	return Vector2(float((value as Array)[0]), float((value as Array)[1]))

## heroes: [archetype, position] pairs in one Advance squad at speed 100, in a normal run of the verdant zone with
## four enemies (parked far off; a test places the ones it uses). Auto Battle on, the auto AI as a player has it.
func _run(heroes: Array, level: int, supplies: Dictionary = {"healing": 0, "revival": 0}, policies: Dictionary = {}) -> BattleState:
	var snapshots: Array[Dictionary] = []
	var ids: Array[String] = []
	for index: int in heroes.size():
		var id: String = "hero:%d" % index
		ids.append(id)
		var point: Vector2 = heroes[index][1]
		snapshots.append({"hero_id": id, "archetype": heroes[index][0], "level": level, "hp": 4000.0, "atk": 50.0, "defense": 20.0, "speed": 100.0,
			"crit_rate": 0.0, "crit_damage": 1.5, "squad_id": "squad:0", "position": [point.x, point.y]})
	var squads: Array[Dictionary] = [{"id": "squad:0", "name": "Alpha", "hero_ids": ids, "stance": "advance", "guard_target_id": ""}]
	var state: BattleState = SIM.create_run("order:gy06", snapshots, _zone(), squads, policies, supplies, 13, "normal", 1)
	for enemy: BattleActor in _enemies(state):
		_lock(enemy, Vector2(float(enemy.spawn_index % 3) * 2.0 - 2.0, 19.0), state.actors[0])
		enemy.order_kind = ""
		enemy.order_target_id = ""
	return state


func _zone() -> ZoneDefinition:
	var zone := ZoneDefinition.new()
	zone.zone_id = &"verdant_outskirts"
	zone.recommended_power = 20
	zone.trash_wave_count = 1
	zone.trash_wave_start_fraction = 0.9
	zone.trash_wave_end_fraction = 0.9
	zone.boss_fraction = 1.0
	zone.reference_force_size = 1
	zone.trash_enemy_count = 4
	zone.max_battle_seconds = 120.0
	zone.exit_position = Vector2(0, -16)
	return zone


func _lock(enemy: BattleActor, point: Vector2, victim: BattleActor) -> BattleActor:
	enemy.position = point
	enemy.effect_state["home_position"] = [point.x, point.y]
	enemy.order_kind = SIM.COMMAND_ATTACK
	enemy.order_target_id = victim.id
	enemy.max_hp = 100000.0
	enemy.hp = enemy.max_hp
	enemy.atk = 1.0
	return enemy


func _enemies(state: BattleState) -> Array[BattleActor]:
	var enemies: Array[BattleActor] = []
	for actor: BattleActor in state.actors:
		if actor.faction == "enemy":
			enemies.append(actor)
	return enemies


func _melee(state: BattleState) -> Array[BattleActor]:
	var melee: Array[BattleActor] = []
	for enemy: BattleActor in _enemies(state):
		if enemy.attack_range < BALANCE.battle_kite_trigger_range:
			melee.append(enemy)
	return melee


## Two Knights with Buckler Blow (hero:k1 at (0, -16), hero:k2 at (0, -15)) inside an enemy Knight's Crushing
## Blow, marked on the first. actors: [k1, enemy, k2]. Auto Battle off (the caller may turn it on).
func _crushing_blow_on_two_knights() -> BattleState:
	var snapshots: Array[Dictionary] = [_unit("hero:k1", "knight", "ally", Vector2(0, -16)), _unit("enemy:1", "knight", "enemy", Vector2(1, -16)), _unit("hero:k2", "knight", "ally", Vector2(0, -15))]
	var state: BattleState = _battle(snapshots)
	_give(state.actors[1], ["enemy_knight_crushing_blow"])
	assert_true(SIM._auto_cast(state, state.actors[1], state.actors[0], ["attack"], null))
	_give(state.actors[0], ["knight_buckler_blow"])
	_give(state.actors[2], ["knight_buckler_blow"])
	return state


func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	return rng


func _hero(state: BattleState) -> BattleActor:
	return SIM._actor_by_id(state, "hero:h")


func _foe(state: BattleState, id: String = "enemy:t") -> BattleActor:
	return SIM._actor_by_id(state, id)


## The running chain: [trigger, step, deadline, target], nulls when none.
func _keys(actor: BattleActor) -> Array:
	var effects: Dictionary = actor.effect_state
	if not effects.has("chain_trigger"):
		return [null, null, null, null]
	return [effects["chain_trigger"], int(effects["chain_step"]), int(effects["chain_deadline_tick"]), effects["chain_target"]]


func _chain(trigger: AbilityDefinition, then: Array) -> Dictionary:
	return {"trigger": str(trigger.skill_id), "then": then}


## hero:h (the archetype's class, kit and chains as given) at (0, 0) ordered onto enemy:t at (1, 0), with
## enemy:u at (0, 1.2) and extra units. Nothing dies in it: the hero has 10000 HP and the enemies 100000.
## A rescue battle with Auto Battle off, so the only orders are the ones a test gives.
func _scene(kit: Dictionary, chains: Array, archetype: String = "knight", extra: Array = []) -> BattleState:
	var snapshots: Array[Dictionary] = [
		_unit("h", archetype, "ally", Vector2(0, 0), {"hp": 10000.0}),
		_unit("enemy:t", "knight", "enemy", Vector2(1, 0), {"hp": 100000.0, "atk": 1.0}),
		_unit("enemy:u", "knight", "enemy", Vector2(0, 1.2), {"hp": 100000.0, "atk": 1.0}),
	]
	for unit: Dictionary in extra:
		snapshots.append(unit)
	var state: BattleState = _battle(snapshots)
	var hero: BattleActor = _hero(state)
	_give(hero, kit.keys())
	for entry: Dictionary in hero.skills:
		entry["mode"] = kit[entry["id"]]
	hero.chains.assign(chains)
	assert_true(SIM.issue_command(state, {"kind": SIM.COMMAND_ATTACK, "actor_ids": ["hero:h"], "target_id": "enemy:t"})["accepted"])
	return state


func _unit(id: String, archetype: String, faction: String, position: Vector2, extra: Dictionary = {}) -> Dictionary:
	var snapshot: Dictionary = {"archetype": archetype, "faction": faction, "hp": 100.0, "atk": 10.0, "defense": 0.0, "speed": 100.0, "crit_rate": 0.0, "crit_damage": 1.5, "position": [position.x, position.y]}
	if faction == "ally":
		snapshot["hero_id"] = id
		snapshot["squad_id"] = "s"
	else:
		snapshot["id"] = id
		snapshot["squad_id"] = ""
	snapshot.merge(extra, true)
	return snapshot


func _squads(snapshots: Array[Dictionary]) -> Array[Dictionary]:
	var hero_ids: Array = snapshots.filter(func(snapshot: Dictionary) -> bool: return snapshot["faction"] == "ally").map(func(snapshot: Dictionary) -> String: return snapshot["hero_id"])
	return [{"id": "s", "name": "S", "hero_ids": hero_ids, "stance": "stay_together", "guard_target_id": ""}]


## No zone spawns (the enemies come in the list), Auto Battle off, no crits, empty kits, pace 1.
func _battle(snapshots: Array[Dictionary]) -> BattleState:
	var state: BattleState = SIM.create_run("piloted:1", snapshots, ZoneDefinition.definition_for(&"verdant_outskirts"), _squads(snapshots), {"auto_battle": false, "suppress_ally_crit": true}, {"healing": 0, "revival": 0}, 7, "rescue", 1)
	for actor: BattleActor in state.actors:
		_give(actor, [])
	return state


func _give(actor: BattleActor, skill_ids: Array) -> void:
	actor.skills.clear()
	actor.skill_cooldowns.clear()
	for skill_id: String in skill_ids:
		actor.add_skill(SIM.ABILITIES[skill_id])
