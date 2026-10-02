extends RefCounted

## Instance-local finishes only. Authored geometry, textures and sockets remain intact.
const CONTACT := preload("res://shaders/combat_contact_shadow.gdshader")
const CLOTH_PARTS := [7, 15, 27, 31, 32, 44]

static func apply(root: Node3D, player_model: bool = false) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		var part := String(mesh.name).trim_prefix("tripo_part_").to_int()
		var cloth := player_model and String(mesh.name).begins_with("tripo_part_") and part in CLOTH_PARTS
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface) as StandardMaterial3D
			if source == null:
				continue
			var finish := source.duplicate() as StandardMaterial3D
			finish.resource_name = "Combat / canvas" if cloth else "Combat / enamel and metal"
			finish.roughness = maxf(source.roughness, 0.88) if cloth else clampf(source.roughness * 0.74, 0.44, 0.68)
			finish.metallic = source.metallic if cloth else maxf(source.metallic, 0.18)
			finish.rim_enabled = not cloth
			finish.rim = 0.22
			finish.rim_tint = 0.25
			mesh.set_surface_override_material(surface, finish)

static func add_contact(root: Node3D) -> void:
	if root.has_node("CombatContactShadow"):
		return
	var shadow := MeshInstance3D.new()
	shadow.name = "CombatContactShadow"
	shadow.set_meta("ignore_hit_flash", true)
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.7, 1.7)
	shadow.mesh = plane
	shadow.position.y = 0.021
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = CONTACT
	# Explicit values keep visibility/echo sampling valid with the headless backend.
	material.set_shader_parameter("visibility_opacity", 1.0)
	material.set_shader_parameter("visibility_silhouette", 0.0)
	shadow.material_override = material
	root.add_child(shadow)
