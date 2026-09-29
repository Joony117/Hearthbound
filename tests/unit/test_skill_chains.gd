extends GutTest

## ig-gy0.5: skill chains (SYSTEMS.md § Chains, DECISIONS.md 2026-09-23 "Skills" item 7). A hero's chain is
## profile state ({trigger, then}, saved on the Hero and fixed into the team snapshot at dispatch); in a fight
## a trigger starts it at its first step, and the chain band sits between heal and buff.

const BALANCE: BalanceTable = preload("res://balance.tres")
const SIM = preload("res://combat/battle/battle_simulation.gd")
const Compare = preload("res://tests/unit/compare.gd")
const KEPT: Array[String] = [SaveService.SAVE_PATH, SaveService.LEDGER_PATH]
var RALLY: AbilityDefinition = SIM.ABILITIES["knight_rally"]
var HEARTEN: AbilityDefinition = SIM.ABILITIES["general_hearten"]
var BRACE: AbilityDefinition = SIM.ABILITIES["general_brace"]
var CHARGE: AbilityDefinition = SIM.ABILITIES["knight_charge"]
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
	SaveService.load_blocked = false
	GameSession.set("_save_deferred_depth", 1)
	GameSession.from_dict({"roster": []})
	GameSession.set("_save_deferred_depth", 0)


func after_each() -> void:
	GameSession.set("_save_deferred_depth", 0)
	var gut_layer: CanvasLayer = get_tree().root.find_child("GutLayer", true, false) as CanvasLayer
	if gut_layer != null:
		gut_layer.visible = true


## ---- the profile

func test_the_balance_rows_and_the_timeout_in_ticks() -> void:
	assert_eq(BALANCE.skill_chain_step_timeout_seconds, 3.0)
	assert_eq(BALANCE.skill_chain_max_steps, 8)
	assert_eq(SIM._chain_timeout_ticks(), 30, "3 s at 0.1 s a tick")


func test_load_keeps_good_chains_drops_bad_ones_and_cuts_a_long_one() -> void:
	var nine: Array = []
	for _i: int in 9:
		nine.append("knight_rally")
	var hero: Hero = Hero.from_dict({
		"instance_id": "hero:k", "name": "K", "rank": 0, "level": 1, "def_id": "knight",
		"skill_chains": [
			{"trigger": "knight_iron_cut", "then": ["knight_rally"]},
			{"trigger": "knight_bulwark", "then": ["knight_rally"]},
			{"trigger": "knight_rally", "then": ["knight_bulwark"]},
			{"trigger": "knight_iron_cut", "then": ["knight_charge"]},
			{"trigger": "knight_charge", "then": nine},
		],
	})
	var eight: Array = nine.slice(0, 8)
	assert_eq(hero.skill_chains, [{"trigger": "knight_iron_cut", "then": ["knight_rally"]}, {"trigger": "knight_charge", "then": eight}] as Array[Dictionary])
	assert_push_warning_count(4)


func test_set_skill_chains_takes_only_legal_chains() -> void:
	var hero: Hero = _knight("hero:k", 1)
	GameSession.add_hero(hero)
	var nine: Array = []
	for _i: int in 9:
		nine.append("knight_rally")
	for bad: Array in [
		[{"trigger": "knight_bulwark", "then": ["knight_rally"]}],
		[{"trigger": "knight_rally", "then": ["knight_bulwark"]}],
		[{"trigger": "knight_rally", "then": ["knight_iron_cut"]}, {"trigger": "knight_rally", "then": ["knight_charge"]}],
		[{"trigger": "knight_rally", "then": nine}],
		[{"trigger": "knight_rally", "then": ["nonsense"]}],
		[{"trigger": "knight_rally", "then": ["knight_buckler_blow"]}],
		[{"trigger": "knight_rally", "then": []}],
		[{"trigger": "knight_rally"}],
	]:
		GameSession.last_action_error = ""
		assert_false(GameSession.set_skill_chains(hero, _chains(bad)), str(bad))
		assert_ne(GameSession.last_action_error, "", str(bad))
	assert_eq(hero.skill_chains, [] as Array[Dictionary], "nothing changed")
	assert_false(GameSession.set_skill_chains(Hero.new("Stranger", 0), _chains([{"trigger": "knight_rally", "then": ["knight_charge"]}])), "not on the roster")

	var good: Array[Dictionary] = _chains([{"trigger": "knight_rally", "then": ["knight_charge", "knight_iron_cut"]}, {"trigger": "knight_charge", "then": ["knight_ground_slam"]}])
	assert_true(GameSession.set_skill_chains(hero, good), GameSession.last_action_error)
	assert_eq(hero.skill_chains, good)
	assert_true(GameSession.set_skill_chains(hero, [] as Array[Dictionary]), "an empty list clears them")
	assert_eq(hero.skill_chains, [] as Array[Dictionary])


## Boundary #1: chains go to disk and come back; a legacy save without the key loads with none.
func test_chains_survive_a_real_disk_round_trip_and_a_legacy_save_loads() -> void:
	var hero: Hero = _knight("hero:k", 5)
	GameSession.add_hero(hero)
	var chains: Array[Dictionary] = _chains([{"trigger": "knight_rally", "then": ["knight_charge", "knight_iron_cut", "knight_charge"]}, {"trigger": "knight_buckler_blow", "then": ["knight_ground_slam"]}])
	assert_true(GameSession.set_skill_chains(hero, chains), GameSession.last_action_error)
	assert_string_contains(FileAccess.get_file_as_string(SaveService.SAVE_PATH), "knight_buckler_blow")
	_reload()
	assert_eq(GameSession.roster[0].skill_chains, chains)

	var payload: Dictionary = GameSession.to_dict()
	(payload["roster"][0] as Dictionary).erase("skill_chains")
	payload["version"] = SaveService.SAVE_VERSION
	FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE).store_string(JSON.stringify(payload))
	_reload()
	assert_false(SaveService.load_blocked, SaveService.load_block_reason)
	assert_eq(GameSession.roster[0].skill_chains, [] as Array[Dictionary], "a legacy hero has no chains")
	assert_push_warning_count(0)


## ---- the chain band

func test_steps_fire_in_order_and_the_chain_ends_after_the_last() -> void:
	var state: BattleState = _scene({"general_hearten": "auto", "general_brace": "auto"}, [_chain(RALLY, ["general_hearten", "general_brace"])])
	var hero: BattleActor = _hero(state)
	SIM._start_chain(state, hero, RALLY, true)
	assert_eq(_keys(hero), ["knight_rally", 0, 30, "enemy:t"], "the first step, 3 s to fire, aimed at the hero's opponent")
	assert_eq(_step(state, hero, 5), SIM.CHAIN_FIRED)
	assert_gt(hero.skill_cooldowns["general_hearten"], 0.0)
	assert_eq(hero.skill_cooldowns["general_brace"], 0.0, "one step at a time")
	assert_eq(_keys(hero), ["knight_rally", 1, 35, "enemy:t"], "the next step gets a fresh deadline")
	assert_eq(_step(state, hero, 6), SIM.CHAIN_FIRED)
	assert_gt(hero.skill_cooldowns["general_brace"], 0.0)
	assert_eq(_keys(hero), [null, null, null, null], "no chain after its last step")


