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

func _init() -> void:
	for action: String in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
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
		ProjectSettings.set_setting("input/" + action, {"deadzone": 0.2, "events": events})
	ProjectSettings.save()
	quit(0)
