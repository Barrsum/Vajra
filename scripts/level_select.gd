extends Control
## World select. Cards are laid along a shallow arc — a race-track curve rather
## than a straight row — and built in code so the curve stays one formula
## instead of four hand-placed nodes that drift apart.

const CARD := Vector2(230, 320)
const ARC_RISE := 120.0     ## how far the ends lift above the middle
const TILT := 9.0           ## degrees of rotation at the outermost card
const GAP := 44.0

@onready var _lane: Control = $Lane
@onready var _hint: Label = $Hint

var _cards: Array[Control] = []


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	$Back.pressed.connect(func() -> void: Game.to_menu())
	$Reset.pressed.connect(func() -> void:
		Game.reset_progress()
		_build())
	_build()
	get_viewport().size_changed.connect(_layout)


func _build() -> void:
	for c in _cards:
		c.queue_free()
	_cards.clear()

	for i in Game.worlds.size():
		var w: Resource = Game.worlds[i]
		var locked := i > Game.unlocked
		var done := Game.is_cleared(i)

		var card := Button.new()
		card.custom_minimum_size = CARD
		card.size = CARD
		card.pivot_offset = CARD * 0.5
		card.disabled = locked
		card.focus_mode = Control.FOCUS_NONE
		card.add_theme_font_size_override("font_size", 1)   # label drawn manually below
		card.text = ""
		_lane.add_child(card)
		_cards.append(card)

		# Explicit type: property access on an untyped Resource cannot be inferred.
		var col: Color = w.sky_horizon
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.07, 0.06, 0.06) if not locked else Color(0.05, 0.05, 0.05)
		sb.border_color = col.darkened(0.2) if not locked else Color(0.16, 0.16, 0.16)
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(10)
		card.add_theme_stylebox_override("normal", sb)
		var hov := sb.duplicate()
		hov.bg_color = Color(0.12, 0.10, 0.09)
		hov.border_color = col
		card.add_theme_stylebox_override("hover", hov)
		card.add_theme_stylebox_override("pressed", hov)
		card.add_theme_stylebox_override("disabled", sb)

		# Colour swatch so each world is identifiable before you've played it.
		var swatch := ColorRect.new()
		swatch.color = col if not locked else Color(0.18, 0.18, 0.18)
		swatch.set_anchors_preset(Control.PRESET_TOP_WIDE)
		swatch.offset_left = 14
		swatch.offset_right = -14
		swatch.offset_top = 16
		swatch.offset_bottom = 120
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(swatch)

		var rows := VBoxContainer.new()
		rows.set_anchors_preset(Control.PRESET_FULL_RECT)
		rows.offset_left = 16
		rows.offset_right = -16
		rows.offset_top = 134
		rows.offset_bottom = -16
		rows.add_theme_constant_override("separation", 6)
		rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(rows)

		rows.add_child(_label("%02d" % (i + 1), 30, Color(1, 1, 1, 0.25)))
		rows.add_child(_label(w.display_name if not locked else "LOCKED", 19,
			Color(1, 0.72, 0.42) if not locked else Color(1, 1, 1, 0.3)))
		rows.add_child(_label(w.subtitle if not locked else "clear the previous world", 12,
			Color(1, 1, 1, 0.4)))
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		rows.add_child(spacer)
		if not locked:
			rows.add_child(_label("%s  x%d" % [w.ingredient, w.ingredient_needed], 14,
				Color(1, 1, 1, 0.55)))
		rows.add_child(_label("CLEARED" if done else ("LOCKED" if locked else "READY"), 13,
			Color(0.5, 1.0, 0.6) if done else Color(1, 1, 1, 0.3)))

		if not locked:
			var idx := i
			card.pressed.connect(func() -> void: Game.start_world(idx))

	_layout()
	_hint.text = "%d of %d unlocked" % [mini(Game.unlocked + 1, Game.worlds.size()), Game.worlds.size()]


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Places the cards along an arc: x spreads evenly, y follows a parabola, and
## rotation eases from -TILT to +TILT so the row reads as a curved track.
func _layout() -> void:
	var n := _cards.size()
	if n == 0:
		return
	var total := n * CARD.x + (n - 1) * GAP
	var vp := get_viewport_rect().size
	var start_x := (vp.x - total) * 0.5
	var base_y := vp.y * 0.5 - CARD.y * 0.5 + 20.0

	for i in n:
		# -1 at the left end, +1 at the right.
		var t := 0.0 if n == 1 else (float(i) / float(n - 1)) * 2.0 - 1.0
		var c := _cards[i]
		c.position = Vector2(
			start_x + i * (CARD.x + GAP),
			base_y - ARC_RISE * (1.0 - t * t))
		c.rotation = deg_to_rad(TILT * t)
