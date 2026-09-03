class_name AchievementsPage
extends Control
## 成就展示页（m4p-u1）：24 条成就逐卡渲染——结构复刻 codex.tscn（返回钮 + 网格 +
## 详情区，像素中文字体 12px，480×270 视口内）。数据源 = AchievementSystem.defs()
## （公开访问器，DEFS 常量不开裸）+ SaveSystem 持久解锁集（经 ach_system.
## unlocked_achievements() 同口径代理）。
## 状态色：已解锁=金框亮名 ✓ / 未解锁=灰框灰名 锁标。每卡：图标位
## （art/generated/ui/icon_achievement.png，缺图回落色块——同 codex 回落口径）+
## 名称 + 状态/进度 + 奖励蓝晶。进度口径：state_threshold 类显示 cur/goal
## （经 _state_value 现读，与判定引擎同一解析）；会话/事件类无可持久进度显示「??？」。
## 详情区：点击卡片显示 条件中文合成 + 当前进度 + 奖励（defs 字段数据驱动合成，
## 不另造第二套文案表）。顶部「已解锁 n / 24」。
## 纯展示：解锁状态/进度每次 open/入树时由 AchievementSystem 现读，不持有持久状态。
## 关闭按钮 → SceneRouter.goto("menu")（路由守卫同 codex 手法：缺席不动作不崩）。
## 手动验证：godot --path . res://ui/achievements.tscn（或主菜单「成就」按钮进入）。

const GRID_COLUMNS := 3
const CELL_MIN := Vector2(140, 58)   # 12px 基准：图标行 + 状态行 + 蓝晶行；24 卡 / 3 列 = 纵向滚动
const CARD_BG := Color(0.07, 0.08, 0.1, 0.96)
const LOCKED_COLOR := Color(0.45, 0.47, 0.52)
const GOLD_COLOR := Color(1.0, 0.84, 0.35)          # 已解锁：金色名/框（主菜单点亮卡）
const GEM_COLOR := Color(0.55, 0.80, 0.95)          # 蓝晶奖赏（同 talents 口径）
const ICON_PATH := "res://art/generated/ui/icon_achievement.png"
const PROGRESS_UNKNOWN := "??？"                     # 无可持久进度的判定类型占位
const DETAIL_DEFAULT := "点击成就查看详情"

## trigger 名 → 条件中文（附录 K 判定触发源）；纯触发/计数源共用。
const TRIGGER_DESC := {
	"boss_slain": "击败 Boss", "floor_reached": "抵达新层", "victory": "通关",
	"resonance": "引发共鸣", "prop_destroyed": "破坏可破坏物", "roll_dodge": "翻滚闪避",
	"floor_cleared": "通过楼层", "enemy_damaged": "命中敌人", "enemy_killed": "击杀敌人",
}
## state_threshold 状态源 → 计数口径中文。
const SOURCE_DESC := {
	"counter:crafts_total": "熔铸次数", "counter:challenge_rooms_total": "挑战房通关数",
	"counter:trials_total": "试炼完成数", "save:codex_seen": "图鉴见录武器",
	"save:unlocked_heroes": "已解锁角色", "save:purchased_talents": "已购天赋",
}
## composite cond src → 条件中文（session 计数 / run 字段 / 信号参数）。
const COND_DESC := {
	"session:remote_fire": "本层远程开火", "session:melee_swings": "近战挥击",
	"session:shots": "射击数", "session:crits": "暴击", "session:deaths": "死亡",
	"session:hurt_window": "受击", "session:heart_pickups": "拾取红心",
	"session:props": "破坏物", "session:dodges": "翻滚",
	"run:coins": "携带金币", "run:run_time_frames": "通关用时",
	"sig:is_elite": "击杀精英", "sig:weapon_category": "武器类别",
}

var ach_system: Node = null   # 测试注入缝；_ready 兜底探测 /root/AchievementSystem
var _router: Node = null      # /root/SceneRouter 探测缓存
var _cells: Array[String] = []    # 渲染顺序的成就 id（defs 表序 = 附录 K 稳定顺序）
var _defs_by_id: Dictionary = {}  # id → def（详情/进度查询）

@onready var _grid: GridContainer = $Center/Panel/VBox/Scroll/Grid
@onready var _summary: Label = $Center/Panel/VBox/Summary
@onready var _detail: Label = $Center/Panel/VBox/Detail

