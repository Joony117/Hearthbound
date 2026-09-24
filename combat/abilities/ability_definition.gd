class_name AbilityDefinition
extends Resource

## One skill (DECISIONS.md 2026-09-23, Skills, item 1). BattleSimulation applies its effects
## through one function; nothing branches on which skill it is.

const KINDS: Array[String] = ["passive", "weaponskill", "ability"]
const ARCHETYPES: Array[String] = ["knight", "ranger", "mage", "rogue", "cleric", "general"]
const COUNTER_TAGS: Array[String] = ["", "stun", "interrupt", "shield", "dodge"]
## "always": whenever it is ready. "allies_near": at least ai_count living allies within ai_radius
## of the caster, the caster included. "enemies_near_target": at least ai_count opponents within
## ai_radius of the target, or (ai_or_elite) the target is elite.
const AI_RULES: Array[String] = ["always", "allies_near", "enemies_near_target"]
## The primitives built so far, from the ADR's closed set (heal, shield and taunt come with the
## slices that use them), each with the keys it may carry beyond "type".
## damage area: "target" (the target only), "circle" (radius_units around the point) or "line"
## (range_units long, radius_units wide, toward the target). A "required" effect that lands on
## nobody fails the cast; it must come before any effect that changes state.
## status on "self" is always on for a passive; on "allies_near_caster" it is applied for "seconds".
## revive lands only on a downed ally target, and "stop" skips the effects after it when it does.
const EFFECT_KEYS: Dictionary = {
	"damage": ["area", "multiplier", "required"],
	"status": ["target", "status", "magnitude", "seconds", "radius"],
	"revive": ["fraction", "stop"],
	"interrupt": ["stun_seconds"],
	"move": ["to"],
}
const DAMAGE_AREAS: Array[String] = ["target", "circle", "line"]
const STATUS_TARGETS: Array[String] = ["self", "allies_near_caster"]
## guard: damage taken x (1 - magnitude) while it lasts; the strongest applies.
## ally_near_damage_reduction: damage taken x (1 - magnitude) within radius of a living ally.
## rear_basic_damage: basic hits from behind x (1 + magnitude). basic_range: basic range
## x (1 + magnitude). cooldown_reduction: ability cooldowns x (1 - magnitude).
const STATUSES: Array[String] = ["guard", "ally_near_damage_reduction", "rear_basic_damage", "basic_range", "cooldown_reduction"]
const MOVE_TO: Array[String] = ["behind_target"]

@export var skill_id: StringName = &""
@export var display_name: String = ""
@export_enum("passive", "weaponskill", "ability") var kind: String = "ability"
@export var archetype: String = ""
@export var unlock_level: int = 1
@export var book_only: bool = false
@export var counter_tag: String = ""
## The skill this one follows in a combo, or empty.
@export var combo_after: StringName = &""
@export var cooldown_seconds: float = 0.0
@export var range_units: float = 0.0
## The skill's area: circle radius, line width or aura radius.
@export var radius_units: float = 0.0
## Cast without a target, it is cast on the caster at the caster's feet.
@export var self_centered: bool = false
@export var ai_rule: String = "always"
@export var ai_count: int = 0
@export var ai_radius: float = 0.0
@export var ai_or_elite: bool = false
## The AI casts it on a downed ally before anything else.
@export var ai_revive_first: bool = false
@export var effects: Array[Dictionary] = []


## Empty when the skill is well-formed, else the first problem.
func validate() -> String:
	if skill_id == &"" or display_name.is_empty():
		return "Skill needs a skill_id and a display_name."
	if not kind in KINDS or not archetype in ARCHETYPES or not counter_tag in COUNTER_TAGS or not ai_rule in AI_RULES:
		return "Skill %s kind, archetype, counter_tag or ai_rule is unknown." % skill_id
	if unlock_level < 1 or cooldown_seconds < 0.0 or range_units < 0.0 or radius_units < 0.0 or ai_count < 0 or ai_radius < 0.0:
		return "Skill %s has a negative number or an unlock level below 1." % skill_id
	if effects.is_empty():
		return "Skill %s has no effects." % skill_id
	for effect: Dictionary in effects:
		var type: String = str(effect.get("type", ""))
		if not EFFECT_KEYS.has(type):
			return "Skill %s has an unknown primitive '%s'." % [skill_id, type]
		for key: Variant in effect:
			if key != "type" and not key in EFFECT_KEYS[type]:
				return "Skill %s %s effect has an unknown field '%s'." % [skill_id, type, key]
		if type == "damage" and (not str(effect.get("area", "")) in DAMAGE_AREAS or float(effect.get("multiplier", 0.0)) <= 0.0):
			return "Skill %s damage needs a known area and a positive multiplier." % skill_id
		if type == "status" and (not str(effect.get("target", "")) in STATUS_TARGETS or not str(effect.get("status", "")) in STATUSES):
			return "Skill %s status needs a known target and status." % skill_id
		if type == "move" and not str(effect.get("to", "")) in MOVE_TO:
			return "Skill %s move needs a known destination." % skill_id
	return ""
