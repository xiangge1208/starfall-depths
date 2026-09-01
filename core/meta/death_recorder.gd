extends Node
## 死亡记录器（m1-t22）：滑动窗口记录玩家受击事件 + 致死时生成 DeathReport 并打开死亡结算。
## autoload 名 "DeathRecorder"（project.godot 注册在 Telemetry 之后，命名规则同 GameDB/RunState）。
##
## 归因路径：Player 结算实际伤害后发 player_hit_resolved；窗口保留完整来源，
## 致死报告以最后一击为权威原因，并同时保留 3 秒窗口供回顾。
##
## 致死接线：player_hit_resolved(fatal=true) → build_report(collect_run_stats()) →
## 开死亡结算场景。场景路由：优先 /root/SceneRouter.goto("death")（T23 可能未合入，
## get_node_or_null 守卫，同 T11 对 RunState 的探测模式）；否则直接
## change_scene_to_file("res://ui/death_summary.tscn")（本卡新建，路径恒存在）。
##
## 【m0_loop_smoke / gdUnit 兼容】真实场景跳转仅在「游戏场景在前台」时接管：
## current_scene 的脚本/场景路径位于 res://tests/ 或 res://addons/（工具场景：gdUnit
## runner、m0_loop_smoke 冒烟）时不跳转（test_skills 等套件会真实致死玩家，接管会
## 把 death_summary 实例漏成孤儿节点）。open_summary_override 注入不受此门限制，
## 单测经接缝验证完整报告/开面板路径；E2E 手动检查以训练房为 current_scene 走全路径。
##
## 【T18 移交】m0 逐行写盘的 user://telemetry.csv 是 5 列头，与 m1-t18 的 6 列头混写
## 会产生烂行——启动时仅删除表头精确命中旧格式的文件。当前格式或无法识别的
## 内容 fail-safe 保留，避免重启丢失合法历史。
##
## 【结算口径】蓝晶死亡保留 50%（GDD §14/§19）：gems_awarded = floor(RunState.gems / 2)，
## 由 DeathSummary 确认时经 SaveSystem.add_gems 入账。reset() 同时清 Telemetry 会话
## 计数（T18 预留的重开口径）；T23 的 start_run 整合时可改为开局调用 reset。
##
## 【m2-t24 回放键】致死时记录 ReplayKey {run_seed, floor_idx, death_frame}：
## death_frame 为层内帧（致死全局帧 - Telemetry floor_build 基准帧，无基准回退
## 原帧、clamp ≥0）——DeathSummary 据此重建该层 FloorScene 做 3s 死亡回顾重放
## （演示性重放，见 death_summary.gd 头注释）；report 同时携带 replay_key。
## reset() 清空（新局不可回放旧局）。

const WINDOW_TICKS := 180   # 3s @60fps：受击事件保留窗
const SUMMARY_SCENE := "res://ui/death_summary.tscn"
const LEGACY_CSV := "user://telemetry.csv"
const LEGACY_CSV_HEADER := "event,ts_frame,v1,v2,v3"

## 致死处理总开关（默认接管）。工具/整合场景可显式置 true 完全忽略致命。
var suppressed := false
## 开结算接缝（测试注入口，同 EventRoom.apply_effect 模式）：有效时替代真实跳转。
var open_summary_override: Callable = Callable()
## 最近一次致死生成的报告（DeathSummary 场景 _ready 读取；reset 清空）。
var current_report: Dictionary = {}
## m2-t24：最近一次致死的回放键 {run_seed, floor_idx, death_frame}（层内帧）；
## DeathSummary「回放」按钮据此重建楼层。reset() 清空。
var replay_key: Dictionary = {}

var _window: Array[Dictionary] = []   # {frame, amount, source_type/id/name, attack_name, pos, fatal}
var _fatal_handled := false           # once-per-fatal：同局第二次致命不再重复开

