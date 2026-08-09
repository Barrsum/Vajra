extends Node3D
## Spawns waves for whichever world the run is currently in.
##
## Knows nothing about progression — it spawns, reports kills to Game, and keeps
## going until Game says the world is complete. That separation is what lets a
## hand-built world be dropped in later without touching this file.

const EnemyScript := preload("res://scripts/enemy.gd")

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
	_start_next_wave()


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
	add_child(e)
	e.player = player
	var a := randf() * TAU
	var r := spawn_radius + randf() * 5.0
	e.global_position = player.global_position + Vector3(sin(a) * r, 0.5, cos(a) * r)
	e.died.connect(_on_enemy_died)
	_alive += 1


func _on_enemy_died(_e: Node) -> void:
	_alive -= 1

	var w: Resource = Game.current_world()
	var finished := Game.add_drop(w.drop_per_kill if w else 1)
	if finished:
		return

	# Keep the pressure on: top up as soon as the field thins, rather than
	# waiting for a full clear. The quota is the goal now, not the wave.
	if _alive <= 1 and not _spawning:
		await get_tree().create_timer(wave_break).timeout
		if is_inside_tree():
			_start_next_wave()
