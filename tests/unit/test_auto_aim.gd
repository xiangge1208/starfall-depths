class_name TestAutoAim
extends GdUnitTestSuite
## m1-t21 三端输入测试：auto_aim 纯逻辑 / 摇杆输出纯函数 / 手柄 InputMap 绑定 / 合成输入。
## 手柄绑定断言依赖 tools/setup_input.gd 已运行并重新生成 project.godot。

const GamepadAimScript := preload("res://core/player/gamepad_aim.gd")
const VirtualJoystickScript := preload("res://ui/virtual_joystick.gd")
const TouchModeScript := preload("res://ui/touch_mode.gd")

var _saved_aim_events: Dictionary = {}
var _saved_touch_controls := false

func before_test() -> void:
	_saved_aim_events.clear()
	for action in [&"aim_right_x", &"aim_right_y"]:
		_saved_aim_events[action] = InputMap.action_get_events(action).duplicate()
	_saved_touch_controls = bool(SaveSystem.get_setting("touch_controls", false))
	# 单测明确从桌面默认设置开始；只改内存，不触发 save_now 污染真人试玩档。
	SaveSystem.data["settings"]["touch_controls"] = false

func after_test() -> void:
	for action in ["fire", "skill", "roll", "switch_weapon", "interact",
			"move_left", "move_right", "move_up", "move_down", "touch_fire",
			"touch_skill", "touch_roll", "touch_switch_weapon", "touch_interact",
			"touch_move_left", "touch_move_right", "touch_move_up", "touch_move_down",
			"aim_right_x", "aim_right_y"]:
		Input.action_release(action)   # 合成输入用例后复位，避免污染其他套件
	for action: StringName in _saved_aim_events:
		InputMap.action_erase_events(action)
		for event: InputEvent in _saved_aim_events[action]:
			InputMap.action_add_event(action, event)
	SaveSystem.data["settings"]["touch_controls"] = _saved_touch_controls

# ---------- AutoAim.pick_target：锥形选择 ----------

func test_pick_target_empty_returns_minus_one() -> void:
	assert_int(AutoAim.pick_target(Vector2.ZERO, 0.0, [])).is_equal(-1)

func test_pick_target_picks_nearest_inside_cone_not_smallest_angle() -> void:
	# 文档要求：先滤锥外，再取锥内最近者；1 号偏角更大但更近，应胜出。
	var enemies: Array[Vector2] = [Vector2(200, 20), Vector2(60, 30)]
	assert_int(AutoAim.pick_target(Vector2.ZERO, 0.0, enemies)).is_equal(1)

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
	# 两者都在锥内且等距；稳定取输入顺序中的首个 → (0.6, 0.8)。
	var v := AutoAim.aim_vector(Vector2.ZERO, [Vector2(30, 40), Vector2(40, 30)] as Array[Vector2], Vector2(8, 6))
	assert_vector(v).is_equal_approx(Vector2(0.6, 0.8), Vector2(0.001, 0.001))

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

# ---------- m4-b3① lead 预判（可选参数；默认关 = 生产零漂移） ----------

func test_aim_vector_default_call_identical_across_signature_widths() -> void:
	# 生产零漂移钉：4 参既有调用 与 6 参全默认（vels 空 + 弹速 0）逐 Case 同结果。
	# 默认路径行为漂移时本测先红（auto_aim 生产参数面零漂移是 B-3 硬验收）。
	var cases := [
		{"pos": Vector2.ZERO, "aim": Vector2.RIGHT, "targets": [Vector2(160, 0)]},
		{"pos": Vector2.ZERO, "aim": Vector2(1, 1), "targets": [Vector2(60, 30), Vector2(200, 20)]},
		{"pos": Vector2(50, 50), "aim": Vector2.LEFT, "targets": [Vector2(-100, 50), Vector2(50, 300)]},
		{"pos": Vector2.ZERO, "aim": Vector2.RIGHT, "targets": [Vector2(-100, 0)]},
		{"pos": Vector2.ZERO, "aim": Vector2(2, 0), "targets": [Vector2(30, 40), Vector2(40, 30)]},
	]
	for c: Dictionary in cases:
		var targets: Array[Vector2] = []
		for t: Vector2 in c["targets"]:
			targets.append(t)
		var a4 := AutoAim.aim_vector(c["pos"], targets, c["aim"])
		var a6 := AutoAim.aim_vector(c["pos"], targets, c["aim"], 60.0, [], 0.0)
		assert_vector(a6).override_failure_message(str(c)).is_equal(a4)

