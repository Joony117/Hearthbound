extends GutTest

const BALANCE: BalanceTable = preload("res://balance.tres")

func before_each() -> void:
	GameSession.from_dict({"roster": []})


func test_equip_moves_item_to_its_definition_slot_and_out_of_inventory() -> void:
	var hero := Hero.new("Equipped Hero", 1)
	var item := Item.new(&"ring", 2)
	var definition: EquipmentDefinition = Item.definition_for(item.def_id)

	GameSession.add_hero(hero)
	GameSession.add_item(item)
	GameSession.equip_item(hero, item)

	assert_eq(hero.equipped[definition.slot], item)
	assert_false(GameSession.inventory.has(item))
	assert_eq(_count_item(hero, item), 1)


func test_equip_replaces_same_slot_without_losing_or_duplicating_items() -> void:
	var hero := Hero.new("Swap Hero", 1)
	var first := Item.new(&"ring", 1)
	var second := Item.new(&"ring", 3)
	var definition: EquipmentDefinition = Item.definition_for(first.def_id)

	GameSession.add_hero(hero)
	GameSession.add_item(first)
	GameSession.add_item(second)
	assert_eq(_count_item(hero, first), 1)
	assert_eq(_count_item(hero, second), 1)

	GameSession.equip_item(hero, first)
	GameSession.equip_item(hero, second)

	assert_eq(hero.equipped[definition.slot], second)
	assert_true(GameSession.inventory.has(first))
	assert_false(GameSession.inventory.has(second))
	assert_eq(_count_item(hero, first), 1)
	assert_eq(_count_item(hero, second), 1)


func test_unequip_returns_item_to_inventory_and_clears_slot() -> void:
	var hero := Hero.new("Unequipped Hero", 1)
	var item := Item.new(&"necklace", 2)
	var definition: EquipmentDefinition = Item.definition_for(item.def_id)

	GameSession.add_hero(hero)
	GameSession.add_item(item)
	GameSession.equip_item(hero, item)
	GameSession.unequip_item(hero, definition.slot)

	assert_false(hero.equipped.has(definition.slot))
	assert_true(GameSession.inventory.has(item))
	assert_eq(_count_item(hero, item), 1)


func test_hub_equipment_display_preserves_unequip_target_and_slot_filter() -> void:
	var hero := Hero.new("Slot Hero", 1)
	var head := Item.new(&"head", 3)
	var boots := Item.new(&"boots", 2)
	var ring := Item.new(&"ring", 3)
	ring.enhance_level = 1
	GameSession.add_hero(hero)
	GameSession.add_item(head)
	GameSession.add_item(boots)
	GameSession.add_item(ring)
	var hub_scene: PackedScene = load("res://hub/hub.tscn") as PackedScene
	assert_not_null(hub_scene)
	var hub: Node3D = hub_scene.instantiate() as Node3D
	add_child_autofree(hub)
	var roster_list: ItemList = hub.get_node("%RosterList") as ItemList
	var inventory_list: ItemList = hub.get_node("%InventoryList") as ItemList
	var inventory_slot_filter: OptionButton = hub.get_node("%InventorySlotFilter") as OptionButton
	var equipped_list: ItemList = hub.get_node("%EquippedList") as ItemList
	var unequip_button: Button = hub.get_node("%Unequip") as Button
	var status: Label = hub.get_node("%Status") as Label

	roster_list.select(0)
	roster_list.multi_selected.emit(0, true)
	assert_eq(equipped_list.item_count, 10)
	for slot: int in EquipmentDefinition.Slot.size():
		var slot_name: String = (EquipmentDefinition.Slot.keys()[slot] as String).capitalize()
		assert_eq(equipped_list.get_item_metadata(slot), slot)
		assert_eq(equipped_list.get_item_text(slot), "%s — (empty)" % slot_name)
	assert_eq(inventory_list.get_item_metadata(0), ring)
	assert_eq(inventory_list.get_item_metadata(1), head)
	assert_eq(inventory_list.get_item_metadata(2), boots)

	var boots_slot: int = EquipmentDefinition.Slot.BOOTS
	equipped_list.select(boots_slot)
	inventory_slot_filter.select(boots_slot + 1)
	inventory_slot_filter.item_selected.emit(boots_slot + 1)
	assert_eq(inventory_list.item_count, 1)
	assert_eq(inventory_list.get_item_metadata(0), boots)
	GameSession.roster_changed.emit()
	assert_eq(equipped_list.get_selected_items(), PackedInt32Array([boots_slot]))
	assert_eq(inventory_list.item_count, 1)

	unequip_button.pressed.emit()
	assert_eq(status.text, "That slot is empty.")
	inventory_slot_filter.select(0)
	inventory_slot_filter.item_selected.emit(0)
	assert_eq(inventory_list.item_count, 3)


