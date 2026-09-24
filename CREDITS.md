# Credits

## Third-party assets

Most third-party art in this repository is **CC0 1.0 Universal (Public Domain Dedication)** —
<https://creativecommons.org/publicdomain/zero/1.0/>. CC0 requires no attribution; this file exists
because a silent omission would be a decision by accident rather than one made on purpose, and
because the next person to touch these files needs to know where they came from and what was left
behind.

**The Mixamo assets below are the exception and are not CC0.** They ship in `game.pck`
(`export_presets.cfg` exports `all_resources`), so the blanket claim this file used to make no
longer covers everything the build contains.

### Adobe Mixamo — <https://www.mixamo.com>

| Staged as | From |
|---|---|
| `combat/arena/models/xbot/X_Bot.fbx` | Mixamo's stock "X Bot" character, downloaded skinned |
| `combat/arena/models/animations/mixamo/*.fbx` (17 clips) | `Pro Sword and Shield Pack.zip` plus seven later single-clip downloads, all "Without Skin" |

These are the arena's hero, enemy, and entire moveset as of the Mixamo swap; the Quaternius rows
below are the pack they replaced, kept on disk as the rollback point.

> ⚠️ **Licensing unconfirmed.** Mixamo content is royalty-free for use *inside* a project, but
> Adobe's terms restrict redistributing the assets standalone — and a public repo containing the raw
> `.fbx` files is arguably exactly that, independent of what the built game does.
> **Settled by:** reading Adobe's current Mixamo terms and deciding whether the source files stay
> committed or move to a fetch step. Nothing else in this file has that ambiguity.

The clip-name-to-Mixamo-move mapping is not one-to-one for the pack files — Mixamo names every
download `sword and shield <move> (n)`, so each was picked by measuring its root travel, and those
file names are the arena's clip names rather than Mixamo's. The seven later files keep Mixamo's own
names, spaces and inconsistent capitalisation included (`Sword And Shield Strafe left`), which is why
the arena's clip constants quote them verbatim instead of matching the pack's `Snake_Case`.

`Roll.fbx` is **no longer bound**. It is a sidestep, and measurement puts it at the same `0.667 s`
and `2.32 m` of travel as `Sword And Shield Strafe left.fbx` — the same move, re-downloaded under its
real name. It stays on disk unreferenced rather than being deleted with the licensing question above
still open; nothing loads it.

### Quaternius — <https://quaternius.com>

