extends Node
## Builds the player animation library and state machine from Quaternius' UAL
## (CC0). One rig, one animator, one coherent set — which is the actual fix for
## the jankiness. Our previous clips were unrelated Mixamo downloads whose start
## and end poses were never designed to meet.
##
## Blend-space speeds are measured from the _RM (root motion) build and applied
## to the in-place clips, so stride matches travel exactly.
##
## Run: godot --headless --path . res://tests/build_ual.tscn

const DIR := "res://assets/quaternius/Universal_Animation_LibraryStandard/Universal Animation Library[Standard]/Unreal-Godot/"
const SRC := DIR + "UAL1_Standard.glb"
const SRC_RM := DIR + "UAL1_Standard_RM.glb"
const LIB_OUT := "res://assets/quaternius/hero_anims.res"
const TREE_OUT := "res://assets/quaternius/hero_tree.tres"

# clip -> [source animation, loop, speed]
const MAP := {
	"idle": ["Idle", true, 1.0],
	"walk": ["Walk", true, 1.0],
	"run": ["Jog_Fwd", true, 1.0],
	"sprint": ["Sprint", true, 1.0],
	"jump": ["Jump_Start", false, 1.0],
	"fall": ["Jump", true, 1.0],
	"land": ["Jump_Land", false, 1.4],
	"dodge": ["Roll", false, 1.5],
	# Three different authored attacks from one set, so they chain cleanly.
	"attack1": ["Punch_Jab", false, 1.15],
	"attack2": ["Punch_Cross", false, 1.15],
	"attack3": ["Sword_Attack", false, 1.35],
	"hit": ["Hit_Chest", false, 1.0],
	"death": ["Death01", false, 1.0],
}

const LOCOMOTION := ["walk", "run", "sprint"]

var _speeds := {"walk": 1.5, "run": 4.0, "sprint": 7.5}


func _ready() -> void:
	print("")
	print("=== building hero animations from UAL (CC0) ===")

	var rm := _player(SRC_RM)
	if rm:
		for clip in LOCOMOTION:
			var src: String = MAP[clip][0]
			if rm.has_animation(src):
				var a := rm.get_animation(src)
				var d := _drift(a)
				if d > 0.05 and a.length > 0.0:
					_speeds[clip] = d / a.length
		print("  measured from root-motion build:")
		for k in LOCOMOTION:
			print("    %-7s %.2f m/s" % [k, _speeds[k]])

	var ap := _player(SRC)
	if ap == null:
		print("  FAILED to load %s" % SRC)
		get_tree().quit(1)
		return

	var lib := AnimationLibrary.new()
	print("")
	for clip in MAP:
		var src: String = MAP[clip][0]
		if not ap.has_animation(src):
			print("  MISSING  %s (wanted for '%s')" % [src, clip])
			continue
		var anim: Animation = ap.get_animation(src).duplicate(true)
		var loop: bool = MAP[clip][1]
		var speed: float = MAP[clip][2]
		anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
		_time_scale(anim, speed)
		lib.add_animation(clip, anim)
		print("  %-8s <- %-16s %5.2fs (x%.2f) loop=%s" % [clip, src, anim.length, speed, loop])

	var e1 := ResourceSaver.save(lib, LIB_OUT)
	print("  library -> %s  %s" % [LIB_OUT, "ok" if e1 == OK else "FAILED"])

	# --- state machine ---
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
				sm.add_transition(from, to, _t(0.10 if to.begins_with("attack") else 0.14))
				n += 1
	print("  transitions: %d" % n)

	var e2 := ResourceSaver.save(sm, TREE_OUT)
	print("  tree    -> %s  %s" % [TREE_OUT, "ok" if e2 == OK else "FAILED"])
	print("")
	get_tree().quit(0 if e1 == OK and e2 == OK else 1)


func _player(path: String) -> AnimationPlayer:
	if not ResourceLoader.exists(path):
		return null
	var scene: Node = (load(path) as PackedScene).instantiate()
	add_child(scene)
	return _find(scene, "AnimationPlayer") as AnimationPlayer


## Horizontal distance the hips travel over a root-motion clip.
func _drift(anim: Animation) -> float:
	for i in anim.get_track_count():
		if anim.track_get_type(i) != Animation.TYPE_POSITION_3D:
			continue
		var p := String(anim.track_get_path(i))
		if not (p.ends_with("root") or p.ends_with("pelvis")):
			continue
		var n := anim.track_get_key_count(i)
		if n < 2:
			continue
		var a: Vector3 = anim.track_get_key_value(i, 0)
		var b: Vector3 = anim.track_get_key_value(i, n - 1)
		var d := Vector2(b.x - a.x, b.z - a.z).length()
		if d > 0.05:
			return d
	return 0.0


func _time_scale(anim: Animation, speed: float) -> void:
	if is_equal_approx(speed, 1.0):
		return
	var inv := 1.0 / speed
	for i in anim.get_track_count():
		for k in anim.track_get_key_count(i):
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
