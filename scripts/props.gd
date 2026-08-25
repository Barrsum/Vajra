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
		rng: RandomNumberGenerator = null) -> Node3D:
	var paths := list(category)
	if paths.is_empty():
		return null
	var i := (rng.randi() if rng != null else randi()) % paths.size()
	return spawn_path(paths[i], height, rng)


static func spawn_path(path: String, height := -1.0,
		rng: RandomNumberGenerator = null, offset := INF) -> Node3D:
	var packed: PackedScene = load(path)
	if packed == null:
		return null
	var cfg := settings(path)
	if height < 0.0:
		height = float(cfg["height"])
	if is_inf(offset):
		offset = float(cfg["offset"])

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
static func spawn_solid(category: String, height := -1.0, radius := 0.0,
		rng: RandomNumberGenerator = null) -> Node3D:
	var node := spawn(category, height, rng)
	if node == null:
		return null
	# The node knows its real height even when -1 was asked for.
	var real: float = _bounds(node).size.y * node.scale.y
	if height < 0.0:
		height = real
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius if radius > 0.0 else height * 0.09
	shape.height = height
	col.shape = shape
	body.add_child(col)
	col.position = Vector3(0, height * 0.5, 0)
	node.add_child(body)
	return node


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
