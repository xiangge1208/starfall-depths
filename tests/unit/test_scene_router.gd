class_name TestSceneRouter
extends GdUnitTestSuite
## m1-t23 场景路由 + 主菜单契约测试。
## 1) 路由表 ROUTES 完整：menu/hero_select/game/death/victory 五键（m2-t18 +victory），
##    值均为 res://*.tscn 且全部在盘。
## 2) goto 真切换：headless 下经真实 autoload 路由，current_scene 逐键变正确；
##    未知键 / 目标缺失 fail-loud（push_error）且不动当前场景、不建过场层。
## 3) 主菜单：占位钮全部点亮（m4p-u1 起成就钮亦为正式入口）、设置内联面板经
##    SaveSystem（临时路径注入）即时落盘 roundtrip、按键接线齐全。
## 4) 选角路由守卫：节点不在树内 → /root/SceneRouter（与 /root/RunState 同理）探测为
##    null → 只发信号 + 静态暂存，不崩（T11 时代兜底路径仍活着）。

const ROUTER_SCRIPT := "res://autoload/scene_router.gd"
const MENU_SCENE := "res://ui/main_menu.tscn"
const HERO_SELECT_SCENE := "res://ui/hero_select.tscn"
const DEATH_SCENE := "res://ui/death_summary.tscn"
const VICTORY_SCENE := "res://ui/victory_summary.tscn"   # m2-t18
const TALENTS_SCENE := "res://ui/talents.tscn"           # m2-t35：天赋页路由（T15 场景在盘）
const ACHIEVEMENTS_SCENE := "res://ui/achievements.tscn" # m4p-u1：成就页路由（场景在盘）

## 测试期间经由真实 autoload 切换的场景，after_test 卸载还原（root 无残留 current_scene）
func after_test() -> void:
	if get_tree().current_scene != null:
		get_tree().unload_current_scene()


# ---------------------------------------------------------------- 路由表

func test_project_default_main_scene_is_main_menu() -> void:
	# Task 23 的默认启动入口属于项目契约，不等同于路由表中的 menu 键。
	# 两者分别锁定，避免调试用 training_room 再次成为发布入口而测试仍然全绿。
	var configured_scene := String(ProjectSettings.get_setting("application/run/main_scene", ""))
	assert_str(configured_scene).is_equal(MENU_SCENE)
	assert_bool(ResourceLoader.exists(configured_scene, "PackedScene")).is_true()
	var packed := load(configured_scene) as PackedScene
	assert_object(packed).is_not_null()
	var root: Node = auto_free(packed.instantiate())
	assert_str(root.name).is_equal("MainMenu")


func test_routes_table_complete() -> void:
	var script: GDScript = load(ROUTER_SCRIPT)
	assert_object(script).is_not_null()
	var routes: Dictionary = script.get_script_constant_map()["ROUTES"]
	# m2-t20：+codex（图鉴页）；m2-t18：+victory（胜利结算）；m2-t35：+talents（天赋页）；
	# m4p-u1：+achievements（成就页）→ 八键
	assert_int(routes.size()).is_equal(8)
	for key in ["menu", "hero_select", "game", "death", "codex", "victory", "talents",
			"achievements"]:
		assert_bool(routes.has(key)).is_true()
		var path := String(routes[key])
		assert_bool(path.begins_with("res://")).is_true()
		assert_bool(path.ends_with(".tscn")).is_true()
	# GDD §19 流程键位钉死（改表须同步本断言）。m1-t27：game → 局根节点（真实主循环），
	# training_room 为 M0 时代占位（仍在盘，作为独立调试场景保留）。
	# m2-t20：codex → 图鉴页（ui/codex.tscn，主菜单入口）。
	# m2-t18：victory → 第 3 层 Boss 通关结算面板（RunRoot 经 InterFloorFlow.victory_achieved 切入）。
	# m2-t35：talents → 天赋页（ui/talents.tscn，主菜单入口点亮）。
	# m4p-u1：achievements → 成就页（ui/achievements.tscn，主菜单入口点亮）。
	assert_str(String(routes["menu"])).is_equal(MENU_SCENE)
	assert_str(String(routes["hero_select"])).is_equal(HERO_SELECT_SCENE)
	assert_str(String(routes["game"])).is_equal("res://core/rooms/run_root.tscn")
	assert_str(String(routes["death"])).is_equal(DEATH_SCENE)
	assert_str(String(routes["codex"])).is_equal("res://ui/codex.tscn")
	assert_str(String(routes["victory"])).is_equal(VICTORY_SCENE)
	assert_str(String(routes["talents"])).is_equal(TALENTS_SCENE)
	assert_str(String(routes["achievements"])).is_equal(ACHIEVEMENTS_SCENE)


