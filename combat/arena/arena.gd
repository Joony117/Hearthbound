class_name Arena
extends Node3D

signal scene_change_requested(scene_path: String)
signal enemy_defeated
signal combat_resolved(result: CombatResult)

const BALANCE: BalanceTable = preload("res://balance.tres")
const ENEMY_WINDUP_COLOR: Color = Color(1.0, 0.72, 0.18)
const ENEMY_TELEGRAPH_COLOR: Color = Color(1.0, 0.95, 0.65)
const HIT_HERO_COLOR: Color = Color(1.0, 1.0, 1.0)
const PARRY_HERO_COLOR: Color = Color(0.35, 0.95, 1.0)
const PARRY_WINDOW_COLOR: Color = Color(0.14, 0.42, 0.55)
const DEFEAT_ENEMY_COLOR: Color = Color(1.0, 1.0, 1.0)

enum HitStopOutcome {
	NONE,
	FLINCH_ENEMY,
	DEFEAT_ENEMY,
	HIT_HERO,
	PARRY_HERO,
}

enum EnemyState {
	MOVE,
	ATTACK,
	DODGE,
	PARRY,
	STAGGER,
}

@onready var _camera_pivot: Node3D = %CameraPivot
@onready var _hero_capsule: CharacterBody3D = %HeroCapsule
@onready var _spring_arm: SpringArm3D = %SpringArm3D
@onready var _attack_hitbox: Area3D = %AttackHitbox
@onready var _enemy_capsule: CharacterBody3D = %EnemyCapsule
@onready var _enemy_attack_hitbox: Area3D = %EnemyAttackHitbox
@onready var _hero_capsule_mesh: Array[MeshInstance3D] = [
	get_node("HeroCapsule/Superhero_Female_FullBody/Armature/Skeleton3D/Superhero_Female") as MeshInstance3D,
	get_node("HeroCapsule/Superhero_Female_FullBody/Armature/Skeleton3D/Eyebrows") as MeshInstance3D,
	get_node("HeroCapsule/Superhero_Female_FullBody/Armature/Skeleton3D/Eyes") as MeshInstance3D,
]
@onready var _enemy_capsule_mesh: Array[MeshInstance3D] = [
	get_node("EnemyCapsule/Superhero_Male_FullBody/Armature/Skeleton3D/SuperHero_Male") as MeshInstance3D,
	get_node("EnemyCapsule/Superhero_Male_FullBody/Armature/Skeleton3D/Eyebrows") as MeshInstance3D,
	get_node("EnemyCapsule/Superhero_Male_FullBody/Armature/Skeleton3D/Eyes") as MeshInstance3D,
]

var _attack_elapsed: float = -1.0
var _attack_active: bool = false
var _attack_hit: bool = false
var _attack_direction: Vector3 = Vector3.FORWARD
var _attack_is_heavy: bool = false
var _combo_index: int = 0
var _combo_buffered: bool = false
var _heavy_buffered: bool = false
var _combo_window_remaining: float = 0.0
var _dodge_elapsed: float = -1.0
var _dodge_cooldown_remaining: float = 0.0
var _parry_elapsed: float = -1.0
var _parry_succeeded: bool = false
var _parry_cooldown_remaining: float = 0.0
var _hit_stun_remaining: float = 0.0
var _hit_stop_remaining: float = 0.0
var _shake_remaining: float = 0.0
var _shake_duration: float = 0.0
var _shake_magnitude: float = 0.0
var _shake_enabled: bool = true
var _hit_stop_outcome: int = HitStopOutcome.NONE
var _enemy_attack_elapsed: float = -1.0
var _enemy_attack_active: bool = false
var _enemy_attack_hit: bool = false
var _enemy_attack_cooldown_remaining: float = 0.0
var _enemy_stagger_remaining: float = 0.0
var _enemy_state: EnemyState = EnemyState.MOVE
var _enemy_hp: float = 0.0
var _enemy_dodge_elapsed: float = -1.0
var _enemy_dodge_direction: Vector3 = Vector3.ZERO
var _enemy_dodge_cooldown_remaining: float = 0.0
var _enemy_parry_elapsed: float = -1.0
var _enemy_parry_cooldown_remaining: float = 0.0
var _hero: Hero
var _wave: Wave
var _maximum_hp: float = 0.0
var _hits_taken: int = 0
var _combat_finished: bool = false
var _result_return_remaining: float = 0.0
var _scene_change_requested: bool = false


