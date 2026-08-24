extends Node
## Verifies the foliage trees.
##
## The whole shader hinges on vertex colours, and getting them wrong fails
## quietly: a mesh with no COLOR array reads as white, blue is 1.0, and every
## trunk renders with leaf colour and leaf wind. It still looks like *a* tree,
## just the wrong one — so the channels are asserted here rather than eyeballed.
##
## Run: godot --path . res://tests/tree_test.tscn   (windowed, for the shot)

const OUT := "res://shots/"
const Foliage := preload("res://scripts/foliage.gd")

var failures := 0


func _ready() -> void:
	await get_tree().process_frame
	print("")
	print("=== foliage trees ===")

	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var mesh := Foliage.build_tree(rng, 12.0, 4.5, 4)

	_check("one surface (trunk and leaves share a material)",
		mesh.get_surface_count() == 1)

	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	_check("has a colour array", cols.size() > 0)
	_check("one colour per vertex", cols.size() == verts.size())

	# The leaf mask must actually split the mesh in two.
	var leaf := 0
	var trunk := 0
	var leaf_top := -999.0
	var trunk_bottom := 999.0
	var r_min := 9.0
	var r_max := -9.0
	var g_max := -9.0
	for i in cols.size():
		if cols[i].b > 0.5:
			leaf += 1
			leaf_top = maxf(leaf_top, verts[i].y)
			g_max = maxf(g_max, cols[i].g)
		else:
			trunk += 1
			trunk_bottom = minf(trunk_bottom, verts[i].y)
		r_min = minf(r_min, cols[i].r)
		r_max = maxf(r_max, cols[i].r)

	_check("has leaf vertices (%d)" % leaf, leaf > 0)
	_check("has trunk vertices (%d)" % trunk, trunk > 0)
	_check("trunk starts at the ground (%.2f)" % trunk_bottom, trunk_bottom < 0.01)
	_check("canopy sits above the trunk (%.1f)" % leaf_top, leaf_top > 12.0)

	# COLOR.r is the height gradient the wind falls off along. If it never
	# reaches near 0 and near 1 the tree either never moves or moves as a block.
	_check("height gradient spans 0..1 (%.2f..%.2f)" % [r_min, r_max],
		r_min < 0.05 and r_max > 0.9)
	# COLOR.g is the leaf tip gradient, only meaningful on leaves.
	_check("leaf tip gradient present (%.2f)" % g_max, g_max > 0.9)

	var mat := Foliage.make_material(Color(0.24, 0.52, 0.20), Color(0.26, 0.18, 0.12))
	_check("material uses the foliage shader",
		mat.shader == preload("res://shaders/foliage.gdshader"))
	_check("flat colour on, so it is not a white blob",
		bool(mat.get_shader_parameter("leaf_flat_color")))
	_check("wind reads the baked gradient",
		bool(mat.get_shader_parameter("use_vertex_color_wind")))

	if DisplayServer.get_name() != "headless":
		await _preview(mat)

	print("")
	print("=== %s ===" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	get_tree().quit(1 if failures > 0 else 0)


## Three trees side by side against a plain sky, so trunk and canopy colours
## can be told apart at a glance.
func _preview(_unused: ShaderMaterial) -> void:
	var root := Node3D.new()
	get_tree().root.add_child(root)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.68, 0.82)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.65, 0.7)
	env.ambient_light_energy = 0.6
	env_node.environment = env
	root.add_child(env_node)

	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-52.0), deg_to_rad(35.0), 0)
	key.light_energy = 1.6
	root.add_child(key)

	var rng := RandomNumberGenerator.new()
	rng.seed = 999
	var sets := [
		[Color(0.24, 0.52, 0.20), Color(0.26, 0.18, 0.12), 0.0],   # forest
		[Color(0.58, 0.52, 0.36), Color(0.44, 0.40, 0.35), 0.0],   # dead
		[Color(0.42, 0.95, 0.62), Color(0.18, 0.16, 0.20), 0.9],   # garden
	]
	for i in sets.size():
		var s: Array = sets[i]
		var mi := MeshInstance3D.new()
		mi.mesh = Foliage.build_tree(rng, 12.0, 4.5, 4)
		mi.material_override = Foliage.make_material(s[0], s[1], s[2], s[0])
		root.add_child(mi)
		mi.position = Vector3((float(i) - 1.0) * 14.0, 0, 0)

	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0, 9.0, 30.0)
	cam.rotation = Vector3(deg_to_rad(-6.0), 0, 0)
	cam.current = true

	await _wait(12)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + "trees.png")
	print("  wrote shots/trees.png")
	root.queue_free()
	await get_tree().process_frame


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
	print("  %-52s %s" % [label, "PASS" if ok else "FAIL"])
