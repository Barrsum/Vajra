extends Node3D
## A dropped sphere. Walk near it and it comes to you.
##
## Two kinds. INGREDIENT feeds the world quota. HEALTH goes into a small carried
## stock the player spends manually — it is a decision, not a pickup.
##
## Collection is a distance check against a stored player reference rather than
## an Area3D, so it cannot be broken by a collision-layer mistake later, and the
## magnet radius is generous on purpose. Chasing pickups is not the game.

enum Kind { INGREDIENT, HEALTH }

@export var kind: Kind = Kind.INGREDIENT
@export var value := 1
@export var magnet_range := 6.0
@export var collect_range := 1.4
@export var lifetime := 45.0

var player: Node3D
var color := Color(0.55, 1.0, 0.72)

var _t := 0.0
var _age := 0.0
var _mesh: MeshInstance3D
var _glow: OmniLight3D
var _vel := Vector3.ZERO
var _settled := false
var _taken := false
## Set when the player's stock is full: the orb reaches them, is refused, and is
## thrown back out. Reads as "he tried and could not carry it".
var _reject_cd := 0.0


func _ready() -> void:
	if kind == Kind.HEALTH:
		color = Color(1.0, 0.22, 0.24)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.25
	mat.metallic = 0.1
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.2

	_mesh = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.32
	sm.height = 0.64
	sm.radial_segments = 12
	sm.rings = 8
	_mesh.mesh = sm
	_mesh.material_override = mat
	add_child(_mesh)

	# A small light so drops are findable in the dark world, where an emissive
	# sphere alone would read as a dot rather than an object.
	_glow = OmniLight3D.new()
	_glow.light_color = color
	_glow.light_energy = 2.0
	_glow.omni_range = 4.5
	add_child(_glow)

	# Pop out of the corpse rather than appearing.
	_vel = Vector3(randf_range(-2.0, 2.0), randf_range(3.5, 5.5), randf_range(-2.0, 2.0))


func _process(delta: float) -> void:
	if _taken:
		return
	_t += delta
	_age += delta
	_reject_cd = maxf(0.0, _reject_cd - delta)
	if _age > lifetime:
		queue_free()
		return

	if not _settled:
		_vel.y -= 16.0 * delta
		position += _vel * delta
		if position.y <= 0.55:
			position.y = 0.55
			_settled = true
			_vel = Vector3.ZERO
	else:
		# Bob and spin so it reads as collectable, not scenery.
		_mesh.position.y = sin(_t * 3.0) * 0.12
		_mesh.rotation.y += delta * 2.2

	if not is_instance_valid(player):
		return
	var to_player: Vector3 = player.global_position + Vector3.UP * 0.9 - global_position
	var dist := to_player.length()

	if dist < collect_range and _reject_cd <= 0.0:
		_collect()
	elif _settled and dist < magnet_range and _reject_cd <= 0.0:
		# Accelerate in as it gets closer, so the last stretch snaps.
		var pull := 1.0 - (dist / magnet_range)
		global_position += to_player.normalized() * (4.0 + pull * 16.0) * delta


func _collect() -> void:
	if kind == Kind.HEALTH:
		if not player.has_method("add_health_orb") or not player.add_health_orb():
			_reject()
			return
		_taken = true
		Sfx.play_at(&"impact_light", global_position, -6.0, 0.3)
		Vfx.sparks(global_position, Vector3.UP, false)
		queue_free()
		return

	_taken = true
	Game.add_drop(value)
	Sfx.play_at(&"impact_light", global_position, -8.0, 0.25)
	Vfx.sparks(global_position, Vector3.UP, false)
	queue_free()


## Refused because the stock is full. Thrown back out and left on the ground,
## so nothing is destroyed — it can be picked up once a slot frees.
func _reject() -> void:
	_reject_cd = 2.2
	_settled = false
	var away: Vector3 = global_position - player.global_position
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3.FORWARD
	_vel = away.normalized() * 5.0 + Vector3.UP * 4.5
	Sfx.play_at(&"dodge", global_position, -10.0, 0.4)