func _ready() -> void:
	purge_legacy_csv()                        # T18 移交：清 m0 的 5 列烂行文件（一次性）
	EventBus.player_hit_resolved.connect(_on_player_hit_resolved)

## 受击入窗：frame 显式传入（测试可注入历史帧）；旧五参调用仍兼容。
func record_event(amount: int, frame: int, source_type := "", source_id := "",
		pos := Vector2.ZERO, source_name := "", attack_name := "", fatal := false,
		remaining_hp := -1, roll_available := false) -> void:
	_window.append({
		"frame": frame,
		"amount": amount,
		"source_type": source_type,
		"source_id": source_id,
		"source_name": source_name,
		"attack_name": attack_name,
		"pos": pos,
		"fatal": fatal,
		"remaining_hp": remaining_hp,
		"roll_available": roll_available,
	})
	while not _window.is_empty() and frame - int(_window[0]["frame"]) > WINDOW_TICKS:
		_window.remove_at(0)                  # 滑动淘汰：超出 180t 的最老事件滚出

func window() -> Array[Dictionary]:
	return _window.duplicate(true)

## 组装 DeathReport：stats（run_stats 注入 + Telemetry 会话）+ cause + window + replay_key。
## run_stats 缺键按 0 处理（纯函数口径，测试注入任意子集均安全）。
func build_report(run_stats: Dictionary) -> Dictionary:
	var gems := int(run_stats.get("gems", 0))
	var summary := Telemetry.session_summary()
	var fatal_event: Dictionary = _window.back().duplicate(true) if not _window.is_empty() else {}
	return {
		"stats": {
			"rooms": int(run_stats.get("rooms", 0)),
			"kills": int(run_stats.get("kills", 0)),
			"coins": int(run_stats.get("coins", 0)),
			"floor": int(run_stats.get("floor", 0)),
			"gems": gems,
			"gems_awarded": int(floor(gems / 2.0)),   # §14/§19：死亡保留 50%（floor）
			"hurt_count": int(summary.get("hurt_count", 0)),
			"peak_dps": int(summary.get("peak_dps", 0)),
			"run_time": float(summary.get("run_time", 0.0)),
		},
		"cause": _cause_text(fatal_event),
		"fatal_event": fatal_event,
		"window": window(),
		"replay_key": replay_key.duplicate(true),
	}


## m2-t24：记录回放键（_on_player_hit_resolved 致死路径调用；测试可直调注入）。
## death_frame 语义为「层内帧」：重放重建的 FloorScene 从层内 0 帧起播，快进/暂停
## 目标均以层内帧计（见 death_summary.gd）。
func record_replay_key(p_run_seed: int, p_floor_idx: int, death_frame: int) -> void:
	replay_key = {
		"run_seed": p_run_seed,
		"floor_idx": p_floor_idx,
		"death_frame": maxi(death_frame, 0),
	}


## 致死全局帧 → 层内帧：减 Telemetry floor_build 基准帧（FloorScene.setup 落行）。
## 无基准（headless/异常注入，基准 -1）回退原帧；差值为负（异常）clamp 0。
func floor_local_death_tick(fatal_frame: int) -> int:
	var build_frame := Telemetry.floor_build_frame()
	if build_frame < 0:
		return maxi(fatal_frame, 0)
	return maxi(fatal_frame - build_frame, 0)

## 致死原因只取最后一击，不用第一击/最大伤害/窗口总伤害替代。
func _cause_text(fatal_event: Dictionary) -> String:
	if fatal_event.is_empty():
		return "未知伤害"
	var source := String(fatal_event.get("source_name", "")).strip_edges()
	var attack := String(fatal_event.get("attack_name", "")).strip_edges()
	if source == "":
		return "未知伤害"
	if attack == "":
		attack = "攻击"
	return "%s的%s" % [source, attack]

## 生产侧局统计采集（build_report 的实参来源；测试可绕过直接注入）。
func collect_run_stats() -> Dictionary:
	return {
		"rooms": RunState.rooms_cleared,
		"kills": RunState.kills,
		"coins": RunState.coins,
		"floor": RunState.floor_idx,
		"gems": RunState.gems,
	}

