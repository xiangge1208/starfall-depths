class_name Shop
extends Interactable
## 商店/黑市交互物（m1-t14）：Interactable 世界实体 + buff_pick 式弹层 UI。
## 房间接线（FloorScene/C 线）注入 stock / wallet / black / drop_weapon 字段，
## InteractionSystem 走 interact(player) → open(...) 开层。
## 金币接缝：wallet 鸭子类型——coins:int + spend_coins(n)->bool；回收再加
## add_coins(n)（缺该方法则回收架隐藏）。T15 RunState 落地后即满足此接缝。
## M1 简化（披露）：买武器直接 weapon_rig.equip（首空槽），无换手替换 UI；
## 道具价 25/20 为固定常量（规格明示），不吃 floor/黑市系数；黑市仅改
## 武器价（ShopLogic.price ×1.8）与标题。

const TITLE := "商店"
const BLACK_TITLE := "黑市商人"
const CARD_MIN := Vector2(108, 84)
const PANEL_BG := Color(0.07, 0.08, 0.1, 0.96)
const FAIL_FLASH := Color(1, 0.25, 0.25)
const RARITY_COLORS := {
	"common": Color("cfd2d6"), "uncommon": Color("6ee86e"), "rare": Color("5ab0ff"),
	"epic": Color("b06cff"), "legend": Color("ffa64d"),
}
# 道具（规格固定价/固定效果；不吃 floor 与黑市系数）
const ITEM_PRICES := {"heart": 25, "energy": 20}
const ITEM_NAMES := {"heart": "红心", "energy": "蓝瓶"}
const ITEM_EFFECTS := {"heart": "回复 2 HP", "energy": "蓝 +20"}
const WEAPON_SLOTS := 3

var stock: Dictionary = {}                 # ShopLogic.roll_stock 产物
var wallet: Object = null                  # duck-typed 金币接缝
var black := false                         # 黑市变体：标题 + 武器价 ×1.8
var drop_weapon: Callable = Callable()     # 回收：func(player) -> {id,name,rarity}

var _player: Node2D = null
var _weapon_ids: Array[String] = []
var _sold: Array[bool] = []
var _item_sold := {}                       # kind -> bool
var _recycled := false
var _ui: Control = null
var _title: Label = null
var _coins: Label = null
var _weapon_cards: Array[PanelContainer] = []
var _weapon_name_labels: Array[Label] = []
var _weapon_price_labels: Array[Label] = []
var _item_cards := {}                      # kind -> PanelContainer
var _item_price_labels := {}               # kind -> Label
var _recycle_card: PanelContainer = null
var _recycle_label: Label = null


func _ready() -> void:
	super()
	action_label = TITLE
	_build_ui()


## 交互入口：用预设字段开层（FloorScene 接线约定）。
func interact(player: Node2D) -> void:
	open(stock, wallet, player, black, drop_weapon)


## 开层：注入 stock/wallet/player/黑市旗/回收回调并填架。
func open(stock_in: Dictionary, wallet_in: Object, player: Node2D,
		black_flag := false, drop_cb: Callable = Callable()) -> void:
	stock = stock_in
	wallet = wallet_in
	_player = player
	black = black_flag
	drop_weapon = drop_cb
	_fill()


func close() -> void:
	if _ui != null:
		_ui.hide()


## 关店（按钮/测试别名）。
func _close() -> void:
	close()


func _unhandled_input(event: InputEvent) -> void:
	if _ui == null or not _ui.visible:
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		if k.keycode == KEY_ESCAPE or k.physical_keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			close()


# ---------------------------------------------------------------- 购买路径

## 买武器卡 idx：扣款成功 → 直接装备（M1 简化）+ 已售；失败 → 价签闪红拒绝。
func _buy_weapon(idx: int) -> void:
	if idx < 0 or idx >= _weapon_ids.size() or _sold[idx]:
		return
	var id := _weapon_ids[idx]
	if id.is_empty():
		return
	var row := GameDB.get_weapon(id)
	if row.is_empty():
		return
	var cost := ShopLogic.price(String(row.get("rarity", "common")), _floor_idx(), black)
	if wallet == null or not wallet.spend_coins(cost):
		_flash(_weapon_price_labels[idx])
		return
	var p := _player as Player
	if p != null and p.weapon_rig != null:
		p.weapon_rig.equip(id)
	_sold[idx] = true
	_weapon_price_labels[idx].text = "已售"
	_refresh_coins()


