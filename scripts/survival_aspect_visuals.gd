extends Node3D

const ASPECTS := preload("res://scripts/survival_aspects.gd")
var attachments: Array[Node3D] = []
var anchors: Array[Dictionary] = []
var actor: Node3D

func configure(player: Node3D, build: Dictionary) -> void:
	actor = player
	for category in ["weapon", "offensive", "defensive", "mobility", "passive"]:
		var aspect := ASPECTS.state(build, category)
		var id := str(aspect.get("path", ""))
		var level := int(aspect.get("rank", 0))
		if level <= 0 or not ASPECTS.DEFINITIONS.has(id):
			continue
		var mount := Node3D.new()
		mount.name = "Aspect_" + id
		var color := Color(str(ASPECTS.DEFINITIONS[id].color))
		attachments.append(mount)
		if category == "weapon":
			player._active_muzzle().add_child(mount)
			mount.position.z = 0.12
			mount.scale = Vector3.ONE * 0.78
			_weapon(mount, id, level, color)
		else:
			player._robot_visuals.add_child(mount)
			mount.position = {"offensive": Vector3(-0.43, 1.55, 0.15), "defensive": Vector3(0.0, 1.15, 0.30), "mobility": Vector3(0.0, 0.20, 0.18), "passive": Vector3(0.40, 1.0, 0.10)}[category]
			_module(mount, id, level, color)
			var bone := {"offensive": "mixamorig_LeftShoulder", "defensive": "mixamorig_Spine2", "mobility": "mixamorig_Hips", "passive": "mixamorig_Spine1"}
			var offset := {"offensive": Vector3(-0.10, 0.02, 0.05), "defensive": Vector3(0.0, 0.0, 0.24), "mobility": Vector3(0.22, 0.0, 0.14), "passive": Vector3(0.22, -0.05, 0.13)}
			if id in ["trail", "thruster"]:
				bone.mobility = "mixamorig_LeftFoot"
				offset.mobility = Vector3(0.0, 0.08, 0.13)
			_anchor(mount, bone[category], offset[category])
		if level == 3:
			var crown := _ring(mount, 0.19 if category == "weapon" else 0.25, color)
			crown.position.y = 0.08
			if category == "weapon":
				crown.rotation.x = PI * 0.5
			for side in [-1.0, 1.0]:
				_box(mount, Vector3(0.04, 0.16, 0.10), Vector3(side * 0.24, 0.0, 0.03), color, true)
		if id in ["trail", "thruster"]:
			var second := mount.duplicate() as Node3D
			second.name = "Aspect_" + id + "_right"
			player._robot_visuals.add_child(second)
			attachments.append(second)
			_anchor(second, "mixamorig_RightFoot", Vector3(0.0, 0.08, 0.13))
	_process(0.0)

func _anchor(mount: Node3D, bone: String, offset: Vector3) -> void:
	var skeleton: Skeleton3D = actor._visual_rig.skeleton
	if skeleton == null:
		return
	var index := skeleton.find_bone(bone)
	if index >= 0:
		anchors.append({"mount": mount, "bone": index, "offset": offset})

func _process(_delta: float) -> void:
	if not is_instance_valid(actor) or actor._visual_rig == null:
		return
	var skeleton: Skeleton3D = actor._visual_rig.skeleton
	if skeleton == null:
		return
	var body_basis: Basis = actor._robot_visuals.global_basis.orthonormalized()
	for entry in anchors:
		if is_instance_valid(entry.mount):
			entry.mount.global_position = skeleton.global_transform * skeleton.get_bone_global_pose(int(entry.bone)).origin + body_basis * entry.offset
			entry.mount.global_basis = body_basis.scaled(Vector3.ONE * 0.78)

func _weapon(mount: Node3D, id: String, level: int, color: Color) -> void:
	match id:
		"breaker":
			_barrel(mount, Vector3(0.0, -0.13, -0.08), 0.09 + level * 0.012, 0.28 + level * 0.06, color)
			_box(mount, Vector3(0.27, 0.04, 0.18), Vector3(0.0, 0.12, 0.1), color)
		"sweeper":
			for side in [-1.0, 1.0]:
				for row in range(level):
					var barrel := _barrel(mount, Vector3(side * (0.14 + row * 0.065), 0.0, 0.05), 0.038, 0.24, color)
					barrel.rotation.y = side * deg_to_rad(10.0 + row * 6.0)
		"rail":
			for side in [-1.0, 1.0]:
				_box(mount, Vector3(0.05, 0.07, 0.4 + level * 0.08), Vector3(side * 0.13, 0.0, 0.18), color)
			for index in range(level):
				var ring := _ring(mount, 0.14, color)
				ring.rotation.x = PI * 0.5
				ring.position.z = 0.12 + index * 0.12
		"arc":
			for index in range(2 + level):
				var angle := TAU * index / (2 + level)
				_box(mount, Vector3(0.045, 0.045, 0.28), Vector3(cos(angle) * 0.16, sin(angle) * 0.16, 0.13), color, true)
			var coil := _ring(mount, 0.19, color)
			coil.rotation.x = PI * 0.5

