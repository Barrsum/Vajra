extends CharacterBody3D
class_name Enemy
## Melee alien. Ported from the browser prototype, where this behaviour was
## already proven to read well.
##
## The important idea is the attack token. Only a fixed number of enemies may
## commit to a swing at once; everyone else circles at the edge of reach. Without
## it, a group all lunges simultaneously and the fight becomes unreadable and
## unfair no matter how good the individual AI is.

signal died(enemy: Enemy)

enum State { CHASE, CIRCLE, TELEGRAPH, STRIKE, RECOVER, STAGGER, DEAD }

const MAX_TOKENS := 2
static var _tokens := MAX_TOKENS

@export_group("Stats")
@export var max_health := 90.0
@export var move_speed := 2.4
@export var reach := 2.3
@export var damage := 9.0

@export_group("Timing")
@export var telegraph_time := 0.68   ## roar wind-up; long enough to see and dodge
@export var strike_time := 0.22
@export var recover_time := 0.75
@export var stagger_time := 0.35

@export_group("Feel")
@export var knockback_scale := 1.0
@export var turn_speed := 8.0

## Size tiers. Bigger ones hit harder and shrug off knockback, but move slower
## and telegraph longer — so they read as a different threat, not just more HP.
const TIERS := [
	{"name": "", "scale": 1.0, "hp": 1.0, "dmg": 1.0, "speed": 1.0,
	 "reach": 1.0, "tele": 1.0, "knock": 1.0, "drops": 1},
	{"name": "BRUTE", "scale": 1.9, "hp": 3.2, "dmg": 1.9, "speed": 0.82,
	 "reach": 1.55, "tele": 1.25, "knock": 0.42, "drops": 2},
	{"name": "COLOSSUS", "scale": 3.6, "hp": 9.0, "dmg": 3.2, "speed": 0.62,
	 "reach": 2.4, "tele": 1.5, "knock": 0.15, "drops": 4},
]

var tier := 0
var drops := 1

@onready var visual: Node3D = $Visual
@onready var model: Node3D = $Visual/Model
@onready var anim_tree: AnimationTree = $Visual/AnimationTree

var health := 0.0
var state := State.CHASE
var _t := 0.0
var _has_token := false
var _did_hit := false
var _roared := false
var _circle_side := 1.0
var _flash := 0.0
var _facing := 0.0
var _sm: AnimationNodeStateMachinePlayback
var _anim_state := ""
var _mats: Array[StandardMaterial3D] = []

var player: Node3D
var _bar_fg: MeshInstance3D
var _bar_root: Node3D
const BAR_W := 1.2


## Must be called before the node enters the tree, so stats are already scaled
## by the time _ready runs.
func set_tier(t: int) -> void:
	tier = clampi(t, 0, TIERS.size() - 1)
	var d: Dictionary = TIERS[tier]
	max_health *= d["hp"]
	damage *= d["dmg"]
	move_speed *= d["speed"]
	reach *= d["reach"]
	telegraph_time *= d["tele"]
	knockback_scale *= d["knock"]
	drops = d["drops"]


func _ready() -> void:
	health = max_health
	_circle_side = 1.0 if randf() < 0.5 else -1.0
	_sm = anim_tree.get("parameters/playback")
	add_to_group("enemies")
	scale = Vector3.ONE * float(TIERS[tier]["scale"])
	_collect_materials(model)
	_build_health_bar()


func _collect_materials(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.30, 0.13, 0.16)
			m.roughness = 0.75
			# Emission carries the hit flash and the telegraph glow.
			m.emission_enabled = true
			m.emission = Color(0.35, 1.0, 0.75)
			m.emission_energy_multiplier = 0.05
			mi.set_surface_override_material(s, m)
			_mats.append(m)
	for c in n.get_children():
		_collect_materials(c)


