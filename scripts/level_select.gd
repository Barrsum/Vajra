extends Control
## Quest select: four cards in a row, drawn.
##
## The cards were previously laid on an arc with each element as a child node.
## The reference art is a flat row of framed plates with an illustration panel,
## a rule, an ingredient chip and a status footer — far more parts per card, and
## twenty-odd nodes each would be a lot of layout code to keep in sync.
##
## So each card is one Button (for focus and clicks, which drawing cannot give
## you) with everything painted on top in _draw. Selection follows focus, so
## keyboard and mouse agree without any extra state.

const Art := preload("res://scripts/ui_art.gd")

const CARD := Vector2(258, 524)
const GAP := 22.0

var _cards: Array[Button] = []
var _sel := 0
var _t := 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for c in get_children():
		c.queue_free()
	_build()
	get_viewport().size_changed.connect(_layout)
	set_process(true)


func _build() -> void:
	for c in _cards:
		c.queue_free()
	_cards.clear()

	for i in Game.worlds.size():
		var locked := i > Game.unlocked
		var b := Button.new()
		b.custom_minimum_size = CARD
		b.size = CARD
		b.flat = true
		b.text = ""
		b.disabled = locked
		b.focus_mode = Control.FOCUS_ALL if not locked else Control.FOCUS_NONE
		# Fully transparent: everything visible is painted in _draw. A styled
		# button underneath would show through the artwork.
		var empty := StyleBoxEmpty.new()
		for s in ["normal", "hover", "pressed", "focus", "disabled"]:
			b.add_theme_stylebox_override(s, empty)
		add_child(b)
		_cards.append(b)

		if not locked:
			var idx := i
			b.pressed.connect(func() -> void: Game.start_world(idx))
			b.focus_entered.connect(func() -> void: _sel = idx)
			b.mouse_entered.connect(func() -> void:
				_sel = idx
				b.grab_focus())

	# Bottom row and the two corner buttons.
	_corner("BACK", Vector2(28, 26), func() -> void: Game.to_menu())
	var vp := get_viewport_rect().size
	_corner("STORY SO FAR", Vector2(28, vp.y - 74.0), func() -> void: pass)
	var reset := _corner("RESET PROGRESS", Vector2(vp.x - 258.0, vp.y - 74.0),
		func() -> void:
			Game.reset_progress()
			_build())
	reset.name = "Reset"

	_layout()
	# Land focus on the furthest world you can actually play, not on world 1 —
	# that is the one you came here to press.
	_sel = mini(Game.unlocked, Game.worlds.size() - 1)
	if _sel < _cards.size():
		_cards[_sel].call_deferred("grab_focus")


