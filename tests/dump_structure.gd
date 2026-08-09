extends Node
## Prints the node tree of the character and the animation track paths, so the
## AnimationPlayer can be pointed at a root where those paths actually resolve.

func _ready() -> void:
	print("")
	print("=== ybot node tree ===")
	var ybot: Node = load("res://assets/character/ybot.fbx").instantiate()
	_tree(ybot, 0)

	print("")
	print("=== sample animation tracks (Walking) ===")
	var walk: Node = load("res://assets/character/anims/Walking.fbx").instantiate()
	add_child(walk)
	var ap := _find_player(walk)
	if ap:
		var anim := ap.get_animation("mixamo_com")
		print("  root_node on source player: %s" % ap.root_node)
		print("  track count: %d" % anim.get_track_count())
		var hips_pos := -1
		for i in mini(6, anim.get_track_count()):
			print("   [%d] type=%d  path=%s" % [i, anim.track_get_type(i), anim.track_get_path(i)])
		# Locate the hips position track and measure drift, which reveals whether
		# "In Place" was ticked on Mixamo.
		for i in anim.get_track_count():
			if anim.track_get_type(i) == Animation.TYPE_POSITION_3D \
			and String(anim.track_get_path(i)).ends_with("Hips"):
				hips_pos = i
				break
		if hips_pos >= 0:
			var n := anim.track_get_key_count(hips_pos)
			var first: Vector3 = anim.track_get_key_value(hips_pos, 0)
			var last: Vector3 = anim.track_get_key_value(hips_pos, n - 1)
			var drift := Vector2(last.x - first.x, last.z - first.z).length()
			print("  hips drift over clip: %.3f m  -> %s" % [
				drift,
				"IN PLACE (good)" if drift < 0.05 else "HAS ROOT MOTION (will need stripping)",
			])
		else:
			print("  no hips position track found")

	print("")
	get_tree().quit(0)


func _tree(n: Node, depth: int) -> void:
	var extra := ""
	if n is Skeleton3D:
		extra = "  [%d bones]" % (n as Skeleton3D).get_bone_count()
	elif n is MeshInstance3D:
		extra = "  [mesh]"
	elif n is AnimationPlayer:
		extra = "  [anims: %s]" % ", ".join((n as AnimationPlayer).get_animation_list())
	print("  %s%s (%s)%s" % ["  ".repeat(depth), n.name, n.get_class(), extra])
	for c in n.get_children():
		_tree(c, depth + 1)


func _find_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_player(c)
		if r:
			return r
	return null
