extends Node
func _ready() -> void:
	var lib: AnimationLibrary = load("res://assets/enemy/enemy_anims.res")
	var l := lib.get_animation_list()
	print("")
	print("enemy library: %d clips" % l.size())
	for a in l:
		print("   %-12s %.2fs  loop=%s" % [a, lib.get_animation(a).length, lib.get_animation(a).loop_mode != 0])
	print("")
	get_tree().quit(0)