func _ready() -> void:
	scene_change_requested.connect(SceneRouter.go_to)
	_create_capsule_material_override(_hero_capsule_mesh)
	_create_capsule_material_override(_enemy_capsule_mesh)
	_bind_hero_animation_libraries()
	_bind_enemy_animation_libraries()
	_spring_arm.spring_length = BALANCE.arena_camera_spring_length
	_spring_arm.add_excluded_object(_hero_capsule.get_rid())
	_attack_hitbox.body_entered.connect(_on_attack_hitbox_body_entered)
	_enemy_attack_hitbox.body_entered.connect(_on_enemy_attack_hitbox_body_entered)
	_enemy_hp = BALANCE.arena_enemy_max_hp
	# Read once on entry rather than per hit: the toggle lives in the hub's pause menu, which is not
	# reachable from inside the arena, so it cannot change while a fight is running.
	_shake_enabled = Settings.screen_shake_enabled()
	var entering_team: Array[Hero] = SceneRouter.arena_team.duplicate()
	var entering_wave: Wave = SceneRouter.arena_wave
	SceneRouter.clear_arena_payload()
	if not entering_team.is_empty() or entering_wave != null:
		_begin_combat(entering_team, entering_wave)
	var shape_node: CollisionShape3D = _attack_hitbox.get_node("CollisionShape3D") as CollisionShape3D
	var attack_shape: BoxShape3D = shape_node.shape.duplicate() as BoxShape3D
	assert(attack_shape != null)
	attack_shape.size.z = BALANCE.arena_light_attack_reach
	shape_node.shape = attack_shape
	shape_node.position.z = -BALANCE.arena_light_attack_reach * 0.5
	var enemy_shape_node: CollisionShape3D = _enemy_attack_hitbox.get_node("CollisionShape3D") as CollisionShape3D
	var enemy_attack_shape: BoxShape3D = enemy_shape_node.shape.duplicate() as BoxShape3D
	assert(enemy_attack_shape != null)
	enemy_attack_shape.size.z = BALANCE.arena_enemy_attack_reach
	enemy_shape_node.shape = enemy_attack_shape
	enemy_shape_node.position.z = -BALANCE.arena_enemy_attack_reach * 0.5
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	_update_capsule_tints()
	if _combat_finished:
		_stop_horizontal()
		_result_return_remaining = maxf(0.0, _result_return_remaining - delta)
		if _result_return_remaining <= 0.0:
			_request_hub()
			return
		_hero_capsule.move_and_slide()
		_play_hero_animation(&"ual1/Idle")
		_update_enemy_animation()
		_update_camera_pivot(delta)
		return
	if _hit_stop_remaining > 0.0:
		_update_hit_stop(delta)
	else:
		_update_enemy(delta)
		_update_dodge_cooldown(delta)
		_update_parry_cooldown(delta)
		_update_combo_window(delta)
		if _hit_stun_remaining > 0.0:
			_update_hit_stun(delta)
		elif _dodge_elapsed >= 0.0:
			_update_dodge(delta)
		elif _parry_elapsed >= 0.0:
			_update_parry(delta)
		elif _attack_elapsed >= 0.0:
			_update_attack(delta)
		else:
			_update_locomotion(delta)
	_update_hero_animation()
	_update_enemy_animation()
	_hero_capsule.move_and_slide()
	_update_camera_pivot(delta)


## Camera shake is the one impact channel that leaves the capsules alone, so it runs during hit-stop
## rather than being frozen by it - the freeze is what it is decorating.
func _update_camera_pivot(delta: float) -> void:
	var pivot_position: Vector3 = _hero_capsule.global_position + Vector3.UP
	if _shake_remaining > 0.0:
		_shake_remaining = maxf(0.0, _shake_remaining - delta)
		var amplitude: float = _shake_magnitude * _shake_remaining / _shake_duration
		var offset := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * amplitude
		pivot_position += _camera_pivot.global_basis * offset
	_camera_pivot.global_position = pivot_position


## Driven by the contact's own hit-stop, which is already the authored measure of how heavy that
## contact is - a parry shakes harder than a flinch without a second table saying so.
func _start_screen_shake(hit_stop: float) -> void:
	if not _shake_enabled:
		return
	_shake_duration = hit_stop * BALANCE.arena_screen_shake_duration_scale
	_shake_remaining = _shake_duration
	_shake_magnitude = hit_stop * BALANCE.arena_screen_shake_magnitude_scale


func _create_capsule_material_override(capsule_meshes: Array[MeshInstance3D]) -> void:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = _authored_capsule_color(capsule_meshes)
	for capsule_mesh: MeshInstance3D in capsule_meshes:
		capsule_mesh.material_override = material


func _update_capsule_tints() -> void:
	var hero_material: StandardMaterial3D = _hero_capsule_mesh[0].material_override as StandardMaterial3D
	assert(hero_material != null)
	hero_material.albedo_color = _hero_tint()
	if not is_instance_valid(_enemy_capsule):
		return
	var enemy_material: StandardMaterial3D = _enemy_capsule_mesh[0].material_override as StandardMaterial3D
	assert(enemy_material != null)
	enemy_material.albedo_color = _enemy_tint()


func _hero_tint() -> Color:
	if _hit_stop_outcome == HitStopOutcome.HIT_HERO or _hit_stun_remaining > 0.0:
		return HIT_HERO_COLOR
	if _hit_stop_outcome == HitStopOutcome.PARRY_HERO:
		return PARRY_HERO_COLOR
	if _hero_has_active_parry():
		return PARRY_WINDOW_COLOR
	return _authored_capsule_color(_hero_capsule_mesh)


func _enemy_tint() -> Color:
	if (
		_hit_stop_outcome == HitStopOutcome.FLINCH_ENEMY
		or _hit_stop_outcome == HitStopOutcome.DEFEAT_ENEMY
	):
		return DEFEAT_ENEMY_COLOR
	if (
		_hit_stop_outcome == HitStopOutcome.PARRY_HERO
		or _enemy_state == EnemyState.PARRY
		or _enemy_stagger_remaining > 0.0
	):
		return PARRY_HERO_COLOR
	if _enemy_attack_elapsed >= 0.0 and _enemy_attack_elapsed < BALANCE.arena_enemy_attack_startup:
		if _enemy_attack_elapsed >= BALANCE.arena_enemy_attack_startup - BALANCE.arena_enemy_telegraph_flash:
			return ENEMY_TELEGRAPH_COLOR
		return ENEMY_WINDUP_COLOR
	return _authored_capsule_color(_enemy_capsule_mesh)


