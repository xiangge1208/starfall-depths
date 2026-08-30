extends EnemyBase
## 藤蔓冲锋者：ENGAGE 后 windup 30t 蓄力（原地红闪）→ dash 27t 直冲锁定方向 → 冷却 90t。
## 与简报参考实现的唯一差异：_phase 初值取 "idle"（简报笔误为 "windup"，会使首测冲刺窗口错位），
## 以及 player_ref 为空时退化为默认冲刺方向——测试用注入帧、不注入玩家。
## m2-t9 键控扩展：行 self_stun_ticks > 0 时冲刺结束自晕该拍数（B.2 A2 晶背龙蜥
## 「冲撞撞墙后自晕 1s（输出窗）」）；既有行不带该键，行为不变。

var _phase := "idle"
var _phase_left := 0
var _dash_dir := Vector2.ZERO

func _engage(frame: int) -> void:
	match _phase:
		"idle":
			_phase = "windup"
			_phase_left = _windup_ticks(int(row["windup_ticks"]))   # m1-t12：狂暴激活时 ×0.7
			_dash_dir = Vector2.RIGHT if player_ref == null else (player_ref.brain_pos - brain_pos).normalized()
			Fx.on_enemy_hit(self, {"telegraph": true})
		"windup":
			_phase_left -= 1
			if _phase_left <= 0:
				_phase = "dash"
				_phase_left = int(row["dash_ticks"])
		"dash":
			brain_pos += _dash_dir * (float(row["dash_speed"]) / TimeConst.FPS)
			_phase_left -= 1
			if _phase_left <= 0:
				_self_stun_after_dash(frame)
				_phase = "cool"
				_phase_left = int(row["dash_cooldown_ticks"])
		"cool":
			_phase_left -= 1
			if _phase_left <= 0:
				_phase = "idle"

func _self_stun_after_dash(frame: int) -> void:
	var stun := int(row.get("self_stun_ticks", 0))
	if stun > 0:
		stun_until = maxi(stun_until, frame + stun)

