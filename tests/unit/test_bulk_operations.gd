extends GutTest

const BALANCE: BalanceTable = preload("res://balance.tres")


func before_each() -> void:
	GameSession.set("_save_deferred_depth", 1)
	GameSession.from_dict({"roster": []})
	GameSession.last_action_error = ""


func after_each() -> void:
	GameSession.set("_save_deferred_depth", 0)


func test_favorite_item_is_excluded_and_stales_an_existing_salvage_plan() -> void:
	var item := Item.new(&"head", 0)
	GameSession.add_item(item)
	var plan: Dictionary = GameSession.preview_bulk_salvage([item.instance_id], 0)
	assert_true(bool(plan["valid"]))

	item.favorite = true
	assert_false(GameSession.commit_bulk_plan(plan))
	assert_string_contains(GameSession.last_action_error, "stale")
	assert_true(GameSession.inventory.has(item))

	var protected_plan: Dictionary = GameSession.preview_bulk_salvage([item.instance_id], 0)
	assert_false(bool(protected_plan["valid"]))
	assert_eq((protected_plan["excluded"] as Array)[0]["reason"], "favorite")


func test_duplicate_or_empty_selected_ids_are_rejected_before_preview() -> void:
	var item := Item.new(&"head", 0)
	GameSession.inventory.append(item)
	var duplicate_salvage: Dictionary = GameSession.preview_bulk_salvage(
		[item.instance_id, item.instance_id],
		0,
	)
	var duplicate_enhance: Dictionary = GameSession.preview_bulk_enhance(
		[item.instance_id, item.instance_id],
		1,
		[10, 0, 0, 0, 0, 0, 0, 0],
	)

	assert_false(bool(duplicate_salvage["valid"]))
	assert_false(bool(duplicate_enhance["valid"]))
	assert_false(bool(GameSession.preview_bulk_salvage([], 0)["valid"]))


func test_busy_or_preset_fodder_and_busy_recipient_are_refused() -> void:
	var fodder: Hero = _hero("Fodder", &"knight")
	var target: Hero = _hero("Target", &"knight")
	GameSession.roster.append_array([fodder, target])
	GameSession.team_presets = [{
		"id": "preset",
		"name": "Protected",
		"hero_ids": [fodder.instance_id],
		"zone_id": "verdant_outskirts",
	}]
	var preset_plan: Dictionary = GameSession.preview_bulk_sacrifice([fodder.instance_id], target.instance_id, 0)
	assert_false(bool(preset_plan["valid"]))

	GameSession.team_presets.clear()
	var plan: Dictionary = GameSession.preview_bulk_sacrifice([fodder.instance_id], target.instance_id, 0)
	assert_true(bool(plan["valid"]))
	GameSession.expedition_orders = [_order_for(target.instance_id)]
	assert_false(GameSession.commit_bulk_plan(plan))
	assert_string_contains(GameSession.last_action_error, "stale")


func test_sacrifice_plan_stales_when_the_recipient_changes() -> void:
	var fodder: Hero = _hero("Fodder", &"knight")
	var target: Hero = _hero("Target", &"knight")
	GameSession.roster.append_array([fodder, target])
	var plan: Dictionary = GameSession.preview_bulk_sacrifice(
		[fodder.instance_id],
		target.instance_id,
		1,
	)
	assert_true(bool(plan["valid"]))

	target.def_id = &"rogue"
	assert_false(GameSession.commit_bulk_plan(plan))
	assert_string_contains(GameSession.last_action_error, "stale")
	assert_true(GameSession.roster.has(fodder))


func test_enhance_budget_processes_first_item_fully_before_next() -> void:
	GameSession.building_levels[1] = 1
	GameSession.parts[0] = 10
	var first := Item.new(&"head", 0)
	var second := Item.new(&"chest", 0)
	GameSession.inventory.append_array([first, second])

	var plan: Dictionary = GameSession.preview_bulk_enhance(
		[first.instance_id, second.instance_id],
		3,
		[10, 0, 0, 0, 0, 0, 0, 0],
	)
	var entries: Array = plan["entries"] as Array
	assert_true(bool(plan["valid"]))
	assert_eq(entries.size(), 1)
	assert_eq(entries[0]["id"], first.instance_id)
	assert_eq(entries[0]["after_level"], 3)
	assert_eq(entries[0]["spend"], 9)
	assert_eq((plan["excluded"] as Array)[0]["id"], second.instance_id)


func test_conversion_reserve_and_positive_overspend_are_exact() -> void:
	GameSession.parts[2] = 20
	var max_plan: Dictionary = GameSession.preview_bulk_conversion(2, 0, 5)
	assert_true(bool(max_plan["valid"]))
	assert_eq((max_plan["entries"] as Array)[0]["units"], 5)
	assert_eq(max_plan["cost_parts"][2], 15)
	assert_eq(max_plan["gain_parts"][3], 5)

	var refused: Dictionary = GameSession.preview_bulk_conversion(2, 6, 5)
	assert_false(bool(refused["valid"]))


