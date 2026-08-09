extends Node
## Headless movement check. Drives the real player through the real scene and
## measures displacement in CAMERA space, so "left goes left" is verified the way
## a player perceives it rather than by reasoning about world axes.
##
## Run: godot --headless --path . res://tests/movement_test.tscn

const MAIN := preload("res://scenes/main.tscn")

var player: CharacterBody3D
var camera: Camera3D
var failures := 0


func _ready() -> void:
	var world := MAIN.instantiate()
	add_child(world)
	await get_tree().process_frame

	player = world.get_node("Player")
	camera = world.get_node("Player/CamRoot/SpringArm3D/Camera3D")

	# Mouse capture is meaningless headless and spams the log.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	print("")
	print("--- movement (camera space) ---")
	await _check("move_forward", Vector3(0, 0, -1), "forward")
	await _check("move_back",    Vector3(0, 0,  1), "back")
	await _check("move_right",   Vector3(1, 0,  0), "right")
	await _check("move_left",    Vector3(-1, 0, 0), "left")

	print("")
	print("--- jump ---")
	await _check_jump()

	print("")
	print("--- variable jump height ---")
	await _check_variable_jump()

	print("")
	print("--- dodge ---")
	await _check_dodge()

	print("")
	print("  %s" % ("ALL PASS" if failures == 0 else "%d FAILURE(S)" % failures))
	print("")
	get_tree().quit(1 if failures > 0 else 0)


func _settle(frames := 30) -> void:
	for i in frames:
		await get_tree().physics_frame


func _local_delta(before: Vector3) -> Vector3:
	# Camera basis is taken fresh; the spring arm trails, so we sample mid-move.
	return camera.global_transform.basis.inverse() * (player.global_position - before)


func _check(action: String, expect: Vector3, label: String) -> void:
	await _settle()
	var before := player.global_position
	Input.action_press(action)
	for i in 18:
		await get_tree().physics_frame
	var moved := _local_delta(before)
	Input.action_release(action)
	await _settle()

	# Dominant axis must match the expected sign and actually travel.
	var got := Vector3(moved.x, 0, moved.z)
	var ok := got.length() > 0.4 and got.normalized().dot(expect) > 0.85
	if not ok:
		failures += 1
	print("  %-8s local(x=%+.2f z=%+.2f)  %s" % [label, moved.x, moved.z, "PASS" if ok else "FAIL"])


func _check_jump() -> void:
	await _settle()
	var y0 := player.global_position.y
	Input.action_press("jump")
	await get_tree().physics_frame
	Input.action_release("jump")

	var peak := y0
	for i in 40:
		await get_tree().physics_frame
		peak = maxf(peak, player.global_position.y)
	await _settle(80)

	var landed := absf(player.global_position.y - y0) < 0.15
	var rose := peak - y0
	var ok := rose > 0.8 and landed
	if not ok:
		failures += 1
	print("  apex +%.2fm, returned to ground: %s  %s" % [rose, landed, "PASS" if ok else "FAIL"])


## Holding jump must clear noticeably more height than tapping it.
func _check_variable_jump() -> void:
	var tap := await _jump_apex(1)
	var hold := await _jump_apex(45)
	var ok := hold > tap * 1.15
	if not ok:
		failures += 1
	print("  tap %.2fm  vs  hold %.2fm   (+%.0f%%)  %s" % [
		tap, hold, (hold / maxf(tap, 0.01) - 1.0) * 100.0, "PASS" if ok else "FAIL",
	])


func _jump_apex(hold_frames: int) -> float:
	await _settle(60)
	var y0 := player.global_position.y
	Input.action_press("jump")
	var peak := y0
	for i in 60:
		await get_tree().physics_frame
		if i == hold_frames:
			Input.action_release("jump")
		peak = maxf(peak, player.global_position.y)
	Input.action_release("jump")
	await _settle(70)
	return peak - y0


func _check_dodge() -> void:
	await _settle()
	var before := player.global_position
	Input.action_press("dodge")
	await get_tree().physics_frame
	Input.action_release("dodge")

	var was_invuln := false
	for i in 12:
		await get_tree().physics_frame
		if player.is_invulnerable():
			was_invuln = true
	await _settle(40)

	var dist := before.distance_to(player.global_position)
	var ok := dist > 1.5 and was_invuln
	if not ok:
		failures += 1
	print("  travelled %.2fm, i-frames seen: %s  %s" % [dist, was_invuln, "PASS" if ok else "FAIL"])
