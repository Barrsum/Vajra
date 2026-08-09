extends Control
## Title screen. Deliberately thin — the run itself lives in the Game autoload,
## so this only has to start one.

@onready var _start: Button = $Center/Rows/Start
@onready var _quit: Button = $Center/Rows/Quit
@onready var _worlds: Label = $Center/Rows/Worlds


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false

	var names := PackedStringArray()
	for w in Game.worlds:
		names.append(w.ingredient)
	_worlds.text = "SHOPPING LIST:   " + "   ·   ".join(names)

	_start.pressed.connect(func() -> void: Game.start_run())
	_quit.pressed.connect(func() -> void: Game.quit())
	_start.grab_focus()
