class_name TestSettingsUI
extends GdUnitTestSuite
## m3-sa S-A 设置面板 UI + 三路音量 + 振动键 + 持久化。
## 覆盖：旧档新键默认值容错（additive 合并）/ 三路音量 int 键持久化往返 / 滑条边界
## clamp / 开关即时落盘 + setting_changed 恰一次 / 音量端点换算（AudioMgr 替身 33→0.33、
## master 真实 AudioServer 0→-80dB）/ apply_audio_settings 纯应用不写键 / main_menu
## 挂钩冒烟（新面板显隐 + 旧内联面板隐藏）。
## 持久化用例走临时 user:// 路径全新 SaveSystem 实例（同 test_save.gd 既定模式），
## 不触碰真实 user://save.json；master 总线音量在每个用例后还原（防跨套件泄漏）。


## 设置宿主替身：get_setting 按预置 store 回答；set_setting 记录调用顺序与写入值。
class SpySettings extends Node:
	var store: Dictionary = {}
	var written: Dictionary = {}
	var write_order: Array[String] = []

	func get_setting(key: String, default: Variant) -> Variant:
		return store.get(key, default)

	func set_setting(key: String, value: Variant) -> void:
		written[key] = value
		write_order.append(key)

	func write_count() -> int:
		return write_order.size()


## AudioMgr 替身：只记录 set_sfx_volume / set_music_volume 的线性实参（0..1）。
class SpyAudio extends Node:
	var sfx_calls: Array = []
	var music_calls: Array = []

	func set_sfx_volume(v: float) -> void:
		sfx_calls.append(v)

	func set_music_volume(v: float) -> void:
		music_calls.append(v)


const PANEL_SCENE := "res://ui/settings_panel.tscn"
const MENU_SCENE := "res://ui/main_menu.tscn"
const MASTER_MUTE_DB := -80.0

## 旧形状存档：settings 仅 5 旧键（新 5 键缺失 → additive 合并回落默认）。
## screen_shake 取 0.5（滑条 step=0.1 的格点值，控件 set_value 量化后不变）。
const LEGACY_SAVE_JSON := '{"version": 2, "gems": 5, "settings": {"screen_shake": 0.5, ' \
	+ '"damage_numbers": false, "colorblind_shapes": true, "auto_aim": false, "touch_controls": true}}'

var _tmp_paths: Array[String] = []
var _master_db_backup := 0.0


func before_test() -> void:
	_master_db_backup = AudioServer.get_bus_volume_db(0)


func after_test() -> void:
	AudioServer.set_bus_volume_db(0, _master_db_backup)   # master 总线还原（防跨套件泄漏）
	for path in _tmp_paths:
		DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(path + ".tmp")
	_tmp_paths.clear()


# ---------------------------------------------------------------- helpers

func _tmp_path(tag: String) -> String:
	var path := "user://test_settings_ui_%s_%d.json" % [tag, absi(randi())]
	_tmp_paths.append(path)
	return path


## 临时路径全新 SaveSystem 实例（不在树内，显式 load_save）。
func _fresh_settings(path: String) -> Node:
	var s: Node = auto_free(load("res://autoload/save_system.gd").new())
	s.set("save_path", path)
	s.call("load_save")
	return s


