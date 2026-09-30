class_name AbilityDefinition
extends Resource

## One skill (DECISIONS.md 2026-09-23, Skills, item 1). BattleSimulation applies its effects
## through one function; nothing branches on which skill it is.

const KINDS: Array[String] = ["passive", "weaponskill", "ability"]
## "enemy_<class>": carried only by enemies of that class (SYSTEMS.md § Skills, Enemies); no hero
## kit, bar or save lists it, since each of those takes only its own class or "general".
const ARCHETYPES: Array[String] = ["knight", "ranger", "mage", "rogue", "cleric", "general", "enemy_knight"]
const COUNTER_TAGS: Array[String] = ["", "stun", "interrupt", "shield", "dodge"]
## The AI rule: when the picker (BattleSimulation._auto_cast) wants the skill. Its band is the
## picker's priority: revive, then heal, then buff, then attack (SYSTEMS.md § Skills).
## attack band:
##   "always": whenever it is ready. "default": a weaponskill for when no other one fits.
##   "combo": right after its combo_after step: a weaponskill after the last swing's skill, an
##   ability after the last ability cast (Ground Slam after Charge, ig-zht).
##   "enemies_near_target": at least ai_count opponents within ai_radius of the target, or
##   (ai_or_elite) the target is elite. "enemies_near_self": ai_count opponents within ai_radius of
##   the caster. "target_below": the target's HP below ai_fraction. "target_lacks_status": the
##   target has no ai_status.
## buff band: "allies_near": at least ai_count living allies within ai_radius of the caster, the
##   caster included. "allies_near_ally" (Hearthward): the lowest-HP ally within range_units with
##   ai_count living allies (itself included) within ai_radius of it, one of them below ai_fraction or
##   inside an enemy telegraph. "fight_on": the caster has a target in range. "enemy_on_weaker_ally": the
##   caster's own target when it is within range_units and attacks a back-row ally (a Knight's
##   covered threat, ig-uu7.2), else an enemy within range_units that attacks a back-row ally or an
##   ally with less HP (as a fraction) than the caster. "melee_near_back_row" (Rime Wall, ig-vl1.5): a
##   living enemy melee actor ai_min_radius to ai_radius from a living back-row ally (Ranger, Mage,
##   Cleric); the cast point is ai_offset from that ally toward it, within range_units. The nearest
##   such pair decides, ties to the lower spawn index (the enemy's, then the ally's).
## heal band: "ally_below_heal_below": the lowest-HP ally within range_units below the battle's
##   heal_below. "ally_below": the lowest-HP ally within range_units below ai_fraction (of
##   ai_archetype when set, without ai_status when set). "allies_below": ai_count allies within
##   ai_radius below ai_fraction. "self_below": the caster below ai_fraction. ai_no_ready_heal:
##   only while none of the hero's own class heals is ready (Field Dressing).
## revive band: "downed_ally": the nearest downed ally. ai_revive_first adds the revive band to a
##   skill whose rule is in another band.
## "telegraph": only as a counter (BattleSimulation._answer_telegraphs); the picker never fires it.
## Counters sit above every band: the answer runs before the picker each tick. A counter with
## another rule (Warding Glyph) is also picked by that rule.
const AI_RULES: Array[String] = [
	"always", "default", "combo", "enemies_near_target", "enemies_near_self", "target_below", "target_lacks_status",
	"allies_near", "allies_near_ally", "fight_on", "enemy_on_weaker_ally", "melee_near_back_row",
	"ally_below_heal_below", "ally_below", "allies_below", "self_below",
	"downed_ally", "telegraph",
]
const AI_BANDS: Dictionary = {
	"always": "attack", "default": "attack", "combo": "attack", "enemies_near_target": "attack",
	"enemies_near_self": "attack", "target_below": "attack", "target_lacks_status": "attack",
	"allies_near": "buff", "allies_near_ally": "buff", "fight_on": "buff", "enemy_on_weaker_ally": "buff",
	"melee_near_back_row": "buff",
	"ally_below_heal_below": "heal", "ally_below": "heal", "allies_below": "heal", "self_below": "heal",
	"downed_ally": "revive", "telegraph": "",
}
## The closed set of primitives (ADR item 1), each with the keys it may carry beyond "type".
## damage area: "target" (the target only), "circle" (radius_units around the point), "line"
## (range_units long, radius_units wide, toward the target), "around_caster" (radius_units around
## the caster) or "near_target" (up to count other opponents nearest the target, within
## radius_units of it). A "required" effect that lands on nobody fails the cast; it must come before
## any effect that changes state. combo_multiplier replaces multiplier on a combo step.
## delay_seconds: the area is marked and lands that much later (a telegraph). push: units each living,
## non-elite target it hits is knocked back (SYSTEMS.md § Knockback), after every hit has landed.
## heal: multiplier x the caster's ATK, or max_hp_fraction of the healed ally's max HP; area
## "target" (a living, hurt ally; the cast needs one), "self" or "allies_near_caster". Never past
## max HP.
## shield: multiplier x the caster's ATK on the target ally, for seconds.
## status on "self" is always on for a passive; on an ability it lasts "seconds", on "self",
## "target" or "allies_near_caster". magnitude is a fraction, or for bleed, burn and
## heal_over_time the caster's ATK multiple per second. combo: only on a combo step.
## revive lands only on a downed ally target, and "stop" skips the effects after it when it does.
## interrupt: cancels the target's pending action, and stuns it for stun_seconds (0 = no stun). area
## "around_caster": every living opponent within radius_units of the caster instead (ig-zht).
## move: "behind_target", "away" (distance units straight back from the target), or "charge"
## (ig-zht): straight to distance units short of the target; every other living opponent within
## radius_units / 2 of that line is pushed lane_push units sideways first (SYSTEMS.md § The v1 kits).
## taunt: the target attacks the caster for seconds.
## zone (ig-vl1.4; DECISIONS.md 2026-09-25, "Casters shape the field"): a circle of radius_units at the
## point for seconds. Each skill_status_tick_seconds it applies pulse, a list of damage (multiplier),
## heal (multiplier) or status (status, magnitude, seconds) effects, to every living actor of side
## ("opponents" or "allies") inside it: amounts are x the caster's ATK at the cast, no crit. A pulse
## status is a timed status that doesn't tick itself; a stat status may cut its stat (magnitude down
## to above -1: Rime Circle's slow).
## wall (ig-vl1.5; same ADR, items 5-6): a segment length long and thickness thick for seconds, centered on
## the point and across the line it was aimed along. It blocks walking for both sides, not attacks. Any
## actor it lands on is pushed out across it (SYSTEMS.md § Casters, Walls). An ability's, with no other
## effect.
## Heals, shields and heal-over-time from a caster with heal_bonus are that much larger.
const EFFECT_KEYS: Dictionary = {
	"damage": ["area", "multiplier", "combo_multiplier", "required", "count", "delay_seconds", "push"],
	"heal": ["area", "multiplier", "max_hp_fraction"],
	"shield": ["multiplier", "seconds"],
	"status": ["target", "status", "magnitude", "seconds", "radius", "combo"],
	"revive": ["fraction", "stop"],
	"interrupt": ["stun_seconds", "area"],
	"move": ["to", "distance", "lane_push"],
	"taunt": ["seconds"],
	"zone": ["side", "seconds", "pulse"],
	"wall": ["seconds", "length", "thickness"],
}
const ZONE_SIDES: Array[String] = ["opponents", "allies"]
const PULSE_KEYS: Dictionary = {"damage": ["multiplier"], "heal": ["multiplier"], "status": ["status", "magnitude", "seconds"]}
const DAMAGE_AREAS: Array[String] = ["target", "circle", "line", "around_caster", "near_target"]
const HEAL_AREAS: Array[String] = ["target", "self", "allies_near_caster"]
const STATUS_TARGETS: Array[String] = ["self", "target", "allies_near_caster"]
## Passive statuses, always on for a passive's owner:
## ally_near_damage_reduction: damage taken x (1 - magnitude) within radius of a living ally.
## rear_basic_damage: basic hits from behind x (1 + magnitude). basic_range: basic range
## x (1 + magnitude). cooldown_reduction: ability cooldowns x (1 - magnitude). heal_bonus: the
## caster's own heals and shields x (1 + magnitude).
const PASSIVE_STATUSES: Array[String] = ["ally_near_damage_reduction", "rear_basic_damage", "basic_range", "cooldown_reduction", "heal_bonus"]
## Timed statuses (BattleActor.statuses): damage_reduction (the strongest applies), bleed, burn and
## heal_over_time (tick every skill_status_tick_seconds), root (no moving), silence (no skills),
## dodge (a telegraph misses), and stat changes to atk, defense, speed, crit_rate, crit_damage
## (x (1 + magnitude)). Stun stays effect_state.stun_remaining (the interrupt primitive); shield
## and taunt have their own primitives.
const TIMED_STATUSES: Array[String] = ["damage_reduction", "bleed", "burn", "heal_over_time", "root", "silence", "dodge", "atk", "defense", "speed", "crit_rate", "crit_damage"]
const STATUS_KINDS: Array[String] = ["damage_reduction", "bleed", "burn", "heal_over_time", "root", "silence", "dodge", "atk", "defense", "speed", "crit_rate", "crit_damage", "shield", "taunt"]
const STAT_STATUSES: Array[String] = ["atk", "defense", "speed", "crit_rate", "crit_damage"]
const MOVE_TO: Array[String] = ["behind_target", "away", "charge"]
const INTERRUPT_AREAS: Array[String] = ["target", "around_caster"]