func _module(mount: Node3D, id: String, level: int, color: Color) -> void:
	_box(mount, Vector3(0.18, 0.19, 0.13), Vector3.ZERO, Color("#384451"))
	match id:
		"harpoon", "beacon":
			for index in range(level):
				_barrel(mount, Vector3(index * 0.06 - 0.08, 0.13, 0.0), 0.022, 0.32, color)
			if id == "beacon":
				_ring(mount, 0.18, color)
		"carapace", "counter":
			for index in range(level + 1):
				_box(mount, Vector3(0.30, 0.08, 0.04), Vector3(0.0, index * 0.09 - 0.1, 0.1), color, true)
			if id == "counter":
				var ring := _ring(mount, 0.20, color)
				ring.rotation.x = PI * 0.5
		"rampart", "capacitor":
			for side in [-1.0, 1.0]:
				_box(mount, Vector3(0.06, 0.20 + level * 0.04, 0.07), Vector3(side * 0.17, 0.05, 0.0), color, true)
			if id == "capacitor":
				for index in range(level):
					_barrel(mount, Vector3(0.0, index * 0.07, 0.10), 0.04, 0.14, color)
		"trail", "thruster":
			var jet := _barrel(mount, Vector3(0.0, 0.0, 0.07), 0.065 + level * 0.012, 0.18 + level * 0.03, color)
			jet.rotation.x = PI * 0.5
			if id == "thruster":
				_box(mount, Vector3(0.06, 0.12, 0.03), Vector3(0.12, 0.04, 0.0), color, true)
		"overdrive", "metabolism":
			for index in range(level + 1):
				var tube := _barrel(mount, Vector3(-0.12 + index * 0.08, 0.22, 0.0), 0.025, 0.25, color)
				tube.rotation.x = PI * 0.5
		"revenge", "escape":
			var reactor := _ring(mount, 0.12 + level * 0.025, color)
			reactor.rotation.x = PI * 0.5
			_box(mount, Vector3(0.06, 0.06, 0.08), Vector3(0.0, 0.0, -0.08), color, true)
			if id == "escape":
				_box(mount, Vector3(0.08, 0.22, 0.05), Vector3(0.16, 0.0, 0.0), color)
		"reserve", "harvest":
			for index in range(level + 1):
				_box(mount, Vector3(0.055, 0.08, 0.08), Vector3(index * 0.07 - 0.10, 0.12, 0.0), color, true)
			if id == "harvest":
				_ring(mount, 0.20, color)

func _material(color: Color, glow: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color.lerp(Color("#49515a"), 0.30 if glow else 0.75)
	material.metallic = 0.7
	material.roughness = 0.35
	material.emission_enabled = glow
	material.emission = color
	material.emission_energy_multiplier = 0.40 if glow else 0.0
	return material

func _box(parent: Node3D, size: Vector3, at: Vector3, color: Color, glow: bool = false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = _material(color, glow)
	parent.add_child(node)
	node.position = at
	return node

func _barrel(parent: Node3D, at: Vector3, radius: float, length: float, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius * 1.25
	mesh.height = length
	node.mesh = mesh
	node.material_override = _material(color)
	parent.add_child(node)
	node.position = at
	node.rotation.x = PI * 0.5
	return node

func _ring(parent: Node3D, radius: float, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius * 0.91
	mesh.outer_radius = radius
	node.mesh = mesh
	node.material_override = _material(color, true)
	parent.add_child(node)
	return node

func clear_visuals() -> void:
	anchors.clear()
	for attachment in attachments:
		if is_instance_valid(attachment):
			if attachment.get_parent() != null:
				attachment.get_parent().remove_child(attachment)
			attachment.queue_free()
	attachments.clear()

func _exit_tree() -> void:
	clear_visuals()