## 买道具：红心 25 → heal(2)；蓝瓶 20 → add_energy(20)；余额不足闪红。
func _buy_item(kind: String) -> void:
	if not ITEM_PRICES.has(kind) or bool(_item_sold.get(kind, false)):
		return
	var cost := int(ITEM_PRICES[kind])
	if wallet == null or not wallet.spend_coins(cost):
		_flash(_item_price_labels[kind] as Label)
		return
	var p := _player as Player
	if p != null:
		if kind == "heart":
			p.heal(2)
		elif kind == "energy":
			p.add_energy(20)
	_item_sold[kind] = true
	(_item_price_labels[kind] as Label).text = "已售"
	_refresh_coins()


## 回收副手：drop_weapon.call() 执行丢弃并返回武器信息，按其稀有度入账回收价。
func _recycle() -> void:
	if _recycled or not _recycle_available():
		return
	var info_v: Variant = drop_weapon.call(_player)
	if typeof(info_v) != TYPE_DICTIONARY:
		return
	var info: Dictionary = info_v
	if info.is_empty():
		return
	var amount := ShopLogic.recycle_price(String(info.get("rarity", "common")), _floor_idx())
	if wallet != null and wallet.has_method("add_coins"):
		wallet.add_coins(amount)
	_recycled = true
	_recycle_card.visible = false
	_refresh_coins()


# ---------------------------------------------------------------- 测试/接线视图

func ui_visible() -> bool:
	return _ui != null and _ui.visible


func title_text() -> String:
	return _title.text


func coins_text() -> String:
	return _coins.text


func weapon_name_text(idx: int) -> String:
	return _weapon_name_labels[idx].text


func weapon_price_text(idx: int) -> String:
	return _weapon_price_labels[idx].text


func is_sold(idx: int) -> bool:
	return _sold[idx]


func item_price_text(kind: String) -> String:
	if not _item_price_labels.has(kind):
		return ""
	return (_item_price_labels[kind] as Label).text


func item_sold(kind: String) -> bool:
	return bool(_item_sold.get(kind, false))


func recycle_visible() -> bool:
	return _recycle_card != null and _recycle_card.visible


func recycle_label_text() -> String:
	return _recycle_label.text


# ---------------------------------------------------------------- UI 构建

func _build_ui() -> void:
	_ui = $UILayer/UI
	_title = $UILayer/UI/Center/Panel/VBox/Title
	_coins = $UILayer/UI/Center/Panel/VBox/Coins
	var weapon_row: HBoxContainer = $UILayer/UI/Center/Panel/VBox/WeaponRow
	var item_row: HBoxContainer = $UILayer/UI/Center/Panel/VBox/ItemRow
	for i in WEAPON_SLOTS:
		var card := _card(Color.WHITE)
		card.gui_input.connect(_on_weapon_input.bind(i))
		weapon_row.add_child(card)
		_weapon_cards.append(card)
		_weapon_name_labels.append(_add_label(card))
		_weapon_price_labels.append(_add_label(card))
	for kind: String in ITEM_PRICES.keys():
		var card := _card(Color.WHITE)
		card.gui_input.connect(_on_item_input.bind(kind))
		item_row.add_child(card)
		_item_cards[kind] = card
		var name_l := _add_label(card)
		name_l.text = String(ITEM_NAMES[kind])
		var effect_l := _add_label(card)
		effect_l.text = String(ITEM_EFFECTS[kind])
		_item_price_labels[kind] = _add_label(card)
	var drink := _card(Color("6b6f76"))
	var drink_l := _add_label(drink)
	drink_l.text = "神秘饮料\n（未开放）"          # T16 接真实饮料前的占位卡
	item_row.add_child(drink)
	# 回收卡与道具同排（480×270 视口竖向空间紧，单排溢出屏外）
	var rec := _card(Color("ffa64d"))
	rec.gui_input.connect(_on_recycle_input)
	item_row.add_child(rec)
	_recycle_card = rec
	_recycle_label = _add_label(rec)
	var close_btn: Button = $UILayer/UI/Center/Panel/VBox/CloseBtn
	close_btn.pressed.connect(_close)
	_ui.hide()                                   # 仅 open()/interact() 后显示


