class_name TestDeathRecorder
extends GdUnitTestSuite
## m1-t22 死亡结算 + 具体来源死亡回顾契约测试。
## 1) 滑动窗口：180 帧保留（含边界 180 留 / 181 淘汰），老事件滚出
## 2) DeathReport：run_stats 注入（房数/击杀/金币/层数/蓝晶）+ Telemetry 会话
##    （hurt_count/run_time）+ 蓝晶死亡保留 50%（floor）
## 3) 致死原因：最后一击具体中文来源；未知来源稳定回退
## 4) 致死接线：fatal=true → 建报告 + 开结算恰一次（once-per-fatal）；
##    reset() 后新局可再开；suppressed 时致命完全不处理（m0_loop_smoke 兼容缝）
## 5) 遗留 CSV 清扫：只删除明确识别的 m0 5 列表头；当前 6 列、未知、
##    空文件或损坏内容均 fail-safe 保留，避免启动时误删有效历史。
## 6) DeathSummary UI：报告填充标签；确认 → SaveSystem.add_gems(gems_awarded)
##    恰一次 + DeathRecorder.reset()；exit_override 接缝优先（单测不真跳场景）。
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


func test_window_event_keeps_detailed_source_shape() -> void:
	DeathRecorder.record_event(7, 500, "projectile", "crossbowman", Vector2(2, 3),
		"弩兵", "弹幕", false)
	var ev: Dictionary = DeathRecorder.window()[0]
	assert_int(ev["amount"]).is_equal(7)
	assert_int(ev["frame"]).is_equal(500)
	assert_str(String(ev["source_type"])).is_equal("projectile")
	assert_str(String(ev["source_id"])).is_equal("crossbowman")
	assert_str(String(ev["source_name"])).is_equal("弩兵")
	assert_str(String(ev["attack_name"])).is_equal("弹幕")
	assert_vector(ev["pos"]).is_equal(Vector2(2, 3))
	assert_bool(ev["fatal"]).is_false()


func test_signal_path_records_player_hit_resolved() -> void:
	EventBus.player_hit_resolved.emit(4, false, {
		"frame": 701, "source_type": "contact", "source_id": "cave_bat",
		"source_name": "穴蝠", "attack_name": "接触冲撞", "from": Vector2(8, 9),
	})
	var win := DeathRecorder.window()
	assert_int(win.size()).is_equal(1)
	assert_int(win[0]["amount"]).is_equal(4)
	assert_int(win[0]["frame"]).is_equal(701)
	assert_str(win[0]["source_name"]).is_equal("穴蝠")


func test_real_player_preserves_source_and_legacy_signal_once() -> void:
	var p: Player = auto_free(Player.new())
	var details: Array[Dictionary] = []
	var legacy: Array = []
	var detail_cb := func(_amount: int, _fatal: bool, ctx: Dictionary) -> void:
		details.append(ctx)
	var legacy_cb := func(amount: int, fatal: bool) -> void:
		legacy.append([amount, fatal])
	EventBus.player_hit_resolved.connect(detail_cb)
	EventBus.player_damaged.connect(legacy_cb)
	p.shield = 0
	p.hp = 3
	var source := {
		"amount": 3, "source_type": "projectile", "source_id": "crossbowman",
		"source_name": "弩兵", "attack_name": "弹幕", "from": Vector2(9, 10),
	}
	p.take_hit_ctx(source, 800)
	EventBus.player_hit_resolved.disconnect(detail_cb)
	EventBus.player_damaged.disconnect(legacy_cb)
	assert_int(details.size()).is_equal(1)
	assert_int(legacy.size()).is_equal(1)
	assert_str(String(details[0]["source_name"])).is_equal("弩兵")
	assert_str(String(details[0]["attack_name"])).is_equal("弹幕")
	assert_int(details[0]["frame"]).is_equal(800)
	assert_bool(details[0]["fatal"]).is_true()
	assert_int(details[0]["remaining_hp"]).is_equal(0)
	assert_bool(details[0]["roll_available"]).is_true()
	assert_int(details[0]["hp_damage"]).is_equal(3)
	assert_bool(source.has("fatal")).is_false()   # 调用方字典未被 Player 改写

