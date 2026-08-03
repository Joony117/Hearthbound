class_name QuickResolve
extends RefCounted
## Stateless statistical combat behind the ADR-fixed combat seam.
## Per ARCHITECTURE.md rule 7, this file knows nothing about expeditions or rosters.

const BALANCE: BalanceTable = preload("res://balance.tres")


static func resolve(team: Array[Hero], wave: Wave) -> CombatResult:
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
		var level: int = BALANCE.level_caps[
			clampi(hero.rank, 0, BALANCE.level_caps.size() - 1)
		]
		definitions.append(definition)
		levels.append(level)
		var stats := Hero.compute_final_stats(hero, definition, BALANCE, level)
		result.maximum_hp[hero] = stats[Hero.STAT_HP]

	var team_power := Hero.compute_team_power(team, definitions, levels, BALANCE)
	assert(team_power > 0.0)
	var effective_enemy_power := wave.enemy_power * (float(team.size()) / 5.0)
	var won := effective_enemy_power <= 0.0 or team_power * randf() > effective_enemy_power
	result.loot_seed = randi()

	if not won:
		for hero: Hero in team:
			result.hp_after[hero] = 0.0
			result.dead_heroes.append(hero)
		return result

	var damage_fraction := effective_enemy_power / team_power
	for hero: Hero in team:
		var hp_after := result.maximum_hp[hero] * (1.0 - damage_fraction)
		result.hp_after[hero] = hp_after
		result.survivors.append(hero)
	return result
