class_name TestRebind
extends GdUnitTestSuite
## m3-sb S-B 按键重映射：序列化往返 / 持久化往返（临时路径）/ 冲突拒绝 / 恢复默认 /
## InputMap 即时生效 / 脏数据 fail-soft / _merge_saved additive / 面板冒烟。
## InputMap 是全局态：before_test 快照 9 动作事件，after_test 逐动作还原（同
## test_setup_input 手法），防跨套件泄漏；存档用例走临时 user:// 路径全新实例
## （同 test_save.gd 既定模式），不触碰真实 user://save.json。

const SAVE_SCRIPT := "res://autoload/save_system.gd"
const PANEL_SCENE := "res://ui/rebind_panel.tscn"
const KEY_A := 65    # move_left 默认主键
const KEY_D := 68    # move_right 默认主键（冲突用例的占用键）
const KEY_Q := 81    # switch_weapon 默认主键
const KEY_F := 70    # skill 默认主键
const KEY_R := 82    # 默认键位表未占用的键（改键目标）
const KEY_G := 71
const KEY_J := 74


## 设置宿主替身：记录改键 / 清表调用（面板 has_method 守卫的契约对端）。
class SpySave extends Node:
	var rebind_calls: Array = []
	var clear_calls := 0

	func record_key_rebind(action: String, event_data: Dictionary) -> void:
		rebind_calls.append([action, event_data])

	func clear_key_rebinds() -> void:
		clear_calls += 1


var _tmp_paths: Array[String] = []
var _saved_actions: Dictionary = {}


func before_test() -> void:
	_saved_actions.clear()
	for action: String in RebindPanelUI.REBINDABLE_ACTIONS:
		_saved_actions[action] = InputMap.action_get_events(action).duplicate()


func after_test() -> void:
	for action: String in RebindPanelUI.REBINDABLE_ACTIONS:
		InputMap.action_erase_events(action)
		for ev: InputEvent in _saved_actions[action]:
			InputMap.action_add_event(action, ev)
	for path in _tmp_paths:
		DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(path + ".tmp")
	_tmp_paths.clear()


# ---------------------------------------------------------------- helpers

func _tmp_path(tag: String) -> String:
	var path := "user://test_rebind_%s_%d.json" % [tag, absi(randi())]
	_tmp_paths.append(path)
	return path


