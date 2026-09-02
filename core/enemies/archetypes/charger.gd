extends EnemyBase
## 藤蔓冲锋者：ENGAGE 后 windup 30t 蓄力（原地红闪）→ dash 27t 直冲锁定方向 → 冷却 90t。
## 与简报参考实现的唯一差异：_phase 初值取 "idle"（简报笔误为 "windup"，会使首测冲刺窗口错位），
## 以及 player_ref 为空时退化为默认冲刺方向——测试用注入帧、不注入玩家。
## m2-t9 键控扩展：行 self_stun_ticks > 0 时冲刺结束自晕该拍数（B.2 A2 晶背龙蜥
## 「冲撞撞墙后自晕 1s（输出窗）」）；既有行不带该键，行为不变。
## m4-c1 派味特技（行键门控，无键行逐行为零变化）——两段扑咬（熔岩犬，bite_stages>1）：
## 第一段冲刺结束 → bite_gap_ticks 短蓄（红闪+重瞄）→ 第二段冲刺 → 冷却。扑咬接触伤
## 经 _contact_element 附 bite_element 元素归因（「附带燃烧」= FIRE，同既有元素归因
## 语义；无敌帧节流不变）。第二段起冲拍上报遥测一次。

var _phase := "idle"
var _phase_left := 0
var _dash_dir := Vector2.ZERO
var _bite_stage := 0          # m4-c1：本轮已冲段数（1=第一段在途/已落，2=第二段…）


func _engage(frame: int) -> void:
	match _phase:
		"idle":
			_phase = "windup"
			_phase_left = _windup_ticks(int(row["windup_ticks"]))   # m1-t12：狂暴激活时 ×0.7
			_dash_dir = Vector2.RIGHT if player_ref == null else (player_ref.brain_pos - brain_pos).normalized()
			_bite_stage = 0
			Fx.on_enemy_hit(self, {"telegraph": true})
		"windup":
			_phase_left -= 1
			if _phase_left <= 0:
				_begin_dash(frame)
		"dash":
			brain_pos += _dash_dir * (float(row["dash_speed"]) / TimeConst.FPS)
			_phase_left -= 1
			if _phase_left <= 0:
				_after_dash(frame)
		"bite_windup":                       # m4-c1：两段扑咬的段间短蓄（重瞄）
			_phase_left -= 1
			if _phase_left <= 0:
				_dash_dir = Vector2.RIGHT if player_ref == null \
					else (player_ref.brain_pos - brain_pos).normalized()
				_begin_dash(frame)
		"cool":
			_phase_left -= 1
			if _phase_left <= 0:
				_phase = "idle"


func _begin_dash(frame: int) -> void:
	_phase = "dash"
	_phase_left = int(row["dash_ticks"])
	_bite_stage += 1
	if _bite_stage == 2:
		Telemetry.log_row(["enemy_double_bite", frame], String(row.get("id", "")))


## 段末分派：带 bite_stages>1 且未打完段数 → 段间短蓄再冲；否则既有自晕/冷却语义不变。
func _after_dash(frame: int) -> void:
	var stages := int(row.get("bite_stages", 1))
	if stages > 1 and _bite_stage < stages:
		_phase = "bite_windup"
		_phase_left = maxi(int(row.get("bite_gap_ticks", 18)), 1)
		Fx.on_enemy_hit(self, {"telegraph": true})
		return
	_bite_stage = 0
	_self_stun_after_dash(frame)
	_phase = "cool"
	_phase_left = int(row["dash_cooldown_ticks"])


func _self_stun_after_dash(frame: int) -> void:
	var stun := int(row.get("self_stun_ticks", 0))
	if stun > 0:
		stun_until = maxi(stun_until, frame + stun)


## m4-c1：扑咬接触伤元素归因（「附带燃烧」）——行 bite_element 命名元素。
func _contact_element() -> int:
	return Elements.from_name(String(row.get("bite_element", "")))