func test_a_step_ready_on_its_deadline_fires_and_one_cooling_then_is_skipped_the_tick_after() -> void:
	var state: BattleState = _scene({"general_hearten": "auto", "general_brace": "auto"}, [_chain(RALLY, ["general_hearten", "general_brace"])])
	var hero: BattleActor = _hero(state)
	SIM._start_chain(state, hero, RALLY, true)
	assert_eq(_step(state, hero, 30), SIM.CHAIN_FIRED, "the deadline tick itself still counts")
	assert_gt(hero.skill_cooldowns["general_hearten"], 0.0)

	state = _scene({"general_hearten": "auto", "general_brace": "auto"}, [_chain(RALLY, ["general_hearten", "general_brace"])])
	hero = _hero(state)
	hero.skill_cooldowns["general_hearten"] = 30.0
	SIM._start_chain(state, hero, RALLY, true)
	assert_eq(_step(state, hero, 30), SIM.CHAIN_WAITING, "cooling on its deadline tick: it waits")
	assert_eq(hero.skill_cooldowns["general_brace"], 0.0, "and nothing behind it fires")
	assert_eq(_keys(hero), ["knight_rally", 0, 30, "enemy:t"])
	assert_eq(_step(state, hero, 31), SIM.CHAIN_FIRED, "the tick after: skipped, and the next step fires")
	assert_eq(hero.skill_cooldowns["general_hearten"], 30.0, "the skipped step did not cast")
	assert_gt(hero.skill_cooldowns["general_brace"], 0.0)
	assert_eq(_keys(hero), [null, null, null, null])


func test_a_step_that_is_off_or_not_on_the_bar_is_skipped_at_once_and_manual_fires() -> void:
	for mode: String in ["off", "absent"]:
		var kit: Dictionary = {"general_brace": "auto"} if mode == "absent" else {"general_hearten": mode, "general_brace": "auto"}
		var state: BattleState = _scene(kit, [_chain(RALLY, ["general_hearten", "general_brace"])])
		var hero: BattleActor = _hero(state)
		SIM._start_chain(state, hero, RALLY, true)
		assert_eq(_step(state, hero, 1), SIM.CHAIN_FIRED, mode)
		assert_eq(float(hero.skill_cooldowns.get("general_hearten", 0.0)), 0.0, "%s: never fired" % mode)
		assert_gt(hero.skill_cooldowns["general_brace"], 0.0, "%s: the step behind it went at once" % mode)
	var manual: BattleState = _scene({"general_hearten": "manual", "general_brace": "auto"}, [_chain(RALLY, ["general_hearten", "general_brace"])])
	SIM._start_chain(manual, _hero(manual), RALLY, true)
	assert_eq(_step(manual, _hero(manual), 1), SIM.CHAIN_FIRED)
	assert_gt(_hero(manual).skill_cooldowns["general_hearten"], 0.0, "a chain fires Manual steps")
	assert_eq(_hero(manual).skill_cooldowns["general_brace"], 0.0)


func test_a_weaponskill_step_fires_at_the_swing_even_on_manual_and_a_repeated_one_fires_twice() -> void:
	var state: BattleState = _scene({"knight_iron_cut": "manual", "general_hearten": "auto"}, [_chain(HEARTEN, ["knight_iron_cut", "knight_iron_cut"])])
	var hero: BattleActor = _hero(state)
	SIM._start_chain(state, hero, HEARTEN, true)
	var seen: Array[int] = []
	var cuts: int = 0
	for _i: int in 80:
		SIM.advance(state, TICK)
		if hero.effect_state.has("chain_step"):
			seen.append(int(hero.effect_state["chain_step"]))
		if hero.combo_skill == "knight_iron_cut":
			cuts += 1
			hero.combo_skill = ""
		if not hero.effect_state.has("chain_trigger"):
			break
	assert_eq(cuts, 2, "Iron Cut is Manual and rides two swings")
	assert_true(seen.has(0) and seen.has(1), "it stood on the first step and then the second")
	assert_false(hero.effect_state.has("chain_trigger"), "and ended")

	var off: BattleState = _scene({"knight_iron_cut": "off", "general_hearten": "auto", "general_brace": "auto"}, [_chain(RALLY, ["knight_iron_cut", "general_brace"])])
	SIM._start_chain(off, _hero(off), RALLY, true)
	assert_eq(_step(off, _hero(off), 1), SIM.CHAIN_FIRED, "an Off weaponskill step is skipped at once")
	assert_gt(_hero(off).skill_cooldowns["general_brace"], 0.0)


func test_a_counter_cuts_in_and_never_ends_a_chain_and_the_deadline_keeps_running() -> void:
	var state: BattleState = _scene({"knight_buckler_blow": "auto", "general_hearten": "auto"}, [_chain(RALLY, ["general_hearten"])])
	var hero: BattleActor = _hero(state)
	var enemy: BattleActor = SIM._actor_by_id(state, "enemy:t")
	_give(enemy, ["enemy_knight_crushing_blow"])
	hero.skill_cooldowns["general_hearten"] = 30.0
	SIM._start_chain(state, hero, RALLY, true)
	SIM._start_telegraph(state, enemy, SIM.ABILITIES["enemy_knight_crushing_blow"], hero.position, 1.2)
	SIM.advance(state, 0.2)
	assert_gt(hero.skill_cooldowns["knight_buckler_blow"], 0.0, "the counter answered the telegraph")
	assert_eq(_keys(hero), ["knight_rally", 0, 30, "enemy:t"], "the chain is exactly where it was, deadline included")
	var left: int = 0
	while hero.effect_state.has("chain_trigger") and left < 60:
		SIM.advance(state, TICK)
		left += 1
	assert_false(hero.effect_state.has("chain_trigger"), "the cold step was skipped at its deadline")
	assert_true(state.tick in [31, 32], "the deadline ran through the cut-in, tick %d" % state.tick)
	assert_gt(hero.skill_cooldowns["general_hearten"], 0.0, "still cold: it was skipped, not cast")

	# The chain goes on after the cut-in: the counter goes first, then the ready step follows the ability lock.
	state = _scene({"knight_buckler_blow": "auto", "general_hearten": "auto"}, [_chain(RALLY, ["general_hearten"])])
	hero = _hero(state)
	enemy = SIM._actor_by_id(state, "enemy:t")
	_give(enemy, ["enemy_knight_crushing_blow"])
	SIM._start_telegraph(state, enemy, SIM.ABILITIES["enemy_knight_crushing_blow"], hero.position, 1.2)
	SIM.advance(state, TICK)
	assert_eq(hero.skill_cooldowns["knight_buckler_blow"], 0.0, "control: the reaction delay is not up yet")
	SIM._start_chain(state, hero, RALLY, true)
	SIM.advance(state, TICK)
	var cut_in_tick: int = state.tick
	assert_gt(hero.skill_cooldowns["knight_buckler_blow"], 0.0, "the counter answered first")
	assert_eq(hero.skill_cooldowns["general_hearten"], 0.0, "the ready step waits out the ability lock")
	assert_eq(_keys(hero), ["knight_rally", 0, 31, "enemy:t"], "the chain is still at its first step")
	left = 0
	while hero.skill_cooldowns["general_hearten"] == 0.0 and left < 60:
		SIM.advance(state, TICK)
		left += 1
	assert_gt(hero.skill_cooldowns["general_hearten"], 0.0, "the chain goes on after the cut-in: the step fired")
	assert_gt(state.tick, cut_in_tick)
	assert_lt(state.tick, 31, "inside its deadline")
	assert_false(hero.effect_state.has("chain_trigger"), "it was the last step")


