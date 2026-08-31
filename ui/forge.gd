class_name Forge
extends Interactable
## 熔铸台（m2-t25，GDD §8.3/§11）：Interactable 世界实体 + shop 式卡片弹层 UI。
## 房间接线（FloorScene._build_shop，每层固定 1 台）：wallet=RunState（coins/spend_coins
## 鸭子接缝）、pool=GameDB.weapons（权威武器表，locked 不入池即天然不可选）、
## rng=RunState 分盐流（SALT_FORGE）、run_state=RunState（通用升级计数字段
## forge_upgrades 的持有者，鸭子读写在测试可换桩）。
## M1 简化（披露）：无背包，材料 = 双武器槽的当前两把（开面板时快照）；熔铸产物
## 自动 equip 入槽 0、副槽清空——走 rig.clear_slot（权威入口）×2 后 rig.equip
##（首空槽即槽 0；rig.slot 复位 0 的直写紧随 equip 的 _sync_run_state 重新同步）。
## 通用升级每局限 2 次（ForgeLogic.UPGRADE_LIMIT_PER_RUN）：只计 upgrade 路径，
## 固定配方熔铸不消耗次数。
## 流程：预览（ForgeLogic.preview，不掷签）→ 扣费（ForgeLogic.fuse_cost）→
## 熔铸（ForgeLogic.fuse，升级路径此刻才消费 rng）→ 产物入槽。
## 产物继承（附录 D，裁定⑯）：配方产物的 energy_cost/element 由 ForgeLogic 算出，
## 本层负责盖到实际装备的槽行上（_apply_inherited_stats）——只复制后改实例，不污染 GameDB。

const TITLE := "熔铸台"
const CARD_MIN := Vector2(108, 84)
const PANEL_BG := Color(0.07, 0.08, 0.1, 0.96)
const FAIL_FLASH := Color(1, 0.25, 0.25)
const OK_FLASH := Color(0.4, 1.0, 0.5)
const RARITY_COLORS := {
	"common": Color("cfd2d6"), "uncommon": Color("6ee86e"), "rare": Color("5ab0ff"),
	"epic": Color("b06cff"), "legend": Color("ffa64d"),
}
const RARITY_CN := {"common": "白", "uncommon": "绿", "rare": "蓝", "epic": "紫", "legend": "橙"}

var wallet: Object = null          # duck-typed 金币接缝（coins + spend_coins [+ add_coins]）
var pool: Dictionary = {}          # 权威武器表（id -> row）；空池 = 不可熔铸
var rng: RandomNumberGenerator = null  # 升级路径掷签；缺省走 RunState 分盐流
var run_state: Node = null         # forge_upgrades 计数持有者（null = 视作 0 且不计数）

var _player: Node2D = null
var _slot_ids: Array[String] = ["", ""]    # 开面板时的双槽快照（材料即当前双槽）
var _ui: Control = null
var _title: Label = null
var _coins: Label = null
var _mat_name_labels: Array[Label] = []
var _mat_rarity_labels: Array[Label] = []
var _preview: Label = null
var _cost: Label = null
var _fuse_btn: Button = null


func _ready() -> void:
	super()
	action_label = TITLE
	_build_ui()


## 交互入口：用预设字段开层（FloorScene 接线约定，同 Shop.interact）。
func interact(player: Node2D) -> void:
	open(player)


## 开层：快照玩家双槽为材料并刷新面板。
func open(player: Node2D) -> void:
	_player = player
	_snapshot_slots()
	_refresh()
	_ui.show()


func close() -> void:
	if _ui != null:
		_ui.hide()


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


# ---------------------------------------------------------------- 熔铸路径

## 熔铸按钮（测试直调同款入口）：预览门控 → 扣费 → 掷签 → 产物入槽 0。
func _on_fuse_pressed() -> void:
	var a := _slot_ids[0]
	var b := _slot_ids[1]
	var look := ForgeLogic.preview(a, b, pool)
	var kind := String(look.get("kind", "none"))
	if kind == "none":
		return
	if kind == "upgrade" and _upgrades_used() >= ForgeLogic.UPGRADE_LIMIT_PER_RUN:
		return
	var cost := ForgeLogic.fuse_cost(_rarity_of(a), _rarity_of(b))
	if wallet == null or not wallet.spend_coins(cost):
		_flash(_cost, FAIL_FLASH)
		return
	var out := ForgeLogic.fuse(a, b, pool, _resolve_rng())
	if out.is_empty():
		# 池在开面板后被外力改动的防御路径：原路退款的兜底（正常流程不可达）
		if wallet != null and wallet.has_method("add_coins"):
			wallet.add_coins(cost)
		return
	if kind == "upgrade" and run_state != null:
		run_state.set("forge_upgrades", _upgrades_used() + 1)
	_apply_result(out)
	# 图鉴 craft_x 计数（评审 5b1061b Important-1）：熔铸成功即上报，取代 CodexSystem 的
	# 「T25 占位、无调用方」接口。5 条 craft_x 任务（含 4 把★图鉴项）此前进度恒 0、永不解锁。
	# 配方熔铸与通用升级都算一次熔铸；先例见 Core/interact/shop.gd 的 CodexSystem.count_buy()。
	CodexSystem.count_craft()
	AchievementSystem.notify_item_forged()   # m2-t33 补线：熔铸匠轮询点（裁定㉗）
	_flash(_preview, OK_FLASH)


