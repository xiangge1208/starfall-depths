class_name TestTrialSettle
extends GdUnitTestSuite
## M3-R-C 试炼结算接线（试炼规格 §4，数值唯一出处）：
## - ×1.5 倍率（向下取整）：胜利/放弃全额出口 settle_victory_gems；死亡保底 75%（= 50% × 1.5）；
##   非试炼路径行为完全不变（死亡 50% / 胜利全额）。
## - trial_completed：每次试炼局结束发一次、每局至多一次（RunState 防重守卫；放弃 +
##   死亡/面板重复确认竞态去重）；非试炼局不计数。
## - 试炼 2 成就激活：试炼者（1 局，+100 蓝晶）/ 试炼大师（累计 10 局，+200）；非试炼局
##   完成不计；trials_total 计数持久化（unlock_tasks 快照，重开进程读档恢复）。
## - records 写入点（R-B 移交②）：死亡确认 / 胜利确认 / 放弃三路各追加恰 1 条、字段完整
##   （date = 开局业务日快照 / clear_time_s = run_time_frames/60 60Hz 帧计 / factors =
##   RunState.trial_factors / gems_earned = 实际入档额）；原子写（tmp 不残留）。
## - HUD 放弃按钮（规格 §4「放弃试炼」；暂停菜单缺席——编排者裁定入口在 HUD）：仅试炼局
##   显示；按当前进度结算（已过层口径 ×1.5 floored，无死亡减半）→ 回菜单路由守卫。
## - 结算面板倍率明细行：试炼局显示（基础 X × 1.5 = Y / 保底 75%），普通局不显示。
## - pending_trial_date 清口（R-B 移交③）：主菜单普通开始路径清迟到 arm（防转让劫持）。
## 密闭口径同 test_achievement_wiring：TestSaveSeal 换隔离档 + 归零计数器；成就消费方 =
## 全局 AchievementSystem（档换 _iso_save）；records 注入临时路径（禁写真档）。

const DATE := "2026-09-01"
const SAVE_SCRIPT := "res://autoload/save_system.gd"

var _seal: Dictionary = {}
var _iso_save: Node = null
var _save_paths: Array[String] = []
var _recs: TrialRecords = null
var _recs_path := ""
var _trial_sig_count := 0
var _trial_cb := Callable()


func before_test() -> void:
	RunState.start_run("vanguard")
	_seal = TestSaveSeal.seal("trial_settle")
	_iso_save = auto_free(load(SAVE_SCRIPT).new())
	_iso_save.save_path = _tmp_path("iso")
	_iso_save.load_save()
	AchievementSystem.save_system = _iso_save
	_recs_path = _tmp_path("recs")
	_recs = auto_free(TrialRecords.new())
	_recs.records_path = _recs_path
	TrialPanelUI.settlement_records = _recs      # 结算写入注入缝（临时路径档）
	_trial_sig_count = 0
	_trial_cb = func() -> void: _trial_sig_count += 1
	EventBus.trial_completed.connect(_trial_cb)


func after_test() -> void:
	if _trial_cb.is_valid():
		EventBus.trial_completed.disconnect(_trial_cb)
	TrialPanelUI.settlement_records = null
	AchievementSystem.save_system = get_node_or_null("/root/SaveSystem")
	AchievementSystem.reset_session()
	TestSaveSeal.restore(_seal)
	_iso_save = null
	for path in _save_paths:
		DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(path + ".tmp")
	_save_paths.clear()
	RunState.start_run("vanguard")               # 池/楼层/试炼标记复位（跨套件卫生）


# ---------------------------------------------------------------- 夹具

func _tmp_path(tag: String) -> String:
	var path := "user://test_trial_settle_%s_%d.json" % [tag, absi(randi())]
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".tmp")
	_save_paths.append(path)
	return path


# ================================================================ 1) ×1.5 倍率（胜利/放弃）

func test_trial_victory_settle_multiplies_floored() -> void:
	RunState.start_trial_run("vanguard", DATE)
	RunState.gems = 101
	assert_int(RunState.settle_victory_gems()).is_equal(151)   # floor(101 × 1.5)
	assert_int(RunState.gems).is_equal(0)
	assert_int(RunState.settle_victory_gems()).is_equal(0)     # 一次性消费防重


