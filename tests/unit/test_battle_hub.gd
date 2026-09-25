extends GutTest


func before_each() -> void:
	GameSession.from_dict({"roster": []})


func test_battle_settings_start_with_contract_defaults() -> void:
	var hub: Node3D = _instantiate_hub()
	assert_eq(hub._battle_policies(), {
		"auto_battle": true,
		"default_stance": "stay_together",
		"auto_heal": true,
		"auto_revive": true,
		"heal_below": 0.35,
		"reserve_last_revival": false,
		"retreat_when_supplies_empty": false,
	})
	assert_eq(hub._battle_loadout(), {
		"healing": 0,
		"revival": 0,
		"keep_healing": 0,
		"keep_revival": 0,
		"healing_masterwork": 0,
		"keep_healing_masterwork": 0,
		"revival_masterwork": 0,
		"keep_revival_masterwork": 0,
	})


func test_supply_preview_uses_kind_quantity_and_reserve_controls() -> void:
	var hub: Node3D = _instantiate_hub()
	var kind: OptionButton = hub.get_node("%SupplyKind") as OptionButton
	var quantity: SpinBox = hub.get_node("%SupplyQuantity") as SpinBox
	var reserve: SpinBox = hub.get_node("%SupplyReserve") as SpinBox
	assert_eq(kind.get_item_metadata(0), "healing")
	assert_eq(kind.get_item_metadata(1), "revival")
	assert_eq(quantity.value, 0.0)
	assert_eq(reserve.value, 0.0)
	assert_true((hub.get_node("%ConfirmSupply") as Button).disabled)


func test_scene_router_practice_payload_configures_battle_scene_on_entry() -> void:
	var hero := Hero.new("Router Practice", 0)
	hero.def_id = &"knight"
	var zone: ZoneDefinition = load("res://zones/defs/verdant_outskirts.tres") as ZoneDefinition
	SceneRouter.prepare_battle_practice([hero], zone)
	var view: BattleView = (load("res://combat/battle/battle_view.tscn") as PackedScene).instantiate() as BattleView
	add_child_autofree(view)
	assert_eq(view._mode, "practice")
	assert_eq(view._practice_state.kind, "practice")
	assert_null(view._controller)
	SceneRouter.clear_battle_payload()


func test_paused_incident_card_keeps_controls_selection_and_can_dispatch_first_rescue() -> void:
	var stranded := Hero.new("Stranded", 0)
	stranded.def_id = &"knight"
	var rescuer := Hero.new("Rescuer", 0)
	rescuer.def_id = &"ranger"
	GameSession.add_hero(stranded)
	GameSession.add_hero(rescuer)
	var preset_id: String = "rescue-preset"
	GameSession.team_presets.append({"id": preset_id, "name": "Ready Rescue", "hero_ids": [rescuer.instance_id], "zone_id": "verdant_outskirts"})
	var zone: ZoneDefinition = load("res://zones/defs/verdant_outskirts.tres") as ZoneDefinition
	var definition: HeroDefinition = Hero.definition_for(stranded.def_id)
	var stats: Dictionary[StringName, float] = Hero.compute_final_stats(stranded, definition, preload("res://balance.tres"), 0)
	var source_state: BattleState = BattleSimulation.create_run("source", [{
		"hero_id": stranded.instance_id,
		"archetype": str(stranded.def_id),
		"hp": stats[Hero.STAT_HP],
		"atk": stats[Hero.STAT_ATK],
		"defense": stats[Hero.STAT_DEF],
		"speed": stats[Hero.STAT_SPD],
		"crit_rate": stats[Hero.STAT_CRIT_RATE],
		"crit_damage": stats[Hero.STAT_CRIT_DMG],
		"squad_id": "source-squad",
	}], zone, [{"id": "source-squad", "name": "Source", "hero_ids": [stranded.instance_id], "stance": "stay_together", "guard_target_id": ""}], {}, {}, 544)
	source_state.actors[0].life = BattleActor.LIFE_DOWNED
	source_state.actors[0].hp = 0.0
	GameSession.stranded_incidents.append({"id": "incident-1", "source_order_id": "private-source-id", "zone_id": "verdant_outskirts", "hero_ids": [stranded.instance_id], "battle_snapshot": GameSession._incident_snapshot(source_state, [stranded.instance_id] as Array[String]), "created_recovery_seconds": GameSession.rescue_clock_seconds, "paused": true, "expiry_pending": false, "active_rescue_order_id": ""})
	var hub: Node3D = _instantiate_hub()
	hub._refresh_incident_cards()
	var cards: VBoxContainer = hub.get_node("%IncidentCards") as VBoxContainer
	assert_eq(cards.get_child_count(), 1)
	var panel: PanelContainer = cards.get_child(0) as PanelContainer
	var label: Label = panel.get_node("Box/IncidentLabel") as Label
	var actions: HBoxContainer = panel.get_node("Box/Actions") as HBoxContainer
	var preset_option: OptionButton = actions.get_node("RescueTeam") as OptionButton
	var dispatch: Button = actions.get_node("DispatchRescue") as Button
	assert_eq(preset_option.item_count, 1)
	preset_option.select(0)
	GameSession.rescue_clock_seconds += 12.0
	GameSession.expeditions_changed.emit()
	assert_eq(cards.get_child(0), panel)
	assert_eq(preset_option.selected, 0)
	assert_false(dispatch.disabled, "A ready team may dispatch the first rescue while the review window is paused")
	assert_false(label.text.contains("private-source-id"))
	dispatch.pressed.emit()
	assert_eq(GameSession.stranded_incidents.size(), 1)
	assert_false(bool(GameSession.stranded_incidents[0].get("paused", true)), "First successful rescue dispatch starts the incident window")
	assert_ne(str(GameSession.stranded_incidents[0].get("active_rescue_order_id", "")), "")


