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

## Creatures. All four use Mixamo's skeleton and share one animation library —
## verified as zero missing bones — so the mesh is a pure swap. `scale`
## normalises their differing heights (1.86m to 2.38m) to a common base, so tier
## multipliers mean the same thing whichever creature they land on.
const CREATURES := [
	{"name": "MUTANT", "scene": "res://assets/enemy/Mutant.fbx",
	 "scale": 1.05, "color": Color(0.30, 0.13, 0.16)},
	{"name": "PUMPKINHULK", "scene": "res://assets/enemy/Pumpkinhulk L Shaw.fbx",
	 "scale": 0.96, "color": Color(0.34, 0.20, 0.08)},
	{"name": "SKELETON", "scene": "res://assets/enemy/Skeletonzombie T Avelange.fbx",
	 "scale": 0.95, "color": Color(0.26, 0.26, 0.22)},
	{"name": "WARROK", "scene": "res://assets/enemy/Warrok W Kurniawan.fbx",
	 "scale": 0.82, "color": Color(0.22, 0.15, 0.20)},
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
var model: Node3D
@onready var anim_tree: AnimationTree = $Visual/AnimationTree

var tier := 0
var archetype := 0
var creature := 0

## Set-piece roles. When one is active the normal brain is bypassed entirely —
## a scripted actor must not be pulled off its mark by circling logic.
enum Role { FREE, CHARGE, HOLD, STALK, SMASH, DONE }
var role := Role.FREE
var role_side := 1.0        ## which arm a HOLD actor takes
var role_speed := 1.0
## Overrides the tier's size when > 0. The set-piece heavy is 2.5x, which is
## between Brute and Colossus and belongs to no tier.
var role_scale := 0.0
var _role_t := 0.0
var _smash_hit := false
var _tether: MeshInstance3D = null
## Latched on the first CHARGE frame. Recomputing the flank each tick makes
## the target orbit the player as the approach angle changes, so a charger
## closes to arm's length and then circles forever without ever arriving.
var _hold_dir := Vector3.ZERO
signal smashed(enemy)
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
## Each material's own albedo, so the hit flash can return to it. Without
## this the flash would have to assume a flat colour and the texture is lost.
var _base_cols: Array[Color] = []
var _accent := Color(0.35, 1.0, 0.75)
var _body_col := Color(0.30, 0.13, 0.16)



## All three must be called before the node enters the tree.
func set_creature(i: int) -> void:
	creature = clampi(i, 0, CREATURES.size() - 1)
	_body_col = CREATURES[creature]["color"]


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
	add_to_group("enemies")

	anim_tree.active = true
	_sm = anim_tree.get("parameters/playback")

	var body: float = role_scale if role_scale > 0.0 else float(TIERS[tier]["scale"])
	scale = Vector3.ONE * body * float(CREATURES[creature]["scale"])
	_collect_materials(model)


## Built in _enter_tree, NOT _ready. Children are made ready before their
## parent, so an AnimationPlayer created in the scene would resolve its
## "../Model" root against a node that did not exist yet and the rig would
## simply T-pose forever. _enter_tree on the parent runs first.
func _enter_tree() -> void:
	if model != null:
		return
	var packed: PackedScene = load(CREATURES[creature]["scene"])
	model = packed.instantiate()
	model.name = "Model"
	var v := get_node("Visual")
	v.add_child(model)
	v.move_child(model, 0)


## Keeps each creature's own imported material — texture and all — and only adds
## an emission channel for the hit flash and telegraph glow. Replacing the
## material outright is what made every monster an untextured silhouette.
func _collect_materials(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var base := mi.get_active_material(s)
			var m: StandardMaterial3D
			if base is StandardMaterial3D:
				m = (base as StandardMaterial3D).duplicate()
			else:
				m = StandardMaterial3D.new()
				m.albedo_color = _body_col
				m.roughness = 0.75
			m.emission_enabled = true
			m.emission = _accent
			m.emission_energy_multiplier = 0.05
			mi.set_surface_override_material(s, m)
			_mats.append(m)
			_base_cols.append(m.albedo_color)
	for c in n.get_children():
		_collect_materials(c)


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
		return

	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	if dist > 0.001:
		to_player /= dist

	var wish := Vector3.ZERO
	var step := _step()

	if role != Role.FREE:
		_scripted(delta, to_player, dist)
		return

	# While the player is pinned, everything else stops fighting and closes into
	# a ring to watch. It turns the grab into a staged moment instead of a free
	# hit for the whole field — and makes the release land harder.
	if player.get("grabbed") == true:
		_spectate(delta, to_player, dist)
		return

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

	_separate(delta)
	_update_animation()
	_apply_materials()


## Scripted actors move, animate and resolve on their own timeline.
func _scripted(delta: float, to_player: Vector3, dist: float) -> void:
	_role_t += delta
	var wish := Vector3.ZERO

	match role:
		Role.CHARGE:
			# Run for the player's flank, not their centre, so two chargers end
			# up on opposite arms rather than fighting for the same spot.
			if _hold_dir == Vector3.ZERO:
				_hold_dir = Vector3(-to_player.z, 0.0, to_player.x).normalized() * role_side
			var mark: Vector3 = player.global_position + _hold_dir * _hold_reach()
			var to_mark: Vector3 = mark - global_position
			to_mark.y = 0.0
			if to_mark.length() < 1.6:
				role = Role.HOLD
				_role_t = 0.0
				if player.has_method("set_grabbed"):
					player.set_grabbed(true)
			else:
				wish = to_mark.normalized() * move_speed * role_speed

		Role.HOLD:
			# They touch, then back off to arm's length. The grip is the beam,
			# not the body — standing inside the player reads as clipping.
			var mark2: Vector3 = player.global_position + _hold_dir * _hold_reach()
			global_position = global_position.lerp(mark2, 1.0 - exp(-9.0 * delta))
			velocity = Vector3.ZERO
			_update_tether()

		Role.STALK:
			if dist > reach * 0.95:
				wish = to_player * move_speed * role_speed
			else:
				role = Role.SMASH
				_role_t = 0.0
				_smash_hit = false
				Sfx.play_at(&"roar", global_position + Vector3.UP * 1.8)

		Role.SMASH:
			# Long wind-up, then one enormous connect.
			if not _smash_hit and _role_t >= 1.15:
				_smash_hit = true
				smashed.emit(self)
			if _role_t >= 2.2:
				role = Role.FREE

		Role.DONE:
			role = Role.FREE
		_:
			_clear_tether()

	var rate := 14.0
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

	match role:
		Role.HOLD:
			_travel(_atk_state(true))
		Role.SMASH:
			_travel("baseball")
		Role.STALK:
			# The limp. A looping clip, so speed is carried by movement not by
			# the animation.
			_travel("injured")
		_:
			_travel(_loco_state())
			anim_tree.set(_blend_path(), Vector2(velocity.x, velocity.z).length())
	_apply_materials()


## A short sprint while closing. Rare, brief, and the single biggest source of
## tension — distance stops being reliable safety.
## Physical collision stops overlap, but a crowd pressing on one point can lock
## up. A soft outward nudge keeps them shuffling instead of jamming.
func _separate(delta: float) -> void:
	var my_r: float = 0.5 * float(TIERS[tier]["scale"])
	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self or not other.is_alive():
			continue
		var d: Vector3 = global_position - other.global_position
		d.y = 0.0
		var dist := d.length()
		var min_d: float = my_r + 0.5 * float(TIERS[other.tier]["scale"])
		if dist > 0.001 and dist < min_d:
			# Position correction, NOT a velocity add. Adding to velocity every
			# frame with no delta and no cap compounds into metres per second and
			# sends a crowd flying — which is exactly what it did.
			var push: float = minf((min_d - dist), 0.5) * 6.0 				* (1.0 if tier <= other.tier else 0.35)
			global_position += d.normalized() * push * delta


## Forms a ring at watching distance. No attacks, no tokens held.
func _spectate(delta: float, to_player: Vector3, dist: float) -> void:
	_release_token()
	_combo_i = 0
	if state != State.CHASE:
		_set_state(State.CHASE)

	const RING := 6.5
	var tangent := Vector3(-to_player.z, 0.0, to_player.x) * _circle_side
	var keep := (dist - RING) * 1.1
	var wish := tangent * move_speed * 0.35 + to_player * keep

	velocity.x = move_toward(velocity.x, wish.x, 9.0 * delta)
	velocity.z = move_toward(velocity.z, wish.z, 9.0 * delta)
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	else:
		velocity.y = 0.0
	move_and_slide()

	if dist > 0.05:
		_facing = lerp_angle(_facing, atan2(to_player.x, to_player.z), 1.0 - exp(-turn_speed * delta))
		visual.rotation.y = _facing

	_separate(delta)
	_travel(_loco_state())
	anim_tree.set(_blend_path(), Vector2(velocity.x, velocity.z).length())
	_apply_materials()


## How far out a holder settles. Scaled by body size so a big one does not end
## up standing on top of the player.
func _hold_reach() -> float:
	return 2.4 * maxf(scale.x, 0.6)


## The energy link. Drawn from chest height to the player, rebuilt each frame,
## because the two ends move independently.
func _update_tether() -> void:
	if _tether == null:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.62, 0.18, 0.55)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var cm := CylinderMesh.new()
		cm.top_radius = 0.09
		cm.bottom_radius = 0.09
		cm.height = 1.0
		cm.radial_segments = 8
		_tether = MeshInstance3D.new()
		_tether.mesh = cm
		_tether.material_override = mat
		_tether.top_level = true      # world space: it must not inherit body scale
		add_child(_tether)

	var a: Vector3 = global_position + Vector3.UP * (1.3 * scale.y)
	var b: Vector3 = player.global_position + Vector3.UP * 1.1
	var mid := (a + b) * 0.5
	var dir := b - a
	var len := dir.length()
	if len < 0.05:
		return
	_tether.visible = true
	_tether.global_position = mid
	# Cylinders are built along +Y, so aim +Y down the link.
	_tether.global_basis = Basis(_axis_to(dir.normalized())).scaled(Vector3(1, len, 1))
	var m: StandardMaterial3D = _tether.material_override
	m.albedo_color.a = 0.35 + sin(_role_t * 11.0) * 0.18


func _axis_to(up: Vector3) -> Quaternion:
	var from := Vector3.UP
	if from.dot(up) > 0.9999:
		return Quaternion.IDENTITY
	if from.dot(up) < -0.9999:
		return Quaternion(Vector3.RIGHT, PI)
	return Quaternion(from.cross(up).normalized(), acos(clampf(from.dot(up), -1.0, 1.0)))


func _clear_tether() -> void:
	if _tether:
		_tether.visible = false


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
	# Anything above the smallest tier ignores the queue entirely. They are slow
	# and telegraph for a long time, so they stay readable — and it fixes the
	# guardians, who could be starved of tokens forever in a crowded fight.
	if tier >= 1:
		_has_token = true
		return true
	if _tokens <= 0:
		return false
	_tokens -= 1
	_has_token = true
	return true


func _release_token() -> void:
	if not _has_token:
		return
	_has_token = false
	if tier == 0:
		_tokens = mini(_tokens + 1, MAX_TOKENS)


static func reset_tokens() -> void:
	_tokens = MAX_TOKENS


# ---------------------------------------------------------------------------

func take_damage(amount: float, from: Vector3, knockback: float) -> void:
	if state == State.DEAD:
		return
	health -= amount
	_flash = 1.0

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
	# Only the heavy ones kick up ground dust, and far less than their arrival
	# did — a small one dying should not be an event.
	if tier >= 1:
		Vfx.dust(global_position + Vector3.UP * 0.15, 10 * tier)
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
			_travel(_atk_state(_combo_i % 2 == 1))
		_:
			_travel(_loco_state())
			anim_tree.set(_blend_path(), Vector2(velocity.x, velocity.z).length())


## Pumpkinhulks have their own walk and their own two attacks. Everything lives
## in one state machine; only the entry name changes.
func _loco_state() -> String:
	return "locomotion_pk" if creature == 1 else "locomotion"


func _atk_state(second: bool) -> String:
	if creature == 1:
		return "pk_attack2" if second else "pk_attack1"
	return "attack2" if second else "attack1"


func _blend_path() -> String:
	return "parameters/%s/blend_position" % _loco_state()


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
	var charged := role == Role.CHARGE or role == Role.HOLD
	var e := 0.05 + _flash * 2.2 + tele * 1.6 + (1.2 if _burst_t > 0.0 else 0.0) 		+ (0.9 + sin(_role_t * 9.0) * 0.35 if charged else 0.0)
	var col := _accent.lerp(Color(1.0, 0.15, 0.05), tele)
	if _burst_t > 0.0:
		col = Color(1.0, 0.9, 0.7)
	if role == Role.CHARGE or role == Role.HOLD:
		# Warm energy, not a light source — the scene glow amplifies this hard.
		col = Color(1.0, 0.62, 0.18)
	for i in _mats.size():
		var m := _mats[i]
		m.emission = col
		m.emission_energy_multiplier = e
		# Flash from the material's own colour, so textured skin is preserved.
		m.albedo_color = _base_cols[i].lerp(Color(1, 0.9, 0.9), _flash * 0.7)
