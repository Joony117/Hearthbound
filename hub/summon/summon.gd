class_name Summon
extends RefCounted

const BALANCE: BalanceTable = preload("res://balance.tres")
const ARCHETYPE_DEF_IDS: PackedStringArray = ["knight", "rogue", "ranger", "mage", "cleric"]
const NAMES: PackedStringArray = [
	"Aldric", "Brenna", "Cassius", "Dara", "Edric", "Fenna", "Gorath", "Hilde",
	"Ivo", "Jorunn", "Kestrel", "Lyra", "Morgen", "Nils", "Orla", "Perrin",
	"Quill", "Rowan", "Sable", "Tamsin", "Ulric", "Vesna", "Wren", "Yorick",
]


static func roll() -> Hero:
	var total_weight: int = _total_weight(BALANCE.summon_weights)
	assert(total_weight > 0, "Summon weights must have a positive total.")
	assert(BALANCE.summon_weights.size() == BALANCE.rank_names.size(), "Summon weights and rank names must align.")
	var rank: int = rank_for_ticket(randi() % total_weight, BALANCE.summon_weights, total_weight)
	assert(rank >= 0, "A ticket inside the summon weight range must resolve to a rank.")
	var def_id: StringName = StringName(ARCHETYPE_DEF_IDS[randi() % ARCHETYPE_DEF_IDS.size()])
	var definition: HeroDefinition = definition_for(def_id)
	assert(definition != null, "Every authored summon archetype must resolve to a HeroDefinition.")
	var hero := Hero.new(NAMES[randi() % NAMES.size()], rank)
	hero.def_id = def_id
	return hero


static func rank_for_ticket(ticket: int, weights: Array[int], expected_total: int) -> int:
	if expected_total <= 0:
		push_error("Summon ticket mapping expected a positive total, got %d." % expected_total)
		return -1

	var total_weight: int = _total_weight(weights)
	if total_weight != expected_total:
		push_error("Summon ticket mapping expected total %d, got %d." % [expected_total, total_weight])
		return -1
	if ticket < 0 or ticket >= total_weight:
		push_error("Summon ticket %d is outside [0, %d)." % [ticket, total_weight])
		return -1

	var upper_bound: int = 0
	for rank: int in weights.size():
		upper_bound += weights[rank]
		if ticket < upper_bound:
			return rank

	push_error("Summon ticket %d did not resolve despite a validated weight table." % ticket)
	return -1


static func definition_for(def_id: StringName) -> HeroDefinition:
	return Hero.definition_for(def_id)


static func archetype_label_for(def_id: StringName) -> String:
	if def_id == Hero.NO_ARCHETYPE_DEF_ID:
		return "No archetype"
	var definition: HeroDefinition = definition_for(def_id)
	if definition == null:
		return "Missing archetype (%s)" % def_id
	return definition.display_name


static func _total_weight(weights: Array[int]) -> int:
	var total_weight: int = 0
	for weight: int in weights:
		if weight < 0:
			push_error("Summon weights cannot be negative, got %d." % weight)
			return -1
		total_weight += weight
	return total_weight
