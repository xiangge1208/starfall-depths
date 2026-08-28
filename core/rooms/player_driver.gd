extends Node
## 玩家输入驱动（m0-t12 房间接线）：开火（含近战挥击）/ 切枪。挂在 Player 下由房间装配。
## 开火成功缝埋点 fire 遥测。瞄准取鼠标（世界坐标）。

var _player: Player
var _rig: WeaponRig
var _melee: Melee

func _ready() -> void:
	_player = get_parent() as Player
	_rig = _player.get_node("WeaponRig") as WeaponRig
	_melee = _player.get_node("Melee") as Melee

func _physics_process(_delta: float) -> void:
	if _player == null or _rig == null or _melee == null:
		return
	var frame := Engine.get_physics_frames()
	if Input.is_action_pressed("fire"):
		var aim := _player.get_global_mouse_position() - _player.global_position
		if aim == Vector2.ZERO:
			aim = _player.facing
		var w := _rig.current()
		if not w.is_empty() and bool(w.get("is_melee", false)):
			if _melee.try_attack(frame):
				Telemetry.log_row(["fire", frame, String(w.get("id", ""))])
		elif _rig.try_fire(aim.normalized(), frame):
			Telemetry.log_row(["fire", frame, String(_rig.current().get("id", ""))])
	if Input.is_action_just_pressed("switch_weapon"):
		_rig.switch_slot(frame)