## A counter is an auto cast like any other: its chain starts when none runs and never replaces one that does.
func test_a_counter_that_is_a_trigger_starts_its_chain_only_when_none_runs() -> void:
	var kit: Dictionary = {"knight_buckler_blow": "auto", "general_hearten": "auto", "general_brace": "auto"}
	var chains: Array = [_chain(SIM.ABILITIES["knight_buckler_blow"], ["general_hearten"]), _chain(RALLY, ["general_brace"])]
	var state: BattleState = _scene(kit, chains)
	var hero: BattleActor = _hero(state)
	var enemy: BattleActor = SIM._actor_by_id(state, "enemy:t")
	_give(enemy, ["enemy_knight_crushing_blow"])
	hero.skill_cooldowns["general_hearten"] = 30.0
	SIM._start_telegraph(state, enemy, SIM.ABILITIES["enemy_knight_crushing_blow"], hero.position, 1.2)
	SIM.advance(state, 0.2)
	assert_gt(hero.skill_cooldowns["knight_buckler_blow"], 0.0, "the counter answered the telegraph")
	assert_eq(_keys(hero), ["knight_buckler_blow", 0, int(hero.effect_state["last_skill_tick"]) + 30, "enemy:t"], "and started its chain: none was running")

	state = _scene(kit, chains)
	hero = _hero(state)
	enemy = SIM._actor_by_id(state, "enemy:t")
	_give(enemy, ["enemy_knight_crushing_blow"])
	hero.skill_cooldowns["general_hearten"] = 30.0
	hero.skill_cooldowns["general_brace"] = 30.0
	SIM._start_chain(state, hero, RALLY, true)
	SIM._start_telegraph(state, enemy, SIM.ABILITIES["enemy_knight_crushing_blow"], hero.position, 1.2)
	SIM.advance(state, 0.2)
	assert_gt(hero.skill_cooldowns["knight_buckler_blow"], 0.0, "the counter answered the telegraph")
	assert_eq(_keys(hero), ["knight_rally", 0, 30, "enemy:t"], "the running chain was not replaced")


func test_a_heal_band_cut_in_leaves_the_chain_alone() -> void:
	var wounded: Dictionary = _unit("k", "knight", "ally", Vector2(2, 0))
	var state: BattleState = _scene({"cleric_sheltering_word": "auto", "general_brace": "auto"}, [_chain(HEARTEN, ["general_brace"])], "cleric", [wounded])
	var cleric: BattleActor = _hero(state)
	var knight: BattleActor = SIM._actor_by_id(state, "hero:k")
	knight.hp = 30.0
	cleric.skill_cooldowns["general_brace"] = 30.0
	SIM._start_chain(state, cleric, HEARTEN, true)
	SIM.advance(state, TICK)
	assert_gt(cleric.skill_cooldowns["cleric_sheltering_word"], 0.0, "Sheltering Word went out ahead of the chain")
	assert_eq(_keys(cleric), ["general_hearten", 0, 30, "enemy:t"], "the chain is untouched")


func test_the_chain_ends_when_its_target_is_gone_or_the_hero_is_given_another() -> void:
	var state: BattleState = _scene({"general_hearten": "auto"}, [_chain(RALLY, ["general_hearten"])])
	var hero: BattleActor = _hero(state)
	hero.skill_cooldowns["general_hearten"] = 30.0
	SIM._start_chain(state, hero, RALLY, true)
	assert_eq(_step(state, hero, 1), SIM.CHAIN_WAITING)
	SIM._actor_by_id(state, "enemy:t").life = BattleActor.LIFE_DEAD
	assert_eq(_step(state, hero, 2), SIM.CHAIN_NONE, "its target died")
	assert_eq(_keys(hero), [null, null, null, null])

	state = _scene({"general_hearten": "auto"}, [_chain(RALLY, ["general_hearten"])])
	hero = _hero(state)
	hero.skill_cooldowns["general_hearten"] = 30.0
	SIM._start_chain(state, hero, RALLY, true)
	hero.order_target_id = ""
	assert_eq(_step(state, hero, 1), SIM.CHAIN_WAITING, "an empty order (a kite hop, a regroup, a hold) keeps it")
	assert_eq(_keys(hero), ["knight_rally", 0, 30, "enemy:t"])
	hero.order_target_id = "enemy:t"
	assert_eq(_step(state, hero, 2), SIM.CHAIN_WAITING, "the same target keeps it")
	hero.order_target_id = "enemy:u"
	assert_eq(_step(state, hero, 3), SIM.CHAIN_NONE, "a different target ends it")
	assert_eq(_keys(hero), [null, null, null, null])

	# The same through a real order: the same target keeps the chain, another enemy ends it on the next tick.
	state = _scene({"general_hearten": "auto"}, [_chain(RALLY, ["general_hearten"])])
	hero = _hero(state)
	hero.skill_cooldowns["general_hearten"] = 30.0
	SIM._start_chain(state, hero, RALLY, true)
	assert_true(SIM.issue_command(state, {"kind": SIM.COMMAND_ATTACK, "actor_ids": ["hero:h"], "target_id": "enemy:t"})["accepted"])
	SIM.advance(state, TICK)
	assert_eq(_keys(hero), ["knight_rally", 0, 30, "enemy:t"], "an order onto the chain's own target keeps it")
	assert_true(SIM.issue_command(state, {"kind": SIM.COMMAND_ATTACK, "actor_ids": ["hero:h"], "target_id": "enemy:u"})["accepted"])
	SIM.advance(state, TICK)
	assert_eq(hero.order_target_id, "enemy:u")
	assert_eq(_keys(hero), [null, null, null, null], "an order onto another enemy ends it")

	# A hold order clears the hero's target as a kite hop does, and the running fight keeps the chain.
	state = _scene({"general_hearten": "auto"}, [_chain(RALLY, ["general_hearten"])])
	hero = _hero(state)
	hero.skill_cooldowns["general_hearten"] = 30.0
	SIM._start_chain(state, hero, RALLY, true)
	assert_true(SIM.issue_command(state, {"kind": SIM.COMMAND_HOLD, "actor_ids": ["hero:h"]})["accepted"])
	for _i: int in 5:
		SIM.advance(state, TICK)
	assert_eq(hero.order_target_id, "", "a hold has no target")
	assert_eq(_keys(hero), ["knight_rally", 0, 30, "enemy:t"], "and the chain waits on")

	# Started with no opponent: it takes the first one the hero is given.
	state = _scene({"general_hearten": "auto"}, [_chain(RALLY, ["general_hearten"])])
	hero = _hero(state)
	hero.skill_cooldowns["general_hearten"] = 30.0
	hero.order_target_id = ""
	SIM._start_chain(state, hero, RALLY, true)
	assert_eq(hero.effect_state["chain_target"], "")
	assert_eq(_step(state, hero, 1), SIM.CHAIN_WAITING)
	assert_eq(hero.effect_state["chain_target"], "", "still none to take")
	hero.order_target_id = "enemy:u"
	assert_eq(_step(state, hero, 2), SIM.CHAIN_WAITING)
	assert_eq(hero.effect_state["chain_target"], "enemy:u")


