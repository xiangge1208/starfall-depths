class_name MainMenu
extends Control
## 主菜单（m1-t23）：GDD §19 流程入口。
## 开始 → SceneRouter.goto("hero_select")（接续 T11 选角卡）；m2-t20 起图鉴 = 正式入口
## （SceneRouter.goto("codex")）；m2-t35 起天赋 = 正式入口（SceneRouter.goto("talents")，
## T15 天赋页）；成就 = M2 占位灰钮；
## 设置 = m3-sa 起改开独立设置面板（ui/settings_panel.tscn，十键：旧 5 键 + 打击停顿/
## 振动/三路音量）；旧内联面板 tscn 不动、运行时隐藏退役（handler 保留）；设置项经
## SaveSystem get_setting/set_setting 读写即时落盘；启动时先 apply_audio_settings
## 推三路音量端点再起 BGM；
## 退出 = quit。main_scene 归整合卡改（本卡不动 project.godot），
## 手动验证：godot --path . res://ui/main_menu.tscn

const SETTING_SHAKE := "screen_shake"
const SETTING_DAMAGE_NUMBERS := "damage_numbers"
const SETTING_COLORBLIND := "colorblind_shapes"
const SETTING_AUTO_AIM := "auto_aim"
const SETTING_TOUCH_CONTROLS := "touch_controls"

const SETTINGS_PANEL_SCENE := preload("res://ui/settings_panel.tscn")   # m3-sa：独立设置面板
const TRIAL_PANEL_SCENE := preload("res://ui/trial_panel.tscn")         # m3-rb：试炼面板
const REBIND_PANEL_SCENE := preload("res://ui/rebind_panel.tscn")       # m3-sb：按键重映射面板

var save_system: Node = null   # 测试注入缝（临时路径档）；_ready 兜底探测 /root/SaveSystem
var _router: Node = null       # /root/SceneRouter 探测缓存（守卫同 T11 选角卡手法）
var _settings_panel: SettingsPanelUI = null   # m3-sa：新设置面板（初始隐藏，返回键只隐藏不销毁）
var _trial_panel: TrialPanelUI = null         # m3-rb：试炼面板（初始隐藏，返回键只隐藏）
var _rebind_panel: RebindPanelUI = null       # m3-sb：按键重映射面板（初始隐藏，返回键只隐藏）

func _ready() -> void:
	if save_system == null:
		save_system = get_node_or_null("/root/SaveSystem")
	_router = get_node_or_null("/root/SceneRouter")
	# m3-sa：挂接新设置面板（旧内联面板不改 tscn、运行时强制隐藏退役）。
	# 注入缝透传：save_system（可为测试替身）→ settings_host；audio 由面板自探测。
	_settings_panel = SETTINGS_PANEL_SCENE.instantiate() as SettingsPanelUI
	if _settings_panel != null:
		_settings_panel.settings_host = save_system
		add_child(_settings_panel)
		_settings_panel.apply_audio_settings()   # 先按持久化音量推 Master/sfx/music 端点
	AudioMgr.play_music("menu")   # m2-t22：主菜单 BGM（同曲幂等，重进不重启）——按已应用音量起
	$Menu/StartBtn.pressed.connect(_on_start_pressed)
	$Menu/SettingsBtn.pressed.connect(_on_settings_pressed)
	$Menu/QuitBtn.pressed.connect(_on_quit_pressed)
	# m2-t20：图鉴入口点亮（占位灰钮 → 正式路由）
	var codex_btn: Button = $Menu/CodexBtn
	codex_btn.disabled = false
	codex_btn.text = "图 鉴"
	codex_btn.pressed.connect(_on_codex_pressed)
	# m2-t35 ④：天赋入口点亮（T15 天赋页 ui/talents.tscn 已在盘 → SceneRouter "talents" 键）
	var talents_btn: Button = $Menu/TalentsBtn
	talents_btn.disabled = false
	talents_btn.text = "天 赋"
	talents_btn.pressed.connect(_on_talents_pressed)
	# m3-rb：试炼入口（main_menu.tscn 禁改 → 运行时构建按钮加入 $Menu，尺寸/字号对齐
	# 既有按钮排，同 CodexBtn 灰钮点亮手法；插「开 始」之下，入口优先级次高）
	var trial_btn := Button.new()
	trial_btn.text = "试 炼"
	trial_btn.custom_minimum_size = Vector2(140, 18)
	trial_btn.add_theme_font_size_override("font_size", 11)
	$Menu.add_child(trial_btn)
	$Menu.move_child(trial_btn, 1)
	trial_btn.pressed.connect(_on_trial_pressed)
	# m3-rb：挂接试炼面板（覆盖层同 settings_panel 挂法，初始隐藏；键盘/触屏同源）
	_trial_panel = TRIAL_PANEL_SCENE.instantiate() as TrialPanelUI
	if _trial_panel != null:
		add_child(_trial_panel)
	# m3-sb：按键设置入口（S-B 1 挂钩）。按钮运行时构建同「试 炼」钮手法
	# （main_menu.tscn 禁改），插「设 置」之下；面板 save_host 透传注入缝
	# （同 settings_host，可为测试替身）。
	var rebind_btn := Button.new()
	rebind_btn.text = "按 键"
	rebind_btn.custom_minimum_size = Vector2(140, 18)
	rebind_btn.add_theme_font_size_override("font_size", 11)
	$Menu.add_child(rebind_btn)
	$Menu.move_child(rebind_btn, 6)   # 开始/试炼/图鉴/天赋/成就/设置 之后、退出之前
	rebind_btn.pressed.connect(_on_rebind_pressed)
	_rebind_panel = REBIND_PANEL_SCENE.instantiate() as RebindPanelUI
	if _rebind_panel != null:
		_rebind_panel.save_host = save_system
		add_child(_rebind_panel)
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
	RunState.pending_trial_date = ""   # M3-R-C 移交③：普通开始清迟到试炼 arm（防选角转让劫持）
	if _router != null:
		_router.goto("hero_select")

func _on_codex_pressed() -> void:
	if _router != null:
		_router.goto("codex")

func _on_talents_pressed() -> void:
	if _router != null:
		_router.goto("talents")

func _on_trial_pressed() -> void:
	# m3-rb：试炼面板打开即刷新（日期/因子/今日最佳/历史）；「开 始」在面板内 arm+路由
	if _trial_panel != null:
		_trial_panel.open()

func _on_settings_pressed() -> void:
	# m3-sa：设置键改开独立面板（开合语义同旧内联面板）；旧面板退役强制隐藏
	# （handler 保留不动，不再可达）
	$SettingsPanel.visible = false
	if _settings_panel != null:
		if _settings_panel.visible:
			_settings_panel.visible = false   # 再按一次收起（同「返 回」）
		else:
			_settings_panel.open()            # 打开（焦点落「返 回」，键盘可达）

func _on_rebind_pressed() -> void:
	# m3-sb：按键设置面板开合（同设置面板手法；再按收起，「返 回」同样收起）
	if _rebind_panel == null:
		return
	if _rebind_panel.visible:
		_rebind_panel.visible = false
	else:
		_rebind_panel.open()

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
