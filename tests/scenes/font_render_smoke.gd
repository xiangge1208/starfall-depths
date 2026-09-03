extends Node
## M3-S-C 像素中文字体全局接线无头冒烟（机检部分）：
##   ① fusion-pixel FontFile 可载且 12px 度量完好；
##   ② gui/theme/custom 项目主题生效（默认字体指向 fusion-pixel、default_font_size=12）；
##   ③ 代表场景 headless 实例化不崩（主菜单/选角/图鉴/天赋/成就/设置/试炼/死亡/胜利/
##      三选一/灾厄/熔铸/toast/战斗 HUD）；
##   ④ 布局回退防护：可见控件全部收在 480×270 视口内（ScrollContainer 裁剪内容豁免）。
## 边界披露：中文文本位图级渲染断言不做（headless 无 GPU 栅格保障）；字形锐利度、
## 长文案观感等真人走查项归 G-1（docs/superpowers/reports/m3-font-walkthrough.md）。
## 运行：godot --headless --path . res://tests/scenes/font_render_smoke.tscn

const FONT_PATH := "res://art/fonts/fusion-pixel-12px-monospaced-zh_hans.ttf"
const THEME_PATH := "res://ui/m3_theme.tres"
const VIEW := Vector2(480, 270)
const TOLERANCE := 0.6   # 浮点/描边容差

var failures: Array[String] = []


func _ready() -> void:
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("SMOKE TIMEOUT")
		get_tree().quit(1)
	)
	_run()


