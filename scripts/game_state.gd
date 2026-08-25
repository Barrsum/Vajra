extends Node
## Run state and world progression. Autoloaded as `Game`.
##
## Owns the only things that must survive a scene change: which world we are in,
## what has been collected, and whether we are playing, paused or finished.
## Everything else is free to be rebuilt per scene.

## OUTRO sits between PLAYING and VICTORY. The tree stays UNPAUSED through it —
## that is the whole point: the win is a camera move over the live scene, not a
## cut to a screen. VICTORY is what pauses, and by then the last rendered frame
## is already the pose the results panel sits on top of.
enum State { MENU, PLAYING, PAUSED, WORLD_CLEAR, VICTORY, DEAD, OUTRO }

signal state_changed(state: State)
signal collected_changed(have: int, need: int)
signal world_started(world, index: int)

const GAME_SCENE := "res://scenes/main_hybrid.tscn"
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const SELECT_SCENE := "res://scenes/ui/level_select.tscn"
const SAVE_PATH := "user://progress.cfg"
const WorldDefScript := preload("res://scripts/world_def.gd")
const THEME_FOREST := 0
const THEME_CAVE := 1
const THEME_OCEAN := 2
const THEME_NIGHT := 3
const THEME_STREET := 4

## The run. Replace or extend this as hand-built worlds arrive — nothing else
## needs to know how many there are.
## Untyped on purpose: depending on the WorldDef class_name would break any
## headless run, because class_name only registers via an editor pass.
var worlds: Array = []

var state := State.MENU
var world_index := 0
var collected := 0

## Per-run stats, for the results screen. Reset on entering a world, not on
## the whole session — the screen reports the run you just played.
var run_time := 0.0
var run_kills := 0
var damage_dealt := 0.0
var damage_taken := 0.0
var max_combo := 0
var potions_used := 0
var _combo := 0
var _combo_t := 0.0
var total_kills := 0
## Highest world reached. Everything up to and including this is playable, so
## testing a later level never means replaying the earlier ones.
var unlocked := 0
var cleared: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_default_worlds()
	load_progress()


