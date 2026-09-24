class_name BalanceTable
extends Resource

@export var stat_multipliers: Array[float] = [1.00, 1.35, 1.82, 2.46, 3.32, 4.48, 6.05, 8.17]
@export var level_caps: Array[int] = [10, 20, 30, 40, 50, 60, 70, 80]
@export var equipment_affix_counts: Array[int] = [1, 1, 2, 2, 3, 3, 4, 4]
@export var core_socket_counts: Array[int] = [0, 0, 0, 0, 1, 1, 2, 2]
@export var essence_bases: Array[int] = [10, 25, 65, 165, 420, 1050, 2600, 6500]
@export var rank_up_essence_costs: Array[int] = [40, 110, 300, 800, 2200, 6000, 16000]
@export var resonance_trait_thresholds: Array[int] = [1, 3, 6]
@export var summon_weights: Array[int] = [4000, 2700, 1700, 1000, 450, 120, 28, 2]
@export var summon_pull_cost: int = 100
@export var xp_coefficient: int = 10
@export var xp_per_wave: int = 4
@export var arena_move_speed: float = 5.8
@export var arena_sprint_speed: float = 8.0
@export var arena_acceleration: float = 42.0
@export var arena_deceleration: float = 65.0
@export var arena_turn_speed_degrees: float = 1200.0
@export var arena_mouse_sensitivity: float = 0.003
@export var arena_camera_spring_length: float = 4.0
@export var arena_camera_pitch_up_degrees: float = 35.0
@export var arena_camera_pitch_down_degrees: float = 65.0
@export var arena_light_attack_startup: float = 0.10
@export var arena_light_attack_active: float = 0.10
@export var arena_light_attack_recovery: float = 0.22
@export var arena_light_attack_displacement: float = 2.0
@export var arena_light_attack_reach: float = 1.5
@export var arena_light_attack_hit_stop: float = 0.04
@export var arena_light_attack_combo_length: int = 5
@export var arena_light_attack_combo_window: float = 0.25
@export var arena_light_attack_damage: float = 20.0
@export var arena_light_attack_combo_damage_step: float = 0.15
@export var arena_heavy_attack_startup: float = 0.30
@export var arena_heavy_attack_active: float = 0.12
@export var arena_heavy_attack_recovery: float = 0.50
@export var arena_heavy_attack_displacement: float = 3.0
@export var arena_heavy_attack_hit_stop: float = 0.09
@export var arena_heavy_attack_damage: float = 45.0
@export var arena_back_attack_damage_multiplier: float = 1.5
@export var arena_enemy_telegraph_flash: float = 0.2
@export var arena_enemy_max_hp: float = 120.0
@export var arena_enemy_hit_flinch_stop: float = 0.05
## One landed hit in ten staggers the enemy outright instead of only freezing the frame.
@export var arena_enemy_big_hit_chance: float = 0.1
## The Mixamo reaction clip is 1.30 s and gets compressed into this. Three light attacks fit in
## 1.26 s, so playing it at its authored length would hand over a free chain for a coin flip that
## the player did not earn; 0.9 s reads as a real stagger and fits two.
@export var arena_enemy_big_hit_stagger: float = 0.9
@export var arena_enemy_move_speed: float = 4.2
@export var arena_enemy_preferred_range: float = 2.4
@export var arena_enemy_backoff_range: float = 1.6
@export var arena_enemy_dodge_chance: float = 0.35
@export var arena_enemy_dodge_speed: float = 11.0
@export var arena_enemy_dodge_duration: float = 0.32
@export var arena_enemy_dodge_iframe_duration: float = 0.22
@export var arena_enemy_dodge_cooldown: float = 1.2
@export var arena_enemy_parry_chance: float = 0.25
@export var arena_enemy_parry_active_window: float = 0.2
@export var arena_enemy_parry_cooldown: float = 1.6
@export var arena_enemy_parry_damage_reduction: float = 0.6
## Screen shake is derived from the hit-stop already authored for each contact type rather than
## from its own per-outcome table: hit-stop length is the project's existing encoding of hit weight
## (0.04 light, 0.05 flinch, 0.06 enemy hit, 0.08 parry), so scaling off it keeps the two channels
## from drifting apart. Metres of camera offset, and seconds of shake, per second of hit-stop.
@export var arena_screen_shake_magnitude_scale: float = 1.6
@export var arena_screen_shake_duration_scale: float = 3.0
@export var arena_enemy_attack_startup: float = 0.55
## The played-build P2b-12 ruling locks enemy facing partway through attack startup so a lateral dodge can escape.
@export var arena_enemy_attack_facing_lock: float = 0.36
@export var arena_enemy_attack_active: float = 0.10
@export var arena_enemy_attack_recovery: float = 0.45
@export var arena_enemy_attack_reach: float = 1.6
@export var arena_enemy_attack_trigger_range: float = 3.0
@export var arena_enemy_attack_cooldown: float = 0.6
@export var arena_enemy_turn_speed_degrees: float = 720.0
@export var arena_enemy_attack_hit_stop: float = 0.06
@export var arena_enemy_knockback_speed: float = 6.0
@export var arena_enemy_hit_stun: float = 0.35
@export var arena_enemy_hits_to_kill_hero: int = 3
@export var arena_result_return_delay: float = 1.0
@export var arena_dodge_speed: float = 13.5
@export var arena_dodge_duration: float = 0.38
@export var arena_dodge_iframe_duration: float = 0.25
@export var arena_dodge_cooldown: float = 0.15
@export var arena_parry_startup: float = 0.0
@export var arena_parry_active_window: float = 0.30
@export var arena_parry_whiff_recovery: float = 0.35
@export var arena_parry_success_recovery: float = 0.10
@export var arena_parry_cooldown: float = 0.15
@export var arena_parry_hit_stop: float = 0.08
@export var arena_parry_enemy_stagger: float = 0.6
@export var rank_names: PackedStringArray = ["F", "D", "C", "B", "A", "S", "SS", "SSS"]
@export var equip_pct_per_rank: Array[float] = [0.04, 0.054, 0.0728, 0.0984, 0.1328, 0.1792, 0.242, 0.3268]
@export var equip_crit_pct_per_rank: Array[float] = [0.015, 0.02025, 0.0273, 0.0369, 0.0498, 0.0672, 0.09075, 0.12255]
@export var equip_crit_rate_cap: float = 0.75
@export var enhance_pct_per_level: float = 0.08

