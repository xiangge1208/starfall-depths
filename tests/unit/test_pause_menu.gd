class_name TestPauseMenu
extends GdUnitTestSuite
## GDD §19 第 10 项收口：局内暂停菜单（ui/pause_menu.gd + hud 挂钩）。
## 钉死：呼出/恢复状态机（`pause` 动作 Esc/Start 事件契约、子层 Esc 逐层返回、幂等）、
## 暂停时世界整树冻结（60Hz 计数探针零推进）/恢复零演出误发（trauma/time_scale 不动）、
## 设置面板往返（打开不退出暂停；改键层经设置层「按 键」可达；面板 270 视口内不溢出）、
## 重开/回主菜单路由调用（重开="game" 层重开键、回主菜单委托 HUD 既有放弃退出路径、
## 路由前已解冻）、呼出门控（三选一/灾厄/商店式 `_ui` 弹层、演出链注入口、过场 _busy、
## 平凡 hitstop 冻结拍先掐权威恢复定时器）、HUD 挂钩（PauseMenu/PauseBtn/防重入共享）。
## 全程不真跳场景（route_override 注入）、不触碰真实存档（无设置值改动、无结算触发）。

const BTN_MIN := Vector2(140, 18)


func after_test() -> void:
	get_tree().paused = false      # 暂停类套件卫生：任何失败路径不把冻结泄漏给后续套件
	Engine.time_scale = 1.0


# ---------------------------------------------------------------- helpers

func _menu() -> PauseMenu:
	var m: PauseMenu = auto_free(PauseMenu.new())
	add_child(m)
	return m


func _esc_event() -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_ESCAPE     # project.godot `pause` 动作的默认键事件
	ev.pressed = true
	return ev


func _start_event() -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.button_index = JOY_BUTTON_START   # 本卡补进 `pause` 动作的手柄绑定
	ev.pressed = true
	return ev


## 60Hz 冻结探针：默认 INHERIT（= pausable），暂停中 _process 不得推进。
class TickProbe extends Node:
	var ticks := 0

	func _process(_delta: float) -> void:
		ticks += 1


## 商店/熔铸/事件卡的 `_ui` 弹层持有惯例替身（PauseMenu 按 duck 读扫描）。
class OverlayHost extends Node:
	var _ui: Control = null


# ---------------------------------------------------------------- 输入契约

func test_pause_action_binds_escape_and_start() -> void:
	assert_bool(InputMap.has_action("pause")).is_true()   # 既有动作；本卡前全库无消费者
	var has_escape := false
	var has_start := false
	for ev: InputEvent in InputMap.action_get_events("pause"):
		var k := ev as InputEventKey
		if k != null and k.physical_keycode == KEY_ESCAPE:
			has_escape = true
		var j := ev as InputEventJoypadButton
		if j != null and j.button_index == JOY_BUTTON_START:
			has_start = true
	assert_bool(has_escape).is_true()
	assert_bool(has_start).is_true()


func test_menu_shell_has_four_items() -> void:
	var m := _menu()
	var rows := m.get_node("Shell/Center/Panel/Rows")
	var texts: Array[String] = []
	for c in rows.get_children():
		if c is Button:
			var b := c as Button
			assert_float(b.custom_minimum_size.x).is_equal(BTN_MIN.x)   # 触屏按钮尺寸惯例
			assert_float(b.custom_minimum_size.y).is_equal(BTN_MIN.y)
			texts.append(b.text)
	assert_array(texts).contains_exactly(["继 续", "设 置", "重 开", "回主菜单"])   # GDD §19 四项


# ---------------------------------------------------------------- 状态机：呼出/恢复/世界冻结

func test_open_freezes_tree_and_resume_unfreezes() -> void:
	var m := _menu()
	var probe := TickProbe.new()
	auto_free(probe)
	add_child(probe)
	await get_tree().process_frame
	var ticks_before := probe.ticks
	assert_bool(m.try_open()).is_true()
	assert_bool(get_tree().paused).is_true()
	assert_bool(m.is_open()).is_true()
	assert_bool(m.visible).is_true()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(probe.ticks).is_equal(ticks_before)   # 世界整树冻结（角标/倒计时等一并停）
	m.resume()
	assert_bool(get_tree().paused).is_false()
	assert_bool(m.visible).is_false()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(probe.ticks).is_greater(ticks_before)   # 恢复后世界照常推进


