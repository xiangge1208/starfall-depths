class_name BuffPick
extends Control
## 三选一增益浮层（m1-t9 展示桩）：open(choices) 弹出三卡（顶部 ui/buffs 图标 + 名称/
## 稀有度描边色/中文描述），键盘 1/2/3 或点击卡片选择，选中即发出 buff_chosen(id) 并关闭。
## 纯展示 + 信号：不持有局内状态，数值落地由调用方接 BuffManager。
## m4p-w2b：卡顶接 ArtLookup.BUFF_TEXTURES 图标（12x12 最近邻居中）；空帧/缺图/表外 id
## 缺行不占位回落原纯文字卡（同 HUD buff 芯片回落语义）。

signal buff_chosen(id: String)

const RARITY_COLORS := {"common": Color("cfd2d6"), "uncommon": Color("6ee86e"), "rare": Color("5ab0ff")}
const RARITY_TAGS := {"common": "白", "uncommon": "绿", "rare": "蓝"}
const HOTKEYS: Array[Key] = [KEY_1, KEY_2, KEY_3]
const CARD_MIN := Vector2(136, 116)
const CARD_BG := Color(0.07, 0.08, 0.1, 0.95)

var _choices: Array[String] = []
var _cards: Array[PanelContainer] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP   # 弹层期间挡住底层点击
	_build_cards()
	hide()                                     # 仅在 open() 后显示

## 弹出三选一：choices 为 buff id（≤3 个；不足按实有几张卡）。
func open(choices: Array[String]) -> void:
	_choices = choices.duplicate()
	_fill_cards()
	show()

func _unhandled_input(event: InputEvent) -> void:
	if not visible or _choices.is_empty():
		return
	if event is InputEventKey:
		var key: InputEventKey = event
		if not key.pressed or key.echo:
			return
		var code: int = key.keycode if key.keycode != KEY_NONE else key.physical_keycode
		var idx := HOTKEYS.find(code)
		if idx >= 0 and idx < _choices.size():
			get_viewport().set_input_as_handled()
			_choose(idx)

func _build_cards() -> void:
	var row: HBoxContainer = $Cards
	for i in 3:
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
		var info := _buff_info(_choices[i]) if i < _choices.size() else {}
		var col: Color = RARITY_COLORS.get(info.get("rarity", "common"), Color.WHITE)
		card.add_theme_stylebox_override("panel", _card_style(col))
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		card.add_child(box)
		var icon: Texture2D = ArtLookup.tex(ArtLookup.buff_texture_path(str(_choices[i]))) \
			if i < _choices.size() else null
		if icon != null:
			var ic := TextureRect.new()
			ic.texture = icon
			ic.custom_minimum_size = Vector2(12, 12)   # ui/buffs/*.png 原生 12x12
			ic.stretch_mode = TextureRect.STRETCH_KEEP
			ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(ic)
		box.add_child(_label("[%d] %s" % [i + 1, info.get("name", "?")], 12))
		box.add_child(_label(str(RARITY_TAGS.get(info.get("rarity", ""), "?")), 12, col))
		var desc := _label(str(info.get("desc", "")), 12)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(CARD_MIN.x - 12.0, 0)
		desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(desc)

func _choose(idx: int) -> void:
	if idx < 0 or idx >= _choices.size():
		return
	var id := _choices[idx]
	AudioMgr.play("buff_pick")   # m4p-w2a：三选一选卡成功拍（祭坛/层间两路共用本浮层）
	hide()
	buff_chosen.emit(id)

func _on_card_input(event: InputEvent, idx: int) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_choose(idx)

## id → 展示行（未知 id 防御性回退，不崩溃）。
func _buff_info(id: String) -> Dictionary:
	var row: Dictionary = GameDB.get_buff(id)
	if row.is_empty():
		return {"name": id, "rarity": "common", "desc": "???"}
	return row

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
