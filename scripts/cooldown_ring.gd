extends Control

## Drawn over a module icon. The arc shows the fraction of cooldown still left.
var remaining_fraction := 1.0
var on_cooldown := false
var recast_ready := false

func set_cooldown(remaining: float, duration: float, is_recast_ready: bool = false) -> void:
	var next_cooldown := remaining > 0.0 and not is_recast_ready
	var next_fraction := clampf(remaining / maxf(duration, 0.001), 0.0, 1.0) if next_cooldown else 1.0
	if is_equal_approx(remaining_fraction, next_fraction) and on_cooldown == next_cooldown and recast_ready == is_recast_ready:
		return
	remaining_fraction = next_fraction
	on_cooldown = next_cooldown
	recast_ready = is_recast_ready
	queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 2.5
	if on_cooldown:
		draw_circle(center, radius - 1.5, Color(0.025, 0.04, 0.045, 0.48))
	draw_arc(center, radius, -PI * 0.5, PI * 1.5, 64, Color("#34484b"), 4.0, true)
	var color := Color("#efb765") if recast_ready else Color("#42d9e5")
	draw_arc(center, radius, -PI * 0.5, -PI * 0.5 + TAU * remaining_fraction, 64, color, 4.0, true)
