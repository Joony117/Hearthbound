extends GutTest

# ig-wgj.11: masterwork draughts are two more supply kinds (DECISIONS.md 2026-09-23, masterwork
# draughts; SYSTEMS.md § Keepers and professions). Only a home master alchemist brews them. Auto-use
# spends the regular draught first; manual use picks a tier; cooldown, range and the reserve are shared.

const BALANCE: BalanceTable = preload("res://balance.tres")
const MASTER_XP: float = 300.0 * 60.0
const MW_HEAL: String = "healing_masterwork"
const MW_REVIVE: String = "revival_masterwork"
const Session = preload("res://systems/game_session.gd")


func before_each() -> void:
	GameSession.set_process(false)
	GameSession.set("_save_deferred_depth", 1)
	SaveService.load_blocked = false
	SaveService.load_block_reason = ""
	GameSession.from_dict({"roster": []})
	GameSession.last_action_error = ""


func after_each() -> void:
	GameSession.set("_save_deferred_depth", 0)
	GameSession.set_process(true)


func test_brewing_is_refused_without_a_home_master_alchemist() -> void:
	GameSession.parts[0] = 200
	for kind: String in [MW_HEAL, MW_REVIVE]:
		var kind_plan: Dictionary = GameSession.preview_bulk_supplies(kind, 1, 0)
		assert_false(bool(kind_plan["valid"]), "%s: no keeper" % kind)
		assert_eq(str(kind_plan["error"]), "Only a master alchemist at home brews masterwork draughts.")
	var alchemist: Hero = _alchemist()
	alchemist.profession_xp[&"alchemy"] = MASTER_XP
	alchemist.passions = [&"farming", &"mining"] as Array[StringName]
	assert_false(bool(GameSession.preview_bulk_supplies(MW_HEAL, 1, 0)["valid"]), "skill 5 without the passion")
	alchemist.passions = [&"alchemy", &"farming"] as Array[StringName]
	var plan: Dictionary = GameSession.preview_bulk_supplies(MW_HEAL, 1, 0)
	assert_true(bool(plan["valid"]), str(plan.get("error", "")))
	# The alchemist leaves between the preview and the commit: the plan is stale.
	alchemist.profession_xp[&"alchemy"] = 0.0
	assert_false(GameSession.commit_bulk_plan(plan))
	# The mutator refuses on its own too, whatever plan reaches it.
	assert_false(GameSession._commit_profile_mutation(GameSession._apply_bulk_plan_in_memory.bind(plan)))
	assert_eq(GameSession.last_action_error, "Only a master alchemist at home brews masterwork draughts.")
	assert_eq(GameSession.parts[0], 200, "nothing spent")
	assert_eq(int(GameSession.supplies[MW_HEAL]), 0, "nothing brewed")


func test_costs_match_the_table_with_and_without_the_alchemy_discount() -> void:
	# SYSTEMS.md: 15 and 45 F parts, less Alchemy's 10% per skill level, never below 1.
	# ponytail: 45 x 0.7 is 31.4999... in floats, so skill 3 rounds to 31, not 32 (wgj.10's formula).
	var healing: Array[int] = [15, 14, 12, 11, 9, 8]
	var revival: Array[int] = [45, 41, 36, 31, 27, 23]
	for skill: int in 6:
		assert_eq(BulkOperations.supply_parts_cost(MW_HEAL, skill, BALANCE), healing[skill], "healing %d" % skill)
		assert_eq(BulkOperations.supply_parts_cost(MW_REVIVE, skill, BALANCE), revival[skill], "revival %d" % skill)
	_master_alchemist()
	for kind: String in [MW_HEAL, MW_REVIVE]:
		GameSession.parts[0] = 100
		var cost: int = healing[5] if kind == MW_HEAL else revival[5]
		var plan: Dictionary = GameSession.preview_bulk_supplies(kind, 2, 0)
		assert_eq(int(plan["cost_parts"][0]), 2 * cost, "%s preview" % kind)
		assert_eq(str((plan["entries"] as Array)[0]["name"]), "Masterwork %s draught" % kind.trim_suffix("_masterwork"))
		assert_true(GameSession.commit_bulk_plan(plan), GameSession.last_action_error)
		assert_eq(GameSession.parts[0], 100 - 2 * cost, "%s settle" % kind)
		assert_eq(int(GameSession.supplies[kind]), 2)


