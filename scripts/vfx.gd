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


## The arm blade materialising.
func morph(pos: Vector3) -> void:
	_emit(pos, 26, Vector3.UP, 140.0,
		2.0, 6.0, 0.5,
		Color(0.55, 0.8, 1.0), 4.0, 0.5, 1.4)
