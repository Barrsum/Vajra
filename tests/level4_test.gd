extends Node
## Walks level 4: four 2x of every species, a 4x Warrok five seconds in, the
## ambush repeating at 53% of its health, and the level's standing rules —
## minis only from wounded mediums, and minis carry no meat.

const OUT := "res://shots/"
var failures := 0
var arena: Node
var player: CharacterBody3D


func _ready() -> void:
	await get_tree().process_frame
	var decoy := Node.new()
	get_tree().root.add_child(decoy)
	get_tree().current_scene = decoy
	await _wait(20)

	print("")
	print("=== level 4: the long night ===")
	Game.start_world(3)
	await _wait(220)
	arena = get_tree().current_scene
	player = arena.get_node("Player") as CharacterBody3D

	_check("quota is 35", Game.needed() == 35)
	var meds := _by_tier(1)
	_check("four mediums", meds.size() == 4)
	_check("one of every species", _species(meds).size() == 4)
	_check("no giant yet", _by_tier(2).is_empty())
	_dump("opening")
	await _shot("l4-01-four")

	# The Warrok is on a five second fuse.
	for i in 500:
		await get_tree().physics_frame
		if not _by_tier(2).is_empty():
			break
	var giants := _by_tier(2)
	_check("4x arrives", giants.size() >= 1)
	_check("it is a Warrok", giants.size() > 0 and giants[0].creature == 3)
	_dump("giant")
	await _shot("l4-02-warrok")

	# A medium worn to 30% calls a mini, and that mini drops a health orb.
	var before := _by_tier(0).size()
	meds[0].take_damage(meds[0].max_health * 0.75, meds[0].global_position + Vector3.FORWARD, 0.0)
	await _wait(140)
	var minis := _by_tier(0)
	_check("30%% calls a mini", minis.size() > before)
	_check("minis carry no meat", _all_zero_drops(minis))

	# Killing that mini should leave a health orb, not an ingredient.
	if not minis.is_empty():
		minis[0].take_damage(99999.0, minis[0].global_position + Vector3.FORWARD, 0.0)
		await _wait(60)
		_check("mini drops a health orb", _health_orbs_on_ground() >= 1)

	# The orb stock caps, and the cap is what makes a sixth bounce off.
	for i in 6:
		player.add_health_orb()
	_check("orb stock caps at 5", player.health_orbs == 5)
	_check("sixth orb refused", player.add_health_orb() == false)

	# The trap springs when the LAST of the opening four is worn to 53%.
	for i in [1, 2, 3]:
		meds[i].take_damage(99999.0, meds[i].global_position + Vector3.FORWARD, 0.0)
	await _wait(80)
	meds[0].take_damage(meds[0].max_health * 0.2, meds[0].global_position + Vector3.FORWARD, 0.0)
	await _wait(220)
	_check("ambush repeats", arena._grabbers.size() == 2)
	_check("beat advanced", arena._beat >= 1)
	_dump("ambush")
	await _shot("l4-03-ambush")

	# The grab and throw should still resolve.
	var thrown := false
	for i in 800:
		await get_tree().physics_frame
		if player.is_launched():
			thrown = true
			break
	_check("thrown again", thrown)
	await _shot("l4-04-thrown")

	print("")
	print("  %s" % ("ALL PASS" if failures == 0 else "%d FAILURE(S)" % failures))
	print("")
	get_tree().quit(1 if failures > 0 else 0)


func _by_tier(t: int) -> Array:
	var o := []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.is_alive() and e.tier == t:
			o.append(e)
	return o


func _species(list: Array) -> Dictionary:
	var o := {}
	for e in list:
		o[e.creature] = true
	return o


## Health orbs sitting on the ground, identified by kind rather than colour.
func _health_orbs_on_ground() -> int:
	var n := 0
	for c in arena.get_children():
		if c.get_script() != null and "kind" in c and c.kind == 1:
			n += 1
	return n


func _all_zero_drops(list: Array) -> bool:
	for e in list:
		if e.drops != 0:
			return false
	return true


func _dump(tag: String) -> void:
	var names := {}
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.is_alive():
			var n: String = "%s %dx" % [e.CREATURES[e.creature]["name"], [1, 2, 4][e.tier]]
			names[n] = int(names.get(n, 0)) + 1
	print("     [%s] beat=%d  %s" % [tag, arena._beat, names])


func _check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
	print("  %-30s %s" % [label, "PASS" if ok else "FAIL"])


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
