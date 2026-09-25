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
# Class odds (SYSTEMS.md § Summoning, Class odds): of 300, in Summon.ARCHETYPE_DEF_IDS order.
@export var summon_archetype_weights: Array[int] = [98, 98, 98, 3, 3]
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
@export var arena_screen_shake_magnitude_scale: float = 0.4
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
# Without a master smith home, the enhance cap stops here; +13 to +15 is masterwork (SYSTEMS.md § Keepers and professions).
@export var forge_masterwork_floor: int = 12
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
# A home keeper's skill counts as this many building levels each, past the building cap (SYSTEMS.md § Keepers and professions).
@export var keeper_skill_bonus_levels: float = 0.5
# The Apothecary has no level: each Alchemy skill level cuts the draught parts cost by this share.
@export var alchemy_cost_cut_per_skill: float = 0.10

@export var battle_tick_seconds: float = 0.1
## ig-1jw (SYSTEMS.md § Battle pace): P. HP, ability cooldowns and amounts, ability statuses, holds, the
## combat bound, the route, rewards and the recovery lifetime are xP. A battle keeps the pace it spawned
## with (BattleState.pace).
@export var battle_pace: int = 6
@export var battle_damage_defense_scale: float = 100.0
@export var battle_basic_interval_numerator: float = 100.0
@export var battle_basic_interval_min: float = 0.3
@export var battle_basic_interval_max: float = 3.0
@export var battle_move_speed_per_stat: float = 0.04
@export var battle_move_speed_min: float = 1.5
@export var battle_move_speed_max: float = 5.0
@export var battle_melee_range: float = 1.6
@export var battle_ranged_range: float = 8.0
## Owner ruling 2026-09-24: our ranged heroes stand farther back than enemy ones.
@export var battle_ally_ranged_range: float = 12.0
@export var battle_attack_windup_seconds: float = 0.3
@export var battle_formation_spacing: float = 1.8
@export var battle_separation_radius: float = 0.65
@export var battle_guard_radius: float = 4.0
@export var battle_cohesion_wait_distance: float = 6.0
@export var battle_cohesion_regroup_distance: float = 4.0
@export var battle_detection_range: float = 12.0
@export var battle_enemy_leash_range: float = 18.0
## A Knight hit on an enemy targeting a back-row ally taunts it this long (ig-uu7.2, PROVISIONAL in SYSTEMS).
@export var battle_cover_taunt_seconds: float = 3.0
## Kiting (ig-uu7.3, PROVISIONAL in SYSTEMS): a back-row hero hops when an enemy on it comes this close,
## at most this far, then waits this long before the next hop.
@export var battle_kite_trigger_range: float = 3.0
@export var battle_kite_distance: float = 4.0
@export var battle_kite_cooldown_seconds: float = 5.0
@export var battle_enemy_hp_budget_multiplier: float = 1.15
@export var battle_enemy_atk_budget_multiplier: float = 0.03
@export var battle_enemy_def_budget_multiplier: float = 0.1
@export var battle_enemy_speed: float = 20.0
@export var battle_enemy_crit_rate: float = 0.05
@export var battle_enemy_crit_damage: float = 1.5
@export var battle_enemy_telegraph_seconds: float = 0.8
@export var battle_item_cooldown_seconds: float = 15.0
@export var battle_healing_fraction: float = 0.4
@export var battle_revival_fraction: float = 0.35
# Masterwork draughts: only a master alchemist brews them (SYSTEMS.md § Keepers and professions, unplayed).
@export var battle_healing_masterwork_fraction: float = 0.6
@export var battle_revival_masterwork_fraction: float = 0.5
@export var battle_revival_range: float = 3.0
@export var battle_carry_range: float = 1.5
# Knockback (SYSTEMS.md § Knockback): a basic crit pushes its target this far, unless the target's
# previous crit is under the gate's ticks old.
@export var battle_crit_push_units: float = 0.5
@export var battle_crit_push_gate_ticks: int = 30
@export var battle_carry_seconds: float = 1.0
@export var battle_carry_speed_fraction: float = 0.65
@export var battle_exit_radius: float = 2.0
@export var battle_supply_allocation_cap: int = 100
@export var healing_supply_parts_cost: int = 5
@export var revival_supply_parts_cost: int = 15
@export var healing_masterwork_supply_parts_cost: int = 15
@export var revival_masterwork_supply_parts_cost: int = 45
# Town builder, first slice (SYSTEMS.md § Town builder; every row there is PROVISIONAL, unplayed).
@export var town_map_radius: int = 8
@export var town_start_wood: float = 40.0
@export var house_wood_cost: int = 10
@export var house_capacity: int = 1
@export var lumbermill_wood_cost: int = 20
@export var lumbermill_worker_slots: int = 2
@export var wood_per_worker_minute: float = 1.0
# The Mine and stone (SYSTEMS.md § Stone and construction).
@export var mine_wood_cost: int = 20
@export var mine_worker_slots: int = 2
@export var stone_per_worker_minute: float = 0.5
# Construction (SYSTEMS.md § Stone and construction): live-play seconds to go up.
@export var house_build_seconds: float = 60.0
@export var workplace_build_seconds: float = 120.0
# Hall upgrades (SYSTEMS.md § Hall upgrades cost wood and stone): level n to n+1 costs this times n+1.
@export var hall_upgrade_wood_per_level: int = 20
@export var hall_upgrade_stone_per_level: int = 10
# Farms and food (SYSTEMS.md § Food and starvation; every row PROVISIONAL).
@export var town_start_food: float = 30.0
@export var food_per_housed_hero_minute: float = 0.2
@export var farm_wood_cost: int = 20
@export var farm_worker_slots: int = 2
@export var food_per_worker_minute: float = 1.0
# Starvation (SYSTEMS.md § Food and starvation; every row PROVISIONAL).
@export var food_low_warning_minutes: float = 10.0
@export var starving_work_multiplier: float = 0.5
@export var starve_first_death_minutes: float = 20.0
@export var starve_next_death_minutes: float = 10.0
@export var starve_last_warning_minutes: float = 5.0
# The Ledger (SYSTEMS.md § The Ledger; both caps PROVISIONAL).
@export var ledger_max_records: int = 10000
@export var battle_max_moments: int = 64
# Caster zones (SYSTEMS.md § Casters, Zones; PROVISIONAL).
@export var battle_field_object_cap: int = 8
# Skills (SYSTEMS.md § Skills, shared rules; PROVISIONAL).
@export var skill_ability_lock_seconds: float = 1.0
@export var skill_combo_window_seconds: float = 6.0
@export var skill_reaction_delay_seconds: float = 0.2
@export var skill_status_tick_seconds: float = 1.0
# Bonds and dreams, slice 1 (SYSTEMS.md § Bonds and dreams, slice 1; every row PROVISIONAL).
@export var bond_points_hard_battle: int = 1
@export var bond_points_saved: int = 3
@export var bond_points_rescued: int = 5
@export var bond_points_death_witnessed: int = 5
@export var bond_threshold: int = 8
@export var dream_fight_beside_battles: int = 3
# SYSTEMS.md § Casters: a Mage's or Cleric's HP, ATK and DEF x stat_multipliers[1]^this.
@export var caster_rank_offset: float = 0.0
