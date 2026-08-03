extends GutTest

const ERROR_MARGIN: float = 0.0001


func test_zone_ramp_builds_first_middle_last_and_boss_waves() -> void:
	var zone := ZoneDefinition.new()
	zone.recommended_power = 1000
	zone.trash_wave_count = 5
	zone.trash_wave_start_fraction = 0.5
	zone.trash_wave_end_fraction = 0.9
	zone.boss_fraction = 1.1

	assert_almost_eq(Wave.from_zone(zone, 0).enemy_power, 500.0, ERROR_MARGIN, "first trash")
	assert_almost_eq(Wave.from_zone(zone, 2).enemy_power, 700.0, ERROR_MARGIN, "middle trash")
	assert_almost_eq(Wave.from_zone(zone, 4).enemy_power, 900.0, ERROR_MARGIN, "last trash")
	assert_almost_eq(Wave.from_zone(zone, 5).enemy_power, 1100.0, ERROR_MARGIN, "boss")


func test_single_trash_wave_uses_zero_progress_without_dividing_by_zero() -> void:
	var zone := ZoneDefinition.new()
	zone.recommended_power = 1000
	zone.trash_wave_count = 1
	zone.trash_wave_start_fraction = 0.5
	zone.trash_wave_end_fraction = 0.9
	zone.boss_fraction = 1.1

	assert_almost_eq(Wave.from_zone(zone, 0).enemy_power, 500.0, ERROR_MARGIN, "single trash")
	assert_almost_eq(Wave.from_zone(zone, 1).enemy_power, 1100.0, ERROR_MARGIN, "boss")
