class_name RebindPanelUI
extends Control
## m3-sb 按键重映射面板（S-B）：独立覆盖层场景（同 settings_panel 手法，任意场景
## 可实例化，不进 SceneRouter 路由）。9 个可重映射动作（GDD §5.1「所有按键可重
## 映射」）：移动四向 / 射击 / 技能 / 翻滚 / 切武器 / 交互。范围外不入清单（Backlog）：
## pause（消费者已落地=ui/pause_menu.gd 暂停菜单，重映射仍不开放——呼出键固定
## Esc/手柄 Start，防止误改后无法呼出）、aim_right_* 为手柄轴（v1 手柄轴不开放重映射）、
## touch_* 为虚拟触屏动作（虚拟面板直接驱动同动作，不依赖键位）。
##
## 流程：点击动作行 → 监听态（状态机 _listening）→ 捕获下一 InputEventKey →
## 冲突检测（编排者裁定：提示并拒绝，不做交换）→ 写存档 + InputMap 运行时覆写
## （即时生效，不写回 project.godot）。Esc 取消；「恢复默认」清存档表并按
## project.godot 默认集重建 InputMap 事件。
##
## 覆写口径（编排者裁定）：重映射 = 覆写该动作的键鼠主事件为新的 InputEventKey
## （该动作原键事件与鼠标事件一并移除——fire 改键后鼠标左键失效、新键生效，符合
## 「改键」直觉），手柄事件保留（手柄轴/键不开放重映射）；触屏走虚拟面板发送同
## 动作，不受影响。被替换的旧键从 InputMap 释放，可再绑定到其他动作。
##
## 捕获实现：_input 前置截获 + set_input_as_handled（比 _unhandled_input 可靠——
## 聚焦按钮会先消费方向键/Enter/Space，而它们恰是常见改键目标），仅键盘按下沿。
## 测试注入缝：save_host（缺省探测 /root/SaveSystem）；监听态可经 _start_listening
## + _capture_key（或 _input 直驱）在 headless 可控测试。

signal closed()
signal rebound(action: String)
signal conflict_rejected(action: String, holder: String)
signal defaults_restored()

## 可重映射动作清单（单一事实源：SaveSystem 归一化不做白名单，应用层据此跳过）
const REBINDABLE_ACTIONS: Array[String] = [
	"move_left", "move_right", "move_up", "move_down",
	"fire", "skill", "roll", "switch_weapon", "interact",
]
const ACTION_NAMES := {
	"move_left": "移动左", "move_right": "移动右", "move_up": "移动上", "move_down": "移动下",
	"fire": "射击", "skill": "技能", "roll": "翻滚",
	"switch_weapon": "切武器", "interact": "交互",
}
const STATUS_HINT := "点击动作行改键（Esc 取消）"

var save_host: Node = null   # 测试注入缝；_ready 兜底探测 /root/SaveSystem
var _listening := ""         # 监听态状态机："" = 空闲，否则为待改动作名

@onready var _grid: GridContainer = $Center/Panel/Margin/Rows/Grid
@onready var _status: Label = $Center/Panel/Margin/Rows/Status
@onready var _reset: Button = $Center/Panel/Margin/Rows/Btns/ResetBtn
@onready var _back: Button = $Center/Panel/Margin/Rows/Btns/BackBtn


func _ready() -> void:
	if save_host == null:
		save_host = get_node_or_null("/root/SaveSystem")
	for action: String in REBINDABLE_ACTIONS:
		var btn: Button = _grid.get_node(NodePath(action))
		btn.pressed.connect(_start_listening.bind(action))
	_reset.pressed.connect(_on_reset_pressed)
	_back.pressed.connect(_on_back_pressed)
	_refresh_rows()


## 打开面板：复位状态 + 行文字按当前 InputMap 刷新 + 焦点落「返 回」
## （键盘可达的安全出口；↑↓/Tab 导航行，Enter 确认）。
func open() -> void:
	_listening = ""
	_status.text = STATUS_HINT
	_refresh_rows()
	visible = true
	_back.grab_focus()


