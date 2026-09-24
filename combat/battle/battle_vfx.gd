class_name BattleVfx
extends Node3D

## One-shot battle effects derived from snapshot diffs. View-only: reads actor dictionaries, never the simulation.

const MAX_LIVE_EFFECTS: int = 40
const SPARK_COLOR: Color = Color("fbe7a0")
const DAMAGE_COLOR: Color = Color("e8483c")
const CRIT_COLOR: Color = Color("ffd23f")
const CRIT_OUTLINE_COLOR: Color = Color("c2410c")
const CRIT_JITTER: float = 0.15
const DAMAGE_FONT_SIZE: int = 40
const CRIT_FONT_SIZE: int = 64
const HEAL_COLOR: Color = Color("7ad17a")
const ALLY_ATTACK_COLOR: Color = Color("d4e6ff")
const ENEMY_ATTACK_COLOR: Color = Color("ffb199")
const KNIGHT_SKILL_COLOR: Color = Color("d4b65b")
const RANGER_SKILL_COLOR: Color = Color("9fe3dc")
const MAGE_SKILL_COLOR: Color = Color("c2b7ff")
const ROGUE_SKILL_COLOR: Color = Color("766f75")
const ENEMY_SKILL_COLOR: Color = Color("e85b4f")
const DODGE_COLOR: Color = Color("8cc8ec")
const DUST_COLOR: Color = Color("8a8a86")

# Every tween spawn starts, so the view's slow-mo can rescale live effects mid-flight.
var _tweens: Array[Tween] = []
var _time_scale: float = 1.0


func set_time_scale(value: float) -> void:
	_time_scale = value
	_prune_tweens()
	for particles: Node in find_children("*", "CPUParticles3D", true, false):
		(particles as CPUParticles3D).speed_scale = value


