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
var _lead: Node = null
# --- level 3 ---
var _l3_mediums: Array = []
var _l3_reinforced: Array = []   ## which mediums have already called a small
var _l3_smalls: Array = []
var _l3_giant_a := -1
# --- level 4 ---
## Stays scripted forever: reinforcement is the level's rule, not an opening.
var _handover := false
var _l4_warrok: Node = null
var _l4_mediums: Array = []
var _l4_surged := false
var _l4_reinforced := {}   ## instance ids of mediums that already called help
var _spawned_t0 := 0
var _spawned_t1 := 0
var _spawned_t2 := 0


func _ready() -> void:
	ui.player = player
	ui._bind_player()
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

	# Fog and haze are off while clarity matters more than atmosphere. The
	# per-world values are still here and still applied, so flipping fog_on
	# brings the mood back without re-tuning anything.
	env.fog_enabled = w.fog_on
	env.volumetric_fog_enabled = w.fog_on
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

	# A drone tuned per world. Silence between fights makes a level feel like
	# a test scene; this makes it feel like somewhere.
	Sfx.start_bed(1.0 + float(Game.world_index) * 0.22, -24.0)

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
	if Game.world_index == 3:
		_check_long_night()
		return
	if Game.world_index == 2:
		_check_dust_shallows()
		return
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
	if Game.world_index == 3:
		await _beats_long_night(b)
	elif Game.world_index == 2:
		await _beats_dust_shallows(b)
	elif Game.world_index == 1:
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
			# Two smalls to pin, one 2.5x heavy to swing. All in frame already.
			var g1 := _prepare(HUSK, 0, 1)          # small Pumpkinhulk
			g1.role_side = -1.0
			g1.role_speed = 2.1
			_place(g1, 0)
			_face_in_view(g1, 11.0, -4.0)
			Vfx.spawn_portal(g1.global_position, Color(1.0, 0.62, 0.18), 0.9)

			var g2 := _prepare(HUSK, 0, 0)          # small Mutant
			g2.role_side = 1.0
			g2.role_speed = 2.1
			_place(g2, 0)
			_face_in_view(g2, 12.0, 4.0)
			Vfx.spawn_portal(g2.global_position, Color(1.0, 0.62, 0.18), 0.9)

			var sm := _prepare(JUGGERNAUT, 1, 1)    # 2.5x Pumpkinhulk
			sm.role_scale = 2.5
			sm.role_speed = 1.35
			_place(sm, 1)
			_face_in_view(sm, 15.0, 0.0)
			Vfx.spawn_portal(sm.global_position, Color(1.0, 0.45, 0.10), 1.8)
			sm.smashed.connect(_on_smash)
			_smasher = sm

			_grabbers = [g1, g2]
			ui.show_message("THEY WERE WAITING")

			# A beat to register the ambush before anything moves. Being grabbed
			# the instant you arrive reads as a bug, not a trap.
			await _delay(1.5)
			for g in _grabbers:
				if is_instance_valid(g):
					g.role = g.Role.CHARGE
			if is_instance_valid(_smasher):
				_smasher.role = _smasher.Role.STALK
		1:
			ui.show_message("HELD")
		2:
			# Thrown clear, into a field that is already occupied.
			await _delay(0.8)
			ui.show_message("GET UP")
			for i in 8:
				await _delay(0.22)
				_spawn_near(HUSK if i % 2 == 0 else STALKER, 0, 13.0 + randf() * 9.0)
			# One 2x Mutant anchors the aftermath; wearing it down summons the
			# next heavy, and only then does the world go random.
			var lead := _prepare(RAVAGER, 1, 0)
			_place(lead, 1)
			_spot_near(lead, 16.0)
			Vfx.spawn_portal(lead.global_position, Color(1.0, 0.45, 0.9), 1.2)
			_lead = lead
		3:
			ui.show_message("ANOTHER ONE")
			var pk := _prepare(JUGGERNAUT, 1, 1)
			_place(pk, 1)
			_spot_near(pk, 18.0)
			Vfx.spawn_portal(pk.global_position, Color(1.0, 0.45, 0.10), 1.5)
		4:
			# Handing over to the generic loop from here.
			_scripted = false
			_start_next_wave()


