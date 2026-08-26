extends RefCounted
## Registry for generated 3D props.
##
## Scans res://assets/props/<category>/ and hands out instances. Nothing is
## hard-coded: drop a new .glb into a category folder, launch once so Godot
## imports it, and it is in the rotation. That is the whole point of generating
## assets — the pipeline cannot require a code edit per tree.
##
## No class_name: registration has silently failed under --headless twice in
## this project. Callers preload it.
##
## SCALE IS NOT OPTIONAL. TRELLIS normalises every asset into a roughly 1-metre
## box, so a generated oak and a generated pebble both arrive one metre tall.
## `spawn` takes the height you want in metres and rescales to it, because a
## registry that hands back one-metre trees is worse than no registry.

const DIR := "res://assets/props/"
## Per-prop height and ground offset, decided in the prop lab and written here.
## A plain ConfigFile rather than a Resource so it can be read in a diff and
## edited by hand when that is faster than opening the lab.
const SETTINGS := "res://assets/props/props.cfg"
## Physics layer 4. Ground clutter: the player walks over it, creatures ignore
## it entirely. A creature catching its foot on a twig is a creature standing
## still swinging at nothing.
const SCENERY_LAYER := 8
## Physics layer 5. Real obstacles — trunks, boulders — that stop the player
## AND creatures, because a monster walking through a tree is what breaks the
## illusion fastest.
##
## Its OWN layer rather than the world layer, so a creature can be told to
## ignore obstacles without also falling through the floor. Scripted set-piece
## actors do exactly that: creatures have no pathfinding, so a smasher told to
## cross the arena and throw the player will stop at the first trunk in the way
## and the scripted moment never fires. Both level 2 and level 4 broke that way
## before this layer existed.
const OBSTACLE_LAYER := 16

## category -> Array[String] of resource paths. Built once per run.
static var _cache := {}
static var _cfg: ConfigFile = null


## Saved settings for one prop. `height` in metres, `offset` in metres along Y
## (positive lifts, negative sinks).
##
## The offset exists because grounding is not a matter of opinion but LOOKING
## grounded is. spawn puts a prop's lowest vertex exactly on y=0 — measured,
## not approximated — and some models still read as buried, because the artist
## (here, the generator) baked a slab of snow or soil into the base. No formula
## can tell that slab from the object; a per-prop nudge can.
static func settings(path: String) -> Dictionary:
	if _cfg == null:
		_cfg = ConfigFile.new()
		_cfg.load(SETTINGS)     # missing file is fine: everything defaults
	var key := _key(path)
	return {
		"height": float(_cfg.get_value(key, "height", 8.0)),
		"offset": float(_cfg.get_value(key, "offset", 0.0)),
	}


static func save_settings(path: String, height: float, offset: float) -> void:
	if _cfg == null:
		_cfg = ConfigFile.new()
		_cfg.load(SETTINGS)
	var key := _key(path)
	_cfg.set_value(key, "height", height)
	_cfg.set_value(key, "offset", offset)
	_cfg.save(SETTINGS)


static func has_settings(path: String) -> bool:
	if _cfg == null:
		_cfg = ConfigFile.new()
		_cfg.load(SETTINGS)
	return _cfg.has_section(_key(path))


## "res://assets/props/night/snowy_tree.glb" -> "night/snowy_tree"
static func _key(path: String) -> String:
	var rel := path.trim_prefix(DIR)
	return rel.get_basename()


## Every .glb found under a category folder.
static func list(category: String) -> Array:
	if _cache.has(category):
		return _cache[category]

	var out: Array = []
	var path := DIR + category
	var d := DirAccess.open(path)
	if d != null:
		for f in d.get_files():
			# Exported builds only ship the imported form, so a .glb is listed
			# as .glb.import there and as .glb in the editor. Accept both and
			# strip the suffix.
			var name := f
			if name.ends_with(".import"):
				name = name.substr(0, name.length() - 7)
			if not name.ends_with(".glb"):
				continue
			var full := path + "/" + name
			if not out.has(full) and ResourceLoader.exists(full):
				out.append(full)
	out.sort()
	_cache[category] = out
	return out


## Every category folder that actually contains something.
##
## Discovered rather than listed. A hardcoded list went stale the moment the
## snow set moved from "night" to "snow", and the prop lab silently showed
## nothing — it exited non-zero with no failing assertion, which is the worst
## kind of broken test.
static func categories() -> Array:
	var out: Array = []
	var d := DirAccess.open(DIR)
	if d == null:
		return out
	for c in d.get_directories():
		if not list(c).is_empty():
			out.append(c)
	out.sort()
	return out


static func has_any(category: String) -> bool:
	return not list(category).is_empty()


## One instance, scaled to `height` metres and randomly turned.
##
## Returns null when the category is empty rather than erroring — every world
## has to keep working before its props have been generated, which is most of
## the time during development.
## Pass height = -1 to use whatever was decided in the prop lab. That is the
## normal case: a world should ask for "a night tree", not restate a number
## someone already stood next to it and chose.
static func spawn(category: String, height := -1.0,
		rng: RandomNumberGenerator = null, offset := INF,
		default_offset := 0.0) -> Node3D:
	var paths := list(category)
	if paths.is_empty():
		return null
	var i := (rng.randi() if rng != null else randi()) % paths.size()
	return spawn_path(paths[i], height, rng, offset, default_offset)


