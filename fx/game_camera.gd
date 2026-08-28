class_name GameCamera
extends Camera2D
## 跟随相机 + 震屏（m0-t12）：每渲染帧按 Fx.trauma 加随机偏移并调 Fx.decay_step()。
## 抖动为纯表现层随机（非逻辑随机，不占 RngSvc 种子流）。

const MAX_OFFSET_PX := 4.0             # trauma=2（受击）时 ≈8px 抖动

var target: Node2D
var follow := true

func _ready() -> void:
	make_current()
	position_smoothing_enabled = true
	position_smoothing_speed = 10.0

func _process(_delta: float) -> void:
	if follow and target != null and is_instance_valid(target):
		global_position = target.global_position
	if Fx.trauma > 0.001:
		offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * Fx.trauma * MAX_OFFSET_PX
	else:
		offset = Vector2.ZERO
	Fx.decay_step()
