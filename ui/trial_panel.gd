class_name TrialPanelUI
extends Control
## M3-R-B 每日试炼面板（试炼规格 §5/§6）：主菜单覆盖层（任意场景可实例化，不进
## SceneRouter 路由，同 settings_panel 手法）。内容 = 今日日期 + 因子卡 ×2（图标+名称
## +文案，数据源 GameDB.trials + TrialSystem.pick_factors(today)）+ 今日最佳 + 历史最近
## 10 条（日期/角色/最深/用时/胜负标记）+「开 始」+「返 回」；打开即刷新（open→refresh）。
##
## 「开 始」= RunState.arm_trial(今日) + SceneRouter.goto("hero_select")（选角经
## RunState.select_hero 消费 pending 转 start_trial_run——hero_select 零改动）；router
## 缺席时只 arm 不路由不崩（同 main_menu 路由守卫手法）。返回 = 只隐藏面板。
##
## 键盘/触屏：open() 焦点落「开 始」，Tab/↑↓ 导航、Enter 确认（容器自动焦点邻接）；
## 按钮可直接点按。测试注入缝：records（TrialRecords 临时路径档）、router（SceneRouter
## 替身）；缺省兜底 TrialRecords.new() / 探测 /root/SceneRouter。
##
## 共用展示装配（本面板因子卡 + HUD 因子角标 + 结算徽标三处单一出处）：
## - factor_display(id)：名称/文案/图标路径三元组（表外 id fail-soft 回显，不崩）；
## - add_settlement_medal / trial_title_text：死亡/胜利结算面板「每日试炼」徽标嵌入
##   缝（规格 §6；death_summary/victory_summary 各 ≤5 行调用，倍率明细行归 R-C）。

const MEDAL_PATH := "res://art/generated/fx/trial_medal.png"                 # 结算徽标素材（在盘）
const FACTOR_ICON_FMT := "res://art/generated/trials/factor_%s.png"          # 因子图标（在盘 ×8）
const HISTORY_ROWS := TrialRecords.HISTORY_ROWS   # 历史最近 10 条（规格 §5 UI）

var records: TrialRecords = null   # 测试注入缝（临时路径档）；_ready 兜底 TrialRecords.new()
var router: Node = null            # 测试注入缝（SceneRouter 替身）；_ready 兜底探测

var _runtime_router: Node = null   # router 注入优先，兜底 /root/SceneRouter（守卫同 main_menu）
var _today := ""                   # open/refresh 缓存的业务日（「开始」arm 用同一日期）

@onready var _date_label: Label = $Center/Panel/Margin/Rows/Date
@onready var _factors_box: VBoxContainer = $Center/Panel/Margin/Rows/Factors
@onready var _best_label: Label = $Center/Panel/Margin/Rows/Best
@onready var _history_head: Label = $Center/Panel/Margin/Rows/History
@onready var _history_grid: GridContainer = $Center/Panel/Margin/Rows/HistoryGrid
@onready var _start_btn: Button = $Center/Panel/Margin/Rows/Buttons/StartBtn
@onready var _back_btn: Button = $Center/Panel/Margin/Rows/Buttons/BackBtn


func _ready() -> void:
	if records == null:
		records = TrialRecords.new()
	_runtime_router = router if router != null else get_node_or_null("/root/SceneRouter")
	_start_btn.pressed.connect(_on_start_pressed)
	_back_btn.pressed.connect(_on_back_pressed)


## 打开面板：刷新（日期/因子/最佳/历史）+ 焦点落「开 始」（键盘可达；Tab 导航「返 回」）。
func open() -> void:
	refresh()
	visible = true
	_start_btn.grab_focus()


## 刷新全部内容（打开时调用；也可外部直调驱动测试）。
func refresh() -> void:
	var trial := TrialSystem.new()
	_today = trial.today_date()
	_date_label.text = "日期 %s（每日 05:00 刷新）" % _today
	_rebuild_factors(trial.pick_factors(_today))
	var table := records.load_records()
	var today_best: Variant = (table["daily_best"] as Dictionary).get(_today, {})
	_best_label.text = best_line(today_best if today_best is Dictionary else {})
	_fill_history(recent_from(table, HISTORY_ROWS))


## 返回：只隐藏（实例保留，主菜单仍在底层；与 settings_panel 同语义）。
func _on_back_pressed() -> void:
	visible = false


## 开始：arm 今日 + 路由选角（试炼转让链第一跳；router 缺席只 arm 不崩）。收起面板。
func _on_start_pressed() -> void:
	if _today.is_empty():                     # 未 open 直按时兜底取业务日
		_today = TrialSystem.new().today_date()
	RunState.arm_trial(_today)
	if _runtime_router != null and _runtime_router.has_method("goto"):
		_runtime_router.call("goto", "hero_select")
	visible = false


# ---------------------------------------------------------------- 因子卡

func _rebuild_factors(factors: Array[String]) -> void:
	for c in _factors_box.get_children():
		c.free()
	for info in factor_displays(factors):
		_factors_box.add_child(_make_factor_card(info))


