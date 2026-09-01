class_name VictorySummary
extends Control
## 胜利结算全屏面板（m2-t18 F-1）：「守夜人凯旋」+ 通关统计 + 蓝晶全额入账 +
## 预告文案 + 任意键回主菜单。
## 生产路径：RunRoot 收 InterFloorFlow.victory_achieved → SceneRouter.goto("victory")
## 进入本场景，_ready 直接读 RunState 全量（英雄/层数/击杀/房数/金币/蓝晶/增益/武器）
## + Telemetry.session_summary()（受击/DPS 峰值/总时长）填充；任意键/点击确认 →
## 本局待结算蓝晶全额入账（RunState.gems → SaveSystem.add_gems，对照死亡 50% 口径）
## → DeathRecorder.reset()（清致死窗/遥测会话）→ 回主菜单。
##
## 【回主菜单路由（披露）】优先 /root/SceneRouter.goto("menu")；路由器缺席时按
## main_menu.tscn 是否存在回落（同 DeathSummary 手法）。测试经 exit_override 接缝
## 注入，不真跳场景。
##
## 【蓝晶口径】RunState 只读消费（本卡不改 run_state.gd）：胜利全额 = RunState.gems
## 整额，消费后写零防重复领取；T32 蓝晶结算收口时如增 settle_victory_gems() 可平移。

signal dismissed

## 回主菜单接缝（测试注入口）：有效时替代真实路由。
var exit_override: Callable = Callable()

var _confirmed := false               # 双击/双键守卫：蓝晶只入账一次

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP   # 全屏面板：挡住底层交互
	_fill()

func label_texts() -> Array[String]:
	var out: Array[String] = []
	for c in $Panel/Box.get_children():
		if c is Label:
			out.append(String(c.text))
	return out

func _fill() -> void:
	var summary := Telemetry.session_summary()
	var hero_row := GameDB.get_hero(RunState.hero_id)
	var hero_name := RunState.hero_id if hero_row.is_empty() \
		else String(hero_row.get("name", RunState.hero_id))
	$Panel/Box/Title.text = TrialPanelUI.trial_title_text("守夜人凯旋")   # M3-R-B 试炼局冠「每日试炼」
	TrialPanelUI.add_settlement_medal($Panel/Box)   # M3-R-B：试炼局标题徽标（倍率明细行归 R-C）
	$Panel/Box/Hero.text = "英雄：%s　　通关层数 %d / %d" % [
		hero_name, RunState.floor_idx, InterFloorFlow.VICTORY_FLOOR,
	]
	$Panel/Box/Stats.text = "击杀 %d　　房数 %d　　金币 %d\n时长 %s　　受击 %d 次　　DPS 峰值 %d\n增益 %d 个　　武器 %s" % [
		RunState.kills, RunState.rooms_cleared, RunState.coins,
		_format_time(float(summary.get("run_time", 0.0))),
		int(summary.get("hurt_count", 0)), int(summary.get("peak_dps", 0)),
		RunState.buffs.size(), _weapons_text(),
	]
	$Panel/Box/Gems.text = "蓝晶结算：+%d（通关全额入账）" % RunState.gems
	$Panel/Box/Preview.text = "更多内容与试炼模式即将开放"
	$Panel/Box/Hint.text = "—— 按任意键返回 ——"

func _format_time(seconds: float) -> String:
	var s := maxi(0, int(seconds))
	return "%d:%02d" % [s / 60, s % 60]

## 双槽武器中文名（空槽「空手」；GameDB 无此行 fail-soft回落原始 id）。
func _weapons_text() -> String:
	var names: Array[String] = []
	for wid in RunState.weapons:
		var id := String(wid)
		if id.is_empty():
			names.append("空手")
			continue
		var row := GameDB.get_weapon(id)
		names.append(id if row.is_empty() else String(row.get("name", id)))
	return "、".join(names)

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

## 确认结算：蓝晶全额入账（一次性）→ 复位记录器 → 广播 dismissed → 回主菜单。
## m2-t31：确认即终局结算点——图鉴跨局计数器（CodexSystem）快照落盘（存档 v2）。
func _confirm() -> void:
	if _confirmed:
		return
	_confirmed = true
	var awarded := RunState.gems            # GDD §14：胜利全额（死亡口径为 50%）
	RunState.gems = 0                       # 本局待结算蓝晶消费归零（防重复领取）
	if awarded > 0:
		SaveSystem.add_gems(awarded)
	var codex: Node = get_node_or_null("/root/CodexSystem")
	if codex != null and codex.has_method("persist_counters"):
		codex.persist_counters()
	DeathRecorder.reset()
	dismissed.emit()
	_exit_to_menu()

func _exit_to_menu() -> void:
	if exit_override.is_valid():
		exit_override.call()                                # 测试/整合注入口
		return
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and router.has_method("goto"):
		router.call("goto", "menu")
		return
	if ResourceLoader.exists("res://ui/main_menu.tscn"):
		get_tree().change_scene_to_file("res://ui/main_menu.tscn")
		return
	get_tree().change_scene_to_file("res://ui/hero_select.tscn")   # 兜底（现存场景）
