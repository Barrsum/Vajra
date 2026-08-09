extends CharacterBody3D
## Third-person character controller.
##
## Movement tuning is carried over verbatim from the browser prototype, where it
## was already proven to feel right. Direction is derived from the camera's own
## basis vectors rather than hand-written sin/cos — that is precisely where the
## reversed-strafe bug came from last time, and basis vectors cannot get it wrong.

# --- movement ---------------------------------------------------------------
@export_group("Movement")
@export var walk_speed := 4.6
@export var sprint_speed := 8.4
@export var acceleration := 42.0
@export var deceleration := 34.0
@export var turn_speed := 14.0

@export_group("Air")
@export var jump_velocity := 7.0
@export var gravity := 20.0
@export var fall_multiplier := 1.45   ## heavier on the way down; a floaty arc reads as weightless
@export var coyote_time := 0.12       ## grace window to still jump just after walking off an edge
@export var jump_buffer := 0.14       ## pressing jump slightly early still fires on landing

@export_group("Dodge")
@export var dodge_speed := 16.5
@export var dodge_time := 0.40
@export var dodge_iframes := 0.28     ## deliberately shorter than the dodge — the gap is the skill
@export var dodge_cooldown := 0.52

@export_group("Camera")
@export var mouse_sensitivity := 0.0022
@export var pitch_min := -0.85
@export var pitch_max := 0.60
@export var base_fov := 62.0

@export_group("Combat")
@export var attack_move_scale := 0.22   ## how much steering survives mid-swing
@export var attack_cancel_at := 0.62    ## fraction of the clip after which the next hit can chain
@export var max_health := 100.0
@export var target_assist_angle := 1.15 ## radians; swings snap onto a target inside this cone

## Per-hit definitions. `active` is the window during the clip when the hitbox is
## live, as a fraction of clip length — that is what couples the damage to the
## visible swing instead of to the button press.
const ATTACKS := [
	{"active": Vector2(0.20, 0.48), "damage": 22.0, "reach": 3.0, "arc": 2.1,
	 "knock": 3.5, "stop": 0.055, "shake": 0.35, "lunge": 2.6},
	{"active": Vector2(0.18, 0.44), "damage": 26.0, "reach": 3.0, "arc": 2.2,
	 "knock": 4.5, "stop": 0.065, "shake": 0.42, "lunge": 3.0},
	{"active": Vector2(0.24, 0.52), "damage": 44.0, "reach": 3.4, "arc": 2.8,
	 "knock": 11.0, "stop": 0.11, "shake": 0.9, "lunge": 3.6},
]

@export_group("Arm blade")
## Bone the blade grows from. The forearm — not the hand — so it reads as the
## arm becoming a weapon rather than the character holding one.
@export var blade_bone := "mixamorig_RightForeArm"
@export var blade_offset := Vector3(0.0, 0.22, 0.0)
@export var blade_rotation := Vector3(0.0, 0.0, 0.0)
@export var blade_length := 1.05
@export var blade_width := 0.17
@export var blade_thickness := 0.045

@export_group("Model")
## Rotate the mesh if it faces the wrong way. Mixamo rigs face +Z; if he runs
## backwards, set this to 180.
@export_range(-180, 180, 1) var model_yaw_offset := 0.0

# --- nodes ------------------------------------------------------------------
@onready var visual: Node3D = $Visual
@onready var model: Node3D = $Visual/Model
@onready var anim_player: AnimationPlayer = $Visual/AnimationPlayer
@onready var anim_tree: AnimationTree = $Visual/AnimationTree
@onready var cam_root: Node3D = $CamRoot
@onready var spring: SpringArm3D = $CamRoot/SpringArm3D
@onready var camera: Camera3D = $CamRoot/SpringArm3D/Camera3D

var _sm: AnimationNodeStateMachinePlayback
var _anim_state := ""
var _land_timer := 0.0
var _attack_index := 0
var _attack_timer := 0.0
var _attack_len := 0.0
var _attack_buffered := false
var _swing_hit: Array = []       ## enemies already struck by the current swing
var _swing_done := false

var health := 0.0
var alive := true

var _trauma := 0.0               ## camera shake, decays every frame
var _hitstop_until_ms := 0

var _blade_root: Node3D
var _blade_scale := 0.0          ## animates 0 -> 1 so the blade grows, not pops

# --- state ------------------------------------------------------------------
var yaw := 0.0
var pitch := -0.24

var _dodging := false
var _dodge_t := 0.0
var _dodge_cd := 0.0
var _dodge_dir := Vector3.ZERO

var _invuln := 0.0
var _coyote := 0.0
var _buffered_jump := 0.0
var _was_on_floor := true

