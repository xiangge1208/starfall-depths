@tool
extends SceneTree
## 幂等写入 InputMap 动作并保存到 project.godot
## 注意：运行时 InputMap.add_action 不会写入 ProjectSettings，
## 必须同步镜像到 `input/<action>` 设置项后 save()，动作才能在新进程中生效。

const ACTIONS := {
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"fire": [],        # 鼠标键在下方单独加
	"roll": [KEY_SHIFT, KEY_SPACE],
	"switch_weapon": [KEY_Q],
	"interact": [KEY_E],
	"skill": [KEY_F],
	"pause": [KEY_ESCAPE],
}

# m1-t21 手柄绑定（GDD §5.1）：左摇杆移动 / A 翻滚 / RB 技能 / LB 切枪 / X 交互。
# 桌面键位不动，手柄事件只是追加到同一动作（重映射仍走 InputMap）。
const JOYPAD_BUTTONS := {
	"roll": JOY_BUTTON_A,
	"skill": JOY_BUTTON_RIGHT_SHOULDER,
	"switch_weapon": JOY_BUTTON_LEFT_SHOULDER,
	"interact": JOY_BUTTON_X,
}

# 动作 → [轴, 极性]（左摇杆：轴0 横移 / 轴1 纵移）
const JOYPAD_AXES := {
	"move_left": [JOY_AXIS_LEFT_X, -1.0],
	"move_right": [JOY_AXIS_LEFT_X, 1.0],
	"move_up": [JOY_AXIS_LEFT_Y, -1.0],
	"move_down": [JOY_AXIS_LEFT_Y, 1.0],
}

# m1-t21 新动作：右摇杆瞄准（轴2/3，双向极性各一条事件；符号值由 gamepad_aim.gd 跟踪）
const AIM_AXIS_ACTIONS := {
	"aim_right_x": JOY_AXIS_RIGHT_X,
	"aim_right_y": JOY_AXIS_RIGHT_Y,
}

# m1-t21 触屏专用动作。它们必须保持无物理事件绑定：TouchControls 通过
# Input.action_press/release 独立驱动，不能与键鼠/手柄动作共用释放状态。
const TOUCH_ACTIONS: Array[String] = [
	"touch_move_left", "touch_move_right", "touch_move_up", "touch_move_down",
	"touch_fire", "touch_roll", "touch_switch_weapon", "touch_interact", "touch_skill",
]

func _init() -> void:
	for action: String in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		InputMap.action_erase_events(action)   # 幂等：清旧事件再写，重复运行不叠加
		var events: Array = []
		for key: Key in ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
			events.append(ev)
		if action == "fire":
			var mb := InputEventMouseButton.new()
			mb.button_index = MOUSE_BUTTON_LEFT
			InputMap.action_add_event(action, mb)
			events.append(mb)
		if JOYPAD_AXES.has(action):
			var axis: int = JOYPAD_AXES[action][0]
			var polarity: float = JOYPAD_AXES[action][1]
			var jm := InputEventJoypadMotion.new()
			jm.axis = axis
			jm.axis_value = polarity
			InputMap.action_add_event(action, jm)
			events.append(jm)
		if JOYPAD_BUTTONS.has(action):
			var jb := InputEventJoypadButton.new()
			jb.button_index = JOYPAD_BUTTONS[action]
			InputMap.action_add_event(action, jb)
			events.append(jb)
		ProjectSettings.set_setting("input/" + action, {"deadzone": 0.2, "events": events})
	# 右摇杆瞄准新动作（无键位，仅轴事件）
	for action: String in AIM_AXIS_ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		InputMap.action_erase_events(action)
		var events: Array = []
		for polarity: float in [-1.0, 1.0]:
			var jm := InputEventJoypadMotion.new()
			jm.axis = AIM_AXIS_ACTIONS[action]
			jm.axis_value = polarity
			InputMap.action_add_event(action, jm)
			events.append(jm)
		ProjectSettings.set_setting("input/" + action, {"deadzone": 0.2, "events": events})
	configure_touch_actions()
	# ProjectSettings.save() 会跳过"当前值 == initial(引擎默认值)"的设置项，
	# 而 60 恰为引擎默认，故仅 set_setting 仍会被省略；
	# 这里把 initial 改为不同值使其计入保存（仅本脚本进程内存生效，不影响引擎行为），
	# 确保 brief 要求的 physics/common/physics_ticks_per_second=60 稳定留在 project.godot。
	const PHYSICS_TICKS := "physics/common/physics_ticks_per_second"
	ProjectSettings.set_setting(PHYSICS_TICKS, 60)
	ProjectSettings.set_initial_value(PHYSICS_TICKS, -1)
	ProjectSettings.save()
	quit(0)


## 从空配置或旧配置幂等重建触屏动作。保持 public static，供门禁测试验证
## setup_input.gd 本身（而非当前 project.godot 偶然已有状态）能够完整生成 T21 契约。
static func configure_touch_actions() -> void:
	for action: String in TOUCH_ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		InputMap.action_erase_events(action)
		ProjectSettings.set_setting("input/" + action, {"deadzone": 0.2, "events": []})
