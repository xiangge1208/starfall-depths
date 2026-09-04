class_name HeroSelect
extends Control
## 选角界面（m1-t11）：6 英雄展示 GameDB.heroes（中文名/面板/被动/技能名+描述/初始武器中文名）。
## M4-K2 布局重排：卡行收进 CardScroll 横向滚动（撤 m3-font-walkthrough §3.6「1316px vs
## 480px」S-C 豁免）——三案取舍定横滚：缩卡网格在 270px 高度下容不下 6 卡文本量（必截字，
## 破 12px 可读性下限）；分页翻页会把 3 张卡藏出树外（focus_neighbors 链物理断开 + 触屏
## 翻页多打两跳）；横滚 6 卡全程在树（导航序闭合），滑动为触屏原生手势。
##
## m4p-ui1 视觉重做（用户反馈「几个大方框左右选，太丑」）：K2 的「6 张 206px 自足卡」
## 把同一份长文案抄 6 遍，480px 视窗一次只见 2 张，读起来是一列信息墙。改为
## **铭牌行 + 共享详情面板** 的选择器语义（对标《元气骑士》选人页）：
##   ① 上排 6 枚 72px 铭牌（立绘 + 中文名 + 解锁角标），6 枚一屏全见、无需滚动即可
##      比较——横滚容器保留（触屏惯例 + follow_focus + 窄屏兜底），只是不再必须滚；
##   ② 下方 Detail 面板只渲染**当前选中**英雄的面板数值/被动/技能/初始武器——长文案
##      从 6 份降到 1 份，同等像素预算下每行可给到全宽，不再靠 autowrap 挤进 206px；
##   ③ 选中态用「金色描边 + 顶部高亮条 + 立绘微放大」替代原「仅描边换色」，48px 铭牌
##      在 12px 字体下靠单像素描边区分度不足。
## 数值展示改芯片化（HP/盾/蓝/速/暴击 逐项独立底色块），替代原 "\n" 拼接的两行纯文本。
## 结构契约保持（既有测试口径不动）：CardScroll/Cards 层级、6 卡 FOCUS_ALL + gui_input
## 轻点判定 + focus_neighbors 闭环、_portraits 64px、_passive_icons 24px、_skill_icons
## 32px、_badges 角标文案、_name_labels 选中金字——被动/技能图标随详情面板走（每英雄
## 仍各一枚，注册表逐 id 对位不变）。
## 导航三路：①keyboard/gamepad——卡 FOCUS_ALL + focus_neighbors 闭环（卡 5 右跳回
## 卡 0），follow_focus 自动把焦点卡滚进可视域，A/D/摇杆（move_left/right 动作）走
## 既有 _move 并回写焦点（两路汇一）；确认 = Enter/Space/手柄 A（ui_accept）；
## ②鼠标——按下记录、松开位移 ≤8px 才算点击选中（触摸滑动起手不再误触发选择）；
## ③触屏——卡上滑动 = 滚动（ScrollContainer 原生），轻点 = 选中（同 ② 释放判定）。
## 选择落地：优先调 RunState autoload 的 select_hero 钩子（T15 未合并则节点不存在，
## 用 /root 路径探测——Engine.has_singleton 只认原生单例，对 GDScript autoload 恒 false）；
## 无钩子时落 HeroSelect.last_chosen 静态暂存（T15 合并时收编）。
## 换场景路由由 T23 加线（hero_chosen 后守卫探测 /root/SceneRouter → goto("game")）。
## M4.5 u3 美术接线：卡首行立绘 portrait_<hero_id>.png（32x32 ×2 整数放大）+ 被动/技能
## 行前小图标（passive_* 12x12 ×2 / skill_* 16x16 ×2，全部 NEAREST）——art/generated/ui
## 生成器注释明示用途=选人卡，此前零引用。skill 图 6/6 显式映射（gen_placeholder_art*.py
## 把技能图与英雄/技能名成对注释，含 assassin 残影斩→skill_afterimage_slash——其
## skill_script 与游侠共享 shadowstep 命名，规则推不出，必须表驱动）。解锁状态视觉标签：
## 只读 SaveSystem.data.unlocked_heroes（该键无正式访问器，achievement_system 同款
## data 键读取）；SaveSystem 缺席/键损 fail-SOFT 全解锁（同存档系统宁纵基调，测试零漂移）。
## 过渡语义：未解锁卡仅加右上角「待解锁·开放体验」角标 + 立绘半透明，不锁点击/不锁
## _choose（购买流未上线，全部开放试玩；裁定购买流后再收紧）。