## 产物装备：清双槽 → 指针复位槽 0 → equip 落首空槽（即槽 0）→ 继承值覆写槽行。
## rig.slot 直写披露：WeaponRig 无显式 set_slot 接缝；clear_slot/equip 内部
## _sync_run_state 会在 equip 收尾把 selected_slot=0 重新同步进 RunState。
func _apply_result(product: Dictionary) -> void:
	var p := _player as Player
	if p == null or p.weapon_rig == null:
		return
	var rig := p.weapon_rig
	var pid := String(product.get("id", ""))
	rig.clear_slot(0)
	rig.clear_slot(1)
	rig.slot = 0
	rig.equip(pid)
	_apply_inherited_stats(rig, pid, product)
	_snapshot_slots()
	_refresh()


## 附录 D 产物继承落槽（裁定⑯）：energy_cost/element 是**局内实例属性**，继承值必须
## 盖到实际装备的那把武器上，否则「蓝耗取两材料较高者、元素取 B 材料」只活在返回值里。
## 仅配方产物携带这两个键（通用升级产物沿用武器自身静表值，行为不变）。
## WeaponRig.equip 存的是 GameDB 行**共享引用**，故必须先 duplicate 再改——直写会污染全量表。
## （rig.slots 直写披露：本卡不拥有 weapon_rig.gd，不改其公开接口；行替换不改 id，
##  equip 收尾的 _sync_run_state 之后 RunState 聚合仍与槽内容一致。）
func _apply_inherited_stats(rig: WeaponRig, pid: String, product: Dictionary) -> void:
	if not (product.has("energy_cost") or product.has("element")):
		return
	if rig.slots.is_empty() or String((rig.slots[0] as Dictionary).get("id", "")) != pid:
		return                                     # equip 失败/槽位不符：不动槽
	var row: Dictionary = (rig.slots[0] as Dictionary).duplicate()
	if product.has("energy_cost"):
		row["energy_cost"] = int(product["energy_cost"])
	if product.has("element"):
		row["element"] = String(product["element"])
	rig.slots[0] = row


# ---------------------------------------------------------------- 面板刷新

func _snapshot_slots() -> void:
	_slot_ids = ["", ""]
	var p := _player as Player
	if p == null or p.weapon_rig == null:
		return
	for i in 2:
		if i < p.weapon_rig.slots.size() and not p.weapon_rig.slots[i].is_empty():
			_slot_ids[i] = String(p.weapon_rig.slots[i].get("id", ""))


func _refresh() -> void:
	_title.text = TITLE
	for i in 2:
		var row: Dictionary = _display_row(_slot_ids[i])
		var rarity := String(row.get("rarity", ""))
		_mat_name_labels[i].text = String(row.get("name", "—")) if not _slot_ids[i].is_empty() else "（空）"
		_mat_rarity_labels[i].text = String(RARITY_CN.get(rarity, "-"))
		_mat_rarity_labels[i].modulate = RARITY_COLORS.get(rarity, Color.WHITE)
	_refresh_preview_and_cost()
	_refresh_coins()


