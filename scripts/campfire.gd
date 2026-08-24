extends Node3D
## A campfire: stones, a raymarched flame, light, and a barrier.
##
## The barrier is the gameplay part. Fire deals no damage and has no trigger —
## instead a StaticBody3D cylinder sits around the flame on the same layers the
## ground uses, so the player and every creature simply walk into it and stop.
## Nothing has to check "am I in fire", nothing can be knocked through it, and
## a Colossus cannot body a small enemy into the flames. It is a wall that
## happens to be on fire.
##
## Two flame shaders are available. The raymarched one is genuinely volumetric
## and genuinely expensive, so it goes on the few large fires; the stylised one
## is a scrolling texture on a cone and goes on the small ones.

const FIRE_RAYMARCHED := preload("res://shaders/fire_raymarched.gdshader")
const FIRE_STYLIZED := preload("res://shaders/fire_stylized.gdshader")
const FxTextures := preload("res://scripts/fx_textures.gd")

## Radius of the no-go barrier. Set before adding to the tree.
var barrier_radius := 2.6
var flame_height := 2.6
var flame_width := 2.2
var volumetric := true
var light_energy := 7.0
var light_color := Color(1.0, 0.62, 0.26)

var _light: OmniLight3D
var _flicker := 0.0


func _ready() -> void:
	_stones()
	if volumetric:
		_volumetric_flame()
	else:
		_stylised_flame()
	_barrier()

	_light = OmniLight3D.new()
	_light.light_color = light_color
	_light.light_energy = light_energy
	_light.omni_range = barrier_radius * 9.0
	# Shadows off: a campfire ringed by trees would otherwise cost a full cube
	# shadow pass each, and the light is warm ambience rather than a key.
	_light.shadow_enabled = false
	add_child(_light)
	_light.position = Vector3(0, flame_height * 0.45, 0)

	_flicker = randf() * TAU


func _process(delta: float) -> void:
	# Firelight that does not move reads as a lamp. Two offset sine waves are
	# enough — a random walk flickers too evenly to look like burning.
	_flicker += delta
	var f := 1.0 + sin(_flicker * 7.3) * 0.08 + sin(_flicker * 2.1) * 0.05
	_light.light_energy = light_energy * f


## A ring of stones, so the fire sits in something rather than on the grass.
func _stones() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(global_position.x * 31.0) + int(global_position.z * 17.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.20, 0.19, 0.18)
	mat.roughness = 0.95

	var count := 11
	for i in count:
		var a := TAU * float(i) / float(count)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var s := rng.randf_range(0.4, 0.7)
		bm.size = Vector3(s, s * 0.75, s * 0.8)
		mi.mesh = bm
		mi.material_override = mat
		add_child(mi)
		mi.position = Vector3(cos(a), 0.16, sin(a)) * (barrier_radius * 0.72)
		mi.rotation.y = a + rng.randf_range(-0.4, 0.4)

	# Charred logs across the middle.
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.10, 0.07, 0.05)
	wood.roughness = 1.0
	for i in 3:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(barrier_radius * 1.1, 0.22, 0.22)
		mi.mesh = bm
		mi.material_override = wood
		add_child(mi)
		mi.position = Vector3(0, 0.2, 0)
		mi.rotation.y = TAU * float(i) / 3.0 + 0.4


## The volumetric flame. A quad the shader billboards and raymarches through.
func _volumetric_flame() -> void:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	# Generous enough to contain the flame from any angle — the shader marches
	# a box inside this, and anything the quad does not cover is clipped away.
	qm.size = Vector2(flame_width * 2.4, flame_height * 2.0)
	qm.orientation = PlaneMesh.FACE_Z
	mi.mesh = qm

	var m := ShaderMaterial.new()
	m.shader = FIRE_RAYMARCHED
	m.set_shader_parameter("sample_noise", FxTextures.fire_volume())
	m.set_shader_parameter("billboard", true)
	m.set_shader_parameter("fire_height", flame_height)
	m.set_shader_parameter("fire_width", flame_width)
	# Six steps is the author's recommendation and it holds up; jitter buys
	# most of the quality back at low step counts.
	m.set_shader_parameter("raymarch_steps", 6)
	m.set_shader_parameter("sample_jitter", true)
	# 9.0 blew the flame out to a featureless white ball once the scene glow
	# got hold of it. At 2.6 the colour ramp inside the fire is actually
	# visible, and the bloom still does its job.
	m.set_shader_parameter("emission_strength", 2.6)
	m.set_shader_parameter("noise_threshold", 0.46)
	m.set_shader_parameter("core_glow_multiplier", 9.0)
	mi.material_override = m
	# The shader displaces the quad toward the camera, so Godot's own culling
	# box is wrong. Grow it or the fire pops out at the screen edge.
	mi.extra_cull_margin = flame_height * 2.0
	add_child(mi)
	mi.position = Vector3(0, 0.25, 0)


## The cheap flame: scrolling noise on crossed quads.
##
## Quads, not a cone. On a cylinder U runs around the circumference, so every
## texture the shader samples wrapped the flame in bands rather than running up
## it — the first attempt came out looking like a traffic cone. On a quad the
## UV is unambiguous: v is height, u is across. Two of them crossed read as
## volume from any angle for the price of four triangles.
func _stylised_flame() -> void:
	var m := ShaderMaterial.new()
	m.shader = FIRE_STYLIZED
	m.set_shader_parameter("Noise_Texture", FxTextures.flame_noise())
	m.set_shader_parameter("Coloring_Texture", FxTextures.fire_ramp())
	m.set_shader_parameter("UV_Random", FxTextures.uv_random())
	m.set_shader_parameter("Alpha_Texture", FxTextures.flame_alpha())
	m.set_shader_parameter("Vertex_Noise_Texture", FxTextures.flame_noise())
	m.set_shader_parameter("Vertex_Noise_Power_Texture", FxTextures.tail_power())
	m.set_shader_parameter("Tail_Vertex_Noise_Texture", FxTextures.flame_noise())
	m.set_shader_parameter("Tail_Vertex_Noise_Power_Texture", FxTextures.tail_power())
	# Scroll upward. Speed.y also drives the vertex stage, so keep it modest or
	# the silhouette shakes rather than flickers.
	m.set_shader_parameter("Speed", Vector2(0.06, -0.55))
	m.set_shader_parameter("Emmision_Power", 2.2)
	m.set_shader_parameter("Twist_Power", 0.15)
	m.set_shader_parameter("Random_Power", 0.05)
	m.set_shader_parameter("Tail_Displace_Power", 0.02)
	m.set_shader_parameter("Displace_Power", 0.05)
	m.set_shader_parameter("Fresnel_Power", 3.0)
	m.set_shader_parameter("Fresnel_Color", Color(1.0, 0.66, 0.26))

	for i in 2:
		var mi := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(flame_width * 1.3, flame_height)
		mi.mesh = qm
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = flame_height
		add_child(mi)
		mi.position = Vector3(0, flame_height * 0.5 + 0.15, 0)
		mi.rotation.y = PI * 0.5 * float(i)


## The reason nothing walks into the fire. A plain static cylinder on the same
## layer as the world, so it stops the player and every creature without any of
## them knowing a campfire exists.
func _barrier() -> void:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = barrier_radius
	shape.height = 6.0
	col.shape = shape
	body.add_child(col)
	add_child(body)
	col.position = Vector3(0, 3.0, 0)