func _authored_capsule_color(capsule_meshes: Array[MeshInstance3D]) -> Color:
	var authored_material: StandardMaterial3D = capsule_meshes[0].mesh.surface_get_material(0) as StandardMaterial3D
	assert(authored_material != null)
	return authored_material.albedo_color


func _bind_hero_animation_libraries() -> void:
	var animation_player: AnimationPlayer = get_node("HeroCapsule/HeroAnimationPlayer") as AnimationPlayer
	_bind_animation_libraries(animation_player)


func _bind_enemy_animation_libraries() -> void:
	var animation_player: AnimationPlayer = get_node("EnemyCapsule/EnemyAnimationPlayer") as AnimationPlayer
	_bind_animation_libraries(animation_player)


func _bind_animation_libraries(animation_player: AnimationPlayer) -> void:
	_add_animation_library(
		animation_player,
		&"ual1",
		"res://combat/arena/models/animations/UAL1_Standard.glb",
	)
	_add_animation_library(
		animation_player,
		&"ual2",
		"res://combat/arena/models/animations/UAL2_Standard.glb",
	)


func _add_animation_library(
	animation_player: AnimationPlayer,
	library_name: StringName,
	scene_path: String,
) -> void:
	var library_scene: PackedScene = load(scene_path) as PackedScene
	assert(library_scene != null)
	var library_instance: Node = library_scene.instantiate()
	var library_player: AnimationPlayer = library_instance.get_node("AnimationPlayer") as AnimationPlayer
	var library: AnimationLibrary = library_player.get_animation_library(&"")
	assert(library != null)
	# The call must sit outside the assert: Godot strips assert() expressions from release
	# builds, so wrapping it would leave the exported game with no character animations at all.
	var add_result: int = animation_player.add_animation_library(library_name, library)
	assert(add_result == OK)
	library_instance.free()


func _update_hero_animation() -> void:
	# Super armor keeps the smash's pose: the hit counts, it just does not cancel the swing. The
	# check is needed here as well as in _update_hit_stop() because HIT_HERO is registered on
	# contact and only resolved when the freeze ends, so the freeze frames would otherwise cut to
	# a reaction and then restart the swing from frame 0. _hit_stun_remaining needs no such guard:
	# an armored hit returns before it is ever set.
	if (_hit_stop_outcome == HitStopOutcome.HIT_HERO and not _hero_has_super_armor()) or _hit_stun_remaining > 0.0:
		_play_hero_animation(&"ual1/Hit_Chest")
		return
	if _dodge_elapsed >= 0.0:
		_play_hero_animation(&"ual1/Roll", BALANCE.arena_dodge_duration)
		return
	if _parry_elapsed >= 0.0:
		_play_hero_animation(&"ual2/Sword_Block")
		return
	if _attack_elapsed >= 0.0:
		if _attack_is_heavy:
			_play_hero_animation(
				&"ual2/Sword_Heavy_Combo",
				BALANCE.arena_heavy_attack_startup
				+ BALANCE.arena_heavy_attack_active
				+ BALANCE.arena_heavy_attack_recovery,
			)
			return
		var chain_clip: int = _combo_index % 3
		if chain_clip == 2:
			_play_hero_animation(
				&"ual2/Sword_Regular_C",
				BALANCE.arena_light_attack_startup
				+ BALANCE.arena_light_attack_active
				+ BALANCE.arena_light_attack_recovery,
			)
			return
		var in_recovery: bool = (
			_attack_elapsed >= BALANCE.arena_light_attack_startup + BALANCE.arena_light_attack_active
		)
		var suffix: StringName = &"B" if chain_clip == 1 else &"A"
		var animation_name := StringName("ual2/Sword_Regular_%s%s" % [suffix, "_Rec" if in_recovery else ""])
		var target_duration: float = (
			BALANCE.arena_light_attack_recovery
			if in_recovery
			else BALANCE.arena_light_attack_startup + BALANCE.arena_light_attack_active
		)
		_play_hero_animation(animation_name, target_duration)
		return
	var horizontal_speed := Vector2(_hero_capsule.velocity.x, _hero_capsule.velocity.z).length()
	if horizontal_speed > (BALANCE.arena_move_speed + BALANCE.arena_sprint_speed) * 0.5:
		_play_hero_animation(&"ual1/Sprint")
	elif horizontal_speed > 0.0:
		_play_hero_animation(&"ual1/Jog_Fwd")
	else:
		_play_hero_animation(&"ual1/Idle")


func _play_hero_animation(animation_name: StringName, target_duration: float = 0.0) -> void:
	var animation_player: AnimationPlayer = get_node("HeroCapsule/HeroAnimationPlayer") as AnimationPlayer
	_play_animation(animation_player, animation_name, target_duration)


