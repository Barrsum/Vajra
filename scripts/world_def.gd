extends Resource
class_name WorldDef
## One hunting ground.
##
## Worlds are data on purpose. Adding a hand-built level later means creating one
## of these and dropping its scene in — no code changes, no touching the game
## loop. `arena_scene` can be left empty to use the procedural street.

@export var display_name := "SECTOR ONE"
@export_multiline var subtitle := ""

@export_group("Objective")
## What the monsters here drop. One ingredient per world.
@export var ingredient := "SCRAP"
@export var ingredient_needed := 12

@export_group("Content")
## Hand-built level. Leave null to fall back to the procedural street.
@export var arena_scene: PackedScene
## Enemies per wave. Waves repeat until the quota is met.
@export var wave_sizes: Array[int] = [3, 4, 5]
## How many ingredients a single kill yields.
@export var drop_per_kill := 1

@export_group("Mood")
@export var sky_horizon := Color(0.95, 0.60, 0.31)
@export var fog_color := Color(0.72, 0.44, 0.26)
@export var fog_density := 0.016
@export var sun_color := Color(1.0, 0.72, 0.44)