func test_auto_heal_spends_regular_first_then_masterwork() -> void:
	var state: BattleState = _pair({"healing": 1, MW_HEAL: 1}, {}, false)
	var user: BattleActor = state.actors[0]
	var patient: BattleActor = state.actors[1]
	BattleSimulation.advance(state, 0.1)
	assert_almost_eq(patient.hp, 50.0, 0.01, "regular: 40% of max HP")
	assert_eq(state.supplies_remaining, {"healing": 0, "revival": 0, MW_HEAL: 1, MW_REVIVE: 0})
	user.item_cooldown = 0.0
	patient.hp = 10.0
	BattleSimulation.advance(state, 0.1)
	assert_almost_eq(patient.hp, 70.0, 0.01, "masterwork once regular is gone: 60%")
	assert_eq(int(state.supplies_remaining[MW_HEAL]), 0)


func test_auto_revive_spends_regular_first_then_masterwork() -> void:
	var state: BattleState = _pair({"revival": 1, MW_REVIVE: 1}, {}, true)
	BattleSimulation.advance(state, 0.1)
	assert_eq(state.actors[1].life, BattleActor.LIFE_ALIVE)
	assert_almost_eq(state.actors[1].hp, 35.0, 0.01, "regular: 35%")
	assert_eq(int(state.supplies_remaining["revival"]), 0)
	assert_eq(int(state.supplies_remaining[MW_REVIVE]), 1)
	state = _pair({MW_REVIVE: 1}, {}, true)
	BattleSimulation.advance(state, 0.1)
	assert_almost_eq(state.actors[1].hp, 50.0, 0.01, "masterwork: 50%")
	assert_eq(int(state.supplies_remaining[MW_REVIVE]), 0)


func test_manual_use_picks_either_tier_and_shares_the_cooldown_and_range() -> void:
	var state: BattleState = _pair({"healing": 1, MW_HEAL: 1}, {}, false)
	var user: BattleActor = state.actors[0]
	var patient: BattleActor = state.actors[1]
	var masterwork: Dictionary = {"kind": BattleSimulation.COMMAND_ITEM_HEALING, "actor_ids": [user.id], "target_id": patient.id, "masterwork": true}
	assert_true(bool(BattleSimulation.issue_command(state, masterwork)["accepted"]))
	assert_almost_eq(patient.hp, 70.0, 0.01)
	assert_eq(int(state.supplies_remaining["healing"]), 1, "the regular stock is untouched")
	assert_eq(int(state.supplies_remaining[MW_HEAL]), 0)
	patient.hp = 10.0
	var regular: Dictionary = {"kind": BattleSimulation.COMMAND_ITEM_HEALING, "actor_ids": [user.id], "target_id": patient.id}
	assert_false(bool(BattleSimulation.issue_command(state, regular)["accepted"]), "one cooldown for both tiers")
	user.item_cooldown = 0.0
	assert_true(bool(BattleSimulation.issue_command(state, regular)["accepted"]))
	assert_almost_eq(patient.hp, 50.0, 0.01)
	# A named tier never falls back to the other one.
	state = _pair({MW_HEAL: 1}, {}, false)
	regular["actor_ids"] = [state.actors[0].id]
	regular["target_id"] = state.actors[1].id
	assert_false(bool(BattleSimulation.issue_command(state, regular)["accepted"]))
	assert_eq(int(state.supplies_remaining[MW_HEAL]), 1)
	regular["masterwork"] = "yes"
	assert_eq(str(BattleSimulation.issue_command(state, regular)["error"]), "The draught tier needs a bool masterwork value.")
	# One revival range for both tiers.
	state = _pair({MW_REVIVE: 1}, {}, true)
	state.actors[1].position = state.actors[0].position + Vector2(BattleSimulation.BALANCE.battle_revival_range + 0.5, 0.0)
	var revive: Dictionary = {"kind": BattleSimulation.COMMAND_ITEM_REVIVAL, "actor_ids": [state.actors[0].id], "target_id": state.actors[1].id, "masterwork": true}
	assert_false(bool(BattleSimulation.issue_command(state, revive)["accepted"]), "out of range")
	state.actors[1].position = state.actors[0].position
	assert_true(bool(BattleSimulation.issue_command(state, revive)["accepted"]))
	assert_almost_eq(state.actors[1].hp, 50.0, 0.01)


