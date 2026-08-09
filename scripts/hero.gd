extends CharacterBody3D
## The hybrid. GDQuest's movement and camera handling (MIT), carrying our combat.
##
## What came from their controller, because it demonstrably feels better:
##   - camera-oriented input with circular normalisation, so diagonals are not
##     faster than the axes
##   - quaternion slerp orientation on a dedicated rotation root, which is
##     smoother than lerping a single euler angle
##   - a ShapeCast3D ground probe feeding the camera, so jumping does not move
##     the view vertically
##   - velocity lerp toward a target rather than move_toward, plus their
##     unstick nudge when a slide collides into nothing
##
## What stayed ours, because their shooter has no equivalent:
##   - arm blade, 3-hit combo with buffered input and per-hit active windows
##   - dodge with i-frames that cancels attack recovery
##   - cone hitbox with target assist
##   - hit-stop, camera trauma, VFX and SFX

@export_group("Movement")
@export var walk_speed := 4.6
@export var sprint_speed := 8.4
@export var acceleration := 9.0
@export var rotation_speed := 12.0
@export var stopping_speed := 1.0

@export_group("Air")
@export var jump_initial_impulse := 8.5
@export var jump_additional_force := 12.0
@export var gravity := -26.0

@export_group("Dodge")
@export var dodge_speed := 16.5
@export var dodge_time := 0.40
@export var dodge_iframes := 0.28
@export var dodge_cooldown := 0.52

@export_group("Combat")
@export var max_health := 100.0
@export var attack_move_scale := 0.20
@export var attack_cancel_at := 0.62
@export var target_assist_angle := 1.15

@export_group("Arm blade")
@export var blade_bone := "mixamorig_RightForeArm"
@export var blade_offset := Vector3(0.0, 0.22, 0.0)
@export var blade_length := 1.05
@export var blade_width := 0.17
@export var blade_thickness := 0.045

const ATTACKS := [
	{"active": Vector2(0.20, 0.48), "damage": 22.0, "reach": 3.0, "arc": 2.1,
	 "knock": 3.5, "stop": 0.055, "shake": 0.35, "lunge": 2.6},
	{"active": Vector2(0.18, 0.44), "damage": 26.0, "reach": 3.0, "arc": 2.2,
	 "knock": 4.5, "stop": 0.065, "shake": 0.42, "lunge": 3.0},
	{"active": Vector2(0.24, 0.52), "damage": 44.0, "reach": 3.4, "arc": 2.8,
	 "knock": 11.0, "stop": 0.11, "shake": 0.9, "lunge": 3.6},
]

@onready var _rotation_root: Node3D = $CharacterRotationRoot
@onready var _camera_controller = $CameraController
@onready var _ground_shapecast: ShapeCast3D = $GroundShapeCast
@onready var model: Node3D = $CharacterRotationRoot/Model
@onready var anim_player: AnimationPlayer = $CharacterRotationRoot/AnimationPlayer
@onready var anim_tree: AnimationTree = $CharacterRotationRoot/AnimationTree

# Read by GDQuest's CameraController — the name must stay as it is.
var _ground_height := 0.0

var _move_direction := Vector3.ZERO
var _last_strong_direction := Vector3.FORWARD
var _is_on_floor_buffer := false

var health := 0.0
var alive := true
var planar_speed := 0.0

var _sm: AnimationNodeStateMachinePlayback
var _anim_state := ""
var _land_timer := 0.0

var _dodging := false
var _dodge_t := 0.0
var _dodge_cd := 0.0
var _dodge_dir := Vector3.ZERO
var _invuln := 0.0

var _attack_index := 0
var _attack_timer := 0.0
var _attack_len := 0.0
var _attack_buffered := false
var _swing_hit: Array = []

var _trauma := 0.0
var _hitstop_until_ms := 0

var _blade_root: Node3D
var _blade_base: Node3D
var _blade_tip: Node3D
var _blade_scale := 0.0
var _trail: MeshInstance3D
var _morph_played := false

var _step_accum := 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	health = max_health
	_sm = anim_tree.get("parameters/playback")
	_camera_controller.setup(self)
	_build_blade()


