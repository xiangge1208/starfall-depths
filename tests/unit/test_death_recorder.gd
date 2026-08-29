class_name TestDeathRecorder
extends GdUnitTestSuite
## m1-t22 死亡结算 + 死亡回顾 v1 契约测试。
## 1) 滑动窗口：180 帧保留（含边界 180 留 / 181 淘汰），老事件滚出
## 2) DeathReport：run_stats 注入（房数/击杀/金币/层数/蓝晶）+ Telemetry 会话
##    （hurt_count/run_time）+ 蓝晶死亡保留 50%（floor）
## 3) 致死原因 v1：窗口内最近 3s 受击次数与总伤害；空窗口泛化文案（归因限制披露）
## 4) 致死接线：fatal=true → 建报告 + 开结算恰一次（once-per-fatal）；
##    reset() 后新局可再开；suppressed 时致命完全不处理（m0_loop_smoke 兼容缝）
## 5) 遗留 CSV 清扫：purge_legacy_csv() 删除 m0 的 user://telemetry.csv（6 列防烂行）
## 6) DeathSummary UI：报告填充标签；确认 → SaveSystem.add_gems(gems_awarded)
##    恰一次 + DeathRecorder.reset()；exit_override 接缝优先（单测不真跳场景）。
##
## 【v1 归因限制（披露）】EventBus.player_damaged 无来源参数，player.gd 非本卡所有，
## 故窗口事件 source_type/source_id/pos 留空占位，致死原因 v1 退化为「最近 3s 受击
## 次数 + 总伤害」；完整来源 plumbing 落 M1-T24 / 整合卡。
##
## 【m0_loop_smoke 兼容（披露）】smoke 第 8 段故意致死，DeathRecorder 默认会接管
## 跳转死亡结算——整合时需在 smoke 致死前置 suppressed = true（本卡不改 smoke）。

const SUMMARY_SCENE := "res://ui/death_summary.tscn"
const LEGACY_CSV := "user://telemetry.csv"

var _saved_run: Dictionary = {}
var _saved_save_path: String = ""
var _tmp_save := ""


func before_test() -> void:
	_saved_run = {
		"kills": RunState.kills,
		"rooms_cleared": RunState.rooms_cleared,
		"coins": RunState.coins,
		"floor_idx": RunState.floor_idx,
		"gems": RunState.gems,
	}
	_saved_save_path = SaveSystem.save_path
	# 全套件用临时档：确认入账路径绝不写真实 user://save.json
	_tmp_save = "user://test_t22_%d.json" % absi(randi())
	SaveSystem.save_path = _tmp_save
	SaveSystem.load_save()                     # 全新默认档（gems=0）
	DeathRecorder.reset()
	DeathRecorder.suppressed = false
	DeathRecorder.open_summary_override = Callable()


func after_test() -> void:
	RunState.kills = int(_saved_run["kills"])
	RunState.rooms_cleared = int(_saved_run["rooms_cleared"])
	RunState.coins = int(_saved_run["coins"])
	RunState.floor_idx = int(_saved_run["floor_idx"])
	RunState.gems = int(_saved_run["gems"])
	DeathRecorder.reset()
	DeathRecorder.suppressed = false
	DeathRecorder.open_summary_override = Callable()
	SaveSystem.save_path = _saved_save_path
	SaveSystem.load_save()                     # 还原真实档视图
	DirAccess.remove_absolute(_tmp_save)
	DirAccess.remove_absolute(_tmp_save + ".tmp")
	_tmp_save = ""


func _spy_open() -> Array[Dictionary]:
	var opened: Array[Dictionary] = []
	DeathRecorder.open_summary_override = func(report: Dictionary) -> void:
		opened.append(report)
	return opened


# ================================================================ 1) 滑动窗口

func test_window_retains_180_frames_boundary_kept() -> void:
	DeathRecorder.record_event(2, 100)
	DeathRecorder.record_event(3, 280)         # 280-100=180：恰好保留窗沿
	assert_int(DeathRecorder.window().size()).is_equal(2)
	assert_int(DeathRecorder.window()[0]["frame"]).is_equal(100)
	assert_int(DeathRecorder.window()[1]["frame"]).is_equal(280)


func test_window_evicts_events_older_than_180_frames() -> void:
	DeathRecorder.record_event(2, 100)
	DeathRecorder.record_event(3, 150)
	DeathRecorder.record_event(4, 281)         # 281-100=181 > 180：100 淘汰
	var win := DeathRecorder.window()
	assert_int(win.size()).is_equal(2)
	assert_int(win[0]["frame"]).is_equal(150)
	assert_int(win[1]["frame"]).is_equal(281)


func test_window_event_fields_v1_shape() -> void:
	# v1 契约：source/pos 占位空值（player_damaged 无来源参数，见文件头披露）
	DeathRecorder.record_event(7, 500)
	var ev: Dictionary = DeathRecorder.window()[0]
	assert_int(ev["amount"]).is_equal(7)
	assert_int(ev["frame"]).is_equal(500)
	assert_str(String(ev["source_type"])).is_equal("")
	assert_str(String(ev["source_id"])).is_equal("")


func test_signal_path_records_player_damaged() -> void:
	# 经真实信号驱动（非致命，避免触发结算分支）
	EventBus.player_damaged.emit(4, false)
	var win := DeathRecorder.window()
	assert_int(win.size()).is_equal(1)
	assert_int(win[0]["amount"]).is_equal(4)
	assert_int(win[0]["frame"]).is_equal(Engine.get_physics_frames())


# ================================================================ 2) 报告统计

func test_report_merges_run_stats_and_telemetry_session() -> void:
	Telemetry.reset_session()
	Telemetry.log_row(["kill", 1, "a", 10])
	Telemetry.log_row(["hurt", 2, 2, 6])
	Telemetry.log_row(["hurt", 3, 1, 5])
	DeathRecorder.record_event(2, 900)
	DeathRecorder.record_event(1, 950)
	var report := DeathRecorder.build_report({
		"rooms": 3, "kills": 12, "coins": 45, "floor": 2, "gems": 5,
	})
	var stats: Dictionary = report["stats"]
	assert_int(stats["rooms"]).is_equal(3)
	assert_int(stats["kills"]).is_equal(12)
	assert_int(stats["coins"]).is_equal(45)
	assert_int(stats["floor"]).is_equal(2)
	assert_int(stats["gems"]).is_equal(5)
	assert_int(stats["gems_awarded"]).is_equal(2)      # floor(5/2)：死亡保留 50%
	assert_int(stats["hurt_count"]).is_equal(2)        # Telemetry 会话口径
	assert_float(stats["run_time"]).is_greater_equal(0.0)
	assert_dict(report).contains_keys(["cause", "window"])
	assert_int(report["window"].size()).is_equal(2)


func test_report_gems_award_floors_half() -> void:
	var odd := DeathRecorder.build_report({"gems": 5})
	assert_int(odd["stats"]["gems_awarded"]).is_equal(2)
	var even := DeathRecorder.build_report({"gems": 4})
	assert_int(even["stats"]["gems_awarded"]).is_equal(2)
	var zero := DeathRecorder.build_report({"gems": 0})
	assert_int(zero["stats"]["gems_awarded"]).is_equal(0)


func test_collect_run_stats_reads_run_state() -> void:
	RunState.rooms_cleared = 4
	RunState.kills = 21
	RunState.coins = 77
	RunState.floor_idx = 2
	RunState.gems = 130
	var stats: Dictionary = DeathRecorder.collect_run_stats()
	assert_int(stats["rooms"]).is_equal(4)
	assert_int(stats["kills"]).is_equal(21)
	assert_int(stats["coins"]).is_equal(77)
	assert_int(stats["floor"]).is_equal(2)
	assert_int(stats["gems"]).is_equal(130)


# ================================================================ 3) 致死原因 v1

func test_cause_empty_window_is_generic_nonempty() -> void:
	var report := DeathRecorder.build_report({"kills": 0})
	assert_str(report["cause"]).is_not_empty()


func test_cause_recaps_last_3s_hits_and_total_damage() -> void:
	DeathRecorder.record_event(2, 1000)
	DeathRecorder.record_event(3, 1030)
	DeathRecorder.record_event(4, 1060)
	var report := DeathRecorder.build_report({})
	assert_str(report["cause"]).contains("3")           # 3 次受击
	assert_str(report["cause"]).contains("9")           # 共 9 点伤害


# ================================================================ 4) 致死接线

func test_fatal_builds_report_and_opens_summary_once() -> void:
	RunState.kills = 9
	RunState.coins = 33
	var opened := _spy_open()
	EventBus.player_damaged.emit(5, true)
	assert_int(opened.size()).is_equal(1)
	var report: Dictionary = opened[0]
	assert_dict(report).contains_keys(["stats", "cause", "window"])
	assert_int(report["stats"]["kills"]).is_equal(9)
	assert_int(report["stats"]["coins"]).is_equal(33)
	assert_dict(DeathRecorder.current_report).is_equal(report)
	# 同局第二次致命：不重复开（once-per-fatal 守卫）
	EventBus.player_damaged.emit(5, true)
	assert_int(opened.size()).is_equal(1)


func test_reset_allows_next_run_summary() -> void:
	var opened := _spy_open()
	EventBus.player_damaged.emit(5, true)
	assert_int(opened.size()).is_equal(1)
	DeathRecorder.reset()
	EventBus.player_damaged.emit(5, true)
	assert_int(opened.size()).is_equal(2)               # 新局（reset 后）可再开


func test_suppressed_fatal_fully_ignored() -> void:
	# m0_loop_smoke / 测试隔离缝：suppressed 时致命不建报告不跳转
	DeathRecorder.suppressed = true
	var opened := _spy_open()
	EventBus.player_damaged.emit(99, true)
	assert_int(opened.size()).is_equal(0)
	assert_bool(DeathRecorder.current_report.is_empty()).is_true()


