extends CanvasLayer
## In-run HUD and the overlay used for pause, world-clear, victory and death.
##
## One overlay reskinned per state rather than four scenes — the layout is
## identical and four near-copies would drift apart the moment anything changed.

@onready var _world: Label = %WorldName
@onready var _quota: Label = %Quota
@onready var _health: Label = %Health
@onready var _bar: Control = %HealthBar
@onready var _fill: ColorRect = %Fill
@onready var _orbs: Label = %Orbs
@onready var _hurt: TextureRect = %Hurt
@onready var _banner: Label = %Banner

@onready var _overlay: Control = %Overlay
@onready var _title: Label = %OverlayTitle
@onready var _msg: Label = %OverlayMessage
@onready var _b1: Button = %Button1
@onready var _b2: Button = %Button2
@onready var _b3: Button = %Button3
@onready var _b4: Button = %Button4

var player: Node = null
var _banner_t := 0.0
var _hurt_t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay.visible = false
	_banner.modulate.a = 0.0

	Game.state_changed.connect(_on_state)
	Game.collected_changed.connect(_on_collected)
	Game.world_started.connect(_on_world_started)

	var w: Resource = Game.current_world()
	if w:
		_on_world_started(w, Game.world_index)
	_on_collected(Game.collected, Game.needed())


## Dark at the edges, clear in the middle — a hurt cue you read peripherally
## without it covering what you are fighting.
func _vignette(size := 128) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d: float = Vector2(x - c, y - c).length() / c
			var a: float = clampf((d - 0.45) / 0.55, 0.0, 1.0)
			img.set_pixel(x, y, Color(0.85, 0.05, 0.06, a * a))
	return ImageTexture.create_from_image(img)


func _process(delta: float) -> void:
	if _hurt_t > 0.0:
		_hurt_t = maxf(0.0, _hurt_t - delta * 2.4)
		_hurt.modulate.a = _hurt_t * 0.55

	if is_instance_valid(player) and "health" in player:
		_health.text = "HP  %d / %d" % [roundi(player.health), roundi(player.max_health)]
		var frac: float = clampf(player.health / maxf(player.max_health, 0.001), 0.0, 1.0)
		_fill.size.x = _bar.size.x * frac
		# Same two-stage ramp as the enemy bars, so both read the same way.
		_fill.color = Color(0.96, 0.84, 0.20).lerp(Color(0.35, 0.85, 0.40), (frac - 0.5) * 2.0) 			if frac > 0.5 else Color(0.94, 0.20, 0.16).lerp(Color(0.96, 0.84, 0.20), frac * 2.0)
		if "alive" in player and not player.alive and Game.state == Game.State.PLAYING:
			Game.player_died()

	if _banner_t > 0.0:
		_banner_t -= delta
		_banner.modulate.a = clampf(_banner_t, 0.0, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_release_mouse"):
		if Game.state == Game.State.PLAYING or Game.state == Game.State.PAUSED:
			Game.toggle_pause()
			get_viewport().set_input_as_handled()


# --- feed -------------------------------------------------------------------

func _bind_player() -> void:
	if not is_instance_valid(player):
		return
	if player.has_signal("orbs_changed") and not player.orbs_changed.is_connected(_on_orbs):
		player.orbs_changed.connect(_on_orbs)
	if player.has_signal("hurt_flash") and not player.hurt_flash.is_connected(_on_hurt):
		player.hurt_flash.connect(_on_hurt)
	_on_orbs(player.health_orbs, player.max_health_orbs)


func _on_orbs(have: int, cap: int) -> void:
	# Filled and empty pips, so the stock is countable at a glance.
	_orbs.text = "ORBS  " + "*".repeat(have) + "-".repeat(maxi(cap - have, 0)) 		+ ("     H TO USE" if have > 0 else "")


func _on_hurt() -> void:
	_hurt_t = 1.0


func _on_world_started(w, index: int) -> void:
	_world.text = "%d / %d   %s" % [index + 1, Game.worlds.size(), w.display_name]
	_show_banner("%s\n%s" % [w.display_name, w.subtitle])


func _on_collected(have: int, need: int) -> void:
	var w: Resource = Game.current_world()
	# Not `name` — that shadows Node.name, and the untyped ternary also defeats
	# type inference, which silently kills the whole script's parse.
	var ing: String = w.ingredient if w else "ITEMS"
	_quota.text = "%s   %d / %d" % [ing, have, need]


## Called by the level director to narrate a beat.
func show_message(text: String) -> void:
	_show_banner(text)


func _show_banner(text: String) -> void:
	_banner.text = text
	_banner_t = 3.0
	_banner.modulate.a = 1.0


# --- overlay ----------------------------------------------------------------

func _on_state(s: int) -> void:
	match s:
		Game.State.PLAYING:
			_overlay.visible = false
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		Game.State.PAUSED:
			_open("PAUSED", _mission_text(), [
				["RESUME", Game.toggle_pause],
				["RESTART WORLD", Game.retry_world],
				["LEVEL SELECT", Game.to_select],
				["MAIN MENU", Game.to_menu]])
		Game.State.WORLD_CLEAR:
			var w: Resource = Game.current_world()
			_open("COLLECTED", "%d %s secured.
One more stop." % [w.ingredient_needed, w.ingredient], [
				["NEXT WORLD", Game.next_world],
				["LEVEL SELECT", Game.to_select],
				["MAIN MENU", Game.to_menu]])
		Game.State.VICTORY:
			_open("SHOPPING DONE", "Everything on the list.
Time to go home.", [
				["LEVEL SELECT", Game.to_select],
				["MAIN MENU", Game.to_menu]])
		Game.State.DEAD:
			_open("SCRAPPED", "She is going to be furious.", [
				["RETRY WORLD", Game.retry_world],
				["LEVEL SELECT", Game.to_select],
				["MAIN MENU", Game.to_menu]])


## The pause screen doubles as the objective board — what you are here for, how
## far along you are, and which world it is.
func _mission_text() -> String:
	var w: Resource = Game.current_world()
	if w == null:
		return ""
	return "MISSION  %d / %d   %s
%s

COLLECT  %s   %d / %d" % [
		Game.world_index + 1, Game.worlds.size(), w.display_name, w.subtitle,
		w.ingredient, Game.collected, w.ingredient_needed]


func _open(title: String, message: String, buttons: Array) -> void:
	_overlay.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Kill any world-intro banner, or it reads through the dim behind the title.
	_banner_t = 0.0
	_banner.modulate.a = 0.0
	_title.text = title
	_msg.text = message
	_msg.visible = message != ""

	var slots := [_b1, _b2, _b3, _b4]
	for i in slots.size():
		if i < buttons.size():
			_wire(slots[i], buttons[i][0], buttons[i][1])
		else:
			_wire(slots[i], "", Callable())
	if _b1.visible:
		_b1.grab_focus()


func _wire(b: Button, label: String, cb: Callable) -> void:
	for c in b.pressed.get_connections():
		b.pressed.disconnect(c["callable"])
	b.visible = label != ""
	b.text = label
	if b.visible and cb.is_valid():
		b.pressed.connect(cb)
