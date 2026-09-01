class_name SettingsPanelUI
extends Control
## m3-sa 设置面板（S-A）：独立覆盖层场景（任意场景可实例化，不进 SceneRouter 路由）。
## 十键全量设置——旧 5 键（屏震强度/伤害数字/色弱形状/自动瞄准/触屏控件，键名与
## 存储类型同 main_menu 旧内联面板）+ 新 5 键（打击停顿/振动/主·音乐·音效音量）。
##
## 行为（裁定 5）：所有控件改动即时 set_setting 落盘（SaveSystem.set_setting 内含
## save_now）并发射 setting_changed 供消费方监听（hitstop_enabled 的消费方是 J-A
## 导演类直接 get_setting 读取，本面板不做额外接线）；返回按钮只隐藏面板。
##
## 三路音量（裁定 3）：int 键（0..100，UI 权威）——
## - volume_sfx / volume_music：写 int 键 + 调 AudioMgr.set_sfx_volume /
##   set_music_volume（float 0..1 线性；AudioMgr 随 setter 持久化自有 float 键
##   属实现细节，不视为双源冲突）；
## - volume_master：AudioMgr 无 master 接口 → 面板直写 AudioServer 总线 0
##   （0 → -80dB 对齐 AudioMgr.MUTE_DB 语义，本地常量 MASTER_MUTE_DB；否则
##   linear_to_db(v/100)）；只持久化 int 键。
## - apply_audio_settings()：从 int 键（默认 80）推三路端点，纯应用不写键；
##   供主菜单启动（BGM 起播前）与面板打开时调用。
##
## 键盘/触屏：行式布局对齐 main_menu 尺寸惯例（滑条可拖动、开关/按钮可点）；
## open() 焦点落「返 回」，↑↓/Tab 导航 + Enter 确认（容器自动焦点邻接）。
## 测试注入缝：settings_host（缺省探测 /root/SaveSystem）、audio（缺省探测 /root/AudioMgr）。

signal setting_changed(key: String, value: Variant)

const MASTER_BUS := 0                     # Master = AudioServer 总线 0
const MASTER_MUTE_DB := -80.0             # 0 线性 → -80dB（对齐 AudioMgr.MUTE_DB，非 -inf）
const VOLUME_DEFAULT := 80                # 音量 int 键缺省值
const VOLUME_MAX := 100

# ---- 键名常量（与 SaveSystem.DEFAULT_SETTINGS 对齐；旧 5 键复刻 main_menu 惯例）----
const KEY_SHAKE := "screen_shake"
const KEY_DAMAGE_NUMBERS := "damage_numbers"
const KEY_COLORBLIND := "colorblind_shapes"
const KEY_AUTO_AIM := "auto_aim"
const KEY_TOUCH_CONTROLS := "touch_controls"
const KEY_HITSTOP := "hitstop_enabled"
const KEY_VIBRATION := "vibration"
const KEY_VOLUME_MASTER := "volume_master"
const KEY_VOLUME_MUSIC := "volume_music"
const KEY_VOLUME_SFX := "volume_sfx"

var settings_host: Node = null   # 测试注入缝（临时路径档替身）；_ready 兜底探测 /root/SaveSystem
var audio: Node = null           # 测试注入缝（AudioMgr 替身）；_ready 兜底探测 /root/AudioMgr

