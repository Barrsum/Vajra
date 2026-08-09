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
| Mutant animation set (8 clips) | Enemy idle, walk, run, roar, attacks, death | Mixamo (Adobe) | Mixamo Terms | 2026-08-09 |
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
