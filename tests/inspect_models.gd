extends Node
## Scans assets/character/ for imported 3D files and reports everything that
## usually goes wrong with a Mixamo import: wrong scale, missing skeleton,
## animations landing in the wrong place, model facing backwards.
##
## Run: godot --headless --path . res://tests/inspect_models.tscn

const DIR := "res://assets/"
const MODEL_EXTS := ["glb", "gltf", "fbx", "dae", "blend"]


func _ready() -> void:
	print("")
	print("=== character asset report ===")

	var files := _find_models(DIR)
	if files.is_empty():
		print("  nothing found in %s" % DIR)
		print("  (drop the Mixamo .fbx files there, then let Godot import them)")
		get_tree().quit(0)
		return

	for path in files:
		_report(path)

	print("")
	get_tree().quit(0)


func _find_models(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if d.current_is_dir():
			if not name.begins_with("."):
				out.append_array(_find_models(full))
		elif name.get_extension().to_lower() in MODEL_EXTS:
			out.append(full)
		name = d.get_next()
	d.list_dir_end()
	return out


func _report(path: String) -> void:
	print("")
	print("-- %s" % path)

	var res := load(path)
	if res == null:
		print("   FAILED to load. Godot has probably not imported it yet — open the")
		print("   editor once so the import runs, then re-run this.")
		return
	if not (res is PackedScene):
		print("   loaded, but not a PackedScene (got %s)" % res.get_class())
		return

	var root: Node = (res as PackedScene).instantiate()
	add_child(root)

	var skels: Array[Node] = []
	var meshes: Array[Node] = []
	var players: Array[Node] = []
	_collect(root, skels, meshes, players)

	# --- skeleton ---
	if skels.is_empty():
		print("   skeleton : NONE  <- not a rigged character")
	else:
		for s in skels:
			print("   skeleton : %s  (%d bones)" % [s.name, (s as Skeleton3D).get_bone_count()])
			var names := PackedStringArray()
			for i in mini(6, (s as Skeleton3D).get_bone_count()):
				names.append((s as Skeleton3D).get_bone_name(i))
			print("              first bones: %s" % ", ".join(names))

	# --- meshes and real-world size ---
	if meshes.is_empty():
		print("   mesh     : NONE  <- animation-only file, which is correct for anim clips")
	else:
		var aabb := AABB()
		var first := true
		for m in meshes:
			var mi := m as MeshInstance3D
			if mi.mesh == null:
				continue
			var box := mi.global_transform * mi.mesh.get_aabb()
			if first:
				aabb = box
				first = false
			else:
				aabb = aabb.merge(box)
		print("   mesh     : %d surface node(s)" % meshes.size())
		print("   height   : %.2f m   %s" % [
			aabb.size.y,
			_height_verdict(aabb.size.y),
		])

	# --- animations ---
	if players.is_empty():
		print("   anims    : no AnimationPlayer")
	else:
		for p in players:
			var ap := p as AnimationPlayer
			var list := ap.get_animation_list()
			print("   anims    : %d in '%s'" % [list.size(), ap.name])
			for a in list:
				var anim := ap.get_animation(a)
				print("              %-28s %.2fs  loop=%s" % [a, anim.length, anim.loop_mode != 0])

	root.queue_free()


func _height_verdict(h: float) -> String:
	if h > 20.0:
		return "<- TOO BIG. Set Root Scale to 0.01 in the Import tab."
	if h < 0.3:
		return "<- TOO SMALL. Root Scale is probably 0.01 when it should be 1."
	if h >= 1.4 and h <= 2.3:
		return "<- good, human scale"
	return "<- unusual for a humanoid, check Root Scale"


func _collect(n: Node, skels: Array[Node], meshes: Array[Node], players: Array[Node]) -> void:
	if n is Skeleton3D:
		skels.append(n)
	elif n is MeshInstance3D:
		meshes.append(n)
	elif n is AnimationPlayer:
		players.append(n)
	for c in n.get_children():
		_collect(c, skels, meshes, players)
