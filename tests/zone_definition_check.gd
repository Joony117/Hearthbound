extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var exit_code: int = _check_zone("Verdant Outskirts", "res://zones/defs/verdant_outskirts.tres", 900, 5, 0.5, 0.9, 1.1, "F–C parts, light Summon Stones", "Available from start")
	if exit_code != 0:
		quit(exit_code)
		return
	exit_code = _check_zone("Ashfall Reaches", "res://zones/defs/ashfall_reaches.tres", 4800, 6, 0.5, 1.0, 1.2, "C–A parts, moderate Summon Stones, first A+ drops", "Clear Verdant Outskirts")
	if exit_code != 0:
		quit(exit_code)
		return
	exit_code = _check_zone("Sundered Vault", "res://zones/defs/sundered_vault.tres", 11500, 7, 0.6, 1.1, 1.3, "S–SSS parts, heavy Summon Stones, best A+ drop rate", "Clear Ashfall Reaches")
	if exit_code == 0:
		print("PASS: all fields of all three zones match SYSTEMS.md.")
	quit(exit_code)


func _check_zone(zone_name: String, resource_path: String, expected_recommended_power: int, expected_trash_wave_count: int, expected_start_fraction: float, expected_end_fraction: float, expected_boss_fraction: float, expected_loot_emphasis: String, expected_unlock_condition: String) -> int:
	var zone: ZoneDefinition = load(resource_path) as ZoneDefinition
	if zone == null:
		return _fail("%s resource load" % zone_name, "ZoneDefinition", "null")
	if zone.display_name != zone_name:
		return _fail("%s display_name" % zone_name, zone_name, zone.display_name)
	if zone.recommended_power != expected_recommended_power:
		return _fail("%s recommended_power" % zone_name, str(expected_recommended_power), str(zone.recommended_power))
	if zone.trash_wave_count != expected_trash_wave_count:
		return _fail("%s trash_wave_count" % zone_name, str(expected_trash_wave_count), str(zone.trash_wave_count))
	if zone.trash_wave_start_fraction != expected_start_fraction:
		return _fail("%s trash_wave_start_fraction" % zone_name, str(expected_start_fraction), str(zone.trash_wave_start_fraction))
	if zone.trash_wave_end_fraction != expected_end_fraction:
		return _fail("%s trash_wave_end_fraction" % zone_name, str(expected_end_fraction), str(zone.trash_wave_end_fraction))
	if zone.boss_fraction != expected_boss_fraction:
		return _fail("%s boss_fraction" % zone_name, str(expected_boss_fraction), str(zone.boss_fraction))
	if zone.loot_emphasis != expected_loot_emphasis:
		return _fail("%s loot_emphasis" % zone_name, expected_loot_emphasis, zone.loot_emphasis)
	if zone.unlock_condition != expected_unlock_condition:
		return _fail("%s unlock_condition" % zone_name, expected_unlock_condition, zone.unlock_condition)
	return 0


func _fail(check_name: String, expected: String, actual: String) -> int:
	print("FAIL: %s | expected: %s | actual: %s" % [check_name, expected, actual])
	return 1
