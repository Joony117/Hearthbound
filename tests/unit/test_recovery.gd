extends GutTest

const BALANCE: BalanceTable = preload("res://balance.tres")


func before_each() -> void:
	GameSession.from_dict({"roster": []})


func test_zone_definition_lookup_returns_authored_zone_and_reports_a_miss() -> void:
	var zone: ZoneDefinition = ZoneDefinition.definition_for(&"verdant_outskirts")
	assert_not_null(zone)
	assert_eq(zone.display_name, "Verdant Outskirts")

	var missing: ZoneDefinition = ZoneDefinition.definition_for(&"not_a_zone")
	assert_push_error("Missing ZoneDefinition for zone_id")
	assert_null(missing)


func test_damaged_halves_clamped_enhancement_then_falls_back_to_rank() -> void:
	var enhanced := Item.new(&"head", 3)
	enhanced.enhance_level = 5
	Item.apply_damaged(enhanced, BALANCE)
	assert_eq(enhanced.enhance_level, 2)
	assert_eq(enhanced.rank, 3)

	var corrupt_enhancement := Item.new(&"head", 3)
	corrupt_enhancement.enhance_level = 999
	Item.apply_damaged(corrupt_enhancement, BALANCE)
	assert_eq(corrupt_enhancement.enhance_level, 7)
	assert_eq(corrupt_enhancement.rank, 3)

	var ranked := Item.new(&"head", 3)
	Item.apply_damaged(ranked, BALANCE)
	assert_eq(ranked.enhance_level, 0)
	assert_eq(ranked.rank, 2)

	var corrupt_rank := Item.new(&"head", 999)
	Item.apply_damaged(corrupt_rank, BALANCE)
	assert_eq(corrupt_rank.rank, BALANCE.rank_names.size() - 2)

	var floor_item := Item.new(&"head", 0)
	Item.apply_damaged(floor_item, BALANCE)
	assert_eq(floor_item.enhance_level, 0)
	assert_eq(floor_item.rank, 0)


func test_damage_chance_uses_pre_tick_elapsed_turns_and_power_deficit() -> void:
	var cache := LostCache.new("Lost", &"verdant_outskirts", 0)
	assert_almost_eq(
		LostCache.compute_damage_chance(cache, 900, 450.0, 0, 0, BALANCE),
		0.35,
		0.0001,
	)
	assert_almost_eq(
		LostCache.compute_damage_chance(cache, 900, 450.0, 15, 0, BALANCE),
		0.80,
		0.0001,
	)


func test_advance_turn_keeps_cache_at_deadline_and_drops_it_one_turn_later() -> void:
	var cache := LostCache.new("Lost", &"verdant_outskirts", 0)
	GameSession.lost_caches.append(cache)
	GameSession.turns = 14

	GameSession.advance_turn(BALANCE)
	assert_eq(GameSession.turns, 15)
	assert_true(GameSession.lost_caches.has(cache))

	GameSession.advance_turn(BALANCE)
	assert_eq(GameSession.turns, 16)
	assert_false(GameSession.lost_caches.has(cache))


func test_refused_recoveries_spend_no_turn_and_mutate_nothing() -> void:
	var cache := LostCache.new("Lost", &"verdant_outskirts", 0)
	cache.items.append(Item.new(&"head", 2))
	GameSession.lost_caches.append(cache)
	var weak_hero: Hero = _add_knight("Weak", 0, 0)
	var oversized_team: Array[Hero] = [weak_hero]
	for hero_index: int in 5:
		oversized_team.append(_add_knight("Extra %d" % hero_index, 0, 0))

	assert_eq(GameSession.recover_cache(null, [weak_hero], BALANCE), GameSession.RECOVERY_NO_CACHE)
	assert_eq(GameSession.recover_cache(cache, [], BALANCE), GameSession.RECOVERY_INVALID_TEAM)
	assert_eq(GameSession.recover_cache(cache, oversized_team, BALANCE), GameSession.RECOVERY_INVALID_TEAM)
	assert_eq(
		GameSession.recover_cache(cache, [weak_hero], BALANCE),
		GameSession.RECOVERY_INSUFFICIENT_POWER,
	)
	assert_eq(GameSession.turns, 0)
	assert_true(GameSession.lost_caches.has(cache))
	assert_true(GameSession.inventory.is_empty())


