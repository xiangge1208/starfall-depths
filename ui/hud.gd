class_name HUD
extends CanvasLayer
## 完整版战斗 HUD（m1-t24，GDD §19）：左上 红心×盾条×蓝条；右上 层数/种子/金币；
## 底中 武器×2 + 技能 CD 环 + 翻滚 CD 点；Buff 图标行（色块=稀有度色，中文缩写，tooltip 全名）；
## 低血量（hp ≤ 2）红晕呼吸提示。
## 数据纪律：所有数值每帧经静态 hud_snapshot(...) 从 RunState/Player/Skill 现读，不缓存
## 旧值（仅节点结构——心形容器/Buff 行——随 hp_max / buff 列表变化按需重建）。
## 装配：代码构建（同 debug_hud 惯例，无 tscn）。宿主场景用法：
##   var hud := HUD.new(); hud.player = player; add_child(hud)
## run 缺省时 _ready 自动取 /root/RunState。武器槽活真值取 WeaponRig（player 子节点），
## 无 rig（纯逻辑测试/极端剥离）时回退 RunState.weapons（record_weapon 聚合值）。

const LOW_HP_THRESHOLD := 2         # GDD §19：hp ≤ 2 红晕呼吸
const WEAPON_SLOTS := 2             # 同 RunState.WEAPON_SLOTS / WeaponRig 双槽契约

const HEART_SIZE := Vector2(6, 6)
const HEART_FULL := Color(0.85, 0.16, 0.16)
const HEART_EMPTY := Color(0.24, 0.1, 0.1)
const BAR_W := 52.0
const SHIELD_COLOR := Color(0.5, 0.8, 1.0)
const ENERGY_COLOR := Color(0.3, 0.45, 1.0)
const COIN_COLOR := Color(1.0, 0.85, 0.3)
const RING_READY := Color(0.3, 1.0, 0.6)
const RING_COOLING := Color(1.0, 0.6, 0.2)
const DOT_READY := Color(0.4, 0.95, 0.55)
const DOT_DIM := Color(0.28, 0.3, 0.32)
const RARITY_COLORS := {
	"common": Color(0.78, 0.78, 0.78, 0.9),
	"uncommon": Color(0.4, 0.85, 0.45, 0.9),
	"rare": Color(0.45, 0.65, 1.0, 0.9),
}

# ---- 纯逻辑（无头可测）：字段映射 / CD 比例 / 低血量阈值 / 名字与缩写 ----

## HUD 读数快照：一次取齐本帧全部显示字段。frame < 0 时取 Engine.get_physics_frames()
##（显式传帧供无头测试钉死数值）。player/run 允许 null（返回零值字段，不抛错）。
static func hud_snapshot(player: Player, run: Node, frame: int = -1) -> Dictionary:
	var f := frame if frame >= 0 else Engine.get_physics_frames()
	var snap := {}
	var coins := 0
	var floor_idx := 0
	var run_seed := 0
	var run_slot := 0
	var run_weapons: Array[String] = ["", ""]
	var buffs: Array[String] = []
	if run != null:
		coins = int(run.get("coins"))
		floor_idx = int(run.get("floor_idx"))
		run_seed = int(run.get("run_seed"))
		# T15 的权威字段是 selected_slot；RunState 仍提供 current_slot 兼容别名。
		var selected: Variant = run.get("selected_slot")
		run_slot = int(selected) if selected != null else int(run.get("current_slot"))
		var raw_buffs: Variant = run.get("buffs")
		if raw_buffs is Array:
			for b: Variant in raw_buffs:
				buffs.append(String(b))
		var raw_weapons: Variant = run.get("weapons")
		if raw_weapons is Array:
			for i in mini(raw_weapons.size(), 2):
				run_weapons[i] = String(raw_weapons[i])
	var hp := 0
	var hp_max := 0
	var shield := 0
	var shield_max := 0
	var energy := 0
	var energy_max := 0
	var names: Array[String] = ["", ""]
	var slot := run_slot
	var skill_ratio := 0.0
	var skill_ready := true
	var roll_ready := true
	if player != null:
		hp = player.hp
		hp_max = player.hp_max
		shield = player.shield
		shield_max = player.shield_max
		energy = player.energy
		energy_max = player.energy_max
		var rig: WeaponRig = player.weapon_rig
		if rig != null and rig.slots.size() > 0:
			slot = rig.slot
			for i in mini(rig.slots.size(), 2):
				var w: Dictionary = rig.slots[i]
				names[i] = "" if w.is_empty() else String(w.get("name", ""))
		else:
			for i in 2:
				names[i] = weapon_display_name(run_weapons[i])
		var sk := player.get_node_or_null("Skill") as SkillBase
		if sk != null:
			var remaining := sk.cooldown_remaining(f)
			skill_ratio = cd_ratio(remaining, sk.cooldown_ticks)
			skill_ready = remaining <= 0
		roll_ready = player.roll_ready_at(f)
	snap["coins"] = coins
	snap["floor_idx"] = floor_idx
	snap["run_seed"] = run_seed
	snap["hp"] = hp
	snap["hp_max"] = hp_max
	snap["shield"] = shield
	snap["shield_max"] = shield_max
	snap["energy"] = energy
	snap["energy_max"] = energy_max
	snap["weapon_names"] = names
	snap["current_slot"] = slot
	snap["skill_cd_ratio"] = skill_ratio
	snap["skill_ready"] = skill_ready
	snap["roll_ready"] = roll_ready
	snap["buffs"] = buffs
	snap["low_hp"] = is_low_hp(hp)
	return snap

