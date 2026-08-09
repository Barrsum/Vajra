extends CharacterBody3D
class_name Enemy
## Melee alien.
##
## Threat comes from three things, in order of how much they matter:
##
## 1. ATTACK TOKENS. Only a fixed number may commit at once; the rest circle.
##    Without it a group all lunges together and the fight is unreadable.
## 2. RHYTHM. Each archetype has its own multi-hit sequence with its own
##    timings, so you learn a pattern rather than a single tell.
## 3. THE BURST. A brief 2-3x speed spike while closing. Four or five frames,
##    rare enough to stay surprising — it is what stops the player from
##    reading distance as safety.

signal died(enemy: Enemy)

enum State { CHASE, CIRCLE, TELEGRAPH, STRIKE, LINK, RECOVER, STAGGER, DEAD }

const MAX_TOKENS := 2
static var _tokens := MAX_TOKENS

## Behaviour archetypes. Variety here is behavioural, not visual — one model,
## four genuinely different fights.
const ARCHETYPES := [
	{
		"name": "HUSK", "color": Color(0.30, 0.13, 0.16), "accent": Color(0.35, 1.0, 0.75),
		"hp": 1.0, "speed": 1.0, "dmg": 1.0, "reach": 1.0,
		# telegraph, strike, link (gap between hits), recover
		"combo": [[0.62, 0.20, 0.0, 0.80]],
		"burst": 0.10, "feint": 0.0, "circle": 1.0, "aggro": 1.0,
	},
	{
		# Fast, wide-circling, opens with a quick double. Bursts often.
		"name": "STALKER", "color": Color(0.12, 0.20, 0.26), "accent": Color(0.4, 0.9, 1.0),
		"hp": 0.75, "speed": 1.45, "dmg": 0.8, "reach": 0.95,
		"combo": [[0.34, 0.14, 0.16, 0.30], [0.10, 0.14, 0.0, 0.70]],
		"burst": 0.42, "feint": 0.15, "circle": 1.6, "aggro": 1.35,
	},
	{
		# Three-hit chain and it feints. The one that punishes panic-dodging.
		"name": "RAVAGER", "color": Color(0.26, 0.10, 0.24), "accent": Color(1.0, 0.45, 0.9),
		"hp": 1.25, "speed": 1.1, "dmg": 0.9, "reach": 1.05,
		"combo": [[0.48, 0.16, 0.18, 0.25], [0.12, 0.16, 0.20, 0.25], [0.14, 0.20, 0.0, 0.95]],
		"burst": 0.22, "feint": 0.45, "circle": 0.9, "aggro": 1.1,
	},
	{
		# Slow, enormous wind-up, enormous payoff. Never bursts; you always see
		# it coming, and it still hurts if you get greedy.
		"name": "JUGGERNAUT", "color": Color(0.22, 0.16, 0.09), "accent": Color(1.0, 0.6, 0.15),
		"hp": 2.2, "speed": 0.72, "dmg": 2.1, "reach": 1.25,
		"combo": [[1.05, 0.26, 0.0, 1.15]],
		"burst": 0.0, "feint": 0.0, "circle": 0.45, "aggro": 0.85,
	},
]

## Size tiers, applied on top of the archetype.
const TIERS := [
	{"name": "", "scale": 1.0, "hp": 1.0, "dmg": 1.0, "speed": 1.0,
	 "reach": 1.0, "tele": 1.0, "knock": 1.0, "drops": 1},
	{"name": "BRUTE", "scale": 1.75, "hp": 3.0, "dmg": 1.8, "speed": 0.85,
	 "reach": 1.45, "tele": 1.2, "knock": 0.45, "drops": 2},
	{"name": "COLOSSUS", "scale": 3.1, "hp": 8.0, "dmg": 3.0, "speed": 0.66,
	 "reach": 2.1, "tele": 1.45, "knock": 0.18, "drops": 4},
]

@export_group("Stats")
@export var max_health := 90.0
@export var move_speed := 2.4
@export var reach := 2.3
@export var damage := 9.0

@export_group("Timing")
@export var stagger_time := 0.35

@export_group("Feel")
@export var knockback_scale := 1.0
@export var turn_speed := 8.0
## Speed multiplier and duration of the closing burst.
@export var burst_speed := 2.8
@export var burst_time := 0.09

@onready var visual: Node3D = $Visual
@onready var model: Node3D = $Visual/Model
@onready var anim_tree: AnimationTree = $Visual/AnimationTree

