class_name HeroSelect
extends Control
## 选角界面（m1-t11）：两卡展示 GameDB.heroes（中文名/面板/被动/技能名+描述/初始武器中文名）。
## ←→/A/D（复用 move_left/move_right 输入动作）切换高亮，Enter 或点击卡片选择。
## 选择落地：优先调 RunState autoload 的 select_hero 钩子（T15 未合并则节点不存在，
## 用 /root 路径探测——Engine.has_singleton 只认原生单例，对 GDScript autoload 恒 false）；
## 无钩子时落 HeroSelect.last_chosen 静态暂存（T15 合并时收编）。
## 换场景路由由 T23 加线（hero_chosen 后守卫探测 /root/SceneRouter → goto("game")）。

signal hero_chosen(hero_id: String)

const CARD_MIN := Vector2(206, 208)
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
	elif event is InputEventKey and event.is_pressed() and not event.is_echo():
		var key := event as InputEventKey
		var code: int = key.keycode if key.keycode != KEY_NONE else key.physical_keycode
		if code == KEY_ENTER or code == KEY_KP_ENTER:
			get_viewport().set_input_as_handled()
			_choose(_selected)

func _move(dir: int) -> void:
	_selected = wrap(_selected + dir, 0, _ids.size())
	_refresh()

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

func _on_card_input(event: InputEvent, idx: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_choose(idx)

func _build_cards() -> void:
	var row: HBoxContainer = $Cards
	for i in _ids.size():
		var card := PanelContainer.new()
		card.custom_minimum_size = CARD_MIN
		card.gui_input.connect(_on_card_input.bind(i))
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
