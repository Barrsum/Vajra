extends Resource
class_name WorldDef
## One hunting ground.
##
## Worlds are data on purpose. Adding a hand-built level later means creating one
## of these and pointing `arena_scene` at it — no code changes, no touching the
## game loop. Leave it null and the procedural generator builds the theme below.

## Theme is a plain int, not an enum. `Theme` is a native Godot class (the UI
## one), so an enum by that name shadows it and refuses to compile — and enums
## on a class_name resource do not resolve through a preload anyway.
## 0 Forest · 1 Cave · 2 Ocean · 3 Night · 4 Street

@export var display_name := "SECTOR ONE"
@export_multiline var subtitle := ""

@export_group("Objective")
## What the monsters here drop. One ingredient per world.
@export var ingredient := "SCRAP"
@export var ingredient_needed := 12

@export_group("Content")
## Hand-built level. Leave null to use the procedural generator.
@export var arena_scene: PackedScene
@export_enum("Forest", "Cave", "Ocean", "Night", "Street") var theme := 0
## Enemies per wave. Waves repeat until the quota is met.
@export var wave_sizes: Array[int] = [3, 4, 5]
@export var drop_per_kill := 1
## Chance an enemy spawns at each size tier: [1x, 2x, 4x]. Normalised on use.
@export var size_weights: Array[float] = [0.7, 0.25, 0.05]
## Chance of each behaviour archetype: [Husk, Stalker, Ravager, Juggernaut].
@export var archetype_weights: Array[float] = [1.0, 0.0, 0.0, 0.0]

@export_group("Mood")
@export var sky_top := Color(0.30, 0.33, 0.42)
@export var sky_horizon := Color(0.95, 0.60, 0.31)
@export var ground_horizon := Color(0.42, 0.28, 0.19)
@export var fog_color := Color(0.72, 0.44, 0.26)
@export var fog_density := 0.016
@export var volumetric_density := 0.028
@export var sun_color := Color(1.0, 0.72, 0.44)
@export var sun_energy := 2.2
## Direction the key light comes from, as euler degrees.
@export var sun_angles := Vector3(-50.0, 35.0, 0.0)
@export var ambient_energy := 1.0
@export var glow_intensity := 0.65

@export_group("Terrain")
@export var ground_color := Color(0.31, 0.28, 0.25)
@export var prop_color := Color(0.55, 0.47, 0.38)
@export var accent_color := Color(0.2, 0.5, 0.25)
@export var arena_size := 120.0