signal hero_chosen(hero_id: String)

## m4p-ui1 铭牌尺寸：72 宽容纳 64px 立绘 + 左右 4px 内边距；96 高 = 立绘 64 + 名字行
## 16 + 边距。6×72 + 5×6 间距 = 462 ≤ 468 视窗宽 → 一屏全见（横滚仅作窄屏/触屏兜底）。
const CARD_MIN := Vector2(72, 96)
const TAP_SLOP := 8.0   # 点击判定位移阈（px）：内=轻点选中，外=滑动滚动不选中
const CARD_BG := Color(0.09, 0.10, 0.13, 0.95)
const CARD_BG_SELECTED := Color(0.16, 0.15, 0.11, 0.98)   # 选中铭牌暖色底（描边之外的第二重区分）
const SELECTED_BORDER := Color(0.95, 0.82, 0.35)
const IDLE_BORDER := Color(0.25, 0.27, 0.32)
const DETAIL_BG := Color(0.07, 0.08, 0.1, 0.95)
const PASSIVE_COLOR := Color(0.55, 0.85, 0.55)
const SKILL_COLOR := Color(0.55, 0.75, 0.95)
const WEAPON_COLOR := Color(0.85, 0.8, 0.6)
const LOCKED_PORTRAIT_ALPHA := 0.45   # 未解锁立绘半透明（视觉暗示，不锁交互）
## 面板数值芯片（逐项独立底色块，替代 "\n" 两行纯文本）：键序即展示序。
const STAT_CHIPS := [
	{"label": "HP", "key": "hp", "color": Color(0.92, 0.45, 0.45)},
	{"label": "盾", "key": "shield", "color": Color(0.45, 0.7, 0.95)},
	{"label": "蓝", "key": "energy", "color": Color(0.6, 0.55, 0.95)},
	{"label": "速", "key": "speed", "color": Color(0.55, 0.85, 0.6)},
	{"label": "暴击", "key": "crit_chance", "color": Color(0.95, 0.82, 0.35)},
]
# 被动中文文案（GDD §6；heroes 行只带 passive_id，展示文案归 UI 层）
const PASSIVES := {
	"defiance": "坚守：护盾破碎时对 60px 内敌人 1 伤+击退+眩晕 0.5s",
	"hawk_eye": "鹰眼：暴击时 50% 概率返还 1 蓝",
	"spare_parts": "备件：开局带 1 台便携炮台（存活 12s），每进入新一层补 1 台",
	"echo": "回响：法杖/激光类武器伤害 +15%",
	"blessing": "祝福：每进入新层回满护盾并 +5% 全伤害（单局至多叠 4 层）",
	"shadow_reap": "掠影：近战击杀返还 5 蓝，1s 内翻滚无冷却",
}
## 被动/技能图标映射（art/generated/ui，表驱动同 PASSIVES 文案先例）：生成器
## （gen_placeholder_art.py / _m2.py）把图标与英雄/被动成对注释，其中
## hawk_eye→passive_hawkeye（去下划线）与 shadow_reap→passive_swift_shadow
## （生成器沿用旧 passive id 命名）非纯规则可推，故全量显式表驱动。
const PASSIVE_ICONS := {
	"defiance": "passive_defiance",
	"hawk_eye": "passive_hawkeye",
	"spare_parts": "passive_spare_parts",
	"echo": "passive_echo",
	"blessing": "passive_blessing",
	"shadow_reap": "passive_swift_shadow",
}
## 技能图（skill_* 基础版 6 张；_plus 强化版留技能升级流接线，选角卡用基础版）。
const SKILL_ICONS := {
	"vanguard": "skill_rampage",          # 狂潮（骑士·凛）
	"ranger": "skill_shadowstep",         # 影袭（游侠·苇）
	"assassin": "skill_afterimage_slash", # 残影斩（刺客·蝉；脚本与游侠共享命名，生成器明示配对）
	"engineer": "skill_turret",           # 自动炮台（工程师·铆）
	"mage": "skill_arcane_nova",          # 奥术新星（法师·烬）
	"guardian": "skill_life_tide",        # 生命潮汐（守护者·萄）
}

