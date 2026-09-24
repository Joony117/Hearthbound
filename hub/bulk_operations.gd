class_name BulkOperations
extends RefCounted
## Pure preview rules. GameSession supplies current state and owns the atomic mutations.


static func preview_salvage(
	item_ids: Array[String],
	quantity: int,
	items: Dictionary[String, Item],
	names: Dictionary[String, String],
	protected_reasons: Dictionary[String, String],
	forge_level: int,
	keeper_skill: int,
	balance: BalanceTable,
) -> Dictionary:
	var plan: Dictionary = _empty_plan("salvage", {
		"item_ids": item_ids.duplicate(),
		"quantity": quantity,
		"forge_level": forge_level,
		"keeper_skill": keeper_skill,
	})
	var selection_error: String = _selection_error(item_ids)
	if not selection_error.is_empty():
		return _invalid(plan, selection_error)
	if quantity < 0:
		return _invalid(plan, "Quantity cannot be negative.")
	var limit: int = item_ids.size() if quantity == 0 else quantity
	for item_id: String in item_ids:
		if plan["entries"].size() >= limit:
			break
		var item: Item = items.get(item_id) as Item
		if item == null:
			plan["excluded"].append(_excluded(item_id, str(names.get(item_id, "Missing item")), "missing"))
			continue
		if protected_reasons.has(item_id):
			plan["excluded"].append(_excluded(item_id, str(names.get(item_id, item_id)), protected_reasons[item_id]))
			continue
		var gain: int = Item.compute_salvage_yield(item, forge_level, keeper_skill, balance)
		var rank: int = clampi(item.rank, 0, balance.rank_names.size() - 1)
		plan["entries"].append({"id": item_id, "name": str(names.get(item_id, item_id)), "rank": rank, "gain": gain})
		plan["gain_parts"][rank] += gain
	plan["valid"] = not plan["entries"].is_empty()
	if not plan["valid"]:
		plan["error"] = "No selected items are eligible for salvage."
	return plan


static func preview_sacrifice(
	hero_ids: Array[String],
	target: Hero,
	quantity: int,
	heroes: Dictionary[String, Hero],
	protected_reasons: Dictionary[String, String],
	sanctum_level: int,
	keeper_skill: int,
	balance: BalanceTable,
) -> Dictionary:
	var plan: Dictionary = _empty_plan("sacrifice", {
		"hero_ids": hero_ids.duplicate(),
		"target_id": target.instance_id if target != null else "",
		"quantity": quantity,
		"sanctum_level": sanctum_level,
		"keeper_skill": keeper_skill,
	})
	var selection_error: String = _selection_error(hero_ids)
	if not selection_error.is_empty():
		return _invalid(plan, selection_error)
	if quantity < 0:
		return _invalid(plan, "Quantity cannot be negative.")
	if target == null:
		return _invalid(plan, "The sacrifice recipient is missing.")
	var limit: int = hero_ids.size() if quantity == 0 else quantity
	for hero_id: String in hero_ids:
		if plan["entries"].size() >= limit:
			break
		var hero: Hero = heroes.get(hero_id) as Hero
		if hero == null:
			plan["excluded"].append(_excluded(hero_id, "Missing hero", "missing"))
			continue
		if hero == target:
			plan["excluded"].append(_excluded(hero_id, hero.hero_name, "recipient"))
			continue
		if protected_reasons.has(hero_id):
			plan["excluded"].append(_excluded(hero_id, hero.hero_name, protected_reasons[hero_id]))
			continue
		if not hero.equipped.is_empty():
			plan["excluded"].append(_excluded(hero_id, hero.hero_name, "equipped"))
			continue
		var essence_gain: int = Hero.compute_essence_yield(hero, target, balance, sanctum_level, keeper_skill)
		var resonance_gain: int = 1 if hero.def_id == target.def_id and hero.def_id != Hero.NO_ARCHETYPE_DEF_ID else 0
		plan["entries"].append({
			"id": hero_id,
			"name": hero.hero_name,
			"rank": hero.rank,
			"essence_gain": essence_gain,
			"resonance_gain": resonance_gain,
		})
		plan["essence_gain"] += essence_gain
		plan["resonance_gain"] += resonance_gain
	plan["valid"] = not plan["entries"].is_empty()
	if not plan["valid"]:
		plan["error"] = "No selected heroes are eligible for sacrifice."
	return plan