## Places an already-added enemy downrange and in the player's view.
func _face_in_view(e: Node3D, distance: float, side: float) -> void:
	var cam := player.get_node_or_null("CameraController")
	var fwd := Vector3.FORWARD
	if cam:
		fwd = cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.001 else Vector3.FORWARD
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	e.global_position = player.global_position + fwd * distance + right * side + Vector3.UP * 0.6


func _spot_near(e: Node3D, radius: float) -> void:
	var a := randf() * TAU
	e.global_position = player.global_position + Vector3(sin(a) * radius, 0.6, cos(a) * radius)


# --- Level 4: the long night ----------------------------------------------
#
# All four species at 2x, close together. Five seconds in, a 4x Warrok arrives
# downrange with a huge light. Wound it to 53% and the level 2 ambush repeats
# mid-fight. After that the world goes random — but only mediums and giants
# spawn, and minis are called solely by a wounded medium, and carry no meat.

func _beats_long_night(b: int) -> void:
	match b:
		0:
			_l4_reinforced.clear()
			_l4_mediums.clear()
			ui.show_message("ALL OF THEM")
			for c in [0, 1, 2, 3]:
				await _delay(0.3)
				var e := _prepare(RAVAGER if c % 2 == 0 else HUSK, 1, c)
				_place(e, 1)
				# Close together, so the opening is one crowd, not four fights.
				_face_in_view(e, 12.0 + randf() * 2.0, -5.0 + float(c) * 3.4)
				Vfx.spawn_portal(e.global_position, _portal_color(HUSK), 1.0)
				_l4_mediums.append(e)

			await _delay(5.0)
			ui.show_message("SOMETHING IS COMING")
			var wk := _prepare(JUGGERNAUT, 2, 3)      # 4x Warrok
			_place(wk, 2)
			_face_in_view(wk, 26.0, 0.0)
			Vfx.spawn_portal(wk.global_position, Color(1.0, 0.42, 0.08), 3.2)
			_l4_warrok = wk
		1:
			# The ambush again, in the middle of an ongoing fight.
			ui.show_message("NOT THIS AGAIN")
			_grabbers.clear()
			var g1 := _prepare(HUSK, 0, 1)
			g1.role_side = -1.0
			g1.role_speed = 2.1
			g1.drops = 0
			_place(g1, 0)
			_face_in_view(g1, 10.0, -4.0)
			Vfx.spawn_portal(g1.global_position, Color(1.0, 0.62, 0.18), 0.9)

			var g2 := _prepare(HUSK, 0, 0)
			g2.role_side = 1.0
			g2.role_speed = 2.1
			g2.drops = 0
			_place(g2, 0)
			_face_in_view(g2, 11.0, 4.0)
			Vfx.spawn_portal(g2.global_position, Color(1.0, 0.62, 0.18), 0.9)

			var sm := _prepare(JUGGERNAUT, 1, 1)
			sm.role_scale = 2.5
			sm.role_speed = 1.35
			_place(sm, 1)
			_face_in_view(sm, 14.0, 0.0)
			Vfx.spawn_portal(sm.global_position, Color(1.0, 0.45, 0.10), 1.8)
			sm.smashed.connect(_on_smash)
			_smasher = sm
			_grabbers = [g1, g2]

			await _delay(1.2)
			for g in _grabbers:
				if is_instance_valid(g):
					g.role = g.Role.CHARGE
			if is_instance_valid(_smasher):
				_smasher.role = _smasher.Role.STALK
		2:
			# Random from here, but the level keeps its own rules.
			ui.show_message("NO END TO THEM")
			_handover = true
			_start_next_wave()


