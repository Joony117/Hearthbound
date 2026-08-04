class_name BalanceTable
extends Resource

@export var stat_multipliers: Array[float] = [1.00, 1.35, 1.82, 2.46, 3.32, 4.48, 6.05, 8.17]
@export var level_caps: Array[int] = [10, 20, 30, 40, 50, 60, 70, 80]
@export var equipment_affix_counts: Array[int] = [1, 1, 2, 2, 3, 3, 4, 4]
@export var core_socket_counts: Array[int] = [0, 0, 0, 0, 1, 1, 2, 2]
@export var essence_bases: Array[int] = [10, 25, 65, 165, 420, 1050, 2600, 6500]
@export var rank_up_essence_costs: Array[int] = [40, 110, 300, 800, 2200, 6000, 16000]
@export var summon_weights: Array[int] = [4000, 2700, 1700, 1000, 450, 120, 28, 2]
@export var rank_names: PackedStringArray = ["F", "D", "C", "B", "A", "S", "SS", "SSS"]

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
