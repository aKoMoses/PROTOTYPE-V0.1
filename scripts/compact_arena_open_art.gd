extends RefCounted
## Open-arena architecture. Every object here is decorative MeshInstance3D;
## the stage's floor and boundary contract remain the only physical geometry.
## Repeated braces, fasteners, fins and inlays are merged by material.

static func build(stage: Node3D, arena_id: String) -> void:
	if arena_id == "gyre":
		_build_foundry(stage)
	elif arena_id == "resonance":
		_build_echo_hall(stage)


static func _build_foundry(stage: Node3D) -> void:
	var materials: Dictionary = stage.get("_materials")
	var iron: Material = materials["cast_iron"]
	var steel: Material = materials["foundry_steel"]
	var ochre: Material = materials["foundry_ochre"]
	var hot: Material = materials["molten_trim"]
	var dark := _material(stage, Color("#172128"), 0.68, 0.52)
	var copper := _material(stage, Color("#b8885b"), 0.37, 0.75)
	var structure := _surface()
	var ribs := _surface()
	var housings := _surface()
	var embers := _surface()
	var fine := _surface()
	# Deep edge girders, triangulated suspension and ventilated casting chambers
	# make the duel deck read as a machine suspended over the furnace lake.
	for side in [-1.0, 1.0]:
		for z in [side * 9.45]:
			_box(stage, structure, Vector3(0, -0.83, z), Vector3(13.4, 0.64, 0.55))
			_box(stage, ribs, Vector3(0, -0.53, z), Vector3(13.7, 0.09, 0.73))
			_box(stage, ribs, Vector3(0, -1.16, z), Vector3(13.7, 0.10, 0.73))
		for z in range(-5, 6, 2):
			var p := Vector3(side * 10.35, -0.89, float(z))
			_box(stage, structure, p, Vector3(0.6, 0.67, 1.6))
			_box(stage, housings, p + Vector3(side * 0.32, 0, 0), Vector3(0.08, 0.42, 1.28))
			for fin in range(5):
				_box(stage, ribs, p + Vector3(side * 0.39, 0, -0.48 + float(fin) * 0.24), Vector3(0.16, 0.59, 0.055))
			_box(stage, embers, p + Vector3(side * 0.36, -0.2, 0), Vector3(0.1, 0.055, 1.18))
		for i in range(6):
			var x := -5.8 + float(i) * 2.32
			var a := Vector3(x, -0.55, side * 9.8)
			var b := Vector3(x + 1.16, -1.82, side * 9.9)
			_beam(stage, ribs, a, b, 0.12)
			_beam(stage, ribs, b, a + Vector3(2.32, 0, 0), 0.12)
			_box(stage, housings, b, Vector3(0.54, 0.19, 0.52))
		# Armored service decks and low casting channels, safely beyond the hull.
		for z in [-5.5, 4.9]:
			var center := Vector3(side * 13.05, -0.75, z)
			_box(stage, structure, center, Vector3(5.1, 0.48, 3.4))
			_box(stage, ribs, center + Vector3(0, 0.27, 0), Vector3(5.15, 0.08, 3.47))
			for step in range(7):
				_box(stage, fine, center + Vector3(-2.15 + float(step) * 0.71, 0.32, 0), Vector3(0.08, 0.055, 3.05))
			for outside in [-1.0, 1.0]:
				_box(stage, housings, center + Vector3(0, 0.1, outside * 1.75), Vector3(5.2, 0.23, 0.21))
				_beam(stage, ribs, center + Vector3(-2.3, 0.7, outside * 1.75), center + Vector3(2.3, 0.7, outside * 1.75), 0.07)
				for post in range(5):
					_beam(stage, ribs, center + Vector3(-2.3 + float(post) * 1.15, 0.16, outside * 1.75), center + Vector3(-2.3 + float(post) * 1.15, 0.72, outside * 1.75), 0.065)
			_beam(stage, ribs, center + Vector3(-side * 2, -0.25, 0), center + Vector3(side * 1.75, -1.55, 0), 0.2)
			# Cooling mold channels have thick dark walls and a recessed orange core.
			_box(stage, structure, Vector3(side * 12.7, -1.55, z + 3.0), Vector3(2.6, 0.54, 1.15))
			_box(stage, embers, Vector3(side * 12.7, -1.265, z + 3.0), Vector3(2.20, 0.025, 0.63))
			for fin in range(6):
				_box(stage, ribs, Vector3(side * 12.7 - 1.2 + float(fin) * 0.48, -1.15, z + 3), Vector3(0.055, 0.18, 1.14))
		# Large cast footing silhouettes punctuate the lake instead of floating
		# boxes: tapering columns and diagonal shoes are tied back to the deck.
		for z in [-11.8, 10.8]:
			var base := Vector3(side * 15.9, -1.8, z)
			_box(stage, structure, base, Vector3(4.0, 0.5, 3.0))
			_box(stage, housings, base + Vector3(0, 0.48, 0), Vector3(2.4, 0.46, 2.2))
			_box(stage, structure, base + Vector3(0, 2.5, 0), Vector3(1.45, 4.5, 1.5))
			_box(stage, ribs, base + Vector3(0, 4.77, 0), Vector3(2.0, 0.14, 1.92))
			for flute in range(4):
				_box(stage, ribs, base + Vector3(-0.62 + float(flute) * 0.415, 2.5, 0.81), Vector3(0.09, 4.4, 0.12))
			_beam(stage, ribs, base + Vector3(-side * 0.8, 1.0, 0), Vector3(side * 10.5, -0.6, z * 0.70), 0.22)
			_box(stage, embers, base + Vector3(0, 4.87, 0), Vector3(1.5, 0.07, 1.45))
			_box(stage, fine, base + Vector3(0, 4.94, 0), Vector3(1.0, 0.045, 0.97))
	# Rear casting gallery: broad industrial silhouette, bays and real trusses.
	for x in [-13.5, -6.8, 6.8, 13.5]:
		_box(stage, structure, Vector3(x, 1.1, -20.5), Vector3(2.1, 6.4, 3.4))
		_box(stage, housings, Vector3(x, 4.48, -20.5), Vector3(2.9, 0.32, 4.1))
		_box(stage, fine, Vector3(x, 1.15, -18.72), Vector3(1.45, 3.8, 0.055))
		for louver in range(8):
			_box(stage, ribs, Vector3(x, -0.40 + float(louver) * 0.44, -18.62), Vector3(1.7, 0.10, 0.22))
		_box(stage, embers, Vector3(x, -1.15, -18.64), Vector3(1.7, 0.48, 0.09))
	_box(stage, structure, Vector3(0, 4.95, -20.5), Vector3(30.8, 0.7, 3.5))
	_box(stage, ribs, Vector3(0, 5.38, -18.6), Vector3(31.2, 0.11, 0.22))
	for i in range(12):
		var x := -14.4 + float(i) * 2.4
		_beam(stage, ribs, Vector3(x, 4.6, -18.7), Vector3(x + 1.2, 5.4, -18.7), 0.095)
		_beam(stage, ribs, Vector3(x + 1.2, 5.4, -18.7), Vector3(x + 2.4, 4.6, -18.7), 0.095)
		_box(stage, housings, Vector3(x + 1.2, 5.58, -19), Vector3(0.52, 0.27, 2.8))
	for x in [-10.15, 0.0, 10.15]:
		_box(stage, structure, Vector3(x, -0.35, -20.0), Vector3(4.1, 2.5, 2.6))
		_box(stage, embers, Vector3(x, 0.25, -18.62), Vector3(2.15, 0.52, 0.07))
		for bar in range(5):
			_box(stage, ribs, Vector3(x - 1.0 + float(bar) * 0.5, 0.25, -18.50), Vector3(0.10, 0.7, 0.16))
	# A few basalt shelves around the architecture break the flat lava plane.
	for i in range(10):
		var a := float(i) * 2.39996
		var p := Vector3(cos(a) * (22.0 + float(i % 3) * 3.0), -1.96, sin(a) * (21.0 + float(i % 2) * 5.0))
		stage.call("_cylinder", stage, "CooledBasaltShelf", 2.0 + float(i % 3) * 0.56, 0.36, p, dark, 1.9 + float(i % 3) * 0.50, 7)
	_finish(stage, stage, "SuspensionAndFoundryArchitecture", structure, iron)
	_finish(stage, stage, "GroupedSteelBracingAndCoolingFins", ribs, steel)
	_finish(stage, stage, "OchreMachineCasingsAndGalleryBands", housings, ochre)
	_finish(stage, stage, "RecessedCastingGlow", embers, hot, false)
	_finish(stage, stage, "MachinedCopperGrilles", fine, copper)
	_foundry_rotor_detail(stage, materials)


