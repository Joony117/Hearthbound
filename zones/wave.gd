class_name Wave
extends RefCounted

var enemy_power: float


func _init(p_enemy_power: float) -> void:
	enemy_power = p_enemy_power


static func from_zone(zone: ZoneDefinition, wave_index: int) -> Wave:
	assert(zone != null)
	assert(zone.trash_wave_count > 0)
	assert(wave_index >= 0 and wave_index <= zone.trash_wave_count)

	var fraction: float
	if wave_index == zone.trash_wave_count:
		fraction = zone.boss_fraction
	else:
		var progress := float(wave_index) / float(maxi(zone.trash_wave_count - 1, 1))
		fraction = lerpf(zone.trash_wave_start_fraction, zone.trash_wave_end_fraction, progress)
	return Wave.new(float(zone.recommended_power) * fraction)