static func preview_enhance(
	item_ids: Array[String],
	target_level: int,
	budget_parts: Array[int],
	items: Dictionary[String, Item],
	names: Dictionary[String, String],
	available_parts: Array[int],
	forge_level: int,
	master_smith_home: bool,
	balance: BalanceTable,
) -> Dictionary:
	var plan: Dictionary = _empty_plan("enhance", {
		"item_ids": item_ids.duplicate(),
		"target_level": target_level,
		"budget_parts": budget_parts.duplicate(),
		"parts_snapshot": available_parts.duplicate(),
		"forge_level": forge_level,
		"master_smith_home": master_smith_home,
	})
	var selection_error: String = _selection_error(item_ids)
	if not selection_error.is_empty():
		return _invalid(plan, selection_error)
	if budget_parts.size() != available_parts.size() or budget_parts.size() != balance.rank_names.size():
		return _invalid(plan, "Enhancement requires one non-negative budget for every rank.")
	for budget: int in budget_parts:
		if budget < 0:
			return _invalid(plan, "Enhancement budgets cannot be negative.")
	var enhance_cap: int = Item.compute_enhance_cap(forge_level, master_smith_home, balance)
	var bounded_target: int = clampi(target_level, 0, enhance_cap)
	plan["parameters"]["target_level"] = bounded_target
	var remaining_budget: Array[int] = []
	for rank: int in budget_parts.size():
		remaining_budget.append(mini(budget_parts[rank], available_parts[rank]))
	for item_id: String in item_ids:
		var item: Item = items.get(item_id) as Item
		if item == null:
			plan["excluded"].append(_excluded(item_id, str(names.get(item_id, "Missing item")), "missing"))
			continue
		var before_level: int = Item.clamped_enhance_level(item, balance)
		if before_level >= bounded_target:
			plan["excluded"].append(_excluded(item_id, str(names.get(item_id, item_id)), "at_target"))
			continue
		var rank: int = clampi(item.rank, 0, balance.rank_names.size() - 1)
		var after_level: int = before_level
		var spend: int = 0
		while after_level < bounded_target:
			var next_cost: int = Item.compute_enhance_cost_for_level(after_level, balance)
			if remaining_budget[rank] < next_cost:
				break
			remaining_budget[rank] -= next_cost
			spend += next_cost
			after_level += 1
		if after_level == before_level:
			plan["excluded"].append(_excluded(item_id, str(names.get(item_id, item_id)), "insufficient_budget"))
			continue
		plan["entries"].append({
			"id": item_id,
			"name": str(names.get(item_id, item_id)),
			"rank": rank,
			"before_level": before_level,
			"after_level": after_level,
			"spend": spend,
		})
		plan["cost_parts"][rank] += spend
	plan["valid"] = not plan["entries"].is_empty()
	if not plan["valid"]:
		plan["error"] = "No selected items can be enhanced with that target and budget."
	return plan


