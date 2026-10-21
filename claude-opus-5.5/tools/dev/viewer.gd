extends Node3D
# Dev tool: renders a model from several angles. Args after --: model_path [anim] [scale]
var cam: Camera3D
var model: Node3D
var frame := 0
var center := Vector3.ZERO
var radius := 3.0
var anim := ""

func _ready():
	var args = OS.get_cmdline_user_args()
	model = load(args[0]).instantiate()
	add_child(model)
	if args.size() > 1: anim = args[1]
	if args.size() > 2: model.scale = Vector3.ONE * float(args[2])
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
	var aabb := AABB()
	var first := true
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var a = mi.global_transform * mi.get_aabb()
		aabb = a if first else aabb.merge(a)
		first = false
	center = aabb.get_center()
	radius = aabb.size.length() * 0.9
	print("AABB ", aabb)
	if anim != "":
		center = Vector3(0, 0.9, 0)
		radius = 4.0
	if anim != "":
		var ap: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
		ap.play(anim)

func _process(_d):
	var views = [Vector3(0, 0.3, -1), Vector3(1, 0.3, 0), Vector3(0, 0.3, 1), Vector3(-1, 0.3, 0), Vector3(0.01, 1, 0.0)]
	var idx = min(frame / 10, views.size() - 1)
	if anim != "": idx = 1
	cam.position = center + views[idx].normalized() * radius
	cam.look_at(center, Vector3.UP if idx < 4 else Vector3.FORWARD)
	frame += 1
