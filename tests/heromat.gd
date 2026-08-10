extends Node
const M := "res://assets/quaternius/RPG_Animations_GLB_FREE-0.1.0-2/Unarmed.glb"
func _ready() -> void:
	var sc: Node = (load(M) as PackedScene).instantiate()
	print("")
	for mi in _meshes(sc):
		var m := mi as MeshInstance3D
		print("  mesh '%s' surfaces=%d" % [m.name, m.mesh.get_surface_count()])
		for i in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(i)
			if mat is StandardMaterial3D:
				var sm := mat as StandardMaterial3D
				print("    surf%d albedo=%s texture=%s" % [i, sm.albedo_color,
					"YES" if sm.albedo_texture else "none"])
			else:
				print("    surf%d %s" % [i, mat])
	print("")
	get_tree().quit(0)
func _meshes(n: Node) -> Array:
	var o := []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh: o.append(n)
	for c in n.get_children(): o.append_array(_meshes(c))
	return o