## Planar speed, exposed so the camera and future animation tree can read it.
var planar_speed := 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera.fov = base_fov
	model.rotation.y = deg_to_rad(model_yaw_offset)
	_sm = anim_tree.get("parameters/playback")
	health = max_health
	_build_blade()


## Grows a blade off the forearm bone via BoneAttachment3D. Built in code rather
## than in the scene because the model is an instanced .fbx, whose skeleton we
## cannot add children to without making the whole instance editable.
func _build_blade() -> void:
	var skel := _find_skeleton(model)
	if skel == null:
		push_warning("no Skeleton3D under Model; arm blade skipped")
		return
	if skel.find_bone(blade_bone) == -1:
		push_warning("bone '%s' not found; arm blade skipped" % blade_bone)
		return

	var att := BoneAttachment3D.new()
	att.bone_name = blade_bone
	skel.add_child(att)

	_blade_root = Node3D.new()
	_blade_root.position = blade_offset
	_blade_root.rotation = blade_rotation
	att.add_child(_blade_root)

	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.78, 0.83, 0.88)
	steel.metallic = 0.85
	steel.roughness = 0.22
	steel.emission_enabled = true
	steel.emission = Color(0.45, 0.72, 1.0)
	steel.emission_energy_multiplier = 0.35

	# Two tapered slabs: a long body and a point. Cheap, and in motion it reads
	# as a blade rather than as boxes.
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(blade_thickness, blade_length, blade_width)
	body.mesh = bm
	body.material_override = steel
	body.position = Vector3(0, blade_length * 0.5, 0)
	_blade_root.add_child(body)

	var tip := MeshInstance3D.new()
	var tm := PrismMesh.new()
	tm.size = Vector3(blade_thickness, 0.42, blade_width)
	tip.mesh = tm
	tip.material_override = steel
	tip.position = Vector3(0, blade_length + 0.18, 0)
	_blade_root.add_child(tip)

	# A stub where the blade meets the arm, so it grows out of him rather than
	# floating alongside.
	var root_stub := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.1, 0.28, blade_width * 1.5)
	root_stub.mesh = sm
	root_stub.material_override = steel
	root_stub.position = Vector3(0, 0.02, 0)
	_blade_root.add_child(root_stub)

	_blade_root.scale = Vector3.ZERO


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r:
			return r
	return null


func _process(delta: float) -> void:
	# Hit-stop is measured in wall-clock ms because Engine.time_scale would
	# otherwise slow down the very timer meant to end it.
	if Engine.time_scale < 1.0 and Time.get_ticks_msec() >= _hitstop_until_ms:
		Engine.time_scale = 1.0

	_trauma = maxf(0.0, _trauma - 2.6 * delta)
	var s := _trauma * _trauma * 0.30
	# Shake the frustum, not the node. SpringArm3D positions its child by setting
	# `position`, so writing to camera.position here would cancel the arm and
	# collapse the camera onto the player's head.
	camera.h_offset = randf_range(-s, s)
	camera.v_offset = randf_range(-s, s)

	# Blade snaps out fast when a swing starts, retracts slowly after. That
	# asymmetry is what makes it read as a transformation.
	if _blade_root:
		var want := 1.0 if _attack_index > 0 else 0.0
		var rate := 26.0 if want > _blade_scale else 7.0
		_blade_scale = lerpf(_blade_scale, want, 1.0 - exp(-rate * delta))
		_blade_root.scale = Vector3(1.0, _blade_scale, 1.0) * maxf(_blade_scale, 0.001)
	camera.fov = lerpf(camera.fov, base_fov + clampf(planar_speed - walk_speed, 0.0, 4.0) * 1.6, 6.0 * delta)


func hit_stop(seconds: float) -> void:
	_hitstop_until_ms = maxi(_hitstop_until_ms, Time.get_ticks_msec() + int(seconds * 1000.0))
	Engine.time_scale = 0.05


