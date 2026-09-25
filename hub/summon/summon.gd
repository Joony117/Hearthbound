class_name Summon
extends RefCounted

const BALANCE: BalanceTable = preload("res://balance.tres")
const ARCHETYPE_DEF_IDS: PackedStringArray = ["knight", "rogue", "ranger", "mage", "cleric"]
const FIRST_NAMES: PackedStringArray = [
	"Aldric", "Brenna", "Cassius", "Dara", "Edric", "Fenna", "Gorath", "Hilde",
	"Ivo", "Jorunn", "Kestrel", "Lyra", "Morgen", "Nils", "Orla", "Perrin",
	"Quill", "Rowan", "Sable", "Tamsin", "Ulric", "Vesna", "Wren", "Yorick",
]
const SURNAMES: PackedStringArray = [
	"Ashdown", "Brackwater", "Coldmere", "Dunhollow", "Emberfell", "Fairwind",
	"Greymantle", "Hallowick", "Ironmoor", "Jarlsbane", "Kestrelmark", "Lowthorn",
	"Marrowvale", "Northgate", "Oakenshield", "Pinecroft", "Quarryhelm", "Ravensworth",
	"Stormhaven", "Thornbury", "Underhill", "Valebrook", "Westmarch", "Yarrowgild",
]


static func roll(circle_level: int = 0) -> Hero:
	var weights: Array[int] = weights_for_circle_level(circle_level, BALANCE.summon_weights)
	var total_weight: int = _total_weight(weights)
	assert(total_weight > 0, "Summon weights must have a positive total.")
	assert(weights.size() == BALANCE.rank_names.size(), "Summon weights and rank names must align.")
	var rank: int = rank_for_ticket(randi() % total_weight, weights, total_weight)
	assert(rank >= 0, "A ticket inside the summon weight range must resolve to a rank.")
	# The class, after the rank and apart from it: the Circle moves ranks only (SYSTEMS.md, Class odds).
	var class_weights: Array[int] = BALANCE.summon_archetype_weights
	var class_total: int = _total_weight(class_weights)
	assert(class_total > 0, "Summon class weights must have a positive total.")
	assert(class_weights.size() == ARCHETYPE_DEF_IDS.size(), "Summon class weights and archetypes must align.")
	var def_id: StringName = StringName(ARCHETYPE_DEF_IDS[rank_for_ticket(randi() % class_total, class_weights, class_total)])
	var definition: HeroDefinition = definition_for(def_id)
	assert(definition != null, "Every authored summon archetype must resolve to a HeroDefinition.")
	var hero := Hero.new(random_name(), rank)
	hero.def_id = def_id
	return hero


## First and last name rolled independently, so 24 x 24 combinations carry the roster far enough
## past the collision point that two identical names read as a coincidence rather than a bug.
static func random_name() -> String:
	return "%s %s" % [
		FIRST_NAMES[randi() % FIRST_NAMES.size()],
		SURNAMES[randi() % SURNAMES.size()],
	]


static func weights_for_circle_level(circle_level: int, base_weights: Array[int]) -> Array[int]:
	var copied_base_weights: Array[int] = base_weights.duplicate()
	var level: int = clampi(circle_level, 0, BALANCE.summoning_circle_level_cap)
	var circle_multiplier: float = 1.0 + BALANCE.summoning_circle_multiplier_per_level * float(level)
	var unscaled_weight_total: int = 0
	var scaled_weight_total: int = 0
	for rank: int in copied_base_weights.size():
		if rank < 4:
			unscaled_weight_total += copied_base_weights[rank]
		else:
			scaled_weight_total += copied_base_weights[rank]
	var denominator: float = float(unscaled_weight_total) + circle_multiplier * float(scaled_weight_total)
	var renormalization_scale: float = float(_total_weight(copied_base_weights)) / denominator
	var renormalized_weights: Array[int] = []
	for rank: int in copied_base_weights.size():
		var weight: float = float(copied_base_weights[rank])
		if rank >= 4:
			weight *= circle_multiplier
		renormalized_weights.append(roundi(weight * renormalization_scale))
	return renormalized_weights


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
