extends Node
## Runs the real game, drives it for a moment, and writes PNGs to shots/.
## Must run WITHOUT --headless — headless has no rasteriser to capture.
##
## Run: godot --path . --resolution 1280x720 res://tests/screenshot.tscn

const MAIN := preload("res://scenes/main.tscn")
const OUT := "res://shots/"

var player: Node


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var world := MAIN.instantiate()
	add_child(world)
	await get_tree().process_frame
	player = world.get_node("Player")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	await _wait(40)
	await _shot("01-idle")

	# Run forward. The camera trails behind, so a correctly-oriented model shows
	# us his back. If we can see his face, the mesh is 180 degrees out.
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _wait(45)
	await _shot("02-running")
	Input.action_release("sprint")
	await _wait(30)
	await _shot("03-walking")
	Input.action_release("move_forward")

	await _wait(30)
	Input.action_press("jump")
	await _wait(2)
	Input.action_release("jump")
	await _wait(14)
	await _shot("04-jump")

	await _wait(60)
	Input.action_press("attack")
	await _wait(2)
	Input.action_release("attack")
	await _wait(16)
	await _shot("05-attack")

	await _wait(40)
	Input.action_press("dodge")
	await _wait(2)
	Input.action_release("dodge")
	await _wait(8)
	await _shot("06-dodge")

	print("\n  screenshots written to %s\n" % OUT)
	get_tree().quit(0)


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT + name + ".png")
	var st := "" if player == null else " speed=%.1f" % player.planar_speed
	print("  %s%s" % [name, st])
