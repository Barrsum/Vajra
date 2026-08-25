extends Control
## The results screen. Draws over the live 3D scene — there is no background
## here beyond a soft vignette, because the frame behind it is the last frame
## of the outro and that is the point.
##
## Everything is drawn: crest, laurel, panels, medals. The reference art is a
## painted mock-up, and chasing it with image files would mean art that cannot
## recolour per world. Level 1 to 3 will want their own palette on the same
## layout, so the palette is four constants at the top.
##
## Panels fade in staggered rather than together. All at once reads as a screen
## appearing; staggered reads as a result being tallied, which is what the
## moment is.

const GOLD := Color(0.92, 0.72, 0.30)
const GOLD_LIT := Color(1.00, 0.90, 0.62)
const GOLD_DARK := Color(0.42, 0.29, 0.10)
const PANEL := Color(0.045, 0.040, 0.035, 0.88)
const INK := Color(0.88, 0.85, 0.78)
const INK_DIM := Color(0.66, 0.62, 0.55)

## Grade thresholds, best first. Each row scores independently and the rank is
## the average, so one bad category cannot sink an otherwise clean run.
const GRADES := ["S", "A", "B", "C", "D"]

var stats := {}
var title := "VICTORY"
var subtitle := "THE LONG NIGHT"

var _t := 0.0
var _rows: Array = []
var _grade_rows: Array = []
var _rank := "S"


signal chose(what: String)


func _ready() -> void:
	# ...AND offsets. set_anchors_preset alone keeps the current offsets, which
	# on a freshly constructed Control means a zero-sized rect — the whole
	# screen drew nothing and the zero-size guard below silently hid it.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The panel itself ignores the mouse; only the buttons take it. Otherwise
	# a full-rect Control swallows every click before the buttons see it.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	_build_buttons()


## Its own buttons, anchored bottom-centre, rather than the shared overlay's.
## That overlay centres its rows, which on this layout puts them straight
## through the middle of the crest.
func _build_buttons() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(row)
	# BOTTOM_WIDE with offsets: full width, pinned above the bottom edge. A
	# CENTER_BOTTOM preset without offsets leaves the container zero-sized and
	# the buttons never appear at all.
	row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	row.offset_top = -104.0
	row.offset_bottom = -46.0

	_mk(row, "LEVEL SELECT", "select", false)
	_mk(row, "MAIN MENU", "menu", true)


func _mk(row: HBoxContainer, label: String, id: String, primary: bool) -> void:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(260, 52)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", 19)
	b.add_theme_color_override("font_color", GOLD_LIT if primary else INK)
	b.add_theme_color_override("font_hover_color", GOLD_LIT)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.045, 0.04, 0.92)
	sb.border_color = GOLD if primary else GOLD_DARK
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(3)
	b.add_theme_stylebox_override("normal", sb)

	var hov := sb.duplicate()
	hov.bg_color = Color(0.12, 0.09, 0.04, 0.95)
	hov.border_color = GOLD_LIT
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("focus", hov)
	b.add_theme_stylebox_override("pressed", hov)

	b.pressed.connect(func() -> void: chose.emit(id))
	row.add_child(b)
	if primary:
		b.call_deferred("grab_focus")


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


## Called once when the screen opens. Computes the grades, then never changes.
func build(s: Dictionary, world_name: String) -> void:
	stats = s
	subtitle = world_name
	_t = 0.0

	var mins := int(s.get("time", 0.0)) / 60
	var secs := int(s.get("time", 0.0)) % 60

	_rows = [
		["Time Elapsed", "%02d:%02d" % [mins, secs]],
		["Enemies Defeated", str(int(s.get("kills", 0)))],
		["Damage Dealt", _comma(int(s.get("dealt", 0.0)))],
		["Damage Taken", _comma(int(s.get("taken", 0.0)))],
		["Max Combo", str(int(s.get("combo", 0)))],
		["Health Potions Used", "%d / %d" % [
			int(s.get("potions", 0)), int(s.get("potion_cap", 5))]],
	]

	# Each grade is a threshold ladder. The numbers are first-pass and want
	# tuning against real runs, but the shape is right: fast, untouched, and
	# efficient with potions all score well independently.
	_grade_rows = [
		["Clear Time", _grade(s.get("time", 0.0), [180.0, 300.0, 450.0, 600.0])],
		["Damage Taken", _grade(s.get("taken", 0.0), [50.0, 200.0, 400.0, 700.0])],
		["Enemies Defeated", _grade_high(s.get("kills", 0), [40, 30, 20, 10])],
		["Core Shards Collected", _grade_high(
			s.get("collected", 0), [s.get("needed", 1), 1, 1, 1])],
		["Health Potions Used", _grade(s.get("potions", 0), [0, 1, 3, 5])],
	]

	var total := 0
	for r in _grade_rows:
		total += GRADES.find(String(r[1]))
	_rank = GRADES[clampi(int(round(float(total) / float(_grade_rows.size()))),
		0, GRADES.size() - 1)]


