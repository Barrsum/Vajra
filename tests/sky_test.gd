extends Node
## Renders the stylised sky for all four worlds and shoots each one.
##
## This suite has to run windowed. A sky shader is compiled by the rendering
## driver, not by the resource loader, so under --headless a broken shader loads
## perfectly happily and reports nothing. The only honest check is to draw it.
##
## Run: godot --path . res://tests/sky_test.tscn

const OUT := "res://shots/"
const SkySetup := preload("res://scripts/sky_setup.gd")

var failures := 0


func _ready() -> void:
	await get_tree().process_frame
	# start_world() swaps the current scene, which frees whatever is in it. This
	# node has to survive four of those, so it lives under root and a throwaway
	# stands in as the current scene. Same trick the level suites use.
	var decoy := Node.new()
	get_tree().root.add_child(decoy)
	get_tree().current_scene = decoy
	await _wait(10)

	print("")
	print("=== sky shader ===")

	if DisplayServer.get_name() == "headless":
		print("  headless: shaders are never compiled, nothing to verify.")
		print("  Run windowed:  godot --path . res://tests/sky_test.tscn")
		get_tree().quit(0)
		return

	# 1. The star field is generated, not downloaded — check it is actually a
	# star field and not a black square or a grey wash.
	var tex := SkySetup.stars_texture()
	_check("stars texture is 1024px", tex != null and tex.get_width() == 1024)
	var img := tex.get_image()
	var lit := 0
	var brightest := 0.0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var v: float = img.get_pixel(x, y).r
			if v > 0.05:
				lit += 1
			brightest = maxf(brightest, v)
	var frac := float(lit) / float((img.get_width() / 2) * (img.get_height() / 2))
	_check("stars are sparse (%.3f%% lit)" % (frac * 100.0), frac > 0.0002 and frac < 0.05)
	_check("stars reach full brightness (%.2f)" % brightest, brightest > 0.5)
	_check("same texture is reused", SkySetup.stars_texture() == tex)

	# 2. Every world must produce a material with the shader on it, and the
	# sun angle must put the sky where the world's name says it is.
	for i in 4:
		var w: Resource = Game.worlds[i]
		var env := Environment.new()
		var m := SkySetup.ensure_material(env)
		_check("world %d: material built" % (i + 1), m != null and m.shader != null)
		# LIGHT0_DIRECTION.y is +basis.z.y of the sun, which for a pure X
		# rotation is sin(-angle_x). Negative means the sun is below the
		# horizon and the shader will render night.
		var sun_y := sin(deg_to_rad(-w.sun_angles.x))
		var is_night: bool = sun_y < 0.0
		_check("world %d: %s is %s (sun y %+.2f)" % [
			i + 1, w.display_name, "night" if is_night else "day", sun_y,
		], is_night == (i == 3))

	# 3. The sky on its own, no level geometry. In the arena the sky is a thin
	# band above the props, which makes it almost impossible to tell a broken
	# sky from a dark level — so shoot the dome directly, camera tilted up.
	await _dome_shots()

	# 4. Draw each world for real. If the shader failed to compile, Godot logs
	# it here and the screenshots come out as flat colour.
	for i in 4:
		Game.start_world(i)
		await _wait(90)
		var slug := String(Game.worlds[i].display_name).to_lower().replace(" ", "-")
		await _shot("sky-%d-%s" % [i + 1, slug])
		# And again looking up. The arenas are walled, so at the normal camera
		# pitch the sky is a thin strip — this says whether that strip is sky or
		# whether something is covering it.
		var cam := get_viewport().get_camera_3d()
		if cam:
			cam.rotation.x = deg_to_rad(35.0)
			await _wait(4)
			await _shot("skyup-%d-%s" % [i + 1, slug])
		print("  shot world %d" % (i + 1))

	print("")
	print("=== %s ===" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	get_tree().quit(1 if failures > 0 else 0)


## Renders each world's sky against nothing, from a camera looking up.
func _dome_shots() -> void:
	var root := Node3D.new()
	get_tree().root.add_child(root)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env_node.environment = env
	root.add_child(env_node)

	var sun := DirectionalLight3D.new()
	var moon := DirectionalLight3D.new()
	root.add_child(sun)
	root.add_child(moon)

	var cam := Camera3D.new()
	cam.rotation = Vector3(deg_to_rad(18.0), 0.0, 0.0)  # tilted up
	cam.fov = 80.0
	root.add_child(cam)
	cam.current = true

	for i in 4:
		var w: Resource = Game.worlds[i]
		_apply_to(env, w)
		sun.rotation = Vector3(
			deg_to_rad(w.sun_angles.x), deg_to_rad(w.sun_angles.y), deg_to_rad(w.sun_angles.z))
		moon.rotation = Vector3(
			deg_to_rad(w.moon_angles.x), deg_to_rad(w.moon_angles.y), deg_to_rad(w.moon_angles.z))
		sun.light_energy = maxf(w.sun_energy, 0.01)
		moon.light_energy = maxf(w.moon_energy, 0.01)
		await _wait(8)
		await _shot("dome-%d" % (i + 1))
		print("  dome %d" % (i + 1))

	root.queue_free()
	await get_tree().process_frame


## The same uniform push arena.gd does, kept here so the dome preview cannot
## silently drift from what the game actually renders.
func _apply_to(env: Environment, w: Resource) -> void:
	var m := SkySetup.ensure_material(env)
	m.set_shader_parameter("day_top_color", w.day_top)
	m.set_shader_parameter("day_bottom_color", w.day_bottom)
	m.set_shader_parameter("sunset_top_color", w.sunset_top)
	m.set_shader_parameter("sunset_bottom_color", w.sunset_bottom)
	m.set_shader_parameter("night_top_color", w.night_top)
	m.set_shader_parameter("night_bottom_color", w.night_bottom)
	m.set_shader_parameter("horizon_color", w.horizon_tint)
	m.set_shader_parameter("horizon_blur", w.horizon_blur)
	m.set_shader_parameter("sun_color", w.sun_disc_color)
	m.set_shader_parameter("sun_size", w.sun_disc_size)
	m.set_shader_parameter("moon_color", w.moon_disc_color)
	m.set_shader_parameter("moon_size", w.moon_disc_size)
	m.set_shader_parameter("clouds_cutoff", w.clouds_cutoff)
	m.set_shader_parameter("clouds_weight", w.clouds_weight)
	m.set_shader_parameter("clouds_scale", w.clouds_scale)
	m.set_shader_parameter("clouds_top_color", w.clouds_tint)
	m.set_shader_parameter("stars_texture", SkySetup.stars_texture())


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + name + ".png")


func _check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
	print("  %-52s %s" % [label, "PASS" if ok else "FAIL"])