func _refresh_rows() -> void:
	for action: String in REBINDABLE_ACTIONS:
		(_grid.get_node(NodePath(action)) as Button).text = describe_binding(action)


## 进入监听态：下一按键将尝试绑定到该动作。
func _start_listening(action: String) -> void:
	_listening = action
	_status.text = "%s：按新键…（Esc 取消）" % ACTION_NAMES[action]


## 监听态键捕获入口（_input 前置截获，见类注释）：仅键盘按下沿进入状态机。
func _input(event: InputEvent) -> void:
	if not visible or _listening == "":
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	get_viewport().set_input_as_handled()
	_capture_key(key)


## 监听态状态机（headless 可直驱）：Esc 取消 / 与当前绑定相同 → 无操作 / 冲突拒绝 /
## 通过 → 写档 + InputMap 即时覆写。
func _capture_key(key: InputEventKey) -> void:
	var action := _listening
	_listening = ""
	if action == "":
		return
	if key.physical_keycode == KEY_ESCAPE:
		_status.text = STATUS_HINT
		_refresh_rows()
		return
	for ev: InputEvent in InputMap.action_get_events(action):
		var k := ev as InputEventKey
		if k != null and key_events_match(key, k):
			_status.text = STATUS_HINT   # 与当前绑定相同 → 无操作（不产生冗余覆写，
			return                       #  同动作其余默认键事件原样保留）
	var holder := find_conflict(action, key)
	if holder != "":
		_status.text = "该键已用于 %s，已拒绝" % String(ACTION_NAMES.get(holder, holder))
		_refresh_rows()
		conflict_rejected.emit(action, holder)
		return
	_write_rebind(action, key)


## 通过：InputMap 即时覆写 + 存档落盘（宿主缺席时仅运行时生效，不落盘）。
func _write_rebind(action: String, key: InputEventKey) -> void:
	var data := serialize_key_event(key)
	apply_rebind(action, key)
	if save_host != null and save_host.has_method("record_key_rebind"):
		save_host.record_key_rebind(action, data)
	_status.text = "已设置"
	_refresh_rows()
	rebound.emit(action)


## 恢复默认：清存档表（空表 = 全默认）+ 按 project.godot 默认集重建 InputMap 事件。
func _on_reset_pressed() -> void:
	if save_host != null and save_host.has_method("clear_key_rebinds"):
		save_host.clear_key_rebinds()
	restore_all_defaults()
	_status.text = "已恢复默认键位"
	_refresh_rows()
	defaults_restored.emit()


## 返回：只隐藏（实例保留，改键状态由存档承载）。
func _on_back_pressed() -> void:
	visible = false
	closed.emit()


# ---- 纯逻辑/静态域（面板与 SaveSystem 启动挂点共用；无场景依赖）----

## InputEventKey → 序列化字典（physical_keycode + 三修饰键；event.as_text 受区域
## 设置影响不可靠，故用结构化字段）。
static func serialize_key_event(key: InputEventKey) -> Dictionary:
	return {
		"physical_keycode": int(key.physical_keycode),
		"ctrl": key.ctrl_pressed,
		"alt": key.alt_pressed,
		"shift": key.shift_pressed,
	}


## 序列化字典 → InputEventKey（缺键回落：键码 0 = KEY_NONE，修饰 false）。
static func deserialize_key_event(data: Dictionary) -> InputEventKey:
	var key := InputEventKey.new()
	key.physical_keycode = int(data.get("physical_keycode", 0)) as Key
	key.ctrl_pressed = bool(data.get("ctrl", false))
	key.alt_pressed = bool(data.get("alt", false))
	key.shift_pressed = bool(data.get("shift", false))
	return key


## 键事件精确匹配（physical_keycode + ctrl/alt/shift）。
static func key_events_match(a: InputEventKey, b: InputEventKey) -> bool:
	return a.physical_keycode == b.physical_keycode \
		and a.ctrl_pressed == b.ctrl_pressed \
		and a.alt_pressed == b.alt_pressed \
		and a.shift_pressed == b.shift_pressed