func test_hub_inventory_rank_and_slot_filters_compose() -> void:
	var hero := Hero.new("Filter Hero", 1)
	var head := Item.new(&"head", 3)
	var boots := Item.new(&"boots", 2)
	var ring := Item.new(&"ring", 3)
	GameSession.add_hero(hero)
	GameSession.add_item(head)
	GameSession.add_item(boots)
	GameSession.add_item(ring)
	var hub: Node3D = (load("res://hub/hub.tscn") as PackedScene).instantiate() as Node3D
	add_child_autofree(hub)
	var inventory_list: ItemList = hub.get_node("%InventoryList") as ItemList
	var rank_filter: OptionButton = hub.get_node("%InventoryRankFilter") as OptionButton
	var slot_filter: OptionButton = hub.get_node("%InventorySlotFilter") as OptionButton

	rank_filter.select(4)
	rank_filter.item_selected.emit(4)
	assert_eq(inventory_list.item_count, 2)
	assert_eq(inventory_list.get_item_metadata(0), head)
	assert_eq(inventory_list.get_item_metadata(1), ring)

	slot_filter.select(EquipmentDefinition.Slot.RING + 1)
	slot_filter.item_selected.emit(EquipmentDefinition.Slot.RING + 1)
	assert_eq(inventory_list.item_count, 1)
	assert_eq(inventory_list.get_item_metadata(0), ring)


## Nothing in this suite drives a real mouse hover, so the tooltip is pinned by its text rather than
## by showing. The roster half asserts equality with the detail panel instead of a second format
## string - that shared head is the whole reason _hero_detail_text() was extracted. The detail adds
## the Ledger's History below it (ig-m6o.1); the tooltip stays short.
func test_hub_rows_carry_hover_detail() -> void:
	var hero := Hero.new("Hover Hero", 1)
	hero.def_id = &"knight"
	var ring := Item.new(&"ring", 3)
	ring.enhance_level = 1
	GameSession.add_hero(hero)
	GameSession.add_item(ring)
	var hub: Node3D = (load("res://hub/hub.tscn") as PackedScene).instantiate() as Node3D
	add_child_autofree(hub)
	var roster_list: ItemList = hub.get_node("%RosterList") as ItemList
	var inventory_list: ItemList = hub.get_node("%InventoryList") as ItemList
	var hero_detail: Label = hub.get_node("%HeroDetail") as Label

	roster_list.select(0)
	roster_list.multi_selected.emit(0, true)
	assert_eq(hero_detail.text, roster_list.get_item_tooltip(0) + "\n\nHistory:\nArrived before the records begin.")
	assert_string_contains(roster_list.get_item_tooltip(0), "Resonance:")

	var tooltip: String = inventory_list.get_item_tooltip(0)
	assert_string_contains(tooltip, "Slot: Ring")
	assert_string_contains(tooltip, "CRIT_DMG: +%.1f%%" % (Item.compute_stat_magnitude(ring, Item.definition_for(ring.def_id), BALANCE) * 100.0))
	assert_string_contains(tooltip, "Enhance: +1 / %d" % Item.compute_enhance_cap(GameSession.building_levels[1], BALANCE))
	assert_string_contains(tooltip, "Salvage: %d B parts" % Item.compute_salvage_yield(ring, GameSession.building_levels[1], 0, BALANCE))

	# The null-definition branch, without rendering one: an unresolvable def_id would push_error on
	# every refresh, and GUT fails a test that leaves one unconsumed.
	var degraded: String = hub.call("_inventory_tooltip_text", ring, null)
	assert_string_contains(degraded, "Missing (ring)")
	assert_string_contains(degraded, "Salvage: ")