func add_trauma(amount: float) -> void:
	_trauma = minf(_trauma + amount, 2.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * mouse_sensitivity
		pitch = clampf(pitch - event.relative.y * mouse_sensitivity, pitch_min, pitch_max)

	if event.is_action_pressed("ui_release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	_dodge_cd = maxf(0.0, _dodge_cd - delta)
	_invuln = maxf(0.0, _invuln - delta)
	_buffered_jump = maxf(0.0, _buffered_jump - delta)

	_land_timer = maxf(0.0, _land_timer - delta)
	_attack_timer = maxf(0.0, _attack_timer - delta)
	if _attack_timer <= 0.0:
		_attack_index = 0
		_attack_buffered = false
	else:
		# The hitbox is live only during the swing's active window, so damage is
		# tied to the visible arc rather than to the moment you clicked.
		var def: Dictionary = ATTACKS[_attack_index - 1]
		var progress := 1.0 - (_attack_timer / maxf(_attack_len, 0.001))
		var w: Vector2 = def["active"]
		if progress >= w.x and progress <= w.y:
			_resolve_swing()
		_process_attack_buffer()

	if not alive:
		velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
		if not is_on_floor():
			velocity.y -= gravity * delta
		move_and_slide()
		return

	_update_camera_rig()
	_update_ground_state(delta)

	if Input.is_action_just_pressed("dodge"):
		_try_dodge()
	if Input.is_action_just_pressed("jump"):
		_buffered_jump = jump_buffer
	if Input.is_action_just_pressed("attack"):
		_try_attack()

	if _dodging:
		_process_dodge(delta)
	else:
		_process_walk(delta)

	_process_vertical(delta)
	move_and_slide()

	planar_speed = Vector2(velocity.x, velocity.z).length()
	_face_travel_direction(delta)
	_update_animation()


# ---------------------------------------------------------------------------

func _update_camera_rig() -> void:
	cam_root.rotation.y = yaw
	spring.rotation.x = pitch


func _update_ground_state(delta: float) -> void:
	# Landing is detected on the transition, before velocity.y is zeroed.
	if is_on_floor() and not _was_on_floor and velocity.y < -4.0:
		_land_timer = 0.28
	if is_on_floor():
		_coyote = coyote_time
	else:
		_coyote = maxf(0.0, _coyote - delta)
	_was_on_floor = is_on_floor()


## Camera-relative movement direction. `Input.get_vector` returns +X for right
## and -Y for forward, and the camera basis supplies the world axes, so there is
## no place here for a sign to be flipped by hand.
func _wish_direction() -> Vector3:
	var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if iv == Vector2.ZERO:
		return Vector3.ZERO
	var basis := cam_root.global_transform.basis
	var forward := -basis.z
	var right := basis.x
	forward.y = 0.0
	right.y = 0.0
	return (forward * -iv.y + right * iv.x).normalized()


func _process_walk(delta: float) -> void:
	var wish := _wish_direction()
	var sprinting := Input.is_action_pressed("sprint") and wish != Vector3.ZERO
	var target := wish * (sprint_speed if sprinting else walk_speed)

	# Swinging commits you. Some steering survives so it never feels like cement.
	if _attack_index > 0:
		target *= attack_move_scale

	var rate := acceleration if target != Vector3.ZERO else deceleration
	# Air control is deliberately reduced — commit to your jump arc.
	if not is_on_floor():
		rate *= 0.35

	velocity.x = move_toward(velocity.x, target.x, rate * delta)
	velocity.z = move_toward(velocity.z, target.z, rate * delta)


func _process_vertical(delta: float) -> void:
	if _buffered_jump > 0.0 and _coyote > 0.0 and not _dodging:
		velocity.y = jump_velocity
		_buffered_jump = 0.0
		_coyote = 0.0
		return

	if not is_on_floor():
		# Falling faster than rising gives the arc weight without a bigger gravity.
		var g := gravity * (fall_multiplier if velocity.y < 0.0 else 1.0)
		velocity.y -= g * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0


func _try_dodge() -> void:
	if _dodging or _dodge_cd > 0.0:
		return
	var wish := _wish_direction()
	if wish == Vector3.ZERO:
		# No input: hop backwards, away from whatever is in your face.
		wish = -visual.global_transform.basis.z
		wish.y = 0.0
		wish = wish.normalized()

	_dodging = true
	_dodge_t = 0.0
	_dodge_cd = dodge_cooldown
	_dodge_dir = wish
	_invuln = maxf(_invuln, dodge_iframes)
	_try_dodge_cancel()   # dodging out of a swing is the core defensive option


func _process_dodge(delta: float) -> void:
	_dodge_t += delta
	if _dodge_t >= dodge_time:
		_dodging = false
		return
	# Fast out of the gate, easing to nothing — a flat burst reads as a slide.
	var p := _dodge_t / dodge_time
	var speed := dodge_speed * (1.0 - p * p)
	velocity.x = _dodge_dir.x * speed
	velocity.z = _dodge_dir.z * speed


func _face_travel_direction(delta: float) -> void:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length_squared() < 0.4:
		return
	var want := atan2(flat.x, flat.z)
	visual.rotation.y = lerp_angle(visual.rotation.y, want, 1.0 - exp(-turn_speed * delta))


# --- combat -----------------------------------------------------------------

func _try_attack() -> void:
	if _dodging or not is_on_floor():
		return
	if _attack_index == 0:
		_start_attack(1)
	else:
		# Mid-swing presses are remembered, not thrown away. Discarding them is
		# what made spam-clicking feel random — some clicks landed in the chain
		# window and some vanished. Buffering makes the rhythm consistent.
		_attack_buffered = true


## Fires a buffered press the instant the chain window opens.
func _process_attack_buffer() -> void:
	if _attack_index == 0 or not _attack_buffered:
		return
	if _attack_timer <= _attack_len * (1.0 - attack_cancel_at):
		_attack_buffered = false
		_start_attack(_attack_index + 1)


func _start_attack(n: int) -> void:
	if n > 3:
		n = 1
	_attack_index = n
	var clip := "attack%d" % n
	_attack_len = anim_player.get_animation(clip).length if anim_player.has_animation(clip) else 0.6
	_attack_timer = _attack_len
	_swing_hit.clear()
	_swing_done = false

	# Snap onto a nearby target and lunge in. Without the assist, a cone hitbox
	# against circling enemies means most swings whiff for no readable reason.
	var target := _find_target(ATTACKS[n - 1]["reach"] * 1.8)
	if target:
		var d: Vector3 = target.global_position - global_position
		visual.rotation.y = atan2(d.x, d.z)
	else:
		visual.rotation.y = _facing_yaw_from_camera()

	var fwd := Vector3(sin(visual.rotation.y), 0.0, cos(visual.rotation.y))
	var speed: float = ATTACKS[n - 1]["lunge"]
	if target:
		# Close the gap without sailing past them.
		var gap: float = maxf(0.0, global_position.distance_to(target.global_position) - ATTACKS[n - 1]["reach"] * 0.6)
		speed = minf(speed, gap * 6.0)
	velocity += fwd * speed

	_travel(clip)


## Ground-plane direction the camera is looking. The camera looks along -Z of
## cam_root, so this is NOT (sin yaw, cos yaw) — that is the model's facing
## convention, and the two are 180 degrees apart. Mixing them up made the target
## assist search behind the player.
func _camera_forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


## Model yaw that corresponds to looking where the camera looks.
func _facing_yaw_from_camera() -> float:
	return yaw + PI


func _find_target(range_m: float) -> Node3D:
	var best: Node3D = null
	var best_score := INF
	var aim := _camera_forward()
	# Duck-typed rather than checking against a class_name, so this keeps working
	# regardless of whether the global class cache has been rebuilt.
	for e in get_tree().get_nodes_in_group("enemies"):
		if not e.has_method("is_alive") or not e.is_alive():
			continue
		var d: Vector3 = e.global_position - global_position
		d.y = 0.0
		var dist := d.length()
		if dist > range_m or dist < 0.01:
			continue
		var ang := acos(clampf(d.normalized().dot(aim), -1.0, 1.0))
		if ang > target_assist_angle:
			continue
		var score := dist + ang * 3.5
		if score < best_score:
			best_score = score
			best = e
	return best


## Runs every frame the swing's hitbox is live.
func _resolve_swing() -> void:
	var def: Dictionary = ATTACKS[_attack_index - 1]
	var fwd := Vector3(sin(visual.rotation.y), 0.0, cos(visual.rotation.y))
	var landed := false

	for e in get_tree().get_nodes_in_group("enemies"):
		if not e.has_method("is_alive") or not e.is_alive() or e in _swing_hit:
			continue
		var d: Vector3 = e.global_position - global_position
		d.y = 0.0
		var dist := d.length()
		if dist > float(def["reach"]) + 0.5 or dist < 0.01:
			continue
		if d.normalized().dot(fwd) < cos(float(def["arc"]) * 0.5):
			continue

		_swing_hit.append(e)
		e.take_damage(def["damage"], global_position, def["knock"])
		landed = true

	if landed:
		hit_stop(def["stop"])
		add_trauma(def["shake"])


# --- damage -----------------------------------------------------------------

func take_damage(amount: float, _from: Vector3) -> void:
	if not alive or _invuln > 0.0:
		return
	health = maxf(0.0, health - amount)
	_invuln = 0.55
	add_trauma(0.55)
	hit_stop(0.05)
	if health <= 0.0:
		alive = false
		_travel("death")


func _try_dodge_cancel() -> void:
	_attack_index = 0
	_attack_timer = 0.0
	_attack_buffered = false


# --- animation --------------------------------------------------------------

func _travel(state: String) -> void:
	if _anim_state == state:
		return
	_anim_state = state
	_sm.travel(state)


func _update_animation() -> void:
	if not alive:
		_travel("death")
		return
	if _dodging:
		_travel("dodge")
		return
	if _attack_index > 0:
		return  # the attack state is already playing; don't interrupt it
	if not is_on_floor():
		_travel("jump" if velocity.y > 0.5 else "fall")
		return
	if _land_timer > 0.0:
		_travel("land")
		return

	_travel("locomotion")
	anim_tree.set("parameters/locomotion/blend_position", planar_speed)


# --- queried by other systems ----------------------------------------------

func is_invulnerable() -> bool:
	return _invuln > 0.0

func is_dodging() -> bool:
	return _dodging
