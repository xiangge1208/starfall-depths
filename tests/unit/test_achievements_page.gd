class_name TestAchievementsPage
extends GdUnitTestSuite
## m4p-u1 成就展示页（ui/achievements.tscn）+ 路由 + 主菜单入口契约测试。
## 1) 24 条成就逐卡渲染（defs 表序），顶部汇总「已解锁 n / 24」；
## 2) 已解锁（金亮 ✓ + 真名）/ 未解锁（灰 + 锁标）渲染区分 + 奖励蓝晶逐卡可见；
## 3) 进度口径：state_threshold 持久源显示 cur/goal（save: 源注入确定值），无持久进度的
##    判定类型（event_once/event_count/composite）显示「??？」；详情区条件中文合成；
## 4) SceneRouter "achievements" 路由键 → 场景真实跳转（headless 经真实 autoload）；
## 5) 主菜单「成 就」钮点亮 + 点击路由到成就页。
## AchievementSystem 直构注入（temp path SaveSystem，同 test_achievements 模式），
## 不触碰真实 user:// 档；不入树 → 不连 EventBus，测试间零串扰。

const AS_PATH := "res://core/meta/achievement_system.gd"
const ROUTER_SCRIPT := "res://autoload/scene_router.gd"
const PAGE_SCENE := "res://ui/achievements.tscn"
const MENU_SCENE := "res://ui/main_menu.tscn"

var _save_paths: Array[String] = []


func after_test() -> void:
	for path in _save_paths:
		DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(path + ".tmp")
	_save_paths.clear()
	# 主菜单入树会经 AudioMgr.play_music("menu") 在共享 autoload 上起 BGM；测试收口
	# 停掉，避免真实音频流给后续计时敏感套件（test_audio_music 淡入 tween）加负载。
	if AudioMgr.has_method("stop_music"):
		AudioMgr.stop_music()
	if get_tree().current_scene != null:
		get_tree().unload_current_scene()


# ---- 夹具 ----

func _tmp_path(tag: String) -> String:
	var path := "user://test_achv_page_%s_%d.json" % [tag, absi(randi())]
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".tmp")
	_save_paths.append(path)
	return path


func _fresh_save(tag: String) -> Variant:
	var s: Variant = auto_free(load("res://autoload/save_system.gd").new())
	s.save_path = _tmp_path(tag)
	s.load_save()
	return s


## 全新成就页（AchievementSystem 直构 + temp path save 注入；不入树）。
func _page(tag: String) -> Control:
	var page: Control = auto_free(load(PAGE_SCENE).instantiate())
	page.ach_system = auto_free(load(AS_PATH).new(_fresh_save(tag)))
	add_child(page)   # 入树 → _ready 兜底不覆盖注入缝 → _rebuild 渲染
	return page


# ---------------------------------------------------------------- 渲染

func test_page_builds_all_24_cards_summary_zero() -> void:
	var page := _page("build")
	assert_int(page.cell_count()).is_equal(24)
	assert_str(page.summary_text()).is_equal("已解锁 0 / 24")
	# 缺省全部未解锁：金/灰口径 fail-closed（ach_system 注入在，未解锁集为空）
	assert_bool(page.cell_info("first_lamp")["unlocked"]).is_false()
	assert_str(page.detail_text()).is_equal("点击成就查看详情")


func test_unlocked_vs_locked_rendering_and_gems() -> void:
	var page := _page("render")
	var sys: Node = page.ach_system
	# 解锁 2 条（直接走 SaveSystem 幂等入档口径——页面只读展示）
	sys.save_system.unlock_achievement("first_lamp")
	sys.save_system.unlock_achievement("trier")
	page.open()   # 重开刷新（路由页重入口径）
	var lamp: Dictionary = page.cell_info("first_lamp")
	assert_bool(lamp["unlocked"]).is_true()
	assert_str(lamp["name_text"]).is_equal("✓ 初次点灯")
	assert_str(lamp["status_text"]).is_equal("已解锁")
	assert_str(lamp["gems_text"]).is_equal("+100 蓝晶")
	var watcher: Dictionary = page.cell_info("night_watcher")
	assert_bool(watcher["unlocked"]).is_false()
	assert_str(watcher["name_text"]).is_equal("锁 守夜人")
	assert_str(watcher["gems_text"]).is_equal("+300 蓝晶")
	assert_str(page.summary_text()).is_equal("已解锁 2 / 24")


func test_progress_state_threshold_cur_goal_vs_unknown() -> void:
	var page := _page("progress")
	var sys: Node = page.ach_system
	# save: 源（codex_seen）注入确定值 3 → collector（goal 50）显示 3/50
	sys.save_system.data["codex_seen"] = ["laohuoji", "tiejian", "shoulei"]
	page.open()
	assert_str(page.cell_info("collector")["status_text"]).is_equal("3/50")
	# state_threshold 其余源：显示 cur/goal 口径（不落 ??？）；goal 数字来自 defs
	var smith: String = page.cell_info("forge_smith")["status_text"]
	assert_bool(smith.contains("/10")).is_true()
	assert_bool(smith.contains("??？")).is_false()
	# 无持久进度的判定类型 → 「??？」占位
	assert_str(page.cell_info("first_lamp")["status_text"]).is_equal("??？")        # event_once
	assert_str(page.cell_info("element_scholar")["status_text"]).is_equal("??？")   # event_count
	assert_str(page.cell_info("bare_hands")["status_text"]).is_equal("??？")        # composite


