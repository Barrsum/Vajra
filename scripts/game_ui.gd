extends CanvasLayer
## In-run HUD and the overlay used for pause, world-clear, victory and death.
##
## One overlay reskinned per state rather than four scenes — the layout is
## identical and four near-copies would drift apart the moment anything changed.

@onready var _world: Label = %WorldName
@onready var _quota: Label = %Quota
@onready var _health: Label = %Health
@onready var _banner: Label = %Banner

@onready var _overlay: Control = %Overlay
@onready var _title: Label = %OverlayTitle
@onready var _msg: Label = %OverlayMessage
@onready var _b1: Button = %Button1
@onready var _b2: Button = %Button2
@onready var _b3: Button = %Button3

var player: Node = null
var _banner_t := 0.0


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


func _process(delta: float) -> void:
	if is_instance_valid(player) and "health" in player:
		_health.text = "HP  %d" % roundi(player.health)
		if "alive" in player and not player.alive and Game.state == Game.State.PLAYING:
			Game.player_died()

	if _banner_t > 0.0:
		_banner_t -= delta
		_banner.modulate.a = clampf(_banner_t, 0.0, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_release_mouse"):
		if Game.state == Game.State.PLAYING or Game.state == Game.State.PAUSED:
			Game.toggle_pause()
			get_viewport().set_input_as_handled()


# --- feed -------------------------------------------------------------------

func _on_world_started(w, index: int) -> void:
	_world.text = "%d / %d   %s" % [index + 1, Game.worlds.size(), w.display_name]
	_show_banner("%s\n%s" % [w.display_name, w.subtitle])


func _on_collected(have: int, need: int) -> void:
	var w: Resource = Game.current_world()
	# Not `name` — that shadows Node.name, and the untyped ternary also defeats
	# type inference, which silently kills the whole script's parse.
	var ing: String = w.ingredient if w else "ITEMS"
	_quota.text = "%s   %d / %d" % [ing, have, need]


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
			_open("PAUSED", "", "RESUME", Game.toggle_pause,
				"RESTART WORLD", Game.retry_world, "MAIN MENU", Game.to_menu)
		Game.State.WORLD_CLEAR:
			var w: Resource = Game.current_world()
			_open("COLLECTED", "%d %s secured.\nOne more stop." % [w.ingredient_needed, w.ingredient],
				"NEXT WORLD", Game.next_world, "LEVEL SELECT", Game.to_select, "MAIN MENU", Game.to_menu)
		Game.State.VICTORY:
			_open("SHOPPING DONE",
				"Everything on the list.\nTime to go home.",
				"LEVEL SELECT", Game.to_select, "MAIN MENU", Game.to_menu, "", Callable())
		Game.State.DEAD:
			_open("SCRAPPED", "She is going to be furious.",
				"RETRY WORLD", Game.retry_world, "LEVEL SELECT", Game.to_select, "MAIN MENU", Game.to_menu)


func _open(title: String, message: String,
		l1: String, c1: Callable, l2: String, c2: Callable, l3: String, c3: Callable) -> void:
	_overlay.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Kill any world-intro banner, or it reads through the dim behind the title.
	_banner_t = 0.0
	_banner.modulate.a = 0.0
	_title.text = title
	_msg.text = message
	_msg.visible = message != ""
	_wire(_b1, l1, c1)
	_wire(_b2, l2, c2)
	_wire(_b3, l3, c3)
	if _b1.visible:
		_b1.grab_focus()


func _wire(b: Button, label: String, cb: Callable) -> void:
	for c in b.pressed.get_connections():
		b.pressed.disconnect(c["callable"])
	b.visible = label != ""
	b.text = label
	if b.visible and cb.is_valid():
		b.pressed.connect(cb)
