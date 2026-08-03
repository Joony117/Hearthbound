class_name CombatResult
extends RefCounted

var survivors: Array[Hero] = []
var hp_after: Dictionary[Hero, float] = {}
var maximum_hp: Dictionary[Hero, float] = {}
var dead_heroes: Array[Hero] = []
var loot_seed: int = 0