## `default_offset` is used ONLY when this prop has nothing saved in the lab.
## A world can say "trees generally want bedding in a little" without
## overriding a height and sink someone stood next to the asset and chose.
static func spawn_path(path: String, height := -1.0,
		rng: RandomNumberGenerator = null, offset := INF,
		default_offset := 0.0) -> Node3D:
	var packed: PackedScene = load(path)
	if packed == null:
		return null
	var cfg := settings(path)
	if height < 0.0:
		height = float(cfg["height"])
	if is_inf(offset):
		offset = float(cfg["offset"]) if has_settings(path) else default_offset

	var node: Node3D = packed.instantiate()

	# Measure what actually arrived rather than trusting the 1-metre
	# convention: a prop whose reference image was wider than it was tall comes
	# out shorter than a metre, and scaling by a constant would make a bush and
	# a tower the same size.
	var box := _bounds(node)
	var tall: float = maxf(box.size.y, 0.0001)
	var s: float = height / tall
	node.scale = Vector3.ONE * s

	# Lowest vertex exactly on y = 0, then the prop's own saved nudge. The
	# nudge is scaled with the prop, so a rock that wanted sinking by a tenth
	# of its height still sinks by a tenth when it is placed twice as large.
	node.position.y = -box.position.y * s + offset * height

	var yaw := (rng.randf() if rng != null else randf()) * TAU
	node.rotation.y = yaw
	return node


## A prop plus a collision body sized to its trunk, for things the player
## should not walk through.
##
## Deliberately a cylinder around the base rather than a mesh collider: a
## 20k-triangle tree makes a 20k-triangle collision shape, and the player only
## ever bumps into the bottom two metres of it anyway.
## `hull` swaps the cheap cylinder for a convex hull of the actual mesh.
##
## A cylinder is right for a tree: the player only ever brushes the trunk, and
## a hull of a 20k-triangle conifer would be a hull of its branches. It is
## wrong for a boulder — with a cylinder you cannot climb a rock, you bump into
## an invisible pillar the width of its widest point and slide off. A convex
## hull is a few dozen planes, follows the real silhouette, and gives sloped
## sides you can run up and stand on.
## `blocks_creatures` puts the body on the world layer instead of the scenery
## layer, so monsters are stopped by it too.
static func spawn_solid(category: String, height := -1.0, radius := 0.0,
		rng: RandomNumberGenerator = null, hull := false,
		offset := INF, default_offset := 0.0,
		blocks_creatures := true) -> Node3D:
	var node := spawn(category, height, rng, offset, default_offset)
	if node == null:
		return null
	# The node knows its real height even when -1 was asked for.
	var real: float = _bounds(node).size.y * node.scale.y
	if height < 0.0:
		height = real

	if hull:
		var mi := _first_mesh(node)
		if mi != null:
			var body := StaticBody3D.new()
			var col := CollisionShape3D.new()
			# clean=true welds the near-duplicate vertices a generated mesh is
			# full of; simplify=true drops the hull down to something a physics
			# step can afford.
			col.shape = mi.mesh.create_convex_shape(true, true)
			body.add_child(col)
			body.collision_layer = (OBSTACLE_LAYER if blocks_creatures
				else SCENERY_LAYER)
			body.collision_mask = 0
			# Under the MeshInstance, so it inherits the same transform the
			# visible mesh has and cannot drift from it.
			mi.add_child(body)
			return node
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius if radius > 0.0 else height * 0.09
	shape.height = height
	col.shape = shape
	body.add_child(col)
	col.position = Vector3(0, height * 0.5, 0)

	# LAYER 4: scenery. Blocks the PLAYER and nothing else.
	#
	# Creatures mask layers 1 and 3 (world and each other), so they walk
	# straight through decoration. That is deliberate. Putting props on the
	# world layer meant every enemy collided with every tree, and the level 4
	# grab set-piece stopped resolving — the smasher crossing the arena got
	# caught on scenery and the throw never happened.
	#
	# The trade is a creature occasionally clipping a rock, against enemies
	# getting stuck on decoration for the rest of the game. In a level meant to
	# be densely dressed that is not a close call.
	body.collision_layer = (OBSTACLE_LAYER if blocks_creatures
		else SCENERY_LAYER)
	body.collision_mask = 0
	node.add_child(body)
	return node


## Exact collision for a mesh, cached per resource path.
##
## Shared, not per instance. A ground patch is ~19k triangles and a level has
## ninety of them; ninety separate shapes would be 1.7 million triangles of
## collision geometry in memory. Nine shapes reused ninety times is nine.
static var _tri_shapes := {}


static func trimesh_shape(path: String) -> ConcavePolygonShape3D:
	if _tri_shapes.has(path):
		return _tri_shapes[path]
	var packed: PackedScene = load(path)
	if packed == null:
		return null
	var probe: Node3D = packed.instantiate()
	var mi := _first_mesh(probe)
	var shape: ConcavePolygonShape3D = null
	if mi != null:
		shape = mi.mesh.create_trimesh_shape()
	probe.free()
	_tri_shapes[path] = shape
	return shape


static func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		return n
	for c in n.get_children():
		var r := _first_mesh(c)
		if r != null:
			return r
	return null


static func _bounds(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for entry in _meshes_with_xform(n, Transform3D.IDENTITY):
		var mi: MeshInstance3D = entry[0]
		var xform: Transform3D = entry[1]
		# The FULL chain from the prop root, not just the mesh's own transform.
		# glTF nests, and one skipped parent silently offsets everything.
		var b: AABB = xform * mi.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


static func _meshes_with_xform(n: Node, acc: Transform3D) -> Array:
	var here := acc
	# The root's own transform is not part of its bounds — it is what we are
	# about to set.
	if n is Node3D and n.get_parent() != null:
		here = acc * (n as Node3D).transform
	var out: Array = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append([n, here])
	for c in n.get_children():
		out.append_array(_meshes_with_xform(c, here))
	return out


static func _meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out
