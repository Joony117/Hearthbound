class_name HeroModel
extends RefCounted

## The KayKit hero and skeleton models, armed, with one shared clip library. Battle units draw
## with it today and town heroes will; neither reaches into the other. Static only: the one piece
## of state is the shared AnimationLibrary.

const MODEL_DIR: String = "res://combat/battle/models/kaykit/"
# Per archetype: [character, {hand bone: weapon}, attack clip].
const ALLY_LOOKS: Dictionary = {
	"knight": ["Knight", {"handslot.r": "sword_1handed", "handslot.l": "shield_round"}, "Melee_1H_Attack_Chop"],
	"mage": ["Mage", {"handslot.r": "staff"}, "Ranged_Magic_Shoot"],
	"ranger": ["Ranger", {"handslot.l": "bow_withString"}, "Ranged_Bow_Release"],
	"rogue": ["Rogue", {"handslot.r": "dagger", "handslot.l": "dagger"}, "Melee_Dualwield_Attack_Stab"],
	"cleric": ["Mage", {"handslot.r": "wand"}, "Ranged_Magic_Shoot"],
}
const ENEMY_LOOKS: Dictionary = {
	"knight": ["Skeleton_Warrior", {"handslot.r": "Skeleton_Blade", "handslot.l": "Skeleton_Shield_Small_A"}, "Melee_1H_Attack_Chop"],
	"rogue": ["Skeleton_Rogue", {"handslot.r": "Skeleton_Blade"}, "Melee_Dualwield_Attack_Stab"],
	"mage": ["Skeleton_Mage", {"handslot.r": "Skeleton_Staff"}, "Ranged_Magic_Shoot"],
	"ranger": ["Skeleton_Rogue", {"handslot.r": "Skeleton_Crossbow"}, "Ranged_1H_Shoot"],
}
const LOOPED_CLIPS: Array[String] = ["Idle_A", "Idle_B", "Running_A", "Walking_A", "Skeletons_Idle", "Skeletons_Walking"]
# Clip file under animations/Rig_Medium_<file>.glb for every clip in the library.
const CLIP_FILES: Dictionary = {
	"Idle_A": "General", "Hit_A": "General", "Hit_B": "General", "Death_A": "General", "Death_B": "General",
	"Running_A": "MovementBasic",
	"Melee_1H_Attack_Chop": "CombatMelee", "Melee_Dualwield_Attack_Stab": "CombatMelee",
	"Ranged_Bow_Release": "CombatRanged", "Ranged_1H_Shoot": "CombatRanged", "Ranged_Magic_Shoot": "CombatRanged",
	"Skeletons_Idle": "Special", "Skeletons_Walking": "Special", "Skeletons_Death": "Special",
	# Town: strolling and using stalls.
	"Walking_A": "MovementBasic", "Idle_B": "General", "Interact": "General", "PickUp": "General", "Use_Item": "General",
}
const ROOT_POSITION_TRACK: NodePath = NodePath("Rig_Medium/Skeleton3D:root")

static var _clip_library: AnimationLibrary


## The look for this faction and archetype; an unknown archetype draws as the knight.
static func look(faction: String, archetype: String) -> Array:
	var looks: Dictionary = ALLY_LOOKS if faction == "ally" else ENEMY_LOOKS
	return looks.get(archetype, looks["knight"])


## The model with its weapons on the hand bones and an AnimationPlayer (child "AnimationPlayer",
## root_node "..") carrying the shared library. The caller parents and scales it.
static func build(faction: String, archetype: String) -> Node3D:
	if not (ALLY_LOOKS if faction == "ally" else ENEMY_LOOKS).has(archetype):
		push_warning("No %s look for archetype '%s'; drawing the knight." % [faction, archetype])
	var chosen: Array = look(faction, archetype)
	var model: Node3D = (load(MODEL_DIR + "characters/%s.glb" % chosen[0]) as PackedScene).instantiate() as Node3D
	attach_weapons(model.get_node("Rig_Medium/Skeleton3D") as Skeleton3D, chosen[1])
	var animator := AnimationPlayer.new()
	animator.name = "AnimationPlayer"
	model.add_child(animator)
	animator.root_node = NodePath("..")
	animator.add_animation_library("", shared_clips())
	return model


## A weapon on a bone the skeleton lacks would float at the model's origin, so it is refused loudly.
static func attach_weapons(skeleton: Skeleton3D, weapons: Dictionary) -> void:
	for bone: String in weapons:
		if skeleton.find_bone(bone) < 0:
			push_error("The skeleton has no bone '%s' for weapon '%s'." % [bone, weapons[bone]])
			continue
		var slot := BoneAttachment3D.new()
		slot.bone_name = bone
		skeleton.add_child(slot)
		slot.add_child((load(MODEL_DIR + "weapons/%s.gltf" % weapons[bone]) as PackedScene).instantiate())


## Clips are copied out of the Rig_Medium files once: loops set, root motion pinned.
## Every model plays from this one library, so callers must not mutate it.
static func shared_clips() -> AnimationLibrary:
	if _clip_library != null:
		return _clip_library
	var library := AnimationLibrary.new()
	var sources: Dictionary = {}
	for clip: String in CLIP_FILES:
		var file: String = CLIP_FILES[clip]
		if not sources.has(file):
			sources[file] = (load(MODEL_DIR + "animations/Rig_Medium_%s.glb" % file) as PackedScene).instantiate()
		var player: AnimationPlayer = (sources[file] as Node).find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		var animation: Animation = player.get_animation(clip).duplicate(true) as Animation
		animation.loop_mode = Animation.LOOP_LINEAR if clip in LOOPED_CLIPS else Animation.LOOP_NONE
		# Skeletons_Death slides the root bone 0.7 back; the fling already moves the corpse, and
		# town movement is driven by code, so every clip plays in place.
		var root_track: int = animation.find_track(ROOT_POSITION_TRACK, Animation.TYPE_POSITION_3D)
		if root_track >= 0:
			animation.remove_track(root_track)
		library.add_animation(clip, animation)
	for scene: Node in sources.values():
		scene.free()
	# Published only once complete, so a build that dies mid-loop leaves nothing half-built behind.
	_clip_library = library
	return _clip_library