func _write_json(path: String, content: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(content)
	f = null


## 设置面板实例（host/audio 在 _ready 前注入 → add_child 触发 _ready 接线 + 控件初值）。
func _panel(host: Node, audio: Node) -> Node:
	var panel: Node = auto_free(load(PANEL_SCENE).instantiate())
	panel.set("settings_host", host)
	panel.set("audio", audio)
	add_child(panel)
	return panel


func _spy_settings() -> Node:
	return auto_free(SpySettings.new())


func _spy_audio() -> Node:
	return auto_free(SpyAudio.new())


func _slider(panel: Node, control_name: String) -> HSlider:
	return panel.get_node("Center/Panel/Margin/Rows/Grid/" + control_name) as HSlider


func _toggle(panel: Node, control_name: String) -> Button:
	return panel.get_node("Center/Panel/Margin/Rows/Grid/" + control_name) as Button


# ---------------------------------------------------------------- 1) 旧档新键默认容错

func test_legacy_save_new_keys_fall_back_to_defaults() -> void:
	# 旧形状存档（settings 仅 5 旧键）→ 载入后 5 新键回落默认（true/true/80/80/80），
	# 调用方 fallback 传哨兵值（false/-1），返回默认即证明键在合并骨架中真实存在。
	var path := _tmp_path("legacy_defaults")
	_write_json(path, LEGACY_SAVE_JSON)
	var s := _fresh_settings(path)
	assert_bool(bool(s.get_setting("hitstop_enabled", false))).is_true()
	assert_bool(bool(s.get_setting("vibration", false))).is_true()
	assert_int(int(s.get_setting("volume_master", -1))).is_equal(80)
	assert_int(int(s.get_setting("volume_music", -1))).is_equal(80)
	assert_int(int(s.get_setting("volume_sfx", -1))).is_equal(80)
	# 旧 5 键值保留
	assert_float(float(s.get_setting("screen_shake", 9.9))).is_equal_approx(0.5, 0.0001)
	assert_bool(bool(s.get_setting("damage_numbers", true))).is_false()
	assert_bool(bool(s.get_setting("colorblind_shapes", false))).is_true()
	assert_bool(bool(s.get_setting("auto_aim", true))).is_false()
	assert_bool(bool(s.get_setting("touch_controls", false))).is_true()


func test_panel_init_reads_legacy_keys_and_defaults() -> void:
	# 面板控件初值：旧 5 键从档读，新 5 键缺省回落（滑条 80、双开关开）。
	var path := _tmp_path("legacy_panel")
	_write_json(path, LEGACY_SAVE_JSON)
	var host := _fresh_settings(path)
	var panel := _panel(host, _spy_audio())
	assert_float(_slider(panel, "ShakeSlider").value).is_equal_approx(0.5, 0.0001)
	assert_bool(_toggle(panel, "DamageToggle").button_pressed).is_false()
	assert_bool(_toggle(panel, "ColorblindToggle").button_pressed).is_true()
	assert_bool(_toggle(panel, "AutoAimToggle").button_pressed).is_false()
	assert_bool(_toggle(panel, "TouchToggle").button_pressed).is_true()
	assert_bool(_toggle(panel, "HitstopToggle").button_pressed).is_true()
	assert_bool(_toggle(panel, "VibrationToggle").button_pressed).is_true()
	assert_float(_slider(panel, "MasterSlider").value).is_equal(80.0)
	assert_float(_slider(panel, "MusicSlider").value).is_equal(80.0)
	assert_float(_slider(panel, "SfxSlider").value).is_equal(80.0)


# ---------------------------------------------------------------- 2) 音量 int 键持久化往返

func test_volume_int_keys_roundtrip_through_disk() -> void:
	var path := _tmp_path("volume_roundtrip")
	var host := _fresh_settings(path)
	var panel := _panel(host, _spy_audio())
	_slider(panel, "SfxSlider").value = 33.0
	_slider(panel, "MasterSlider").value = 100.0
	_slider(panel, "MusicSlider").value = 0.0
	# 活动档读回（int 键是 UI 权威）
	assert_int(int(host.get_setting("volume_sfx", -1))).is_equal(33)
	assert_int(int(host.get_setting("volume_master", -1))).is_equal(100)
	assert_int(int(host.get_setting("volume_music", -1))).is_equal(0)
	# 全新实例从盘上重读 → 同值（JSON 数字 float → int() 归一后一致）
	var reloaded := _fresh_settings(path)
	assert_int(int(reloaded.get_setting("volume_sfx", -1))).is_equal(33)
	assert_int(int(reloaded.get_setting("volume_master", -1))).is_equal(100)
	assert_int(int(reloaded.get_setting("volume_music", -1))).is_equal(0)


# ---------------------------------------------------------------- 3) 滑条边界 clamp

func test_volume_slider_clamps_out_of_range_inputs() -> void:
	var spy := _spy_settings()
	var panel := _panel(spy, _spy_audio())
	# handler 直驱（绕过 Range 自钳制的野值）→ 面板侧 clampi 0..100，无越界持久化
	panel.call("_on_sfx_volume_changed", -5.0)
	assert_int(int(spy.written["volume_sfx"])).is_equal(0)
	panel.call("_on_sfx_volume_changed", 120.0)
	assert_int(int(spy.written["volume_sfx"])).is_equal(100)
	panel.call("_on_music_volume_changed", -5.0)
	assert_int(int(spy.written["volume_music"])).is_equal(0)
	panel.call("_on_master_volume_changed", 120.0)
	assert_int(int(spy.written["volume_master"])).is_equal(100)
	# Range 自钳制：value setter 收敛到 min/max 后才发 value_changed（持久化同为边界值）
	var master := _slider(panel, "MasterSlider")
	master.value = -5.0
	assert_int(int(spy.written["volume_master"])).is_equal(0)
	master.value = 120.0
	assert_int(int(spy.written["volume_master"])).is_equal(100)


# ---------------------------------------------------------------- 4) 开关即时落盘 + 信号恰一次

func test_toggles_persist_and_emit_setting_changed_once() -> void:
	var path := _tmp_path("toggle_hitstop")
	var host := _fresh_settings(path)
	var panel := _panel(host, _spy_audio())
	var seen: Array = []
	panel.connect("setting_changed", func(k: String, v: Variant) -> void: seen.append([k, v]))
	_toggle(panel, "HitstopToggle").button_pressed = false
	assert_int(seen.size()).is_equal(1)   # 恰一次
	assert_str(String(seen[0][0])).is_equal("hitstop_enabled")
	assert_bool(bool(seen[0][1])).is_false()
	_toggle(panel, "VibrationToggle").button_pressed = false
	assert_int(seen.size()).is_equal(2)
	assert_str(String(seen[1][0])).is_equal("vibration")
	assert_bool(bool(seen[1][1])).is_false()
	# 落盘（set_setting → save_now 原子写）
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_that(parsed).is_not_null()
	assert_bool(bool((parsed as Dictionary)["settings"]["hitstop_enabled"])).is_false()
	assert_bool(bool((parsed as Dictionary)["settings"]["vibration"])).is_false()
	# 全新实例重读 → roundtrip 一致
	var reloaded := _fresh_settings(path)
	assert_bool(bool(reloaded.get_setting("hitstop_enabled", true))).is_false()
	assert_bool(bool(reloaded.get_setting("vibration", true))).is_false()


func test_init_does_not_write_or_emit() -> void:
	# 控件初值走 *_no_signal：初始化不写盘、不发 setting_changed（跨面板重开不产生幽灵写）
	var spy := _spy_settings()
	var panel: Node = auto_free(load(PANEL_SCENE).instantiate())
	panel.set("settings_host", spy)
	panel.set("audio", _spy_audio())
	var seen: Array = []
	panel.connect("setting_changed", func(k: String, v: Variant) -> void: seen.append([k, v]))
	add_child(panel)   # _ready 在信号连线后触发
	assert_int(spy.write_count()).is_equal(0)
	assert_int(seen.size()).is_equal(0)


func test_legacy_keys_via_panel_keep_names_and_types() -> void:
	# 旧 5 键 handler 从 main_menu 复刻：键名不变、存储类型不变（shake float / 开关 bool）
	var spy := _spy_settings()
	var panel := _panel(spy, _spy_audio())
	_slider(panel, "ShakeSlider").value = 0.4
	assert_bool(spy.written["screen_shake"] is float).is_true()
	assert_float(float(spy.written["screen_shake"])).is_equal_approx(0.4, 0.0001)
	_toggle(panel, "DamageToggle").button_pressed = false
	assert_bool(spy.written["damage_numbers"] is bool).is_true()
	assert_bool(bool(spy.written["damage_numbers"])).is_false()
	_toggle(panel, "ColorblindToggle").button_pressed = true
	assert_bool(bool(spy.written["colorblind_shapes"])).is_true()
	_toggle(panel, "AutoAimToggle").button_pressed = false
	assert_bool(bool(spy.written["auto_aim"])).is_false()
	_toggle(panel, "TouchToggle").button_pressed = true
	assert_bool(bool(spy.written["touch_controls"])).is_true()


# ---------------------------------------------------------------- 5) 音量端点换算

func test_volume_endpoints_linear_and_master_bus() -> void:
	# sfx/music：注入 AudioMgr 替身断言 int→线性换算（33 → 0.33）；
	# master：真实 AudioServer 总线 0（0 → -80dB；80 → linear_to_db(0.8)）。
	var audio := _spy_audio()
	var panel := _panel(_spy_settings(), audio)
	_slider(panel, "SfxSlider").value = 33.0
	assert_float(float(audio.sfx_calls[0])).is_equal_approx(0.33, 0.0001)
	_slider(panel, "MusicSlider").value = 60.0   # 初值 80 → 改 60（值必须变化才发 value_changed）
	assert_float(float(audio.music_calls[0])).is_equal_approx(0.6, 0.0001)
	_slider(panel, "SfxSlider").value = 0.0
	assert_float(float(audio.sfx_calls[1])).is_equal(0.0)
	var master := _slider(panel, "MasterSlider")
	master.value = 0.0
	assert_float(AudioServer.get_bus_volume_db(0)).is_equal(MASTER_MUTE_DB)
	master.value = 80.0
	assert_float(AudioServer.get_bus_volume_db(0)).is_equal_approx(linear_to_db(0.8), 0.001)


# ---------------------------------------------------------------- 6) apply_audio_settings 纯应用

func test_apply_audio_settings_pushes_without_writing() -> void:
	# 预置 int 键（0/33/100）→ 推端点（-80dB / 0.33 / 1.0）且零 set_setting 调用
	var spy := _spy_settings()
	spy.store = {"volume_master": 0, "volume_music": 33, "volume_sfx": 100}
	var audio := _spy_audio()
	var panel := _panel(spy, audio)
	panel.call("apply_audio_settings")
	assert_int(spy.write_count()).is_equal(0)
	assert_float(float(audio.sfx_calls[0])).is_equal_approx(1.0, 0.0001)
	assert_float(float(audio.music_calls[0])).is_equal_approx(0.33, 0.0001)
	assert_float(AudioServer.get_bus_volume_db(0)).is_equal(MASTER_MUTE_DB)
	# 键全缺省 → 默认 80 → 线性 0.8 / linear_to_db(0.8)
	var spy2 := _spy_settings()
	var audio2 := _spy_audio()
	var panel2 := _panel(spy2, audio2)
	panel2.call("apply_audio_settings")
	assert_int(spy2.write_count()).is_equal(0)
	assert_float(float(audio2.sfx_calls[0])).is_equal_approx(0.8, 0.0001)
	assert_float(float(audio2.music_calls[0])).is_equal_approx(0.8, 0.0001)
	assert_float(AudioServer.get_bus_volume_db(0)).is_equal_approx(linear_to_db(0.8), 0.001)


# ---------------------------------------------------------------- 7) main_menu 挂钩冒烟

func test_main_menu_hook_opens_new_panel_hides_inline() -> void:
	# 实例化 main_menu.tscn（headless）：不崩、新面板在位且隐藏；设置键 → 新面板开、
	# 旧内联面板强制隐藏；返回按钮只隐藏新面板。
	var path := _tmp_path("menu_hook")
	var host := _fresh_settings(path)
	var menu: Node = auto_free(load(MENU_SCENE).instantiate())
	menu.set("save_system", host)   # _ready 前注入 → 面板 settings_host 透传该档
	add_child(menu)
	var new_panel: Node = menu.get_node("SettingsPanelUI")
	assert_that(new_panel).is_not_null()
	assert_bool(new_panel.visible).is_false()
	assert_bool((menu.get_node("SettingsPanel") as Control).visible).is_false()
	menu.call("_on_settings_pressed")
	assert_bool(new_panel.visible).is_true()
	assert_bool((menu.get_node("SettingsPanel") as Control).visible).is_false()
	# 新面板控件初值 = 默认档（临时档无显式键）
	assert_float(_slider(new_panel, "MasterSlider").value).is_equal(80.0)
	assert_float(_slider(new_panel, "MusicSlider").value).is_equal(80.0)
	assert_float(_slider(new_panel, "SfxSlider").value).is_equal(80.0)
	assert_bool(_toggle(new_panel, "HitstopToggle").button_pressed).is_true()
	assert_bool(_toggle(new_panel, "VibrationToggle").button_pressed).is_true()
	# 返回按钮：只隐藏新面板
	new_panel.call("_on_back_pressed")
	assert_bool(new_panel.visible).is_false()
