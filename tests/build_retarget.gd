extends Node
## Retargets the RPG pack's combat animations onto the Quaternius UAL character.
##
## Gets us both halves: UAL's good mesh, RPG's real combat vocabulary (an
## authored 3-hit chain, four-directional dodges and rolls, hit reactions).
##
## Renaming tracks alone is NOT enough. Godot stores bone rotations relative to
## each bone's rest pose, so if the two rigs rest differently the same numbers
## mean different poses. The fix is to take the source's delta from its own rest
## and re-apply it to the target's rest:
##
##     delta      = src_rest.inverse() * src_key
##     target_key = dst_rest * delta
##
## Run: godot --headless --path . res://tests/build_retarget.tscn

const RPG := "res://assets/quaternius/RPG_Animations_GLB_FREE-0.1.0-2/Unarmed.glb"
const RPG_RM := "res://assets/quaternius/RPG_Animations_GLB_FREE-0.1.0-2/Unarmed_RM.glb"
const UAL := "res://assets/quaternius/Universal_Animation_LibraryStandard/Universal Animation Library[Standard]/Unreal-Godot/UAL1_Standard.glb"
const LIB_OUT := "res://assets/quaternius/retargeted_anims.res"
const TREE_OUT := "res://assets/quaternius/retargeted_tree.tres"

const BONES := {
	"Motion": "root", "B_Pelvis": "pelvis",
	"B_Spine": "spine_01", "B_Spine1": "spine_02", "B_Spine2": "spine_03",
	"B_Neck": "neck_01", "B_Head": "Head",
	"B_L_Clavicle": "clavicle_l", "B_L_UpperArm": "upperarm_l",
	"B_L_Forearm": "lowerarm_l", "B_L_Hand": "hand_l",
	"B_R_Clavicle": "clavicle_r", "B_R_UpperArm": "upperarm_r",
	"B_R_Forearm": "lowerarm_r", "B_R_Hand": "hand_r",
	"B_L_Thigh": "thigh_l", "B_L_Calf": "calf_l", "B_L_Foot": "foot_l", "B_L_Toe0": "ball_l",
	"B_R_Thigh": "thigh_r", "B_R_Calf": "calf_r", "B_R_Foot": "foot_r", "B_R_Toe0": "ball_r",
}

const MAP := {
	"idle": ["UnarmedIdleAlert1", true, 1.0],
	"walk": ["UnarmedStrafeForward", true, 1.0],
	"run": ["UnarmedRunForward", true, 1.0],
	"sprint": ["UnarmedSprint", true, 1.0],
	"jump": ["UnarmedJump", false, 1.0],
	"fall": ["UnarmedFall", true, 1.0],
	"land": ["UnarmedLand", false, 1.0],
	"dodge": ["UnarmedRollForward", false, 1.0],
	"attack1": ["UnarmedAttackR1", false, 1.0],
	"attack2": ["UnarmedAttackL2", false, 1.0],
	"attack3": ["UnarmedAttackR3", false, 0.85],
	"hit": ["UnarmedGetHitF1", false, 1.0],
	"death": ["UnarmedDeath1", false, 1.0],
}

const LOCOMOTION := ["walk", "run", "sprint"]

var _src_rest := {}   # bone name -> Transform3D
var _dst_rest := {}
## Node path prefix the TARGET rig's own tracks use, e.g. "Armature/Skeleton3D".
## Assuming plain "Skeleton3D" silently produces a T-pose, because the tracks
## resolve to nothing and the skeleton simply stays at rest.
var _dst_prefix := "Skeleton3D"
var _speeds := {"walk": 3.0, "run": 5.9, "sprint": 9.4}


