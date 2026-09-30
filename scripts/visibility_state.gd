class_name VisibilityState
extends RefCounted

## Shared reveal timers. Combat and SPOTTED are intentionally independent:
## combat reveals without drawing the SPOTTED eye, while SPOTTED can reveal a
## robot that has already left combat.

const COMBAT_DURATION := 3.0
const DEFAULT_VISION_RADIUS := 22.0
const DEFAULT_VISION_FADE_WIDTH := 8.0
const SILHOUETTE_OPACITY := 0.24

var combat_remaining := 0.0
var spotted_remaining := 0.0


func reset() -> void:
	combat_remaining = 0.0
	spotted_remaining = 0.0


func update(delta: float) -> void:
	if delta <= 0.0:
		return
	combat_remaining = maxf(0.0, combat_remaining - delta)
	spotted_remaining = maxf(0.0, spotted_remaining - delta)


func mark_combat_event() -> void:
	combat_remaining = COMBAT_DURATION


func mark_spotted(duration: float) -> void:
	spotted_remaining = maxf(spotted_remaining, maxf(0.0, duration))


func is_in_combat() -> bool:
	return combat_remaining > 0.0


func is_spotted() -> bool:
	return spotted_remaining > 0.0


func is_revealed() -> bool:
	return is_in_combat() or is_spotted()


static func visible_to_observer(revealed: bool, in_bush: bool, line_of_sight: bool, same_bush: bool = false) -> bool:
	# Combat and SPOTTED defeat foliage concealment, never physical cover.
	if not line_of_sight:
		return false
	if revealed:
		return true
	if in_bush:
		return same_bush
	return true


static func distance_visibility(distance: float, radius: float = DEFAULT_VISION_RADIUS, fade_width: float = DEFAULT_VISION_FADE_WIDTH) -> float:
	# The boundary is continuous in world units, independent of frame rate.
	# Full sight ends at radius - fade_width; the outer edge is fully concealed.
	radius = maxf(0.0, radius)
	if distance >= radius:
		return 0.0
	fade_width = clampf(fade_width, 0.0, radius)
	if fade_width <= 0.0 or distance <= radius - fade_width:
		return 1.0
	return 1.0 - smoothstep(radius - fade_width, radius, distance)


static func observer_radius(observer: Node3D) -> float:
	if observer != null and is_instance_valid(observer) and observer.has_method("get_vision_radius"):
		return maxf(0.0, float(observer.call("get_vision_radius")))
	return DEFAULT_VISION_RADIUS


static func silhouette_visibility(distance: float, radius: float, fade_width: float) -> float:
	radius = maxf(0.0, radius)
	fade_width = clampf(fade_width, 0.0, radius)
	var weight := distance_visibility(distance, radius, fade_width)
	if weight <= 0.0:
		return 0.0
	# Keep a readable silhouette across the halo, then dissolve it in its final
	# two units. A pure alpha smoothstep made the last half of the halo invisible.
	var fringe := minf(2.0, maxf(0.0, fade_width) * 0.25)
	var edge := 1.0 - smoothstep(radius - fringe, radius, distance) if fringe > 0.0 else 1.0
	return lerpf(SILHOUETTE_OPACITY, 1.0, weight * weight) * edge


static func observer_fade_width(observer: Node3D) -> float:
	if observer != null and is_instance_valid(observer) and observer.has_method("get_vision_fade_width"):
		return maxf(0.0, float(observer.call("get_vision_fade_width")))
	return DEFAULT_VISION_FADE_WIDTH


static func range_weight(target: Node3D, observer: Node3D) -> float:
	if observer == null or not is_instance_valid(observer) or target == observer:
		return 1.0
	var offset := target.global_position - observer.global_position
	# Arena sight is a circle on the floor, including during leaps/projections.
	var distance := Vector2(offset.x, offset.z).length()
	return distance_visibility(distance, observer_radius(observer), observer_fade_width(observer))