## 冲突检测：遍历 9 动作在 InputMap 的现有键盘事件（默认集 + 已改键——启动挂点
## 已把档内覆写应用过，InputMap 即当前有效集），返回占用者动作名；目标动作自身
## 不算冲突（空串 = 无冲突）。
static func find_conflict(target: String, key: InputEventKey) -> String:
	for action: String in REBINDABLE_ACTIONS:
		if action == target:
			continue
		for ev: InputEvent in InputMap.action_get_events(action):
			var k := ev as InputEventKey
			if k != null and key_events_match(key, k):
				return action
	return ""


## 单动作运行时覆写：清该动作全部键鼠事件（含 fire 的鼠标默认事件——口径见类
## 注释），保留手柄事件，追加新键。仅运行时 InputMap，不写回 project.godot。
## 先收集后擦除（action_get_events 返回内部数组引用，边遍历边擦会破坏迭代）。
static func apply_rebind(action: String, key: InputEventKey) -> void:
	if not InputMap.has_action(action):
		return
	var drop: Array[InputEvent] = []
	for ev: InputEvent in InputMap.action_get_events(action):
		if ev is InputEventKey or ev is InputEventMouseButton:
			drop.append(ev)
	for ev: InputEvent in drop:
		InputMap.action_erase_event(action, ev)
	InputMap.action_add_event(action, key)


## 覆写表批量应用（启动挂点用）：清单外动作 / 非法条目 / 键码 0 静默跳过（fail-SOFT）。
static func apply_rebinds(table: Dictionary) -> void:
	for action: Variant in table:
		var data: Variant = table[action]
		if typeof(action) != TYPE_STRING or typeof(data) != TYPE_DICTIONARY:
			continue
		var action_name := String(action)
		if not REBINDABLE_ACTIONS.has(action_name) or not InputMap.has_action(action_name):
			continue
		var key := deserialize_key_event(data)
		if key.physical_keycode == KEY_NONE:
			continue
		apply_rebind(action_name, key)


## 单动作按 project.godot 默认集重建 InputMap 事件（「恢复默认」基线；运行时覆写，
## 不写回 project.godot；事件 duplicate 防与 ProjectSettings 共享引用）。
static func restore_action_default(action: String) -> void:
	if not InputMap.has_action(action):
		return
	var setting: Variant = ProjectSettings.get_setting("input/" + action)
	if typeof(setting) != TYPE_DICTIONARY:
		return
	InputMap.action_erase_events(action)
	for ev: InputEvent in (setting as Dictionary).get("events", []):
		InputMap.action_add_event(action, ev.duplicate() as InputEvent)


static func restore_all_defaults() -> void:
	for action: String in REBINDABLE_ACTIONS:
		restore_action_default(action)


## 当前绑定描述（行按钮文字）：主键事件（键名含修饰前缀）；无键事件时描述鼠标键
## （fire 默认 = 鼠标左键）；都没有 → 「无」。
static func describe_binding(action: String) -> String:
	if not InputMap.has_action(action):
		return "无"
	for ev: InputEvent in InputMap.action_get_events(action):
		var key := ev as InputEventKey
		if key != null:
			var prefix := ""
			if key.ctrl_pressed:
				prefix += "Ctrl+"
			if key.alt_pressed:
				prefix += "Alt+"
			if key.shift_pressed:
				prefix += "Shift+"
			return prefix + OS.get_keycode_string(key.physical_keycode)
		var mouse := ev as InputEventMouseButton
		if mouse != null:
			match mouse.button_index:
				MOUSE_BUTTON_LEFT:
					return "鼠标左键"
				MOUSE_BUTTON_RIGHT:
					return "鼠标右键"
				MOUSE_BUTTON_MIDDLE:
					return "鼠标中键"
				_:
					return "鼠标 %d" % mouse.button_index
	return "无"