## Each event carries the sim tick it happened on when the snapshot records one, so the view can
## spread a multi-tick render back out over time; events without a tick play at the render.
static func events_between(previous: Dictionary, actors: Array) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var current: Dictionary[String, Dictionary] = {}
	for raw_actor: Variant in actors:
		if raw_actor is Dictionary:
			current[str((raw_actor as Dictionary).get("id", ""))] = raw_actor as Dictionary
	var hit_ids: Array[String] = []
	for actor_id: String in current:
		if previous.get(actor_id) is Dictionary and _tick(current[actor_id], "last_hit_tick") > _tick(previous[actor_id] as Dictionary, "last_hit_tick"):
			hit_ids.append(actor_id)
	for actor_id: String in current:
		if not previous.get(actor_id) is Dictionary:
			continue
		var before: Dictionary = previous[actor_id] as Dictionary
		var after: Dictionary = current[actor_id]
		var before_effects: Dictionary = _effects(before)
		var after_effects: Dictionary = _effects(after)
		var faction: String = str(after.get("faction", "enemy"))
		var archetype: String = str(after.get("archetype", ""))
		var spot: Vector3 = _world(after.get("position"))
		var facing: Vector3 = _world(after.get("facing"), Vector2.RIGHT).normalized()
		var hp_before: float = float(before.get("hp", 0.0))
		var hp_after: float = float(after.get("hp", 0.0))
		var life_before: String = str(before.get("life", "alive"))
		var life_after: String = str(after.get("life", "alive"))
		if actor_id in hit_ids:
			events.append({"kind": "hit", "actor_id": actor_id, "faction": faction, "position": spot, "damage": roundi(maxf(hp_before - hp_after, 0.0)), "critical": _tick(after, "last_crit_tick") > _tick(before, "last_crit_tick"), "tick": _tick(after, "last_hit_tick")})
		if life_before == "alive" and life_after == "alive" and roundi(hp_after - hp_before) > 0:
			events.append({"kind": "heal", "actor_id": actor_id, "position": spot, "amount": roundi(hp_after - hp_before)})
		var attack_target: String = str(before_effects.get("attack_target_id", ""))
		if not attack_target.is_empty() and str(after_effects.get("attack_target_id", "")).is_empty() and attack_target in hit_ids and float(after.get("attack_cooldown", 0.0)) > float(before.get("attack_cooldown", 0.0)):
			events.append({
				"kind": "basic_attack",
				"actor_id": actor_id,
				"faction": faction,
				"projectile": archetype in ["ranger", "mage"],
				"position": spot,
				"facing": facing,
				"target_id": attack_target,
				"target_position": _world(current[attack_target].get("position")),
				"critical": _tick(current[attack_target], "last_crit_tick") > _tick(previous[attack_target] as Dictionary, "last_crit_tick"),
				"tick": _tick(current[attack_target], "last_hit_tick"),
			})
		var skill_visible: bool = archetype in ["knight", "rogue"] or faction == "ally"
		if skill_visible and _tick(after, "last_skill_tick") > _tick(before, "last_skill_tick") and BattleSimulation.ABILITIES.has(archetype):
			var ability: AbilityDefinition = BattleSimulation.ABILITIES[archetype]
			var skill: Dictionary = {
				"kind": "skill",
				"actor_id": actor_id,
				"archetype": archetype,
				"position": spot,
				"previous_position": _world(before.get("position")),
				"facing": facing,
				"radius": ability.radius_units,
				"range": ability.range_units,
				"center": spot + facing * 2.0,
				"tick": _tick(after, "last_skill_tick"),
			}
			if archetype in ["mage", "ranger"]:
				var total: Vector3 = Vector3.ZERO
				var count: int = 0
				for hit_id: String in hit_ids:
					var hit_position: Vector3 = _world(current[hit_id].get("position"))
					if str(current[hit_id].get("faction", "")) != faction and hit_position.distance_to(spot) <= ability.range_units:
						total += hit_position
						count += 1
				if count > 0:
					var centroid: Vector3 = total / float(count)
					skill["center"] = centroid
					# Sim facing only turns while moving, so a standing ranger aims at what it actually hit.
					if archetype == "ranger" and not centroid.is_equal_approx(spot):
						skill["facing"] = (centroid - spot).normalized()
			events.append(skill)
		var telegraph_kind: String = str(before_effects.get("telegraph_kind", ""))
		# ponytail: rogue stun is 0.3s (3 ticks of 0.1s) against the 0.25s live pulse, so a frame hitch of 4+ ticks between renders lets the stun expire unseen and the cancel fakes a blast; carry a cancel flag in the snapshot if that shows up.
		if telegraph_kind in ["circle", "line"] and str(after_effects.get("telegraph_kind", "")).is_empty() and life_after == "alive" and float(after_effects.get("stun_remaining", 0.0)) <= 0.0:
			events.append({
				"kind": "enemy_skill",
				"actor_id": actor_id,
				"shape": telegraph_kind,
				"origin": _world(before_effects.get("telegraph_origin")),
				"point": _world(before_effects.get("telegraph_point")),
				"radius": float(before_effects.get("telegraph_radius", 0.0)),
			})
		if faction == "ally" and not before_effects.get("evade_point") is Array and after_effects.get("evade_point") is Array:
			events.append({"kind": "dodge", "actor_id": actor_id, "position": _world(before.get("position"))})
		if faction == "enemy" and life_before == "alive" and life_after == "dead":
			events.append({"kind": "death", "actor_id": actor_id, "position": spot, "tick": _tick(after, "last_hit_tick")})
	return events


func spawn(event: Dictionary) -> void:
	# ponytail: hard cap drops effects under heavy load; pool nodes if dropped effects become visible.
	if get_child_count() >= MAX_LIVE_EFFECTS:
		return
	var effect := Node3D.new()
	add_child(effect)
	var lifetime: float = 0.3
	var spot: Vector3 = event.get("position", Vector3.ZERO)
	match str(event.get("kind", "")):
		"hit":
			_burst(effect, spot + Vector3(0.0, 0.9, 0.0), SPARK_COLOR, 14, 0.3)
			var damage: int = int(event.get("damage", 0))
			if damage > 0:
				if bool(event.get("critical", false)):
					_crit_label(effect, spot, "%d!" % damage)
					lifetime = 0.85
				else:
					_rising_label(effect, spot, str(damage), DAMAGE_COLOR)
					lifetime = 0.7
		"heal":
			_rising_label(effect, spot, "+%d" % int(event.get("amount", 0)), HEAL_COLOR)
			lifetime = 0.7
		"basic_attack":
			lifetime = _basic_attack(effect, event)
		"skill":
			lifetime = _skill(effect, event)
		"enemy_skill":
			lifetime = _enemy_skill(effect, event)
		"dodge":
			var ghost_mesh := CapsuleMesh.new()
			ghost_mesh.radius = 0.34
			ghost_mesh.height = 1.4
			var ghost: MeshInstance3D = _mesh(effect, ghost_mesh, Color(DODGE_COLOR, 0.5))
			ghost.position = spot + Vector3(0.0, 0.7, 0.0)
			_fade(ghost, 0.3)
			_rising_label(effect, spot, "DODGE", DODGE_COLOR)
			lifetime = 0.7
		"death":
			_burst(effect, spot + Vector3(0.0, 0.3, 0.0), DUST_COLOR, 10, 0.5)
			lifetime = 0.5
		_:
			effect.queue_free()
			return
	var reaper: Tween = _track(effect.create_tween())
	reaper.tween_interval(lifetime + 0.05)
	reaper.tween_callback(effect.queue_free)


