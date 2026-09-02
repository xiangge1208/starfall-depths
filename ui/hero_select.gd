class_name HeroSelect
extends Control
## 选角界面（m1-t11）：6 英雄卡展示 GameDB.heroes（中文名/面板/被动/技能名+描述/初始武器中文名）。
## M4-K2 布局重排：卡行收进 CardScroll 横向滚动（卡 206px 固定宽不缩、12px 像素字体
## 零缩放，撤 m3-font-walkthrough §3.6「1316px vs 480px」S-C 豁免）——三案取舍定横滚：
## 缩卡网格在 270px 高度下容不下 6 卡文本量（必截字，破 12px 可读性下限）；分页翻页
## 会把 3 张卡藏出树外（focus_neighbors 链物理断开 + 触屏翻页多打两跳）；横滚 6 卡
## 全程在树（导航序闭合），滑动为触屏原生手势（与图鉴同款滚动容器惯例）。
## 导航三路：①keyboard/gamepad——卡 FOCUS_ALL + focus_neighbors 闭环（卡 5 右跳回
## 卡 0），follow_focus 自动把焦点卡滚进可视域，A/D/摇杆（move_left/right 动作）走
## 既有 _move 并回写焦点（两路汇一）；确认 = Enter/Space/手柄 A（ui_accept）；
## ②鼠标——按下记录、松开位移 ≤8px 才算点击选中（触摸滑动起手不再误触发选择）；
## ③触屏——卡上滑动 = 滚动（ScrollContainer 原生），轻点 = 选中（同 ② 释放判定）。
## 选择落地：优先调 RunState autoload 的 select_hero 钩子（T15 未合并则节点不存在，
## 用 /root 路径探测——Engine.has_singleton 只认原生单例，对 GDScript autoload 恒 false）；
## 无钩子时落 HeroSelect.last_chosen 静态暂存（T15 合并时收编）。
## 换场景路由由 T23 加线（hero_chosen 后守卫探测 /root/SceneRouter → goto("game")）。

signal hero_chosen(hero_id: String)

const CARD_MIN := Vector2(206, 208)
const TAP_SLOP := 8.0   # 点击判定位移阈（px）：内=轻点选中，外=滑动滚动不选中
const CARD_BG := Color(0.07, 0.08, 0.1, 0.95)
const SELECTED_BORDER := Color(0.95, 0.82, 0.35)
const IDLE_BORDER := Color(0.25, 0.27, 0.32)
# 被动中文文案（GDD §6；heroes 行只带 passive_id，展示文案归 UI 层）
const PASSIVES := {
	"defiance": "坚守：护盾破碎时对 60px 内敌人 1 伤+击退+眩晕 0.5s",
	"hawk_eye": "鹰眼：暴击时 50% 概率返还 1 蓝",
	"spare_parts": "备件：开局带 1 台便携炮台（存活 12s），每进入新一层补 1 台",
	"echo": "回响：法杖/激光类武器伤害 +15%",
	"blessing": "祝福：每进入新层回满护盾并 +5% 全伤害（单局至多叠 4 层）",
	"shadow_reap": "掠影：近战击杀返还 5 蓝，1s 内翻滚无冷却",
}

static var last_chosen := ""   # 静态暂存 fallback（RunState 未合并期间的选角结果）

var _ids: Array = []
var _selected := 0
var _cards: Array[PanelContainer] = []
var _press_idx := -1          # 按压中的卡索引（-1 = 无），释放时按位移判轻点/滑动
var _press_pos := Vector2.ZERO

func _ready() -> void:
	_ids = GameDB.heroes.keys()
	if _ids.is_empty():
		push_error("HeroSelect: no heroes loaded")
		return
	_build_cards()
	_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if _ids.is_empty():
		return
	if event.is_action_pressed("move_left"):
		get_viewport().set_input_as_handled()
		_move(-1)
	elif event.is_action_pressed("move_right"):
		get_viewport().set_input_as_handled()
		_move(1)
	elif event.is_action_pressed("ui_accept"):
		# Enter/KP Enter/Space/手柄 A（ui_accept 默认集）；焦点卡不吞 ui_accept
		#（PanelContainer 非按钮），落到此处确认当前高亮。
		get_viewport().set_input_as_handled()
		_choose(_selected)

func _move(dir: int) -> void:
	_selected = wrap(_selected + dir, 0, _ids.size())
	_refresh()
	# 焦点回写：A/D 与焦点导航两路汇一（焦点跟随自动滚出可视域）；
	# 已聚焦同一卡时幂等（focus_entered 里 _selected 相等不重刷）。
	if _selected < _cards.size():
		_cards[_selected].grab_focus()

