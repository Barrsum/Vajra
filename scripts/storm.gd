extends Node3D
## Random lightning over the garden.
##
## A strike picks one target — a living creature, or the player — and does one
## of two things:
##
##   creature   loses 10% of its MAX health. Ten strikes would kill anything,
##              which is deliberate: it can soften a Colossus but never trade
##              places with you actually fighting it.
##   player     the next landed attack deals 10% more. Charge, not damage, so
##              the storm is never something that just kills you from off
##              screen — the worst case is a wasted strike.
##
## Targets are weighted toward creatures, so it mostly reads as the storm
## helping. Hitting the player is the surprise, and it is a gift.

const LIGHTNING_SHADER := preload("res://shaders/lightning.gdshader")
const FxTextures := preload("res://scripts/fx_textures.gd")

## Seconds between strikes, picked uniformly in this range.
@export var interval := Vector2(4.5, 11.0)
## Chance a strike targets the player rather than a creature.
@export var player_chance := 0.22
## Fraction of max health a strike removes from a creature.
@export var creature_damage := 0.10
## How much the player's next hit is boosted.
@export var charge_bonus := 0.10
@export var strike_height := 26.0

var player: Node3D
var _t := 0.0
var _next := 3.0


func _ready() -> void:
	_next = randf_range(interval.x, interval.y)


func _process(delta: float) -> void:
	if Game.state != Game.State.PLAYING:
		return
	_t += delta
	if _t < _next:
		return
	_t = 0.0
	_next = randf_range(interval.x, interval.y)
	_strike()


func _strike() -> void:
	var target: Node3D = null
	var on_player := false

	var alive: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.has_method("is_alive") and e.is_alive():
			alive.append(e)

	if player != null and (alive.is_empty() or randf() < player_chance):
		target = player
		on_player = true
	elif not alive.is_empty():
		target = alive[randi() % alive.size()]

	if target == null:
		return

	var at := target.global_position
	_bolt(at, on_player)

	if on_player:
		if player.has_method("charge_next_hit"):
			player.charge_next_hit(charge_bonus)
		Sfx.play_at(&"heal", at + Vector3.UP * 1.2)
		Vfx.shockwave(at, Color(0.62, 0.72, 1.0), 3.2)
		Vfx.impact_flash(at + Vector3.UP * 1.1, Color(0.75, 0.82, 1.0), 1.2)
	else:
		# 10% of MAX health, so it scales with the target rather than being
		# lethal to a small one and meaningless to a Colossus.
		var dmg: float = target.max_health * creature_damage
		# Zero knockback: a bolt from directly overhead has no direction to
		# push in, and shoving a creature on every strike would wreck spacing.
		target.take_damage(dmg, at + Vector3.UP * 4.0, 0.0)
		Sfx.play_at(&"impact", at + Vector3.UP * 1.2)
		Vfx.impact_flash(at + Vector3.UP * 1.0, Color(0.7, 0.8, 1.0), 1.0)


## The visible bolt: two crossed quads so it reads from any angle, plus a brief
## light. Crossed quads rather than a billboard because the strike is over in
## a fifth of a second — long enough to see, too short to notice the seam.
func _bolt(at: Vector3, friendly: bool) -> void:
	var col := Color(0.55, 0.72, 1.0) if not friendly else Color(0.72, 0.9, 1.0)
	var root := Node3D.new()
	add_child(root)
	root.global_position = at

	var mat := ShaderMaterial.new()
	mat.shader = LIGHTNING_SHADER
	mat.set_shader_parameter("Main_Color", Color(1, 1, 1))
	mat.set_shader_parameter("Effect_Color", col)
	mat.set_shader_parameter("Power_Texture", FxTextures.bolt_falloff())
	mat.set_shader_parameter("Speed", randf_range(2.0, 4.5))
	mat.set_shader_parameter("Y_Size", 5.0)
	mat.set_shader_parameter("X_Size", 1.0)
	mat.set_shader_parameter("Emission_Power", 4.0)
	mat.set_shader_parameter("Octave_Count", 8)

	for i in 2:
		var mi := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(5.0, strike_height)
		mi.mesh = qm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		mi.position = Vector3(0, strike_height * 0.5, 0)
		mi.rotation.y = PI * 0.5 * float(i)

	var fl := OmniLight3D.new()
	fl.light_color = col
	fl.light_energy = 22.0
	fl.omni_range = 34.0
	fl.shadow_enabled = false
	root.add_child(fl)
	fl.position = Vector3(0, 3.0, 0)

	# Flash out fast. A bolt that lingers stops reading as lightning.
	var tw := create_tween()
	tw.tween_property(fl, "light_energy", 0.0, 0.22)
	tw.parallel().tween_method(
		func(v: float) -> void: mat.set_shader_parameter("Emission_Power", v),
		4.0, 0.0, 0.22)
	tw.tween_callback(root.queue_free)
