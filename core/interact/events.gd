class_name EventRoom
extends Node
## 事件房编排器（m1-t19）：房挂载节点（同 buff_pick 的「纯逻辑+自建 UI」模式），
## 进房由房间接线调 open_random_event() 4 选 1（神秘商人/乞丐/星髓泉/涂鸦墙），
## 弹中文面板（标题/描述/接受·拒绝两按钮，Esc=拒绝）。
## 每房每局一次（_used 简单守卫）；局级守卫走 RunState 旗（star_spring_used）。
##
## 披露（规格明示/整合期对齐）：
## - 神秘商人的 2 HP 为 hp 字段直写（min 0），绕盾不经 take_hit——设计如此；
## - 随机饮料效果池 = GDD §13.2 八饮料去「随机」共 7 条；apply_effect Callable 为落地
##   接缝（测试 spy 注入；T16 drink_machine 若暴露同语义接缝，整合期换绑即可），
##   缺省走本地 _apply_effect：仅落地 Player 有公开写字段的 3 条（hp_max/energy_max/
##   move_speed_pct），crit/盾延时/翻滚 CD/状态积累无公开写字段（同 BuffManager 披露），
##   默认路径记为 no-op；
## - 乞丐只记账（pending_investment=120 + beggar_paid_floor），70% 返还掷签与
##   跨层消费归 T20 inter-floor；
## - RunState.beggar_paid_floor / star_spring_used 为 declare-only 新增字段，
##   start_run 不重置（T19 文件所有权 0 逻辑约束）——多局重开的重置在整合任务接线。

signal event_resolved(id: String, accepted: bool)

const EVENT_IDS: Array[String] = ["mystery_merchant", "beggar", "star_spring", "graffiti"]
const MERCHANT_HP_COST := 2        # 神秘商人血价（GDD §11：2HP 换随机道具）
const BEGGAR_COST := 40            # 乞丐投入（GDD §11：40 金）
const BEGGAR_PAYOUT := 120         # 记账返还额（70% 掷签在 T20 跨层结算）
const PANEL_BG := Color(0.07, 0.08, 0.1, 0.96)
const PANEL_BORDER := Color("5ab0ff")
const DESC_WIDTH := 300.0

# 随机饮料效果池（GDD §13.2 去「随机」）：键与 BuffManager EFFECT_DEFAULTS 同口径，
# 值为固定效果量（盾延时 -0.5s=30t、翻滚 CD -0.05s=3t，按 Player tick 常量口径）。
const DRINK_EFFECT_IDS: Array[String] = [
	"hp_max", "energy_max", "move_speed_pct", "crit_pct",
	"shield_delay_reduction_ticks", "roll_cd_pct", "status_rate_pct",
]
const DRINK_EFFECTS := {
	"hp_max": 2, "energy_max": 20, "move_speed_pct": 0.05, "crit_pct": 3.0,
	"shield_delay_reduction_ticks": 30, "roll_cd_pct": 0.05, "status_rate_pct": 0.20,
}

const EVENT_TITLES := {
	"mystery_merchant": "神秘商人",
	"beggar": "乞丐",
	"star_spring": "星髓泉",
	"graffiti": "涂鸦墙",
}

# 涂鸦墙构筑提示池（10 条，纯叙事，引用既有系统口径）
const GRAFFITI_TIPS: Array[String] = [
	"翻滚有无敌帧，穿弹幕有时比躲弹幕更稳。",
	"近战挥砍能反弹弹幕——贴脸不一定是坏事。",
	"不同元素的弹幕接连命中可引发共鸣，伤害更上一层。",
	"蓝量是技能的底线，留一手蓝总比空手好。",
	"护盾破碎后有回复延时，破盾期别硬抗。",
	"乞丐收的不只是施舍，还有投资。",
	"星髓泉每局只润泽一人，路过别错过。",
	"副手武器可以拿去商店回收，备胎也有身价。",
	"传闻地牢深处藏着熔铸台，能把旧武器重获新生。",
	"暴击伤害词条配低速重炮，一击抵十击。",
]

var apply_effect: Callable = Callable()   # 饮料效果落地接缝：(effect, value, player)

var _player: Node2D = null
var _rng: RandomNumberGenerator = null
var _used := {}                # event_id -> true（每房每局一次的简单守卫）
var _event_id := ""            # 当前面板中的事件（"" = 无/已决）
var _effect_id := ""           # 神秘商人开面板时预掷的效果 id
var _tip := ""                 # 涂鸦墙抽中的提示
var _ui: Control = null
var _title: Label = null
var _desc: Label = null
var _accept_btn: Button = null
var _refuse_btn: Button = null


func _ready() -> void:
	_build_ui()


## 房间接线：注入玩家与 rng（抽取确定性靠注入 rng）。
func setup(player: Node2D, rng: RandomNumberGenerator) -> void:
	_player = player
	_rng = rng


## 4 选 1 随机开事件；本房已抽过则拒绝（返回 ""）。
func open_random_event() -> String:
	if _rng == null or not _used.is_empty():
		return ""
	var id: String = EVENT_IDS[_rng.randi_range(0, EVENT_IDS.size() - 1)]
	open_event(id)
	return id


## 指定事件开面板（房间定向接线/测试用）；未知 id 或本房已抽过拒绝。
func open_event(id: String) -> bool:
	if _rng == null or not _used.is_empty() or not EVENT_IDS.has(id):
		return false
	_used[id] = true
	_event_id = id
	_prepare(id)
	_fill_panel(id)
	_ui.show()
	return true