## CD 环比例：剩余/总量，钳 [0,1]；总量 ≤ 0（无 CD 技能）恒 0（= 环空就绪）。
static func cd_ratio(remaining: int, total: int) -> float:
	if total <= 0:
		return 0.0
	return clampf(float(maxi(remaining, 0)) / float(total), 0.0, 1.0)

## 低血量红晕阈值（spec 边界：hp==2 亮，hp==3 灭）。
static func is_low_hp(hp: int) -> bool:
	return hp <= LOW_HP_THRESHOLD

## 武器显示名（GameDB 中文名；表外 id 原样回显；空槽空名）。
static func weapon_display_name(weapon_id: String) -> String:
	if weapon_id.is_empty():
		return ""
	return String(GameDB.get_weapon(weapon_id).get("name", weapon_id))

## Buff 中文缩写：中文名前 2 字（tooltip 走全名）；表外 id / 空值原样回显。
static func buff_abbrev(buff_id: String) -> String:
	if buff_id.is_empty():
		return ""
	var row: Dictionary = GameDB.get_buff(buff_id)
	if row.is_empty():
		return buff_id
	var display := String(row.get("name", buff_id))
	return display.substr(0, 2) if display.length() >= 2 else display

# ---- 节点引用 ----

var player: Player = null
var run: Node = null

var _vignette: ColorRect
var _hearts: HBoxContainer
var _shield_fill: ColorRect
var _energy_fill: ColorRect
var _floor_label: Label
var _seed_label: Label
var _coin_label: Label
var _buff_row: HBoxContainer
var _slot_panels: Array[PanelContainer] = []
var _slot_labels: Array[Label] = []
var _skill_ring: CdRing
var _roll_dot: ColorRect
var _trial_badges: TrialPanelUI.FactorBadges = null   # M3-R-B 试炼因子角标（层数旁）
var _abandon_btn: Button = null              # M3-R-C 放弃试炼按钮（仅试炼局显示）
## 回试炼面板路由接缝（M3-R-C 测试注入口，同 DeathSummary.exit_override 模式）：
## 有效时替代真实路由（生产 = SceneRouter.goto("menu")，试炼面板在主菜单）。
var abandon_route_override: Callable = Callable()
var _style_normal: StyleBoxFlat
var _style_active: StyleBoxFlat
var _hearts_count := -1
var _buff_keys: Array[String] = []

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS    # 同 debug_hud：hitstop 冻结期读数照常刷新
	if run == null:
		run = get_node_or_null("/root/RunState")
	_build_vignette()
	_build_top_left()
	_build_buff_row()
	_build_top_right()
	_build_bottom_center()
	_start_breath_tween()

func _process(_delta: float) -> void:
	var snap := hud_snapshot(player, run)
	_apply_top_left(snap)
	_apply_buffs(snap)
	_apply_top_right(snap)
	_apply_bottom(snap)
	_vignette.visible = bool(snap["low_hp"])

# ---- 构建 ----

func _build_vignette() -> void:
	_vignette = ColorRect.new()
	_vignette.color = Color(0.75, 0.05, 0.05, 0.12)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vignette)
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

