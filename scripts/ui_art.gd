extends RefCounted
## Shared drawing language for the menus, level select and results screen.
##
## Every screen in the reference art is the same handful of shapes — a gold
## diamond, a thin rule with a diamond in the middle, a dark panel with a gold
## border, a crest. Rather than four copies of each, they live here as static
## functions taking the CanvasItem to draw into.
##
## No class_name: registration has silently failed under --headless in this
## project twice. Callers preload it.

const GOLD := Color(0.92, 0.72, 0.30)
const GOLD_LIT := Color(1.00, 0.90, 0.62)
const GOLD_DARK := Color(0.42, 0.29, 0.10)
const GOLD_FAINT := Color(0.30, 0.21, 0.09)
const PANEL := Color(0.045, 0.040, 0.038, 0.90)
const PANEL_LIT := Color(0.10, 0.085, 0.06, 0.94)
const INK := Color(0.90, 0.87, 0.80)
const INK_DIM := Color(0.62, 0.58, 0.52)
const BG := Color(0.028, 0.024, 0.022)
const OK := Color(0.42, 0.88, 0.50)


static func diamond(ci: CanvasItem, c: Vector2, r: float, col: Color,
		squash := 0.62) -> void:
	ci.draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -r), c + Vector2(r * squash, 0),
		c + Vector2(0, r), c + Vector2(-r * squash, 0),
	]), col)


## A thin rule with a diamond set into the middle — the divider used under
## every heading in the reference.
static func rule(ci: CanvasItem, c: Vector2, half_w: float, a := 1.0) -> void:
	var col := Color(GOLD_DARK.r, GOLD_DARK.g, GOLD_DARK.b, a)
	var gap := 14.0
	ci.draw_line(c + Vector2(-half_w, 0), c + Vector2(-gap, 0), col, 1.0)
	ci.draw_line(c + Vector2(gap, 0), c + Vector2(half_w, 0), col, 1.0)
	diamond(ci, c, 6.0, Color(GOLD.r, GOLD.g, GOLD.b, a))


## Dark plate with a gold border. `lit` is the selected/highlighted variant.
static func panel(ci: CanvasItem, r: Rect2, a := 1.0, lit := false) -> void:
	var bg := PANEL_LIT if lit else PANEL
	ci.draw_rect(r, Color(bg.r, bg.g, bg.b, bg.a * a))
	var edge := GOLD if lit else GOLD_FAINT
	ci.draw_rect(r, Color(edge.r, edge.g, edge.b, a), false, 2.0 if lit else 1.0)
	if lit:
		# A second, softer line just outside reads as a glow without a shader.
		ci.draw_rect(r.grow(3.0),
			Color(GOLD.r, GOLD.g, GOLD.b, 0.22 * a), false, 2.0)


## Centred text with a dark outline, so it survives any background.
static func text(ci: CanvasItem, font: Font, pos: Vector2, s: String, fs: int,
		col: Color, centred := true, outline := true) -> float:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := pos - Vector2(w * 0.5 if centred else 0.0, 0.0)
	if outline:
		for o in [Vector2(-1.5, 0), Vector2(1.5, 0), Vector2(0, -1.5), Vector2(0, 1.5)]:
			ci.draw_string(font, p + o, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				Color(0.02, 0.015, 0.01, col.a * 0.85))
	ci.draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	return w