static func _foundry_rotor_detail(stage: Node3D, materials: Dictionary) -> void:
	var roots: Array = stage.get("_orbit_rings")
	var direction_cues: Array[Dictionary] = []
	for index in range(roots.size()):
		var parent: Node3D = roots[index]
		var seams := _surface()
		var plates := _surface()
		var inner := 0.9 if index == 0 else 4.0
		var outer := 4.0 if index == 0 else 7.6
		var count := 12 if index == 0 else 20
		for i in range(count):
			var a := TAU * float(i) / float(count)
			var radial := Vector3(cos(a), 0, sin(a))
			var tangent := Vector3(-sin(a), 0, cos(a))
			# Fine radial joints and inset slots reveal segmentation without
			# covering the steel shader or raising the navigable floor.
			_beam(stage, seams, radial * (inner + 0.16) + Vector3.UP * 0.033, radial * (outer - 0.16) + Vector3.UP * 0.033, 0.015)
			for radius in [inner + 0.30, outer - 0.30]:
				for offset in [-0.11, 0.11]:
					_box(stage, plates, radial * radius + tangent * offset + Vector3.UP * 0.035, Vector3(0.05, 0.007, 0.05))
			for offset in [-0.11, 0.0, 0.11]:
				_beam(stage, seams, radial * (outer - 0.68) + tangent * offset + Vector3.UP * 0.034, radial * (outer - 0.43) + tangent * offset + Vector3.UP * 0.034, 0.013)
		_finish(stage, parent, "RotorRadialJoinery", seams, materials["dark_metal"], false)
		_finish(stage, parent, "RotorFlushFastenerHeads", plates, materials["gold"], false)
		var entry := {"positive": Node3D.new(), "negative": Node3D.new(), "index": index}
		for positive in [true, false]:
			var cue: Node3D = entry.positive if positive else entry.negative
			cue.name = "PositiveRotorDirection" if positive else "NegativeRotorDirection"
			parent.add_child(cue)
			var arrows := _surface()
			var sign_value := -1.0 if positive else 1.0
			for i in range(6 if index == 0 else 10):
				var angle := TAU * float(i) / (6.0 if index == 0 else 10.0)
				var radial := Vector3(cos(angle), 0, sin(angle))
				var tangent := Vector3(-sin(angle), 0, cos(angle)) * sign_value
				var center := radial * (2.75 if index == 0 else 6.15) + Vector3.UP * 0.040
				for step in range(2):
					var p := center + tangent * (float(step) - 0.5) * 0.25
					_floor_triangle(stage, arrows, p - tangent * 0.15 - radial * 0.14, p + tangent * 0.14, p - tangent * 0.15 - radial * 0.07)
					_floor_triangle(stage, arrows, p - tangent * 0.15 + radial * 0.07, p + tangent * 0.14, p - tangent * 0.15 + radial * 0.14)
			_finish(stage, cue, "OpposedRotorDirectionInlays", arrows, materials["amber_glow"] if index == 0 else materials["aqua_glow"], false)
			cue.visible = positive == (index == 0)
		direction_cues.append(entry)
	stage.set_meta("open_orbit_direction_cues", direction_cues)