static var last_chosen := ""   # 静态暂存 fallback（RunState 未合并期间的选角结果）

var _ids: Array = []
var _selected := 0
var _cards: Array[PanelContainer] = []
var _name_labels: Array[Label] = []          # 选中金字高亮寻址（u3 布局重排后不再按 child 序猜）
var _portraits: Array[TextureRect] = []      # u3：卡首立绘（解锁状态 modulate 寻址）
var _passive_icons: Array[TextureRect] = []  # u3：被动行小图标
var _skill_icons: Array[TextureRect] = []    # u3：技能行小图标
var _badges: Array[Control] = []             # u3：未解锁角标（待解锁·开放体验）
var _accents: Array[ColorRect] = []          # ui1：选中铭牌顶部高亮条（48px 下描边区分度补强）
## ui1 详情面板（共享单份，随 _selected 重建内容）：_detail_slots 存各段容器，
## 逐英雄的被动/技能图标注册表按 id 对位预建一次（_passive_icons/_skill_icons
## 长度恒 6 的既有契约不变），切换时只改可见性与文案，不重建图标节点。
var _detail_name: Label = null
var _detail_stats: HBoxContainer = null
var _detail_rows: VBoxContainer = null
var _passive_rows: Array[Control] = []
var _skill_rows: Array[Control] = []
var _passive_labels: Array[Label] = []
var _skill_labels: Array[Label] = []
var _detail_weapon: Label = null
var _detail_badge: Label = null
var _unlocked: Array[String] = []            # 构建期解锁快照（_resolve_unlocks 落填）
var _all_unlocked := false                   # true = 全解锁语义（SaveSystem 缺席/键损）
## 测试缝（生产恒零值）：unlocked_override 非 null 时替代 SaveSystem 快照（注入
## 确定态，不触碰环境档）；ignore_save = true 模拟 SaveSystem 缺席路径。
var unlocked_override: Variant = null
var ignore_save := false
var _press_idx := -1          # 按压中的卡索引（-1 = 无），释放时按位移判轻点/滑动
var _press_pos := Vector2.ZERO

func _ready() -> void:
	_ids = GameDB.heroes.keys()
	if _ids.is_empty():
		push_error("HeroSelect: no heroes loaded")
		return
	_resolve_unlocks()
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

