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

## category -> Array[String] of resource paths. Built once per run.
static var _cache := {}


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
static func spawn(category: String, height := 6.0, rng: RandomNumberGenerator = null) -> Node3D:
	var paths := list(category)
	if paths.is_empty():
		return null
	var i := (rng.randi() if rng != null else randi()) % paths.size()
	return spawn_path(paths[i], height, rng)


static func spawn_path(path: String, height := 6.0,
		rng: RandomNumberGenerator = null) -> Node3D:
	var packed: PackedScene = load(path)
	if packed == null:
		return null
	var node: Node3D = packed.instantiate()

	# Measure what actually arrived rather than trusting the 1-metre
	# convention: a prop whose reference image was wider than it was tall comes
	# out shorter than a metre, and scaling by a constant would make a bush and
	# a tower the same size.
	var box := _bounds(node)
	var tall: float = maxf(box.size.y, 0.0001)
	var s: float = height / tall
	node.scale = Vector3.ONE * s

	# Sit it on the ground. Generated meshes are centred in their box, so
	# without this half the tree is underground.
	node.position.y = -box.position.y * s

	var yaw := (rng.randf() if rng != null else randf()) * TAU
	node.rotation.y = yaw
	return node


## A prop plus a collision body sized to its trunk, for things the player
## should not walk through.
##
## Deliberately a cylinder around the base rather than a mesh collider: a
## 20k-triangle tree makes a 20k-triangle collision shape, and the player only
## ever bumps into the bottom two metres of it anyway.
static func spawn_solid(category: String, height := 6.0, radius := 0.0,
		rng: RandomNumberGenerator = null) -> Node3D:
	var node := spawn(category, height, rng)
	if node == null:
		return null
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
	for mi in _meshes(n):
		var b: AABB = (mi as MeshInstance3D).get_aabb()
		# Into the prop's own space, so a glTF's internal transforms are
		# accounted for rather than assumed away.
		b = (mi as Node3D).transform * b
		out = b if first else out.merge(b)
		first = false
	return out


static func _meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out
