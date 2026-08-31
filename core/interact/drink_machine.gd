class_name DrinkMachine
extends Interactable
## 饮料机（m1-t16，附录 F.1）：每层 3 次购买机会，8 张饮料卡（名称/效果/价格），
## 购买 → wallet.spend_coins(行内价格) → _apply_drink 效果落地 → 次数 -1，0 次 = 售罄。
## UI 走 buff_pick 卡片模式（代码构建 PanelContainer 卡片，点击购买）；
## 神秘混合 = 从 7 条具体饮料均匀现抽（rng 字段可注入保测试确定性）。
## 效果落地哲学同 BuffManager：hp_max/energy_max/move_speed 直写 player 公开字段；
## 无公开字段的键（crit/status/盾延时/翻滚CD）经 player meta 累加（消费接线属 T18/集成，已披露）：
##   crit_pct / status_rate_pct（分数累加）、shield_delay_reduction_ticks / roll_cd_ticks（tick 累加）。
## wallet 为 duck-typed（同 T14 契约）：spend_coins(n) -> bool；金币不足拒绝且不扣次数。

signal drink_bought(id: String)
## m2-t35：购买成功点信号（T3 K 表同名；kind 恒 "drink"——附录 K.1 发射点接线归本卡）。
## 消费方（T25 结算聚合 / 成就 K 表）后续按同名对接；缺席期间不误解锁。
signal shop_purchase(kind: String)

const USES_PER_FLOOR := 3
const PANEL_OFFSET := Vector2(-236, -84) # 面板相对机器（480x270 视口居中偏上）
const CARD_MIN := Vector2(56, 96)
const HEADER_FONT := 10
const CARD_FONT := 8
const PANEL_BG := Color(0.07, 0.08, 0.1, 0.95)
const ACCENT := Color("5ab0ff")
const SOLD_OUT_COLOR := Color(0.55, 0.55, 0.55)

var uses_left := USES_PER_FLOOR
var rng: RandomNumberGenerator = null    # 神秘混合现抽用；注入优先，兜底也只经 RunState 分盐流
var wallet = null                        # duck-typed：spend_coins(n) -> bool
var _state: Dictionary = {"uses_left": USES_PER_FLOOR}
var _player: Node2D = null
var _panel: PanelContainer = null
var _header: Label = null
var _cards: Array[PanelContainer] = []

func _ready() -> void:
	super()
	action_label = "饮料机"

## 绑定楼层级持久状态而不自动打开面板。FloorScene 在创建生产实例时调用，
## 从而保证同一层重建/重进不会把 3 次购买机会悄悄补满；新楼层传入新字典。
func configure(machine_state: Dictionary, wallet_, rng_: RandomNumberGenerator = null) -> DrinkMachine:
	_state = machine_state
	if not _state.has("uses_left"):
		_state["uses_left"] = USES_PER_FLOOR
	uses_left = int(_state["uses_left"])
	wallet = wallet_
	if rng_ != null:
		rng = rng_
	return self

## 开机（每层由房间流传入持久状态字典 + 钱包 + 玩家）：同步剩余次数并弹出卡片面板。
func open(machine_state: Dictionary, wallet_, player: Node2D) -> void:
	configure(machine_state, wallet_)
	_player = player
	_ensure_panel()
	_refresh_panel()
	_panel.show()

## 卡片列表（确定性顺序：表键排序），buy(idx) 的 idx 以此为准。
func drink_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in GameDB.drinks:
		out.append(id)
	out.sort()
	return out

## 神秘混合的抽取池：7 条具体饮料（排序确定）。
func concrete_ids() -> Array[String]:
	var out: Array[String] = []
	for id in drink_ids():
		if GameDB.get_drink(id).get("effect", "") != GameDB.DRINK_RANDOM_EFFECT:
			out.append(id)
	return out

## 购买第 idx 张卡：售罄/非法 idx/扣费失败 → false（不扣次数不落地）。
func buy(idx: int) -> bool:
	if uses_left <= 0:
		return false                      # 售罄
	var ids := drink_ids()
	if idx < 0 or idx >= ids.size():
		return false
	var row := GameDB.get_drink(ids[idx])
	if row.is_empty():
		return false
	if wallet == null or not wallet.spend_coins(int(row["price"])):
		return false                      # 金币不足拒绝
	var applied_id := ids[idx]
	var effect: String = row["effect"]
	var value := float(int(row["value"]))
	if effect == GameDB.DRINK_RANDOM_EFFECT:
		applied_id = _roll_concrete()     # 神秘混合：从 7 选 1（扣的是混合价 20）
		var picked := GameDB.get_drink(applied_id)
		effect = picked["effect"]
		value = float(int(picked["value"]))
	_apply_drink(effect, value, _player as Player)
	uses_left -= 1
	_state["uses_left"] = uses_left       # 状态回写（跨楼层持久归调用方）
	drink_bought.emit(applied_id)
	shop_purchase.emit("drink")           # m2-t35：T3 K 表同名购买信号（成功点）
	_refresh_panel()
	return true