func _make_factor_card(info: Dictionary) -> HBoxContainer:
	var card := HBoxContainer.new()
	card.add_theme_constant_override("separation", 4)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(14, 14)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if ResourceLoader.exists(String(info["icon"])):
		icon.texture = load(String(info["icon"]))
	icon.tooltip_text = "%s：%s" % [info["name"], info["desc"]]
	card.add_child(icon)
	var col := VBoxContainer.new()
	var name_label := Label.new()
	name_label.text = String(info["name"])
	name_label.add_theme_font_size_override("font_size", 12)
	var desc_label := Label.new()
	desc_label.text = String(info["desc"])
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.modulate = Color(1, 1, 1, 0.72)
	col.add_child(name_label)
	col.add_child(desc_label)
	card.add_child(col)
	return card


# ---------------------------------------------------------------- 历史/最佳文案

func _fill_history(rows: Array) -> void:
	for c in _history_grid.get_children():
		c.free()
	if rows.is_empty():
		_history_head.text = "历史：暂无记录"
		return
	_history_head.text = "历史（最近 %d 条）" % rows.size()
	# 双列布局（480×270 内收实测：单列 11 行面板 305px 超界，双列 ~200px）——
	# 列优先：左列最新 5 条、右列次新 5 条，每列仍新在上。
	var half := int(ceil(rows.size() / 2.0))
	for i in half:
		_history_grid.add_child(_history_cell(history_line(rows[i])))
		if i + half < rows.size():
			_history_grid.add_child(_history_cell(history_line(rows[i + half])))


