class_name TestFx
extends GdUnitTestSuite
## m0-t12：Fx hitstop 合并（取更长）与震屏衰减。
## M1 设置消费者：屏震倍率 / 伤害数字开关 / 元素色弱形状编码。

const CAMERA_SCRIPT := preload("res://fx/game_camera.gd")

var _old_settings: Dictionary

func before_test() -> void:
	# Fx 是 Autoload；前一套房间/Boss 测试可能留下仍在计时的 120ms hitstop。
	# 每个用例从明确的未冻结边界开始，避免“最长 hitstop 优先”的生产语义
	# 把上一用例的冻结误算进本用例。
	Fx.cancel_hitstop()
	_old_settings = (SaveSystem.data.get("settings", {}) as Dictionary).duplicate(true)
	if typeof(SaveSystem.data.get("settings")) != TYPE_DICTIONARY:
		SaveSystem.data["settings"] = SaveSystem.DEFAULT_SETTINGS.duplicate()

func after_test() -> void:
	Fx.cancel_hitstop()
	SaveSystem.data["settings"] = _old_settings
	Fx.trauma = 0.0
	for child in Fx.get_children():
		if child.name == "DamageNumber" or child.name == "ElementShape":
			child.free()

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

## m1-t18 juice v1.5：hitstop 冻结拍（树暂停中）shake 早退，不再叠加震屏；
## 解冻后恢复原语义。
func test_shake_suppressed_during_hitstop_pause() -> void:
	for _i in 300:
		Fx.decay_step()                       # 隔离前序用例残留 trauma
	Fx.hitstop(80)
	assert_bool(get_tree().paused).is_true()
	Fx.shake(6.0, 0.1)
	assert_float(Fx.trauma).is_equal(0.0)     # 冻结拍不吃震屏
	await get_tree().create_timer(0.12, true, false, true).timeout
	assert_bool(get_tree().paused).is_false()
	Fx.shake(6.0, 0.1)
	assert_float(Fx.trauma).is_greater(0.0)   # 解冻后照常
	for _i in 300:
		Fx.decay_step()

func test_hitstop_extension_not_cut_short_by_replaced_timer() -> void:
	# fix1 回归：40ms hitstop 进行中延长为 60ms —— 被替换的旧定时器到点不得提前解冻
	#（真实序列：暴击 hitstop(40) 后同帧击杀 hitstop(60)；原实现只冻 ~40ms）。
	# m3-ja 集成稳固化：全量高负载下 SceneTreeTimer 实际触发可晚漂 15ms+，原两段定点
	# 采样（55ms 定点判「仍冻结」）余量过薄会假红；改为轮询记录实际解冻时刻，只设
	# 下界——提前解冻（bug 形态 ~40ms）才判负，回归意图不变且与负载无关。
	var t0 := Time.get_ticks_msec()
	Fx.hitstop(40)
	await get_tree().create_timer(0.01, true, false, true).timeout   # ~10ms 后延长
	Fx.hitstop(60)                       # 权威换为 60ms；旧 40ms 定时器已断开
	while get_tree().paused and Time.get_ticks_msec() - t0 < 300:
		await get_tree().process_frame
	assert_int(Time.get_ticks_msec() - t0).is_greater(50)   # bug 在此暴露：~40ms 处已被旧定时器解冻
	assert_bool(get_tree().paused).is_false()   # 60ms 权威到期已恢复（或 300ms 兜底判负）

func test_screen_shake_setting_is_clamped_scale() -> void:
	SaveSystem.data["settings"]["screen_shake"] = 0.5
	assert_float(Fx.screen_shake_scale()).is_equal_approx(0.5, 0.0001)
	SaveSystem.data["settings"]["screen_shake"] = -2.0
	assert_float(Fx.screen_shake_scale()).is_equal(0.0)
	SaveSystem.data["settings"]["screen_shake"] = 7.0
	assert_float(Fx.screen_shake_scale()).is_equal(1.0)

func test_game_camera_zero_setting_forces_zero_offset_and_still_decays() -> void:
	SaveSystem.data["settings"]["screen_shake"] = 0.0
	Fx.trauma = 2.0
	var camera: Camera2D = auto_free(CAMERA_SCRIPT.new())
	camera.offset = Vector2(99, 99)
	camera._process(0.0)
	assert_vector(camera.offset).is_equal(Vector2.ZERO)
	assert_float(Fx.trauma).is_equal_approx(1.8, 0.0001)