## Lower is better.
func _grade(v: float, thresholds: Array) -> String:
	for i in thresholds.size():
		if v <= float(thresholds[i]):
			return GRADES[i]
	return GRADES[GRADES.size() - 1]


## Higher is better.
func _grade_high(v: float, thresholds: Array) -> String:
	for i in thresholds.size():
		if v >= float(thresholds[i]):
			return GRADES[i]
	return GRADES[GRADES.size() - 1]


func _comma(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out


func _fade(delay: float, span := 0.45) -> float:
	return clampf((_t - delay) / span, 0.0, 1.0)


func _draw() -> void:
	var w := size.x
	var h := size.y
	# Headless and the first frame after add_child both hand this a zero-sized
	# rect. Every font size here is derived from width, and a font size of 0 is
	# an engine error rather than an invisible string.
	if w < 64.0 or h < 64.0:
		return
	var font := ThemeDB.fallback_font

	# A vignette so the panels have something to sit against without hiding
	# the scene. Four edge bands, cheaper than a texture and it scales.
	var dim := _fade(0.0, 0.8) * 0.55
	draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, dim * 0.45))

	_draw_crest(Vector2(w * 0.5, h * 0.20), w, font)

	# Left: performance and rank.
	var lf := _fade(0.55)
	if lf > 0.01:
		_draw_performance(Rect2(w * 0.055, h * 0.34, w * 0.19, h * 0.42), font, lf)

	# Right: summary, stats, rewards.
	var rx := w * 0.755
	var rw := w * 0.19
	var f1 := _fade(0.35)
	if f1 > 0.01:
		_draw_summary(Rect2(rx, h * 0.13, rw, h * 0.12), font, f1)
	var f2 := _fade(0.45)
	if f2 > 0.01:
		_draw_stats(Rect2(rx, h * 0.29, rw, h * 0.25), font, f2)
	var f3 := _fade(0.70)
	if f3 > 0.01:
		_draw_rewards(Rect2(rx, h * 0.57, rw, h * 0.20), font, f3)
	var f4 := _fade(0.90)
	if f4 > 0.01:
		_draw_flavour(Rect2(rx, h * 0.82, rw, h * 0.12), font, f4)


# --- crest --------------------------------------------------------------------