@onready var _shake: HSlider = $Center/Panel/Margin/Rows/Grid/ShakeSlider
# 开关用 toggle Button +「开/关」文字（CheckButton 开关图标 24px 行高会令面板超出
# 270px 基准；Button 16px 行高对齐 main_menu 按钮尺寸惯例，键盘 Enter/触屏点按同效）
@onready var _damage: Button = $Center/Panel/Margin/Rows/Grid/DamageToggle
@onready var _colorblind: Button = $Center/Panel/Margin/Rows/Grid/ColorblindToggle
@onready var _auto_aim: Button = $Center/Panel/Margin/Rows/Grid/AutoAimToggle
@onready var _touch: Button = $Center/Panel/Margin/Rows/Grid/TouchToggle
@onready var _hitstop: Button = $Center/Panel/Margin/Rows/Grid/HitstopToggle
@onready var _vibration: Button = $Center/Panel/Margin/Rows/Grid/VibrationToggle
@onready var _master: HSlider = $Center/Panel/Margin/Rows/Grid/MasterSlider
@onready var _music: HSlider = $Center/Panel/Margin/Rows/Grid/MusicSlider
@onready var _sfx: HSlider = $Center/Panel/Margin/Rows/Grid/SfxSlider
@onready var _back: Button = $Center/Panel/Margin/Rows/BackBtn


func _ready() -> void:
	if settings_host == null:
		settings_host = get_node_or_null("/root/SaveSystem")
	if audio == null:
		audio = get_node_or_null("/root/AudioMgr")
	_shake.value_changed.connect(_on_shake_changed)
	_damage.toggled.connect(_on_damage_numbers_toggled)
	_colorblind.toggled.connect(_on_colorblind_toggled)
	_auto_aim.toggled.connect(_on_auto_aim_toggled)
	_touch.toggled.connect(_on_touch_controls_toggled)
	_hitstop.toggled.connect(_on_hitstop_toggled)
	_vibration.toggled.connect(_on_vibration_toggled)
	_master.value_changed.connect(_on_master_volume_changed)
	_music.value_changed.connect(_on_music_volume_changed)
	_sfx.value_changed.connect(_on_sfx_volume_changed)
	_back.pressed.connect(_on_back_pressed)
	_init_controls()


## 打开面板：可见 + 焦点落「返 回」（键盘可达的安全出口；↑↓/Tab 导航其余控件）。
func open() -> void:
	visible = true
	_back.grab_focus()


## 返回：只隐藏（实例保留，设置状态由存档承载，不销毁不重置）。
func _on_back_pressed() -> void:
	visible = false


## 从 int 音量键（默认 80）推三路端点——纯应用，不写任何键。
## 主菜单启动时（BGM 起播前）与面板打开场景调用。
func apply_audio_settings() -> void:
	var master := _volume_int(KEY_VOLUME_MASTER)
	var music := _volume_int(KEY_VOLUME_MUSIC)
	var sfx := _volume_int(KEY_VOLUME_SFX)
	_apply_master_bus(master)
	if audio != null:
		audio.set_music_volume(float(music) / 100.0)
		audio.set_sfx_volume(float(sfx) / 100.0)


## 控件初值读档（set_*_no_signal：初始化不触发 handler，不写盘不发 setting_changed）。
func _init_controls() -> void:
	_shake.set_value_no_signal(clampf(float(_setting(KEY_SHAKE, 1.0)), 0.0, 1.0))
	_damage.set_pressed_no_signal(bool(_setting(KEY_DAMAGE_NUMBERS, true)))
	_colorblind.set_pressed_no_signal(bool(_setting(KEY_COLORBLIND, false)))
	_auto_aim.set_pressed_no_signal(bool(_setting(KEY_AUTO_AIM, true)))
	_touch.set_pressed_no_signal(bool(_setting(KEY_TOUCH_CONTROLS, false)))
	_hitstop.set_pressed_no_signal(bool(_setting(KEY_HITSTOP, true)))
	_vibration.set_pressed_no_signal(bool(_setting(KEY_VIBRATION, true)))
	_sync_toggle_texts()
	_master.set_value_no_signal(float(_volume_int(KEY_VOLUME_MASTER)))
	_music.set_value_no_signal(float(_volume_int(KEY_VOLUME_MUSIC)))
	_sfx.set_value_no_signal(float(_volume_int(KEY_VOLUME_SFX)))