func test_salvage_removes_inventory_item_and_credits_only_its_rank() -> void:
	var item := Item.new(&"ring", 3)
	var balance := BalanceTable.new()
	GameSession.add_item(item)

	GameSession.salvage_item(item, balance)

	assert_false(GameSession.inventory.has(item))
	for rank_index: int in GameSession.parts.size():
		assert_eq(GameSession.parts[rank_index], 3 if rank_index == item.rank else 0)


func test_enhance_uses_the_cost_ladder() -> void:
	var item := Item.new(&"ring", 3)
	var balance := BalanceTable.new()
	GameSession.building_levels[1] = 5
	GameSession.add_item(item)
	GameSession.parts[item.rank] = 5

	assert_true(GameSession.enhance_item(item, balance))
	assert_eq(item.enhance_level, 1)
	assert_eq(GameSession.parts[item.rank], 3)
	assert_true(GameSession.enhance_item(item, balance))
	assert_eq(item.enhance_level, 2)
	assert_eq(GameSession.parts[item.rank], 0)


func test_enhance_refuses_at_cap_without_writing() -> void:
	var item := Item.new(&"ring", 3)
	var balance := BalanceTable.new()
	GameSession.building_levels[1] = 5
	item.enhance_level = balance.forge_enhance_cap_max
	GameSession.add_item(item)
	GameSession.parts[item.rank] = 99
	var parts_before: Array[int] = GameSession.parts.duplicate()

	assert_false(GameSession.enhance_item(item, balance))
	assert_eq(item.enhance_level, balance.forge_enhance_cap_max)
	assert_eq(GameSession.parts, parts_before)


func test_enhance_refuses_fresh_item_with_unbuilt_forge_without_writing() -> void:
	var item := Item.new(&"ring", 3)
	var balance := BalanceTable.new()
	GameSession.add_item(item)
	GameSession.parts[item.rank] = 99
	var parts_before: Array[int] = GameSession.parts.duplicate()

	assert_false(GameSession.enhance_item(item, balance))
	assert_eq(item.enhance_level, 0)
	assert_eq(GameSession.parts, parts_before)


func test_forge_level_one_allows_three_enhancements_then_refuses() -> void:
	var item := Item.new(&"ring", 3)
	var balance := BalanceTable.new()
	GameSession.building_levels[1] = 1
	GameSession.add_item(item)
	GameSession.parts[item.rank] = 99

	assert_true(GameSession.enhance_item(item, balance))
	assert_true(GameSession.enhance_item(item, balance))
	assert_true(GameSession.enhance_item(item, balance))
	var parts_before: Array[int] = GameSession.parts.duplicate()
	assert_false(GameSession.enhance_item(item, balance))
	assert_eq(item.enhance_level, 3)
	assert_eq(GameSession.parts, parts_before)


func test_enhance_refuses_insufficient_parts_without_writing() -> void:
	var item := Item.new(&"ring", 3)
	var balance := BalanceTable.new()
	GameSession.building_levels[1] = 5
	GameSession.add_item(item)
	GameSession.parts[item.rank] = 1
	var parts_before: Array[int] = GameSession.parts.duplicate()

	assert_false(GameSession.enhance_item(item, balance))
	assert_eq(item.enhance_level, 0)
	assert_eq(GameSession.parts, parts_before)