func _ready() -> void:
	if ach_system == null:
		ach_system = get_node_or_null("/root/AchievementSystem")
	_router = get_node_or_null("/root/SceneRouter")
	$Center/Panel/VBox/CloseBtn.pressed.connect(_on_close_pressed)
	_rebuild()

## 入树即渲染（路由场景整页打开）；解锁状态变化后重开本页自动刷新。
func open() -> void:
	_rebuild()

func _rebuild() -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.free()   # 立即释放：重建点（_ready/open）不在卡片信号回调内，无悬空引用；
		# 摘除后 queue_free 不再入帧队列（不在树）→ 会漏孤儿节点，故不用 codex 的排毁写法
	_cells.clear()
	_defs_by_id.clear()
	if ach_system != null:
		for def: Dictionary in ach_system.defs():
			var id := String(def.get("id", ""))
			if not id.is_empty():
				_cells.append(id)
				_defs_by_id[id] = def
	for id in _cells:
		_grid.add_child(_make_cell(id))
	_summary.text = "已解锁 %d / %d" % [unlocked_count(), _cells.size()]
	_detail.text = DETAIL_DEFAULT

func _make_cell(id: String) -> Button:
	var def: Dictionary = _defs_by_id.get(id, {})
	var unlocked := _is_unlocked(id)
	var border := GOLD_COLOR if unlocked else LOCKED_COLOR
	var cell := Button.new()
	cell.custom_minimum_size = CELL_MIN
	cell.clip_contents = true   # 长名称/进度文案裁在卡内，不溢出压邻卡
	cell.add_theme_stylebox_override("normal", _cell_style(border))
	cell.add_theme_stylebox_override("hover", _cell_style(border.lightened(0.15)))
	cell.add_theme_stylebox_override("pressed", _cell_style(border.darkened(0.15)))
	cell.pressed.connect(_show_detail.bind(id))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 点击穿透到卡片按钮
	cell.add_child(box)
	# 名称行：图标位 + 名称。已解锁金亮 ✓；未解锁灰 + 锁标。
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 2)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_row)
	name_row.add_child(_make_icon(unlocked))
	var mark := "✓ " if unlocked else "锁 "
	var name_l := _label(mark + String(def.get("name", id)), 12,
		GOLD_COLOR if unlocked else LOCKED_COLOR)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_row.add_child(name_l)
	# 状态行：已解锁金字；未解锁灰 + 进度（state_threshold cur/goal，其余 ??？）
	var status := _label("已解锁" if unlocked else _progress_text(def), 12,
		GOLD_COLOR if unlocked else LOCKED_COLOR)
	box.add_child(status)
	# 奖励行：蓝晶原值（附录 G.1），双色常亮（解锁与否奖励不变）
	box.add_child(_label("+%d 蓝晶" % int(def.get("gems", 0)), 12, GEM_COLOR))
	return cell

## 图标：art/generated/ui/icon_achievement.png（缺图回落暗色占位块——同 codex/
## training_room 回落口径，接线存量零引用图标资产）。
func _make_icon(unlocked: bool) -> Control:
	if ResourceLoader.exists(ICON_PATH):
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(14, 14)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.modulate = GOLD_COLOR if unlocked else Color(0.6, 0.6, 0.65, 1.0)
		icon.texture = load(ICON_PATH)
		return icon
	var ph := ColorRect.new()
	ph.custom_minimum_size = Vector2(14, 14)
	ph.color = Color(0.16, 0.18, 0.22, 1.0)
	return ph

## 进度口径：state_threshold（持久状态源）→ cur/goal（与判定引擎同走 _state_value
## 解析）；event_once/event_count/composite 无可持久进度（会话口径随局清零）→ 「??？」。
func _progress_text(def: Dictionary) -> String:
	if String(def.get("type", "")) != "state_threshold":
		return PROGRESS_UNKNOWN
	if ach_system == null or not ach_system.has_method("_state_value"):
		return PROGRESS_UNKNOWN
	var cur := int(ach_system._state_value(String(def.get("source", ""))))
	return "%d/%d" % [cur, int(def.get("goal", 0))]