func test_aim_vector_lead_intercepts_moving_target() -> void:
	# 目标 (160,0) 横移 60px/s、弹速 320px/s → 飞行 0.5s → 命中点 (160,30)。
	# m3-fix2 §2.1.3 风筝残差签名（60px/s 横移 × 弹 320px/s）的同参数复现。
	var aim := AutoAim.aim_vector(Vector2.ZERO, [Vector2(160, 0)] as Array[Vector2],
		Vector2.RIGHT, 60.0, [Vector2(0, 60)], 320.0)
	assert_vector(aim).is_equal_approx(Vector2(160, 30).normalized(), Vector2(0.001, 0.001))

func test_aim_vector_lead_off_when_bullet_speed_zero() -> void:
	# 弹速 ≤0 = lead 关（即便速度在场）→ 直瞄。
	var aim := AutoAim.aim_vector(Vector2.ZERO, [Vector2(160, 0)] as Array[Vector2],
		Vector2.RIGHT, 60.0, [Vector2(0, 60)], 0.0)
	assert_vector(aim).is_equal_approx(Vector2.RIGHT, Vector2(0.001, 0.001))

func test_aim_vector_stationary_target_lead_equals_direct() -> void:
	# 静止目标（零速度）：lead 打开也与直瞄逐字节同（无预判位移）。
	var direct := AutoAim.aim_vector(Vector2.ZERO, [Vector2(160, 0)] as Array[Vector2], Vector2.RIGHT)
	var leaded := AutoAim.aim_vector(Vector2.ZERO, [Vector2(160, 0)] as Array[Vector2],
		Vector2.RIGHT, 60.0, [Vector2.ZERO], 320.0)
	assert_vector(leaded).is_equal(direct)

func test_aim_vector_lead_missing_vel_entry_treated_stationary() -> void:
	# vels 短于 targets：缺项按静止处理（不崩、不误 lead）。
	# 锥内最近者 idx=1（160,0），vels[1] 缺 → 直瞄。
	var aim := AutoAim.aim_vector(Vector2.ZERO, [Vector2(200, 0), Vector2(160, 0)] as Array[Vector2],
		Vector2.RIGHT, 60.0, [Vector2(0, 60)], 320.0)
	assert_vector(aim).is_equal_approx(Vector2.RIGHT, Vector2(0.001, 0.001))

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

# ---------- GamepadAim 显式输入源 ----------

func test_gamepad_aim_exposes_direction_without_mutating_global_fire() -> void:
	var node: Node = auto_free(GamepadAimScript.new())
	Input.action_press("fire")
	var v: Vector2 = node._apply_axes(1.0, 0.0)
	assert_vector(v).is_equal(Vector2(1, 0))
	assert_vector(node.aim_vector).is_equal(Vector2(1, 0))
	assert_bool(Input.is_action_pressed("fire")).is_true()

func test_gamepad_aim_return_to_center_does_not_release_other_fire_source() -> void:
	var node: Node = auto_free(GamepadAimScript.new())
	Input.action_press("fire")
	node._apply_axes(1.0, 0.0)
	node._apply_axes(0.2, 0.0)
	assert_vector(node.aim_vector).is_equal(Vector2.ZERO)
	assert_bool(Input.is_action_pressed("fire")).is_true()

