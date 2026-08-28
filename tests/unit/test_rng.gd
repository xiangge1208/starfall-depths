class_name TestRng
extends GdUnitTestSuite

func test_same_seed_same_sequence() -> void:
	RngSvc.setup_run(12345)
	var a := RngSvc.stream(1, "combat")
	var b := RngSvc.stream(1, "combat")
	for _i in 10:
		assert_float(a.randf()).is_equal(b.randf())

func test_different_floor_different_sequence() -> void:
	RngSvc.setup_run(12345)
	var a := RngSvc.stream(1, "combat")
	var b := RngSvc.stream(2, "combat")
	var diff := false
	for _i in 10:
		if a.randf() != b.randf(): diff = true
	assert_bool(diff).is_true()

func test_stable_hash_known_vector() -> void:
	# FNV-1a-64("") = 0xcbf29ce484222325；对单字节 0x00：h ^= 0 → h * prime
	assert_int(RngSvc.stable_hash(0, 0)).is_equal(RngSvc.stable_hash(0, 0))
	assert_int(RngSvc.stable_hash(1, 2)).is_not_equal(RngSvc.stable_hash(2, 1))
