class_name TestPlayerInput
extends GdUnitTestSuite
## 生产 player.tscn 输入接线：技能/手柄/触屏/自动瞄准均由真实 Driver 消费。

const PLAYER_SCENE := preload("res://core/player/player.tscn")
const TOUCH_CONTROLS_SCENE := preload("res://ui/touch_controls.tscn")

class TargetDummy extends Node2D:
	var state := EnemyBase.State.ENGAGE

var _old_selected_slot := 0
var _old_touch_controls := false

func before_test() -> void:
	_old_selected_slot = RunState.selected_slot
	_old_touch_controls = bool(SaveSystem.get_setting("touch_controls", false))

func after_test() -> void:
	for action in ["fire", "skill", "roll", "switch_weapon", "interact",
			"move_left", "move_right", "move_up", "move_down", "touch_fire",
			"touch_skill", "touch_roll", "touch_switch_weapon", "touch_interact",
			"touch_move_left", "touch_move_right", "touch_move_up", "touch_move_down"]:
		Input.action_release(action)
	RunState.selected_slot = _old_selected_slot
	SaveSystem.data["settings"]["touch_controls"] = _old_touch_controls

func _player() -> Player:
	var p: Player = PLAYER_SCENE.instantiate()
	auto_free(p)
	add_child(p)
	return p

func test_production_player_contains_full_input_chain() -> void:
	var p := _player()
	assert_object(p.get_node_or_null("Driver")).is_not_null()
	assert_object(p.get_node_or_null("GamepadAim")).is_not_null()
	assert_object(p.get_node_or_null("TouchControls")).is_not_null()
	assert_object(p.get_node_or_null("TouchControls/Root/MoveJoystick")).is_not_null()
	assert_object(p.get_node_or_null("TouchControls/Root/AimJoystick")).is_not_null()
	assert_object(p.get_node_or_null("Skill")).is_not_null()

func test_gamepad_explicit_aim_wins_over_mouse_and_updates_facing() -> void:
	var p := _player()
	var pad: Node = p.get_node("GamepadAim")
	var driver: Node = p.get_node("Driver")
	pad._apply_axes(0.0, -1.0)
	driver._physics_process(0.0)
	assert_vector(p.facing).is_equal_approx(Vector2.UP, Vector2(0.001, 0.001))

func test_touch_aim_push_to_fire_updates_facing() -> void:
	var p := _player()
	var aim: Control = p.get_node("TouchControls/Root/AimJoystick")
	var driver: Node = p.get_node("Driver")
	aim._apply_raw(Vector2(-48, 0))
	assert_bool(Input.is_action_pressed("touch_fire")).is_true()
	assert_bool(Input.is_action_pressed("fire")).is_false()
	driver._physics_process(0.0)   # 起始房 combat=null：必须安全 no-op
	assert_vector(p.facing).is_equal_approx(Vector2.LEFT, Vector2(0.001, 0.001))

func test_ranger_skill_uses_current_explicit_aim_for_140px_dash() -> void:
	var p := _player()
	HeroApplier.apply(GameDB.get_hero("ranger"), p)
	var pad: Node = p.get_node("GamepadAim")
	var driver: Node = p.get_node("Driver")
	pad._apply_axes(0.0, 1.0)
	var start := p.position
	Input.action_press("skill")
	driver._physics_process(0.0)
	assert_vector(p.position - start).is_equal_approx(Vector2.DOWN * 140.0, Vector2(0.01, 0.01))
	# 按住技能时 just_pressed 只消费一次，不得逐帧重复影袭。
	var after_first := p.position
	driver._physics_process(0.0)
	assert_vector(p.position).is_equal_approx(after_first, Vector2(0.01, 0.01))

func test_fire_without_combat_system_is_safe_noop() -> void:
	var p := _player()
	var rig: WeaponRig = p.get_node("WeaponRig")
	rig.equip("laohuoji")
	assert_object(rig.combat).is_null()
	Input.action_press("fire")
	p.get_node("Driver")._physics_process(0.0)
	assert_int(p.energy).is_equal(100)

func test_touch_auto_aim_chooses_nearest_omnidirectional() -> void:
	var p := _player()
	p.position = Vector2.ZERO
	p.facing = Vector2.RIGHT
	var driver: Node = p.get_node("Driver")
	var rig: WeaponRig = p.get_node("WeaponRig")
	rig.equip("laohuoji")
	var combat_root: Node2D = auto_free(Node2D.new())
	add_child(combat_root)
	var combat := CombatSystem.new(combat_root, RngSvc.stream(77, "auto_aim"))
	combat_root.add_child(combat)
	rig.combat = combat
	driver.current_aim = Vector2.RIGHT
	driver.touch_mode_override = true
	var far_straight: TargetDummy = auto_free(TargetDummy.new())
	far_straight.position = Vector2(200, 5)
	far_straight.add_to_group("enemies")
	add_child(far_straight)
	var near_angled: TargetDummy = auto_free(TargetDummy.new())
	near_angled.position = Vector2(60, 30)
	near_angled.add_to_group("enemies")
	add_child(near_angled)
	SaveSystem.data["settings"]["auto_aim"] = true
	driver._physics_process(0.0)
	assert_vector(p.facing).is_equal_approx(Vector2(60, 30).normalized(), Vector2(0.001, 0.001))
	assert_int(combat.active_count()).is_equal(1)   # 无右杆/无 fire 输入也向锁定目标自动开火

