extends SceneTree
func _xf(n: Node, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	while n != root and n != null:
		if n is Node3D: t = n.transform * t
		n = n.get_parent()
	return t
func _init():
	for f in ["props/trafficlight", "props/lamp", "props/palm", "buildings/gasstation", "buildings/beachhouse", "props/umbrella", "props/busstop", "props/bench", "buildings/hotel"]:
		var root = load("res://assets/" + f + ".glb").instantiate()
		for cs in root.find_children("*", "CollisionShape3D", true, false):
			var t = _xf(cs, root)
			var faces: PackedVector3Array = cs.shape.get_faces()
			var a = AABB(t * faces[0], Vector3.ZERO)
			for p in faces: a = a.expand(t * p)
			print(f, " ", cs.get_parent().name, " ", a.position, " size ", a.size)
		root.free()
	quit()