## The sim's own kite (ig-uu7.3, set up as test_kite.gd does): a ranger with a melee enemy closing in hops away
## mid-chain. The hop's order has no target, and the chain waits it out and goes on.
func test_a_kite_hop_mid_chain_keeps_the_chain_and_its_next_step_fires_in_time() -> void:
	var piercing: AbilityDefinition = SIM.ABILITIES["ranger_piercing_shot"]
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
	var snapshots: Array[Dictionary] = [_unit("h", "ranger", "ally", Vector2(0, 0), {"hp": 10000.0, "atk": 50.0, "defense": 20.0, "level": 1})]
	var state: BattleState = SIM.create_run("chain:kite", snapshots, zone, _squads(snapshots), {}, {"healing": 0, "revival": 0}, 13, "normal", 1)
	var ranger: BattleActor = _hero(state)
	# Every spawned enemy waits far off but one melee, which is on the ranger: what test_kite.gd's _park and _lock do.
	var foe: BattleActor = null
	for enemy: BattleActor in state.actors:
		if enemy.faction != "enemy":
			continue
		if foe == null and enemy.attack_range < BALANCE.battle_kite_trigger_range:
			foe = enemy
			continue
		enemy.position = Vector2(float(enemy.spawn_index % 3) * 2.0 - 2.0, 19.0)
		enemy.effect_state["home_position"] = [enemy.position.x, enemy.position.y]
		enemy.order_kind = ""
		enemy.order_target_id = ""
	foe.position = Vector2(0, 2.5)
	foe.effect_state["home_position"] = [0.0, 2.5]
	foe.order_kind = SIM.COMMAND_ATTACK
	foe.order_target_id = ranger.id
	foe.max_hp = 100000.0
	foe.hp = foe.max_hp
	foe.atk = 1.0
	_give(ranger, ["ranger_piercing_shot", "general_brace"])
	ranger.skill_cooldowns["ranger_piercing_shot"] = 60.0
	ranger.skill_cooldowns["general_brace"] = 60.0
	ranger.chains.assign([_chain(piercing, ["general_brace"])])
	ranger.order_kind = SIM.COMMAND_ATTACK
	ranger.order_target_id = foe.id
	SIM._start_chain(state, ranger, piercing, true)
	var running: Array = ["ranger_piercing_shot", 0, 30, foe.id]
	assert_eq(_keys(ranger), running)
	var hopped: bool = false
	var hop_over: int = -1
	for _i: int in 60:
		SIM.advance(state, TICK)
		if ranger.effect_state.get("kite_point") is Array:
			hopped = true
			assert_eq(ranger.order_target_id, "", "tick %d: the hop's order has no target" % state.tick)
			assert_eq(_keys(ranger), running, "tick %d: mid-hop the chain is untouched" % state.tick)
		elif hopped:
			hop_over = state.tick
			break
	assert_true(hopped, "the enemy closed in, so the sim's own kite hopped the ranger")
	assert_between(hop_over, 1, 29, "the hop ended inside the chain's deadline")
	assert_eq(_keys(ranger), running, "and the chain came out of it as it went in")
	# The step comes ready: it fires on the chain's target, inside its deadline, and the chain is over.
	ranger.skill_cooldowns["general_brace"] = 0.0
	while ranger.skill_cooldowns["general_brace"] == 0.0 and state.tick < 40:
		SIM.advance(state, TICK)
	assert_gt(ranger.skill_cooldowns["general_brace"], 0.0, "the next step fired after the hop")
	assert_lte(state.tick, 30, "before its deadline")
	assert_false(ranger.effect_state.has("chain_trigger"), "it was the last step")


func test_a_hero_going_down_ends_its_chain_and_a_stale_one_on_a_downed_body_is_erased() -> void:
	var state: BattleState = _scene({"general_hearten": "auto"}, [_chain(RALLY, ["general_hearten"])])
	var hero: BattleActor = _hero(state)
	hero.skill_cooldowns["general_hearten"] = 30.0
	SIM._start_chain(state, hero, RALLY, true)
	SIM._take_damage(state, SIM._actor_by_id(state, "enemy:t"), hero, 1000000.0)
	assert_eq(hero.life, BattleActor.LIFE_DOWNED)
	assert_eq(_keys(hero), [null, null, null, null], "downed: no chain")

	# A body saved with one (a checkpoint from a build that let it stay) loses it on the next tick.
	hero.effect_state.merge({"chain_trigger": "knight_rally", "chain_step": 0, "chain_deadline_tick": 5, "chain_target": "enemy:t"})
	SIM.advance(state, TICK)
	assert_eq(_keys(hero), [null, null, null, null])


## No chain key outlives a living hero: a hero that leaves the fight mid-chain (a retreat, a timeout) keeps none.
func test_a_hero_extracted_mid_chain_keeps_no_chain_key() -> void:
	var state: BattleState = _scene({"general_hearten": "auto"}, [_chain(RALLY, ["general_hearten"])])
	var hero: BattleActor = _hero(state)
	hero.skill_cooldowns["general_hearten"] = 30.0
	SIM._start_chain(state, hero, RALLY, true)
	assert_eq(_keys(hero), ["knight_rally", 0, 30, "enemy:t"], "mid-chain")
	SIM._extract_actor(state, hero)
	assert_eq(hero.life, BattleActor.LIFE_EXTRACTED)
	assert_eq(_keys(hero), [null, null, null, null], "extracted: no chain")

	# The timeout takes every living ally out through the same call.
	state = _scene({"general_hearten": "auto"}, [_chain(RALLY, ["general_hearten"])])
	hero = _hero(state)
	hero.skill_cooldowns["general_hearten"] = 30.0
	SIM._start_chain(state, hero, RALLY, true)
	SIM._finish_timeout(state)
	assert_eq(state.status, "timeout")
	assert_eq(hero.life, BattleActor.LIFE_EXTRACTED)
	assert_eq(_keys(hero), [null, null, null, null], "timed out: no chain")

	# And a real retreat: the hero at the exit, ordered to leave, with a chain running.
	state = _scene({"general_hearten": "auto"}, [_chain(RALLY, ["general_hearten"])])
	hero = _hero(state)
	hero.skill_cooldowns["general_hearten"] = 30.0
	SIM._start_chain(state, hero, RALLY, true)
	hero.position = SIM._objective_point(state, "exit_position")
	assert_true(SIM.issue_command(state, {"kind": SIM.COMMAND_RETREAT, "actor_ids": ["hero:h"]})["accepted"])
	SIM.advance(state, TICK)
	assert_eq(hero.life, BattleActor.LIFE_EXTRACTED, "it reached the exit")
	assert_eq(_keys(hero), [null, null, null, null], "retreated: no chain")


## ---- where a step aims

func test_a_heal_step_lands_on_the_lowest_hp_ally_in_reach_the_caster_included() -> void:
	var state: BattleState = _scene({"cleric_mend": "auto"}, [_chain(HEARTEN, ["cleric_mend"])], "cleric", [_unit("a", "knight", "ally", Vector2(2, 0)), _unit("b", "knight", "ally", Vector2(-2, 0)), _unit("far", "knight", "ally", Vector2(9, 0))])
	var cleric: BattleActor = _hero(state)
	var ally: BattleActor = SIM._actor_by_id(state, "hero:a")
	var lowest: BattleActor = SIM._actor_by_id(state, "hero:b")
	var far: BattleActor = SIM._actor_by_id(state, "hero:far")
	ally.hp = 60.0
	lowest.hp = 30.0
	far.hp = 5.0
	SIM._start_chain(state, cleric, HEARTEN, true)
	assert_eq(_step(state, cleric, 1), SIM.CHAIN_FIRED)
	assert_gt(lowest.hp, 30.0, "Mend went to the weakest ally, not the chain's foe")
	assert_eq(ally.hp, 60.0)
	assert_eq(far.hp, 5.0, "the weakest one out of reach is not aimed at")

	state = _scene({"cleric_mend": "auto"}, [_chain(HEARTEN, ["cleric_mend"])], "cleric", [_unit("a", "knight", "ally", Vector2(2, 0))])
	cleric = _hero(state)
	cleric.hp = 20.0
	SIM._actor_by_id(state, "hero:a").hp = 60.0
	SIM._start_chain(state, cleric, HEARTEN, true)
	assert_eq(_step(state, cleric, 1), SIM.CHAIN_FIRED)
	assert_gt(cleric.hp, 20.0, "the caster counts")


