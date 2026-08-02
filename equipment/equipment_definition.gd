class_name EquipmentDefinition
extends Resource

enum Slot { HEAD, CHEST, LEGS, GLOVES, BOOTS, MAIN_HAND, OFF_HAND, NECKLACE, RING, BELT }
enum PrimaryStat { HP, ATK, DEF, SPD, CRIT_RATE, CRIT_DMG }

@export var slot: Slot = Slot.HEAD
@export var primary_stat: PrimaryStat = PrimaryStat.HP
@export var display_name: String = ""