func test_touch_auto_aim_acquires_target_behind_player() -> void:
	# m4p 全向索敌：身后敌人（旧 60° 锥语义下不可达）也被锁定——朝向自动回身。
	var p := _player()
	p.position = Vector2.ZERO
	p.facing = Vector2.RIGHT
	var driver: Node = p.get_node("Driver")
	var rig: WeaponRig = p.get_node("WeaponRig")
	rig.equip("laohuoji")
	var combat_root: Node2D = auto_free(Node2D.new())
	add_child(combat_root)
	var combat := CombatSystem.new(combat_root, RngSvc.stream(79, "auto_aim_behind"))
	combat_root.add_child(combat)
	rig.combat = combat
	driver.current_aim = Vector2.RIGHT
	driver.touch_mode_override = true
	var behind: TargetDummy = auto_free(TargetDummy.new())
	behind.position = Vector2(-80, 0)
	behind.add_to_group("enemies")
	add_child(behind)
	SaveSystem.data["settings"]["auto_aim"] = true
	driver._physics_process(0.0)
	assert_vector(p.facing).is_equal_approx(Vector2.LEFT, Vector2(0.001, 0.001))
	assert_int(combat.active_count()).is_equal(1)

func test_desktop_auto_aim_locks_nearest_fires_only_on_key() -> void:
	# m4p 桌面全向索敌：auto_aim 开 → 朝向锁最近敌（鼠标不再决定朝向）；
	# 但不自动开火——扣 fire 才射（与触屏「锁定即射」的刻意差异）。
	var p := _player()
	p.position = Vector2.ZERO
	p.facing = Vector2.RIGHT
	var driver: Node = p.get_node("Driver")
	var rig: WeaponRig = p.get_node("WeaponRig")
	rig.equip("laohuoji")
	var combat_root: Node2D = auto_free(Node2D.new())
	add_child(combat_root)
	var combat := CombatSystem.new(combat_root, RngSvc.stream(80, "auto_aim_desktop"))
	combat_root.add_child(combat)
	rig.combat = combat
	driver.current_aim = Vector2.RIGHT
	driver.touch_mode_override = false     # 桌面路径
	var near: TargetDummy = auto_free(TargetDummy.new())
	near.position = Vector2(0, -50)
	near.add_to_group("enemies")
	add_child(near)
	var far: TargetDummy = auto_free(TargetDummy.new())
	far.position = Vector2(300, 0)
	far.add_to_group("enemies")
	add_child(far)
	SaveSystem.data["settings"]["auto_aim"] = true
	driver._physics_process(0.0)
	assert_vector(p.facing).is_equal_approx(Vector2.UP, Vector2(0.001, 0.001))
	assert_int(combat.active_count()).is_equal(0)  # 未扣 fire：不自动开火
	Input.action_press("fire")
	driver._physics_process(0.0)
	Input.action_release("fire")
	assert_int(combat.active_count()).is_equal(1)  # 扣 fire：向锁定目标射出

func test_desktop_auto_aim_off_keeps_mouse_aim_path() -> void:
	# auto_aim 关：桌面回到既有鼠标瞄准路径（本测只钉「不锁敌」——facing 不被
	# 场上敌人改写为指向它；鼠标合成事件在 headless 下不可靠，方向值不断言）。
	var p := _player()
	p.position = Vector2.ZERO
	var driver: Node = p.get_node("Driver")
	driver.current_aim = Vector2.UP
	driver.touch_mode_override = false
	var target: TargetDummy = auto_free(TargetDummy.new())
	target.position = Vector2(50, 0)
	target.add_to_group("enemies")
	add_child(target)
	var old: bool = bool(SaveSystem.get_setting("auto_aim", true))
	SaveSystem.data["settings"]["auto_aim"] = false
	driver._physics_process(0.0)
	SaveSystem.data["settings"]["auto_aim"] = old
	assert_vector(p.facing).is_not_equal(Vector2.RIGHT)

