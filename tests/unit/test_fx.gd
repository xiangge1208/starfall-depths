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
	# J4 v2 适配（意图保持「暴击更大」）：定值 1.5× → 弹跳缓动 1.0→1.6→1.3（0.18s）
	assert_vector(label.scale).is_equal(Vector2.ONE)   # 弹跳起点 1.0（tween 首帧前）
	label.queue_free()

func test_crit_number_bounces_to_peak_then_settles() -> void:
	# J4：暴击弹跳规格钉（0.18s / 峰值 1.6 / 落定 1.3）。满载套件下前序用例可能留下
	# 慢速/冻结时间窗（真实导演段定时器跨套件恢复），定点采样会假红——轮询至 tween
	# 落定（连续两帧不变且 >1.2；终值 1.3 唯弹跳 tween 可达），5s 兜底。
	assert_float(Fx.CRIT_BOUNCE_SEC).is_equal(0.18)
	assert_float(Fx.CRIT_BOUNCE_PEAK).is_equal(1.6)
	assert_float(Fx.CRIT_BOUNCE_SETTLE).is_equal(1.3)
	var label := Fx.spawn_damage_number(Vector2.ZERO, 7, true)
	assert_vector(label.scale).is_equal(Vector2.ONE)          # 弹跳起点（v1 定值 1.5× 已废）
	var deadline := Time.get_ticks_msec() + 5000
	var last := Vector2(-1.0, -1.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if label.scale.is_equal_approx(last) and label.scale.x > 1.2:
			break                                             # tween 已落定（冻结值 = 终值）
		last = label.scale
	assert_vector(label.scale).is_equal(Vector2(1.3, 1.3))    # 落定 1.3
	label.queue_free()

func test_tick_number_small_colored_no_bounce() -> void:
	# J4：元素 tick 跳字（燃烧/中毒 DOT）——元素色、0.8× 小号、不弹跳
	var label := Fx.spawn_damage_number(Vector2.ZERO, 1, false, Elements.Id.FIRE)
	assert_object(label).is_not_null()
	assert_vector(label.scale).is_equal(Vector2(0.8, 0.8))
	assert_that(label.get_theme_color("font_color")).is_equal(Fx.ELEMENT_COLORS[Elements.Id.FIRE])
	await get_tree().create_timer(0.1, true, false, true).timeout
	assert_vector(label.scale).is_equal(Vector2(0.8, 0.8))   # 无弹跳：保持 0.8×
	label.queue_free()

func test_enemy_hit_status_ctx_spawns_element_tick_number() -> void:
	# J4 接线钉：DOT 结算点（element_dot / blaze）ctx.source_type == "status" 且携带
	# tick_element → on_enemy_hit 自动出 0.8× 元素色小字（结算点各 +1 行注入，判定不读）
	SaveSystem.data["settings"]["hitstop_enabled"] = false
	var enemy: Node2D = auto_free(Node2D.new())
	add_child(enemy)
	var before := Fx.get_child_count()
	Fx.on_enemy_hit(enemy, {"amount": 1, "is_crit": false, "element": Elements.Id.NONE,
		"source_type": "status", "source_id": "element_dot", "tick_element": Elements.Id.POISON})
	var tick_labels: Array = []
	for child in Fx.get_children().slice(before):
		if child is Label and String(child.name).begins_with("DamageNumber"):
			tick_labels.append(child)
	assert_int(tick_labels.size()).is_equal(1)
	var label: Label = tick_labels[0]
	assert_vector(label.scale).is_equal(Vector2(0.8, 0.8))
	assert_that(label.get_theme_color("font_color")).is_equal(Fx.ELEMENT_COLORS[Elements.Id.POISON])
	label.queue_free()

func test_damage_number_culled_when_offscreen_by_injected_rect() -> void:
	# J4 视野裁剪：注入矩形缝（不依赖真实相机）；空矩形/无相机默认不裁剪
	Fx.visible_world_rect_provider = func() -> Rect2:
		return Rect2(0, 0, 100, 100)
	assert_object(Fx.spawn_damage_number(Vector2(50, 50), 3, false)).is_not_null()
	assert_object(Fx.spawn_damage_number(Vector2(200, 200), 3, false)).is_null()
	Fx.visible_world_rect_provider = Callable()
	assert_object(Fx.spawn_damage_number(Vector2(9999, 9999), 3, false)).is_not_null()
	Fx.particles.step(1.0)   # 清理本次产生的池上单元

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

# ---------- M3 J3：池化火花 / 击杀碎片环 / 枪口焰消费入口（接线） ----------

func test_enemy_hit_spawns_pooled_spark_three_states() -> void:
	# 总开关关：暴击分支的 hitstop 不冻结测试树（火花表现与开关无关）
	SaveSystem.data["settings"]["hitstop_enabled"] = false
	var enemy: Node2D = auto_free(Node2D.new())
	add_child(enemy)
	# 通用火花（无元素）
	var before := Fx.particles.active_units()
	Fx.on_enemy_hit(enemy, {"amount": 3, "is_crit": false, "element": Elements.Id.NONE})
	assert_int(Fx.particles.active_units()).is_equal(before + 1)
	# 元素命中 → 元素条带（ctx.element 为武器原生元素）
	Fx.on_enemy_hit(enemy, {"amount": 3, "is_crit": false, "element": Elements.Id.ICE})
	var ice_u := _pool_unit_by_strip("spark_ice")
	assert_object(ice_u).is_not_null()
	Fx.particles.step(1.0)
	# 暴击 → spark_crit（金 tint + 1.3×）
	before = Fx.particles.active_units()
	Fx.on_enemy_hit(enemy, {"amount": 9, "is_crit": true, "element": Elements.Id.NONE})
	var crit_u := _pool_unit_by_strip("spark_crit")
	assert_object(crit_u).is_not_null()
	assert_vector(crit_u.scale).is_equal(Vector2(1.3, 1.3))
	assert_that(crit_u.modulate).is_equal(Color(1.0, 0.85, 0.2))
	Fx.particles.step(1.0)
	# 蓄力/引信预警：无火花、无数字（既有语义保持）
	before = Fx.particles.active_units()
	var labels_before := Fx.get_child_count()
	Fx.on_enemy_hit(enemy, {"amount": 3, "telegraph": true})
	assert_int(Fx.particles.active_units()).is_equal(before)
	assert_int(Fx.get_child_count()).is_equal(labels_before)

func test_enemy_killed_overlays_kill_shard_ring() -> void:
	# J3：击杀爆散（v1 _puff 保留）之上叠加 6 帧碎片环；总开关关避免击杀 hitstop 冻结测试树
	SaveSystem.data["settings"]["hitstop_enabled"] = false
	var before := Fx.particles.active_units()
	Fx.on_enemy_killed(Vector2(8, 8))
	assert_int(Fx.particles.active_units()).is_equal(before + 1)
	var shard := _pool_unit_by_strip("kill_shard")
	assert_object(shard).is_not_null()
	assert_vector(shard.position).is_equal(Vector2(8, 8))
	Fx.particles.step(1.0)

func test_spawn_muzzle_flash_entry_plays_pooled_unit() -> void:
	# J3：枪口焰消费入口（weapon_rig._fire_slot 调用；类别 tint/朝向在池端落位）
	var before := Fx.particles.active_units()
	Fx.spawn_muzzle_flash(Vector2(30, 40), 1.2, "rifle")
	assert_int(Fx.particles.active_units()).is_equal(before + 1)
	var muzzle := _pool_unit_by_strip("muzzle_v2")
	assert_object(muzzle).is_not_null()
	assert_float(muzzle.rotation).is_equal_approx(1.2, 0.0001)
	Fx.particles.step(1.0)

func _pool_unit_by_strip(strip: String) -> ParticlesPool.Unit:
	for u: ParticlesPool.Unit in Fx.particles.units():
		if u.playing and u.strip == strip:
			return u
	return null
