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
# PROVISIONAL (ig-iml): impact feel numbers, unfelt. Settled by: a played build.
const HIT_SPARK_COUNT: int = 28
const HIT_SPARK_SIZE: float = 0.13
const HIT_SPARK_SPEED: float = 1.4
const CRIT_RING_RADIUS: float = 1.0
const CRIT_BIG_RING_RADIUS: float = 2.0
const CRIT_RING_SECONDS: float = 0.3
const PROJECTILE_SECONDS: float = 0.12
const PROJECTILE_IMPACT_COUNT: int = 16
const PROJECTILE_IMPACT_SIZE: float = 0.12
const SKILL_CAST_FLASH_RADIUS: float = 0.9
const SKILL_CAST_FLASH_SECONDS: float = 0.22
const SKILL_SHOCKWAVE_RADIUS: float = 2.4
const SKILL_SHOCKWAVE_SECONDS: float = 0.35
const SKILL_IMPACT_COUNT: int = 32
const SKILL_IMPACT_SIZE: float = 0.18
const SKILL_IMPACT_SPEED: float = 1.5
const BURST_SPHERE_SECONDS: float = 0.35
const BURST_SPHERE_ALPHA: float = 0.55
const DAMAGE_POP_SCALE: float = 1.3
const CRIT_POP_SCALE: float = 2.2
const DAMAGE_POP_SECONDS: float = 0.12
const LANDING_DUST_COUNT: int = 18
const LANDING_DUST_SIZE: float = 0.16
const LANDING_DUST_SPEED: float = 0.6
const LANDING_RING_RADIUS: float = 1.1
# Camera trauma per event, 0-1; battle_view squares it into a shake offset.
const SHAKE_CRIT: float = 0.45
const SHAKE_SKILL: float = 0.55
const SHAKE_MAGE: float = 0.9

