extends Node
## Verifies the randomised animation sets.
##
## A pool entry that names a state the tree does not have fails silently at
## runtime: travel() is ignored and the creature simply stands in its rest pose
## forever. That looks like a rigging bug and costs an hour to trace back to a
## one-character typo in a constant. So every pooled name is checked against the
## real state machine here, and a sample of spawns is checked for coverage.
##
## Run: godot --headless --path . res://tests/anim_pool_test.tscn

const ENEMY := preload("res://scenes/enemy.tscn")
const TREE := "res://assets/enemy/enemy_tree.tres"
const LIB := "res://assets/enemy/enemy_anims.res"
const SAMPLE := 240

var failures := 0


func _ready() -> void:
	await get_tree().process_frame
	print("")
	print("=== animation pools ===")

	var sm: AnimationNodeStateMachine = load(TREE)
	var lib: AnimationLibrary = load(LIB)
	# Constants are read off a bare instance. instantiate() alone does not fire
	# _enter_tree, so no model is built and nothing needs cleaning up but this.
	var e: Node = ENEMY.instantiate()

	var states := {}
	for n in sm.get_node_list():
		states[String(n)] = true
	print("  tree has %d states, library has %d clips" % [
		states.size(), lib.get_animation_list().size(),
	])

	# 1. Every pooled name must exist as a state.
	var pools := {
		"LOCO_POOL": e.LOCO_POOL,
		"ATTACK_POOL": e.ATTACK_POOL,
		"TELEGRAPH_POOL": e.TELEGRAPH_POOL,
		"HIT_POOL": e.HIT_POOL,
		"DEATH_POOL": e.DEATH_POOL,
	}
	for pool_name in pools:
		var missing: Array[String] = []
		for s in pools[pool_name]:
			if not states.has(String(s)):
				missing.append(String(s))
		_check("%s: all %d states exist" % [pool_name, pools[pool_name].size()],
			missing.is_empty(), ", ".join(missing))

	# The curated sets are named directly in _pick_anims, not via a pool, so
	# they need checking too — they are exactly as easy to typo.
	for s in ["locomotion", "locomotion_pk", "attack1", "attack2",
			"pk_attack1", "pk_attack2", "telegraph", "hit", "death",
			"injured", "baseball"]:
		if not states.has(s):
			_check("curated state '%s' exists" % s, false)

	# An attack pair is drawn by shuffle, so both entries must be distinct
	# states — a pool of one would hand out the same clip twice.
	_check("attack pool has 2+ entries", e.ATTACK_POOL.size() >= 2)

	e.free()

	# 2. Spawn a sample and confirm what actually gets rolled.
	var seen := {}
	var pairs_same := 0
	for i in SAMPLE:
		var en := ENEMY.instantiate()
		en.set_creature(i % 4)
		add_child(en)
		var set_of := {
			"loco": en._loco, "atk1": en._atk1, "atk2": en._atk2,
			"tele": en._tele, "hit": en._hit_anim, "death": en._death_anim,
		}
		for k in set_of:
			var v: String = set_of[k]
			if not states.has(v):
				_check("spawned %s rolled unknown state '%s'" % [k, v], false)
			seen[v] = int(seen.get(v, 0)) + 1
		if en._atk1 == en._atk2:
			pairs_same += 1
		en.queue_free()
	await get_tree().process_frame

	_check("no enemy drew the same clip for both attacks", pairs_same == 0)

	# 3. Coverage: over 240 spawns every pooled variant should have appeared.
	# If one never does, the draw is not reaching it — a pool that is defined
	# but unreachable is the failure this catches.
	var unused: Array[String] = []
	for pool_name in pools:
		for s in pools[pool_name]:
			if not seen.has(String(s)):
				unused.append(String(s))
	_check("every pooled variant appeared in %d spawns" % SAMPLE,
		unused.is_empty(), ", ".join(unused))

	# Mutant and Pumpkinhulk must keep their authored locomotion and attacks.
	var drift := 0
	for i in 60:
		var en := ENEMY.instantiate()
		en.set_creature(0 if i % 2 == 0 else 1)
		add_child(en)
		var want_loco := "locomotion" if i % 2 == 0 else "locomotion_pk"
		var want_atk := "attack1" if i % 2 == 0 else "pk_attack1"
		if en._loco != want_loco or en._atk1 != want_atk:
			drift += 1
		en.queue_free()
	await get_tree().process_frame
	_check("Mutant and Pumpkinhulk keep their authored sets", drift == 0)

	print("")
	for k in seen:
		print("    %-16s %d" % [k, seen[k]])
	print("")
	print("=== %s ===" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	get_tree().quit(1 if failures > 0 else 0)


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		failures += 1
	var line := "  %-52s %s" % [label, "PASS" if ok else "FAIL"]
	if not ok and detail != "":
		line += "  (%s)" % detail
	print(line)
