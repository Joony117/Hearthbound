extends GutTest

const ERROR_MARGIN: float = 0.0001
const HERO_POWER: float = 212.0
const HERO_MAX_HP: float = 280.0


func before_each() -> void:
	GameSession.from_dict({"roster": []})


func test_zero_power_wave_sequence_completes_with_hero_alive() -> void:
	var hero := _add_knight()
	var expedition := Expedition.new()
	var team: Array[Hero] = [hero]
	seed(1)

	var outcome := expedition.resolve(team, _make_zone(0, 1.0, 2))

	assert_eq(outcome, Expedition.OUTCOME_COMPLETED)
	assert_true(GameSession.roster.has(hero))
	assert_eq(expedition.waves_resolved, 3)
	assert_almost_eq(expedition.current_hp[hero], HERO_MAX_HP, ERROR_MARGIN)


func test_overwhelming_wave_kills_once_and_shrinks_roster_once() -> void:
	var hero := _add_knight()
	var other := _add_knight("Other")
	var before_size := GameSession.roster.size()
	var expedition := Expedition.new()
	var team: Array[Hero] = [hero]
	seed(1)

	var outcome := expedition.resolve(
		team,
		_make_zone(1_000_000, 1.0, 1),
	)

	assert_eq(outcome, Expedition.OUTCOME_DEFEATED)
	assert_eq(GameSession.roster.size(), before_size - 1)
	assert_false(GameSession.roster.has(hero))
	assert_true(GameSession.roster.has(other))
	assert_eq(expedition.waves_resolved, 1)


func test_hero_without_archetype_is_refused_without_permadeath() -> void:
	var hero := Hero.new("Legacy Hero", 0)
	hero.def_id = Hero.NO_ARCHETYPE_DEF_ID
	GameSession.add_hero(hero)
	var before_size: int = GameSession.roster.size()
	var expedition := Expedition.new()
	var team: Array[Hero] = [hero]

	var outcome := expedition.resolve(team, _make_zone(1_000_000, 1.0, 1))

	assert_push_error("Missing HeroDefinition for def_id")
	assert_eq(outcome, Expedition.OUTCOME_INVALID_TEAM)
	assert_eq(expedition.waves_resolved, 0)
	assert_eq(GameSession.roster.size(), before_size)
	assert_true(GameSession.roster.has(hero))


func test_retreat_at_twenty_five_percent_stops_before_later_waves() -> void:
	var hero := _add_knight()
	var expedition := Expedition.new()
	var team: Array[Hero] = [hero]
	var team_size_factor := float(team.size()) / 5.0
	var recommended_power := int(HERO_POWER * 0.75 / (team_size_factor * 0.25))
	_seed_for_roll_above(0.75)

	var outcome := expedition.resolve(
		team,
		_make_zone(recommended_power, 0.25, 2),
	)

	assert_eq(outcome, Expedition.OUTCOME_RETREATED)
	assert_eq(expedition.waves_resolved, 1)
	assert_almost_eq(expedition.current_hp[hero], HERO_MAX_HP * 0.25, ERROR_MARGIN)
	assert_true(GameSession.roster.has(hero))


func test_damage_carries_forward_across_two_waves() -> void:
	var hero := _add_knight()
	var expedition := Expedition.new()
	var team: Array[Hero] = [hero]
	seed(1)
	var enemy_power := 14
	var team_size_factor := float(team.size()) / 5.0
	var per_wave_damage := HERO_MAX_HP * (float(enemy_power) * team_size_factor) / HERO_POWER

	var outcome := expedition.resolve(
		team,
		_make_zone(enemy_power, 1.0, 1),
	)

	assert_eq(outcome, Expedition.OUTCOME_COMPLETED)
	assert_eq(expedition.waves_resolved, 2)
	assert_almost_eq(
		expedition.current_hp[hero],
		HERO_MAX_HP - per_wave_damage * 2.0,
		ERROR_MARGIN,
	)
	assert_lt(expedition.current_hp[hero], HERO_MAX_HP - per_wave_damage)


func test_team_size_scaling_keeps_solo_and_full_team_rolls_in_parity() -> void:
	var solo_hero := Hero.new("Solo Knight", 0)
	solo_hero.def_id = &"knight"
	var solo_team: Array[Hero] = [solo_hero]
	var full_team: Array[Hero] = []
	for index: int in 5:
		var hero := Hero.new("Knight %d" % index, 0)
		hero.def_id = &"knight"
		full_team.append(hero)
	var enemy_power := HERO_POWER * 2.5
	var saw_win: bool = false
	var saw_loss: bool = false

	for rng_seed: int in range(1, 11):
		seed(rng_seed)
		var roll := randf()
		var expected_win := roll > 0.5
		seed(rng_seed)
		var solo_result := QuickResolve.resolve(solo_team, Wave.new(enemy_power))
		seed(rng_seed)
		var full_result := QuickResolve.resolve(full_team, Wave.new(enemy_power))
		var solo_won := solo_result.dead_heroes.is_empty()
		var full_won := full_result.dead_heroes.is_empty()

		assert_eq(solo_won, expected_win)
		assert_eq(full_won, expected_win)
		assert_eq(solo_won, full_won)
		saw_win = saw_win or expected_win
		saw_loss = saw_loss or not expected_win

	assert_true(saw_win)
	assert_true(saw_loss)


func _add_knight(hero_name: String = "Knight") -> Hero:
	var hero := Hero.new(hero_name, 0)
	hero.def_id = &"knight"
	GameSession.add_hero(hero)
	return hero


func _make_zone(recommended_power: int, fraction: float, trash_wave_count: int) -> ZoneDefinition:
	var zone := ZoneDefinition.new()
	zone.recommended_power = recommended_power
	zone.trash_wave_count = trash_wave_count
	zone.trash_wave_start_fraction = fraction
	zone.trash_wave_end_fraction = fraction
	zone.boss_fraction = fraction
	return zone


func _seed_for_roll_above(minimum_roll: float) -> void:
	for candidate: int in range(1000):
		seed(candidate)
		if randf() > minimum_roll:
			seed(candidate)
			return
	fail_test("No deterministic seed produced the required roll.")