## Placeholder run until hand-built worlds exist. Each entry is just data, so
## replacing one with a real level later touches nothing else.
func _build_default_worlds() -> void:
	worlds.clear()

	# 1 — fenced forest. Soft, green, low contrast: the tutorial ground.
	var forest: Resource = WorldDefScript.new()
	forest.display_name = "THE THICKET"
	forest.subtitle = "she wants it fresh"
	forest.ingredient = "SAP GLAND"
	forest.ingredient_needed = 11
	forest.theme = THEME_FOREST
	# Beat-scripted: 4 small, then a medium, then 5 more small, then guardians.
	# 9 small (1 meat) + 1 medium (2 meat) = exactly the 11 required.
	forest.scripted = true
	forest.wave_sizes = [3, 4, 4] as Array[int]
	forest.player_power = 1.0
	forest.size_weights = [0.85, 0.15, 0.0] as Array[float]
	forest.archetype_weights = [0.75, 0.25, 0.0, 0.0] as Array[float]
	# one creature; the level teaches the fight, not the bestiary
	forest.creature_weights = [1.0, 0.0, 0.0, 0.0] as Array[float]
	forest.sky_top = Color(0.42, 0.60, 0.52)
	forest.sky_horizon = Color(0.74, 0.82, 0.58)
	forest.ground_horizon = Color(0.20, 0.28, 0.16)
	forest.fog_color = Color(0.48, 0.62, 0.42)
	forest.fog_density = 0.010
	forest.volumetric_density = 0.014
	forest.sun_color = Color(0.92, 1.0, 0.82)
	forest.sun_energy = 1.5
	forest.sun_angles = Vector3(-58.0, 28.0, 0.0)
	forest.ambient_energy = 1.1
	# Late morning over the canopy. Sun high, sky pushed green so it agrees with
	# the forest below, and enough cloud to give the light something to break on.
	forest.day_top = Color(0.30, 0.55, 0.78)
	forest.day_bottom = Color(0.62, 0.80, 0.72)
	forest.sunset_top = Color(0.62, 0.70, 0.85)
	forest.sunset_bottom = Color(0.95, 0.66, 0.52)
	forest.horizon_tint = Color(0.55, 0.72, 0.55)
	forest.sun_disc_color = Color(9.0, 8.6, 4.0)
	forest.sun_disc_size = 0.16
	forest.clouds_cutoff = 0.36
	forest.clouds_speed = 1.4
	forest.clouds_scale = 1.1
	forest.clouds_tint = Color(1.0, 1.0, 0.97)
	forest.moon_angles = Vector3(38.0, 200.0, 0.0)
	forest.moon_energy = 0.0

	forest.glow_intensity = 0.30
	forest.ground_color = Color(0.20, 0.30, 0.16)
	forest.prop_color = Color(0.34, 0.33, 0.26)
	forest.accent_color = Color(0.24, 0.52, 0.22)
	forest.arena_size = 110.0
	worlds.append(forest)

	# 2 — cave mouth under an open, near-white sky.
	var cave: Resource = WorldDefScript.new()
	cave.display_name = "THE OPEN MOUTH"
	cave.subtitle = "mind the drop"
	cave.ingredient = "STONE MARROW"
	cave.ingredient_needed = 23
	cave.theme = THEME_CAVE
	# Scripted opening: two chargers pin you, the heavy swings, you are thrown
	# into the middle of everything else.
	cave.scripted = true
	cave.wave_sizes = [4, 5, 5] as Array[int]
	cave.player_power = 1.5
	cave.size_weights = [0.6, 0.35, 0.05] as Array[float]
	cave.archetype_weights = [0.40, 0.35, 0.25, 0.0] as Array[float]
	# Pumpkinhulk joins the Mutant
	cave.creature_weights = [0.5, 0.5, 0.0, 0.0] as Array[float]
	cave.sky_top = Color(0.34, 0.48, 0.66)
	cave.sky_horizon = Color(0.62, 0.72, 0.84)
	cave.ground_horizon = Color(0.30, 0.31, 0.33)
	cave.fog_color = Color(0.55, 0.63, 0.74)
	cave.fog_density = 0.009
	cave.volumetric_density = 0.010
	cave.sun_color = Color(1.0, 0.98, 0.94)
	cave.sun_energy = 1.5
	cave.sun_angles = Vector3(-72.0, 10.0, 0.0)
	cave.ambient_energy = 0.8
	# The brief asked for pure sky at the cave mouth: noon, deep blue overhead,
	# and heavy bright cloud so stepping out of the dark actually hurts.
	cave.day_top = Color(0.10, 0.42, 0.88)
	cave.day_bottom = Color(0.55, 0.80, 1.00)
	cave.sunset_top = Color(0.70, 0.75, 1.00)
	cave.sunset_bottom = Color(1.00, 0.60, 0.62)
	cave.horizon_tint = Color(0.72, 0.85, 0.95)
	cave.horizon_blur = 0.07
	cave.sun_disc_color = Color(12.0, 11.0, 7.0)
	cave.sun_disc_size = 0.13
	cave.clouds_cutoff = 0.26
	cave.clouds_speed = 2.6
	cave.clouds_scale = 0.85
	cave.clouds_fuzziness = 0.42
	cave.clouds_tint = Color(1.0, 1.0, 1.0)
	cave.moon_angles = Vector3(42.0, 200.0, 0.0)
	cave.moon_energy = 0.0

	cave.glow_intensity = 0.35
	cave.ground_color = Color(0.24, 0.25, 0.27)
	cave.prop_color = Color(0.22, 0.22, 0.23)
	cave.accent_color = Color(0.52, 0.58, 0.62)
	cave.aerial_perspective = 0.35
	cave.arena_size = 120.0
	worlds.append(cave)

	# 3 — dusty shallows. Hazy, washed out, water underfoot.
	var ocean: Resource = WorldDefScript.new()
	ocean.display_name = "THE DUST SHALLOWS"
	ocean.subtitle = "bring a container"
	ocean.ingredient = "GEL SAC"
	ocean.ingredient_needed = 29
	ocean.theme = THEME_OCEAN
	# Scripted: three 2x, reinforcements at 80%, then two 4x arrivals.
	ocean.scripted = true
	ocean.wave_sizes = [4, 5, 6] as Array[int]
	ocean.player_power = 1.9
	ocean.size_weights = [0.5, 0.38, 0.12] as Array[float]
	ocean.archetype_weights = [0.25, 0.35, 0.28, 0.12] as Array[float]
	# all four in play
	# No Warrok here — it is held back so level 4 has something new.
	ocean.creature_weights = [0.34, 0.33, 0.33, 0.0] as Array[float]
	ocean.sky_top = Color(0.62, 0.66, 0.68)
	ocean.sky_horizon = Color(0.86, 0.80, 0.68)
	ocean.ground_horizon = Color(0.52, 0.50, 0.44)
	ocean.fog_color = Color(0.74, 0.72, 0.63)
	ocean.fog_density = 0.014
	ocean.volumetric_density = 0.034
	ocean.sun_color = Color(1.0, 0.94, 0.80)
	ocean.sun_energy = 1.45
	ocean.sun_angles = Vector3(-38.0, 55.0, 0.0)
	ocean.ambient_energy = 0.9
	# A low sun over a dried sea. Dropping it to 20 degrees puts the shader into
	# a partial sunset on its own and rakes long shadows across the flat, which
	# is most of what sells the emptiness.
	ocean.sun_angles = Vector3(-20.0, 55.0, 0.0)
	ocean.day_top = Color(0.45, 0.55, 0.70)
	ocean.day_bottom = Color(0.82, 0.78, 0.66)
	ocean.sunset_top = Color(0.72, 0.62, 0.72)
	ocean.sunset_bottom = Color(1.00, 0.62, 0.42)
	ocean.horizon_tint = Color(0.88, 0.76, 0.58)
	ocean.horizon_blur = 0.10
	ocean.sun_disc_color = Color(11.0, 6.5, 2.4)
	ocean.sun_disc_sunset_color = Color(11.0, 3.2, 0.6)
	ocean.sun_disc_size = 0.24
	ocean.clouds_cutoff = 0.44
	ocean.clouds_weight = 0.12
	ocean.clouds_speed = 1.0
	ocean.clouds_scale = 1.5
	ocean.clouds_tint = Color(1.0, 0.92, 0.82)
	ocean.moon_angles = Vector3(36.0, 200.0, 0.0)
	ocean.moon_energy = 0.0

	ocean.glow_intensity = 0.50
	ocean.ground_color = Color(0.40, 0.38, 0.33)
	ocean.prop_color = Color(0.38, 0.37, 0.34)
	ocean.accent_color = Color(0.35, 0.55, 0.58)
	ocean.aerial_perspective = 0.45
	ocean.arena_size = 130.0
	worlds.append(ocean)

	# 4 — night. Dark, lamp-lit, and the only world where the big ones are common.
	var night: Resource = WorldDefScript.new()
	night.display_name = "THE LONG NIGHT"
	night.subtitle = "last item. then dinner."
	night.ingredient = "CORE SHARD"
	night.ingredient_needed = 35
	night.theme = THEME_NIGHT
	# Scripted, and it never fully hands over: minis are only ever called by a
	# wounded medium here, and they carry no meat.
	night.scripted = true
	night.wave_sizes = [4, 6, 7] as Array[int]
	night.player_power = 2.5
	# Equal odds once it goes random: a 4x is as likely as a 2x.
	night.size_weights = [0.0, 0.5, 0.5] as Array[float]
	night.archetype_weights = [0.15, 0.30, 0.30, 0.25] as Array[float]
	# everything, weighted toward the heavies
	night.creature_weights = [0.2, 0.25, 0.25, 0.30] as Array[float]
	night.sky_top = Color(0.04, 0.05, 0.10)
	night.sky_horizon = Color(0.10, 0.11, 0.20)
	night.ground_horizon = Color(0.05, 0.05, 0.08)
	night.fog_color = Color(0.10, 0.12, 0.22)
	night.fog_density = 0.016
	night.volumetric_density = 0.028
	night.sun_color = Color(0.42, 0.52, 0.85)
	night.sun_energy = 0.55
	night.sun_angles = Vector3(-30.0, 200.0, 0.0)
	night.ambient_energy = 0.85
	# Night is not a colour setting — it is the sun below the horizon. A positive
	# X angle puts it there, and the shader takes over: sky to night colours,
	# stars up, moon lit. The sun keeps no energy, so the moon is the key light
	# and shadows fall from above where they should, not up from underground.
	night.sun_angles = Vector3(16.0, 200.0, 0.0)
	night.sun_energy = 0.0
	night.night_top = Color(0.02, 0.03, 0.09)
	night.night_bottom = Color(0.08, 0.09, 0.20)
	night.sunset_top = Color(0.24, 0.20, 0.42)
	night.sunset_bottom = Color(0.55, 0.28, 0.34)
	night.horizon_tint = Color(0.10, 0.12, 0.24)
	night.horizon_blur = 0.09
	night.moon_angles = Vector3(-46.0, 20.0, 0.0)
	night.moon_energy = 0.75
	night.moon_light_color = Color(0.58, 0.68, 1.00)
	night.moon_disc_color = Color(0.92, 0.94, 1.00)
	night.moon_disc_size = 0.11
	night.clouds_cutoff = 0.52
	night.clouds_weight = 0.35
	night.clouds_speed = 0.8
	night.clouds_scale = 1.2
	night.clouds_tint = Color(0.72, 0.76, 0.92)
	night.stars_speed = 0.6
	night.storm_on = true

	night.glow_intensity = 0.95
	# Snow, not mud. The generated set for this world is a winter one, and the
	# base ground shows through everywhere the scattered patches do not reach —
	# so it has to already be the right colour rather than something the
	# patches are expected to hide. Blue-grey rather than white: lit by
	# lamplight it reads as snow, and pure white would blow out under the
	# campfires.
	night.ground_color = Color(0.66, 0.71, 0.80)
	night.prop_color = Color(0.34, 0.36, 0.42)
	night.accent_color = Color(1.0, 0.62, 0.28)
	night.arena_size = 115.0
	worlds.append(night)


