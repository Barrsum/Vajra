extends RefCounted
## Builds the stylised sky material and its star field.
##
## No class_name: registration has silently failed under --headless twice in
## this project, taking a whole autoload down with it. Callers preload it.
##
## Kept out of arena.gd because the star texture is generated once and shared by
## every world — regenerating a 1024x1024 image on each level load would be a
## visible hitch for something that never changes.

const SKY_SHADER := preload("res://shaders/sky.gdshader")

static var _stars: ImageTexture = null


## A star field, generated rather than downloaded. The shader wants stars on a
## black background, which is exactly what this is: mostly black, with a few
## thousand small bright points at varying brightness.
##
## Tiling matters here. The shader wraps this texture across the sky dome, so
## any structure in the placement shows up as a repeating constellation. Pure
## random placement has no structure, which is what we want.
static func stars_texture() -> ImageTexture:
	if _stars != null:
		return _stars

	const SIZE := 1024
	var img := Image.create(SIZE, SIZE, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 1))

	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5EED  # fixed, so the sky is the same sky every run

	# Two populations. A lot of faint pinpricks reads as depth; a handful of
	# bright ones give the eye something to land on. All stars only.
	_scatter(img, rng, 2600, 0.18, 0.45, 0.0)
	_scatter(img, rng, 240, 0.55, 1.00, 0.55)

	img.generate_mipmaps()
	_stars = ImageTexture.create_from_image(img)
	return _stars


## Places `count` stars with brightness in [lo, hi]. `bloom` adds a dimmer
## one-pixel halo, which is what stops the bright ones looking like dead pixels.
static func _scatter(img: Image, rng: RandomNumberGenerator, count: int,
		lo: float, hi: float, bloom: float) -> void:
	var size := img.get_width()
	for i in count:
		var x := rng.randi_range(0, size - 1)
		var y := rng.randi_range(0, size - 1)
		var b := rng.randf_range(lo, hi)
		# A slight colour spread. Real starfields are not neutral grey, and the
		# variation survives even at one pixel.
		var col := Color(
			b * rng.randf_range(0.85, 1.0),
			b * rng.randf_range(0.88, 1.0),
			b * rng.randf_range(0.92, 1.0), 1.0)
		img.set_pixel(x, y, col)
		if bloom <= 0.0:
			continue
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var px := wrapi(x + o.x, 0, size)
			var py := wrapi(y + o.y, 0, size)
			img.set_pixel(px, py, col * bloom)


## Swaps a WorldEnvironment's sky over to the stylised shader, once.
## Returns the ShaderMaterial either way, so callers can just push uniforms.
static func ensure_material(env: Environment) -> ShaderMaterial:
	if env == null:
		return null
	if env.sky == null:
		env.sky = Sky.new()
	var mat := env.sky.sky_material as ShaderMaterial
	if mat == null:
		mat = ShaderMaterial.new()
		mat.shader = SKY_SHADER
		env.sky.sky_material = mat
		mat.set_shader_parameter("stars_texture", stars_texture())
	# The dome is cheap to evaluate per pixel but this shader is not — five
	# octaves of cubic value noise, three times over. Quarter resolution on the
	# background is invisible on a sky and roughly a quarter of the cost.
	env.sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	return mat
