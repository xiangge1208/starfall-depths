class_name TestElements
extends GdUnitTestSuite
## brief ④：Elements.from_name 与 Resonance.resolve 的 NONE 路径覆盖
##（四对共鸣已由 test_resonance.gd 覆盖，此处补齐缺口）

func test_from_name_fire() -> void:
	assert_int(Elements.from_name("fire")).is_equal(Elements.Id.FIRE)

func test_from_name_none() -> void:
	assert_int(Elements.from_name("none")).is_equal(Elements.Id.NONE)

func test_from_name_unknown_returns_none() -> void:
	assert_int(Elements.from_name("bogus")).is_equal(Elements.Id.NONE)

func test_resolve_left_none() -> void:
	assert_int(Resonance.resolve(Elements.Id.NONE, Elements.Id.FIRE)).is_equal(Resonance.R.NONE)

func test_resolve_right_none() -> void:
	assert_int(Resonance.resolve(Elements.Id.FIRE, Elements.Id.NONE)).is_equal(Resonance.R.NONE)