# --- queries ----------------------------------------------------------------

func current_world() -> Resource:
	if worlds.is_empty():
		return null
	return worlds[clampi(world_index, 0, worlds.size() - 1)]


func _process(delta: float) -> void:
	if state != State.PLAYING and state != State.OUTRO:
		return
	run_time += delta
	# A combo is a chain of landed hits with no long gap. Two seconds is
	# generous enough that repositioning mid-fight does not break it, tight
	# enough that it is not just a kill counter.
	if _combo > 0:
		_combo_t -= delta
		if _combo_t <= 0.0:
			_combo = 0


func note_damage_dealt(amount: float) -> void:
	damage_dealt += amount
	_combo += 1
	_combo_t = 2.0
	max_combo = maxi(max_combo, _combo)


func note_damage_taken(amount: float) -> void:
	damage_taken += amount
	# Being hit ends the chain. That is what makes a high combo mean something
	# beyond "the fight went on a while".
	_combo = 0


func note_potion() -> void:
	potions_used += 1


func _reset_run_stats() -> void:
	run_time = 0.0
	run_kills = 0
	damage_dealt = 0.0
	damage_taken = 0.0
	max_combo = 0
	potions_used = 0
	_combo = 0
	_combo_t = 0.0


func needed() -> int:
	var w := current_world()
	return w.ingredient_needed if w else 0


