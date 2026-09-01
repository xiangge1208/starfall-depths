class_name Codex
extends Control
## 武器图鉴墙（m2-t20）：115 格 GridContainer 数据驱动渲染——GameDB.weapons_all 全量
## 逐把一格。已解锁：亮色描边（稀有度色）+ 图标（ArtLookup.weapon_icon_path，缺图回落
## 色块）+ 真名；未解锁：灰描边 + "???" + 解锁条件中文（unlock_tasks.desc 直读 + 进度）。
## 关闭按钮 → SceneRouter.goto("menu")（路由守卫同 main_menu 手法：缺席不动作不崩）。
## 纯展示：进度/解锁状态每次 open/入树时由 CodexSystem 现读，不持有持久状态。
## 手动验证：godot --path . res://ui/codex.tscn（或主菜单「图鉴」按钮进入）。

const GRID_COLUMNS := 7
const CELL_MIN := Vector2(60, 104)   # 12px 基准：4 字名 48px + 条件 5 行；115 把 / 7 列 = 纵向滚动
const CARD_BG := Color(0.07, 0.08, 0.1, 0.96)
const LOCKED_COLOR := Color(0.45, 0.47, 0.52)
const RARITY_COLORS := {
	"common": Color("cfd2d6"), "uncommon": Color("6ee86e"), "rare": Color("5ab0ff"),
	"epic": Color("b06cff"), "legend": Color("ffa64d"),
}

var codex_system: Node = null   # 测试注入缝；_ready 兜底探测 /root/CodexSystem
var _router: Node = null        # /root/SceneRouter 探测缓存
var _cells: Array[String] = []  # 渲染顺序的武器 id（字典序 = 全名录稳定排序）

@onready var _grid: GridContainer = $Center/Panel/VBox/Scroll/Grid
@onready var _summary: Label = $Center/Panel/VBox/Summary

func _ready() -> void:
	if codex_system == null:
		codex_system = get_node_or_null("/root/CodexSystem")
	_router = get_node_or_null("/root/SceneRouter")
	$Center/Panel/VBox/CloseBtn.pressed.connect(_on_close_pressed)
	_rebuild()

## 入树即渲染（路由场景整页打开）；解锁状态变化后重开本页自动刷新。
func open() -> void:
	_rebuild()

func _rebuild() -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)   # 先摘再排毁：重开同帧不残留旧格
		c.queue_free()
	_cells.clear()
	for id: String in GameDB.weapons_all:
		_cells.append(id)
	_cells.sort()
	for id in _cells:
		_grid.add_child(_make_cell(id))
	_summary.text = "已解锁 %d / %d" % [unlocked_count(), _cells.size()]

func _make_cell(weapon_id: String) -> PanelContainer:
	var row: Dictionary = GameDB.weapons_all[weapon_id]
	var unlocked := _is_unlocked(weapon_id)
	var border: Color = LOCKED_COLOR if not unlocked \
		else RARITY_COLORS.get(String(row.get("rarity", "common")), Color.WHITE)
	var cell := PanelContainer.new()
	cell.custom_minimum_size = CELL_MIN
	cell.clip_contents = true   # 长条件文案裁在格内，不溢出压邻格
	cell.add_theme_stylebox_override("panel", _cell_style(border))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	cell.add_child(box)
	box.add_child(_make_icon(weapon_id, unlocked))
	# 名称：已解锁亮真名；未解锁灰 + "???"（附录 A 解锁规则口径）
	var name_l := _label("???" if not unlocked else String(row.get("name", weapon_id)), 12,
		Color.WHITE if unlocked else LOCKED_COLOR)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY   # 5 字名（左轮·正午）断行防破格
	box.add_child(name_l)
	# 条件行：未解锁 = unlock_tasks.desc 直读 + cur/goal 进度；已解锁 = 类别小字
	var cond := _label(_cond_text(weapon_id, unlocked), 12, LOCKED_COLOR)
	cond.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cond.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	cond.custom_minimum_size = Vector2(CELL_MIN.x - 8.0, 0)
	box.add_child(cond)
	return cell

## 图标：ui/weapons/<id>.png（缺图回落暗色占位块——同 training_room 回落口径，
## art 侧 10 把尚未生成图标，补图后自动点亮）。
func _make_icon(weapon_id: String, unlocked: bool) -> Control:
	var path := ArtLookup.weapon_icon_path(weapon_id)
	if ResourceLoader.exists(path):
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(16, 16)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.modulate = Color.WHITE if unlocked else Color(0.6, 0.6, 0.65, 1.0)
		icon.texture = load(path)
		return icon
	var ph := ColorRect.new()
	ph.custom_minimum_size = Vector2(16, 16)
	ph.color = Color(0.16, 0.18, 0.22, 1.0)
	return ph

## 未解锁：条件中文（unlock_tasks.desc）+ 进度；已解锁：类别；未知任务：仅 "未解锁"。
func _cond_text(weapon_id: String, unlocked: bool) -> String:
	if unlocked:
		return String(GameDB.weapons_all.get(weapon_id, {}).get("category", ""))
	if codex_system == null:
		return "未解锁"
	var p: Dictionary = codex_system.progress(weapon_id)
	var desc := String(codex_system.tasks.get(weapon_id, {}).get("desc", ""))
	if desc.is_empty():
		return "未解锁"
	return "%s（%d/%d）" % [desc, int(p["cur"]), int(p["goal"])]

func _is_unlocked(weapon_id: String) -> bool:
	if codex_system == null:
		return true   # 缺席兜底（纯展示不崩）：按全解锁渲染真名
	return bool(codex_system.is_unlocked(weapon_id))

func unlocked_count() -> int:
	if codex_system == null:
		return _cells.size()
	var n := 0
	for id in _cells:
		if _is_unlocked(id):
			n += 1
	return n

# ---- 测试/接线视图 ----

func cell_count() -> int:
	return _cells.size()

## 单格渲染快照（数据驱动断言缝）：{unlocked, name_text, cond_text}。
func cell_info(weapon_id: String) -> Dictionary:
	var unlocked := _is_unlocked(weapon_id)
	var row: Dictionary = GameDB.weapons_all.get(weapon_id, {})
	return {
		"unlocked": unlocked,
		"name_text": "???" if not unlocked else String(row.get("name", weapon_id)),
		"cond_text": _cond_text(weapon_id, unlocked),
	}

func summary_text() -> String:
	return _summary.text

# ---- 关闭 ----

func _on_close_pressed() -> void:
	if _router != null:
		_router.goto("menu")
	else:
		hide()   # 无路由环境（测试/独立实例）仅隐藏

func _cell_style(border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD_BG
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(4)
	return sb

func _label(text: String, font_size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l
