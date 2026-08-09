extends Node
## Captures GDQuest's controller running in our street, for side-by-side
## comparison against our own. Their move actions are move_up/move_down, not
## move_forward/move_back — that difference is why both sets now exist.

const SCENE := preload("res://scenes/compare_gdquest.tscn")
const OUT := "res://shots/"


func _ready() -> void:
	add_child(SCENE.instantiate())
	await get_tree().process_frame
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	await _wait(50)
	await _shot("gd-01-idle")

	Input.action_press("move_up")
	await _wait(50)
	await _shot("gd-02-running")

	Input.action_press("jump")
	await _wait(16)
	await _shot("gd-03-jump")
	Input.action_release("jump")

	await _wait(30)
	Input.action_release("move_up")

	Input.action_press("attack")
	await _wait(10)
	await _shot("gd-04-melee")
	Input.action_release("attack")

	print("")
	get_tree().quit(0)


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + name + ".png")
	print("  " + name)