## 红晕呼吸：alpha 0.12 ↔ 0.38 正弦往返（常驻循环 tween，显隐由 visible 控制）。
func _start_breath_tween() -> void:
	var tw := create_tween().set_loops()
	tw.tween_property(_vignette, "color:a", 0.38, 0.7) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_vignette, "color:a", 0.12, 0.7) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _build_top_left() -> void:
	var col := VBoxContainer.new()
	col.position = Vector2(4, 4)
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	_hearts = HBoxContainer.new()
	_hearts.add_theme_constant_override("separation", 1)
	_hearts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_hearts)
	_shield_fill = _bar(col, SHIELD_COLOR, 4)
	_energy_fill = _bar(col, ENERGY_COLOR, 3)

## 条：底槽 ColorRect + 内嵌填充（每帧按比例改宽）。
func _bar(parent: Control, color: Color, h: float) -> ColorRect:
	var bg := ColorRect.new()
	bg.custom_minimum_size = Vector2(BAR_W, h)
	bg.color = Color(0.1, 0.11, 0.13, 0.85)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)
	var fill := ColorRect.new()
	fill.position = Vector2(1, 1)
	fill.color = color
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(fill)
	return fill

func _build_buff_row() -> void:
	_buff_row = HBoxContainer.new()
	_buff_row.position = Vector2(4, 30)
	_buff_row.add_theme_constant_override("separation", 2)
	_buff_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_buff_row)

func _build_top_right() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	col.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	col.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_floor_label = _hud_label(col, "第 0 层")
	_trial_badges = TrialPanelUI.FactorBadges.new()   # M3-R-B 试炼因子角标（层数旁，零稳态分配）
	col.add_child(_trial_badges)
	_seed_label = _hud_label(col, "种子 0")
	_seed_label.modulate = Color(1, 1, 1, 0.6)
	_coin_label = _hud_label(col, "金币 0")
	_coin_label.modulate = COIN_COLOR
	_abandon_btn = Button.new()               # M3-R-C：规格 §4「放弃试炼」（暂停菜单缺席，
	_abandon_btn.name = "AbandonTrial"        # 编排者裁定入口在 HUD；仅试炼局显示）
	_abandon_btn.text = "放弃试炼"
	_abandon_btn.add_theme_font_size_override("font_size", 8)
	_abandon_btn.visible = run != null and bool(run.get("is_trial_run"))
	_abandon_btn.pressed.connect(_on_abandon_pressed)
	col.add_child(_abandon_btn)

func _build_bottom_center() -> void:
	_style_normal = StyleBoxFlat.new()
	_style_normal.bg_color = Color(0.08, 0.09, 0.11, 0.85)
	_style_normal.set_border_width_all(1)
	_style_normal.border_color = Color(0.35, 0.38, 0.42)
	_style_normal.set_content_margin_all(3.0)
	_style_active = StyleBoxFlat.new()
	_style_active.bg_color = Color(0.17, 0.15, 0.07, 0.9)
	_style_active.set_border_width_all(1)
	_style_active.border_color = COIN_COLOR
	_style_active.set_content_margin_all(3.0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	row.offset_bottom = -4.0
	for i in WEAPON_SLOTS:
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_theme_stylebox_override("panel", _style_normal)
		var name_label := Label.new()
		name_label.add_theme_font_size_override("font_size", 8)
		panel.add_child(name_label)
		row.add_child(panel)
		_slot_panels.append(panel)
		_slot_labels.append(name_label)
	_skill_ring = CdRing.new()
	_skill_ring.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_skill_ring)
	_roll_dot = ColorRect.new()
	_roll_dot.custom_minimum_size = Vector2(6, 6)
	_roll_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_roll_dot.color = DOT_DIM
	row.add_child(_roll_dot)

