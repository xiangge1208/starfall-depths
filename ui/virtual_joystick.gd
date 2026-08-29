extends Control
## 触屏虚拟摇杆（m1-t21，GDD §5.1：左虚拟摇杆移动 / 右虚拟摇杆推即射 + 自动瞄准辅助）。
##
## 用法：把本场景实例化两个到 HUD 层——左侧（默认，移动）与右侧（is_aim = true，
## 瞄准+推过死区即合成 "fire"）。浮杆式：按下处为基座，拖动偏移经
## joystick_output 归一（死区 0.15 / 半径 48px / 单位圆钳制）。
## 桌面自动隐藏（DisplayServer.is_touchscreen_available()），force_visible 供调试。

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

func _ready() -> void:
	_refresh_visibility()

## 触屏设备自动显示；桌面隐藏（force_visible 优先，供无触屏调试）。
func _refresh_visibility() -> void:
	visible = force_visible or DisplayServer.is_touchscreen_available()

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

func _release() -> void:
	_active = false
	_touch_index = -1
	_nub_offset = Vector2.ZERO
	_apply_raw(Vector2.ZERO)
	queue_redraw()

func _exit_tree() -> void:
	if is_aim and output != Vector2.ZERO:
		Input.action_release("fire")   # 防卡键

## 由原始像素偏移推进：更新 output/aim_vector，is_aim 时合成 fire。测试可直接调用。
func _apply_raw(raw: Vector2) -> void:
	output = joystick_output(raw, dead_zone, radius)
	_nub_offset = (raw / radius).limit_length(1.0) * radius
	if is_aim:
		aim_vector = output
		if output != Vector2.ZERO:
			Input.action_press("fire")
		else:
			Input.action_release("fire")

func _draw() -> void:
	var b := _base if _active else size * 0.5
	draw_circle(b, radius, Color(1.0, 1.0, 1.0, 0.12))
	draw_arc(b, radius, 0.0, TAU, 40, Color(1.0, 1.0, 1.0, 0.35), 2.0)
	draw_circle(b + _nub_offset, nub_radius, Color(1.0, 1.0, 1.0, 0.55))

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