func _update_enemy_animation() -> void:
	if not is_instance_valid(_enemy_capsule) or _enemy_capsule.is_queued_for_deletion():
		return
	if (
		_hit_stop_outcome == HitStopOutcome.PARRY_HERO
		or _enemy_state == EnemyState.STAGGER
	):
		_play_enemy_animation(&"ual1/Hit_Chest", BALANCE.arena_parry_enemy_stagger)
		return
	match _enemy_state:
		EnemyState.ATTACK:
			assert(_enemy_attack_elapsed >= 0.0)
			var active_end: float = (
				BALANCE.arena_enemy_attack_startup + BALANCE.arena_enemy_attack_active
			)
			if _enemy_attack_elapsed < active_end:
				_play_enemy_animation(&"ual2/Sword_Regular_A", active_end)
			else:
				_play_enemy_animation(
					&"ual2/Sword_Regular_A_Rec",
					BALANCE.arena_enemy_attack_recovery,
				)
		EnemyState.DODGE:
			_play_enemy_animation(&"ual1/Roll", BALANCE.arena_enemy_dodge_duration)
		EnemyState.PARRY:
			_play_enemy_animation(&"ual2/Sword_Block", BALANCE.arena_enemy_parry_active_window)
		EnemyState.MOVE:
			var horizontal_speed := Vector2(
				_enemy_capsule.velocity.x,
				_enemy_capsule.velocity.z,
			).length()
			_play_enemy_animation(&"ual1/Jog_Fwd" if horizontal_speed > 0.0 else &"ual1/Idle")


func _play_enemy_animation(animation_name: StringName, target_duration: float = 0.0) -> void:
	var animation_player: AnimationPlayer = get_node("EnemyCapsule/EnemyAnimationPlayer") as AnimationPlayer
	_play_animation(animation_player, animation_name, target_duration)


func _play_animation(
	animation_player: AnimationPlayer,
	animation_name: StringName,
	target_duration: float = 0.0,
) -> void:
	if animation_player.current_animation == animation_name:
		return
	var custom_speed: float = 1.0
	if target_duration > 0.0:
		var animation: Animation = animation_player.get_animation(animation_name)
		assert(animation != null)
		custom_speed = animation.length / target_duration
	animation_player.play(animation_name, -1.0, custom_speed)


func _update_locomotion(delta: float) -> void:
	var input_direction: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var move_direction: Vector3 = _camera_relative_direction(input_direction)
	var speed: float = BALANCE.arena_sprint_speed if Input.is_action_pressed(&"sprint") else BALANCE.arena_move_speed
	var target_velocity := Vector2(move_direction.x, move_direction.z) * speed
	var horizontal_velocity := Vector2(_hero_capsule.velocity.x, _hero_capsule.velocity.z)
	var rate: float = BALANCE.arena_acceleration if input_direction != Vector2.ZERO else BALANCE.arena_deceleration
	horizontal_velocity = horizontal_velocity.move_toward(target_velocity, rate * delta)
	_hero_capsule.velocity.x = horizontal_velocity.x
	_hero_capsule.velocity.z = horizontal_velocity.y

	_turn_hero(delta)


func _update_attack(delta: float) -> void:
	_attack_elapsed += delta
	var active: float = _attack_active_window()
	var active_end: float = _attack_startup() + active
	var recovery_end: float = active_end + _attack_recovery()

	if _attack_elapsed < _attack_startup():
		_turn_hero(delta)
		_stop_horizontal()
		return

	if _attack_elapsed < active_end:
		if not _attack_active:
			_attack_active = true
			_attack_direction = -_hero_capsule.global_basis.z.normalized()
			_try_start_enemy_reaction()
			_attack_hitbox.monitoring = true
		var attack_speed: float = _attack_displacement() / active
		_hero_capsule.velocity.x = _attack_direction.x * attack_speed
		_hero_capsule.velocity.z = _attack_direction.z * attack_speed
		return

	if _attack_active:
		_attack_active = false
		_attack_hitbox.monitoring = false
	_stop_horizontal()
	if _attack_elapsed < recovery_end:
		return
	# A smash consumes no buffer and takes no follow-up: it *is* the end of the chain, so its link
	# point returns to neutral rather than opening one.
	if not _attack_is_heavy:
		if _heavy_buffered:
			_begin_combo_attack(_next_chain_index(), true)
			return
		if _combo_buffered and _combo_index + 1 < BALANCE.arena_light_attack_combo_length:
			_begin_combo_attack(_combo_index + 1, false)
			return
	_attack_elapsed = -1.0
	_combo_buffered = false
	_heavy_buffered = false
	if _attack_is_heavy or _combo_index + 1 >= BALANCE.arena_light_attack_combo_length:
		_reset_combo_chain()
	else:
		_combo_window_remaining = BALANCE.arena_light_attack_combo_window


func _attack_startup() -> float:
	return BALANCE.arena_heavy_attack_startup if _attack_is_heavy else BALANCE.arena_light_attack_startup


func _attack_active_window() -> float:
	return BALANCE.arena_heavy_attack_active if _attack_is_heavy else BALANCE.arena_light_attack_active


func _attack_recovery() -> float:
	return BALANCE.arena_heavy_attack_recovery if _attack_is_heavy else BALANCE.arena_light_attack_recovery


func _attack_displacement() -> float:
	return BALANCE.arena_heavy_attack_displacement if _attack_is_heavy else BALANCE.arena_light_attack_displacement


## The smash occupies a chain step like any other hit, capped at the last one - a smash off a full
## five-hit chain still scales, it just cannot invent a sixth step.
func _next_chain_index() -> int:
	return mini(_combo_index + 1, BALANCE.arena_light_attack_combo_length - 1)


## Super armor, the one protection state the arena has: the smash trades a hit for its swing. The
## hit still counts against the hero, it just stops cancelling the attack.
func _hero_has_super_armor() -> bool:
	return (
		_attack_is_heavy
		and _attack_elapsed >= 0.0
		and _attack_elapsed < _attack_startup() + _attack_active_window()
	)


func _update_combo_window(delta: float) -> void:
	if _attack_elapsed >= 0.0 or _combo_window_remaining <= 0.0:
		return
	_combo_window_remaining = maxf(0.0, _combo_window_remaining - delta)
	if _combo_window_remaining <= 0.0:
		_reset_combo_chain()