func test_touch_auto_aim_off_keeps_current_aim() -> void:
	var p := _player()
	var driver: Node = p.get_node("Driver")
	var rig: WeaponRig = p.get_node("WeaponRig")
	rig.equip("laohuoji")
	var combat_root: Node2D = auto_free(Node2D.new())
	add_child(combat_root)
	var combat := CombatSystem.new(combat_root, RngSvc.stream(78, "auto_aim_off"))
	combat_root.add_child(combat)
	rig.combat = combat
	driver.current_aim = Vector2.UP
	driver.touch_mode_override = true
	var target: TargetDummy = auto_free(TargetDummy.new())
	target.position = Vector2(20, 0)
	target.add_to_group("enemies")
	add_child(target)
	var old: bool = bool(SaveSystem.get_setting("auto_aim", true))
	SaveSystem.data["settings"]["auto_aim"] = false
	driver._physics_process(0.0)
	SaveSystem.data["settings"]["auto_aim"] = old
	assert_vector(p.facing).is_equal(Vector2.UP)
	assert_int(combat.active_count()).is_equal(0)

func test_driver_touch_mode_explicit_override_wins() -> void:
	var p := _player()
	var driver: Node = p.get_node("Driver")
	driver.touch_mode_override = true
	assert_bool(driver._touch_mode()).is_true()
	driver.touch_mode_override = false
	assert_bool(driver._touch_mode()).is_false()

func test_saved_desktop_touch_setting_enables_ui_and_driver_together() -> void:
	SaveSystem.data["settings"]["touch_controls"] = true
	var p := _player()
	var controls: CanvasLayer = p.get_node("TouchControls")
	controls._refresh_visibility()
	assert_bool(controls.visible).is_true()
	assert_bool((controls.get_node("Root/MoveJoystick") as Control).visible).is_true()
	assert_bool((controls.get_node("Root/AimJoystick") as Control).visible).is_true()
	assert_bool(p.get_node("Driver")._touch_mode()).is_true()

func test_production_switch_updates_run_state_selected_slot() -> void:
	var p := _player()
	var rig: WeaponRig = p.get_node("WeaponRig")
	# 正式局由 RunRoot 在 HeroApplier 之前绑定；本测试直接实例化 player.tscn，
	# 因而需要复现同一生产装配接缝，不能把未绑定的训练/组件模式误判成同步失败。
	rig.bind_run_state(RunState)
	rig.equip("laohuoji")
	rig.equip("tiejian")
	RunState.selected_slot = 0
	Input.action_press("switch_weapon")
	p.get_node("Driver")._physics_process(0.0)
	Input.action_release("switch_weapon")
	assert_int(rig.slot).is_equal(1)
	assert_int(RunState.selected_slot).is_equal(1)

func test_touch_controls_force_visible_reveals_both_joysticks() -> void:
	var controls: CanvasLayer = TOUCH_CONTROLS_SCENE.instantiate()
	controls.force_visible = true
	auto_free(controls)
	add_child(controls)
	assert_bool(controls.visible).is_true()
	assert_bool((controls.get_node("Root/MoveJoystick") as Control).visible).is_true()
	assert_bool((controls.get_node("Root/AimJoystick") as Control).visible).is_true()

func test_move_joystick_exit_releases_only_touch_actions() -> void:
	var stick: Control = auto_free(load("res://ui/virtual_joystick.gd").new())
	Input.action_press("move_right")
	stick._apply_raw(Vector2(48, -48))
	assert_bool(Input.is_action_pressed("touch_move_right")).is_true()
	assert_bool(Input.is_action_pressed("touch_move_up")).is_true()
	stick._exit_tree()
	assert_bool(Input.is_action_pressed("touch_move_right")).is_false()
	assert_bool(Input.is_action_pressed("touch_move_up")).is_false()
	assert_bool(Input.is_action_pressed("move_right")).is_true()

func test_driver_fire_sources_remain_independent() -> void:
	var p := _player()
	var driver: Node = p.get_node("Driver")
	var pad: Node = p.get_node("GamepadAim")
	var aim: Control = p.get_node("TouchControls/Root/AimJoystick")
	pad._apply_axes(1.0, 0.0)
	aim._apply_raw(Vector2.RIGHT * 48.0)
	assert_bool(driver._fire_requested()).is_true()
	aim._apply_raw(Vector2.ZERO)
	assert_bool(driver._fire_requested()).is_true()
	pad._apply_axes(0.0, 0.0)
	assert_bool(driver._fire_requested()).is_false()
	Input.action_press("fire")
	aim._apply_raw(Vector2.RIGHT * 48.0)
	aim._apply_raw(Vector2.ZERO)
	assert_bool(driver._fire_requested()).is_true()