func test_gamepad_aim_reads_aim_actions_after_inputmap_remap() -> void:
	# 所有按键均须支持 InputMap 重映射。把瞄准动作从旧轴 2/3 改到 0/1 后，
	# 新轴必须立即生效；旧轴事件即使送达节点也必须失效。
	var node: Node = auto_free(GamepadAimScript.new())
	add_child(node)
	await _send_joy_motion(node, JOY_AXIS_RIGHT_X, 1.0)
	assert_vector(node._read_aim_actions()).is_equal(Vector2.RIGHT)

	_remap_axis_action(&"aim_right_x", JOY_AXIS_LEFT_X)
	_remap_axis_action(&"aim_right_y", JOY_AXIS_LEFT_Y)
	assert_vector(node._read_aim_actions()).is_equal(Vector2.ZERO)
	await _send_joy_motion(node, JOY_AXIS_RIGHT_X, -1.0)
	assert_vector(node._read_aim_actions()).is_equal(Vector2.ZERO)

	await _send_joy_motion(node, JOY_AXIS_LEFT_X, 0.8)
	await _send_joy_motion(node, JOY_AXIS_LEFT_Y, -0.6)
	assert_vector(node._read_aim_actions()).is_equal_approx(Vector2(0.8, -0.6), Vector2(0.001, 0.001))
	node._physics_process(0.0)
	assert_vector(node.aim_vector).is_equal_approx(Vector2(0.8, -0.6), Vector2(0.001, 0.001))

func _remap_axis_action(action: StringName, axis: JoyAxis) -> void:
	InputMap.action_erase_events(action)
	for polarity: float in [-1.0, 1.0]:
		var motion := InputEventJoypadMotion.new()
		motion.axis = axis
		motion.axis_value = polarity
		InputMap.action_add_event(action, motion)

func _send_joy_motion(_node: Node, axis: JoyAxis, value: float) -> void:
	var motion := InputEventJoypadMotion.new()
	motion.axis = axis
	motion.axis_value = value
	Input.parse_input_event(motion)
	await get_tree().process_frame

# ---------- VirtualJoystickScript.joystick_output：死区/钳制/归一化 ----------

func test_touch_mode_touch_capable_desktop_stays_desktop_until_setting_enabled() -> void:
	assert_bool(TouchModeScript.enabled(false, false)).is_false()
	# Windows 触摸屏能力只是硬件事实，不是启用虚拟控件/自动瞄准的授权。
	assert_bool(TouchModeScript.enabled(true, false, false)).is_false()
	assert_bool(TouchModeScript.enabled(true, false, true)).is_true()

func test_touch_mode_pure_logic_supports_mobile_and_explicit_override() -> void:
	assert_bool(TouchModeScript.enabled(false, true)).is_true()
	assert_bool(TouchModeScript.enabled(false, false, true)).is_true()
	assert_bool(TouchModeScript.enabled(false, false, false, true)).is_true()
	assert_bool(TouchModeScript.enabled(true, true, true, false)).is_false()

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
	assert_bool(Input.is_action_pressed("touch_move_right")).is_true()
	assert_bool(Input.is_action_pressed("move_right")).is_false()
	node._apply_raw(Vector2.ZERO)
	assert_vector(node.output).is_equal(Vector2.ZERO)
	assert_bool(Input.is_action_pressed("touch_move_right")).is_false()

func test_joystick_aim_presses_fire_beyond_dead_zone() -> void:
	var node: Control = auto_free(VirtualJoystickScript.new())
	node.is_aim = true
	node._apply_raw(Vector2(48, 0))
	assert_vector(node.aim_vector).is_equal_approx(Vector2(1, 0), Vector2(0.001, 0.001))
	assert_bool(Input.is_action_pressed("touch_fire")).is_true()
	assert_bool(Input.is_action_pressed("fire")).is_false()