func _process(delta: float) -> void:
	if Engine.time_scale < 1.0 and Time.get_ticks_msec() >= _hitstop_until_ms:
		Engine.time_scale = 1.0

	_trauma = maxf(0.0, _trauma - 2.6 * delta)
	var s := _trauma * _trauma * 0.30
	var cam: Camera3D = _camera_controller.camera
	cam.h_offset = randf_range(-s, s)
	cam.v_offset = randf_range(-s, s)

	if _blade_root:
		var want := 1.0 if _attack_index > 0 else 0.0
		var rate := 26.0 if want > _blade_scale else 7.0
		_blade_scale = lerpf(_blade_scale, want, 1.0 - exp(-rate * delta))
		_blade_root.scale = Vector3.ONE * maxf(_blade_scale, 0.001)

		if want > 0.0 and not _morph_played:
			_morph_played = true
			Vfx.morph(_blade_root.global_position)
		elif want == 0.0 and _blade_scale < 0.1:
			_morph_played = false

		if _trail:
			_trail.set_active(_attack_index > 0 and _blade_scale > 0.5)
			if _blade_scale > 0.5:
				_trail.sample(_blade_base.global_position, _blade_tip.global_position)


func _physics_process(delta: float) -> void:
	_dodge_cd = maxf(0.0, _dodge_cd - delta)
	_invuln = maxf(0.0, _invuln - delta)
	_land_timer = maxf(0.0, _land_timer - delta)

	# Ground probe for the camera. Straight from their controller.
	if _ground_shapecast.get_collision_count() > 0:
		for r in _ground_shapecast.collision_result:
			_ground_height = maxf(_ground_height, r.point.y)
	else:
		_ground_height = global_position.y + _ground_shapecast.target_position.y
	if global_position.y < _ground_height:
		_ground_height = global_position.y

	_attack_timer = maxf(0.0, _attack_timer - delta)
	if _attack_timer <= 0.0:
		_attack_index = 0
		_attack_buffered = false
	else:
		var def: Dictionary = ATTACKS[_attack_index - 1]
		var progress := 1.0 - (_attack_timer / maxf(_attack_len, 0.001))
		var w: Vector2 = def["active"]
		if progress >= w.x and progress <= w.y:
			_resolve_swing()
		if _attack_buffered and _attack_timer <= _attack_len * (1.0 - attack_cancel_at):
			_attack_buffered = false
			_start_attack(_attack_index + 1)

	var is_just_jumping := Input.is_action_just_pressed("jump") and is_on_floor()
	var is_air_boosting := Input.is_action_pressed("jump") and not is_on_floor() and velocity.y > 0.0
	var is_just_on_floor := is_on_floor() and not _is_on_floor_buffer
	_is_on_floor_buffer = is_on_floor()

	if alive:
		if Input.is_action_just_pressed("dodge"):
			_try_dodge()
		if Input.is_action_just_pressed("attack"):
			_try_attack()

	_move_direction = _get_camera_oriented_input()
	if _move_direction.length() > 0.2:
		_last_strong_direction = _move_direction.normalized()
	_orient_character_to_direction(_last_strong_direction, delta)

	# Vertical is held out of the lerp so gravity is never interpolated.
	var y_velocity := velocity.y
	velocity.y = 0.0

	if _dodging:
		_dodge_t += delta
		if _dodge_t >= dodge_time:
			_dodging = false
		var p := _dodge_t / dodge_time
		var sp := dodge_speed * (1.0 - p * p)
		velocity.x = _dodge_dir.x * sp
		velocity.z = _dodge_dir.z * sp
	else:
		var sprinting := Input.is_action_pressed("sprint") and _move_direction.length() > 0.1
		var speed := sprint_speed if sprinting else walk_speed
		if _attack_index > 0:
			speed *= attack_move_scale
		if not alive:
			speed = 0.0
		velocity = velocity.lerp(_move_direction * speed, acceleration * delta)
		if _move_direction.length() == 0 and velocity.length() < stopping_speed:
			velocity = Vector3.ZERO

	velocity.y = y_velocity
	velocity.y += gravity * delta
	if is_just_jumping and alive and not _dodging:
		velocity.y = jump_initial_impulse
	elif is_air_boosting:
		velocity.y += jump_additional_force * delta

	if is_just_on_floor and not _dodging:
		_land_timer = 0.26
		Sfx.play_at(&"land", global_position)
		Vfx.dust(global_position + Vector3.UP * 0.1, 14)
		add_trauma(0.22)

	var before := global_position
	move_and_slide()
	# Their unstick: if we had velocity but went nowhere, nudge off the wall.
	if (global_position - before).length() < 0.001 and velocity.length() > 0.001:
		global_position += get_wall_normal() * 0.1

	planar_speed = Vector2(velocity.x, velocity.z).length()
	_update_animation(is_just_jumping)
	_update_footsteps(delta)


