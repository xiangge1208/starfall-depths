class_name TestAutoAim
extends GdUnitTestSuite
## m1-t21 三端输入测试：auto_aim 纯逻辑 / 摇杆输出纯函数 / 手柄 InputMap 绑定 / 合成输入。
## 手柄绑定断言依赖 tools/setup_input.gd 已运行并重新生成 project.godot。

const GamepadAimScript := preload("res://core/player/gamepad_aim.gd")
const VirtualJoystickScript := preload("res://ui/virtual_joystick.gd")

func after_test() -> void:
	Input.action_release("fire")   # 合成输入用例后复位，避免污染其他套件

# ---------- AutoAim.pick_target：锥形选择 ----------

func test_pick_target_empty_returns_minus_one() -> void:
	assert_int(AutoAim.pick_target(Vector2.ZERO, 0.0, [])).is_equal(-1)

func test_pick_target_picks_min_angle_over_min_distance() -> void:
	# 锥内选最小偏角：0 号角度更小但更远，仍应胜出（同角才比距离）
	var enemies: Array[Vector2] = [Vector2(200, 20), Vector2(60, 30)]
	assert_int(AutoAim.pick_target(Vector2.ZERO, 0.0, enemies)).is_equal(0)

func test_pick_target_distance_tiebreak_on_equal_angle() -> void:
	# 同一方向上两个敌人：偏角相同（都为 0），取更近者
	var enemies: Array[Vector2] = [Vector2(200, 0), Vector2(100, 0)]
	assert_int(AutoAim.pick_target(Vector2.ZERO, 0.0, enemies)).is_equal(1)

func test_pick_target_ignores_out_of_cone() -> void:
	# 正后方与正侧方（±30° 锥外）均忽略
	var enemies: Array[Vector2] = [Vector2(-100, 0), Vector2(0, 100)]
	assert_int(AutoAim.pick_target(Vector2.ZERO, 0.0, enemies)).is_equal(-1)

func test_pick_target_boundary_at_half_cone_inclusive() -> void:
	# 恰在锥边界（偏角 = cone/2 = 30°）算锥内
	var enemies: Array[Vector2] = [Vector2(cos(deg_to_rad(30.0)), sin(deg_to_rad(30.0))) * 100.0]
	assert_int(AutoAim.pick_target(Vector2.ZERO, 0.0, enemies)).is_equal(0)

func test_pick_target_behind_180_excluded() -> void:
	# ±180° 边缘：正后方之敌，cone 359.9° 仍不可选（偏角 180° > 179.95°）
	var enemies: Array[Vector2] = [Vector2(-100, 0)]
	assert_int(AutoAim.pick_target(Vector2.ZERO, 0.0, enemies, 359.9)).is_equal(-1)

func test_pick_target_full_circle_includes_behind() -> void:
	# cone 360° 时 180° 偏角恰好可达（<=），可选
	var enemies: Array[Vector2] = [Vector2(-100, 0)]
	assert_int(AutoAim.pick_target(Vector2.ZERO, 0.0, enemies, 360.0)).is_equal(0)

func test_pick_target_angle_wraps_across_pm_pi() -> void:
	# 朝向 -171.9°，敌人在 +171.9°：跨 ±π 环绕后偏角 16.2°，在 60° 锥内
	var facing := deg_to_rad(-171.9)
	var enemies: Array[Vector2] = [Vector2.from_angle(deg_to_rad(171.9)) * 100.0]
	assert_int(AutoAim.pick_target(Vector2.ZERO, facing, enemies)).is_equal(0)

func test_pick_target_skips_enemy_on_player_position() -> void:
	# 与玩家重合的敌人方向未定义，跳过（不算"锥内 0 角"）
	var enemies: Array[Vector2] = [Vector2(1000, 1000), Vector2(1100, 1000)]
	assert_int(AutoAim.pick_target(Vector2(1000, 1000), 0.0, enemies)).is_equal(1)

# ---------- AutoAim.aim_vector：归一化 + 回退 ----------

func test_aim_vector_toward_picked_target_normalized() -> void:
	# 锥内取最小偏角（(40,30) 偏角 0° 胜出）→ 返回指向该目标的单位向量 (0.8, 0.6)
	var v := AutoAim.aim_vector(Vector2.ZERO, [Vector2(30, 40), Vector2(40, 30)] as Array[Vector2], Vector2(8, 6))
	assert_vector(v).is_equal_approx(Vector2(0.8, 0.6), Vector2(0.001, 0.001))

func test_aim_vector_fallback_when_no_targets() -> void:
	# 无目标 → 回退当前瞄准方向（归一化）
	var v := AutoAim.aim_vector(Vector2.ZERO, [] as Array[Vector2], Vector2(0, -10))
	assert_vector(v).is_equal_approx(Vector2(0, -1), Vector2(0.001, 0.001))

