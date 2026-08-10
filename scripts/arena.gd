extends Node3D
## Spawns for whichever world the run is in.
##
## Two modes. Worlds marked `scripted` run a hand-authored beat sequence, so the
## opening level can teach the fight in a fixed order. Everything else uses the
## generic wave loop, which stays random on purpose.
##
## Either way this knows nothing about progression — it spawns, drops, and lets
## Game decide when the quota is met.

const EnemyScript := preload("res://scripts/enemy.gd")
const PickupScript := preload("res://scripts/pickup.gd")

# Archetype ids, matching Enemy.ARCHETYPES.
const HUSK := 0
const STALKER := 1
const RAVAGER := 2
const JUGGERNAUT := 3

@export var enemy_scene: PackedScene
@export var spawn_radius := 7.5
@export var wave_break := 2.0
@export var max_alive := 7

@onready var player: CharacterBody3D = $Player
@onready var ui: CanvasLayer = $GameUI

var _wave := -1
var _alive := 0
var _spawning := false

# --- scripted mode ---
var _scripted := false
var _beat := 0
var _kills := 0
var _guardian: Node = null      ## the first medium; beat 2 waits on its health
var _beat_locked := false
var _grabbers: Array = []
var _smasher: Node = null
var _spawned_t0 := 0
var _spawned_t1 := 0
var _spawned_t2 := 0


func _ready() -> void:
	ui.player = player
	_apply_mood()
	var w: Resource = Game.current_world()
	_scripted = w != null and w.scripted
	if _scripted:
		_run_beat(0)
	else:
		_start_next_wave()


func _process(_delta: float) -> void:
	if _scripted and Game.state == Game.State.PLAYING:
		_check_beats()


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

	# Aerial perspective ties distant geometry to the fog; height fog puts haze
	# on the ground. Together they do most of the work of making a scene cohere.
	env.fog_aerial_perspective = w.aerial_perspective
	env.fog_height = w.fog_height
	env.fog_height_density = w.fog_height_density
	env.adjustment_enabled = true
	env.adjustment_brightness = w.brightness
	env.adjustment_contrast = w.contrast
	env.adjustment_saturation = w.saturation

	var sun := $Sun as DirectionalLight3D
	sun.light_color = w.sun_color
	sun.light_energy = w.sun_energy
	sun.rotation = Vector3(
		deg_to_rad(w.sun_angles.x), deg_to_rad(w.sun_angles.y), deg_to_rad(w.sun_angles.z))


# --- scripted level ---------------------------------------------------------
#
# Beat 0  four smalls. The whole fight, taught plainly.
# Beat 1  after two die, one medium walks in. First real threat.
# Beat 2  at 15% of that medium's health, five more smalls answer the call.
# Beat 3  at nine meat, two mediums and a small arrive from a distance —
#         the world defending itself. The quota is already reachable without
#         them, so they are pressure rather than a wall.

func _check_beats() -> void:
	if _beat_locked:
		return
	if Game.world_index == 1:
		_check_open_mouth()
		return
	match _beat:
		0:
			if _kills >= 2:
				_run_beat(1)
		1:
			if is_instance_valid(_guardian) and _guardian.is_alive() \
			and _guardian.health <= _guardian.max_health * 0.15:
				_run_beat(2)
			elif not is_instance_valid(_guardian) or not _guardian.is_alive():
				_run_beat(2)   # killed outright; do not stall the level
		2:
			if Game.collected >= 9:
				_run_beat(3)


func _run_beat(b: int) -> void:
	_beat = b
	_beat_locked = true
	if Game.world_index == 1:
		await _beats_open_mouth(b)
	else:
		await _beats_thicket(b)
	_beat_locked = false


func _beats_thicket(b: int) -> void:
	match b:
		0:
			for i in 4:
				await _delay(0.35)
				_spawn_near(HUSK if i % 2 == 0 else STALKER, 0)
		1:
			ui.show_message("SOMETHING BIGGER NOTICED YOU")
			await _delay(0.8)
			_guardian = _spawn_near(HUSK, 1, 11.0, 1.0)
		2:
			ui.show_message("THE SMALL ONES ANSWER")
			for i in 5:
				await _delay(0.30)
				_spawn_near(HUSK if i % 3 else STALKER, 0, 0.0, 0.45)
		3:
			ui.show_message("THE BIG ONES PROTECT THEIR OWN")
			await _delay(0.5)
			# Placed downrange and in view, so you see them coming.
			_spawn_in_view(JUGGERNAUT, 1, 19.0, -5.0, 1.8)
			await _delay(0.4)
			_spawn_in_view(JUGGERNAUT, 1, 21.0, 5.0, 1.8)
			await _delay(0.4)
			_spawn_in_view(STALKER, 0, 16.0, 0.0, 1.8)


# --- Level 2 opening: the ambush -------------------------------------------
#
# Three are already in frame when you arrive. Two charge and pin an arm each;
# the heavy one limps in and swings. You are thrown, and you land in the middle
# of everything else.

