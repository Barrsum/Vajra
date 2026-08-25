extends Node
## Measures where a generated prop's lowest point actually sits, at several
## heights, and dumps the imported node structure that produced it.
##
## Written because "the tree is half underground" is a symptom with at least
## three possible causes — a wrong AABB, a missed transform in the chain, or
## geometry that genuinely extends below the trunk — and they look identical
## on screen.

const Props := preload("res://scripts/props.gd")


func _ready() -> void:
	await get_tree().process_frame
	print("")
	for cat in ["forest", "cave", "dust", "night"]:
		for p in Props.list(cat):
			print("=== %s ===" % p)
			var raw: Node3D = (load(p) as PackedScene).instantiate()
			add_child(raw)
			await get_tree().process_frame
			print("  imported structure:")
			_dump(raw, 4)
			var rb := _global_bounds(raw)
			print("  raw aabb: base %.4f  top %.4f  height %.4f"
				% [rb.position.y, rb.position.y + rb.size.y, rb.size.y])
			raw.queue_free()

			for h in [4.0, 12.0, 24.0]:
				var n := Props.spawn_path(p, h)
				add_child(n)
				await get_tree().process_frame
				var b := _global_bounds(n)
				print("  asked %5.1fm -> base %+.4f  top %+.4f  actual %.3f"
					% [h, b.position.y, b.position.y + b.size.y, b.size.y])
				n.queue_free()
			print("")
	get_tree().quit(0)


func _dump(n: Node, indent: int) -> void:
	var pad := ""
	for i in indent:
		pad += " "
	var extra := ""
	if n is Node3D:
		var t: Transform3D = (n as Node3D).transform
		extra = "  origin=(%.2f, %.2f, %.2f) scale=%.2f" % [
			t.origin.x, t.origin.y, t.origin.z, t.basis.get_scale().y]
	print("%s%s (%s)%s" % [pad, n.name, n.get_class(), extra])
	for c in n.get_children():
		_dump(c, indent + 2)


func _global_bounds(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in _meshes(n):
		var b: AABB = (mi as MeshInstance3D).get_aabb()
		b = (mi as Node3D).global_transform * b
		out = b if first else out.merge(b)
		first = false
	return out


func _meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out