func test_salvage_scales_with_forge_level_and_rounds() -> void:
	var level_two_item := Item.new(&"ring", 2)
	var level_five_item := Item.new(&"ring", 3)
	var balance := BalanceTable.new()
	level_five_item.enhance_level = 4
	GameSession.add_item(level_two_item)
	GameSession.add_item(level_five_item)

	GameSession.building_levels[1] = 2
	GameSession.salvage_item(level_two_item, balance)
	GameSession.building_levels[1] = 5
	GameSession.salvage_item(level_five_item, balance)

	assert_eq(GameSession.parts[level_two_item.rank], 4)
	assert_eq(GameSession.parts[level_five_item.rank], 11)


func test_salvage_credits_enhance_level_at_unbuilt_forge() -> void:
	var item := Item.new(&"ring", 3)
	var balance := BalanceTable.new()
	item.enhance_level = 4
	GameSession.add_item(item)

	GameSession.salvage_item(item, balance)

	assert_eq(GameSession.parts[item.rank], 7)


func test_item_compute_salvage_yield_clamps_enhance_and_forge_levels() -> void:
	var capped_item := Item.new(&"ring", 3)
	var max_item := Item.new(&"ring", 3)
	var negative_item := Item.new(&"ring", 3)
	var unbonused_item := Item.new(&"ring", 3)
	capped_item.enhance_level = 999
	max_item.enhance_level = BALANCE.forge_enhance_cap_max
	negative_item.enhance_level = -1
	unbonused_item.enhance_level = 4

	assert_eq(
		Item.compute_salvage_yield(capped_item, 999, 0, BALANCE),
		Item.compute_salvage_yield(max_item, 5, 0, BALANCE)
	)
	assert_eq(
		Item.compute_salvage_yield(negative_item, 0, 0, BALANCE),
		Item.compute_salvage_yield(Item.new(&"ring", 3), 0, 0, BALANCE)
	)
	assert_eq(Item.compute_salvage_yield(unbonused_item, 0, 0, BALANCE), 7)


func test_item_compute_enhance_cap_clamps_forge_level() -> void:
	assert_eq(Item.compute_enhance_cap(0, BALANCE), 0)
	assert_eq(Item.compute_enhance_cap(-1, BALANCE), 0)
	assert_eq(Item.compute_enhance_cap(999, BALANCE), Item.compute_enhance_cap(5, BALANCE))


func test_corrupt_forge_level_clamps_to_level_five_in_both_paths() -> void:
	var enhanced_item := Item.new(&"ring", 3)
	var salvaged_item := Item.new(&"ring", 4)
	var balance := BalanceTable.new()
	GameSession.building_levels[1] = 999
	GameSession.add_item(enhanced_item)
	GameSession.add_item(salvaged_item)
	GameSession.parts[enhanced_item.rank] = 99
	enhanced_item.enhance_level = 14

	assert_true(GameSession.enhance_item(enhanced_item, balance))
	var parts_before: Array[int] = GameSession.parts.duplicate()
	assert_false(GameSession.enhance_item(enhanced_item, balance))
	assert_eq(enhanced_item.enhance_level, 15)
	assert_eq(GameSession.parts, parts_before)
	GameSession.salvage_item(salvaged_item, balance)
	assert_eq(GameSession.parts[salvaged_item.rank], 5)


## Item.from_dict never validates rank, and assert() is stripped in release - so a hand-edited
## save must be absorbed by the clamp. Negative ranks are the sharp case: GDScript indexes arrays
## from the end, so -1 credited SSS while the same item displayed as F.
func test_salvage_clamps_a_corrupt_rank() -> void:
	var above := Item.new(&"ring", 99)
	var below := Item.new(&"ring", -1)
	var balance := BalanceTable.new()
	GameSession.add_item(above)
	GameSession.add_item(below)

	GameSession.salvage_item(above, balance)
	GameSession.salvage_item(below, balance)

	assert_eq(GameSession.parts[GameSession.parts.size() - 1], 3)
	assert_eq(GameSession.parts[0], 3)


func test_item_from_dict_defaults_explicit_null_enhance_level() -> void:
	var item: Item = Item.from_dict({"def_id": "ring", "rank": 3, "enhance_level": null})

	assert_not_null(item)
	assert_eq(item.enhance_level, 0)