func test_reserve_last_revival_counts_both_tiers() -> void:
	var state: BattleState = _pair({MW_REVIVE: 1}, {"reserve_last_revival": true}, true)
	BattleSimulation.advance(state, 0.1)
	assert_eq(state.actors[1].life, BattleActor.LIFE_DOWNED, "the last draught of either tier is held")
	assert_eq(int(state.supplies_remaining[MW_REVIVE]), 1)
	var manual: Dictionary = {"kind": BattleSimulation.COMMAND_ITEM_REVIVAL, "actor_ids": [state.actors[0].id], "target_id": state.actors[1].id, "masterwork": true}
	assert_true(bool(BattleSimulation.issue_command(state, manual)["accepted"]), "manual use may spend it")
	state = _pair({"revival": 1, MW_REVIVE: 1}, {"reserve_last_revival": true}, true)
	BattleSimulation.advance(state, 0.1)
	assert_eq(state.actors[1].life, BattleActor.LIFE_ALIVE, "two in all: one may go")
	assert_eq(int(state.supplies_remaining["revival"]), 0)
	assert_eq(int(state.supplies_remaining[MW_REVIVE]), 1)


func test_settlement_refunds_each_kind_exactly_once_including_a_wipe() -> void:
	for status: String in ["victory", "stranded"]:
		GameSession.from_dict({"roster": []})
		_stock({"healing": 2, "revival": 1, MW_HEAL: 3, MW_REVIVE: 2})
		var order_id: String = _dispatch(_loadout({"healing": 1, "revival": 1, MW_HEAL: 2, MW_REVIVE: 2}), 1)
		assert_ne(order_id, "", GameSession.last_action_error)
		assert_eq(GameSession.supplies, {"healing": 1, "revival": 0, MW_HEAL: 1, MW_REVIVE: 0}, "escrowed")
		var order: Dictionary = GameSession.expedition_orders[0]
		assert_eq(order["escrow"], {"healing": 1, "revival": 1, MW_HEAL: 2, MW_REVIVE: 2})
		var battle: Dictionary = order["battle"] as Dictionary
		battle["status"] = status
		battle["supplies_remaining"] = {"healing": 1, "revival": 0, MW_HEAL: 1, MW_REVIVE: 2}
		if status == "stranded":
			for actor: Dictionary in battle["actors"]:
				if str(actor["faction"]) == "ally":
					actor["life"] = BattleActor.LIFE_DOWNED
					actor["hp"] = 0.0
		order["remaining_seconds"] = 0.0
		GameSession.tick_expeditions(0.1)
		assert_true(GameSession.expedition_orders.is_empty(), status)
		var expected: Dictionary = {"healing": 2, "revival": 0, MW_HEAL: 2, MW_REVIVE: 2}
		assert_eq(GameSession.supplies, expected, "%s: the remainder comes home" % status)
		GameSession.tick_expeditions(0.1)
		assert_eq(GameSession.supplies, expected, "%s: and only once" % status)


