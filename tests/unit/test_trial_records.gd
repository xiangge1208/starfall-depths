class_name TestTrialRecords
extends GdUnitTestSuite
## M3-R-B 试炼流程 UI + 本地排行榜（试炼规格 §5/§6）：
## - trial_records 服务：追加/落盘往返/30 条截断/daily_best 归并（深优先·次短用时）/
##   分日分桶/fail-soft（损坏重建空表不崩）/字段从宽默认；
## - 因子展示装配：factors id → 名称/文案/图标路径三元组（面板因子卡与 HUD 角标共用）；
## - RunState 最小增量：arm_trial → select_hero → start_trial_run 转让链
##   （pending 消费即清）+ trial_factors 随 start_run 复位；
## - 试炼面板：open 刷新（日期/因子卡 ×2/今日最佳/历史 10 条）+ 开始 = arm+路由
##   （spy router 守卫）+ 返回只隐藏；
## - main_menu 试炼按钮挂钩冒烟（运行时构建、点击开面板）；
## - HUD 因子角标 / 死亡·胜利结算徽标：is_trial_run 翻转显隐。
## 排行榜用例走临时 user:// 路径注入（同 test_save.gd 惯例，禁写真档）；
## RunState 污染守卫：after_test 复位普通局 + 清 pending_trial_date（跨套件卫生）。

const PANEL_SCENE := "res://ui/trial_panel.tscn"
const MENU_SCENE := "res://ui/main_menu.tscn"
const DATE := "2026-09-01"

## SceneRouter 替身：只记录 goto 目标（面板「开始」路由守卫测试用）。
class SpyRouter extends Node:
	var calls: Array[String] = []

	func goto(scene: String) -> void:
		calls.append(scene)


# ---------------------------------------------------------------- helpers

func _tmp_path(tag: String) -> String:
	# 随机后缀：即便上次运行残留文件也不会污染本用例
	return "user://test_trial_records_%s_%d.json" % [tag, absi(randi())]


func _wipe(path: String) -> void:
	DirAccess.remove_absolute(path)