func _update_dodge(delta: float) -> void:
	_dodge_elapsed += delta
	if _dodge_elapsed >= BALANCE.arena_dodge_duration:
		_dodge_elapsed = -1.0
		_dodge_cooldown_remaining = BALANCE.arena_dodge_cooldown
		_stop_horizontal()
		return
	var horizontal_velocity := Vector2(_hero_capsule.velocity.x, _hero_capsule.velocity.z)
	horizontal_velocity = horizontal_velocity.move_toward(
		Vector2.ZERO,
		BALANCE.arena_dodge_speed / BALANCE.arena_dodge_duration * delta,
	)
	_hero_capsule.velocity.x = horizontal_velocity.x
	_hero_capsule.velocity.z = horizontal_velocity.y


func _update_dodge_cooldown(delta: float) -> void:
	if _dodge_elapsed < 0.0:
		_dodge_cooldown_remaining = maxf(0.0, _dodge_cooldown_remaining - delta)


func _update_parry_cooldown(delta: float) -> void:
	if _parry_elapsed < 0.0:
		_parry_cooldown_remaining = maxf(0.0, _parry_cooldown_remaining - delta)


func _update_parry(delta: float) -> void:
	_parry_elapsed += delta
	var recovery: float = BALANCE.arena_parry_success_recovery if _parry_succeeded else BALANCE.arena_parry_whiff_recovery
	if _parry_elapsed >= BALANCE.arena_parry_startup + BALANCE.arena_parry_active_window + recovery:
		if _parry_succeeded:
			_parry_cooldown_remaining = BALANCE.arena_parry_cooldown
		_parry_elapsed = -1.0
		_parry_succeeded = false
		_stop_horizontal()


func _update_hit_stun(delta: float) -> void:
	_hit_stun_remaining = maxf(0.0, _hit_stun_remaining - delta)
	var horizontal_velocity := Vector2(_hero_capsule.velocity.x, _hero_capsule.velocity.z)
	horizontal_velocity = horizontal_velocity.move_toward(Vector2.ZERO, BALANCE.arena_deceleration * delta)
	_hero_capsule.velocity.x = horizontal_velocity.x
	_hero_capsule.velocity.z = horizontal_velocity.y


func _update_hit_stop(delta: float) -> void:
	_stop_horizontal()
	_hit_stop_remaining = maxf(0.0, _hit_stop_remaining - delta)
	if _hit_stop_remaining > 0.0:
		return
	if _hit_stop_outcome == HitStopOutcome.DEFEAT_ENEMY and is_instance_valid(_enemy_capsule):
		_enemy_capsule.queue_free()
		enemy_defeated.emit()
		_finish_combat()
	elif _hit_stop_outcome == HitStopOutcome.HIT_HERO:
		_hits_taken += 1
		var armored: bool = _hero_has_super_armor()
		if not armored:
			_cancel_player_action_for_hit()
		if _hits_taken >= BALANCE.arena_enemy_hits_to_kill_hero:
			_finish_combat()
			_hit_stop_outcome = HitStopOutcome.NONE
			return
		if armored:
			_hit_stop_outcome = HitStopOutcome.NONE
			return
		var knockback_direction: Vector3 = _hero_capsule.global_position - _enemy_capsule.global_position
		knockback_direction.y = 0.0
		assert(knockback_direction != Vector3.ZERO)
		knockback_direction = knockback_direction.normalized()
		_hero_capsule.velocity.x = knockback_direction.x * BALANCE.arena_enemy_knockback_speed
		_hero_capsule.velocity.z = knockback_direction.z * BALANCE.arena_enemy_knockback_speed
		_hit_stun_remaining = BALANCE.arena_enemy_hit_stun
	elif _hit_stop_outcome == HitStopOutcome.PARRY_HERO:
		_enemy_attack_elapsed = -1.0
		_enemy_attack_active = false
		_enemy_attack_hitbox.monitoring = false
		_enemy_stagger_remaining = BALANCE.arena_parry_enemy_stagger
		_enemy_state = EnemyState.STAGGER
	_hit_stop_outcome = HitStopOutcome.NONE


func _begin_combat(team: Array[Hero], wave: Wave) -> void:
	assert(team.size() == 1)
	assert(team[0] != null)
	assert(wave != null)
	var definition: HeroDefinition = Hero.definition_for(team[0].def_id)
	if definition == null:
		push_error("Arena cannot start without a valid HeroDefinition for '%s'." % team[0].hero_name)
		return
	var level: int = Hero.level_for(team[0], BALANCE)
	var stats: Dictionary[StringName, float] = Hero.compute_final_stats(
		team[0],
		definition,
		BALANCE,
		level,
	)
	_hero = team[0]
	_wave = wave
	_maximum_hp = stats[Hero.STAT_HP]


func resolve(team: Array[Hero], wave: Wave) -> CombatResult:
	assert(team.size() == 1)
	assert(team[0] == _hero)
	assert(wave == _wave)
	var result := CombatResult.new()
	var damage_fraction: float = clamp(
		float(_hits_taken) / float(BALANCE.arena_enemy_hits_to_kill_hero),
		0.0,
		1.0,
	)
	result.maximum_hp[_hero] = _maximum_hp
	result.hp_after[_hero] = _maximum_hp * (1.0 - damage_fraction)
	if _hits_taken >= BALANCE.arena_enemy_hits_to_kill_hero:
		result.dead_heroes.append(_hero)
	else:
		result.survivors.append(_hero)
	return result


