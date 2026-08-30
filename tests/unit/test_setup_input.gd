class_name TestSetupInput
extends GdUnitTestSuite
## m1-t21：setup_input.gd 必须能从干净 InputMap 幂等生成全部触屏动作。

const SetupInputScript := preload("res://tools/setup_input.gd")
const REQUIRED_TOUCH_ACTIONS: Array[String] = [
	"touch_move_left", "touch_move_right", "touch_move_up", "touch_move_down",
	"touch_fire", "touch_roll", "touch_switch_weapon", "touch_interact", "touch_skill",
]

var _saved_actions: Dictionary = {}
var _saved_settings: Dictionary = {}


func before_test() -> void:
	_saved_actions.clear()
	_saved_settings.clear()
	for action: String in REQUIRED_TOUCH_ACTIONS:
		var existed := InputMap.has_action(action)
		_saved_actions[action] = {
			"existed": existed,
			"deadzone": InputMap.action_get_deadzone(action) if existed else 0.2,
			"events": InputMap.action_get_events(action).duplicate() if existed else [],
		}
		var key := "input/" + action
		_saved_settings[key] = {
			"existed": ProjectSettings.has_setting(key),
			"value": ProjectSettings.get_setting(key) if ProjectSettings.has_setting(key) else null,
		}


func after_test() -> void:
	for action: String in REQUIRED_TOUCH_ACTIONS:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
		var saved: Dictionary = _saved_actions[action]
		if bool(saved["existed"]):
			InputMap.add_action(action, float(saved["deadzone"]))
			for event: InputEvent in saved["events"]:
				InputMap.action_add_event(action, event)
		var key := "input/" + action
		var saved_setting: Dictionary = _saved_settings[key]
		if bool(saved_setting["existed"]):
			ProjectSettings.set_setting(key, saved_setting["value"])
		else:
			ProjectSettings.clear(key)


func test_touch_action_contract_is_complete() -> void:
	assert_array(SetupInputScript.TOUCH_ACTIONS).contains_exactly(REQUIRED_TOUCH_ACTIONS)


func test_project_explicitly_locks_physics_to_60hz() -> void:
	var project_text := FileAccess.get_file_as_string("res://project.godot")
	assert_str(project_text).contains("[physics]")
	assert_str(project_text).contains("common/physics_ticks_per_second=60")


func test_configure_touch_actions_from_clean_map_is_idempotent_and_unbound() -> void:
	for action: String in REQUIRED_TOUCH_ACTIONS:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
		ProjectSettings.clear("input/" + action)

	SetupInputScript.configure_touch_actions()
	_assert_touch_actions_generated()
	# 第二次运行不得叠事件、改动作数量或改变镜像结构。
	SetupInputScript.configure_touch_actions()
	_assert_touch_actions_generated()


func _assert_touch_actions_generated() -> void:
	for action: String in REQUIRED_TOUCH_ACTIONS:
		assert_bool(InputMap.has_action(action)).override_failure_message(action).is_true()
		assert_float(InputMap.action_get_deadzone(action)).is_equal_approx(0.2, 0.0001)
		assert_array(InputMap.action_get_events(action)).is_empty()
		var setting: Dictionary = ProjectSettings.get_setting("input/" + action, {})
		assert_float(float(setting.get("deadzone", -1.0))).is_equal_approx(0.2, 0.0001)
		assert_array(setting.get("events", []) as Array).is_empty()