func test_resume_emits_no_juice_side_effects() -> void:
	var m := _menu()
	var fx := get_node_or_null("/root/Fx")
	var trauma_before := 0.0
	if fx != null:
		trauma_before = float(fx.trauma)
	assert_bool(m.try_open()).is_true()
	assert_float(Engine.time_scale).is_equal_approx(1.0, 0.0001)   # 暂停本身不动时计
	m.resume()
	assert_float(Engine.time_scale).is_equal_approx(1.0, 0.0001)
	if fx != null:
		assert_float(float(fx.trauma)).is_equal_approx(trauma_before, 0.0001)   # 零屏震误发
	assert_bool(get_tree().paused).is_false()


func test_pause_action_event_toggles_state_machine() -> void:
	var m := _menu()
	m._unhandled_input(_esc_event())            # Esc 呼出
	assert_bool(m.is_open()).is_true()
	assert_bool(get_tree().paused).is_true()
	m._unhandled_input(_esc_event())            # 再按恢复（子层未开 → 直接 resume）
	assert_bool(m.is_open()).is_false()
	assert_bool(get_tree().paused).is_false()
	m._unhandled_input(_start_event())          # 手柄 Start 同一动作
	assert_bool(m.is_open()).is_true()
	m._unhandled_input(_esc_event())
	assert_bool(get_tree().paused).is_false()


func test_open_is_idempotent_and_resume_when_closed_is_noop() -> void:
	var m := _menu()
	assert_bool(m.try_open()).is_true()
	assert_bool(m.try_open()).is_false()        # 已开：二次呼出零副作用
	assert_bool(m.is_open()).is_true()
	m.resume()
	m.resume()                                  # 未开：恢复零副作用
	assert_bool(get_tree().paused).is_false()


func test_hitstop_frozen_tree_is_drained_before_menu_pause() -> void:
	# 平凡 hitstop 冻结拍模拟（树已被暂停）：呼出须先掐权威恢复定时器再上自己的暂停，
	# 否则菜单打开期间世界会被解冻复活（Fx.cancel_hitstop 幂等，真实 Fx 走全路径）。
	var m := _menu()
	get_tree().paused = true
	assert_bool(m.try_open()).is_true()
	assert_bool(m.is_open()).is_true()
	assert_bool(get_tree().paused).is_true()    # 菜单持有暂停权（非 hitstop 遗留）
	m.resume()
	assert_bool(get_tree().paused).is_false()
	assert_float(Engine.time_scale).is_equal_approx(1.0, 0.0001)


# ---------------------------------------------------------------- 设置/改键往返

func test_settings_roundtrip_keeps_pause_alive() -> void:
	var m := _menu()
	assert_bool(m.try_open()).is_true()
	var settings_btn := m.get_node("Shell/Center/Panel/Rows/SettingsBtn") as Button
	settings_btn.pressed.emit()
	var settings := m.find_child("SettingsPanelUI", true, false) as Control
	assert_that(settings).is_not_null()
	assert_bool(settings.visible).is_true()
	assert_bool(m.is_open()).is_true()          # 设置层不退出暂停
	assert_bool(get_tree().paused).is_true()
	# 面板（含追加的「按 键」行）整体在 270 视口内不溢出
	await get_tree().process_frame
	await get_tree().process_frame
	var panel := settings.get_node("Center/Panel") as Control
	var vp := settings.get_viewport().get_visible_rect().size
	assert_bool(panel.position.y >= 0.0).is_true()
	assert_bool(panel.position.y + panel.size.y <= vp.y + 0.5).is_true()
	# Esc：设置层 → 回暂停主层（不恢复世界）
	assert_bool(m.handle_pause_key()).is_true()
	assert_bool(settings.visible).is_false()
	assert_bool(m.is_open()).is_true()
	assert_bool(get_tree().paused).is_true()
	# 再 Esc：主层恢复
	assert_bool(m.handle_pause_key()).is_true()
	assert_bool(m.is_open()).is_false()
	assert_bool(get_tree().paused).is_false()


