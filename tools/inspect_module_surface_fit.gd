extends SceneTree
## Read-only triangle/texture anatomy audit, including the final idle pose.
const MODEL := preload("res://art/player_mecha_animated.glb")
const UNITS := 3.05 / 0.86084
var skeleton: Skeleton3D
var skin_deltas: Array[Transform3D] = []
var candidates := {"bio": [], "rocket": [], "reactor": []}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var model := MODEL.instantiate() as Node3D
	root.add_child(model)
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var animator := model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for clip in animator.get_animation_list():
		if String(clip).to_lower().ends_with("idle"):
			animator.play(clip, 0.0)
			animator.seek(.35, true)
			animator.advance(0.0)
			break
	skeleton.force_update_all_bone_transforms()
	await process_frame
	for i in skeleton.get_bone_count():
		skin_deltas.append(skeleton.get_bone_global_pose(i) * skeleton.get_bone_global_rest(i).affine_inverse())
	var inverse := skeleton.global_transform.affine_inverse()
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or mesh.skin == null:
			continue
		var transform: Transform3D = inverse * mesh.global_transform
		var bind_bones: Array[int] = []
		for bind in mesh.skin.get_bind_count():
			var bone: int = skeleton.find_bone(mesh.skin.get_bind_name(bind))
			if bone < 0:
				bone = mesh.skin.get_bind_bone(bind)
			bind_bones.append(bone)
		for surface in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var influences: int = bones.size() / positions.size()
			var image: Image
			var material := mesh.get_active_material(surface) as StandardMaterial3D
			if material != null and material.albedo_texture != null:
				image = material.albedo_texture.get_image()
				if image != null and image.is_compressed():
					image.decompress()
			for triangle in range(0, indices.size(), 3):
				var rest: Array[Vector3] = []
				var posed: Array[Vector3] = []
				var uv := Vector2.ZERO
				var ownership: Dictionary = {}
				for corner in 3:
					var vertex: int = indices[triangle+corner]
					var point: Vector3 = transform * positions[vertex]
					rest.append(point * UNITS)
					uv += uvs[vertex] / 3.0
					var final_point := Vector3.ZERO
					for influence in influences:
						var offset: int = vertex*influences+influence
						var weight: float = weights[offset]
						var bone: int = bind_bones[bones[offset]]
						if weight > .00001 and bone >= 0:
							final_point += (skin_deltas[bone] * point) * weight
							ownership[bone] = float(ownership.get(bone, 0.0)) + weight/3.0
					posed.append(final_point * UNITS)
				var center: Vector3 = (rest[0]+rest[1]+rest[2])/3.0
				var normal: Vector3 = (rest[2]-rest[0]).cross(rest[1]-rest[0]).normalized()
				var posed_center: Vector3 = (posed[0]+posed[1]+posed[2])/3.0
				var posed_normal: Vector3 = (posed[2]-posed[0]).cross(posed[1]-posed[0]).normalized()
				var color := Color(.5, .5, .5)
				if image != null:
					color = image.get_pixel(clampi(int(fposmod(uv.x,1.0)*image.get_width()),0,image.get_width()-1), clampi(int(fposmod(uv.y,1.0)*image.get_height()),0,image.get_height()-1))
				var selected := -1
				var highest := 0.0
				for bone in ownership:
					if float(ownership[bone]) > highest:
						highest = float(ownership[bone])
						selected = int(bone)
				if selected < 0:
					continue
				var label: String = skeleton.get_bone_name(selected).to_lower().replace("mixamorig_", "").replace("mixamorig:", "")
				# Reject saturated red cloth; textured ochre hardware also fails
				# this conservative filter, retaining definite cream/steel armor.
				if color.r > color.g*1.35 and color.r > color.b*1.45:
					continue
				var mount_inverse: Transform3D = skin_deltas[selected].affine_inverse()
				var idle_mount_center: Vector3 = (mount_inverse * (posed_center/UNITS))*UNITS
				var idle_mount_normal: Vector3 = (mount_inverse.basis * posed_normal).normalized()
				var record := {"rest": _vec(center), "posed": _vec(posed_center), "normal": _vec(normal), "posed_normal": _vec(posed_normal), "bone": label, "rigidity": highest, "color": [color.r,color.g,color.b], "bone_offset": _vec(center-skeleton.get_bone_global_rest(selected).origin*UNITS), "idle_mount_offset": _vec(idle_mount_center-skeleton.get_bone_global_rest(selected).origin*UNITS), "idle_mount_normal": _vec(idle_mount_normal), "triangle": [_vec(rest[0]),_vec(rest[1]),_vec(rest[2])]}
				var long_y: Vector3 = (Vector3.RIGHT-idle_mount_normal*Vector3.RIGHT.dot(idle_mount_normal)).normalized()
				record["source_x_long_euler"] = _vec(Basis(long_y.cross(idle_mount_normal),long_y,idle_mount_normal).get_euler())
				var posed_x: Vector3 = Vector3.UP.cross(posed_normal).normalized()
				var posed_y: Vector3 = posed_normal.cross(posed_x).normalized()
				record["idle_upright_euler"] = _vec((mount_inverse.basis*Basis(posed_x,posed_y,posed_normal)).get_euler())
				if center.x >= .18 and center.x <= .45 and center.y >= 1.86 and center.y <= 2.20 and normal.z > .35 and label in ["spine", "spine1", "spine2", "leftshoulder"]:
					record["score"] = center.distance_to(Vector3(.31,2.03,.49))
					candidates.bio.append(record)
				if center.x >= .55 and center.x <= .80 and center.y >= 2.15 and center.y <= 2.35 and normal.z > .20 and label == "leftarm":
					record["score"] = center.distance_to(Vector3(.64,2.25,.34))
					candidates.rocket.append(record)
				if center.x >= .55 and center.x <= .85 and center.y >= 2.0 and center.y <= 2.35 and normal.z < -.30 and label == "leftarm":
					record["score"] = center.distance_to(Vector3(.65,2.20,-.02))
					candidates.reactor.append(record)
	for area in candidates:
		var records: Array = candidates[area]
		records.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return float(a.score)<float(b.score))
		print("FIT AREA ", area, " count=", records.size())
		for record in records.slice(0,12):
			print("FIT ",area," ",JSON.stringify(record))
	quit()

func _vec(value: Vector3) -> Array:
	return [snappedf(value.x,.0001),snappedf(value.y,.0001),snappedf(value.z,.0001)]
