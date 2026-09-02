extends EnemyBase
## 穴蝠：绕玩家 orbit_radius 公转（角速度使线速度 = speed），每 180t 俯冲 60t 扑向玩家。
## m2-t9 键控扩展（既有穴蝠行不带键，行为不变）：
## - 行 bullet_dmg > 0 且 cd_ticks > 0：绕行中周期开火——windup 预警后单发瞄射
##   （B.2 飞行翼蜥「切线俯冲」带弹 / 幽光水母「电弧链射击」/ 熔火飞龙「俯冲喷吐」）；
## - 行 death_burst_count > 0：死亡爆出 N 向晶针（B.2 A2 晶簇蝙蝠）。

const DIVE_EVERY_TICKS := 180
const DIVE_TICKS := 60

var _angle := 0.0
var _dive_left := 0
var _fire_phase := "idle"
var _fire_left := 0

func _engage(frame: int) -> void:
	var speed := float(row.get("speed", 70))
	if _dive_left > 0:
		_dive_left -= 1
		brain_pos = brain_pos.move_toward(_player_pos(), speed / TimeConst.FPS)
		_tick_fire(frame)
		return
	if frame % DIVE_EVERY_TICKS == 0:
		_dive_left = DIVE_TICKS - 1
		_tick_fire(frame)
		return
	var radius := maxf(float(row.get("orbit_radius", 120)), 1.0)
	_angle += speed / radius / TimeConst.FPS          # 线速度 = speed
	var desired := _player_pos() + Vector2.from_angle(_angle) * radius
	brain_pos = brain_pos.move_toward(desired, speed / TimeConst.FPS)
	_tick_fire(frame)

## 周期开火（键控）：windup 预警 → 单发瞄射 → 冷却（整周期 = cd_ticks）。
func _tick_fire(frame: int) -> void:
	if int(row.get("bullet_dmg", 0)) <= 0 or int(row.get("cd_ticks", 0)) <= 0:
		return
	match _fire_phase:
		"idle":
			_fire_phase = "windup"
			_fire_left = _windup_ticks(30)
			telegraph_fx()
		"windup":
			_fire_left -= 1
			if _fire_left <= 0:
				fire_bullet(_player_pos(), frame)
				_fire_phase = "cool"
				_fire_left = _attack_cooldown_ticks(150)
		"cool":
			_fire_left -= 1
			if _fire_left <= 0:
				_fire_phase = "windup"
				_fire_left = _windup_ticks(30)
				telegraph_fx()

## 死亡爆晶针（键控 death_burst_count）：die() 先落弹再走基类退场（单一死亡源不变）。
func die() -> void:
	if state != State.DEAD:
		var burst := int(row.get("death_burst_count", 0))
		if burst > 0 and combat != null:
			for i in burst:
				var dir := Vector2.from_angle(TAU * float(i) / float(burst))
				combat.spawn_projectile({
					"pos": brain_pos, "vel": dir * enemy_bullet_speed(110.0),
					"damage": int(row.get("bullet_dmg", 5)), "faction": Projectile.Faction.ENEMY,
					"element": Elements.Id.NONE, "pierce": 0, "bounce": 0,
					"life_seconds": float(row.get("bullet_life_seconds", 2.0)),
					"radius": float(row.get("bullet_radius", 3.0)),
					"source_type": "projectile", "source_id": String(row.get("id", "")),
					"source_name": String(row.get("name", row.get("id", ""))),
					"attack_name": "晶针爆散",
				})
	super()

