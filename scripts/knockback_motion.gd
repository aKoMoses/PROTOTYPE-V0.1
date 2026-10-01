class_name KnockbackMotion
extends RefCounted

## Integrate a quadratic ease-out exactly, even when physics ticks vary.
## Remaining distance is proportional to remaining time squared.
static func step(distance_remaining: float, time_remaining: float, delta: float) -> float:
	if distance_remaining <= 0.0 or time_remaining <= 0.0 or delta <= 0.0:
		return 0.0
	var fraction := clampf(delta / time_remaining, 0.0, 1.0)
	return distance_remaining * fraction * (2.0 - fraction)


static func speed(distance_remaining: float, time_remaining: float) -> float:
	return 2.0 * maxf(0.0, distance_remaining) / time_remaining if time_remaining > 0.0001 else 0.0
