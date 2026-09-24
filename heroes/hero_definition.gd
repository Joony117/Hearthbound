class_name HeroDefinition
extends Resource

@export var display_name: String = ""
@export var role: String = ""
@export var base_hp: float = 0.0
@export var hp_growth: float = 0.0
@export var base_atk: float = 0.0
@export var atk_growth: float = 0.0
@export var base_def: float = 0.0
@export var def_growth: float = 0.0
@export var base_spd: float = 0.0
@export var spd_growth: float = 0.0
@export var crit_rate: float = 0.0
@export var crit_dmg: float = 0.0
@export var battle_ability: AbilityDefinition
@export var resonance_trait_pool: Array[TraitDefinition] = [] # Unlock order keeps resonance thresholds data-only.
@export var instructor_trait_pool: Array[TraitDefinition] = [] # Separate so instructor-only traits cannot enter resonance rewards.