func test_the_forecast_agrees_with_the_unattended_run() -> void:
	var zone: ZoneDefinition = ZoneDefinition.definition_for(&"verdant_outskirts")
	var snapshots: Array[Dictionary] = [
		{"hero_id": "hero:a", "archetype": "knight", "hp": 120.0, "atk": 12.0, "defense": 8.0, "speed": 100.0, "crit_rate": 0.0, "crit_damage": 1.5, "squad_id": "alpha"},
		{"hero_id": "hero:b", "archetype": "ranger", "hp": 90.0, "atk": 12.0, "defense": 5.0, "speed": 100.0, "crit_rate": 0.0, "crit_damage": 1.5, "squad_id": "alpha"},
	]
	var squads: Array[Dictionary] = [{"id": "alpha", "name": "Alpha", "hero_ids": ["hero:a", "hero:b"], "stance": "stay_together", "guard_target_id": ""}]
	var policies: Dictionary = {"heal_below": 0.99}
	var escrow: Dictionary = {"healing": 0, "revival": 0, MW_HEAL: 5, MW_REVIVE: 1}
	var forecast: Dictionary = BattleSimulation.forecast("mw:forecast", snapshots, zone, squads, policies, escrow, 7)
	var state: BattleState = BattleSimulation.create_run("mw:forecast", snapshots, zone, squads, policies, escrow, 7)
	# The battle's own bound: the zone's x its pace (ig-1jw).
	var outcome: BattleOutcome = BattleSimulation.advance(state, state.max_seconds)
	assert_eq(forecast["normal"], outcome.to_dict())
	assert_lt(int((forecast["normal"]["supplies_remaining"] as Dictionary)[MW_HEAL]), 5, "the forecast spent masterwork draughts")


# The forecast above is fed its stocks by hand; here every GameSession path that builds a run
# (dispatch, repeat refill, rescue) must hand the simulation the masterwork stock it escrowed.
func test_dispatch_repeat_and_rescue_carry_the_masterwork_stock_into_the_run() -> void:
	_stock({"healing": 2, "revival": 2, MW_HEAL: 4, MW_REVIVE: 4})
	var escrow: Dictionary = {"healing": 1, "revival": 0, MW_HEAL: 2, MW_REVIVE: 1}
	var order_id: String = _dispatch(_loadout(escrow), 2)
	assert_ne(order_id, "", GameSession.last_action_error)
	var order: Dictionary = GameSession.expedition_orders[0]
	assert_eq(order["escrow"], escrow)
	assert_eq((order["battle"] as Dictionary)["supplies_remaining"], escrow, "dispatch")
	assert_eq(GameSession.supplies, {"healing": 1, "revival": 2, MW_HEAL: 2, MW_REVIVE: 3})
	var battle: Dictionary = order["battle"] as Dictionary
	battle["status"] = "victory"
	battle["supplies_remaining"] = {"healing": 1, "revival": 0, MW_HEAL: 1, MW_REVIVE: 1}
	order["remaining_seconds"] = 0.0
	GameSession.tick_expeditions(0.1)
	_land_repeat_checks()
	assert_eq(GameSession.expedition_orders.size(), 1, "the repeat leg starts: " + GameSession.last_action_error)
	order = GameSession.expedition_orders[0]
	assert_eq(order["escrow"], escrow)
	assert_eq((order["battle"] as Dictionary)["supplies_remaining"], escrow, "repeat refill")
	assert_eq(GameSession.supplies, {"healing": 1, "revival": 2, MW_HEAL: 1, MW_REVIVE: 3}, "refund, then refill")
	# The repeat's safety forecast is the run it starts.
	var team: Array[Hero] = []
	for hero_id: String in Session._string_array(order["hero_ids"]):
		team.append(GameSession.hero_by_id(hero_id))
	var squads: Array[Dictionary] = []
	for squad: Dictionary in order["squads"]:
		squads.append(squad)
	var zone: ZoneDefinition = ZoneDefinition.definition_for(&"verdant_outskirts")
	var forecast: Dictionary = BattleSimulation.forecast(order_id + ":repeat", GameSession._team_snapshots(team, squads), zone, squads, order["policies"] as Dictionary, order["escrow"] as Dictionary, int(order["run_seed"]))
	var run: BattleState = BattleState.from_dict(order["battle"] as Dictionary)
	var outcome: Dictionary = BattleSimulation.advance(run, zone.max_battle_seconds).to_dict()
	for key: String in outcome:
		# Enemy ids carry the run's name ("<order>:repeat:..." in the forecast); the count must match.
		var same: Variant = (forecast["normal"][key] as Array).size() == (outcome[key] as Array).size() if key == "enemy_dead_ids" else forecast["normal"][key] == outcome[key]
		assert_true(same, "repeat forecast: " + key)
	# Rescue.
	var stranded := Hero.new("Stranded", 7)
	stranded.def_id = &"mage"
	stranded.level = 80
	GameSession.roster.append(stranded)
	var incident_id: String = _strand(stranded)
	var rescuer := Hero.new("Rescuer", 7)
	rescuer.def_id = &"ranger"
	rescuer.level = 80
	GameSession.roster.append(rescuer)
	GameSession.team_presets.append({"id": "rescue", "name": "Rescue", "hero_ids": [rescuer.instance_id], "zone_id": "verdant_outskirts"})
	var rescue_escrow: Dictionary = {"healing": 0, "revival": 1, MW_HEAL: 0, MW_REVIVE: 2}
	var rescue_id: String = GameSession.dispatch_rescue(incident_id, "rescue", _loadout(rescue_escrow))
	assert_ne(rescue_id, "", GameSession.last_action_error)
	var rescue: Dictionary = GameSession.expedition_orders[GameSession._order_index(rescue_id)]
	assert_eq(rescue["escrow"], rescue_escrow)
	assert_eq((rescue["battle"] as Dictionary)["supplies_remaining"], rescue_escrow, "rescue")
	assert_eq(GameSession.supplies, {"healing": 1, "revival": 1, MW_HEAL: 1, MW_REVIVE: 1})


