extends EnemyBase
## 穴蝠：绕玩家 orbit_radius 公转（角速度使线速度 = speed），每 180t 俯冲 60t 扑向玩家。

const DIVE_EVERY_TICKS := 180
const DIVE_TICKS := 60

var _angle := 0.0
var _dive_left := 0

func _engage(frame: int) -> void:
	var speed := float(row.get("speed", 70))
	if _dive_left > 0:
		_dive_left -= 1
		brain_pos = brain_pos.move_toward(_player_pos(), speed / TimeConst.FPS)
		return
	if frame % DIVE_EVERY_TICKS == 0:
		_dive_left = DIVE_TICKS - 1
		return
	var radius := maxf(float(row.get("orbit_radius", 120)), 1.0)
	_angle += speed / radius / TimeConst.FPS          # 线速度 = speed
	var desired := _player_pos() + Vector2.from_angle(_angle) * radius
	brain_pos = brain_pos.move_toward(desired, speed / TimeConst.FPS)
