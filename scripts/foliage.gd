extends RefCounted
## Generates trees for shaders/foliage.gdshader.
##
## No class_name: registration has silently failed under --headless twice in
## this project. Callers preload it.
##
## The shader is written for Synty's vertex-colour convention, and that is the
## whole reason this file exists. It reads:
##
##   COLOR.r  height gradient, 0 at the base and 1 at the top. Scales gale and
##            strong wind, so a trunk base stays planted while the crown moves.
##   COLOR.g  leaf tip gradient. Drives breeze and the light-wind leaf fade.
##   COLOR.b  leaf mask. Above 0.5 the fragment takes the leaf branch of the
##            shader, below it the trunk branch.
##
## Godot's primitive meshes (SphereMesh, CylinderMesh) carry no colour array,
## and a mesh without one reads as opaque white — blue 1.0 — so every trunk
## would render as a leaf with leaf colours and leaf wind. Hence a real
## ArrayMesh built by hand.
##
## Trunk and canopy go into ONE surface so a single material covers both and
## the shader's own branch decides which is which. Two surfaces with two
## materials would work too, and would throw away the entire point of the
## shader.

const FOLIAGE_SHADER := preload("res://shaders/foliage.gdshader")


## One tree. `height` is trunk height; the canopy sits on top of it.
static func build_tree(rng: RandomNumberGenerator, height: float,
		canopy_radius: float, blobs: int = 3) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()

	var top := height
	_trunk(verts, norms, uvs, cols, idx, rng, height)

	# Canopy: overlapping spheres, the first centred and the rest offset. Blue
	# is 1.0 so every one of these takes the leaf path.
	for b in blobs:
		var centre := Vector3(0, top * 0.98, 0)
		var r := canopy_radius
		if b > 0:
			centre += Vector3(
				rng.randf_range(-canopy_radius * 0.7, canopy_radius * 0.7),
				rng.randf_range(canopy_radius * 0.15, canopy_radius * 0.75),
				rng.randf_range(-canopy_radius * 0.7, canopy_radius * 0.7))
			r = canopy_radius * rng.randf_range(0.55, 0.85)
		_blob(verts, norms, uvs, cols, idx, centre, r, height, canopy_radius, rng)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## A tapered trunk. Blue 0.0 puts it on the trunk branch of the shader.
static func _trunk(verts: PackedVector3Array, norms: PackedVector3Array,
		uvs: PackedVector2Array, cols: PackedColorArray, idx: PackedInt32Array,
		rng: RandomNumberGenerator, height: float) -> void:
	var sides := 8
	var rings := 5
	var base_r: float = maxf(height * 0.085, 0.30)
	var start := verts.size()

	for ring in rings + 1:
		var t := float(ring) / float(rings)
		# Taper, plus a slight lean so a stand of them does not look stamped.
		var r: float = lerpf(base_r, base_r * 0.45, t)
		var lean := Vector3(sin(t * 1.7) * height * 0.02, 0, cos(t * 1.3) * height * 0.015)
		for s in sides + 1:
			var a := TAU * float(s) / float(sides)
			var dir := Vector3(cos(a), 0, sin(a))
			verts.append(dir * r + Vector3(0, t * height, 0) + lean)
			norms.append(dir)
			uvs.append(Vector2(float(s) / float(sides), t))
			# r = height gradient, g = 0 (not a leaf tip), b = 0 (trunk).
			cols.append(Color(t, 0.0, 0.0, 1.0))

	for ring in rings:
		for s in sides:
			var a: int = start + ring * (sides + 1) + s
			var b: int = a + 1
			var c: int = a + sides + 1
			var d: int = c + 1
			idx.append_array([a, c, b, b, c, d])