static func _build_echo_hall(stage: Node3D) -> void:
	var materials: Dictionary = stage.get("_materials")
	var midnight: Material = materials["midnight"]
	var alabaster: Material = materials["alabaster"]
	var nacre: Material = materials["nacre"]
	var champagne := _material(stage, Color("#b6a481"), 0.30, 0.75)
	var ivory := _material(stage, Color("#ede7d5"), 0.32, 0.22)
	var blue := _material(stage, Color("#416574"), 0.34, 0.50)
	var rose := _material(stage, Color("#705466"), 0.36, 0.43)
	var glow := _material(stage, Color("#a8d2d7"), 0.4, 0.2, Color("#8fbac4"), 0.45)
	# The concave inner surface must remain visible from an oblique overhead
	# view. Its matte finish also avoids a white specular disk at the mouth.
	var throat_material := _material(stage, Color("#101a23"), 0.86, 0.04) as StandardMaterial3D
	throat_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	throat_material.metallic_specular = 0.12
	var stone := _surface()
	var bases := _surface()
	var metal := _surface()
	var details := _surface()
	var light_lines := _surface()
	var tubes := _surface()
	var interiors := _surface()
	# Floating foundation has a dark shadow joint, gilded edge and repeating
	# grooved supports. Only its outside face and underside receive new relief.
	for side in [-1.0, 1.0]:
		for z in [side * 8.47]:
			_box(stage, bases, Vector3(0, -0.57, z), Vector3(13.6, 0.44, 0.4))
			_box(stage, metal, Vector3(0, -0.30, z + side * 0.025), Vector3(13.7, 0.05, 0.45))
			for i in range(17):
				var x := -6.4 + float(i) * 0.80
				_box(stage, stone, Vector3(x, -0.59, z + side * 0.2), Vector3(0.1, 0.4, 0.1))
		for z in [-4.8, 0.0, 4.8]:
			_box(stage, bases, Vector3(side * 10.4, -0.51, z), Vector3(0.65, 0.48, 2.7))
			_box(stage, metal, Vector3(side * 10.75, -0.49, z), Vector3(0.075, 0.38, 2.6))
			for flute in range(6):
				_box(stage, stone, Vector3(side * 10.8, -0.49, z - 1.05 + float(flute) * 0.42), Vector3(0.15, 0.50, 0.08))
		# Gallery landings wrap the fan installations with a credible bass
		# chamber, a marble cornice and restrained metal fretwork.
		for z in [-4.8, 4.8]:
			var p := Vector3(side * 13.6, -0.36, z)
			_box(stage, bases, p, Vector3(4.2, 0.63, 3.3))
			_box(stage, stone, p + Vector3(0, 0.37, 0), Vector3(4.35, 0.10, 3.46))
			_box(stage, metal, p + Vector3(0, 0.46, 0), Vector3(4.4, 0.045, 3.51))
			for i in range(8):
				_box(stage, details, p + Vector3(-1.80 + float(i) * 0.515, 0.01, 1.71), Vector3(0.14, 0.43, 0.05))
			_beam(stage, metal, Vector3(side * 10.3, -0.72, z), p + Vector3(0, -0.14, 0), 0.14)
			_beam(stage, stone, Vector3(side * 10.3, -0.72, z), p + Vector3(0, -0.7, 0), 0.22)
			# Full-size tuning forks are acoustic objects with visibly joined
			# prongs, resonant throat and base; all four stand outside the hull.
			_tuning_fork(stage, stone, bases, metal, light_lines, Vector3(side * 16.15, 0.08, z), side)
		# Flared horns aim toward the hall from outside x=10. Their hollow
		# mouths and shadowed throats prevent the old flat-fan appearance.
		for z in [-2.35, 2.35]:
			var throat := Vector3(side * 13.0, 1.45, z)
			var mouth := Vector3(side * 10.8, 1.60, z)
			_horn(stage, tubes, interiors, metal, throat, mouth, 0.16, 0.68)
			_box(stage, bases, throat + Vector3(side * 0.4, -1.32, 0), Vector3(1.0, 0.45, 1.4))
			_beam(stage, metal, throat + Vector3(0, -0.10, 0), throat + Vector3(0, -1.05, 0), 0.10)
	# Back shell has darker ribs and a gilt open coffer grid; it frames rather
	# than roofs the playing field, so robots remain unobscured from above.
	stage.call("_arch", stage, "ChampagneAcousticShellFrontRib", 10.72, 7.05, 0.045, 0.12, Vector3(0, 0.08, -11.0), champagne)
	stage.call("_arch", stage, "MidnightAcousticShellBackRib", 11.35, 7.75, 0.25, 0.42, Vector3(0, 0.08, -13.15), midnight)
	stage.call("_arch", stage, "IvoryAcousticShellBackCornice", 11.35, 7.79, 0.075, 0.45, Vector3(0, 0.10, -13.18), ivory)
	for i in range(17):
		var x := -10.0 + float(i) * 1.25
		var front_height := 0.1 + sqrt(maxf(0, 1.0 - pow(x / 10.72, 2))) * 7.05
		var back_height := 0.1 + sqrt(maxf(0, 1.0 - pow(x / 11.35, 2))) * 7.75
		_beam(stage, metal, Vector3(x, front_height, -11.05), Vector3(x, back_height, -13.1), 0.048)
		_box(stage, details, Vector3(x, front_height - 0.10, -11.02), Vector3(0.15, 0.21, 0.16))
	for i in range(9):
		var x := -8.0 + float(i) * 2.0
		var peak := 0.1 + sqrt(maxf(0, 1.0 - pow(x / 10.7, 2))) * 7.0
		var length := 2.0 + sin(float(i) * 0.72) * 0.65 + (2.0 if i == 4 else 0.0)
		var bottom := Vector3(x, peak - 0.5 - length, -11.6)
		var axis := Vector3(0, -0.55, 0.56)
		_horn(stage, tubes, interiors, metal, bottom + Vector3(0, 0.50, 0), bottom + axis, 0.15 + float(i % 3) * 0.06, 0.38 + float(i % 3) * 0.09)
		for collar in [peak - 0.72, bottom.y + 0.22]:
			_tube_band(stage, metal, Vector3(x, collar, -11.6), Vector3.UP, 0.23 + float(i % 3) * 0.08, 0.08)
		_box(stage, light_lines, Vector3(x, peak - 0.62, -11.31), Vector3(0.07, 0.24, 0.04))
	for side in [-1.0, 1.0]:
		var p := Vector3(side * 11.5, -0.55, -12.1)
		_box(stage, bases, p, Vector3(2.8, 0.72, 4.0))
		_box(stage, stone, p + Vector3(0, 0.44, 0), Vector3(2.95, 0.14, 4.1))
		_box(stage, metal, p + Vector3(0, 0.54, 0), Vector3(3.0, 0.045, 4.15))
		_box(stage, bases, p + Vector3(0, 2.0, -0.5), Vector3(1.4, 3.2, 1.6))
		for i in range(7):
			_box(stage, stone, p + Vector3(-0.65 + float(i) * 0.22, 2.0, 0.32), Vector3(0.10, 3.1, 0.12))
			_box(stage, light_lines, p + Vector3(-0.65 + float(i) * 0.22, 3.55, 0.32), Vector3(0.08, 0.055, 0.13))
	# Distant tiers of paired arches establish a hall receding over the basin.
	for layer in range(3):
		var z := -24.0 - float(layer) * 12.0
		var span := 17.0 + float(layer) * 4.0
		stage.call("_arch", stage, "DistantEchoCloister", span, 8.0 + float(layer) * 2.0, 0.30, 0.6, Vector3(0, -1.25, z), blue if layer % 2 == 0 else rose)
		for side in [-1.0, 1.0]:
			_box(stage, bases, Vector3(side * span, -0.7, z), Vector3(3.1, 1.1, 3.4))
			_box(stage, stone, Vector3(side * span, 0.0, z), Vector3(3.3, 0.3, 3.6))
	_finish(stage, stage, "CarvedIvoryAcousticPlinths", stone, alabaster)
	_finish(stage, stage, "MidnightBassChambers", bases, midnight)
	_finish(stage, stage, "ChampagneBindingsAndHornRims", metal, champagne)
	_finish(stage, stage, "EchoHallArchitecturalFretwork", details, nacre)
	_finish(stage, stage, "AcousticCeramicSignalInlays", light_lines, glow, false)
	_finish(stage, stage, "SculptedIvoryHornShells", tubes, ivory)
	_finish(stage, stage, "ShadowedHornThroats", interiors, throat_material, false)


