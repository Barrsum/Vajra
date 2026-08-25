extends Node3D
## Procedural arena generator, themed per world.
##
## Built in code because at this stage layouts change every iteration and a seed
## plus a few numbers re-tunes faster than a hundred hand-placed nodes. When real
## hand-built levels arrive they replace this entirely via WorldDef.arena_scene —
## this generator is scaffolding, not the destination.

const WorldDefScript := preload("res://scripts/world_def.gd")
const Foliage := preload("res://scripts/foliage.gd")
const CampfireScript := preload("res://scripts/campfire.gd")
const Props := preload("res://scripts/props.gd")
const Scatter := preload("res://scripts/ground_scatter.gd")
const THEME_FOREST := 0
const THEME_CAVE := 1
const THEME_OCEAN := 2
const THEME_NIGHT := 3
const THEME_STREET := 4

@export var regenerate := false : set = _set_regenerate
@export var seed_value := 20260810
## Used when running the scene directly, outside a run.
## Theme ids are plain ints: enum access through a preloaded script const
## does not resolve in GDScript, and the failure kills the whole parse.
@export_enum("Forest", "Cave", "Ocean", "Night", "Street") var fallback_theme := 0

var _rng := RandomNumberGenerator.new()
var _def: Resource = null
var _size := 120.0
var _half := 60.0
## Kept so generated trees can replace them when the night set exists.
var _procedural_trees: Array = []


func _set_regenerate(v: bool) -> void:
	regenerate = false
	if is_inside_tree():
		build()


func _ready() -> void:
	build()


func build() -> void:
	for c in get_children():
		c.free()

	_def = Game.current_world() if Engine.has_singleton("Game") or Game else null
	_size = _def.arena_size if _def else 120.0
	_half = _size * 0.5
	_rng.seed = seed_value + (Game.world_index * 977 if _def else 0)

	var theme: int = _def.theme if _def else fallback_theme
	_ground(theme)
	match theme:
		THEME_FOREST: _forest()
		THEME_CAVE: _cave()
		THEME_OCEAN: _ocean()
		THEME_NIGHT: _night()
		_: _street()


# --- helpers ----------------------------------------------------------------

## One shared noise texture, triplanar-mapped onto roughness. Flat roughness is
## what makes untextured boxes read as plastic; breaking it up costs nothing and
## gives every surface some grain.
static var _noise_tex: NoiseTexture2D = null

func _noise() -> NoiseTexture2D:
	if _noise_tex == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX
		n.frequency = 0.035
		n.fractal_octaves = 3
		var t := NoiseTexture2D.new()
		t.width = 256
		t.height = 256
		t.seamless = true
		t.noise = n
		# Roughness textures MULTIPLY, so raw noise averaging 0.5 halves roughness
		# and turns terrain glossy. Remap into 0.72-1.0: visible grain, still matte.
		var grad := Gradient.new()
		grad.set_color(0, Color(0.72, 0.72, 0.72))
		grad.set_color(1, Color(1.0, 1.0, 1.0))
		t.color_ramp = grad
		_noise_tex = t
	return _noise_tex


func _mat(c: Color, rough := 0.92, metal := 0.0, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	m.roughness_texture = _noise()
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.09, 0.09, 0.09)
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	return m


func _ground_color() -> Color:
	return _def.ground_color if _def else Color(0.3, 0.3, 0.28)

func _prop_color() -> Color:
	return _def.prop_color if _def else Color(0.5, 0.45, 0.4)

func _accent_color() -> Color:
	return _def.accent_color if _def else Color(0.2, 0.5, 0.25)


func _box(size: Vector3, pos: Vector3, mat: StandardMaterial3D, solid := true, yaw := 0.0) -> Node3D:
	var root: Node3D
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
		body.add_child(col)
		root = body
	else:
		root = Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	root.add_child(mi)
	add_child(root)
	root.position = pos
	root.rotation.y = yaw
	return root


