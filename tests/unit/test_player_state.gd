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
