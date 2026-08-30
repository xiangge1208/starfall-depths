class_name DeathSummary
extends Control
## 死亡结算全屏面板（m1-t22）：「守夜人陨落」+ 本局统计 + 致死原因回顾 + 蓝晶死亡保留 50%。
## 生产路径：DeathRecorder 致死时 change_scene/SceneRouter.goto("death") 进入本场景，
## _ready 直接读 DeathRecorder.current_report 填充；任意键/点击确认 →
## RunState.settle_death_gems() 一次性消费本局蓝晶 → SaveSystem.add_gems 入账持久化 →
## DeathRecorder.reset()（清窗口/报告/Telemetry 会话）→ 回主菜单。
##
## 【回主菜单路由（披露）】优先 /root/SceneRouter.goto("menu")（T23 可能未合入，
## get_node_or_null 守卫，同 T11 对 RunState 的探测模式）；SceneRouter 缺席时按
## main_menu.tscn 是否存在回落（T23 未合入则退到现存的 hero_select.tscn）。
## 测试经 exit_override 接缝注入，不真跳场景。

signal dismissed

## 回主菜单接缝（测试注入口）：有效时替代真实路由。
var exit_override: Callable = Callable()

var _report: Dictionary = {}
var _confirmed := false               # 双击/双键守卫：蓝晶只入账一次

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP   # 全屏面板：挡住底层交互
	if not DeathRecorder.current_report.is_empty():
		open(DeathRecorder.current_report)     # 场景直入时从记录器取报告

## 填充面板（测试可直接注入报告）。
func open(report: Dictionary) -> void:
	_report = report
	_fill()

func label_texts() -> Array[String]:
	var out: Array[String] = []
	for c in $Panel/Box.get_children():
		if c is Label:
			out.append(String(c.text))
	return out

func _fill() -> void:
	var stats: Dictionary = _report.get("stats", {})
	$Panel/Box/Title.text = "守夜人陨落"
	$Panel/Box/Stats.text = "房数 %d　　击杀 %d　　金币 %d　　层数 %d\n时长 %s　　受击 %d 次　　DPS 峰值 %d" % [
		int(stats.get("rooms", 0)), int(stats.get("kills", 0)),
		int(stats.get("coins", 0)), int(stats.get("floor", 0)),
		_format_time(float(stats.get("run_time", 0.0))), int(stats.get("hurt_count", 0)),
		int(stats.get("peak_dps", 0)),
	]
	$Panel/Box/Cause.text = "致死原因：%s" % str(_report.get("cause", "未知"))
	var fatal_event: Dictionary = _report.get("fatal_event", {})
	var hp_text := "未知" if int(fatal_event.get("remaining_hp", -1)) < 0 \
		else str(int(fatal_event.get("remaining_hp", 0)))
	var roll_text := "可用" if bool(fatal_event.get("roll_available", false)) else "不可用"
	$Panel/Box/Cause.text += "\n致死后剩余生命：%s　当时翻滚：%s" % [hp_text, roll_text]
	$Panel/Box/Gems.text = "蓝晶结算：+%d（死亡保留 50%%）" % _gems_awarded()
	$Panel/Box/Hint.text = "—— 按任意键返回 ——"

func _format_time(seconds: float) -> String:
	var s := maxi(0, int(seconds))
	return "%d:%02d" % [s / 60, s % 60]

## 入账蓝晶：优先报告中的 gems_awarded；报告缺 stats 时按 RunState.gems 现算 floor/2。
func _gems_awarded() -> int:
	var stats: Dictionary = _report.get("stats", {})
	if stats.has("gems_awarded"):
		return int(stats["gems_awarded"])
	return int(floor(int(stats.get("gems", RunState.gems)) / 2.0))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
	else:
		return
	get_viewport().set_input_as_handled()
	_confirm()

## 确认结算：蓝晶入账（一次性）→ 复位记录器 → 广播 dismissed → 回主菜单。
func _confirm() -> void:
	if _confirmed:
		return
	_confirmed = true
	var awarded := RunState.settle_death_gems()
	if awarded > 0:
		SaveSystem.add_gems(awarded)
	DeathRecorder.reset()
	dismissed.emit()
	_exit_to_menu()

func _exit_to_menu() -> void:
	if exit_override.is_valid():
		exit_override.call()                                # 测试/整合注入口
		return
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and router.has_method("goto"):
		router.call("goto", "menu")                         # T23 已合入：正式路由
		return
	if ResourceLoader.exists("res://ui/main_menu.tscn"):
		get_tree().change_scene_to_file("res://ui/main_menu.tscn")
		return
	get_tree().change_scene_to_file("res://ui/hero_select.tscn")   # T23 未合入兜底（现存场景）