func test_no_hand_written_supply_kind_list_is_left() -> void:
	for path: String in ["res://systems/game_session.gd", "res://combat/battle/battle_simulation.gd", "res://combat/battle/battle_view.gd", "res://hub/hub.gd", "res://hub/hub_ui_builder.gd", "res://hub/bulk_operations.gd"]:
		var source: String = FileAccess.get_file_as_string(path)
		assert_false(source.contains("[\"healing\", \"revival\"]"), path)
		assert_false(source.contains("\"keep_healing\""), path)
		assert_false(source.contains("{\"healing\": 0, \"revival\": 0}"), path)


func test_a_disk_round_trip_keeps_stocks_loadouts_escrow_and_a_battle_in_flight() -> void:
	GameSession.set("_save_deferred_depth", 0)
	_stock({"healing": 3, "revival": 1, MW_HEAL: 4, MW_REVIVE: 2})
	var loadout: Dictionary = _loadout({"healing": 1, MW_HEAL: 2, MW_REVIVE: 1})
	loadout["keep_" + MW_HEAL] = 1
	var order_id: String = _dispatch(loadout, 1)
	assert_ne(order_id, "", GameSession.last_action_error)
	var order: Dictionary = (GameSession.expedition_orders[0] as Dictionary).duplicate(true)
	var supplies: Dictionary = GameSession.supplies.duplicate()
	assert_true(SaveService.save(), SaveService.last_write_error)
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveService.SAVE_PATH)) as Dictionary
	GameSession.from_dict({"roster": []})
	_load_in_the_future(saved)
	assert_eq(GameSession.supplies, supplies)
	var loaded: Dictionary = GameSession.expedition_orders[0]
	# JSON reads every number back as a float; compare through it.
	for key: String in ["loadout", "escrow"]:
		assert_eq(loaded[key], JSON.parse_string(JSON.stringify(order[key])), key)
	assert_eq((loaded["battle"] as Dictionary)["supplies_remaining"], JSON.parse_string(JSON.stringify((order["battle"] as Dictionary)["supplies_remaining"])))
	assert_eq(int((loaded["battle"] as Dictionary)["supplies_remaining"][MW_HEAL]), 2)


