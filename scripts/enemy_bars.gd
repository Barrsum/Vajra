extends Control
## Enemy health bars drawn in screen space.
##
## A billboarded 3D quad is the wrong tool for this. It inherits the enemy's
## scale, so a Colossus gets a bar three times wider than a Husk; it
## perspective-distorts toward the screen edges; and it shrinks with distance in
## a way that fights readability rather than helping it.
##
## Instead each bar is a real 2D Control, positioned every frame by projecting
## the enemy's head through the camera with `unproject_position`. Constant pixel
## size, axis-aligned at all times, and locked exactly above the head no matter
## where the camera is or how big the creature is.

const BAR_W := 58.0
const BAR_H := 7.0
const BORDER := 2.0
## Head clearance, in world units, before the enemy's own scale is applied.
const HEAD_OFFSET := 2.15
const MAX_DIST := 55.0

const GREEN := Color(0.30, 0.90, 0.35)
const YELLOW := Color(0.96, 0.84, 0.20)
const RED := Color(0.94, 0.20, 0.16)

var _widgets: Array[Control] = []
var _free: Array[Control] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _make_widget() -> Control:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var border := ColorRect.new()
	border.name = "Border"
	border.color = Color(0.02, 0.02, 0.02, 0.85)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(border)

	var track := ColorRect.new()
	track.name = "Track"
	track.color = Color(0.24, 0.24, 0.27, 0.9)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(track)

	var fill := ColorRect.new()
	fill.name = "Fill"
	fill.color = GREEN
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fill)

	add_child(root)
	_widgets.append(root)
	return root


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return

	# Recycle every widget, then claim one per visible enemy.
	_free = _widgets.duplicate()
	for w in _widgets:
		w.visible = false

	for e in get_tree().get_nodes_in_group("enemies"):
		if not e.has_method("is_alive") or not e.is_alive():
			continue

		var head: Vector3 = e.global_position + Vector3.UP * (HEAD_OFFSET * e.scale.y)
		# Behind the camera, unproject returns a mirrored point — it would draw
		# a bar on screen for something stood behind you.
		if cam.is_position_behind(head):
			continue
		var dist := cam.global_position.distance_to(head)
		if dist > MAX_DIST:
			continue

		var w: Control = _free.pop_back() if not _free.is_empty() else _make_widget()
		w.visible = true

		# Bigger creatures get a wider bar so importance reads at a glance, but
		# the width is a fixed pixel choice, not a consequence of world scale.
		var scale_mul: float = 1.0 + 0.35 * float(e.tier)
		var bw := BAR_W * scale_mul
		var bh := BAR_H * scale_mul
		var frac: float = clampf(e.health / maxf(e.max_health, 0.001), 0.0, 1.0)

		var p := cam.unproject_position(head)
		w.position = Vector2(round(p.x - bw * 0.5), round(p.y - bh * 0.5))
		w.size = Vector2(bw, bh)

		var border: ColorRect = w.get_node("Border")
		border.position = Vector2(-BORDER, -BORDER)
		border.size = Vector2(bw + BORDER * 2.0, bh + BORDER * 2.0)

		var track: ColorRect = w.get_node("Track")
		track.position = Vector2.ZERO
		track.size = Vector2(bw, bh)

		var fill: ColorRect = w.get_node("Fill")
		fill.position = Vector2.ZERO
		fill.size = Vector2(maxf(bw * frac, 1.0), bh)
		# Two-stage ramp: a single lerp across the full range never reads as
		# yellow at half.
		fill.color = YELLOW.lerp(GREEN, (frac - 0.5) * 2.0) if frac > 0.5 \
			else RED.lerp(YELLOW, frac * 2.0)

		# Fade the far ones out rather than popping them at the cutoff.
		var a: float = clampf(inverse_lerp(MAX_DIST, MAX_DIST * 0.6, dist), 0.25, 1.0)
		w.modulate.a = a