func _beats_open_mouth(b: int) -> void:
	match b:
		0:
			_grabbers.clear()
			# Two chargers, one per flank, and the heavy hanging back.
			var g1 := _spawn_in_view(HUSK, 0, 9.0, -3.5, 0.9)
			g1.set_deferred("role", g1.Role.CHARGE)
			g1.role_side = -1.0
			g1.role_speed = 2.2

			var g2 := _spawn_in_view(HUSK, 1, 10.0, 3.5, 1.2)
			g2.set_deferred("role", g2.Role.CHARGE)
			g2.role_side = 1.0
			g2.role_speed = 1.9

			_grabbers = [g1, g2]

			# Close enough that the wait is dread rather than tedium: a limp at
			# ~2.3 m/s from 10m is about four seconds of being held.
			var sm := _spawn_in_view(JUGGERNAUT, 1, 10.5, 0.0, 1.6)
			sm.creature = 1                      # Pumpkinhulk
			sm.role_speed = 1.55                 # a limp, not a charge
			sm.set_deferred("role", sm.Role.STALK)
			sm.smashed.connect(_on_smash)
			_smasher = sm
			ui.show_message("THEY WERE WAITING")
		1:
			ui.show_message("HELD")
		2:
			# Thrown clear, and the ground you land on is not empty.
			await _delay(0.9)
			ui.show_message("GET UP")
			for i in 7:
				await _delay(0.25)
				_spawn_near(HUSK if i % 2 == 0 else STALKER, 0, 14.0 + randf() * 8.0)


func _check_open_mouth() -> void:
	match _beat:
		0:
			# Both arms taken, or the player killed one before it landed.
			var holding := 0
			var lost := 0
			for g in _grabbers:
				if not is_instance_valid(g) or not g.is_alive():
					lost += 1
				elif g.role == g.Role.HOLD:
					holding += 1
			if holding >= 1 or lost >= _grabbers.size():
				_run_beat(1)
		1:
			# The smash resolves this beat; if the heavy dies first, move on.
			if not is_instance_valid(_smasher) or not _smasher.is_alive():
				_release_grabbers()
				_run_beat(2)


func _on_smash(_e: Node) -> void:
	if _beat > 1:
		return
	var away: Vector3 = player.global_position - _smasher.global_position
	away.y = 0.0
	_release_grabbers()
	if player.has_method("launch"):
		player.launch(away, 17.0, 9.0)
	if player.has_method("take_damage"):
		player.take_damage(18.0, _smasher.global_position)
	_run_beat(2)


func _release_grabbers() -> void:
	if player.has_method("set_grabbed"):
		player.set_grabbed(false)
	for g in _grabbers:
		if is_instance_valid(g):
			g.role = g.Role.FREE
	if is_instance_valid(_smasher):
		_smasher.role = _smasher.Role.FREE


func _delay(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


# --- generic waves ----------------------------------------------------------

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
			_spawn_near(_roll_weighted(_world_weights("archetype_weights")),
				_roll_weighted(_world_weights("size_weights")))
	_spawning = false


# --- spawning ---------------------------------------------------------------

func _make(archetype: int, tier: int) -> CharacterBody3D:
	var e: CharacterBody3D = enemy_scene.instantiate()
	e.set_creature(_roll_weighted(_world_weights("creature_weights")))
	e.set_archetype(archetype)
	e.set_tier(tier)
	add_child(e)
	e.player = player
	e.died.connect(_on_enemy_died)
	_alive += 1
	match tier:
		0: _spawned_t0 += 1
		1: _spawned_t1 += 1
		_: _spawned_t2 += 1
	return e


## Ring spawn around the player.
func _spawn_near(archetype: int, tier: int, radius := 0.0, glow := 0.0) -> CharacterBody3D:
	var e := _make(archetype, tier)
	var a := randf() * TAU
	var r := (radius if radius > 0.0 else spawn_radius + randf() * 3.0)
	e.global_position = player.global_position + Vector3(sin(a) * r, 0.6, cos(a) * r)
	if glow > 0.0:
		Vfx.spawn_portal(e.global_position, _portal_color(archetype), glow)
	return e


## Arrivals borrow the archetype's own accent, so the colour of the light tells
## you what is coming before you can see it.
func _portal_color(archetype: int) -> Color:
	return EnemyScript.ARCHETYPES[archetype]["accent"]


## Downrange and inside the player's view, so an arrival can be seen rather than
## simply appearing behind them.
func _spawn_in_view(archetype: int, tier: int, distance: float, side: float,
		glow := 0.0) -> CharacterBody3D:
	var e := _make(archetype, tier)
	var cam := player.get_node_or_null("CameraController")
	var fwd := Vector3.FORWARD
	if cam:
		# This rig treats +Z as forward (see hero.gd).
		fwd = cam.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.001:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	e.global_position = player.global_position + fwd * distance + right * side + Vector3.UP * 0.6
	if glow > 0.0:
		Vfx.spawn_portal(e.global_position, _portal_color(archetype), glow)
	return e


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
	_kills += 1

	# Drops are physical: the quota only advances when the player walks over a
	# sphere, which is what makes clearing an area feel like collecting.
	var w: Resource = Game.current_world()
	var per_kill: int = w.drop_per_kill if w else 1
	var count: int = per_kill * (e.drops if "drops" in e else 1)
	var at: Vector3 = e.global_position if is_instance_valid(e) else player.global_position
	for i in count:
		_spawn_pickup(at + Vector3.UP * 1.2)

	if Game.state != Game.State.PLAYING or _scripted:
		return

	# Generic worlds top up as soon as the field thins, rather than waiting for
	# a full clear. The quota is the goal, not the wave.
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
