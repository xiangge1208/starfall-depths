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
	# 跨实现位稳定锚：期望值由 tests/unit/fnv_reference.py（同算法 Python 参考）算出，
	# 证明 GDScript 与参考实现逐位一致；重构/升级若改变位型在此立即失败。
	# 期望值必须写十进制：本引擎会把超出 int64 正域的十六进制字面量钳到 INT64_MAX。
	assert_int(RngSvc.stable_hash(0, 0)).is_equal(-8637869204239850395)
	assert_int(RngSvc.stable_hash(1, 2)).is_equal(8581494755304202342)