func _hud_label(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_font_size_override("font_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

# ---- 每帧应用（全部来自快照，不读缓存） ----

func _apply_top_left(snap: Dictionary) -> void:
	var hp := int(snap["hp"])
	var hp_max := int(snap["hp_max"])
	if hp_max != _hearts_count:
		_hearts_count = hp_max
		for c in _hearts.get_children():
			c.free()                           # 立即释放：同帧重建无闪烁
		for i in hp_max:
			var cell := ColorRect.new()
			cell.custom_minimum_size = HEART_SIZE
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_hearts.add_child(cell)
	var cells := _hearts.get_children()
	for i in cells.size():
		(cells[i] as ColorRect).color = HEART_FULL if i < hp else HEART_EMPTY
	_set_bar(_shield_fill, int(snap["shield"]), int(snap["shield_max"]), 4.0)
	_set_bar(_energy_fill, int(snap["energy"]), int(snap["energy_max"]), 3.0)

func _set_bar(fill: ColorRect, value: int, vmax: int, h: float) -> void:
	var ratio := 0.0 if vmax <= 0 else clampf(float(value) / float(vmax), 0.0, 1.0)
	fill.size = Vector2(maxf(0.0, (BAR_W - 2.0) * ratio), h - 2.0)

func _apply_buffs(snap: Dictionary) -> void:
	var keys: Array[String] = snap["buffs"]
	if keys == _buff_keys:
		return
	_buff_keys = keys.duplicate()
	for c in _buff_row.get_children():
		c.free()
	for k in keys:
		_buff_row.add_child(_make_chip(k))

func _make_chip(id: String) -> ColorRect:
	var chip := ColorRect.new()
	chip.custom_minimum_size = Vector2(18, 12)
	var row: Dictionary = GameDB.get_buff(id)
	chip.color = RARITY_COLORS.get(String(row.get("rarity", "")), Color(0.4, 0.42, 0.45, 0.9))
	chip.tooltip_text = String(row.get("name", id))
	var l := Label.new()
	l.text = buff_abbrev(id)
	l.add_theme_font_size_override("font_size", 8)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(l)
	return chip

func _apply_top_right(snap: Dictionary) -> void:
	_floor_label.text = "第 %d 层" % int(snap["floor_idx"])
	_seed_label.text = "种子 %d" % int(snap["run_seed"])
	_coin_label.text = "金币 %d" % int(snap["coins"])
	_trial_badges.sync(run)   # M3-R-B：试炼局两枚因子图标（tooltip=名称：文案），非试炼零开销
	if _abandon_btn != null:  # M3-R-C：放弃试炼仅试炼局显示（bool 同步无分配）
		_abandon_btn.visible = run != null and bool(run.get("is_trial_run"))

func _apply_bottom(snap: Dictionary) -> void:
	var names: Array[String] = snap["weapon_names"]
	var slot := int(snap["current_slot"])
	for i in _slot_labels.size():
		_slot_labels[i].text = names[i] if i < names.size() else ""
		_slot_panels[i].add_theme_stylebox_override(
			"panel", _style_active if i == slot else _style_normal)
	_skill_ring.ratio = float(snap["skill_cd_ratio"])
	_skill_ring.cd_done = bool(snap["skill_ready"])
	_skill_ring.queue_redraw()
	_roll_dot.color = DOT_READY if bool(snap["roll_ready"]) else DOT_DIM

## 放弃试炼（M3-R-C，规格 §4；暂停菜单全库缺席——编排者裁定入口在 HUD）：按当前进度
## 结算（已过层 + 击杀池现值 ×1.5 floored，无死亡减半——GDD §14 仅死亡减半）→
## settlement_record（records 追加 + trial_completed + trials_total 并档落盘）→
## 回主菜单（试炼面板在主菜单覆盖层，与死亡/胜利结算回菜单口径一致；规格字面
## 「回试炼面板」的偏离随 G-1 走查统一勘误）。
func _on_abandon_pressed() -> void:
	var awarded := RunState.settle_victory_gems()
	if awarded > 0:
		SaveSystem.add_gems(awarded)
	TrialPanelUI.settlement_record(awarded, false)
	if abandon_route_override.is_valid():
		abandon_route_override.call()
		return
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and router.has_method("goto"):
		router.call("goto", "menu")

## 技能 CD 环：暗环垫底 + 亮弧按 ratio 顺时针收缩（就绪绿 / 冷却橙）。
class CdRing extends Control:
	var ratio := 0.0
	var cd_done := true

	func _init() -> void:
		custom_minimum_size = Vector2(16, 16)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0 - 1.0
		draw_arc(c, r, 0.0, TAU, 32, Color(1, 1, 1, 0.15), 2.0, true)
		if ratio > 0.0:
			draw_arc(c, r, -PI / 2.0, -PI / 2.0 + TAU * ratio, 32,
				RING_READY if cd_done else RING_COOLING, 2.0, true)
