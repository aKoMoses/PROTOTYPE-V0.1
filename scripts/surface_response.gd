extends RefCounted

## Shared presentation classification; never changes a collision or its damage.
static func classify(collider: Node) -> String:
	if not is_instance_valid(collider):
		return "environment"
	if collider.has_method("take_damage"):
		if collider.has_method("get_stasis_remaining") and float(collider.call("get_stasis_remaining")) > 0.0:
			return "shield"
		return "shield" if bool(collider.get_meta("duel_static_shield", false)) else "robot"
	if collider is Area3D:
		return "shield"
	var tagged := str(collider.get_meta("vfx_surface", ""))
	if tagged in ["metal", "shield", "robot", "concrete", "sand"]:
		return tagged
	var label := String(collider.name).to_lower()
	if "ground" in label or "floor" in label:
		return "concrete"
	if "wall" in label or "concrete" in label or "platform" in label or "ramp" in label:
		return "concrete"
	if "cover" in label or "wreck" in label or "pipe" in label or "container" in label or "tank" in label:
		return "metal"
	return tagged if not tagged.is_empty() else "environment"