func test_aim_vector_fallback_when_all_out_of_cone() -> void:
	# 全部锥外 → 回退当前瞄准方向
	var v := AutoAim.aim_vector(Vector2.ZERO, [Vector2(-100, 0)] as Array[Vector2], Vector2.RIGHT)
	assert_vector(v).is_equal_approx(Vector2(1, 0), Vector2(0.001, 0.001))

func test_aim_vector_zero_current_aim_fallback_is_zero() -> void:
	# 当前瞄准为零向量且无目标 → 返回零（调用方据零判断"不开火"）
	var v := AutoAim.aim_vector(Vector2.ZERO, [] as Array[Vector2], Vector2.ZERO)
	assert_vector(v).is_equal(Vector2.ZERO)

# ---------- GamepadAimScript.stick_output：阈值纯函数 ----------

func test_stick_output_full_deflection_normalized() -> void:
	assert_vector(GamepadAimScript.stick_output(1.0, 0.0)).is_equal(Vector2(1, 0))

func test_stick_output_below_threshold_zero() -> void:
	assert_vector(GamepadAimScript.stick_output(0.3, 0.3)).is_equal(Vector2.ZERO)

func test_stick_output_exact_threshold_zero() -> void:
	# 模长恰为 0.5：不严格大于 → 无输出（spec: magnitude > 0.5）
	assert_vector(GamepadAimScript.stick_output(0.4, 0.3)).is_equal(Vector2.ZERO)

func test_stick_output_over_threshold_normalized() -> void:
	assert_vector(GamepadAimScript.stick_output(-0.6, 0.8)).is_equal_approx(Vector2(-0.6, 0.8), Vector2(0.001, 0.001))

func test_stick_output_custom_dead_zone() -> void:
	assert_vector(GamepadAimScript.stick_output(0.45, 0.0, 0.4)).is_equal(Vector2(1, 0))
	assert_vector(GamepadAimScript.stick_output(0.35, 0.0, 0.4)).is_equal(Vector2.ZERO)

# ---------- GamepadAim 合成输入（player.gd 零改动的关键） ----------

func test_gamepad_aim_presses_fire_beyond_threshold() -> void:
	var node: Node = auto_free(GamepadAimScript.new())
	var v: Vector2 = node._apply_axes(1.0, 0.0)
	assert_vector(v).is_equal(Vector2(1, 0))
	assert_vector(node.aim_vector).is_equal(Vector2(1, 0))
	assert_bool(Input.is_action_pressed("fire")).is_true()

func test_gamepad_aim_releases_fire_below_threshold() -> void:
	var node: Node = auto_free(GamepadAimScript.new())
	node._apply_axes(1.0, 0.0)
	node._apply_axes(0.2, 0.0)
	assert_vector(node.aim_vector).is_equal(Vector2.ZERO)
	assert_bool(Input.is_action_pressed("fire")).is_false()

# ---------- VirtualJoystickScript.joystick_output：死区/钳制/归一化 ----------

func test_joystick_output_unit_radius() -> void:
	assert_vector(VirtualJoystickScript.joystick_output(Vector2(48, 0))).is_equal_approx(Vector2(1, 0), Vector2(0.001, 0.001))

func test_joystick_output_zero_input() -> void:
	assert_vector(VirtualJoystickScript.joystick_output(Vector2.ZERO)).is_equal(Vector2.ZERO)

func test_joystick_output_dead_zone_boundary_zero() -> void:
	# 7.2/48 = 0.15 = 死区：边界内置零
	assert_vector(VirtualJoystickScript.joystick_output(Vector2(7.2, 0))).is_equal(Vector2.ZERO)

func test_joystick_output_clamps_over_radius() -> void:
	assert_vector(VirtualJoystickScript.joystick_output(Vector2(480, 0))).is_equal_approx(Vector2(1, 0), Vector2(0.001, 0.001))
	# 斜向超半径：钳制到单位圆
	assert_vector(VirtualJoystickScript.joystick_output(Vector2(48, 48))).is_equal_approx(Vector2(0.7071, 0.7071), Vector2(0.001, 0.001))

func test_joystick_output_rescales_after_dead_zone() -> void:
	# 死区外重缩放：(0.5-0.15)/(1-0.15) ≈ 0.4118，保留中心细控
	var v := VirtualJoystickScript.joystick_output(Vector2(24, 0))
	assert_float(v.x).is_equal_approx(0.41176, 0.001)

func test_joystick_output_custom_dead_zone() -> void:
	assert_vector(VirtualJoystickScript.joystick_output(Vector2(24, 0), 0.5, 48.0)).is_equal(Vector2.ZERO)

# ---------- VirtualJoystick 节点行为 ----------

