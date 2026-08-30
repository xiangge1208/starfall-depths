class_name TestPlayerState
extends GdUnitTestSuite

# 注：brief 原文 `var p := auto_free(Player.new())`，auto_free 返回 Variant，:= 无法推断类型
# （同 test_combat_system.gd 既定决议），需显式类型标注。
func _player() -> Player:
	var p: Player = auto_free(Player.new())
	p._test_init()
	return p

func test_shield_absorbs_first() -> void:
	var p := _player()
	p.hp = 8; p.shield = 4
	p.take_hit_ctx({"amount": 3}, 100)
	assert_int(p.shield).is_equal(1)
	assert_int(p.hp).is_equal(8)

func test_negative_damage_is_noop_before_rampage_shield_and_status() -> void:
	var p := _player()
	p.hp = 5
	p.shield = 2
	p.move_speed = 80.0
	p.rampage_active_until = 1000
	p.take_hit_ctx({"amount": -99, "slow_pct": 0.5, "slow_ticks": 60}, 100)
	assert_int(p.hp).is_equal(5)
	assert_int(p.shield).is_equal(2)
	assert_bool(p.is_invincible_at(100)).is_false()
	assert_float(p.effective_move_speed(100)).is_equal_approx(80.0, 0.001)

func test_iframes_block_and_expire() -> void:
	var p := _player()
	p.take_hit_ctx({"amount": 1}, 100)
	assert_bool(p.is_invincible_at(110)).is_true()       # 0.8s=48 ticks
	assert_bool(p.is_invincible_at(100 + 48)).is_false()

func test_shield_regen_after_delay() -> void:
	var p := _player()
	p.hp = 8; p.shield = 0
	p.take_hit_ctx({"amount": 1}, 100)
	assert_int(p.shield_at(100 + 179)).is_equal(0)        # 3.0s 延迟内不回
	assert_int(p.shield_at(100 + 180)).is_equal(1)        # 延迟结束立即回第 1 点
	assert_int(p.shield_at(100 + 180 + 71)).is_equal(1)
	assert_int(p.shield_at(100 + 180 + 72)).is_equal(2)   # 之后每 1.2s 回 1

func test_roll_iframes_and_cooldown() -> void:
	var p := _player()
	p.start_roll(Vector2.RIGHT, 100)
	for f in range(100, 113):
		assert_bool(p.is_invincible_at(f)).is_true()      # 13 ticks 全程无敌
	assert_bool(p.roll_ready_at(100 + 13 + 42 - 1)).is_false()
	assert_bool(p.roll_ready_at(100 + 13 + 42)).is_true() # 0.7s CD 从结束起算

func test_runtime_modifiers_drive_shield_delay_and_roll_cooldown() -> void:
	var p := _player()
	p.shield = 0
	p.shield_delay_reduction_ticks = 60
	p.take_hit_ctx({"amount": 1}, 100)
	assert_int(p.shield_at(219)).is_equal(0)
	assert_int(p.shield_at(220)).is_equal(1)              # 3.0s - 1.0s = 2.0s
	p.roll_cd_pct = -0.15
	p.roll_cd_reduction_ticks = 3
	p.start_roll(Vector2.RIGHT, 300)
	assert_bool(p.roll_ready_at(300 + 13 + 33 - 1)).is_false()
	assert_bool(p.roll_ready_at(300 + 13 + 33)).is_true() # round(42*0.85)-3 = 33t

func test_temporary_move_speed_uses_exact_frame_boundary() -> void:
	var p := _player()
	p.move_speed = 80.0
	p.move_speed_boost_pct = 0.30
	p.move_speed_boost_until = 400
	assert_float(p.effective_move_speed(399)).is_equal_approx(104.0, 0.001)
	assert_float(p.effective_move_speed(400)).is_equal_approx(80.0, 0.001)

func test_incoming_spore_slow_reduces_speed_for_exact_duration() -> void:
	var p := _player()
	p.move_speed = 80.0
	p.take_hit_ctx({"amount": 1, "slow_pct": 0.3, "slow_ticks": 60}, 100)
	assert_float(p.effective_move_speed(159)).is_equal_approx(56.0, 0.001)
	assert_float(p.effective_move_speed(160)).is_equal_approx(80.0, 0.001)

func test_incoming_slow_merges_stronger_percent_and_longer_duration() -> void:
	var p := _player()
	p.move_speed = 100.0
	p.take_hit_ctx({"amount": 1, "slow_pct": 0.2, "slow_ticks": 90}, 100)
	# 跳过受击无敌窗后叠更强但更短的减速：强度取 max，期限也取 max。
	p.take_hit_ctx({"amount": 1, "slow_pct": 0.4, "slow_ticks": 20}, 149)
	assert_float(p.effective_move_speed(168)).is_equal_approx(60.0, 0.001)
	assert_float(p.effective_move_speed(189)).is_equal_approx(60.0, 0.001)
	assert_float(p.effective_move_speed(190)).is_equal_approx(100.0, 0.001)

func test_iframes_block_incoming_slow_application() -> void:
	var p := _player()
	p.move_speed = 80.0
	p.take_hit_ctx({"amount": 1}, 100)
	p.take_hit_ctx({"amount": 1, "slow_pct": 0.5, "slow_ticks": 60}, 110)
	assert_float(p.effective_move_speed(110)).is_equal_approx(80.0, 0.001)
	assert_float(p.incoming_slow_pct).is_equal(0.0)
