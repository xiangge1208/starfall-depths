class_name TestComboCounter
extends GdUnitTestSuite
## J-B（Juice v2 §2 J2/J5）TDD：trauma 震屏 v2 + 连击音高。
## 纯逻辑全注入（合成时间戳，不依赖真实抖动时序）；相机用例注入 trauma/设置档，
## 断言平方曲线幅值公式与 clamp（噪声采样确定性由 seed 42 钉住）。
## 数值唯一出处：res://data/balance.json juice 节本卡键（JSON 数字一律 float，
## 断言按 float 比）；生产装载 fail-soft，坏键回落规格默认。

const CAMERA_SCRIPT := preload("res://fx/game_camera.gd")
const SAVE_SYSTEM_SCRIPT := preload("res://autoload/save_system.gd")

var _old_settings: Dictionary
var _tmp_paths: Array[String] = []


func before_test() -> void:
	Fx.cancel_hitstop()
	Fx.trauma = 0.0
	Fx.on_weapon_switched()   # 隔离前序用例残留连击
	_old_settings = (SaveSystem.data.get("settings", {}) as Dictionary).duplicate(true)
	if typeof(SaveSystem.data.get("settings")) != TYPE_DICTIONARY:
		SaveSystem.data["settings"] = SaveSystem.DEFAULT_SETTINGS.duplicate()


func after_test() -> void:
	Fx.cancel_hitstop()
	Fx.trauma = 0.0
	Fx.on_weapon_switched()
	SaveSystem.data["settings"] = _old_settings
	for path in _tmp_paths:
		DirAccess.remove_absolute(path)
	_tmp_paths.clear()


func _tmp_path(tag: String) -> String:
	var path := "user://test_jb_%s_%d.json" % [tag, absi(randi())]
	_tmp_paths.append(path)
	return path


