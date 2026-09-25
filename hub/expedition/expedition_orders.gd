class_name ExpeditionOrders
extends RefCounted
## Pure timing, availability, and worst-case forecast rules for timed expeditions.


static func duration_seconds(
	team: Array[Hero],
	zone: ZoneDefinition,
	balance: BalanceTable,
) -> float:
	if team.is_empty() or team.size() > 5 or zone == null or zone.recommended_power <= 0:
		return 0.0
	var definitions: Array[HeroDefinition] = []
	var levels: Array[int] = []
	for hero: Hero in team:
		var definition: HeroDefinition = Hero.definition_for(hero.def_id)
		if definition == null:
			return 0.0
		definitions.append(definition)
		levels.append(Hero.level_for(hero, balance))
	var team_power: float = Hero.compute_team_power(team, definitions, levels, balance)
	var scaled_zone_power: float = float(zone.recommended_power) * float(team.size()) / 5.0
	if team_power <= 0.0 or scaled_zone_power <= 0.0:
		return 0.0
	var combat_ratio: float = team_power / scaled_zone_power
	# ig-1jw: a legacy order reads the live battle_pace.
	var full_team_seconds: float = maxf(
		zone.minimum_duration_seconds * balance.battle_pace,
		zone.base_duration_seconds * balance.battle_pace / sqrt(combat_ratio),
	)
	return ceilf(full_team_seconds * 5.0 / float(team.size()))


static func force_duration_seconds(team: Array[Hero], zone: ZoneDefinition, balance: BalanceTable) -> float:
	if team.is_empty() or zone == null or team.size() > zone.hero_cap or zone.reference_force_size <= 0:
		return 0.0
	var definitions: Array[HeroDefinition] = []
	var levels: Array[int] = []
	for hero: Hero in team:
		var definition: HeroDefinition = Hero.definition_for(hero.def_id)
		if definition == null:
			return 0.0
		definitions.append(definition)
		levels.append(Hero.level_for(hero, balance))
	var team_power: float = Hero.compute_team_power(team, definitions, levels, balance)
	var scaled_zone_power: float = float(zone.recommended_power) * float(team.size()) / float(zone.reference_force_size)
	if team_power <= 0.0 or scaled_zone_power <= 0.0:
		return 0.0
	# ig-1jw: the route is x battle_pace; the battle spawns with the same live pace.
	var full_force_seconds: float = maxf(zone.minimum_duration_seconds * balance.battle_pace, zone.base_duration_seconds * balance.battle_pace / sqrt(team_power / scaled_zone_power))
	return ceilf(full_force_seconds * float(zone.reference_force_size) / float(team.size()))


static func safety_forecast(
	team: Array[Hero],
	zone: ZoneDefinition,
	balance: BalanceTable,
) -> Dictionary:
	if team.is_empty() or team.size() > 5:
		return {"safe": false, "reason": "A team must contain 1 to 5 heroes."}
	if zone == null or zone.trash_wave_count <= 0:
		return {"safe": false, "reason": "The destination is invalid."}

	var definitions: Array[HeroDefinition] = []
	var levels: Array[int] = []
	var current_hp: Dictionary[Hero, float] = {}
	var maximum_hp: Dictionary[Hero, float] = {}
	for hero: Hero in team:
		var definition: HeroDefinition = Hero.definition_for(hero.def_id)
		if definition == null:
			return {"safe": false, "reason": "A selected hero has no valid definition."}
		definitions.append(definition)
		var level: int = Hero.level_for(hero, balance)
		levels.append(level)
		var stats: Dictionary[StringName, float] = Hero.compute_final_stats(hero, definition, balance, level)
		var hero_maximum_hp: float = stats[Hero.STAT_HP]
		maximum_hp[hero] = hero_maximum_hp
		current_hp[hero] = hero_maximum_hp

	var team_power: float = Hero.compute_team_power(team, definitions, levels, balance)
	if team_power <= 0.0:
		return {"safe": false, "reason": "The selected team has no combat power."}
	for wave_index: int in range(zone.trash_wave_count + 1):
		var wave: Wave = Wave.from_zone(zone, wave_index)
		var effective_enemy_power: float = wave.enemy_power * (float(team.size()) / 5.0)
		var power_ratio: float = effective_enemy_power / team_power
		var damage_fraction: float = clampf(
			balance.wave_loss_damage_coefficient * power_ratio * power_ratio * power_ratio,
			0.0,
			1.0,
		)
		for hero: Hero in team:
			var hp_after: float = maximum_hp[hero] * (1.0 - damage_fraction)
			var damage_taken: float = maximum_hp[hero] - hp_after
			current_hp[hero] = maxf(
				current_hp[hero] - damage_taken,
				0.0,
			)
			if current_hp[hero] <= 0.0:
				return {"safe": false, "reason": "Worst-case damage can kill %s." % hero.hero_name}
		if wave_index < zone.trash_wave_count:
			var total_current: float = 0.0
			var total_maximum: float = 0.0
			for hero: Hero in team:
				total_current += current_hp[hero]
				total_maximum += maximum_hp[hero]
			if total_current / total_maximum <= Expedition.RETREAT_THRESHOLD:
				return {"safe": false, "reason": "Worst-case damage reaches the retreat threshold."}
	return {"safe": true, "reason": "Every hero survives the worst-case loss sequence without retreating."}


static func is_zone_unlocked(
	zone_id: StringName,
	cleared_zone_ids: Dictionary[StringName, bool],
) -> bool:
	match zone_id:
		&"verdant_outskirts":
			return true
		&"ashfall_reaches":
			return cleared_zone_ids.has(&"verdant_outskirts")
		&"sundered_vault":
			return cleared_zone_ids.has(&"ashfall_reaches")
		&"fallen_citadel", &"frontier_march":
			return cleared_zone_ids.has(&"ashfall_reaches")
	return false