func _check_long_night() -> void:
	# A wounded medium calls a mini. It runs for every medium in the level, not
	# just the scripted four — and those minis carry no meat, so the quota can
	# only come from mediums and giants.
	for e in get_tree().get_nodes_in_group("enemies"):
		if not e.is_alive() or e.tier != 1:
			continue
		var id := e.get_instance_id()
		if _l4_reinforced.has(id):
			continue
		if e.health <= e.max_health * 0.3:
			_l4_reinforced[id] = true
			var mini := _prepare(STALKER, 0, e.creature)
			mini.drops = 0
			_place(mini, 0)
			_spot_near(mini, 8.0 + randf() * 4.0)
			Vfx.spawn_portal(mini.global_position, _portal_color(STALKER), 0.4)

	# A last surge with the quota in sight, so the level does not trail off into
	# an easy final stretch.
	if not _l4_surged and Game.collected >= 29:
		_l4_surged = true
		_l4_surge()

	if _beat_locked:
		return

	match _beat:
		0:
			# The trap springs when the LAST of the opening four is worn to 53%,
			# so it lands at the end of that fight rather than during it.
			var live := []
			for m in _l4_mediums:
				if is_instance_valid(m) and m.is_alive():
					live.append(m)
			if _l4_mediums.size() == 4 and live.size() <= 1:
				if live.is_empty():
					_run_beat(1)
				elif live[0].health <= live[0].max_health * 0.53:
					_run_beat(1)
		1:
			# The smash ends this beat; _on_smash advances it. If the heavy dies
			# first, do not stall.
			if not is_instance_valid(_smasher) or not _smasher.is_alive():
				_release_grabbers()
				_run_beat(2)


# --- Level 3: the shallows -------------------------------------------------
#
# Three 2x monsters, one of each species. Wound any of them to 80% and it calls
# a small. Kill two and something 4x wades in. Clear the rest and a second 4x,
# a different species, follows. Then the world goes random.

func _beats_dust_shallows(b: int) -> void:
	match b:
		0:
			_l3_mediums.clear()
			_l3_reinforced.clear()
			_l3_smalls.clear()
			ui.show_message("THREE OF THEM")
			# One of each species so the roster reads immediately.
			for c in [0, 1, 2]:
				await _delay(0.45)
				var e := _prepare(RAVAGER if c == 0 else HUSK, 1, c)
				_place(e, 1)
				_spot_near(e, 13.0 + randf() * 4.0)
				Vfx.spawn_portal(e.global_position, _portal_color(HUSK), 1.1)
				_l3_mediums.append(e)
				_l3_reinforced.append(false)
		1:
			ui.show_message("SOMETHING LARGER")
			_l3_giant_a = randi() % 3
			var g := _prepare(JUGGERNAUT, 2, _l3_giant_a)
			_place(g, 2)
			_spot_near(g, 20.0)
			Vfx.spawn_portal(g.global_position, Color(1.0, 0.45, 0.10), 1.9)
		2:
			ui.show_message("AND ANOTHER")
			# Deliberately a different species from the first, so the second
			# arrival is not a repeat.
			var others: Array = [0, 1, 2].filter(func(i): return i != _l3_giant_a)
			var pick: int = others[randi() % others.size()]
			var g2 := _prepare(JUGGERNAUT, 2, pick)
			_place(g2, 2)
			_spot_near(g2, 22.0)
			Vfx.spawn_portal(g2.global_position, Color(1.0, 0.45, 0.10), 1.9)
		3:
			# Random spawning from here.
			_scripted = false
			_start_next_wave()


func _check_dust_shallows() -> void:
	# Runs every frame regardless of beat: a medium can cross 80% at any point.
	for i in _l3_mediums.size():
		if i >= _l3_reinforced.size() or _l3_reinforced[i]:
			continue
		var m = _l3_mediums[i]
		if not is_instance_valid(m) or not m.is_alive():
			continue
		if m.health <= m.max_health * 0.8:
			_l3_reinforced[i] = true
			var sm := _prepare(STALKER, 0, m.creature)
			_place(sm, 0)
			_spot_near(sm, 9.0 + randf() * 4.0)
			Vfx.spawn_portal(sm.global_position, _portal_color(STALKER), 0.5)
			_l3_smalls.append(sm)

	if _beat_locked:
		return

	match _beat:
		0:
			if _l3_mediums.size() >= 3 and _dead_count(_l3_mediums) >= 2:
				_run_beat(1)
		1:
			if _dead_count(_l3_mediums) >= _l3_mediums.size() 			and _dead_count(_l3_smalls) >= _l3_smalls.size():
				_run_beat(2)
		2:
			if _alive <= 2:
				_run_beat(3)