func test_real_player_overkill_records_only_actual_effective_damage() -> void:
	var p: Player = auto_free(Player.new())
	var details: Array[Dictionary] = []
	var legacy: Array = []
	var detail_cb := func(amount: int, fatal: bool, ctx: Dictionary) -> void:
		details.append({"amount": amount, "fatal": fatal, "ctx": ctx})
	var legacy_cb := func(amount: int, fatal: bool) -> void:
		legacy.append([amount, fatal])
	EventBus.player_hit_resolved.connect(detail_cb)
	EventBus.player_damaged.connect(legacy_cb)
	p.shield = 2
	p.hp = 1
	p.take_hit_ctx({"amount": 99, "source_name": "藤蔓巨像", "attack_name": "毒雨"}, 810)
	EventBus.player_hit_resolved.disconnect(detail_cb)
	EventBus.player_damaged.disconnect(legacy_cb)
	assert_int(p.shield).is_equal(0)
	assert_int(p.hp).is_equal(0)
	assert_int(details.size()).is_equal(1)
	assert_int(details[0]["amount"]).is_equal(3)
	assert_bool(details[0]["fatal"]).is_true()
	assert_int(details[0]["ctx"]["amount"]).is_equal(3)
	assert_int(details[0]["ctx"]["hp_damage"]).is_equal(1)
	assert_array(legacy).contains_exactly([[3, true]])


func test_negative_player_damage_emits_no_damage_telemetry_or_death_record() -> void:
	var p: Player = auto_free(Player.new())
	var details: Array = []
	var legacy: Array = []
	var detail_cb := func(amount: int, fatal: bool, ctx: Dictionary) -> void:
		details.append([amount, fatal, ctx])
	var legacy_cb := func(amount: int, fatal: bool) -> void:
		legacy.append([amount, fatal])
	EventBus.player_hit_resolved.connect(detail_cb)
	EventBus.player_damaged.connect(legacy_cb)
	p.rampage_active_until = 1000
	p.take_hit_ctx({"amount": -99, "source_name": "藤蔓巨像", "attack_name": "毒雨"}, 820)
	EventBus.player_hit_resolved.disconnect(detail_cb)
	EventBus.player_damaged.disconnect(legacy_cb)
	assert_array(details).is_empty()
	assert_array(legacy).is_empty()
	assert_array(DeathRecorder.window()).is_empty()
	assert_int(Telemetry.session_summary()["hurt_count"]).is_equal(0)


func test_projectile_setup_resets_pooled_source_fields() -> void:
	var p: Projectile = auto_free(Projectile.new())
	p.setup({"source_type": "projectile", "source_id": "crossbowman",
		"source_name": "弩兵", "attack_name": "弹幕"})
	assert_str(p.source_name).is_equal("弩兵")
	p.setup({})
	assert_str(p.source_type).is_equal("projectile")
	assert_str(p.source_id).is_equal("")
	assert_str(p.source_name).is_equal("")
	assert_str(p.attack_name).is_equal("弹幕")


# ================================================================ 2) 报告统计

func test_report_merges_run_stats_and_telemetry_session() -> void:
	Telemetry.reset_session()
	Telemetry.record_player_damage(7, 100)
	Telemetry.record_player_damage(5, 140)
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
	assert_int(stats["peak_dps"]).is_equal(12)         # 60t 滚动窗口峰值
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


# ================================================================ 3) 致死原因

func test_cause_empty_window_is_generic_nonempty() -> void:
	var report := DeathRecorder.build_report({"kills": 0})
	assert_str(report["cause"]).is_not_empty()


func test_cause_uses_last_fatal_hit_not_first_or_largest() -> void:
	DeathRecorder.record_event(20, 1000, "contact", "cave_bat", Vector2.ZERO, "穴蝠", "接触冲撞")
	DeathRecorder.record_event(3, 1030, "projectile", "crossbowman", Vector2.ZERO, "弩兵", "弹幕")
	DeathRecorder.record_event(4, 1060, "boss", "vine_colossus", Vector2.ZERO,
		"藤蔓巨像", "藤蔓横扫", true)
	var report := DeathRecorder.build_report({})
	assert_str(report["cause"]).is_equal("藤蔓巨像的藤蔓横扫")
	assert_dict(report["fatal_event"]).is_equal(report["window"].back())
	assert_int(report["fatal_event"]["remaining_hp"]).is_equal(-1)
	assert_bool(report["fatal_event"]["roll_available"]).is_false()