@export var skill_id: StringName = &""
@export var display_name: String = ""
@export_enum("passive", "weaponskill", "ability") var kind: String = "ability"
@export var archetype: String = ""
@export var unlock_level: int = 1
## A general skill's tier (1-3); 0 for a class skill. General skills never open by level.
@export var tier: int = 0
@export var book_only: bool = false
@export var counter_tag: String = ""
## The skill this one follows in a combo, or empty.
@export var combo_after: StringName = &""
@export var cooldown_seconds: float = 0.0
@export var range_units: float = 0.0
## The closest its target may be (Charge, ig-zht); 0 = none.
@export var min_range_units: float = 0.0
## The skill's area: circle radius, line width or aura radius.
@export var radius_units: float = 0.0
## Cast without a target, it is cast on the caster at the caster's feet.
@export var self_centered: bool = false
@export var ai_rule: String = "always"
@export var ai_count: int = 0
@export var ai_radius: float = 0.0
## melee_near_back_row only: the closest the enemy may be to the ally, and how far from the ally the cast
## point sits.
@export var ai_min_radius: float = 0.0
@export var ai_offset: float = 0.0
@export var ai_or_elite: bool = false
## The AI casts it on a downed ally before anything else.
@export var ai_revive_first: bool = false
@export var ai_fraction: float = 0.0
@export var ai_status: String = ""
@export var ai_archetype: String = ""
@export var ai_no_ready_heal: bool = false
@export var effects: Array[Dictionary] = []


