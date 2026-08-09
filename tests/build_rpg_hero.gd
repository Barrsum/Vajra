extends Node
## Builds the hero animation set from the RPG pack's consolidated Unarmed.glb.
##
## Chosen over UAL because it ships a real combat vocabulary: a genuine 3-hit
## combo (AttackL1/L2/L3, 0.83s each), four-directional dodges and rolls, four
## -directional hit reactions, block and block-break. Same rig as its own mesh,
## so nothing needs retargeting.
##
## Run: godot --headless --path . res://tests/build_rpg_hero.tscn

const DIR := "res://assets/quaternius/RPG_Animations_GLB_FREE-0.1.0-2/"
const SRC := DIR + "Unarmed.glb"
const SRC_RM := DIR + "Unarmed_RM.glb"
const LIB_OUT := DIR + "hero_anims.res"
const TREE_OUT := DIR + "hero_tree.tres"

# clip -> [source, loop, speed]
const MAP := {
	# Alert idle, not the relaxed one — he is in a fight.
	"idle": ["UnarmedIdleAlert1", true, 1.0],
	"walk": ["UnarmedStrafeForward", true, 1.0],
	"run": ["UnarmedRunForward", true, 1.0],
	"sprint": ["UnarmedSprint", true, 1.0],
	"jump": ["UnarmedJump", false, 1.0],
	"fall": ["UnarmedFall", true, 1.0],
	"land": ["UnarmedLand", false, 1.0],
	"dodge": ["UnarmedRollForward", false, 1.0],
	# A real authored 3-hit chain. Left, right, left — alternating like a combo
	# should, rather than three unrelated swings.
	"attack1": ["UnarmedAttackR1", false, 1.0],
	"attack2": ["UnarmedAttackL2", false, 1.0],
	"attack3": ["UnarmedAttackR3", false, 0.85],
	"hit": ["UnarmedGetHitF1", false, 1.0],
	"death": ["UnarmedDeath1", false, 1.0],
}

const LOCOMOTION := ["walk", "run", "sprint"]
var _speeds := {"walk": 1.6, "run": 4.5, "sprint": 7.5}


func _ready() -> void:
	print("")
	print("=== building hero from RPG pack ===")

	var rm := _player(SRC_RM)
	if rm:
		for clip in LOCOMOTION:
			var src: String = MAP[clip][0]
			if rm.has_animation(src):
				var a := rm.get_animation(src)
				var d := _drift(a)
				if d > 0.05 and a.length > 0.0:
					_speeds[clip] = d / a.length
		print("  measured speeds: walk %.2f  run %.2f  sprint %.2f" % [
			_speeds["walk"], _speeds["run"], _speeds["sprint"]])

	var ap := _player(SRC)
	if ap == null:
		print("  FAILED to load %s" % SRC)
		get_tree().quit(1)
		return

	var available := ap.get_animation_list()
	var lib := AnimationLibrary.new()
	print("")
	for clip in MAP:
		var src: String = MAP[clip][0]
		if not ap.has_animation(src):
			print("  MISSING %-24s -> '%s'" % [src, clip])
			# Fall back to the closest name so the build never breaks entirely.
			var alt := _closest(available, src)
			if alt == "":
				continue
			src = alt
			print("           using '%s' instead" % alt)
		var anim: Animation = ap.get_animation(src).duplicate(true)
		anim.loop_mode = Animation.LOOP_LINEAR if MAP[clip][1] else Animation.LOOP_NONE
		_time_scale(anim, MAP[clip][2])
		lib.add_animation(clip, anim)
		print("  %-8s <- %-24s %5.2fs loop=%s" % [clip, src, anim.length, MAP[clip][1]])

	var e1 := ResourceSaver.save(lib, LIB_OUT)
	print("  library -> %s  %s" % [LIB_OUT, "ok" if e1 == OK else "FAILED"])

	var sm := AnimationNodeStateMachine.new()
	var bs := AnimationNodeBlendSpace1D.new()
	bs.min_space = 0.0
	bs.max_space = _speeds["sprint"]
	bs.add_blend_point(_clip("idle"), 0.0, -1, "idle")
	bs.add_blend_point(_clip("walk"), _speeds["walk"], -1, "walk")
	bs.add_blend_point(_clip("run"), _speeds["run"], -1, "run")
	bs.add_blend_point(_clip("sprint"), _speeds["sprint"], -1, "sprint")
	sm.add_node("locomotion", bs, Vector2(340, 40))

	var states := ["jump", "fall", "land", "dodge", "attack1", "attack2", "attack3", "hit", "death"]
	var x := 60
	var y := 220
	for s in states:
		sm.add_node(s, _clip(s), Vector2(x, y))
		x += 210
		if x > 900:
			x = 60
			y += 120

	sm.add_transition("Start", "locomotion", _t(0.0))
	var all := states.duplicate()
	all.append("locomotion")
	var n := 0
	for from in all:
		if from == "death":
			continue
		for to in all:
			if from != to:
				# Attacks blend fast so the chain reads as one motion.
				sm.add_transition(from, to, _t(0.07 if to.begins_with("attack") else 0.13))
				n += 1
	print("  transitions: %d" % n)

	var e2 := ResourceSaver.save(sm, TREE_OUT)
	print("  tree    -> %s  %s" % [TREE_OUT, "ok" if e2 == OK else "FAILED"])
	print("")
	get_tree().quit(0 if e1 == OK and e2 == OK else 1)


func _closest(list: PackedStringArray, wanted: String) -> String:
	for a in list:
		if a.to_lower().contains(wanted.to_lower().replace("unarmed", "")):
			return a
	return ""


func _player(path: String) -> AnimationPlayer:
	if not ResourceLoader.exists(path):
		return null
	var scene: Node = (load(path) as PackedScene).instantiate()
	add_child(scene)
	return _find(scene, "AnimationPlayer") as AnimationPlayer


func _drift(anim: Animation) -> float:
	for i in anim.get_track_count():
		if anim.track_get_type(i) != Animation.TYPE_POSITION_3D:
			continue
		var p := String(anim.track_get_path(i))
		if not (p.ends_with("Motion") or p.ends_with("B_Pelvis")):
			continue
		var n := anim.track_get_key_count(i)
		if n < 2:
			continue
		var a: Vector3 = anim.track_get_key_value(i, 0)
		var b: Vector3 = anim.track_get_key_value(i, n - 1)
		var d := Vector2(b.x - a.x, b.z - a.z).length()
		# This pack's root track is authored in centimetres while the mesh
		# imports in metres, so raw drift comes out ~100x too large.
		if d > 50.0:
			d *= 0.01
		if d > 0.05:
			return d
	return 0.0


func _time_scale(anim: Animation, speed: float) -> void:
	if is_equal_approx(speed, 1.0):
		return
	var inv := 1.0 / speed
	# Lengthening moves keys later, so walk backwards or a key overtakes the one
	# after it and Godot rejects the write.
	for i in anim.get_track_count():
		var n := anim.track_get_key_count(i)
		if inv > 1.0:
			for k in range(n - 1, -1, -1):
				anim.track_set_key_time(i, k, anim.track_get_key_time(i, k) * inv)
		else:
			for k in n:
				anim.track_set_key_time(i, k, anim.track_get_key_time(i, k) * inv)
	anim.length *= inv


func _clip(name: String) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = name
	return a


func _t(xfade: float) -> AnimationNodeStateMachineTransition:
	var t := AnimationNodeStateMachineTransition.new()
	t.xfade_time = xfade
	t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
	t.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
	return t


func _find(n: Node, cls: String) -> Node:
	if n.get_class() == cls:
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null
