class_name TestStatus
extends GdUnitTestSuite

func _sc(stacks := 2) -> StatusComponent:
	var s: StatusComponent = auto_free(StatusComponent.new())  # auto_free 返回 Variant，:= 无法推断类型（同 t8/t9 处理）
	s.setup(stacks)
	return s

func test_fire_triggers_burning_after_2_hits() -> void:
	var s := _sc()
	s.apply_hit(Elements.Id.FIRE, 5, 0)
	assert_dict(s.active).is_empty()
	s.apply_hit(Elements.Id.FIRE, 5, 60)
	assert_bool(s.active.has(Elements.Id.FIRE)).is_true()

func test_burn_dot_ticks() -> void:
	var s := _sc()
	s.apply_hit(Elements.Id.FIRE, 5, 0)
	s.apply_hit(Elements.Id.FIRE, 5, 10)      # 触发燃烧
	var total := 0
	for f in range(11, 11 + 180):
		total += s.tick(f)
	assert_int(total).is_equal(6)             # 3s，每 0.5s 1 点 = 6

func test_shatter_resonance_once_with_icd() -> void:
	var s := _sc()
	s.apply_hit(Elements.Id.FIRE, 8, 0)
	s.apply_hit(Elements.Id.FIRE, 8, 10)      # 2 层 → 燃烧激活
	s.apply_hit(Elements.Id.ICE, 8, 20)
	s.apply_hit(Elements.Id.ICE, 8, 30)       # 火+冰 → 淬爆（两种激活状态相遇）
	assert_int(s.resonance_event.get("reaction", -1)).is_equal(Resonance.R.SHATTER)
	assert_dict(s.active).is_empty()          # 共鸣清除双方状态
	s.resonance_event = {}
	s.apply_hit(Elements.Id.FIRE, 8, 140)
	s.apply_hit(Elements.Id.FIRE, 8, 150)     # 燃烧再激活
	s.apply_hit(Elements.Id.POISON, 8, 160)
	s.apply_hit(Elements.Id.POISON, 8, 170)   # >2s（ICD 至 150），火+毒 → 燎原
	assert_int(s.resonance_event.get("reaction", -1)).is_equal(Resonance.R.BLAZE)
	s.resonance_event = {}
	s.apply_hit(Elements.Id.SHOCK, 8, 180)
	s.apply_hit(Elements.Id.SHOCK, 8, 190)    # 麻痹照常触发，但每目标 ICD 至 290 → 不共鸣
	assert_dict(s.resonance_event).is_empty()

func test_subthreshold_no_status_no_resonance() -> void:
	var s := _sc()
	s.apply_hit(Elements.Id.FIRE, 8, 0)
	s.apply_hit(Elements.Id.ICE, 8, 10)       # 未达阈值：不触发状态，也不共鸣
	assert_dict(s.active).is_empty()
	assert_dict(s.resonance_event).is_empty()

func test_boss_threshold_four() -> void:
	var s := _sc(4)
	for f in range(0, 3):
		s.apply_hit(Elements.Id.POISON, 1, f * 10)
	assert_dict(s.active).is_empty()
	s.apply_hit(Elements.Id.POISON, 1, 40)
	assert_bool(s.active.has(Elements.Id.POISON)).is_true()
