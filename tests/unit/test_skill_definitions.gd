extends GutTest

const SKILL_DIR: String = "res://combat/abilities/"


func test_every_skill_file_is_well_formed_and_registered() -> void:
	var files: PackedStringArray = _skill_files()
	assert_gt(files.size(), 0)
	for file: String in files:
		var skill: AbilityDefinition = load(SKILL_DIR + file) as AbilityDefinition
		assert_not_null(skill, "%s is an AbilityDefinition" % file)
		if skill == null:
			continue
		assert_eq(skill.validate(), "", file)
		assert_eq(_unknown_fields(FileAccess.get_file_as_string(SKILL_DIR + file)), [], "%s has only known fields" % file)
		assert_true(BattleSimulation.ABILITIES.has(str(skill.skill_id)), "%s is in BattleSimulation.ABILITIES" % file)
		assert_same(BattleSimulation.ABILITIES.get(str(skill.skill_id)), skill)
	assert_eq(BattleSimulation.ABILITIES.size(), files.size(), "every registered skill has a file")


func test_validate_rejects_an_unknown_primitive_or_effect_field() -> void:
	var skill: AbilityDefinition = (BattleSimulation.ABILITIES["ranger_piercing_shot"] as AbilityDefinition).duplicate(true)
	skill.effects = [{"type": "heal_everyone", "amount": 1.0}]
	assert_string_contains(skill.validate(), "unknown primitive")
	skill.effects = [{"type": "damage", "area": "line", "multiplier": 1.8, "pierce": true}]
	assert_string_contains(skill.validate(), "unknown field")
	skill.effects = [{"type": "damage", "area": "cone", "multiplier": 1.8}]
	assert_ne(skill.validate(), "")
	skill.effects = []
	assert_ne(skill.validate(), "")


func test_unknown_resource_field_is_caught() -> void:
	var text: String = FileAccess.get_file_as_string(SKILL_DIR + "mage_burst.tres")
	assert_eq(_unknown_fields(text), [])
	assert_eq(_unknown_fields(text + "mana_cost = 3.0\n"), ["mana_cost"])


func test_default_kit_is_one_passive_then_one_ability_per_class() -> void:
	for archetype: String in ["knight", "ranger", "mage", "rogue"]:
		var kit: Array[AbilityDefinition] = BattleSimulation.default_kit(archetype)
		assert_eq(kit.size(), 2, archetype)
		assert_eq(kit[0].kind, "passive", archetype)
		assert_eq(kit[1].kind, "ability", archetype)
		assert_same(BattleSimulation.signature_for(archetype), kit[1])


