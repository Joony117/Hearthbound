extends GutTest

const BALANCE: BalanceTable = preload("res://balance.tres")
const VERDANT: ZoneDefinition = preload("res://zones/defs/verdant_outskirts.tres")


func test_equal_gear_solo_duration_is_five_times_full_team_duration() -> void:
	var solo: Array[Hero] = [_hero("Solo", 0, 10)]
	var full_team: Array[Hero] = []
	for index: int in 5:
		full_team.append(_hero("Knight %d" % index, 0, 10))
	var solo_seconds: float = ExpeditionOrders.duration_seconds(solo, VERDANT, BALANCE)
	var full_seconds: float = ExpeditionOrders.duration_seconds(full_team, VERDANT, BALANCE)

	assert_gt(full_seconds, 0.0)
	assert_gt(solo_seconds, full_seconds * 4.9)
	assert_lte(solo_seconds, full_seconds * 5.0)
	# Per-order ceil rounding can differ by a few seconds, but five disjoint solo orders and one
	# five-hero order still have the same authored throughput within two percent.
	var solo_fleet_throughput: float = 5.0 / solo_seconds
	var full_team_throughput: float = 1.0 / full_seconds
	assert_lt(absf(solo_fleet_throughput - full_team_throughput) / full_team_throughput, 0.02)
	print("ig-6l4 equal-gear Verdant durations: solo %.0fs, five-hero %.0fs" % [solo_seconds, full_seconds])


func test_fresh_three_hero_pace_is_finite_and_respects_the_authored_floor() -> void:
	var team: Array[Hero] = [
		_hero("Knight", 0, 0, &"knight"),
		_hero("Rogue", 0, 0, &"rogue"),
		_hero("Cleric", 0, 0, &"cleric"),
	]
	var duration: float = ExpeditionOrders.duration_seconds(team, VERDANT, BALANCE)

	assert_gt(duration, 0.0)
	assert_gte(duration, ceilf(VERDANT.minimum_duration_seconds * 5.0 / 3.0))
	print("ig-6l4 fresh three-hero Verdant duration: %.0f seconds" % duration)


func test_worst_case_forecast_honors_the_exact_retreat_boundary() -> void:
	var hero: Hero = _hero("Boundary", 0, 10)
	var team: Array[Hero] = [hero]
	var definition: HeroDefinition = Hero.definition_for(hero.def_id)
	var team_power: float = Hero.compute_team_power(team, [definition], [hero.level], BALANCE)
	var desired_ratio: float = pow(0.25, 1.0 / 3.0)
	var recommended_power: int = ceili(team_power * desired_ratio / 0.2)
	var safe_zone: ZoneDefinition = _zone(recommended_power, 2)
	var retreat_zone: ZoneDefinition = _zone(recommended_power, 3)

	var safe_forecast: Dictionary = ExpeditionOrders.safety_forecast(team, safe_zone, BALANCE)
	var retreat_forecast: Dictionary = ExpeditionOrders.safety_forecast(team, retreat_zone, BALANCE)

	assert_true(bool(safe_forecast["safe"]))
	assert_false(bool(retreat_forecast["safe"]))
	assert_string_contains(str(retreat_forecast["reason"]), "retreat")


func test_mixed_team_traits_and_stats_feed_forecast_power() -> void:
	var knight: Hero = _hero("Knight", 0, 10, &"knight")
	var rogue: Hero = _hero("Rogue", 1, 20, &"rogue")
	rogue.resonance = 6
	rogue.taught_traits = [&"rogue_quick_hands"]
	var mixed_team: Array[Hero] = [knight, rogue]

	var duration_with_traits: float = ExpeditionOrders.duration_seconds(mixed_team, VERDANT, BALANCE)
	rogue.resonance = 0
	rogue.taught_traits.clear()
	var duration_without_traits: float = ExpeditionOrders.duration_seconds(mixed_team, VERDANT, BALANCE)

	assert_lte(duration_with_traits, duration_without_traits)
	assert_has(ExpeditionOrders.safety_forecast(mixed_team, VERDANT, BALANCE), "safe")


func test_seeded_quick_resolve_replays_hp_and_loot_seed() -> void:
	var hero: Hero = _hero("Seeded", 0, 10)
	var team: Array[Hero] = [hero]
	var first_rng := RandomNumberGenerator.new()
	first_rng.seed = 424242
	var second_rng := RandomNumberGenerator.new()
	second_rng.seed = 424242

	var first: CombatResult = QuickResolve.resolve_seeded(team, Wave.new(500.0), first_rng)
	var second: CombatResult = QuickResolve.resolve_seeded(team, Wave.new(500.0), second_rng)

	assert_eq(first.loot_seed, second.loot_seed)
	assert_almost_eq(first.hp_after[hero], second.hp_after[hero], 0.000001)
	assert_eq(first.dead_heroes.has(hero), second.dead_heroes.has(hero))


func _hero(
	hero_name: String,
	rank: int,
	level: int,
	def_id: StringName = &"knight",
) -> Hero:
	var hero := Hero.new(hero_name, rank)
	hero.level = level
	hero.def_id = def_id
	return hero


func _zone(recommended_power: int, trash_wave_count: int) -> ZoneDefinition:
	var zone := ZoneDefinition.new()
	zone.zone_id = &"forecast_test"
	zone.recommended_power = recommended_power
	zone.trash_wave_count = trash_wave_count
	zone.trash_wave_start_fraction = 1.0
	zone.trash_wave_end_fraction = 1.0
	zone.boss_fraction = 1.0
	return zone
