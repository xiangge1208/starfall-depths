class_name TestMoveMath
extends GdUnitTestSuite

func test_accel_toward_target_speed() -> void:
	var v := MoveMath.accelerate(Vector2.ZERO, Vector2.RIGHT, 80.0, 1400.0, 1800.0)
	assert_float(v.x).is_equal_approx(1400.0 / 60.0, 0.001)

func test_friction_stops_within_3_ticks() -> void:
	var v := Vector2.RIGHT * 80.0
	var ticks := 0
	while v.length() > 0.01 and ticks < 20:
		v = MoveMath.accelerate(v, Vector2.ZERO, 80.0, 1400.0, 1800.0)
		ticks += 1
	assert_int(ticks).is_less_equal(3)     # 80/1800*60 = 2.67 → ≤3 tick 停稳 (GDD §5.2)