func test_missing_cache_zone_and_missing_hero_definition_refuse_without_mutation() -> void:
	var hero: Hero = _add_knight("Valid", 7, 80)
	var missing_zone_cache := LostCache.new("Lost", &"not_a_zone", 0)
	missing_zone_cache.items.append(Item.new(&"head", 2))
	GameSession.lost_caches.append(missing_zone_cache)

	assert_eq(
		GameSession.recover_cache(missing_zone_cache, [hero], BALANCE),
		GameSession.RECOVERY_MISSING_ZONE,
	)
	assert_push_error("Missing ZoneDefinition for zone_id")
	assert_eq(GameSession.turns, 0)
	assert_true(GameSession.inventory.is_empty())

	var invalid_hero := Hero.new("Invalid", 0)
	invalid_hero.def_id = &"not_an_archetype"
	GameSession.add_hero(invalid_hero)
	var valid_cache := LostCache.new("Lost", &"verdant_outskirts", 0)
	GameSession.lost_caches.append(valid_cache)
	assert_eq(
		GameSession.recover_cache(valid_cache, [invalid_hero], BALANCE),
		GameSession.RECOVERY_INVALID_TEAM,
	)
	assert_push_error("Missing HeroDefinition for def_id")
	assert_eq(GameSession.turns, 0)
	assert_true(GameSession.lost_caches.has(valid_cache))


func test_permitted_recovery_rolls_each_item_and_moves_every_item_to_inventory() -> void:
	var hero: Hero = _add_knight("Rescuer", 7, 80)
	var cache := LostCache.new("Lost", &"verdant_outskirts", 0)
	var damaged_item := Item.new(&"head", 3)
	damaged_item.enhance_level = 4
	var intact_item := Item.new(&"body", 3)
	intact_item.enhance_level = 4
	cache.items.append(damaged_item)
	cache.items.append(intact_item)
	GameSession.lost_caches.append(cache)
	var definitions: Array[HeroDefinition] = [Hero.definition_for(hero.def_id)]
	var levels: Array[int] = [Hero.level_for(hero, BALANCE)]
	var team_power: float = Hero.compute_team_power([hero], definitions, levels, BALANCE)
	var damage_chance: float = LostCache.compute_damage_chance(
		cache,
		900,
		team_power,
		GameSession.turns,
		0,
		BALANCE,
	)
	var rng_seed: int = _seed_for_hit_then_miss(damage_chance)
	seed(rng_seed)

	assert_eq(GameSession.recover_cache(cache, [hero], BALANCE), GameSession.RECOVERY_COMPLETED)
	assert_eq(damaged_item.enhance_level, 2)
	assert_eq(intact_item.enhance_level, 4)
	assert_true(GameSession.inventory.has(damaged_item))
	assert_true(GameSession.inventory.has(intact_item))
	assert_false(GameSession.lost_caches.has(cache))
	assert_eq(GameSession.turns, 1)
	assert_true(GameSession.roster.has(hero))


func test_hub_lists_cache_details_and_missing_zone_fallback() -> void:
	GameSession.turns = 3
	var cache := LostCache.new("Aster", &"not_a_zone", 1)
	cache.items.append(Item.new(&"head", 1))
	cache.items.append(Item.new(&"body", 2))
	GameSession.lost_caches.append(cache)
	var hub: Node3D = (load("res://hub/hub.tscn") as PackedScene).instantiate() as Node3D
	add_child_autofree(hub)
	assert_push_error("Missing ZoneDefinition for zone_id")
	var cache_list: ItemList = hub.get_node("%LostCacheList") as ItemList

	assert_eq(cache_list.item_count, 1)
	assert_string_contains(cache_list.get_item_text(0), "Aster")
	assert_string_contains(cache_list.get_item_text(0), "[Missing definition: not_a_zone]")
	assert_string_contains(cache_list.get_item_text(0), "2 items")
	assert_string_contains(cache_list.get_item_text(0), "13 turns remaining")


func test_hub_recover_button_reuses_roster_selection() -> void:
	var hero: Hero = _add_knight("Rescuer", 7, 80)
	var cache := LostCache.new("Aster", &"verdant_outskirts", 0)
	cache.items.append(Item.new(&"head", 1))
	GameSession.lost_caches.append(cache)
	var hub: Node3D = (load("res://hub/hub.tscn") as PackedScene).instantiate() as Node3D
	add_child_autofree(hub)
	var roster_list: ItemList = hub.get_node("%RosterList") as ItemList
	var cache_list: ItemList = hub.get_node("%LostCacheList") as ItemList
	var recover_button: Button = hub.get_node("UI/Root/RosterPanel/VBox/Recover") as Button
	var status: Label = hub.get_node("%Status") as Label
	roster_list.select(0)
	cache_list.select(0)
	seed(1)

	recover_button.pressed.emit()
	assert_eq(status.text, "Recovered 1 items from Aster's cache.")
	assert_true(GameSession.inventory.has(cache.items[0]))
	assert_true(GameSession.lost_caches.is_empty())
	assert_true(GameSession.roster.has(hero))


func _add_knight(hero_name: String, rank: int, level: int) -> Hero:
	var hero := Hero.new(hero_name, rank)
	hero.def_id = &"knight"
	hero.level = level
	GameSession.add_hero(hero)
	return hero


func _seed_for_hit_then_miss(damage_chance: float) -> int:
	for candidate: int in 10_000:
		seed(candidate)
		if randf() < damage_chance and randf() >= damage_chance:
			return candidate
	fail_test("No deterministic seed produced one hit followed by one miss.")
	return -1
