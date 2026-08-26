extends RefCounted
## Lets a CharacterBody3D walk over small obstacles instead of stopping dead.
##
## Godot's CharacterBody3D has no step handling. move_and_slide treats a
## two-centimetre lip exactly like a wall, which on generated ground — where
## every patch has stones moulded into it — means the robot catches on scenery
## constantly. It is the single worst thing about walking around a dressed
## level.
##
## The fix is the standard three-probe climb, run only when movement was
## actually blocked:
##
##   1. can the body rise by max_step without hitting anything?
##   2. from up there, can it move the way it wanted to?
##   3. is there something to stand on when it drops back down?
##
## All three must pass. Step three is what separates a step from a ledge:
## without it the body would happily climb into mid-air and float.
##
## No class_name: registration has silently failed under --headless in this
## project. Callers preload it.

## How far the probe drops looking for ground, beyond the height it rose.
const OVERSHOOT := 0.08
## Below this the horizontal probe counts as "did not get anywhere", and the
## obstacle is a wall rather than a step.
const MIN_PROGRESS := 0.25


## Returns true if the body was moved up onto a step.
##
## `motion` is the horizontal distance the body wanted to travel this frame.
static func climb(body: CharacterBody3D, motion: Vector3,
		max_step: float) -> bool:
	motion.y = 0.0
	if motion.length_squared() < 1e-8 or max_step <= 0.0:
		return false

	var rid := body.get_rid()
	var params := PhysicsTestMotionParameters3D.new()
	# Recovery would let the probe resolve overlaps and report progress it did
	# not really make, which reads as climbing through walls.
	params.recovery_as_collision = true
	var res := PhysicsTestMotionResult3D.new()

	# 1. Rise. If something is directly overhead, rise as far as it allows.
	params.from = body.global_transform
	params.motion = Vector3.UP * max_step
	var rise := max_step
	if PhysicsServer3D.body_test_motion(rid, params, res):
		rise = maxf(res.get_travel().y, 0.0)
		if rise < 0.03:
			return false        # no headroom: this is a wall, not a step

	var raised := body.global_transform
	raised.origin += Vector3.UP * rise

	# 2. Move the way we wanted to, from up there.
	params.from = raised
	params.motion = motion
	PhysicsServer3D.body_test_motion(rid, params, res)
	var across: Vector3 = res.get_travel()
	across.y = 0.0
	if across.length() < motion.length() * MIN_PROGRESS:
		return false            # still blocked at head height: a real wall

	# 3. Drop back down. Something has to be under us, or this was a ledge
	# and the body would end up standing on air.
	var over := raised
	over.origin += across
	params.from = over
	params.motion = Vector3.DOWN * (rise + OVERSHOOT)
	if not PhysicsServer3D.body_test_motion(rid, params, res):
		return false

	body.global_position = over.origin + res.get_travel()
	return true