func test_a_save_from_before_masterwork_with_an_order_in_flight_loads_and_settles() -> void:
	GameSession.set("_save_deferred_depth", 0)
	_stock({"healing": 3, "revival": 1})
	assert_ne(_dispatch(_loadout({"healing": 2, "revival": 1}), 1), "", GameSession.last_action_error)
	assert_true(SaveService.save(), SaveService.last_write_error)
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveService.SAVE_PATH)) as Dictionary
	# The shape every save had before this change: two kinds everywhere.
	for kind: String in [MW_HEAL, MW_REVIVE]:
		(saved["supplies"] as Dictionary).erase(kind)
		var old_order: Dictionary = (saved["expedition_orders"] as Array)[0]
		(old_order["loadout"] as Dictionary).erase(kind)
		(old_order["loadout"] as Dictionary).erase("keep_" + kind)
		(old_order["escrow"] as Dictionary).erase(kind)
		((old_order["battle"] as Dictionary)["supplies_remaining"] as Dictionary).erase(kind)
	assert_eq(((saved["expedition_orders"] as Array)[0]["loadout"] as Dictionary).size(), 4, "the old four-key loadout")
	GameSession.from_dict({"roster": []})
	_load_in_the_future(saved)
	assert_eq(GameSession.supplies, {"healing": 1, "revival": 0, MW_HEAL: 0, MW_REVIVE: 0}, "a missing kind is 0")
	assert_eq(GameSession.expedition_orders.size(), 1)
	var order: Dictionary = GameSession.expedition_orders[0]
	(order["battle"] as Dictionary)["status"] = "victory"
	order["remaining_seconds"] = 0.0
	GameSession.tick_expeditions(0.1)
	assert_true(GameSession.expedition_orders.is_empty())
	assert_eq(GameSession.supplies, {"healing": 3, "revival": 1, MW_HEAL: 0, MW_REVIVE: 0}, "the old escrow comes home")
	assert_true(SaveService.save(), SaveService.last_write_error)
	assert_true(SaveService.load_game(), SaveService.load_block_reason)


func test_brewed_stock_stays_usable_after_the_alchemist_leaves_or_dies() -> void:
	var alchemist: Hero = _master_alchemist()
	GameSession.parts[0] = 100
	assert_true(GameSession.commit_bulk_plan(GameSession.preview_bulk_supplies(MW_REVIVE, 2, 0)), GameSession.last_action_error)
	assert_true(GameSession.unstation_hero(alchemist), GameSession.last_action_error)
	assert_false(GameSession.keeper_is_master(&"Apothecary"))
	var order_id: String = _dispatch(_loadout({MW_REVIVE: 1}), 1)
	assert_ne(order_id, "", GameSession.last_action_error)
	assert_eq(int(GameSession.supplies[MW_REVIVE]), 1)
	GameSession.kill_hero(alchemist, &"", BALANCE)
	assert_null(GameSession.hero_by_id(alchemist.instance_id))
	assert_eq(int(GameSession.supplies[MW_REVIVE]), 1, "no clawback")
	# And the escrowed draught still works in the field: one hero down beside another.
	var battle: Dictionary = GameSession.expedition_orders[0]["battle"] as Dictionary
	var user: Dictionary = (battle["actors"] as Array)[0]
	var body: Dictionary = (battle["actors"] as Array)[1]
	body.merge({"life": BattleActor.LIFE_DOWNED, "hp": 0.0, "position": (user["position"] as Array).duplicate()}, true)
	var result: Dictionary = GameSession.issue_battle_command(order_id, {"kind": BattleSimulation.COMMAND_ITEM_REVIVAL, "actor_ids": [user["id"]], "target_id": body["id"], "masterwork": true})
	assert_true(bool(result.get("accepted", false)), str(result.get("error", "")))
	var after: BattleState = BattleState.from_dict(GameSession.expedition_orders[0]["battle"] as Dictionary)
	assert_eq(int(after.supplies_remaining[MW_REVIVE]), 0)
	assert_eq(after.actors[1].life, BattleActor.LIFE_ALIVE)
	assert_almost_eq(after.actors[1].hp, after.actors[1].max_hp * 0.5, 0.01)


