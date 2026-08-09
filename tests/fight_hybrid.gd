extends Node
## Same fight check, run against the hybrid (GDQuest movement + our combat).
##
## Aiming here means driving GDQuest's CameraController rather than a yaw field,
## since target assist reads the camera's forward vector.

const MAIN := preload("res://scenes/main_hybrid.tscn")
const OUT := "res://shots/"

var player: CharacterBody3D
var cam: Node3D


func _ready() -> void:
	# The arena only spawns while the run is live. Loading the scene directly
	# bypasses Game.start_run(), so declare the state by hand.
	Game.state = Game.State.PLAYING
	Game.collected = 0
	var world := MAIN.instantiate()
	add_child(world)
	await get_tree().process_frame
	player = world.get_node("Player")
	cam = player.get_node("CameraController")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	print("")
	print("=== hybrid fight ===")
	await _wait(150)

	var n := _enemies().size()
	print("  spawned: %d" % n)
	if n == 0:
		print("  FAIL - nothing spawned")
		get_tree().quit(1)
		return
	await _shot("hy-01-approach")

	var start_hp := _hp()
	var swings := 0

	for i in 110:
		var t := _nearest()
		if t == null:
			break
		var d: Vector3 = t.global_position - player.global_position
		# This rig's forward is +basis.z (see hero.gd), so yaw is unnegated.
		cam._euler_rotation.y = atan2(d.x, d.z)
		var dist := Vector2(d.x, d.z).length()

		if dist > 3.6:
			Input.action_press("move_forward")
			await _wait(6)
			Input.action_release("move_forward")
		else:
			Input.action_press("attack")
			await _wait(2)
			Input.action_release("attack")
			swings += 1
			await _wait(14)

		if i == 34:
			await _shot("hy-02-fighting")
		if _enemies().is_empty():
			break

	await _shot("hy-03-after")
	var end_hp := _hp()
	print("  swings      : %d" % swings)
	print("  enemy hp    : %.0f -> %.0f  (dealt %.0f)" % [start_hp, end_hp, start_hp - end_hp])
	print("  player hp   : %.0f / %.0f" % [player.health, player.max_health])
	print("  enemies left: %d" % _enemies().size())
	var ok := (start_hp - end_hp) > 0.0
	print("")
	print("  %s" % ("DAMAGE LANDS" if ok else "*** NO DAMAGE ***"))
	print("")
	get_tree().quit(0 if ok else 1)


func _enemies() -> Array:
	var out := []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.has_method("is_alive") and e.is_alive():
			out.append(e)
	return out


func _hp() -> float:
	var t := 0.0
	for e in _enemies():
		t += e.health
	return t


func _nearest() -> Node3D:
	var best: Node3D = null
	var bd := INF
	for e in _enemies():
		var d: float = player.global_position.distance_squared_to(e.global_position)
		if d < bd:
			bd = d
			best = e
	return best


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + name + ".png")
