class_name TouchControls
extends CanvasLayer
## 触屏生产控制层：双摇杆 + 技能/翻滚/切枪/交互按钮。
## 所有触屏输入只写独立 touch_* 动作；生产消费者再与桌面/手柄输入合并。
## 这样任一来源释放时不会取消另一个仍按住的来源。

@export var force_visible := false

@onready var move_joystick: Control = $Root/MoveJoystick
@onready var aim_joystick: Control = $Root/AimJoystick

## 只有由真实桌面 MouseButton 左键按下的按钮才进入本表。
## ScreenTouch、触摸仿真鼠标和键盘焦点激活不会屏蔽物理 fire。
var _mouse_button_holds: Dictionary = {}

func _ready() -> void:
	_refresh_visibility()
	_bind_button($Root/SkillButton, &"touch_skill")
	_bind_button($Root/RollButton, &"touch_roll")
	_bind_button($Root/SwitchButton, &"touch_switch_weapon")
	_bind_button($Root/InteractButton, &"touch_interact")

func _refresh_visibility() -> void:
	var touch_enabled := TouchMode.enabled(
		DisplayServer.is_touchscreen_available(),
		OS.has_feature("mobile"),
		bool(SaveSystem.get_setting("touch_controls", false)),
		true if force_visible else null)
	visible = touch_enabled
	# 子摇杆也有独立的桌面隐藏守卫；父层被显式强制显示时同步刷新，避免出现
	# “按钮可见但双摇杆仍隐藏”的半套调试界面。
	if move_joystick != null:
		move_joystick.set("force_visible", touch_enabled)
		move_joystick.call("_refresh_visibility")
	if aim_joystick != null:
		aim_joystick.set("force_visible", touch_enabled)
		aim_joystick.call("_refresh_visibility")

func _bind_button(button: BaseButton, action: StringName) -> void:
	button.gui_input.connect(_on_button_gui_input.bind(button))
	button.button_down.connect(_on_button_down.bind(action))
	button.button_up.connect(_on_button_up.bind(button, action))
	button.tree_exiting.connect(_on_button_tree_exiting.bind(button, action))

func _on_button_gui_input(event: InputEvent, button: BaseButton) -> void:
	if event is not InputEventMouseButton:
		return
	var mouse := event as InputEventMouseButton
	if mouse.device == InputEvent.DEVICE_ID_EMULATION \
			or mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	if mouse.pressed:
		_mouse_button_holds[button] = true
	else:
		_mouse_button_holds.erase(button)

func _on_button_down(action: StringName) -> void:
	Input.action_press(action)

func _on_button_up(button: BaseButton, action: StringName) -> void:
	_mouse_button_holds.erase(button)
	Input.action_release(action)

func _on_button_tree_exiting(button: BaseButton, action: StringName) -> void:
	# 单个按钮消失时只释放自己的动作；不能取消其它触屏或物理来源。
	_mouse_button_holds.erase(button)
	Input.action_release(action)

func captures_pointer_fire() -> bool:
	if not _mouse_button_holds.is_empty():
		return true
	for stick in [move_joystick, aim_joystick]:
		if stick != null and stick.has_method("captures_mouse_pointer") \
				and bool(stick.call("captures_mouse_pointer")):
			return true
	return false

func _exit_tree() -> void:
	_mouse_button_holds.clear()
	for action in [&"touch_fire", &"touch_skill", &"touch_roll", &"touch_switch_weapon",
			&"touch_interact", &"touch_move_left", &"touch_move_right",
			&"touch_move_up", &"touch_move_down"]:
		Input.action_release(action)