## 神秘混合现抽：注入 rng 均匀取一。独立场景/测试未注入时仍必须经当前局
## RunState 分盐流派生，禁止裸 RandomNumberGenerator.new() 绕过可回放种子链。
func _roll_concrete() -> String:
	if rng == null:
		rng = RunState.stream(RunState.SALT_DRINK)
	var pool := concrete_ids()
	return pool[rng.randi_range(0, pool.size() - 1)]

## 效果应用器（static 纯逻辑，headless 直测）：同 BuffManager 写公开字段的口径；
## 白名单外键 no-op（fail-closed 第二道防线，GameDB 校验外的运行时保险）。
## m2-t35 大胃王：效果值 ×(1+buff_drink_effect_pct)（glutton +50% → hp_max +2 落 +3；
## 移速 +10% 落 +15%）——商店第六饮料卡复用本应用器，两条购买路径口径天然一致；
## int 效果按 float 缩放后取整（floor，json 值均为整数量纲）。
static func _apply_drink(effect: String, value: float, p: Player) -> void:
	if p == null:
		return
	var glutton := float(p.get_meta("buff_drink_effect_pct", 0.0))
	if glutton != 0.0:
		value = value * (1.0 + glutton)
	match effect:
		"hp_max":
			p.hp_max = int(p.hp_max) + int(value)
		"energy_max":
			p.energy_max = int(p.energy_max) + int(value)
		"move_speed_pct":
			p.move_speed = float(p.move_speed) * (1.0 + value / 100.0)
		"crit_pct":
			p.set_meta("drink_crit_bonus", float(p.get_meta("drink_crit_bonus", 0.0)) + value / 100.0)
			p.crit_bonus += value / 100.0
		"status_rate_pct":
			p.set_meta("drink_status_rate_bonus", float(p.get_meta("drink_status_rate_bonus", 0.0)) + value / 100.0)
			p.status_rate_bonus += value / 100.0
		"shield_delay_reduction_ticks":
			p.set_meta("drink_shield_delay_reduction_ticks", int(p.get_meta("drink_shield_delay_reduction_ticks", 0)) + int(value))
			p.shield_delay_reduction_ticks += int(value)
		"roll_cd_ticks":
			p.set_meta("drink_roll_cd_reduction_ticks", int(p.get_meta("drink_roll_cd_reduction_ticks", 0)) + int(value))
			p.roll_cd_reduction_ticks += int(value)
		_:
			push_error("DrinkMachine: unknown drink effect %s" % effect)

## ---- UI（buff_pick 卡片模式）----

## E 交互：面板已开 → 关；未开且有钱包 → 开。
func interact(player: Node2D) -> void:
	if _panel != null and _panel.visible:
		_panel.hide()
	elif wallet != null:
		open(_state, wallet, player if player != null else _player)

func _ensure_panel() -> void:
	if _panel != null:
		return
	_panel = PanelContainer.new()
	_panel.position = PANEL_OFFSET
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = ACCENT
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(6)
	_panel.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_panel.add_child(box)
	_header = _label("", HEADER_FONT, ACCENT)
	box.add_child(_header)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	box.add_child(row)
	for i in GameDB.drinks.size():
		var card := PanelContainer.new()
		card.custom_minimum_size = CARD_MIN
		card.gui_input.connect(_on_card_input.bind(i))
		row.add_child(card)
		_cards.append(card)
	add_child(_panel)

func _refresh_panel() -> void:
	if _panel == null:
		return
	var sold_out := uses_left <= 0
	_header.text = "售罄" if sold_out else "饮料机 剩余 %d/%d" % [uses_left, USES_PER_FLOOR]
	var ids := drink_ids()
	for i in _cards.size():
		var card := _cards[i]
		for c in card.get_children():
			c.queue_free()
		var info: Dictionary = GameDB.get_drink(ids[i]) if i < ids.size() else {}
		var tint := SOLD_OUT_COLOR if sold_out else Color.WHITE
		card.modulate = tint
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 1)
		card.add_child(box)
		box.add_child(_label(str(info.get("name", "?")), CARD_FONT, tint))
		var desc := _label(effect_desc(str(info.get("effect", "")), info.get("value", 0)), CARD_FONT, tint)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(CARD_MIN.x - 8.0, 0)
		box.add_child(desc)
		box.add_child(_label("%d金" % int(info.get("price", 0)), CARD_FONT, ACCENT if not sold_out else tint))

func _on_card_input(event: InputEvent, idx: int) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and uses_left > 0:
			buy(idx)

## 效果 → 中文描述（卡片第 2 行；附录 F.1 口径）。
static func effect_desc(effect: String, value: Variant) -> String:
	match effect:
		"hp_max":
			return "HP上限+%d" % int(value)
		"energy_max":
			return "蓝上限+%d" % int(value)
		"move_speed_pct":
			return "移速+%d%%" % int(value)
		"crit_pct":
			return "暴击+%d%%" % int(value)
		"shield_delay_reduction_ticks":
			return "盾回复延时-0.5s"
		"roll_cd_ticks":
			return "翻滚CD-0.05s"
		"status_rate_pct":
			return "异常积累+%d%%" % int(value)
		GameDB.DRINK_RANDOM_EFFECT:
			return "随机一条上述效果"
	return "???"

func _label(text: String, font_size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l