func test_detail_area_condition_synthesis() -> void:
	var page := _page("detail")
	# state_threshold：源中文 + goal + 当前进度
	page._show_detail("collector")
	assert_str(page.detail_text()) \
		.contains("藏品家 · 图鉴见录武器达 50（当前 0/50） · +150 蓝晶")
	# event_once：触发中文 + 层号谓词后缀
	page._show_detail("first_lamp")
	assert_str(page.detail_text()).contains("初次点灯 · 击败 Boss（第 1 层） · +100 蓝晶")
	# event_count：累计口径
	page._show_detail("element_scholar")
	assert_str(page.detail_text()).contains("元素学者 · 引发共鸣 累计 30 次 · +150 蓝晶")
	# composite：条件与合成（赤手空拳 = 通过楼层：本层远程开火为 0 且 近战挥击≥1，
	# cond 序与 defs bare_hands.conds 表序一致；bare_hands 无 floor_idx pred → 无层号后缀）
	page._show_detail("bare_hands")
	assert_str(page.detail_text()) \
		.contains("赤手空拳 · 通过楼层：本层远程开火为 0 且 近战挥击≥1 · +200 蓝晶")
	# 未知 id 回落缺省占位，不崩
	page._show_detail("__nope__")
	assert_str(page.detail_text()).is_equal("点击成就查看详情")


# ---------------------------------------------------------------- 路由

func test_route_key_registered_and_scene_on_disk() -> void:
	var script: GDScript = load(ROUTER_SCRIPT)
	var routes: Dictionary = script.get_script_constant_map()["ROUTES"]
	assert_bool(routes.has("achievements")).is_true()
	assert_str(String(routes["achievements"])).is_equal(PAGE_SCENE)
	assert_bool(ResourceLoader.exists(PAGE_SCENE, "PackedScene")).is_true()
	var root: Node = auto_free((load(PAGE_SCENE) as PackedScene).instantiate())
	assert_str(root.name).is_equal("Achievements")


func test_goto_achievements_routes_via_real_autoload() -> void:
	var router: Node = get_tree().root.get_node_or_null("SceneRouter")
	assert_object(router).is_not_null()
	router.goto("achievements")
	await _await_settled(router, "Achievements")
	assert_str(get_tree().current_scene.name).is_equal("Achievements")


# ---------------------------------------------------------------- 主菜单入口

func test_menu_achievements_button_live_and_routes() -> void:
	var menu: Control = auto_free(load(MENU_SCENE).instantiate())
	# 临时路径 save 注入（同 test_menu_settings_roundtrip 口径）：菜单 _ready 的
	# apply_audio_settings 会把 legacy int 音量键（默认 80）换算成 float 写回 settings
	# （music/sfx_volume=0.8）。写路径有两段：面板读 menu.save_system，AudioMgr.
	# set_music_volume 的持久化宿主是 AudioMgr.settings_host —— 两缝都注入临时档，
	# 否则共享真实 SaveSystem 内存档被污染，紧随其后的计时敏感套件
	# （test_audio_music 期望默认 music_volume=1 → 0 dB 淡入终点）确定性误报。
	menu.save_system = _fresh_save("menu")
	AudioMgr.settings_host = menu.save_system
	add_child(menu)   # 入树 → _ready 点亮（写点全部落在临时档上）
	AudioMgr.settings_host = null   # _ready 同步写点已过，立即还原共享 autoload
	var btn: Button = menu.get_node("Menu/AchievementsBtn")
	assert_bool(btn.disabled).is_false()
	assert_str(btn.text).is_equal("成 就")
	assert_bool(btn.pressed.is_connected(menu._on_achievements_pressed)).is_true()
	# 点击 → 真实路由到成就页（与 goto 测试同一过场收口口径）
	btn.pressed.emit()
	var router: Node = get_tree().root.get_node_or_null("SceneRouter")
	await _await_settled(router, "Achievements")
	assert_str(get_tree().current_scene.name).is_equal("Achievements")


# ---------------------------------------------------------------- helpers

## 等待 goto 整段过场收场：current_scene 就位为目标 且 路由器 busy 复位（淡出完成）
func _await_settled(router: Node, scene_name: String, max_frames: int = 240) -> void:
	for _i in max_frames:
		var cs: Node = get_tree().current_scene
		if cs != null and cs.name == StringName(scene_name) and not bool(router.get("_busy")):
			return
		await get_tree().process_frame