@export var summoning_circle_multiplier_per_level: float = 0.15
@export var wave_damage_coefficient: float = 0.35
@export var wave_loss_damage_coefficient: float = 1.0
@export var summoning_circle_level_cap: int = 5
@export var forge_enhance_cap_per_level: int = 3
@export var forge_enhance_cap_max: int = 15
@export var forge_salvage_yield_bonus: float = 0.10
@export var training_hall_xp_bonus: float = 0.15
@export var sanctum_essence_yield_bonus: float = 0.10
@export var reliquary_decay_turns_bonus: int = 5
@export var reliquary_damage_chance_reduction: float = 0.03
@export var recovery_base_duration_seconds: float = 900.0
@export var recovery_duration_seconds_per_level: float = 300.0
# Profession skill level k costs k * this many minutes of XP (SYSTEMS.md § Keepers and professions).
@export var profession_xp_minutes_per_level: float = 20.0
@export var profession_skill_cap: int = 5
# XP from working in either of a hero's passions; the owner's "immense XP boost", near a RimWorld major passion.
@export var passion_xp_multiplier: float = 4.0

@export var battle_tick_seconds: float = 0.1
@export var battle_damage_defense_scale: float = 100.0
@export var battle_basic_interval_numerator: float = 100.0
@export var battle_basic_interval_min: float = 0.3
@export var battle_basic_interval_max: float = 3.0
@export var battle_move_speed_per_stat: float = 0.04
@export var battle_move_speed_min: float = 1.5
@export var battle_move_speed_max: float = 5.0
@export var battle_melee_range: float = 1.6
@export var battle_ranged_range: float = 8.0
@export var battle_attack_windup_seconds: float = 0.3
@export var battle_formation_spacing: float = 1.8
@export var battle_separation_radius: float = 0.65
@export var battle_guard_radius: float = 4.0
@export var battle_cohesion_wait_distance: float = 6.0
@export var battle_cohesion_regroup_distance: float = 4.0
@export var battle_detection_range: float = 12.0
@export var battle_enemy_leash_range: float = 18.0
@export var battle_enemy_hp_budget_multiplier: float = 1.0
@export var battle_enemy_atk_budget_multiplier: float = 0.04
@export var battle_enemy_def_budget_multiplier: float = 0.1
@export var battle_enemy_speed: float = 20.0
@export var battle_enemy_crit_rate: float = 0.05
@export var battle_enemy_crit_damage: float = 1.5
@export var battle_enemy_telegraph_seconds: float = 0.8
@export var battle_item_cooldown_seconds: float = 15.0
@export var battle_healing_fraction: float = 0.4
@export var battle_revival_fraction: float = 0.35
@export var battle_revival_range: float = 3.0
@export var battle_carry_range: float = 1.5
@export var battle_carry_seconds: float = 1.0
@export var battle_carry_speed_fraction: float = 0.65
@export var battle_exit_radius: float = 2.0
@export var battle_supply_allocation_cap: int = 100
@export var healing_supply_parts_cost: int = 5
@export var revival_supply_parts_cost: int = 15
