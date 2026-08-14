extends Node
## Builds the enemy animation library and state machine.
##
## No idle clip was downloaded for the Mutant, so it borrows the player's
## Breathing Idle. Both rigs use Mixamo's bone naming, but the Mutant has 37
## bones to Y Bot's 65 (no fingers) — so tracks targeting bones the Mutant does
## not have are dropped. That is retargeting in miniature, and it is the reason
## sticking to one skeleton family keeps paying off.
##
## Run: godot --headless --path . res://tests/build_enemy.tscn

const SRC := "res://assets/enemy/anims/"
const MODEL := "res://assets/enemy/Mutant.fbx"
const IDLE_DONOR := "res://assets/character/anims/Breathing Idle.fbx"
const LIB_OUT := "res://assets/enemy/enemy_anims.res"
const TREE_OUT := "res://assets/enemy/enemy_tree.tres"

# stem -> [clip, loop, speed]
#
# One coherent set per creature. Mixing a zombie shamble with a mutant punch and
# a human idle on the *same* body gave the creature three different body
# languages at once — which reads as "wrong" long before you can point at any
# single clip. So the clips are grouped into categories, and a creature draws a
# whole set from within one category rather than one clip at a time.
const MAP := {
	"Mutant Breathing Idle": ["idle", true, 1.0],
	"Mutant Walking": ["walk", true, 1.0],
	"Mutant Run": ["run", true, 1.0],
	# The roar runs 5.4s raw — far longer than any wind-up you'd want to stand
	# through. Compressed to about a second so the whole beat lands.
	"Mutant Roaring": ["telegraph", false, 5.0],
	"Mutant Punch": ["attack1", false, 1.3],
	"Mutant Swiping": ["attack2", false, 3.0],
	"Standing React Large From Front": ["hit", false, 1.5],
	"Mutant Dying": ["death", false, 1.5],

	# Creature-specific clips. They live in the same library and the same state
	# machine; the enemy simply travels to a different state name. One tree for
	# every creature is far less fragile than a tree per creature.
	"Pumpkinhulk Walking": ["pk_walk", true, 1.0],
	"Standing Melee Attack Backhand": ["pk_attack1", false, 1.15],
	"Standing Melee Attack Downward": ["pk_attack2", false, 1.15],
	# Set-piece only: the limp and the swing that throws the player.
	"Injured Walk": ["injured", true, 1.0],
	"Baseball Hit": ["baseball", false, 1.0],

	# --- variant pool -------------------------------------------------------
	# Skeleton and Warrok shipped without animations of their own, so they roll
	# a set from here at spawn. Speeds are tuned to land near the clip each one
	# stands in for, because the combo windows come from the archetype table,
	# not from clip length — an attack that plays at half the speed of its
	# timing window looks like it whiffed.
	# Zombie Walk is authored as a 4s shamble covering 1.3m — a 0.32 m/s stride.
	# Left alone its blend point sits so low that a charging enemy is past it
	# before the clip is ever visible, and the variant may as well not exist.
	"Zombie Walk": ["walk_z", true, 2.2],
	"Monster walk 3": ["walk_m3", true, 1.0],
	"Monster walk 4": ["walk_m4", true, 1.0],
	# Both raw clips run well over 2s. Damage lands on the archetype's strike
	# window (~0.26s in), so a long clip is barely underway when the hit
	# registers. Compressed to sit alongside the Mutant's 0.85s punch.
	"Zombie Attack": ["attack_z", false, 2.0],
	"Mutant Jump Attack": ["attack_jump", false, 2.5],
	"Mutant Flexing Muscles": ["telegraph_flex", false, 4.2],
	"Standing React Large From Left": ["hit_l", false, 1.5],
	"Zombie Death": ["death_z", false, 1.35],
}

## One-shot states. Every one of these becomes a node in the state machine that
## an enemy can travel to by name.
const STATES := ["telegraph", "attack1", "attack2", "hit", "death",
	"pk_attack1", "pk_attack2", "injured", "baseball",
	"attack_z", "attack_jump", "telegraph_flex", "hit_l", "death_z"]

## Deaths are terminal — nothing transitions out of them.
const TERMINAL := ["death", "death_z"]

## Blend-space name -> the walk clip it is built around. Every locomotion space
## shares the same idle and run; only the middle point changes, so a creature
## that shambles still sprints when it has to.
const LOCOS := {
	"locomotion": "walk",
	"locomotion_pk": "pk_walk",
	"locomotion_z": "walk_z",
	"locomotion_m3": "walk_m3",
	"locomotion_m4": "walk_m4",
}

## Blend points are measured from each clip's own root motion, so the stride
## matches the speed it plays at. clip -> metres per second, as authored.
var stride := {}
var run_speed := 3.4