## One canopy sphere, as an octahedron subdivided twice — cheap, and the facets
## suit the low-poly look better than a smooth UV sphere.
static func _blob(verts: PackedVector3Array, norms: PackedVector3Array,
		uvs: PackedVector2Array, cols: PackedColorArray, idx: PackedInt32Array,
		centre: Vector3, radius: float, tree_height: float, canopy_radius: float,
		rng: RandomNumberGenerator) -> void:
	var rows := 6
	var cols_n := 8
	var start := verts.size()
	# A per-blob jitter so overlapping spheres do not read as spheres.
	var wobble := rng.randf_range(0.85, 1.15)

	for row in rows + 1:
		var phi := PI * float(row) / float(rows)
		for col in cols_n + 1:
			var theta := TAU * float(col) / float(cols_n)
			var n := Vector3(
				sin(phi) * cos(theta),
				cos(phi),
				sin(phi) * sin(theta))
			var rr := radius * (1.0 + sin(theta * 3.0 + phi * 2.0) * 0.08 * wobble)
			var v := centre + n * rr
			verts.append(v)
			norms.append(n)
			uvs.append(Vector2(float(col) / float(cols_n), float(row) / float(rows)))

			# r: height gradient across the WHOLE tree, so the shader's gale
			# rotation pivots at the ground rather than at the canopy base.
			var total: float = tree_height + canopy_radius * 2.0
			var height_grad: float = clampf(v.y / maxf(total, 0.001), 0.0, 1.0)
			# g: leaf tip gradient — 1 at the outside of the blob, 0 at its
			# centre, which is what makes the breeze ripple the edges only.
			var tip: float = clampf((v - centre).length() / maxf(radius, 0.001), 0.0, 1.0)
			cols.append(Color(height_grad, tip, 1.0, 1.0))

	for row in rows:
		for col in cols_n:
			var a: int = start + row * (cols_n + 1) + col
			var b: int = a + 1
			var c: int = a + cols_n + 1
			var d: int = c + 1
			idx.append_array([a, c, b, b, c, d])


## A material for the foliage shader. `glow` above zero lights the leaves,
## which is what the garden level uses instead of lamps in the canopy.
static func make_material(leaf: Color, trunk: Color, glow := 0.0,
		glow_color := Color(0.5, 1.0, 0.6)) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FOLIAGE_SHADER

	# Flat colours rather than textures. Every sampler in this shader defaults
	# to white when unset, so leaf_flat_color is what stops the tree rendering
	# as a plain white blob — it swaps the texture read for the tint.
	m.set_shader_parameter("leaf_flat_color", true)
	m.set_shader_parameter("trunk_flat_color", true)
	m.set_shader_parameter("leaf_base_color", leaf)
	m.set_shader_parameter("trunk_base_color", trunk)
	m.set_shader_parameter("leaf_smoothness", 0.12)
	m.set_shader_parameter("trunk_smoothness", 0.06)
	m.set_shader_parameter("alpha_clip_threshold", 0.0)

	# Colour noise varies the canopy across a stand. It works in world space,
	# so neighbouring trees share the pattern and read as one wood.
	m.set_shader_parameter("use_color_noise", true)
	m.set_shader_parameter("leaf_noise_color", leaf.darkened(0.28))
	m.set_shader_parameter("leaf_noise_large_color", leaf.lightened(0.14))
	m.set_shader_parameter("trunk_noise_color", trunk.darkened(0.2))
	m.set_shader_parameter("color_noise_small_freq", 6.0)
	m.set_shader_parameter("color_noise_large_freq", 0.6)

	# Wind. use_vertex_color_wind makes the falloff read COLOR.r, which is the
	# gradient baked above — without it the shader falls back to VERTEX.y * 0.5
	# and tall trees tear apart at the top.
	m.set_shader_parameter("use_vertex_color_wind", true)
	m.set_shader_parameter("enable_breeze", true)
	m.set_shader_parameter("breeze_strength", 0.06)
	m.set_shader_parameter("enable_light_wind", true)
	m.set_shader_parameter("light_wind_strength", 0.10)
	m.set_shader_parameter("light_wind_use_leaf_fade", true)
	m.set_shader_parameter("enable_strong_wind", true)
	m.set_shader_parameter("strong_wind_strength", 0.03)
	m.set_shader_parameter("strong_wind_frequency", 0.25)

	if glow > 0.0:
		m.set_shader_parameter("enable_emission", true)
		m.set_shader_parameter("emissive_color", glow_color)
		m.set_shader_parameter("emissive_amount", glow)
	return m
