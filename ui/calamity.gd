class_name CalamityPanel
extends Control
## 挑战房灾厄 4 选 1 面板（m2-t26 / GDD §11 挑战房）：open() 弹四卡（中文名 + 描述，
## 标题注明「仅本房生效」），键盘 1~4 或点击卡片选择，选定发 calamity_chosen(id) 并关闭。
## 同 buff_pick 的「纯展示 + 信号」模式：不持有局内状态；灾厄数值落地与房清还原由
## FloorScene 消费（行级 override / 临时 meta 标志 / BiomeFx 复用，见 floor_scene.gd）。

signal calamity_chosen(id: String)

## 灾厄目录（GDD §11：敌速+30% / 视野-35% / 治疗无效 / 弹速+25%，仅本房生效）。
## id 为 FloorScene 行为键；label/desc 为面板展示行（中文逐字对齐设计表）。
const CALAMITIES: Array[Dictionary] = [
	{"id": "enemy_speed", "label": "敌速+30%", "desc": "本房内敌人移动速度 +30%。"},
	{"id": "vision", "label": "视野-35%", "desc": "本房内视野缩减 35%（光圈缩小、画面变暗）。"},
	{"id": "heal_disable", "label": "治疗无效", "desc": "本房内一切治疗无效。"},
	{"id": "bullet_speed", "label": "弹速+25%", "desc": "本房内敌方弹幕速度 +25%。"},
]
const CALAMITY_IDS: Array[String] = ["enemy_speed", "vision", "heal_disable", "bullet_speed"]
const TITLE_TEXT := "挑战房·灾厄 4 选 1（仅本房生效）"
const HOTKEYS: Array[Key] = [KEY_1, KEY_2, KEY_3, KEY_4]
# 布局兜底（M3-S-C 冒烟实测）：4 卡 ×136 + 间距 24 + 面板边距 24 = 592px 超 480 视口
# （固定卡宽预存超界，与字号无关）；108×4 + 24 + 24 = 480 恰好收下，12px 文案 3 行内可容。
const CARD_MIN := Vector2(108, 116)
const CARD_BG := Color(0.09, 0.06, 0.07, 0.95)
const BORDER := Color(0.85, 0.3, 0.25)

var _cards: Array[PanelContainer] = []
var _title: Label = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP     # 弹层期间挡住底层点击
	_build_ui()
	hide()                                       # 仅 open() 后显示


## 弹出灾厄 4 选 1（重开重填）。
func open() -> void:
	_fill_cards()
	show()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var key: InputEventKey = event
		if not key.pressed or key.echo:
			return
		var code: int = key.keycode if key.keycode != KEY_NONE else key.physical_keycode
		var idx := HOTKEYS.find(code)
		if idx >= 0 and idx < CALAMITIES.size():
			get_viewport().set_input_as_handled()
			_choose(idx)


## 选定入口（键盘位/点击/测试共用）；越界忽略。
func _choose(idx: int) -> void:
	if idx < 0 or idx >= CALAMITIES.size():
		return
	hide()
	calamity_chosen.emit(String((CALAMITIES[idx] as Dictionary)["id"]))


# ---------------------------------------------------------------- 测试/接线视图

func title_text() -> String:
	return _title.text


func card_label(idx: int) -> String:
	if idx < 0 or idx >= _cards.size():
		return ""
	for node in (_cards[idx] as PanelContainer).find_children("CardTitle", "Label", true, false):
		return (node as Label).text             # 标题行 = 灾厄中文标签（无键位前缀）
	return ""


# ---------------------------------------------------------------- UI 构建（代码内建，无 .tscn）

func _build_ui() -> void:
	var center := CenterContainer.new()
	center.name = "CalamityUI"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD_BG
	sb.border_color = BORDER
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	_title = Label.new()
	_title.text = TITLE_TEXT
	_title.add_theme_font_size_override("font_size", 12)
	box.add_child(_title)
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	for i in CALAMITIES.size():
		var card := PanelContainer.new()
		card.custom_minimum_size = CARD_MIN
		card.gui_input.connect(_on_card_input.bind(i))
		row.add_child(card)
		_cards.append(card)


func _fill_cards() -> void:
	for i in _cards.size():
		var card := _cards[i]
		for c in card.get_children():
			c.queue_free()
		var info: Dictionary = CALAMITIES[i]
		card.add_theme_stylebox_override("panel", _card_style())
		var item := VBoxContainer.new()
		item.add_theme_constant_override("separation", 2)
		card.add_child(item)
		item.add_child(_make_label("[%d] %s" % [i + 1, String(info["label"])], 12, "CardTitle"))
		var desc := _make_label(String(info["desc"]), 12)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(CARD_MIN.x - 12.0, 0)
		desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		item.add_child(desc)


func _on_card_input(event: InputEvent, idx: int) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_choose(idx)


func _card_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD_BG
	sb.border_color = BORDER
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(6)
	return sb


func _make_label(text: String, font_size: int, node_name := "") -> Label:
	var l := Label.new()
	l.text = text
	if not node_name.is_empty():
		l.name = node_name
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color.WHITE)
	return l
