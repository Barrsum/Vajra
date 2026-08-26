extends RefCounted
## Scatters generated ground patches into a continuous, non-repeating surface.
##
## The technique is not tiling. TRELLIS patches are irregular blobs, not tiles
## with matching edges — butt two together and you get a seam every time. So
## they are OVERLAPPED instead: each patch is laid down larger than its
## spacing, at a random turn and size, until the gaps are covered. Irregular
## edges hiding under other irregular edges is what makes a scatter read as one
## surface rather than as a grid of stamps. It is how ground clutter is done in
## commercial engines, for the same reason.
##
## MULTIMESH, NOT NODES. Two hundred patch nodes is two hundred draw calls and
## two hundred sets of culling work. A MultiMeshInstance3D draws every copy of
## one mesh in a single call, so the cost of the two-hundredth patch is a
## transform in a buffer. That is the difference between this being a nice idea
## and this being usable.
##
## No class_name: registration has silently failed under --headless in this
## project. Callers preload it.

const Props := preload("res://scripts/props.gd")


## Lay a field of patches over a disc of `radius` metres.
##
## `patch_size` is how wide one patch is in metres — ground is judged by how
## much floor it covers, not by how tall it is, so this measures across rather
## than up like Props.spawn does.
##
## `density` is patches per 100 square metres. Cover is roughly
## density * (patch_size / spacing)^2, and overlapping is the point: below
## about 1.6x coverage the gaps start showing.
## `avoid` is a list of Vector3(x, z, radius) keep-out circles — campfires,
## spawn points, anywhere a prop standing in the way would be a gameplay
## problem rather than a decoration.
## `tri_budget` caps the total triangles this field may draw, in thousands.
##
## Density alone stopped working once sets arrived at different weights: the
## snow assets are 20k triangles each, the desert ones 40k, so the same density
## produced a level twice as heavy without a line changing. A budget is the
## thing that was actually meant — how much of the frame this field may cost —
## and it self-corrects as assets change.
##
## `solid` gives every patch exact trimesh collision on the scenery layer, so
## the small rocks moulded into a ground patch are things you step over rather
## than through. The shape is shared per source mesh — ninety separate ones
## would be well over a million triangles of collision in memory.
static func scatter(parent: Node3D, category: String, radius: float,
		patch_size := 9.0, density := 1.4, rng: RandomNumberGenerator = null,
		sink := 0.06, inner := 0.0, avoid: Array = [],
		square := false, solid := false, tri_budget := 0) -> Node3D:
	var paths := Props.list(category)
	if paths.is_empty():
		return null
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	var root := Node3D.new()
	root.name = "GroundScatter"
	parent.add_child(root)

	var area: float = (radius * radius * 4.0) if square else (PI * radius * radius)
	var total := int(area / 100.0 * density)
	if total <= 0:
		return root

	if tri_budget > 0:
		var per := _tris_of(String(paths[0]))
		if per > 0:
			var allowed: int = maxi(4, int(tri_budget * 1000.0 / float(per)))
			if allowed < total:
				print("[scatter] %s: %d -> %d instances (%dk tri budget, "
					% [category, total, allowed, tri_budget]
					+ "%d per instance)" % per)
				total = allowed

	# Instances are grouped by mesh, because a MultiMesh holds exactly one.
	# More unique patches means more draw calls but far less visible repeat;
	# five or six is the sweet spot.
	var buckets := {}
	for p in paths:
		buckets[p] = []

	var placed: Array[Vector2] = []
	# Spacing under patch_size is what forces the overlap. Squared once here
	# rather than per comparison in the loop below.
	# 0.52 left visible seams between patches. At 0.34 each one is laid down
	# roughly three times its own spacing wide, so every edge is buried under
	# two neighbours and the field reads as one surface.
	var spacing: float = patch_size * 0.34
	var min_d2: float = spacing * spacing

	var tries := 0
	while placed.size() < total and tries < total * 30:
		tries += 1
		# Uniform over the disc: sqrt on the radius, or everything piles into
		# the middle.
		var at: Vector2
		if square:
			# Arenas are square. Scattering a disc into one leaves the corners
			# bare, which is very visible from the middle.
			at = Vector2(rng.randf_range(-radius, radius),
				rng.randf_range(-radius, radius))
			if at.length() < inner:
				continue
		else:
			# Uniform over the disc: sqrt on the radius, or everything piles
			# into the middle.
			var a := rng.randf() * TAU
			var r: float = sqrt(rng.randf()) * radius
			if r < inner:
				continue
			at = Vector2(cos(a) * r, sin(a) * r)

		var blocked := false
		for zone in avoid:
			var z: Vector3 = zone
			if at.distance_to(Vector2(z.x, z.y)) < z.z:
				blocked = true
				break
		if blocked:
			continue

		var clash := false
		for q in placed:
			if at.distance_squared_to(q) < min_d2:
				clash = true
				break
		if clash:
			continue
		placed.append(at)

		var path: String = paths[rng.randi() % paths.size()]
		buckets[path].append(at)

	var made := 0
	for path in buckets:
		var spots: Array = buckets[path]
		if spots.is_empty():
			continue
		var mm := _build(String(path), spots, patch_size, rng, sink)
		if mm != null:
			root.add_child(mm)
			made += 1
			if solid:
				_add_collision(root, String(path), mm.multimesh)
	return root


