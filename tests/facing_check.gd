extends Node
## Determines which way the character mesh actually faces.
##
## The rotation root is built so that +Z is the travel direction. A glTF
## character conventionally faces -Z. If those disagree the model moonwalks and
## attacks behind itself — one root cause, two symptoms.

const MAIN := preload("res://scenes/main_hybrid.tscn")
const OUT := "res://shots/"

var player: CharacterBody3D


func _ready() -> void:
	var world := MAIN.instantiate()
	add_child(world)
	await get_tree().process_frame
	player = world.get_node("Player")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	await _wait(40)
	Input.action_press("move_forward")
	await _wait(45)

	var root: Node3D = player.get_node("CharacterRotationRoot")
	var travel := Vector3(player.velocity.x, 0, player.velocity.z).normalized()
	var root_pos_z := root.global_transform.basis.z
	root_pos_z.y = 0
	root_pos_z = root_pos_z.normalized()

	print("")
	print("=== facing ===")
	print("  travel dir        : (%.2f, %.2f)" % [travel.x, travel.z])
	print("  rotation root +Z  : (%.2f, %.2f)" % [root_pos_z.x, root_pos_z.z])
	print("  dot(+Z, travel)   : %+.2f" % root_pos_z.dot(travel))
	print("")
	print("  A glTF mesh faces -Z. Model forward is therefore %s travel." % [
		"AGAINST" if root_pos_z.dot(travel) > 0.5 else "WITH"])
	print("  -> mesh needs a 180 yaw: %s" % ("YES" if root_pos_z.dot(travel) > 0.5 else "no"))

	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + "facing.png")
	Input.action_release("move_forward")
	print("")
	get_tree().quit(0)


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
