extends Node
## Overview shots of a built world: from above, and from head height.
##
## A screenshot from the player camera cannot tell you whether a level is well
## dressed — it shows whatever happens to be two metres in front of the robot.
## These two angles show the layout and the eye-line, which are the two things
## worth judging.
##
##   godot --path . res://tests/level_shot.tscn

const OUT := "res://shots/"


func _ready() -> void:
	await get_tree().process_frame
	var decoy := Node.new()
	get_tree().root.add_child(decoy)
	get_tree().current_scene = decoy
	await _wait(10)

	var which := 3
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--world="):
			which = int(a.split("=")[1])

	Game.start_world(which)
	await _wait(180)
	var arena := get_tree().current_scene
	var w: Resource = Game.current_world()
	var name := String(w.display_name).to_lower().replace(" ", "-") if w else "world"

	_report(arena)

	if DisplayServer.get_name() == "headless":
		get_tree().quit(0)
		return

	# Enemies and the HUD are not the subject here.
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	for n in arena.get_children():
		if n is CanvasLayer:
			n.visible = false
	await _wait(4)

	var cam := Camera3D.new()
	arena.add_child(cam)
	cam.far = 900.0
	cam.current = true

	# Straight down: layout, spacing, whether the corners are bare.
	cam.position = Vector3(0, 105, 1)
	cam.rotation = Vector3(deg_to_rad(-89.0), 0, 0)
	cam.fov = 78.0
	await _shot("level-%d-%s-top" % [which + 1, name])

	# Head height: what the player actually sees.
	cam.position = Vector3(4, 2.2, 34)
	cam.rotation = Vector3(deg_to_rad(-3.0), 0, 0)
	cam.fov = 72.0
	await _shot("level-%d-%s-eye" % [which + 1, name])

	# Three-quarters, the angle level art is usually judged at.
	cam.position = Vector3(-46, 26, 46)
	cam.look_at(Vector3(0, 2, 0), Vector3.UP)
	cam.fov = 62.0
	await _shot("level-%d-%s-wide" % [which + 1, name])

	get_tree().quit(0)


## What the level actually costs, which is the number that decides whether a
## dressing pass was a good idea.
func _report(arena: Node) -> void:
	var tris := 0
	var draws := 0
	var instances := 0
	for n in _all(arena):
		if n is MultiMeshInstance3D:
			var mm := (n as MultiMeshInstance3D).multimesh
			if mm == null or mm.mesh == null:
				continue
			draws += 1
			instances += mm.instance_count
			tris += _tris(mm.mesh) * mm.instance_count
		elif n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			draws += 1
			tris += _tris((n as MeshInstance3D).mesh)
	print("")
	print("=== %s ===" % Game.current_world().display_name)
	print("  %d draw sources, %d multimesh instances" % [draws, instances])
	print("  ~%.2f M triangles before culling and LOD" % (float(tris) / 1e6))
	print("")


func _tris(m: Mesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		if arr.is_empty():
			continue
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		if idx.size() > 0:
			n += idx.size() / 3
		elif arr[Mesh.ARRAY_VERTEX] != null:
			n += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


func _all(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out


func _shot(name: String) -> void:
	await _wait(12)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + name + ".png")
	print("  wrote shots/%s.png" % name)


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
