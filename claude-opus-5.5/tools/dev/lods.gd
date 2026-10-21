extends SceneTree
func _walk(n: Node, f: String):
	if n is MeshInstance3D and n.mesh:
		var s = RenderingServer.mesh_get_surface(n.mesh.get_rid(), 0)
		var out = "%s %s base=%d aabb=%s" % [f.get_file(), n.name, s.index_count/3 if s.has("index_count") else -1, str(n.get_aabb().size)]
		for l in s.get("lods", []):
			out += " | e=%.3f t=%d" % [l.edge_length, l.index_data.size() / 4 / 3 if s.vertex_count > 65535 else l.index_data.size()/2/3]
		print(out)
		var mat = n.mesh.surface_get_material(0)
		if mat: print("   mat ", mat, " ", mat.get_class(), " transp=", mat.transparency if mat is BaseMaterial3D else "")
	for c in n.get_children(): _walk(c, f)
func _init():
	for d in ["buildings", "people", "props", "vehicles"]:
		for f in DirAccess.get_files_at("res://assets/" + d):
			if f.ends_with(".glb"):
				var i = load("res://assets/" + d + "/" + f).instantiate()
				_walk(i, f)
				i.free()
	quit()
