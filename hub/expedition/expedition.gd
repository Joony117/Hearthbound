class_name Expedition
extends RefCounted
## One expedition run's wave index and transient HP, per the No CombatState ADR.

const RETREAT_THRESHOLD: float = 0.25
const OUTCOME_COMPLETED: StringName = &"completed"
const OUTCOME_RETREATED: StringName = &"retreated"
const OUTCOME_DEFEATED: StringName = &"defeated"
const OUTCOME_INVALID_TEAM: StringName = &"invalid_team"

var wave_index: int = -1
var waves_resolved: int = 0
var current_hp: Dictionary[Hero, float] = {}
var maximum_hp: Dictionary[Hero, float] = {}


func resolve(team: Array[Hero], zone: ZoneDefinition) -> StringName:
	assert(team.size() >= 1 and team.size() <= 5)
	assert(zone != null)
	assert(zone.zone_id != &"")
	assert(zone.trash_wave_count > 0)

	wave_index = -1
	waves_resolved = 0
	current_hp.clear()
	maximum_hp.clear()
	for hero: Hero in team:
		if Hero.definition_for(hero.def_id) == null:
			return OUTCOME_INVALID_TEAM

	# The boss index is trash_wave_count, so this bound remains safe in release builds.
	for next_wave_index: int in range(zone.trash_wave_count + 1):
		wave_index = next_wave_index
		var wave := Wave.from_zone(zone, next_wave_index)
		var result := QuickResolve.resolve(team, wave)
		waves_resolved += 1
		var dead_heroes: Array[Hero] = []

		for hero: Hero in team:
			var fresh_maximum := result.maximum_hp[hero]
			var damage_taken := fresh_maximum - result.hp_after[hero]
			if not maximum_hp.has(hero):
				maximum_hp[hero] = fresh_maximum
				current_hp[hero] = fresh_maximum
			current_hp[hero] = maxf(current_hp[hero] - damage_taken, 0.0)
			if current_hp[hero] <= 0.0:
				dead_heroes.append(hero)

		if not dead_heroes.is_empty():
			for hero: Hero in dead_heroes:
				# The expedition resolver is the sole permadeath writer (architecture rule 8).
				GameSession.kill_hero(hero)
			return OUTCOME_DEFEATED

		if next_wave_index < zone.trash_wave_count and _party_hp_fraction(team) <= RETREAT_THRESHOLD:
			return OUTCOME_RETREATED

	GameSession.mark_zone_cleared(zone.zone_id)
	return OUTCOME_COMPLETED


func _party_hp_fraction(team: Array[Hero]) -> float:
	var total_current := 0.0
	var total_maximum := 0.0
	for hero: Hero in team:
		total_current += current_hp[hero]
		total_maximum += maximum_hp[hero]
	assert(total_maximum > 0.0)
	return total_current / total_maximum
