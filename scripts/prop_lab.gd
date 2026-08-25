extends Node3D
## Prop lab: every generated asset laid out on a floor, with a free camera and
## a resize control. No enemies, no quota, no combat.
##
## This exists because the only question that matters about a generated prop is
## "how big should it be in metres", and that is not answerable from a
## turntable in a browser. You have to stand next to it. The 1.8m reference
## figure is here for exactly that — a tree is not 9 metres because 9 is a nice
## number, it is 9 metres because it looks right beside a person.
##
## When a prop looks right, press P. It prints a line you can paste straight
## into world.gd.
##
## Run:  PROPS.bat

const Props := preload("res://scripts/props.gd")

const CATEGORIES := ["forest", "cave", "dust", "night"]
const SPACING := 14.0

var _items: Array = []          # [{node, name, category, height, label}]
var _sel := 0
var _cam: Camera3D
var _yaw := 0.0
var _pitch := -0.12
var _speed := 14.0
var _hud: Label
var _free_mouse := false


func _ready() -> void:
	_ground()
	_lights()
	_reference_figure()
	_layout()
	_camera()
	_ui()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _ground() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	# Subdivided so the grid material has geometry to shade across; a single
	# quad would give a flat wash with no sense of distance.
	pm.subdivide_width = 40
	pm.subdivide_depth = 40
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.16, 0.17, 0.18)
	m.roughness = 0.95
	mi.material_override = m
	add_child(mi)

	# One-metre grid, so size is readable without measuring anything.
	var grid := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.vertex_color_use_as_albedo = true
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	im.surface_begin(Mesh.PRIMITIVE_LINES, gm)
	for i in range(-100, 101):
		var f := float(i)
		# Every tenth line brighter, so you can count in tens at a glance.
		var c := Color(1, 1, 1, 0.16) if i % 10 == 0 else Color(1, 1, 1, 0.05)
		im.surface_set_color(c)
		im.surface_add_vertex(Vector3(f, 0.02, -100))
		im.surface_set_color(c)
		im.surface_add_vertex(Vector3(f, 0.02, 100))
		im.surface_set_color(c)
		im.surface_add_vertex(Vector3(-100, 0.02, f))
		im.surface_set_color(c)
		im.surface_add_vertex(Vector3(100, 0.02, f))
	im.surface_end()
	grid.mesh = im
	add_child(grid)


func _lights() -> void:
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.5
	sun.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(38.0), 0.0)
	sun.shadow_enabled = true
	add_child(sun)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var pm := ProceduralSkyMaterial.new()
	pm.sky_top_color = Color(0.28, 0.36, 0.50)
	pm.sky_horizon_color = Color(0.62, 0.66, 0.70)
	pm.ground_bottom_color = Color(0.14, 0.14, 0.15)
	pm.ground_horizon_color = Color(0.4, 0.4, 0.42)
	sky.sky_material = pm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)


## A 1.8m figure at the origin. Every judgement about prop size is really a
## judgement about size relative to the player, so the player has to be here.
func _reference_figure() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.95, 0.45, 0.15)
	m.roughness = 0.6

	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.28
	cap.height = 1.5
	body.mesh = cap
	body.material_override = m
	add_child(body)
	body.position = Vector3(0, 0.9, 0)

	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.14
	sm.height = 0.28
	head.mesh = sm
	head.material_override = m
	add_child(head)
	head.position = Vector3(0, 1.72, 0)

	_tag("1.8 m — the player", Vector3(0, 2.1, 0), Color(1.0, 0.7, 0.35))


func _layout() -> void:
	var x := SPACING
	for cat in CATEGORIES:
		for path in Props.list(cat):
			var name := path.get_file().get_basename()
			# 8m is a middling tree: tall enough to read as scenery, short
			# enough that a wrong guess is obvious rather than absurd.
			var h := 8.0
			var node := Props.spawn_path(path, h)
			if node == null:
				continue
			add_child(node)
			node.position = Vector3(x, 0, 0)
			var label := _tag("%s  ·  %s" % [name, cat],
				Vector3(x, 0.0, 0), Color(1, 1, 1))
			_items.append({
				"node": node, "name": name, "category": cat,
				"height": h, "label": label, "path": path, "x": x,
			})
			x += SPACING

	if _items.is_empty():
		_tag("no props generated yet — run forge.py",
			Vector3(0, 3.4, -6), Color(1, 0.5, 0.4))