func test_convert_parts_spends_three_parts_for_one_of_the_next_rank() -> void:
	GameSession.parts[2] = 3

	assert_true(GameSession.convert_parts(2))
	for rank_index: int in GameSession.parts.size():
		assert_eq(GameSession.parts[rank_index], 1 if rank_index == 3 else 0)


func test_convert_parts_refuses_insufficient_parts_without_writing() -> void:
	GameSession.parts[2] = 2
	var parts_before: Array[int] = GameSession.parts.duplicate()

	assert_false(GameSession.convert_parts(2))
	assert_eq(GameSession.parts, parts_before)


func test_convert_parts_refuses_top_and_negative_ranks_without_writing() -> void:
	var top_rank: int = GameSession.parts.size() - 1
	GameSession.parts[top_rank] = 3
	var parts_before: Array[int] = GameSession.parts.duplicate()

	assert_false(GameSession.convert_parts(top_rank))
	assert_false(GameSession.convert_parts(-1))
	assert_eq(GameSession.parts, parts_before)


func test_kill_hero_moves_all_equipped_items_to_lost_cache() -> void:
	var hero := Hero.new("Doomed Hero", 2)
	var ring := Item.new(&"ring", 1)
	var necklace := Item.new(&"necklace", 3)

	GameSession.add_hero(hero)
	GameSession.add_item(ring)
	GameSession.add_item(necklace)
	GameSession.equip_item(hero, ring)
	GameSession.equip_item(hero, necklace)
	GameSession.kill_hero(hero, &"doomed_zone", BALANCE)

	assert_false(GameSession.roster.has(hero))
	assert_true(hero.equipped.is_empty())
	assert_false(GameSession.inventory.has(ring))
	assert_false(GameSession.inventory.has(necklace))
	assert_eq(GameSession.lost_caches.size(), 1)
	var cache: LostCache = GameSession.lost_caches[0]
	assert_eq(cache.hero_name, "Doomed Hero")
	assert_eq(cache.zone_id, &"doomed_zone")
	assert_true(cache.items.has(ring))
	assert_true(cache.items.has(necklace))


func test_lost_cache_survives_game_session_round_trip() -> void:
	var hero := Hero.new("Cached Hero", 2)
	var ring := Item.new(&"ring", 1)
	var necklace := Item.new(&"necklace", 3)

	GameSession.add_hero(hero)
	GameSession.add_item(ring)
	GameSession.add_item(necklace)
	GameSession.equip_item(hero, ring)
	GameSession.equip_item(hero, necklace)
	GameSession.kill_hero(hero, &"cache_zone", BALANCE)
	GameSession.from_dict(GameSession.to_dict())

	assert_eq(GameSession.lost_caches.size(), 1)
	var cache: LostCache = GameSession.lost_caches[0]
	assert_eq(cache.hero_name, "Cached Hero")
	assert_eq(cache.zone_id, &"cache_zone")
	assert_eq(cache.items.size(), 2)
	assert_true(_has_item(cache.items, &"ring", 1))
	assert_true(_has_item(cache.items, &"necklace", 3))


func test_kill_hero_without_equipped_items_creates_no_lost_cache() -> void:
	var hero := Hero.new("Ungeared Hero", 2)

	GameSession.add_hero(hero)
	GameSession.kill_hero(hero, &"empty_zone", BALANCE)

	assert_true(GameSession.lost_caches.is_empty())


func test_equipped_item_survives_game_session_round_trip() -> void:
	var hero := Hero.new("Saved Hero", 3)
	hero.def_id = &"mage"
	var item := Item.new(&"ring", 4)
	var definition: EquipmentDefinition = Item.definition_for(item.def_id)

	GameSession.add_hero(hero)
	GameSession.add_item(item)
	GameSession.equip_item(hero, item)
	var saved: Dictionary = GameSession.to_dict()

	GameSession.from_dict(saved)
	var reloaded_hero: Hero = null
	for candidate: Hero in GameSession.roster:
		if candidate.def_id == &"mage" and candidate.hero_name == "Saved Hero" and candidate.rank == 3:
			reloaded_hero = candidate

	assert_not_null(reloaded_hero)
	assert_true(reloaded_hero.equipped.has(definition.slot))
	var reloaded_item: Item = reloaded_hero.equipped[definition.slot]
	assert_eq(reloaded_item.def_id, &"ring")
	assert_eq(reloaded_item.rank, 4)
	assert_false(GameSession.inventory.has(reloaded_item))