func test_trial_victory_settle_exact_100() -> void:
	RunState.start_trial_run("vanguard", DATE)
	RunState.gems = 100
	assert_int(RunState.settle_victory_gems()).is_equal(150)


func test_trial_abandon_settles_full_rate_no_death_halving() -> void:
	# 放弃口径：已过层 + 击杀池现值 ×1.5 floored，无死亡减半（GDD §14 仅死亡减半）
	RunState.start_trial_run("vanguard", DATE)
	assert_int(RunState.next_floor()).is_equal(2)              # 已过层 +60
	RunState.settle_kill_gems("elite", "shuangdao_lizardman")  # +5 → 池 65
	assert_int(RunState.settle_victory_gems()).is_equal(97)    # floor(65 × 1.5)，非 32（减半口径）


func test_normal_victory_settle_full_unchanged() -> void:
	RunState.start_run("vanguard")
	RunState.gems = 101
	assert_int(RunState.settle_victory_gems()).is_equal(101)   # 非试炼全额不变


# ================================================================ 2) 死亡保底 75%

func test_trial_death_settle_75_percent() -> void:
	RunState.start_trial_run("vanguard", DATE)
	RunState.gems = 100
	assert_int(RunState.settle_death_gems()).is_equal(75)      # 非 50（规格 §4）
	assert_int(RunState.gems).is_equal(0)
	RunState.start_trial_run("ranger", DATE)                   # 新局再验奇数池
	RunState.gems = 101
	assert_int(RunState.settle_death_gems()).is_equal(75)      # floor(101 × 0.75)


func test_normal_death_settle_half_unchanged() -> void:
	# 既有语义钉死（test_run_state 同口径）：非试炼死亡 50% 完全不变
	RunState.start_run("vanguard")
	RunState.gems = 100
	assert_int(RunState.settle_death_gems()).is_equal(50)
	RunState.start_run("ranger")
	RunState.gems = 101
	assert_int(RunState.settle_death_gems()).is_equal(50)      # floor(101/2)


# ================================================================ 3) trial_completed 每局至多一次

func test_trial_completed_fires_at_most_once_per_run() -> void:
	RunState.start_trial_run("vanguard", DATE)
	RunState.record_trial_completed()
	RunState.record_trial_completed()                          # 防重：同局二次无信号
	assert_int(_trial_sig_count).is_equal(1)
	assert_int(int(_iso_save.data["unlock_tasks"]["trials_total"])).is_equal(1)
	RunState.start_run("vanguard")                             # 新普通局：record 无操作
	RunState.record_trial_completed()
	assert_int(_trial_sig_count).is_equal(1)
	RunState.start_trial_run("ranger", DATE)                   # 新试炼局重新武装
	RunState.record_trial_completed()
	assert_int(_trial_sig_count).is_equal(2)


func test_trial_date_snapshot_and_reset() -> void:
	RunState.start_trial_run("vanguard", DATE)
	assert_str(RunState.trial_date).is_equal(DATE)             # 开局业务日定格（跨业务日不漂移）
	RunState.start_run("ranger")
	assert_str(RunState.trial_date).is_empty()
	assert_bool(RunState.trial_completed_fired).is_false()


# ================================================================ 4) 试炼 2 成就激活

func test_trier_unlocks_on_first_completed_trial() -> void:
	assert_bool(AchievementSystem.is_active("trier")).is_true()
	RunState.start_trial_run("vanguard", DATE)
	RunState.record_trial_completed()
	assert_bool(AchievementSystem.is_unlocked("trier")).is_true()
	assert_int(_iso_save.gems()).is_equal(100)                 # +100 蓝晶（附录 G.1）
	assert_bool(AchievementSystem.is_unlocked("trial_master")).is_false()


func test_trial_master_unlocks_at_ten_total() -> void:
	_iso_save.data["unlock_tasks"]["trials_total"] = 9         # 9 局存量（跨会话累计口径）
	RunState.start_trial_run("vanguard", DATE)
	RunState.record_trial_completed()                          # 第 10 局
	assert_bool(AchievementSystem.is_unlocked("trial_master")).is_true()
	# 全新档 trier 尚未解锁：本次轮询 goal1/goal10 同时达成 → 两条件一并解锁（100+200）
	assert_int(_iso_save.gems()).is_equal(300)
	assert_int(int(_iso_save.data["unlock_tasks"]["trials_total"])).is_equal(10)