func test_a_revive_step_takes_the_nearest_downed_ally_and_waits_when_there_is_none_or_it_is_out_of_reach() -> void:
	var state: BattleState = _scene({"cleric_hearthcall": "auto"}, [_chain(HEARTEN, ["cleric_hearthcall"])], "cleric", [_unit("a", "knight", "ally", Vector2(2, 0)), _unit("b", "knight", "ally", Vector2(3, 0))])
	var cleric: BattleActor = _hero(state)
	var near: BattleActor = SIM._actor_by_id(state, "hero:a")
	var next: BattleActor = SIM._actor_by_id(state, "hero:b")
	SIM._start_chain(state, cleric, HEARTEN, true)
	assert_eq(_step(state, cleric, 1), SIM.CHAIN_WAITING, "nobody is down: it waits")
	assert_eq(cleric.skill_cooldowns["cleric_hearthcall"], 0.0)
	next.life = BattleActor.LIFE_DOWNED
	near.life = BattleActor.LIFE_DOWNED
	near.hp = 0.0
	next.hp = 0.0
	assert_eq(_step(state, cleric, 2), SIM.CHAIN_FIRED)
	assert_eq(near.life, BattleActor.LIFE_ALIVE, "the nearest one was raised")
	assert_eq(next.life, BattleActor.LIFE_DOWNED)
	assert_eq(_keys(cleric), [null, null, null, null], "and it was the last step")

	var out: BattleState = _scene({"cleric_hearthcall": "auto"}, [_chain(HEARTEN, ["cleric_hearthcall"])], "cleric", [_unit("a", "knight", "ally", Vector2(5, 0))])
	var body: BattleActor = SIM._actor_by_id(out, "hero:a")
	body.life = BattleActor.LIFE_DOWNED
	body.hp = 0.0
	SIM._start_chain(out, _hero(out), HEARTEN, true)
	assert_eq(_step(out, _hero(out), 30), SIM.CHAIN_WAITING, "5 away is out of its range 4")
	assert_eq(_step(out, _hero(out), 31), SIM.CHAIN_NONE, "and it was skipped at the deadline")
	assert_eq(body.life, BattleActor.LIFE_DOWNED)


func test_rally_raises_a_downed_ally_first_and_with_none_down_casts_as_its_buff() -> void:
	var state: BattleState = _scene({"knight_rally": "auto"}, [_chain(HEARTEN, ["knight_rally"])], "knight", [_unit("a", "ranger", "ally", Vector2(1, 1))])
	var body: BattleActor = SIM._actor_by_id(state, "hero:a")
	body.life = BattleActor.LIFE_DOWNED
	body.hp = 0.0
	var knight: BattleActor = _hero(state)
	SIM._start_chain(state, knight, HEARTEN, true)
	assert_eq(_step(state, knight, 1), SIM.CHAIN_FIRED)
	assert_eq(body.life, BattleActor.LIFE_ALIVE, "revive first")

	var buff: BattleState = _scene({"knight_rally": "auto"}, [_chain(HEARTEN, ["knight_rally"])], "knight", [_unit("a", "ranger", "ally", Vector2(1, 1))])
	SIM._start_chain(buff, _hero(buff), HEARTEN, true)
	assert_eq(_step(buff, _hero(buff), 1), SIM.CHAIN_FIRED, "nobody down: the buff half casts")
	assert_gt(_hero(buff).skill_cooldowns["knight_rally"], 0.0)
	assert_false(_hero(buff).statuses.is_empty(), "with its shield on the Knight")


func test_a_zone_step_aims_by_its_side_allies_at_the_weakest_ally_opponents_at_the_foe() -> void:
	var state: BattleState = _scene({"cleric_hearthward": "auto"}, [_chain(HEARTEN, ["cleric_hearthward"])], "cleric", [_unit("a", "knight", "ally", Vector2(3, 0))])
	SIM._actor_by_id(state, "hero:a").hp = 40.0
	SIM._start_chain(state, _hero(state), HEARTEN, true)
	assert_eq(_step(state, _hero(state), 1), SIM.CHAIN_FIRED)
	assert_eq(state.field_objects.size(), 1)
	assert_eq(_vector(state.field_objects[0]["center"]), Vector2(3, 0), "Hearthward is centred on the weakest ally, not on the foe at (1, 0)")

	var circle: BattleState = _scene({"mage_rime_circle": "auto"}, [_chain(HEARTEN, ["mage_rime_circle"])], "mage")
	SIM._actor_by_id(circle, "enemy:t").position = Vector2(5, 0)
	SIM._start_chain(circle, _hero(circle), HEARTEN, true)
	assert_eq(_step(circle, _hero(circle), 1), SIM.CHAIN_FIRED)
	assert_eq(_vector(circle.field_objects[0]["center"]), Vector2(5, 0), "Rime Circle is centred on the chain's foe")


func test_a_wall_step_goes_across_the_line_to_the_foe_as_a_wall_cast_by_hand_does() -> void:
	var state: BattleState = _scene({"mage_rime_wall": "auto"}, [_chain(HEARTEN, ["mage_rime_wall"])], "mage")
	SIM._actor_by_id(state, "enemy:t").position = Vector2(5, 0)
	SIM._start_chain(state, _hero(state), HEARTEN, true)
	assert_eq(_step(state, _hero(state), 1), SIM.CHAIN_FIRED)
	var start: Vector2 = _vector(state.field_objects[0]["start"])
	var finish: Vector2 = _vector(state.field_objects[0]["end"])
	var middle: Vector2 = (start + finish) * 0.5
	assert_almost_eq(start.distance_to(finish), 6.0, 0.0001, "6 long")
	assert_almost_eq(start.x, finish.x, 0.0001, "across the line from the caster to the foe")
	assert_lt(middle.x, 5.0, "the foe ends up on the far side of it")
	assert_gt(middle.x, 3.5)
	assert_almost_eq(middle.y, 0.0, 0.0001)

	var by_hand: BattleState = _scene({"mage_rime_wall": "auto"}, [], "mage")
	SIM._actor_by_id(by_hand, "enemy:t").position = Vector2(5, 0)
	assert_true(SIM.issue_command(by_hand, {"kind": SIM.COMMAND_ABILITY, "actor_ids": ["hero:h"], "target_id": "enemy:t"})["accepted"])
	assert_eq(by_hand.field_objects[0]["start"], state.field_objects[0]["start"], "the same wall")
	assert_eq(by_hand.field_objects[0]["end"], state.field_objects[0]["end"])


func test_a_step_that_needs_the_foe_waits_when_it_is_out_of_its_band() -> void:
	var state: BattleState = _scene({"knight_charge": "auto"}, [_chain(HEARTEN, ["knight_charge"])])
	SIM._start_chain(state, _hero(state), HEARTEN, true)
	assert_eq(_step(state, _hero(state), 30), SIM.CHAIN_WAITING, "the foe is 1 away, inside Charge's min range 4")
	assert_eq(_hero(state).skill_cooldowns["knight_charge"], 0.0)
	assert_eq(_step(state, _hero(state), 31), SIM.CHAIN_NONE, "and it is skipped at the deadline")


## ---- how a chain starts

func test_a_trigger_starts_a_chain_only_when_none_runs_and_a_hand_cast_replaces_one() -> void:
	var state: BattleState = _scene({"general_hearten": "auto", "general_brace": "auto"}, [_chain(HEARTEN, ["general_brace"]), _chain(BRACE, ["general_hearten"])])
	var hero: BattleActor = _hero(state)
	state.tick = 5
	SIM._start_chain(state, hero, RALLY, false)
	assert_eq(_keys(hero), [null, null, null, null], "a skill with no chain starts none")
	SIM._start_chain(state, hero, BRACE, false)
	assert_eq(_keys(hero), ["general_brace", 0, 35, "enemy:t"], "an auto cast starts its chain when none runs")
	state.tick = 9
	SIM._start_chain(state, hero, HEARTEN, false)
	assert_eq(_keys(hero), ["general_brace", 0, 35, "enemy:t"], "and never replaces one that runs")

	# A trigger fired by hand does, from step 0 with a fresh deadline.
	state.tick = 12
	assert_true(SIM.issue_command(state, {"kind": SIM.COMMAND_ABILITY, "actor_ids": ["hero:h"], "target_id": "hero:h", "point": [0.0, 0.0]})["accepted"])
	assert_gt(hero.skill_cooldowns["general_hearten"], 0.0, "the signature is the first ability on the bar")
	assert_eq(_keys(hero), ["general_hearten", 0, 42, "enemy:t"])


