extends Node
## 手柄右摇杆瞄准（m1-t21，GDD §5.1「右摇杆推即射」）。
##
## 本节点经 InputMap 的 aim_right_x / aim_right_y 动作跟踪所映射轴，每个物理帧
## 读取动作轴值；不依赖固定轴号，因此运行时重映射后新轴生效、旧轴失效。模长超过
## 死区阈值 0.5 时暴露 aim_vector。开火由 PlayerDriver 读取该显式向量；
## 不再改写全局 fire，避免与触屏右杆或鼠标来源相互释放。
##
## 接线：在玩家场景挂本节点即可；开火方向消费 aim_vector 属 T23/整合层
## （与 auto_aim.gd 的调用点约定一致）。

const DEAD_ZONE := 0.5
const AIM_RIGHT_X := &"aim_right_x"
const AIM_RIGHT_Y := &"aim_right_y"

## 最近一次右摇杆瞄准方向（单位向量；无输入时 Vector2.ZERO）
var aim_vector := Vector2.ZERO

var _axis_values: Dictionary = {}   # 已观察到的物理轴值；动作映射每拍动态解析

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		_axis_values[motion.axis] = motion.axis_value

func _physics_process(_delta: float) -> void:
	var axes := _read_aim_actions()
	_apply_axes(axes.x, axes.y)

## 暴露生产读取接缝供重映射测试；每次都重新解析当前 InputMap，故动作改绑后
## 旧轴即使仍有缓存值也不再参与，新轴收到事件后立即生效。
func _read_aim_actions() -> Vector2:
	return Vector2(_read_action_axis(AIM_RIGHT_X), _read_action_axis(AIM_RIGHT_Y))

func _read_action_axis(action: StringName) -> float:
	var strongest := 0.0
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventJoypadMotion:
			var value := float(_axis_values.get((event as InputEventJoypadMotion).axis, 0.0))
			if absf(value) > absf(strongest):
				strongest = value
	return strongest

## 每物理帧的推进步：轴值 → 阈值判定。测试可直接调用（不经物理帧）。
func _apply_axes(x: float, y: float) -> Vector2:
	aim_vector = stick_output(x, y, DEAD_ZONE)
	return aim_vector

## 纯函数：摇杆原始轴值 → 瞄准方向。模长 ≤ dead 返回 ZERO，否则单位向量。
static func stick_output(x: float, y: float, dead := 0.5) -> Vector2:
	var v := Vector2(x, y)
	return v.normalized() if v.length() > dead else Vector2.ZERO
