extends Control
## 触屏虚拟摇杆（m1-t21，GDD §5.1：左虚拟摇杆移动 / 右虚拟摇杆推即射 + 自动瞄准辅助）。
##
## 用法：把本场景实例化两个到 HUD 层——左侧（默认，移动）与右侧（is_aim = true，
## 瞄准+推过死区即写入独立的 "touch_fire"）。浮杆式：按下处为基座，拖动偏移经
## joystick_output 归一（死区 0.15 / 半径 48px / 单位圆钳制）。
## 桌面自动隐藏；触屏能力或 mobile feature 任一成立即显示，force_visible 供调试。

@export var is_aim := false        # true：右摇杆语义（瞄准 + 推即射）
@export var radius := 48.0         # 摇杆可视半径（px）
@export var dead_zone := 0.15      # 输出死区（归一化模长）
@export var force_visible := false # 桌面调试强制显示
@export var nub_radius := 18.0     # 帽头半径（px）

## 当前输出（归一化向量；死区内为 ZERO）。移动杆由移动层读取（同 Input.get_vector 语义）
var output := Vector2.ZERO
## is_aim 时的瞄准方向（= output；T23/整合层与 auto_aim.aim_vector 二选一消费）
var aim_vector := Vector2.ZERO

var _base := Vector2.ZERO        # 基座中心（局部坐标，浮杆式）
var _nub_offset := Vector2.ZERO  # 帽头相对基座的像素偏移（已钳制）
var _active := false
var _touch_index := -1
var _mouse_active := false

const TOUCH_FIRE := &"touch_fire"
const TOUCH_MOVE_LEFT := &"touch_move_left"
const TOUCH_MOVE_RIGHT := &"touch_move_right"
const TOUCH_MOVE_UP := &"touch_move_up"
const TOUCH_MOVE_DOWN := &"touch_move_down"

## m1-t28：摇杆视觉接线 ui/joystick_base.png（48x48）/ joystick_nub.png（24x24）。
const TEX_BASE := preload("res://art/generated/ui/joystick_base.png")
const TEX_NUB := preload("res://art/generated/ui/joystick_nub.png")

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # 像素风必需
	_refresh_visibility()

## 触屏设备/mobile 导出自动显示；桌面隐藏（force_visible 优先，供无触屏调试）。
func _refresh_visibility() -> void:
	visible = TouchMode.enabled(
		DisplayServer.is_touchscreen_available(),
		OS.has_feature("mobile"),
		bool(SaveSystem.get_setting("touch_controls", false)),
		null,
		SaveSystem.is_setting_explicit("touch_controls") == true) 		or force_visible

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and not _active:
			_active = true
			_touch_index = t.index
			_base = t.position
			_nub_offset = Vector2.ZERO
			_apply_raw(Vector2.ZERO)
			queue_redraw()
		elif not t.pressed and _active and t.index == _touch_index:
			_release()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if _active and d.index == _touch_index:
			_apply_raw(d.position - _base)
			queue_redraw()
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		# Godot 可把 ScreenTouch 仿真成 MouseButton；那不是桌面真实鼠标，
		# 不得据此屏蔽一个同时保持的物理 fire 来源。
		if button.device == InputEvent.DEVICE_ID_EMULATION \
				or button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed and not _active and not _mouse_active:
			accept_event()
			_active = true
			_mouse_active = true
			_base = button.position
			_nub_offset = Vector2.ZERO
			_apply_raw(Vector2.ZERO)
			queue_redraw()
		elif not button.pressed and _mouse_active:
			accept_event()
			_release()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _mouse_active and (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			accept_event()
			_apply_raw(motion.position - _base)
			queue_redraw()

func _release() -> void:
	_active = false
	_touch_index = -1
	_mouse_active = false
	_nub_offset = Vector2.ZERO
	_apply_raw(Vector2.ZERO)
	queue_redraw()

func _exit_tree() -> void:
	_active = false
	_touch_index = -1
	_mouse_active = false
	output = Vector2.ZERO
	aim_vector = Vector2.ZERO
	_release_actions()   # 防卡键/卡方向：无论当前输出缓存为何都完整释放

## 供 TouchControls/PlayerDriver 查询桌面鼠标是否正由此摇杆独占。
## 只报告真实 MouseButton 左键；ScreenTouch 与触摸仿真鼠标始终为 false。
func captures_mouse_pointer() -> bool:
	return _mouse_active

## 由原始像素偏移推进：更新 output/aim_vector，is_aim 时合成 fire。测试可直接调用。
func _apply_raw(raw: Vector2) -> void:
	output = joystick_output(raw, dead_zone, radius)
	_nub_offset = (raw / radius).limit_length(1.0) * radius
	if is_aim:
		aim_vector = output
		if output != Vector2.ZERO:
			Input.action_press(TOUCH_FIRE)
		else:
			Input.action_release(TOUCH_FIRE)
	else:
		_apply_move_actions(output)

## 左杆也走统一 InputMap，Player 的 Input.get_vector 因而无需触屏旁路。
## 每次先按当前强度重写四向，归中/释放/退出树都保证清干净。
func _apply_move_actions(v: Vector2) -> void:
	_set_action_strength(TOUCH_MOVE_LEFT, maxf(-v.x, 0.0))
	_set_action_strength(TOUCH_MOVE_RIGHT, maxf(v.x, 0.0))
	_set_action_strength(TOUCH_MOVE_UP, maxf(-v.y, 0.0))
	_set_action_strength(TOUCH_MOVE_DOWN, maxf(v.y, 0.0))

func _set_action_strength(action: StringName, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)

func _release_actions() -> void:
	if is_aim:
		Input.action_release(TOUCH_FIRE)
	else:
		for action in [TOUCH_MOVE_LEFT, TOUCH_MOVE_RIGHT, TOUCH_MOVE_UP, TOUCH_MOVE_DOWN]:
			Input.action_release(action)

func _draw() -> void:
	var b := _base if _active else size * 0.5
	# m1-t28：底盘/帽头换 ui/joystick_*.png（拉伸绘制到既定半径，半透明基座由贴图自带）。
	draw_texture_rect(TEX_BASE, Rect2(b - Vector2(radius, radius), Vector2(radius, radius) * 2.0),
		false, Color(1, 1, 1, 0.6))
	draw_texture_rect(TEX_NUB,
		Rect2(b + _nub_offset - Vector2(nub_radius, nub_radius), Vector2(nub_radius, nub_radius) * 2.0),
		false, Color(1, 1, 1, 0.9))

## 纯函数：像素偏移 → 输出向量。先除以半径归一，模长钳到 1；
## 死区（≤ dead）内置零；死区外按 (len-dead)/(1-dead) 重缩放，保留中心细控。
static func joystick_output(raw: Vector2, dead := 0.15, radius := 48.0) -> Vector2:
	if radius <= 0.0:
		return Vector2.ZERO
	var v := raw / radius
	var magnitude := v.length()
	if magnitude <= dead:
		return Vector2.ZERO
	if magnitude >= 1.0:
		return v.normalized()
	return v.normalized() * ((magnitude - dead) / (1.0 - dead))
