class_name MoveMath
const TICK := 1.0 / 60.0

static func accelerate(vel: Vector2, dir: Vector2, max_speed: float, accel: float, friction: float) -> Vector2:
	if dir == Vector2.ZERO:
		var sp := maxf(0.0, vel.length() - friction * TICK)
		return vel.normalized() * sp if sp > 0.001 else Vector2.ZERO
	return vel.move_toward(dir.normalized() * max_speed, accel * TICK)