func test_open_rescue_team_popup_survives_timer_pulse_without_rebuilding_options() -> void:
	var stranded := Hero.new("Stranded", 0)
	stranded.def_id = &"knight"
	var rescuer := Hero.new("Rescuer", 0)
	rescuer.def_id = &"ranger"
	GameSession.add_hero(stranded)
	GameSession.add_hero(rescuer)
	var preset_id: String = GameSession.save_team_preset("", "Ready Rescue", [rescuer.instance_id], "verdant_outskirts")
	assert_ne(preset_id, "")
	var zone: ZoneDefinition = load("res://zones/defs/verdant_outskirts.tres") as ZoneDefinition
	var definition: HeroDefinition = Hero.definition_for(stranded.def_id)
	var stats: Dictionary[StringName, float] = Hero.compute_final_stats(stranded, definition, preload("res://balance.tres"), 0)
	var source_state: BattleState = BattleSimulation.create_run("source-popup", [{
		"hero_id": stranded.instance_id,
		"archetype": str(stranded.def_id),
		"hp": stats[Hero.STAT_HP],
		"atk": stats[Hero.STAT_ATK],
		"defense": stats[Hero.STAT_DEF],
		"speed": stats[Hero.STAT_SPD],
		"crit_rate": stats[Hero.STAT_CRIT_RATE],
		"crit_damage": stats[Hero.STAT_CRIT_DMG],
		"squad_id": "source-squad",
	}], zone, [{"id": "source-squad", "name": "Source", "hero_ids": [stranded.instance_id], "stance": "stay_together", "guard_target_id": ""}], {}, {}, 544)
	source_state.actors[0].life = BattleActor.LIFE_DOWNED
	source_state.actors[0].hp = 0.0
	GameSession.stranded_incidents.append({"id": "incident-popup", "source_order_id": "private-source-id", "zone_id": "verdant_outskirts", "hero_ids": [stranded.instance_id], "battle_snapshot": GameSession._incident_snapshot(source_state, [stranded.instance_id] as Array[String]), "created_recovery_seconds": GameSession.rescue_clock_seconds, "paused": true, "expiry_pending": false, "active_rescue_order_id": ""})
	var hub: Node3D = _instantiate_hub()
	hub._refresh_incident_cards()
	var panel: PanelContainer = hub._incident_panel("incident-popup")
	assert_not_null(panel)
	var option: OptionButton = panel.get_node("Box/Actions/RescueTeam") as OptionButton
	var popup: PopupMenu = option.get_popup()
	var retained_meta: Dictionary = option.get_item_metadata(0) as Dictionary
	option.show_popup()
	await get_tree().process_frame
	assert_true(popup.visible, "The rescue team choices are open before the periodic update")
	GameSession.rescue_clock_seconds += 12.0
	GameSession.expeditions_changed.emit()
	await get_tree().process_frame
	assert_true(popup.visible, "A pure timer pulse must not close the open rescue team popup")
	assert_eq(option.item_count, 1)
	assert_eq(option.get_item_metadata(0), retained_meta, "Timer pulses retain the exact selected option data")


