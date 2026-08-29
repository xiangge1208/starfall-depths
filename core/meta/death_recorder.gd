extends Node
## 死亡记录器（m1-t22）：滑动窗口记录玩家受击事件 + 致死时生成 DeathReport 并打开死亡结算。
## autoload 名 "DeathRecorder"（project.godot 注册在 Telemetry 之后，命名规则同 GameDB/RunState）。
##
## 【v1 归因限制——有意披露】EventBus.player_damaged(amount, fatal) 不携带来源，
## player.gd 不在本卡改动范围，故窗口事件 source_type/source_id/pos 为 v1 占位空值；
## 致死原因 v1 退化为「最近 3s（180t 窗口）受击次数 + 总伤害」的因果链回顾，
## 完整的来源 plumbing（弹幕来源/敌人 id/位置）落 M1-T24 或整合卡（见任务简报）。
##
## 致死接线：player_damaged(fatal=true) → build_report(collect_run_stats()) →
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
## 会产生烂行——启动时删除一次（Telemetry 首次落盘会以新表头重建）。
##
## 【结算口径】蓝晶死亡保留 50%（GDD §14/§19）：gems_awarded = floor(RunState.gems / 2)，
## 由 DeathSummary 确认时经 SaveSystem.add_gems 入账。reset() 同时清 Telemetry 会话
## 计数（T18 预留的重开口径）；T23 的 start_run 整合时可改为开局调用 reset。

const WINDOW_TICKS := 180   # 3s @60fps：受击事件保留窗
const SUMMARY_SCENE := "res://ui/death_summary.tscn"
const LEGACY_CSV := "user://telemetry.csv"

## 致死处理总开关（默认接管）。工具/整合场景可显式置 true 完全忽略致命。
var suppressed := false
## 开结算接缝（测试注入口，同 EventRoom.apply_effect 模式）：有效时替代真实跳转。
var open_summary_override: Callable = Callable()
## 最近一次致死生成的报告（DeathSummary 场景 _ready 读取；reset 清空）。
var current_report: Dictionary = {}

var _window: Array[Dictionary] = []   # {frame, amount, source_type, source_id, pos}
var _fatal_handled := false           # once-per-fatal：同局第二次致命不再重复开

func _ready() -> void:
	purge_legacy_csv()                        # T18 移交：清 m0 的 5 列烂行文件（一次性）
	EventBus.player_damaged.connect(_on_player_damaged)

## 受击入窗：frame 显式传入（测试可注入历史帧；信号路径传当前物理帧）。
## v1：source_type/source_id/pos 占位空值——归因限制见文件头披露。
func record_event(amount: int, frame: int, source_type := "", source_id := "", pos := Vector2.ZERO) -> void:
	_window.append({
		"frame": frame,
		"amount": amount,
		"source_type": source_type,
		"source_id": source_id,
		"pos": pos,
	})
	while not _window.is_empty() and frame - int(_window[0]["frame"]) > WINDOW_TICKS:
		_window.remove_at(0)                  # 滑动淘汰：超出 180t 的最老事件滚出

func window() -> Array[Dictionary]:
	return _window.duplicate()

## 组装 DeathReport：stats（run_stats 注入 + Telemetry 会话）+ cause + window。
## run_stats 缺键按 0 处理（纯函数口径，测试注入任意子集均安全）。
func build_report(run_stats: Dictionary) -> Dictionary:
	var gems := int(run_stats.get("gems", 0))
	var summary := Telemetry.session_summary()
	var total := 0
	for ev in _window:
		total += int(ev["amount"])
	return {
		"stats": {
			"rooms": int(run_stats.get("rooms", 0)),
			"kills": int(run_stats.get("kills", 0)),
			"coins": int(run_stats.get("coins", 0)),
			"floor": int(run_stats.get("floor", 0)),
			"gems": gems,
			"gems_awarded": int(floor(gems / 2.0)),   # §14/§19：死亡保留 50%（floor）
			"hurt_count": int(summary.get("hurt_count", 0)),
			"run_time": float(summary.get("run_time", 0.0)),
		},
		"cause": _cause_text(total),
		"window": window(),
	}

## 致死原因 v1：窗口空 → 泛化文案；否则最近 3s 受击次数与总伤害（归因限制见文件头）。
func _cause_text(total_damage: int) -> String:
	if _window.is_empty():
		return "未记录到致命受击——守夜人耗尽了最后一丝力气"
	return "最近 3 秒受击 %d 次，共 %d 点伤害" % [_window.size(), total_damage]

## 生产侧局统计采集（build_report 的实参来源；测试可绕过直接注入）。
func collect_run_stats() -> Dictionary:
	return {
		"rooms": RunState.rooms_cleared,
		"kills": RunState.kills,
		"coins": RunState.coins,
		"floor": RunState.floor_idx,
		"gems": RunState.gems,
	}

## 新局复位：清窗口/报告/致命守卫，并清 Telemetry 会话计数（T18 重开口径）。
## T23 整合时建议在 start_run 调用；v1 由 DeathSummary 确认离场时触发。
func reset() -> void:
	_window.clear()
	current_report = {}
	_fatal_handled = false
	Telemetry.reset_session()

func _on_player_damaged(amount: int, fatal: bool) -> void:
	record_event(amount, Engine.get_physics_frames())
	if not fatal or suppressed or _fatal_handled:
		return
	_fatal_handled = true                   # once-per-fatal：同局只开一次
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

## T18 移交：删除 m0 遗留 telemetry.csv（5 列头与 6 列头混写即烂行）。
## 文件不存在时静默（首启常态）；Telemetry 首次 flush 会以新表头重建。
func purge_legacy_csv() -> void:
	if FileAccess.file_exists(LEGACY_CSV):
		DirAccess.remove_absolute(LEGACY_CSV)
