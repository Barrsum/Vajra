extends Node3D
## Spawns waves for whichever world the run is currently in.
##
## Knows nothing about progression — it spawns, reports kills to Game, and keeps
## going until Game says the world is complete. That separation is what lets a
## hand-built world be dropped in later without touching this file.

const EnemyScript := preload("res://scripts/enemy.gd")
const PickupScript := preload("res://scripts/pickup.gd")

@export var enemy_scene: PackedScene
@export var spawn_radius := 12.0
@export var wave_break := 2.0
@export var max_alive := 7

@onready var player: CharacterBody3D = $Player
@onready var ui: CanvasLayer = $GameUI

var _wave := -1
var _alive := 0
var _spawning := false


func _ready() -> void:
	ui.player = player
	_apply_mood()
	_start_next_wave()


## Push the current world's sky, fog and key light into the scene. Doing this at
## runtime rather than per-scene is what lets one arena scene serve every world.
func _apply_mood() -> void:
	var w: Resource = Game.current_world()
	if w == null:
		return

	var env: Environment = ($WorldEnvironment as WorldEnvironment).environment
	var sky_mat := env.sky.sky_material as ProceduralSkyMaterial
	if sky_mat:
		sky_mat.sky_top_color = w.sky_top
		sky_mat.sky_horizon_color = w.sky_horizon
		sky_mat.ground_horizon_color = w.ground_horizon
		sky_mat.ground_bottom_color = w.ground_horizon.darkened(0.4)

	env.fog_light_color = w.fog_color
	env.fog_density = w.fog_density
	env.volumetric_fog_density = w.volumetric_density
	env.volumetric_fog_emission = w.fog_color.darkened(0.6)
	env.glow_intensity = w.glow_intensity
	env.ambient_light_energy = w.ambient_energy

	var sun := $Sun as DirectionalLight3D
	sun.light_color = w.sun_color
	sun.light_energy = w.sun_energy
	sun.rotation = Vector3(
		deg_to_rad(w.sun_angles.x), deg_to_rad(w.sun_angles.y), deg_to_rad(w.sun_angles.z))


func _wave_sizes() -> Array:
	var w: Resource = Game.current_world()
	if w and not w.wave_sizes.is_empty():
		return w.wave_sizes
	return [3, 4, 5]


func _start_next_wave() -> void:
	if Game.state != Game.State.PLAYING:
		return
	_spawning = true
	var sizes := _wave_sizes()
	_wave = (_wave + 1) % sizes.size()
	EnemyScript.reset_tokens()

	var count: int = sizes[_wave]
	for i in count:
		await get_tree().create_timer(0.35).timeout
		if not is_inside_tree() or Game.state != Game.State.PLAYING:
			_spawning = false
			return
		if _alive < max_alive:
			_spawn()
	_spawning = false


func _spawn() -> void:
	var e: CharacterBody3D = enemy_scene.instantiate()
	e.set_archetype(_roll_weighted(_world_weights("archetype_weights")))
	e.set_tier(_roll_weighted(_world_weights("size_weights")))
	add_child(e)
	e.player = player
	var a := randf() * TAU
	var r := spawn_radius + randf() * 5.0
	e.global_position = player.global_position + Vector3(sin(a) * r, 0.6, cos(a) * r)
	e.died.connect(_on_enemy_died)
	_alive += 1


func _world_weights(prop: String) -> Array:
	var w: Resource = Game.current_world()
	if w == null:
		return [1.0]
	var arr: Array = w.get(prop)
	return arr if not arr.is_empty() else [1.0]


## Weighted pick over an arbitrary weight array.
func _roll_weighted(weights: Array) -> int:
	var total := 0.0
	for x in weights:
		total += float(x)
	if total <= 0.0:
		return 0
	var roll := randf() * total
	var acc := 0.0
	for i in weights.size():
		acc += float(weights[i])
		if roll <= acc:
			return i
	return 0


func _on_enemy_died(e: Node) -> void:
	_alive -= 1

	# Drops are physical now: the quota only advances when the player walks over
	# a sphere, which is what makes clearing an area feel like collecting.
	var w: Resource = Game.current_world()
	var per_kill: int = w.drop_per_kill if w else 1
	var count: int = per_kill * (e.drops if "drops" in e else 1)
	var at: Vector3 = e.global_position if is_instance_valid(e) else player.global_position
	for i in count:
		_spawn_pickup(at + Vector3.UP * 1.2)

	if Game.state != Game.State.PLAYING:
		return

	# Keep the pressure on: top up as soon as the field thins, rather than
	# waiting for a full clear. The quota is the goal now, not the wave.
	if _alive <= 1 and not _spawning:
		await get_tree().create_timer(wave_break).timeout
		if is_inside_tree():
			_start_next_wave()


func _spawn_pickup(at: Vector3) -> void:
	var p := Node3D.new()
	p.set_script(PickupScript)
	add_child(p)
	p.global_position = at
	p.player = player
	var w: Resource = Game.current_world()
	if w:
		p.color = w.accent_color.lightened(0.25)
