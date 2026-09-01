class_name ComboCounter
extends RefCounted
## J5 连击计数（Juice v2 §2）：纯逻辑、无树依赖、零分配。连击窗口（默认 1.2s）内
## 连续命中累计 combo；命中音 pitch = 1.0 + 0.02 × min(combo, 封顶档数)。
## 窗口过期惰性判断：事件携带时间戳，命中时判过期清零——无逐帧 tick（60Hz 逻辑帧
## 零占用）。时间口径为真实毫秒（表现层计时例外，与 hitstop 同口径，判定无关）。
## 窗口/步长/封顶由构造参数注入（测试注入合成时间；生产由 Fx 读 balance.json juice 节）。

var window_ms: int
var pitch_step: float
var pitch_max_steps: int

var _combo := 0
var _last_hit_ms := -(1 << 30)   # 远古值：首次命中必视为窗内

func _init(p_window_ms: int = 1200, p_pitch_step: float = 0.02, p_pitch_max_steps: int = 6) -> void:
	window_ms = p_window_ms
	pitch_step = p_pitch_step
	pitch_max_steps = p_pitch_max_steps

## 命中上报：窗内（含恰在窗边界）累加；窗外先惰性清零再从 1 计（「脱战 1.2s」重置）。
func on_hit(t_ms: int) -> void:
	if _combo > 0 and t_ms - _last_hit_ms > window_ms:
		_combo = 0
	_combo += 1
	_last_hit_ms = t_ms

## 受击重置（生产经 EventBus.player_damaged → Fx 转发）。
func on_player_hurt(_t_ms: int) -> void:
	reset()

## 换武器重置（生产经 WeaponRig.switch_slot → Fx 转发）。
func on_weapon_switch(_t_ms: int) -> void:
	reset()

func reset() -> void:
	_combo = 0
	_last_hit_ms = -(1 << 30)

func combo() -> int:
	return _combo

## 命中音音高查询：反映最近一次事件后的连击档位（消费点总在 on_hit 之后，无需时间参）。
func pitch() -> float:
	return 1.0 + pitch_step * float(mini(_combo, pitch_max_steps))
