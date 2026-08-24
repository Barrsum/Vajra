extends Node
## Fire, lightning and the storm rules.
##
## Run windowed to also compile the shaders and shoot the garden:
##   godot --path . res://tests/storm_test.tscn

const OUT := "res://shots/"
const CampfireScript := preload("res://scripts/campfire.gd")
const StormScript := preload("res://scripts/storm.gd")
const FxTextures := preload("res://scripts/fx_textures.gd")

var failures := 0


func _ready() -> void:
	await get_tree().process_frame
	var decoy := Node.new()
	get_tree().root.add_child(decoy)
	get_tree().current_scene = decoy
	await _wait(10)

	print("")
	print("=== fire, lightning, storm ===")

	# --- generated textures -------------------------------------------------
	var vol := FxTextures.fire_volume()
	_check("fire volume is 3D and 64 cubed",
		vol != null and vol.width == 64 and vol.depth == 64)
	_check("fire volume is seamless (it is sampled with fract)", vol.seamless)
	_check("volume is cached", FxTextures.fire_volume() == vol)

	# Sampled down the Y axis: the ramp is vertical, because on a mesh it is v
	# that maps to flame height. A horizontal ramp banded the flame instead.
	var ramp := FxTextures.fire_ramp().get_image()
	var tip := ramp.get_pixel(4, 2)
	var base := ramp.get_pixel(4, ramp.get_height() - 3)
	_check("ramp is taller than it is wide (it is vertical)",
		ramp.get_height() > ramp.get_width())
	_check("ramp runs cool tip to hot base (%.2f -> %.2f)" % [tip.r, base.r],
		base.r > tip.r and base.r > 0.9)
	_check("base is warm, not white-blue", base.b < base.r)

	var fall := FxTextures.bolt_falloff().get_image()
	_check("bolt falloff fades at both ends",
		fall.get_pixel(0, 0).r < 0.1
		and fall.get_pixel(0, fall.get_height() - 1).r < 0.1
		and fall.get_pixel(0, int(fall.get_height() / 2)).r > 0.8)

	# --- the campfire barrier ----------------------------------------------
	var fire: Node3D = CampfireScript.new()
	fire.barrier_radius = 3.0
	fire.volumetric = true
	add_child(fire)
	await _wait(3)

	var body: StaticBody3D = null
	for c in fire.get_children():
		if c is StaticBody3D:
			body = c
	_check("campfire has a static body", body != null)
	if body:
		var shape: CollisionShape3D = null
		for c in body.get_children():
			if c is CollisionShape3D:
				shape = c
		_check("barrier is a cylinder", shape != null and shape.shape is CylinderShape3D)
		if shape and shape.shape is CylinderShape3D:
			var cyl := shape.shape as CylinderShape3D
			_check("barrier radius matches (%.1f)" % cyl.radius,
				is_equal_approx(cyl.radius, 3.0))
		# Layer 1 is what the ground uses, so player and creatures both stop.
		_check("barrier collides on the default layer", body.collision_layer & 1 != 0)
	_check("campfire lights the ground", _has_child_of(fire, "OmniLight3D"))
	fire.queue_free()

	# --- storm rules --------------------------------------------------------
	var storm: Node3D = StormScript.new()
	_check("creature strike is 10 percent of max health",
		is_equal_approx(storm.creature_damage, 0.10))
	_check("player charge is 10 percent", is_equal_approx(storm.charge_bonus, 0.10))
	_check("player is the rarer target", storm.player_chance < 0.5)
	storm.free()

	# --- the charge, end to end --------------------------------------------
	Game.start_world(3)
	await _wait(160)
	var arena := get_tree().current_scene
	var found_storm := false
	for c in arena.get_children():
		if c.get_script() == StormScript:
			found_storm = true
	_check("level 4 spawns a storm", found_storm)

	var hero: Node = arena.get_node_or_null("Player")
	if hero:
		_check("hero starts uncharged", is_equal_approx(hero.charge, 0.0))
		hero.charge_next_hit(0.10)
		_check("charge sticks after a strike", is_equal_approx(hero.charge, 0.10))
		# A second strike must refresh, not stack — otherwise waiting out a
		# storm before engaging would be the optimal way to play the level.
		hero.charge_next_hit(0.10)
		_check("a second strike does not stack", is_equal_approx(hero.charge, 0.10))

	# A strike must scale with the target, not flatten small ones.
	var live: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.has_method("is_alive") and e.is_alive():
			live.append(e)
	if not live.is_empty():
		var e = live[0]
		var before: float = e.health
		var maxhp: float = e.max_health
		e.take_damage(maxhp * 0.10, e.global_position + Vector3.UP * 4.0, 0.0)
		_check("strike removes 10 percent of max (%.0f of %.0f)" % [
			before - e.health, maxhp],
			is_equal_approx(before - e.health, maxhp * 0.10))

	if DisplayServer.get_name() != "headless":
		await _wait(30)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OUT + "garden.png")
		print("  wrote shots/garden.png  (both flame shaders, lamps, trees)")

	print("")
	print("=== %s ===" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	get_tree().quit(1 if failures > 0 else 0)


func _has_child_of(n: Node, cls: String) -> bool:
	for c in n.get_children():
		if c.get_class() == cls:
			return true
	return false


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
	print("  %-52s %s" % [label, "PASS" if ok else "FAIL"])