## Floating bar. Billboarded and unshaded so it reads at any angle and in the
## dark level, where a lit bar would simply vanish.
func _build_health_bar() -> void:
	_bar_root = Node3D.new()
	add_child(_bar_root)
	# Placed in local space, so the tier scale lifts it clear of bigger bodies.
	_bar_root.position = Vector3(0, 2.35, 0)

	var bg := MeshInstance3D.new()
	var bgm := QuadMesh.new()
	bgm.size = Vector2(BAR_W, 0.14)
	bg.mesh = bgm
	bg.material_override = _bar_mat(Color(0.05, 0.03, 0.04, 0.85))
	_bar_root.add_child(bg)

	_bar_fg = MeshInstance3D.new()
	var fgm := QuadMesh.new()
	fgm.size = Vector2(BAR_W, 0.14)
	_bar_fg.mesh = fgm
	_bar_fg.material_override = _bar_mat(Color(1.0, 0.30, 0.22, 1.0))
	_bar_fg.position.z = 0.01
	_bar_root.add_child(_bar_fg)


func _bar_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = false
	m.disable_receive_shadows = true
	return m


func _update_health_bar() -> void:
	if _bar_fg == null:
		return
	var frac := clampf(health / maxf(max_health, 0.001), 0.0, 1.0)
	# Shrink from the right by scaling and shifting half the lost width.
	_bar_fg.scale.x = maxf(frac, 0.001)
	_bar_fg.position.x = -(1.0 - frac) * BAR_W * 0.5
	var m: StandardMaterial3D = _bar_fg.material_override
	m.albedo_color = Color(1.0, 0.30, 0.22).lerp(Color(1.0, 0.85, 0.35), 1.0 - frac)
	var vis := state != State.DEAD
	_bar_root.visible = vis


func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return

	_t += delta
	_flash = maxf(0.0, _flash - delta * 6.0)

	if state == State.DEAD:
		_apply_materials()
		_update_health_bar()
		return

	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	if dist > 0.001:
		to_player /= dist

	var wish := Vector3.ZERO

	match state:
		State.CHASE:
			# Holding a token means committing: close all the way in, then swing.
			if _has_token or _take_token():
				if dist < reach * 0.9:
					_set_state(State.TELEGRAPH)
				else:
					wish = to_player * move_speed
			elif dist < reach * 1.6:
				_set_state(State.CIRCLE)
			else:
				wish = to_player * move_speed

		State.CIRCLE:
			# Circling holds spacing at reach * 1.35, which is further out than
			# attack range — so waiting here for proximity would deadlock. The
			# token is the trigger, and it sends us back to CHASE to close.
			if _take_token():
				_set_state(State.CHASE)
			elif dist > reach * 2.6:
				_set_state(State.CHASE)
			else:
				# Strafe at the edge of reach, drifting in or out to hold spacing.
				var tangent := Vector3(-to_player.z, 0.0, to_player.x) * _circle_side
				var keep := (dist - reach * 1.35) * 0.9
				wish = tangent * move_speed * 0.6 + to_player * keep
				if _t > 2.2:
					_circle_side *= -1.0
					_t = 0.0

		State.TELEGRAPH:
			if not _roared:
				_roared = true
				Sfx.play_at(&"roar", global_position + Vector3.UP * 1.6)
			wish = to_player * move_speed * 0.25
			if _t >= telegraph_time:
				_set_state(State.STRIKE)
				_did_hit = false

		State.STRIKE:
			wish = to_player * move_speed * 1.3
			if not _did_hit and _t > strike_time * 0.4:
				_did_hit = true
				if dist < reach + 0.6 and player.has_method("take_damage"):
					player.take_damage(damage, global_position)
			if _t >= strike_time:
				_set_state(State.RECOVER)

		State.RECOVER:
			_roared = false
			if _t >= recover_time:
				_release_token()
				_set_state(State.CHASE)

		State.STAGGER:
			if _t >= stagger_time:
				_set_state(State.CHASE)

	# Movement. Knockback lives in velocity and decays on its own.
	var rate := 26.0 if state == State.STRIKE else 10.0
	velocity.x = move_toward(velocity.x, wish.x, rate * delta)
	velocity.z = move_toward(velocity.z, wish.z, rate * delta)
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	else:
		velocity.y = 0.0
	move_and_slide()

	if dist > 0.05:
		_facing = lerp_angle(_facing, atan2(to_player.x, to_player.z), 1.0 - exp(-turn_speed * delta))
		visual.rotation.y = _facing

	_update_animation()
	_apply_materials()
	_update_health_bar()


