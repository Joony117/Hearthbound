class_name BattleUnitView
extends Node3D

## Emitted once when an animated death clip ends, with the body where it came to rest.
signal body_landed(at: Vector3)

# Scales the 2.5-unit KayKit knight to the old unit's height, under the bar.
const MODEL_SCALE: float = 0.75
# Models, weapons, attack clips and the clip library come from HeroModel.
const ALLY_CLIPS: Dictionary = {"idle": "Idle_A", "move": "Running_A", "dead": "Death_A", "downed": "Death_B"}
const ENEMY_CLIPS: Dictionary = {"idle": "Skeletons_Idle", "move": "Skeletons_Walking", "dead": "Skeletons_Death", "downed": "Death_B"}
# Matches battle_vfx: these attacks fly as projectiles, so battle_view never lunges them.
const PROJECTILE_ARCHETYPES: Array[String] = ["ranger", "mage"]
const CLIP_BLEND_SECONDS: float = 0.15
const DEAD_TWEEN_SECONDS: float = 0.35
const RECOIL_DISTANCE: float = 0.35
const RECOIL_CRIT_DISTANCE: float = 0.55
const RECOIL_OUT_SECONDS: float = 0.06
const RECOIL_BACK_SECONDS: float = 0.2
const RECOIL_HP_FRACTION: float = 0.25
const HIT_STOP_SECONDS: float = 0.1
const LUNGE_DISTANCE: float = 0.5
const LUNGE_OUT_SECONDS: float = 0.07
const LUNGE_BACK_SECONDS: float = 0.2
const FLING_DISTANCE: float = 0.25
const FLING_CRIT_DISTANCE: float = 0.8
const FLING_ARC_HEIGHT: float = 0.3
const BAR_HEIGHT_OFFSET: float = 2.2
const BAR_WIDTH: float = 0.7
const BAR_ELITE_WIDTH: float = 0.85
const BAR_THICKNESS: float = 0.07
const BAR_BACK_COLOR: Color = Color(0.102, 0.102, 0.102, 0.6)
const BAR_CHIP_COLOR: Color = Color("f5e6a8")
const BAR_ALLY_COLOR: Color = Color("6fcf6f")
const BAR_ENEMY_COLOR: Color = Color("e8483c")
const BAR_CHIP_SECONDS: float = 0.4
# One priority for every bar layer, under damage numbers (Label3D at 3/4); sorting_offset orders
# the layers inside one bar so two overlapping bars never interleave.
const BAR_RENDER_PRIORITY: int = 1
# PROVISIONAL (ig-iml): hit flash feel, unfelt. Settled by: a played build.
const HIT_FLASH_SECONDS: float = 0.08
const HIT_FLASH_CRIT_SECONDS: float = 0.16
const HIT_FLASH_STRENGTH: float = 0.6
const HIT_FLASH_CRIT_STRENGTH: float = 0.95
# PROVISIONAL (ig-hpu): faction ring colours and corpse dim, unplayed. Settled by: a played build.
# The old capsule body colours, now a thin ground ring; the gold selection ring covers it.
const ALLY_COLOR: Color = Color("a8c9a8")
const ENEMY_COLOR: Color = Color("e87b68")
const CORPSE_DIM: Color = Color(0.0, 0.0, 0.0, 0.7)

static var _bar_back_material: StandardMaterial3D = _bar_material(BAR_BACK_COLOR)
static var _bar_chip_material: StandardMaterial3D = _bar_material(BAR_CHIP_COLOR)
static var _bar_ally_material: StandardMaterial3D = _bar_material(BAR_ALLY_COLOR)
static var _bar_enemy_material: StandardMaterial3D = _bar_material(BAR_ENEMY_COLOR)
# One overlay for every unit's hit flash; each mesh carries its own strength as an instance uniform.
static var _flash_material: ShaderMaterial = _build_flash_material()
# Shared by every unit, so 60 units add no per-unit materials or meshes.
static var _faction_ring_mesh: TorusMesh = _build_faction_ring_mesh()
static var _ally_ring_material: StandardMaterial3D = _flat_material(ALLY_COLOR)
static var _enemy_ring_material: StandardMaterial3D = _flat_material(ENEMY_COLOR)
static var _corpse_material: StandardMaterial3D = _flat_material(CORPSE_DIM)