func _corner(label: String, at: Vector2, cb: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(230, 46)
	Art.style_button(b, false, 46.0, 15)
	b.pressed.connect(cb)
	add_child(b)
	b.position = at
	return b


func _layout() -> void:
	var n := _cards.size()
	if n == 0:
		return
	var vp := get_viewport_rect().size
	var total := float(n) * CARD.x + float(n - 1) * GAP
	var x0 := (vp.x - total) * 0.5
	var y := vp.y * 0.5 - CARD.y * 0.5 + 26.0
	for i in n:
		_cards[i].position = Vector2(x0 + float(i) * (CARD.x + GAP), y)

	for c in get_children():
		if c is Button and not (c in _cards):
			if String(c.text) == "STORY SO FAR":
				c.position = Vector2(28, vp.y - 74.0)
			elif String(c.text) == "RESET PROGRESS":
				c.position = Vector2(vp.x - 258.0, vp.y - 74.0)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 64.0 or h < 64.0:
		return
	var font := ThemeDB.fallback_font

	Art.vgrad(self, Rect2(0, 0, w, h), Color(0.038, 0.034, 0.032), Art.BG, 20)

	# Heading.
	Art.crest(self, Vector2(w * 0.5, h * 0.062), w * 0.011, 0.85, false, _t)
	Art.text(self, font, Vector2(w * 0.5, h * 0.145), "SELECT YOUR QUEST",
		int(w * 0.030), Art.GOLD_LIT)
	Art.rule(self, Vector2(w * 0.5, h * 0.175), w * 0.25)
	Art.text(self, font, Vector2(w * 0.5, h * 0.212),
		"CHOOSE YOUR PATH. THE NIGHT IS LONG, WARRIOR.",
		int(w * 0.0105), Art.INK_DIM)

	# Shard tally, top right.
	var need := 0
	var got := 0
	for i in Game.worlds.size():
		var wd: Resource = Game.worlds[i]
		need += int(wd.ingredient_needed)
		if Game.is_cleared(i):
			got += int(wd.ingredient_needed)
	var tally := Vector2(w - 40.0, 52.0)
	Art.diamond(self, tally - Vector2(150.0, 8.0), 20.0, Art.GOLD, 0.66)
	Art.diamond(self, tally - Vector2(150.0, 8.0), 11.0, Art.GOLD_LIT, 0.66)
	Art.text(self, font, tally - Vector2(120.0, 12.0), "CORE SHARDS", 13,
		Art.INK_DIM, false)
	Art.text(self, font, tally - Vector2(120.0, -14.0), "%d / %d" % [got, need],
		22, Art.INK, false)

	for i in _cards.size():
		_draw_card(i, font)

	# Page pips under the row.
	var py := h * 0.5 + CARD.y * 0.5 + 54.0
	for i in _cards.size():
		var px := w * 0.5 + (float(i) - float(_cards.size() - 1) * 0.5) * 30.0
		Art.diamond(self, Vector2(px, py), 7.0,
			Art.GOLD if i == _sel else Art.GOLD_FAINT)


func _draw_card(i: int, font: Font) -> void:
	var b := _cards[i]
	var r := Rect2(b.position, b.size)
	var wd: Resource = Game.worlds[i]
	var locked: bool = i > Game.unlocked
	var done: bool = Game.is_cleared(i)
	var sel: bool = i == _sel and not locked
	var a := 1.0 if not locked else 0.55

	Art.panel(self, r, a, sel)
	if sel:
		Art.corners(self, r.grow(6.0), 22.0,
			Color(Art.GOLD.r, Art.GOLD.g, Art.GOLD.b, 0.9))
		# The little finial over the selected card, as in the reference.
		Art.diamond(self, Vector2(r.get_center().x, r.position.y - 12.0), 11.0,
			Art.GOLD)

	# Illustration panel. No art files yet, so it is the world's own sky and
	# ground colours as a gradient — which at least means each card already
	# looks like the place it leads to.
	var art := Rect2(r.position.x + 12.0, r.position.y + 46.0,
		r.size.x - 24.0, 210.0)
	var top: Color = wd.sky_horizon
	var bot: Color = wd.ground_color
	if locked:
		top = top.darkened(0.75)
		bot = bot.darkened(0.8)
	Art.vgrad(self, art, top.darkened(0.35), bot.darkened(0.55), 18)
	# A suggestion of depth: a lighter well toward the centre.
	for k in 5:
		var f := float(k) / 4.0
		var inset := art.grow(-art.size.x * 0.10 * (1.0 - f))
		draw_rect(Rect2(inset.position.x, inset.position.y + inset.size.y * 0.30,
			inset.size.x, inset.size.y * 0.55),
			Color(top.r, top.g, top.b, 0.05 * a))
	draw_rect(art, Color(Art.GOLD_FAINT.r, Art.GOLD_FAINT.g, Art.GOLD_FAINT.b, a),
		false, 1.0)

	# Index, top left, over the art.
	Art.text(self, font, r.position + Vector2(18.0, 36.0), "%02d" % (i + 1),
		30, Color(Art.INK.r, Art.INK.g, Art.INK.b, a), false)
	if locked:
		# Padlock: a body and a shackle.
		var lp := Vector2(r.position.x + r.size.x - 30.0, r.position.y + 30.0)
		draw_rect(Rect2(lp.x - 9.0, lp.y - 2.0, 18.0, 14.0),
			Color(Art.INK_DIM.r, Art.INK_DIM.g, Art.INK_DIM.b, 0.8))
		draw_arc(lp + Vector2(0, -2.0), 6.5, PI, TAU, 12,
			Color(Art.INK_DIM.r, Art.INK_DIM.g, Art.INK_DIM.b, 0.8), 2.5)
	else:
		Art.diamond(self, r.position + Vector2(26.0, 52.0), 5.0,
			Color(Art.GOLD.r, Art.GOLD.g, Art.GOLD.b, a))

	var cx := r.get_center().x
	var y := art.position.y + art.size.y + 34.0

	# Name, badge, tagline.
	var name_col: Color = wd.sky_horizon.lightened(0.35)
	if locked:
		name_col = Color(Art.INK_DIM.r, Art.INK_DIM.g, Art.INK_DIM.b, 0.7)
	Art.text(self, font, Vector2(cx, y), String(wd.display_name).to_upper(), 19,
		name_col)

	y += 30.0
	draw_arc(Vector2(cx, y - 4.0), 13.0, 0.0, TAU, 20,
		Color(Art.GOLD_FAINT.r, Art.GOLD_FAINT.g, Art.GOLD_FAINT.b, a), 1.5)
	Art.diamond(self, Vector2(cx, y - 4.0), 7.0,
		Color(name_col.r, name_col.g, name_col.b, a), 0.8)

	y += 30.0
	Art.text(self, font, Vector2(cx, y), String(wd.subtitle), 13,
		Color(Art.INK_DIM.r, Art.INK_DIM.g, Art.INK_DIM.b, a))

	# Rewards block.
	y += 26.0
	Art.text(self, font, Vector2(cx, y), "REWARDS", 11,
		Color(Art.GOLD.r, Art.GOLD.g, Art.GOLD.b, a * 0.9))
	y += 8.0
	Art.rule(self, Vector2(cx, y), r.size.x * 0.30, a * 0.8)

	y += 18.0
	var chip := Rect2(r.position.x + 20.0, y, 46.0, 46.0)
	draw_rect(chip, Color(0.08, 0.07, 0.055, a))
	draw_rect(chip, Color(Art.GOLD_FAINT.r, Art.GOLD_FAINT.g, Art.GOLD_FAINT.b, a),
		false, 1.0)
	var icol: Color = wd.accent_color
	if locked:
		icol = icol.darkened(0.6)
	Art.diamond(self, chip.get_center(), 15.0, Color(icol.r, icol.g, icol.b, a), 0.7)
	Art.diamond(self, chip.get_center(), 8.0,
		Color(icol.lightened(0.5).r, icol.lightened(0.5).g,
			icol.lightened(0.5).b, a), 0.7)

	Art.text(self, font, Vector2(chip.position.x + 60.0, y + 20.0),
		String(wd.ingredient).to_upper(), 13,
		Color(Art.INK.r, Art.INK.g, Art.INK.b, a), false)
	Art.text(self, font, Vector2(chip.position.x + 60.0, y + 40.0),
		"x%d" % int(wd.ingredient_needed), 15,
		Color(Art.INK_DIM.r, Art.INK_DIM.g, Art.INK_DIM.b, a), false)

	# Footer: cleared, ready or locked.
	var fy := r.position.y + r.size.y - 26.0
	Art.rule(self, Vector2(cx, fy - 18.0), r.size.x * 0.38, a * 0.6)
	if locked:
		Art.text(self, font, Vector2(cx + 10.0, fy), "LOCKED", 14,
			Color(Art.INK_DIM.r, Art.INK_DIM.g, Art.INK_DIM.b, 0.75))
	elif done:
		var tw := Art.text(self, font, Vector2(cx + 10.0, fy), "CLEARED", 14, Art.OK)
		# Tick, drawn to the right of the word.
		var t0 := Vector2(cx + 14.0 + tw * 0.5, fy - 5.0)
		draw_line(t0, t0 + Vector2(5.0, 6.0), Art.OK, 2.5)
		draw_line(t0 + Vector2(5.0, 6.0), t0 + Vector2(13.0, -8.0), Art.OK, 2.5)
	else:
		Art.text(self, font, Vector2(cx, fy), "READY", 14, Art.GOLD_LIT)
