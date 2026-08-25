extends Node3D
## The level 4 win: a cutscene that never leaves the game.
##
## Nothing here cuts, loads or fades to black. The tree stays unpaused, the
## arena keeps rendering, and the only thing that changes is who owns the
## camera. By the time the results panel appears, the frame behind it is the
## frame the game was already drawing — which is the whole reason it reads as
## seamless rather than as a screen that opened.
##
## Beats, in order:
##
##   0.0  input off, every survivor drops where it stands
##   0.4  a new camera takes over from the player's rig, matching its exact
##        pose so the handover is invisible
##   0.4  it pulls out and begins a slow orbit
##   1.2  the robot turns to face the camera's resting side and poses
##   ~6.5 the orbit eases to a stop and Game.finish_outro() shows the results

## Total length of the camera move.
@export var duration := 6.5
## How far round the robot the camera travels, in turns.
@export var sweep := 0.62
@export var start_radius := 5.0
@export var end_radius := 7.6
@export var start_height := 2.1
@export var end_height := 3.4

var player: Node3D

var _cam: Camera3D
var _from := Transform3D.IDENTITY
var _angle0 := 0.0
var _t := 0.0
var _running := false
var _light: OmniLight3D


func begin(p: Node3D) -> void:
	if _running:
		return
	player = p
	_running = true
	_t = 0.0

	# Every creature still standing goes down. Not killed — laid down: no meat,
	# no quota, no dissolve. A field that unmakes itself leaves the hero alone
	# in an empty circle by the time the camera gets there, and the shot wants
	# bodies in it.
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.has_method("lay_down"):
			e.lay_down()

	if player == null:
		return
	if "grabbed" in player:
		player.grabbed = true          # freezes input, not physics
	if "charge" in player and player.charge > 0.0 and player.has_method("_clear_charge"):
		player._clear_charge()

	var old := _find_active_camera()
	_cam = Camera3D.new()
	add_child(_cam)
	if old != null:
		# Start exactly where the gameplay camera was. Any discrepancy here is
		# a visible jump cut on the handover frame.
		_cam.global_transform = old.global_transform
		_cam.fov = old.fov
		_from = old.global_transform
	else:
		_from = _cam.global_transform
	_cam.current = true

	var to_cam := _from.origin - _pivot()
	_angle0 = atan2(to_cam.x, to_cam.z)

	# A warm key light on the robot, so it is lit for the shot rather than
	# whatever the nearest campfire happened to be doing.
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.86, 0.55)
	_light.light_energy = 0.0
	_light.omni_range = 14.0
	_light.shadow_enabled = false
	add_child(_light)

	Sfx.play_at(&"heal", _pivot(), 2.0)


func _process(delta: float) -> void:
	if not _running or not is_instance_valid(player):
		return
	_t += delta
	var raw := clampf(_t / duration, 0.0, 1.0)
	# Ease out, hard. The orbit should be quick at the start and almost stopped
	# by the end, so the shot settles instead of being cut off mid-move.
	var e := 1.0 - pow(1.0 - raw, 3.0)

	var pivot := _pivot()
	var ang := _angle0 + TAU * sweep * e
	var rad: float = lerpf(start_radius, end_radius, e)
	var hgt: float = lerpf(start_height, end_height, e)

	var pos := pivot + Vector3(sin(ang) * rad, hgt, cos(ang) * rad)
	# Blend out of the gameplay camera's exact pose over the first half second
	# rather than snapping onto the orbit.
	var blend := clampf(_t / 0.45, 0.0, 1.0)
	_cam.global_position = _from.origin.lerp(pos, blend)
	_cam.look_at(pivot + Vector3.UP * 0.35, Vector3.UP)

	_light.global_position = pivot + Vector3(sin(ang) * 3.0, 3.2, cos(ang) * 3.0)
	_light.light_energy = 5.0 * blend

	# Turn the robot to face the camera's resting position and hold the pose.
	if _t > 1.2:
		var face := pivot - pos
		face.y = 0.0
		if face.length() > 0.01:
			var want := atan2(face.x, face.z)
			var root: Node3D = player.get_node_or_null("CharacterRotationRoot")
			if root != null:
				root.rotation.y = lerp_angle(root.rotation.y, want, delta * 2.4)
		if player.has_method("pose_victory"):
			player.pose_victory()

	if raw >= 1.0:
		_running = false
		Game.finish_outro()


func _pivot() -> Vector3:
	return player.global_position + Vector3.UP * 1.1


func _find_active_camera() -> Camera3D:
	var vp := get_viewport()
	return vp.get_camera_3d() if vp != null else null
