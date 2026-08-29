extends Node
## 手柄右摇杆瞄准（m1-t21，GDD §5.1「右摇杆推即射」）。
##
## 实现方式（合成输入，disclosed approach）：本节点每个物理帧读右摇杆轴
## （经 _input 事件跟踪 InputEventJoypadMotion 的轴 2/3 符号值），模长超过
## 死区阈值 0.5 时用 Input.action_press("fire") 合成开火输入并暴露 aim_vector；
## 回中时 action_release。player.gd / weapon_rig.gd 零改动（桌面行为完全不变）。
##
## 接线：在玩家场景挂本节点即可；开火方向消费 aim_vector 属 T23/整合层
## （与 auto_aim.gd 的调用点约定一致）。节点移出树时自动松开 fire，防卡键。

const DEAD_ZONE := 0.5

## 最近一次右摇杆瞄准方向（单位向量；无输入时 Vector2.ZERO）
var aim_vector := Vector2.ZERO

var _axis := Vector2.ZERO   # 右摇杆原始轴值（x=轴2, y=轴3），事件驱动更新
var _firing := false

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadMotion:
		var jm := event as InputEventJoypadMotion
		match jm.axis:
			JOY_AXIS_RIGHT_X:
				_axis.x = jm.axis_value
			JOY_AXIS_RIGHT_Y:
				_axis.y = jm.axis_value

func _physics_process(_delta: float) -> void:
	_apply_axes(_axis.x, _axis.y)

func _exit_tree() -> void:
	if _firing:
		Input.action_release("fire")
		_firing = false

## 每物理帧的推进步：轴值 → 阈值判定 → 合成 fire。测试可直接调用（不经物理帧）。
func _apply_axes(x: float, y: float) -> Vector2:
	aim_vector = stick_output(x, y, DEAD_ZONE)
	if aim_vector != Vector2.ZERO:
		if not _firing:
			Input.action_press("fire")
			_firing = true
	elif _firing:
		Input.action_release("fire")
		_firing = false
	return aim_vector

## 纯函数：摇杆原始轴值 → 瞄准方向。模长 ≤ dead 返回 ZERO，否则单位向量。
static func stick_output(x: float, y: float, dead := 0.5) -> Vector2:
	var v := Vector2(x, y)
	return v.normalized() if v.length() > dead else Vector2.ZERO