func test_fixed_conversion_refuses_when_parts_change_but_output_stays_the_same() -> void:
	GameSession.parts[0] = 10
	var plan: Dictionary = GameSession.preview_bulk_conversion(0, 1, 0)
	assert_true(bool(plan["valid"]))
	assert_eq((plan["parameters"] as Dictionary)["parts_snapshot"], GameSession.parts)

	GameSession.parts[0] = 9
	assert_false(GameSession.commit_bulk_plan(plan))
	assert_string_contains(GameSession.last_action_error, "stale")
	assert_eq(GameSession.parts[0], 9)
	assert_eq(GameSession.parts[1], 0)


func test_enhance_refuses_when_parts_change_but_budget_still_covers_the_cost() -> void:
	GameSession.building_levels[1] = 1
	GameSession.parts[0] = 10
	var item := Item.new(&"head", 0)
	GameSession.inventory.append(item)
	var plan: Dictionary = GameSession.preview_bulk_enhance(
		[item.instance_id],
		1,
		[10, 0, 0, 0, 0, 0, 0, 0],
	)
	assert_true(bool(plan["valid"]))
	assert_eq((plan["parameters"] as Dictionary)["parts_snapshot"], GameSession.parts)

	GameSession.parts[0] = 9
	assert_false(GameSession.commit_bulk_plan(plan))
	assert_string_contains(GameSession.last_action_error, "stale")
	assert_eq(item.enhance_level, 0)
	assert_eq(GameSession.parts[0], 9)


func test_large_conversion_commits_in_one_aggregate_notification() -> void:
	GameSession.parts[0] = 300_000
	var plan: Dictionary = GameSession.preview_bulk_conversion(0, 0, 0)
	watch_signals(GameSession)

	assert_true(GameSession.commit_bulk_plan(plan))
	assert_eq(GameSession.parts[0], 0)
	assert_eq(GameSession.parts[1], 100_000)
	assert_signal_emit_count(GameSession, "roster_changed", 1)


func test_supply_craft_max_preview_preserves_reserve_and_commits_exact_snapshot() -> void:
	GameSession.parts[0] = 27
	var plan: Dictionary = GameSession.preview_bulk_supplies("healing", 0, 7)
	assert_true(bool(plan["valid"]))
	assert_eq(plan["kind"], "supplies")
	assert_eq((plan["cost_parts"] as Array)[0], 20)
	assert_eq((plan["entries"] as Array).size(), 1)
	assert_eq((plan["entries"] as Array)[0], {"id": "supply_healing", "name": "Healing draught", "units": 4, "spend": 20, "gain": 4, "supply_kind": "healing"})
	assert_true(GameSession.commit_bulk_plan(plan))
	assert_eq(GameSession.parts[0], 7)
	assert_eq(GameSession.supplies["healing"], 7)
	assert_false(GameSession.commit_bulk_plan(plan))
	assert_string_contains(GameSession.last_action_error, "stale")


func test_building_preview_and_mutation_share_the_existing_cost_ladder() -> void:
	GameSession.town_resources["wood"] = 20.0
	GameSession.town_resources["stone"] = 10.0
	GameSession.parts[0] = 19
	var short_plan: Dictionary = GameSession.preview_building_upgrade(0)
	assert_false(bool(short_plan["valid"]))
	assert_eq(short_plan["current_level"], 0)
	assert_eq(short_plan["next_level"], 1)
	assert_eq(short_plan["part_rank"], 0)
	assert_eq(short_plan["part_cost"], 20)

	GameSession.parts[0] = 20
	var ready_plan: Dictionary = GameSession.preview_building_upgrade(0)
	assert_true(bool(ready_plan["valid"]))
	assert_true(GameSession.upgrade_building(0, BALANCE))
	assert_eq(GameSession.building_levels[0], ready_plan["next_level"])
	assert_eq(GameSession.parts[0], 0)


func _hero(hero_name: String, def_id: StringName) -> Hero:
	var hero := Hero.new(hero_name, 0)
	hero.def_id = def_id
	return hero


func _order_for(hero_id: String) -> Dictionary:
	return {
		"id": "busy",
		"team_name": "Busy",
		"preset_id": "",
		"hero_ids": [hero_id],
		"zone_id": "verdant_outskirts",
		"total_runs": 1,
		"runs_completed": 0,
		"stop_requested": false,
		"run_seed": 1,
		"initial_duration_seconds": 10.0,
		"remaining_seconds": 10.0,
		"cumulative_stones": 0,
		"cumulative_xp": 0,
		"cumulative_items": 0,
	}
