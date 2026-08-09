extends Node3D
## An ingredient sphere dropped on death. Walk near it and it comes to you.
##
## Collection is a distance check against a stored player reference rather than
## an Area3D, so it cannot be broken by a collision-layer mistake later — and the
## magnet radius is generous on purpose. Chasing pickups is not the game.

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


func _ready() -> void:
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
	if _age > lifetime:
		queue_free()
		return

	if not _settled:
		_vel.y -= 16.0 * delta
		position += _vel * delta
		if position.y <= 0.55:
			position.y = 0.55
			_settled = true
	else:
		# Bob and spin so it reads as collectable, not scenery.
		_mesh.position.y = sin(_t * 3.0) * 0.12
		_mesh.rotation.y += delta * 2.2

	if not is_instance_valid(player):
		return
	var to_player: Vector3 = player.global_position + Vector3.UP * 0.9 - global_position
	var dist := to_player.length()

	if dist < collect_range:
		_collect()
	elif _settled and dist < magnet_range:
		# Accelerate in as it gets closer, so the last stretch snaps.
		var pull := 1.0 - (dist / magnet_range)
		global_position += to_player.normalized() * (4.0 + pull * 16.0) * delta


func _collect() -> void:
	_taken = true
	Game.add_drop(value)
	Sfx.play_at(&"impact_light", global_position, -8.0, 0.25)
	Vfx.sparks(global_position, Vector3.UP, false)
	queue_free()