func _choose(idx: int) -> void:
	if idx < 0 or idx >= _ids.size():
		return
	var id := String(_ids[idx])
	last_chosen = id                                  # 静态暂存 fallback（恒写，T23 兜底可用）
	var run_state := get_node_or_null("/root/RunState")
	if run_state != null and run_state.has_method("select_hero"):
		run_state.call("select_hero", id)              # T15 已合并则走其选择钩子
	hero_chosen.emit(id)
	# T23 接线：选角即路由进局。双重守卫：/root/SceneRouter 未注册或节点不在树内
	# → 探测为 null 不路由不崩；且仅当本节点是当前活动场景（生产路径：经
	# SceneRouter.change_scene 挂载）才路由——T11 嵌入式单测（hero_select 挂在
	# 测试套件节点下）不触发真实场景切换（防跨套件场景易主/孤儿节点）。
	var sr := get_node_or_null("/root/SceneRouter")
	if sr != null and get_tree() != null and get_tree().current_scene == self:
		sr.goto("game")

## 焦点即选中（keyboard/gamepad 单一事实源）：焦点链移动 → 高亮同步，
## 滚动交给 CardScroll.follow_focus，不在焦点回调里手动 ensure_control_visible。
func _on_card_focus(idx: int) -> void:
	if _selected != idx:
		_selected = idx
		_refresh()

func _on_card_input(event: InputEvent, idx: int) -> void:
	# 轻点判定：按下记录、松开对账。位移 ≤ TAP_SLOP 才算点击选中——横滚布局下
	# 触摸滑动起手若按「按下即选」会立刻误触发选择，故对齐 BaseButton 默认的
	# 释放激活语义（与图鉴按钮一致），滚动中的释放（位移超阈）不选。
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_press_idx = idx
			_press_pos = mb.position
		elif _press_idx == idx:
			_press_idx = -1
			if mb.position.distance_to(_press_pos) <= TAP_SLOP:
				_choose(idx)

func _build_cards() -> void:
	var row: HBoxContainer = $CardScroll/Cards
	for i in _ids.size():
		var card := PanelContainer.new()
		card.custom_minimum_size = CARD_MIN
		card.focus_mode = Control.FOCUS_ALL          # keyboard/gamepad 焦点可落卡
		card.gui_input.connect(_on_card_input.bind(i))
		card.focus_entered.connect(_on_card_focus.bind(i))
		row.add_child(card)
		_cards.append(card)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 3)
		card.add_child(box)
		var hero: Dictionary = GameDB.get_hero(String(_ids[i]))
		box.add_child(_label(String(hero.get("name", _ids[i])), 12))
		box.add_child(_label("HP %d  盾 %d  蓝 %d\n速 %.0f  暴击 %d%%" % [
			int(hero.get("hp", 0)), int(hero.get("shield", 0)), int(hero.get("energy", 0)),
			float(hero.get("speed", 0.0)), roundi(float(hero.get("crit_chance", 0.0)) * 100.0)], 12))
		var passive := _label("被动 %s" % str(PASSIVES.get(hero.get("passive_id", ""), hero.get("passive_id", "?"))), 12)
		passive.add_theme_color_override("font_color", Color(0.55, 0.85, 0.55))
		passive.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # 12px 下长被动断行（防横向破卡）
		box.add_child(passive)
		var skill := _label("%s %s" % [str(hero.get("skill_name", "?")), str(hero.get("skill_desc", ""))], 12)
		skill.add_theme_color_override("font_color", Color(0.55, 0.75, 0.95))
		skill.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		skill.custom_minimum_size = Vector2(CARD_MIN.x - 14.0, 0)
		skill.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(skill)
		box.add_child(_label("初始 %s" % _weapon_names(hero.get("start_weapons", [])), 12, Color(0.85, 0.8, 0.6)))
	_wire_focus_chain()

## focus_neighbors 闭环（导航序完整）：左/右指向相邻卡、卡 5 右跳回卡 0（横滚下
## 焦点链不因视口裁剪断开，follow_focus 负责滚出可视域）；上/下指向自身（单行布局
## 无纵向邻卡，钉死防自动搜索逃逸出卡行）。
func _wire_focus_chain() -> void:
	var n := _cards.size()
	for i in n:
		var card := _cards[i]
		card.focus_neighbor_left = card.get_path_to(_cards[(i - 1 + n) % n])
		card.focus_neighbor_right = card.get_path_to(_cards[(i + 1) % n])
		card.focus_neighbor_top = card.get_path_to(card)
		card.focus_neighbor_bottom = card.get_path_to(card)

## 高亮刷新：选中卡描边金字，其余灰（样式整体重建，与 BuffPick 同手法）
func _refresh() -> void:
	for i in _cards.size():
		var border := SELECTED_BORDER if i == _selected else IDLE_BORDER
		_cards[i].add_theme_stylebox_override("panel", _card_style(border))
		var name_label := _cards[i].get_child(0).get_child(0) as Label
		name_label.add_theme_color_override("font_color",
			SELECTED_BORDER if i == _selected else Color.WHITE)

## 初始武器中文名（经 GameDB weapons 表，未知 id 防御性回退）
func _weapon_names(ids: Array) -> String:
	var names: Array[String] = []
	for wid: Variant in ids:
		names.append(str(GameDB.get_weapon(String(wid)).get("name", wid)))
	return " + ".join(names)

func _card_style(border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD_BG
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(6)
	return sb

func _label(text: String, font_size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l