func test_cause_fallbacks_are_chinese_and_stable() -> void:
	DeathRecorder.record_event(1, 100, "contact", "x", Vector2.ZERO, "穴蝠", "", true)
	assert_str(DeathRecorder.build_report({})["cause"]).is_equal("穴蝠的攻击")
	DeathRecorder.reset()
	DeathRecorder.record_event(1, 100, "", "", Vector2.ZERO, "", "", true)
	assert_str(DeathRecorder.build_report({})["cause"]).is_equal("未知伤害")


# ================================================================ 4) 致死接线

func test_fatal_builds_report_and_opens_summary_once() -> void:
	RunState.kills = 9
	RunState.coins = 33
	var opened := _spy_open()
	EventBus.player_hit_resolved.emit(5, true, {
		"frame": 100, "source_name": "弩兵", "attack_name": "弹幕",
		"source_type": "projectile", "source_id": "crossbowman",
	})
	assert_int(opened.size()).is_equal(1)
	var report: Dictionary = opened[0]
	assert_dict(report).contains_keys(["stats", "cause", "window"])
	assert_int(report["stats"]["kills"]).is_equal(9)
	assert_int(report["stats"]["coins"]).is_equal(33)
	assert_dict(DeathRecorder.current_report).is_equal(report)
	# 同局第二次致命：不重复开（once-per-fatal 守卫）
	EventBus.player_hit_resolved.emit(5, true, {"frame": 101})
	assert_int(opened.size()).is_equal(1)


func test_reset_allows_next_run_summary() -> void:
	var opened := _spy_open()
	EventBus.player_hit_resolved.emit(5, true, {"frame": 100})
	assert_int(opened.size()).is_equal(1)
	DeathRecorder.reset()
	EventBus.player_hit_resolved.emit(5, true, {"frame": 200})
	assert_int(opened.size()).is_equal(2)               # 新局（reset 后）可再开


func test_suppressed_fatal_fully_ignored() -> void:
	# m0_loop_smoke / 测试隔离缝：suppressed 时致命不建报告不跳转
	DeathRecorder.suppressed = true
	var opened := _spy_open()
	EventBus.player_hit_resolved.emit(99, true, {"frame": 100})
	assert_int(opened.size()).is_equal(0)
	assert_bool(DeathRecorder.current_report.is_empty()).is_true()


func test_scene_open_gated_off_outside_gameplay_scenes() -> void:
	# gdUnit 环境无游戏主场景（current_scene 为 null / 工具场景）→ 默认路径不接管
	# 场景流（test_skills 等真实致死不再把 death_summary 漏成孤儿节点）；
	# override 注入不受此门限制（下断言钉死优先级）。
	assert_bool(DeathRecorder.is_gameplay_scene_active()).is_false()
	var opened := _spy_open()
	EventBus.player_hit_resolved.emit(5, true, {"frame": 100})
	assert_int(opened.size()).is_equal(1)
	assert_bool(DeathRecorder.current_report.is_empty()).is_false()


func test_non_fatal_never_opens_summary() -> void:
	var opened := _spy_open()
	EventBus.player_hit_resolved.emit(5, false, {"frame": 100})
	EventBus.player_hit_resolved.emit(5, false, {"frame": 200})
	assert_int(opened.size()).is_equal(0)
	assert_bool(DeathRecorder.current_report.is_empty()).is_true()


# ================================================================ 5) 遗留 CSV 清扫

func _write_telemetry_bytes(bytes: PackedByteArray) -> void:
	var f := FileAccess.open(LEGACY_CSV, FileAccess.WRITE)
	assert_object(f).is_not_null()
	f.store_buffer(bytes)
	f.flush()
	f = null


func _assert_telemetry_bytes_equal(expected: PackedByteArray) -> void:
	var f := FileAccess.open(LEGACY_CSV, FileAccess.READ)
	assert_object(f).is_not_null()
	var actual := f.get_buffer(f.get_length())
	f = null
	assert_int(actual.size()).is_equal(expected.size())
	if actual.size() != expected.size():
		return
	for i in expected.size():
		assert_int(actual[i]).is_equal(expected[i])


func test_purge_legacy_csv_removes_recognized_five_column_file() -> void:
	var f := FileAccess.open(LEGACY_CSV, FileAccess.WRITE)
	f.store_line("event,ts_frame,v1,v2,v3")   # m0 的 5 列头（烂行源）
	f.store_line("hurt,10,2,6,")
	f = null
	assert_bool(FileAccess.file_exists(LEGACY_CSV)).is_true()
	DeathRecorder.purge_legacy_csv()
	assert_bool(FileAccess.file_exists(LEGACY_CSV)).is_false()


