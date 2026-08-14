# VAJRA

A third-person action game about a robot whose wife sent him out for groceries.

Four worlds, four monster species, and a meat quota. Clear the quota, come home,
dinner gets cooked. The story is a wrapper — underneath it is a wave-and-quota
brawler with a combo system, dodges, grabs and a lot of dissolving corpses.

Built in Godot 4. This is a passion project, not a commercial one.

---

## Play it

You need **Godot 4.7.1 (Standard, not .NET)**. It is a single portable
executable — there is no installer, and nothing is added to your system.

```
git clone https://github.com/Barrsum/Vajra.git
cd Vajra
```

Then download Godot from the [archive](https://godotengine.org/download/archive/),
make a folder called `godot` in the project root, and drop the executable in:

```
Vajra/
├── godot/
│   └── Godot_v4.7.1-stable_win64.exe    <- here
├── PLAY.bat
└── ...
```

Now double-click **`PLAY.bat`** (Windows) or run **`./play.sh`** (Linux/macOS).

That folder is gitignored, so your copy of the engine never gets committed.

> The launchers also find Godot if it is on your `PATH`, if `GODOT` points at
> it, or if it is sitting next to the project folder — so if you already have
> Godot installed, `PLAY.bat` should just work with no setup at all.

The clone is around 200 MB. Almost all of that is character meshes and their
textures.

### Other launchers

| | |
|---|---|
| `PLAY.bat` / `play.sh` | The game. Start here. |
| `EDIT.bat` | Opens the Godot editor, for tweaking values in the Inspector. |
| `TEST.bat` | Runs the whole automated suite headless. |
| `HYBRID.bat` | The bare combat sandbox, no menus or level structure. |
| `COMPARE.bat` | GDQuest's reference controller, unmodified, for A/B feel checks. |

---

## Controls

| Action | Key |
|---|---|
| Move | `W` `A` `S` `D` |
| Sprint | `Shift` |
| Jump | `Space` |
| Attack | `Left Mouse` — tap three times for the full combo |
| Dodge | `Ctrl` or `Right Mouse` |
| Heal | `H`, `1`, or `Mouse Wheel Down` — spends one health orb |
| Pause | `P` |
| Free the mouse | `Esc` |

Health orbs only drop in world 4, and you can carry five.

---

## The four worlds

Each world is data, not a scene — quota, enemy mix, lighting mood and power
level all come from one table in `scripts/game_state.gd`. Hand-built levels can
be dropped in later without touching combat code.

| # | World | Quota | Your power |
|---|---|---|---|
| 1 | The Thicket — green forest | 11 | 1.0x |
| 2 | The Open Mouth — cave entrance under bright sky | 23 | 1.5x |
| 3 | The Dust Shallows — a dried ocean | 29 | 1.9x |
| 4 | The Long Night — darkness | 35 | 2.5x |

Worlds 1 to 3 open with a hand-authored sequence of beats — specific monsters,
specific counts, specific triggers — and hand over to random waves once the
opening has played. World 4 stays scripted the whole way through.

---

## How it is put together

```
scripts/       Game logic. enemy.gd and hero.gd are the two big ones.
scenes/        Scene files, including the UI.
shaders/       Death dissolve.
assets/        Meshes, animations, textures.
tests/         Automated suites, and the build scripts that generate
               the animation library and state machine.
player/        GDQuest's controller, used whole (MIT).
```

A few decisions worth knowing before you read the code:

**All four monsters share one skeleton and one animation library.** They are
Mixamo characters with identical rigs, verified at zero missing bones, so
swapping a mesh is a pure swap. One state machine serves every creature; they
just travel to different state names inside it.

**Animation sets are rolled per individual.** The Mutant and the Pumpkinhulk
keep their authored walk and attacks. The Skeleton and the Warrok shipped
without animations of their own, so each one draws a set at spawn — a walk from
the walks, an attack pair from the attacks — which is why no two look alike.
See `LOCO_POOL` and friends in `scripts/enemy.gd`.

**Nothing about combat timing comes from animation length.** Telegraph, strike,
link and recover windows are per-archetype numbers. Clips are time-scaled to fit
those windows, not the other way round.

**No audio files ship.** Every sound is synthesised into an `AudioStreamWAV` at
runtime in `scripts/sfx.gd`.

**The animation library is generated, not hand-built.** `tests/build_enemy.gd`
reads the raw Mixamo FBX files, strips root motion, measures each walk's real
stride so blend points land where the feet actually move, and writes
`enemy_anims.res` and `enemy_tree.tres`. Re-run it after adding clips:

```
godot --headless --path . res://tests/build_enemy.tscn
```

---

## Tests

```
TEST.bat
```

Or one at a time:

```
godot --headless --path . res://tests/level1_test.tscn
```

These are not unit tests. They drive real scenes — spawning waves, killing
through quotas, running set-pieces — and assert that the right monsters arrive
at the right beats. Each exits non-zero on failure.

| Suite | Covers |
|---|---|
| `anim_pool_test` | Every pooled animation name exists; 240 spawns for coverage |
| `level1_test` — `level4_test` | Each world's scripted beats, counts and triggers |
| `flow_test` | Menus, pausing, death, victory, progress saving |

Run them windowed instead of headless and they also write screenshots to
`shots/`.

---

## Exporting a standalone build

See **[docs/EXPORTING.md](docs/EXPORTING.md)** for Windows, Linux and macOS —
including what you can and cannot do without a Mac.

---

## Credits

Third-party assets are logged in **[CREDITS.md](CREDITS.md)** — every mesh,
animation and borrowed system, with its source and licence.

The engine is [Godot](https://godotengine.org) (MIT). Characters and animations
are from [Mixamo](https://www.mixamo.com). The player controller is
[GDQuest's](https://github.com/gdquest-demos/godot-4-3d-third-person-controller)
(MIT). The hero mesh and its animations are [Quaternius](https://quaternius.com)
(CC0).

Everything else — combat, enemy AI, the animation pipeline, world generation,
audio synthesis, VFX — was written for this project.