func _finish_combat() -> void:
	if _hero == null or _combat_finished:
		return
	_combat_finished = true
	_result_return_remaining = BALANCE.arena_result_return_delay
	var team: Array[Hero] = [_hero]
	var result: CombatResult = resolve(team, _wave)
	SceneRouter.store_arena_result(result)
	combat_resolved.emit(result)


func _update_enemy(delta: float) -> void:
	if not is_instance_valid(_enemy_capsule):
		return
	if _enemy_state != EnemyState.DODGE:
		_enemy_dodge_cooldown_remaining = maxf(0.0, _enemy_dodge_cooldown_remaining - delta)
	if _enemy_state != EnemyState.PARRY:
		_enemy_parry_cooldown_remaining = maxf(0.0, _enemy_parry_cooldown_remaining - delta)
	_enemy_attack_cooldown_remaining = maxf(0.0, _enemy_attack_cooldown_remaining - delta)

	match _enemy_state:
		EnemyState.ATTACK:
			_update_enemy_attack(delta)
		EnemyState.DODGE:
			_update_enemy_dodge(delta)
		EnemyState.PARRY:
			_update_enemy_parry(delta)
		EnemyState.STAGGER:
			_update_enemy_stagger(delta)
		EnemyState.MOVE:
			_update_enemy_movement(delta)
	_enemy_capsule.move_and_slide()


func _update_enemy_movement(delta: float) -> void:
	_turn_enemy(delta)
	var offset: Vector3 = _hero_capsule.global_position - _enemy_capsule.global_position
	offset.y = 0.0
	var distance: float = offset.length()
	if (
		_enemy_attack_cooldown_remaining <= 0.0
		and distance <= BALANCE.arena_enemy_attack_trigger_range
	):
		_start_enemy_attack()
		return
	if distance == 0.0:
		_stop_enemy_horizontal()
		return
	var move_direction: Vector3 = offset / distance
	if distance > BALANCE.arena_enemy_preferred_range:
		_set_enemy_horizontal_velocity(move_direction * BALANCE.arena_enemy_move_speed)
	elif distance < BALANCE.arena_enemy_backoff_range:
		_set_enemy_horizontal_velocity(-move_direction * BALANCE.arena_enemy_move_speed)
	else:
		_stop_enemy_horizontal()


func _start_enemy_attack() -> void:
	_enemy_state = EnemyState.ATTACK
	_enemy_attack_elapsed = 0.0
	_enemy_attack_active = false
	_enemy_attack_hit = false
	_stop_enemy_horizontal()


func _update_enemy_attack(delta: float) -> void:
	_enemy_attack_elapsed += delta
	var active_end: float = BALANCE.arena_enemy_attack_startup + BALANCE.arena_enemy_attack_active
	var recovery_end: float = active_end + BALANCE.arena_enemy_attack_recovery
	if _enemy_attack_elapsed < BALANCE.arena_enemy_attack_startup:
		_turn_enemy(delta)
		return
	if _enemy_attack_elapsed < active_end:
		if not _enemy_attack_active:
			_enemy_attack_active = true
			_enemy_attack_hitbox.monitoring = true
		return
	if _enemy_attack_active:
		_enemy_attack_active = false
		_enemy_attack_hitbox.monitoring = false
	if _enemy_attack_elapsed >= recovery_end:
		_enemy_attack_elapsed = -1.0
		_enemy_attack_cooldown_remaining = BALANCE.arena_enemy_attack_cooldown
		_enemy_state = EnemyState.MOVE


func _update_enemy_dodge(delta: float) -> void:
	_enemy_dodge_elapsed += delta
	if _enemy_dodge_elapsed >= BALANCE.arena_enemy_dodge_duration:
		_enemy_dodge_elapsed = -1.0
		_enemy_dodge_cooldown_remaining = BALANCE.arena_enemy_dodge_cooldown
		_enemy_state = EnemyState.MOVE
		_stop_enemy_horizontal()
		return
	_set_enemy_horizontal_velocity(_enemy_dodge_direction * BALANCE.arena_enemy_dodge_speed)


func _update_enemy_parry(delta: float) -> void:
	_enemy_parry_elapsed += delta
	_stop_enemy_horizontal()
	if _enemy_parry_elapsed >= BALANCE.arena_enemy_parry_active_window:
		_enemy_parry_elapsed = -1.0
		_enemy_parry_cooldown_remaining = BALANCE.arena_enemy_parry_cooldown
		_enemy_state = EnemyState.MOVE


func _update_enemy_stagger(delta: float) -> void:
	_stop_enemy_horizontal()
	_enemy_stagger_remaining = maxf(0.0, _enemy_stagger_remaining - delta)
	if _enemy_stagger_remaining <= 0.0:
		_enemy_attack_cooldown_remaining = BALANCE.arena_enemy_attack_cooldown
		_enemy_state = EnemyState.MOVE