func test_joystick_move_output_via_apply_raw() -> void:
	var node: Control = auto_free(VirtualJoystickScript.new())
	node._apply_raw(Vector2(48, 0))
	assert_vector(node.output).is_equal_approx(Vector2(1, 0), Vector2(0.001, 0.001))
	node._apply_raw(Vector2.ZERO)
	assert_vector(node.output).is_equal(Vector2.ZERO)

func test_joystick_aim_presses_fire_beyond_dead_zone() -> void:
	var node: Control = auto_free(VirtualJoystickScript.new())
	node.is_aim = true
	node._apply_raw(Vector2(48, 0))
	assert_vector(node.aim_vector).is_equal_approx(Vector2(1, 0), Vector2(0.001, 0.001))
	assert_bool(Input.is_action_pressed("fire")).is_true()

func test_joystick_aim_releases_fire_on_center() -> void:
	var node: Control = auto_free(VirtualJoystickScript.new())
	node.is_aim = true
	node._apply_raw(Vector2(48, 0))
	node._apply_raw(Vector2(3, 0))   # 死区内
	assert_bool(Input.is_action_pressed("fire")).is_false()

func test_joystick_hidden_on_desktop_unless_forced() -> void:
	var node: Control = auto_free(VirtualJoystickScript.new())
	node._refresh_visibility()
	assert_bool(node.visible).is_false()          # headless 无触屏 → 隐藏
	node.force_visible = true
	node._refresh_visibility()
	assert_bool(node.visible).is_true()

func test_joystick_touch_drag_release_glue() -> void:
	# 用构造事件驱动 _gui_input 胶水层（本机无触屏，等效真机按下-拖动-抬起）
	var node: Control = auto_free(VirtualJoystickScript.new())
	var press := InputEventScreenTouch.new()
	press.index = 3
	press.pressed = true
	press.position = Vector2(100, 100)
	node._gui_input(press)
	var drag := InputEventScreenDrag.new()
	drag.index = 3
	drag.position = Vector2(148, 100)             # 基座 (100,100) 起拖满半径
	node._gui_input(drag)
	assert_vector(node.output).is_equal_approx(Vector2(1, 0), Vector2(0.001, 0.001))
	var release := InputEventScreenTouch.new()
	release.index = 3
	release.pressed = false
	release.position = Vector2(148, 100)
	node._gui_input(release)
	assert_vector(node.output).is_equal(Vector2.ZERO)

# ---------- InputMap 手柄绑定（setup_input.gd 幂等写入后） ----------

func _motion_events(action: String) -> Array:
	var found: Array = []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadMotion:
			found.append(ev)
	return found

func _button_events(action: String) -> Array:
	var found: Array = []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton:
			found.append(ev)
	return found

func test_inputmap_left_stick_moves_bound() -> void:
	var axes := {
		"move_left": [JOY_AXIS_LEFT_X, -1.0],
		"move_right": [JOY_AXIS_LEFT_X, 1.0],
		"move_up": [JOY_AXIS_LEFT_Y, -1.0],
		"move_down": [JOY_AXIS_LEFT_Y, 1.0],
	}
	for action: String in axes:
		assert_bool(InputMap.has_action(action)).is_true()
		var bound := false
		for ev in _motion_events(action):
			if ev.axis == axes[action][0] and signf(ev.axis_value) == signf(axes[action][1]):
				bound = true
		assert_bool(bound).override_failure_message("动作 %s 缺少左摇杆绑定" % action).is_true()

func test_inputmap_buttons_bound() -> void:
	var buttons := {
		"roll": JOY_BUTTON_A,
		"skill": JOY_BUTTON_RIGHT_SHOULDER,
		"switch_weapon": JOY_BUTTON_LEFT_SHOULDER,
		"interact": JOY_BUTTON_X,
	}
	for action: String in buttons:
		var bound := false
		for ev in _button_events(action):
			if ev.button_index == buttons[action]:
				bound = true
		assert_bool(bound).override_failure_message("动作 %s 缺少手柄按键绑定" % action).is_true()

func test_inputmap_aim_actions_on_right_stick() -> void:
	# 新动作：右摇杆轴 2/3（双向极性都有事件）
	var axes := {"aim_right_x": JOY_AXIS_RIGHT_X, "aim_right_y": JOY_AXIS_RIGHT_Y}
	for action: String in axes:
		assert_bool(InputMap.has_action(action)).is_true()
		var bound := false
		for ev in _motion_events(action):
			if ev.axis == axes[action]:
				bound = true
		assert_bool(bound).override_failure_message("动作 %s 缺少右摇杆绑定" % action).is_true()

func test_inputmap_keeps_keyboard_bindings() -> void:
	# 手柄加入后桌面键位不动（桌面行为完全不变）
	var has_key := false
	for ev in InputMap.action_get_events("move_left"):
		if ev is InputEventKey and ev.physical_keycode == KEY_A:
			has_key = true
	assert_bool(has_key).is_true()
