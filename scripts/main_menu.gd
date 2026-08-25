extends Control
## Title screen.
##
## The frame — crest, wordmark, rule, vignette — is drawn; only the buttons are
## real nodes, because they need focus and clicks. Same reason as the results
## screen: image files could not recolour, and this palette is shared with
## every other screen through ui_art.gd.

const Art := preload("res://scripts/ui_art.gd")

const TITLE := "VAJRA"
const TAGLINE := "SHE NEEDS INGREDIENTS. YOU HAVE A BLADE."

var _t := 0.0
var _rows: VBoxContainer


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# The scene's own nodes are replaced wholesale — the old layout was a
	# centred VBox with the title as a Label, and none of it survives the new
	# frame. Freeing rather than hiding keeps the tree honest.
	for c in get_children():
		c.queue_free()

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 12)
	_rows.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_rows)
	_rows.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_rows.offset_top = -300.0
	_rows.offset_bottom = -90.0

	_button("START GAME", true, func() -> void: Game.start_run())
	# Continue only means something once something has been cleared.
	var has_save: bool = Game.unlocked > 0 or Game.cleared.size() > 0
	var cont := _button("CONTINUE", false, func() -> void: Game.to_select())
	cont.disabled = not has_save
	# Only after the story is finished. Showing a locked button would advertise
	# the mode and then refuse it, which is worse than not mentioning it — and
	# the whole point of holding it back is that the terrain overlay reads as a
	# bug until the game has told you the rules changed.
	if Game.endless_unlocked:
		_button("ENDLESS", false, func() -> void: Game.start_endless())
	_button("QUIT", false, func() -> void: Game.quit())

	set_process(true)


func _button(label: String, primary: bool, cb: Callable) -> Button:
	# Each button is a row: an icon plate, then the button itself. The plate is
	# drawn in _draw rather than being a child, so it cannot steal the click.
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(430, 0)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	Art.style_button(b, primary, 54.0, 20)
	b.pressed.connect(cb)

	# The icon plate is a CHILD of the button, not something _draw paints.
	# Children render above their parent, but the menu's own _draw runs BELOW
	# every child — so a painted plate sat behind the button background and
	# vanished entirely on the focused one, whose background is near-opaque.
	var plate := Panel.new()
	plate.custom_minimum_size = Vector2(32, 32)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.10, 0.085, 0.055, 0.95)
	ps.border_color = Art.GOLD_FAINT
	ps.set_border_width_all(1)
	ps.set_corner_radius_all(2)
	plate.add_theme_stylebox_override("panel", ps)
	b.add_child(plate)
	plate.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	plate.offset_left = 12.0
	plate.offset_right = 44.0
	plate.offset_top = -16.0
	plate.offset_bottom = 16.0

	var mark := Label.new()
	mark.text = "◆"
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark.add_theme_font_size_override("font_size", 15)
	mark.add_theme_color_override("font_color", Art.GOLD_LIT)
	plate.add_child(mark)
	mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var row := CenterContainer.new()
	row.add_child(b)
	_rows.add_child(row)
	if primary:
		b.call_deferred("grab_focus")
	return b


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 64.0 or h < 64.0:
		return
	var font := ThemeDB.fallback_font

	# Ground. A vertical fade plus a soft pool of warm light behind the centre,
	# so the wordmark is not floating on flat black.
	Art.vgrad(self, Rect2(0, 0, w, h), Color(0.035, 0.032, 0.032), Art.BG, 20)
	var glow := Vector2(w * 0.5, h * 0.62)
	for i in 22:
		var f := float(i) / 21.0
		draw_circle(glow, w * (0.06 + f * 0.36),
			Color(0.58, 0.34, 0.12, 0.020 * (1.0 - f * f)))

	# Crest above the wordmark.
	Art.crest(self, Vector2(w * 0.5, h * 0.105), w * 0.020, 1.0, false, _t)

	# Wordmark. Letter-spaced by drawing each glyph, which is the difference
	# between a title and a label — the reference is widely tracked out.
	var fs := int(w * 0.062)
	var track := fs * 0.30
	var total := 0.0
	for i in TITLE.length():
		total += font.get_string_size(TITLE[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if i < TITLE.length() - 1:
			total += track
	var x := w * 0.5 - total * 0.5
	var y := h * 0.235
	for i in TITLE.length():
		var ch := TITLE[i]
		for o in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2)]:
			draw_string(font, Vector2(x, y) + o, ch, HORIZONTAL_ALIGNMENT_LEFT,
				-1, fs, Color(0.02, 0.015, 0.01, 0.9))
		draw_string(font, Vector2(x, y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(0.94, 0.93, 0.90))
		x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + track

	# Tagline, also tracked out, then the rule under it.
	var tfs := int(w * 0.0115)
	var spaced := ""
	for i in TAGLINE.length():
		spaced += TAGLINE[i]
		if i < TAGLINE.length() - 1:
			spaced += " "
	Art.text(self, font, Vector2(w * 0.5, h * 0.288), spaced, tfs,
		Color(Art.INK_DIM.r, Art.INK_DIM.g, Art.INK_DIM.b, 0.9))
	Art.rule(self, Vector2(w * 0.5, h * 0.318), w * 0.16)

	# Closing rule under the buttons, to bracket them.
	Art.rule(self, Vector2(w * 0.5, h * 0.945), w * 0.11, 0.8)