func _write_json(path: String, content: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(content)
	f = null


func _fresh(path: String) -> TrialRecords:
	var r: TrialRecords = auto_free(TrialRecords.new())
	r.records_path = path
	return r


func _rec(date, floor_i: int, time_s: int, hero := "vanguard",
		gems := 100, victory := false,
		factors: Array = ["enemy_haste", "elite_surge"]) -> Dictionary:
	# 规格 §5 示例同形记录（date 故意不标注型：坏类型用例可构造；factors 入参从宽，
	# 服务侧归一 Array[String]）
	return {"date": date, "hero_id": hero, "deepest_floor": floor_i,
		"clear_time_s": time_s, "gems_earned": gems, "victory": victory,
		"factors": factors}


func _today() -> String:
	return TrialSystem.new().today_date()


func before_test() -> void:
	RunState.start_run("vanguard")   # 试炼局改写全局种子/楼层 → 复位（跨套件卫生）


func after_test() -> void:
	RunState.pending_trial_date = ""   # 清转让（防泄漏到其他套件的 select_hero）
	RunState.start_run("vanguard")
	DeathRecorder.reset()


# ================================================================ 1) 记录追加 + 落盘往返

func test_missing_file_loads_empty_table() -> void:
	var r := _fresh(_tmp_path("missing"))
	var table := r.load_records()
	assert_int(int(table["version"])).is_equal(1)
	assert_array(table["records"]).is_empty()
	assert_dict(table["daily_best"]).is_empty()


func test_append_roundtrip_through_disk() -> void:
	var path := _tmp_path("roundtrip")
	var r := _fresh(path)
	assert_bool(r.append_record(_rec("2026-08-30", 2, 1043, "vanguard", 180, false))).is_true()
	assert_bool(r.append_record(_rec("2026-08-31", 3, 900, "ranger", 260, true))).is_true()
	# 全新实例从盘上重读 → 同 2 条（顺序保持）+ daily_best 两日分桶
	var r2 := _fresh(path)
	var table := r2.load_records()
	var records: Array = table["records"]
	assert_int(records.size()).is_equal(2)
	assert_str(String(records[0]["date"])).is_equal("2026-08-30")
	assert_str(String(records[1]["hero_id"])).is_equal("ranger")
	assert_int(int(records[1]["gems_earned"])).is_equal(260)
	assert_bool(bool(records[1]["victory"])).is_true()
	assert_dict(table["daily_best"]).has_size(2)
	# factors 归一为字符串数组并往返
	assert_array(records[0]["factors"]).is_equal(["enemy_haste", "elite_surge"])


func test_append_rejects_invalid_date_or_factors() -> void:
	var r := _fresh(_tmp_path("reject"))
	assert_bool(r.append_record({})).is_false()                              # 缺 date
	assert_bool(r.append_record(_rec(5, 1, 10))).is_false()                  # date 类型错
	var bad_factors := _rec(DATE, 1, 10)
	bad_factors["factors"] = "enemy_haste"                                   # factors 类型错
	assert_bool(r.append_record(bad_factors)).is_false()
	assert_array(r.load_records()["records"]).is_empty()


func test_record_missing_fields_get_lenient_defaults() -> void:
	var r := _fresh(_tmp_path("lenient"))
	var sparse := {"date": DATE, "factors": ["enemy_haste"]}
	assert_bool(r.append_record(sparse)).is_true()
	var rec: Dictionary = r.load_records()["records"][0]
	assert_str(String(rec["hero_id"])).is_equal("")
	assert_int(int(rec["deepest_floor"])).is_equal(0)
	assert_int(int(rec["clear_time_s"])).is_equal(0)
	assert_int(int(rec["gems_earned"])).is_equal(0)
	assert_bool(bool(rec["victory"])).is_false()
	assert_array(rec["factors"]).is_equal(["enemy_haste"])


# ================================================================ 2) 30 条截断

func test_truncates_to_thirty_most_recent() -> void:
	var r := _fresh(_tmp_path("cap30"))
	for i in 31:
		r.append_record(_rec("2026-08-%02d" % (i + 1), 1, 60 * i))
	var table := r.load_records()
	var records: Array = table["records"]
	assert_int(records.size()).is_equal(30)
	assert_str(String(records[0]["date"])).is_equal("2026-08-02")   # 最旧 1 条被挤掉
	assert_str(String(records[29]["date"])).is_equal("2026-08-31")  # 最近 30 条保留
	# daily_best 不受 30 条截断约束（规格只限 records）
	assert_dict(table["daily_best"]).has_size(31)


# ================================================================ 3) daily_best 归并

func test_daily_best_deeper_wins() -> void:
	var r := _fresh(_tmp_path("deeper"))
	r.append_record(_rec(DATE, 2, 1043))
	r.append_record(_rec(DATE, 3, 1500))
	var best := r.daily_best(DATE)
	assert_int(int(best["deepest_floor"])).is_equal(3)
	assert_int(int(best["clear_time_s"])).is_equal(1500)


func test_daily_best_same_depth_shorter_time_wins() -> void:
	var r := _fresh(_tmp_path("faster"))
	r.append_record(_rec(DATE, 3, 1500))
	r.append_record(_rec(DATE, 3, 1200))
	var best := r.daily_best(DATE)
	assert_int(int(best["deepest_floor"])).is_equal(3)
	assert_int(int(best["clear_time_s"])).is_equal(1200)
	# 更慢同深不回退
	r.append_record(_rec(DATE, 3, 1800))
	assert_int(int(r.daily_best(DATE)["clear_time_s"])).is_equal(1200)


func test_daily_best_shallower_never_overwrites() -> void:
	var r := _fresh(_tmp_path("shallow"))
	r.append_record(_rec(DATE, 3, 1500))
	r.append_record(_rec(DATE, 1, 100))
	r.append_record(_rec(DATE, 2, 100))
	var best := r.daily_best(DATE)
	assert_int(int(best["deepest_floor"])).is_equal(3)
	assert_int(int(best["clear_time_s"])).is_equal(1500)


func test_daily_best_buckets_by_date() -> void:
	var r := _fresh(_tmp_path("buckets"))
	r.append_record(_rec("2026-08-30", 2, 1043))
	r.append_record(_rec("2026-08-31", 3, 900))
	assert_int(int(r.daily_best("2026-08-30")["deepest_floor"])).is_equal(2)
	assert_int(int(r.daily_best("2026-08-31")["deepest_floor"])).is_equal(3)
	assert_dict(r.daily_best("2026-09-02")).is_empty()   # 无记录日期 → 空字典


# ================================================================ 4) fail-soft（损坏重建，不崩）

func test_corrupt_json_rebuilds_empty_and_recovers() -> void:
	var path := _tmp_path("corrupt")
	_write_json(path, "{not json~~")
	var r := _fresh(path)
	var table := r.load_records()
	assert_array(table["records"]).is_empty()
	assert_dict(table["daily_best"]).is_empty()
	# 重建后照常可写（绝不阻断）
	assert_bool(r.append_record(_rec(DATE, 1, 60))).is_true()
	assert_int(_fresh(path).load_records()["records"].size()).is_equal(1)


func test_wrong_top_level_shapes_rebuild_empty() -> void:
	for content: String in [
		"[]",                                  # 顶层非对象
		'{"version":1}',                       # 缺 records
		'{"version":1,"records":5}',           # records 类型错
		'{"version":1,"records":[],"daily_best":[]}',   # daily_best 类型错
	]:
		var path := _tmp_path("badshape")
		_write_json(path, content)
		var table := _fresh(path).load_records()
		assert_array(table["records"]).is_empty()
		assert_dict(table["daily_best"]).is_empty()
		_wipe(path)


func test_bad_records_dropped_individually() -> void:
	var path := _tmp_path("mixed")
	_write_json(path, JSON.stringify({
		"version": 1,
		"records": [
			_rec("2026-08-30", 2, 100),
			{"date": 20260830, "factors": []},             # date 类型错 → 剔除
			_rec("2026-08-31", 3, 200),
			{"date": "2026-09-01", "factors": "x"},        # factors 类型错 → 剔除
		],
		"daily_best": {"2026-08-30": {"deepest_floor": 2, "clear_time_s": 100}},
	}))
	var table := _fresh(path).load_records()
	var records: Array = table["records"]
	assert_int(records.size()).is_equal(2)
	assert_str(String(records[0]["date"])).is_equal("2026-08-30")
	assert_str(String(records[1]["date"])).is_equal("2026-08-31")
	# 合法 daily_best 保留
	assert_int(int(table["daily_best"]["2026-08-30"]["deepest_floor"])).is_equal(2)


# ================================================================ 5) 因子展示装配

func test_factor_display_triple_from_gamedb() -> void:
	var info := TrialPanelUI.factor_display("enemy_haste")
	assert_str(String(info["name"])).is_equal("敌人提速")
	assert_str(String(info["desc"])).is_not_empty()
	assert_str(String(info["icon"])).is_equal("res://art/generated/trials/factor_enemy_haste.png")
	assert_bool(ResourceLoader.exists(String(info["icon"]))).is_true()   # 素材在盘（§6）


func test_factor_displays_preserve_order_and_cover_today_pair() -> void:
	var factors: Array[String] = TrialSystem.new().pick_factors(DATE)
	assert_int(factors.size()).is_equal(2)
	var infos := TrialPanelUI.factor_displays(factors)
	assert_int(infos.size()).is_equal(2)
	for i in 2:
		var row: Dictionary = GameDB.trials[factors[i]]
		assert_str(String(infos[i]["name"])).is_equal(String(row["name"]))
		assert_str(String(infos[i]["desc"])).is_equal(String(row["desc"]))
		assert_str(String(infos[i]["icon"])) \
			.is_equal("res://art/generated/trials/factor_%s.png" % factors[i])


func test_factor_display_unknown_id_fail_soft() -> void:
	var info := TrialPanelUI.factor_display("mystery_factor")
	assert_str(String(info["name"])).is_equal("mystery_factor")   # 表外回显 id
	assert_str(String(info["desc"])).is_empty()
	assert_str(String(info["icon"])) \
		.is_equal("res://art/generated/trials/factor_mystery_factor.png")


func test_settlement_badge_helpers_flip_with_is_trial_run() -> void:
	# 普通局：标题原样、无徽标
	assert_str(TrialPanelUI.trial_title_text("守夜人陨落")).is_equal("守夜人陨落")
	var box: VBoxContainer = auto_free(VBoxContainer.new())
	assert_bool(TrialPanelUI.add_settlement_medal(box)).is_false()
	assert_object(box.get_node_or_null("TrialMedal")).is_null()
	# 试炼局：标题冠「每日试炼」+ 徽标插入首位，且幂等（重复调用不重复插）
	RunState.start_trial_run("vanguard", DATE)
	assert_str(TrialPanelUI.trial_title_text("守夜人陨落")).is_equal("每日试炼 · 守夜人陨落")
	var box2: VBoxContainer = auto_free(VBoxContainer.new())
	assert_bool(TrialPanelUI.add_settlement_medal(box2)).is_true()
	assert_bool(TrialPanelUI.add_settlement_medal(box2)).is_false()
	assert_object(box2.get_node("TrialMedal")).is_not_null()
	assert_int(box2.get_child(0).get_instance_id()).is_equal(
		box2.get_node("TrialMedal").get_instance_id())   # 插在首位


# ================================================================ 6) RunState 增量（转让链）

func test_arm_trial_pends_until_select_hero_consumes() -> void:
	RunState.arm_trial(DATE)
	# 仅挂起：未开局、pending 记录日期
	assert_bool(RunState.is_trial_run).is_false()
	assert_str(RunState.pending_trial_date).is_equal(DATE)
	# 选角消费转让 → 试炼局（种子/因子单点注入）
	RunState.select_hero("vanguard")
	assert_bool(RunState.is_trial_run).is_true()
	assert_int(RunState.run_seed).is_equal(TrialSystem.new().daily_seed(DATE))
	assert_array(RunState.trial_factors).is_equal(TrialSystem.new().pick_factors(DATE))
	assert_str(RunState.pending_trial_date).is_empty()   # 消费即清


func test_pending_consumed_once_next_select_is_normal_run() -> void:
	RunState.arm_trial(DATE)
	RunState.select_hero("vanguard")
	assert_bool(RunState.is_trial_run).is_true()
	RunState.select_hero("ranger")   # 同一次 pending 只消费一次 → 普通局
	assert_bool(RunState.is_trial_run).is_false()
	assert_dict(RunState.mods).is_empty()


func test_start_run_resets_trial_factors_and_pending() -> void:
	RunState.arm_trial(DATE)
	RunState.select_hero("vanguard")
	assert_array(RunState.trial_factors).is_not_empty()
	RunState.start_run("ranger")
	assert_array(RunState.trial_factors).is_empty()      # 复位（不残留到普通局）
	assert_bool(RunState.is_trial_run).is_false()
	# 已挂起未消费时直接开普通局 → pending 一并清除（防迟到转让）
	RunState.arm_trial(DATE)
	RunState.start_run("ranger")
	assert_str(RunState.pending_trial_date).is_empty()
	RunState.select_hero("ranger")
	assert_bool(RunState.is_trial_run).is_false()


# ================================================================ 7) 试炼面板

func _panel(path: String, router: Node = null) -> Node:
	# records/router 在 _ready 前注入 → add_child 触发接线（同 test_settings_ui 手法）
	var panel: Node = auto_free(load(PANEL_SCENE).instantiate())
	var r: TrialRecords = TrialRecords.new()
	r.records_path = path
	panel.set("records", r)
	if router != null:
		panel.set("router", router)
	add_child(panel)
	return panel


func test_panel_open_refreshes_date_factors_best_history() -> void:
	var path := _tmp_path("panel")
	var r := _fresh(path)
	r.append_record(_rec(_today(), 2, 1043, "vanguard", 180))
	var panel := _panel(path)
	assert_bool(panel.visible).is_false()
	panel.call("open")
	assert_bool(panel.visible).is_true()
	# 日期行 + 因子卡 ×2
	assert_str(String(panel.get_node("Center/Panel/Margin/Rows/Date").text)) \
		.contains(_today())
	assert_int(panel.get_node("Center/Panel/Margin/Rows/Factors").get_child_count()) \
		.is_equal(2)
	# 今日最佳（深 2 层 · 17:23）
	var best_text := String(panel.get_node("Center/Panel/Margin/Rows/Best").text)
	assert_str(best_text).contains("今日最佳")
	assert_str(best_text).contains("第 2 层")
	assert_str(best_text).contains("17:23")
	# 历史行含角色与胜负标记
	var history := String(panel.call("history_text"))
	assert_str(history).contains("骑士")   # vanguard = 骑士·凛（GameDB 中文名）


func test_panel_history_lists_recent_ten_newest_first() -> void:
	var path := _tmp_path("history")
	var r := _fresh(path)
	for i in 12:
		r.append_record(_rec("2026-08-%02d" % (i + 1), 1, 60, "vanguard", 0,
			i % 2 == 0))
	r.append_record(_rec(_today(), 3, 300, "ranger", 300, true))
	var panel := _panel(path)
	panel.call("open")
	# 双列网格：history_text = 表头 + 最近 10 条（左列最新 5、右列次新 5，列内新在上）
	var lines := String(panel.call("history_text")).split("\n")
	assert_int(lines.size()).is_equal(11)
	assert_str(lines[1]).contains(_today().substr(5))   # 最新在最前（左列首行）
	assert_str(lines[1]).contains("游侠")
	assert_str(lines[1]).contains("胜")
	assert_str(lines[10]).contains("负")           # 第 10 新（右列末行，i=3 非胜）
	# 网格恰 10 格（双列 × 5 行）
	assert_int(panel.get_node("Center/Panel/Margin/Rows/HistoryGrid") \
		.get_child_count()).is_equal(10)


func test_panel_start_arms_trial_and_routes_to_hero_select() -> void:
	var spy: SpyRouter = auto_free(SpyRouter.new())
	var panel := _panel(_tmp_path("start"), spy)
	panel.call("open")
	panel.call("_on_start_pressed")
	# arm 今日 + 路由选角 + 面板收起
	assert_str(RunState.pending_trial_date).is_equal(_today())
	assert_array(spy.calls).is_equal(["hero_select"])
	assert_bool(panel.visible).is_false()
	# 转让链闭环：选角即试炼局
	RunState.select_hero("vanguard")
	assert_bool(RunState.is_trial_run).is_true()


func test_panel_back_only_hides() -> void:
	var panel := _panel(_tmp_path("back"))
	panel.call("open")
	panel.call("_on_back_pressed")
	assert_bool(panel.visible).is_false()
	assert_str(RunState.pending_trial_date).is_empty()   # 返回不 arm


# ================================================================ 8) main_menu 挂钩冒烟

func test_main_menu_builds_trial_button_and_panel() -> void:
	var path := _tmp_path("menu")
	var host: Node = auto_free(load("res://autoload/save_system.gd").new())
	host.set("save_path", path)
	host.call("load_save")
	var menu: Node = auto_free(load(MENU_SCENE).instantiate())
	menu.set("save_system", host)   # _ready 前注入（同 test_settings_ui 手法）
	add_child(menu)
	# 运行时构建的「试 炼」按钮：在位、可用、排「开 始」之下
	var menu_box: Node = menu.get_node("Menu")
	var trial_btn: Button = null
	for c in menu_box.get_children():
		if c is Button and (c as Button).text == "试 炼":
			trial_btn = c
	assert_object(trial_btn).is_not_null()
	assert_bool(trial_btn.disabled).is_false()
	assert_int(trial_btn.get_index()).is_equal(1)
	# 试炼面板在位且隐藏；点击按钮 → 面板开；返回 → 只隐藏
	var panel: Node = menu.get_node("TrialPanelUI")
	assert_that(panel).is_not_null()
	assert_bool(panel.visible).is_false()
	menu.call("_on_trial_pressed")
	assert_bool(panel.visible).is_true()
	panel.call("_on_back_pressed")
	assert_bool(panel.visible).is_false()


# ================================================================ 9) HUD 角标 / 结算徽标

func test_hud_factor_badges_follow_trial_flag() -> void:
	var hud: CanvasLayer = auto_free(HUD.new())
	hud.run = RunState   # _ready 前注入（同生产宿主用法）
	add_child(hud)
	var badges: Node = hud.find_child("TrialBadges", true, false)
	assert_that(badges).is_not_null()
	# 普通局：无角标
	badges.call("sync", RunState)
	assert_int(badges.get_child_count()).is_equal(0)
	# 试炼局：两枚图标 + tooltip = 名称：文案
	RunState.start_trial_run("vanguard", DATE)
	badges.call("sync", RunState)
	assert_int(badges.get_child_count()).is_equal(2)
	var factors: Array[String] = TrialSystem.new().pick_factors(DATE)
	for i in 2:
		var icon: TextureRect = badges.get_child(i)
		var row: Dictionary = GameDB.trials[factors[i]]
		assert_str(icon.tooltip_text).contains(String(row["name"]))
		assert_str(icon.tooltip_text).contains(String(row["desc"]))
		assert_object(icon.texture).is_not_null()
	# 稳态再同步不重建（零分配纪律的行为面：无重复子节点）
	badges.call("sync", RunState)
	assert_int(badges.get_child_count()).is_equal(2)
	# 回普通局：角标清空
	RunState.start_run("ranger")
	badges.call("sync", RunState)
	assert_int(badges.get_child_count()).is_equal(0)


func test_death_summary_trial_medal_on_and_off() -> void:
	# 试炼局：标题冠「每日试炼」+ Panel/Box 首位徽标
	RunState.start_trial_run("vanguard", DATE)
	var summary: Node = auto_free(load("res://ui/death_summary.tscn").instantiate())
	add_child(summary)
	summary.call("open", {"stats": {"rooms": 1, "kills": 2}})
	var box: Node = summary.get_node("Panel/Box")
	assert_object(box.get_node_or_null("TrialMedal")).is_not_null()
	assert_str(summary.label_texts()[0]).contains("每日试炼")
	summary.free()
	# 普通局：无徽标、标题原样
	RunState.start_run("vanguard")
	var summary2: Node = auto_free(load("res://ui/death_summary.tscn").instantiate())
	add_child(summary2)
	summary2.call("open", {"stats": {"rooms": 1, "kills": 2}})
	assert_object(summary2.get_node("Panel/Box").get_node_or_null("TrialMedal")).is_null()
	var plain_death_title := String(summary2.label_texts()[0])
	assert_bool(plain_death_title.contains("守夜人陨落")).is_true()
	assert_bool(plain_death_title.contains("每日试炼")).is_false()


func test_victory_summary_trial_medal_on_and_off() -> void:
	# 试炼局
	RunState.start_trial_run("vanguard", DATE)
	var summary: Node = auto_free(load("res://ui/victory_summary.tscn").instantiate())
	add_child(summary)
	assert_object(summary.get_node("Panel/Box").get_node_or_null("TrialMedal")) \
		.is_not_null()
	assert_str(summary.label_texts()[0]).contains("每日试炼")
	summary.free()
	# 普通局
	RunState.start_run("vanguard")
	var summary2: Node = auto_free(load("res://ui/victory_summary.tscn").instantiate())
	add_child(summary2)
	assert_object(summary2.get_node("Panel/Box").get_node_or_null("TrialMedal")).is_null()
	var plain_victory_title := String(summary2.label_texts()[0])
	assert_bool(plain_victory_title.contains("守夜人凯旋")).is_true()
	assert_bool(plain_victory_title.contains("每日试炼")).is_false()