## ui1 铭牌行：每枚 = 立绘 + 中文名 + 顶部高亮条 + 解锁角标。长文案不进铭牌
## （归共享详情面板），因此铭牌无 autowrap 压力，6 枚 72px 一屏全见。
func _build_cards() -> void:
	var row: HBoxContainer = $CardScroll/Cards
	for i in _ids.size():
		var id := String(_ids[i])
		var card := PanelContainer.new()
		card.custom_minimum_size = CARD_MIN
		card.size_flags_vertical = Control.SIZE_SHRINK_CENTER   # 铭牌不被容器拉高
		card.focus_mode = Control.FOCUS_ALL          # keyboard/gamepad 焦点可落卡
		card.gui_input.connect(_on_card_input.bind(i))
		card.focus_entered.connect(_on_card_focus.bind(i))
		row.add_child(card)
		_cards.append(card)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		card.add_child(box)
		var hero: Dictionary = GameDB.get_hero(id)
		var locked := not is_hero_unlocked(id)
		# 顶部高亮条（选中态第三重信号；未选中时透明保位，不产生布局抖动）
		var accent := ColorRect.new()
		accent.custom_minimum_size = Vector2(0, 2)
		accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
		accent.color = Color(SELECTED_BORDER, 0.0)
		_accents.append(accent)
		box.add_child(accent)
		var portrait := _icon("portrait_%s" % id, 64, 32)
		portrait.modulate = Color(1.0, 1.0, 1.0, LOCKED_PORTRAIT_ALPHA if locked else 1.0)
		portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_portraits.append(portrait)
		box.add_child(portrait)
		var name_label := _label(String(hero.get("name", id)), 12)
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # 「骑士·凛」级短名兜底
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_name_labels.append(name_label)
		box.add_child(name_label)
		# u3 解锁角标（右上角覆盖层，零纵向占位）：PanelContainer 会把全部子节点撑到
		# 内容矩形，overlay 置于 box 之后 = 盖在卡面上层；全链 MOUSE_FILTER_IGNORE
		# 防吞卡的轻点判定。过渡语义只做视觉：不锁焦点/不锁 _choose。
		# ui1：72px 铭牌容不下「待解锁/开放体验」两行文案 → 角标退化为单枚锁形标记，
		# 两行文案移入详情面板（_detail_badge，仅选中未解锁英雄时显示）。角标只承担
		# 「这枚被锁」的一览信号，详情面板承担「但仍可试玩」的解释——分工后铭牌行
		# 不再有文字溢出压力（font_render_smoke「Label 收在卡内」专项对此即时报警）。
		var overlay := Control.new()
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(overlay)
		var badge := PanelContainer.new()
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_theme_stylebox_override("panel", _badge_style())
		var badge_col := VBoxContainer.new()
		badge_col.add_theme_constant_override("separation", 0)
		badge.add_child(badge_col)
		badge_col.add_child(_label("锁", 12, Color(0.95, 0.82, 0.35)))
		overlay.add_child(badge)
		badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 1)
		badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		badge.grow_vertical = Control.GROW_DIRECTION_END
		badge.visible = locked
		_badges.append(badge)
	_build_detail()
	_wire_focus_chain()


## ui1 共享详情面板（单份，随选中英雄改文案）：名字行 + 数值芯片行 + 被动/技能行
## + 初始武器行 + 未解锁提示。被动/技能图标逐英雄预建 6 份（既有注册表长度契约），
## 仅当前英雄那份可见——切换零节点重建，避免每次选人重跑 load()。
func _build_detail() -> void:
	var panel: PanelContainer = $Detail
	panel.add_theme_stylebox_override("panel", _detail_style())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	panel.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	col.add_child(head)
	_detail_name = _label("", 12, SELECTED_BORDER)
	head.add_child(_detail_name)
	_detail_badge = _label("待解锁 · 开放体验", 12, Color(0.72, 0.75, 0.8))
	head.add_child(_detail_badge)
	_detail_stats = HBoxContainer.new()
	_detail_stats.add_theme_constant_override("separation", 4)
	col.add_child(_detail_stats)
	for chip: Dictionary in STAT_CHIPS:
		_detail_stats.add_child(_stat_chip(String(chip["label"]), "", chip["color"] as Color))
	_detail_rows = VBoxContainer.new()
	_detail_rows.add_theme_constant_override("separation", 2)
	col.add_child(_detail_rows)
	for i in _ids.size():
		var id := String(_ids[i])
		var hero: Dictionary = GameDB.get_hero(id)
		var passive := _label("", 12, PASSIVE_COLOR)
		passive.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		passive.text = "被动 %s" % str(PASSIVES.get(hero.get("passive_id", ""),
			hero.get("passive_id", "?")))
		_passive_labels.append(passive)
		_passive_rows.append(_add_icon_row(_detail_rows, _passive_icons,
			String(PASSIVE_ICONS.get(hero.get("passive_id", ""))), passive, 24))
		var skill := _label("", 12, SKILL_COLOR)
		skill.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		skill.text = "%s %s" % [str(hero.get("skill_name", "?")), str(hero.get("skill_desc", ""))]
		_skill_labels.append(skill)
		_skill_rows.append(_add_icon_row(_detail_rows, _skill_icons,
			String(SKILL_ICONS.get(id, "")), skill, 32))
	_detail_weapon = _label("", 12, WEAPON_COLOR)
	_detail_weapon.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_detail_weapon)