func test_early_victory_card_explains_the_route_clock() -> void:
	var battle: Dictionary = BattleState.new().to_dict()
	battle["status"] = "victory"
	GameSession.expedition_orders.append({"id": "won-order", "backend": "battle_v1", "team_name": "Winners", "zone_id": "verdant_outskirts", "hero_ids": [], "phase": "returning", "remaining_seconds": 151.0, "initial_duration_seconds": 300.0, "battle": battle})
	var hub: Node3D = _instantiate_hub()
	hub._refresh_expeditions(true)
	var details: Label = hub._order_cards.get_child(hub._order_cards.get_child_count() - 1).get_node("Box/Bottom/Details") as Label
	assert_string_contains(details.text, "
Won · heading home · rewards in 2:3")
	assert_false(details.text.contains("route min"))


## ---- ig-7sn.3: a battle pulse updates only its own card; a roster change refreshes the detail once

func test_a_battle_pulse_updates_only_its_own_order_card() -> void:
	GameSession.set_process(false)
	var order_ids: Array[String] = []
	for index: int in 5:
		var hero := Hero.new("Card %d" % index, 7)
		hero.def_id = &"knight"
		hero.level = 80
		GameSession.add_hero(hero)
		order_ids.append(GameSession.dispatch_expedition([hero.instance_id], "verdant_outskirts", 1, "Card %d" % index))
		assert_ne(order_ids.back(), "", GameSession.last_action_error)
	var hub: Node3D = _instantiate_hub()
	assert_eq(hub._order_cards.get_child_count(), 5)
	for card: Node in hub._order_cards.get_children():
		_details(card).text = "stale"
	var updates: int = hub.order_card_updates
	GameSession.battle_changed.emit(order_ids[2])
	assert_eq(hub.order_card_updates, updates + 1, "one battle_changed updates one card")
	for card: Node in hub._order_cards.get_children():
		var own: bool = str(card.get_meta("order_id")) == order_ids[2]
		assert_eq(_details(card).text == "stale", not own, "only order 2's card is rewritten")
		if own:
			assert_string_contains(_details(card).text, "Fighting · 1 alive · 0 downed", "with its live status")
	# A roster change rebuilds every card; a battle_changed in the same frame reaches the new card.
	var old_card: Node = hub._order_cards.get_child(0)
	hub._refresh_expeditions(true)
	assert_eq(hub._order_cards.get_child_count(), 5, "the old cards are out of the list at once")
	assert_true(old_card.is_queued_for_deletion())
	for card: Node in hub._order_cards.get_children():
		_details(card).text = "stale"
	updates = hub.order_card_updates
	GameSession.battle_changed.emit(order_ids[2])
	assert_eq(hub.order_card_updates, updates + 1, "one update after a rebuild too")
	for card: Node in hub._order_cards.get_children():
		assert_eq(_details(card).text == "stale", str(card.get_meta("order_id")) != order_ids[2], "the live card of order 2 is rewritten")
	updates = hub.order_card_updates
	GameSession.battle_changed.emit("no-such-order")
	assert_eq(hub.order_card_updates, updates, "no card, nothing to do")
	GameSession.expeditions_changed.emit()
	assert_eq(hub.order_card_updates, updates + 5, "one expeditions_changed updates each card once")
	# A quiet pulse: one battle_changed per order, then expeditions_changed. 10 updates, not 5 x 5 + 5.
	updates = hub.order_card_updates
	GameSession.tick_expeditions(0.25)
	assert_eq(hub.order_card_updates, updates + 10)
	for card: Node in hub._order_cards.get_children():
		assert_string_contains(_details(card).text, "alive", "every card still shows its live status")
	await wait_process_frames(1)
	assert_false(is_instance_valid(old_card), "an old card is freed at the frame's end, not leaked")
	GameSession.set_process(true)


func test_a_roster_change_refreshes_the_selected_heros_detail_once() -> void:
	var hero := Hero.new("Detail", 7)
	hero.def_id = &"knight"
	GameSession.add_hero(hero)
	var hub: Node3D = _instantiate_hub()
	assert_eq(hub.detail_refreshes, 1, "_ready refreshes it once")
	var roster: ItemList = hub.get_node("%RosterList") as ItemList
	for index: int in roster.item_count:
		if roster.get_item_text(index).contains("Detail"):
			roster.select(index)
			roster.multi_selected.emit(index, true)
	assert_string_contains(hub._hero_detail.text, "History:", "the hero is selected")
	var refreshes: int = hub.detail_refreshes
	GameSession.roster_changed.emit()
	assert_eq(hub.detail_refreshes, refreshes + 1, "one roster change, one detail refresh")
	assert_string_contains(hub._hero_detail.text, "History:", "and it still shows the hero")


func _details(card: Node) -> Label:
	return card.get_node("Box/Bottom/Details") as Label


func _instantiate_hub() -> Node3D:
	var scene: PackedScene = load("res://hub/hub.tscn") as PackedScene
	assert_not_null(scene)
	var hub: Node3D = scene.instantiate() as Node3D
	add_child_autofree(hub)
	return hub