func _try_start_enemy_reaction() -> void:
	if _enemy_state != EnemyState.MOVE:
		return
	var offset: Vector3 = _hero_capsule.global_position - _enemy_capsule.global_position
	offset.y = 0.0
	var danger_range: float = BALANCE.arena_light_attack_reach + _attack_displacement()
	if offset.length() > danger_range:
		return
	if (
		_enemy_parry_cooldown_remaining <= 0.0
		and randf() < BALANCE.arena_enemy_parry_chance
	):
		_enemy_state = EnemyState.PARRY
		_enemy_parry_elapsed = 0.0
		_stop_enemy_horizontal()
		return
	if (
		_enemy_dodge_cooldown_remaining <= 0.0
		and randf() < BALANCE.arena_enemy_dodge_chance
	):
		var away_direction: Vector3 = -offset.normalized()
		if away_direction == Vector3.ZERO:
			away_direction = _enemy_capsule.global_basis.x.normalized()
		_enemy_state = EnemyState.DODGE
		_enemy_dodge_elapsed = 0.0
		_enemy_dodge_direction = away_direction
		_set_enemy_horizontal_velocity(_enemy_dodge_direction * BALANCE.arena_enemy_dodge_speed)


func _enemy_has_iframes() -> bool:
	return (
		_enemy_state == EnemyState.DODGE
		and _enemy_dodge_elapsed >= 0.0
		and _enemy_dodge_elapsed < BALANCE.arena_enemy_dodge_iframe_duration
	)


func _enemy_has_active_parry() -> bool:
	return (
		_enemy_state == EnemyState.PARRY
		and _enemy_parry_elapsed >= 0.0
		and _enemy_parry_elapsed < BALANCE.arena_enemy_parry_active_window
	)


func _set_enemy_horizontal_velocity(horizontal_velocity: Vector3) -> void:
	_enemy_capsule.velocity.x = horizontal_velocity.x
	_enemy_capsule.velocity.z = horizontal_velocity.z


func _stop_enemy_horizontal() -> void:
	_enemy_capsule.velocity.x = 0.0
	_enemy_capsule.velocity.z = 0.0


func _start_attack(is_heavy: bool) -> void:
	if _combat_finished or _enemy_hp <= 0.0:
		return
	if _attack_elapsed >= 0.0:
		if is_heavy:
			_heavy_buffered = true
		elif _combo_index + 1 < BALANCE.arena_light_attack_combo_length:
			_combo_buffered = true
		return
	if (
		_dodge_elapsed >= 0.0
		or (_parry_elapsed >= 0.0 and not _parry_succeeded)
		or _hit_stun_remaining > 0.0
		or _hit_stop_remaining > 0.0
	):
		return
	if _parry_elapsed >= 0.0:
		_parry_elapsed = -1.0
		_parry_succeeded = false
		_parry_cooldown_remaining = BALANCE.arena_parry_cooldown
	if _combo_window_remaining > 0.0:
		_begin_combo_attack(_next_chain_index(), is_heavy)
	else:
		_begin_combo_attack(0, is_heavy)


func _begin_combo_attack(combo_index: int, is_heavy: bool) -> void:
	assert(combo_index >= 0 and combo_index < BALANCE.arena_light_attack_combo_length)
	_combo_index = combo_index
	_attack_is_heavy = is_heavy
	_combo_buffered = false
	_heavy_buffered = false
	_combo_window_remaining = 0.0
	_attack_elapsed = 0.0
	_attack_active = false
	_attack_hit = false
	_stop_horizontal()


func _reset_combo_chain() -> void:
	_combo_index = 0
	_combo_buffered = false
	_heavy_buffered = false
	_combo_window_remaining = 0.0


func _start_dodge() -> void:
	if (
		_combat_finished
		or _dodge_elapsed >= 0.0
		or _parry_elapsed >= 0.0
		or _hit_stun_remaining > 0.0
		or _hit_stop_remaining > 0.0
	):
		return
	var input_direction: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	if input_direction == Vector2.ZERO:
		if _parry_cooldown_remaining <= 0.0:
			_start_parry()
		return
	if _dodge_cooldown_remaining > 0.0:
		return
	if _attack_elapsed >= 0.0:
		_attack_elapsed = -1.0
		_attack_active = false
		_attack_hitbox.monitoring = false
	var dodge_direction: Vector3 = _camera_relative_direction(input_direction)
	_reset_combo_chain()
	_dodge_elapsed = 0.0
	_hero_capsule.velocity.x = dodge_direction.x * BALANCE.arena_dodge_speed
	_hero_capsule.velocity.z = dodge_direction.z * BALANCE.arena_dodge_speed


func _start_parry() -> void:
	if _attack_elapsed >= 0.0:
		_attack_elapsed = -1.0
		_attack_active = false
		_attack_hitbox.monitoring = false
	_parry_elapsed = 0.0
	_parry_succeeded = false
	_stop_horizontal()


func _cancel_player_action_for_hit() -> void:
	if _dodge_elapsed >= 0.0:
		_dodge_cooldown_remaining = BALANCE.arena_dodge_cooldown
	_dodge_elapsed = -1.0
	_parry_elapsed = -1.0
	_parry_succeeded = false
	_attack_elapsed = -1.0
	_attack_active = false
	_attack_hitbox.monitoring = false
	_reset_combo_chain()


func _turn_hero(delta: float) -> void:
	var target_yaw: float = _camera_pivot.global_rotation.y
	_hero_capsule.rotation.y = rotate_toward(
		_hero_capsule.rotation.y,
		target_yaw,
		deg_to_rad(BALANCE.arena_turn_speed_degrees) * delta,
	)


func _turn_enemy(delta: float) -> void:
	var move_direction: Vector3 = _hero_capsule.global_position - _enemy_capsule.global_position
	move_direction.y = 0.0
	if move_direction == Vector3.ZERO:
		return
	move_direction = move_direction.normalized()
	var target_yaw := atan2(-move_direction.x, -move_direction.z)
	_enemy_capsule.rotation.y = rotate_toward(
		_enemy_capsule.rotation.y,
		target_yaw,
		deg_to_rad(BALANCE.arena_enemy_turn_speed_degrees) * delta,
	)


