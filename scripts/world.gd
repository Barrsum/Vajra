extends Node3D
## Procedural arena generator, themed per world.
##
## Built in code because at this stage layouts change every iteration and a seed
## plus a few numbers re-tunes faster than a hundred hand-placed nodes. When real
## hand-built levels arrive they replace this entirely via WorldDef.arena_scene —
## this generator is scaffolding, not the destination.

const WorldDefScript := preload("res://scripts/world_def.gd")
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
	var rock := _mat(_prop_color(), 0.95)
	var dark := _mat(_prop_color().darkened(0.45), 0.98)

	# A ring of rock forming a bowl, open to a bright sky.
	var count := 40
	for i in count:
		var a := TAU * float(i) / float(count)
		var r := _half * 0.96
		var h := _rng.randf_range(14.0, 26.0)
		_box(Vector3(_rng.randf_range(8.0, 16.0), h, _rng.randf_range(8.0, 16.0)),
			Vector3(sin(a) * r, h * 0.5 - 2.0, cos(a) * r), dark, true, a)

	# Stalagmites, and a few hanging columns to imply a roof edge.
	for i in 30:
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

	for i in 14:
		var p := _spot(14.0, 20.0)
		var h := _rng.randf_range(10.0, 20.0)
		_cyl(_rng.randf_range(1.0, 2.4), h, p + Vector3(0, 22.0 - h * 0.5, 0), dark, false)

	for i in 18:
		var p := _spot(6.0, 8.0)
		_box(Vector3(_rng.randf_range(1.0, 3.0), _rng.randf_range(0.6, 1.6),
			_rng.randf_range(1.0, 3.0)), p + Vector3(0, 0.5, 0), rock, false, _rng.randf() * TAU)


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


func _night() -> void:
	var ruin := _mat(_prop_color(), 0.95)
	var lamp_col := _accent_color()
	var lamp := _mat(lamp_col, 0.4, 0.0, 3.0)

	_perimeter(14.0, 2.0, _mat(_ground_color().darkened(0.4)))

	# Broken walls to break sightlines.
	for i in 34:
		var p := _spot(7.0, 11.0)
		var h := _rng.randf_range(2.0, 7.0)
		_box(Vector3(_rng.randf_range(3.0, 9.0), h, _rng.randf_range(0.6, 1.2)),
			p + Vector3(0, h * 0.5, 0), ruin, true, _rng.randf() * TAU)

	# Rubble.
	for i in 44:
		var p := _spot(4.0, 6.0)
		var s := _rng.randf_range(0.4, 1.6)
		_box(Vector3(s, s * 0.7, s), p + Vector3(0, s * 0.35, 0), ruin, false, _rng.randf() * TAU)

	# The only light sources: emissive lamps with a small point light each. They
	# are what make a dark level readable instead of merely dark.
	for i in 10:
		var p := _spot(10.0, 14.0)
		_cyl(0.2, 7.0, p + Vector3(0, 3.5, 0), _mat(Color(0.1, 0.1, 0.12)), false)
		_sphere(0.55, p + Vector3(0, 7.2, 0), lamp)
		var pl := OmniLight3D.new()
		pl.light_color = lamp_col
		pl.light_energy = 6.0
		pl.omni_range = 22.0
		add_child(pl)
		pl.position = p + Vector3(0, 7.2, 0)


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
