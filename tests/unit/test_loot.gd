extends GutTest

const BALANCE: BalanceTable = preload("res://balance.tres")
const VERDANT: ZoneDefinition = preload("res://zones/defs/verdant_outskirts.tres")
const ASHFALL: ZoneDefinition = preload("res://zones/defs/ashfall_reaches.tres")
const SUNDERED: ZoneDefinition = preload("res://zones/defs/sundered_vault.tres")


func before_each() -> void:
	GameSession.from_dict({"roster": []})


func test_authored_loot_bands_match_the_design() -> void:
	assert_eq(VERDANT.loot_rank_min, 0)
	assert_eq(VERDANT.loot_rank_max, 2)
	assert_eq(ASHFALL.loot_rank_min, 2)
	assert_eq(ASHFALL.loot_rank_max, 4)
	assert_eq(SUNDERED.loot_rank_min, 5)
	assert_eq(SUNDERED.loot_rank_max, 7)


func test_loot_roll_is_deterministic_and_resolves_all_slots() -> void:
	var first: Item = Expedition.roll_loot(VERDANT, BALANCE, 42)
	var second: Item = Expedition.roll_loot(VERDANT, BALANCE, 42)
	var slots: Dictionary[StringName, bool] = {}
	for loot_seed: int in range(1000):
		var item: Item = Expedition.roll_loot(VERDANT, BALANCE, loot_seed)
		assert_gte(item.rank, VERDANT.loot_rank_min)
		assert_lte(item.rank, VERDANT.loot_rank_max)
		assert_not_null(Item.definition_for(item.def_id))
		slots[item.def_id] = true

	assert_eq(first.def_id, second.def_id)
	assert_eq(first.rank, second.rank)
	assert_eq(slots.size(), EquipmentDefinition.Slot.size())


func test_each_zone_rolls_only_its_band() -> void:
	for zone: ZoneDefinition in [VERDANT, ASHFALL, SUNDERED]:
		var ranks: Dictionary[int, bool] = {}
		for loot_seed: int in range(1000):
			var item: Item = Expedition.roll_loot(zone, BALANCE, loot_seed)
			assert_gte(item.rank, zone.loot_rank_min)
			assert_lte(item.rank, zone.loot_rank_max)
			ranks[item.rank] = true
		assert_eq(ranks.size(), zone.loot_rank_max - zone.loot_rank_min + 1)


func test_only_completed_expeditions_add_pace_items_and_round_trip_them() -> void:
	var hero: Hero = _add_knight()
	var completed := Expedition.new()
	var team: Array[Hero] = [hero]
	var outcome: StringName = completed.resolve(team, _make_zone(0, 1))

	assert_eq(outcome, Expedition.OUTCOME_COMPLETED)
	# ig-1jw: a completed run rolls battle_pace items; the first is the boss_loot_seed roll.
	assert_eq(GameSession.inventory.size(), BALANCE.battle_pace)
	var saved: Dictionary = GameSession.to_dict()
	GameSession.from_dict({"roster": []})
	GameSession.from_dict(saved)
	assert_eq(GameSession.inventory.size(), BALANCE.battle_pace)
	assert_eq(GameSession.inventory[0].to_dict(), completed.loot.to_dict())

	GameSession.from_dict({"roster": []})
	hero = _add_knight()
	var retreated := Expedition.new()
	# A lost wave here costs 84% HP, so retreat is overwhelmingly likely but not certain -
	# seeding the global RNG keeps this branch reproducible the way test_expedition.gd does.
	seed(1)
	outcome = retreated.resolve([hero], _make_zone(1000, 3))
	assert_eq(outcome, Expedition.OUTCOME_RETREATED)
	assert_true(GameSession.inventory.is_empty())

	GameSession.from_dict({"roster": []})
	hero = _add_knight()
	var defeated := Expedition.new()
	outcome = defeated.resolve([hero], _make_zone(1_000_000, 1))
	assert_eq(outcome, Expedition.OUTCOME_DEFEATED)
	assert_true(GameSession.inventory.is_empty())


func _add_knight() -> Hero:
	var hero := Hero.new("Knight", 0)
	hero.def_id = &"knight"
	hero.level = 10
	GameSession.add_hero(hero)
	return hero


func _make_zone(recommended_power: int, trash_wave_count: int) -> ZoneDefinition:
	var zone := ZoneDefinition.new()
	zone.zone_id = &"verdant_outskirts"  # A known zone: mark_zone_cleared saves it, and a save must load (ig-6pm).
	zone.recommended_power = recommended_power
	zone.trash_wave_count = trash_wave_count
	zone.trash_wave_start_fraction = 1.0
	zone.trash_wave_end_fraction = 1.0
	zone.boss_fraction = 1.0
	return zone
