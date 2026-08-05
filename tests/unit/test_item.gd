extends GutTest


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