func _basic_attack(effect: Node3D, event: Dictionary) -> float:
	var color: Color = ALLY_ATTACK_COLOR if str(event.get("faction", "")) == "ally" else ENEMY_ATTACK_COLOR
	var origin: Vector3 = (event.get("position", Vector3.ZERO) as Vector3) + Vector3(0.0, 0.9, 0.0)
	if bool(event.get("projectile", false)):
		var ball := SphereMesh.new()
		ball.radius = 0.12
		ball.height = 0.24
		var projectile: MeshInstance3D = _mesh(effect, ball, color)
		projectile.position = origin
		var target: Vector3 = (event.get("target_position", Vector3.ZERO) as Vector3) + Vector3(0.0, 0.9, 0.0)
		_track(projectile.create_tween()).tween_property(projectile, "position", target, 0.12)
		return 0.12
	var facing: Vector3 = event.get("facing", Vector3.FORWARD)
	var arc_mesh := TorusMesh.new()
	arc_mesh.inner_radius = 0.45
	arc_mesh.outer_radius = 0.55
	var arc: MeshInstance3D = _mesh(effect, arc_mesh, color)
	arc.position = origin + facing * 0.7
	arc.rotation.y = atan2(facing.x, facing.z)
	arc.scale = Vector3(0.4, 0.1, 0.2)
	var tween: Tween = _track(arc.create_tween().set_parallel())
	tween.tween_property(arc, "scale", Vector3(1.0, 0.1, 0.45), 0.18)
	tween.tween_property(arc.material_override, "albedo_color:a", 0.0, 0.18)
	return 0.18


func _skill(effect: Node3D, event: Dictionary) -> float:
	var spot: Vector3 = event.get("position", Vector3.ZERO)
	var facing: Vector3 = event.get("facing", Vector3.FORWARD)
	match str(event.get("archetype", "")):
		"knight":
			_expanding_ring(effect, spot, KNIGHT_SKILL_COLOR, 0.3, float(event.get("radius", 1.0)), 0.4)
			return 0.4
		"ranger":
			_streak(effect, spot, spot + facing * float(event.get("range", 1.0)), 0.12, RANGER_SKILL_COLOR, 0.3)
			return 0.3
		"mage":
			var center: Vector3 = event.get("center", spot)
			var radius: float = float(event.get("radius", 1.0))
			_expanding_ring(effect, center, MAGE_SKILL_COLOR, radius * 0.3, radius, 0.4)
			_burst(effect, center + Vector3(0.0, 0.4, 0.0), MAGE_SKILL_COLOR, 18, 0.4)
			return 0.4
		"rogue":
			_burst(effect, (event.get("previous_position", spot) as Vector3) + Vector3(0.0, 0.6, 0.0), ROGUE_SKILL_COLOR, 12, 0.4)
			_burst(effect, spot + Vector3(0.0, 0.6, 0.0), ROGUE_SKILL_COLOR, 12, 0.4)
			return 0.4
	return 0.0


func _enemy_skill(effect: Node3D, event: Dictionary) -> float:
	var point: Vector3 = event.get("point", Vector3.ZERO)
	if str(event.get("shape", "")) == "line":
		_streak(effect, event.get("origin", point), point, 0.3, ENEMY_SKILL_COLOR, 0.3)
		return 0.3
	var radius: float = float(event.get("radius", 1.0))
	_expanding_ring(effect, point, ENEMY_SKILL_COLOR, radius * 0.3, radius, 0.4)
	_burst(effect, point + Vector3(0.0, 0.4, 0.0), ENEMY_SKILL_COLOR, 16, 0.4)
	return 0.4


func _burst(effect: Node3D, at: Vector3, color: Color, amount: int, lifetime: float) -> void:
	var particles := CPUParticles3D.new()
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = amount
	particles.lifetime = lifetime
	particles.direction = Vector3.UP
	particles.spread = 180.0
	particles.initial_velocity_min = 2.0
	particles.initial_velocity_max = 4.0
	particles.gravity = Vector3(0.0, -6.0, 0.0)
	var speck := BoxMesh.new()
	speck.size = Vector3(0.08, 0.08, 0.08)
	speck.material = _material(color)
	particles.mesh = speck
	particles.speed_scale = _time_scale
	particles.position = at
	effect.add_child(particles)
	particles.emitting = true