func test_normal_run_completion_not_counted() -> void:
	RunState.start_run("vanguard")
	RunState.record_trial_completed()
	assert_int(_trial_sig_count).is_equal(0)
	assert_bool(AchievementSystem.is_unlocked("trier")).is_false()
	assert_int(int(_iso_save.data["unlock_tasks"].get("trials_total", 0))).is_equal(0)


func test_trials_total_persists_across_save_reload() -> void:
	RunState.start_trial_run("vanguard", DATE)
	RunState.record_trial_completed()
	_iso_save.load_save()                                      # 模拟重开进程读档
	assert_int(int(_iso_save.data["unlock_tasks"]["trials_total"])).is_equal(1)
	assert_int(AchievementSystem._state_value("counter:trials_total")).is_equal(1)


# ================================================================ 5) HUD 放弃按钮（三路之一）

func test_hud_abandon_settles_records_and_routes() -> void:
	RunState.start_trial_run("vanguard", DATE)
	assert_int(RunState.next_floor()).is_equal(2)              # +60
	RunState.settle_kill_gems("elite", "shuangdao_lizardman")  # +5 → 池 65
	RunState.run_time_frames = 1234                            # 60Hz 帧计：20s
	var hud: CanvasLayer = auto_free(HUD.new())
	hud.run = RunState
	add_child(hud)
	var btn: Button = hud.find_child("AbandonTrial", true, false)
	assert_that(btn).is_not_null()
	assert_bool(btn.visible).is_true()                         # 仅试炼局显示
	var routed: Array = []
	hud.abandon_route_override = func() -> void: routed.append("menu")
	btn.pressed.emit()
	assert_int(SaveSystem.gems()).is_equal(97)                 # ×1.5 floored 实际入档（无死亡减半）
	assert_int(_trial_sig_count).is_equal(1)                   # trial_completed 恰一次
	assert_int(int(_iso_save.data["unlock_tasks"]["trials_total"])).is_equal(1)
	var records: Array = _recs.load_records()["records"]
	assert_int(records.size()).is_equal(1)                     # 放弃路恰 1 条
	assert_str(String(records[0]["date"])).is_equal(DATE)
	assert_str(String(records[0]["hero_id"])).is_equal("vanguard")
	assert_int(int(records[0]["deepest_floor"])).is_equal(2)
	assert_int(int(records[0]["clear_time_s"])).is_equal(20)   # 1234 帧 / 60
	assert_int(int(records[0]["gems_earned"])).is_equal(97)
	assert_bool(records[0]["victory"]).is_false()
	var expected: Array[String] = TrialSystem.new().pick_factors(DATE)
	assert_array(records[0]["factors"]).contains_exactly(expected)
	assert_int(routed.size()).is_equal(1)                      # 回面板路由（守卫注入不真跳）


func test_hud_abandon_button_hidden_on_normal_run() -> void:
	RunState.start_run("vanguard")
	var hud: CanvasLayer = auto_free(HUD.new())
	hud.run = RunState
	add_child(hud)
	var btn: Button = hud.find_child("AbandonTrial", true, false)
	assert_that(btn).is_not_null()
	assert_bool(btn.visible).is_false()                        # 普通局不显示


# ================================================================ 6) 死亡/胜利确认写入点

func test_death_confirm_settles_75_and_appends_record_once() -> void:
	RunState.start_trial_run("vanguard", DATE)
	RunState.gems = 100
	RunState.run_time_frames = 600
	var summary: Node = auto_free(load("res://ui/death_summary.tscn").instantiate())
	add_child(summary)
	summary.exit_override = func() -> void: pass               # 不真跳场景
	summary.open({"stats": {"rooms": 3, "kills": 4, "floor": 2, "gems": 100,
		"gems_awarded": 50}})
	assert_str(_gems_line(summary)).contains("保底 75%")        # 试炼明细行（覆盖报告 50% 快照）
	summary.call("_confirm")
	assert_int(SaveSystem.gems()).is_equal(75)                 # 试炼死亡保底实际入档
	assert_int(_trial_sig_count).is_equal(1)
	var records: Array = _recs.load_records()["records"]
	assert_int(records.size()).is_equal(1)
	assert_int(int(records[0]["gems_earned"])).is_equal(75)
	assert_int(int(records[0]["clear_time_s"])).is_equal(10)
	assert_bool(records[0]["victory"]).is_false()
	summary.call("_confirm")                                   # 面板重复确认竞态：不再入账不再追加
	assert_int(SaveSystem.gems()).is_equal(75)
	assert_int(_trial_sig_count).is_equal(1)
	assert_int((_recs.load_records()["records"] as Array).size()).is_equal(1)