func _write_tmp(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _counter() -> ComboCounter:
	return ComboCounter.new()   # 规格默认：窗 1200ms / 步长 0.02 / 封顶 6 档


# ---- 1. ComboCounter 纯逻辑（J5） ----

func test_combo_accumulates_within_window() -> void:
	var c := _counter()
	c.on_hit(0)
	c.on_hit(500)
	c.on_hit(1199)
	assert_int(c.combo()).is_equal(3)


func test_combo_boundary_exactly_window_ms_still_counts() -> void:
	var c := _counter()
	c.on_hit(0)
	c.on_hit(1200)          # 恰在窗边界：仍算连击
	assert_int(c.combo()).is_equal(2)


func test_combo_expires_lazily_after_window() -> void:
	# 惰性过期：无逐帧 tick，下一次命中时判过期清零后重新计 1
	var c := _counter()
	c.on_hit(0)
	c.on_hit(1200)
	c.on_hit(2401)          # 距上一击 1201 > 1200：脱战
	assert_int(c.combo()).is_equal(1)


func test_pitch_formula_samples() -> void:
	var c := _counter()
	assert_float(c.pitch()).is_equal_approx(1.0, 0.0001)   # 0 连击 → 1.0
	c.on_hit(0)
	assert_float(c.pitch()).is_equal_approx(1.02, 0.0001)  # combo 1 → 1.0 + 0.02
	for i in 6:
		c.on_hit(100 + i)                                   # combo 7
	assert_float(c.pitch()).is_equal_approx(1.12, 0.0001)  # min(7, 6) → 1.0 + 0.12
	c.on_hit(300)
	assert_float(c.pitch()).is_equal_approx(1.12, 0.0001)  # 封顶后不再升高


func test_weapon_switch_resets() -> void:
	var c := _counter()
	c.on_hit(0)
	c.on_hit(10)
	c.on_weapon_switch(20)
	assert_int(c.combo()).is_equal(0)
	assert_float(c.pitch()).is_equal_approx(1.0, 0.0001)


func test_player_hurt_resets() -> void:
	var c := _counter()
	c.on_hit(0)
	c.on_hit(10)
	c.on_player_hurt(20)
	assert_int(c.combo()).is_equal(0)
	assert_float(c.pitch()).is_equal_approx(1.0, 0.0001)


func test_constructor_injection_params() -> void:
	# 窗口/步长/封顶全注入：3 命中 → min(3, 2) × 0.05
	var c := ComboCounter.new(1000, 0.05, 2)
	c.on_hit(0)
	c.on_hit(500)
	c.on_hit(999)
	assert_int(c.combo()).is_equal(3)
	assert_float(c.pitch()).is_equal_approx(1.10, 0.0001)
	c.on_hit(1999)          # 距上一击恰 1000ms = 窗边界：仍累计
	assert_int(c.combo()).is_equal(4)
	c.on_hit(3001)          # 距上一击 1002ms > 1000ms：过期清零
	assert_int(c.combo()).is_equal(1)


# ---- 2. Fx trauma v2：注入 / clamp / 衰减 / 来源表 ----

func test_trauma_injection_clamps_at_one() -> void:
	Fx.add_trauma(0.7)
	Fx.add_trauma(0.7)
	assert_float(Fx.trauma).is_equal(1.0)   # 晕动红线：峰值 clamp 1.0


func test_decay_16_per_second_sample_points() -> void:
	Fx.add_trauma(0.6)
	Fx.decay_step(0.1)
	assert_float(Fx.trauma).is_equal_approx(0.44, 0.0001)   # 1.6/s × 0.1s
	Fx.decay_step(0.1)
	assert_float(Fx.trauma).is_equal_approx(0.28, 0.0001)
	Fx.decay_step(1.0)
	assert_float(Fx.trauma).is_equal(0.0)                   # 线性衰减夹 0，不穿负


func test_source_table_amounts_from_balance() -> void:
	# 来源表逐项（balance.json juice 节为唯一数值出处）
	assert_float(Fx.trauma_source_amount("shake_player_hurt")).is_equal_approx(0.3, 0.0001)
	assert_float(Fx.trauma_source_amount("shake_explosion")).is_equal_approx(0.4, 0.0001)
	assert_float(Fx.trauma_source_amount("shake_boss_phase")).is_equal_approx(0.5, 0.0001)
	assert_float(Fx.trauma_source_amount("shake_boss_death")).is_equal_approx(1.0, 0.0001)
	assert_float(Fx.trauma_source_amount("shake_kill")).is_equal_approx(0.15, 0.0001)


func test_shake_by_source_name_injects_trauma() -> void:
	Fx.shake("shake_player_hurt")
	assert_float(Fx.trauma).is_equal_approx(0.3, 0.0001)


func test_unknown_source_falls_back_to_zero() -> void:
	Fx.shake("shake_nonsense")
	assert_float(Fx.trauma).is_equal(0.0)


func test_shake_early_exits_during_hitstop_pause() -> void:
	# v1.5 契约保持：hitstop 冻结拍（树暂停中）不吃震屏
	for _i in 300:
		Fx.decay_step(1.0 / 60.0)
	Fx.hitstop(80)
	assert_bool(get_tree().paused).is_true()
	Fx.shake("shake_boss_death")
	assert_float(Fx.trauma).is_equal(0.0)


func test_boss_death_source_is_j7_exception_one_point_oh() -> void:
	# J7 唯一例外：单事件注入 1.0（其余来源 ≤0.5，由来源表数据保证）
	assert_float(Fx.trauma_source_amount("shake_boss_death")).is_equal(1.0)
	Fx.shake("shake_boss_death")
	assert_float(Fx.trauma).is_equal(1.0)


func test_juice_params_known_key_bad_type_falls_back_to_default() -> void:
	# 本卡新增键「已知即校验类型」：非数值回落规格默认（fail-soft，不崩表现层）
	var path := _tmp_path("badtype")
	_write_tmp(path, '{"version":1,"juice":{"trauma_decay_per_s":"fast","shake_player_hurt":0.9}}')
	var p := Fx.load_juice_params(path)
	assert_float(p["trauma_decay_per_s"]).is_equal(1.6)                  # 坏键回落默认
	assert_float(p["shake_player_hurt"]).is_equal_approx(0.9, 0.0001)    # 好键生效


func test_juice_params_missing_file_falls_back_to_defaults() -> void:
	var p := Fx.load_juice_params("user://test_jb_absent_%d.json" % absi(randi()))
	assert_float(p["trauma_decay_per_s"]).is_equal(1.6)
	assert_float(p["trauma_offset_px"]).is_equal(8.0)
	assert_float(p["trauma_rot_deg"]).is_equal(2.0)
	assert_float(p["combo_window_ms"]).is_equal(1200.0)


# ---- 3. 幅值公式：平方曲线 + 设置档映射（J2） ----

func test_squared_curve_amplitude_samples() -> void:
	# trauma 0.5 → 位移 2px、旋转 0.5°（trauma² = 0.25 × 8px / 2°）
	assert_float(CAMERA_SCRIPT.shake_amplitude(0.5, 1.0)).is_equal_approx(2.0, 0.0001)
	assert_float(CAMERA_SCRIPT.shake_rotation_deg(0.5, 1.0)).is_equal_approx(0.5, 0.0001)
	# trauma 1.0 → 满幅 8px / 2°
	assert_float(CAMERA_SCRIPT.shake_amplitude(1.0, 1.0)).is_equal_approx(8.0, 0.0001)
	assert_float(CAMERA_SCRIPT.shake_rotation_deg(1.0, 1.0)).is_equal_approx(2.0, 0.0001)


func test_setting_scale_mapping_0_half_1() -> void:
	assert_float(CAMERA_SCRIPT.shake_amplitude(1.0, 0.0)).is_equal(0.0)
	assert_float(CAMERA_SCRIPT.shake_rotation_deg(1.0, 0.0)).is_equal(0.0)
	assert_float(CAMERA_SCRIPT.shake_amplitude(1.0, 0.5)).is_equal_approx(4.0, 0.0001)
	assert_float(CAMERA_SCRIPT.shake_rotation_deg(1.0, 0.5)).is_equal_approx(1.0, 0.0001)
	assert_float(CAMERA_SCRIPT.shake_amplitude(1.0, 1.0)).is_equal_approx(8.0, 0.0001)


func test_amplitude_defensive_clamp_negative_and_over_one() -> void:
	# 防御夹取：负值/超 1 的 trauma 也不会放大振幅（晕动防线）
	assert_float(CAMERA_SCRIPT.shake_amplitude(-0.5, 1.0)).is_equal(0.0)
	assert_float(CAMERA_SCRIPT.shake_amplitude(2.0, 1.0)).is_equal_approx(8.0, 0.0001)
	assert_float(CAMERA_SCRIPT.shake_rotation_deg(7.0, 1.0)).is_equal_approx(2.0, 0.0001)


func test_default_setting_is_half() -> void:
	# 晕动防线「默认档 50%」：DEFAULT_SETTINGS 与全新档读取双断言
	assert_float(float(SaveSystem.DEFAULT_SETTINGS["screen_shake"])).is_equal_approx(0.5, 0.0001)
	var s: Node = auto_free(SAVE_SYSTEM_SCRIPT.new())
	var path := _tmp_path("default")
	s.set("save_path", path)
	s.call("load_save")
	assert_float(float(s.get_setting("screen_shake", 9.9))).is_equal_approx(0.5, 0.0001)


# ---- 4. 相机实例（seed 42 确定性 / 0 档断零 / 真实 delta 衰减） ----

func test_camera_offset_within_squared_amplitude_bounds() -> void:
	SaveSystem.data["settings"]["screen_shake"] = 1.0
	Fx.trauma = 0.5
	var camera: Camera2D = auto_free(CAMERA_SCRIPT.new())
	camera._process(1.0 / 60.0)
	assert_float(camera.offset.length()).is_less_equal(2.0 + 0.0001)          # trauma²×8
	assert_float(absf(camera.rotation)).is_less_equal(deg_to_rad(0.5) + 0.0001)


func test_camera_noise_deterministic_with_seed_42() -> void:
	SaveSystem.data["settings"]["screen_shake"] = 1.0
	var c1: Camera2D = auto_free(CAMERA_SCRIPT.new())
	var c2: Camera2D = auto_free(CAMERA_SCRIPT.new())
	Fx.trauma = 1.0
	c1._process(1.0 / 60.0)
	var o1: Vector2 = c1.offset
	var r1: float = c1.rotation
	Fx.trauma = 1.0                       # 复位（c1._process 已衰减一次）
	c2._process(1.0 / 60.0)
	assert_vector(c2.offset).is_equal(o1) # seed 42 钉死：同一时间线同偏移
	assert_float(c2.rotation).is_equal(r1)


func test_camera_advances_noise_over_time() -> void:
	# x 轴随时间推进：连续两帧采样不恒零（trauma=1 满幅下噪声必有位移输出）
	SaveSystem.data["settings"]["screen_shake"] = 1.0
	Fx.trauma = 1.0
	var camera: Camera2D = auto_free(CAMERA_SCRIPT.new())
	camera._process(1.0 / 60.0)
	Fx.trauma = 1.0
	camera._process(1.0 / 60.0)
	Fx.trauma = 1.0
	camera._process(1.0 / 60.0)
	var moved := false
	for _i in 10:
		Fx.trauma = 1.0
		camera._process(1.0 / 60.0)
		if camera.offset.length() > 0.001:
			moved = true
	assert_bool(moved).is_true()


func test_camera_zero_setting_zero_offset_and_still_decays() -> void:
	SaveSystem.data["settings"]["screen_shake"] = 0.0
	Fx.trauma = 1.0
	var camera: Camera2D = auto_free(CAMERA_SCRIPT.new())
	camera.offset = Vector2(99, 99)
	camera.rotation = 1.234
	camera._process(1.0 / 60.0)
	assert_vector(camera.offset).is_equal(Vector2.ZERO)
	assert_float(camera.rotation).is_equal(0.0)
	assert_float(Fx.trauma).is_equal_approx(1.0 - 1.6 / 60.0, 0.0001)   # 关档仍衰减


func test_camera_decays_trauma_with_render_delta() -> void:
	# 衰减按渲染 delta（表现层计时，与 hitstop 真实毫秒同口径）
	SaveSystem.data["settings"]["screen_shake"] = 1.0
	Fx.trauma = 0.8
	var camera: Camera2D = auto_free(CAMERA_SCRIPT.new())
	camera._process(0.25)
	assert_float(Fx.trauma).is_equal_approx(0.4, 0.0001)   # 0.8 - 1.6 × 0.25


# ---- 5. 生产接线（命中结算点上报 / 换武器重置 / 受击重置 / 来源表注入行） ----

class DummyBody extends Node2D:
	var hits: Array = []
	func take_hit(ctx: Dictionary) -> void:
		hits.append(ctx)
	func combat_radius() -> float:
		return 6.0


func _make_cs() -> CombatSystem:
	# 同 test_combat_system 惯例
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var rng := RngSvc.stream(0, "combat")
	rng.seed = 11
	var cs := CombatSystem.new(root, rng)
	root.add_child(cs)
	return cs


func _player_bullet(cs: CombatSystem) -> void:
	cs.spawn_projectile({"pos": Vector2(100, 0), "vel": Vector2.RIGHT * 600, "damage": 4,
		"faction": Projectile.Faction.PLAYER, "element": 0, "pierce": 0, "bounce": 0,
		"life_seconds": 1.0, "radius": 3.0})


func test_combat_system_player_hits_report_combo_pitch() -> void:
	# 命中结算点上报缝（跟随 test_combat_system 惯例做最小验证）
	var cs := _make_cs()
	var body: DummyBody = auto_free(DummyBody.new())
	cs.get_parent().add_child(body)
	body.position = Vector2(200, 0)
	cs.register_body(body, Projectile.Faction.ENEMY)
	_player_bullet(cs)
	for _i in 30:
		await get_tree().physics_frame
	assert_int(body.hits.size()).is_equal(1)
	assert_float(Fx.combo_pitch()).is_equal_approx(1.02, 0.0001)   # 1 命中 → +1 档
	_player_bullet(cs)
	for _i in 30:
		await get_tree().physics_frame
	assert_int(body.hits.size()).is_equal(2)
	assert_float(Fx.combo_pitch()).is_equal_approx(1.04, 0.0001)   # 2 连击


func test_combat_system_enemy_hits_do_not_report() -> void:
	var cs := _make_cs()
	var body: DummyBody = auto_free(DummyBody.new())
	cs.get_parent().add_child(body)
	body.position = Vector2(200, 0)
	cs.register_body(body, Projectile.Faction.PLAYER)   # 敌方弹目标
	cs.spawn_projectile({"pos": Vector2(100, 0), "vel": Vector2.RIGHT * 600, "damage": 4,
		"faction": Projectile.Faction.ENEMY, "element": 0, "pierce": 0, "bounce": 0,
		"life_seconds": 1.0, "radius": 3.0})
	for _i in 30:
		await get_tree().physics_frame
	assert_int(body.hits.size()).is_equal(1)
	assert_float(Fx.combo_pitch()).is_equal_approx(1.0, 0.0001)   # 敌方弹命中不计连击


func test_weapon_rig_switch_resets_fx_combo() -> void:
	Fx.on_combo_hit()
	Fx.on_combo_hit()
	assert_float(Fx.combo_pitch()).is_equal_approx(1.04, 0.0001)
	var rig: WeaponRig = auto_free(WeaponRig.new())
	rig._test_init()
	rig.switch_slot(0)
	assert_float(Fx.combo_pitch()).is_equal_approx(1.0, 0.0001)   # 换武器重置


func test_player_damaged_resets_fx_combo() -> void:
	Fx.on_combo_hit()
	assert_float(Fx.combo_pitch()).is_greater(1.0)
	EventBus.player_damaged.emit(3, false)
	assert_float(Fx.combo_pitch()).is_equal_approx(1.0, 0.0001)   # 受击重置


func test_production_wiring_lines_present() -> void:
	# 行级接线钉（同 test_hitstop 惯例）：结算点/近战/换武器/Boss 阶段/Boss 死亡来源注入
	var cs_src := FileAccess.get_file_as_string("res://core/combat/combat_system.gd")
	assert_bool(cs_src.contains("Fx.on_combo_hit()")).is_true()
	assert_bool(cs_src.contains("AudioMgr.play(\"hit_enemy\", Fx.combo_pitch())")).is_true()
	assert_bool(FileAccess.get_file_as_string("res://core/player/melee.gd")
		.contains("Fx.on_combo_hit()")).is_true()
	assert_bool(FileAccess.get_file_as_string("res://core/player/weapon_rig.gd")
		.contains("Fx.on_weapon_switched()")).is_true()
	assert_bool(FileAccess.get_file_as_string("res://core/enemies/boss_base.gd")
		.contains("Fx.shake(\"shake_boss_phase\")")).is_true()
	# J7 例外值经 request_boss_death 链启动注入（gdUnit 前台门使功能性断言不可达，钉源码）
	assert_bool(FileAccess.get_file_as_string("res://autoload/fx.gd")
		.contains("shake(\"shake_boss_death\")")).is_true()
