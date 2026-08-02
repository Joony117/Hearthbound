class_name Summon
extends RefCounted
## ponytail: Phase 1 placeholder. Uniform random rank, name off a fixed list, no cost and no
## HeroDefinition. Replaced wholesale by P2-02 (weight table + definition pools) - do not
## build on this.

const NAMES: PackedStringArray = [
	"Aldric", "Brenna", "Cassius", "Dara", "Edric", "Fenna", "Gorath", "Hilde",
	"Ivo", "Jorunn", "Kestrel", "Lyra", "Morgen", "Nils", "Orla", "Perrin",
	"Quill", "Rowan", "Sable", "Tamsin", "Ulric", "Vesna", "Wren", "Yorick",
]


static func roll() -> Hero:
	return Hero.new(
		NAMES[randi() % NAMES.size()],
		randi() % Hero.RANK_NAMES.size(),
	)
