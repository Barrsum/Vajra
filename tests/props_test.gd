extends Node
## The generated-prop registry: scaling, grounding, and behaving when empty.

const Props := preload("res://scripts/props.gd")

var failures := 0


func _ready() -> void:
	await get_tree().process_frame
	print("")
	print("=== generated props ===")

	for cat in ["forest", "cave", "dust", "night"]:
		print("  %-8s %d asset(s)" % [cat, Props.list(cat).size()])

	# An empty category must not error. Most categories are empty for most of
	# development, and every world has to keep running regardless.
	_check("an empty category returns null, not an error",
		Props.spawn("definitely_not_a_category", 5.0) == null)

	if not Props.has_any("forest"):
		print("  (no forest props generated yet — scaling checks skipped)")
		_done()
		return

	# The whole reason the registry exists: TRELLIS hands back everything at
	# roughly one metre, so a prop that is not rescaled is useless.
	for want in [3.0, 8.0, 14.0]:
		var p := Props.spawn("forest", want)
		add_child(p)
		await get_tree().process_frame
		var box := _bounds(p)
		_check("asked for %.0fm, got %.2fm" % [want, box.size.y],
			absf(box.size.y - want) < want * 0.02)
		_check("  sits on the ground (base at %.3f)" % box.position.y,
			absf(box.position.y) < 0.05)
		p.queue_free()

	var solid := Props.spawn_solid("forest", 7.0)
	add_child(solid)
	await get_tree().process_frame
	var body: StaticBody3D = null
	for c in solid.get_children():
		if c is StaticBody3D:
			body = c
	_check("spawn_solid adds a body", body != null)
	if body:
		var shape: CollisionShape3D = null
		for c in body.get_children():
			if c is CollisionShape3D:
				shape = c
		# A mesh collider off a 20k-triangle tree would be 20k triangles of
		# physics for a trunk the player brushes past.
		_check("collision is a cheap cylinder, not the mesh",
			shape != null and shape.shape is CylinderShape3D)
	solid.queue_free()

	_done()


func _done() -> void:
	print("")
	print("=== %s ===" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	get_tree().quit(1 if failures > 0 else 0)


func _bounds(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in _meshes(n):
		var b: AABB = (mi as MeshInstance3D).get_aabb()
		b = (mi as Node3D).global_transform * b
		out = b if first else out.merge(b)
		first = false
	return out


func _meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


func _check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
	print("  %-48s %s" % [label, "PASS" if ok else "FAIL"])
