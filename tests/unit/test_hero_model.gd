extends GutTest


func test_every_look_loads_its_model_with_every_weapon_on_a_real_bone() -> void:
	for faction: String in ["ally", "enemy"]:
		var looks: Dictionary = HeroModel.ALLY_LOOKS if faction == "ally" else HeroModel.ENEMY_LOOKS
		for archetype: String in looks:
			var model: Node3D = HeroModel.build(faction, archetype)
			add_child_autofree(model)
			assert_eq(model.scene_file_path, "%scharacters/%s.glb" % [HeroModel.MODEL_DIR, looks[archetype][0]], "%s %s model" % [faction, archetype])
			# Skeleton models ship their own attachment nodes; only the ones holding a weapon scene count.
			var slots: Array[Node] = model.find_children("*", "BoneAttachment3D", true, false).filter(
				func(slot: Node) -> bool: return slot.get_child_count() > 0 and not slot.get_child(0).scene_file_path.is_empty())
			assert_eq(slots.size(), (looks[archetype][1] as Dictionary).size(), "%s %s holds every weapon" % [faction, archetype])
			for slot: Node in slots:
				assert_gt((slot as BoneAttachment3D).bone_idx, -1, "%s %s %s is a real bone" % [faction, archetype, (slot as BoneAttachment3D).bone_name])
			var animator: AnimationPlayer = model.get_node("AnimationPlayer") as AnimationPlayer
			assert_eq(animator.root_node, NodePath(".."))
			assert_true(animator.has_animation(looks[archetype][2]), "%s %s has its attack clip" % [faction, archetype])


func test_every_model_shares_one_clip_library() -> void:
	var knight: Node3D = autofree(HeroModel.build("ally", "knight"))
	var skeleton: Node3D = autofree(HeroModel.build("enemy", "mage"))
	var library: AnimationLibrary = (knight.get_node("AnimationPlayer") as AnimationPlayer).get_animation_library(&"")
	assert_same(library, (skeleton.get_node("AnimationPlayer") as AnimationPlayer).get_animation_library(&""))
	assert_same(library, HeroModel.shared_clips())


func test_the_library_holds_every_clip_in_place_with_walks_and_idles_looping() -> void:
	var library: AnimationLibrary = HeroModel.shared_clips()
	for clip: String in HeroModel.CLIP_FILES:
		assert_true(library.has_animation(clip), "%s is in the library" % clip)
		var animation: Animation = library.get_animation(clip)
		assert_eq(animation.loop_mode == Animation.LOOP_LINEAR, clip in HeroModel.LOOPED_CLIPS, "%s loop mode" % clip)
		assert_eq(animation.find_track(HeroModel.ROOT_POSITION_TRACK, Animation.TYPE_POSITION_3D), -1, "%s plays in place" % clip)
	for clip: String in ["Walking_A", "Idle_A", "Idle_B", "Running_A", "Skeletons_Idle", "Skeletons_Walking"]:
		assert_eq(library.get_animation(clip).loop_mode, Animation.LOOP_LINEAR, "%s loops" % clip)
	for clip: String in ["Interact", "PickUp", "Use_Item", "Death_A", "Death_B", "Hit_A", "Skeletons_Death"]:
		assert_eq(library.get_animation(clip).loop_mode, Animation.LOOP_NONE, "%s plays once" % clip)


func test_the_pin_removes_a_root_track_the_source_death_clip_really_has() -> void:
	var source: Node = (load(HeroModel.MODEL_DIR + "animations/Rig_Medium_Special.glb") as PackedScene).instantiate()
	var player: AnimationPlayer = source.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	assert_gt(player.get_animation(&"Skeletons_Death").find_track(HeroModel.ROOT_POSITION_TRACK, Animation.TYPE_POSITION_3D), -1,
		"if the rig renames its root, the pin silently stops pinning")
	source.free()


func test_town_clips_drive_the_skeleton_off_its_rest_pose() -> void:
	var model: Node3D = HeroModel.build("ally", "knight")
	add_child_autofree(model)
	var animator: AnimationPlayer = model.get_node("AnimationPlayer") as AnimationPlayer
	var skeleton: Skeleton3D = model.get_node("Rig_Medium/Skeleton3D") as Skeleton3D
	var spine: int = skeleton.find_bone("spine")
	var rest: Quaternion = skeleton.get_bone_rest(spine).basis.get_rotation_quaternion()
	for clip: String in ["Walking_A", "Interact"]:
		animator.play(clip)
		animator.seek(0.0, true)
		var moved: float = 0.0
		# Frame-sized steps: one long jump lands on the pending seek and barely moves the pose.
		for step: int in 8:
			animator.advance(0.1)
			moved = maxf(moved, skeleton.get_bone_pose_rotation(spine).angle_to(rest))
		assert_gt(moved, 0.05, "%s moves the spine" % clip)


func test_an_unknown_archetype_warns_and_draws_the_knight() -> void:
	var model: Node3D = autofree(HeroModel.build("ally", "paladin"))
	assert_push_warning("No ally look for archetype 'paladin'")
	assert_eq(model.scene_file_path, "%scharacters/Knight.glb" % HeroModel.MODEL_DIR)


func test_a_weapon_on_a_missing_bone_is_an_error_not_a_floating_weapon() -> void:
	var model: Node3D = autofree(HeroModel.build("ally", "mage"))
	var skeleton: Skeleton3D = model.get_node("Rig_Medium/Skeleton3D") as Skeleton3D
	var before: int = skeleton.find_children("*", "BoneAttachment3D", false, false).size()
	HeroModel.attach_weapons(skeleton, {"handslot.x": "dagger"})
	assert_push_error("no bone 'handslot.x'")
	assert_eq(skeleton.find_children("*", "BoneAttachment3D", false, false).size(), before)
