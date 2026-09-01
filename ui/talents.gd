class_name Talents
extends Control
## 天赋树界面（m2-t15）：三系（红攻击/蓝防御/绿资源）×8 层列状排布 + 购买按钮 +
## 蓝晶余额。节点名称/价格/描述/前置全部读 GameDB.talents（data/talents.json，T2 表），
## 场景零硬编码玩法数值；蓝晶余额与购买走 TalentSystem（SaveSystem 后端持久化）。
## 状态色：已购=系色亮框 ✓ / 可购=白框 ◆价格 / 锁定=灰（前置未满足）。
## 手动验证：godot --path . res://ui/talents.tscn（读真实 user://save.json）；
## 主菜单入口与 SceneRouter 路由键接线归后续收口卡（本卡不动 main_menu/scene_router）。

const BRANCHES: Array[String] = ["red", "blue", "green"]
const BRANCH_TITLES := {"red": "红·攻击", "blue": "蓝·防御", "green": "绿·资源"}
const BRANCH_COLORS := {
	"red": Color(0.90, 0.35, 0.30),
	"blue": Color(0.40, 0.60, 0.95),
	"green": Color(0.45, 0.80, 0.45),
}
const LOCKED_COLOR := Color(0.42, 0.44, 0.48)
const GEM_COLOR := Color(0.55, 0.80, 0.95)
const CARD_BG := Color(0.07, 0.08, 0.1, 0.95)
const NODE_MIN := Vector2(138, 18)
const DEFAULT_DETAIL := "点击节点查看详情；可购节点点击即购买"

## 购买后端系统；测试可注入（临时档 SaveSystem），_ready 兜底自动解析 autoload。
var system: TalentSystem = null

var _nodes: Dictionary = {}    # talent id -> Button
var _columns: Dictionary = {}  # branch -> VBoxContainer

func _ready() -> void:
	if system == null:
		system = TalentSystem.new()   # _default_save 解析 /root/SaveSystem
	$BackBtn.pressed.connect(_on_back_pressed)
	_build_columns()
	_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		var code: int = key.keycode if key.keycode != KEY_NONE else key.physical_keycode
		if code == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_on_back_pressed()

## 三系列：每系一个 PanelContainer 列，头标 + tier 1..8 纵向堆叠（列内自上而下即
## 前置链方向，分叉拓扑经详情面板的前置文案表达——480×270 下不画连线）。
func _build_columns() -> void:
	var row: HBoxContainer = $Branches
	for branch in BRANCHES:
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(panel)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		panel.add_child(box)
		_columns[branch] = box
		var header := _label(String(BRANCH_TITLES[branch]), 12, BRANCH_COLORS[branch])
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(header)
		var ids := _branch_ids_sorted(branch)
		for id in ids:
			var btn := Button.new()
			btn.custom_minimum_size = NODE_MIN
			btn.add_theme_font_size_override("font_size", 12)
			btn.pressed.connect(_on_node_pressed.bind(String(id)))
			box.add_child(btn)
			_nodes[String(id)] = btn

## 全量刷新：蓝晶余额 + 各节点按钮态（文案/描边/可用性）。
func _refresh() -> void:
	if system == null or system.save_system == null:
		return
	$Gems.text = "蓝晶 %d" % int(system.save_system.gems())
	var avail := {}
	for id in system.available():
		avail[id] = true
	for id: String in _nodes:
		var btn: Button = _nodes[id]
		var row_data: Dictionary = GameDB.get_talent(id)
		var branch := String(row_data["branch"])
		if system.is_purchased(id):
			btn.text = "✓ T%d %s" % [int(row_data["tier"]), String(row_data["name"])]
			btn.disabled = false                       # 已购仍可点开详情
			_style_node(btn, BRANCH_COLORS[branch], BRANCH_COLORS[branch])
		elif avail.has(id):
			btn.text = "T%d %s ◆%d" % [int(row_data["tier"]), String(row_data["name"]),
				int(row_data["cost"])]
			btn.disabled = false
			_style_node(btn, Color.WHITE, GEM_COLOR)
		else:
			btn.text = "T%d %s ◇%d" % [int(row_data["tier"]), String(row_data["name"]),
				int(row_data["cost"])]
			btn.disabled = false                       # 锁定节点点击查看前置（非禁用态）
			_style_node(btn, LOCKED_COLOR, LOCKED_COLOR)

func _on_node_pressed(id: String) -> void:
	var row_data := GameDB.get_talent(id)
	if row_data.is_empty():
		return
	if system.is_purchased(id):
		_show_detail(id, "已购买")
		return
	if not system.is_available(id):
		_show_detail(id, "前置未满足：%s" % _require_names(row_data))
		return
	if system.buy(id):
		_show_detail(id, "购买成功")
	else:
		_show_detail(id, "蓝晶不足（还需 ◆%d）" % (int(row_data["cost"]) - int(system.save_system.gems())))
	_refresh()

func _show_detail(id: String, status: String) -> void:
	var row_data := GameDB.get_talent(id)
	$Detail.text = "%s ｜ %s\n%s\n%s ｜ %s" % [String(row_data["name"]), status,
		String(row_data["desc"]), _effect_summary(row_data), _require_names(row_data)]

## 效果文案：白名单键 → 中文量纲（int 直值 / 百分键 ×100%；roll_cd_pct 负=缩短）。
func _effect_summary(row_data: Dictionary) -> String:
	var parts: Array[String] = []
	var eff: Dictionary = row_data["effects"]
	for k: String in eff:
		if GameDB.TALENT_INT_KEYS.has(k):
			parts.append("%s%+d" % [k, int(eff[k])])
		elif k == "roll_cd_pct":
			parts.append("%s%.0f%%" % [k, float(eff[k]) * 100.0])
		else:
			parts.append("%s%+.0f%%" % [k, float(eff[k]) * 100.0])
	return " ".join(parts)

func _require_names(row_data: Dictionary) -> String:
	var requires: Array = row_data["requires"]
	if requires.is_empty():
		return "无前置"
	var names: Array[String] = []
	for req: Variant in requires:
		names.append(String(GameDB.get_talent(String(req)).get("name", req)))
	return "前置：" + "、".join(names)

func _branch_ids_sorted(branch: String) -> Array:
	var ids: Array = []
	for id: String in GameDB.talents:
		if String(GameDB.talents[id]["branch"]) == branch:
			ids.append(id)
	ids.sort_custom(_tier_less)
	return ids

func _tier_less(a: Variant, b: Variant) -> bool:
	return int(GameDB.talents[a]["tier"]) < int(GameDB.talents[b]["tier"])

## 返回：SceneRouter 缺席（独立运行场景）时无操作不崩。
func _on_back_pressed() -> void:
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and get_tree() != null and get_tree().current_scene == self:
		router.goto("menu")

func _style_node(btn: Button, border: Color, text_color: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD_BG
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.set_content_margin_all(3)
	btn.add_theme_stylebox_override("normal", sb)
	var sb_hover := sb.duplicate()
	sb_hover.border_color = border.lightened(0.3)
	btn.add_theme_stylebox_override("hover", sb_hover)
	btn.add_theme_stylebox_override("pressed", sb_hover)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", text_color)
	btn.add_theme_color_override("font_hover_color", text_color.lightened(0.2))
	btn.add_theme_color_override("font_pressed_color", text_color.lightened(0.2))

func _label(text: String, font_size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l
