extends Node
## What a dressed world actually contains, checked in the built level rather
## than in isolation.
##
## The scatter unit test proves the machinery works. This proves the machinery
## was switched ON in the world — three of these settings were passed as
## arguments from world.gd, and an argument in the wrong position is invisible
## until someone walks through a rock.

const Props := preload("res://scripts/props.gd")

var failures := 0


func _ready() -> void:
	await get_tree().process_frame
	var decoy := Node.new()
	get_tree().root.add_child(decoy)
	get_tree().current_scene = decoy
	await _wait(10)

	print("")
	print("=== dressed world ===")

	# World 2 carries the snow set.
	Game.start_world(1)
	await _wait(180)
	var arena := get_tree().current_scene
	var w: Resource = Game.current_world()
	print("  %s, prop_set '%s'" % [w.display_name, w.prop_set])

	if String(w.prop_set) == "":
		print("  no set assigned — skipped")
		_done()
		return

	var nodes := _all(arena)

	# --- ground -------------------------------------------------------------
	var patches := 0
	for n in nodes:
		if n is MultiMeshInstance3D and String(n.name).begins_with("Patch_"):
			patches += (n as MultiMeshInstance3D).multimesh.instance_count
	_check("ground is scattered (%d patches)" % patches, patches > 20)

	# Solid ground is the thing the player notices: the patches have stones
	# moulded into them, and walking through those was the complaint.
	var ground_bodies := 0
	for n in nodes:
		if not (n is StaticBody3D):
			continue
		var parent: Node = n.get_parent()
		if parent != null and String(parent.name).ends_with("Ground"):
			ground_bodies += 1
	_check("ground has collision (%d bodies)" % ground_bodies,
		ground_bodies > 20)

	# --- everything solid is on the scenery layer ---------------------------
	# Not the world layer. Props there collide with creatures, and the level 4
	# set-piece stopped resolving when they did.
	var clutter := 0
	var obstacles := 0
	var wrong := 0
	for n in nodes:
		if not (n is StaticBody3D):
			continue
		var b := n as StaticBody3D
		if b.collision_layer == 1:
			continue            # campfire barriers, deliberately world layer
		if b.collision_mask != 0:
			wrong += 1          # scenery must never collide with anything
		if b.collision_layer == Props.SCENERY_LAYER:
			clutter += 1
		elif b.collision_layer == Props.OBSTACLE_LAYER:
			obstacles += 1
		else:
			wrong += 1
	# Ground clutter is player-only; trunks and boulders stop creatures too.
	_check("%d ground clutter, %d obstacles, %d mis-layered"
		% [clutter, obstacles, wrong], wrong == 0 and clutter > 20
		and obstacles > 10)

	# --- bedded in ----------------------------------------------------------
	# Grounding alone leaves a slanted rock balanced on one corner and a tree
	# standing on a visible plinth of its own base slab.
	var sunk := 0
	var proud := 0
	# Walk UP from each hull shape to the prop root, rather than down from the
	# arena looking for "the topmost node containing a hull" — that found one
	# node, because the World and the arena also contain hulls in their
	# subtrees and so swallowed every rock.
	#
	# props.gd builds: prop root -> MeshInstance3D -> StaticBody3D -> shape.
	for n in nodes:
		if not (n is CollisionShape3D):
			continue
		if not ((n as CollisionShape3D).shape is ConvexPolygonShape3D):
			continue
		var root: Node = n
		for step in 3:
			if root.get_parent() == null:
				break
			root = root.get_parent()
		if not (root is Node3D):
			continue
		# NOT position.y. Grounding lifts a centred mesh, so a prop's node
		# origin is positive whether or not it is bedded in. What "sunk"
		# means is that the LOWEST VERTEX ends up below the floor.
		var low := _lowest_vertex(root)
		if low < -0.05:
			sunk += 1
		else:
			proud += 1
	_check("rocks bed into the floor (%d sunk, %d proud)" % [sunk, proud],
		sunk > 0 and proud == 0)

	# Trees too. A generated tree carries a slab of ground moulded round its
	# trunk; grounded exactly, that slab sits ON the floor like a plinth with
	# a visible lip. This was missed on the first pass — rocks were bedded in
	# and trees were not.
	var t_sunk := 0
	var t_proud := 0
	for n in nodes:
		if not (n is CollisionShape3D):
			continue
		if not ((n as CollisionShape3D).shape is CylinderShape3D):
			continue
		var root: Node = n
		for step in 2:
			if root.get_parent() == null:
				break
			root = root.get_parent()
		# Campfire barriers are cylinders too, and are meant to sit level.
		if not (root is Node3D) or not _has_mesh(root):
			continue
		if _lowest_vertex(root) < -0.05:
			t_sunk += 1
		else:
			t_proud += 1
	_check("trees bed into the floor (%d sunk, %d proud)" % [t_sunk, t_proud],
		t_sunk > 0 and t_proud == 0)

	_done()


func _done() -> void:
	print("")
	print("=== %s ===" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	get_tree().quit(1 if failures > 0 else 0)


## Lowest point of a prop's geometry, in world space.
func _lowest_vertex(n: Node) -> float:
	var low := INF
	for m in _all(n):
		if not (m is MeshInstance3D) or (m as MeshInstance3D).mesh == null:
			continue
		var b: AABB = (m as Node3D).global_transform * (m as MeshInstance3D).get_aabb()
		low = minf(low, b.position.y)
	return low if low != INF else 0.0


func _has_mesh(n: Node) -> bool:
	for m in _all(n):
		if m is MeshInstance3D and (m as MeshInstance3D).mesh != null:
			return true
	return false


func _has_hull(n: Node) -> bool:
	if n is CollisionShape3D and (n as CollisionShape3D).shape is ConvexPolygonShape3D:
		return true
	for c in n.get_children():
		if _has_hull(c):
			return true
	return false


func _all(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
	print("  %-52s %s" % [label, "PASS" if ok else "FAIL"])
