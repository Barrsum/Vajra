extends Node3D
## Spawns waves around the player and reports state to a minimal HUD.
## Deliberately thin — this is a combat testbed, not the story sequencer yet.

const EnemyScript := preload("res://scripts/enemy.gd")

@export var enemy_scene: PackedScene
@export var wave_sizes: Array[int] = [2, 3, 4]
@export var spawn_radius := 12.0
@export var wave_break := 2.5

@onready var player: CharacterBody3D = $Player
@onready var hud_health: Label = $HUD/Margin/Rows/Health
@onready var hud_wave: Label = $HUD/Margin/Rows/Wave
@onready var hud_hint: Label = $HUD/Margin/Rows/Hint

var _wave := -1
var _alive := 0
var _breaking := false


func _ready() -> void:
	hud_hint.text = "WASD move   SHIFT sprint   SPACE jump   CTRL/RMB dodge   LMB attack"
	_start_next_wave()


func _process(_delta: float) -> void:
	hud_health.text = "HP  %d / %d" % [roundi(player.health), roundi(player.max_health)]
	if not player.alive:
		hud_wave.text = "YOU DIED   —   press R to restart"
		if Input.is_key_pressed(KEY_R):
			get_tree().reload_current_scene()
		return
	hud_wave.text = "WAVE %d / %d      enemies %d" % [
		_wave + 1, wave_sizes.size(), _alive,
	]


func _start_next_wave() -> void:
	_breaking = false
	_wave += 1
	if _wave >= wave_sizes.size():
		_wave = 0   # loop forever; this is a testbed
	EnemyScript.reset_tokens()

	for i in wave_sizes[_wave]:
		await get_tree().create_timer(0.35 * i).timeout
		if not is_inside_tree():
			return
		_spawn()


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
	if _alive <= 0 and not _breaking:
		_breaking = true
		# Small heal between waves so the fight can escalate without a wipe.
		player.health = minf(player.max_health, player.health + 25.0)
		await get_tree().create_timer(wave_break).timeout
		if is_inside_tree():
			_start_next_wave()
