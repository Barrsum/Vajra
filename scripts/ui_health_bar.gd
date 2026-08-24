extends Control
## The ornate health bar: gold frame, gem finial, green fill, numbers inside.
##
## Drawn rather than textured. A nine-patch would need art files, would not
## recolour, and would blur at other resolutions — everything here is geometry,
## so the same code gives a crisp bar at any size and any palette.
##
## Two fills, not one. `_shown` is the green bar and snaps to the real value
## instantly; `_ghost` is the pale red behind it and chases down over about a
## second. The gap between them is how you read *how hard* something just hit
## you, which a single bar cannot show — by the time you look at it, it has
## already moved.

const GOLD := Color(0.85, 0.66, 0.28)
const GOLD_LIT := Color(1.00, 0.86, 0.52)
const GOLD_DARK := Color(0.38, 0.26, 0.09)
const TRACK := Color(0.06, 0.05, 0.05, 0.88)
const GHOST := Color(0.85, 0.24, 0.20, 0.75)

## Fill colours, high to low. Same two-stage ramp the enemy bars use, so a
## player bar and a creature bar are read the same way.
const HI := Color(0.42, 0.90, 0.32)
const MID := Color(0.95, 0.80, 0.22)
const LOW := Color(0.92, 0.24, 0.18)

## Width of the diamond finial on the left, and the gap after it.
const GEM := 26.0
const GEM_GAP := 7.0

@export var show_numbers := true

var value := 1.0        ## 0..1, the real health fraction
var current := 0.0
var maximum := 0.0

var _shown := 1.0
var _ghost := 1.0
var _pulse := 0.0


func _ready() -> void:
	set_process(true)
	_shown = value
	_ghost = value


func _process(delta: float) -> void:
	_shown = value
	# Chase down only. A heal should read instantly; damage is what wants the
	# trailing bar behind it.
	if _ghost > _shown:
		_ghost = maxf(_shown, _ghost - delta * 0.55)
	else:
		_ghost = _shown
	# The bar breathes when you are nearly dead. Cheap, and it catches the eye
	# without another element on screen.
	if _shown < 0.28:
		_pulse += delta
	else:
		_pulse = 0.0
	queue_redraw()


func set_health(hp: float, hp_max: float) -> void:
	current = hp
	maximum = hp_max
	value = clampf(hp / maxf(hp_max, 0.001), 0.0, 1.0)


func _fill_color() -> Color:
	if _shown > 0.55:
		return HI
	if _shown > 0.25:
		return HI.lerp(MID, inverse_lerp(0.55, 0.25, _shown))
	return MID.lerp(LOW, inverse_lerp(0.25, 0.0, _shown))


func _draw() -> void:
	var h := size.y
	var bar_x := GEM + GEM_GAP
	var bar_w := maxf(size.x - bar_x, 8.0)
	var r := Rect2(bar_x, 0.0, bar_w, h)

	_draw_gem(Vector2(GEM * 0.5, h * 0.5), GEM * 0.5)

	# Track, inset one pixel so the frame sits proud of it.
	draw_rect(r.grow(-1.0), TRACK)

	# Ghost first, so the live fill draws over it.
	if _ghost > _shown + 0.001:
		draw_rect(Rect2(r.position.x + 2.0, 2.0,
			(r.size.x - 4.0) * _ghost, h - 4.0), GHOST)

	var col := _fill_color()
	if _pulse > 0.0:
		col = col.lerp(Color(1, 1, 1), (sin(_pulse * 7.0) * 0.5 + 0.5) * 0.35)

	var fw := (r.size.x - 4.0) * _shown
	if fw > 1.0:
		var fr := Rect2(r.position.x + 2.0, 2.0, fw, h - 4.0)
		draw_rect(fr, col)
		# A brighter band along the top third reads as a lit, rounded surface
		# without needing a gradient texture.
		draw_rect(Rect2(fr.position.x, fr.position.y, fr.size.x, fr.size.y * 0.34),
			col.lightened(0.32))
		# and a darker one along the bottom.
		draw_rect(Rect2(fr.position.x, fr.position.y + fr.size.y * 0.74,
			fr.size.x, fr.size.y * 0.26), col.darkened(0.28))
		# Bright leading edge, so the end of the bar has an edge to catch.
		draw_rect(Rect2(fr.position.x + fr.size.x - 2.0, fr.position.y, 2.0, fr.size.y),
			col.lightened(0.6))

	# Frame: a dark line outside a gold one, which is what gives it weight.
	draw_rect(r.grow(1.0), GOLD_DARK, false, 2.0)
	draw_rect(r, GOLD, false, 2.0)
	# Top highlight on the frame itself.
	draw_line(r.position + Vector2(1, 1), r.position + Vector2(r.size.x - 1, 1),
		GOLD_LIT, 1.0)

	if show_numbers and maximum > 0.0:
		var font := ThemeDB.fallback_font
		var fs := int(clampf(h * 0.62, 11.0, 18.0))
		var txt := "%d / %d" % [roundi(current), roundi(maximum)]
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos := Vector2(r.position.x + r.size.x - tw - 8.0,
			h * 0.5 + float(fs) * 0.36)
		# Outline by overdraw: the fill behind the numbers changes colour, and
		# an outline is what keeps them legible against all of it.
		for o in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
			draw_string(font, pos + o, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				Color(0, 0, 0, 0.85))
		draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(1, 1, 1, 0.95))


## The diamond finial that caps the left end.
func _draw_gem(c: Vector2, rad: float) -> void:
	var outer := PackedVector2Array([
		c + Vector2(0, -rad), c + Vector2(rad, 0),
		c + Vector2(0, rad), c + Vector2(-rad, 0),
	])
	draw_colored_polygon(outer, GOLD_DARK)
	var inner := PackedVector2Array([
		c + Vector2(0, -rad * 0.62), c + Vector2(rad * 0.62, 0),
		c + Vector2(0, rad * 0.62), c + Vector2(-rad * 0.62, 0),
	])
	draw_colored_polygon(inner, GOLD)
	var core := PackedVector2Array([
		c + Vector2(0, -rad * 0.28), c + Vector2(rad * 0.28, 0),
		c + Vector2(0, rad * 0.28), c + Vector2(-rad * 0.28, 0),
	])
	draw_colored_polygon(core, GOLD_LIT)