static func _tuning_fork(stage: Node3D, stone: SurfaceTool, bases: SurfaceTool, metal: SurfaceTool, glow: SurfaceTool, point: Vector3, side: float) -> void:
	_box(stage, bases, point + Vector3(0, 0.22, 0), Vector3(1.6, 0.44, 1.8))
	_box(stage, stone, point + Vector3(0, 0.49, 0), Vector3(1.72, 0.12, 1.92))
	_box(stage, metal, point + Vector3(0, 1.0, 0), Vector3(0.24, 0.9, 0.38))
	var split := point + Vector3(0, 1.6, 0)
	for prong in [-1.0, 1.0]:
		var elbow := point + Vector3(0, 2.2, prong * 0.62)
		_beam(stage, metal, split, elbow, 0.19)
		_beam(stage, metal, elbow, point + Vector3(0, 5.6, prong * 0.62), 0.19)
		_box(stage, glow, point + Vector3(-side * 0.11, 4.35, prong * 0.62), Vector3(0.06, 1.8, 0.15))
		_box(stage, stone, point + Vector3(0, 5.68, prong * 0.62), Vector3(0.35, 0.15, 0.38))


static func _horn(stage: Node3D, outside: SurfaceTool, inside: SurfaceTool, rims: SurfaceTool, from: Vector3, to: Vector3, throat: float, mouth: float) -> void:
	var direction := to - from
	var basis := Basis(Quaternion(Vector3.UP, direction.normalized()))
	const SEGMENTS := 20
	const LENGTH_STEPS := 5
	for step in range(LENGTH_STEPS):
		var t1 := float(step) / LENGTH_STEPS
		var t2 := float(step + 1) / LENGTH_STEPS
		var r1 := lerpf(throat, mouth, pow(t1, 2.2))
		var r2 := lerpf(throat, mouth, pow(t2, 2.2))
		for i in range(SEGMENTS):
			var a := TAU * float(i) / SEGMENTS
			var b := TAU * float(i + 1) / SEGMENTS
			var a1 := from + direction * t1 + basis * Vector3(cos(a) * r1, 0, sin(a) * r1)
			var b1 := from + direction * t1 + basis * Vector3(cos(b) * r1, 0, sin(b) * r1)
			var a2 := from + direction * t2 + basis * Vector3(cos(a) * r2, 0, sin(a) * r2)
			var b2 := from + direction * t2 + basis * Vector3(cos(b) * r2, 0, sin(b) * r2)
			stage.call("_quad", outside, a1, a2, b2, b1)
			stage.call("_quad", inside, a1 - basis * Vector3(cos(a) * 0.035, 0, sin(a) * 0.035), b1 - basis * Vector3(cos(b) * 0.035, 0, sin(b) * 0.035), b2 - basis * Vector3(cos(b) * 0.035, 0, sin(b) * 0.035), a2 - basis * Vector3(cos(a) * 0.035, 0, sin(a) * 0.035))
	# A tiny recessed dark termination belongs at the narrow throat, never
	# across the flared mouth. It gives a sense of depth along the horn axis.
	var back := from + direction * 0.012
	for index in range(SEGMENTS):
		var a := TAU * float(index) / SEGMENTS
		var b := TAU * float(index + 1) / SEGMENTS
		stage.call("_tri", inside, back, back + basis * Vector3(cos(a) * (throat - 0.036), 0, sin(a) * (throat - 0.036)), back + basis * Vector3(cos(b) * (throat - 0.036), 0, sin(b) * (throat - 0.036)))
	_tube_band(stage, rims, to, direction.normalized(), mouth + 0.012, 0.055)
	_tube_band(stage, rims, from, direction.normalized(), throat + 0.012, 0.06)


