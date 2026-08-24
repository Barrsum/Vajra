extends RefCounted
## Textures for the fire and lightning shaders, all generated at runtime.
##
## No class_name: registration has silently failed under --headless twice in
## this project. Callers preload it.
##
## Between them the three shaders want a 3D noise volume, two scrolling noise
## sheets, a fire colour ramp, a soft alpha mask and a vertical falloff — eight
## textures for three effects. Generating them keeps the repo free of binary
## art nobody can diff, and every one is a few lines of maths.
##
## All are cached statically: a 64-cubed volume is a quarter of a million
## voxels and is not something to rebuild per campfire.

static var _volume: NoiseTexture3D = null
static var _fire_noise: NoiseTexture2D = null
static var _uv_random: NoiseTexture2D = null
static var _ramp: ImageTexture = null
static var _flame_alpha: ImageTexture = null
static var _falloff: ImageTexture = null
static var _tail: ImageTexture = null


## The 3D noise the raymarched fire samples. Seamless matters here: the shader
## reads it with fract(), so a volume that does not tile shows a hard plane
## through the middle of every flame.
static func fire_volume() -> NoiseTexture3D:
	if _volume != null:
		return _volume
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.035
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 4
	n.fractal_gain = 0.5

	var t := NoiseTexture3D.new()
	t.noise = n
	t.width = 64
	t.height = 64
	t.depth = 64
	t.seamless = true
	t.normalize = true
	_volume = t
	return _volume


## Scrolling flame noise for the stylised fire.
static func flame_noise() -> NoiseTexture2D:
	if _fire_noise != null:
		return _fire_noise
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = 0.02
	n.fractal_octaves = 3
	var t := NoiseTexture2D.new()
	t.noise = n
	t.width = 256
	t.height = 256
	t.seamless = true
	_fire_noise = t
	return _fire_noise


## A second, coarser noise used to jitter UVs so the flame does not scroll as
## one flat sheet.
static func uv_random() -> NoiseTexture2D:
	if _uv_random != null:
		return _uv_random
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_VALUE
	n.frequency = 0.06
	var t := NoiseTexture2D.new()
	t.noise = n
	t.width = 128
	t.height = 128
	t.seamless = true
	_uv_random = t
	return _uv_random


## Fire colour ramp: white-hot at the base, cooling up through orange to a deep
## red tip.
##
## VERTICAL, and that matters. The first version ran the gradient along X, and
## the shader samples it with the mesh UV — on a cylinder, U runs around the
## circumference, so the ramp wrapped the flame in bands and the whole thing
## came out looking like a traffic cone. Temperature belongs on the axis that
## maps to height.
static func fire_ramp() -> ImageTexture:
	if _ramp != null:
		return _ramp
	const H := 128
	var img := Image.create(8, H, false, Image.FORMAT_RGBA8)
	# v = 0 is the top of the texture and the top of the flame.
	var stops := [
		[0.00, Color(0.24, 0.02, 0.00)],
		[0.22, Color(0.85, 0.12, 0.01)],
		[0.52, Color(1.00, 0.48, 0.04)],
		[0.78, Color(1.00, 0.82, 0.30)],
		[1.00, Color(1.00, 0.97, 0.82)],
	]
	for y in H:
		var t := float(y) / float(H - 1)
		var col := _ramp_at(stops, t)
		# Alpha ZERO, deliberately. The shader does
		#     ALPHA = clamp(Alpha_Texture.a + Final_Color.a, 0, 1)
		# and Final_Color is the noise times this ramp. Leaving alpha at 1 here
		# drove that sum to 1 across the whole mesh, so the flame rendered as a
		# solid rectangle with a nice gradient on it. At 0 the silhouette comes
		# entirely from the alpha mask, which is the only thing that knows the
		# shape of a flame.
		col.a = 0.0
		for x in 8:
			img.set_pixel(x, y, col)
	_ramp = ImageTexture.create_from_image(img)
	return _ramp


## Flame silhouette: opaque at the base, tapering to nothing at the tip, and
## narrowing toward the top. This is what gives the stylised fire its shape —
## the mesh is a plain cone.
static func flame_alpha() -> ImageTexture:
	if _flame_alpha != null:
		return _flame_alpha
	const S := 128
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	for y in S:
		var v := float(y) / float(S - 1)
		# v = 0 is the top of the flame, so width grows as v does.
		var width: float = pow(v, 0.7)
		for x in S:
			var u := (float(x) / float(S - 1)) * 2.0 - 1.0
			var inside := 1.0 - smoothstep(width * 0.45, width, absf(u))
			# Fade the very top to a point, and the very bottom into the logs.
			var ends: float = smoothstep(0.0, 0.10, v) * (1.0 - smoothstep(0.90, 1.0, v))
			var a := clampf(inside * ends, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_flame_alpha = ImageTexture.create_from_image(img)
	return _flame_alpha


## Vertical falloff. The lightning shader multiplies ALPHA by this, so a bolt
## fades in at the cloud and out at the ground instead of ending at the quad
## edge with a visible straight cut.
static func bolt_falloff() -> ImageTexture:
	if _falloff != null:
		return _falloff
	const S := 64
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	for y in S:
		var v := float(y) / float(S - 1)
		# Bright through the middle, softening at both ends.
		var a := smoothstep(0.0, 0.16, v) * (1.0 - smoothstep(0.72, 1.0, v))
		for x in S:
			img.set_pixel(x, y, Color(a, a, a, 1.0))
	_falloff = ImageTexture.create_from_image(img)
	return _falloff


## Displacement weight for the stylised fire's vertex stage: none at the base
## so the flame stays planted, rising toward the tip.
static func tail_power() -> ImageTexture:
	if _tail != null:
		return _tail
	const S := 64
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	for y in S:
		var v := float(y) / float(S - 1)
		var p := pow(1.0 - v, 1.6)
		for x in S:
			img.set_pixel(x, y, Color(p, p, p, 1.0))
	_tail = ImageTexture.create_from_image(img)
	return _tail


static func _ramp_at(stops: Array, t: float) -> Color:
	for i in range(stops.size() - 1):
		var a: Array = stops[i]
		var b: Array = stops[i + 1]
		if t <= float(b[0]):
			var span: float = maxf(float(b[0]) - float(a[0]), 0.0001)
			return (a[1] as Color).lerp(b[1] as Color, (t - float(a[0])) / span)
	return stops[stops.size() - 1][1]
