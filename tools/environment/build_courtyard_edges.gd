extends SceneTree
## Offline visual-only dressing, sampled from the existing collision footprints.
## Small dry tufts are clearly shorter than the functional hiding vegetation.
var _random := RandomNumberGenerator.new()
var _batches: Array = []

func _initialize() -> void:
	call_deferred("_build")

func _build() -> void:
	_random.seed = 20261002
	for _index in range(8):
		_batches.append({"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(), "uv": PackedVector2Array()})
	var arena := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(arena)
	var tuft_count := 0
	for body in get_nodes_in_group("arena_solid"):
		if body.get_meta("invisible_safety_limit", false):
			continue
		var shape := body.get_node("Collision").shape as BoxShape3D
		var size := shape.size
		var longitudinal_x := size.x >= size.z
		for side in [-1.0, 1.0]:
			for slot in range(3):
				var along: float = (-0.38 + float(slot) * 0.38) * maxf(size.x, size.z)
				var inset := minf(size.x, size.z) * .5 + _random.randf_range(.10, .35)
				var local := Vector3(along, -size.y*.5, side*inset) if longitudinal_x else Vector3(side*inset,-size.y*.5,along)
				var position: Vector3 = body.to_global(local)
				position.y = .015
				if maxf(absf(position.x), absf(position.z)) > 28.5:
					continue
				var quadrant := (0 if position.x < 0 else 1) + (0 if position.z < 0 else 2)
				_tuft(position, quadrant)
				tuft_count += 1
				for _pebble in range(3):
					var offset := Vector3(_random.randf_range(-.35,.35),0,_random.randf_range(-.20,.20))
					_rock(position+offset, quadrant+4)
	var dressing := Node3D.new()
	dressing.name = "CourtyardEdges"
	dressing.set_meta("visual_only", true)
	dressing.set_meta("short_tuft_count", tuft_count)
	for index in _batches.size():
		var data: Dictionary = _batches[index]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = data.v
		arrays[Mesh.ARRAY_NORMAL] = data.n
		arrays[Mesh.ARRAY_COLOR] = data.c
		arrays[Mesh.ARRAY_TEX_UV] = data.uv
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		if index < 4:
			var material := ShaderMaterial.new()
			material.shader = load("res://scripts/bush_foliage.gdshader")
			material.set_shader_parameter("wind_strength", .45)
			mesh.surface_set_material(0, material)
		else:
			var material := StandardMaterial3D.new()
			material.vertex_color_use_as_albedo = true
			material.roughness = .95
			mesh.surface_set_material(0, material)
		var path := "res://art/environment/courtyard_edges_%d.res" % index
		ResourceSaver.save(mesh, path)
		var instance := MeshInstance3D.new()
		instance.name = "DryTufts%d" % index if index < 4 else "GroundChips%d" % index
		instance.mesh = load(path)
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.extra_cull_margin = .08
		dressing.add_child(instance)
		instance.owner = dressing
	var packed := PackedScene.new()
	packed.pack(dressing)
	ResourceSaver.save(packed, "res://scenes/environment/courtyard_edges.tscn")
	print("COURTYARD EDGES: ", tuft_count, " short tufts; 8 spatial batches; no physics")
	var sfx := root.get_node_or_null("GameSfx")
	if sfx != null:
		sfx.call("clear")
	arena.queue_free()
	dressing.free()
	await process_frame
	quit()

func _triangle(batch: int, a: Vector3, b: Vector3, c: Vector3, color: Color, heights := Vector3.ZERO) -> void:
	var data: Dictionary = _batches[batch]
	var normal := (b-a).cross(c-a).normalized()
	if batch >= 4 and normal.y < 0:
		var swap := b
		b = c
		c = swap
		normal = -normal
	# Godot uses clockwise winding for the outward normal.
	data.v.append_array(PackedVector3Array([a,c,b]))
	data.n.append_array(PackedVector3Array([normal,normal,normal]))
	for t in [heights.x,heights.z,heights.y]:
		var tint := Color("#706746").lerp(color, .45 + t*.55) if batch < 4 else color
		data.c.append(tint.srgb_to_linear() if batch < 4 else tint)
		data.uv.append(Vector2(0,t))

func _tuft(position: Vector3, batch: int) -> void:
	var palette := [Color("#a3945d"),Color("#b8a169"),Color("#8f9467"),Color("#c6ac73")]
	for blade in range(9):
		var angle := float(blade)*2.39996 + _random.randf_range(-.3,.3)
		var direction := Vector3(cos(angle),0,sin(angle))
		var side := Vector3(-direction.z,0,direction.x)
		var base := position + direction*_random.randf_range(.01,.13)
		var height := _random.randf_range(.25,.62)
		var middle := base + Vector3.UP*height*.55 + direction*.07
		var tip := base + Vector3.UP*height + direction*_random.randf_range(.10,.25)
		var width := _random.randf_range(.025,.052)
		var color: Color = palette[blade%palette.size()]
		_triangle(batch,base-side*width*.4,middle-side*width,base+side*width*.4,color,Vector3(0,.55,0))
		_triangle(batch,base+side*width*.4,middle-side*width,middle+side*width,color,Vector3(0,.55,.55))
		_triangle(batch,middle-side*width,tip,middle+side*width,color,Vector3(.55,1,.55))

func _rock(position: Vector3, batch: int) -> void:
	var radius := _random.randf_range(.035,.095)
	var color := Color("#ac9773").lerp(Color("#7e7c6b"),_random.randf())
	var peak := position+Vector3(_random.randf_range(-.02,.02),radius*.65,0)
	for index in range(5):
		var a := float(index)*TAU/5
		var b := float(index+1)*TAU/5
		_triangle(batch,position+Vector3(cos(a)*radius,0,sin(a)*radius),peak,position+Vector3(cos(b)*radius,0,sin(b)*radius),color)