func test_rebind_reachable_from_settings_and_esc_chain_back() -> void:
	var m := _menu()
	assert_bool(m.try_open()).is_true()
	(m.get_node("Shell/Center/Panel/Rows/SettingsBtn") as Button).pressed.emit()
	var settings := m.find_child("SettingsPanelUI", true, false) as Control
	var shortcut := settings.find_child("RebindShortcut", true, false) as Button
	assert_that(shortcut).is_not_null()
	assert_bool(shortcut.visible).is_true()     # 「按 键」钮随设置层显隐（visibility_changed 同步）
	shortcut.pressed.emit()
	var rebind := m.find_child("RebindPanelUI", true, false) as Control
	assert_that(rebind).is_not_null()
	assert_bool(rebind.visible).is_true()       # 改键层自设置层可达
	# Esc：改键层 → 回设置层 → 回暂停主层 → 恢复（逐层返回，不一步退出）
	assert_bool(m.handle_pause_key()).is_true()
	assert_bool(rebind.visible).is_false()
	assert_bool(settings.visible).is_true()
	assert_bool(m.handle_pause_key()).is_true()
	assert_bool(settings.visible).is_false()
	assert_bool(m.is_open()).is_true()
	assert_bool(m.handle_pause_key()).is_true()
	assert_bool(get_tree().paused).is_false()


func test_resume_resets_sublayers_for_next_open() -> void:
	var m := _menu()
	assert_bool(m.try_open()).is_true()
	(m.get_node("Shell/Center/Panel/Rows/SettingsBtn") as Button).pressed.emit()
	var settings := m.find_child("SettingsPanelUI", true, false) as Control
	assert_bool(settings.visible).is_true()
	m.resume()
	assert_bool(settings.visible).is_false()    # 子层复位：下次呼出回主层（非设置层）
	assert_bool(m.try_open()).is_true()
	assert_bool(settings.visible).is_false()
	m.resume()


# ---------------------------------------------------------------- 路由：重开 / 回主菜单

func test_restart_routes_game_after_unpause() -> void:
	var m := _menu()
	var routed: Array = []
	var paused_at_route: Array = []
	m.route_override = func(key: String) -> void:
		routed.append(key)
		paused_at_route.append(get_tree().paused)
	assert_bool(m.try_open()).is_true()
	(m.get_node("Shell/Center/Panel/Rows/RestartBtn") as Button).pressed.emit()
	assert_array(routed).contains_exactly(["game"])   # 重开 = "game" 键重载 run_root（层重开）
	assert_array(paused_at_route).contains_exactly([false])   # 路由前已解冻（过场 tween 不被冻死）
	assert_bool(get_tree().paused).is_false()
	assert_bool(m.is_open()).is_false()


func test_quit_delegates_hud_settlement_path() -> void:
	var m := _menu()
	var calls: Array = []
	var routed: Array = []
	m.quit_action = func() -> void: calls.append("quit")
	m.route_override = func(key: String) -> void: routed.append(key)
	assert_bool(m.try_open()).is_true()
	(m.get_node("Shell/Center/Panel/Rows/QuitBtn") as Button).pressed.emit()
	assert_array(calls).contains_exactly(["quit"])   # 委托 HUD 既有放弃退出路径（结算+落盘+回菜单）
	assert_array(routed).is_empty()                  # 委托生效时不直走路由（不重复触发）
	assert_bool(get_tree().paused).is_false()        # 结算路径执行前已恢复世界


func test_quit_without_host_falls_back_to_menu_route() -> void:
	var m := _menu()
	var routed: Array = []
	m.route_override = func(key: String) -> void: routed.append(key)
	assert_bool(m.try_open()).is_true()
	(m.get_node("Shell/Center/Panel/Rows/QuitBtn") as Button).pressed.emit()
	assert_array(routed).contains_exactly(["menu"])   # 无宿主 HUD（独立使用）兜底直走