## Empty when the skill is well-formed, else the first problem.
func validate() -> String:
	if skill_id == &"" or display_name.is_empty():
		return "Skill needs a skill_id and a display_name."
	if not kind in KINDS or not archetype in ARCHETYPES or not counter_tag in COUNTER_TAGS or not ai_rule in AI_RULES:
		return "Skill %s kind, archetype, counter_tag or ai_rule is unknown." % skill_id
	if unlock_level < 1 or cooldown_seconds < 0.0 or range_units < 0.0 or radius_units < 0.0 or ai_count < 0 or ai_radius < 0.0 or ai_fraction < 0.0 or ai_min_radius < 0.0 or ai_offset < 0.0:
		return "Skill %s has a negative number or an unlock level below 1." % skill_id
	if min_range_units < 0.0 or min_range_units > range_units:
		return "Skill %s: min_range_units runs from 0 to range_units." % skill_id
	if (archetype == "general") != (tier >= 1 and tier <= 3):
		return "Skill %s: a general skill has a tier of 1-3, and only a general skill has one." % skill_id
	if not ai_status.is_empty() and not ai_status in STATUS_KINDS:
		return "Skill %s ai_status is unknown." % skill_id
	if not ai_archetype.is_empty() and not ai_archetype in ARCHETYPES:
		return "Skill %s ai_archetype is unknown." % skill_id
	if (kind == "weaponskill" and band() != "attack") or (kind != "weaponskill" and ai_rule == "default") or (kind == "passive" and ai_rule == "combo"):
		return "Skill %s: a weaponskill needs an attack rule, default is for weaponskills, and combo for weaponskills and abilities." % skill_id
	if (ai_rule == "combo") != (combo_after != &""):
		return "Skill %s: a combo rule needs combo_after, and combo_after needs the combo rule." % skill_id
	if effects.is_empty():
		return "Skill %s has no effects." % skill_id
	if ai_rule == "melee_near_back_row" and not (ai_min_radius <= ai_radius and ai_offset > 0.0 and ai_offset < ai_min_radius):
		return "Skill %s: melee_near_back_row needs ai_min_radius <= ai_radius and an ai_offset between 0 and ai_min_radius." % skill_id
	var walls: int = effects.filter(func(effect: Dictionary) -> bool: return str(effect.get("type", "")) == "wall").size()
	if walls > 0 and (walls != effects.size() or kind != "ability"):
		return "Skill %s: a wall is an ability's only effect." % skill_id
	for effect: Dictionary in effects:
		var type: String = str(effect.get("type", ""))
		if not EFFECT_KEYS.has(type):
			return "Skill %s has an unknown primitive '%s'." % [skill_id, type]
		for key: Variant in effect:
			if key != "type" and not key in EFFECT_KEYS[type]:
				return "Skill %s %s effect has an unknown field '%s'." % [skill_id, type, key]
		var problem: String = _effect_problem(type, effect)
		if not problem.is_empty():
			return "Skill %s %s effect: %s" % [skill_id, type, problem]
	return ""


