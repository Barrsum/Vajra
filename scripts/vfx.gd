extends Node
## Pooled one-shot particle effects. Autoloaded as `Vfx`.
##
## One pool of GPUParticles3D reconfigured per emission. At this scale that is
## cheaper than maintaining a separate pool per effect, and far easier to tune.

const POOL := 16

var _pool: Array[GPUParticles3D] = []
var _cursor := 0


func _ready() -> void:
	for i in POOL:
		var p := GPUParticles3D.new()
		p.one_shot = true
		p.emitting = false
		p.local_coords = false
		p.explosiveness = 0.9
		p.draw_pass_1 = _quad()
		p.process_material = ParticleProcessMaterial.new()
		add_child(p)
		_pool.append(p)


## A soft radial dot. Without it every particle is a hard-edged square, which is
## the single most obvious tell of untextured billboards.
func _dot_texture(size := 32) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d: float = Vector2(x - c, y - c).length() / c
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)


func _quad() -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(0.085, 0.085)
	var m := StandardMaterial3D.new()
	m.albedo_texture = _dot_texture()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.disable_receive_shadows = true
	q.material = m
	return q


func _next() -> GPUParticles3D:
	var p := _pool[_cursor]
	_cursor = (_cursor + 1) % _pool.size()
	return p


func _emit(pos: Vector3, count: int, dir: Vector3, spread: float,
		speed_min: float, speed_max: float, life: float,
		color: Color, gravity: float, scale_min: float, scale_max: float) -> void:
	var p := _next()
	var m: ParticleProcessMaterial = p.process_material

	m.direction = dir if dir.length_squared() > 0.001 else Vector3.UP
	m.spread = spread
	m.initial_velocity_min = speed_min
	m.initial_velocity_max = speed_max
	m.gravity = Vector3(0, -gravity, 0)
	m.scale_min = scale_min
	m.scale_max = scale_max
	m.damping_min = 1.5
	m.damping_max = 4.0
	m.color = color

	# Shrink over life so particles vanish rather than pop out.
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	var tex := CurveTexture.new()
	tex.curve = curve
	m.scale_curve = tex

	p.amount = maxi(count, 1)
	p.lifetime = life
	p.global_position = pos
	p.restart()
	p.emitting = true


# --- presets ----------------------------------------------------------------

## Sparks off a blade hit, thrown along the swing direction.
func sparks(pos: Vector3, dir: Vector3, heavy := false) -> void:
	_emit(pos, 22 if heavy else 14, dir.normalized(), 48.0,
		5.0, 13.0 if heavy else 9.0, 0.42,
		Color(1.0, 0.72, 0.32), 16.0, 0.4, 1.1)


## Cold alien ichor — the enemy's own colour, so hits read as damage to *it*.
func ichor(pos: Vector3, dir: Vector3, heavy := false) -> void:
	_emit(pos, 18 if heavy else 10, dir.normalized(), 65.0,
		3.0, 8.0, 0.55,
		Color(0.45, 1.0, 0.72), 20.0, 0.45, 1.2)


## Ground dust for dodges and landings.
func dust(pos: Vector3, amount := 12) -> void:
	_emit(pos, amount, Vector3.UP, 75.0,
		1.5, 4.0, 0.6,
		Color(0.85, 0.68, 0.48), 3.0, 0.9, 2.6)


## Death: a wide burst of embers.
func death_burst(pos: Vector3) -> void:
	_emit(pos, 46, Vector3.UP, 180.0,
		4.0, 12.0, 0.9,
		Color(1.0, 0.55, 0.18), 11.0, 0.7, 2.0)
	_emit(pos, 24, Vector3.UP, 180.0,
		2.0, 7.0, 1.1,
		Color(0.45, 1.0, 0.72), 8.0, 0.6, 1.5)


## A pillar of light marking something arriving. `intensity` scales the whole
## effect, so the same call can read as a footnote or an event:
##   0.45  a minor arrival
##   1.0   a real threat
##   1.8   something you should be worried about
func spawn_portal(pos: Vector3, color: Color, intensity := 1.0) -> void:
	var root := Node3D.new()
	add_child(root)
	root.global_position = pos

	var beam_mat := StandardMaterial3D.new()
	beam_mat.albedo_color = Color(color.r, color.g, color.b, 0.55)
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam_mat.disable_receive_shadows = true

	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.1 * intensity
	cm.bottom_radius = 1.5 * intensity
	cm.height = 14.0 * intensity
	cm.radial_segments = 16
	beam.mesh = cm
	beam.material_override = beam_mat
	beam.position.y = cm.height * 0.5
	root.add_child(beam)

	# Ground ring, so the landing point is unambiguous.
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.4 * intensity
	tm.outer_radius = 1.9 * intensity
	ring.mesh = tm
	ring.material_override = beam_mat
	ring.position.y = 0.1
	root.add_child(ring)

	var lamp := OmniLight3D.new()
	lamp.light_color = color
	lamp.light_energy = 9.0 * intensity
	lamp.omni_range = 16.0 * intensity
	lamp.position.y = 2.0
	root.add_child(lamp)

	_emit(pos + Vector3.UP * 0.4, int(26 * intensity), Vector3.UP, 22.0,
		5.0 * intensity, 12.0 * intensity, 0.9, color, 4.0, 0.5, 1.6 * intensity)

	# Snap open, then drain away. The asymmetry is what makes it read as an
	# arrival rather than a fade-in.
	beam.scale = Vector3(0.15, 0.2, 0.15)
	ring.scale = Vector3(0.3, 1.0, 0.3)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(beam, "scale", Vector3(1.0, 1.0, 1.0), 0.18)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "scale", Vector3(1.6, 1.0, 1.6), 0.35)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(beam_mat, "albedo_color:a", 0.0, 0.75)
	tw.parallel().tween_property(lamp, "light_energy", 0.0, 0.75)
	tw.parallel().tween_property(beam, "scale", Vector3(0.4, 1.3, 0.4), 0.75)
	tw.chain().tween_callback(root.queue_free)


