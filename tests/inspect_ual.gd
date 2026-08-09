extends Node
## Reports what the Quaternius Universal Animation Library actually contains:
## rig size, mesh presence, and every clip with its length.

const UAL := "res://assets/quaternius/Universal_Animation_LibraryStandard/Universal Animation Library[Standard]/Unreal-Godot/UAL1_Standard.glb"


func _ready() -> void:
	print("")
	print("=== UAL1_Standard.glb ===")
	if not ResourceLoader.exists(UAL):
		print("  NOT IMPORTED at %s" % UAL)
		get_tree().quit(1)
		return

	var scene: Node = (load(UAL) as PackedScene).instantiate()
	add_child(scene)

	var skel := _find(scene, "Skeleton3D") as Skeleton3D
	if skel:
		print("  rig: %d bones" % skel.get_bone_count())
		var names := PackedStringArray()
		for i in mini(10, skel.get_bone_count()):
			names.append(skel.get_bone_name(i))
		print("  bones: %s" % ", ".join(names))

	var meshes: Array[Node] = []
	_collect_meshes(scene, meshes)
	print("  meshes: %d" % meshes.size())
	if meshes.size() > 0:
		var aabb := (meshes[0] as MeshInstance3D).mesh.get_aabb()
		print("  height: %.2f m" % aabb.size.y)

	var ap := _find(scene, "AnimationPlayer") as AnimationPlayer
	if ap:
		var list := ap.get_animation_list()
		print("  animations: %d" % list.size())
		print("")
		for a in list:
			print("    %-34s %.2fs" % [a, ap.get_animation(a).length])

	scene.queue_free()
	print("")
	get_tree().quit(0)


func _collect_meshes(n: Node, out: Array[Node]) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		_collect_meshes(c, out)


func _find(n: Node, cls: String) -> Node:
	if n.get_class() == cls:
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null