## 详情区：条件中文合成（defs 字段数据驱动）+ 当前进度 + 奖励蓝晶。
func _show_detail(id: String) -> void:
	var def: Dictionary = _defs_by_id.get(id, {})
	if def.is_empty():
		_detail.text = DETAIL_DEFAULT
		return
	_detail.text = "%s · %s · +%d 蓝晶" % [
		String(def.get("name", id)), _cond_text(def), int(def.get("gems", 0))]

## 条件中文：按判定类型合成（与成就引擎附录 K 判定字段一一对应）。
func _cond_text(def: Dictionary) -> String:
	var trigger := String(def.get("trigger", ""))
	var base := String(TRIGGER_DESC.get(trigger, trigger))
	match String(def.get("type", "")):
		"event_once":
			return base + _pred_suffix(def)
		"event_count":
			return "%s 累计 %d 次" % [base, int(def.get("goal", 0))]
		"state_threshold":
			var text := "%s达 %d" % [String(SOURCE_DESC.get(String(def.get("source", "")),
				String(def.get("source", "")))), int(def.get("goal", 0))]
			var cur := _progress_text(def)
			if cur == PROGRESS_UNKNOWN:
				return text
			return "%s（当前 %s）" % [text, cur]
		"composite":
			var parts: Array[String] = []
			for cond: Dictionary in def.get("conds", [] as Array):
				parts.append(_cond_desc(cond))
			return "%s：%s" % [base + _pred_suffix(def), " 且 ".join(parts)]
	return base

## 触发谓词后缀（floor_idx 层号条件；其余字段不合成直接省略）。
func _pred_suffix(def: Dictionary) -> String:
	var pred: Dictionary = def.get("pred", {})
	if pred.is_empty() or String(pred.get("field", "")) != "floor_idx":
		return ""
	match String(pred.get("op", "")):
		"==":
			return "（第 %d 层）" % int(pred.get("value", 0))
		">=":
			return "（第 %d 层起）" % int(pred.get("value", 0))
	return ""

## 单条 composite 条件 → 中文（比值条件走百分比口径，帧数条件换算分钟）。
func _cond_desc(cond: Dictionary) -> String:
	var src := String(cond.get("src", ""))
	var op := String(cond.get("op", ""))
	var value := int(cond.get("value", 0))
	if op == "ratio_gt":
		var part := String(COND_DESC.get("session:" + src.substr(6).get_slice(",", 0), src))
		return "%s>%d%%" % [part, value]
	var desc := String(COND_DESC.get(src, src))
	if src == "run:run_time_frames":
		return "%s<%d 分钟" % [desc, value / 3600]
	match op:
		"==":
			return "%s为 %d" % [desc, value]
		">=":
			return "%s≥%d" % [desc, value]
		">":
			return "%s>%d" % [desc, value]
		"<":
			return "%s<%d" % [desc, value]
	return "%s%s%d" % [desc, op, value]

func _is_unlocked(id: String) -> bool:
	if ach_system == null:
		return false   # 缺席兜底（fail-closed 同成就引擎口径）：按未解锁灰显
	return bool(ach_system.is_unlocked(id))

func unlocked_count() -> int:
	var n := 0
	for id in _cells:
		if _is_unlocked(id):
			n += 1
	return n

# ---- 测试/接线视图 ----

func cell_count() -> int:
	return _cells.size()

## 单卡渲染快照（数据驱动断言缝）：{unlocked, name_text, status_text, gems_text}。
func cell_info(id: String) -> Dictionary:
	var def: Dictionary = _defs_by_id.get(id, {})
	var unlocked := _is_unlocked(id)
	var mark := "✓ " if unlocked else "锁 "
	return {
		"unlocked": unlocked,
		"name_text": mark + String(def.get("name", id)),
		"status_text": "已解锁" if unlocked else _progress_text(def),
		"gems_text": "+%d 蓝晶" % int(def.get("gems", 0)),
	}

func summary_text() -> String:
	return _summary.text

func detail_text() -> String:
	return _detail.text

# ---- 关闭 ----

func _on_close_pressed() -> void:
	if _router != null:
		_router.goto("menu")
	else:
		hide()   # 无路由环境（测试/独立实例）仅隐藏

func _cell_style(border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD_BG
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(4)
	return sb

func _label(text: String, font_size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l
