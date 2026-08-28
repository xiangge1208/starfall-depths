class_name TestFx
extends GdUnitTestSuite
## m0-t12：Fx hitstop 合并（取更长）与震屏衰减。

func test_hitstop_restores_and_coalesces() -> void:
	Fx.hitstop(40)
	Fx.hitstop(60)          # 取更长的
	assert_bool(get_tree().paused).is_true()
	await get_tree().create_timer(0.1, true, false, true).timeout   # 真实 100ms
	assert_bool(get_tree().paused).is_false()

func test_shake_decays() -> void:
	Fx.shake(6.0, 0.25)
	assert_float(Fx.trauma).is_greater(0.0)
	for _i in 300:
		Fx.decay_step()                    # 每帧衰减（×0.9），300 帧后归零
	assert_float(Fx.trauma).is_equal_approx(0.0, 0.001)