| Staged as | From | Pack |
|---|---|---|
| `combat/arena/models/hero/Superhero_{Male,Female}_FullBody.gltf` + `.bin` + `T_Superhero_*_Dark*.png` | `Universal Base Characters[Standard].zip` (122 MB) | [Universal Base Characters](https://quaternius.itch.io/universal-base-characters) |
| `combat/arena/models/animations/UAL1_Standard.glb` | `Universal Animation Library[Standard].zip` (15 MB) | [Universal Animation Library](https://quaternius.itch.io/universal-animation-library) |
| `combat/arena/models/animations/UAL2_Standard.glb` | `Universal Animation Library 2[Standard].zip` (17 MB) | [Universal Animation Library 2](https://quaternius.itch.io/universal-animation-library-2) |

The female body is the arena hero (`P2b-09`), the male body is the arena enemy (`P2b-10`) — both are
in use, so neither is dead weight to prune.

Downloaded 2026-08-11 from itch.io at the free ("name your own price", $0) tier. The paid `[Source]`
tiers are `.blend` files and engine shader projects; nothing in `P2b-09`/`P2b-10` needs them.

**What was deliberately left out of the repo**, and where to get it again if it turns out to be
needed:

- **The `_RM` animation variants.** Each library ships twice — `UAL*_Standard_RM.glb` has root
  motion baked into every clip, `UAL*_Standard.glb` has it disabled (the packs' own `README.txt`
  states this). `arena.gd` drives locomotion and the attack lunge itself, so a baked root track
  would double-count displacement. **Only the no-root-motion files are staged**, so the wrong one
  cannot be picked by accident.
- **Normal and roughness maps** (~7 MB per character). Base colour only for now; the arena is a
  graybox and the `material_override` tint channel writes `albedo_color` over the top regardless.
- **The other four base characters** (Regular and Teen proportions, male and female). The free tier
  ships only the two Superhero-proportion bodies as glTF.
- **20 hairstyles, eyebrows, and the FBX/Unity variants.** Not needed by either ticket.
- **Modular Character Outfits — Fantasy** (12 outfits, 62 parts, same rig, also CC0). Not staged and
  not scheduled. Recorded because it is the pack that would let the five archetypes look different
  from each other, and because it is the reason this rig was chosen over a one-off model.

### KayKit (Kay Lousberg) — <https://www.kaylousberg.com>

All CC0. The pack licences are copied beside the files as `LICENSE-KayKit-*.txt`. Downloaded
2026-09-23 from itch.io at the free ($0) tier.

| Staged as | From | Pack |
|---|---|---|
| `combat/battle/models/kaykit/characters/{Knight,Mage,Ranger,Rogue}.glb` + `*_texture.png`; `weapons/{sword_1handed,shield_round,shield_badge,staff,wand,bow_withString,dagger}.gltf` + `.bin` | `Free 2.0` (12 MB) | [Character Pack: Adventurers](https://kaylousberg.itch.io/kaykit-adventurers) |
| `combat/battle/models/kaykit/characters/Skeleton_{Warrior,Rogue,Mage,Minion}.glb` + `skeleton_texture.png`; `weapons/Skeleton_{Blade,Shield_Small_A,Staff,Crossbow}.gltf` + `.bin` | `Free 1.1` (7.7 MB) | [Character Pack: Skeletons](https://kaylousberg.itch.io/kaykit-skeletons) |
| `combat/battle/models/kaykit/animations/Rig_Medium_{General,MovementBasic,MovementAdvanced,CombatMelee,CombatRanged,Special}.glb` | `Free 1.1` (14 MB) | [Character Animations](https://kaylousberg.itch.io/kaykit-character-animations) |
| `combat/battle/models/kaykit/animations/Rig_Medium_{Simulation,Tools}.glb` | `Free 1.1` (14 MB), the same zip | [Character Animations](https://kaylousberg.itch.io/kaykit-character-animations) |
| `hub/town/models/hexagon/building_{tower_base,tower_A,tower_B,blacksmith,archeryrange,barracks,church,castle,market}_blue.gltf`, `building_{destroyed,stage_B,stage_C}.gltf`, `wall_straight_gate.gltf`; props `{barrel,crate_A_big,crate_open,weaponrack,target,tent,wheelbarrow,flag_blue}.gltf`; nature `{tree_single_A,tree_single_B,rock_single_A}.gltf`; each with its `.bin`, plus `hexagons_medieval.png` | `1.0 FREE` (33 MB) | [Medieval Hexagon Pack](https://kaylousberg.itch.io/kaykit-medieval-hexagon) |
| `hub/town/models/resource_bits/{Iron_Bars_Stack_Small,Gold_Bars_Stack_Small,Wood_Log_Stack,Wood_Planks_Stack_Medium,Stone_Bricks_Stack_Medium,Textiles_Stack_Small,Pallet_Wood_Covered_A}.gltf` + `.bin` + `resource_bits_texture.png` | `1.0 FREE` (8.1 MB) | [Resource Bits](https://kaylousberg.itch.io/resource-bits) |

The first three rows are the squad battle's units (`ig-ixj`). The last four are the town (`ig-wgj.3`):
the Simulation and Tools clips are for keepers at work and townsfolk; the Hexagon and Resource Bits
models are the buildings by level tier and the square's props. Every Hexagon file shares the one
`hexagons_medieval.png` (the pack ships identical copies per folder), so the staged files sit flat in
one directory. Heroes and skeletons share `Rig_Medium`, so one
animation set drives both sides. The weapon `.gltf` files reference the character textures by
relative path, which is why the textures appear in both `characters/` and `weapons/`.

**Left out on purpose:** Barbarian and Rogue_Hooded, the other weapons and props, the `Rig_Large`
clips, the FBX copies, and the duplicate clip files that
ship inside the Adventurers and Skeletons packs (the Character Animations pack is their superset).
From the town packs: the green, red and yellow building colours (the blue set is the only one
used); the other nine blue buildings (home_A, home_B, tavern, mine, lumbermill, windmill,
watermill, well, tower_catapult); bridges, fences, the other walls, scaffolding,
`building_dirt`, `building_grain`, `building_stage_A` and the catapult projectile; every hex tile
(base, coast, river, road); the other props and nature pieces (mountains, hills, clouds, water
plants); the other 69 Resource Bits (bars, nuggets, fuel, parts, loose planks); and each pack's FBX,
FBX(Unity) and OBJ copies, samples and PDF guide. All are in the same free zips if a later ticket
needs them.