var tier := 0
var archetype := 0
var drops := 1

var health := 0.0
var state := State.CHASE
var player: Node3D

var _combo: Array = []
var _combo_i := 0
var _t := 0.0
var _has_token := false
var _did_hit := false
var _roared := false
var _feinting := false
var _circle_side := 1.0
var _circle_mul := 1.0
var _aggro := 1.0
var _flash := 0.0
var _facing := 0.0
var _burst_t := 0.0
var _burst_cd := 0.0
var _sm: AnimationNodeStateMachinePlayback
var _anim_state := ""
var _mats: Array[StandardMaterial3D] = []
var _accent := Color(0.35, 1.0, 0.75)
var _body_col := Color(0.30, 0.13, 0.16)

var _bar_fg: MeshInstance3D
var _bar_root: Node3D
const BAR_W := 1.2


## Both must be called before the node enters the tree.
func set_archetype(i: int) -> void:
	archetype = clampi(i, 0, ARCHETYPES.size() - 1)
	var a: Dictionary = ARCHETYPES[archetype]
	max_health *= a["hp"]
	move_speed *= a["speed"]
	damage *= a["dmg"]
	reach *= a["reach"]
	_combo = a["combo"]
	_circle_mul = a["circle"]
	_aggro = a["aggro"]
	_body_col = a["color"]
	_accent = a["accent"]


func set_tier(t: int) -> void:
	tier = clampi(t, 0, TIERS.size() - 1)
	var d: Dictionary = TIERS[tier]
	max_health *= d["hp"]
	damage *= d["dmg"]
	move_speed *= d["speed"]
	reach *= d["reach"]
	knockback_scale *= d["knock"]
	drops = d["drops"]


func _ready() -> void:
	if _combo.is_empty():
		_combo = ARCHETYPES[0]["combo"]
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
			m.albedo_color = _body_col
			m.roughness = 0.75
			m.emission_enabled = true
			m.emission = _accent
			m.emission_energy_multiplier = 0.05
			mi.set_surface_override_material(s, m)
			_mats.append(m)
	for c in n.get_children():
		_collect_materials(c)


# --- health bar -------------------------------------------------------------

func _build_health_bar() -> void:
	_bar_root = Node3D.new()
	add_child(_bar_root)
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
	m.disable_receive_shadows = true
	return m


func _update_health_bar() -> void:
	if _bar_fg == null:
		return
	var frac := clampf(health / maxf(max_health, 0.001), 0.0, 1.0)
	_bar_fg.scale.x = maxf(frac, 0.001)
	_bar_fg.position.x = -(1.0 - frac) * BAR_W * 0.5
	var m: StandardMaterial3D = _bar_fg.material_override
	m.albedo_color = Color(1.0, 0.30, 0.22).lerp(Color(1.0, 0.85, 0.35), 1.0 - frac)
	_bar_root.visible = state != State.DEAD


# --- brain ------------------------------------------------------------------

func _step() -> Array:
	return _combo[mini(_combo_i, _combo.size() - 1)]