func test_purge_legacy_csv_preserves_current_six_column_file_byte_for_byte() -> void:
	var original := (Telemetry.HEADER + "\r\nkill,42,bat,7,,tiejian\r\n").to_utf8_buffer()
	_write_telemetry_bytes(original)
	DeathRecorder.purge_legacy_csv()
	assert_bool(FileAccess.file_exists(LEGACY_CSV)).is_true()
	_assert_telemetry_bytes_equal(original)
	DirAccess.remove_absolute(LEGACY_CSV)


func test_purge_legacy_csv_preserves_unknown_header_file() -> void:
	var original := "future_event,frame,payload\nopaque,1,x\n".to_utf8_buffer()
	_write_telemetry_bytes(original)
	DeathRecorder.purge_legacy_csv()
	assert_bool(FileAccess.file_exists(LEGACY_CSV)).is_true()
	_assert_telemetry_bytes_equal(original)
	DirAccess.remove_absolute(LEGACY_CSV)


func test_purge_legacy_csv_preserves_empty_and_corrupt_files() -> void:
	_write_telemetry_bytes(PackedByteArray())
	DeathRecorder.purge_legacy_csv()
	assert_bool(FileAccess.file_exists(LEGACY_CSV)).is_true()
	_assert_telemetry_bytes_equal(PackedByteArray())
	var corrupt := PackedByteArray([0xff, 0xfe, 0x00, 0x81, 0x0a])
	_write_telemetry_bytes(corrupt)
	DeathRecorder.purge_legacy_csv()
	assert_bool(FileAccess.file_exists(LEGACY_CSV)).is_true()
	_assert_telemetry_bytes_equal(corrupt)
	DirAccess.remove_absolute(LEGACY_CSV)


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
	DeathRecorder.record_event(3, 100, "projectile", "crossbowman", Vector2.ZERO,
		"弩兵", "弹幕", true)
	Telemetry.record_player_damage(7, 100)
	Telemetry.record_player_damage(5, 140)
	var report := DeathRecorder.build_report({
		"rooms": 3, "kills": 12, "coins": 45, "floor": 2, "gems": 5,
	})
	var node: Control = _summary()
	node.open(report)
	var texts: Array[String] = node.label_texts()
	var joined := "\n".join(texts)
	assert_bool(texts.any(func(t: String) -> bool: return t.contains("守夜人陨落"))).is_true()
	assert_bool(joined.contains("致死原因")).is_true()
	assert_bool(joined.contains("弩兵的弹幕")).is_true()
	assert_bool(joined.contains("剩余生命：未知")).is_true()
	assert_bool(joined.contains("当时翻滚：不可用")).is_true()
	assert_bool(joined.contains("12")).is_true()        # 击杀数上屏
	assert_bool(joined.contains("45")).is_true()        # 金币上屏
	assert_bool(joined.contains("DPS 峰值 12")).is_true()
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
	assert_int(RunState.gems).is_equal(0)               # 本局待结算蓝晶已消费
	assert_bool(dismissed[0]).is_true()
	assert_int(exits.size()).is_equal(1)
	assert_bool(DeathRecorder.current_report.is_empty()).is_true()   # reset 收尾
	assert_int(DeathRecorder.window().size()).is_equal(0)

	node._confirm()                                     # 双击守卫：不再入账
	assert_int(SaveSystem.gems()).is_equal(2)
	assert_int(exits.size()).is_equal(1)

func test_next_run_cannot_reaward_previous_run_gems() -> void:
	RunState.start_run("vanguard")
	assert_int(RunState.next_floor()).is_equal(2)
	assert_int(RunState.gems).is_equal(60)          # A1 通关奖励进入本局待结算池
	DeathRecorder.current_report = DeathRecorder.build_report(DeathRecorder.collect_run_stats())
	var first: Control = _summary()
	first.exit_override = func() -> void: pass
	first._confirm()
	assert_int(SaveSystem.gems()).is_equal(30)
	assert_int(RunState.gems).is_equal(0)
	SaveSystem.data = {}
	SaveSystem.load_save()
	assert_int(SaveSystem.gems()).is_equal(30)       # 重新读临时存档仍为 30，证明已持久化

	# 即使误建第二个死亡面板，同一局已消费的 pending gems 也不能再领取。
	var duplicate: Control = _summary()
	duplicate.open({"stats": {"gems": 60, "gems_awarded": 30}})
	duplicate.exit_override = func() -> void: pass
	duplicate._confirm()
	assert_int(SaveSystem.gems()).is_equal(30)

	RunState.start_run("ranger")
	assert_int(RunState.gems).is_equal(0)
	DeathRecorder.current_report = DeathRecorder.build_report(DeathRecorder.collect_run_stats())
	var second: Control = _summary()
	second.exit_override = func() -> void: pass
	second._confirm()
	assert_int(SaveSystem.gems()).is_equal(30)


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


