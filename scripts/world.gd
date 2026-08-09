extends Node3D
## Generates a Delhi street blockout in code.
##
## Built procedurally rather than hand-placed because at this stage the layout
## changes every iteration — a seed and a few numbers is faster to re-tune than
## a hundred nodes in a scene file. Set `seed_value` to lock a layout you like.

@export var regenerate := false : set = _set_regenerate

@export_group("Street")
@export var street_length := 130.0
@export var street_half_width := 11.0
@export var seed_value := 20260809

@export_group("Density")
@export var rickshaws := 12
@export var stalls := 10
@export var debris := 26

var _rng := RandomNumberGenerator.new()


func _set_regenerate(v: bool) -> void:
	regenerate = false
	if is_inside_tree():
		build()


func _ready() -> void:
	build()


func build() -> void:
	for c in get_children():
		c.free()
	_rng.seed = seed_value

	_road()
	_buildings()
	_props()
	_debris()


# --- materials --------------------------------------------------------------

func _mat(color: Color, rough := 0.92, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m


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


# --- pieces -----------------------------------------------------------------

func _road() -> void:
	_box(Vector3(street_half_width * 2.0, 1.0, street_length),
		Vector3(0, -0.5, 0), _mat(Color(0.20, 0.18, 0.17)))

	# Pavements. The lip is what makes it read as a street rather than a plane.
	for s: float in [-1.0, 1.0]:
		_box(Vector3(5.0, 0.34, street_length),
			Vector3(s * (street_half_width + 2.5), 0.17, 0),
			_mat(Color(0.34, 0.31, 0.28)))

	# Centre dashes.
	var line := _mat(Color(0.62, 0.56, 0.36), 0.8)
	var z := -street_length * 0.5
	while z < street_length * 0.5:
		_box(Vector3(0.24, 0.02, 3.0), Vector3(0, 0.02, z), line, false)
		z += 7.5


func _buildings() -> void:
	var palette := [
		Color(0.52, 0.44, 0.35), Color(0.44, 0.37, 0.30), Color(0.56, 0.47, 0.36),
		Color(0.38, 0.32, 0.27), Color(0.49, 0.41, 0.32),
	]
	for s: float in [-1.0, 1.0]:
		var z := -street_length * 0.5
		while z < street_length * 0.5:
			var depth := _rng.randf_range(9.0, 20.0)
			var h := _rng.randf_range(10.0, 26.0)
			var w := _rng.randf_range(9.0, 15.0)
			var x := s * (street_half_width + 5.0 + w * 0.5)
			var col: Color = palette[_rng.randi() % palette.size()]

			_box(Vector3(w, h, depth), Vector3(x, h * 0.5, z + depth * 0.5), _mat(col))

			# Balconies — the horizontal banding that says "lived in".
			var floors := int(h / 3.6)
			for f in range(1, floors):
				_box(Vector3(1.3, 0.18, depth * 0.78),
					Vector3(x - s * (w * 0.5 + 0.6), f * 3.6, z + depth * 0.5),
					_mat(Color(0.30, 0.27, 0.24)), false)

			# Signage. Saturated slabs against dull masonry read as hoardings.
			if _rng.randf() < 0.8:
				var sc := Color.from_hsv(_rng.randf(), 0.72, 0.5)
				var sm := _mat(sc, 0.6)
				sm.emission_enabled = true
				sm.emission = sc
				sm.emission_energy_multiplier = 0.25
				_box(Vector3(0.3, _rng.randf_range(1.8, 3.6), _rng.randf_range(3.0, 5.5)),
					Vector3(x - s * (w * 0.5 + 0.3), _rng.randf_range(4.0, 11.0), z + depth * 0.5),
					sm, false)
			z += depth + 0.5

	# Cap both ends so the arena is bounded.
	for s: float in [-1.0, 1.0]:
		_box(Vector3(street_half_width * 2.0 + 12.0, 16.0, 2.0),
			Vector3(0, 8.0, s * (street_length * 0.5 + 1.0)),
			_mat(Color(0.30, 0.26, 0.22)))


func _props() -> void:
	var green := _mat(Color(0.10, 0.32, 0.16), 0.7)
	var yellow := _mat(Color(0.66, 0.58, 0.14), 0.7)
	var wood := _mat(Color(0.26, 0.19, 0.13))

	for i in rickshaws:
		var z := _rng.randf_range(-street_length * 0.45, street_length * 0.45)
		var x := (1.0 if _rng.randf() < 0.5 else -1.0) * _rng.randf_range(4.0, 8.5)
		var yaw := _rng.randf_range(-0.3, 0.3) + (0.0 if _rng.randf() < 0.5 else PI)
		var g := Node3D.new()
		add_child(g)
		g.position = Vector3(x, 0, z)
		g.rotation.y = yaw
		_reparent(_box(Vector3(1.6, 1.0, 2.7), Vector3(0, 0.7, 0), green), g)
		_reparent(_box(Vector3(1.6, 0.95, 2.0), Vector3(0, 1.65, -0.25), yellow, false), g)

	for i in stalls:
		var s := 1.0 if _rng.randf() < 0.5 else -1.0
		var z := _rng.randf_range(-street_length * 0.45, street_length * 0.45)
		var canopy := _mat(Color.from_hsv(_rng.randf_range(0.0, 0.12), 0.6, 0.45), 0.85)
		var base := Vector3(s * (street_half_width + 2.0), 0.34, z)
		_box(Vector3(2.6, 1.0, 1.5), base + Vector3(0, 0.5, 0), wood)
		_box(Vector3(3.2, 0.14, 2.2), base + Vector3(0, 2.3, 0), canopy, false)

	# Poles down both pavements.
	var pole := _mat(Color(0.16, 0.15, 0.14))
	var pz := -street_length * 0.5 + 8.0
	while pz < street_length * 0.5:
		for s: float in [-1.0, 1.0]:
			_box(Vector3(0.28, 8.5, 0.28),
				Vector3(s * (street_half_width + 1.0), 4.25, pz), pole, false)
		pz += 17.0


func _debris() -> void:
	var rubble := _mat(Color(0.28, 0.25, 0.22))
	for i in debris:
		var sz := Vector3(
			_rng.randf_range(0.4, 1.6), _rng.randf_range(0.3, 0.9), _rng.randf_range(0.4, 1.6))
		_box(sz,
			Vector3(_rng.randf_range(-street_half_width, street_half_width),
				sz.y * 0.5,
				_rng.randf_range(-street_length * 0.45, street_length * 0.45)),
			rubble, false, _rng.randf() * TAU)


func _reparent(n: Node3D, to: Node3D) -> void:
	var local := n.position
	remove_child(n)
	to.add_child(n)
	n.position = local
