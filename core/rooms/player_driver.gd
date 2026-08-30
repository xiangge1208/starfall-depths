extends Node
## 玩家生产输入驱动：桌面鼠标、手柄右杆、触屏右杆和触屏自动瞄准统一在此消费。
## 技能先使用本拍瞄准更新 facing，再以 just_pressed 施放一次；开火/切枪随后处理。

var _player: Player
var _rig: WeaponRig
var _melee: Melee
var _skill: SkillBase
var _gamepad_aim: Node
var _touch_controls: CanvasLayer
var current_aim := Vector2.RIGHT
var _auto_target_locked := false

## 测试可显式覆写触屏模式；null 时按触屏能力、mobile feature 或持久设置判定。
var touch_mode_override: Variant = null

func _ready() -> void:
	_player = get_parent() as Player
	_rig = _player.get_node_or_null("WeaponRig") as WeaponRig
	_melee = _player.get_node_or_null("Melee") as Melee
	_skill = _player.get_node_or_null("Skill") as SkillBase
	_gamepad_aim = _player.get_node_or_null("GamepadAim")
	_touch_controls = _player.get_node_or_null("TouchControls") as CanvasLayer
	if _player.facing != Vector2.ZERO:
		current_aim = _player.facing.normalized()

func _physics_process(_delta: float) -> void:
	if _player == null:
		return
	var frame := Engine.get_physics_frames()
	var aim := _resolve_aim()
	if aim != Vector2.ZERO:
		current_aim = aim.normalized()
		_player.facing = current_aim
	if (Input.is_action_just_pressed("skill") or Input.is_action_just_pressed("touch_skill")) \
			and _skill != null:
		_skill.cast(frame)
	if _fire_requested() or _auto_target_locked:
		var w := _rig.current() if _rig != null else {}
		if not w.is_empty() and bool(w.get("is_melee", false)):
			if _melee != null and _melee.combat != null and _melee.try_attack(frame):
				Telemetry.log_row(["fire", frame, String(w.get("id", ""))])
		elif _rig != null and _rig.combat != null and current_aim != Vector2.ZERO \
				and _rig.try_fire(current_aim, frame):
			Telemetry.log_row(["fire", frame, String(_rig.current().get("id", ""))])
	if (Input.is_action_just_pressed("switch_weapon") \
			or Input.is_action_just_pressed("touch_switch_weapon")) and _rig != null:
		_rig.switch_slot(frame)

func _touch_mouse_captured() -> bool:
	if _touch_controls == null:
		return false
	return bool(_touch_controls.call("captures_pointer_fire"))

func _fire_requested() -> bool:
	var touch_fire := Input.is_action_pressed("touch_fire")
	var gamepad_fire := false
	if _gamepad_aim != null:
		var pad: Vector2 = _gamepad_aim.get("aim_vector")
		gamepad_fire = pad != Vector2.ZERO
	var physical_fire := Input.is_action_pressed("fire")
	# 桌面调试开启触屏控件时，左键本身仍属于物理 fire 映射；若它正在被
	# 虚拟摇杆捕获，则只有右杆生成的 touch_fire 可以请求射击。
	if _touch_mouse_captured():
		physical_fire = false
	return physical_fire or touch_fire or gamepad_fire

func _touch_mode() -> bool:
	return TouchMode.enabled(
		DisplayServer.is_touchscreen_available(),
		OS.has_feature("mobile"),
		bool(SaveSystem.get_setting("touch_controls", false)),
		touch_mode_override)

func _explicit_aim() -> Vector2:
	if _touch_controls != null:
		var touch_aim: Variant = _touch_controls.get_node_or_null("Root/AimJoystick")
		if touch_aim != null:
			var v: Vector2 = touch_aim.get("aim_vector")
			if v != Vector2.ZERO:
				return v.normalized()
	if _gamepad_aim != null:
		var pad: Vector2 = _gamepad_aim.get("aim_vector")
		if pad != Vector2.ZERO:
			return pad.normalized()
	return Vector2.ZERO

func _resolve_aim() -> Vector2:
	_auto_target_locked = false
	var explicit := _explicit_aim()
	if explicit != Vector2.ZERO:
		return explicit
	if _touch_mode():
		if bool(SaveSystem.get_setting("auto_aim", true)):
			var targets: Array[Vector2] = []
			for node in get_tree().get_nodes_in_group("enemies"):
				if node is Node2D and not bool(node.get("state") == EnemyBase.State.DEAD):
					targets.append((node as Node2D).global_position)
			var idx := AutoAim.pick_target(_player.global_position, current_aim.angle(), targets)
			if idx >= 0:
				_auto_target_locked = true
				return (targets[idx] - _player.global_position).normalized()
			return current_aim
		return current_aim
	var mouse := _player.get_global_mouse_position() - _player.global_position
	return mouse.normalized() if mouse != Vector2.ZERO else current_aim