func _write_json(path: String, content: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(content)
	f = null


## 临时路径全新 SaveSystem 实例（不在树内，显式 load_save）。
func _fresh_settings(path: String) -> Node:
	var s: Node = auto_free(load(SAVE_SCRIPT).new())
	s.set("save_path", path)
	s.call("load_save")
	return s


func _key(code: int, ctrl := false, alt := false, shift := false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = code as Key
	ev.pressed = true   # 按下沿（监听态只捕获 pressed；_capture_key 直驱亦同语义）
	ev.ctrl_pressed = ctrl
	ev.alt_pressed = alt
	ev.shift_pressed = shift
	return ev


## 面板实例（save_host 在 _ready 前注入 → add_child 触发接线 + 行初值刷新）。
func _panel(host: Node) -> Node:
	var panel: Node = auto_free(load(PANEL_SCENE).instantiate())
	panel.set("save_host", host)
	add_child(panel)
	return panel


func _spy() -> Node:
	return auto_free(SpySave.new())


func _row(panel: Node, action: String) -> Button:
	return panel.get_node("Center/Panel/Margin/Rows/Grid/" + action) as Button


func _status(panel: Node) -> Label:
	return panel.get_node("Center/Panel/Margin/Rows/Status") as Label


func _has_key_event(action: String, key: InputEventKey) -> bool:
	for ev: InputEvent in InputMap.action_get_events(action):
		var k := ev as InputEventKey
		if k != null and RebindPanelUI.key_events_match(key, k):
			return true
	return false


func _project_default_events(action: String) -> Array:
	var setting: Dictionary = ProjectSettings.get_setting("input/" + action)
	return setting.get("events", [])


# ---------------------------------------------------------------- 1) 动作契约 + 序列化往返

func test_rebindable_action_contract() -> void:
	# 清单 = 移动四向 / fire / skill / roll / switch_weapon / interact 恰 9 个；
	# pause（无消费者）/ aim_right_*（手柄轴）/ touch_*（虚拟触屏）不入清单。
	assert_array(RebindPanelUI.REBINDABLE_ACTIONS).contains_exactly([
		"move_left", "move_right", "move_up", "move_down",
		"fire", "skill", "roll", "switch_weapon", "interact",
	])
	for action: String in RebindPanelUI.REBINDABLE_ACTIONS:
		assert_bool(InputMap.has_action(action)).override_failure_message(action).is_true()
		assert_str(String(RebindPanelUI.ACTION_NAMES[action])).is_not_empty()


func test_serialize_roundtrip() -> void:
	# InputEventKey → 字典 → 还原 → 字段精确比对（physical_keycode + 三修饰键）
	var data := RebindPanelUI.serialize_key_event(_key(KEY_R, true, false, true))
	assert_int(int(data["physical_keycode"])).is_equal(KEY_R)
	assert_bool(bool(data["ctrl"])).is_true()
	assert_bool(bool(data["alt"])).is_false()
	assert_bool(bool(data["shift"])).is_true()
	var back := RebindPanelUI.deserialize_key_event(data)
	assert_bool(RebindPanelUI.key_events_match(back, _key(KEY_R, true, false, true))).is_true()
	# 修饰键不同即不匹配（精确口径，不做宽松比对）
	assert_bool(RebindPanelUI.key_events_match(back, _key(KEY_R))).is_false()
	assert_bool(RebindPanelUI.key_events_match(back, _key(KEY_R, true, false, false))).is_false()
	# 无修饰键最小往返 + 未序列化的字典缺键回落
	assert_bool(RebindPanelUI.key_events_match(
		RebindPanelUI.deserialize_key_event(RebindPanelUI.serialize_key_event(_key(KEY_G))),
		_key(KEY_G))).is_true()


# ---------------------------------------------------------------- 2) 持久化往返 + additive

func test_persistence_roundtrip_through_disk() -> void:
	var path := _tmp_path("roundtrip")
	var s := _fresh_settings(path)
	assert_dict(s.key_rebinds()).is_empty()   # 无档 → 空表 = 全默认键位
	s.record_key_rebind("switch_weapon",
		{"physical_keycode": KEY_R, "ctrl": false, "alt": false, "shift": true})
	s.record_key_rebind("skill",
		{"physical_keycode": KEY_G, "ctrl": false, "alt": false, "shift": false})
	var reloaded := _fresh_settings(path)
	var table: Dictionary = reloaded.key_rebinds()
	assert_int(table.size()).is_equal(2)
	assert_int(int(table["switch_weapon"]["physical_keycode"])).is_equal(KEY_R)
	assert_bool(bool(table["switch_weapon"]["shift"])).is_true()
	assert_int(int(table["skill"]["physical_keycode"])).is_equal(KEY_G)
	# 恢复默认（清表）落盘 → 重读为空
	reloaded.clear_key_rebinds()
	assert_dict(_fresh_settings(path).key_rebinds()).is_empty()


func test_merge_additive_v2_save_without_key() -> void:
	# 旧 v2 档（无 key_rebinds 键）载入 → 空表回落（全默认），既有键不受影响
	var path := _tmp_path("legacy")
	_write_json(path, '{"version": 2, "gems": 7, "settings": {"screen_shake": 0.5},'
		+ ' "unlock_tasks": {"kills": 3}}')
	var s := _fresh_settings(path)
	assert_dict(s.key_rebinds()).is_empty()
	assert_int(s.gems()).is_equal(7)
	assert_float(float(s.get_setting("screen_shake", 9.9))).is_equal_approx(0.5, 0.0001)
	assert_int(int(s.unlock_tasks()["kills"])).is_equal(3)


func test_dirty_rebinds_fail_soft() -> void:
	# 畸形表逐项剔除不崩（fail-SOFT）：值非字典 / 键码非数字 / 修饰非 bool / 键码 0
	var path := _tmp_path("dirty")
	_write_json(path, '{"version": 2, "key_rebinds": {'
		+ '"move_left": "oops", '
		+ '"fire": {"physical_keycode": "x"}, '
		+ '"roll": {"physical_keycode": 32, "ctrl": "yes"}, '
		+ '"switch_weapon": {"physical_keycode": 0}, '
		+ '"skill": {"physical_keycode": 74.9}, '
		+ '"interact": {"physical_keycode": 69, "shift": true}}}')
	var s := _fresh_settings(path)
	var table: Dictionary = s.key_rebinds()
	assert_int(table.size()).is_equal(2)
	assert_int(int(table["skill"]["physical_keycode"])).is_equal(74)   # JSON float 截断归一
	assert_bool(bool(table["skill"]["shift"])).is_false()              # 缺省修饰回落 false
	assert_int(int(table["interact"]["physical_keycode"])).is_equal(69)
	assert_bool(bool(table["interact"]["shift"])).is_true()
	assert_bool(table.has("roll")).is_false()
	# 归一层不做动作白名单（单一事实源在 RebindPanelUI.REBINDABLE_ACTIONS，应用层
	# 跳过——同 unlock_tasks 不做 codex 白名单的先例）
	var direct: Dictionary = s.call("_normalize_key_rebinds",
		{"unknown_action": {"physical_keycode": KEY_A}})
	assert_int(direct.size()).is_equal(1)


# ---------------------------------------------------------------- 3) InputMap 即时生效

func test_apply_rebinds_immediate_effect_keeps_joypad() -> void:
	# 覆写 = 键鼠主事件替换为新键（旧键释放）、手柄事件保留（编排者裁定口径）
	RebindPanelUI.apply_rebinds({"switch_weapon":
		{"physical_keycode": KEY_R, "ctrl": false, "alt": false, "shift": false}})
	assert_bool(InputMap.has_action("switch_weapon")).is_true()
	assert_bool(_has_key_event("switch_weapon", _key(KEY_R))).is_true()   # 新键生效
	assert_bool(_has_key_event("switch_weapon", _key(KEY_Q))).is_false()  # 旧键 Q 释放
	var joy := false
	for ev: InputEvent in InputMap.action_get_events("switch_weapon"):
		if ev is InputEventJoypadButton:
			joy = true
	assert_bool(joy).is_true()
	# fire（默认鼠标左键）：改键后鼠标左键失效、新键生效
	RebindPanelUI.apply_rebinds({"fire":
		{"physical_keycode": KEY_G, "ctrl": false, "alt": false, "shift": false}})
	assert_bool(_has_key_event("fire", _key(KEY_G))).is_true()
	var mouse_left := false
	for ev: InputEvent in InputMap.action_get_events("fire"):
		var mb := ev as InputEventMouseButton
		if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
			mouse_left = true
	assert_bool(mouse_left).is_false()
	# 清单外动作（pause）/ 键码 0：应用层静默跳过（启动挂点 fail-soft）
	RebindPanelUI.apply_rebinds({"pause": {"physical_keycode": 80},
		"roll": {"physical_keycode": 0, "ctrl": false, "alt": false, "shift": false}})
	assert_bool(_has_key_event("pause", _key(80))).is_false()
	assert_bool(_has_key_event("roll", _key(80))).is_false()


# ---------------------------------------------------------------- 4) 面板：冲突拒绝 / 恢复默认 / 接受

func test_conflict_rejected_keeps_binding() -> void:
	var spy := _spy()
	var panel := _panel(spy)
	# move_left 改按 D（move_right 默认键）→ 提示并拒绝，原绑定不变
	panel.call("_start_listening", "move_left")
	assert_str(_status(panel).text).contains("按新键")
	panel.call("_capture_key", _key(KEY_D))
	assert_int(spy.rebind_calls.size()).is_equal(0)                       # 不写档
	assert_bool(_has_key_event("move_left", _key(KEY_A))).is_true()       # 原绑定 A 不变
	assert_bool(_has_key_event("move_left", _key(KEY_D))).is_false()
	assert_str(_status(panel).text).contains("移动右")                     # 提示占用者
	assert_str(String(panel.get("_listening"))).is_empty()                # 退出监听态
	# 与当前绑定相同 → 无操作（不写档不覆写，保住同动作的其余默认键事件）
	panel.call("_start_listening", "move_left")
	panel.call("_capture_key", _key(KEY_A))
	assert_int(spy.rebind_calls.size()).is_equal(0)
	assert_bool(_has_key_event("move_left", _key(4194319))).is_true()     # 方向键副键仍在


func test_accept_rebind_writes_save_and_inputmap() -> void:
	var path := _tmp_path("accept")
	var host := _fresh_settings(path)
	var panel := _panel(host)
	var seen: Array = []
	panel.connect("rebound", func(a: String) -> void: seen.append(a))
	panel.call("_start_listening", "switch_weapon")
	panel.call("_capture_key", _key(KEY_R))
	assert_int(seen.size()).is_equal(1)
	assert_str(String(seen[0])).is_equal("switch_weapon")
	assert_bool(_has_key_event("switch_weapon", _key(KEY_R))).is_true()   # 即时生效
	# 落盘 + 全新实例重读 → 往返一致
	var reloaded := _fresh_settings(path)
	var table: Dictionary = reloaded.key_rebinds()
	assert_int(int(table["switch_weapon"]["physical_keycode"])).is_equal(KEY_R)
	# 行按钮文字随新键刷新
	assert_str(_row(panel, "switch_weapon").text).contains("R")


func test_restore_defaults_rebuilds_project_bindings() -> void:
	var spy := _spy()
	var panel := _panel(spy)
	# 改两个键（写档 + InputMap 即时覆写）
	panel.call("_start_listening", "switch_weapon")
	panel.call("_capture_key", _key(KEY_R))
	panel.call("_start_listening", "skill")
	panel.call("_capture_key", _key(KEY_G))
	assert_bool(_has_key_event("switch_weapon", _key(KEY_R))).is_true()
	assert_bool(_has_key_event("skill", _key(KEY_G))).is_true()
	# 恢复默认：清表 + 按 project.godot 重建事件
	panel.call("_on_reset_pressed")
	assert_int(spy.clear_calls).is_equal(1)
	for action: String in RebindPanelUI.REBINDABLE_ACTIONS:
		var defaults: Array = _project_default_events(action)
		var current: Array = InputMap.action_get_events(action)
		assert_int(current.size()).override_failure_message(action).is_equal(defaults.size())
		for ev: InputEvent in defaults:
			var k := ev as InputEventKey
			if k != null:
				assert_bool(_has_key_event(action, k)).override_failure_message(action).is_true()
	assert_bool(_has_key_event("switch_weapon", _key(KEY_Q))).is_true()   # Q 回归
	assert_bool(_has_key_event("skill", _key(KEY_F))).is_true()           # F 回归


# ---------------------------------------------------------------- 5) 启动挂点

func test_save_ready_applies_rebinds_to_inputmap() -> void:
	# 启动挂点：SaveSystem._ready 读档后把覆写表应用到 InputMap（清单外动作跳过）
	var path := _tmp_path("hook")
	_write_json(path, '{"version": 2, "key_rebinds":'
		+ '{"skill": {"physical_keycode": %d}, "pause": {"physical_keycode": 80}}}' % KEY_J)
	var s: Node = auto_free(load(SAVE_SCRIPT).new())
	s.set("save_path", path)
	add_child(s)   # 触发 _ready：load_save + 应用覆写
	assert_bool(_has_key_event("skill", _key(KEY_J))).is_true()
	assert_bool(_has_key_event("pause", _key(80))).is_false()


# ---------------------------------------------------------------- 6) 面板冒烟

func test_panel_smoke_rows_and_listening_cancel() -> void:
	var spy := _spy()
	var panel := _panel(spy)
	var closed_seen: Array = []
	panel.connect("closed", func() -> void: closed_seen.append(true))
	# 9 行渲染：Grid 内按钮恰 9 个，节点名 = 动作名
	var grid: GridContainer = panel.get_node("Center/Panel/Margin/Rows/Grid")
	var buttons := 0
	for child: Node in grid.get_children():
		if child is Button:
			buttons += 1
	assert_int(buttons).is_equal(9)
	# 行初值从 project.godot 默认集读取（fire 无键事件 → 鼠标左键描述）
	assert_str(_row(panel, "move_left").text).is_equal("A")
	assert_str(_row(panel, "fire").text).is_equal("鼠标左键")
	# 初始隐藏 → open() 可见
	assert_bool(panel.visible).is_false()
	panel.call("open")
	assert_bool(panel.visible).is_true()
	# 非监听态 _input 直驱无副作用
	panel.call("_input", _key(KEY_R))
	assert_int(spy.rebind_calls.size()).is_equal(0)
	# 监听态 Esc 取消：无写入、提示复原
	panel.call("_start_listening", "fire")
	panel.call("_capture_key", _key(KEY_ESCAPE))
	assert_int(spy.rebind_calls.size()).is_equal(0)
	assert_str(_status(panel).text).is_equal(RebindPanelUI.STATUS_HINT)
	# 监听态 _input 路由到捕获（状态机经 _input 可控驱动）
	panel.call("_start_listening", "switch_weapon")
	panel.call("_input", _key(KEY_R))
	assert_int(spy.rebind_calls.size()).is_equal(1)
	# 返回：隐藏 + closed 信号
	panel.call("_on_back_pressed")
	assert_bool(panel.visible).is_false()
	assert_int(closed_seen.size()).is_equal(1)
