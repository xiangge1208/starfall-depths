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
	# m2-t18：第 3 层 Boss 通关后的胜利结算面板（RunRoot 经本键切换）。
	"victory": "res://ui/victory_summary.tscn",
	# m2-t35 ④：天赋页（主菜单「天赋」入口 → T15 三系天赋树，SaveSystem 持久化）。
	"talents": "res://ui/talents.tscn",
	# m4p-u1：成就页（主菜单「成就」入口 → 24 条成就墙，AchievementSystem 判定引擎）。
	"achievements": "res://ui/achievements.tscn",
}

const FADE_TIME := 0.2   # 过场时长（brief 规格 0.2s）

var _overlay: CanvasLayer = null   # 惰性创建的黑场层（首次 goto 时挂到常驻路由器下）
var _rect: ColorRect = null
var _busy := false                 # 过场进行中忽略新请求（防连点双切）

## m4p-ui4 全屏切换（全局键，任意场景可用）：路由器为常驻 autoload，一处接线覆盖
## 全部界面，无需每个场景各自处理。
##
## 为什么需要它：项目用 stretch/scale_mode="integer"（像素画不容非整数缩放的糊边），
## 于是缩放倍率只能取整。1920x1080 屏上「最大化」的客户区约 1920x1000（标题栏 +
## 任务栏吃掉纵向像素）→ min(1920/480, 1000/270) 向下取整 = **3×** = 1440x810，
## 四周留大黑边；而真全屏 1920x1080 恰好 = **4×** 铺满。用户报的「全屏后界面没跟着
## 缩放」正是这个——最大化 ≠ 全屏，且整数档位差一级就差 480x270 的可视面积。
## 处置：给出真全屏入口（F11 / Alt+Enter，桌面惯例），并持久化选择跨局记忆。
## 缩放模式本身不动（改 fractional 会让 12px 像素字体和整数放大的贴图出现半像素糊边）。
const KEY_FULLSCREEN := "fullscreen"      # SaveSystem 设置键（bool，默认 false）

func _ready() -> void:
	# 启动应用持久化的全屏偏好（设置键缺席/SaveSystem 未就绪一律按窗口化，fail-soft）
	if bool(_saved_fullscreen()):
		_apply_fullscreen(true)

## 全局快捷键：F11（InputMap 动作，可重映射）或 Alt+Enter（桌面惯例，直接识键——
## 不占 InputMap 槽位，避免与 ui_accept 的 Enter 冲突需要额外修饰键状态判定）。
func _unhandled_input(event: InputEvent) -> void:
	var hit := event.is_action_pressed(KEY_FULLSCREEN)
	if not hit and event is InputEventKey:
		var k := event as InputEventKey
		hit = k.pressed and not k.echo and k.alt_pressed \
			and k.physical_keycode in [KEY_ENTER, KEY_KP_ENTER]
	if not hit:
		return
	get_viewport().set_input_as_handled()
	toggle_fullscreen()

## 切换并持久化（设置键与面板/存档同源；SaveSystem 缺席时仅切换不落盘）。
func toggle_fullscreen() -> void:
	var target := not is_fullscreen()
	_apply_fullscreen(target)
	var ss := get_node_or_null("/root/SaveSystem")
	if ss != null and ss.has_method("set_setting"):
		ss.call("set_setting", KEY_FULLSCREEN, target)

func is_fullscreen() -> bool:
	var m := DisplayServer.window_get_mode()
	return m == DisplayServer.WINDOW_MODE_FULLSCREEN \
		or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN

## 纯窗口模式应用（不落盘）：全屏用 FULLSCREEN（借屏幕原生分辨率的无边框全屏，
## 比 EXCLUSIVE 切换快且 Alt-Tab 友好）；退出回 WINDOWED。
func _apply_fullscreen(on: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on \
		else DisplayServer.WINDOW_MODE_WINDOWED)

func _saved_fullscreen() -> bool:
	var ss := get_node_or_null("/root/SaveSystem")
	if ss == null or not ss.has_method("get_setting"):
		return false
	return bool(ss.call("get_setting", KEY_FULLSCREEN, false))

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
