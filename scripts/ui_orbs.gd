extends Control
## The health orb rack: five glass flasks with red liquid, gold collars.
##
## Replaces a row of asterisks. Drawn, like the health bar — a flask is a
## circle, a neck and a collar, which is a dozen draw calls and no art files.
##
## Empty flasks stay on screen as dark glass rather than disappearing. A rack
## that shrinks tells you how many you have; a rack that dims tells you that
## AND how many you are missing, which is the number that decides whether you
## go looking for one.

const GOLD := Color(0.85, 0.66, 0.28)
const GOLD_LIT := Color(1.00, 0.88, 0.55)
const GOLD_DARK := Color(0.34, 0.23, 0.08)
const GLASS := Color(0.14, 0.13, 0.16, 0.85)
const LIQUID := Color(0.90, 0.13, 0.10)
const LIQUID_LIT := Color(1.00, 0.52, 0.30)

## Flask body radius and the spacing between flasks. The control reserves
## RAD * 2 + 28: the extra is headroom for the neck and collar, which are drawn
## ABOVE the body centre and get clipped without it.
const RAD := 19.0
const STEP := 46.0

var have := 0
var cap := 5

var _t := 0.0
## Rises when an orb is spent or gained, and drives a brief flare on that
## flask. Without it the rack changes between frames and is easy to miss.
var _flash := 0.0
var _flash_i := -1


func _ready() -> void:
	custom_minimum_size = Vector2(STEP * float(cap) + 8.0, RAD * 2.0 + 28.0)
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 2.4)
	queue_redraw()


func set_orbs(n: int, c: int) -> void:
	if c != cap:
		cap = c
		custom_minimum_size = Vector2(STEP * float(cap) + 8.0, RAD * 2.0 + 28.0)
	if n != have:
		# Flash the flask that changed — the one gained, or the one spent.
		_flash_i = mini(n, cap - 1) if n > have else mini(have - 1, cap - 1)
		_flash = 1.0
	have = n


func _draw() -> void:
	for i in cap:
		var c := Vector2(RAD + 4.0 + STEP * float(i), RAD + 18.0)
		_draw_flask(c, i < have, i)


func _draw_flask(c: Vector2, full: bool, index: int) -> void:
	var flare := _flash if index == _flash_i else 0.0
	var lit := LIQUID.lerp(Color(1, 1, 1), flare * 0.55)

	# --- neck -------------------------------------------------------------
	# A tapered trapezoid from the shoulder of the body up to the collar,
	# drawn BEFORE the body so the body covers where they meet. The first
	# version drew a glass-coloured rectangle, which against a dark scene was
	# invisible — the collar read as a gold dash floating above a bead.
	var collar_y := c.y - RAD - 11.0
	var shoulder_y := c.y - RAD * 0.72
	var neck := PackedVector2Array([
		Vector2(c.x - RAD * 0.30, collar_y),
		Vector2(c.x + RAD * 0.30, collar_y),
		Vector2(c.x + RAD * 0.52, shoulder_y),
		Vector2(c.x - RAD * 0.52, shoulder_y),
	])
	draw_colored_polygon(neck, Color(0.30, 0.11, 0.10, 0.95) if full else GLASS)
	# Gold rails down each side of the neck.
	var rail := GOLD if full else GOLD_DARK
	draw_line(neck[0], neck[3], rail, 2.0)
	draw_line(neck[1], neck[2], rail, 2.0)

	# --- glow -------------------------------------------------------------
	if full:
		# Two soft rings. Cheaper and steadier than a particle, and it survives
		# being resized.
		var pulse := 1.0 + sin(_t * 2.6 + float(index)) * 0.10 + flare * 0.5
		draw_circle(c, RAD * 1.45 * pulse, Color(LIQUID.r, LIQUID.g, LIQUID.b, 0.12))
		draw_circle(c, RAD * 1.18 * pulse, Color(LIQUID.r, LIQUID.g, LIQUID.b, 0.17))

	# --- body -------------------------------------------------------------
	draw_circle(c, RAD, GLASS)
	if full:
		draw_circle(c, RAD - 2.5, lit.darkened(0.30))
		draw_circle(c, RAD - 5.0, lit)
		# Hot core offset toward the highlight, so it reads as a glowing volume
		# rather than a flat disc.
		draw_circle(c + Vector2(-RAD * 0.12, -RAD * 0.12), RAD * 0.44,
			LIQUID_LIT.lerp(Color(1, 1, 1), flare * 0.6))
	else:
		# Spent: dark glass with a little dried residue pooled at the bottom,
		# so the shape stays legible against a dark scene.
		draw_circle(c, RAD - 2.5, Color(0.10, 0.09, 0.11, 0.85))
		draw_circle(c + Vector2(0, RAD * 0.44), RAD * 0.34,
			Color(0.26, 0.09, 0.09, 0.5))

	# Gold rim, doubled: a dark line outside a bright one gives it thickness.
	draw_arc(c, RAD + 1.0, 0.0, TAU, 32, GOLD_DARK, 3.0, true)
	draw_arc(c, RAD, 0.0, TAU, 32, rail, 2.4, true)
	# Specular pip on the upper left of the glass.
	draw_circle(c + Vector2(-RAD * 0.40, -RAD * 0.42), 3.2,
		Color(1, 1, 1, 0.6 if full else 0.2))

	# --- collar -----------------------------------------------------------
	# Last, so it caps the neck cleanly.
	var cw := RAD * 0.62
	draw_rect(Rect2(c.x - cw, collar_y - 4.0, cw * 2.0, 7.0), GOLD_DARK)
	draw_rect(Rect2(c.x - cw, collar_y - 4.0, cw * 2.0, 3.0), rail)
	if full:
		draw_rect(Rect2(c.x - cw, collar_y - 4.0, cw * 2.0, 1.5), GOLD_LIT)