static func _tube_band(stage: Node3D, surface: SurfaceTool, point: Vector3, axis: Vector3, radius: float, height: float) -> void:
	var basis := Basis(Quaternion(Vector3.UP, axis.normalized()))
	for i in range(20):
		var a := TAU * float(i) / 20.0
		var b := TAU * float(i + 1) / 20.0
		var radial := Vector3(cos((a + b) * 0.5), 0, sin((a + b) * 0.5))
		var center := point + basis * radial * radius
		_box(stage, surface, center, Vector3(0.04, height, radius * (b - a) * 1.03), basis * Basis(Vector3.UP, -(a + b) * 0.5))


static func _material(stage: Node3D, color: Color, roughness: float, metallic: float, emission: Color = Color.BLACK, energy: float = 0.0) -> Material:
	return stage.call("_material", color, roughness, metallic, emission, energy) as Material


static func _surface() -> SurfaceTool:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	return surface


static func _box(stage: Node3D, surface: SurfaceTool, center: Vector3, size: Vector3, basis: Basis = Basis.IDENTITY) -> void:
	stage.call("_append_box", surface, center, size, basis)


static func _beam(stage: Node3D, surface: SurfaceTool, from: Vector3, to: Vector3, width: float) -> void:
	var direction := to - from
	_box(stage, surface, (from + to) * 0.5, Vector3(width, direction.length(), width), Basis(Quaternion(Vector3.UP, direction.normalized())))


static func _floor_triangle(stage: Node3D, surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	if (b - a).cross(c - a).y >= 0.0:
		stage.call("_tri", surface, a, b, c)
	else:
		stage.call("_tri", surface, a, c, b)


static func _finish(stage: Node3D, parent: Node3D, label: String, surface: SurfaceTool, material: Material, casts_shadow: bool = true) -> MeshInstance3D:
	surface.generate_normals()
	var mesh: MeshInstance3D = stage.call("_instance", parent, label, surface.commit(), Vector3.ZERO, material)
	if not casts_shadow:
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh
