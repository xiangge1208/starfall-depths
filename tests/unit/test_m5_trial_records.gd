class_name TestM5TrialRecords
extends GdUnitTestSuite
## M5-G 每日挑战本地记录：试炼胜利蓝晶 Top10 榜（存档字段 trial_records）+
## 分享码 + 试炼入口今日最佳。
## - 服务层（SaveSystem）：胜利入库 / Top10 蓝晶降序裁剪 / 同分日期新者优先·同日
##   追加序新者优先 / 落盘往返（seed 十进制串防 int64 JSON 精度丢失）/ 防御归一化
##   （非数组丢弃、非字典/缺关键键单条剔除）/ 今日最佳查询；
## - 分享码（TrialSystem.share_code static）：STF-<seed>-<因子 - 连接> 确定式；
## - 结算接线（生产路径唯一写点 victory_summary._confirm）：试炼胜利恰 1 条、字段
##   完整、防重入；普通局不写；分享码按钮试炼局显示/可复制反馈、普通局隐藏；
## - 试炼入口（trial_panel.refresh）：无记录「今日未挑战」、有蓝晶榜记录「+N 蓝晶」、
##   与 M3-R-B daily_best 同行合并展示。
## 档隔离口径同 test_trial_settle：TestSaveSeal 换全局隔离档 + TrialRecords 注入
## 临时路径（禁写真档）；服务层用例走临时 user:// 路径全新实例（同 test_save.gd）。

const SAVE_SCRIPT := "res://autoload/save_system.gd"
const VICTORY_SCENE := "res://ui/victory_summary.tscn"
const PANEL_SCENE := "res://ui/trial_panel.tscn"
const DATE := "2026-09-01"

var _seal: Dictionary = {}
var _recs: TrialRecords = null
var _paths: Array[String] = []


func before_test() -> void:
	RunState.start_run("vanguard")
	_seal = TestSaveSeal.seal("m5_trial")          # 全局 SaveSystem 换隔离空档
	_recs = auto_free(TrialRecords.new())
	_recs.records_path = _tmp_path("recs")
	TrialPanelUI.settlement_records = _recs        # 结算 TrialRecords 注入临时路径


func after_test() -> void:
	TrialPanelUI.settlement_records = null
	TestSaveSeal.restore(_seal)
	for path in _paths:
		DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(path + ".tmp")
	_paths.clear()
	AudioMgr.stop_music()                          # victory_summary 夹具切曲卫生
	RunState.start_run("vanguard")                 # 试炼标记/种子复位（跨套件卫生）


# ---------------------------------------------------------------- 夹具

func _tmp_path(tag: String) -> String:
	var path := "user://test_m5_trial_records_%s_%d.json" % [tag, absi(randi())]
	_paths.append(path)
	return path


func _fresh(path: String) -> Node:
	# 全新实例（不在树内，_ready 不触发，显式 load_save），同 test_save.gd 模式
	var s: Node = auto_free(load(SAVE_SCRIPT).new())
	s.save_path = path
	s.load_save()
	return s


