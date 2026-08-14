extends Node
## Verifies the scripted opening level fires its beats in order and produces
## exactly the intended monster and meat counts.

const OUT := "res://shots/"
var failures := 0
var arena: Node


func _ready() -> void:
	await get_tree().process_frame
	var decoy := Node.new()
	get_tree().root.add_child(decoy)
	get_tree().current_scene = decoy
	await _wait(20)

	print("")
	print("=== level 1 beats ===")
	Game.start_world(0)
	await _wait(260)
	arena = get_tree().current_scene

	_check("quota is 11", Game.needed() == 11)
	var a := _tally()
	_dump("beat0", a)
	_check("beat 0: 4 spawned", a["total"] == 4)
	_check("beat 0: all small", a["t0"] == 4)
	await _shot("l1-01-opening")

	# Two kills should bring the first medium in.
	_kill(2)
	await _wait(120)
	a = _tally()
	_dump("beat1", a)
	_check("beat 1: medium arrives", a["t1"] == 1)
	_check("beat 1: 3 alive total", a["total"] == 3)
	await _shot("l1-02-medium")

	# Drive the medium to 15% and the small ones should answer.
	var med := _find_tier(1)
	_check("medium found", med != null)
	if med:
		med.take_damage(med.max_health * 0.86, med.global_position + Vector3.FORWARD, 0.0)
	# Beat 2 staggers five spawns over 1.5s, and the scene is heavier now.
	await _wait(240)
	a = _tally()
	_dump("beat2", a)
	_check("beat 2: 5 more small", a["t0"] >= 6)
	await _shot("l1-03-swarm")

	# Nine meat should summon the guardians.
	while Game.collected < 9:
		Game.add_drop(1)
	await _wait(160)
	a = _tally()
	_dump("beat3", a)
	_check("beat 3: guardians in", a["t1"] >= 2)
	_check("arena reached beat 3", arena._beat == 3)
	await _shot("l1-04-guardians")

	print("")
	print("  spawned overall: %d small, %d medium" % [arena._spawned_t0, arena._spawned_t1])
	var meat: int = arena._spawned_t0 * 1 + arena._spawned_t1 * 2
	print("  meat available : %d  (quota %d)" % [meat, Game.needed()])
	_check("meat covers quota", meat >= Game.needed())

	print("")
	print("  %s" % ("ALL PASS" if failures == 0 else "%d FAILURE(S)" % failures))
	print("")
	get_tree().quit(1 if failures > 0 else 0)


func _tally() -> Dictionary:
	var out := {"total": 0, "t0": 0, "t1": 0, "t2": 0}
	for e in get_tree().get_nodes_in_group("enemies"):
		if not e.is_alive():
			continue
		out["total"] += 1
		out["t%d" % e.tier] += 1
	return out


func _find_tier(t: int) -> Node:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.is_alive() and e.tier == t:
			return e
	return null


func _kill(n: int) -> void:
	var killed := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if killed >= n:
			break
		if e.is_alive() and e.tier == 0:
			e.take_damage(99999.0, e.global_position + Vector3.FORWARD, 0.0)
			killed += 1


func _dump(tag: String, a: Dictionary) -> void:
	print("     [%s] alive total=%d  t0=%d t1=%d t2=%d  beat=%d  collected=%d" % [
		tag, a["total"], a["t0"], a["t1"], a["t2"], arena._beat, Game.collected])


func _check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
	print("  %-24s %s" % [label, "PASS" if ok else "FAIL"])


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(name: String) -> void:
	# frame_post_draw never fires under --headless, so an unguarded await here
	# hangs the whole suite forever. Headless runs assert; windowed runs also shoot.
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + name + ".png")
