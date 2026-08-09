extends Node
## Generates the AnimationTree state machine as a saved .tres, so it opens as a
## real editable graph in the editor rather than being conjured at runtime.
##
## Locomotion is a BlendSpace1D driven by planar speed — idle/walk/run blend
## continuously instead of snapping, which is most of why movement reads as
## smooth. Everything else is a discrete state the code travels to.
##
## Run: godot --headless --path . res://tests/build_anim_tree.tscn

const OUT := "res://assets/character/player_tree.tres"

# One-shot states. Locomotion is built separately as a blend space.
const STATES := ["jump", "fall", "land", "dodge", "attack1", "attack2", "attack3", "hit", "death"]

# Crossfade lengths. Snappy where responsiveness matters, softer where it reads
# as weight. These are feel values — expect to tune them.
const XFADE := {
	"jump": 0.06,
	"fall": 0.12,
	"land": 0.08,
	"dodge": 0.05,
	# Long enough that chaining reads as one continuous motion rather than a cut.
	"attack1": 0.13,
	"attack2": 0.13,
	"attack3": 0.13,
	"hit": 0.04,
	"death": 0.10,
	"locomotion": 0.14,
}


func _ready() -> void:
	print("")
	print("=== building animation tree ===")

	var sm := AnimationNodeStateMachine.new()

	# --- locomotion blend space ---
	var bs := AnimationNodeBlendSpace1D.new()
	bs.min_space = 0.0
	bs.max_space = 8.4
	bs.snap = 0.1
	# Each clip sits at the speed it was authored to travel at, measured from the
	# root motion we stripped: walk covered 1.72 m/s, run 4.56 m/s. Placing them
	# there is what keeps the feet planted instead of skating.
	bs.add_blend_point(_clip("idle"), 0.0, -1, "idle")
	bs.add_blend_point(_clip("walk"), 1.7, -1, "walk")
	bs.add_blend_point(_clip("run"), 4.6, -1, "run")
	bs.add_blend_point(_clip("sprint"), 8.4, -1, "sprint")
	sm.add_node("locomotion", bs, Vector2(320, 40))
	print("  locomotion blend space: idle@0.0  walk@1.7  run@4.6  sprint@8.4")

	# --- one-shot states ---
	var x := 60
	var y := 200
	for s in STATES:
		var node := _clip(s)
		# Jumping Up opens with an anticipation crouch, but the code applies jump
		# velocity immediately — so he'd be airborne while still crouching. Skip
		# straight to the launch pose.
		if s == "jump":
			if "start_offset" in node:
				node.start_offset = 0.20
				print("  jump: skipping 0.20s of anticipation")
			else:
				print("  jump: start_offset unavailable on this build")
		sm.add_node(s, node, Vector2(x, y))
		x += 210
		if x > 900:
			x = 60
			y += 120
	print("  states: %s" % ", ".join(STATES))

	# --- transitions ---
	sm.add_transition("Start", "locomotion", _t(0.0))

	var all := STATES.duplicate()
	all.append("locomotion")
	var count := 0
	for from in all:
		if from == "death":
			continue  # death is terminal
		for to in all:
			if from == to:
				continue
			# Direct transition for every pair, so travel() never routes through
			# an unrelated state and plays half a clip on the way.
			sm.add_transition(from, to, _t(XFADE.get(to, 0.1)))
			count += 1
	print("  transitions: %d" % count)

	var err := ResourceSaver.save(sm, OUT)
	print("")
	print("  saved -> %s" % OUT if err == OK else "  SAVE FAILED (%d)" % err)
	print("")
	get_tree().quit(0 if err == OK else 1)


func _clip(name: String) -> AnimationNodeAnimation:
	var n := AnimationNodeAnimation.new()
	n.animation = name
	return n


func _t(xfade: float) -> AnimationNodeStateMachineTransition:
	var t := AnimationNodeStateMachineTransition.new()
	t.xfade_time = xfade
	t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
	t.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
	return t