## 新局复位：清窗口/报告/回放键/致命守卫，并清 Telemetry 会话计数（T18 重开口径）。
## T23 整合时建议在 start_run 调用；v1 由 DeathSummary 确认离场时触发。
func reset() -> void:
	_window.clear()
	current_report = {}
	replay_key = {}
	_fatal_handled = false
	Telemetry.reset_session()

func _on_player_hit_resolved(amount: int, fatal: bool, ctx: Dictionary) -> void:
	var frame := int(ctx.get("frame", Engine.get_physics_frames()))
	record_event(amount, frame, String(ctx.get("source_type", "")),
		String(ctx.get("source_id", "")), ctx.get("from", Vector2.ZERO),
		String(ctx.get("source_name", "")), String(ctx.get("attack_name", "")), fatal,
		int(ctx.get("remaining_hp", -1)), bool(ctx.get("roll_available", false)))
	if not fatal or suppressed or _fatal_handled:
		return
	_fatal_handled = true                   # once-per-fatal：同局只开一次
	Fx.request_player_death()               # J-A：0.3× 慢速 600ms 演出（判定已完成，前台门在 Fx）
	record_replay_key(RunState.run_seed, RunState.floor_idx, floor_local_death_tick(frame))
	current_report = build_report(collect_run_stats())
	if open_summary_override.is_valid():    # 测试/整合注入口（不受前台场景门限制）
		open_summary_override.call(current_report)
		return
	if is_gameplay_scene_active():
		_open_summary()

## 前台是否为游戏场景：current_scene 脚本/场景路径落在工具区（res://tests/、
## res://addons/）视为非游戏前台——gdUnit 无主场景（current_scene 为 null）或
## 冒烟自管生命周期，均不接管场景流。
func is_gameplay_scene_active() -> bool:
	var cs := get_tree().current_scene
	if cs == null:
		return false
	var s := cs.get_script() as Script
	var path := s.resource_path if s != null else cs.scene_file_path
	return not (path.begins_with("res://tests/") or path.begins_with("res://addons/"))

func _open_summary() -> void:
	var router := get_node_or_null("/root/SceneRouter")   # T23 可能未合入（同 T11 探测）
	if router != null and router.has_method("goto"):
		router.call_deferred("goto", "death")         # ROUTES 含 "death"（T23 契约）
		return
	# 本卡新建，路径恒存在。延迟到帧末：致命信号在物理回调内发出，
	# 同帧内立即换场景会先于其他监听者（训练房 1.5s 重启路径）把节点摘树。
	get_tree().change_scene_to_file.call_deferred(SUMMARY_SCENE)

## T18 移交：只删除首行精确匹配 m0 5 列表头的 telemetry.csv。
## 文件不存在时静默（首启常态）；空文件、当前 6 列、未知/损坏内容或读取
## 失败都 fail-safe 保留，因为它们不能被证明是可丢弃的遗留格式。
func purge_legacy_csv() -> void:
	if not FileAccess.file_exists(LEGACY_CSV):
		return
	var f := FileAccess.open(LEGACY_CSV, FileAccess.READ)
	if f == null:
		return
	var legacy_header_bytes := LEGACY_CSV_HEADER.to_utf8_buffer()
	var prefix := f.get_buffer(legacy_header_bytes.size())
	var is_legacy := prefix.size() == legacy_header_bytes.size()
	if is_legacy:
		for i in legacy_header_bytes.size():
			if prefix[i] != legacy_header_bytes[i]:
				is_legacy = false
				break
	if is_legacy and f.get_position() < f.get_length():
		var line_end := f.get_8()
		if line_end == 0x0d:
			is_legacy = f.get_position() < f.get_length() and f.get_8() == 0x0a
		else:
			is_legacy = line_end == 0x0a
	f = null
	if is_legacy:
		DirAccess.remove_absolute(LEGACY_CSV)
