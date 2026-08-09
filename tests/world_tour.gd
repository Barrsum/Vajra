extends Node
## Captures every world in the run so the themes can be compared side by side.

const OUT := "res://shots/"


func _ready() -> void:
	await get_tree().process_frame
	var decoy := Node.new()
	get_tree().root.add_child(decoy)
	get_tree().current_scene = decoy
	await _wait(20)

	print("")
	print("=== world tour ===")
	Game.start_run()
	await _wait(120)

	for i in Game.worlds.size():
		var w: Resource = Game.current_world()
		# Nudge the camera down the arena so the shot shows the space, not a wall.
		var p := get_tree().current_scene.get_node_or_null("Player")
		if p:
			var cam := p.get_node_or_null("CameraController")
			if cam:
				cam._euler_rotation.y = PI * 0.25
		await _wait(60)
		await _shot("world-%d-%s" % [i + 1, w.display_name.to_lower().replace(" ", "-")])
		print("  %d  %-22s theme=%d  %s x%d  enemies %d" % [
			i + 1, w.display_name, w.theme, w.ingredient, w.ingredient_needed,
			get_tree().get_nodes_in_group("enemies").size()])
		if i < Game.worlds.size() - 1:
			Game.world_index = i + 1
			Game.retry_world()
			await _wait(120)

	print("")
	get_tree().quit(0)


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + name + ".png")