func test_scene_open_gated_off_outside_gameplay_scenes() -> void:
	# gdUnit 环境无游戏主场景（current_scene 为 null / 工具场景）→ 默认路径不接管
	# 场景流（test_skills 等真实致死不再把 death_summary 漏成孤儿节点）；
	# override 注入不受此门限制（下断言钉死优先级）。
	assert_bool(DeathRecorder.is_gameplay_scene_active()).is_false()
	var opened := _spy_open()
	EventBus.player_damaged.emit(5, true)
	assert_int(opened.size()).is_equal(1)
	assert_bool(DeathRecorder.current_report.is_empty()).is_false()


func test_non_fatal_never_opens_summary() -> void:
	var opened := _spy_open()
	EventBus.player_damaged.emit(5, false)
	EventBus.player_damaged.emit(5, false)
	assert_int(opened.size()).is_equal(0)
	assert_bool(DeathRecorder.current_report.is_empty()).is_true()


# ================================================================ 5) 遗留 CSV 清扫

func test_purge_legacy_csv_removes_stale_file() -> void:
	var f := FileAccess.open(LEGACY_CSV, FileAccess.WRITE)
	f.store_line("event,ts_frame,v1,v2,v3")   # m0 的 5 列头（烂行源）
	f = null
	assert_bool(FileAccess.file_exists(LEGACY_CSV)).is_true()
	DeathRecorder.purge_legacy_csv()
	assert_bool(FileAccess.file_exists(LEGACY_CSV)).is_false()


func test_purge_legacy_csv_missing_file_is_soft() -> void:
	DirAccess.remove_absolute(LEGACY_CSV)      # 不存在也应静默（err 可忽略）
	DeathRecorder.purge_legacy_csv()
	assert_bool(FileAccess.file_exists(LEGACY_CSV)).is_false()


# ================================================================ 6) DeathSummary UI

func _summary() -> Control:
	var node: Control = auto_free((load(SUMMARY_SCENE) as PackedScene).instantiate())
	add_child(node)
	return node


func test_summary_labels_filled_from_report() -> void:
	var report := DeathRecorder.build_report({
		"rooms": 3, "kills": 12, "coins": 45, "floor": 2, "gems": 5,
	})
	var node: Control = _summary()
	node.open(report)
	var texts: Array[String] = node.label_texts()
	var joined := "\n".join(texts)
	assert_bool(texts.any(func(t: String) -> bool: return t.contains("守夜人陨落"))).is_true()
	assert_bool(joined.contains("致死原因")).is_true()
	assert_bool(joined.contains("12")).is_true()        # 击杀数上屏
	assert_bool(joined.contains("45")).is_true()        # 金币上屏
	assert_bool(joined.contains("蓝晶")).is_true()       # 保留结算提示
	assert_bool(joined.contains("任意键")).is_true()      # 继续提示


func test_summary_auto_opens_current_report_from_recorder() -> void:
	# 生产路径：change_scene 进来时 _ready 直接读 DeathRecorder.current_report
	DeathRecorder.current_report = DeathRecorder.build_report({"kills": 7})
	var node: Control = _summary()
	var joined := "\n".join(node.label_texts())
	assert_bool(joined.contains("守夜人陨落")).is_true()
	assert_bool(joined.contains("7")).is_true()


func test_confirm_awards_half_gems_once_and_resets_recorder() -> void:
	# 生产口径：报告来自 collect_run_stats()（RunState.gems=5）→ gems_awarded=2
	RunState.gems = 5
	DeathRecorder.record_event(3, 100)
	DeathRecorder.current_report = DeathRecorder.build_report(DeathRecorder.collect_run_stats())
	var node: Control = _summary()
	var dismissed := [false]
	node.dismissed.connect(func() -> void: dismissed[0] = true)
	var exits: Array = []
	node.exit_override = func() -> void: exits.append(1)

	node._confirm()
	assert_int(SaveSystem.gems()).is_equal(2)           # floor(5/2) 入账
	assert_bool(dismissed[0]).is_true()
	assert_int(exits.size()).is_equal(1)
	assert_bool(DeathRecorder.current_report.is_empty()).is_true()   # reset 收尾
	assert_int(DeathRecorder.window().size()).is_equal(0)

	node._confirm()                                     # 双击守卫：不再入账
	assert_int(SaveSystem.gems()).is_equal(2)
	assert_int(exits.size()).is_equal(1)


func test_any_key_confirms_via_input_path() -> void:
	RunState.gems = 6
	var node: Control = _summary()
	node.open(DeathRecorder.build_report(DeathRecorder.collect_run_stats()))
	node.exit_override = func() -> void: pass
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.pressed = true
	node._unhandled_input(ev)
	assert_int(SaveSystem.gems()).is_equal(3)           # floor(6/2)


func test_summary_exit_override_takes_precedence() -> void:
	# exit seam 注入时不触碰 SceneRouter / change_scene（单测不真跳场景）
	var node: Control = _summary()
	node.open(DeathRecorder.build_report({"gems": 2}))
	var exits: Array = []
	node.exit_override = func() -> void: exits.append(1)
	node._confirm()
	assert_int(exits.size()).is_equal(1)
