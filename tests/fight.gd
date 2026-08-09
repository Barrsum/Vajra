extends Node
## Drives an actual fight: closes on the nearest enemy, swings, and reports
## whether damage lands and whether anything dies. Windowed so it also captures
## frames of the fight.
##
## Run: godot --path . --resolution 1280x720 res://tests/fight.tscn

const MAIN := preload("res://scenes/main.tscn")
const OUT := "res://shots/"

var world: Node
var player: CharacterBody3D


func _ready() -> void:
	world = MAIN.instantiate()
	add_child(world)
	await get_tree().process_frame
	player = world.get_node("Player")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	print("")
	print("=== fight ===")

	await _wait(150)   # let the wave spawn and close in
	var n := _enemies().size()
	print("  spawned: %d enemies" % n)
	if n == 0:
		print("  FAIL — nothing spawned")
		get_tree().quit(1)
		return

	await _shot("10-approach")

	var start_hp := _total_enemy_hp()
	var kills := 0
	var swings := 0

	for round_i in 90:
		var target := _nearest()
		if target == null:
			break

		# Face and close the distance.
		var d: Vector3 = target.global_position - player.global_position
		player.yaw = atan2(-d.x, -d.z)   # camera yaw convention, not model facing
		var dist := Vector2(d.x, d.z).length()
		if dist > 4.0:
			Input.action_press("move_forward")
			await _wait(6)
			Input.action_release("move_forward")
		else:
			Input.action_press("attack")
			await _wait(2)
			Input.action_release("attack")
			swings += 1
			await _wait(14)

		if round_i % 15 == 0:
			print("   r%-3d dist=%.2f  player=(%.1f,%.1f)  enemy_state=%s  swings=%d" % [
				round_i, dist, player.global_position.x, player.global_position.z,
				target.state, swings,
			])
		if round_i == 30:
			await _shot("11-fighting")

		kills = _dead_count()
		if _enemies().is_empty():
			break

	var end_hp := _total_enemy_hp()
	await _shot("12-after")

	print("  swings thrown : %d" % swings)
	print("  enemy hp      : %.0f -> %.0f  (dealt %.0f)" % [start_hp, end_hp, start_hp - end_hp])
	print("  player hp     : %.0f / %.0f" % [player.health, player.max_health])
	print("  enemies left  : %d" % _enemies().size())
	var ok := (start_hp - end_hp) > 0.0
	print("")
	print("  %s" % ("DAMAGE LANDS" if ok else "*** NO DAMAGE DEALT ***"))
	print("")
	get_tree().quit(0 if ok else 1)


func _enemies() -> Array:
	var out := []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.has_method("is_alive") and e.is_alive():
			out.append(e)
	return out


func _dead_count() -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.has_method("is_alive") and not e.is_alive():
			n += 1
	return n


func _total_enemy_hp() -> float:
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