# ---------------------------------------------------------------- 呼出门控（不误触发）

func test_open_blocked_while_buff_pick_visible() -> void:
	var m := _menu()
	var bp: Control = auto_free(load("res://ui/buff_pick.tscn").instantiate())
	add_child(bp)                               # 生产挂局场景内；gdUnit 无 current_scene，
	(bp as BuffPick).open(["vigor"])            # 扫描回退树根（同一扫描器路径）
	assert_bool(m.try_open()).is_false()        # Esc 不得在弹层上误开暂停
	assert_bool(get_tree().paused).is_false()
	bp.hide()
	assert_bool(m.try_open()).is_true()         # 弹层关闭后照常呼出
	m.resume()


func test_open_blocked_while_calamity_visible() -> void:
	var m := _menu()
	var cp := CalamityPanel.new()
	auto_free(cp)
	add_child(cp)
	cp.open()
	assert_bool(m.try_open()).is_false()
	assert_bool(get_tree().paused).is_false()
	cp.hide()
	assert_bool(m.try_open()).is_true()
	m.resume()


func test_open_blocked_while_shop_style_ui_overlay_visible() -> void:
	var m := _menu()
	var host := OverlayHost.new()
	auto_free(host)
	add_child(host)
	var ui := Control.new()
	auto_free(ui)
	host.add_child(ui)                          # 生产：`_ui` 是宿主实体的子节点（在树内）
	host._ui = ui
	ui.visible = true                           # 商店/熔铸/事件卡 `_ui` 惯例（弹层开着）
	assert_bool(m.try_open()).is_false()
	ui.visible = false
	assert_bool(m.try_open()).is_true()
	m.resume()


func test_open_blocked_when_presentation_override_active() -> void:
	var m := _menu()
	m.presentation_blocked_override = func() -> bool: return true
	assert_bool(m.try_open()).is_false()        # Boss 死亡/玩家死亡演出链中呼出被忽略
	assert_bool(get_tree().paused).is_false()
	m.presentation_blocked_override = func() -> bool: return false
	assert_bool(m.try_open()).is_true()         # 链空闲（默认探测全 false）照常呼出
	m.resume()


func test_open_blocked_while_router_busy() -> void:
	var m := _menu()
	var router := get_node_or_null("/root/SceneRouter")
	if router == null:
		return                                  # 无路由器环境：门控天然放行（不崩）
	router.set("_busy", true)
	assert_bool(m.try_open()).is_false()        # 0.2s 过场中不叠加暂停（tween 挂路由器上）
	router.set("_busy", false)
	assert_bool(m.try_open()).is_true()
	m.resume()


# ---------------------------------------------------------------- HUD 挂钩

func test_hud_hooks_pause_menu_with_quit_delegate_and_button() -> void:
	var hud: CanvasLayer = auto_free(HUD.new())
	add_child(hud)
	var pm := hud.find_child("PauseMenu", true, false) as PauseMenu
	assert_that(pm).is_not_null()               # HUD._ready 挂菜单壳
	assert_bool(pm.quit_action.is_valid()).is_true()   # 回主菜单委托既有放弃退出路径
	assert_int(pm.layer).is_greater(hud.layer)  # 遮罩盖住 HUD（置灰口径）
	var dim := pm.get_node("Shell/Dim") as ColorRect
	assert_int(dim.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)   # 暂停中挡底层点击
	var pause_btn := hud.find_child("PauseBtn", true, false) as Button
	assert_that(pause_btn).is_not_null()        # 触屏呼出钮
	pause_btn.pressed.emit()
	assert_bool(pm.is_open()).is_true()
	assert_bool(get_tree().paused).is_true()
	pm.handle_pause_key()
	assert_bool(get_tree().paused).is_false()
	# 弃钮保留不回退（试炼规格 §4）：普通局隐藏，仅试炼局显示（既有口径）
	var abandon := hud.find_child("AbandonTrial", true, false) as Button
	assert_that(abandon).is_not_null()
	assert_bool(abandon.visible).is_false()
