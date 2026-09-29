class_name ActionGate
extends RefCounted

## Authoritative per-actor ownership for mutually exclusive combat actions.
## Operational state (charge progress, animation phase, projectile travel) stays
## in the weapon/module, but only the current token may start or finish it.

enum Kind { NONE, WEAPON, MODULE }

var _kind := Kind.NONE
var _owner_id := ""
var _generation := 0
var _last_claim_frame := -1


func try_acquire(kind: Kind, owner_id: String, claim_frame: int = -1, allow_same_frame: bool = false) -> int:
	if kind == Kind.NONE or owner_id.is_empty() or _kind != Kind.NONE:
		return 0
	var frame := Engine.get_physics_frames() if claim_frame < 0 else claim_frame
	# Releasing an instantaneous action does not allow another incompatible
	# command received during that same physics frame to slip through.
	if not allow_same_frame and frame == _last_claim_frame:
		return 0
	_generation += 1
	_kind = kind
	_owner_id = owner_id
	_last_claim_frame = frame
	return _generation


func replace_weapon_with_module(owner_id: String, claim_frame: int = -1) -> int:
	if owner_id.is_empty() or _kind != Kind.WEAPON:
		return 0
	var frame := Engine.get_physics_frames() if claim_frame < 0 else claim_frame
	# A weapon accepted earlier in this frame wins that frame. A held/charging
	# weapon from an earlier frame may still be atomically interrupted by a cast.
	if frame == _last_claim_frame:
		return 0
	_generation += 1
	_kind = Kind.MODULE
	_owner_id = owner_id
	_last_claim_frame = frame
	return _generation


func owns(token: int, kind: Kind = Kind.NONE, owner_id: String = "") -> bool:
	if token <= 0 or token != _generation or _kind == Kind.NONE:
		return false
	if kind != Kind.NONE and _kind != kind:
		return false
	return owner_id.is_empty() or _owner_id == owner_id


func release(token: int) -> bool:
	if not owns(token):
		return false
	_kind = Kind.NONE
	_owner_id = ""
	return true


func reset() -> void:
	_generation += 1
	_kind = Kind.NONE
	_owner_id = ""
	_last_claim_frame = -1


func is_busy() -> bool:
	return _kind != Kind.NONE


func is_kind(kind: Kind) -> bool:
	return _kind == kind


func was_claimed_this_frame(claim_frame: int = -1) -> bool:
	var frame := Engine.get_physics_frames() if claim_frame < 0 else claim_frame
	return frame == _last_claim_frame


func get_kind() -> Kind:
	return _kind


func get_owner_id() -> String:
	return _owner_id


func get_generation() -> int:
	return _generation