func test_route_paths_exist_on_disk_except_death() -> void:
	# T22 已交付 death_summary.tscn、m2-t18 已交付 victory_summary.tscn → 五路径全部在盘
	# （原"缺失"断言按计划翻转）。
	assert_bool(ResourceLoader.exists(DEATH_SCENE)).is_true()
	assert_bool(ResourceLoader.exists(VICTORY_SCENE)).is_true()
	assert_bool(ResourceLoader.exists(MENU_SCENE)).is_true()
	assert_bool(ResourceLoader.exists(HERO_SELECT_SCENE)).is_true()
	assert_bool(ResourceLoader.exists("res://core/rooms/run_root.tscn")).is_true()
	assert_bool(ResourceLoader.exists("res://core/rooms/training_room.tscn")).is_true()


# ---------------------------------------------------------------- goto 行为

func _fresh_router_in_tree() -> Node:
	var router: Node = auto_free(load(ROUTER_SCRIPT).new())
	add_child(router)
	return router


func test_goto_unknown_key_fails_loud_no_scene_change() -> void:
	var router := _fresh_router_in_tree()
	var before: Node = get_tree().current_scene
	await assert_error(func() -> void: router.goto("__nope__")) \
		.is_push_error("SceneRouter: unknown route key '__nope__'")
	# 未建过场层、未动当前场景
	assert_int(router.get_child_count()).is_equal(0)
	assert_bool(get_tree().current_scene == before).is_true()


func test_goto_unknown_route_fails_loud_no_scene_change() -> void:
	# T22 已交付 death 场景（原"death 缺失 fail-loud"前提过时）；
	# fail-loud 契约改由未知键路径覆盖：必须 push_error，绝不静默半切
	var router := _fresh_router_in_tree()
	var before: Node = get_tree().current_scene
	await assert_error(func() -> void: router.goto("no_such_route")) \
		.is_push_error("SceneRouter: unknown route key 'no_such_route'")
	assert_int(router.get_child_count()).is_equal(0)
	assert_bool(get_tree().current_scene == before).is_true()


func test_goto_death_scene_routes_after_t22() -> void:
	# T22 交付 death_summary.tscn 后，"death" 键应真实可达（T23 期间不可达）
	var router: Node = get_tree().root.get_node_or_null("SceneRouter")
	assert_object(router).is_not_null()
	router.goto("death")
	await _await_settled(router, "DeathSummary")
	assert_str(get_tree().current_scene.name).is_equal("DeathSummary")


func test_goto_changes_current_scene_headless() -> void:
	# 经真实 autoload：菜单 → 选角 两跳，current_scene 逐跳正确（0.2s 淡入 → 切换 → 淡出）。
	# 断言只在整段过场收场后（场景就位 + busy 复位）读取——切换中帧的节点态不稳定。
	var router: Node = get_tree().root.get_node_or_null("SceneRouter")
	assert_object(router).is_not_null()
	router.goto("hero_select")
	await _await_settled(router, "HeroSelect")
	assert_str(get_tree().current_scene.name).is_equal("HeroSelect")
	# 第二跳回主菜单（表内另一真实键，验证连续切换链）
	router.goto("menu")
	await _await_settled(router, "MainMenu")
	assert_str(get_tree().current_scene.name).is_equal("MainMenu")


## 等待 goto 整段过场收场：current_scene 就位为目标 且 路由器 busy 复位（淡出完成）
func _await_settled(router: Node, scene_name: String, max_frames: int = 240) -> void:
	for _i in max_frames:
		var cs: Node = get_tree().current_scene
		if cs != null and cs.name == StringName(scene_name) and not bool(router.get("_busy")):
			return
		await get_tree().process_frame


# ---------------------------------------------------------------- 主菜单

