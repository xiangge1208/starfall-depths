class_name TestSpatialHash
extends GdUnitTestSuite

func test_query_radius_and_borders() -> void:
	var h := SpatialHash.new(32.0)
	h.insert(1, Vector2(0, 0))
	h.insert(2, Vector2(30, 0))    # 同格
	h.insert(3, Vector2(34, 0))    # 邻格
	var r := h.query(Vector2(0, 0), 35.0)
	assert_int(r.size()).is_equal(3)

func test_move_updates_bucket() -> void:
	var h := SpatialHash.new(32.0)
	h.insert(1, Vector2(0, 0))
	h.move(1, Vector2(1000, 1000))
	assert_int(h.query(Vector2(0, 0), 10.0).size()).is_equal(0)
	assert_int(h.query(Vector2(1000, 1000), 10.0).size()).is_equal(1)

func test_remove_and_reinsert() -> void:
	var h := SpatialHash.new(32.0)
	h.insert(1, Vector2(5, 5))
	h.remove(1)
	assert_int(h.query(Vector2(5, 5), 10.0).size()).is_equal(0)
	h.insert(1, Vector2(5, 5))
	assert_int(h.query(Vector2(5, 5), 10.0).size()).is_equal(1)

func test_5000_entities_perf_sanity() -> void:
	var h := SpatialHash.new(32.0)
	var rng := RngSvc.stream(0, "perf")
	rng.seed = 1
	for i in 5000:
		h.insert(i, Vector2(rng.randf_range(0, 2000), rng.randf_range(0, 2000)))
	var t := Time.get_ticks_usec()
	for _i in 5000:
		h.query(Vector2(rng.randf_range(0, 2000), rng.randf_range(0, 2000)), 48.0)
	# 冒烟上限：宽松（无头 CI 波动），真实预算见 t13 门禁压测
	assert_int(Time.get_ticks_usec() - t).is_less(2_000_000)