static func _build(path: String, spots: Array, patch_size: float,
		rng: RandomNumberGenerator, sink: float) -> MultiMeshInstance3D:
	var packed: PackedScene = load(path)
	if packed == null:
		return null
	var probe: Node3D = packed.instantiate()
	var found := _first_mesh(probe)
	if found == null:
		probe.free()
		return null
	var mesh: Mesh = found.mesh
	var box: AABB = found.get_aabb()
	probe.free()

	var xforms := plan(box, spots, patch_size, rng, sink)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])

	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.name = "Patch_" + path.get_file().get_basename()
	# Ground clutter casting shadows onto itself is a lot of shadow work for
	# something already lying flat on the floor.
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The MultiMesh bounds are computed from instance transforms lazily, and a
	# wrong one pops the whole field out of view at glancing angles.
	node.custom_aabb = AABB(
		Vector3(-1000, -20, -1000), Vector3(2000, 40, 2000))
	return node


## The per-instance transforms, as a plain array.
##
## Separate from the MultiMesh on purpose. A MultiMesh keeps its buffer in the
## RenderingServer, and the headless driver does not retain it — read the
## transforms back under --headless and every one is the identity. So a test
## that asks the MultiMesh what it holds verifies nothing in the one
## environment the suite actually runs in. Computing them here lets the test
## check the real values.
##
## Scale comes from the WIDER horizontal axis, so a patch always covers at
## least patch_size across whichever way the generator happened to orient it.
## One static body per instance, all sharing one shape resource.
##
## Bodies, not one merged mesh: the transforms already exist in the MultiMesh,
## and reusing them means the collision cannot drift from what is drawn.
static func _add_collision(root: Node3D, path: String, mm: MultiMesh) -> void:
	var shape := Props.trimesh_shape(path)
	if shape == null:
		return
	for i in mm.instance_count:
		var body := StaticBody3D.new()
		# Scenery layer: the player steps over these, creatures ignore them.
		# An enemy catching its foot on a twig is a stuck enemy.
		body.collision_layer = Props.SCENERY_LAYER
		body.collision_mask = 0
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)
		root.add_child(body)
		body.transform = mm.get_instance_transform(i)


static func plan(box: AABB, spots: Array, patch_size: float,
		rng: RandomNumberGenerator, sink: float) -> Array[Transform3D]:
	var across: float = maxf(maxf(box.size.x, box.size.z), 0.0001)
	var base_scale: float = patch_size / across
	var out: Array[Transform3D] = []
	for i in spots.size():
		var at: Vector2 = spots[i]
		# Size varies per instance. Without it the eye finds the repeat almost
		# immediately, however random the positions are.
		var s: float = base_scale * rng.randf_range(0.70, 1.60)
		var basis := Basis()
		basis = basis.rotated(Vector3.UP, rng.randf() * TAU)
		# A degree or two of tilt, so patches are not all perfectly coplanar.
		basis = basis.rotated(Vector3.RIGHT, rng.randf_range(-0.03, 0.03))
		basis = basis.rotated(Vector3.FORWARD, rng.randf_range(-0.03, 0.03))
		basis = basis.scaled(Vector3.ONE * s)

		# Ground it, sink it so the rim beds in rather than sitting proud, then
		# stagger the height slightly. Coplanar overlapping surfaces z-fight;
		# a fraction of a centimetre apart do not.
		#
		# The stagger CYCLES rather than accumulating. A straight i * 1.5mm
		# reads fine over forty patches and floats the two-hundredth thirty
		# centimetres off the floor — a bug that only shows up on the big
		# fields this exists for. Twenty-four levels is more than enough to
		# separate any two patches that actually overlap, and it is bounded.
		var stagger: float = float(i % 24) * patch_size * 0.0001
		var y: float = -box.position.y * s - sink * patch_size + stagger
		out.append(Transform3D(basis, Vector3(at.x, y, at.y)))
	return out


## Triangle count of one instance, cached per path.
static var _tri_counts := {}


static func _tris_of(path: String) -> int:
	if _tri_counts.has(path):
		return _tri_counts[path]
	var packed: PackedScene = load(path)
	var n := 0
	if packed != null:
		var probe: Node3D = packed.instantiate()
		var mi := _first_mesh(probe)
		if mi != null:
			for si in mi.mesh.get_surface_count():
				var arr := mi.mesh.surface_get_arrays(si)
				if arr.is_empty():
					continue
				var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
				n += (idx.size() / 3) if idx.size() > 0 else 					((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3)
		probe.free()
	_tri_counts[path] = n
	return n


static func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		return n
	for c in n.get_children():
		var r := _first_mesh(c)
		if r != null:
			return r
	return null
