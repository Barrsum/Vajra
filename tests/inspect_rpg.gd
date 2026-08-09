extends Node
## Checks whether the RPG animation pack's rig matches the Quaternius rig.
## If the bone names line up, its 67 clips play on the Quaternius character
## directly and no retargeting is needed.

const RPG_DIR := "res://assets/quaternius/RPG_Animations_GLB_FREE-0.1.0-2/"
const UAL := "res://assets/quaternius/Universal_Animation_LibraryStandard/Universal Animation Library[Standard]/Unreal-Godot/UAL1_Standard.glb"


func _ready() -> void:
	print("")
	var ual := _bones(UAL)
	print("UAL rig      : %d bones" % ual.size())

	var rpg := _bones(RPG_DIR + "RPG-Character-Bones.FBX")
	print("RPG rig      : %d bones" % rpg.size())
	if rpg.is_empty():
		print("  (bones file not imported; trying an animation file)")
		rpg = _bones(RPG_DIR + "Unarmed/RPG-Character@Unarmed-Idle.FBX")
		print("RPG anim rig : %d bones" % rpg.size())

	if ual.is_empty() or rpg.is_empty():
		print("could not read one of the rigs")
		get_tree().quit(1)
		return

	var shared := 0
	for b in rpg:
		if b in ual:
			shared += 1
	print("")
	print("shared bone names: %d of %d RPG bones" % [shared, rpg.size()])
	print("match: %.0f%%" % (float(shared) / float(rpg.size()) * 100.0))
	print("")
	print("RPG first 12 : %s" % ", ".join(rpg.slice(0, 12)))
	print("UAL first 12 : %s" % ", ".join(ual.slice(0, 12)))
	print("")
	if shared > rpg.size() * 0.8:
		print(">>> COMPATIBLE - clips will play on the UAL character directly")
	else:
		print(">>> DIFFERENT RIGS - retargeting required")
	print("")
	get_tree().quit(0)


func _bones(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not ResourceLoader.exists(path):
		return out
	var res := load(path)
	if res == null or not (res is PackedScene):
		return out
	var scene: Node = (res as PackedScene).instantiate()
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