static func preview_conversion(
	parts: Array[int],
	rank: int,
	quantity: int,
	reserve: int,
) -> Dictionary:
	var plan: Dictionary = _empty_plan("conversion", {
		"rank": rank,
		"quantity": quantity,
		"reserve": reserve,
		"parts_snapshot": parts.duplicate(),
	})
	if rank < 0 or rank >= parts.size() - 1:
		return _invalid(plan, "Only ranks F through SS can be converted upward.")
	if quantity < 0 or reserve < 0:
		return _invalid(plan, "Quantity and reserve cannot be negative.")
	var max_units: int = floori(float(maxi(parts[rank] - reserve, 0)) / 3.0)
	var units: int = max_units if quantity == 0 else quantity
	if quantity > max_units:
		return _invalid(plan, "The requested conversion would spend the reserve or exceed available parts.")
	if units <= 0:
		return _invalid(plan, "No parts are available above the reserve.")
	var spend: int = units * 3
	plan["entries"].append({
		"id": "parts_%d" % rank,
		"name": "Rank %d parts" % rank,
		"rank": rank,
		"units": units,
		"source_rank": rank,
		"target_rank": rank + 1,
		"spend": spend,
		"gain": units,
	})
	plan["cost_parts"][rank] = spend
	plan["gain_parts"][rank + 1] = units
	plan["valid"] = true
	return plan


## F parts one draught costs: the base, cut by the Apothecary keeper's Alchemy, never below 1.
static func supply_parts_cost(supply_kind: String, alchemy_skill: int, balance: BalanceTable) -> int:
	var base: int = balance.healing_supply_parts_cost if supply_kind == "healing" else balance.revival_supply_parts_cost
	return maxi(1, roundi(base * (1.0 - balance.alchemy_cost_cut_per_skill * alchemy_skill)))


static func preview_supplies(
	supply_kind: String,
	quantity: int,
	reserve: int,
	parts: Array[int],
	supplies: Dictionary,
	alchemy_skill: int,
	balance: BalanceTable,
) -> Dictionary:
	var plan: Dictionary = _empty_plan("supplies", {
		"supply_kind": supply_kind,
		"quantity": quantity,
		"reserve": reserve,
		"alchemy_skill": alchemy_skill,
		"parts_snapshot": parts.duplicate(),
		"supplies_snapshot": supplies.duplicate(true),
	})
	if not supply_kind in ["healing", "revival"]:
		return _invalid(plan, "Choose healing or revival supplies.")
	if quantity < 0 or reserve < 0:
		return _invalid(plan, "Quantity and reserve cannot be negative.")
	var cost: int = supply_parts_cost(supply_kind, alchemy_skill, balance)
	var available: int = maxi(parts[0] - reserve, 0)
	var maximum: int = available / cost
	var units: int = maximum if quantity == 0 else quantity
	if units <= 0 or units > maximum:
		return _invalid(plan, "The requested supplies would spend the reserve or exceed available F parts.")
	var spend: int = units * cost
	plan["entries"].append({
		"id": "supply_" + supply_kind,
		"name": "Healing draught" if supply_kind == "healing" else "Revival draught",
		"units": units,
		"spend": spend,
		"gain": units,
		"supply_kind": supply_kind,
	})
	plan["cost_parts"][0] = spend
	plan["valid"] = true
	return plan


static func _empty_plan(kind: String, parameters: Dictionary) -> Dictionary:
	return {
		"kind": kind,
		"valid": false,
		"error": "",
		"entries": [],
		"excluded": [],
		"cost_parts": [0, 0, 0, 0, 0, 0, 0, 0],
		"gain_parts": [0, 0, 0, 0, 0, 0, 0, 0],
		"essence_gain": 0,
		"resonance_gain": 0,
		"parameters": parameters,
	}


static func _invalid(plan: Dictionary, error: String) -> Dictionary:
	plan["error"] = error
	return plan


static func _excluded(id: String, name: String, reason: String) -> Dictionary:
	return {"id": id, "name": name, "reason": reason}


static func _selection_error(ids: Array[String]) -> String:
	if ids.is_empty():
		return "Select at least one entry."
	var seen: Dictionary[String, bool] = {}
	for id: String in ids:
		if id.is_empty():
			return "Selected IDs cannot be empty."
		if seen.has(id):
			return "Selected IDs cannot contain duplicates."
		seen[id] = true
	return ""
