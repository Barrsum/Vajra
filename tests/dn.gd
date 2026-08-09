extends Node
const UAL := "res://assets/quaternius/Universal_Animation_LibraryStandard/Universal Animation Library[Standard]/Unreal-Godot/UAL1_Standard.glb"
func _ready() -> void:
	var s: Node = (load(UAL) as PackedScene).instantiate()
	_t(s, 0)
	var ap := _f(s, "AnimationPlayer") as AnimationPlayer
	if ap:
		var a := ap.get_animation("Idle")
		print("  Idle track0 path: %s" % a.track_get_path(0))
	get_tree().quit(0)
func _t(n: Node, d: int) -> void:
	print("  %s%s (%s)" % ["  ".repeat(d), n.name, n.get_class()])
	for c in n.get_children(): _t(c, d + 1)
func _f(n: Node, c: String) -> Node:
	if n.get_class() == c: return n
	for k in n.get_children():
		var r := _f(k, c)
		if r: return r
	return null