## Two giants and two minis, all random species, once the quota is close.
func _l4_surge() -> void:
	ui.show_message("THEY KNOW YOU ARE LEAVING")
	for i in 2:
		var g := _prepare(JUGGERNAUT, 2, randi() % 4)
		_place(g, 2)
		_spot_near(g, 18.0 + randf() * 6.0)
		Vfx.spawn_portal(g.global_position, Color(1.0, 0.42, 0.08), 2.2)
	for i in 2:
		var m := _prepare(STALKER, 0, randi() % 4)
		m.drops = 0
		_place(m, 0)
		_spot_near(m, 11.0 + randf() * 4.0)
		Vfx.spawn_portal(m.global_position, _portal_color(STALKER), 0.5)


func _dead_count(list: Array) -> int:
	var n := 0
	for e in list:
		if not is_instance_valid(e) or not e.is_alive():
			n += 1
	return n


func _check_open_mouth() -> void:
	match _beat:
		0:
			if _beat_locked:
				return
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
		2:
			# Wearing the lead Mutant to 60% calls in the next heavy.
			if not is_instance_valid(_lead) or not _lead.is_alive():
				_run_beat(3)
			elif _lead.health <= _lead.max_health * 0.6:
				_run_beat(3)
		3:
			if _alive <= 3:
				_run_beat(4)


func _on_smash(_e: Node) -> void:
	var next := 2 if Game.world_index != 3 else 2
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

## Instantiates and configures WITHOUT adding to the tree. Creature and scale
## are consumed in _enter_tree/_ready, so they must be set before that.
func _prepare(archetype: int, tier: int, creature := -1) -> CharacterBody3D:
	var e: CharacterBody3D = enemy_scene.instantiate()
	e.set_creature(creature if creature >= 0 else _roll_weighted(_world_weights("creature_weights")))
	e.set_archetype(archetype)
	e.set_tier(tier)
	return e


func _make(archetype: int, tier: int) -> CharacterBody3D:
	return _place(_prepare(archetype, tier), tier)


func _place(e: CharacterBody3D, tier: int) -> CharacterBody3D:
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
	var at: Vector3 = e.global_position if is_instance_valid(e) else player.global_position

	# In the long night a mini carries no meat at all — it carries a health orb.
	# That is what makes the small ones worth killing without making them a way
	# to farm the quota.
	if Game.world_index == 3 and "tier" in e and e.tier == 0:
		_spawn_pickup(at + Vector3.UP * 1.2, true)
		if Game.state != Game.State.PLAYING or (_scripted and not _handover):
			return
	else:
		var count: int = per_kill * (e.drops if "drops" in e else 1)
		for i in count:
			_spawn_pickup(at + Vector3.UP * 1.2)

	if Game.state != Game.State.PLAYING or (_scripted and not _handover):
		return

	# Generic worlds top up as soon as the field thins, rather than waiting for
	# a full clear. The quota is the goal, not the wave.
	if _alive <= 1 and not _spawning:
		await get_tree().create_timer(wave_break).timeout
		if is_inside_tree():
			_start_next_wave()


func _spawn_pickup(at: Vector3, health := false) -> void:
	var p := Node3D.new()
	p.set_script(PickupScript)
	p.kind = 1 if health else 0      # Pickup.Kind.HEALTH / INGREDIENT
	add_child(p)
	p.global_position = at
	p.player = player
	if not health:
		var w: Resource = Game.current_world()
		if w:
			p.color = w.accent_color.lightened(0.25)