func test_game_camera_half_setting_caps_offset_to_half_amplitude() -> void:
	SaveSystem.data["settings"]["screen_shake"] = 0.5
	Fx.trauma = 2.0
	var camera: Camera2D = auto_free(CAMERA_SCRIPT.new())
	camera._process(0.0)
	assert_float(CAMERA_SCRIPT.shake_amplitude(2.0, 0.5)).is_equal(4.0)
	assert_float(CAMERA_SCRIPT.shake_amplitude(2.0, 0.0)).is_equal(0.0)
	assert_float(absf(camera.offset.x)).is_less_equal(4.0)
	assert_float(absf(camera.offset.y)).is_less_equal(4.0)

func test_damage_numbers_false_creates_no_label() -> void:
	SaveSystem.data["settings"]["damage_numbers"] = false
	var before := Fx.get_child_count()
	assert_object(Fx.spawn_damage_number(Vector2.ZERO, 12, false)).is_null()
	assert_int(Fx.get_child_count()).is_equal(before)

func test_damage_numbers_true_creates_named_label() -> void:
	SaveSystem.data["settings"]["damage_numbers"] = true
	var label := Fx.spawn_damage_number(Vector2.ZERO, 12, true)
	assert_object(label).is_not_null()
	assert_bool(String(label.name).begins_with("DamageNumber")).is_true()
	assert_str(label.text).is_equal("12")
	assert_vector(label.scale).is_equal(Vector2(1.5, 1.5))
	label.queue_free()

func test_colorblind_shape_mapping_matches_gdd() -> void:
	assert_str(Fx.element_shape(Elements.Id.FIRE)).is_equal("▲")
	assert_str(Fx.element_shape(Elements.Id.ICE)).is_equal("◆")
	assert_str(Fx.element_shape(Elements.Id.POISON)).is_equal("●")
	assert_str(Fx.element_shape(Elements.Id.SHOCK)).is_equal("ϟ")
	assert_str(Fx.element_shape(Elements.Id.NONE)).is_empty()

func test_colorblind_shapes_false_creates_no_shape() -> void:
	SaveSystem.data["settings"]["colorblind_shapes"] = false
	var before := Fx.get_child_count()
	assert_object(Fx.spawn_element_shape(Vector2.ZERO, Elements.Id.FIRE)).is_null()
	assert_int(Fx.get_child_count()).is_equal(before)

func test_colorblind_shapes_true_creates_production_hit_glyph() -> void:
	SaveSystem.data["settings"]["colorblind_shapes"] = true
	var label := Fx.spawn_element_shape(Vector2(10, 20), Elements.Id.ICE)
	assert_object(label).is_not_null()
	assert_bool(String(label.name).begins_with("ElementShape")).is_true()
	assert_str(label.text).is_equal("◆")
	label.queue_free()

func test_enemy_hit_consumes_damage_number_and_both_element_shape_settings() -> void:
	SaveSystem.data["settings"]["damage_numbers"] = false
	SaveSystem.data["settings"]["colorblind_shapes"] = true
	var enemy: Node2D = auto_free(Node2D.new())
	add_child(enemy)
	var before := Fx.get_child_count()
	Fx.on_enemy_hit(enemy, {
		"amount": 9, "is_crit": false,
		"element": Elements.Id.FIRE, "proc_element": Elements.Id.SHOCK,
	})
	var damage_count := 0
	var glyphs: Array[String] = []
	# SceneTree 在同名节点入树时会把第二个形状自动改成可读唯一名；按节点内容分类，
	# 不依赖运行时 name 的冲突后缀。
	for child in Fx.get_children().slice(before):
		if String(child.name).begins_with("DamageNumber"):
			damage_count += 1
		elif child is Label and ["▲", "◆", "●", "ϟ"].has(String(child.text)):
			glyphs.append(String(child.text))
	assert_int(damage_count).is_equal(0)
	assert_array(glyphs).contains_exactly(["▲", "ϟ"])

func test_status_applied_signal_consumes_colorblind_shape_setting() -> void:
	SaveSystem.data["settings"]["colorblind_shapes"] = true
	var enemy: Node2D = auto_free(Node2D.new())
	add_child(enemy)
	var before := Fx.get_child_count()
	EventBus.status_applied.emit(enemy, Elements.Id.POISON)
	var glyphs: Array[String] = []
	for child in Fx.get_children().slice(before):
		if child is Label:
			glyphs.append(String(child.text))
	assert_array(glyphs).contains_exactly(["●"])