## 预览行 + 费用行 + 按钮可用态（同一条 ForgeLogic.preview 判定源，UI 不复读规则）。
## 产物/材料展示名走 _display_row：locked 产物不在 pool（掉落池）时回落 GameDB 全量行
## （仅展示；熔铸合法性判定始终以 pool 为权威）。
func _refresh_preview_and_cost() -> void:
	var a := _slot_ids[0]
	var b := _slot_ids[1]
	var look := ForgeLogic.preview(a, b, pool)
	var kind := String(look.get("kind", "none"))
	var cost := ForgeLogic.fuse_cost(_rarity_of(a), _rarity_of(b))
	match kind:
		"recipe":
			var disp: Dictionary = _display_row(String(look.get("id", "")))
			var cn: String = RARITY_CN.get(String(disp.get("rarity", "")), "?")
			_preview.text = "配方 → %s（%s）" % [String(disp.get("name", "")), cn]
			_cost.text = "%d 金币" % cost
			_fuse_btn.disabled = false
		"upgrade":
			var left := ForgeLogic.UPGRADE_LIMIT_PER_RUN - _upgrades_used()
			if left <= 0:
				_preview.text = "通用升级已达上限（每局 %d 次）" % ForgeLogic.UPGRADE_LIMIT_PER_RUN
				_cost.text = "—"
				_fuse_btn.disabled = true
			else:
				var cn2: String = RARITY_CN.get(String(look.get("target_rarity", "")), "?")
				_preview.text = "通用升级 → 随机%s武器（剩 %d 次）" % [cn2, left]
				_cost.text = "%d 金币" % cost
				_fuse_btn.disabled = false
		_:
			if a.is_empty() or b.is_empty():
				_preview.text = "无法熔铸（双槽均需武器）"
			else:
				_preview.text = "无法熔铸（同名/稀有度不同/无候选/不在池）"
			_cost.text = "—"
			_fuse_btn.disabled = true


func _rarity_of(id: String) -> String:
	if id.is_empty():
		return "common"
	return String((_display_row(id) as Dictionary).get("rarity", "common"))


## 展示行：pool 优先，缺则回落 GameDB 全量行（locked 产物/已持有 locked 武器仅展示用）。
func _display_row(id: String) -> Dictionary:
	var row: Dictionary = pool.get(id, {})
	return GameDB.get_weapon(id) if row.is_empty() and not id.is_empty() else row


## 通用升级计数（鸭子读）：正式局 = RunState.forge_upgrades；无 run_state 视作 0。
func _upgrades_used() -> int:
	if run_state == null:
		return 0
	var v: Variant = run_state.get("forge_upgrades")
	return int(v) if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT else 0


func _resolve_rng() -> RandomNumberGenerator:
	if rng != null:
		return rng
	return RunState.stream(RunState.SALT_FORGE)   # 正式局缺省（测试注入 rng 不走此路）


func _refresh_coins() -> void:
	if wallet == null:
		_coins.text = ""
		return
	var v: Variant = wallet.get("coins")
	_coins.text = "%d 金币" % int(v) if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT else ""


func _flash(target: CanvasItem, color: Color) -> void:
	target.modulate = color
	var tw := target.create_tween()
	tw.tween_property(target, "modulate", Color.WHITE, 0.45)


# ---------------------------------------------------------------- 测试/接线视图

func ui_visible() -> bool:
	return _ui != null and _ui.visible


func title_text() -> String:
	return _title.text


func coins_text() -> String:
	return _coins.text


func material_name_text(idx: int) -> String:
	return _mat_name_labels[idx].text if idx >= 0 and idx < _mat_name_labels.size() else ""


func preview_text() -> String:
	return _preview.text


func cost_text() -> String:
	return _cost.text


# ---------------------------------------------------------------- UI 构建

func _build_ui() -> void:
	_ui = $UILayer/UI
	_title = $UILayer/UI/Center/Panel/VBox/Title
	_coins = $UILayer/UI/Center/Panel/VBox/Coins
	var mat_row: HBoxContainer = $UILayer/UI/Center/Panel/VBox/MatRow
	for i in 2:
		var card := PanelContainer.new()
		card.custom_minimum_size = CARD_MIN
		card.add_theme_stylebox_override("panel", _card_style())
		mat_row.add_child(card)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		card.add_child(box)
		var name_l := Label.new()
		name_l.add_theme_font_size_override("font_size", 10)
		box.add_child(name_l)
		_mat_name_labels.append(name_l)
		var rarity_l := Label.new()
		rarity_l.add_theme_font_size_override("font_size", 10)
		box.add_child(rarity_l)
		_mat_rarity_labels.append(rarity_l)
	_preview = $UILayer/UI/Center/Panel/VBox/Preview
	_cost = $UILayer/UI/Center/Panel/VBox/Cost
	_fuse_btn = $UILayer/UI/Center/Panel/VBox/FuseBtn
	_fuse_btn.pressed.connect(_on_fuse_pressed)
	var close_btn: Button = $UILayer/UI/Center/Panel/VBox/CloseBtn
	close_btn.pressed.connect(close)
	_ui.hide()                                   # 仅 open()/interact() 后显示


func _card_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = Color(0.9, 0.6, 0.2)       # 熔铸暖色描边
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(6)
	return sb