func _write_json(path: String, content: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(content)
	f = null


func _factors() -> Array[String]:
	return ["enemy_haste", "elite_surge"]


func _today() -> String:
	return TrialSystem.new().today_date()


# ================================================================ 1) 入库 + 落盘往返

func test_record_victory_appends_exact_shape() -> void:
	var s := _fresh(_tmp_path("append"))
	assert_bool(s.record_trial_victory(DATE, "4865579447467337913", _factors(),
		151, 60)).is_true()
	var board: Array = s.trial_records_board()
	assert_int(board.size()).is_equal(1)
	var rec: Dictionary = board[0]
	assert_str(String(rec["date"])).is_equal(DATE)
	assert_str(String(rec["seed"])).is_equal("4865579447467337913")   # 十进制串入库
	assert_array(rec["factors"]).contains_exactly(_factors())
	assert_int(int(rec["gems"])).is_equal(151)
	assert_int(int(rec["duration_s"])).is_equal(60)


func test_record_roundtrip_seed_survives_reload() -> void:
	# seed 是 FNV-1a-64 全域 int64：以十进制串入库，重读必须零漂移
	# （-3750763034362895579 = FNV 偏移基位型，落在 float 精度丢失段）
	var path := _tmp_path("roundtrip")
	var s := _fresh(path)
	var seed_str := str(-3750763034362895579)
	assert_bool(s.record_trial_victory(DATE, seed_str, _factors(), 151, 60)).is_true()
	var reread: Array = _fresh(path).trial_records_board()
	assert_int(reread.size()).is_equal(1)
	assert_str(String(reread[0]["seed"])).is_equal(seed_str)
	assert_int(int(reread[0]["gems"])).is_equal(151)


func test_record_rejects_empty_date() -> void:
	var s := _fresh(_tmp_path("reject"))
	assert_bool(s.record_trial_victory("", "123", _factors(), 1, 1)).is_false()
	assert_array(s.trial_records_board()).is_empty()


# ================================================================ 2) Top10 裁剪 + 排序

func test_board_trims_to_top10_by_gems() -> void:
	var s := _fresh(_tmp_path("cap10"))
	for i in 12:   # gems 101..112，全部入库后只留前 10（112..103）
		s.record_trial_victory("2026-08-%02d" % (i + 1), str(i), _factors(), 101 + i, 60)
	var board: Array = s.trial_records_board()
	assert_int(board.size()).is_equal(10)
	for i in 10:
		assert_int(int(board[i]["gems"])).is_equal(112 - i)   # 蓝晶降序
	assert_str(String(board[0]["date"])).is_equal("2026-08-12")
	assert_str(String(board[9]["date"])).is_equal("2026-08-03")   # 101/102 两条被挤出


func test_same_gems_newer_date_first() -> void:
	var s := _fresh(_tmp_path("date"))
	s.record_trial_victory("2026-08-30", "1", _factors(), 100, 60)
	s.record_trial_victory("2026-08-31", "2", _factors(), 100, 60)   # 同分，日期更新
	var board: Array = s.trial_records_board()
	assert_int(int(board[0]["gems"])).is_equal(100)
	assert_str(String(board[0]["date"])).is_equal("2026-08-31")      # 新者优先
	assert_str(String(board[1]["date"])).is_equal("2026-08-30")


func test_same_gems_same_date_later_append_first() -> void:
	var s := _fresh(_tmp_path("appendorder"))
	var earlier: Array[String] = ["earlier_factor"]
	var later: Array[String] = ["later_factor"]
	s.record_trial_victory(DATE, "1", earlier, 100, 60)
	s.record_trial_victory(DATE, "2", later, 100, 60)                # 同分同日，后打先列
	var board: Array = s.trial_records_board()
	assert_str(String(board[0]["seed"])).is_equal("2")               # 追加序新者优先
	assert_str(String(board[1]["seed"])).is_equal("1")


func test_lower_gems_never_displaces_higher() -> void:
	var s := _fresh(_tmp_path("stable"))
	s.record_trial_victory(DATE, "1", _factors(), 300, 60)
	s.record_trial_victory("2026-09-02", "2", _factors(), 50, 60)
	s.record_trial_victory("2026-09-03", "3", _factors(), 90, 60)    # 更新的低分不越位
	var board: Array = s.trial_records_board()
	assert_int(int(board[0]["gems"])).is_equal(300)
	assert_int(int(board[1]["gems"])).is_equal(90)
	assert_int(int(board[2]["gems"])).is_equal(50)


# ================================================================ 3) 防御归一化（_merge_saved 读回）

func test_malformed_records_dropped_individually() -> void:
	var path := _tmp_path("malformed")
	_write_json(path, JSON.stringify({
		"version": 2,
		"trial_records": [
			42,                                                   # 非字典 → 剔除
			{},                                                   # 缺 date → 剔除
			{"date": "", "factors": []},                          # 空 date → 剔除
			{"date": 20260901, "factors": []},                    # date 类型错 → 剔除
			{"date": DATE, "factors": "enemy_haste"},             # factors 类型错 → 剔除
			{"date": DATE, "factors": ["enemy_haste"], "seed": 4865579447,
				"gems": "x", "duration_s": null},                # 从宽：gems/duration 回落 0、
			                                                      # 数字 seed 归一十进制串，保留
		],
	}))
	var board: Array = _fresh(path).trial_records_board()
	assert_int(board.size()).is_equal(1)
	var rec: Dictionary = board[0]
	assert_str(String(rec["date"])).is_equal(DATE)
	assert_str(String(rec["seed"])).is_equal("4865579447")
	assert_array(rec["factors"]).contains_exactly(["enemy_haste"])
	assert_int(int(rec["gems"])).is_equal(0)
	assert_int(int(rec["duration_s"])).is_equal(0)


func test_non_array_trial_records_falls_back_to_empty() -> void:
	var path := _tmp_path("nonarray")
	_write_json(path, JSON.stringify({"version": 2, "trial_records": "oops"}))
	var s: Node = _fresh(path)
	assert_array(s.trial_records_board()).is_empty()
	assert_array(s.data["trial_records"]).is_empty()   # 骨架回落空表（不残留脏键）


func test_default_save_has_empty_board() -> void:
	assert_array(_fresh(_tmp_path("default")).data["trial_records"]).is_empty()


# ================================================================ 4) 今日最佳查询

func test_today_best_returns_max_gems_per_date() -> void:
	var path := _tmp_path("best")
	var s := _fresh(path)
	s.record_trial_victory("2026-09-01", "1", _factors(), 100, 60)
	s.record_trial_victory("2026-09-01", "2", _factors(), 250, 60)
	s.record_trial_victory("2026-09-02", "3", _factors(), 180, 60)
	assert_int(int(s.trial_today_best("2026-09-01")["gems"])).is_equal(250)
	assert_int(int(s.trial_today_best("2026-09-02")["gems"])).is_equal(180)
	assert_dict(s.trial_today_best("2026-09-03")).is_empty()   # 无记录日 → 空字典
	# 重读档后查询一致（落盘往返）
	assert_int(int(_fresh(path).trial_today_best("2026-09-01")["gems"])).is_equal(250)


# ================================================================ 5) 分享码（TrialSystem static）

func test_share_code_format() -> void:
	assert_str(TrialSystem.share_code("4865579447467337913", _factors())) \
		.is_equal("STF-4865579447467337913-enemy_haste-elite_surge")


func test_share_code_negative_seed_and_empty_factors() -> void:
	assert_str(TrialSystem.share_code("-3750763034362895579", _factors())) \
		.is_equal("STF--3750763034362895579-enemy_haste-elite_surge")
	assert_str(TrialSystem.share_code("1", [] as Array[String])).is_equal("STF-1-")


func test_share_code_deterministic_on_real_chain() -> void:
	# 真实派生链：当日种子 + 当日因子 → 两次构造恒同串（确定式钉死）
	var trial := TrialSystem.new()
	var seed_str := str(trial.daily_seed(DATE))
	var factors: Array[String] = trial.pick_factors(DATE)
	var code := TrialSystem.share_code(seed_str, factors)
	assert_str(code).is_equal(TrialSystem.share_code(seed_str, factors))
	assert_str(code).contains(factors[0])
	assert_str(code).contains(factors[1])
	assert_bool(code.begins_with("STF-")).is_true()
	assert_bool(code.contains(seed_str)).is_true()


# ================================================================ 6) 结算接线（生产路径唯一写点）

func test_trial_victory_confirm_writes_board_record_once() -> void:
	RunState.start_trial_run("vanguard", DATE)
	assert_int(RunState.next_floor()).is_equal(2)              # 真实胜利链上下文
	RunState.gems = 101
	RunState.run_time_frames = 3600
	var summary: Node = auto_free(load(VICTORY_SCENE).instantiate())
	add_child(summary)                                         # _ready 即 _fill（试炼局 → 按钮显示）
	summary.exit_override = func() -> void: pass               # 不真跳场景
	summary.call("_confirm")
	var board: Array = SaveSystem.trial_records_board()
	assert_int(board.size()).is_equal(1)                       # 胜利恰 1 条
	var rec: Dictionary = board[0]
	assert_str(String(rec["date"])).is_equal(DATE)             # 开局业务日快照
	assert_str(String(rec["seed"])).is_equal(
		str(TrialSystem.new().daily_seed(DATE)))               # 试炼局 run_seed = 当日种子
	assert_array(rec["factors"]).contains_exactly(
		TrialSystem.new().pick_factors(DATE))
	assert_int(int(rec["gems"])).is_equal(151)                 # ×1.5 floored 实际入档额
	assert_int(int(rec["duration_s"])).is_equal(60)            # 3600 帧 / 60（60Hz 帧计）
	summary.call("_confirm")                                   # 面板重复确认竞态：不再追加
	assert_int(SaveSystem.trial_records_board().size()).is_equal(1)


func test_normal_victory_confirm_writes_nothing() -> void:
	RunState.start_run("vanguard")
	RunState.gems = 101
	var summary: Node = auto_free(load(VICTORY_SCENE).instantiate())
	add_child(summary)
	summary.exit_override = func() -> void: pass
	summary.call("_confirm")
	assert_array(SaveSystem.trial_records_board()).is_empty()  # 普通局不入试炼榜


# ================================================================ 7) 结算页分享码按钮

func test_victory_share_button_trial_run_visible_and_copies() -> void:
	RunState.start_trial_run("vanguard", DATE)
	var summary: Node = auto_free(load(VICTORY_SCENE).instantiate())
	add_child(summary)
	var btn: Button = summary.get_node("Panel/Box/ShareBtn")
	assert_bool(btn.visible).is_true()                         # 试炼局显示
	# 复制的就是 share_code_text()（headless 剪贴板 no-op，文案缝直验）
	assert_str(summary.call("share_code_text")).is_equal(
		TrialSystem.share_code(str(RunState.run_seed), RunState.trial_factors))
	btn.pressed.emit()
	assert_str(btn.text).is_equal("已复制")                     # 反馈态（处理链跑通）


func test_victory_share_button_hidden_on_normal_run() -> void:
	RunState.start_run("vanguard")
	var summary: Node = auto_free(load(VICTORY_SCENE).instantiate())
	add_child(summary)
	assert_bool((summary.get_node("Panel/Box/ShareBtn") as Button).visible).is_false()


# ================================================================ 8) 入口今日最佳 + best_line 分支

func test_best_line_branches() -> void:
	# 双空 → 「今日未挑战」（M5-G 文案）
	assert_str(TrialPanelUI.best_line({}, {})).is_equal("今日未挑战")
	# 仅 M3-R-B daily_best → 原深层/用时口径
	assert_str(TrialPanelUI.best_line({"deepest_floor": 2, "clear_time_s": 1043}, {})) \
		.is_equal("今日最佳：第 2 层 · 17:23")
	# 仅蓝晶榜 → 「+N 蓝晶」（M5-G 文案）
	assert_str(TrialPanelUI.best_line({}, {"gems": 151})) \
		.is_equal("今日最佳：+151 蓝晶")
	# 双源同标签合并
	assert_str(TrialPanelUI.best_line({"deepest_floor": 3, "clear_time_s": 300},
		{"gems": 225})).is_equal("今日最佳：第 3 层 · 5:00 · +225 蓝晶")


func test_panel_open_shows_today_gems_best() -> void:
	# 蓝晶榜有今日记录（M3-R-B daily_best 空）→ 入口显示「+N 蓝晶」
	var today := _today()
	SaveSystem.record_trial_victory(today, "123", _factors(), 151, 60)
	var panel: Node = auto_free(load(PANEL_SCENE).instantiate())
	panel.set("records", _recs)          # _ready 前注入（空 TrialRecords）
	add_child(panel)
	panel.call("open")
	var text := String(panel.get_node("Center/Panel/Margin/Rows/Best").text)
	assert_str(text).contains("今日最佳")
	assert_str(text).contains("+151 蓝晶")


func test_panel_open_shows_untouched_when_no_records() -> void:
	# 双源皆空 → 「今日未挑战」
	var panel: Node = auto_free(load(PANEL_SCENE).instantiate())
	panel.set("records", _recs)
	add_child(panel)
	panel.call("open")
	assert_str(String(panel.get_node("Center/Panel/Margin/Rows/Best").text)) \
		.contains("今日未挑战")


func test_panel_open_merges_daily_best_and_gems_board() -> void:
	# M3-R-B daily_best（深层/用时）+ M5-G 蓝晶榜同行合并展示
	_recs.append_record({"date": _today(), "hero_id": "vanguard",
		"deepest_floor": 2, "clear_time_s": 1043, "gems_earned": 180,
		"victory": false, "factors": _factors()})
	SaveSystem.record_trial_victory(_today(), "123", _factors(), 151, 60)
	var panel: Node = auto_free(load(PANEL_SCENE).instantiate())
	panel.set("records", _recs)
	add_child(panel)
	panel.call("open")
	var text := String(panel.get_node("Center/Panel/Margin/Rows/Best").text)
	assert_str(text).contains("第 2 层")
	assert_str(text).contains("17:23")
	assert_str(text).contains("+151 蓝晶")