# --- movement, from GDQuest ---------------------------------------------------

func _get_camera_oriented_input() -> Vector3:
	if not alive:
		return Vector3.ZERO
	var raw := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var input := Vector3.ZERO
	# Circular normalisation — without it, diagonals travel ~41% faster.
	input.x = -raw.x * sqrt(1.0 - raw.y * raw.y / 2.0)
	input.z = -raw.y * sqrt(1.0 - raw.x * raw.x / 2.0)
	input = _camera_controller.global_transform.basis * input
	input.y = 0.0
	return input


func _orient_character_to_direction(direction: Vector3, delta: float) -> void:
	if direction.length_squared() < 0.001:
		return
	var left_axis := Vector3.UP.cross(direction)
	var target := Basis(left_axis, Vector3.UP, direction).get_rotation_quaternion()
	var scale := _rotation_root.transform.basis.get_scale()
	_rotation_root.transform.basis = Basis(
		_rotation_root.transform.basis.get_rotation_quaternion().slerp(
			target, delta * rotation_speed)).scaled(scale)


# --- combat, ours -------------------------------------------------------------

func hit_stop(seconds: float) -> void:
	_hitstop_until_ms = maxi(_hitstop_until_ms, Time.get_ticks_msec() + int(seconds * 1000.0))
	Engine.time_scale = 0.05


func add_trauma(amount: float) -> void:
	_trauma = minf(_trauma + amount, 2.0)


func _try_dodge() -> void:
	if _dodging or _dodge_cd > 0.0 or not is_on_floor():
		return
	var dir := _move_direction
	if dir.length_squared() < 0.01:
		# The rotation root is built with basis.z == facing direction.
		dir = _rotation_root.global_transform.basis.z
	dir.y = 0.0
	_dodge_dir = dir.normalized()
	_dodging = true
	_dodge_t = 0.0
	_dodge_cd = dodge_cooldown
	_invuln = maxf(_invuln, dodge_iframes)
	_attack_index = 0
	_attack_timer = 0.0
	_attack_buffered = false
	_last_strong_direction = _dodge_dir
	Sfx.play_at(&"dodge", global_position + Vector3.UP)
	Vfx.dust(global_position + Vector3.UP * 0.15, 14)


func _try_attack() -> void:
	if _dodging or not is_on_floor():
		return
	if _attack_index == 0:
		_start_attack(1)
	else:
		_attack_buffered = true


func _start_attack(n: int) -> void:
	if n > 3:
		n = 1
	_attack_index = n
	var clip := "attack%d" % n
	_attack_len = anim_player.get_animation(clip).length if anim_player.has_animation(clip) else 0.6
	_attack_timer = _attack_len
	_swing_hit.clear()

	var def: Dictionary = ATTACKS[n - 1]
	var target := _find_target(float(def["reach"]) * 1.8)
	var face: Vector3
	if target:
		face = target.global_position - global_position
		face.y = 0.0
		face = face.normalized()
	else:
		face = _last_strong_direction
	_last_strong_direction = face
	_orient_character_to_direction(face, 1.0)

	var speed: float = def["lunge"]
	if target:
		var gap: float = maxf(0.0,
			global_position.distance_to(target.global_position) - float(def["reach"]) * 0.6)
		speed = minf(speed, gap * 6.0)
	velocity += face * speed

	Sfx.play_at(&"swing_heavy" if n == 3 else &"swing_light", global_position + Vector3.UP)
	_travel(clip)


func _find_target(range_m: float) -> Node3D:
	# GDQuest's rig treats +Z as forward: the PlayerCamera child is rotated 180
	# and sits at -Z looking back toward +Z. So view direction is +basis.z here,
	# not the -basis.z you would expect from a plain Godot camera.
	var aim: Vector3 = _camera_controller.global_transform.basis.z
	aim.y = 0.0
	aim = aim.normalized()
	var best: Node3D = null
	var best_score := INF
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


func _resolve_swing() -> void:
	var def: Dictionary = ATTACKS[_attack_index - 1]
	var fwd := _rotation_root.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
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

		var contact: Vector3 = global_position.lerp(e.global_position, 0.62) + Vector3.UP * 1.1
		var heavy: bool = float(def["damage"]) >= 40.0
		Vfx.sparks(contact, fwd + Vector3.UP * 0.4, heavy)
		Vfx.ichor(contact, -fwd * 0.3 + Vector3.UP, heavy)
		Sfx.play_at(&"impact_heavy" if heavy else &"impact_light", contact)

	if landed:
		hit_stop(def["stop"])
		add_trauma(def["shake"])


func take_damage(amount: float, _from: Vector3) -> void:
	if not alive or _invuln > 0.0:
		return
	health = maxf(0.0, health - amount)
	_invuln = 0.55
	add_trauma(0.55)
	hit_stop(0.05)
	Sfx.play_at(&"hurt", global_position + Vector3.UP)
	if health <= 0.0:
		alive = false


func is_invulnerable() -> bool:
	return _invuln > 0.0


func is_dodging() -> bool:
	return _dodging


# --- animation ---------------------------------------------------------------

func _travel(state: String) -> void:
	if _anim_state == state:
		return
	_anim_state = state
	_sm.travel(state)


func _update_animation(just_jumped: bool) -> void:
	if not alive:
		_travel("death")
		return
	if _dodging:
		_travel("dodge")
		return
	if _attack_index > 0:
		return
	if just_jumped:
		_travel("jump")
		return
	if not is_on_floor():
		_travel("jump" if velocity.y > 0.5 else "fall")
		return
	if _land_timer > 0.0:
		_travel("land")
		return
	_travel("locomotion")
	anim_tree.set("parameters/locomotion/blend_position", planar_speed)


func _update_footsteps(delta: float) -> void:
	if is_on_floor() and planar_speed > 0.6 and not _dodging:
		_step_accum += planar_speed * delta
		if _step_accum >= 1.9:
			_step_accum = 0.0
			Sfx.play_at(&"footstep", global_position, -6.0)
	elif planar_speed <= 0.6:
		_step_accum = 1.5


# --- arm blade ---------------------------------------------------------------

func _build_blade() -> void:
	var skel := _find_skeleton(model)
	if skel == null or skel.find_bone(blade_bone) == -1:
		push_warning("arm blade skipped: bone '%s' not found" % blade_bone)
		return

	var att := BoneAttachment3D.new()
	att.bone_name = blade_bone
	skel.add_child(att)

	_blade_root = Node3D.new()
	_blade_root.position = blade_offset
	att.add_child(_blade_root)

	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.78, 0.83, 0.88)
	steel.metallic = 0.85
	steel.roughness = 0.22
	steel.emission_enabled = true
	steel.emission = Color(0.45, 0.72, 1.0)
	steel.emission_energy_multiplier = 0.35

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

	var stub := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.1, 0.28, blade_width * 1.5)
	stub.mesh = sm
	stub.material_override = steel
	stub.position = Vector3(0, 0.02, 0)
	_blade_root.add_child(stub)

	_blade_base = Node3D.new()
	_blade_base.position = Vector3(0, 0.15, 0)
	_blade_tip = Node3D.new()
	_blade_tip.position = Vector3(0, blade_length + 0.35, 0)
	_blade_root.add_child(_blade_base)
	_blade_root.add_child(_blade_tip)
	_blade_root.scale = Vector3.ZERO

	_trail = MeshInstance3D.new()
	_trail.set_script(load("res://scripts/blade_trail.gd"))
	add_child(_trail)


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r:
			return r
	return null