func _set_state(s: State) -> void:
	state = s
	_t = 0.0


func _take_token() -> bool:
	if _has_token:
		return true
	if _tokens <= 0:
		return false
	_tokens -= 1
	_has_token = true
	return true


func _release_token() -> void:
	if _has_token:
		_has_token = false
		_tokens = mini(_tokens + 1, MAX_TOKENS)


static func reset_tokens() -> void:
	_tokens = MAX_TOKENS


# ---------------------------------------------------------------------------

func take_damage(amount: float, from: Vector3, knockback: float) -> void:
	if state == State.DEAD:
		return
	health -= amount
	_flash = 1.0
	_update_health_bar()

	var dir := global_position - from
	dir.y = 0.0
	if dir.length_squared() > 0.001:
		velocity += dir.normalized() * knockback * knockback_scale

	if health <= 0.0:
		_die()
		return

	# Heavy hits always interrupt; light ones sometimes don't, or there is no
	# threat in standing next to one.
	if amount >= 25.0 or randf() < 0.4:
		_release_token()
		_set_state(State.STAGGER)


func _die() -> void:
	_release_token()
	_set_state(State.DEAD)
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	died.emit(self)
	_travel("death")
	Sfx.play_at(&"death", global_position + Vector3.UP * 1.2)
	Vfx.death_burst(global_position + Vector3.UP * 1.1)
	# Leave the corpse a moment, then sink it out of sight.
	var tw := create_tween()
	tw.tween_interval(2.6)
	tw.tween_property(self, "position:y", position.y - 2.2, 1.4)
	tw.tween_callback(queue_free)


func is_alive() -> bool:
	return state != State.DEAD


# ---------------------------------------------------------------------------

func _update_animation() -> void:
	match state:
		State.DEAD:
			_travel("death")
		State.STAGGER:
			_travel("hit")
		State.TELEGRAPH:
			# A roar, not the swing itself. The wind-up is now readable as its own
			# beat instead of being the first frames of the attack.
			_travel("telegraph")
		State.STRIKE, State.RECOVER:
			# Recovery keeps the attack clip playing. Cutting back to locomotion
			# the instant the hitbox closes made every swing look truncated.
			_travel("attack1" if _circle_side > 0.0 else "attack2")
		_:
			_travel("locomotion")
			anim_tree.set("parameters/locomotion/blend_position",
				Vector2(velocity.x, velocity.z).length())


func _travel(s: String) -> void:
	if _anim_state == s:
		return
	_anim_state = s
	_sm.travel(s)


func _apply_materials() -> void:
	# White on impact, red rising through the wind-up so the swing is readable.
	var tele := 0.0
	if state == State.TELEGRAPH:
		tele = clampf(_t / telegraph_time, 0.0, 1.0)
	# Glow is enabled in the environment, so emission energy compounds fast —
	# these stay low or the creature reads as a light bulb rather than a body.
	var e := 0.05 + _flash * 2.2 + tele * 1.6
	var col := Color(0.35, 1.0, 0.75).lerp(Color(1.0, 0.15, 0.05), tele)
	for m in _mats:
		m.emission = col
		m.emission_energy_multiplier = e
		m.albedo_color = Color(0.30, 0.13, 0.16).lerp(Color(1, 0.9, 0.9), _flash * 0.7)
