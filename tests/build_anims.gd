extends Node
## Turns 12 separate Mixamo FBX files into one AnimationLibrary with sane clip
## names, correct loop flags, and root motion stripped.
##
## Mixamo bakes forward travel into locomotion clips unless "In Place" is ticked.
## The CharacterBody3D already drives movement, so that translation has to go or
## the character skates away from where the code thinks he is. Vertical motion is
## kept — that's the body bob, and losing it makes everything look glued down.
##
## Run: godot --headless --path . res://tests/build_anims.tscn

const SRC := "res://assets/character/anims/"
const OUT := "res://assets/character/player_anims.res"

# file stem -> [clip name, should loop, playback speed]
#
# Speed matters more than it looks. Mixamo's melee clips run 1.3–3.5s, which is
# far too slow to feel like a combo, and Hard Landing holds for a full 2s. The
# locomotion clips are left at 1.0 and instead placed in the blend space at the
# speed they were authored for — that is what stops the feet sliding.
const MAP := {
	"Breathing Idle": ["idle", true, 1.0],
	"Walking": ["walk", true, 1.0],
	"Running": ["run", true, 1.0],
	"Jumping Up": ["jump", false, 1.3],
	"Falling Idle": ["fall", true, 1.0],
	"Hard Landing": ["land", false, 2.6],
	"Standing Dodge Forward": ["dodge", false, 2.2],
	"Great Sword Slash-1": ["attack1", false, 2.4],
	"Great Sword Slash-2": ["attack2", false, 1.7],
	"Great Sword Slash-3": ["attack3", false, 1.4],
	"Standing React Small From Front": ["hit", false, 1.6],
	"Falling Back Death": ["death", false, 1.0],
}

## Speed the Running clip up to cover the sprint end of the blend space.
const SPRINT_FROM := "run"
const SPRINT_SPEED := 1.55


func _ready() -> void:
	print("")
	print("=== building animation library ===")

	var lib := AnimationLibrary.new()
	var built := 0

	for stem in MAP:
		var path: String = SRC + String(stem) + ".fbx"
		if not ResourceLoader.exists(path):
			print("  MISSING  %s" % path)
			continue

		var scene: Node = (load(path) as PackedScene).instantiate()
		var ap := _find_player(scene)
		if ap == null or not ap.has_animation("mixamo_com"):
			print("  NO ANIM  %s" % stem)
			scene.free()
			continue

		var anim: Animation = ap.get_animation("mixamo_com").duplicate(true)
		var clip_name: String = MAP[stem][0]
		var should_loop: bool = MAP[stem][1]

		var speed: float = MAP[stem][2]

		anim.loop_mode = Animation.LOOP_LINEAR if should_loop else Animation.LOOP_NONE
		var drift := _strip_root_motion(anim)
		_time_scale(anim, speed)

		lib.add_animation(clip_name, anim)
		built += 1
		print("  %-9s <- %-32s %5.2fs (x%.1f) loop=%-5s rootmotion=%.2fm" % [
			clip_name, String(stem), anim.length, speed, should_loop, drift,
		])
		scene.free()

	# Sprint is the run clip played faster, so the far end of the blend space
	# has a clip whose stride actually matches 8.4 m/s.
	if lib.has_animation(SPRINT_FROM):
		var sprint: Animation = lib.get_animation(SPRINT_FROM).duplicate(true)
		_time_scale(sprint, SPRINT_SPEED)
		sprint.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation("sprint", sprint)
		built += 1
		print("  %-9s <- %-32s %5.2fs (x%.1f) loop=true" % [
			"sprint", SPRINT_FROM + " (time-scaled)", sprint.length, SPRINT_SPEED,
		])

	var err := ResourceSaver.save(lib, OUT)
	print("")
	if err == OK:
		print("  saved %d clips -> %s" % [built, OUT])
	else:
		print("  SAVE FAILED (%d)" % err)

	print("")
	get_tree().quit(0 if err == OK else 1)


## Flattens horizontal translation on the hips, returning how much was removed.
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


## Rescales every keyframe time so the clip plays `speed`x faster.
func _time_scale(anim: Animation, speed: float) -> void:
	if is_equal_approx(speed, 1.0):
		return
	var inv := 1.0 / speed
	for i in anim.get_track_count():
		for k in anim.track_get_key_count(i):
			anim.track_set_key_time(i, k, anim.track_get_key_time(i, k) * inv)
	anim.length *= inv


func _find_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_player(c)
		if r:
			return r
	return null
