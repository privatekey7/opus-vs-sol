extends Node3D
# Dev: hero with a weapon mounted, playing a clip. Args: weapon clip
var cam: Camera3D
var frame := 0
var hero: Node3D
var weapon: Node3D
func _ready():
	var args = OS.get_cmdline_user_args()
	var weapon_id = args[0]
	var clip = args[1]
	hero = load("res://assets/people/hero.glb").instantiate()
	hero.scale = Vector3.ONE * 1.7444954588
	add_child(hero)
	var skeleton = hero.find_children("*", "Skeleton3D", true, false)[0]
	var attachment = BoneAttachment3D.new()
	skeleton.add_child(attachment)
	attachment.bone_name = "mixamorig_RightHand"
	var mounts = JSON.parse_string(FileAccess.get_file_as_string("res://assets/weapon_mounts.json"))
	var info = mounts[weapon_id]
	var b = info.local_basis
	var o = info.local_origin
	weapon = load("res://assets/weapons/" + weapon_id + ".glb").instantiate()
	attachment.add_child(weapon)
	weapon.transform = Transform3D(Basis(Vector3(b[0], b[1], b[2]), Vector3(b[3], b[4], b[5]), Vector3(b[6], b[7], b[8])), Vector3(o[0], o[1], o[2]))
	var ap: AnimationPlayer = hero.find_children("*", "AnimationPlayer", true, false)[0]
	ap.play(clip)
	if args.size() > 2: ap.seek(float(args[2]), true); ap.pause()
	var env = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.5, 0.6, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	add_child(env)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	cam = Camera3D.new()
	add_child(cam)
	var grid = MeshInstance3D.new(); var pm = PlaneMesh.new(); pm.size = Vector2(4,4); grid.mesh = pm; add_child(grid)
	var axis = MeshInstance3D.new(); var bm = BoxMesh.new(); bm.size = Vector3(0.05,0.05,2); axis.mesh = bm; axis.position = Vector3(0,0.02,1); add_child(axis)
func _process(_d):
	var c = Vector3(0, 1.2, 0)
	var views = [Vector3(0, 0.6, 1), Vector3(1, 0.3, 0), Vector3(0.01, 1, 0)]
	var idx = min(frame / 10, 2)
	cam.position = c + views[idx].normalized() * 3.5
	cam.look_at(c, Vector3.UP if idx < 2 else Vector3.FORWARD)
	if frame == 5:
		var f = -weapon.global_transform.basis.z
		print("weapon fwd world ", f, " yaw ", atan2(f.x, f.z), " muzzle ", weapon.find_child("muzzle", true, false).global_position if weapon.find_child("muzzle", true, false) else Vector3.ZERO)
	frame += 1