func _draw_crest(c: Vector2, w: float, font: Font) -> void:
	var f := _fade(0.15, 0.6)
	if f < 0.01:
		return
	var a := f

	# Rays behind the title. Drawn as thin triangles fanning from the centre,
	# which is enough to suggest the painted sunburst without a texture.
	var rays := 18
	for i in rays:
		var ang := TAU * float(i) / float(rays) + _t * 0.06
		var len_r := (w * 0.19) * (0.55 + 0.45 * sin(float(i) * 2.3))
		var spread := 0.022
		draw_colored_polygon(PackedVector2Array([
			c,
			c + Vector2(sin(ang - spread), cos(ang - spread)) * len_r,
			c + Vector2(sin(ang + spread), cos(ang + spread)) * len_r,
		]), Color(GOLD.r, GOLD.g, GOLD.b, 0.10 * a))

	# Wings: long tapered feathers sweeping out and up from behind the sword.
	# The first pass drew them short and in the dark gold, which against a dark
	# scene left the crest reading as a bare cross.
	for side_i in 2:
		var side := -1.0 if side_i == 0 else 1.0
		for i in 6:
			var t := float(i) / 5.0
			var root := c + Vector2(side * w * 0.016, -w * 0.016 + t * w * 0.022)
			var span := w * 0.052 + (1.0 - t) * w * 0.062
			var rise := -w * 0.026 - (1.0 - t) * w * 0.020
			var tip := root + Vector2(side * span, rise + t * w * 0.030)
			var thick := (w * 0.013) * (1.0 - t * 0.45)
			# Each feather is a quad: a broad root narrowing to a point.
			draw_colored_polygon(PackedVector2Array([
				root + Vector2(0.0, -thick * 0.5),
				tip,
				root + Vector2(0.0, thick * 0.9),
			]), Color(GOLD.r, GOLD.g, GOLD.b, (0.92 - t * 0.30) * a))
			# A lighter inner edge, so the feathers separate from each other.
			draw_line(root, tip,
				Color(GOLD_LIT.r, GOLD_LIT.g, GOLD_LIT.b, (0.55 - t * 0.25) * a), 1.5)

	# The sword: blade, crossguard, pommel.
	var bh := w * 0.055
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -bh),
		c + Vector2(w * 0.006, -bh * 0.72),
		c + Vector2(w * 0.006, bh * 0.30),
		c + Vector2(-w * 0.006, bh * 0.30),
		c + Vector2(-w * 0.006, -bh * 0.72),
	]), Color(GOLD_LIT.r, GOLD_LIT.g, GOLD_LIT.b, a))
	draw_rect(Rect2(c.x - w * 0.026, c.y - bh * 0.30, w * 0.052, w * 0.006),
		Color(GOLD.r, GOLD.g, GOLD.b, a))
	draw_circle(c + Vector2(0, bh * 0.38), w * 0.008,
		Color(GOLD.r, GOLD.g, GOLD.b, a))

	# VICTORY.
	var fs := int(w * 0.052)
	var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var tp := Vector2(c.x - tw * 0.5, c.y + w * 0.075)
	for o in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2)]:
		draw_string(font, tp + o, title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(0.12, 0.07, 0.02, 0.9 * a))
	draw_string(font, tp, title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		Color(GOLD_LIT.r, GOLD_LIT.g, GOLD_LIT.b, a))

	# World name, then COMPLETE.
	var f2 := _fade(0.4, 0.5)
	if f2 > 0.01:
		var sfs := int(w * 0.020)
		var sw := font.get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs).x
		draw_string(font, Vector2(c.x - sw * 0.5, c.y + w * 0.108), subtitle,
			HORIZONTAL_ALIGNMENT_LEFT, -1, sfs,
			Color(GOLD.r, GOLD.g, GOLD.b, f2))
		var cfs := int(w * 0.014)
		var cw := font.get_string_size("COMPLETE", HORIZONTAL_ALIGNMENT_LEFT, -1, cfs).x
		draw_string(font, Vector2(c.x - cw * 0.5, c.y + w * 0.132), "COMPLETE",
			HORIZONTAL_ALIGNMENT_LEFT, -1, cfs,
			Color(0.62, 0.92, 0.70, f2))

		# Three gem pips under the title.
		for i in 3:
			var gx := c.x + (float(i) - 1.0) * w * 0.030
			var gy := c.y + w * 0.155
			_diamond(Vector2(gx, gy), w * 0.010,
				Color(GOLD.r, GOLD.g, GOLD.b, f2))


func _diamond(c: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -r), c + Vector2(r * 0.62, 0),
		c + Vector2(0, r), c + Vector2(-r * 0.62, 0),
	]), col)


# --- panels -------------------------------------------------------------------

func _panel(r: Rect2, a: float, heading: String, font: Font) -> float:
	draw_rect(r, Color(PANEL.r, PANEL.g, PANEL.b, PANEL.a * a))
	draw_rect(r, Color(GOLD_DARK.r, GOLD_DARK.g, GOLD_DARK.b, a), false, 2.0)
	var fs := int(clampf(r.size.y * 0.10, 12.0, 18.0))
	if heading != "":
		var tw := font.get_string_size(heading, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(r.position.x + r.size.x * 0.5 - tw * 0.5,
			r.position.y + fs + 8.0), heading, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(GOLD.r, GOLD.g, GOLD.b, a))
		var uy := r.position.y + fs + 16.0
		draw_line(Vector2(r.position.x + 12.0, uy),
			Vector2(r.position.x + r.size.x - 12.0, uy),
			Color(GOLD_DARK.r, GOLD_DARK.g, GOLD_DARK.b, a * 0.9), 1.0)
		return uy + 14.0
	return r.position.y + 12.0


