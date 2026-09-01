class_name TestEnemyNanGuard
extends GdUnitTestSuite
## m3-fix1：EnemyBase 非有限坐标防御（B-1 停滞下游症状——NaN 经表现层 velocity 传播、
## 拍末 brain_pos 回写永久污染，敌人成不可伤幽灵、房间永不可清）。
## 契约（ensure_finite_position）：检测 → 重置到 combat_bounds 内域中心（空 bounds 回
## 原点）→ 返回 false（重置拍跳过表现层）；有限时返回 true 零干预。NaN 不跨拍存活。

func test_nan_brain_pos_reset_to_bounds_center() -> void:
	var e: EnemyBase = auto_free(EnemyFactory.create({"id": "kuli_bug", "archetype": "suicide", "hp": 12, "speed": 95}))
	e.combat_bounds = Rect2(488, 16, 456, 238)
	e.brain_pos = Vector2(NAN, NAN)
	e.position = Vector2(600, 120)
	assert_bool(e.ensure_finite_position()).is_false()      # 重置拍：跳过表现层
	assert_vector(e.brain_pos).is_equal(Vector2(716, 135))  # bounds 内域中心
	assert_bool(e.brain_pos.is_finite()).is_true()
	assert_bool(e.global_position.is_finite()).is_true()

func test_nan_global_position_reset_and_velocity_zeroed() -> void:
	var e: EnemyBase = auto_free(EnemyFactory.create({"id": "crossbowman", "archetype": "shooter", "hp": 16, "speed": 60}))
	e.combat_bounds = Rect2(488, 16, 456, 238)
	e.brain_pos = Vector2(600, 120)
	e.global_position = Vector2(INF, NAN)
	assert_bool(e.ensure_finite_position()).is_false()
	assert_vector(e.global_position).is_equal(Vector2(716, 135))
	assert_vector(e.velocity).is_equal(Vector2.ZERO)
	# 下一拍：坐标已有限 → 守卫零干预（NaN 不跨拍存活的另一半：恢复后正常行走）
	assert_bool(e.ensure_finite_position()).is_true()
	assert_vector(e.brain_pos).is_equal(Vector2(600, 120))

func test_inf_position_reset_without_bounds_falls_to_origin() -> void:
	# 纯脑测路径（未注入 bounds）：回原点，不崩溃、不留非有限值。
	var e: EnemyBase = auto_free(EnemyFactory.create({"id": "cave_bat", "archetype": "orbiter", "hp": 10, "speed": 70}))
	assert_vector(e.combat_bounds.size).is_equal(Vector2.ZERO)
	e.brain_pos = Vector2(INF, INF)
	e.global_position = Vector2(INF, INF)
	assert_bool(e.ensure_finite_position()).is_false()
	assert_vector(e.brain_pos).is_equal(Vector2.ZERO)
	assert_vector(e.global_position).is_equal(Vector2.ZERO)

func test_finite_positions_pass_through_untouched() -> void:
	# 零漂移：有限坐标下守卫必须零干预（普通对局每拍都走本函数）。
	var e: EnemyBase = auto_free(EnemyFactory.create({"id": "kuli_bug", "archetype": "suicide", "hp": 12, "speed": 95}))
	e.combat_bounds = Rect2(488, 16, 456, 238)
	e.brain_pos = Vector2(600, 120)
	e.position = Vector2(599, 120)
	assert_bool(e.ensure_finite_position()).is_true()
	assert_vector(e.brain_pos).is_equal(Vector2(600, 120))
	assert_vector(e.global_position).is_equal(Vector2(599, 120))