var actor_id: String = ""
var hero_id: String = ""
var squad_id: String = ""
var faction: String = ""
var archetype: String = ""
var life: String = "alive"
var hp: float = 0.0
var max_hp: float = 1.0
var target_position: Vector3 = Vector3.ZERO
var selected: bool = false

# Every visual hangs off this pivot so recoil, lunge and fling move it; set_actor owns the root's rotation.y.
var _pivot: Node3D
var _animator: AnimationPlayer
var _clips: Dictionary = ALLY_CLIPS
var _attack_clip: String = ""
# An attack or hit clip is playing; the idle, move and death clips wait for it.
var _one_shot: bool = false
var _attack_cooldown: float = 0.0
var _dead_posed: bool = false
var _animate_death: bool = false
var _selection_ring: MeshInstance3D
var _faction_ring: MeshInstance3D
# The health bar sits on the root, not the pivot, so recoil and the death fling never move it.
var _hp_bar: Node3D
var _hp_back: MeshInstance3D
var _hp_chip: MeshInstance3D
var _hp_fill: MeshInstance3D
var _chip_tween: Tween
var _chip_fraction: float = 1.0:
	set(value):
		_chip_fraction = value
		_layout_bar()
var _downed_marker: MeshInstance3D
var _elite_ring: MeshInstance3D
var _guard_bubble: MeshInstance3D
var _state_label: Label3D
var _telegraph_ring: MeshInstance3D
var _telegraph_line: MeshInstance3D
var _last_hit_tick: int = -1
var _last_skill_tick: int = -1
var _last_crit_tick: int = -1
var _recoil_tween: Tween
var _lunge_tween: Tween
# Pivot offsets live in world space, one per effect; _apply_pivot is the only writer of _pivot.position.
var _recoil_offset: Vector3 = Vector3.ZERO:
	set(value):
		_recoil_offset = value
		_apply_pivot()
var _lunge_offset: Vector3 = Vector3.ZERO:
	set(value):
		_lunge_offset = value
		_apply_pivot()
var _fling_offset: Vector3 = Vector3.ZERO:
	set(value):
		_fling_offset = value
		_apply_pivot()
var _fling_arc: float = 0.0:
	set(value):
		_fling_arc = value
		_apply_pivot()
var _facing_world: Vector3 = Vector3.RIGHT
var _fling_distance: float = FLING_DISTANCE
# Every tween this view starts, so slow-mo and hit-stop can rescale them together.
var _tweens: Array[Tween] = []
var _view_time_scale: float = 1.0
var _freeze_remaining: float = 0.0
var _effects: Dictionary = {}
# Linear playback between snapshots: from where the unit is drawn to the new sim position over one render interval.
var _placed: bool = false
var _glide_from: Vector3 = Vector3.ZERO
var _glide_seconds: float = 0.0
var _glide_elapsed: float = 0.0
# A hit inside a multi-tick render reacts at its own tick, not the moment the render lands.
var _pending_reaction: Dictionary = {}
var _reaction_remaining: float = 0.0
var _flash_meshes: Array[MeshInstance3D] = []
var _flash_tween: Tween
# The fall played as a clip, so its end is a landing worth a dust puff; a corpse seen already down never lands.
var _fall_animated: bool = false


func _ready() -> void:
	_build_visual()