func test_legacy_hero_without_equipped_key_loads_empty() -> void:
	var saved_hero := Hero.new("Legacy Hero", 2).to_dict()
	saved_hero.erase("equipped")
	var roster_entries: Array[Dictionary] = [saved_hero]

	GameSession.from_dict({"roster": roster_entries})

	assert_eq(GameSession.roster.size(), 1)
	assert_true(GameSession.roster[0].equipped.is_empty())


func test_equipping_changes_hp_and_team_power_but_ring_is_crit_blind() -> void:
	var definition := _make_definition()
	var balance := BalanceTable.new()
	var hero := Hero.new("Combat Hero", 2)
	var team: Array[Hero] = [hero]
	var definitions: Array[HeroDefinition] = [definition]
	var levels: Array[int] = [5]
	var head := Item.new(&"head", 4)
	var item := Item.new(&"ring", 4)
	var stats_before: Dictionary[StringName, float] = Hero.compute_final_stats(hero, definition, balance, 5)
	var power_before: float = Hero.compute_team_power(team, definitions, levels, balance)

	hero.equipped[EquipmentDefinition.Slot.HEAD] = head
	var stats_with_head: Dictionary[StringName, float] = Hero.compute_final_stats(hero, definition, balance, 5)
	var power_with_head: float = Hero.compute_team_power(team, definitions, levels, balance)
	assert_almost_eq(stats_before[Hero.STAT_HP], 273.0, 0.0001)
	assert_almost_eq(stats_with_head[Hero.STAT_HP], 309.2544, 0.0001)
	assert_almost_eq(power_with_head, power_before + (stats_with_head[Hero.STAT_HP] - stats_before[Hero.STAT_HP]) / 10.0, 0.0001)

	hero.equipped[EquipmentDefinition.Slot.RING] = item
	var stats_with_ring: Dictionary[StringName, float] = Hero.compute_final_stats(hero, definition, balance, 5)
	assert_almost_eq(stats_with_ring[Hero.STAT_CRIT_DMG], stats_before[Hero.STAT_CRIT_DMG] + 0.0498, 0.0001)
	assert_almost_eq(Hero.compute_team_power(team, definitions, levels, balance), power_with_head, 0.0001)


func test_same_stat_equipment_sums_before_multiplying() -> void:
	var definition := _make_definition()
	var balance := BalanceTable.new()
	var hero := Hero.new("Stacked Hero", 2)
	hero.equipped[EquipmentDefinition.Slot.HEAD] = Item.new(&"head", 4)
	hero.equipped[EquipmentDefinition.Slot.LEGS] = Item.new(&"legs", 4)

	var stats: Dictionary[StringName, float] = Hero.compute_final_stats(hero, definition, balance, 5)
	assert_almost_eq(stats[Hero.STAT_HP], 273.0 * (1.0 + 0.1328 + 0.1328), 0.0001)


func test_enhanced_non_crit_contribution_scales_before_summing() -> void:
	var definition := _make_definition()
	var balance := BalanceTable.new()
	var hero := Hero.new("Enhanced HP Hero", 2)
	var head := Item.new(&"head", 4)
	head.enhance_level = 3
	hero.equipped[EquipmentDefinition.Slot.HEAD] = head
	hero.equipped[EquipmentDefinition.Slot.LEGS] = Item.new(&"legs", 4)

	var stats: Dictionary[StringName, float] = Hero.compute_final_stats(hero, definition, balance, 5)
	var enhanced_contribution: float = 0.1328 * (1.0 + 0.08 * 3.0)
	assert_almost_eq(stats[Hero.STAT_HP], 273.0 * (1.0 + enhanced_contribution + 0.1328), 0.0001)


