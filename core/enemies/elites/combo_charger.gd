extends EnemyBase
## 双刀蜥人（小 Boss，附录 B.3「三连冲锋斩，第三段有 0.6s 大前摇（最大输出窗）」）：
## windup(行) → dash → 36t 停顿 → dash → 60t 停顿 → 36t 大前摇 → dash → cool(行) 循环。
## dash 参数取行 walk/dash 字段（dash_speed × dash_ticks）；每次蓄力进入拍锁定冲刺方向并预警。
## 帧参数与 charger.gd 同约定：换相拍不减计数、不位移，移动整窗从下一拍起算（可注入帧测试）。

const PAUSE1_TICKS := 36      # 一段后停顿
const PAUSE2_TICKS := 60      # 二段后停顿（接大前摇）
const BIG_WINDUP_TICKS := 36  # 第三段 0.6s 大前摇 = 最大输出窗

var _phase := "idle"
var _phase_left := 0
var _dash_dir := Vector2.ZERO
var _combo_done := 0          # 已完成段数（1..3）

func _engage(_frame: int) -> void:
	match _phase:
		"idle":
			_start_windup("windup", int(row["windup_ticks"]))
		"windup":
			_tick_phase("dash")
		"pause1":
			_tick_phase("dash")
		"pause2":
			_tick_phase("big_windup")
		"big_windup":
			_tick_phase("dash")
		"dash":
			brain_pos += _dash_dir * (float(row["dash_speed"]) / TimeConst.FPS)
			_phase_left -= 1
			if _phase_left <= 0:
				_after_dash()
		"cool":
			_phase_left -= 1
			if _phase_left <= 0:
				_phase = "idle"
				_combo_done = 0

## 蓄力进入拍：锁定方向 + 预警；第三段（big_windup）即 0.6s 最大输出窗。
## 方向退化规则：玩家位与自身重合时保持上一次锁定方向（零向量冲刺无效）；
## 无玩家替身且尚无方向时退化为 RIGHT（镜像 charger 缺省）。
func _start_windup(phase: String, ticks: int) -> void:
	_phase = phase
	_phase_left = ticks
	var to_player := Vector2.ZERO
	if player_ref != null:
		to_player = player_ref.brain_pos - brain_pos
	if to_player.length_squared() > 0.0001:
		_dash_dir = to_player.normalized()
	elif _dash_dir == Vector2.ZERO:
		_dash_dir = Vector2.RIGHT
	Fx.on_enemy_hit(self, {"telegraph": true})

## 停顿/前摇倒数；到点切下一相（dash 直接起跑，前摇再蓄力）。
func _tick_phase(next: String) -> void:
	_phase_left -= 1
	if _phase_left <= 0:
		if next == "dash":
			_begin_dash()
		else:
			_start_windup("big_windup", BIG_WINDUP_TICKS)

func _begin_dash() -> void:
	_phase = "dash"
	_phase_left = int(row["dash_ticks"])

## 一段→36t 停顿；二段→60t 停顿；三段→冷却后回 idle 重新起手。
func _after_dash() -> void:
	_combo_done += 1
	match _combo_done:
		1:
			_phase = "pause1"
			_phase_left = PAUSE1_TICKS
		2:
			_phase = "pause2"
			_phase_left = PAUSE2_TICKS
		_:
			_phase = "cool"
			_phase_left = int(row.get("dash_cooldown_ticks", 90))