## One label-left, value-right row. Every panel is built from these.
func _row(font: Font, x0: float, x1: float, y: float, label: String,
		value: String, a: float, fs: int, val_col := GOLD) -> void:
	draw_string(font, Vector2(x0, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		Color(INK.r, INK.g, INK.b, a))
	var vw := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2(x1 - vw, y), value, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		Color(val_col.r, val_col.g, val_col.b, a))


func _draw_summary(r: Rect2, font: Font, a: float) -> void:
	var y := _panel(r, a, "MISSION SUMMARY", font)
	var fs := 14
	var x0 := r.position.x + 16.0
	var x1 := r.position.x + r.size.x - 16.0
	_diamond(Vector2(x0 + 5.0, y - 4.0), 6.0, Color(GOLD.r, GOLD.g, GOLD.b, a))
	_row(font, x0 + 18.0, x1, y, "Core Shards Collected",
		"%d / %d" % [int(stats.get("collected", 0)), int(stats.get("needed", 0))], a, fs)
	y += 24.0
	draw_circle(Vector2(x0 + 5.0, y - 4.0), 5.0, Color(INK_DIM.r, INK_DIM.g, INK_DIM.b, a))
	_row(font, x0 + 18.0, x1, y, "Enemies Defeated", "All", a, fs)


func _draw_stats(r: Rect2, font: Font, a: float) -> void:
	var y := _panel(r, a, "STATS", font)
	var fs := 14
	var x0 := r.position.x + 16.0
	var x1 := r.position.x + r.size.x - 16.0
	for row in _rows:
		# Each row fades in behind the one above it.
		var i := _rows.find(row)
		var ra := a * _fade(0.50 + float(i) * 0.05, 0.25)
		_row(font, x0, x1, y, String(row[0]), String(row[1]), ra, fs)
		y += 23.0


func _draw_performance(r: Rect2, font: Font, a: float) -> void:
	var y := _panel(r, a, "PERFORMANCE", font)
	var cx := r.position.x + r.size.x * 0.5

	# Laurel + rank badge.
	var badge := Vector2(cx, y + 56.0)
	_laurel(badge, 50.0, a)
	_diamond(badge, 40.0, Color(GOLD_DARK.r, GOLD_DARK.g, GOLD_DARK.b, a))
	_diamond(badge, 33.0, Color(GOLD.r, GOLD.g, GOLD.b, a))
	_diamond(badge, 25.0, Color(0.10, 0.07, 0.03, a))
	var bfs := 34
	var bw := font.get_string_size(_rank, HORIZONTAL_ALIGNMENT_LEFT, -1, bfs).x
	draw_string(font, badge + Vector2(-bw * 0.5, bfs * 0.36), _rank,
		HORIZONTAL_ALIGNMENT_LEFT, -1, bfs,
		Color(GOLD_LIT.r, GOLD_LIT.g, GOLD_LIT.b, a))

	y = badge.y + 78.0
	var fs := 13
	var x0 := r.position.x + 16.0
	var x1 := r.position.x + r.size.x - 16.0
	for row in _grade_rows:
		var i := _grade_rows.find(row)
		var ra := a * _fade(0.62 + float(i) * 0.06, 0.25)
		_row(font, x0, x1, y, String(row[0]), String(row[1]), ra, fs)
		y += 22.0

	# RANK, big, at the bottom.
	var rf := a * _fade(1.00, 0.4)
	if rf > 0.01:
		draw_line(Vector2(x0, y + 2.0), Vector2(x1, y + 2.0),
			Color(GOLD_DARK.r, GOLD_DARK.g, GOLD_DARK.b, rf), 1.0)
		draw_string(font, Vector2(x0, y + 32.0), "RANK",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(INK.r, INK.g, INK.b, rf))
		var big := 34
		var gw := font.get_string_size(_rank, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
		draw_string(font, Vector2(x1 - gw, y + 38.0), _rank,
			HORIZONTAL_ALIGNMENT_LEFT, -1, big,
			Color(GOLD_LIT.r, GOLD_LIT.g, GOLD_LIT.b, rf))


## Two arcs of tapering leaves, the classic wreath.
func _laurel(c: Vector2, rad: float, a: float) -> void:
	for side_i in 2:
		var side := -1.0 if side_i == 0 else 1.0
		for i in 8:
			var t := float(i) / 7.0
			var ang := PI * 0.5 + side * (0.38 + t * 1.55)
			var at := c + Vector2(cos(ang), -sin(ang)) * rad
			var leaf := 9.0 - t * 3.4
			draw_circle(at, leaf, Color(GOLD_DARK.r, GOLD_DARK.g, GOLD_DARK.b,
				a * (0.95 - t * 0.3)))
			draw_circle(at + Vector2(-side * 1.2, -1.2), leaf * 0.62,
				Color(GOLD.r, GOLD.g, GOLD.b, a * (0.8 - t * 0.3)))


func _draw_flavour(r: Rect2, font: Font, a: float) -> void:
	var cx := r.position.x + r.size.x * 0.5
	var head := "WELL DONE, WARRIOR."
	var fs := 17
	var tw := font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2(cx - tw * 0.5, r.position.y), head,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(GOLD.r, GOLD.g, GOLD.b, a))
	var lines := ["The darkness retreats", "before your strength."]
	var y := r.position.y + 28.0
	for l in lines:
		var lw := font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string(font, Vector2(cx - lw * 0.5, y), l,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(INK_DIM.r, INK_DIM.g, INK_DIM.b, a))
		y += 20.0
	_diamond(Vector2(cx, y + 8.0), 6.0, Color(GOLD_DARK.r, GOLD_DARK.g, GOLD_DARK.b, a))