func test_menu_structure_and_button_wiring() -> void:
	var menu: Control = auto_free(load(MENU_SCENE).instantiate())
	add_child(menu)                          # 入树 → _ready 接线（save_system 走真实 autoload 只读）
	# 中文标题
	assert_str((menu.get_node("Title") as Label).text).is_equal("星陨地牢")
	# M2 占位钮灰置；流程钮可用（m2-t20：图鉴钮点亮；m2-t35：天赋钮点亮为正式入口；
	# m4p-u1：成就钮点亮为正式入口——24 条判定引擎在盘，展示页落库）
	assert_bool((menu.get_node("Menu/CodexBtn") as Button).disabled).is_false()
	assert_bool((menu.get_node("Menu/TalentsBtn") as Button).disabled).is_false()
	assert_bool((menu.get_node("Menu/AchievementsBtn") as Button).disabled).is_false()
	assert_str((menu.get_node("Menu/AchievementsBtn") as Button).text).is_equal("成 就")
	assert_bool((menu.get_node("Menu/StartBtn") as Button).disabled).is_false()
	assert_bool((menu.get_node("Menu/SettingsBtn") as Button).disabled).is_false()
	assert_bool((menu.get_node("Menu/QuitBtn") as Button).disabled).is_false()
	# 按键接线（不实际按压：start/codex/talents 会切场景、quit 会退出进程）
	assert_bool((menu.get_node("Menu/StartBtn") as Button).pressed.is_connected(menu._on_start_pressed)).is_true()
	assert_bool((menu.get_node("Menu/CodexBtn") as Button).pressed.is_connected(menu._on_codex_pressed)).is_true()
	assert_bool((menu.get_node("Menu/TalentsBtn") as Button).pressed.is_connected(menu._on_talents_pressed)).is_true()
	assert_bool((menu.get_node("Menu/AchievementsBtn") as Button).pressed.is_connected(menu._on_achievements_pressed)).is_true()
	assert_bool((menu.get_node("Menu/SettingsBtn") as Button).pressed.is_connected(menu._on_settings_pressed)).is_true()
	assert_bool((menu.get_node("Menu/QuitBtn") as Button).pressed.is_connected(menu._on_quit_pressed)).is_true()
	# 设置内联面板默认收起（m3-sa 起退役：设置键改开独立 SettingsPanelUI，旧面板强制
	# 隐藏、不再开合——原「设置键切换内联面板」断言随挂钩裁定最小适配）
	var panel: Control = menu.get_node("SettingsPanel")
	var settings_ui: Control = menu.get_node("SettingsPanelUI")
	assert_bool(panel.visible).is_false()
	assert_bool(settings_ui.visible).is_false()
	menu._on_settings_pressed()
	assert_bool(panel.visible).is_false()
	assert_bool(settings_ui.visible).is_true()
	menu._on_settings_pressed()
	assert_bool(panel.visible).is_false()
	assert_bool(settings_ui.visible).is_false()


func test_menu_settings_roundtrip_via_save_system() -> void:
	# 临时路径注入（同 test_save 模式）：不触碰真实 user://save.json
	var path := "user://test_scene_router_settings_%d.json" % absi(randi())
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".tmp")
	var fresh: Variant = auto_free(load("res://autoload/save_system.gd").new())
	fresh.save_path = path
	fresh.load_save()
	var menu: Control = auto_free(load(MENU_SCENE).instantiate())
	menu.save_system = fresh                 # _ready 前注入 → 控件初值从该档读
	add_child(menu)
	# 控件初值 = 默认档（m3-jb：J2 晕动防线 screen_shake 默认档 50%）
	assert_float((menu.get_node("SettingsPanel/Rows/ScreenShakeSlider") as HSlider).value) \
		.is_equal_approx(0.5, 0.0001)
	assert_bool((menu.get_node("SettingsPanel/Rows/DamageNumbersToggle") as CheckButton).button_pressed).is_true()
	assert_bool((menu.get_node("SettingsPanel/Rows/ColorblindToggle") as CheckButton).button_pressed).is_false()
	assert_bool((menu.get_node("SettingsPanel/Rows/AutoAimToggle") as CheckButton).button_pressed).is_true()
	assert_bool((menu.get_node("SettingsPanel/Rows/TouchControlsToggle") as CheckButton).button_pressed).is_false()
	# 驱动控件 → 经 set_setting 即时落盘
	var slider: HSlider = menu.get_node("SettingsPanel/Rows/ScreenShakeSlider")
	slider.value = 0.4
	slider.value_changed.emit(slider.value)
	var dn: CheckButton = menu.get_node("SettingsPanel/Rows/DamageNumbersToggle")
	dn.button_pressed = false
	var cb: CheckButton = menu.get_node("SettingsPanel/Rows/ColorblindToggle")
	cb.button_pressed = true
	var aa: CheckButton = menu.get_node("SettingsPanel/Rows/AutoAimToggle")
	aa.button_pressed = false
	var touch: CheckButton = menu.get_node("SettingsPanel/Rows/TouchControlsToggle")
	touch.button_pressed = true
	# 全新实例重读盘 → 五键 roundtrip 一致
	var reloaded: Variant = auto_free(load("res://autoload/save_system.gd").new())
	reloaded.save_path = path
	reloaded.load_save()
	assert_float(reloaded.get_setting("screen_shake", 9.9)).is_equal_approx(0.4, 0.0001)
	assert_bool(reloaded.get_setting("damage_numbers", true)).is_false()
	assert_bool(reloaded.get_setting("colorblind_shapes", false)).is_true()
	assert_bool(reloaded.get_setting("auto_aim", true)).is_false()
	assert_bool(reloaded.get_setting("touch_controls", false)).is_true()
	_wipe(path)


