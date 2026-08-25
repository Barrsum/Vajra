extends Node
## Reports what a generated .glb actually contains, so a prop's real cost is
## known before twenty of them go into a level.
##
##   godot --headless --path . res://tests/inspect_glb.tscn

const DIR := "res://assets/props/"


func _ready() -> void:
	await get_tree().process_frame
	print("")
	print("=== generated props ===")
	var d := DirAccess.open(DIR)
	if d == null:
		print("  no props folder")
		get_tree().quit(0)
		return
	for f in d.get_files():
		if not f.ends_with(".glb"):
			continue
		var packed: PackedScene = load(DIR + f)
		if packed == null:
			print("  %-24s FAILED TO LOAD" % f)
			continue
		var root: Node = packed.instantiate()
		var tris := 0
		var surfaces := 0
		var meshes := 0
		var tex_mb := 0.0
		var aabb := AABB()
		var seen := {}
		for mi in _all_meshes(root):
			meshes += 1
			var m: Mesh = mi.mesh
			aabb = aabb.merge(mi.get_aabb()) if meshes > 1 else mi.get_aabb()
			for s in m.get_surface_count():
				surfaces += 1
				var arr := m.surface_get_arrays(s)
				var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
				tris += (idx.size() / 3) if idx.size() > 0 else \
					(arr[Mesh.ARRAY_VERTEX].size() / 3)
				var mat := m.surface_get_material(s)
				if mat is BaseMaterial3D:
					for slot in [BaseMaterial3D.TEXTURE_ALBEDO,
							BaseMaterial3D.TEXTURE_NORMAL,
							BaseMaterial3D.TEXTURE_ROUGHNESS,
							BaseMaterial3D.TEXTURE_METALLIC]:
						var t: Texture2D = (mat as BaseMaterial3D).get_texture(slot)
						if t != null and not seen.has(t.get_rid()):
							seen[t.get_rid()] = true
							tex_mb += float(t.get_width() * t.get_height() * 4) / 1048576.0
		print("  %s" % f)
		print("    %d triangles, %d surfaces, %d mesh nodes" % [tris, surfaces, meshes])
		print("    size %.2f x %.2f x %.2f m" % [aabb.size.x, aabb.size.y, aabb.size.z])
		print("    textures ~%.1f MB in VRAM" % tex_mb)
		root.free()
	print("")
	get_tree().quit(0)


func _all_meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_meshes(c))
	return out