func test_a_step_never_starts_a_chain() -> void:
	var state: BattleState = _scene({"general_hearten": "auto", "general_brace": "auto"}, [_chain(RALLY, ["general_hearten"]), _chain(HEARTEN, ["general_brace"])])
	var hero: BattleActor = _hero(state)
	SIM._start_chain(state, hero, RALLY, true)
	assert_eq(_step(state, hero, 1), SIM.CHAIN_FIRED)
	assert_gt(hero.skill_cooldowns["general_hearten"], 0.0, "the step was a trigger of its own")
	assert_eq(_keys(hero), [null, null, null, null], "but it started none: the first chain just ended")
	assert_eq(hero.skill_cooldowns["general_brace"], 0.0)


func test_a_waiting_chain_shuts_the_buff_and_attack_bands_but_the_swing_still_lands() -> void:
	var lands: Array = []
	for chained: bool in [false, true]:
		var state: BattleState = _scene({"ranger_hunters_focus": "auto", "general_hearten": "auto"}, [_chain(RALLY, ["general_hearten"])] if chained else [], "ranger")
		var hero: BattleActor = _hero(state)
		var foe: BattleActor = SIM._actor_by_id(state, "enemy:t")
		hero.skill_cooldowns["general_hearten"] = 40.0
		if chained:
			SIM._start_chain(state, hero, RALLY, true)
		for _i: int in 25:
			SIM.advance(state, TICK)
		lands.append([hero.skill_cooldowns["ranger_hunters_focus"] > 0.0, foe.hp < foe.max_hp])
	assert_eq(lands[0], [true, true], "control: with no chain it casts Hunter's Focus and swings")
	assert_eq(lands[1], [false, true], "waiting on a cold step: no other ability goes, the swing lands")


func test_a_charge_chain_held_by_a_cold_step_blocks_the_slam_until_its_deadline() -> void:
	var slam_ticks: Array[int] = []
	for chained: bool in [false, true]:
		var state: BattleState = _scene({"knight_charge": "auto", "knight_ground_slam": "auto", "general_brace": "auto"}, [_chain(CHARGE, ["general_brace"])] if chained else [])
		var hero: BattleActor = _hero(state)
		hero.skill_cooldowns["general_brace"] = 40.0
		SIM._actor_by_id(state, "enemy:t").position = Vector2(7, 0)
		assert_true(SIM._use_skill(state, hero, CHARGE, SIM._actor_by_id(state, "enemy:t"), Vector2(7, 0), _rng()))
		assert_eq(hero.effect_state.has("chain_trigger"), chained, "the auto cast started its chain")
		for _i: int in 80:
			SIM.advance(state, TICK)
			if hero.skill_cooldowns["knight_ground_slam"] > 0.0:
				break
		assert_gt(hero.skill_cooldowns["knight_ground_slam"], 0.0, "the Slam really cast (chained: %s)" % chained)
		assert_eq(hero.effect_state["last_skill_id"], "knight_ground_slam")
		slam_ticks.append(state.tick)
	assert_lt(slam_ticks[0], 20, "control: the Slam follows the Charge once the lock is over")
	assert_gte(slam_ticks[1], 30, "held: not before the cold step's deadline")
	assert_lt(slam_ticks[1], 45, "and it does go once the chain is over")


func test_a_slam_step_follows_the_charge_it_is_chained_to() -> void:
	var state: BattleState = _scene({"knight_charge": "auto", "knight_ground_slam": "auto"}, [_chain(CHARGE, ["knight_ground_slam"])])
	var hero: BattleActor = _hero(state)
	var foe: BattleActor = SIM._actor_by_id(state, "enemy:t")
	foe.position = Vector2(7, 0)
	assert_true(SIM._use_skill(state, hero, CHARGE, foe, foe.position, _rng()))
	assert_eq(hero.effect_state["chain_trigger"], "knight_charge")
	for _i: int in 60:
		SIM.advance(state, TICK)
		if hero.skill_cooldowns["knight_ground_slam"] > 0.0:
			break
	assert_gt(hero.skill_cooldowns["knight_ground_slam"], 0.0)
	assert_gte(state.tick, 10, "after the 1 s ability lock")
	assert_lt(state.tick, 20)
	assert_false(hero.effect_state.has("chain_trigger"), "it was the last step")


## ---- checkpoints (boundaries #1 and #4)

## Godot's JSON parser misrounds some 17-digit numbers by 1 ulp, so the reload is held to 1e-6 against the
## unbroken fight, and its chain (step, deadline, target) to exactly.
func test_a_running_chain_saves_in_json_validates_and_plays_on_identically() -> void:
	var state: BattleState = _scene({"general_hearten": "auto", "knight_iron_cut": "manual"}, [_chain(RALLY, ["general_hearten", "knight_iron_cut", "knight_iron_cut"])])
	var hero: BattleActor = _hero(state)
	hero.skill_cooldowns["general_hearten"] = 4.0
	SIM._start_chain(state, hero, RALLY, true)
	for _i: int in 3:
		SIM.advance(state, TICK)
	assert_eq(_keys(hero), ["knight_rally", 0, 30, "enemy:t"], "mid-chain")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict(), "", true, true)) as Dictionary
	assert_eq(SIM.validate_snapshot(saved), "")
	var loaded := BattleState.from_dict(saved)
	assert_eq(_keys(SIM._actor_by_id(loaded, "hero:h")), ["knight_rally", 0, 30, "enemy:t"])
	assert_eq(SIM._actor_by_id(loaded, "hero:h").chains, hero.chains)
	for _i: int in 130:
		SIM.advance(state, TICK)
		SIM.advance(loaded, TICK)
		assert_eq(_keys(SIM._actor_by_id(loaded, "hero:h")), _keys(hero), "tick %d" % state.tick)
		assert_eq(Compare.mismatch(_where(loaded.to_dict()), _where(state.to_dict())), "", "tick %d" % state.tick)
		if not hero.effect_state.has("chain_trigger"):
			break
	assert_false(hero.effect_state.has("chain_trigger"), "the chain ran to its end on both")

	var bare: BattleState = _scene({"general_hearten": "auto"}, [])
	assert_false(_hero(bare).to_dict().has("chains"), "no chain, no key: the no-chain fight saves as it did")
	assert_false(_hero(bare).effect_state.has("chain_trigger"))
	assert_true(_hero(state).to_dict().has("chains"))


func test_a_snapshot_with_a_bad_chain_state_is_refused() -> void:
	var state: BattleState = _scene({"general_hearten": "auto"}, [_chain(RALLY, ["general_hearten"])])
	SIM._start_chain(state, _hero(state), RALLY, true)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict(), "", true, true)) as Dictionary
	assert_eq(SIM.validate_snapshot(saved), "")
	var actor: Dictionary = (saved["actors"] as Array).filter(func(entry: Dictionary) -> bool: return entry["id"] == "hero:h")[0]
	(actor["effect_state"] as Dictionary)["chain_target"] = "enemy:gone"
	assert_eq(SIM.validate_snapshot(saved), "Battle actor references must target existing actors.", "a chain_target that names no actor")


func test_a_leg_carry_keeps_the_chains_and_drops_the_running_chain() -> void:
	var state: BattleState = _scene({"general_hearten": "auto"}, [_chain(RALLY, ["general_hearten"])])
	SIM._start_chain(state, _hero(state), RALLY, true)
	var carried_in: Array[Dictionary] = []
	for actor: BattleActor in state.actors:
		carried_in.append(actor.to_dict())
	var carried: BattleState = _battle(carried_in)
	var hero: BattleActor = _hero(carried)
	assert_eq(_keys(hero), [null, null, null, null], "its ticks were the last leg's")
	assert_eq(hero.chains, [_chain(RALLY, ["general_hearten"])] as Array[Dictionary], "but the chains stay")

	var incident: Dictionary = GameSession._incident_snapshot(state, ["h"] as Array[String])
	assert_eq(SIM.validate_snapshot(incident), "")
	for actor: Dictionary in incident["actors"]:
		for key: String in BattleActor.CHAIN_KEYS:
			assert_false((actor["effect_state"] as Dictionary).has(key), "%s: no %s in a rescue's snapshot" % [actor["id"], key])


