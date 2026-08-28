class_name TestDamageCalc
extends GdUnitTestSuite

func test_fixed_no_variance() -> void:
	var rng := RngSvc.stream(0, "test")
	rng.seed = 7
	for _i in 20:
		var r := DamageCalc.compute(5, rng, 0.0)   # 暴击率 0
		assert_int(r["amount"]).is_equal(5)

func test_crit_doubles() -> void:
	var rng := RngSvc.stream(0, "test")
	rng.seed = 7
	var r := DamageCalc.compute(5, rng, 1.0)       # 必暴
	assert_int(r["amount"]).is_equal(10)
	assert_bool(r["is_crit"]).is_true()

func test_min_clamp_and_global_mult() -> void:
	var rng := RngSvc.stream(0, "test")
	rng.seed = 7
	assert_int(DamageCalc.compute(3, rng, 0.0, 2.0, 0.1)["amount"]).is_equal(1)
	assert_int(DamageCalc.compute(6, rng, 0.0, 2.0, 0.5)["amount"]).is_equal(3)
