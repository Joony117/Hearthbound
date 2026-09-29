class_name BattleActor
extends RefCounted

const LIFE_ALIVE: String = "alive"
const LIFE_DOWNED: String = "downed"
const LIFE_EXTRACTED: String = "extracted"
const LIFE_DEAD: String = "dead"
const VALID_LIFE: Array[String] = [LIFE_ALIVE, LIFE_DOWNED, LIFE_EXTRACTED, LIFE_DEAD]
const VALID_ARCHETYPES: Array[String] = ["knight", "ranger", "mage", "rogue", "cleric"]
const VALID_FACTIONS: Array[String] = ["ally", "enemy"]
const VALID_ORDERS: Array[String] = ["", "move", "attack", "attack_move", "hold", "guard", "carry", "retreat"]
const SKILL_MODES: Array[String] = ["auto", "manual", "off"]
# validate_dict's key lists (ig-7sn.10: constants, so a save builds none of them per actor).
const _STRING_KEYS: Array[String] = ["id", "hero_id", "archetype", "faction", "squad_id", "life", "order_kind", "order_target_id", "carried_by_id", "carrying_id", "guard_target_id"]
const _VECTOR_KEYS: Array[String] = ["position", "facing", "order_point"]
const _NUMBER_KEYS: Array[String] = ["hp", "max_hp", "atk", "defense", "speed", "crit_rate", "crit_damage", "attack_range", "move_speed", "attack_cooldown", "item_cooldown"]
const _NONNEGATIVE_KEYS: Array[String] = ["atk", "defense", "speed", "attack_range", "move_speed", "attack_cooldown", "item_cooldown"]
const _EFFECT_NONNEGATIVE_KEYS: Array[String] = ["stun_remaining", "attack_windup_remaining", "attack_windup_total", "telegraph_radius", "telegraph_remaining", "telegraph_total"]
const _GUARD_KEYS: Array[String] = ["guard_remaining", "guard_reduction"]
const _EFFECT_OPTIONAL_STRING_KEYS: Array[String] = ["telegraph_skill", "last_skill_id", "telegraph_claimed_by"]
const _EFFECT_TICK_KEYS: Array[String] = ["last_hit_tick", "last_skill_tick"]
const _EFFECT_OPTIONAL_TICK_KEYS: Array[String] = ["last_counter_tick", "last_crit_tick", "last_push_tick"]
const _EFFECT_STRING_KEYS: Array[String] = ["attack_target_id", "telegraph_kind"]
const _TELEGRAPH_KINDS: Array[String] = ["", "circle", "line"]
const _EFFECT_VECTOR_KEYS: Array[String] = ["telegraph_origin", "telegraph_point", "home_position"]
const _EFFECT_HOP_KEYS: Array[String] = ["kite_point", "evade_point"]
## A running chain (ig-gy0.5): all four or none.
const CHAIN_KEYS: Array[String] = ["chain_trigger", "chain_step", "chain_deadline_tick", "chain_target"]

var id: String = ""
var hero_id: String = ""
var archetype: String = ""
var faction: String = ""
var spawn_index: int = 0
var squad_id: String = ""
var position: Vector2 = Vector2.ZERO
var facing: Vector2 = Vector2.RIGHT
var hp: float = 0.0
var max_hp: float = 0.0
var atk: float = 0.0
var defense: float = 0.0
var speed: float = 0.0
var crit_rate: float = 0.0
var crit_damage: float = 1.0
var life: String = LIFE_ALIVE
var attack_range: float = 1.6
var move_speed: float = 1.5
var attack_cooldown: float = 0.0
var item_cooldown: float = 0.0
var order_kind: String = ""
var order_target_id: String = ""
var order_point: Vector2 = Vector2.ZERO
var carried_by_id: String = ""
var carrying_id: String = ""
var guard_target_id: String = ""
## [{id, mode}] in bar order; mode is "auto", "manual" (fired only by command, or as a chain step) or
## "off" (never fired). A passive is always "auto".
var skills: Array[Dictionary] = []
## {skill_id: seconds} for every ability in skills.
var skill_cooldowns: Dictionary = {}
## The player's chains (ig-gy0.5), [{trigger, then: [ids]}] as the team snapshot carried them: the ids
## may name skills the actor lacks (skipped when reached). An enemy has none. A chain that is running
## is four effect_state keys (chain_trigger, chain_step, chain_deadline_tick, chain_target).
var chains: Array[Dictionary] = []
## Seconds until the next ability may fire (skill_ability_lock_seconds after any ability).
var ability_lock: float = 0.0
## The last weaponskill and the tick it landed, for combos.
var combo_skill: String = ""
var combo_tick: int = 0
## Timed statuses: [{id, kind, source, remaining, magnitude}]. id is the skill that applied it, so the
## same status from any source refreshes; kind is an AbilityDefinition.STATUS_KINDS entry; source is
## the caster's actor id; magnitude is a fraction, a per-second amount (bleed, burn,
## heal_over_time) or what a shield has left.
var statuses: Array[Dictionary] = []
var effect_state: Dictionary = {}


func to_dict() -> Dictionary:
	var data: Dictionary = {
		"id": id,
		"hero_id": hero_id,
		"archetype": archetype,
		"faction": faction,
		"spawn_index": spawn_index,
		"squad_id": squad_id,
		"position": [position.x, position.y],
		"facing": [facing.x, facing.y],
		"hp": hp,
		"max_hp": max_hp,
		"atk": atk,
		"defense": defense,
		"speed": speed,
		"crit_rate": crit_rate,
		"crit_damage": crit_damage,
		"life": life,
		"attack_range": attack_range,
		"move_speed": move_speed,
		"attack_cooldown": attack_cooldown,
		"item_cooldown": item_cooldown,
		"order_kind": order_kind,
		"order_target_id": order_target_id,
		"order_point": [order_point.x, order_point.y],
		"carried_by_id": carried_by_id,
		"carrying_id": carrying_id,
		"guard_target_id": guard_target_id,
		"skills": skills.duplicate(true),
		"skill_cooldowns": skill_cooldowns.duplicate(),
		"ability_lock": ability_lock,
		"combo_skill": combo_skill,
		"combo_tick": combo_tick,
		"statuses": statuses.duplicate(true),
		"effect_state": effect_state.duplicate(true),
	}
	# Only when there are some, so a battle with no chains saves the bytes it always did.
	if not chains.is_empty():
		data["chains"] = chains.duplicate(true)
	return data


static func from_dict(data: Dictionary) -> BattleActor:
	var actor := BattleActor.new()
	actor.id = str(data.get("id", ""))
	actor.hero_id = str(data.get("hero_id", ""))
	actor.archetype = str(data.get("archetype", ""))
	actor.faction = str(data.get("faction", ""))
	actor.spawn_index = _integer(data.get("spawn_index"), 0)
	actor.squad_id = str(data.get("squad_id", ""))
	actor.position = _vector(data.get("position"))
	actor.facing = _vector(data.get("facing"), Vector2.RIGHT)
	actor.hp = _number(data.get("hp"), 0.0)
	actor.max_hp = _number(data.get("max_hp"), 0.0)
	actor.atk = _number(data.get("atk"), 0.0)
	actor.defense = _number(data.get("defense"), 0.0)
	actor.speed = _number(data.get("speed"), 0.0)
	actor.crit_rate = _number(data.get("crit_rate"), 0.0)
	actor.crit_damage = _number(data.get("crit_damage"), 1.0)
	actor.life = str(data.get("life", LIFE_ALIVE))
	actor.attack_range = _number(data.get("attack_range"), 1.6)
	actor.move_speed = _number(data.get("move_speed"), 1.5)
	actor.attack_cooldown = _number(data.get("attack_cooldown"), 0.0)
	actor.item_cooldown = _number(data.get("item_cooldown"), 0.0)
	actor.order_kind = str(data.get("order_kind", ""))
	actor.order_target_id = str(data.get("order_target_id", ""))
	actor.order_point = _vector(data.get("order_point"))
	actor.carried_by_id = str(data.get("carried_by_id", ""))
	actor.carrying_id = str(data.get("carrying_id", ""))
	actor.guard_target_id = str(data.get("guard_target_id", ""))
	if data.get("skills") is Array:
		for entry: Variant in data.get("skills") as Array:
			if entry is Dictionary:
				actor.skills.append({"id": str((entry as Dictionary).get("id", "")), "mode": str((entry as Dictionary).get("mode", "auto"))})
		if data.get("skill_cooldowns") is Dictionary:
			for skill_id: Variant in data.get("skill_cooldowns") as Dictionary:
				actor.skill_cooldowns[str(skill_id)] = _number((data.get("skill_cooldowns") as Dictionary)[skill_id], 0.0)
	else:
		# A checkpoint from before skills were data (ig-gy0.1): the archetype's kit, its signature
		# carrying the old ability_cooldown and the old ability_auto mode.
		actor.set_default_kit(bool(data.get("ability_auto", true)), _number(data.get("ability_cooldown"), 0.0))
	if data.get("chains") is Array:
		for entry: Variant in data.get("chains") as Array:
			if entry is Dictionary and (entry as Dictionary).get("then") is Array:
				actor.chains.append({"trigger": str((entry as Dictionary).get("trigger", "")), "then": ((entry as Dictionary)["then"] as Array).map(func(step: Variant) -> String: return str(step))})
	actor.ability_lock = _number(data.get("ability_lock"), 0.0)
	actor.combo_skill = str(data.get("combo_skill", ""))
	actor.combo_tick = _integer(data.get("combo_tick"), 0)
	if data.get("statuses") is Array:
		for entry: Variant in data.get("statuses") as Array:
			if entry is Dictionary:
				var status: Dictionary = entry as Dictionary
				actor.statuses.append({"id": str(status.get("id", "")), "kind": str(status.get("kind", "")), "source": str(status.get("source", "")), "remaining": _number(status.get("remaining"), 0.0), "magnitude": _number(status.get("magnitude"), 0.0)})
	var raw_effects: Variant = data.get("effect_state")
	actor.effect_state = (raw_effects as Dictionary).duplicate(true) if raw_effects is Dictionary else {}
	# A checkpoint from before statuses (ig-gy0.2): the old guard becomes Stand Fast's damage-reduction status.
	if actor.effect_state.has("guard_remaining") or actor.effect_state.has("guard_reduction"):
		var guard_remaining: float = _number(actor.effect_state.get("guard_remaining"), 0.0)
		if guard_remaining > 0.0 and not actor.statuses.any(func(status: Dictionary) -> bool: return status["id"] == "knight_rally" and status["kind"] == "damage_reduction"):
			actor.statuses.append({"id": "knight_rally", "kind": "damage_reduction", "source": "", "remaining": guard_remaining, "magnitude": _number(actor.effect_state.get("guard_reduction"), 0.0)})
		actor.effect_state.erase("guard_remaining")
		actor.effect_state.erase("guard_reduction")
	return actor


static func validate_dict(data: Dictionary) -> String:
	# ig-7sn.10: every save checks every actor of every battle out (hundreds at five battles), so each field
	# is read once into a typed local and the key lists are constants. Same checks, order and messages.
	for key: String in _STRING_KEYS:
		if not data.get(key) is String:
			return "Battle actor %s must be a String." % key
	if (data["id"] as String).is_empty():
		return "Battle actor id must be non-empty."
	var actor_archetype: String = data["archetype"]
	var actor_faction: String = data["faction"]
	if not actor_archetype in VALID_ARCHETYPES or not actor_faction in VALID_FACTIONS:
		return "Battle actor archetype or faction is invalid."
	if not (data["order_kind"] as String) in VALID_ORDERS:
		return "Battle actor order_kind is invalid."
	var ally: bool = actor_faction == "ally"
	if ally == (data["hero_id"] as String).is_empty():
		return "Allied battle actors need hero IDs and enemies must not have them."
	if not _valid_nonnegative_integer(data.get("spawn_index")):
		return "Battle actor spawn_index must be a non-negative integer."
	for key: String in _VECTOR_KEYS:
		if not _valid_vector(data.get(key)):
			return "Battle actor %s must contain two finite numbers." % key
	for key: String in _NUMBER_KEYS:
		if not _valid_number(data.get(key)):
			return "Battle actor %s must be finite." % key
	var actor_hp: float = float(data["hp"])
	var actor_max_hp: float = float(data["max_hp"])
	if actor_max_hp <= 0.0 or actor_hp < 0.0 or actor_hp > actor_max_hp:
		return "Battle actor HP is outside its valid range."
	for key: String in _NONNEGATIVE_KEYS:
		if float(data[key]) < 0.0:
			return "Battle actor %s must be non-negative." % key
	var actor_crit_rate: float = float(data["crit_rate"])
	if actor_crit_rate < 0.0 or actor_crit_rate > 1.0 or float(data["crit_damage"]) < 1.0:
		return "Battle actor critical values are invalid."
	var actor_life: String = data["life"]
	if not actor_life in VALID_LIFE:
		return "Battle actor life is invalid."
	if ally and actor_life == LIFE_DEAD:
		return "Allied battle actors cannot be dead inside a battle snapshot."
	if not ally and actor_life == LIFE_DOWNED:
		return "Enemy battle actors cannot be downed."
	if actor_life == LIFE_ALIVE and actor_hp <= 0.0:
		return "Living battle actors need positive HP."
	if (actor_life == LIFE_DOWNED or actor_life == LIFE_DEAD) and actor_hp != 0.0:
		return "Downed and dead battle actors must have zero HP."
	var skills_error: String = _validate_skills(data, actor_archetype, actor_faction)
	if not skills_error.is_empty():
		return skills_error
	if not data.get("effect_state") is Dictionary:
		return "Battle actor effect_state must be a Dictionary."
	var effects: Dictionary = data["effect_state"]
	if not effects.get("elite") is bool:
		return "Battle actor elite effect flag must be a bool."
	# Variant: each effect is read once and checked for its type before it is used as a number.
	var value: Variant
	for key: String in _EFFECT_NONNEGATIVE_KEYS:
		value = effects.get(key)
		if not _valid_number(value) or float(value) < 0.0:
			return "Battle actor effect %s must be finite and non-negative." % key
	# Optional: a checkpoint from before statuses (ig-gy0.2) carries the old guard here.
	var guard_reduction: float = 0.0
	for key: String in _GUARD_KEYS:
		if effects.has(key):
			value = effects[key]
			if not _valid_number(value) or float(value) < 0.0:
				return "Battle actor effect %s must be finite and non-negative." % key
			if key == "guard_reduction":
				guard_reduction = float(value)
	if guard_reduction > 1.0:
		return "Battle actor guard_reduction cannot exceed one."
	for key: String in _EFFECT_OPTIONAL_STRING_KEYS:
		if effects.has(key) and not effects[key] is String:
			return "Battle actor effect %s must be a String." % key
	var status_error: String = _validate_skill_state(data)
	if not status_error.is_empty():
		return status_error
	for key: String in _EFFECT_TICK_KEYS:
		if not _valid_nonnegative_integer(effects.get(key)):
			return "Battle actor effect %s must be a non-negative integer." % key
	# Optional: saves written before counters (ig-gy0.4), crits, or knockback's view cues (ig-36y) lack them.
	for key: String in _EFFECT_OPTIONAL_TICK_KEYS:
		if effects.has(key) and not _valid_nonnegative_integer(effects[key]):
			return "Battle actor effect %s must be a non-negative integer." % key
	if effects.has("hit_from") and not _valid_vector(effects["hit_from"]):
		return "Battle actor effect hit_from must contain two finite numbers."
	for key: String in _EFFECT_STRING_KEYS:
		if not effects.get(key) is String:
			return "Battle actor effect %s must be a String." % key
	if not (effects["telegraph_kind"] as String) in _TELEGRAPH_KINDS:
		return "Battle actor telegraph_kind is invalid."
	for key: String in _EFFECT_VECTOR_KEYS:
		if not _valid_vector(effects.get(key)):
			return "Battle actor effect %s must contain two finite numbers." % key
	if effects.has("direct_order") and not effects["direct_order"] is bool:
		return "Battle actor direct_order effect must be a bool."
	if effects.has("carry_progress"):
		value = effects["carry_progress"]
		if not _valid_number(value) or float(value) < 0.0:
			return "Battle actor carry_progress must be finite and non-negative."
	# Optional: a hop in flight and the next hop's tick (ig-uu7.3), and a telegraph evade in flight.
	for key: String in _EFFECT_HOP_KEYS:
		if effects.has(key) and not _valid_vector(effects[key]):
			return "Battle actor effect %s must contain two finite numbers." % key
	var hop_tick: bool = effects.has("kite_ready_tick")
	if hop_tick and not _valid_nonnegative_integer(effects["kite_ready_tick"]):
		return "Battle actor effect kite_ready_tick must be a non-negative integer."
	# A hop in flight derives its start from kite_ready_tick, so one without the other is refused.
	if not hop_tick and effects.has("kite_point"):
		return "Battle actor effect kite_point needs kite_ready_tick."
	# Optional: a Knight's cover order (ig-uu7.4). A battle from before it has no key and reads as [].
	if effects.has("cover_order"):
		value = effects["cover_order"]
		if not value is Array:
			return "Battle actor effect cover_order must be an Array of Strings."
		for entry: Variant in value as Array:
			if not entry is String:
				return "Battle actor effect cover_order must be an Array of Strings."
	return _validate_chains(data, effects, actor_archetype, ally)


## The skill archetypes an actor of archetype and faction may carry: its class, then the general
## pool for a hero or the enemy-only skills for an enemy (enemies never use the general pool).
static func kit_archetypes(for_archetype: String, for_faction: String) -> Array[String]:
	return [for_archetype, "enemy_" + for_archetype] if for_faction == "enemy" else [for_archetype, "general"]


## The archetype's kit (BattleSimulation.default_kit), every ability ready. auto sets the
## abilities' mode; cooldown is what the signature has left.
func set_default_kit(auto: bool = true, cooldown: float = 0.0) -> void:
	skills.clear()
	skill_cooldowns.clear()
	for skill: AbilityDefinition in BattleSimulation.default_kit(archetype):
		add_skill(skill, "manual" if skill.is_ability() and not auto else "auto", cooldown)


## Appends skill to the list (an ability gets its cooldown). A passive is always "auto"; a
## weaponskill or an ability takes the bar's mode.
func add_skill(skill: AbilityDefinition, mode: String = "auto", cooldown: float = 0.0) -> void:
	skills.append({"id": str(skill.skill_id), "mode": "auto" if skill.kind == "passive" or not mode in SKILL_MODES else mode})
	if skill.is_ability():
		skill_cooldowns[str(skill.skill_id)] = cooldown


## Every ability on the list to Auto or Manual; passives, weaponskills and Off abilities stay as
## they are (Off is never fired).
func set_abilities_auto(auto: bool) -> void:
	for entry: Dictionary in skills:
		if BattleSimulation.ABILITIES[entry["id"]].is_ability() and entry["mode"] != "off":
			entry["mode"] = "auto" if auto else "manual"


## Both shapes load: skills + skill_cooldowns, or the old ability_cooldown + ability_auto. archetype and
## faction are the actor's, already checked.
static func _validate_skills(data: Dictionary, actor_archetype: String, actor_faction: String) -> String:
	if not data.has("skills"):
		if not _valid_number(data.get("ability_cooldown")) or float(data.get("ability_cooldown")) < 0.0:
			return "Battle actor ability_cooldown must be finite and non-negative."
		if not data.get("ability_auto") is bool:
			return "Battle actor ability_auto must be a bool."
		return ""
	if not data.get("skills") is Array or not data.get("skill_cooldowns") is Dictionary:
		return "Battle actor skills must be an Array and skill_cooldowns a Dictionary."
	# Untyped: kit_archetypes builds its pair with a ternary, which Godot returns as a plain Array.
	var kit: Array = kit_archetypes(actor_archetype, actor_faction)
	var seen: Dictionary = {}
	var abilities: Dictionary = {}
	for raw_entry: Variant in data["skills"] as Array:
		if not raw_entry is Dictionary:
			return "Every battle actor skill must be {id, mode} Strings."
		var entry: Dictionary = raw_entry as Dictionary
		if entry.size() != 2 or not entry.get("id") is String or not entry.get("mode") is String:
			return "Every battle actor skill must be {id, mode} Strings."
		var skill_key: String = entry["id"]
		var mode: String = entry["mode"]
		var skill: AbilityDefinition = BattleSimulation.ABILITIES.get(skill_key) as AbilityDefinition
		if skill == null or not skill.archetype in kit:
			return "Battle actor skill %s is unknown or from another class." % skill_key
		if not mode in SKILL_MODES or (skill.kind == "passive" and mode != "auto"):
			return "Battle actor skill %s mode is invalid." % skill_key
		if seen.has(skill.skill_id):
			return "Battle actor skill %s is listed twice." % str(skill.skill_id)
		seen[skill.skill_id] = true
		if skill.is_ability():
			abilities[skill.skill_id] = true
	var cooldowns: Dictionary = data["skill_cooldowns"]
	if cooldowns.size() != abilities.size():
		return "Battle actor skill_cooldowns must hold exactly its abilities."
	for skill_id: Variant in cooldowns:
		if not skill_id is String or not abilities.has(StringName(skill_id as String)):
			return "Battle actor skill_cooldowns must hold exactly its abilities."
		if not _valid_number(cooldowns[skill_id]) or float(cooldowns[skill_id]) < 0.0:
			return "Battle actor skill cooldowns must be finite and non-negative."
	return ""


## Optional (a checkpoint from before ig-gy0.5 has none): the actor's chains, and the four keys of a
## running one. Absent costs four key lookups. The steps' ids are checked against the class's kit, not
## the actor's skills, and a chain's length not at all, so lowering skill_chain_max_steps never locks a
## save out. A deadline is ahead of the tick by design, so it is no tick-bound check's.
static func _validate_chains(data: Dictionary, effects: Dictionary, actor_archetype: String, ally: bool) -> String:
	var chains_here: Array = []
	if data.has("chains"):
		if not ally:
			return "Enemy battle actors cannot have chains."
		if not data["chains"] is Array:
			return "Battle actor chains must be an Array of {trigger, then}."
		chains_here = data["chains"]
		var kit: Array = kit_archetypes(actor_archetype, "ally")
		var triggers: Dictionary = {}
		for raw_chain: Variant in chains_here:
			var problem: String = _chain_problem(raw_chain, kit, triggers)
			if not problem.is_empty():
				return problem
			triggers[(raw_chain as Dictionary)["trigger"]] = true
	var present: int = 0
	for key: String in CHAIN_KEYS:
		if effects.has(key):
			present += 1
	if present == 0:
		return ""
	if present != CHAIN_KEYS.size():
		return "Battle actor chain state needs chain_trigger, chain_step, chain_deadline_tick and chain_target together."
	if not effects["chain_trigger"] is String or not effects["chain_target"] is String:
		return "Battle actor effects chain_trigger and chain_target must be Strings."
	var running: Dictionary = {}
	for chain: Dictionary in chains_here:
		if chain["trigger"] == effects["chain_trigger"]:
			running = chain
	if running.is_empty():
		return "Battle actor effect chain_trigger must name one of its chains."
	if not _valid_nonnegative_integer(effects["chain_step"]) or int(effects["chain_step"]) >= (running["then"] as Array).size():
		return "Battle actor effect chain_step must be a non-negative integer inside its chain."
	if not _valid_nonnegative_integer(effects["chain_deadline_tick"]):
		return "Battle actor effect chain_deadline_tick must be a non-negative integer."
	return ""


## Why raw_chain cannot be one of an ally's chains, or "": {trigger, then} with a String and a non-empty
## Array of Strings, each a non-passive skill of the class kit (kit_archetypes), and a trigger not in triggers.
static func _chain_problem(raw_chain: Variant, kit: Array, triggers: Dictionary) -> String:
	const SHAPE: String = "Every battle actor chain must be {trigger, then}: a String and a non-empty Array of Strings."
	if not raw_chain is Dictionary:
		return SHAPE
	var chain: Dictionary = raw_chain
	if chain.size() != 2 or not chain.get("trigger") is String or not chain.get("then") is Array or (chain["then"] as Array).is_empty():
		return SHAPE
	for raw_id: Variant in [chain["trigger"]] + (chain["then"] as Array):
		if not raw_id is String:
			return SHAPE
		var skill: AbilityDefinition = BattleSimulation.ABILITIES.get(raw_id) as AbilityDefinition
		if skill == null or skill.kind == "passive" or not skill.archetype in kit:
			return "Battle actor chain skill %s is unknown, a passive or from another class." % raw_id
	if triggers.has(chain["trigger"]):
		return "Battle actor chain trigger %s is listed twice." % chain["trigger"]
	return ""


