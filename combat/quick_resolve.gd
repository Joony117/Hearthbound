class_name QuickResolve
extends RefCounted
## Stateless statistical combat behind the ADR-fixed combat seam.
## Per ARCHITECTURE.md rule 7, this file knows nothing about expeditions or rosters.

const BALANCE: BalanceTable = preload("res://balance.tres")


static func resolve(team: Array[Hero], wave: Wave) -> CombatResult:
	return _resolve(team, wave, randf(), randi())


## Timed orders persist the RNG seed and use a local generator so a pre-commit crash replays
## the same run without perturbing, or depending on, unrelated global random calls.
static func resolve_seeded(
	team: Array[Hero],
	wave: Wave,
	rng: RandomNumberGenerator,
) -> CombatResult:
	assert(rng != null)
	return _resolve(team, wave, rng.randf(), rng.randi())


static func _resolve(
	team: Array[Hero],
	wave: Wave,
	win_roll: float,
	loot_seed: int,
) -> CombatResult:
	assert(not team.is_empty())
	assert(wave != null)
	assert(wave.enemy_power >= 0.0)

	var definitions: Array[HeroDefinition] = []
	var levels: Array[int] = []
	var result := CombatResult.new()
	for hero: Hero in team:
		var definition: HeroDefinition = Hero.definition_for(hero.def_id)
		if definition == null:
			return result
		var level: int = Hero.level_for(hero, BALANCE)
		definitions.append(definition)
		levels.append(level)
		var stats := Hero.compute_final_stats(hero, definition, BALANCE, level)
		result.maximum_hp[hero] = stats[Hero.STAT_HP]

	var team_power := Hero.compute_team_power(team, definitions, levels, BALANCE)
	assert(team_power > 0.0)
	var effective_enemy_power := wave.enemy_power * (float(team.size()) / 5.0)
	var won := effective_enemy_power <= 0.0 or team_power * win_roll > effective_enemy_power
	result.loot_seed = loot_seed
	var r := effective_enemy_power / team_power

	if not won:
		var loss_fraction: float = clamp(
			BALANCE.wave_loss_damage_coefficient * r * r * r,
			0.0,
			1.0,
		)
		for hero: Hero in team:
			var hp_after := result.maximum_hp[hero] * (1.0 - loss_fraction)
			result.hp_after[hero] = hp_after
			if hp_after > 0.0:
				result.survivors.append(hero)
			else:
				result.dead_heroes.append(hero)
		return result

	var damage_fraction: float = clamp(BALANCE.wave_damage_coefficient * r * r * r, 0.0, 1.0)
	for hero: Hero in team:
		var hp_after := result.maximum_hp[hero] * (1.0 - damage_fraction)
		result.hp_after[hero] = hp_after
		result.survivors.append(hero)
	return result
