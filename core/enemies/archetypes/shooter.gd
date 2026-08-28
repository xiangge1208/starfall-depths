extends EnemyBase
## 弩兵：保持 140~200px 距离游走；每 cd_ticks 一轮——windup_ticks 预警后 fire_bullet。
## 整周期 = cd_ticks（含 windup），故两次射击间隔恰为 1.8s。

const KITE_MIN_PX := 140.0
const KITE_MAX_PX := 200.0

var _phase := "idle"
var _phase_left := 0

func _engage(frame: int) -> void:
	_kite_move(frame)
	match _phase:
		"idle":
			_phase = "windup"
			_phase_left = int(row.get("windup_ticks", 30))
		"windup":
			_phase_left -= 1
			if _phase_left <= 0:
				fire_bullet(_player_pos(), frame)
				_phase = "cool"
				_phase_left = maxi(int(row.get("cd_ticks", 108)) - int(row.get("windup_ticks", 30)), 0)
		"cool":
			_phase_left -= 1
			if _phase_left <= 0:
				_phase = "windup"
				_phase_left = int(row.get("windup_ticks", 30))

## 走位：太近后撤、太远贴近、距离区间内垂直于视线方向横移（每秒换向）。
func _kite_move(frame: int) -> void:
	var to_player := _player_pos() - brain_pos
	var dist := to_player.length()
	var step := Vector2.ZERO
	if dist < KITE_MIN_PX:
		step = -to_player.normalized()
	elif dist > KITE_MAX_PX:
		step = to_player.normalized()
	else:
		var side := 1.0 if (frame / 60) % 2 == 0 else -1.0
		step = to_player.orthogonal().normalized() * side
	brain_pos += step * (float(row.get("speed", 60)) / TimeConst.FPS)