func _stop_horizontal() -> void:
	_hero_capsule.velocity.x = 0.0
	_hero_capsule.velocity.z = 0.0


func _on_attack_hitbox_body_entered(body: Node3D) -> void:
	if body != _enemy_capsule or not _attack_active or _attack_hit or _hit_stop_remaining > 0.0:
		return
	_attack_hit = true
	_attack_hitbox.set_deferred("monitoring", false)
	if _enemy_has_iframes():
		return
	var base_damage: float = BALANCE.arena_heavy_attack_damage if _attack_is_heavy else BALANCE.arena_light_attack_damage
	var damage: float = base_damage * (
		1.0 + BALANCE.arena_light_attack_combo_damage_step * float(_combo_index)
	)
	# Rear 180° of the enemy, by position rather than by swing angle - the enemy turns at 720°/s, so
	# this only pays out where its facing is locked: mid-swing, staggered, or dodged through.
	if (_hero_capsule.global_position - _enemy_capsule.global_position).dot(-_enemy_capsule.global_basis.z) < 0.0:
		damage *= BALANCE.arena_back_attack_damage_multiplier
	# The smash breaks the guard outright. Without one absolute counter, an enemy parry roll the
	# player cannot see coming is a pure tax on the chain.
	if _enemy_has_active_parry() and not _attack_is_heavy:
		damage *= 1.0 - BALANCE.arena_enemy_parry_damage_reduction
	_enemy_hp -= damage
	if _enemy_hp <= 0.0:
		_reset_combo_chain()
		_hit_stop_remaining = BALANCE.arena_heavy_attack_hit_stop if _attack_is_heavy else BALANCE.arena_light_attack_hit_stop
		_hit_stop_outcome = HitStopOutcome.DEFEAT_ENEMY
	else:
		_hit_stop_remaining = BALANCE.arena_heavy_attack_hit_stop if _attack_is_heavy else BALANCE.arena_enemy_hit_flinch_stop
		_hit_stop_outcome = HitStopOutcome.FLINCH_ENEMY
	_start_screen_shake(_hit_stop_remaining)


func _on_enemy_attack_hitbox_body_entered(body: Node3D) -> void:
	if (
		body != _hero_capsule
		or not _enemy_attack_active
		or _enemy_attack_hit
		or _hit_stop_remaining > 0.0
		or _hero_has_iframes()
	):
		return
	_enemy_attack_hit = true
	if _hero_has_active_parry():
		_parry_succeeded = true
		_hit_stop_remaining = BALANCE.arena_parry_hit_stop
		_hit_stop_outcome = HitStopOutcome.PARRY_HERO
	else:
		_hit_stop_remaining = BALANCE.arena_enemy_attack_hit_stop
		_hit_stop_outcome = HitStopOutcome.HIT_HERO
	_start_screen_shake(_hit_stop_remaining)
	_enemy_attack_hitbox.set_deferred("monitoring", false)


func _hero_has_iframes() -> bool:
	return _dodge_elapsed >= 0.0 and _dodge_elapsed < BALANCE.arena_dodge_iframe_duration


func _hero_has_active_parry() -> bool:
	return (
		_parry_elapsed >= BALANCE.arena_parry_startup
		and _parry_elapsed < BALANCE.arena_parry_startup + BALANCE.arena_parry_active_window
	)


func _camera_relative_direction(input_direction: Vector2) -> Vector3:
	if input_direction == Vector2.ZERO:
		return Vector3.ZERO
	var camera_forward := -_camera_pivot.global_basis.z
	camera_forward.y = 0.0
	camera_forward = camera_forward.normalized()
	var camera_right := _camera_pivot.global_basis.x
	camera_right.y = 0.0
	camera_right = camera_right.normalized()
	return (camera_right * input_direction.x - camera_forward * input_direction.y).normalized()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mouse_motion := event as InputEventMouseMotion
		_camera_pivot.rotation.y = wrapf(
			_camera_pivot.rotation.y - mouse_motion.screen_relative.x * BALANCE.arena_mouse_sensitivity,
			-PI,
			PI,
		)
		_camera_pivot.rotation.x = clampf(
			_camera_pivot.rotation.x - mouse_motion.screen_relative.y * BALANCE.arena_mouse_sensitivity,
			-deg_to_rad(BALANCE.arena_camera_pitch_down_degrees),
			deg_to_rad(BALANCE.arena_camera_pitch_up_degrees),
		)
		return
	if event.is_action_pressed(&"attack"):
		get_viewport().set_input_as_handled()
		_start_attack(false)
		return
	if event.is_action_pressed(&"heavy_attack"):
		get_viewport().set_input_as_handled()
		_start_attack(true)
		return
	if event.is_action_pressed(&"dodge"):
		get_viewport().set_input_as_handled()
		_start_dodge()
		return
	if not event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_request_hub()


## The only way out of the arena. Fires once, and stops physics before it does: the scene swap is
## deferred, so `_physics_process` otherwise keeps ticking for a few frames against a `HeroCapsule`
## already removed from the tree, and `move_and_slide()` errors out with no space to move in.
func _request_hub() -> void:
	if _scene_change_requested:
		return
	_scene_change_requested = true
	set_physics_process(false)
	scene_change_requested.emit(SceneRouter.HUB)