func _ready() -> void:
	print("")
	print("=== building enemy ===")

	var bones := _bone_set(MODEL)
	print("  target rig: %d bones" % bones.size())

	var lib := AnimationLibrary.new()

	for stem in MAP:
		var path: String = SRC + String(stem) + ".fbx"
		if not ResourceLoader.exists(path):
			print("  MISSING  %s" % path)
			continue
		var anim := _extract(path)
		if anim == null:
			continue

		var clip: String = MAP[stem][0]
		var loop: bool = MAP[stem][1]
		var speed: float = MAP[stem][2]

		anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
		var drift := _strip_root_motion(anim)
		if anim.length > 0.0 and drift > 0.05:
			# Measured before the time scale, then corrected by it — playing a
			# clip faster covers the same ground in less time.
			stride[clip] = (drift / anim.length) * speed
			if clip == "run":
				run_speed = stride[clip]
		_time_scale(anim, speed)
		_filter_tracks(anim, bones)

		lib.add_animation(clip, anim)
		print("  %-8s <- %-32s %5.2fs (x%.2f) rootmotion=%.2fm" % [
			clip, String(stem), anim.length, speed, drift,
		])

	# Fallback only. Now that a real Mutant idle exists this is skipped — but it
	# stays as the pattern for any future creature that ships without one.
	var idle := _extract(IDLE_DONOR) if not lib.has_animation("idle") else null
	if idle:
		idle.loop_mode = Animation.LOOP_LINEAR
		_strip_root_motion(idle)
		var removed := _filter_tracks(idle, bones)
		lib.add_animation("idle", idle)
		print("  %-8s <- %-32s %5.2fs (borrowed, %d tracks dropped)" % [
			"idle", "player Breathing Idle", idle.length, removed,
		])

	var e1 := ResourceSaver.save(lib, LIB_OUT)
	print("  library -> %s  %s" % [LIB_OUT, "ok" if e1 == OK else "FAILED"])

	# --- state machine ---
	var sm := AnimationNodeStateMachine.new()

	# One blend space per walk clip. Each is built around that clip's own
	# measured stride, which is the whole reason feet do not slide: the walk
	# point sits at exactly the speed the animator authored it for.
	var by := 40
	var locos: Array[String] = []
	for loco in LOCOS:
		var walk_clip: String = LOCOS[loco]
		if not lib.has_animation(walk_clip):
			print("  SKIP  %s (no %s)" % [loco, walk_clip])
			continue
		var w: float = maxf(float(stride.get(walk_clip, 1.2)), 0.4)
		var top: float = maxf(run_speed, w + 0.5)
		var bs := AnimationNodeBlendSpace1D.new()
		bs.min_space = 0.0
		bs.max_space = top
		bs.add_blend_point(_clip("idle"), 0.0, -1, "idle")
		bs.add_blend_point(_clip(walk_clip), w, -1, walk_clip)
		bs.add_blend_point(_clip("run"), top, -1, "run")
		sm.add_node(loco, bs, Vector2(320, by))
		locos.append(loco)
		by += 90
		print("  %-14s idle@0.0  %-8s@%.2f  run@%.2f" % [loco, walk_clip, w, top])

	var x := 60
	var y := by + 60
	var states: Array[String] = []
	for s in STATES:
		if not lib.has_animation(s):
			print("  SKIP  state %s (clip missing)" % s)
			continue
		sm.add_node(s, _clip(s), Vector2(x, y))
		states.append(s)
		x += 220
		if x > 900:
			x = 60
			y += 120

	sm.add_transition("Start", "locomotion", _t(0.0))
	var all: Array[String] = states.duplicate()
	all.append_array(locos)
	var n := 0
	for from in all:
		if from in TERMINAL:
			continue
		for to in all:
			if from != to:
				sm.add_transition(from, to, _t(0.12))
				n += 1
	print("  %d states, %d transitions" % [all.size(), n])

	var e2 := ResourceSaver.save(sm, TREE_OUT)
	print("  tree    -> %s  %s" % [TREE_OUT, "ok" if e2 == OK else "FAILED"])
	print("")
	get_tree().quit(0 if e1 == OK and e2 == OK else 1)


func _bone_set(model_path: String) -> Dictionary:
	var out := {}
	var scene: Node = (load(model_path) as PackedScene).instantiate()
	var skel := _find(scene, "Skeleton3D") as Skeleton3D
	if skel:
		for i in skel.get_bone_count():
			out[skel.get_bone_name(i)] = true
	scene.free()
	return out


func _extract(path: String) -> Animation:
	var scene: Node = (load(path) as PackedScene).instantiate()
	var ap := _find(scene, "AnimationPlayer") as AnimationPlayer
	var out: Animation = null
	if ap and ap.has_animation("mixamo_com"):
		out = ap.get_animation("mixamo_com").duplicate(true)
	scene.free()
	return out


## Drops tracks aimed at bones this rig does not have. Returns how many.
func _filter_tracks(anim: Animation, bones: Dictionary) -> int:
	var removed := 0
	for i in range(anim.get_track_count() - 1, -1, -1):
		var p := String(anim.track_get_path(i))
		if not p.contains(":"):
			continue
		var bone := p.get_slice(":", 1)
		if bone != "" and not bones.has(bone):
			anim.remove_track(i)
			removed += 1
	return removed


func _strip_root_motion(anim: Animation) -> float:
	for i in anim.get_track_count():
		if anim.track_get_type(i) != Animation.TYPE_POSITION_3D:
			continue
		if not String(anim.track_get_path(i)).ends_with("Hips"):
			continue
		var n := anim.track_get_key_count(i)
		if n == 0:
			return 0.0
		var first: Vector3 = anim.track_get_key_value(i, 0)
		var last: Vector3 = anim.track_get_key_value(i, n - 1)
		var drift := Vector2(last.x - first.x, last.z - first.z).length()
		for k in n:
			var v: Vector3 = anim.track_get_key_value(i, k)
			anim.track_set_key_value(i, k, Vector3(first.x, v.y, first.z))
		return drift
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
	var n := AnimationNodeAnimation.new()
	n.animation = name
	return n


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