## 详情面板内容同步（选中变化时调用；纯改文案/可见性，零节点增删）。
func _sync_detail() -> void:
	if _detail_name == null or _selected < 0 or _selected >= _ids.size():
		return
	var id := String(_ids[_selected])
	var hero: Dictionary = GameDB.get_hero(id)
	_detail_name.text = String(hero.get("name", id))
	var locked := not is_hero_unlocked(id)
	_detail_badge.visible = locked
	for i in _detail_stats.get_child_count():
		if i >= STAT_CHIPS.size():
			break
		var chip: Dictionary = STAT_CHIPS[i]
		var key := String(chip["key"])
		var value := ""
		if key == "crit_chance":
			value = "%d%%" % roundi(float(hero.get(key, 0.0)) * 100.0)
		elif key == "speed":
			value = "%.0f" % float(hero.get(key, 0.0))
		else:
			value = str(int(hero.get(key, 0)))
		var chip_node := _detail_stats.get_child(i) as PanelContainer
		var value_label := chip_node.get_child(0).get_child(1) as Label
		value_label.text = value
	for i in _ids.size():
		var on := i == _selected
		_passive_rows[i].visible = on
		_skill_rows[i].visible = on
	_detail_weapon.text = "初始 %s" % _weapon_names(hero.get("start_weapons", []))


## 数值芯片：底色块 + 「标签 值」两段（标签暗、值亮，12px 下靠明度分层而非字号）。
func _stat_chip(label_text: String, value_text: String, accent: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(accent.r, accent.g, accent.b, 0.14)
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.5)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	chip.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(row)
	row.add_child(_label(label_text, 12, Color(0.62, 0.65, 0.7)))
	row.add_child(_label(value_text, 12, accent))
	return chip

## 解锁快照（构建期一次）：优先测试注入 → SaveSystem.data.unlocked_heroes（该键无
## 正式访问器，走 achievement_system 同款 data 键只读）；SaveSystem 缺席/档容器/键型
## 异常一律 fail-SOFT 全解锁（同存档系统「宁纵勿锁」基调，测试与无头环境零漂移）。
func _resolve_unlocks() -> void:
	_unlocked.clear()
	_all_unlocked = false
	if ignore_save:
		_all_unlocked = true
		return
	if unlocked_override != null:
		for e: Variant in unlocked_override:
			if typeof(e) == TYPE_STRING:
				_unlocked.append(e)
		return
	var ss := get_node_or_null("/root/SaveSystem")
	if ss == null:
		_all_unlocked = true
		return
	var d: Variant = ss.get("data")
	if typeof(d) != TYPE_DICTIONARY:
		_all_unlocked = true
		return
	var arr: Variant = d.get("unlocked_heroes")
	if typeof(arr) != TYPE_ARRAY:
		_all_unlocked = true
		return
	for e: Variant in arr:
		if typeof(e) == TYPE_STRING:
			_unlocked.append(e)

## 解锁查询（构建期快照，公开给测试/后续购买流消费）：全解锁语义恒真。
func is_hero_unlocked(id: String) -> bool:
	return _all_unlocked or _unlocked.has(id)

