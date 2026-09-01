class_name GameCamera
extends Camera2D
## 跟随相机 + trauma 震屏 v2（m0-t12 → J2）：位移 = trauma² × 8px × 设置档、
## 旋转 = trauma² × 2° × 设置档（平方曲线，小 trauma 更克制）；FastNoiseLite
## （seed 固定 42）采样，x 轴随时间推进，三通道（x/y/旋转）分离去相关。
## 抖动为纯表现层随机（非逻辑随机，不占 RngSvc 种子流）；噪声/计时成员全部复用，
## _process 热路径零分配。衰减经 Fx.decay_step(delta)（1.6/s × 渲染 delta——表现层
## 计时例外，与 hitstop 真实毫秒同口径；冻结拍树暂停时相机停摆，trauma 不被吃掉）。

const NOISE_SEED := 42            # 规格：噪声 seed 固定 42（确定性可测）
const NOISE_TIME_RATE := 20.0     # 表现层调校：噪声 x 轴推进速率（单位/秒）
const CHANNEL_X := 0.0            # 2D 噪声 y 通道取值分离 x/位移、y/位移、旋转
const CHANNEL_Y := 17.0
const CHANNEL_ROT := 43.0

var target: Node2D
var follow := true
var _noise := FastNoiseLite.new()   # 成员复用：禁每帧 new（热路径零分配）
var _noise_time := 0.0              # 表现层计时：渲染 delta 累积（秒）

func _init() -> void:
	_noise.seed = NOISE_SEED
	_noise.frequency = 1.0

func _ready() -> void:
	make_current()
	position_smoothing_enabled = true
	position_smoothing_speed = 10.0
	ignore_rotation = false   # v2：trauma 旋转抖动需作用于视口

func _process(delta: float) -> void:
	if follow and target != null and is_instance_valid(target):
		global_position = target.global_position
	_noise_time += delta
	var shake_scale := Fx.screen_shake_scale()
	var t := Fx.trauma
	var nx := _noise_time * NOISE_TIME_RATE
	if t > 0.001 and shake_scale > 0.0:
		offset = Vector2(
			_noise.get_noise_2d(nx, CHANNEL_X),
			_noise.get_noise_2d(nx, CHANNEL_Y)) \
			* shake_amplitude(t, shake_scale, Fx.trauma_offset_px())
		rotation = deg_to_rad(_noise.get_noise_2d(nx, CHANNEL_ROT)
			* shake_rotation_deg(t, shake_scale, Fx.trauma_rot_deg()))
	else:
		offset = Vector2.ZERO
		rotation = 0.0
	Fx.decay_step(delta)

## v2 位移幅值上限：trauma² × 8px × 设置档。trauma 在此防御性夹取 [0,1]
##（注入侧 add_trauma 已 clamp，此处兜底损坏值不放大振幅）。
static func shake_amplitude(trauma: float, setting_scale: float, max_offset_px := 8.0) -> float:
	var t := clampf(trauma, 0.0, 1.0)
	return t * t * max_offset_px * clampf(setting_scale, 0.0, 1.0)

## v2 旋转幅值上限：trauma² × 2° × 设置档（同上防御夹取）。
static func shake_rotation_deg(trauma: float, setting_scale: float, max_rot_deg := 2.0) -> float:
	var t := clampf(trauma, 0.0, 1.0)
	return t * t * max_rot_deg * clampf(setting_scale, 0.0, 1.0)
