extends EnemyBase
## 弩兵：保持 140~200px 距离游走；每 cd_ticks 一轮——windup_ticks 预警后 fire_bullet。
## 整周期 = cd_ticks（含 windup），故两次射击间隔恰为 1.8s。

const KITE_MIN_PX := 140.0
const KITE_MAX_PX := 200.0
const VOLLEY_SPREAD_DEG := 8.0   # m1-t12 弹幕大师：extra 发每级 ±8° 对称展开

var _phase := "idle"
var _phase_left := 0

func _engage(frame: int) -> void:
	_kite_move(frame)
	match _phase:
		"idle":
			_phase = "windup"
			_phase_left = _windup_ticks(30)              # m1-t12：狂暴激活时 ×0.7
			Fx.on_enemy_hit(self, {"telegraph": true})   # t10 定影：windup 进入拍预警（镜像 charger）
		"windup":
			_phase_left -= 1
			if _phase_left <= 0:
				_fire_volley(frame)
				_phase = "cool"
				_phase_left = maxi(int(row.get("cd_ticks", 108)) - int(row.get("windup_ticks", 30)), 0)
		"cool":
			_phase_left -= 1
			if _phase_left <= 0:
				_phase = "windup"
				_phase_left = _windup_ticks(30)          # 同上：狂暴激活时 ×0.7
				Fx.on_enemy_hit(self, {"telegraph": true})   # 同上：cool→windup 亦为 windup 进入拍

## m1-t12 弹幕大师：每轮 volley = 1 + barrage_extra 发——首发瞄向玩家，extra 发
## 沿瞄准方向交替左右展开（±8°，每侧逐级加倍偏角）。节拍不变（fired_this_tick 单拍一轮语义不变）。
func _fire_volley(frame: int) -> void:
	var extra := maxi(int(barrage_extra), 0)
	if extra <= 0:
		fire_bullet(_player_pos(), frame)
		return
	var target := _player_pos()
	var base_dir := (target - brain_pos).normalized()
	var spread := deg_to_rad(VOLLEY_SPREAD_DEG)
	var angles := PackedFloat32Array([0.0])   # 首发居中
	for i in range(1, extra + 1):              # extra 发：+s/-s/+2s/-2s… 交替展开
		var mag := ceilf(float(i) / 2.0)
		var side := 1.0 if i % 2 == 1 else -1.0
		angles.append(spread * mag * side)
	for a in angles:
		fire_bullet(brain_pos + base_dir.rotated(a) * 100.0, frame)

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
