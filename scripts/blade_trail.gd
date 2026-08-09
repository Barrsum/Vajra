extends MeshInstance3D
## Ribbon trail swept by the blade.
##
## Samples the blade's base and tip in world space each frame and rebuilds a
## triangle strip between the stored pairs. Nothing here is expensive — the whole
## effect is a dozen quads — but it does more for the feel of a swing than any
## amount of extra animation, because it makes the arc visible.

@export var max_points := 14
## Additive blending plus the environment glow compounds fast — these are much
## dimmer than they look, or the ribbon blooms into a white slab.
@export var color_hot := Color(0.40, 0.62, 0.95, 0.42)
@export var color_cold := Color(0.12, 0.28, 0.70, 0.0)

var _pts: Array[Array] = []      ## [base, tip] pairs, newest last
var _active := false
var _mesh := ImmediateMesh.new()


func _ready() -> void:
	mesh = _mesh
	# World space: the ribbon must not follow the arm once it is laid down.
	top_level = true
	global_transform = Transform3D.IDENTITY
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.disable_receive_shadows = true
	m.no_depth_test = false
	material_override = m


func set_active(v: bool) -> void:
	_active = v


func sample(base: Vector3, tip: Vector3) -> void:
	if not _active:
		return
	_pts.append([base, tip])
	while _pts.size() > max_points:
		_pts.pop_front()


func _process(_delta: float) -> void:
	# When the swing ends the ribbon drains from the tail rather than vanishing.
	if not _active and not _pts.is_empty():
		_pts.pop_front()

	_mesh.clear_surfaces()
	if _pts.size() < 2:
		return

	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in _pts.size():
		# Newest end is bright and opaque; the tail fades to nothing.
		var t := float(i) / float(_pts.size() - 1)
		var c := color_cold.lerp(color_hot, t * t)
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(_pts[i][0])
		_mesh.surface_set_color(Color(c.r, c.g, c.b, c.a * 0.35))
		_mesh.surface_add_vertex(_pts[i][1])
	_mesh.surface_end()
