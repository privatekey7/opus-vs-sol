class_name AnimUtil
extends RefCounted
## Helpers for the people GLBs: clip lookup without library prefixes and one-frame pose clips.

# Body yaw (relative to the aim direction, atan2(x, z) convention) at which the "aim" pose at
# 0.8 s points the mounted weapon straight ahead: hero_yaw from assets/weapon_mounts.json.
const AIM_YAW := 0.956271588802338
const PEOPLE_SCALE := {
	"hero": 1.7444954588, "cop": 1.7843919564, "tourist": 1.7505452665, "woman": 1.4812555337,
	"thug": 1.8290786731, "bikini": 1.6260519810, "jogger": 1.7492516445, "businessman": 1.7610197929,
}


static func clip_names(ap: AnimationPlayer) -> Dictionary:
	## short name ("walk") -> full name ("lib/walk" or "walk")
	var out := {}
	for full_name in ap.get_animation_list():
		var short: String = full_name.get_slice("/", full_name.get_slice_count("/") - 1)
		out[short] = full_name
	return out


static func make_pose_clip(ap: AnimationPlayer, names: Dictionary, new_name: String, src_clip: String, t: float) -> void:
	## Builds a looping one-frame clip by sampling every track of src_clip at time t.
	if names.has(new_name):
		return
	var full: String = names[src_clip]
	var lib_name := full.get_slice("/", 0) if full.contains("/") else ""
	var lib := ap.get_animation_library(lib_name)
	if lib.has_animation(new_name):
		names[new_name] = (lib_name + "/" + new_name) if lib_name != "" else new_name
		return
	var src := ap.get_animation(full)
	var a := Animation.new()
	a.length = 0.1
	a.loop_mode = Animation.LOOP_LINEAR
	for i in src.get_track_count():
		var type := src.track_get_type(i)
		var ni := a.add_track(type)
		a.track_set_path(ni, src.track_get_path(i))
		match type:
			Animation.TYPE_POSITION_3D:
				a.position_track_insert_key(ni, 0.0, src.position_track_interpolate(i, t))
			Animation.TYPE_ROTATION_3D:
				a.rotation_track_insert_key(ni, 0.0, src.rotation_track_interpolate(i, t))
			Animation.TYPE_SCALE_3D:
				a.scale_track_insert_key(ni, 0.0, src.scale_track_interpolate(i, t))
			Animation.TYPE_BLEND_SHAPE:
				a.blend_shape_track_insert_key(ni, 0.0, src.blend_shape_track_interpolate(i, t))
			Animation.TYPE_VALUE:
				a.track_insert_key(ni, 0.0, src.value_track_interpolate(i, t))
	lib.add_animation(new_name, a)
	names[new_name] = (lib_name + "/" + new_name) if lib_name != "" else new_name


static var _mounts: Dictionary


static func attach_weapon(model: Node3D, weapon_scene: PackedScene, weapon_id: String) -> Node3D:
	## Mounts a weapon in the right hand using assets/weapon_mounts.json (calibrated on hero's aim pose).
	if _mounts.is_empty():
		_mounts = JSON.parse_string(FileAccess.get_file_as_string("res://assets/weapon_mounts.json"))
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var attachment := skeleton.get_node_or_null("RightHandMount") as BoneAttachment3D
	if attachment == null:
		attachment = BoneAttachment3D.new()
		attachment.name = "RightHandMount"
		skeleton.add_child(attachment)
		attachment.bone_name = "mixamorig_RightHand"
	for c in attachment.get_children():
		c.queue_free()
	if weapon_scene == null:
		return null
	var info: Dictionary = _mounts[weapon_id]
	var b: Array = info.local_basis
	var o: Array = info.local_origin
	# Pivot between the bone and the weapon so code can swing the weapon (the attachment
	# itself is overwritten by the bone pose every frame).
	var pivot := Node3D.new()
	attachment.add_child(pivot)
	var weapon: Node3D = weapon_scene.instantiate()
	pivot.add_child(weapon)
	weapon.transform = Transform3D(
		Basis(Vector3(b[0], b[1], b[2]), Vector3(b[3], b[4], b[5]), Vector3(b[6], b[7], b[8])),
		Vector3(o[0], o[1], o[2]))
	for gi in weapon.find_children("*", "GeometryInstance3D", true, false):
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return weapon
