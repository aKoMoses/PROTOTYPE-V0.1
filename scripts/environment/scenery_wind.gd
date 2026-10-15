extends RefCounted
## One travelling gust shared by CPU simulation and rendered scenery.
const DIRECTION := Vector3(0.9403762, 0.0, -0.3401361)
const PERIOD := 29.0
const DURATION := 4.8
const SPEED := 6.0

static func strength(clock: float, at: Vector3) -> float:
	var phase := fposmod(clock - at.dot(DIRECTION) / SPEED, PERIOD)
	if phase >= DURATION:
		return 0.0
	return pow(sin(phase / DURATION * PI), 2.0)

static func velocity(clock: float, at: Vector3) -> Vector3:
	return DIRECTION * (0.34 + strength(clock, at) * 1.4)