func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return

	_t += delta
	_flash = maxf(0.0, _flash - delta * 6.0)
	_burst_t = maxf(0.0, _burst_t - delta)
	_burst_cd = maxf(0.0, _burst_cd - delta)

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
	var step := _step()

	match state:
		State.CHASE:
			if _has_token or _take_token():
				if dist < reach * 0.9:
					_begin_attack()
				else:
					wish = to_player * move_speed * _aggro
					_maybe_burst(dist)
			elif dist < reach * 1.6:
				_set_state(State.CIRCLE)
			else:
				wish = to_player * move_speed

		State.CIRCLE:
			if _take_token():
				_set_state(State.CHASE)
			elif dist > reach * 2.6:
				_set_state(State.CHASE)
			else:
				# Strafe at the edge of reach. Wider circlers flank; the heavy
				# ones barely move sideways at all.
				var tangent := Vector3(-to_player.z, 0.0, to_player.x) * _circle_side
				var keep := (dist - reach * 1.35) * 0.9
				wish = tangent * move_speed * 0.6 * _circle_mul + to_player * keep
				if _t > 1.6 + randf() * 1.4:
					_circle_side *= -1.0
					_t = 0.0

		State.TELEGRAPH:
			if not _roared:
				_roared = true
				Sfx.play_at(&"roar", global_position + Vector3.UP * 1.6, -2.0 if _combo_i > 0 else 0.0)
			wish = to_player * move_speed * 0.25
			var tele: float = step[0]
			# A feint stalls at 65% of the wind-up, then resumes. Punishes anyone
			# dodging on the tell instead of on the strike.
			if _feinting and _t >= tele * 0.65 and _t < tele * 0.65 + 0.28:
				wish = Vector3.ZERO
			elif _t >= tele + (0.28 if _feinting else 0.0):
				_set_state(State.STRIKE)
				_did_hit = false

		State.STRIKE:
			wish = to_player * move_speed * 1.6
			if not _did_hit and _t > float(step[1]) * 0.35:
				_did_hit = true
				if dist < reach + 0.6 and player.has_method("take_damage"):
					player.take_damage(damage, global_position)
			if _t >= float(step[1]):
				if _combo_i < _combo.size() - 1:
					_set_state(State.LINK)
				else:
					_set_state(State.RECOVER)

		State.LINK:
			# The gap between chained hits. Short, and you can dodge through it.
			wish = to_player * move_speed * 0.5
			if _t >= float(step[2]):
				_combo_i += 1
				_roared = false
				_set_state(State.TELEGRAPH)

		State.RECOVER:
			_roared = false
			if _t >= float(step[3]):
				_release_token()
				_combo_i = 0
				_set_state(State.CHASE)

		State.STAGGER:
			if _t >= stagger_time:
				_set_state(State.CHASE)

	var speed_mul := burst_speed if _burst_t > 0.0 else 1.0
	var rate := 26.0 if state == State.STRIKE or _burst_t > 0.0 else 10.0
	velocity.x = move_toward(velocity.x, wish.x * speed_mul, rate * delta)
	velocity.z = move_toward(velocity.z, wish.z * speed_mul, rate * delta)
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


## A short sprint while closing. Rare, brief, and the single biggest source of
## tension — distance stops being reliable safety.
func _maybe_burst(dist: float) -> void:
	if _burst_cd > 0.0 or _burst_t > 0.0:
		return
	var chance: float = ARCHETYPES[archetype]["burst"]
	if chance <= 0.0 or dist > reach * 5.0 or dist < reach * 1.2:
		return
	if randf() < chance * 0.06:
		_burst_t = burst_time
		_burst_cd = 1.4 + randf() * 1.2
		Vfx.dust(global_position + Vector3.UP * 0.2, 8)


func _begin_attack() -> void:
	_combo_i = 0
	_roared = false
	_feinting = randf() < float(ARCHETYPES[archetype]["feint"])
	_set_state(State.TELEGRAPH)


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

	Sfx.play_at(&"impact_heavy" if amount > 30.0 else &"impact_light", global_position + Vector3.UP)

	if health <= 0.0:
		_die()
		return

	# Mid-combo enemies resist interruption, so a chain has to be dodged rather
	# than simply out-damaged.
	var resist := 0.55 if state == State.LINK or state == State.STRIKE else 0.0
	if amount >= 25.0 and randf() > resist or randf() < 0.35 - resist:
		_release_token()
		_combo_i = 0
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
	var tw := create_tween()
	tw.tween_interval(2.6)
	tw.tween_property(self, "position:y", position.y - 2.2, 1.4)
	tw.tween_callback(queue_free)


func is_alive() -> bool:
	return state != State.DEAD


# --- presentation -----------------------------------------------------------

func _update_animation() -> void:
	match state:
		State.DEAD:
			_travel("death")
		State.STAGGER:
			_travel("hit")
		State.TELEGRAPH:
			_travel("telegraph")
		State.STRIKE, State.RECOVER, State.LINK:
			# Alternate hands down the chain so a combo reads as a sequence.
			_travel("attack1" if _combo_i % 2 == 0 else "attack2")
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
	var tele := 0.0
	if state == State.TELEGRAPH:
		tele = clampf(_t / maxf(float(_step()[0]), 0.01), 0.0, 1.0)
		if _feinting:
			tele *= 0.6   # a feint glows less, so it can be told apart if you look
	var e := 0.05 + _flash * 2.2 + tele * 1.6 + (1.2 if _burst_t > 0.0 else 0.0)
	var col := _accent.lerp(Color(1.0, 0.15, 0.05), tele)
	if _burst_t > 0.0:
		col = Color(1.0, 0.9, 0.7)
	for m in _mats:
		m.emission = col
		m.emission_energy_multiplier = e
		m.albedo_color = _body_col.lerp(Color(1, 0.9, 0.9), _flash * 0.7)
