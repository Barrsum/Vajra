extends Node
## Loads the prop lab and screenshots it. Exists because I shipped the lab
## once with a parse error and told the user it was open — a scene that
## launches is not the same as a scene that renders.

func _ready() -> void:
	await get_tree().process_frame
	var packed: PackedScene = load("res://scenes/prop_lab.tscn")
	if packed == null:
		print("FAILED to load prop_lab.tscn")
		get_tree().quit(1)
		return
	var lab: Node = packed.instantiate()
	get_tree().root.add_child(lab)
	for i in 40:
		await get_tree().process_frame
	var n := 0
	for c in lab.get_children():
		if c is MeshInstance3D or c is Label3D:
			n += 1
	print("prop lab built: %d visible nodes, %d props laid out"
		% [n, lab._items.size()])
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://shots/prop_lab.png")
		print("wrote shots/prop_lab.png")
	get_tree().quit(0 if lab._items.size() > 0 else 1)
