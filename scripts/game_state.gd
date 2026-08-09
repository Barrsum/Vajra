extends Node
## Run state and world progression. Autoloaded as `Game`.
##
## Owns the only things that must survive a scene change: which world we are in,
## what has been collected, and whether we are playing, paused or finished.
## Everything else is free to be rebuilt per scene.

enum State { MENU, PLAYING, PAUSED, WORLD_CLEAR, VICTORY, DEAD }

signal state_changed(state: State)
signal collected_changed(have: int, need: int)
signal world_started(world, index: int)

const GAME_SCENE := "res://scenes/main_hybrid.tscn"
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const WorldDefScript := preload("res://scripts/world_def.gd")

## The run. Replace or extend this as hand-built worlds arrive — nothing else
## needs to know how many there are.
## Untyped on purpose: depending on the WorldDef class_name would break any
## headless run, because class_name only registers via an editor pass.
var worlds: Array = []

var state := State.MENU
var world_index := 0
var collected := 0
var total_kills := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_default_worlds()


## Placeholder run until hand-built worlds exist. Each entry is just data.
func _build_default_worlds() -> void:
	var defs := [
		["SECTOR SEVEN", "the shopping list starts here", "SCRAP MEAT", 10,
			Color(0.95, 0.60, 0.31), Color(0.72, 0.44, 0.26)],
		["THE UNDERPASS", "she said it grows in the dark", "RUST BLOOM", 14,
			Color(0.42, 0.36, 0.62), Color(0.28, 0.24, 0.42)],
		["COOLANT FLATS", "bring a container", "GEL SAC", 16,
			Color(0.36, 0.72, 0.70), Color(0.24, 0.46, 0.48)],
		["THE FOUNDRY", "last item. then dinner.", "CORE SHARD", 20,
			Color(0.92, 0.34, 0.24), Color(0.52, 0.18, 0.14)],
	]
	for d in defs:
		var w: Resource = WorldDefScript.new()
		w.display_name = d[0]
		w.subtitle = d[1]
		w.ingredient = d[2]
		w.ingredient_needed = d[3]
		w.sky_horizon = d[4]
		w.fog_color = d[5]
		w.wave_sizes = [3, 4, 5] as Array[int]
		worlds.append(w)


# --- queries ----------------------------------------------------------------

func current_world() -> Resource:
	if worlds.is_empty():
		return null
	return worlds[clampi(world_index, 0, worlds.size() - 1)]


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
	world_index = 0
	collected = 0
	total_kills = 0
	_enter_world()


func _enter_world() -> void:
	collected = 0
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
	collected = mini(collected + amount, needed())
	collected_changed.emit(collected, needed())
	if collected >= needed():
		if is_last_world():
			_set_state(State.VICTORY)
		else:
			_set_state(State.WORLD_CLEAR)
		get_tree().paused = true
		return true
	return false


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