## Rewards: three medallions with a value under each. Scaled off the run, so a
## fast clean clear is worth visibly more than a slow one.
func _draw_rewards(r: Rect2, font: Font, a: float) -> void:
	var y := _panel(r, a, "REWARDS", font)
	var shards := int(stats.get("collected", 0)) * 7
	var exp := int(stats.get("kills", 0)) * 30 + int(stats.get("combo", 0)) * 10
	var gold := int(stats.get("dealt", 0.0) * 0.08) + shards

	var items := [
		["shard", "+%s" % _comma(shards), "CORE SHARDS", GOLD],
		["xp", "+%s" % _comma(exp), "EXP", Color(0.62, 0.36, 0.92)],
		["gold", "+%s" % _comma(gold), "GOLD", Color(0.95, 0.78, 0.26)],
	]
	var cw := r.size.x / 3.0
	for i in items.size():
		var it: Array = items[i]
		var cx := r.position.x + cw * (float(i) + 0.5)
		var cy := y + 26.0
		var col: Color = it[3]
		# Medallion: a dark disc, a coloured ring, a bright core.
		draw_circle(Vector2(cx, cy), 22.0, Color(0.06, 0.05, 0.05, a))
		draw_arc(Vector2(cx, cy), 21.0, 0.0, TAU, 28,
			Color(col.r, col.g, col.b, a), 3.0, true)
		if String(it[0]) == "shard":
			_diamond(Vector2(cx, cy), 15.0, Color(col.r, col.g, col.b, a))
			_diamond(Vector2(cx, cy), 8.0,
				Color(GOLD_LIT.r, GOLD_LIT.g, GOLD_LIT.b, a))
		else:
			draw_circle(Vector2(cx, cy), 15.0,
				Color(col.r * 0.5, col.g * 0.5, col.b * 0.5, a))
			var gl := "XP" if String(it[0]) == "xp" else "S"
			var gw := font.get_string_size(gl, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			draw_string(font, Vector2(cx - gw * 0.5, cy + 5.0), gl,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
				Color(1, 1, 1, a * 0.95))

		var vt := String(it[1])
		var vw := font.get_string_size(vt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		draw_string(font, Vector2(cx - vw * 0.5, cy + 46.0), vt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(INK.r, INK.g, INK.b, a))
		var lt := String(it[2])
		var lw := font.get_string_size(lt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_string(font, Vector2(cx - lw * 0.5, cy + 62.0), lt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(INK_DIM.r, INK_DIM.g, INK_DIM.b, a))