# ---------------------------------------------------------------- 全屏切换（m4p-ui4）

func test_fullscreen_action_registered_and_setting_defaults_false() -> void:
	# 整数缩放（scale_mode=integer）下「最大化」只能取 3×（1920x1000 客户区容不下
	# 4× 的 1080 高），真全屏 1920x1080 才恰好 4× 铺满——故必须有真全屏入口。
	# 本测钉死：InputMap 动作已注册（F11，随 project.godot 入库、新进程可用）+
	# 设置键默认窗口化（旧档缺失回落 false，行为与此前一致）。
	assert_bool(InputMap.has_action("fullscreen")).override_failure_message(
		"fullscreen 动作必须在 project.godot 落盘（运行期 add_action 不写设置项）"
	).is_true()
	var f11_found := false
	for ev: InputEvent in InputMap.action_get_events("fullscreen"):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_F11:
			f11_found = true
	assert_bool(f11_found).is_true()
	assert_bool(SaveSystem.DEFAULT_SETTINGS["fullscreen"]).is_false()

func test_fullscreen_toggle_persists_setting() -> void:
	# toggle_fullscreen 落盘到设置键（跨局记忆）。headless 无真实窗口模式切换，
	# 故只断言「设置键往返」这一可测半边；窗口模式调用本身由 DisplayServer 承接
	# （无头下为 no-op，不崩即符合 fail-soft 口径）。
	var path := "user://test_fs_%d.json" % randi()
	var ss: Variant = auto_free(load("res://autoload/save_system.gd").new())
	ss.save_path = path
	ss.load_save()
	ss.set_setting("fullscreen", true)
	var reloaded: Variant = auto_free(load("res://autoload/save_system.gd").new())
	reloaded.save_path = path
	reloaded.load_save()
	assert_bool(reloaded.get_setting("fullscreen", false)).is_true()
	_wipe(path)


# ---------------------------------------------------------------- 选角路由守卫

func test_hero_select_choose_router_absent_no_crash() -> void:
	# 树外实例：/root/SceneRouter（与 /root/RunState 同理）探测为 null →
	# _choose 只发信号 + 静态暂存，无路由调用、不崩（守卫兜底路径）
	HeroSelect.last_chosen = ""
	var hs: Control = auto_free(load(HERO_SELECT_SCENE).instantiate())
	hs._ready()                              # 树外手动构建卡（_ready 不会自动跑）
	var chosen: Array = []
	hs.hero_chosen.connect(func(id: String) -> void: chosen.append(id))
	var first_id := String(GameDB.heroes.keys()[0])
	hs._choose(0)
	assert_array(chosen).contains_exactly([first_id])
	assert_str(HeroSelect.last_chosen).is_equal(first_id)
	HeroSelect.last_chosen = ""              # 静态状态复位（跨套件卫生）


# ---------------------------------------------------------------- helpers

func _await_until(check: Callable, max_frames: int = 240) -> void:
	for _i in max_frames:
		if check.call():
			return
		await get_tree().process_frame


func _wipe(path: String) -> void:
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".tmp")
