extends SceneTree

func _tri(mesh: Mesh) -> int:
	var t := 0
	for s in mesh.get_surface_count():
		var arr = mesh.surface_get_arrays(s)
		if arr[Mesh.ARRAY_INDEX] != null and arr[Mesh.ARRAY_INDEX].size() > 0:
			t += arr[Mesh.ARRAY_INDEX].size() / 3
		else:
			t += arr[Mesh.ARRAY_VERTEX].size() / 3
	return t

func _walk(n: Node, depth: int, verbose: bool, acc: Dictionary) -> void:
	var line := "  ".repeat(depth) + n.name + " [" + n.get_class() + "]"
	if n is MeshInstance3D and n.mesh:
		var t = _tri(n.mesh)
		acc.tris += t
		acc.meshes += 1
		line += " tris=%d surf=%d lods=%d" % [t, n.mesh.get_surface_count(), RenderingServer.mesh_get_surface(n.mesh.get_rid(), 0).get("lods", []).size()]
		if n.skin: line += " skinned"
	if n is CollisionShape3D and n.shape:
		line += " " + str(n.shape)
		if n.shape is BoxShape3D: line += " size=" + str(n.shape.size) + " at " + str((n as Node3D).global_transform.origin if n.is_inside_tree() else n.transform.origin)
	if n is AnimationPlayer:
		line += " anims=" + str(n.get_animation_list())
	if n is Node3D and n.transform != Transform3D.IDENTITY:
		line += " xf=" + str(n.transform.origin) + (" rot" if n.transform.basis != Basis.IDENTITY else "")
	if verbose and depth < 6:
		print(line)
	for c in n.get_children():
		_walk(c, depth + 1, verbose, acc)

func _init():
	var args = OS.get_cmdline_user_args()
	var verbose = args.size() > 0
	var files = []
	for d in ["buildings", "people", "props", "vehicles", "weapons"]:
		for f in DirAccess.get_files_at("res://assets/" + d):
			if f.ends_with(".glb"):
				files.append("res://assets/" + d + "/" + f)
	for f in files:
		if verbose and not f.contains(args[0]): continue
		var t0 = Time.get_ticks_msec()
		var sc = load(f)
		var inst = sc.instantiate()
		var acc = {"tris": 0, "meshes": 0}
		_walk(inst, 0, verbose, acc)
		print("%s tris=%d meshes=%d load=%dms" % [f, acc.tris, acc.meshes, Time.get_ticks_msec() - t0])
		inst.free()
	quit()