## 开关按钮文字同步当前态（tscn 初值为默认档，读档后在此校正）。
func _sync_toggle_texts() -> void:
	_set_toggle_text(_damage, _damage.button_pressed)
	_set_toggle_text(_colorblind, _colorblind.button_pressed)
	_set_toggle_text(_auto_aim, _auto_aim.button_pressed)
	_set_toggle_text(_touch, _touch.button_pressed)
	_set_toggle_text(_hitstop, _hitstop.button_pressed)
	_set_toggle_text(_vibration, _vibration.button_pressed)

func _set_toggle_text(btn: Button, on: bool) -> void:
	btn.text = "开" if on else "关"


# ---- handlers：改动即落盘 + 发射 setting_changed（每次用户改动恰一次）----

func _on_shake_changed(v: float) -> void:
	if settings_host == null:
		return
	settings_host.set_setting(KEY_SHAKE, v)
	setting_changed.emit(KEY_SHAKE, v)


func _on_damage_numbers_toggled(on: bool) -> void:
	_toggle_setting(KEY_DAMAGE_NUMBERS, on)
	_set_toggle_text(_damage, on)


func _on_colorblind_toggled(on: bool) -> void:
	_toggle_setting(KEY_COLORBLIND, on)
	_set_toggle_text(_colorblind, on)


func _on_auto_aim_toggled(on: bool) -> void:
	_toggle_setting(KEY_AUTO_AIM, on)
	_set_toggle_text(_auto_aim, on)


func _on_touch_controls_toggled(on: bool) -> void:
	_toggle_setting(KEY_TOUCH_CONTROLS, on)
	_set_toggle_text(_touch, on)


func _on_hitstop_toggled(on: bool) -> void:
	_toggle_setting(KEY_HITSTOP, on)
	_set_toggle_text(_hitstop, on)


func _on_vibration_toggled(on: bool) -> void:
	_toggle_setting(KEY_VIBRATION, on)
	_set_toggle_text(_vibration, on)


func _on_master_volume_changed(v: float) -> void:
	_apply_master_bus(_write_volume(KEY_VOLUME_MASTER, v))


func _on_music_volume_changed(v: float) -> void:
	var vol := _write_volume(KEY_VOLUME_MUSIC, v)
	if audio != null:
		audio.set_music_volume(float(vol) / 100.0)


func _on_sfx_volume_changed(v: float) -> void:
	var vol := _write_volume(KEY_VOLUME_SFX, v)
	if audio != null:
		audio.set_sfx_volume(float(vol) / 100.0)


## 开关统一口径：写 bool 键 + 发射 setting_changed（宿主缺席静默，同 main_menu 守卫）。
func _toggle_setting(key: String, on: bool) -> void:
	if settings_host == null:
		return
	settings_host.set_setting(key, on)
	setting_changed.emit(key, on)


## 音量滑条统一口径：无论入参多野（拖动 tick / 直调 handler 的越界值），先
## clampi(round) 到 0..100 整数，再写 int 键（UI 权威）+ 发射 setting_changed。
## 返回实际写盘值供端点推线（保证持久化值与端点值恒一致，无越界外泄）。
func _write_volume(key: String, raw: float) -> int:
	var vol := clampi(int(round(raw)), 0, VOLUME_MAX)
	if settings_host == null:
		return vol
	settings_host.set_setting(key, vol)
	setting_changed.emit(key, vol)
	return vol


## master 总线直写（无 AudioMgr 接口）：0 → -80dB（对齐 MUTE_DB 语义），否则 linear_to_db。
func _apply_master_bus(v: int) -> void:
	AudioServer.set_bus_volume_db(MASTER_BUS,
		MASTER_MUTE_DB if v <= 0 else linear_to_db(float(v) / 100.0))


# ---- 读取兜底 ----

func _setting(key: String, default: Variant) -> Variant:
	if settings_host == null:
		return default
	return settings_host.get_setting(key, default)


## 音量 int 键读取归一：档内可能是 int（本会话写入）或 float（JSON 重载），
## 统一收敛为 0..100 int。
func _volume_int(key: String) -> int:
	return clampi(int(round(float(_setting(key, float(VOLUME_DEFAULT))))), 0, VOLUME_MAX)