func _history_cell(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	return l


## 历史区全文（表头 + 各行，自上而下、左列先于右列；测试/走查看口）。
func history_text() -> String:
	var out: Array[String] = [_history_head.text]
	for c in _history_grid.get_children():
		out.append((c as Label).text)
	return "\n".join(out)


## 最近 n 条取自给定表（不重读盘；测试可注入）。
func recent_from(table: Dictionary, n: int) -> Array:
	var records_arr: Array = table["records"]
	var out := records_arr.slice(maxi(records_arr.size() - maxi(n, 0), 0))
	out.reverse()
	return out


## 历史单行：`08-30 先锋 第2层 17:23 胜`（日期缩 MM-DD 省宽；表外角色回显 id fail-soft）。
static func history_line(rec: Dictionary) -> String:
	var date := String(rec.get("date", ""))
	var hero_id := String(rec.get("hero_id", ""))
	var hero_row := GameDB.get_hero(hero_id)
	var hero := hero_id if hero_row.is_empty() else String(hero_row.get("name", hero_id))
	return "%s %s 第%d层 %s %s" % [
		date.substr(mini(5, date.length())), hero, int(rec.get("deepest_floor", 0)),
		format_time(int(rec.get("clear_time_s", 0))),
		"胜" if bool(rec.get("victory", false)) else "负",
	]


## 今日最佳行（规格 §5：深层数 + 最短用时；无记录日回落「暂无」）。
static func best_line(best: Dictionary) -> String:
	if best.is_empty():
		return "今日最佳：暂无记录"
	return "今日最佳：第 %d 层 · %s" % [
		int(best.get("deepest_floor", 0)), format_time(int(best.get("clear_time_s", 0)))]


## 用时 mm:ss（记录秒为非负整数口径；异常负值按 0 处理）。
static func format_time(seconds: int) -> String:
	var s := maxi(seconds, 0)
	return "%d:%02d" % [s / 60, s % 60]


# ---------------------------------------------------------------- 共用展示装配（含 HUD/结算）

## 因子展示三元组（面板卡与 HUD 角标共用；数据源唯一 = GameDB.trials）：表外 id
## fail-soft 回显（name=id、desc 空、图标路径仍按格式拼——调用方 ResourceLoader.exists 兜底）。
static func factor_display(id: String) -> Dictionary:
	var row: Dictionary = GameDB.trials.get(id, {})
	return {
		"name": String(row.get("name", id)),
		"desc": String(row.get("desc", "")),
		"icon": FACTOR_ICON_FMT % id,
	}


## 批量装配（保序）：factors id 数组 → 三元组数组。
static func factor_displays(factors: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in factors:
		out.append(factor_display(id))
	return out


## 结算面板「每日试炼」徽标（规格 §6 嵌入缝；死亡/胜利结算各 ≤5 行调用）：
## is_trial_run 时在结算 VBox 首位插入 trial_medal 徽标。幂等（name 守卫，open 重复
## 调用不重复插）；普通局/box 缺席为无操作。倍率明细行（×1.5 结算数学）归 R-C。
static func add_settlement_medal(box: Node) -> bool:
	if box == null or not RunState.is_trial_run or box.has_node("TrialMedal"):
		return false
	var medal := TextureRect.new()
	medal.name = "TrialMedal"
	medal.texture = load(MEDAL_PATH)
	medal.custom_minimum_size = Vector2(14, 14)
	medal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(medal)
	box.move_child(medal, 0)
	return true


## 结算标题文案：试炼局冠「每日试炼 · 」（普通局原样返回）。
static func trial_title_text(base: String) -> String:
	return ("每日试炼 · %s" % base) if RunState.is_trial_run else base


# ---------------------------------------------------------------- 结算接线（M3-R-C）

## 结算写入注入缝（测试）：临时路径 TrialRecords；null → 默认 user:// 档（生产路径）。
static var settlement_records: TrialRecords = null

## 试炼结算数学（规格 §4 单点展示口径）：死亡保底 75%（= 50% × 1.5，floor）；
## 胜利/放弃 ×1.5 floor。权威结算在 RunState.settle_death_gems / settle_victory_gems
## （同式），等价性由 test_trial_settle 钉死——本助手只服务结算面板明细行。
static func trial_award(base_gems: int, death: bool) -> int:
	return int(floor(base_gems * 0.75)) if death else int(floor(base_gems * 1.5))


## 结算蓝晶行文案（规格 §6 倍率明细行）：试炼局「基础 X × 1.5 = Y」/死亡「保底 75%」
## 口径（X = 倍率前值，Y = 实际入档额）；普通局返回空串——站点保留既有文案不改动。
static func settlement_gems_line(base_gems: int, death: bool) -> String:
	if not RunState.is_trial_run:
		return ""
	if death:
		return "蓝晶结算：+%d（试炼保底 75%%：基础 %d 的 3/4）" % [trial_award(base_gems, true), base_gems]
	return "蓝晶结算：+%d（基础 %d × 1.5 = %d）" % [
		trial_award(base_gems, false), base_gems, trial_award(base_gems, false)]


## 结算写入点（R-B 移交②收敛单点，规格 §5「每次试炼局结束追加 1 条」）：死亡确认 /
## 胜利确认 / 放弃入口三路各 1 行调用。试炼局：records 追加 1 条（date = 开局业务日
## 快照 RunState.trial_date——局可跨业务日不漂移；gems_earned = 实际入档额；
## clear_time_s = run_time_frames/60，60Hz 帧计换算禁墙钟；factors = RunState.
## trial_factors）+ record_trial_completed（EventBus.trial_completed 每局至多一次 +
## 试炼成就轮询）。普通局无操作（records 只收试炼局）。返回是否入档。
static func settlement_record(gems_earned: int, victory: bool) -> bool:
	if not RunState.is_trial_run:
		return false
	RunState.record_trial_completed()
	var recs: TrialRecords = settlement_records if settlement_records != null \
		else TrialRecords.new()
	return recs.append_record({
		"date": RunState.trial_date,
		"hero_id": RunState.hero_id,
		"deepest_floor": RunState.floor_idx,
		"clear_time_s": int(RunState.run_time_frames / 60.0),
		"gems_earned": gems_earned,
		"victory": victory,
		"factors": RunState.trial_factors,
	})


# ---------------------------------------------------------------- HUD 因子角标（规格 §6）

## HUD 层数旁因子小图标行（挂 HUD 右上层数列——现版 HUD 层数显示在右上，角标随层数
## 旁而置）。sync(run) 供 HUD._apply_top_right 每帧调：零稳态分配（有效 id 序列未变
## 即早退，无逐帧节点/数组分配，硬约束「HUD 角标处禁逐帧分配」）。tooltip = 名称：文案
## （悬浮显示；触屏长按显示可延至 J-D/走查）。
class FactorBadges extends HBoxContainer:
	var _ids: Array[String] = []

	func _init() -> void:
		name = "TrialBadges"
		add_theme_constant_override("separation", 2)
		size_flags_horizontal = Control.SIZE_SHRINK_END   # 右列右对齐（与层数标签同列）
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	## run 为 RunState（或同形 Node/测试替身）：is_trial_run 且 trial_factors 非空时
	## 显示至多 2 枚 factor_<id>.png；普通局/空表不显示。
	func sync(run: Node) -> void:
		var raw: Variant = run.get("trial_factors") if run != null else null
		var count := 0
		if run != null and bool(run.get("is_trial_run")) and raw is Array:
			count = mini((raw as Array).size(), 2)
		var changed := count != _ids.size()
		if not changed:
			for i in count:
				if String(raw[i]) != _ids[i]:
					changed = true
					break
		if not changed:
			return                                   # 稳态早退：零分配
		_ids.clear()
		for i in count:
			_ids.append(String(raw[i]))
		for c in get_children():
			c.free()
		for id: String in _ids:
			add_child(_make_badge(id))

	func _make_badge(id: String) -> TextureRect:
		var info := TrialPanelUI.factor_display(id)
		var icon := TextureRect.new()
		if ResourceLoader.exists(String(info["icon"])):
			icon.texture = load(String(info["icon"]))
		icon.custom_minimum_size = Vector2(10, 10)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.tooltip_text = "%s：%s" % [info["name"], info["desc"]]
		# 悬浮显示文案：仅小图标本体收鼠标（PASS 不拦截后续 UI）；触屏长按延后 J-D
		icon.mouse_filter = Control.MOUSE_FILTER_PASS
		return icon
