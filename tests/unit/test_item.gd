extends GutTest

const BALANCE: BalanceTable = preload("res://balance.tres")


func before_each() -> void:
	GameSession.from_dict({"roster": []})


func test_item_dict_round_trip() -> void:
	var item := Item.new(&"main_hand", 4)

	var reloaded: Item = Item.from_dict(item.to_dict())

	assert_eq(reloaded.def_id, &"main_hand")
	assert_eq(reloaded.rank, 4)


func test_bad_def_id_reports_error_and_returns_null() -> void:
	var definition: EquipmentDefinition = Item.definition_for(&"missing_slot")

	assert_push_error("Missing EquipmentDefinition for def_id")
	assert_null(definition)


func test_compute_stat_magnitude_uses_authored_non_crit_table_and_enhancement() -> void:
	var boots := Item.new(&"boots", 2)
	var definition: EquipmentDefinition = Item.definition_for(boots.def_id)

	assert_almost_eq(Item.compute_stat_magnitude(boots, definition, BALANCE), BALANCE.equip_pct_per_rank[2], 0.0001)
	boots.enhance_level = 3
	assert_almost_eq(Item.compute_stat_magnitude(boots, definition, BALANCE), BALANCE.equip_pct_per_rank[2] * (1.0 + BALANCE.enhance_pct_per_level * 3.0), 0.0001)


func test_compute_stat_magnitude_uses_authored_crit_table_and_enhancement() -> void:
	var ring := Item.new(&"ring", 3)
	var definition: EquipmentDefinition = Item.definition_for(ring.def_id)

	assert_almost_eq(Item.compute_stat_magnitude(ring, definition, BALANCE), BALANCE.equip_crit_pct_per_rank[3], 0.0001)
	ring.enhance_level = 4
	assert_almost_eq(Item.compute_stat_magnitude(ring, definition, BALANCE), BALANCE.equip_crit_pct_per_rank[3] * (1.0 + BALANCE.enhance_pct_per_level * 4.0), 0.0001)


## A save can carry any integer at all, and the magnitude is what a corrupt one would mint.
func test_compute_stat_magnitude_clamps_an_out_of_range_enhance_level() -> void:
	var boots := Item.new(&"boots", 2)
	boots.enhance_level = 999
	var definition: EquipmentDefinition = Item.definition_for(boots.def_id)

	var capped: float = BALANCE.equip_pct_per_rank[2] * (1.0 + BALANCE.enhance_pct_per_level * BALANCE.forge_enhance_cap_max)
	assert_almost_eq(Item.compute_stat_magnitude(boots, definition, BALANCE), capped, 0.0001)


func test_inventory_round_trip_and_legacy_save() -> void:
	GameSession.add_item(Item.new(&"ring", 2))
	var saved: Dictionary = GameSession.to_dict()

	GameSession.from_dict({"roster": []})
	assert_true(GameSession.inventory.is_empty())
	GameSession.from_dict(saved)
	assert_eq(GameSession.inventory.size(), 1)
	assert_eq(GameSession.inventory[0].def_id, &"ring")
	assert_eq(GameSession.inventory[0].rank, 2)

	GameSession.from_dict({"roster": []})
	assert_true(GameSession.inventory.is_empty())


func test_malformed_save_fields_load_empty_without_erroring() -> void:
	# An explicit null is not a missing key, so Dictionary.get()'s default never fires for it.
	GameSession.from_dict({"roster": null, "inventory": null, "cleared_zone_ids": null})
	assert_true(GameSession.inventory.is_empty())
	assert_true(GameSession.roster.is_empty())

	GameSession.from_dict({"inventory": "not an array"})
	assert_true(GameSession.inventory.is_empty())

	GameSession.from_dict({"inventory": [42, "junk", null, []]})
	assert_true(GameSession.inventory.is_empty())


func test_explicit_null_fields_decode_into_roster_and_lost_caches() -> void:
	# A null scalar must not abort from_dict, which would append null into these arrays and throw
	# again on the next field read. LostCache already type-validates every field; Hero did not.
	GameSession.from_dict({
		"roster": [{"name": "Ash", "rank": null}],
		"lost_caches": [{"hero_name": "Ash", "zone_id": "ashfall", "items": null}],
	})

	assert_push_error("Invalid lost cache items")
	assert_eq(GameSession.roster.size(), 1)
	assert_not_null(GameSession.roster[0])
	assert_eq(GameSession.roster[0].rank, 0)
	assert_eq(GameSession.lost_caches.size(), 1)
	assert_not_null(GameSession.lost_caches[0])
	assert_true(GameSession.lost_caches[0].items.is_empty())


func test_turns_and_turn_lost_absorb_the_three_untrusted_save_shapes() -> void:
	var cache_entry: Dictionary = {"hero_name": "Ash", "zone_id": "ashfall", "items": []}

	# Missing: both default to 0 rather than carrying the previous session's clock forward.
	GameSession.turns = 9
	GameSession.from_dict({"lost_caches": [cache_entry]})
	assert_eq(GameSession.turns, 0)
	assert_eq(GameSession.lost_caches[0].turn_lost, 0)

	# Float: how every int reaches JSON and comes back.
	GameSession.from_dict({
		"turns": 12.0,
		"lost_caches": [cache_entry.merged({"turn_lost": 5.0})],
	})
	assert_eq(GameSession.turns, 12)
	assert_eq(GameSession.lost_caches[0].turn_lost, 5)

	# Explicit null: Dictionary.get()'s default does not absorb it.
	GameSession.from_dict({
		"turns": null,
		"lost_caches": [cache_entry.merged({"turn_lost": null})],
	})
	assert_eq(GameSession.turns, 0)
	assert_eq(GameSession.lost_caches[0].turn_lost, 0)

	# Negative: the clock is monotonic, so a corrupt save floors instead of running it backwards.
	GameSession.from_dict({
		"turns": -3,
		"lost_caches": [cache_entry.merged({"turn_lost": -4})],
	})
	assert_eq(GameSession.turns, 0)
	assert_eq(GameSession.lost_caches[0].turn_lost, 0)


func test_explicit_null_version_loads_from_disk_instead_of_crashing_at_boot() -> void:
	# load_game() reads version before any from_dict, so this one crashes earlier than the rest.
	var file := FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	file.store_string('{"version": null, "roster": [{"name": "Ash", "rank": 2}]}')
	file.close()

	assert_true(SaveService.load_game())
	assert_eq(GameSession.roster.size(), 1)
	assert_eq(GameSession.roster[0].rank, 2)