func test_actor_validator_accepts_both_shapes_and_rejects_bad_kits() -> void:
	var snapshots: Array[Dictionary] = [{"hero_id": "hero:1", "archetype": "knight", "hp": 100.0, "atk": 10.0, "defense": 10.0, "speed": 100.0, "crit_rate": 0.0, "crit_damage": 1.5, "squad_id": "s"}]
	var squads: Array[Dictionary] = [{"id": "s", "name": "S", "hero_ids": ["hero:1"], "stance": "advance", "guard_target_id": ""}]
	var state: BattleState = BattleSimulation.create_run("skills:1", snapshots, ZoneDefinition.definition_for(&"verdant_outskirts"), squads, {}, {"healing": 0, "revival": 0}, 1)
	var current: Dictionary = state.actors[0].to_dict()
	assert_eq(BattleActor.validate_dict(current), "")

	var legacy: Dictionary = current.duplicate(true)
	legacy.erase("skills")
	legacy.erase("skill_cooldowns")
	legacy["ability_cooldown"] = 3.5
	legacy["ability_auto"] = false
	assert_eq(BattleActor.validate_dict(legacy), "", "a pre-skills actor still loads")
	var migrated: BattleActor = BattleActor.from_dict(legacy)
	assert_eq(migrated.skill_cooldowns, {"knight_rally": 3.5})
	assert_eq(migrated.skills, [{"id": "knight_bulwark", "mode": "auto"}, {"id": "knight_rally", "mode": "manual"}])
	legacy["ability_auto"] = "no"
	assert_ne(BattleActor.validate_dict(legacy), "")

	for label: String in ["unknown id", "other class", "passive manual", "bad mode", "listed twice", "extra entry key", "missing cooldown", "passive cooldown", "negative cooldown", "no cooldowns"]:
		var broken: Dictionary = current.duplicate(true)
		var skills: Array = broken["skills"] as Array
		var cooldowns: Dictionary = broken["skill_cooldowns"] as Dictionary
		match label:
			"unknown id": skills[1]["id"] = "knight_meteor"
			"other class": skills[1]["id"] = "mage_burst"
			"passive manual": skills[0]["mode"] = "manual"
			"bad mode": skills[1]["mode"] = "sometimes"
			"listed twice": skills.append({"id": "knight_rally", "mode": "auto"})
			"extra entry key": skills[1]["rank"] = 2
			"missing cooldown": cooldowns.erase("knight_rally")
			"passive cooldown": cooldowns["knight_bulwark"] = 0.0
			"negative cooldown": cooldowns["knight_rally"] = -1.0
			"no cooldowns": broken.erase("skill_cooldowns")
		assert_ne(BattleActor.validate_dict(broken), "", label)


func test_snapshot_kit_keeps_only_legal_skills_and_never_loses_its_signature() -> void:
	var retired: BattleState = _knight_run([{"id": "retired_skill", "mode": "auto"}])
	assert_eq(retired.actors[0].skills, [{"id": "knight_bulwark", "mode": "auto"}, {"id": "knight_rally", "mode": "auto"}])
	assert_eq(BattleSimulation.validate_snapshot(retired.to_dict()), "")
	var messy: BattleState = _knight_run([{"id": "knight_rally", "mode": "manual"}, {"id": "knight_rally", "mode": "auto"}, {"id": "mage_burst", "mode": "auto"}])
	assert_eq(messy.actors[0].skills, [{"id": "knight_rally", "mode": "manual"}])
	assert_eq(messy.actors[0].skill_cooldowns, {"knight_rally": 0.0})
	assert_eq(BattleSimulation.validate_snapshot(messy.to_dict()), "")


func _knight_run(skills: Array) -> BattleState:
	var snapshots: Array[Dictionary] = [{"hero_id": "hero:1", "archetype": "knight", "hp": 100.0, "atk": 10.0, "defense": 10.0, "speed": 100.0, "crit_rate": 0.0, "crit_damage": 1.5, "squad_id": "s", "skills": skills}]
	var squads: Array[Dictionary] = [{"id": "s", "name": "S", "hero_ids": ["hero:1"], "stance": "advance", "guard_target_id": ""}]
	return BattleSimulation.create_run("skills:kit", snapshots, ZoneDefinition.definition_for(&"verdant_outskirts"), squads, {}, {"healing": 0, "revival": 0}, 1)


func _skill_files() -> PackedStringArray:
	var files := PackedStringArray()
	for file: String in DirAccess.get_files_at(SKILL_DIR):
		if file.ends_with(".tres"):
			files.append(file)
	return files


## Property lines in the [resource] section that AbilityDefinition does not declare; Godot would
## drop them silently on load.
func _unknown_fields(text: String) -> Array[String]:
	var known: Dictionary = {}
	for property: Dictionary in AbilityDefinition.new().get_property_list():
		known[str(property["name"])] = true
	var unknown: Array[String] = []
	var in_resource: bool = false
	for line: String in text.split("\n"):
		if line.begins_with("["):
			in_resource = line.begins_with("[resource]")
		elif in_resource and " = " in line and not line.begins_with("\t") and not line.begins_with(" "):
			var field: String = line.get_slice(" = ", 0)
			if not known.has(field):
				unknown.append(field)
	return unknown