func test_joystick_aim_releases_fire_on_center() -> void:
	var node: Control = auto_free(VirtualJoystickScript.new())
	node.is_aim = true
	Input.action_press("fire")
	node._apply_raw(Vector2(48, 0))
	node._apply_raw(Vector2(3, 0))   # 死区内
	assert_bool(Input.is_action_pressed("touch_fire")).is_false()
	assert_bool(Input.is_action_pressed("fire")).is_true()

func test_joystick_hidden_on_desktop_unless_forced() -> void:
	var node: Control = auto_free(VirtualJoystickScript.new())
	node._refresh_visibility()
	assert_bool(node.visible).is_false()          # 设置关闭的桌面/无头模式 → 隐藏
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

func test_joystick_mouse_drag_release_uses_same_inputmap_path() -> void:
	var node: Control = auto_free(VirtualJoystickScript.new())
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(100, 100)
	node._gui_input(press)
	var drag := InputEventMouseMotion.new()
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	drag.position = Vector2(148, 100)
	node._gui_input(drag)
	assert_vector(node.output).is_equal_approx(Vector2.RIGHT, Vector2(0.001, 0.001))
	assert_bool(Input.is_action_pressed("touch_move_right")).is_true()
	assert_bool(Input.is_action_pressed("fire")).is_false()
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = drag.position
	node._gui_input(release)
	assert_vector(node.output).is_equal(Vector2.ZERO)
	assert_bool(Input.is_action_pressed("touch_move_right")).is_false()

func test_joystick_public_mouse_capture_tracks_mouse_only() -> void:
	var node: Control = auto_free(VirtualJoystickScript.new())
	var touch := InputEventScreenTouch.new()
	touch.index = 2
	touch.pressed = true
	touch.position = Vector2(20, 20)
	node._gui_input(touch)
	assert_bool(node.captures_mouse_pointer()).is_false()
	touch.pressed = false
	node._gui_input(touch)

	var mouse := InputEventMouseButton.new()
	mouse.device = 0
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	mouse.position = Vector2(20, 20)
	node._gui_input(mouse)
	assert_bool(node.captures_mouse_pointer()).is_true()
	mouse.pressed = false
	node._gui_input(mouse)
	assert_bool(node.captures_mouse_pointer()).is_false()

	var emulated := InputEventMouseButton.new()
	emulated.device = InputEvent.DEVICE_ID_EMULATION
	emulated.button_index = MOUSE_BUTTON_LEFT
	emulated.pressed = true
	node._gui_input(emulated)
	assert_bool(node.captures_mouse_pointer()).is_false()

func test_touch_fire_release_does_not_cancel_held_physical_fire() -> void:
	var node: Control = auto_free(VirtualJoystickScript.new())
	node.is_aim = true
	Input.action_press("fire")
	node._apply_raw(Vector2.RIGHT * 48.0)
	assert_bool(Input.is_action_pressed("touch_fire")).is_true()
	node._apply_raw(Vector2.ZERO)
	assert_bool(Input.is_action_pressed("touch_fire")).is_false()
	assert_bool(Input.is_action_pressed("fire")).is_true()

func test_move_joystick_release_does_not_cancel_keyboard_move() -> void:
	var node: Control = auto_free(VirtualJoystickScript.new())
	Input.action_press("move_right")
	node._apply_raw(Vector2.RIGHT * 48.0)
	node._apply_raw(Vector2.ZERO)
	assert_bool(Input.is_action_pressed("touch_move_right")).is_false()
	assert_bool(Input.is_action_pressed("move_right")).is_true()

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

func test_touch_actions_are_unbound_and_source_isolated() -> void:
	for action in ["touch_move_left", "touch_move_right", "touch_move_up", "touch_move_down",
			"touch_fire", "touch_roll", "touch_switch_weapon", "touch_interact", "touch_skill"]:
		assert_bool(InputMap.has_action(action)).override_failure_message(action).is_true()
		assert_int(InputMap.action_get_events(action).size()).override_failure_message(action).is_zero()
