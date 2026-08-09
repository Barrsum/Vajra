extends Node
## Dumps both rigs' full bone lists so a retarget map can be written accurately.

const RPG := "res://assets/quaternius/RPG_Animations_GLB_FREE-0.1.0-2/Unarmed.glb"
const UAL := "res://assets/quaternius/Universal_Animation_LibraryStandard/Universal Animation Library[Standard]/Unreal-Godot/UAL1_Standard.glb"


func _ready() -> void:
	print("")
	print("RPG:")
	for b in _bones(RPG):
		print("  " + b)
	print("")
	print("UAL:")
	for b in _bones(UAL):
		print("  " + b)
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


func _find(n: Node, cls: String) -> Node:
	if n.get_class() == cls:
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null
