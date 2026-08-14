# Credits

Every third-party asset in this project, logged as it is added.

This is bookkeeping, not paperwork. Provenance is trivial to record the moment
you download something and genuinely painful to reconstruct six months later —
so the rule is simply: **add the row when you add the file.**

| Asset | Used for | Source | License | Added |
|---|---|---|---|---|
| Y Bot | Player character mesh + rig | Mixamo (Adobe) | Mixamo Terms — free use with an Adobe account | 2026-08-09 |
| Mixamo animation set (11 clips) | Player locomotion, jump, dodge, attacks, hit, death | Mixamo (Adobe) | Mixamo Terms | 2026-08-09 |
| Mutant | Enemy mesh + rig | Mixamo (Adobe) | Mixamo Terms | 2026-08-09 |
| Pumpkinhulk L Shaw, Skeletonzombie T Avelange, Warrok W Kurniawan | Enemy meshes. All share Mixamo's skeleton, so they play the existing enemy animation set with zero missing bones | Mixamo (Adobe) | Mixamo Terms | 2026-08-10 |
| Pumpkinhulk Walking, Injured Walk, Baseball Hit, Standing Melee Attack Backhand / Downward | Pumpkinhulk locomotion and attacks; the level 2 set-piece limp and swing | Mixamo (Adobe) | Mixamo Terms | 2026-08-10 |
| Mutant animation set (8 clips) | Enemy idle, walk, run, roar, attacks, death | Mixamo (Adobe) | Mixamo Terms | 2026-08-09 |
| Zombie Walk / Attack / Death, Monster walk 3 & 4, Mutant Jump Attack, Mutant Flexing Muscles, Standing React Large From Left | The variant pool. Skeleton and Warrok have no animations of their own, so each individual draws a set from these at spawn | Mixamo (Adobe) | Mixamo Terms | 2026-08-14 |
| Godot Engine 4.7.1 | Engine | godotengine.org | MIT | 2026-08-09 |
| GDQuest TPS controller | Four techniques reimplemented, not copied: ground-height camera decoupling, last-strong-direction facing, variable jump height, stopping-speed snap | [gdquest-demos/godot-4-3d-third-person-controller](https://github.com/gdquest-demos/godot-4-3d-third-person-controller) | MIT (source) | 2026-08-09 |
| GDQuest player system | Copied verbatim into `res://player/` — camera controller, model, animation tree, shaders. Used whole in `compare_gdquest.tscn`; the camera rig is reused in `hero.tscn` | same as above | MIT (source) | 2026-08-09 |
| Universal Animation Library (Standard) | **Hero character mesh + all 13 player animations.** Single rig, single animator — this is what fixed the animation jank | [Quaternius](https://quaternius.com/packs/universalanimationlibrary.html) | **CC0** | 2026-08-09 |
| RPG Animations GLB FREE | Downloaded, 67 clips on a different rig (`B_Pelvis` vs `pelvis`). Not yet used — needs retargeting | [Explosive LLC, Godot Asset Store](https://store.godotengine.org/asset/explosive-llc/rpg-character-animations-pack-free/) | MIT | 2026-08-09 |

## Everything else is original

Street generation, combat system, enemy AI, animation pipeline, arm blade,
camera and all tuning were written for this project.

## Notes on licences

Current project intent is **personal / non-commercial**, which is the least
restrictive case — most obligations attached to open assets (share-alike,
non-commercial clauses, GPL copyleft) are triggered by *distribution*, not by
building something for yourself.

If that intent ever changes, this table is the thing that makes the audit an
afternoon instead of a rebuild.

### One thing publishing changes

Most of the obligations above are triggered by *distribution*, and pushing the
raw asset files to a **public** repository is distribution — which local use
never was.

The specific point of friction is Mixamo. Adobe's terms let you use their
characters and animations in a project freely, but they do not grant the right
to redistribute the source `.fbx` files as files. A public repo containing
`Mutant.fbx` is handing out the asset, not the game. Nobody is likely to care
about a hobby project, and Adobe has not historically pursued this — but it is
a real term and worth knowing you are crossing it rather than finding out
later.

Three ways to sit comfortably, in order of how little work they are:

1. **Keep the repository private** and add friends as collaborators. Changes
   nothing about how you work, and the whole question goes away.
2. **Ship builds instead of source.** Exported games bake meshes into an
   engine-specific format — that is use, not redistribution, and it is what
   Mixamo's terms are written to permit. See `docs/EXPORTING.md`.
3. **Public repo, assets excluded**, with a short script that fetches them.
   Most correct, most annoying for anyone cloning.

Godot, GDQuest's controller (MIT) and Quaternius' library (CC0) are all fine to
redistribute as-is. The CC0 assets have no conditions at all.
