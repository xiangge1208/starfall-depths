extends Node
## m4p-ui1 选角界面视觉核对诊断（诊断脚本随库走，同 diag_light_attribution 先例）：
## 有窗运行渲染 hero_select，
## ① 逐一切换 6 名英雄各存一张 PNG 供人工核对；
## ② 打印实测布局矩形（铭牌行/详情面板/各行），供无法看图时做数值核对——
##    重叠、越界、空隙过大都能在数字上看出来。
## 运行：godot --path . res://tools/shot_hero_select.tscn
## 产物：user_export/shot_hero_select/*.png（user_export 已 gitignore）
## 无头模式无渲染管线（frame_post_draw 恒不触发）→ 只打印布局，不截图。

const OUT_DIR := "user_export/shot_hero_select"

func _ready() -> void:
	var headless := DisplayServer.get_name() == "headless"
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var ui: Control = (load("res://ui/hero_select.tscn") as PackedScene).instantiate()
	add_child(ui)
	await get_tree().process_frame
	await get_tree().process_frame
	_report_layout(ui)
	for i in 6:
		ui._selected = i
		ui._refresh()
		await get_tree().process_frame
		if headless:
			continue
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var id := String(ui._ids[i])
		var path := "%s/%02d-%s.png" % [OUT_DIR, i, id]
		print("  SHOT %s -> %s" % [id, "ok" if img.save_png(path) == Error.OK else "ERR"])
	print("SHOT DONE")
	get_tree().quit(0)


## 布局实测：480x270 设计分辨率下各区块的 position/size（视口坐标）。
func _report_layout(ui: Control) -> void:
	print("--- LAYOUT (design 480x270) ---")
	var scroll := ui.get_node("CardScroll") as ScrollContainer
	var row := ui.get_node("CardScroll/Cards") as HBoxContainer
	var detail := ui.get_node("Detail") as PanelContainer
	print("CardScroll  pos=%s size=%s" % [scroll.position, scroll.size])
	print("Cards row   size=%s (needs <= %s)" % [row.size, scroll.size])
	print("Detail      pos=%s size=%s bottom=%.0f" % [
		detail.position, detail.size, detail.position.y + detail.size.y])
	var gap := detail.position.y - (scroll.position.y + scroll.size.y)
	print("gap scroll->detail = %.0f px" % gap)
	for i in ui._cards.size():
		var c := ui._cards[i] as Control
		print("  plaque %d %-10s pos=%s size=%s" % [
			i, String(ui._ids[i]), c.position, c.size])
	# 详情面板内各段（仅当前选中可见的那份被算入）
	var name_l := ui._detail_name as Label
	print("  detail name  pos=%s size=%s text=%s" % [
		name_l.global_position, name_l.size, name_l.text])
	var stats := ui._detail_stats as HBoxContainer
	print("  stat chips   pos=%s size=%s children=%d" % [
		stats.global_position, stats.size, stats.get_child_count()])
	for i in 6:
		var pr := ui._passive_rows[i] as Control
		if pr.visible:
			print("  passive row  pos=%s size=%s" % [pr.global_position, pr.size])
		var sr := ui._skill_rows[i] as Control
		if sr.visible:
			print("  skill row    pos=%s size=%s" % [sr.global_position, sr.size])
	var w := ui._detail_weapon as Label
	print("  weapon row   pos=%s size=%s bottom=%.0f" % [
		w.global_position, w.size, w.global_position.y + w.size.y])
	# 越界/重叠自检
	var vp := Vector2(480, 270)
	var bad: Array[String] = []
	for n: Node in ui.find_children("*", "Control", true, false):
		var c := n as Control
		if not c.is_visible_in_tree():
			continue
		var r := c.get_global_rect()
		if r.position.x < -0.5 or r.position.y < -0.5 \
				or r.end.x > vp.x + 0.5 or r.end.y > vp.y + 0.5:
			bad.append("%s %s" % [c.name, r])
	print("out-of-viewport controls: %d %s" % [bad.size(), ", ".join(bad.slice(0, 6))])
	var srect := scroll.get_global_rect()
	var drect := detail.get_global_rect()
	print("scroll/detail overlap: %s" % str(srect.intersects(drect)))