func is_last_world() -> bool:
	return world_index >= worlds.size() - 1


# --- transitions ------------------------------------------------------------

func _set_state(s: State) -> void:
	state = s
	state_changed.emit(s)


func start_run() -> void:
	total_kills = 0
	to_select()


## Jump straight into any unlocked world.
func start_world(index: int) -> void:
	if index > unlocked:
		return
	world_index = clampi(index, 0, worlds.size() - 1)
	collected = 0
	_enter_world()


func to_select() -> void:
	get_tree().paused = false
	_set_state(State.MENU)
	get_tree().change_scene_to_file(SELECT_SCENE)


func is_cleared(index: int) -> bool:
	return index in cleared


func _mark_cleared(index: int) -> void:
	if not index in cleared:
		cleared.append(index)
	unlocked = maxi(unlocked, mini(index + 1, worlds.size() - 1))
	save_progress()


func save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "unlocked", unlocked)
	cfg.set_value("progress", "cleared", cleared)
	cfg.save(SAVE_PATH)


func load_progress() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	unlocked = int(cfg.get_value("progress", "unlocked", 0))
	cleared = cfg.get_value("progress", "cleared", [])


func reset_progress() -> void:
	unlocked = 0
	cleared = []
	save_progress()


func _enter_world() -> void:
	collected = 0
	_reset_run_stats()
	_set_state(State.PLAYING)
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME_SCENE)
	# The scene swap happens next frame; announce once it exists.
	await get_tree().process_frame
	await get_tree().process_frame
	world_started.emit(current_world(), world_index)
	collected_changed.emit(collected, needed())


## Called when an enemy dies. Returns true if this completed the world.
func add_drop(amount := 1) -> bool:
	if state != State.PLAYING:
		return false
	total_kills += 1
	run_kills += 1
	collected = mini(collected + amount, needed())
	collected_changed.emit(collected, needed())
	if collected >= needed():
		_mark_cleared(world_index)
		if is_last_world():
			# No pause. The arena runs the outro over a live scene and calls
			# finish_outro() when the camera has come to rest.
			_set_state(State.OUTRO)
		else:
			_set_state(State.WORLD_CLEAR)
			get_tree().paused = true
		return true
	return false


## Called by the outro once the camera move is done and the robot is posed.
func finish_outro() -> void:
	if state != State.OUTRO:
		return
	_set_state(State.VICTORY)
	get_tree().paused = true


func next_world() -> void:
	world_index = mini(world_index + 1, worlds.size() - 1)
	_enter_world()


func player_died() -> void:
	if state != State.PLAYING:
		return
	_set_state(State.DEAD)


func retry_world() -> void:
	_enter_world()


func toggle_pause() -> void:
	if state == State.PLAYING:
		_set_state(State.PAUSED)
		get_tree().paused = true
	elif state == State.PAUSED:
		_set_state(State.PLAYING)
		get_tree().paused = false


func to_menu() -> void:
	get_tree().paused = false
	_set_state(State.MENU)
	get_tree().change_scene_to_file(MENU_SCENE)


func quit() -> void:
	get_tree().quit()