func test_enhanced_crit_contribution_scales_before_adding() -> void:
	var definition := _make_definition()
	var balance := BalanceTable.new()
	var hero := Hero.new("Enhanced Crit Hero", 2)
	var necklace := Item.new(&"necklace", 4)
	necklace.enhance_level = 3
	hero.equipped[EquipmentDefinition.Slot.NECKLACE] = necklace

	var stats: Dictionary[StringName, float] = Hero.compute_final_stats(hero, definition, balance, 5)
	var enhanced_contribution: float = 0.0498 * (1.0 + 0.08 * 3.0)
	assert_almost_eq(stats[Hero.STAT_CRIT_RATE], 0.15 + enhanced_contribution, 0.0001)


func test_crit_rate_is_capped_by_equipped_necklace() -> void:
	var definition := _make_definition()
	definition.crit_rate = 0.7
	var hero := Hero.new("Capped Hero", 2)
	hero.equipped[EquipmentDefinition.Slot.NECKLACE] = Item.new(&"necklace", 7)

	var stats: Dictionary[StringName, float] = Hero.compute_final_stats(hero, definition, BalanceTable.new(), 5)
	assert_almost_eq(stats[Hero.STAT_CRIT_RATE], 0.75, 0.0001)


func test_full_same_rank_gear_scales_team_power() -> void:
	var definition := _make_definition()
	var balance := BalanceTable.new()
	var hero := Hero.new("Fully Equipped Hero", 2)
	var team: Array[Hero] = [hero]
	var definitions: Array[HeroDefinition] = [definition]
	var levels: Array[int] = [5]
	var power_before: float = Hero.compute_team_power(team, definitions, levels, balance)
	for def_id: StringName in [&"head", &"chest", &"legs", &"gloves", &"boots", &"main_hand", &"off_hand", &"necklace", &"ring", &"belt"]:
		var equipment_definition: EquipmentDefinition = Item.definition_for(def_id)
		hero.equipped[equipment_definition.slot] = Item.new(def_id, 4)

	var expected_multiplier: float = 1.0 + 2.0 * balance.equip_pct_per_rank[4]
	assert_almost_eq(Hero.compute_team_power(team, definitions, levels, balance), power_before * expected_multiplier, 0.0001)


func test_equipped_item_round_trip_keeps_geared_stats() -> void:
	var definition := _make_definition()
	var balance := BalanceTable.new()
	var hero := Hero.new("Geared Saved Hero", 2)
	hero.def_id = &"mage"
	var item := Item.new(&"head", 4)

	GameSession.add_hero(hero)
	GameSession.add_item(item)
	GameSession.equip_item(hero, item)
	GameSession.from_dict(GameSession.to_dict())

	var reloaded_hero: Hero = GameSession.roster[0]
	var stats: Dictionary[StringName, float] = Hero.compute_final_stats(reloaded_hero, definition, balance, 5)
	assert_almost_eq(stats[Hero.STAT_HP], 309.2544, 0.0001)


func _count_item(hero: Hero, item: Item) -> int:
	var count: int = _count_inventory_item(item)
	for equipped_item: Item in hero.equipped.values():
		if equipped_item == item:
			count += 1
	return count


func _count_inventory_item(item: Item) -> int:
	var count: int = 0
	for inventory_item: Item in GameSession.inventory:
		if inventory_item == item:
			count += 1
	return count


func _has_item(items: Array[Item], def_id: StringName, rank: int) -> bool:
	for item: Item in items:
		if item.def_id == def_id and item.rank == rank:
			return true
	return false


func _make_definition() -> HeroDefinition:
	var definition := HeroDefinition.new()
	definition.base_hp = 100.0
	definition.hp_growth = 10.0
	definition.base_atk = 20.0
	definition.atk_growth = 2.0
	definition.base_def = 10.0
	definition.def_growth = 1.0
	definition.base_spd = 80.0
	definition.spd_growth = 3.0
	definition.crit_rate = 0.15
	definition.crit_dmg = 1.8
	return definition