func _fill() -> void:
	var t := BLACK_TITLE if black else TITLE
	_title.text = t
	action_label = t
	_weapon_ids.clear()
	_sold.clear()
	var in_stock: Array = stock.get("weapons", [])
	for i in WEAPON_SLOTS:
		var id := String(in_stock[i]) if i < in_stock.size() else ""
		_weapon_ids.append(id)
		_sold.append(false)
		var card := _weapon_cards[i]
		card.modulate = Color.WHITE
		var name_l := _weapon_name_labels[i]
		var price_l := _weapon_price_labels[i]
		if id.is_empty() or GameDB.get_weapon(id).is_empty():
			name_l.text = "?" if not id.is_empty() else "—"
			price_l.text = "-"
			continue
		var row := GameDB.get_weapon(id)
		var col: Color = RARITY_COLORS.get(String(row.get("rarity", "common")), Color.WHITE)
		card.add_theme_stylebox_override("panel", _card_style(col))
		name_l.text = String(row.get("name", id))
		price_l.text = "%d 金币" % ShopLogic.price(String(row.get("rarity", "common")),
			_floor_idx(), black)
	# 道具卡：货单内才可购
	var kinds := {}
	for it: Variant in stock.get("items", []):
		if typeof(it) == TYPE_DICTIONARY:
			kinds[String(it.get("kind", ""))] = true
	for kind: String in ITEM_PRICES.keys():
		var card := _item_cards[kind] as PanelContainer
		var price_l := _item_price_labels[kind] as Label
		card.visible = kinds.has(kind)
		card.modulate = Color.WHITE
		price_l.text = "%d 金币" % int(ITEM_PRICES[kind])
	_item_sold.clear()
	_recycled = false
	_fill_recycle()
	_refresh_coins()
	_ui.show()


## 回收卡文案：X 取玩家副手（rig 非当前槽）预览价；副手空 → 仅文案不计价。
## 入账仍以点击时 drop_weapon 返回的稀有度为准（丢弃瞬间权威）。
func _fill_recycle() -> void:
	_recycle_card.visible = _recycle_available()
	if not _recycle_card.visible:
		return
	var amount := _recycle_preview()
	_recycle_label.text = ("回收副手 +%d金" % amount) if amount >= 0 else "回收副手"
	_recycle_card.modulate = Color.WHITE


func _recycle_available() -> bool:
	return drop_weapon.is_valid() and wallet != null and wallet.has_method("add_coins")


## 副手预览回收价（无副手返回 -1）。
func _recycle_preview() -> int:
	var p := _player as Player
	if p == null or p.weapon_rig == null:
		return -1
	var rig := p.weapon_rig
	if rig.slots.size() < 2:
		return -1
	var alt := (rig.slot + 1) % 2
	var w: Dictionary = rig.slots[alt]
	if w.is_empty():
		return -1
	return ShopLogic.recycle_price(String(w.get("rarity", "common")), _floor_idx())


func _refresh_coins() -> void:
	if wallet == null:
		_coins.text = ""
		return
	var v: Variant = wallet.get("coins")
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		_coins.text = "%d 金币" % int(v)
	else:
		_coins.text = ""


func _floor_idx() -> int:
	return int(stock.get("floor_idx", 1))


func _flash(label: Label) -> void:
	label.modulate = FAIL_FLASH
	var tw := label.create_tween()
	tw.tween_property(label, "modulate", Color.WHITE, 0.45)


func _on_weapon_input(event: InputEvent, idx: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_buy_weapon(idx)


func _on_item_input(event: InputEvent, kind: String) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_buy_item(kind)


func _on_recycle_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_recycle()


func _card(border: Color) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_MIN
	card.add_theme_stylebox_override("panel", _card_style(border))
	return card


func _card_style(border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(6)
	return sb


func _add_label(card: PanelContainer) -> Label:
	# 卡内纵向盒惰性创建：名字/效果/价签依次叠放
	var box: VBoxContainer = null
	for c in card.get_children():
		if c is VBoxContainer:
			box = c
			break
	if box == null:
		box = VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		card.add_child(box)
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 10)
	box.add_child(l)
	return l