## 图标行装配：行首小图标（fail-closed 缺图隐藏、行退化纯文字）+ 文案吃剩余宽。
## 返回行容器——ui1 详情面板按行控制可见性（每英雄一份，仅选中那份显示）。
func _add_icon_row(box: VBoxContainer, registry: Array[TextureRect], stem: String,
		label: Label, px: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	box.add_child(row)
	var icon := _icon(stem, px, px / 2)   # 生成器原生 12/16px → ×2 整数放大
	registry.append(icon)
	row.add_child(icon)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	return row

## art/generated/ui 小图工厂：NEAREST 最近邻 + 整数 ×2 放大 + 不吞鼠标
## （卡轻点判定按 gui_input 走 PanelContainer，子控件必须全链穿透）。
func _icon(stem: String, display_px: int, source_px: int) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.size_flags_vertical = Control.SIZE_SHRINK_BEGIN   # 顶对齐首行文案
	var t := _ui_tex(stem)
	if t != null:
		tr.texture = t
		tr.custom_minimum_size = Vector2(display_px, display_px)
		if int(t.get_width()) != source_px or int(t.get_height()) != source_px:
			push_warning("HeroSelect: '%s' 原生尺寸 %dx%d ≠ %dx2 整数放大基准" % [
				stem, int(t.get_width()), int(t.get_height()), source_px])
	else:
		tr.visible = false   # fail-closed：无图退回纯文字布局（同 ArtLookup 表契约）
	return tr

static func _ui_tex(stem: String) -> Texture2D:
	if stem.is_empty():
		return null
	var t := load("res://art/generated/ui/%s.png" % stem) as Texture2D
	if t == null:
		push_warning("HeroSelect: ui art missing '%s'" % stem)
	return t

func _detail_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = DETAIL_BG
	sb.border_color = Color(0.2, 0.22, 0.27)
	sb.set_border_width_all(1)
	sb.border_width_top = 2                 # 顶边加重：与上方铭牌行的视觉分隔线
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(5)
	return sb


func _badge_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.14, 0.17, 0.92)
	sb.border_color = Color(0.45, 0.47, 0.52)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.set_content_margin_all(3)
	return sb

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

## 高亮刷新：选中铭牌金描边 + 暖底 + 顶部高亮条 + 立绘微放大 + 金字，其余灰
## （样式整体重建，与 BuffPick 同手法）；卡名寻址走 _name_labels（名字不在固定
## child 序位）。ui1：48px 级铭牌单靠 1px 描边换色区分度不足，故四重叠加。
## 末尾同步共享详情面板（选中英雄的长文案单份渲染）。
func _refresh() -> void:
	for i in _cards.size():
		var on := i == _selected
		_cards[i].add_theme_stylebox_override("panel",
			_card_style(SELECTED_BORDER if on else IDLE_BORDER, on))
		if i < _name_labels.size():
			_name_labels[i].add_theme_color_override("font_color",
				SELECTED_BORDER if on else Color(0.78, 0.8, 0.85))
		if i < _accents.size():
			_accents[i].color = Color(SELECTED_BORDER, 1.0 if on else 0.0)
		if i < _portraits.size():
			# 选中立绘 ×1.08 轻放大（pivot 居中，整数像素外观不破——TEXTURE_FILTER_NEAREST
			# 下缩放仍走最近邻，无插值糊边）；未选中恒 1.0。
			var p := _portraits[i]
			p.pivot_offset = p.custom_minimum_size * 0.5
			p.scale = Vector2.ONE * (1.08 if on else 1.0)
	_sync_detail()

## 初始武器中文名（经 GameDB weapons 表，未知 id 防御性回退）
func _weapon_names(ids: Array) -> String:
	var names: Array[String] = []
	for wid: Variant in ids:
		names.append(str(GameDB.get_weapon(String(wid)).get("name", wid)))
	return " + ".join(names)

func _card_style(border: Color, selected := false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD_BG_SELECTED if selected else CARD_BG
	sb.border_color = border
	sb.set_border_width_all(2 if selected else 1)   # 选中加粗描边（未选中收细，减视觉噪声）
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(4)
	return sb

func _label(text: String, font_size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l
