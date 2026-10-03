extends Node3D
## The courtyard's final lighting/material pass. Uses the existing Mobile
## renderer, geometry, UV layout and local lamp budget. No actor or camera edits.
const SURFACE_FINISH = preload("res://scripts/environment/arena_surface_finish.gd")
const LIGHTING_PROFILE = preload("res://scripts/environment/arena_lighting_profile.gd")
const CONTACT_SHADOWS = preload("res://scripts/environment/arena_contact_shadows.gd")
@export var lighting_profile: Resource = LIGHTING_PROFILE.new()
var _surface_finish := SURFACE_FINISH.new()
const DETAILS := preload("res://art/environment/reference_finish/detail_builder.gd")
var _scene: Node3D
var _director: Node3D
var _materials: Dictionary = _surface_finish.materials
var _quality := -1
var _clock := 0.0
var _initialized := false
var _shadow_defaults: Array = []
var _original_msaa := Viewport.MSAA_DISABLED

func _ready() -> void:
	set_process(false)
	if OS.get_cmdline_user_args().has("reference-render-baseline"):
		return
	_director = get_parent() as Node3D
	_scene = _director.get_parent() as Node3D
	_configure.call_deferred()

func _configure() -> void:
	# Existing deferred presentation adapters run first. Shared source resources
	# are never changed, and a scene transition cannot leave a coroutine alive.
	if not is_inside_tree():
		return
	var tree := get_tree()
	for frame in range(2):
		await tree.process_frame
		if not is_inside_tree() or is_queued_for_deletion():
			return
	if not is_inside_tree() or not is_instance_valid(_scene):
		return
	_shadow_defaults = [
		int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size", 2048)),
		bool(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/16_bits", true)),
		int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality", 1)),
	]
	_original_msaa = get_viewport().msaa_3d
	_configure_lighting()
	for mesh in _scene.find_children("*", "MeshInstance3D", true, false):
		if _is_scenery(mesh):
			_surface_finish.finish_mesh(mesh)
	_surface_finish.finish_ground(_scene.get_node_or_null("Ground") as MeshInstance3D)
	_surface_finish.finish_exterior(_scene.get_node_or_null("ArenaExterior/ExteriorDustTerrain") as MeshInstance3D)
	_build_contacts()
	# Bounded static details are batched once. They belong to this presentation
	# branch so changing arenas hides them together with the workshops.
	DETAILS.new().build(self, _scene)
	_initialized = true
	_update_quality()
	set_process(true)
	set_meta("finished_materials", _materials.size())
	set_meta("visual_only", true)

func _is_scenery(mesh: MeshInstance3D) -> bool:
	if _director.is_ancestor_of(mesh):
		return true
	var branch: Node = mesh
	while branch != null and branch.get_parent() != _scene:
		branch = branch.get_parent()
	return branch != null and (branch.is_in_group("arena_solid") or branch.name in ["Ground", "ArenaExterior"])

func _configure_lighting() -> void:
	var environment: Environment
	for child in _scene.get_children():
		if child is WorldEnvironment:
			environment = child.environment
	lighting_profile.apply(environment, _scene.get_node_or_null("ArenaKeyLight") as DirectionalLight3D, _scene.get_node_or_null("CoolFillLight") as DirectionalLight3D)

func _build_contacts() -> void:
	var entries: Array[Node3D] = []
	for body in get_tree().get_nodes_in_group("arena_solid"):
		if _scene.is_ancestor_of(body) and not body.get_meta("invisible_safety_limit", false) and body.get_node_or_null("Collision") is CollisionShape3D:
			if (body.get_node("Collision") as CollisionShape3D).shape is BoxShape3D:
				entries.append(body)
	CONTACT_SHADOWS.build(self, entries)

func _process(delta: float) -> void:
	_clock += delta
	if _clock >= 0.25:
		_clock = 0.0
		_update_quality()

func _update_quality() -> void:
	var quality := int(_director.get_meta("active_quality", 1))
	if quality == _quality:
		return
	_quality = quality
	var details := get_node_or_null("ReferenceEdgeDetails")
	if details != null:
		for mesh in details.get_children():
			if mesh is MeshInstance3D:
				mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if quality > 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lighting_profile.apply_render_quality(get_viewport(), quality)
	set_meta("active_quality", quality)

func _exit_tree() -> void:
	if _initialized and DisplayServer.get_name() != "headless":
		# RenderingServer shadow controls are global; release this arena's budget.
		get_viewport().msaa_3d = _original_msaa
		RenderingServer.directional_shadow_atlas_set_size(_shadow_defaults[0], _shadow_defaults[1])
		RenderingServer.directional_soft_shadow_filter_set_quality(_shadow_defaults[2])