func accept() -> void:
	if _event_id.is_empty() or not _ui.visible:
		return
	var id := _event_id
	match id:
		"mystery_merchant":
			_merchant_accept()
		"beggar":
			_beggar_accept()
		"star_spring":
			_spring_accept()
		"graffiti":
			pass                                       # 纯叙事，无副作用
	_close(id, true)


func refuse() -> void:
	if _event_id.is_empty() or not _ui.visible:
		return
	_close(_event_id, false)


func _unhandled_input(event: InputEvent) -> void:
	if _ui == null or not _ui.visible:
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		if k.keycode == KEY_ESCAPE or k.physical_keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			refuse()                                   # Esc=拒绝（零副作用）


# ---------------------------------------------------------------- 事件路径

## 神秘商人：2 HP 直扣（绕盾，规格明示）→ 预掷效果经接缝/默认路径落地。
func _merchant_accept() -> void:
	var p := _player as Player
	if p != null:
		p.hp = maxi(0, p.hp - MERCHANT_HP_COST)        # 直写字段，不经 take_hit
	var value := float(DRINK_EFFECTS.get(_effect_id, 0.0))
	if apply_effect.is_valid():
		apply_effect.call(_effect_id, value, _player)
	else:
		_apply_effect(_effect_id, value, _player)


## 乞丐：扣 40 金成功才记账（返还额 + 付款层）；余额不足走拒绝路径零副作用。
func _beggar_accept() -> void:
	if not RunState.spend_coins(BEGGAR_COST):
		return
	RunState.pending_investment = BEGGAR_PAYOUT
	RunState.beggar_paid_floor = RunState.floor_idx


## 星髓泉：shield_max+1 且 shield+1；每局一次（RunState 旗守卫，二次无效）。
func _spring_accept() -> void:
	if RunState.star_spring_used:
		return
	RunState.star_spring_used = true
	var p := _player as Player
	if p != null:
		p.shield_max += 1
		p.shield += 1


## 默认效果落地：仅 Player 公开可写的 3 条真实生效，其余 no-op（披露见头注释）。
func _apply_effect(effect: String, value: float, p: Node2D) -> void:
	var player := p as Player
	if player == null:
		return
	match effect:
		"hp_max":
			player.hp_max += int(value)
		"energy_max":
			player.energy_max += int(value)
		"move_speed_pct":
			player.move_speed *= 1.0 + value
		_:
			pass                                       # 无公开写字段（整合期接线）


## 开面板时的每事件预掷（消费 rng 的顺序固定 → 同 seed 全程确定）。
func _prepare(id: String) -> void:
	_effect_id = ""
	_tip = ""
	match id:
		"mystery_merchant":
			_effect_id = DRINK_EFFECT_IDS[
				_rng.randi_range(0, DRINK_EFFECT_IDS.size() - 1)]
		"graffiti":
			_tip = GRAFFITI_TIPS[_rng.randi_range(0, GRAFFITI_TIPS.size() - 1)]


func _fill_panel(id: String) -> void:
	_title.text = String(EVENT_TITLES.get(id, id))
	_desc.text = _desc_for(id)


func _desc_for(id: String) -> String:
	match id:
		"mystery_merchant":
			return "兜帽下的商人举起一杯冒着气泡的饮料。\n「%d 点生命，换一杯未知的饮品——喝不喝？」" % MERCHANT_HP_COST
		"beggar":
			return "衣衫褴褛的乞丐朝你摊开手掌。\n「投入 %d 金币，若命运垂青，下一层奉还 %d。」" % [BEGGAR_COST, BEGGAR_PAYOUT]
		"star_spring":
			if RunState.star_spring_used:
				return "泉眼已经枯寂，星髓的光辉本局已被取走。"
			return "一泓星光在泉中流转。\n饮下它，本局护盾上限 +1（每局一次）。"
		"graffiti":
			return _tip
	return ""


func _close(id: String, accepted: bool) -> void:
	_event_id = ""
	_ui.hide()
	event_resolved.emit(id, accepted)


# ---------------------------------------------------------------- 测试/接线视图

func ui_visible() -> bool:
	return _ui != null and _ui.visible


func current_event() -> String:
	return _event_id


func title_text() -> String:
	return _title.text


func desc_text() -> String:
	return _desc.text


func accept_button() -> Button:
	return _accept_btn


func refuse_button() -> Button:
	return _refuse_btn


# ---------------------------------------------------------------- UI 构建（代码内建，无 .tscn）

func _build_ui() -> void:
	var center := CenterContainer.new()
	center.name = "EventUI"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_STOP  # 弹层期间挡住底层点击
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = PANEL_BORDER
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 13)
	box.add_child(_title)
	_desc = Label.new()
	_desc.add_theme_font_size_override("font_size", 10)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(DESC_WIDTH, 0)
	box.add_child(_desc)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	_accept_btn = Button.new()
	_accept_btn.text = "接受"
	_accept_btn.pressed.connect(accept)
	row.add_child(_accept_btn)
	_refuse_btn = Button.new()
	_refuse_btn.text = "拒绝"
	_refuse_btn.pressed.connect(refuse)
	row.add_child(_refuse_btn)
	box.add_child(row)
	add_child(center)
	_ui = center
	_ui.hide()                                       # 仅 open_*() 后显示