# ================================================================ 7) ReplayKey 与死亡回放（m2-t24）
## 回放键契约：致死时记录 {run_seed, floor_idx, death_frame}，death_frame 为
## 层内帧（致死全局帧 - Telemetry floor_build 基准帧，无基准回退原帧，clamp ≥0）。
## 回放状态机：start_replay → 8x 快进至死亡帧前 3s → 恢复 1.0 → death_frame 到点
## 暂停 +「这就是你的死亡时刻」；观战玩家无敌+输入禁用；time_scale 恢复 1.0
## 具 finally 语义（到点/退出/_exit_tree 三路兜底）。


func test_fatal_records_replay_key_with_run_seed_floor_and_death_frame() -> void:
	RunState.run_seed = 123456789
	RunState.floor_idx = 2
	EventBus.player_hit_resolved.emit(5, true, {
		"frame": 555, "source_name": "弩兵", "attack_name": "弹幕",
	})
	assert_dict(DeathRecorder.replay_key).contains_keys(["run_seed", "floor_idx", "death_frame"])
	assert_int(int(DeathRecorder.replay_key["run_seed"])).is_equal(123456789)
	assert_int(int(DeathRecorder.replay_key["floor_idx"])).is_equal(2)
	assert_int(int(DeathRecorder.replay_key["death_frame"])).is_equal(555)   # 无构建基准 → 原帧回退


func test_replay_key_death_frame_is_floor_local_tick() -> void:
	Telemetry.log_row(["floor_build", 1000, "5"])     # 楼层构建于全局帧 1000
	EventBus.player_hit_resolved.emit(5, true, {"frame": 1180})
	assert_int(int(DeathRecorder.replay_key["death_frame"])).is_equal(180)   # 层内帧


func test_replay_key_floor_local_clamps_negative_to_zero() -> void:
	Telemetry.log_row(["floor_build", 2000, "5"])
	EventBus.player_hit_resolved.emit(5, true, {"frame": 1500})   # 异常：致死帧早于构建帧
	assert_int(int(DeathRecorder.replay_key["death_frame"])).is_equal(0)


func test_replay_key_absent_for_non_fatal_and_cleared_on_reset() -> void:
	EventBus.player_hit_resolved.emit(5, false, {"frame": 100})
	assert_bool(DeathRecorder.replay_key.is_empty()).is_true()
	EventBus.player_hit_resolved.emit(5, true, {"frame": 200})
	assert_bool(DeathRecorder.replay_key.is_empty()).is_false()
	DeathRecorder.reset()
	assert_bool(DeathRecorder.replay_key.is_empty()).is_true()


func test_report_carries_replay_key() -> void:
	RunState.run_seed = 42
	RunState.floor_idx = 3
	EventBus.player_hit_resolved.emit(5, true, {"frame": 777})
	var report := DeathRecorder.build_report({})
	assert_dict(report["replay_key"]).is_equal(DeathRecorder.replay_key)


func _replayable_summary(death_frame: int) -> Control:
	# 回放面板脚手架：激活种子 + 注入回放键 + 装载报告（走 _ready 自动填充路径）
	RunState.start_run("vanguard")
	DeathRecorder.record_replay_key(RunState.run_seed, 1, death_frame)
	DeathRecorder.current_report = DeathRecorder.build_report(DeathRecorder.collect_run_stats())
	return _summary()


func test_summary_replay_button_visible_only_with_replay_key() -> void:
	var plain: Control = _summary()
	plain.open(DeathRecorder.build_report({}))
	assert_bool((plain.get_node("Panel/Box/Replay") as Button).visible).is_false()
	var keyed: Control = _replayable_summary(100000)
	assert_bool((keyed.get_node("Panel/Box/Replay") as Button).visible).is_true()


