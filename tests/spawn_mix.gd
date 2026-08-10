extends Node
## Rolls a large sample of spawns per world and reports the actual creature mix,
## so a roster can be verified rather than assumed from a few playthroughs.
const ENEMY := preload("res://scripts/enemy.gd")
func _ready() -> void:
	print("")
	for wi in Game.worlds.size():
		Game.world_index = wi
		var w: Resource = Game.current_world()
		var tally := {}
		for i in 400:
			var idx := _roll(w.creature_weights)
			var n: String = ENEMY.CREATURES[idx]["name"]
			tally[n] = int(tally.get(n, 0)) + 1
		print("  %d %-20s %s" % [wi + 1, w.display_name, tally])
	print("")
	get_tree().quit(0)
func _roll(weights: Array) -> int:
	var total := 0.0
	for x in weights: total += float(x)
	if total <= 0.0: return 0
	var r := randf() * total
	var acc := 0.0
	for i in weights.size():
		acc += float(weights[i])
		if r <= acc: return i
	return 0