func test_the_hub_loadout_form_and_stock_show_both_tiers() -> void:
	_stock({"healing": 3, "revival": 1, MW_HEAL: 2, MW_REVIVE: 1})
	var hub: Node3D = (load("res://hub/hub.tscn") as PackedScene).instantiate() as Node3D
	add_child_autofree(hub)
	(hub.get_node("%HealingMasterworkAllocation") as SpinBox).value = 2
	(hub.get_node("%RevivalMasterworkFloor") as SpinBox).value = 1
	var loadout: Dictionary = hub.call("_battle_loadout")
	assert_eq(loadout, _loadout({MW_HEAL: 2, "keep_" + MW_REVIVE: 1}))
	var kinds: OptionButton = hub.get_node("%SupplyKind") as OptionButton
	assert_eq(kinds.item_count, 4)
	for index: int in kinds.item_count:
		assert_eq(kinds.get_item_metadata(index), BattleState.SUPPLY_KINDS[index])
	hub.call("_refresh_supply_stock")
	assert_eq((hub.get_node("%SupplyStock") as Label).text, "Healing 3 · Revival 1 · Masterwork healing 2 · Masterwork revival 1")


## One ranger (no rally) and a patient mage on the same spot, off the exit; a harmless enemy far off. The patient is
## alive at 10 of 100 HP, or downed. Pace 1: the authored HP (test_battle_pace covers xP).
func _pair(supplies: Dictionary, policies: Dictionary, downed: bool) -> BattleState:
	var zone: ZoneDefinition = ZoneDefinition.definition_for(&"verdant_outskirts")
	var patient: Dictionary = {"hero_id": "hero:patient", "archetype": "mage", "hp": 100.0, "current_hp": 10.0, "atk": 0.0, "defense": 10.0, "speed": 95.0, "crit_rate": 0.0, "crit_damage": 1.5, "squad_id": "rescue", "position": [0.0, 0.0]}
	if downed:
		patient.merge({"current_hp": 0.0, "life": "downed", "squad_id": ""}, true)
	var snapshots: Array[Dictionary] = [
		{"hero_id": "hero:user", "archetype": "ranger", "hp": 200.0, "atk": 0.0, "defense": 20.0, "speed": 100.0, "crit_rate": 0.0, "crit_damage": 1.5, "squad_id": "rescue", "position": [0.0, 0.0]},
		patient,
		{"id": "enemy:far", "hero_id": "", "archetype": "knight", "faction": "enemy", "hp": 100.0, "atk": 0.0, "defense": 10.0, "speed": 20.0, "crit_rate": 0.0, "crit_damage": 1.5, "squad_id": "enemy", "position": [15.0, 15.0]},
	]
	var members: Array = ["hero:user"] if downed else ["hero:user", "hero:patient"]
	var squads: Array[Dictionary] = [{"id": "rescue", "name": "Rescue", "hero_ids": members, "stance": "stay_together", "guard_target_id": ""}]
	var all_policies: Dictionary = {"auto_battle": true}
	all_policies.merge(policies, true)
	return BattleSimulation.create_run("mw:pair", snapshots, zone, squads, all_policies, supplies, 12, "rescue", 1)


func _alchemist() -> Hero:
	var hero := Hero.new("Ivo", 7)
	hero.def_id = &"knight"
	hero.level = 80
	hero.passions = [&"alchemy", &"farming"] as Array[StringName]
	GameSession.add_hero(hero)
	assert_true(GameSession.station_hero(hero, &"Apothecary"), GameSession.last_action_error)
	return hero