# One material for every effect mesh; each mesh carries its color and fade as an instance uniform.
static var _effect_material: ShaderMaterial = _build_effect_material()
# One material for every particle speck; CPUParticles3D.color tints it per burst.
static var _speck_material: StandardMaterial3D = _build_speck_material()
static var _specks: Dictionary = {}

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
		var ability: AbilityDefinition = BattleSimulation.signature_for(archetype)
		if skill_visible and _tick(after, "last_skill_tick") > _tick(before, "last_skill_tick") and ability != null:
			var skill: Dictionary = {
				"kind": "skill",
				"actor_id": actor_id,
				"faction": faction,
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
					# The sim faces the shot at its first target; the streak follows what it actually pierced.
					if archetype == "ranger" and not centroid.is_equal_approx(spot):
						skill["facing"] = (centroid - spot).normalized()
			elif archetype == "cleric":
				# Mend lands on the ally in range whose HP rose the most.
				var best_gain: float = 0.0
				for other_id: String in current:
					var other: Dictionary = current[other_id]
					var gain: float = float(other.get("hp", 0.0)) - float((previous.get(other_id, {}) as Dictionary).get("hp", 0.0))
					var other_position: Vector3 = _world(other.get("position"))
					if previous.get(other_id) is Dictionary and str(other.get("faction", "")) == faction and gain > best_gain and other_position.distance_to(spot) <= ability.range_units:
						best_gain = gain
						skill["center"] = other_position
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
			_burst(effect, spot + Vector3(0.0, 0.9, 0.0), SPARK_COLOR, HIT_SPARK_COUNT, 0.3, HIT_SPARK_SIZE, HIT_SPARK_SPEED)
			var critical: bool = bool(event.get("critical", false))
			if critical:
				_expanding_ring(effect, spot, CRIT_COLOR, 0.3, CRIT_RING_RADIUS, CRIT_RING_SECONDS)
				_expanding_ring(effect, spot, CRIT_OUTLINE_COLOR, 0.5, CRIT_BIG_RING_RADIUS, CRIT_RING_SECONDS * 1.5)
			var damage: int = int(event.get("damage", 0))
			if damage > 0:
				if critical:
					_crit_label(effect, spot, "%d!" % damage)
					lifetime = 0.85
				else:
					_rising_label(effect, spot, str(damage), DAMAGE_COLOR, 0.0, DAMAGE_POP_SCALE)
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
		"landing":
			_burst(effect, spot + Vector3(0.0, 0.15, 0.0), DUST_COLOR, LANDING_DUST_COUNT, 0.6, LANDING_DUST_SIZE, LANDING_DUST_SPEED)
			_expanding_ring(effect, spot, DUST_COLOR, 0.3, LANDING_RING_RADIUS, 0.4)
			lifetime = 0.6
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
		var flight: Tween = _track(projectile.create_tween())
		flight.tween_property(projectile, "position", target, PROJECTILE_SECONDS)
		flight.tween_callback(projectile.hide)
		_burst(effect, target, color, PROJECTILE_IMPACT_COUNT, 0.3, PROJECTILE_IMPACT_SIZE, 1.0, PROJECTILE_SECONDS)
		return PROJECTILE_SECONDS + 0.3
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
	_fade(arc, 0.18)
	return 0.18


# Every signature: a cast flash at the caster, a ground shockwave, and a big impact where it lands.
func _skill(effect: Node3D, event: Dictionary) -> float:
	var spot: Vector3 = event.get("position", Vector3.ZERO)
	var facing: Vector3 = event.get("facing", Vector3.FORWARD)
	var archetype: String = str(event.get("archetype", ""))
	var colors: Dictionary = {"knight": KNIGHT_SKILL_COLOR, "ranger": RANGER_SKILL_COLOR, "mage": MAGE_SKILL_COLOR, "rogue": ROGUE_SKILL_COLOR, "cleric": HEAL_COLOR}
	var color: Color = ENEMY_SKILL_COLOR if str(event.get("faction", "")) == "enemy" else colors.get(archetype, ENEMY_SKILL_COLOR)
	match archetype:
		"knight":
			_cast_flash(effect, spot, color)
			_expanding_ring(effect, spot, color, 0.3, float(event.get("radius", 1.0)), 0.4)
			_impact(effect, spot, color)
			return 0.45
		"ranger":
			return _line_signature(effect, spot, spot + facing * float(event.get("range", 1.0)), event.get("center", spot), 0.12, color)
		"mage":
			return _burst_signature(effect, spot, event.get("center", spot), float(event.get("radius", 1.0)), color)
		"rogue":
			# Vanish where it stood, strike where it lands.
			_cast_flash(effect, event.get("previous_position", spot), color)
			_expanding_ring(effect, spot, color, 0.3, SKILL_SHOCKWAVE_RADIUS * 0.7, SKILL_SHOCKWAVE_SECONDS)
			_impact(effect, spot, color)
			return 0.45
		"cleric":
			# Single-target heal: no shockwave.
			_cast_flash(effect, spot, color)
			_impact(effect, event.get("center", spot), color)
			return 0.45
	return 0.0


func _enemy_skill(effect: Node3D, event: Dictionary) -> float:
	var point: Vector3 = event.get("point", Vector3.ZERO)
	var origin: Vector3 = event.get("origin", point)
	if str(event.get("shape", "")) == "line":
		return _line_signature(effect, origin, point, point, 0.3, ENEMY_SKILL_COLOR)
	return _burst_signature(effect, origin, point, float(event.get("radius", 1.0)), ENEMY_SKILL_COLOR)


func _line_signature(effect: Node3D, from: Vector3, to: Vector3, impact_at: Vector3, width: float, color: Color) -> float:
	_cast_flash(effect, from, color)
	_expanding_ring(effect, from, color, 0.2, SKILL_SHOCKWAVE_RADIUS * 0.5, SKILL_SHOCKWAVE_SECONDS)
	_streak(effect, from, to, width, color, 0.3)
	_impact(effect, impact_at, color)
	return 0.45


# The mage burst is the showpiece: a sphere swelling to the blast radius over a double shockwave.
func _burst_signature(effect: Node3D, caster: Vector3, center: Vector3, radius: float, color: Color) -> float:
	_cast_flash(effect, caster, color)
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radial_segments = 24
	sphere_mesh.rings = 12
	var sphere: MeshInstance3D = _mesh(effect, sphere_mesh, Color(color, BURST_SPHERE_ALPHA))
	sphere.position = Vector3(center.x, 0.3, center.z)
	sphere.scale = Vector3.ONE * radius * 0.2
	_track(sphere.create_tween()).tween_property(sphere, "scale", Vector3(radius, radius * 0.6, radius), BURST_SPHERE_SECONDS).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_fade(sphere, BURST_SPHERE_SECONDS)
	_expanding_ring(effect, center, color, radius * 0.3, radius, 0.4)
	_expanding_ring(effect, center, color.lightened(0.4), radius * 0.5, radius * 1.4, 0.5)
	_impact(effect, center, color)
	return 0.5


func _cast_flash(effect: Node3D, at: Vector3, color: Color) -> void:
	var flash_mesh := SphereMesh.new()
	flash_mesh.radial_segments = 16
	flash_mesh.rings = 8
	var flash: MeshInstance3D = _mesh(effect, flash_mesh, Color(color.lightened(0.5), 0.9))
	flash.position = at + Vector3(0.0, 0.9, 0.0)
	flash.scale = Vector3.ONE * 0.2
	_track(flash.create_tween()).tween_property(flash, "scale", Vector3.ONE * SKILL_CAST_FLASH_RADIUS, SKILL_CAST_FLASH_SECONDS)
	_fade(flash, SKILL_CAST_FLASH_SECONDS)


func _impact(effect: Node3D, at: Vector3, color: Color) -> void:
	_burst(effect, at + Vector3(0.0, 0.6, 0.0), color, SKILL_IMPACT_COUNT, 0.45, SKILL_IMPACT_SIZE, SKILL_IMPACT_SPEED)


## Camera trauma an event adds: crits and skills shake, ordinary hits never do.
static func shake_for(event: Dictionary) -> float:
	match str(event.get("kind", "")):
		"hit":
			return SHAKE_CRIT if bool(event.get("critical", false)) else 0.0
		"skill":
			match str(event.get("archetype", "")):
				"mage":
					return SHAKE_MAGE
				"cleric":
					return 0.0
			return SHAKE_SKILL
		"enemy_skill":
			return SHAKE_MAGE if str(event.get("shape", "")) == "circle" else SHAKE_SKILL
	return 0.0


func _burst(effect: Node3D, at: Vector3, color: Color, amount: int, lifetime: float, size: float = 0.08, speed: float = 1.0, delay: float = 0.0) -> void:
	var particles := CPUParticles3D.new()
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = amount
	particles.lifetime = lifetime
	particles.direction = Vector3.UP
	particles.spread = 180.0
	particles.initial_velocity_min = 2.0 * speed
	particles.initial_velocity_max = 4.0 * speed
	particles.gravity = Vector3(0.0, -6.0, 0.0)
	particles.mesh = _speck(size)
	particles.color = color
	particles.speed_scale = _time_scale
	particles.position = at
	effect.add_child(particles)
	# CPUParticles3D starts emitting on its own, so a delayed burst must be held first.
	particles.emitting = delay <= 0.0
	if delay <= 0.0:
		return
	var fuse: Tween = _track(particles.create_tween())
	fuse.tween_interval(delay)
	fuse.tween_callback(particles.set_emitting.bind(true))


func _expanding_ring(effect: Node3D, at: Vector3, color: Color, from_radius: float, to_radius: float, seconds: float) -> void:
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.88
	ring_mesh.outer_radius = 1.0
	var ring: MeshInstance3D = _mesh(effect, ring_mesh, color)
	ring.position = Vector3(at.x, 0.08, at.z)
	ring.scale = Vector3(from_radius, 1.0, from_radius)
	var tween: Tween = _track(ring.create_tween().set_parallel())
	tween.tween_property(ring, "scale", Vector3(to_radius, 1.0, to_radius), seconds)
	_fade(ring, seconds)


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
	var label: Label3D = _rising_label(effect, at + jitter, text, CRIT_COLOR, 0.12, CRIT_POP_SCALE)
	label.outline_modulate = CRIT_OUTLINE_COLOR
	label.font_size = CRIT_FONT_SIZE


# pop: the scale a damage number bursts in at before it settles, with overshoot, to its resting size.
func _rising_label(effect: Node3D, at: Vector3, text: String, color: Color, delay: float = 0.0, pop: float = 1.0) -> Label3D:
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
	if pop != 1.0:
		label.scale = Vector3.ONE * pop
		_track(label.create_tween()).tween_property(label, "scale", Vector3.ONE, DAMAGE_POP_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return label


func _fade(instance: MeshInstance3D, seconds: float) -> void:
	var tint: Color = instance.get_instance_shader_parameter(&"tint")
	_track(instance.create_tween()).tween_method(_set_alpha.bind(instance, tint), tint.a, 0.0, seconds)


static func _set_alpha(alpha: float, instance: MeshInstance3D, tint: Color) -> void:
	instance.set_instance_shader_parameter(&"tint", Color(tint, alpha))


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
	instance.material_override = _effect_material
	instance.set_instance_shader_parameter(&"tint", color)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	effect.add_child(instance)
	return instance


static func _speck(size: float) -> BoxMesh:
	if not _specks.has(size):
		var speck := BoxMesh.new()
		speck.size = Vector3.ONE * size
		speck.material = _speck_material
		_specks[size] = speck
	return _specks[size]


static func _build_effect_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never;
instance uniform vec4 tint : source_color = vec4(1.0);
void fragment() {
	ALBEDO = tint.rgb;
	ALPHA = tint.a;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


static func _build_speck_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
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