## The winged-sword crest. Used full size on the results screen and small as
## the mark above the title.
static func crest(ci: CanvasItem, c: Vector2, scale: float, a: float,
		rays := true, t := 0.0) -> void:
	if rays:
		var n := 18
		for i in n:
			var ang := TAU * float(i) / float(n) + t * 0.05
			var len_r := scale * 3.4 * (0.55 + 0.45 * sin(float(i) * 2.3))
			var sp := 0.020
			ci.draw_colored_polygon(PackedVector2Array([
				c,
				c + Vector2(sin(ang - sp), cos(ang - sp)) * len_r,
				c + Vector2(sin(ang + sp), cos(ang + sp)) * len_r,
			]), Color(GOLD.r, GOLD.g, GOLD.b, 0.09 * a))

	for side_i in 2:
		var side := -1.0 if side_i == 0 else 1.0
		for i in 5:
			var f := float(i) / 4.0
			var root := c + Vector2(side * scale * 0.30, -scale * 0.30 + f * scale * 0.40)
			var span := scale * (0.95 + (1.0 - f) * 1.15)
			var tip := root + Vector2(side * span,
				-scale * 0.50 - (1.0 - f) * scale * 0.36 + f * scale * 0.55)
			var thick := scale * 0.24 * (1.0 - f * 0.45)
			ci.draw_colored_polygon(PackedVector2Array([
				root + Vector2(0.0, -thick * 0.5),
				tip,
				root + Vector2(0.0, thick * 0.9),
			]), Color(GOLD.r, GOLD.g, GOLD.b, (0.92 - f * 0.30) * a))

	# Sword: blade, crossguard, pommel.
	var bh := scale
	ci.draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -bh),
		c + Vector2(scale * 0.12, -bh * 0.72),
		c + Vector2(scale * 0.12, bh * 0.34),
		c + Vector2(-scale * 0.12, bh * 0.34),
		c + Vector2(-scale * 0.12, -bh * 0.72),
	]), Color(GOLD_LIT.r, GOLD_LIT.g, GOLD_LIT.b, a))
	ci.draw_rect(Rect2(c.x - scale * 0.48, c.y - bh * 0.26, scale * 0.96, scale * 0.11),
		Color(GOLD.r, GOLD.g, GOLD.b, a))
	diamond(ci, c + Vector2(0, bh * 0.44), scale * 0.17,
		Color(GOLD.r, GOLD.g, GOLD.b, a), 1.0)


## Vertical gradient, drawn as horizontal bands. Godot has no draw_gradient,
## and a GradientTexture2D per card would be a resource per world.
static func vgrad(ci: CanvasItem, r: Rect2, top: Color, bottom: Color,
		bands := 24) -> void:
	var bh := r.size.y / float(bands)
	for i in bands:
		var f := float(i) / float(bands - 1)
		ci.draw_rect(Rect2(r.position.x, r.position.y + bh * float(i),
			r.size.x, bh + 1.0), top.lerp(bottom, f))


## Corner brackets, the "selected" mark on the level cards.
static func corners(ci: CanvasItem, r: Rect2, len_c: float, col: Color,
		width := 3.0) -> void:
	var p := r.position
	var s := r.size
	ci.draw_line(p, p + Vector2(len_c, 0), col, width)
	ci.draw_line(p, p + Vector2(0, len_c), col, width)
	ci.draw_line(p + Vector2(s.x, 0), p + Vector2(s.x - len_c, 0), col, width)
	ci.draw_line(p + Vector2(s.x, 0), p + Vector2(s.x, len_c), col, width)
	ci.draw_line(p + Vector2(0, s.y), p + Vector2(len_c, s.y), col, width)
	ci.draw_line(p + Vector2(0, s.y), p + Vector2(0, s.y - len_c), col, width)
	ci.draw_line(p + s, p + s - Vector2(len_c, 0), col, width)
	ci.draw_line(p + s, p + s - Vector2(0, len_c), col, width)


## Button styling shared by every screen, so a button looks the same wherever
## it appears.
static func style_button(b: Button, primary := false, h := 52.0,
		fs := 19) -> void:
	b.custom_minimum_size = Vector2(b.custom_minimum_size.x, h)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", fs)
	b.add_theme_color_override("font_color", GOLD_LIT if primary else INK)
	b.add_theme_color_override("font_hover_color", GOLD_LIT)
	b.add_theme_color_override("font_focus_color", GOLD_LIT)
	b.add_theme_color_override("font_disabled_color", Color(0.4, 0.38, 0.35))

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.055, 0.048, 0.042, 0.92)
	sb.border_color = GOLD if primary else GOLD_FAINT
	sb.set_border_width_all(2 if primary else 1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	b.add_theme_stylebox_override("normal", sb)

	var hov := sb.duplicate()
	hov.bg_color = Color(0.13, 0.10, 0.045, 0.95)
	hov.border_color = GOLD_LIT
	hov.set_border_width_all(2)
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("focus", hov)
	b.add_theme_stylebox_override("pressed", hov)

	var dis := sb.duplicate()
	dis.bg_color = Color(0.04, 0.038, 0.036, 0.85)
	dis.border_color = Color(0.16, 0.15, 0.14)
	b.add_theme_stylebox_override("disabled", dis)
