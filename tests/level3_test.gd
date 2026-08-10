extends Node
## Walks level 3: three 2x of different species, a small called at 80% health,
## a 4x after two die, a second 4x of a different species after the rest clear.

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
	print("=== level 3: the shallows ===")
	Game.start_world(2)
	await _wait(300)
	arena = get_tree().current_scene

	var meds: Array = arena._l3_mediums
	_check("three mediums", meds.size() == 3)
	_check("all are 2x", _all_tier(meds, 1))
	_check("one of each species", _species(meds).size() == 3)
	_dump("opening")
	await _shot("l3-01-three")

	# Wound the first one to 80%: it should call a small of its own species.
	var before: int = _tally()["total"]
	var m0 = meds[0]
	m0.take_damage(m0.max_health * 0.22, m0.global_position + Vector3.FORWARD, 0.0)
	await _wait(140)
	_check("80%% calls a small", int(_tally()["total"]) > before)
	_check("the small matches species", _matching_small(m0.creature))
	await _shot("l3-02-reinforced")

	# Wound the other two the same way, then kill two mediums.
	for i in [1, 2]:
		var m = meds[i]
		m.take_damage(m.max_health * 0.22, m.global_position + Vector3.FORWARD, 0.0)
	await _wait(140)
	_check("three smalls called", arena._l3_smalls.size() == 3)

	for i in [0, 1]:
		meds[i].take_damage(99999.0, meds[i].global_position + Vector3.FORWARD, 0.0)
	await _wait(220)
	_check("two dead brings a 4x", _count_tier(2) >= 1)
	_check("beat advanced", arena._beat >= 1)
	_dump("first giant")
	await _shot("l3-03-giant")

	# Clear the remaining medium and all smalls; a second 4x should follow.
	meds[2].take_damage(99999.0, meds[2].global_position + Vector3.FORWARD, 0.0)
	for sm in arena._l3_smalls:
		if is_instance_valid(sm) and sm.is_alive():
			sm.take_damage(99999.0, sm.global_position + Vector3.FORWARD, 0.0)
	await _wait(260)
	_check("second 4x arrives", _count_tier(2) >= 2)
	_check("different species", _giant_species().size() >= 2)
	_dump("second giant")
	await _shot("l3-04-second")

	print("")
	print("  %s" % ("ALL PASS" if failures == 0 else "%d FAILURE(S)" % failures))
	print("")
	get_tree().quit(1 if failures > 0 else 0)


func _live() -> Array:
	var o := []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.is_alive():
			o.append(e)
	return o


func _tally() -> Dictionary:
	return {"total": _live().size()}


func _count_tier(t: int) -> int:
	var n := 0
	for e in _live():
		if e.tier == t:
			n += 1
	return n


func _giant_species() -> Dictionary:
	var o := {}
	for e in _live():
		if e.tier == 2:
			o[e.creature] = true
	return o


func _all_tier(list: Array, t: int) -> bool:
	for e in list:
		if not is_instance_valid(e) or e.tier != t:
			return false
	return true


func _species(list: Array) -> Dictionary:
	var o := {}
	for e in list:
		if is_instance_valid(e):
			o[e.creature] = true
	return o


func _matching_small(creature: int) -> bool:
	for sm in arena._l3_smalls:
		if is_instance_valid(sm) and sm.creature == creature:
			return true
	return false


func _dump(tag: String) -> void:
	var names := {}
	for e in _live():
		var n: String = "%s %dx" % [e.CREATURES[e.creature]["name"], [1, 2, 4][e.tier]]
		names[n] = int(names.get(n, 0)) + 1
	print("     [%s] beat=%d  %s" % [tag, arena._beat, names])


func _check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
	print("  %-28s %s" % [label, "PASS" if ok else "FAIL"])


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + name + ".png")
