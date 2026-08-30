class_name MainMenu
extends Control
## 主菜单（m1-t23）：GDD §19 流程入口。
## 开始 → SceneRouter.goto("hero_select")（接续 T11 选角卡）；图鉴/天赋/成就 = M2 占位灰钮；
## 设置 = 内联面板（屏震强度 0-1 滑条 + 伤害数字/色弱形状/自动瞄准/触屏控件开关），经 SaveSystem
## get_setting/set_setting 读写即时落盘（键位与 SaveSystem.DEFAULT_SETTINGS 对齐）；
## 退出 = quit。main_scene 归整合卡改（本卡不动 project.godot），
## 手动验证：godot --path . res://ui/main_menu.tscn

const SETTING_SHAKE := "screen_shake"
const SETTING_DAMAGE_NUMBERS := "damage_numbers"
const SETTING_COLORBLIND := "colorblind_shapes"
const SETTING_AUTO_AIM := "auto_aim"
const SETTING_TOUCH_CONTROLS := "touch_controls"

var save_system: Node = null   # 测试注入缝（临时路径档）；_ready 兜底探测 /root/SaveSystem
var _router: Node = null       # /root/SceneRouter 探测缓存（守卫同 T11 选角卡手法）

func _ready() -> void:
	if save_system == null:
		save_system = get_node_or_null("/root/SaveSystem")
	_router = get_node_or_null("/root/SceneRouter")
	$Menu/StartBtn.pressed.connect(_on_start_pressed)
	$Menu/SettingsBtn.pressed.connect(_on_settings_pressed)
	$Menu/QuitBtn.pressed.connect(_on_quit_pressed)
	var slider: HSlider = $SettingsPanel/Rows/ScreenShakeSlider
	slider.value_changed.connect(_on_shake_changed)
	$SettingsPanel/Rows/DamageNumbersToggle.toggled.connect(_on_damage_numbers_toggled)
	$SettingsPanel/Rows/ColorblindToggle.toggled.connect(_on_colorblind_toggled)
	$SettingsPanel/Rows/AutoAimToggle.toggled.connect(_on_auto_aim_toggled)
	$SettingsPanel/Rows/TouchControlsToggle.toggled.connect(_on_touch_controls_toggled)
	_init_settings_controls()
	$Menu/StartBtn.grab_focus()   # 键盘即焦点（↑↓/Tab 移动，Enter 确认）

## 控件初值读档（set_*_no_signal：避免初始化触发 handler 重复写盘）
func _init_settings_controls() -> void:
	if save_system == null:
		return
	var slider: HSlider = $SettingsPanel/Rows/ScreenShakeSlider
	slider.set_value_no_signal(clampf(float(save_system.get_setting(SETTING_SHAKE, 1.0)), 0.0, 1.0))
	$SettingsPanel/Rows/DamageNumbersToggle.set_pressed_no_signal(
		bool(save_system.get_setting(SETTING_DAMAGE_NUMBERS, true)))
	$SettingsPanel/Rows/ColorblindToggle.set_pressed_no_signal(
		bool(save_system.get_setting(SETTING_COLORBLIND, false)))
	$SettingsPanel/Rows/AutoAimToggle.set_pressed_no_signal(
		bool(save_system.get_setting(SETTING_AUTO_AIM, true)))
	$SettingsPanel/Rows/TouchControlsToggle.set_pressed_no_signal(
		bool(save_system.get_setting(SETTING_TOUCH_CONTROLS, false)))

# ---- 按键 handlers（接线在 _ready；路由守卫：SceneRouter 缺席时不动作不崩）----

func _on_start_pressed() -> void:
	if _router != null:
		_router.goto("hero_select")

func _on_settings_pressed() -> void:
	$SettingsPanel.visible = not $SettingsPanel.visible

func _on_quit_pressed() -> void:
	get_tree().quit()

# ---- 设置项：改动即落盘（SaveSystem.set_setting 内含 save_now）----

func _on_shake_changed(v: float) -> void:
	if save_system == null:
		return
	save_system.set_setting(SETTING_SHAKE, v)

func _on_damage_numbers_toggled(on: bool) -> void:
	if save_system == null:
		return
	save_system.set_setting(SETTING_DAMAGE_NUMBERS, on)

func _on_colorblind_toggled(on: bool) -> void:
	if save_system == null:
		return
	save_system.set_setting(SETTING_COLORBLIND, on)

func _on_auto_aim_toggled(on: bool) -> void:
	if save_system == null:
		return
	save_system.set_setting(SETTING_AUTO_AIM, on)

func _on_touch_controls_toggled(on: bool) -> void:
	if save_system == null:
		return
	save_system.set_setting(SETTING_TOUCH_CONTROLS, on)
