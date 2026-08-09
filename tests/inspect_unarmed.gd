extends Node
## Inspects the RPG pack's consolidated Unarmed.glb — 67 clips in one file.
## Reports rig, mesh, and how its bone names line up with the UAL rig.

const RPG := "res://assets/quaternius/RPG_Animations_GLB_FREE-0.1.0-2/Unarmed.glb"
const UAL := "res://assets/quaternius/Universal_Animation_LibraryStandard/Universal Animation Library[Standard]/Unreal-Godot/UAL1_Standard.glb"


func _ready() -> void:
	print("")
	var ual := _bones(UAL)
	var rpg := _bones(RPG)
	print("UAL bones : %d" % ual.size())
	print("RPG bones : %d" % rpg.size())

	var scene: Node = (load(RPG) as PackedScene).instantiate()
	add_child(scene)
	var meshes: Array[Node] = []
	_meshes(scene, meshes)
	print("RPG meshes: %d" % meshes.size())

	var ap := _find(scene, "AnimationPlayer") as AnimationPlayer
	if ap:
		var list := ap.get_animation_list()
		print("RPG clips : %d" % list.size())
		print("")
		print("attack / dodge / combat clips:")
		for a in list:
			var low := a.to_lower()
			if low.contains("attack") or low.contains("dodge") or low.contains("roll") \
			or low.contains("block") or low.contains("jump") or low.contains("land") \
			or low.contains("gethit") or low.contains("death") or low.contains("idle") \
			or low.contains("sprint") or a.to_lower().contains("walk"):
				print("    %-46s %.2fs" % [a, ap.get_animation(a).length])

	print("")
	print("RPG rig: %s" % ", ".join(rpg.slice(0, 14)))
	print("")
	get_tree().quit(0)


func _bones(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not ResourceLoader.exists(path):
		return out
	var scene: Node = (load(path) as PackedScene).instantiate()
	var skel := _find(scene, "Skeleton3D") as Skeleton3D
	if skel:
		for i in skel.get_bone_count():
			out.append(skel.get_bone_name(i))
	scene.free()
	return out


func _meshes(n: Node, out: Array[Node]) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		_meshes(c, out)


func _find(n: Node, cls: String) -> Node:
	if n.get_class() == cls:
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null
