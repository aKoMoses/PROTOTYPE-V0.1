extends RefCounted
## Parametric fittings assembled into the caller's batches, in local metres.
var batch: RefCounted
var palette: Dictionary

func _init(detail_batch: RefCounted, materials: Dictionary) -> void:
	batch = detail_batch
	palette = materials

func pedestal(at: Vector3, size: Vector3) -> void:
	batch.box(palette.stone, at + Vector3.UP * size.y * 0.5, size)
	for fraction in [0.12, 0.90]:
		batch.box(palette.trim, at + Vector3.UP * size.y * fraction, Vector3(size.x + 0.08, 0.07, size.z + 0.08))
	for side in [-1.0, 1.0]:
		batch.box(palette.dark, at + Vector3(side * (size.x * 0.5 + 0.006), size.y * 0.5, 0), Vector3(0.02, size.y * 0.45, size.z * 0.66))

func louvred_panel(at: Vector3, size: Vector2, yaw: float = 0.0) -> void:
	var basis := Basis(Vector3.UP, yaw)
	batch.box(palette.dark, at, Vector3(size.x, size.y, 0.08), basis)
	for side in [-1.0, 1.0]:
		batch.box(palette.trim, at + basis * Vector3(side * size.x * 0.5, 0, 0.02), Vector3(0.07, size.y + 0.12, 0.14), basis)
	for index in range(6):
		batch.box(palette.metal, at + basis * Vector3(0, size.y * (-0.4 + float(index) * 0.16), 0.08), Vector3(size.x * 0.91, 0.06, 0.14), basis * Basis(Vector3.RIGHT, -0.25))
	for side in [-1.0, 1.0]:
		for top in [-1.0, 1.0]:
			batch.box(palette.bright, at + basis * Vector3(side * size.x * 0.43, top * size.y * 0.43, 0.13), Vector3.ONE * 0.045, basis)

func column_collar(at: Vector3, radius: float, yaw: float = 0.0) -> void:
	batch.ring(palette.metal, at, radius, 0.10, 0.18)
	batch.ring(palette.bright, at + Vector3.UP * 0.11, radius + 0.012, 0.035, 0.025)
	for index in range(8):
		var angle := TAU * float(index) / 8.0 + yaw
		batch.box(palette.bright, at + Vector3(cos(angle) * radius, 0, sin(angle) * radius), Vector3(0.07, 0.10, 0.07), Basis(Vector3.UP, -angle))

func planter(at: Vector3, size: Vector2, seed: int, lush: bool = true) -> void:
	batch.box(palette.stone, at + Vector3.UP * 0.25, Vector3(size.x, 0.5, size.y))
	batch.box(palette.dark, at + Vector3.UP * 0.508, Vector3(size.x * 0.84, 0.02, size.y * 0.84))
	for side in [-1.0, 1.0]:
		batch.box(palette.trim, at + Vector3(0, 0.52, side * size.y * 0.49), Vector3(size.x + 0.08, 0.1, 0.1))
		batch.box(palette.trim, at + Vector3(side * size.x * 0.49, 0.52, 0), Vector3(0.1, 0.1, size.y + 0.08))
	foliage(at + Vector3.UP * 0.54, minf(size.x, size.y) * (0.85 if lush else 0.45), seed)

func foliage(at: Vector3, reach: float, seed: int) -> void:
	for index in range(7):
		var angle := float(index) * 2.39996 + float(seed) * 0.73
		var direction := Vector3(cos(angle), 0, sin(angle))
		var length := reach * (0.7 + float((index + seed) % 4) * 0.15)
		batch.leaf(palette.leaf if index % 2 == 0 else palette.leaf_light, at, direction, length, length * 0.32, length * 0.45)
		batch.beam(palette.stem, at, at + direction * length * 0.65 + Vector3.UP * length * 0.43, 0.026)

func service_pipe(a: Vector3, b: Vector3, radius: float) -> void:
	batch.beam(palette.metal, a, b, radius * 2.0)
	var direction := (b - a).normalized()
	var up := Vector3.RIGHT if absf(direction.dot(Vector3.UP)) > 0.99 else Vector3.UP
	var basis := Basis.looking_at(direction, up) * Basis(Vector3.RIGHT, PI * 0.5)
	for fraction in [0.04, 0.5, 0.96]:
		batch.ring(palette.bright, a.lerp(b, fraction), radius + 0.025, 0.035, 0.05, basis, 12)

func dial(at: Vector3, radius: float, yaw: float = 0.0) -> void:
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5)
	batch.ring(palette.dark, at, radius, radius * 0.24, 0.08, basis, 32)
	batch.ring(palette.bright, at + Basis(Vector3.UP, yaw) * Vector3(0, 0, 0.07), radius * 0.9, 0.06, 0.055, basis, 32)
	for index in range(12):
		var angle := TAU * float(index) / 12.0
		var radial := Vector3(cos(angle), 0, sin(angle))
		var position := at + basis * (radial * radius * 0.82 + Vector3.UP * 0.1)
		batch.box(palette.bright, position, Vector3(0.07, 0.03, radius * 0.15), basis * Basis(Vector3.UP, -angle + PI * 0.5))
	batch.beam(palette.trim, at + basis * Vector3(0, 0.13, 0), at + basis * Vector3(radius * 0.50, 0.13, -radius * 0.33), 0.06)
	batch.beam(palette.bright, at + basis * Vector3(0, 0.14, 0), at + basis * Vector3(-radius * 0.21, 0.14, -radius * 0.70), 0.04)