## The running chain ends: its four keys go.
func end_chain() -> void:
	for key: String in CHAIN_KEYS:
		effect_state.erase(key)


## A team snapshot's chains, as far as a checkpoint could hold them: the malformed, passive, other-class
## and repeated-trigger ones are left out, as a kit's bad ids are. Heroes only.
func take_chains(raw: Variant) -> void:
	if not raw is Array or faction != "ally":
		return
	var kit: Array = kit_archetypes(archetype, faction)
	var triggers: Dictionary = {}
	for entry: Variant in raw as Array:
		if _chain_problem(entry, kit, triggers).is_empty():
			var chain: Dictionary = entry
			triggers[chain["trigger"]] = true
			chains.append({"trigger": chain["trigger"], "then": (chain["then"] as Array).duplicate()})


## Optional keys (a checkpoint from before ig-gy0.2 has none): the ability lock, combo state and
## the status list.
static func _validate_skill_state(data: Dictionary) -> String:
	if data.has("ability_lock") and (not _valid_number(data.get("ability_lock")) or float(data.get("ability_lock")) < 0.0):
		return "Battle actor ability_lock must be finite and non-negative."
	if data.has("combo_skill") and not data.get("combo_skill") is String:
		return "Battle actor combo_skill must be a String."
	if data.has("combo_tick") and not _valid_nonnegative_integer(data.get("combo_tick")):
		return "Battle actor combo_tick must be a non-negative integer."
	if not data.has("statuses"):
		return ""
	if not data.get("statuses") is Array:
		return "Battle actor statuses must be an Array."
	var seen: Dictionary = {}
	for entry: Variant in data.get("statuses") as Array:
		if not entry is Dictionary or (entry as Dictionary).size() != 5:
			return "Every battle actor status must be {id, kind, source, remaining, magnitude}."
		var status: Dictionary = entry as Dictionary
		for key: String in ["id", "kind", "source"]:
			if not status.get(key) is String:
				return "Battle actor status %s must be a String." % key
		if str(status["id"]).is_empty() or not str(status["kind"]) in AbilityDefinition.STATUS_KINDS:
			return "Battle actor status id is empty or its kind is unknown."
		# ig-vl1.4: a stat status may cut its stat (Rime Circle's slow), never to 0 or below.
		var cut: bool = str(status["kind"]) in AbilityDefinition.STAT_STATUSES and _valid_number(status.get("magnitude")) and float(status["magnitude"]) > -1.0
		for key: String in ["remaining", "magnitude"]:
			if not _valid_number(status.get(key)) or (float(status.get(key)) < 0.0 and not (key == "magnitude" and cut)):
				return "Battle actor status %s must be finite and non-negative (a stat status's magnitude above -1)." % key
		if str(status["kind"]) == "damage_reduction" and float(status["magnitude"]) > 1.0:
			return "Battle actor damage reduction cannot exceed one."
		var identity: String = "%s|%s" % [status["id"], status["kind"]]
		if seen.has(identity):
			return "Battle actor status %s is listed twice." % status["id"]
		seen[identity] = true
	return ""


static func _vector(value: Variant, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	if not _valid_vector(value):
		return fallback
	var entries: Array = value as Array
	return Vector2(float(entries[0]), float(entries[1]))


static func _valid_vector(value: Variant) -> bool:
	if not value is Array or (value as Array).size() != 2:
		return false
	var entries: Array = value as Array
	return _valid_number(entries[0]) and _valid_number(entries[1])


static func _valid_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _number(value: Variant, fallback: float) -> float:
	return float(value) if _valid_number(value) else fallback


static func _integer(value: Variant, fallback: int) -> int:
	return int(value) if _valid_nonnegative_integer(value) else fallback


static func _valid_nonnegative_integer(value: Variant) -> bool:
	return _valid_number(value) and float(value) >= 0.0 and float(value) == floorf(float(value))