func _run() -> void:
	# ---- ① 字体资产 ----
	print("SMOKE 0: font asset")
	var font := load(FONT_PATH) as FontFile
	_check(font != null, "fusion-pixel ttf loads as FontFile")
	if font != null:
		_check(font.get_height(12) == 12.0, "12px design metrics intact (height == 12)")
		_check(is_equal_approx(font.get_string_size("中中", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x, 24.0),
			"CJK advance 12px/glyph (monospaced grid)")
	_check(load(THEME_PATH) is Theme, "m3_theme.tres loads as Theme")

	# ---- ② 项目主题接线 ----
	print("SMOKE 1: project theme wiring")
	var pt := ThemeDB.get_project_theme()
	_check(pt != null, "project custom theme registered (project.godot gui/theme/custom)")
	if pt != null:
		_check(pt.default_font != null and pt.default_font.resource_path == FONT_PATH,
			"project theme default font -> fusion-pixel")
		_check(pt.default_font_size == 12, "project theme default_font_size == 12")

	# ---- ③ 代表场景实例化 + ④ 视口收下 ----
	# hero_select M4-K2 重排落地：卡行改 CardScroll 横向滚动（卡 206px 固定宽不缩、
	# 12px 像素字体零缩放；触屏滑动 + follow_focus 焦点跟随），S-C「卡行超界」豁免
	# 撤销，恢复全量视口断言（滚动容器内内容按 ④ 总则归 ScrollContainer 裁剪豁免）；
	# 另保「卡内文案不破卡」专项 + 新增「6 卡 focus_neighbors 导航序闭合」专项。
	print("SMOKE 2: scene cases")
	await _scene_case("res://ui/main_menu.tscn", "", true)          # 主菜单（含挂接的设置/试炼层）
	await _scene_case("res://ui/hero_select.tscn", "", true, _check_hero_select_cards)  # 选角（横滚 6 卡 + 专项）
	await _scene_case("res://ui/codex.tscn", "open", true)          # 图鉴（115 格长条件）
	await _scene_case("res://ui/talents.tscn", "", true)            # 天赋树（3 系列 dense 布局）
	await _scene_case("res://ui/achievements.tscn", "open", true)   # 成就页（24 卡网格 + 详情区，m4p-u1）
	await _scene_case("res://ui/settings_panel.tscn", "open", true) # 设置面板（打开态量测）
	await _scene_case("res://ui/trial_panel.tscn", "open", true)    # 试炼面板（打开态量测）
	await _scene_case("res://ui/death_summary.tscn", "", true)      # 死亡结算
	await _scene_case("res://ui/victory_summary.tscn", "", true)    # 胜利结算
	await _scene_case("res://ui/buff_pick.tscn", "open3", true)     # 三选一（真实 buff 文案）
	await _overlay_cases()                                          # 灾厄/熔铸/toast（代码构建层）
	await _hud_case()                                               # 战斗 HUD

	print("SMOKE DONE: %s (%d checks failed)" % ["OK" if failures.is_empty() else "FAILED",
		failures.size()])
	for f in failures:
		print("  FAIL: ", f)
	get_tree().quit(0 if failures.is_empty() else 1)


# ================================================================ helpers

## 场景用例：实例化 →（可选）打开态 → 字体落实抽检 → 视口收下断言 →（可选）场景
## 专项断言 → 释放。视口断言按 ④ 总则：ScrollContainer 裁剪域内内容豁免（由滚动承载）。
func _scene_case(path: String, open_action: String, check_fit: bool,
		extra: Callable = Callable()) -> void:
	var tag := path.get_file()
	var ps: PackedScene = load(path)
	if ps == null:
		_check(false, tag + " loads")
		return
	var inst := ps.instantiate()
	add_child(inst)
	await _frames(3)
	_check(is_instance_valid(inst), tag + " instantiates headless")
	if not is_instance_valid(inst):
		return
	if open_action == "open" and inst.has_method("open"):
		inst.call("open")
		await _frames(2)
	elif open_action == "open3":
		var ids: Array[String] = []
		for k: String in GameDB.buffs.keys():
			ids.append(k)
		inst.call("open", ids.slice(0, 3))
		await _frames(2)
	_check(_labels_use_fusion_font(inst), tag + " labels resolve fusion-pixel default font")
	if check_fit:
		await _check_tree_fits(inst, tag)
	if extra.is_valid():
		await extra.call(inst)
	inst.queue_free()
	await _frames(1)


## 灾厄面板（无 tscn，代码自建）+ 熔铸台（打开态）+ toast（动态行）。
func _overlay_cases() -> void:
	var calamity := CalamityPanel.new()
	add_child(calamity)
	await _frames(2)
	calamity.open()
	await _frames(2)
	_check(_labels_use_fusion_font(calamity), "calamity labels resolve fusion-pixel font")
	await _check_tree_fits(calamity, "calamity")
	calamity.queue_free()
	await _frames(1)

	var forge: Node = (load("res://ui/forge.tscn") as PackedScene).instantiate()
	add_child(forge)
	await _frames(2)
	forge.call("open", null)
	await _frames(2)
	_check(_labels_use_fusion_font(forge), "forge labels resolve fusion-pixel font")
	await _check_tree_fits(forge, "forge")
	forge.queue_free()
	await _frames(1)

	var toast: Node = (load("res://ui/toast.tscn") as PackedScene).instantiate()
	add_child(toast)
	await _frames(1)
	toast.call("show_toast", "成就解锁：像素中文接线")
	await _frames(2)
	_check(_labels_use_fusion_font(toast), "toast labels resolve fusion-pixel font")
	await _check_tree_fits(toast, "toast")
	toast.free()


## 战斗 HUD（代码构建 CanvasLayer；player/run 缺省零值快照）。
func _hud_case() -> void:
	var hud := HUD.new()
	add_child(hud)
	await _frames(3)
	await _check_tree_fits(hud, "hud")
	hud.free()


## 抽检：场景内首个可见 Label 的默认主题字体须指向 fusion-pixel。
func _labels_use_fusion_font(root: Node) -> bool:
	for child in root.find_children("*", "Label", true, false):
		var l := child as Label
		if l != null and l.is_visible_in_tree():
			var f := l.get_theme_default_font()
			return f != null and f.resource_path == FONT_PATH
	return false


## 控件是否处在 ScrollContainer 裁剪域内（其内容允许超出视口，由滚动承载）。
func _in_clipped_scope(c: Control, root: Node) -> bool:
	var p: Node = c.get_parent()
	while p != null and p != root:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false


## hero_select 专项断言（M4-K2 撤豁免后保留 + 新增）：
## ① 横滚容器接线——卡行收在 CardScroll 内、横向可滚且 follow_focus（焦点移动自动
##    滚出可视域，键盘/手柄导航逐卡可达）；
## ② 卡内文案不破卡——每个 Label 收在其所属 PanelContainer 卡片矩形内（12px 长中文
##    断行不破卡，沿 S-C 专项口径）；
## ③ 导航序闭合——6 卡 FOCUS_ALL 且 focus_neighbor_right 自卡 0 起 6 跳回到卡 0、
##    途中不重复地遍历全部 6 卡（keyboard/gamepad 导航链无断点）。
func _check_hero_select_cards(root: Node) -> void:
	var scroll := root.find_child("CardScroll", true, false) as ScrollContainer
	_check(scroll != null and scroll.follow_focus
		and scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED,
		"hero_select cards in horizontal scroll container (follow_focus)")
	var bad: Array[String] = []
	var cards: Array[Control] = []
	var row := root.find_child("Cards", true, false)
	if row != null:
		for child in row.get_children():
			var c := child as Control
			if c != null and c.focus_mode == Control.FOCUS_ALL:
				cards.append(c)
		for child in row.find_children("*", "Label", true, false):
			var l := child as Label
			var card := l.get_parent() as Control
			while card != null and not card is PanelContainer:
				card = card.get_parent() as Control
			if card == null:
				continue
			var lr := l.get_global_rect()
			var cr := (card as Control).get_global_rect().grow(2.0)
			if not cr.encloses(lr):
				bad.append("%s %s outside %s" % [l.name, lr, cr])
	_check(bad.is_empty(), "hero_select card labels stay inside cards" +
		("" if bad.is_empty() else " overflow: " + ", ".join(bad.slice(0, 4))))
	_check(cards.size() == 6, "hero_select 6 focusable cards (got %d)" % cards.size())
	if not cards.is_empty():
		var visited: Array[Control] = []
		var cur := cards[0]
		for _i in cards.size():
			if cur == null or not cards.has(cur) or visited.has(cur):
				cur = null
				break
			visited.append(cur)
			var np: NodePath = cur.focus_neighbor_right
			cur = null if np.is_empty() else cur.get_node_or_null(np) as Control
		_check(cur == cards[0] and visited.size() == cards.size(),
			"hero_select focus chain closed over all cards (%d visited)" % visited.size())


## 布局回退防护：全部树内可见 Control 的全局矩形收在 480×270 内。
func _check_tree_fits(root: Node, tag: String) -> void:
	var bad: Array[String] = []
	var pool: Array[Node] = root.find_children("*", "Control", true, false)
	if root is Control:
		pool.append(root)
	for child in pool:
		var c := child as Control
		if c == null or not c.is_visible_in_tree() or _in_clipped_scope(c, root):
			continue
		var r := c.get_global_rect()
		if r.position.x < -TOLERANCE or r.position.y < -TOLERANCE \
				or r.end.x > VIEW.x + TOLERANCE or r.end.y > VIEW.y + TOLERANCE:
			bad.append("%s %s" % [c.name, r])
	_check(bad.is_empty(), tag + " visible controls within 480x270" +
		("" if bad.is_empty() else " overflow: " + ", ".join(bad.slice(0, 4))))
	# 图鉴专用：网格宽度不得超 ScrollContainer（防横向滚动条破版）
	var grid := root.find_child("Grid", true, false) as Control
	var scroll := root.find_child("Scroll", true, false) as Control
	if grid != null and scroll != null:
		_check(grid.size.x <= scroll.size.x + TOLERANCE,
			"codex grid fits scroll width (%d <= %d)" % [int(grid.size.x), int(scroll.size.x)])


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
	print("  %s %s" % ["PASS" if ok else "FAIL", label])


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
