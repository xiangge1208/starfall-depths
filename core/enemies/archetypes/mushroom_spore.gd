extends EnemyBase
## 蘑菇孢子手（附录 B.2）：原地蓄力后向玩家发射 3 发减速孢子。
## 与通用 shooter 分离：不走风筝位移，扇形固定为 -12/0/+12 度；
## 命中减速值由行数据 slow_pct/slow_ticks 进入玩家 take_hit_ctx。

const DEFAULT_WINDUP_TICKS := 30
const DEFAULT_COOLDOWN_TICKS := 108
const SPORE_SPREAD_DEG := 12.0

var _phase := "idle"
var _phase_left := 0


func _engage(frame: int) -> void:
	match _phase:
		"idle":
			_begin_windup()
		"windup":
			_phase_left -= 1
			if _phase_left <= 0:
				_fire_spore_fan(frame)
				_phase = "cool"
				_phase_left = maxi(int(row.get("cd_ticks", DEFAULT_COOLDOWN_TICKS)) \
					- int(row.get("windup_ticks", DEFAULT_WINDUP_TICKS)), 0)
		"cool":
			_phase_left -= 1
			if _phase_left <= 0:
				_begin_windup()


func _begin_windup() -> void:
	_phase = "windup"
	_phase_left = _windup_ticks(DEFAULT_WINDUP_TICKS)
	telegraph_fx()


func _fire_spore_fan(_frame: int) -> void:
	fired_this_tick = true
	if combat == null:
		return
	var base_dir := (_player_pos() - brain_pos).normalized()
	if base_dir == Vector2.ZERO:
		base_dir = Vector2.RIGHT
	for deg in [-SPORE_SPREAD_DEG, 0.0, SPORE_SPREAD_DEG]:
		combat.spawn_projectile({
			"pos": brain_pos,
			"vel": base_dir.rotated(deg_to_rad(deg)) * enemy_bullet_speed(95),
			"damage": int(row.get("bullet_dmg", 3)),
			"faction": Projectile.Faction.ENEMY,
			"element": Elements.Id.NONE,
			"pierce": 0,
			"bounce": 0,
			"life_seconds": float(row.get("bullet_life_seconds", 2.5)),
			"radius": float(row.get("bullet_radius", 4.0)),
			"slow_pct": float(row.get("slow_pct", 0.3)),
			"slow_ticks": int(row.get("slow_ticks", TimeConst.ticks(1.0))),
			"source_type": "projectile",
			"source_id": String(row.get("id", "mushroom_spore")),
			"source_name": String(row.get("name", "蘑菇孢子手")),
			"attack_name": "减速孢子扇",
		})
