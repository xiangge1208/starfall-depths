extends EnemyBase
## 弹幕（附录 B 原型「弹幕」）：低速驻守（speed 0 为主），周期 windup 预警 → 齐射 →
## 冷却。齐射形态（行键驱动）：
## - volley_mode "ring"：volley_count 发全向环弹（冰晶法师「冰环弹」/火雨祭司/
##   星髓聚合体）；
## - 默认扇面：volley_count 发以玩家方向为中心、volley_spread_deg 均布扇弹
##   （种子投手/深窟回响者/烈焰巫妖「火墙推进弹」）。
## 增益键：slow_pct/slow_ticks（冰缓，沿用蘑菇孢子手弹契约）；
## element_rotate=true 时元素按 火→冰→电→毒 逐轮轮换（星髓聚合体「随机切换 4 元素」
## 的确定性轮换实现——同 seed 可复现，不引入额外 RNG 流）。

const DEFAULT_VOLLEY_COUNT := 3
const DEFAULT_SPREAD_DEG := 30.0
const ROTATE_ELEMENTS: Array[int] = [
	Elements.Id.FIRE, Elements.Id.ICE, Elements.Id.SHOCK, Elements.Id.POISON,
]

var _phase := "idle"
var _phase_left := 0
var _volley_index := 0

func _engage(_frame: int) -> void:
	var speed := float(row.get("speed", 0))
	if speed > 0.0:
		var to_player := _player_pos() - brain_pos
		if to_player.length_squared() > 0.0001:
			brain_pos += to_player.normalized() * (speed / TimeConst.FPS)
	match _phase:
		"idle":
			_phase = "windup"
			_phase_left = _windup_ticks(30)
			Fx.on_enemy_hit(self, {"telegraph": true})
		"windup":
			_phase_left -= 1
			if _phase_left <= 0:
				_fire_volley()
				_phase = "cool"
				_phase_left = maxi(int(row.get("cd_ticks", 108)) - int(row.get("windup_ticks", 30)), 0)
		"cool":
			_phase_left -= 1
			if _phase_left <= 0:
				_phase = "windup"
				_phase_left = _windup_ticks(30)
				Fx.on_enemy_hit(self, {"telegraph": true})

func _fire_volley() -> void:
	fired_this_tick = true
	if combat == null:
		return
	var count := int(row.get("volley_count", DEFAULT_VOLLEY_COUNT))
	var element := _volley_element()
	var dirs: Array[Vector2] = []
	if String(row.get("volley_mode", "")) == "ring":
		for i in count:
			dirs.append(Vector2.from_angle(TAU * float(i) / float(count)))
	else:
		var base_dir := (_player_pos() - brain_pos).normalized()
		if base_dir == Vector2.ZERO:
			base_dir = Vector2.RIGHT
		var spread := deg_to_rad(float(row.get("volley_spread_deg", DEFAULT_SPREAD_DEG)))
		for i in count:
			var ang := -spread / 2.0 + spread * float(i) / float(maxi(count - 1, 1))
			dirs.append(base_dir.rotated(ang))
	for dir in dirs:
		var cfg := {
			"pos": brain_pos, "vel": dir * float(row.get("bullet_speed", 95.0)),
			"damage": int(row.get("bullet_dmg", 3)), "faction": Projectile.Faction.ENEMY,
			"element": element, "pierce": 0, "bounce": 0,
			"life_seconds": float(row.get("bullet_life_seconds", 2.5)),
			"radius": float(row.get("bullet_radius", 4.0)),
			"source_type": "projectile", "source_id": String(row.get("id", "")),
			"source_name": String(row.get("name", row.get("id", ""))), "attack_name": "弹幕齐射",
		}
		var slow := float(row.get("slow_pct", 0.0))
		if slow > 0.0:
			cfg["slow_pct"] = slow
			cfg["slow_ticks"] = int(row.get("slow_ticks", 60))
		combat.spawn_projectile(cfg)

func _volley_element() -> int:
	if not bool(row.get("element_rotate", false)):
		return Elements.Id.NONE
	var element: int = ROTATE_ELEMENTS[_volley_index % ROTATE_ELEMENTS.size()]
	_volley_index += 1
	return element