func test_mouse_dragging_move_joystick_masks_physical_left_click_fire() -> void:
	var p := _player()
	var driver: Node = p.get_node("Driver")
	var move: Control = p.get_node("TouchControls/Root/MoveJoystick")
	Input.action_press("fire") # 模拟 project.godot 的左键映射已先进入 InputMap
	var press := InputEventMouseButton.new()
	press.device = 0
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(32, 32)
	move._gui_input(press)
	assert_bool(driver._fire_requested()).is_false()
	press.pressed = false
	move._gui_input(press)
	assert_bool(driver._fire_requested()).is_true()

func test_touch_or_keyboard_button_activation_does_not_mask_physical_fire() -> void:
	var p := _player()
	var controls: CanvasLayer = p.get_node("TouchControls")
	var driver: Node = p.get_node("Driver")
	var skill_button: Button = controls.get_node("Root/SkillButton")
	Input.action_press("fire")

	var touch := InputEventScreenTouch.new()
	touch.index = 7
	touch.pressed = true
	touch.position = Vector2(5, 5)
	skill_button.gui_input.emit(touch)
	skill_button.button_down.emit()
	assert_bool(controls.captures_pointer_fire()).is_false()
	assert_bool(driver._fire_requested()).is_true()
	skill_button.button_up.emit()

	var key := InputEventKey.new()
	key.physical_keycode = KEY_ENTER
	key.pressed = true
	skill_button.gui_input.emit(key)
	skill_button.button_down.emit()
	assert_bool(controls.captures_pointer_fire()).is_false()
	assert_bool(driver._fire_requested()).is_true()
	skill_button.button_up.emit()

func test_mouse_button_activation_masks_fire_until_same_button_releases() -> void:
	var p := _player()
	var controls: CanvasLayer = p.get_node("TouchControls")
	var driver: Node = p.get_node("Driver")
	var roll_button: Button = controls.get_node("Root/RollButton")
	Input.action_press("fire")

	var mouse := InputEventMouseButton.new()
	mouse.device = 0
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	roll_button.gui_input.emit(mouse)
	roll_button.button_down.emit()
	assert_bool(controls.captures_pointer_fire()).is_true()
	assert_bool(driver._fire_requested()).is_false()
	roll_button.button_up.emit()
	assert_bool(controls.captures_pointer_fire()).is_false()
	assert_bool(driver._fire_requested()).is_true()

func test_single_button_exit_releases_only_its_touch_action() -> void:
	var controls: CanvasLayer = TOUCH_CONTROLS_SCENE.instantiate()
	auto_free(controls)
	add_child(controls)
	var roll_button: Button = controls.get_node("Root/RollButton")
	Input.action_press("touch_skill")
	roll_button.button_down.emit()
	assert_bool(Input.is_action_pressed("touch_roll")).is_true()
	roll_button.free()
	assert_bool(Input.is_action_pressed("touch_roll")).is_false()
	assert_bool(Input.is_action_pressed("touch_skill")).is_true()

func test_pointer_capture_masks_only_mouse_during_touch_gamepad_interleave() -> void:
	var p := _player()
	var controls: CanvasLayer = p.get_node("TouchControls")
	var driver: Node = p.get_node("Driver")
	var move: Control = controls.get_node("Root/MoveJoystick")
	var aim: Control = controls.get_node("Root/AimJoystick")
	var pad: Node = p.get_node("GamepadAim")
	Input.action_press("fire")
	var mouse := InputEventMouseButton.new()
	mouse.device = 0
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	move._gui_input(mouse)
	assert_bool(driver._fire_requested()).is_false()

	pad._apply_axes(1.0, 0.0)
	assert_bool(driver._fire_requested()).is_true()
	aim._apply_raw(Vector2.UP * 48.0)
	pad._apply_axes(0.0, 0.0)
	assert_bool(driver._fire_requested()).is_true()
	aim._apply_raw(Vector2.ZERO)
	assert_bool(driver._fire_requested()).is_false()

	mouse.pressed = false
	move._gui_input(mouse)
	assert_bool(driver._fire_requested()).is_true()

func test_touch_controls_exit_releases_own_actions_not_physical_sources() -> void:
	var controls: CanvasLayer = TOUCH_CONTROLS_SCENE.instantiate()
	auto_free(controls)
	add_child(controls)
	Input.action_press("fire")
	Input.action_press("move_right")
	Input.action_press("touch_fire")
	Input.action_press("touch_skill")
	Input.action_press("touch_roll")
	Input.action_press("touch_switch_weapon")
	Input.action_press("touch_interact")
	controls._exit_tree()
	for action in [&"touch_fire", &"touch_skill", &"touch_roll", &"touch_switch_weapon", &"touch_interact"]:
		assert_bool(Input.is_action_pressed(action)).override_failure_message(action).is_false()
	assert_bool(Input.is_action_pressed("fire")).is_true()
	assert_bool(Input.is_action_pressed("move_right")).is_true()