func _effect_problem(type: String, effect: Dictionary) -> String:
	match type:
		"damage":
			if not str(effect.get("area", "")) in DAMAGE_AREAS or float(effect.get("multiplier", 0.0)) <= 0.0:
				return "needs a known area and a positive multiplier."
			if effect.has("delay_seconds") and (str(effect["area"]) != "circle" or float(effect["delay_seconds"]) <= 0.0):
				return "a delay needs a circle and a positive delay."
			if str(effect["area"]) == "near_target" and int(effect.get("count", 0)) <= 0:
				return "near_target needs a positive count."
			if effect.has("push") and (not str(effect["area"]) in ["line", "circle"] or not (effect["push"] is float or effect["push"] is int) or not (float(effect["push"]) > 0.0 and is_finite(float(effect["push"])))):
				return "a push needs a line or circle and a positive, finite distance."
		"heal":
			if not str(effect.get("area", "target")) in HEAL_AREAS or (float(effect.get("multiplier", 0.0)) <= 0.0) == (float(effect.get("max_hp_fraction", 0.0)) <= 0.0):
				return "needs a known area and exactly one of multiplier or max_hp_fraction."
		"shield":
			if float(effect.get("multiplier", 0.0)) <= 0.0 or float(effect.get("seconds", 0.0)) <= 0.0:
				return "needs a positive multiplier and seconds."
		"status":
			var status: String = str(effect.get("status", ""))
			if not str(effect.get("target", "")) in STATUS_TARGETS:
				return "needs a known target."
			if kind == "passive" and (str(effect["target"]) != "self" or not status in PASSIVE_STATUSES):
				return "a passive's status is a passive status on self."
			if kind != "passive" and (not status in TIMED_STATUSES or float(effect.get("seconds", 0.0)) <= 0.0):
				return "needs a timed status and positive seconds."
		"move":
			if not str(effect.get("to", "")) in MOVE_TO:
				return "needs a known destination."
			if str(effect["to"]) == "charge" and not (float(effect.get("distance", 0.0)) > 0.0 and float(effect.get("lane_push", 0.0)) >= 0.0 and is_finite(float(effect.get("lane_push", 0.0)))):
				return "a charge needs a positive distance and a non-negative, finite lane_push."
			if effect.has("lane_push") and str(effect["to"]) != "charge":
				return "only a charge has a lane_push."
		"interrupt":
			if not str(effect.get("area", "target")) in INTERRUPT_AREAS:
				return "needs a known area."
		"taunt":
			if float(effect.get("seconds", 0.0)) <= 0.0:
				return "needs positive seconds."
		"wall":
			for key: String in ["seconds", "length", "thickness"]:
				if not _positive(effect.get(key)):
					return "needs positive, finite seconds, length and thickness."
		"zone":
			if kind != "ability" or not str(effect.get("side", "")) in ZONE_SIDES or not _positive(effect.get("seconds")) or not (radius_units > 0.0):
				return "an ability's, with a known side, positive seconds and a radius."
			if not effect.get("pulse") is Array or (effect["pulse"] as Array).is_empty():
				return "needs a pulse."
			for entry: Variant in effect["pulse"] as Array:
				var problem: String = _pulse_problem(entry, str(effect["side"]))
				if not problem.is_empty():
					return problem
	return ""


## A zone's pulse effect: damage only on opponents, a heal only on allies.
func _pulse_problem(entry: Variant, side: String) -> String:
	if not entry is Dictionary or not PULSE_KEYS.has(str((entry as Dictionary).get("type", ""))):
		return "a pulse is damage, heal or status."
	var pulse: Dictionary = entry as Dictionary
	var type: String = str(pulse["type"])
	for key: Variant in pulse:
		if key != "type" and not key in PULSE_KEYS[type]:
			return "its %s pulse has an unknown field '%s'." % [type, key]
	if type != "status":
		if not _positive(pulse.get("multiplier")) or (type == "damage") != (side == "opponents"):
			return "a pulse's %s needs a positive multiplier, damage on opponents and a heal on allies." % type
		return ""
	var status: String = str(pulse.get("status", ""))
	var magnitude: Variant = pulse.get("magnitude")
	if not status in TIMED_STATUSES or status in ["bleed", "burn", "heal_over_time"] or not _positive(pulse.get("seconds")):
		return "a pulse status is a timed status that doesn't tick, with positive seconds."
	if not (magnitude is float or magnitude is int) or not is_finite(float(magnitude)) or not (float(magnitude) > -1.0 if status in STAT_STATUSES else float(magnitude) >= 0.0):
		return "a pulse status needs a finite magnitude, non-negative but for a stat's (above -1)."
	return ""


static func _positive(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) > 0.0


## An ability has a cooldown and the ability lock; passives and weaponskills have neither.
func is_ability() -> bool:
	return kind == "ability"


## A skill a book can teach (ig-gy0.7): any general skill, or a class's book-only one.
func is_bookable() -> bool:
	return archetype == "general" or book_only


## The picker band its AI rule puts it in ("" for a counter-only skill).
func band() -> String:
	return str(AI_BANDS[ai_rule])