## An expanding ground ring. Reads as force transmitted into the floor, which
## is what a heavy landing or a big death should look like.
func shockwave(pos: Vector3, color: Color, radius := 3.0) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, 0.5)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.85
	tm.outer_radius = 1.0
	tm.rings = 24
	ring.mesh = tm
	ring.material_override = mat
	add_child(ring)
	ring.global_position = pos + Vector3.UP * 0.12
	ring.scale = Vector3(0.2, 1.0, 0.2)

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(radius, 0.4, radius), 0.42)		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.42)
	tw.chain().tween_callback(ring.queue_free)


## A brief additive flare exactly where a hit connected. Small, bright, gone in
## four frames — it marks the contact point the sparks spray away from.
func impact_flash(pos: Vector3, color: Color, size := 1.0) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, 0.9)
	mat.albedo_texture = _dot_texture()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD

	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.6, 1.6) * size
	q.mesh = qm
	q.material_override = mat
	add_child(q)
	q.global_position = pos

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(q, "scale", Vector3.ONE * 1.9, 0.16)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.16)
	tw.chain().tween_callback(q.queue_free)


# --- death companions -------------------------------------------------------

## Slow drifting embers that float up as they fade. Warm deaths.
func embers(pos: Vector3, color: Color, count := 26) -> void:
	_emit(pos, count, Vector3.UP, 55.0, 1.2, 4.0, 1.5, color, -1.2, 0.5, 1.6)


## Fast, hard, low-spread chunks. Cold deaths that break rather than burn.
func shards(pos: Vector3, color: Color, count := 24) -> void:
	_emit(pos, count, Vector3.UP, 120.0, 9.0, 18.0, 0.55, color, 26.0, 0.7, 2.2)


## A slow column lifting away. Vapour and dispersal.
func rise(pos: Vector3, color: Color, count := 24) -> void:
	_emit(pos, count, Vector3.UP, 16.0, 1.0, 2.6, 2.2, color, -2.4, 0.8, 2.0)


## Collapse inward: a ring snapping shut, then one bright point.
func implode(pos: Vector3, color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, 0.7)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.05
	ring.mesh = tm
	ring.material_override = mat
	add_child(ring)
	ring.global_position = pos
	ring.scale = Vector3(3.4, 1.0, 3.4)

	var tw := create_tween()
	tw.tween_property(ring, "scale", Vector3(0.12, 0.5, 0.12), 0.5)		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		impact_flash(pos, Color(1, 1, 1), 1.6)
		_emit(pos, 20, Vector3.UP, 180.0, 6.0, 12.0, 0.5, color, 6.0, 0.5, 1.4))
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.12)
	tw.tween_callback(ring.queue_free)


# --- hit dressing -----------------------------------------------------------

## A crescent left in the air along the swing. Reads as the cut itself.
func slash_arc(pos: Vector3, dir: Vector3, color: Color, size := 1.0) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, 0.75)
	mat.albedo_texture = _dot_texture()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2.6, 0.42) * size
	q.mesh = qm
	q.material_override = mat
	add_child(q)
	q.global_position = pos
	if dir.length_squared() > 0.001:
		q.look_at(pos + Vector3.UP, dir.normalized())
	q.rotate_object_local(Vector3.FORWARD, randf_range(-0.6, 0.6))

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(q, "scale", Vector3(1.5, 0.4, 1.0), 0.22)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.22)
	tw.chain().tween_callback(q.queue_free)


## A tight vertical ring at the contact point — a punchier alternative to the
## ground shockwave, for hits that land in the air rather than on the floor.
func burst_ring(pos: Vector3, color: Color, size := 1.0) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, 0.8)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.55
	tm.outer_radius = 0.72
	ring.mesh = tm
	ring.material_override = mat
	add_child(ring)
	ring.global_position = pos
	ring.rotation = Vector3(PI * 0.5, randf() * TAU, 0.0)
	ring.scale = Vector3.ONE * 0.25

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3.ONE * (1.8 * size), 0.26)		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.26)
	tw.chain().tween_callback(ring.queue_free)


## A tight cone of fast fragments straight down the swing line.
func shard_spray(pos: Vector3, dir: Vector3, color: Color) -> void:
	_emit(pos, 18, dir.normalized(), 22.0, 12.0, 22.0, 0.34, color, 14.0, 0.4, 1.2)


## The arm blade materialising.
func morph(pos: Vector3) -> void:
	_emit(pos, 26, Vector3.UP, 140.0,
		2.0, 6.0, 0.5,
		Color(0.55, 0.8, 1.0), 4.0, 0.5, 1.4)
