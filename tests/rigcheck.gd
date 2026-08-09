extends Node
## Confirms each creature can play the shared enemy animation set.
const DIR := "res://assets/enemy/"
func _ready() -> void:
	var lib: AnimationLibrary = load(DIR + "enemy_anims.res")
	var wanted := {}
	for a in lib.get_animation_list():
		var anim := lib.get_animation(a)
		for i in anim.get_track_count():
			var p := String(anim.track_get_path(i))
			if p.contains(":"):
				wanted[p.get_slice(":", 1)] = true
	print("")
	print("animation set targets %d distinct bones" % wanted.size())
	var d := DirAccess.open(DIR)
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.to_lower().ends_with(".fbx"):
			var sc: Node = (load(DIR + f) as PackedScene).instantiate()
			var sk := _f(sc, "Skeleton3D") as Skeleton3D
			var have := {}
			var h := 0.0
			if sk:
				for i in sk.get_bone_count():
					have[sk.get_bone_name(i)] = true
			for m in _meshes(sc):
				h = maxf(h, (m as MeshInstance3D).mesh.get_aabb().size.y)
			var miss := 0
			for b in wanted:
				if not have.has(b):
					miss += 1
			print("  %-34s %3d bones  %5.2fm  missing %d/%d" % [f, have.size(), h, miss, wanted.size()])
			sc.free()
		f = d.get_next()
	print("")
	get_tree().quit(0)
func _meshes(n: Node) -> Array:
	var o := []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh: o.append(n)
	for c in n.get_children(): o.append_array(_meshes(c))
	return o
func _f(n: Node, c: String) -> Node:
	if n.get_class() == c: return n
	for k in n.get_children():
		var r := _f(k, c)
		if r: return r
	return null
