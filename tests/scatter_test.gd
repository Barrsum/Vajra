extends Node3D
## The ground scatter: instancing, coverage, and the two things that make a
## field of overlapping patches look like a surface instead of a mess.

const Props := preload("res://scripts/props.gd")
const Scatter := preload("res://scripts/ground_scatter.gd")

const OUT := "res://shots/"
var failures := 0


func _ready() -> void:
	await get_tree().process_frame
	print("")
	print("=== ground scatter ===")

	var cat := ""
	var found := Props.categories()
	if not found.is_empty():
		cat = String(found[0])
	if cat == "":
		print("  nothing generated yet — skipped")
		_done()
		return
	print("  scattering '%s'" % cat)

	_check("an empty category scatters to null, not an error",
		Scatter.scatter(self, "no_such_category", 20.0) == null)

	var field: Node3D = Scatter.scatter(self, cat, 30.0, 8.0, 1.5)
	await get_tree().process_frame
	_check("a field is produced", field != null)

	# One MultiMesh per unique mesh, NOT one node per patch. This is the whole
	# performance argument: 200 patch nodes is 200 draw calls.
	var calls := 0
	var instances := 0
	for c in field.get_children():
		if c is MultiMeshInstance3D:
			calls += 1
			instances += (c as MultiMeshInstance3D).multimesh.instance_count
	_check("instanced: %d patches in %d draw calls" % [instances, calls],
		calls <= Props.list(cat).size() and instances > calls)

	var area := PI * 30.0 * 30.0
	var want := int(area / 100.0 * 1.5)
	_check("count tracks density (%d, wanted about %d)" % [instances, want],
		instances > want * 0.3)

	# The properties that stop a scatter reading as stamped copies, checked
	# against Scatter.plan rather than against the MultiMesh — the headless
	# renderer does not retain a MultiMesh buffer, so reading transforms back
	# from it returns identities and verifies nothing.
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var spots: Array = []
	for i in 40:
		spots.append(Vector2(float(i) * 3.0, float(i % 7) * 2.0))
	var box := AABB(Vector3(-0.5, -0.04, -0.5), Vector3(1.0, 0.08, 1.0))
	var xf := Scatter.plan(box, spots, 8.0, rng, 0.06)

	_check("one transform per patch", xf.size() == spots.size())

	var yaws := {}
	var scales: Array = []
	var ys: Array = []
	for t in xf:
		yaws[roundi(t.basis.get_euler().y * 12.0)] = true
		scales.append(t.basis.get_scale().x)
		ys.append(t.origin.y)
	_check("rotations vary (%d distinct)" % yaws.size(), yaws.size() > 3)
	var lo: float = scales.min()
	var hi: float = scales.max()
	_check("sizes vary (%.2f to %.2f)" % [lo, hi], hi > lo * 1.2)
	var uniq := {}
	for y in ys:
		uniq[snappedf(y, 0.0001)] = true
	# The stagger cycles every 24, so 40 patches share heights by design —
	# what matters is that there are many distinct levels, not that every one
	# is unique. An unbounded stagger would float the far end of a big field.
	_check("heights are staggered (%d levels over %d patches)"
		% [uniq.size(), ys.size()], uniq.size() >= 20)
	var spread: float = float(ys.max()) - float(ys.min())
	_check("stagger is bounded, not accumulating (spread %.3f m)" % spread,
		spread < 0.6)
	_check("a flat patch ends up at or below ground", float(ys.max()) <= 0.02)

	rng.seed = 12345
	var shallow := Scatter.plan(box, spots, 8.0, rng, 0.0)
	rng.seed = 12345
	var deeper := Scatter.plan(box, spots, 8.0, rng, 0.25)
	_check("sink lowers the field (%.2f -> %.2f)"
		% [shallow[0].origin.y, deeper[0].origin.y],
		deeper[0].origin.y < shallow[0].origin.y - 1.0)

	var mmi: MultiMeshInstance3D = null
	for c in field.get_children():
		if c is MultiMeshInstance3D:
			mmi = c
			break

	# A wrong AABB pops the whole field out of view at glancing angles, which
	# looks like the ground blinking off.
	if mmi:
		_check("custom aabb is set, so the field cannot be wrongly culled",
			mmi.custom_aabb.size.length() > 100.0)

	if DisplayServer.get_name() != "headless":
		await _shot(field)

	_done()


func _shot(field: Node3D) -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.7
	add_child(env)
	env.environment = e

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(35.0), 0)
	sun.light_energy = 1.4
	add_child(sun)

	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 12, 30)
	cam.look_at(Vector3(0, 0, 0), Vector3.UP)
	cam.current = true

	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + "scatter.png")
	print("  wrote shots/scatter.png")


func _done() -> void:
	print("")
	print("=== %s ===" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	get_tree().quit(1 if failures > 0 else 0)


func _check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
	print("  %-56s %s" % [label, "PASS" if ok else "FAIL"])