## glide_seconds: how long to move from the drawn position to the new one; 0 snaps.
## reaction_delay: real seconds until this render's hit and skill reactions play.
func set_actor(actor: Dictionary, is_selected: bool, glide_seconds: float = 0.0, reaction_delay: float = 0.0) -> void:
	_flush_reaction()
	actor_id = str(actor.get("id", ""))
	hero_id = str(actor.get("hero_id", ""))
	squad_id = str(actor.get("squad_id", ""))
	faction = str(actor.get("faction", "enemy"))
	archetype = str(actor.get("archetype", ""))
	life = str(actor.get("life", "alive"))
	var hp_before: float = hp
	hp = float(actor.get("hp", 0.0))
	max_hp = maxf(float(actor.get("max_hp", 1.0)), 1.0)
	# Snapshot effect_state is serialized input; narrow to Dictionary before reading presentation cues.
	var effect_value: Variant = actor.get("effect_state", {})
	_effects = effect_value as Dictionary if effect_value is Dictionary else {}
	var hit_tick: int = int(_effects.get("last_hit_tick", -1))
	var skill_tick: int = int(_effects.get("last_skill_tick", -1))
	var crit_tick: int = int(_effects.get("last_crit_tick", -1))
	var was_hit: bool = _last_hit_tick >= 0 and hit_tick > _last_hit_tick
	var reaction: Dictionary = {
		"hit": was_hit,
		"skill": _last_skill_tick >= 0 and skill_tick > _last_skill_tick,
		"critical": was_hit and crit_tick > _last_crit_tick,
		"heavy": was_hit and hp_before - hp >= max_hp * RECOIL_HP_FRACTION,
	}
	_last_hit_tick = hit_tick
	_last_skill_tick = skill_tick
	_last_crit_tick = crit_tick
	# A cooldown that went up means this unit just attacked; projectile attackers get no lunge to show it.
	# ponytail: misses an attack whose fresh cooldown ends below the old one inside one render; an attack event would fix it.
	var attack_cooldown: float = float(actor.get("attack_cooldown", 0.0))
	if _placed and attack_cooldown > _attack_cooldown and archetype in PROJECTILE_ARCHETYPES:
		_play_attack()
	_attack_cooldown = attack_cooldown
	selected = is_selected
	var destination: Vector3 = _world_position(actor.get("position", [0.0, 0.0]))
	if not _placed or glide_seconds <= 0.0:
		_glide_from = destination
		_glide_seconds = 0.0
		position = destination
	elif destination != target_position:
		_glide_from = position
		_glide_seconds = glide_seconds
		_glide_elapsed = 0.0
	target_position = destination
	_placed = true
	var facing: Vector2 = _vector2(actor.get("facing", [1.0, 0.0]))
	_facing_world = Vector3(facing.x, 0.0, facing.y).normalized()
	# +Z along the facing: KayKit models look down their own +Z.
	rotation.y = atan2(facing.x, facing.y)
	if reaction_delay > 0.0 and (reaction["hit"] or reaction["skill"]):
		_pending_reaction = reaction
		_reaction_remaining = reaction_delay
	else:
		_react(reaction)
	if _animator != null:
		_track_chip(hp_before)
		_update_status()
	_apply_pivot()


# Real-time freeze: a crit holds the impact pose even while slow-mo runs.
func hit_stop() -> void:
	_freeze_remaining = HIT_STOP_SECONDS
	_apply_time_scale()


func set_time_scale(value: float) -> void:
	_view_time_scale = value
	_apply_time_scale()