## A fight saved mid-chain by the real SaveService reads back as its full-precision round trip and runs on as
## it, through the chain; against the unbroken fight it is held to 1e-6.
func test_a_mid_chain_save_and_reload_through_disk_runs_on_identically() -> void:
	GameSession.set("_save_deferred_depth", 1)
	var ids: Array[String] = []
	for index: int in 5:
		var hero := Hero.new("Chainer %d" % index, 7)
		hero.def_id = &"knight"
		hero.level = 20
		hero.instance_id = "hero:chain:%d" % index
		hero.skill_chains = [{"trigger": "knight_rally", "then": ["knight_charge", "knight_ground_slam"]}]
		GameSession.roster.append(hero)
		ids.append(hero.instance_id)
	var preset_id: String = GameSession.save_team_preset("", "Chain", ids, "verdant_outskirts")
	var order_id: String = GameSession.dispatch_force([preset_id], "verdant_outskirts", 1, {}, {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0})
	assert_ne(order_id, "", GameSession.last_action_error)
	var seeded: Dictionary = JSON.parse_string(JSON.stringify(GameSession.to_dict(), "", true, true)) as Dictionary
	((seeded["expedition_orders"] as Array)[0] as Dictionary)["battle"]["rng_state"] = "1"
	GameSession.from_dict(seeded)
	GameSession.tick_expeditions(0.5)
	# Staged at the save: one Knight ordered onto an enemy 8 away with a second beside it, already
	# holding a chain on its Charge step.
	var staged: Dictionary = JSON.parse_string(JSON.stringify(GameSession.to_dict(), "", true, true)) as Dictionary
	var battle_data: Dictionary = ((staged["expedition_orders"] as Array)[0] as Dictionary)["battle"]
	var actors: Array = battle_data["actors"]
	var knight: Dictionary = actors.filter(func(actor: Dictionary) -> bool: return actor["faction"] == "ally")[0]
	assert_eq(knight["chains"], [{"trigger": "knight_rally", "then": ["knight_charge", "knight_ground_slam"]}], "dispatch fixed the chains into the snapshot")
	var enemies: Array = actors.filter(func(actor: Dictionary) -> bool: return actor["faction"] == "enemy" and actor["life"] == "alive")
	assert_gte(enemies.size(), 3, "three enemies to stage")
	knight["position"] = [-4.0, 0.0]
	knight["order_kind"] = SIM.COMMAND_ATTACK
	knight["order_target_id"] = enemies[0]["id"]
	knight["effect_state"]["direct_order"] = true
	knight["skill_cooldowns"]["knight_charge"] = 0.0
	knight["skill_cooldowns"]["knight_ground_slam"] = 0.0
	knight["ability_lock"] = 0.0
	var tick: int = int(battle_data["tick"])
	knight["effect_state"]["chain_trigger"] = "knight_rally"
	knight["effect_state"]["chain_step"] = 0
	knight["effect_state"]["chain_deadline_tick"] = tick + 30
	knight["effect_state"]["chain_target"] = enemies[0]["id"]
	enemies[0]["position"] = [4.0, 0.0]
	enemies[1]["position"] = [5.0, 1.0]
	enemies[2]["position"] = [0.0, 0.3]
	GameSession.from_dict(staged)
	var battle: Dictionary = GameSession.expedition_orders[0]["battle"]
	assert_eq(str(battle["status"]), "active", "mid-fight")
	var straight := BattleState.from_dict(battle.duplicate(true))
	var round_trip: Dictionary = JSON.parse_string(JSON.stringify(battle, "", true, true)) as Dictionary
	var written := BattleState.from_dict(round_trip)
	var start: int = written.tick
	GameSession.set("_save_deferred_depth", 0)
	var saved: bool = SaveService.save()
	GameSession.set("_save_deferred_depth", 1)
	assert_true(saved, SaveService.last_write_error)
	var stamp := RegEx.create_from_string("\"saved_at_unix\": ?[^,}\\n]+")
	var text: String = FileAccess.get_file_as_string(SaveService.SAVE_PATH)
	var file := FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	file.store_string(stamp.sub(text, "\"saved_at_unix\":%d" % int(Time.get_unix_time_from_system() + 3600.0)))
	file.close()
	GameSession.from_dict({"roster": []})
	assert_true(SaveService.load_game(), SaveService.load_block_reason)
	var read_back: Dictionary = GameSession.expedition_orders[0]["battle"]
	assert_eq(Compare.first_difference(read_back, round_trip), "", "the file reads back as the round trip, raw")
	var loaded := BattleState.from_dict(read_back)
	var chain_id: String = str(knight["id"])
	assert_eq(_keys(SIM._actor_by_id(loaded, chain_id)), ["knight_rally", 0, tick + 30, str(enemies[0]["id"])], "the chain came back off the disk")
	# All three run to a terminal state (the zone's time limit bounds it), the reload's chain watched on the way:
	# the Charge step fires before its deadline, then the Slam after it. A skip would not show either.
	var fired: Array[String] = []
	var step_one_tick: int = -1
	var limit: int = int(ceilf(written.max_seconds / TICK)) + 10
	var ran: int = 0
	while ran < limit and (straight.status == "active" or written.status == "active" or loaded.status == "active"):
		SIM.advance(straight, TICK)
		SIM.advance(written, TICK)
		SIM.advance(loaded, TICK)
		ran += 1
		var effects: Dictionary = SIM._actor_by_id(loaded, chain_id).effect_state
		var last: String = str(effects.get("last_skill_id", ""))
		if int(effects.get("last_skill_tick", 0)) > start and (fired.is_empty() or fired.back() != last):
			fired.append(last)
		if step_one_tick < 0 and effects.has("chain_trigger") and int(effects["chain_step"]) == 1:
			step_one_tick = loaded.tick
	assert_lt(ran, limit, "it reached a terminal state")
	assert_ne(loaded.status, "active")
	assert_eq(loaded.status, written.status)
	assert_eq(straight.status, written.status, "the unbroken fight ended the same way")
	assert_gt(step_one_tick, 0, "the chain reached its second step")
	assert_lt(step_one_tick, tick + 30, "by firing the Charge before its deadline, not by skipping it at it")
	assert_true(fired.has("knight_charge") and fired.find("knight_ground_slam") > fired.find("knight_charge"), "the Charge and then the Slam fired after the reload: %s" % [fired])
	assert_eq(Compare.first_difference(loaded.to_dict(), written.to_dict()), "", "the reload ends as its round trip, whole")
	assert_eq(Compare.first_difference(SIM.snapshot_outcome(loaded).to_dict(), SIM.snapshot_outcome(written).to_dict()), "", "with the same outcome")
	assert_eq(Compare.first_difference(SIM.snapshot_outcome(loaded).to_dict(), SIM.snapshot_outcome(straight).to_dict()), "", "and the unbroken fight's outcome, whole")
	assert_eq(written.tick, straight.tick, "on the same tick as the unbroken fight")
	assert_eq(Compare.mismatch(_where(loaded.to_dict()), _where(straight.to_dict())), "", "and as the unbroken fight, to 1e-6")


## ---- the skill panel (boundary #2: the panel is built in code, so its names are the seam)

