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
				_log_fire(w, frame)
		elif _rig != null and _rig.combat != null and current_aim != Vector2.ZERO \
				and _rig.try_fire(current_aim, frame):
			_log_fire(_rig.current(), frame)
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


## 开火/挥击成功点（近战 try_attack / 远程 try_fire 各一处汇口）：
## telemetry fire 行（m1-t18 契约）+ 成就开火窗口源（m2-t33 补线，K.3 赤手空拳
## 「本层仅用近战」口径：近战挥击计 melee，其余计远程）。
func _log_fire(w: Dictionary, frame: int) -> void:
	var id := String(w.get("id", ""))
	Telemetry.log_row(["fire", frame, id])
	AchievementSystem.notify_weapon_used(id)

func _touch_mode() -> bool:
	return TouchMode.enabled(
		DisplayServer.is_touchscreen_available(),
		OS.has_feature("mobile"),
		bool(SaveSystem.get_setting("touch_controls", false)),
		touch_mode_override,
		SaveSystem.is_setting_explicit("touch_controls") == true)

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
	var auto_on := bool(SaveSystem.get_setting("auto_aim", true))
	if _touch_mode():
		if auto_on:
			var auto_dir := _auto_aim_dir()
			if auto_dir != Vector2.ZERO:
				_auto_target_locked = true   # 触屏语义不变：锁定即自动开火
				return auto_dir
			return current_aim
		return current_aim
	# 桌面（m4p 全向索敌）：auto_aim 开启时朝向自动锁最近敌人（元气骑士式），
	# 鼠标退为「场上无敌人」的回退瞄准；开火仍由 fire 键控制（不设 _auto_target_locked，
	# 桌面不自动开火——与触屏「锁定即射」的差异是刻意的：鼠标端保留扣扳机的操作感）。
	if auto_on:
		var auto_dir := _auto_aim_dir()
		if auto_dir != Vector2.ZERO:
			return auto_dir
	var mouse := _player.get_global_mouse_position() - _player.global_position
	return mouse.normalized() if mouse != Vector2.ZERO else current_aim


## 全向就近索敌（m4p：GDD §5.1 由「朝向 60° 锥」改全向 360°，桌面/触屏同口径）：
## 收集存活敌人 → AutoAim.pick_target 以 360° 全锥取最近者。无目标返回零向量。
## cone_deg 显式传 360——AutoAim 默认 60° 不动（bot lead 路径与 B-3 零漂移钉测同参）。
func _auto_aim_dir() -> Vector2:
	var targets: Array[Vector2] = []
	for node in get_tree().get_nodes_in_group("enemies"):
		if node is Node2D and not bool(node.get("state") == EnemyBase.State.DEAD):
			targets.append((node as Node2D).global_position)
	var idx := AutoAim.pick_target(_player.global_position, current_aim.angle(), targets, 360.0)
	if idx < 0:
		return Vector2.ZERO
	var dir := targets[idx] - _player.global_position
	return dir.normalized() if dir != Vector2.ZERO else Vector2.ZERO