func lunge(toward: Vector3) -> void:
	if _pivot == null or life != "alive":
		return
	var direction: Vector3 = Vector3(toward.x - target_position.x, 0.0, toward.z - target_position.z).normalized()
	if _lunge_tween != null:
		_lunge_tween.kill()
	_lunge_tween = _track(create_tween())
	_lunge_tween.tween_property(self, "_lunge_offset", direction * LUNGE_DISTANCE, LUNGE_OUT_SECONDS)
	_lunge_tween.tween_property(self, "_lunge_offset", Vector3.ZERO, LUNGE_BACK_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_play_attack()


func set_selected(value: bool) -> void:
	selected = value
	if _selection_ring != null:
		_selection_ring.visible = selected and life == "alive"


func _process(delta: float) -> void:
	if _reaction_remaining > 0.0:
		_reaction_remaining -= delta
		if _reaction_remaining <= 0.0:
			_flush_reaction()
	if _freeze_remaining > 0.0:
		_freeze_remaining = maxf(0.0, _freeze_remaining - delta)
		if _freeze_remaining == 0.0:
			_apply_time_scale()
	var scaled: float = delta * _time_scale()
	_glide_elapsed += scaled
	position = _glide_from.lerp(target_position, 1.0 if _glide_seconds <= 0.0 else minf(_glide_elapsed / _glide_seconds, 1.0))
	_update_status()


func _react(reaction: Dictionary) -> void:
	var critical: bool = reaction["critical"]
	_fling_distance = FLING_CRIT_DISTANCE if critical else FLING_DISTANCE
	# A killing hit skips recoil and the hit clip so the death clip reads cleanly.
	if (critical or reaction["heavy"]) and life != "dead" and _pivot != null:
		_recoil(critical)
	if reaction["hit"]:
		_flash(critical)
		_play_once("Hit_B" if critical else "Hit_A")


func _flush_reaction() -> void:
	_reaction_remaining = 0.0
	if _pending_reaction.is_empty():
		return
	var reaction: Dictionary = _pending_reaction
	_pending_reaction = {}
	_react(reaction)
	_update_status()


func _time_scale() -> float:
	return 0.0 if _freeze_remaining > 0.0 else _view_time_scale


func _apply_time_scale() -> void:
	if _animator != null:
		_animator.speed_scale = _time_scale()
	var live: Array[Tween] = []
	for tween: Tween in _tweens:
		if tween.is_valid():
			tween.set_speed_scale(_time_scale())
			live.append(tween)
	_tweens = live


func _track(tween: Tween) -> Tween:
	_tweens.append(tween)
	_apply_time_scale()
	return tween


func _apply_pivot() -> void:
	if _pivot == null:
		return
	var offset: Vector3 = basis.inverse() * (_recoil_offset + _lunge_offset + _fling_offset)
	_pivot.position = Vector3(offset.x, _fling_arc, offset.z)


func _build_visual() -> void:
	_pivot = Node3D.new()
	add_child(_pivot)
	_clips = ALLY_CLIPS if faction == "ally" else ENEMY_CLIPS
	_attack_clip = HeroModel.look(faction, archetype)[2]
	var model: Node3D = HeroModel.build(faction, archetype)
	model.scale = Vector3.ONE * MODEL_SCALE
	_pivot.add_child(model)
	_animator = model.get_node("AnimationPlayer") as AnimationPlayer
	_animator.animation_finished.connect(_on_clip_finished)
	for mesh: Node in model.find_children("*", "MeshInstance3D", true, false):
		_flash_meshes.append(mesh as MeshInstance3D)
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.48
	ring_mesh.outer_radius = 0.57
	_selection_ring = _mesh(ring_mesh, Vector3(0.0, 0.045, 0.0), Vector3.ONE, _material(Color("d4b65b")))
	_selection_ring.visible = false
	# Flattened so it lies on the ground under the selection ring instead of crossing it.
	_faction_ring = _mesh(_faction_ring_mesh, Vector3(0.0, 0.01, 0.0), Vector3(1.0, 0.3, 1.0), _ally_ring_material if faction == "ally" else _enemy_ring_material)
	_faction_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hp_bar = Node3D.new()
	_hp_bar.position = Vector3(0.0, BAR_HEIGHT_OFFSET, 0.0)
	add_child(_hp_bar)
	_hp_back = _bar_layer(_bar_back_material, 0.0)
	_hp_chip = _bar_layer(_bar_chip_material, 0.01)
	_hp_fill = _bar_layer(_bar_ally_material if faction == "ally" else _bar_enemy_material, 0.02)
	_chip_fraction = clampf(hp / max_hp, 0.0, 1.0)
	_downed_marker = _mesh(SphereMesh.new(), Vector3(0.0, 1.78, 0.0), Vector3(0.2, 0.2, 0.2), _material(Color("e3b668")))
	_downed_marker.visible = false
	var elite_mesh := TorusMesh.new()
	elite_mesh.inner_radius = 0.36
	elite_mesh.outer_radius = 0.39
	_elite_ring = _mesh(elite_mesh, Vector3(0.0, 1.8, 0.0), Vector3.ONE, _material(Color("e3b668")))
	_guard_bubble = _mesh(SphereMesh.new(), Vector3(0.0, 0.82, 0.0), Vector3(0.74, 1.1, 0.74), _transparent_material(Color(0.55, 0.78, 0.93, 0.2)))
	_guard_bubble.visible = false
	_state_label = Label3D.new()
	_state_label.position = Vector3(0.0, 2.45, 0.0)
	_state_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_state_label.font_size = 48
	_state_label.outline_size = 8
	_state_label.modulate = Color("e8a974")
	_pivot.add_child(_state_label)
	var telegraph_mesh := TorusMesh.new()
	# Telegraphs hang off the root, not the pivot, so recoil never moves a danger zone.
	_telegraph_ring = _mesh(telegraph_mesh, Vector3(0.0, 0.07, 0.0), Vector3.ONE, _transparent_material(Color(0.91, 0.36, 0.31, 0.42)), self)
	_telegraph_line = _mesh(BoxMesh.new(), Vector3.ZERO, Vector3.ONE, _transparent_material(Color(0.91, 0.36, 0.31, 0.42)), self)
	_telegraph_ring.visible = false
	_telegraph_line.visible = false
	# A unit first seen already dead or downed (mid-battle load) snaps; later falls animate.
	_apply_time_scale()
	_update_status()
	_animate_death = true


func _update_status() -> void:
	if _animator == null:
		return
	var downed: bool = life == "downed"
	var dead: bool = life == "dead"
	# The death waits for the killing hit's reaction, so the corpse never tips before the blow lands.
	if dead and not _dead_posed and _reaction_remaining <= 0.0:
		_pose_dead()
	_update_clip()
	_hp_bar.visible = life == "alive" and (hp < max_hp or selected)
	_layout_bar()
	_state_label.visible = not dead
	_downed_marker.visible = downed
	_selection_ring.visible = selected and life == "alive"
	# A corpse loses its ring, so a pile of dead reads apart from the living.
	_faction_ring.visible = not dead
	_elite_ring.visible = bool(_effects.get("elite", false)) and life == "alive"
	_guard_bubble.visible = float(_effects.get("guard_remaining", 0.0)) > 0.0 and life == "alive"
	var label_text: String = "!" if float(_effects.get("attack_windup_remaining", 0.0)) > 0.0 else "STUN" if float(_effects.get("stun_remaining", 0.0)) > 0.0 else ""
	_state_label.text = "%s  %s" % ["ELITE" if bool(_effects.get("elite", false)) else "", label_text]
	var telegraph_kind: String = str(_effects.get("telegraph_kind", ""))
	var telegraph_remaining: float = float(_effects.get("telegraph_remaining", 0.0))
	_telegraph_ring.visible = telegraph_remaining > 0.0 and telegraph_kind == "circle" and not dead
	_telegraph_line.visible = telegraph_remaining > 0.0 and telegraph_kind == "line" and not dead
	if _telegraph_ring.visible:
		var point: Vector2 = _vector2(_effects.get("telegraph_point", [0.0, 0.0]))
		_telegraph_ring.position = to_local(Vector3(point.x, 0.07, point.y))
		var radius: float = maxf(float(_effects.get("telegraph_radius", 0.0)), 0.1)
		var ring_mesh: TorusMesh = _telegraph_ring.mesh as TorusMesh
		# Primitive mesh setters rebuild the mesh, and this runs every frame.
		if ring_mesh.outer_radius != radius or ring_mesh.inner_radius != radius * 0.92:
			ring_mesh.inner_radius = radius * 0.92
			ring_mesh.outer_radius = radius
	if _telegraph_line.visible:
		var origin: Vector2 = _vector2(_effects.get("telegraph_origin", [0.0, 0.0]))
		var point: Vector2 = _vector2(_effects.get("telegraph_point", [0.0, 0.0]))
		var local_origin: Vector3 = to_local(Vector3(origin.x, 0.0, origin.y))
		var local_point: Vector3 = to_local(Vector3(point.x, 0.0, point.y))
		var line_vector: Vector2 = Vector2(local_point.x - local_origin.x, local_point.z - local_origin.z)
		_telegraph_line.position = (local_origin + local_point) * 0.5 + Vector3(0.0, 0.08, 0.0)
		# The box's length runs along its local +Z.
		_telegraph_line.rotation.y = atan2(line_vector.x, line_vector.y)
		var line_mesh: BoxMesh = _telegraph_line.mesh as BoxMesh
		var line_size: Vector3 = Vector3(0.14, 0.03, maxf(line_vector.length(), 0.1))
		if line_mesh.size != line_size:
			line_mesh.size = line_size


# View-only knockback: the sim position is untouched. Each effect owns its own offset and
# _apply_pivot sums them, so an in-flight recoil, a lunge and the death fling never fight.
func _recoil(critical: bool) -> void:
	if _recoil_tween != null:
		_recoil_tween.kill()
	_recoil_tween = _track(create_tween())
	_recoil_tween.tween_property(self, "_recoil_offset", -_facing_world * (RECOIL_CRIT_DISTANCE if critical else RECOIL_DISTANCE), RECOIL_OUT_SECONDS)
	_recoil_tween.tween_property(self, "_recoil_offset", Vector3.ZERO, RECOIL_BACK_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# The chip trails a hit and snaps on a heal, so only damage leaves a pale tail behind the fill.
func _track_chip(hp_before: float) -> void:
	var fraction: float = clampf(hp / max_hp, 0.0, 1.0)
	if hp == hp_before:
		return
	if _chip_tween != null:
		_chip_tween.kill()
	if hp > hp_before:
		_chip_fraction = fraction
		return
	_chip_tween = _track(create_tween())
	_chip_tween.tween_property(self, "_chip_fraction", fraction, BAR_CHIP_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# Death is one-way in the sim, so the pose is applied once and never undone.
func _pose_dead() -> void:
	_dead_posed = true
	# The killing hit's flash owns the overlay until it ends; _clear_flash hands it the dim.
	if _flash_tween == null or not _flash_tween.is_running():
		_clear_flash()
	if not _animate_death:
		return
	_fall_animated = true
	var tween: Tween = _track(create_tween().set_parallel())
	tween.tween_property(self, "_fling_offset", -_facing_world * _fling_distance, DEAD_TWEEN_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_method(_set_fling_phase, 0.0, 1.0, DEAD_TWEEN_SECONDS)


# The arc rises and lands inside the fling, so the corpse ends at rest on the ground.
func _set_fling_phase(phase: float) -> void:
	_fling_arc = sin(phase * PI) * FLING_ARC_HEIGHT if phase < 1.0 else 0.0


func _layout_bar() -> void:
	if _hp_fill == null:
		return
	var width: float = BAR_ELITE_WIDTH if bool(_effects.get("elite", false)) else BAR_WIDTH
	var fraction: float = clampf(hp / max_hp, 0.0, 1.0)
	_size_bar_layer(_hp_back, width, 1.0)
	_size_bar_layer(_hp_chip, width, maxf(_chip_fraction, fraction))
	_size_bar_layer(_hp_fill, width, fraction)


# Left-anchored through the mesh's own offset: billboarding turns vertices, not the node's position.
func _size_bar_layer(layer: MeshInstance3D, width: float, fraction: float) -> void:
	layer.visible = fraction > 0.0
	var quad: QuadMesh = layer.mesh as QuadMesh
	var size: Vector2 = Vector2(width * fraction, BAR_THICKNESS)
	if quad.size != size:
		quad.size = size
		quad.center_offset = Vector3((fraction - 1.0) * width * 0.5, 0.0, 0.0)


func _bar_layer(material: StandardMaterial3D, sort_offset: float) -> MeshInstance3D:
	var layer := MeshInstance3D.new()
	layer.mesh = QuadMesh.new()
	layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	layer.sorting_use_aabb_center = false
	layer.sorting_offset = sort_offset
	layer.material_override = material
	_hp_bar.add_child(layer)
	return layer


static func _bar_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.no_depth_test = true
	material.render_priority = BAR_RENDER_PRIORITY
	return material


# Serialized snapshots may contain either Vector2 values or two-number JSON arrays.
func _world_position(value: Variant) -> Vector3:
	var point: Vector2 = _vector2(value)
	return Vector3(point.x, 0.0, point.y)


# Variant is confined to the serialized coordinate boundary and narrowed before use.
func _vector2(value: Variant) -> Vector2:
	if value is Vector2:
		return value as Vector2
	if value is Array and (value as Array).size() == 2:
		var point: Array = value as Array
		return Vector2(float(point[0]), float(point[1]))
	return Vector2.ZERO


func _mesh(mesh_resource: Mesh, offset: Vector3, mesh_scale: Vector3, material: StandardMaterial3D, parent: Node3D = null) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh_resource
	instance.position = offset
	instance.scale = mesh_scale
	instance.material_override = material
	(parent if parent != null else _pivot).add_child(instance)
	return instance


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	return material


func _transparent_material(color: Color) -> StandardMaterial3D:
	var material := _material(color)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


# Idle, move, downed and dead are the base clips; attack and hit play once over them.
func _update_clip() -> void:
	if _one_shot and life == "alive":
		return
	_one_shot = false
	var clip: String
	if life == "dead":
		# The fall waits for _pose_dead, which waits for the killing hit.
		if not _dead_posed:
			return
		clip = _clips["dead"]
	elif life == "downed":
		clip = _clips["downed"]
	elif _glide_seconds > 0.0 and _glide_elapsed < _glide_seconds:
		clip = _clips["move"]
	else:
		clip = _clips["idle"]
	if _animator.assigned_animation == clip:
		return
	# Falls hold their last frame; a unit first seen fallen starts on it.
	_animator.play(clip, CLIP_BLEND_SECONDS if _animate_death else 0.0)
	if not _animate_death and not clip in HeroModel.LOOPED_CLIPS:
		_animator.seek(_animator.current_animation_length, true)


func _play_attack() -> void:
	_play_once(_attack_clip)


func _play_once(clip: String) -> void:
	if _animator == null or life != "alive":
		return
	_one_shot = true
	_animator.play(clip, CLIP_BLEND_SECONDS)
	_animator.seek(0.0)


func _on_clip_finished(clip: StringName) -> void:
	_one_shot = false
	if _fall_animated and clip == StringName(_clips["dead"]):
		_fall_animated = false
		body_landed.emit(_pivot.global_position)


# Hit-stop freezes this tween with the rest, so a crit holds its flash through the freeze.
func _flash(critical: bool) -> void:
	if _flash_meshes.is_empty():
		return
	if _flash_tween != null:
		_flash_tween.kill()
	for mesh: MeshInstance3D in _flash_meshes:
		mesh.material_overlay = _flash_material
	var strength: float = HIT_FLASH_CRIT_STRENGTH if critical else HIT_FLASH_STRENGTH
	_set_flash(strength)
	_flash_tween = _track(create_tween())
	_flash_tween.tween_method(_set_flash, strength, 0.0, HIT_FLASH_CRIT_SECONDS if critical else HIT_FLASH_SECONDS)
	_flash_tween.tween_callback(_clear_flash)


func _set_flash(strength: float) -> void:
	for mesh: MeshInstance3D in _flash_meshes:
		mesh.set_instance_shader_parameter(&"flash", strength)


# The overlay is an extra draw pass, so it only stays on while a flash runs, or on a corpse.
func _clear_flash() -> void:
	for mesh: MeshInstance3D in _flash_meshes:
		mesh.material_overlay = _corpse_material if _dead_posed else null


static func _build_faction_ring_mesh() -> TorusMesh:
	var ring := TorusMesh.new()
	ring.inner_radius = 0.49
	ring.outer_radius = 0.55
	return ring


static func _flat_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


static func _build_flash_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never;
instance uniform float flash = 0.0;
void fragment() {
	ALBEDO = vec3(1.0);
	ALPHA = flash;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material
