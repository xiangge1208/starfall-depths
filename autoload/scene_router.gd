extends Node
## 场景路由器 autoload（m1-t23）：键控路由表 + 0.2s 黑场淡入淡出过场。
## autoload 名 "SceneRouter"（无 class_name，命名规则同 GameDB/RunState/SaveSystem）。
##
## 用法：SceneRouter.goto("hero_select")。键不存在 / 目标 tscn 缺失时 push_error
## fail-loud 且不做任何切换——death_summary.tscn 属 T22 交付物，本卡合并时点尚不在盘，
## goto("death") 即走该路径（T22 落地后自然翻转为正常切换，路由表键位先行占位）。
##
## 过场实现：路由器为常驻 autoload，黑场 CanvasLayer（layer 100）跨场景存活——
## 淡入至全黑 → change_scene_to_file（引擎 deferred 卸旧挂新）→ 淡出回透明。

const ROUTES := {
	"menu": "res://ui/main_menu.tscn",
	"hero_select": "res://ui/hero_select.tscn",
	# m1-t27：game 键从 M0 时代的 training_room 切到局根节点（选角 → 真实楼层主循环）。
	"game": "res://core/rooms/run_root.tscn",
	"death": "res://ui/death_summary.tscn",
	# m2-t20：图鉴页（主菜单「图鉴」入口 → 115 格武器墙）
	"codex": "res://ui/codex.tscn",
}

const FADE_TIME := 0.2   # 过场时长（brief 规格 0.2s）

var _overlay: CanvasLayer = null   # 惰性创建的黑场层（首次 goto 时挂到常驻路由器下）
var _rect: ColorRect = null
var _busy := false                 # 过场进行中忽略新请求（防连点双切）

## 路由跳转：0.2s 淡入 → 切场景 → 0.2s 淡出。异步（fire-and-forget 可，不 await 亦走完）。
func goto(key: String) -> void:
	if _busy:
		return
	if not ROUTES.has(key):
		push_error("SceneRouter: unknown route key '%s'" % key)
		return
	var path := String(ROUTES[key])
	if not ResourceLoader.exists(path):
		push_error("SceneRouter: route '%s' scene missing: %s" % [key, path])
		return
	_busy = true
	_ensure_overlay()
	var fade_in := create_tween()
	fade_in.tween_property(_rect, "color:a", 1.0, FADE_TIME)
	await fade_in.finished
	get_tree().change_scene_to_file(path)
	var fade_out := create_tween()
	fade_out.tween_property(_rect, "color:a", 0.0, FADE_TIME)
	await fade_out.finished
	_busy = false

## 黑场覆盖层：全屏 ColorRect，纯视觉（mouse_filter IGNORE 不挡输入）。
func _ensure_overlay() -> void:
	if _overlay != null:
		return
	_overlay = CanvasLayer.new()
	_overlay.layer = 100
	_rect = ColorRect.new()
	_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(_rect)
	add_child(_overlay)
