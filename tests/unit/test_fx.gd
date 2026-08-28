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

func test_hitstop_extension_not_cut_short_by_replaced_timer() -> void:
	# fix1 回归：40ms hitstop 进行中延长为 60ms —— 被替换的旧定时器到点不得提前解冻
	#（真实序列：暴击 hitstop(40) 后同帧击杀 hitstop(60)；原实现只冻 ~40ms）。
	Fx.hitstop(40)
	await get_tree().create_timer(0.01, true, false, true).timeout   # ~10ms 后延长
	Fx.hitstop(60)                       # 权威换为 60ms；旧 40ms 定时器已断开
	await get_tree().create_timer(0.045, true, false, true).timeout  # ~55ms：已越过旧 40ms 到期点
	assert_bool(get_tree().paused).is_true()      # bug 在此暴露：~40ms 处已被旧定时器解冻
	await get_tree().create_timer(0.05, true, false, true).timeout   # ~105ms：60ms 权威（~15ms 起 → ~75ms）已恢复
	assert_bool(get_tree().paused).is_false()
