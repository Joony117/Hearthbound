class_name Expedition
extends RefCounted
## One expedition run's wave index and transient HP, per the No CombatState ADR.

const BALANCE: BalanceTable = preload("res://balance.tres")
const RETREAT_THRESHOLD: float = 0.25
const OUTCOME_COMPLETED: StringName = &"completed"
const OUTCOME_RETREATED: StringName = &"retreated"
const OUTCOME_DEFEATED: StringName = &"defeated"
const OUTCOME_INVALID_TEAM: StringName = &"invalid_team"

var wave_index: int = -1
var waves_resolved: int = 0
var current_hp: Dictionary[Hero, float] = {}
var maximum_hp: Dictionary[Hero, float] = {}
var loot: Item = null


func resolve(team: Array[Hero], zone: ZoneDefinition) -> StringName:
	return _resolve(team, zone, null)


func resolve_seeded(team: Array[Hero], zone: ZoneDefinition, run_seed: int) -> StringName:
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed
	return _resolve(team, zone, rng)


func _resolve(
	team: Array[Hero],
	zone: ZoneDefinition,
	rng: RandomNumberGenerator,
) -> StringName:
	assert(team.size() >= 1 and team.size() <= 5)
	assert(zone != null)
	assert(zone.zone_id != &"")
	assert(zone.trash_wave_count > 0)

	wave_index = -1
	waves_resolved = 0
	current_hp.clear()
	maximum_hp.clear()
	loot = null
	for hero: Hero in team:
		if Hero.definition_for(hero.def_id) == null:
			return OUTCOME_INVALID_TEAM
	# Before the waves, not after: a hero dying below stamps its LostCache with the turn this
	# expedition became, so an immediate recovery run reads turns_elapsed == 0 rather than -1
	# (docs/SYSTEMS.md, Turns).
	GameSession.advance_turn(BALANCE)
	var xp_multiplier: float = GameSession.training_xp_multiplier()

	# The boss index is trash_wave_count, so this bound remains safe in release builds.
	var boss_loot_seed: int = 0
	for next_wave_index: int in range(zone.trash_wave_count + 1):
		wave_index = next_wave_index
		var wave := Wave.from_zone(zone, next_wave_index)
		var result: CombatResult = (
			QuickResolve.resolve_seeded(team, wave, rng)
			if rng != null
			else QuickResolve.resolve(team, wave)
		)
		if next_wave_index == zone.trash_wave_count:
			boss_loot_seed = result.loot_seed
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
				GameSession.kill_hero(hero, zone.zone_id, BALANCE)
			GameSession.credit_team_xp(
				team,
				roundi(float(BALANCE.xp_per_wave * waves_resolved * BALANCE.battle_pace) * xp_multiplier),
				BALANCE,
				true,
			)
			return OUTCOME_DEFEATED

		if next_wave_index < zone.trash_wave_count and _party_hp_fraction(team) <= RETREAT_THRESHOLD:
			GameSession.credit_team_xp(
				team,
				roundi(float(BALANCE.xp_per_wave * waves_resolved * BALANCE.battle_pace) * xp_multiplier),
				BALANCE,
				true,
			)
			return OUTCOME_RETREATED

	GameSession.mark_zone_cleared(zone.zone_id)
	# ig-1jw: a legacy order reads the live battle_pace: stones and XP xP, P loot rolls.
	loot = roll_loot(zone, BALANCE, boss_loot_seed)
	GameSession.add_item(loot)
	for roll: int in range(1, BALANCE.battle_pace):
		GameSession.add_item(roll_loot(zone, BALANCE, boss_loot_seed + roll))
	GameSession.credit_stones(ExpeditionOrders.stone_payout(zone, BALANCE.battle_pace, BALANCE))
	GameSession.credit_team_xp(
		team,
		roundi(float((BALANCE.xp_per_wave * waves_resolved + zone.xp_reward) * BALANCE.battle_pace) * xp_multiplier),
		BALANCE,
		true,
	)
	return OUTCOME_COMPLETED


static func roll_loot(zone: ZoneDefinition, balance: BalanceTable, loot_seed: int) -> Item:
	assert(zone != null)
	assert(balance != null)
	assert(zone.loot_rank_min >= 0 and zone.loot_rank_min <= zone.loot_rank_max)
	assert(zone.loot_rank_max < balance.summon_weights.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = loot_seed
	var slots: PackedStringArray = EquipmentDefinition.Slot.keys()
	# Slot first fixes the seeded drop sequence while keeping the independent rolls uniform.
	var def_id: StringName = StringName(slots[rng.randi_range(0, slots.size() - 1)].to_lower())
	var weights: Array[int] = []
	var total_weight: int = 0
	for rank: int in balance.summon_weights.size():
		var weight: int = balance.summon_weights[rank] if rank >= zone.loot_rank_min and rank <= zone.loot_rank_max else 0
		weights.append(weight)
		total_weight += weight
	assert(total_weight > 0)
	var rank: int = Summon.rank_for_ticket(rng.randi_range(0, total_weight - 1), weights, total_weight)
	assert(rank >= 0)
	return Item.new(def_id, rank)


## One skill-book roll of a victory (ig-gy0.7): a skill id, or "" for none. Book roll `roll` has its own
## generator, seeded from ("%d:book:%d" % [run_seed, roll]).hash(), so it never reuses a loot seed and
## roll_loot's draws are untouched. A book is loot, not stones: no route factor. First the zone's chance;
## then a general book (skill_book_general_share), one general skill picked uniformly; else a class book,
## one of the given archetypes (each counts once, however many heroes) and that class's book-only skill.
## No class on the roster with a book gives a general one.
static func roll_book(zone: ZoneDefinition, balance: BalanceTable, run_seed: int, roll: int, archetypes: Array[String]) -> String:
	assert(zone != null)
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d:book:%d" % [run_seed, roll]).hash()
	if rng.randf() >= zone.skill_book_drop_chance:
		return ""
	var general: Array[String] = []
	var class_books: Dictionary[String, String] = {}
	for skill: AbilityDefinition in BattleSimulation.ABILITIES.values():
		if skill.archetype == "general":
			general.append(str(skill.skill_id))
		elif skill.book_only and skill.archetype in archetypes:
			class_books[skill.archetype] = str(skill.skill_id)
	var classes: Array = class_books.keys()
	classes.sort()
	var general_draw: bool = rng.randf() < balance.skill_book_general_share
	if general_draw or classes.is_empty():
		return general[rng.randi_range(0, general.size() - 1)]
	return class_books[classes[rng.randi_range(0, classes.size() - 1)]]


## Each died record names the order whose battle stranded that hero: the incident's
## source_order_id, unless battle_orders holds an exception (a rescuer a failed rescue stranded).
static func finalize_permanent_losses(incident: Dictionary, hero_ids: Array[String]) -> void:
	var zone_id := StringName(str(incident.get("zone_id", "")))
	var links: Variant = incident.get("battle_orders")
	for hero_id: String in hero_ids:
		var hero: Hero = GameSession.hero_by_id(hero_id)
		if hero != null:
			var battle_order: String = str((links as Dictionary).get(hero_id, "")) if links is Dictionary else ""
			if battle_order.is_empty():
				battle_order = str(incident.get("source_order_id", ""))
			GameSession.kill_hero(hero, zone_id, BALANCE, "expedition", "", battle_order)


func _party_hp_fraction(team: Array[Hero]) -> float:
	var total_current := 0.0
	var total_maximum := 0.0
	for hero: Hero in team:
		total_current += current_hp[hero]
		total_maximum += maximum_hp[hero]
	assert(total_maximum > 0.0)
	return total_current / total_maximum
