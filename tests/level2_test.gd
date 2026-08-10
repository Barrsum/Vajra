extends Node
## Walks the level 2 ambush: three arrive in frame, two pin an arm each, the
## heavy swings, the player is thrown, and a crowd is waiting where they land.

const OUT := "res://shots/"
var failures := 0
var arena: Node
var player: CharacterBody3D


func _ready() -> void:
	await get_tree().process_frame
	var decoy := Node.new()
	get_tree().root.add_child(decoy)
	get_tree().current_scene = decoy
	await _wait(20)

	print("")
	print("=== level 2 ambush ===")
	Game.start_world(1)
	await _wait(280)
	arena = get_tree().current_scene
	player = arena.get_node("Player") as CharacterBody3D

	var a := _tally()
	_dump("arrival", a)
	_check("three arrive", a["total"] == 3)
	_check("two chargers", arena._grabbers.size() == 2)
	_check("smasher is pumpkinhulk", arena._smasher.creature == 1)
	await _shot("l2-01-ambush")

	# They should close and pin without any input from the player.
	var held := false
	var grabbed := false
	for i in 400:
		await get_tree().physics_frame
		for g in arena._grabbers:
			if is_instance_valid(g) and g.role == g.Role.HOLD:
				held = true
		if player.grabbed:
			grabbed = true
		if held and grabbed:
			break
	_check("an arm is taken", held)
	_check("player is held", grabbed)
	await _shot("l2-02-held")

	# The heavy closes and swings; the player gets thrown.
	var start: Vector3 = player.global_position
	var launched := false
	for i in 700:
		await get_tree().physics_frame
		if player.is_launched():
			launched = true
			break
	_check("smash launches player", launched)
	await _shot("l2-03-launch")

	await _wait(90)
	var moved: float = start.distance_to(player.global_position)
	_check("thrown clear (%.1fm)" % moved, moved > 4.0)
	_check("released after smash", not player.grabbed)

	# Reinforcements at the landing spot.
	for i in 360:
		await get_tree().physics_frame
		if _tally()["total"] >= 5:
			break
	var b := _tally()
	_dump("aftermath", b)
	_check("crowd waiting", b["total"] >= 5)
	await _shot("l2-04-aftermath")

	print("")
	print("  %s" % ("ALL PASS" if failures == 0 else "%d FAILURE(S)" % failures))
	print("")
	get_tree().quit(1 if failures > 0 else 0)


func _tally() -> Dictionary:
	var out := {"total": 0, "t0": 0, "t1": 0, "t2": 0}
	for e in get_tree().get_nodes_in_group("enemies"):
		if not e.is_alive():
			continue
		out["total"] += 1
		out["t%d" % e.tier] += 1
	return out


func _dump(tag: String, a: Dictionary) -> void:
	var names := {}
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.is_alive():
			var n: String = e.CREATURES[e.creature]["name"]
			names[n] = int(names.get(n, 0)) + 1
	print("     [%s] alive=%d t0=%d t1=%d  beat=%d  %s" % [
		tag, a["total"], a["t0"], a["t1"], arena._beat, names])


func _check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
	print("  %-28s %s" % [label, "PASS" if ok else "FAIL"])


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + name + ".png")