func _ready() -> void:
	print("")
	print("=== retargeting RPG combat set onto UAL character ===")

	_src_rest = _rest(RPG)
	_dst_rest = _rest(UAL)
	print("  source rig %d bones, target rig %d bones" % [_src_rest.size(), _dst_rest.size()])

	_dst_prefix = _track_prefix(UAL)
	print("  target track prefix: '%s'" % _dst_prefix)

	var mapped := 0
	for b in BONES:
		if _src_rest.has(b) and _dst_rest.has(BONES[b]):
			mapped += 1
	print("  mapped %d / %d core bones" % [mapped, BONES.size()])
	if mapped < BONES.size():
		print("  WARNING: some mapped bones missing on one side")

	var rm := _player(RPG_RM)
	if rm:
		for clip in LOCOMOTION:
			var src: String = MAP[clip][0]
			if rm.has_animation(src):
				var a := rm.get_animation(src)
				var d := _drift(a)
				if d > 0.05 and a.length > 0.0:
					_speeds[clip] = d / a.length
		print("  speeds: walk %.2f  run %.2f  sprint %.2f" % [
			_speeds["walk"], _speeds["run"], _speeds["sprint"]])

	var ap := _player(RPG)
	if ap == null:
		print("  FAILED to load source")
		get_tree().quit(1)
		return

	var lib := AnimationLibrary.new()
	print("")
	for clip in MAP:
		var src: String = MAP[clip][0]
		if not ap.has_animation(src):
			print("  MISSING %s" % src)
			continue
		var anim: Animation = ap.get_animation(src).duplicate(true)
		var kept := _retarget(anim)
		anim.loop_mode = Animation.LOOP_LINEAR if MAP[clip][1] else Animation.LOOP_NONE
		_time_scale(anim, MAP[clip][2])
		lib.add_animation(clip, anim)
		print("  %-8s <- %-22s %5.2fs  %d tracks" % [clip, src, anim.length, kept])

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
				sm.add_transition(from, to, _t(0.07 if to.begins_with("attack") else 0.13))
				n += 1

	var e2 := ResourceSaver.save(sm, TREE_OUT)
	print("  tree    -> %s  %s  (%d transitions)" % [TREE_OUT, "ok" if e2 == OK else "FAILED", n])
	print("")
	get_tree().quit(0 if e1 == OK and e2 == OK else 1)


## Rewrites every track onto the target rig, rebasing rotations through rest
## poses. Tracks aimed at unmapped bones (fingers, leaves) are dropped.
func _retarget(anim: Animation) -> int:
	var pelvis_scale := 1.0
	if _src_rest.has("B_Pelvis") and _dst_rest.has("pelvis"):
		var sy: float = (_src_rest["B_Pelvis"] as Transform3D).origin.y
		var dy: float = (_dst_rest["pelvis"] as Transform3D).origin.y
		if absf(sy) > 0.0001:
			pelvis_scale = dy / sy

	for i in range(anim.get_track_count() - 1, -1, -1):
		var path := String(anim.track_get_path(i))
		if not path.contains(":"):
			anim.remove_track(i)
			continue
		var bone := path.get_slice(":", 1)
		if not BONES.has(bone):
			anim.remove_track(i)
			continue

		var dst: String = BONES[bone]
		anim.track_set_path(i, NodePath(_dst_prefix + ":" + dst))

		var t := anim.track_get_type(i)
		if t == Animation.TYPE_ROTATION_3D:
			var s_rest: Quaternion = (_src_rest[bone] as Transform3D).basis.get_rotation_quaternion()
			var d_rest: Quaternion = (_dst_rest[dst] as Transform3D).basis.get_rotation_quaternion()
			var s_inv := s_rest.inverse()
			for k in anim.track_get_key_count(i):
				var q: Quaternion = anim.track_get_key_value(i, k)
				anim.track_set_key_value(i, k, d_rest * (s_inv * q))
		elif t == Animation.TYPE_POSITION_3D:
			# Only the pelvis carries useful translation; rescale it to the
			# target rig's proportions and drop the rest.
			if dst != "pelvis":
				anim.remove_track(i)
				continue
			for k in anim.track_get_key_count(i):
				var p: Vector3 = anim.track_get_key_value(i, k)
				anim.track_set_key_value(i, k, p * pelvis_scale)
		elif t == Animation.TYPE_SCALE_3D:
			anim.remove_track(i)

	return anim.get_track_count()


## Reads the node path a rig's own animation tracks use, so retargeted tracks
## address the skeleton exactly the way its native clips do.
func _track_prefix(path: String) -> String:
	var scene: Node = (load(path) as PackedScene).instantiate()
	var ap := _find(scene, "AnimationPlayer") as AnimationPlayer
	var out := "Skeleton3D"
	if ap:
		var list := ap.get_animation_list()
		if list.size() > 0:
			var a := ap.get_animation(list[0])
			for i in a.get_track_count():
				var p := String(a.track_get_path(i))
				if p.contains(":"):
					out = p.get_slice(":", 0)
					break
	scene.free()
	return out


func _rest(path: String) -> Dictionary:
	var out := {}
	var scene: Node = (load(path) as PackedScene).instantiate()
	var skel := _find(scene, "Skeleton3D") as Skeleton3D
	if skel:
		for i in skel.get_bone_count():
			out[skel.get_bone_name(i)] = skel.get_bone_rest(i)
	scene.free()
	return out


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
		if d > 50.0:
			d *= 0.01
		if d > 0.05:
			return d
	return 0.0


func _time_scale(anim: Animation, speed: float) -> void:
	if is_equal_approx(speed, 1.0):
		return
	var inv := 1.0 / speed
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