func test_victory_confirm_multiplies_and_appends_record() -> void:
	RunState.start_trial_run("vanguard", DATE)
	assert_int(RunState.next_floor()).is_equal(2)              # 真实胜利链：A3 Boss 后 victory
	assert_int(RunState.next_floor()).is_equal(3)              # （过层蓝晶由下方覆写，不参与断言）
	RunState.gems = 101
	RunState.run_time_frames = 3600
	var summary: Node = auto_free(load("res://ui/victory_summary.tscn").instantiate())
	add_child(summary)                                         # _ready 即 _fill
	summary.exit_override = func() -> void: pass
	assert_str(_gems_line(summary)).contains("基础 101 × 1.5 = 151")
	summary.call("_confirm")
	assert_int(SaveSystem.gems()).is_equal(151)                # ×1.5 floored 全额入档
	assert_int(_trial_sig_count).is_equal(1)
	var records: Array = _recs.load_records()["records"]
	assert_int(records.size()).is_equal(1)
	assert_int(int(records[0]["gems_earned"])).is_equal(151)
	assert_int(int(records[0]["deepest_floor"])).is_equal(3)   # 胜利 = 第 3 层
	assert_int(int(records[0]["clear_time_s"])).is_equal(60)
	assert_bool(records[0]["victory"]).is_true()


## 结算面板蓝晶行文案（Panel/Box 内含「蓝晶结算」的 Label）。
func _gems_line(summary: Node) -> String:
	for text: String in summary.call("label_texts"):
		if text.contains("蓝晶结算"):
			return text
	return ""


func test_detail_line_absent_on_normal_runs() -> void:
	RunState.start_run("vanguard")
	RunState.gems = 100
	var death: Node = auto_free(load("res://ui/death_summary.tscn").instantiate())
	add_child(death)
	death.open({"stats": {"gems": 100, "gems_awarded": 50}})
	var death_line := _gems_line(death)
	assert_str(death_line).contains("50%")
	assert_str(death_line).not_contains("× 1.5")
	var victory: Node = auto_free(load("res://ui/victory_summary.tscn").instantiate())
	add_child(victory)
	var victory_line := _gems_line(victory)
	assert_str(victory_line).contains("全额")
	assert_str(victory_line).not_contains("× 1.5")
	assert_int((_recs.load_records()["records"] as Array).size()).is_equal(0)   # 普通局不写 records


# ================================================================ 7) records 服务（R-B 移交①原子写）

func _rec() -> Dictionary:
	return {"date": DATE, "hero_id": "vanguard", "deepest_floor": 2,
		"clear_time_s": 1043, "gems_earned": 180, "victory": false,
		"factors": ["enemy_haste", "elite_surge"]}


func test_append_record_atomic_no_tmp_residue() -> void:
	assert_bool(_recs.append_record(_rec())).is_true()
	assert_bool(FileAccess.file_exists(_recs_path)).is_true()
	assert_bool(FileAccess.file_exists(_recs_path + ".tmp")).is_false()   # tmp+rename 无残骸
	var records: Array = _recs.load_records()["records"]
	assert_int(records.size()).is_equal(1)                     # 落盘往返一致
	assert_int(int(records[0]["gems_earned"])).is_equal(180)


# ================================================================ 8) pending_trial_date 清口（R-B 移交③）

func test_normal_start_clears_stale_trial_arm() -> void:
	RunState.arm_trial(DATE)
	assert_str(RunState.pending_trial_date).is_equal(DATE)
	var menu: Node = auto_free(load("res://ui/main_menu.tscn").instantiate())
	add_child(menu)
	menu.set("_router", null)                                  # 守卫路由（不真跳场景）
	menu.call("_on_start_pressed")                             # 普通开始路径
	assert_str(RunState.pending_trial_date).is_empty()         # 迟到 arm 已清
	RunState.select_hero("ranger")
	assert_bool(RunState.is_trial_run).is_false()              # 无转让劫持：普通局正常开局
