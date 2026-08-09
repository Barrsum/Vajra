extends Node
## Walks the whole run flow without a human: menu -> world 1 -> quota met ->
## next world -> pause -> resume -> death -> menu. Captures a frame at each stop.
##
## Run: godot --path . --resolution 1280x720 res://tests/flow_test.tscn

const OUT := "res://shots/"
var failures := 0


func _ready() -> void:
	# change_scene_to_file frees whatever the tree considers the current scene.
	# This node IS that, so it must step aside first or it deletes itself the
	# moment the run starts — which reads as a hang, not an error.
	await get_tree().process_frame
	var decoy := Node.new()
	get_tree().root.add_child(decoy)
	get_tree().current_scene = decoy

	await _wait(20)
	print("")
	print("=== run flow ===")

	get_tree().change_scene_to_file(Game.MENU_SCENE)
	await _wait(40)
	await _shot("ui-01-menu")
	_check("menu state", Game.state == Game.State.MENU)

	Game.start_run()
	await _wait(90)
	await _shot("ui-02-world1")
	_check("playing", Game.state == Game.State.PLAYING)
	_check("world 0", Game.world_index == 0)
	_check("quota reset", Game.collected == 0)

	# Fill the quota the way kills would.
	var need := Game.needed()
	for i in need:
		Game.add_drop(1)
	await _wait(20)
	await _shot("ui-03-world-clear")
	_check("world clear", Game.state == Game.State.WORLD_CLEAR)
	_check("tree paused", get_tree().paused)

	Game.next_world()
	await _wait(90)
	await _shot("ui-04-world2")
	_check("world 1", Game.world_index == 1)
	_check("playing again", Game.state == Game.State.PLAYING)
	_check("unpaused", not get_tree().paused)

	Game.toggle_pause()
	await _wait(20)
	await _shot("ui-05-paused")
	_check("paused", Game.state == Game.State.PAUSED and get_tree().paused)
	Game.toggle_pause()
	await _wait(20)
	_check("resumed", Game.state == Game.State.PLAYING and not get_tree().paused)

	Game.player_died()
	await _wait(20)
	await _shot("ui-06-dead")
	_check("dead", Game.state == Game.State.DEAD)

	# Straight to the last world and finish it, to reach victory.
	Game.world_index = Game.worlds.size() - 1
	Game.retry_world()
	await _wait(90)
	for i in Game.needed():
		Game.add_drop(1)
	await _wait(20)
	await _shot("ui-07-victory")
	_check("victory", Game.state == Game.State.VICTORY)

	Game.to_menu()
	await _wait(50)
	_check("back to menu", Game.state == Game.State.MENU)

	print("")
	print("  %s" % ("ALL PASS" if failures == 0 else "%d FAILURE(S)" % failures))
	print("")
	get_tree().quit(1 if failures > 0 else 0)


func _check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
	print("  %-18s %s" % [label, "PASS" if ok else "FAIL"])


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + name + ".png")
