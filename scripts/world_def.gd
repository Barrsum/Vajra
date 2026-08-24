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
## Hand-authored beat sequence instead of random waves. Used for the opening
## level, where the order things arrive in is the whole point.
@export var scripted := false
## Enemies per wave. Waves repeat until the quota is met.
@export var wave_sizes: Array[int] = [3, 4, 5]
@export var drop_per_kill := 1
## Player damage multiplier for this world. The bestiary scales up level to
## level, so the hero has to as well or every fight just gets longer.
@export var player_power := 1.0
## Chance an enemy spawns at each size tier: [1x, 2x, 4x]. Normalised on use.
@export var size_weights: Array[float] = [0.7, 0.25, 0.05]
## Chance of each behaviour archetype: [Husk, Stalker, Ravager, Juggernaut].
@export var archetype_weights: Array[float] = [1.0, 0.0, 0.0, 0.0]
## Which creatures live here: [Mutant, Pumpkinhulk, Skeleton, Warrok].
@export var creature_weights: Array[float] = [1.0, 0.0, 0.0, 0.0]

@export_group("Mood")
## Master switch for fog and haze. Off for now — clarity first; atmosphere
## comes back later via shaders. The values below are kept, not deleted.
@export var fog_on := false
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
## Blends distant geometry into the fog colour. The single biggest contributor
## to a scene reading as one place rather than objects on a backdrop.
@export_range(0.0, 1.0) var aerial_perspective := 0.65
## Ground haze. Height is where it starts thinning out.
@export var fog_height := 8.0
@export var fog_height_density := 0.06
## Random lightning. Strikes cost creatures 10% of max health and charge the
## player's next hit instead of hurting them, so it reads as the world helping.
@export var storm_on := false

@export_group("Sky")
## The stylised sky shader. Time of day is not a separate setting: it falls out
## of where `sun_angles` puts the key light. Point the sun below the horizon and
## the sky goes to night, the stars come up and the moon lights the scene.
@export var sky_shader_on := true
## Day colours. The base the sunset and night tints are mixed over.
@export var day_top := Color(0.10, 0.60, 1.00)
@export var day_bottom := Color(0.40, 0.80, 1.00)
@export var sunset_top := Color(0.70, 0.75, 1.00)
@export var sunset_bottom := Color(1.00, 0.50, 0.70)
@export var night_top := Color(0.02, 0.00, 0.04)
@export var night_bottom := Color(0.10, 0.00, 0.20)
@export var horizon_tint := Color(0.00, 0.70, 0.80)
@export_range(0.0, 1.0) var horizon_blur := 0.05
## Sun and moon discs. These are drawn by the sky, not by the lights — the
## lights only say which way they are.
@export var sun_disc_color := Color(10.0, 8.0, 1.0)
@export var sun_disc_sunset_color := Color(10.0, 0.0, 0.0)
@export_range(0.01, 1.0) var sun_disc_size := 0.2
## Where the moon sits, as euler degrees, and how hard it lights the ground.
## Below the horizon it is hidden, which is how daytime worlds hide it.
@export var moon_angles := Vector3(40.0, 200.0, 0.0)
@export var moon_energy := 0.0
@export var moon_light_color := Color(0.62, 0.70, 1.00)
@export var moon_disc_color := Color(1.0, 0.95, 0.7)
@export_range(0.01, 1.0) var moon_disc_size := 0.06
## Clouds. Cutoff is coverage — lower means more sky covered. Weight darkens
## them toward storm without changing coverage.
@export_range(0.0, 1.0) var clouds_cutoff := 0.3
@export_range(0.0, 1.0) var clouds_weight := 0.0
@export_range(0.0, 20.0) var clouds_speed := 2.0
@export_range(0.0, 4.0) var clouds_scale := 1.0
@export_range(0.0, 2.0) var clouds_fuzziness := 0.5
@export var clouds_tint := Color(1.0, 1.0, 1.0)
@export_range(0.0, 20.0) var stars_speed := 1.0

@export_group("Grading")
@export var brightness := 1.0
@export var contrast := 1.06
@export var saturation := 1.04

@export_group("Terrain")
@export var ground_color := Color(0.31, 0.28, 0.25)
@export var prop_color := Color(0.55, 0.47, 0.38)
@export var accent_color := Color(0.2, 0.5, 0.25)
@export var arena_size := 120.0