func _master_alchemist() -> Hero:
	var hero: Hero = _alchemist()
	hero.profession_xp[&"alchemy"] = MASTER_XP
	assert_true(GameSession.keeper_is_master(&"Apothecary"))
	return hero


func _stock(stock: Dictionary) -> void:
	GameSession.supplies = BattleState.supplies_from(stock)


## Every allocation and reserve at 0, then the given fields.
func _loadout(fields: Dictionary) -> Dictionary:
	var loadout: Dictionary = Session._empty_loadout()
	loadout.merge(fields, true)
	return loadout


## A strong five-knight team into the first zone.
func _dispatch(loadout: Dictionary, runs: int) -> String:
	var ids: Array[String] = []
	for index: int in 5:
		var hero := Hero.new("Draught %d" % index, 7)
		hero.def_id = &"knight"
		hero.level = 80
		hero.instance_id = "hero:draught:%d" % index
		GameSession.roster.append(hero)
		ids.append(hero.instance_id)
	var preset_id: String = GameSession.save_team_preset("", "Draught Team", ids, "verdant_outskirts")
	return GameSession.dispatch_force([preset_id], "verdant_outskirts", runs, {}, loadout)


## A stranded incident for hero, from a real checkpoint (as test_keeper_bonuses.gd does).
func _strand(hero: Hero) -> String:
	var zone: ZoneDefinition = ZoneDefinition.definition_for(&"verdant_outskirts")
	var stats: Dictionary[StringName, float] = Hero.compute_final_stats(hero, Hero.definition_for(hero.def_id), BALANCE, 0)
	var state: BattleState = BattleSimulation.create_run("source", [{
		"hero_id": hero.instance_id, "archetype": str(hero.def_id), "hp": stats[Hero.STAT_HP], "atk": stats[Hero.STAT_ATK],
		"defense": stats[Hero.STAT_DEF], "speed": stats[Hero.STAT_SPD], "crit_rate": stats[Hero.STAT_CRIT_RATE],
		"crit_damage": stats[Hero.STAT_CRIT_DMG], "squad_id": "source-squad",
	}], zone, [{"id": "source-squad", "name": "Source", "hero_ids": [hero.instance_id], "stance": "stay_together", "guard_target_id": ""}], {}, {}, 544)
	state.actors[0].life = BattleActor.LIFE_DOWNED
	state.actors[0].hp = 0.0
	var snapshot: Dictionary = GameSession._incident_snapshot(state, [hero.instance_id] as Array[String])
	GameSession.stranded_incidents.append({"id": "incident-1", "source_order_id": "gone-source", "zone_id": "verdant_outskirts", "hero_ids": [hero.instance_id], "battle_snapshot": snapshot, "created_recovery_seconds": GameSession.rescue_clock_seconds, "paused": true, "expiry_pending": false, "active_rescue_order_id": ""})
	return "incident-1"


## Writes saved through the real loader, stamped in the future so no offline time passes.
func _load_in_the_future(saved: Dictionary) -> void:
	saved["saved_at_unix"] = Time.get_unix_time_from_system() + 3600.0
	var file := FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(saved, "\t"))
	file.close()
	assert_true(SaveService.load_game(), SaveService.load_block_reason)
	assert_false(SaveService.load_blocked, SaveService.load_block_reason)


## ig-7sn.6: a due repeat waits in "checking" until its forecast's two jobs land at a pulse. This sends
## them and lands them (without advancing any battle).
func _land_repeat_checks() -> void:
	GameSession._send_battle_checks()
	var deadline: int = Time.get_ticks_msec() + 60000
	while not GameSession._battle_checks.is_empty() and Time.get_ticks_msec() < deadline:
		OS.delay_msec(1)
		GameSession._land_battle_checks()
	assert_true(GameSession._battle_checks.is_empty(), "the repeat checks landed")