func _tag(text: String, at: Vector3, col: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0011
	l.modulate = col
	l.outline_size = 10
	add_child(l)
	l.position = at
	return l


func _camera() -> void:
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.far = 800.0
	add_child(_cam)
	_cam.position = Vector3(-6, 4.5, 14)
	_yaw = deg_to_rad(-20.0)
	_look()


func _ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.add_theme_font_size_override("font_size", 15)
	_hud.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	_hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_hud.add_theme_constant_override("outline_size", 6)
	layer.add_child(_hud)
	_hud.position = Vector2(18, 14)
	_refresh_hud()


func _refresh_hud() -> void:
	var lines := [
		"PROP LAB     WASD + mouse to fly, SHIFT faster, ALT free cursor",
		"TAB next prop   [ ] resize   R random spin   P print for world.gd",
		"",
	]
	if _items.is_empty():
		lines.append("no props yet — put images in pronto-expo/refs/<world>/")
		lines.append("then:  python forge.py --in refs/forest --category forest")
	else:
		var it: Dictionary = _items[_sel]
		lines.append("[%d/%d]  %s  (%s)" % [
			_sel + 1, _items.size(), it["name"], it["category"]])
		lines.append("height  %.1f m        %s" % [
			it["height"], _describe(float(it["height"]))])
	_hud.text = "\n".join(lines)


## Height alone is abstract; anchoring it to something in the world is not.
func _describe(h: float) -> String:
	if h < 1.0:
		return "(underfoot — a rock or a mushroom)"
	if h < 2.5:
		return "(waist to head high — a bush, a crate)"
	if h < 5.0:
		return "(taller than the player — a boulder, a stall)"
	if h < 12.0:
		return "(scenery — a tree you walk under)"
	if h < 25.0:
		return "(landmark — visible across the arena)"
	return "(skyline — seen from anywhere)"


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and not _free_mouse:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.0032
		_pitch = clampf(_pitch - mm.relative.y * 0.0032, -1.45, 1.45)
		_look()

	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		match k:
			KEY_ESCAPE:
				get_tree().quit()
			KEY_ALT:
				pass
			KEY_TAB:
				if not _items.is_empty():
					_sel = (_sel + 1) % _items.size()
					_focus()
					_refresh_hud()
			KEY_BRACKETLEFT:
				_resize(-1)
			KEY_BRACKETRIGHT:
				_resize(1)
			KEY_R:
				if not _items.is_empty():
					_items[_sel]["node"].rotation.y = randf() * TAU
			KEY_P:
				_print_line()


func _process(delta: float) -> void:
	# ALT frees the cursor without leaving the scene, so the window can be
	# resized or a screenshot taken mid-inspection.
	var want_free := Input.is_key_pressed(KEY_ALT)
	if want_free != _free_mouse:
		_free_mouse = want_free
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _free_mouse \
			else Input.MOUSE_MODE_CAPTURED

	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		dir -= _cam.global_transform.basis.z
	if Input.is_key_pressed(KEY_S):
		dir += _cam.global_transform.basis.z
	if Input.is_key_pressed(KEY_A):
		dir -= _cam.global_transform.basis.x
	if Input.is_key_pressed(KEY_D):
		dir += _cam.global_transform.basis.x
	if Input.is_key_pressed(KEY_E):
		dir += Vector3.UP
	if Input.is_key_pressed(KEY_Q):
		dir -= Vector3.UP
	var mul := 3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0
	if dir.length() > 0.01:
		_cam.global_position += dir.normalized() * _speed * mul * delta


func _look() -> void:
	_cam.rotation = Vector3(_pitch, _yaw, 0.0)


## Rebuilds the prop at the new height rather than scaling the node, so what is
## on screen is exactly what world.gd will produce from the same number.
func _resize(dir: int) -> void:
	if _items.is_empty():
		return
	var it: Dictionary = _items[_sel]
	var h: float = float(it["height"])
	# Proportional steps: 0.5m matters at 2m and is invisible at 30m.
	var step: float = maxf(0.25, h * 0.10)
	h = clampf(h + step * float(dir), 0.25, 80.0)
	it["height"] = h

	var old: Node3D = it["node"]
	var spin: float = old.rotation.y
	old.queue_free()
	var node := Props.spawn_path(String(it["path"]), h)
	add_child(node)
	node.position = Vector3(float(it["x"]), 0, 0)
	node.rotation.y = spin
	it["node"] = node
	_refresh_hud()


func _focus() -> void:
	var it: Dictionary = _items[_sel]
	var h: float = float(it["height"])
	# Back off proportionally, so a 30m landmark and a 2m crate both fill a
	# similar part of the screen when selected.
	_cam.global_position = Vector3(float(it["x"]) - h * 0.9, h * 0.55, h * 1.5)
	_yaw = deg_to_rad(-28.0)
	_pitch = -0.18
	_look()


func _print_line() -> void:
	if _items.is_empty():
		return
	var it: Dictionary = _items[_sel]
	print("")
	print("  # %s" % it["name"])
	print('  var p := Props.spawn("%s", %.1f, _rng)' % [it["category"], it["height"]])
	print('  # or, for something solid:')
	print('  var p := Props.spawn_solid("%s", %.1f, 0.0, _rng)'
		% [it["category"], it["height"]])
	print("")