func _cyl(radius: float, height: float, pos: Vector3, mat: StandardMaterial3D, solid := true) -> Node3D:
	var root: Node3D
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var col := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = height
		col.shape = shape
		body.add_child(col)
		root = body
	else:
		root = Node3D.new()
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius * 1.15
	cm.height = height
	mi.mesh = cm
	mi.material_override = mat
	root.add_child(mi)
	add_child(root)
	root.position = pos
	return root


func _sphere(radius: float, pos: Vector3, mat: StandardMaterial3D) -> Node3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 10
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = mat
	add_child(mi)
	mi.position = pos
	return mi


## Random point on the arena floor, keeping clear of the centre spawn.
func _spot(margin := 8.0, clear_centre := 10.0) -> Vector3:
	for i in 20:
		var p := Vector3(
			_rng.randf_range(-_half + margin, _half - margin), 0,
			_rng.randf_range(-_half + margin, _half - margin))
		if Vector2(p.x, p.z).length() > clear_centre:
			return p
	return Vector3(_half * 0.5, 0, _half * 0.5)


## Plants one foliage-shader tree. These are the Synty-style trees: a real
## ArrayMesh with baked vertex colours, not the primitive blobs used for the
## background woods. They are expensive enough per-vertex that a handful per
## level is the point — they are set dressing you walk up to, not the forest.
func _tree(pos: Vector3, height: float, canopy: float, mat: ShaderMaterial,
		blobs := 3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Foliage.build_tree(_rng, height, canopy, blobs)
	mi.material_override = mat
	# The wind deforms vertices on the GPU, so Godot's culling box has to be
	# grown by hand or the whole tree pops out of view when its origin leaves
	# the frustum but its swaying crown has not.
	mi.extra_cull_margin = canopy * 2.0
	add_child(mi)
	mi.position = pos
	mi.rotation.y = _rng.randf() * TAU
	return mi


func _ground(_theme: int) -> void:
	_box(Vector3(_size, 1.0, _size), Vector3(0, -0.5, 0), _mat(_ground_color()))


## Four walls enclosing the arena. `h` sets how boxed-in it feels.
func _perimeter(h: float, thickness: float, mat: StandardMaterial3D) -> void:
	for s in [-1.0, 1.0]:
		_box(Vector3(_size + thickness * 2.0, h, thickness),
			Vector3(0, h * 0.5, s * _half), mat)
		_box(Vector3(thickness, h, _size + thickness * 2.0),
			Vector3(s * _half, h * 0.5, 0), mat)


# --- themes -----------------------------------------------------------------

func _forest() -> void:
	var bark := _mat(Color(0.20, 0.14, 0.10))
	var wood := _mat(Color(0.34, 0.24, 0.15))

	# Wooden fence: posts with two rails between them.
	var step := 6.0
	var x := -_half
	while x <= _half:
		for s in [-1.0, 1.0]:
			_box(Vector3(0.4, 3.0, 0.4), Vector3(x, 1.5, s * _half), wood, false)
			_box(Vector3(0.4, 3.0, 0.4), Vector3(s * _half, 1.5, x), wood, false)
		x += step
	for s in [-1.0, 1.0]:
		for h in [1.2, 2.3]:
			_box(Vector3(_size, 0.22, 0.22), Vector3(0, h, s * _half), wood, false)
			_box(Vector3(0.22, 0.22, _size), Vector3(s * _half, h, 0), wood, false)
	_perimeter(4.0, 1.0, _mat(_ground_color().darkened(0.3)))

	# Trees: trunk plus two stacked canopy blobs.
	for i in 46:
		var p := _spot(6.0, 12.0)
		var th := _rng.randf_range(5.0, 11.0)
		_cyl(_rng.randf_range(0.35, 0.7), th, p + Vector3(0, th * 0.5, 0), bark)
		var leaf := _mat(_accent_color().lerp(Color(0.1, 0.3, 0.12), _rng.randf() * 0.5), 0.95)
		_sphere(_rng.randf_range(2.0, 3.4), p + Vector3(0, th * 0.95, 0), leaf)
		_sphere(_rng.randf_range(1.4, 2.4), p + Vector3(
			_rng.randf_range(-1.2, 1.2), th * 1.25, _rng.randf_range(-1.2, 1.2)), leaf)

	# One foliage-shader tree, deliberately larger than the background woods so
	# it reads as a landmark rather than more scenery.
	var canopy := Foliage.make_material(
		Color(0.24, 0.52, 0.20), Color(0.26, 0.18, 0.12))
	_tree(_spot(18.0, 22.0), 13.0, 5.2, canopy, 4)

	# Bushes and rocks.
	for i in 40:
		var p := _spot(4.0, 6.0)
		if _rng.randf() < 0.6:
			_sphere(_rng.randf_range(0.6, 1.4), p + Vector3(0, 0.4, 0),
				_mat(_accent_color().darkened(_rng.randf() * 0.4), 0.95))
		else:
			_box(Vector3(_rng.randf_range(0.8, 2.0), _rng.randf_range(0.5, 1.2),
				_rng.randf_range(0.8, 2.0)), p + Vector3(0, 0.4, 0),
				_mat(_prop_color()), false, _rng.randf() * TAU)


func _cave() -> void:
	# Once a real asset set dresses this world, the procedural filler goes.
	# Untextured cones and boxes standing among photoscanned rock do not read
	# as a different art style, they read as unfinished — which is what they
	# are. The wall stays because nothing generated replaces it yet, but it
	# goes darker so it sits back as cliff rather than competing.
	var dressed: bool = _prop_set() != "" and not OS.has_environment("VAJRA_NO_DRESS")
	var rock := _mat(_prop_color(), 0.95)
	var dark := _mat(_prop_color().darkened(0.45 if not dressed else 0.72), 0.98)

	# A ring of rock forming a bowl, open to a bright sky.
	var count := 40
	for i in count:
		var a := TAU * float(i) / float(count)
		var r := _half * 0.96
		var h := _rng.randf_range(14.0, 26.0)
		_box(Vector3(_rng.randf_range(8.0, 16.0), h, _rng.randf_range(8.0, 16.0)),
			Vector3(sin(a) * r, h * 0.5 - 2.0, cos(a) * r), dark, true, a)

	# Stalagmites, and a few hanging columns to imply a roof edge.
	for i in (0 if dressed else 30):
		var p := _spot(8.0, 12.0)
		var h := _rng.randf_range(2.5, 9.0)
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05
		cm.bottom_radius = _rng.randf_range(0.8, 2.0)
		cm.height = h
		cone.mesh = cm
		cone.material_override = rock
		add_child(cone)
		cone.position = p + Vector3(0, h * 0.5, 0)

	# Hanging columns, or sky islands where a set provides them. The columns
	# were always a stand-in for "there is more world above you"; a floating
	# island says it far better and does not need a roof to hang from.
	if dressed and Props.has_any(_prop_set() + "_sky"):
		_sky_islands(_prop_set())
	else:
		for i in 14:
			var p := _spot(14.0, 20.0)
			var h := _rng.randf_range(10.0, 20.0)
			_cyl(_rng.randf_range(1.0, 2.4), h,
				p + Vector3(0, 22.0 - h * 0.5, 0), dark, false)

	for i in (0 if dressed else 18):
		var p := _spot(6.0, 8.0)
		_box(Vector3(_rng.randf_range(1.0, 3.0), _rng.randf_range(0.6, 1.6),
			_rng.randf_range(1.0, 3.0)), p + Vector3(0, 0.5, 0), rock, false, _rng.randf() * TAU)

	# Two trees clinging to the rock. Paler and sparser than the forest's —
	# things growing at a cave mouth get less light.
	var scrub := Foliage.make_material(
		Color(0.30, 0.44, 0.26), Color(0.30, 0.26, 0.22))
	for i in (0 if dressed else 2):
		_procedural_trees.append(_tree(_spot(16.0, 20.0),
			_rng.randf_range(9.0, 12.0), _rng.randf_range(3.4, 4.4), scrub, 3))

	if not OS.has_environment("VAJRA_NO_DRESS"):
		# The rock ring sits at 0.96 of the half-size, so keep generated props
		# inside it — a tree spawned in the wall is a tree in a wall.
		_dress(_half * 0.86, 6.0)


func _ocean() -> void:
	var wet := _mat(_ground_color().lightened(0.05), 0.55)
	var stone := _mat(_prop_color(), 0.92)

	# A shallow water plane just above the floor, and haze-blue beyond the edge.
	var water := _mat(_accent_color(), 0.15, 0.0)
	water.albedo_color.a = 0.55
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var wm := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(_size * 6.0, _size * 6.0)
	wm.mesh = pm
	wm.material_override = water
	add_child(wm)
	wm.position = Vector3(0, 0.12, 0)

	# Sandbars: low wide slabs the fight happens on.
	for i in 26:
		var p := _spot(5.0, 7.0)
		_box(Vector3(_rng.randf_range(4.0, 12.0), _rng.randf_range(0.3, 0.9),
			_rng.randf_range(4.0, 12.0)), p + Vector3(0, 0.2, 0), wet, false, _rng.randf() * TAU)

	# Rock stacks and driftwood.
	for i in 30:
		var p := _spot(6.0, 10.0)
		var h := _rng.randf_range(1.5, 7.0)
		_box(Vector3(_rng.randf_range(1.5, 4.0), h, _rng.randf_range(1.5, 4.0)),
			p + Vector3(0, h * 0.5, 0), stone, true, _rng.randf() * TAU)

	_perimeter(9.0, 2.0, stone)

	# Three dead trees on the dry seabed. Bleached leaves and a grey trunk —
	# the same shader, saying something completely different.
	var dead := Foliage.make_material(
		Color(0.58, 0.52, 0.36), Color(0.44, 0.40, 0.35))
	for i in 3:
		_tree(_spot(15.0, 18.0), _rng.randf_range(8.0, 14.0),
			_rng.randf_range(3.0, 5.0), dead, 3)


## Level 4: a night garden.
##
## Readable in the dark is the whole brief. A square walking path just inside
## the boundary with lamps along it draws the edge; a second, shorter ring of
## lamps and a scatter of campfires light the middle, which is where the fight
## actually happens and which the first pass left far too dark.
func _night() -> void:
	var lamp_col := _accent_color()
	if Props.has_any("night_ground"):
		# A winter set needs cold lamps. Orange lamplight over pale ground
		# reads as sand, and it also puts the level's warm light everywhere,
		# which leaves the campfires with nothing to contrast against.
		lamp_col = Color(0.72, 0.84, 1.00)
	var lamp_mat := _mat(lamp_col, 0.4, 0.0, 3.0)
	var post := _mat(Color(0.10, 0.10, 0.12))

	# A low hedge rather than a wall, so the sky stays visible.
	_perimeter(2.6, 1.2, _mat(_ground_color().darkened(0.25)))

	# --- the walking path ---------------------------------------------------
	var pr := _half * 0.74          ## centre to path centreline
	var pw := 5.0                    ## path width
	var paving := _mat(_prop_color().lightened(0.22), 0.85)
	for sgn in [-1.0, 1.0]:
		_box(Vector3(pr * 2.0 + pw, 0.12, pw), Vector3(0, 0.06, sgn * pr), paving, false)
		_box(Vector3(pw, 0.12, pr * 2.0 + pw), Vector3(sgn * pr, 0.06, 0), paving, false)

	# --- lamps --------------------------------------------------------------
	# Two rings. The outer one on the path draws the border; the inner one is
	# purely to stop the middle of the arena being a black hole.
	_lamp_ring(pr + pw * 0.5, 7, 6.0, 6.5, 26.0, lamp_col, lamp_mat, post)
	_lamp_ring(_half * 0.34, 4, 5.0, 5.0, 24.0, lamp_col, lamp_mat, post)

	# --- campfires ----------------------------------------------------------
	# Four big volumetric fires between the two lamp rings. Each carries its own
	# barrier, so they are obstacles you fight around — no damage, no trigger,
	# just somewhere neither you nor anything else can stand.
	var fire_r := _half * 0.52
	for i in 4:
		var a := TAU * (float(i) + 0.5) / 4.0
		var f: Node3D = CampfireScript.new()
		f.barrier_radius = 3.0
		f.flame_height = 3.2
		f.flame_width = 2.6
		f.volumetric = true
		f.light_energy = 9.0
		add_child(f)
		f.position = Vector3(cos(a), 0, sin(a)) * fire_r

	# Small braziers on the path corners, on the cheap flame shader.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var b: Node3D = CampfireScript.new()
			b.barrier_radius = 1.1
			b.flame_height = 1.9
			b.flame_width = 1.0
			b.volumetric = false
			b.light_energy = 4.0
			b.light_color = Color(1.0, 0.70, 0.34)
			add_child(b)
			b.position = Vector3(sx * pr, 0.55, sz * pr)
			# A stone plinth under each, so they are not floating flames.
			_cyl(0.7, 1.1, Vector3(sx * pr, 0.55, sz * pr), post, false)

	# --- trees --------------------------------------------------------------
	# A proper stand of them now. Kept out of the middle and off the path.
	var glow_leaf := Color(0.42, 0.95, 0.62)
	var garden := Foliage.make_material(
		glow_leaf, Color(0.18, 0.16, 0.20), 0.32, glow_leaf)
	var placed := 0
	var tries := 0
	while placed < 22 and tries < 400:
		tries += 1
		var p := Vector3(
			_rng.randf_range(-pr + pw, pr - pw), 0.0,
			_rng.randf_range(-pr + pw, pr - pw))
		if Vector2(p.x, p.z).length() < 15.0:
			continue
		# Not on top of a campfire.
		var clash := false
		for i in 4:
			var a := TAU * (float(i) + 0.5) / 4.0
			if p.distance_to(Vector3(cos(a), 0, sin(a)) * fire_r) < 8.0:
				clash = true
				break
		if clash:
			continue
		placed += 1
		var h := _rng.randf_range(8.0, 15.0)
		var canopy := _rng.randf_range(3.2, 5.4)
		_procedural_trees.append(_tree(p, h, canopy, garden, 4))
		# Only every third canopy gets a light. Twenty-two omni lights in one
		# scene is a real cost, and the emission carries the look on its own.
		if placed % 3 == 0:
			var gl := OmniLight3D.new()
			gl.light_color = glow_leaf
			gl.light_energy = 2.6
			gl.omni_range = canopy * 3.6
			gl.shadow_enabled = false
			add_child(gl)
			gl.position = p + Vector3(0, h + canopy * 0.4, 0)

	# --- glowing things -----------------------------------------------------
	# Cheap emissive props, no lights attached. They read as glow because the
	# scene has bloom, and they give the dark ground something in it.
	var pods := [
		Color(0.45, 1.00, 0.70), Color(0.55, 0.80, 1.00),
		Color(1.00, 0.72, 0.35), Color(0.85, 0.55, 1.00),
	]
	for i in 60:
		var p := _spot(5.0, 8.0)
		if absf(p.x) > pr - pw or absf(p.z) > pr - pw:
			continue
		var c: Color = pods[_rng.randi() % pods.size()]
		var m := _mat(c, 0.35, 0.0, _rng.randf_range(2.0, 5.0))
		_sphere(_rng.randf_range(0.16, 0.42), p + Vector3(0, _rng.randf_range(0.2, 1.1), 0), m)

	# Glowing flower beds — skipped once a generated ground set exists. Bright
	# green slabs lying on snow read as untextured placeholder geometry, which
	# is exactly what they are.
	var bed_cols := [Color(0.30, 0.85, 0.55), Color(0.45, 0.60, 1.00)]
	for i in (0 if Props.has_any("night_ground") else 26):
		var p := _spot(8.0, 12.0)
		if absf(p.x) > pr - pw or absf(p.z) > pr - pw:
			continue
		var c: Color = bed_cols[_rng.randi() % bed_cols.size()]
		_box(Vector3(_rng.randf_range(2.0, 5.0), 0.5, _rng.randf_range(2.0, 5.0)),
			p + Vector3(0, 0.25, 0), _mat(c.darkened(0.35), 0.9, 0.0, 0.9),
			false, _rng.randf() * TAU)

	# Benches on the path.
	var bench := _mat(Color(0.24, 0.18, 0.13))
	for i in 6:
		var side := _rng.randi() % 4
		var t := _rng.randf_range(-pr * 0.8, pr * 0.8)
		var bp: Vector3
		var yaw := 0.0
		match side:
			0: bp = Vector3(t, 0, -pr)
			1: bp = Vector3(t, 0, pr)
			2:
				bp = Vector3(-pr, 0, t)
				yaw = PI * 0.5
			_:
				bp = Vector3(pr, 0, t)
				yaw = PI * 0.5
		_box(Vector3(2.4, 0.18, 0.7), bp + Vector3(0, 0.65, 0), bench, false, yaw)
		_box(Vector3(2.4, 0.6, 0.15), bp + Vector3(0, 1.0, 0), bench, false, yaw)

	# Generated assets last, so they can be told where everything else went.
	# VAJRA_NO_DRESS=1 builds the level without any generated assets. Kept
	# because it is the fastest way to tell an art problem from a logic one —
	# it is how the level 4 set-piece regression was pinned to scenery
	# collision in one run rather than by bisecting the dressing code.
	if not OS.has_environment("VAJRA_NO_DRESS"):
		# Campfires carry barriers, so nothing may spawn inside one — a tree in
		# a fire is a tree the player can see and never reach.
		var keep_out: Array = []
		for i in 4:
			var a := TAU * (float(i) + 0.5) / 4.0
			keep_out.append(Vector3(cos(a) * fire_r, sin(a) * fire_r, 7.0))
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				keep_out.append(Vector3(sx * pr, sz * pr, 4.0))
		_dress(pr, pw, keep_out)


## Lays the world's generated asset set over the built level.
##
## Order matters, and it is the order a real place is built in: ground first,
## everything else standing on it. Ground goes everywhere including under the
## props; rocks and trees keep out of the arena centre and off the fires;
## bushes fill what is left.
##
## Every step degrades to nothing when its category is empty, so the level
## still builds before any assets exist for it.
func _dress(path_r: float, path_w: float, keep_out: Array = []) -> void:
	var w: Resource = Game.current_world()
	var set_id: String = String(w.prop_set) if w != null else ""
	if set_id == "":
		return
	# Endless mode overlays a second set on top of the world's own. Held back
	# until the story is finished: it is a good look and a bad first
	# impression, because a snow drift in a cave reads as a bug until the game
	# has already told you the rules changed.
	var extra: String = Game.endless_set() if Game.endless else ""

	# --- ground ------------------------------------------------------------
	# Square, because the arena is: a disc of patches leaves the corners bare
	# and that is very visible from the middle. Sunk slightly so the rims bed
	# into the floor rather than standing on it.
	#
	# 16m patches rather than more small ones is a triangle-budget decision.
	# A patch costs ~19k triangles whatever size it is drawn at, so covering
	# the arena with big ones costs a fraction of covering it with small ones,
	# and at ground level nobody reads the difference.
	for key in _sets(set_id, extra):
		if not Props.has_any(key + "_ground"):
			continue
		var g := Scatter.scatter(self, key + "_ground", _half * 0.98,
			16.0, 1.35 if key == set_id else 0.4, _rng, 0.10, 0.0, [], true,
			key == set_id)
		if g != null:
			g.name = key.capitalize() + "Ground"

	# --- big rocks ---------------------------------------------------------
	# Placed, not scattered. There are only a handful and each is a landmark
	# you navigate by, so they want spreading deliberately rather than
	# clustering wherever the random happened to land. Solid, so they are cover.
	if Props.has_any(set_id + "_rock"):
		var rocks := 7
		for i in rocks:
			var a := TAU * float(i) / float(rocks) + _rng.randf_range(-0.3, 0.3)
			var r: float = _rng.randf_range(_half * 0.30, _half * 0.62)
			var at := Vector3(cos(a) * r, 0, sin(a) * r)
			if _blocked(at, keep_out):
				continue
			var h := _rng.randf_range(3.0, 6.5)
			# hull=true: a boulder you can run up and stand on, rather than an
			# invisible pillar the width of its widest point.
			#
			# Sunk 12%. Grounding puts the LOWEST vertex on the floor, which on
			# a slanted rock means it balances on one corner — you can see the
			# gap under the high side, and from a low angle you see straight
			# into the hollow shell. Bedding it in costs nothing and there is
			# no such thing as a boulder resting on a point.
			var rock := Props.spawn_solid(set_id + "_rock", h, 0.0, _rng, true,
				-0.12)
			if rock == null:
				continue
			add_child(rock)
			rock.position = Vector3(at.x, rock.position.y, at.z)
			keep_out.append(Vector3(at.x, at.z, h * 0.8))

	# A skirt of rocks around the rim. Without it the generated ground stops
	# dead against the built wall, and a hard line is the one thing a scatter
	# exists to prevent.
	if Props.has_any(set_id + "_rock"):
		var skirt := 14
		for i in skirt:
			var a := TAU * float(i) / float(skirt) + _rng.randf_range(-0.18, 0.18)
			var r: float = path_r * _rng.randf_range(0.94, 1.08)
			var at := Vector3(cos(a) * r, 0, sin(a) * r)
			var sh := _rng.randf_range(2.0, 5.0)
			var srock := Props.spawn_solid(set_id + "_rock", sh, 0.0, _rng, true,
				-0.14)
			if srock == null:
				continue
			add_child(srock)
			srock.position = Vector3(at.x, srock.position.y, at.z)

	# --- trees -------------------------------------------------------------
	# Replaces the procedural canopies rather than joining them. Mixing the two
	# looks worse than either alone — a low-poly blob beside a photoscanned
	# conifer reads as a bug, not as variety.
	if Props.has_any(set_id + "_tree"):
		for old in _procedural_trees:
			if is_instance_valid(old):
				old.queue_free()
		_procedural_trees.clear()

		var placed := 0
		var tries := 0
		while placed < 26 and tries < 600:
			tries += 1
			var p := Vector3(
				_rng.randf_range(-path_r + path_w, path_r - path_w), 0,
				_rng.randf_range(-path_r + path_w, path_r - path_w))
			# The middle is where the fight happens. Trees there are cover the
			# player did not ask for and the camera has to see through.
			if Vector2(p.x, p.z).length() < 17.0:
				continue
			if _blocked(p, keep_out):
				continue
			# Wide height spread. One tree species repeated is a forest; one
			# tree SIZE repeated is wallpaper.
			var h := _rng.randf_range(7.0, 17.0)
			var t := Props.spawn_solid(set_id + "_tree", h, h * 0.045, _rng)
			if t == null:
				continue
			add_child(t)
			t.position = Vector3(p.x, t.position.y, p.z)
			keep_out.append(Vector3(p.x, p.z, 5.0))
			placed += 1

	# --- bushes ------------------------------------------------------------
	# Scattered rather than placed, and deliberately NOT solid: they are ankle
	# height, and a player caught on invisible shrubbery mid-dodge is a bug
	# report every time.
	for key in _sets(set_id, extra):
		if not Props.has_any(key + "_bush"):
			continue
		var b := Scatter.scatter(self, key + "_bush", _half * 0.90,
			2.2, 0.34 if key == set_id else 0.14, _rng, 0.12, 14.0,
			keep_out, true)
		if b != null:
			b.name = key.capitalize() + "Bushes"


func _blocked(at: Vector3, zones: Array) -> bool:
	for z in zones:
		var v: Vector3 = z
		if Vector2(at.x, at.z).distance_to(Vector2(v.x, v.y)) < v.z:
			return true
	return false


## One square ring of lamps. `per_side` on each edge, so the light traces the
## shape rather than dotting it randomly.
func _lamp_ring(radius: float, per_side: int, height: float, energy: float,
		omni_range: float, col: Color, head: StandardMaterial3D,
		post: StandardMaterial3D) -> void:
	for side in 4:
		for i in per_side:
			var t: float = -radius + (2.0 * radius) * (float(i) + 0.5) / float(per_side)
			var p: Vector3
			match side:
				0: p = Vector3(t, 0, -radius)
				1: p = Vector3(t, 0, radius)
				2: p = Vector3(-radius, 0, t)
				_: p = Vector3(radius, 0, t)
			_cyl(0.16, height, p + Vector3(0, height * 0.5, 0), post, false)
			_sphere(0.5, p + Vector3(0, height + 0.2, 0), head)
			var pl := OmniLight3D.new()
			pl.light_color = col
			pl.light_energy = energy
			pl.omni_range = omni_range
			pl.shadow_enabled = false
			add_child(pl)
			pl.position = p + Vector3(0, height + 0.2, 0)


func _street() -> void:
	var half_w := 11.0
	_box(Vector3(half_w * 2.0, 1.0, _size), Vector3(0, -0.48, 0), _mat(Color(0.20, 0.18, 0.17)))
	for s in [-1.0, 1.0]:
		_box(Vector3(5.0, 0.34, _size), Vector3(s * (half_w + 2.5), 0.17, 0),
			_mat(Color(0.34, 0.31, 0.28)))
	for s in [-1.0, 1.0]:
		var z := -_half
		while z < _half:
			var d := _rng.randf_range(9.0, 20.0)
			var h := _rng.randf_range(10.0, 26.0)
			var w := _rng.randf_range(9.0, 15.0)
			_box(Vector3(w, h, d), Vector3(s * (half_w + 5.0 + w * 0.5), h * 0.5, z + d * 0.5),
				_mat(_prop_color().darkened(_rng.randf() * 0.3)))
			z += d + 0.5
	for i in 26:
		var p := _spot(4.0, 6.0)
		p.x = clampf(p.x, -half_w, half_w)
		var s := _rng.randf_range(0.5, 1.6)
		_box(Vector3(s, s * 0.7, s), p + Vector3(0, s * 0.35, 0), _mat(_prop_color()),
			false, _rng.randf() * TAU)


func _prop_set() -> String:
	var w: Resource = Game.current_world()
	return String(w.prop_set) if w != null else ""


## The world's own set, plus the endless overlay when there is one.
func _sets(own: String, extra: String) -> Array:
	if extra == "" or extra == own:
		return [own]
	return [own, extra]


## Floating islands overhead.
##
## Placed high and wide rather than densely: they are skyline, and the moment
## one is close enough to read as reachable the player will try to reach it.
## Spread across a band well outside the arena so they frame it instead of
## hanging over the fight.
func _sky_islands(set_id: String) -> void:
	var count := 9
	for i in count:
		var a := TAU * float(i) / float(count) + _rng.randf_range(-0.35, 0.35)
		var r: float = _half * _rng.randf_range(0.75, 1.55)
		var size := _rng.randf_range(14.0, 34.0)
		# No collision: an island you can land on is a platform, and this level
		# has no way up to one.
		var isle := Props.spawn(set_id + "_sky", size, _rng)
		if isle == null:
			continue
		add_child(isle)
		isle.position = Vector3(
			cos(a) * r,
			_rng.randf_range(34.0, 62.0),
			sin(a) * r)
		# Tipped, because a flat-bottomed slab reads as a floor tile in the
		# sky. A few degrees is enough to say "this is a broken piece of
		# something".
		isle.rotation.x = _rng.randf_range(-0.16, 0.16)
		isle.rotation.z = _rng.randf_range(-0.16, 0.16)