func test_the_skill_panel_edits_chains_through_set_skill_chains_and_shows_a_refusal() -> void:
	GameSession.add_hero(_knight("hero:k", 1))
	var panel := SkillPanel.new()
	add_child_autofree(panel)
	panel.show_hero(GameSession.roster[0])
	var rows: Node = panel.find_child("Rows", true, false)
	var error: Label = panel.find_child("Error", true, false) as Label
	assert_true(rows.has_node("ChainsTitle"))
	assert_false((rows.get_node("NewChain") as Button).disabled)
	(rows.get_node("NewChain") as Button).pressed.emit()
	assert_eq(GameSession.roster[0].skill_chains, _chains([{"trigger": "knight_rally", "then": ["knight_iron_cut"]}]), "the first free trigger, and the first other skill as its step")
	assert_string_contains(FileAccess.get_file_as_string(SaveService.SAVE_PATH), "knight_iron_cut", "saved")
	(rows.get_node("Chain_knight_rally/AddStep") as Button).pressed.emit()
	assert_eq(_steps(0), ["knight_iron_cut", "knight_rally"])
	(rows.get_node("Chain_knight_rally/Step_1/Up") as Button).pressed.emit()
	assert_eq(_steps(0), ["knight_rally", "knight_iron_cut"])
	assert_true((rows.get_node("Chain_knight_rally/Step_0/Up") as Button).disabled)
	assert_true((rows.get_node("Chain_knight_rally/Step_1/Down") as Button).disabled)
	var menu: OptionButton = rows.get_node("Chain_knight_rally/Step_0/Skill") as OptionButton
	assert_eq(menu.item_count, 4, "no passive in the menu")
	menu.select(3)
	menu.item_selected.emit(3)
	assert_eq(_steps(0), ["knight_ground_slam", "knight_iron_cut"])
	(rows.get_node("Chain_knight_rally/Step_0/Remove") as Button).pressed.emit()
	assert_eq(_steps(0), ["knight_iron_cut"])
	assert_true((rows.get_node("Chain_knight_rally/Step_0/Remove") as Button).disabled, "a chain keeps a step; Remove chain takes it away")

	# A second chain, then a trigger already taken: refused, shown, nothing changed.
	(rows.get_node("NewChain") as Button).pressed.emit()
	assert_eq(GameSession.roster[0].skill_chains.map(func(chain: Dictionary) -> String: return chain["trigger"]), ["knight_rally", "knight_iron_cut"])
	var trigger: OptionButton = rows.get_node("Chain_knight_iron_cut/Head/Trigger") as OptionButton
	trigger.select(0)
	trigger.item_selected.emit(0)
	assert_string_contains(error.text, "same trigger")
	assert_eq(GameSession.roster[0].skill_chains.map(func(chain: Dictionary) -> String: return chain["trigger"]), ["knight_rally", "knight_iron_cut"])
	assert_eq((rows.get_node("Chain_knight_iron_cut/Head/Trigger") as OptionButton).get_selected(), 1, "the panel shows what is saved")
	(rows.get_node("Chain_knight_iron_cut/Head/Trigger") as OptionButton).select(2)
	(rows.get_node("Chain_knight_iron_cut/Head/Trigger") as OptionButton).item_selected.emit(2)
	assert_eq(error.text, "", "a good change clears it")
	assert_true(rows.has_node("Chain_knight_charge"))

	# The cap: Add step goes dark at 8, and a 9th pushed at it anyway is refused.
	while not (rows.get_node("Chain_knight_rally/AddStep") as Button).disabled:
		(rows.get_node("Chain_knight_rally/AddStep") as Button).pressed.emit()
	assert_eq(_steps(0).size(), BALANCE.skill_chain_max_steps)
	(rows.get_node("Chain_knight_rally/AddStep") as Button).pressed.emit()
	assert_string_contains(error.text, "at most 8 steps")
	assert_eq(_steps(0).size(), BALANCE.skill_chain_max_steps, "unchanged")

	# New chain goes dark when every skill triggers one; Remove chain frees a trigger.
	assert_true(GameSession.set_skill_chains(GameSession.roster[0], _chains([{"trigger": "knight_rally", "then": ["knight_charge"]}, {"trigger": "knight_iron_cut", "then": ["knight_rally"]}, {"trigger": "knight_charge", "then": ["knight_rally"]}, {"trigger": "knight_ground_slam", "then": ["knight_rally"]}])), GameSession.last_action_error)
	panel.refresh()
	assert_true((rows.get_node("NewChain") as Button).disabled)
	(rows.get_node("Chain_knight_charge/Head/RemoveChain") as Button).pressed.emit()
	assert_false(rows.has_node("Chain_knight_charge"))
	assert_false((rows.get_node("NewChain") as Button).disabled)


## ---- helpers

func _knight(id: String, level: int) -> Hero:
	var hero := Hero.new("Knight", 0)
	hero.def_id = &"knight"
	hero.instance_id = id
	hero.level = level
	return hero


func _chains(raw: Array) -> Array[Dictionary]:
	var chains: Array[Dictionary] = []
	chains.assign(raw)
	return chains


func _steps(index: int) -> Array:
	return GameSession.roster[0].skill_chains[index]["then"]


func _chain(trigger: AbilityDefinition, then: Array) -> Dictionary:
	return {"trigger": str(trigger.skill_id), "then": then}


func _reload() -> void:
	GameSession.set("_save_deferred_depth", 1)
	GameSession.from_dict({"roster": []})
	GameSession.set("_save_deferred_depth", 0)
	assert_true(SaveService.load_game(), SaveService.load_block_reason)


func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	return rng


func _vector(value: Variant) -> Vector2:
	return Vector2(float((value as Array)[0]), float((value as Array)[1]))


func _hero(state: BattleState) -> BattleActor:
	return SIM._actor_by_id(state, "hero:h")


## The running chain: [trigger, step, deadline, target], nulls when none.
func _keys(actor: BattleActor) -> Array:
	var effects: Dictionary = actor.effect_state
	if not effects.has("chain_trigger"):
		return [null, null, null, null]
	return [effects["chain_trigger"], int(effects["chain_step"]), int(effects["chain_deadline_tick"]), effects["chain_target"]]


## One chain step at tick, with the ability lock off so a step can follow a step.
func _step(state: BattleState, actor: BattleActor, tick: int) -> int:
	state.tick = tick
	actor.ability_lock = 0.0
	return SIM._chain_step(state, actor, _rng())


## hero:h (the archetype's class, kit and chains as given) at (0, 0) ordered onto enemy:t at (1, 0), with
## enemy:u at (0, 1.2) and extra units. Nothing dies in it: the hero has 10000 HP and the enemies 100000.
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


## What the chain's steps decide: exact facts first, then the floats.
func _where(snapshot: Dictionary) -> Array:
	var result: Array = []
	for actor: Dictionary in snapshot["actors"]:
		var effects: Dictionary = actor["effect_state"]
		result.append(["%s %s %s %d %s %d %d" % [snapshot["rng_state"], actor["id"], actor["life"], int(snapshot["tick"]), effects.get("last_skill_id", ""), int(effects.get("last_skill_tick", 0)), int(effects.get("chain_step", -1))], float(actor["hp"]), float(actor["position"][0]), float(actor["position"][1])])
	return result


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
	var state: BattleState = SIM.create_run("chain:1", snapshots, ZoneDefinition.definition_for(&"verdant_outskirts"), _squads(snapshots), {"auto_battle": false, "suppress_ally_crit": true}, {"healing": 0, "revival": 0}, 7, "rescue", 1)
	for actor: BattleActor in state.actors:
		_give(actor, [])
	return state


func _give(actor: BattleActor, skill_ids: Array) -> void:
	actor.skills.clear()
	actor.skill_cooldowns.clear()
	for skill_id: String in skill_ids:
		actor.add_skill(SIM.ABILITIES[skill_id])