func test_summary_replay_fast_forwards_then_pauses_at_death_frame() -> void:
	var node: Control = _replayable_summary(40)       # 死亡帧 40 < 180t 预滚 → 快进段为 0
	node.start_replay()
	assert_int(node.replay_state()).is_equal(1)       # FAST_FORWARD
	assert_float(Engine.time_scale).is_equal(8.0)
	var fl: FloorScene = node.replay_floor()
	assert_object(fl).is_not_null()
	var spectator: Player = fl.player_node()
	assert_int(spectator.process_mode).is_equal(Node.PROCESS_MODE_DISABLED)   # 观战：输入禁用
	assert_bool(spectator.is_invincible()).is_true()                          # 观战：无敌
	node._replay_advance(1)                           # ≥ ff_until(0)：恢复实速进 LIVE
	assert_float(Engine.time_scale).is_equal(1.0)
	assert_int(node.replay_state()).is_equal(2)       # LIVE
	node._replay_advance(39)
	assert_int(node.replay_state()).is_equal(2)
	node._replay_advance(40)                          # ≥ death_frame：到点
	assert_int(node.replay_state()).is_equal(3)       # DONE
	assert_float(Engine.time_scale).is_equal(1.0)
	assert_int((node.replay_floor() as FloorScene).process_mode).is_equal(Node.PROCESS_MODE_DISABLED)
	assert_str(node.replay_banner_text()).is_equal("这就是你的死亡时刻")
	node.end_replay()                                 # after_test 前恢复全局状态


func test_summary_replay_end_restores_timescale_and_panel() -> void:
	var node: Control = _replayable_summary(100000)
	node.start_replay()
	assert_bool(node.replay_active()).is_true()
	node.end_replay()
	assert_float(Engine.time_scale).is_equal(1.0)
	assert_bool(node.replay_active()).is_false()
	assert_object(node.replay_floor()).is_null()
	assert_bool((node.get_node("Panel") as Control).visible).is_true()
	assert_bool((node.get_node("Dim") as ColorRect).visible).is_true()
	assert_bool((node.get_node("ReplayView") as Control).visible).is_false()
	assert_bool(DeathRecorder.suppressed).is_false()


func test_summary_input_during_replay_ends_replay_not_confirm() -> void:
	var node: Control = _replayable_summary(100000)
	RunState.gems = 6                                  # start_run 之后注入（开局会清零）
	var exits: Array = []
	node.exit_override = func() -> void: exits.append(1)
	node.start_replay()
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.pressed = true
	node._unhandled_input(ev)
	assert_bool(node.replay_active()).is_false()
	assert_float(Engine.time_scale).is_equal(1.0)
	assert_array(exits).is_empty()                    # 回放中按键不触发结算离场
	assert_int(RunState.gems).is_equal(6)             # 蓝晶未入账（待结算池原封不动）


func test_summary_replay_teleports_spectator_to_fatal_room_with_waves() -> void:
	RunState.start_run("vanguard")
	var build := DungeonBuilder.build(RunState.run_seed, 1)
	var target := -1
	var pos := Vector2.ZERO
	for id in build["rooms"]:
		var rid := int(id)
		if String((((build["rooms"] as Dictionary)[rid] as Dictionary)["node"] as Dictionary)["type"]) == "combat":
			target = rid
			var rd: Dictionary = (build["rooms"] as Dictionary)[rid]
			var tpl := RoomTemplate.get_room(String(rd["template_id"]))
			var size: Array = tpl.get("size", [22, 14])
			pos = Vector2(rd["world_pos"]) + Vector2(size[0], size[1]) * 8.0   # 房外框中心
			break
	assert_int(target).is_greater_equal(0)
	DeathRecorder.record_replay_key(RunState.run_seed, 1, 100000)
	var report := DeathRecorder.build_report({})
	report["fatal_event"] = {"pos": pos}
	var node: Control = _summary()
	node.open(report)
	node.start_replay()
	var fl: FloorScene = node.replay_floor()
	assert_int(fl.flow.current_room).is_equal(target)      # BFS 放行 → 致死房即当前房
	assert_int(fl.room_node(target).enemies.size()).is_greater(0)   # 同波次：进房即刷波
	assert_vector(fl.player_node().global_position).is_equal(pos)   # 观战者落于致死点
	assert_int(fl.room_count()).is_equal((build["rooms"] as Dictionary).size())   # 同布局
	node.end_replay()


func test_summary_exit_tree_restores_timescale_finally() -> void:
	var node: Control = _replayable_summary(100000)
	node.start_replay()
	assert_float(Engine.time_scale).is_equal(8.0)
	node.free()                                       # 任意路径离场：finally 语义
	assert_float(Engine.time_scale).is_equal(1.0)
