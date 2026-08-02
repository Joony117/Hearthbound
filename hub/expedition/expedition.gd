class_name Expedition
extends RefCounted
## ponytail: Phase 1 placeholder. A coin flip - no combat, no stats, no waves, no team.
## Its only job is proving the permadeath path runs end to end. Replaced by P2-03
## (quick_resolve.gd behind the CombatResult seam).

const SURVIVAL_CHANCE := 0.5


static func survives() -> bool:
	return randf() < SURVIVAL_CHANCE