func _expanding_ring(effect: Node3D, at: Vector3, color: Color, from_radius: float, to_radius: float, seconds: float) -> void:
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.88
	ring_mesh.outer_radius = 1.0
	var ring: MeshInstance3D = _mesh(effect, ring_mesh, color)
	ring.position = Vector3(at.x, 0.08, at.z)
	ring.scale = Vector3(from_radius, 1.0, from_radius)
	var tween: Tween = _track(ring.create_tween().set_parallel())
	tween.tween_property(ring, "scale", Vector3(to_radius, 1.0, to_radius), seconds)
	tween.tween_property(ring.material_override, "albedo_color:a", 0.0, seconds)


func _streak(effect: Node3D, from: Vector3, to: Vector3, width: float, color: Color, seconds: float) -> void:
	var span: Vector3 = Vector3(to.x - from.x, 0.0, to.z - from.z)
	var box := BoxMesh.new()
	box.size = Vector3(width, 0.05, maxf(span.length(), 0.1))
	var streak: MeshInstance3D = _mesh(effect, box, color)
	streak.position = Vector3((from.x + to.x) * 0.5, 0.9, (from.z + to.z) * 0.5)
	streak.rotation.y = atan2(span.x, span.z)
	_fade(streak, seconds)


func _crit_label(effect: Node3D, at: Vector3, text: String) -> void:
	var jitter: Vector3 = Vector3(randf_range(-CRIT_JITTER, CRIT_JITTER), 0.0, 0.0)
	var label: Label3D = _rising_label(effect, at + jitter, text, CRIT_COLOR, 0.12)
	label.outline_modulate = CRIT_OUTLINE_COLOR
	label.font_size = CRIT_FONT_SIZE
	label.scale = Vector3.ONE * 1.8
	_track(label.create_tween()).tween_property(label, "scale", Vector3.ONE, 0.12)


func _rising_label(effect: Node3D, at: Vector3, text: String, color: Color, delay: float = 0.0) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = DAMAGE_FONT_SIZE
	label.pixel_size = 0.02
	label.outline_size = 8
	label.modulate = color
	# Above the HP bar layers (BattleUnitView.BAR_RENDER_PRIORITY), which also skip the depth test.
	label.render_priority = 4
	label.outline_render_priority = 3
	label.position = at + Vector3(0.0, 2.3, 0.0)
	effect.add_child(label)
	var tween: Tween = _track(label.create_tween().set_parallel())
	tween.tween_property(label, "position:y", label.position.y + 0.9, 0.7).set_delay(delay)
	tween.tween_property(label, "modulate:a", 0.0, 0.7).set_delay(delay)
	tween.tween_property(label, "outline_modulate:a", 0.0, 0.7).set_delay(delay)
	return label


func _fade(instance: MeshInstance3D, seconds: float) -> void:
	_track(instance.create_tween()).tween_property(instance.material_override, "albedo_color:a", 0.0, seconds)


func _track(tween: Tween) -> Tween:
	_tweens.append(tween)
	_prune_tweens()
	return tween


func _prune_tweens() -> void:
	var live: Array[Tween] = []
	for tween: Tween in _tweens:
		if tween.is_valid():
			tween.set_speed_scale(_time_scale)
			live.append(tween)
	_tweens = live


func _mesh(effect: Node3D, mesh_resource: Mesh, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh_resource
	instance.material_override = _material(color)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	effect.add_child(instance)
	return instance


static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	return material


static func _effects(actor: Dictionary) -> Dictionary:
	# effect_state crosses the serialized snapshot boundary; narrow before reading cues.
	var value: Variant = actor.get("effect_state", {})
	return value as Dictionary if value is Dictionary else {}


static func _tick(actor: Dictionary, key: String) -> int:
	return int(_effects(actor).get(key, -1))


# Snapshot coordinates are two-number arrays on the ground plane.
static func _world(value: Variant, fallback: Vector2 = Vector2.ZERO) -> Vector3:
	var point: Vector2 = fallback
	if value is Vector2:
		point = value as Vector2
	elif value is Array and (value as Array).size() == 2:
		point = Vector2(float((value as Array)[0]), float((value as Array)[1]))
	return Vector3(point.x, 0.0, point.y)
