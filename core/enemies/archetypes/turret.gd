extends EnemyBase
## 炮台（附录 B 原型「炮台」）：固定不动（speed 0），周期 windup 预警 → 发射 → 冷却。
## 两种发射形态（行键驱动）：
## - burst_count > 1：连发（荆棘炮台「抛物 3 连发」；岩晶炮台蓄能单发 burst_count=1）
##   ——windup 结束拍即发第 1 发，此后每 burst_interval_ticks 一发、逐发瞄向玩家；
## - fan_count > 1：扇形喷发（岩浆喷吐炮台「扇形 5 喷发」）——一次性 fan_spread_deg
##   均布扇面。
## 契约：任何形态首发前都有 windup（≥24t）蓄力预警。

const DEFAULT_BURST_INTERVAL := 6

var _phase := "idle"
var _phase_left := 0
var _burst_left := 0
var _burst_wait := 0

func _engage(frame: int) -> void:
	match _phase:
		"idle":
			_phase = "windup"
			_phase_left = _windup_ticks(30)
			Fx.on_enemy_hit(self, {"telegraph": true})
		"windup":
			_phase_left -= 1
			if _phase_left <= 0:
				_begin_volley(frame)
		"burst":
			if _burst_wait > 0:
				_burst_wait -= 1
			else:
				fire_bullet(_player_pos(), frame)
				_burst_left -= 1
				_burst_wait = _burst_gap()
				if _burst_left <= 0:
					_begin_cool()
		"cool":
			_phase_left -= 1
			if _phase_left <= 0:
				_phase = "windup"
				_phase_left = _windup_ticks(30)
				Fx.on_enemy_hit(self, {"telegraph": true})

## windup 结束拍：扇形一次性齐射；连发先落第 1 发（间隔从下一拍起算）。
## m2-t7：行键 laser=true → 激光形态（A2 岩晶炮台）：改发 EnemyLaser（直线激光束，
## 命中晶柱 45° 折射一次，见 core/enemies/enemy_laser.gd），随后照常进冷却。
func _begin_volley(frame: int) -> void:
	if bool(row.get("laser", false)):
		_fire_laser()
		_begin_cool()
		return
	var fan := int(row.get("fan_count", 0))
	if fan > 1:
		_fire_fan(fan)
		_begin_cool()
		return
	_burst_left = int(row.get("burst_count", 1))
	fire_bullet(_player_pos(), frame)            # 首发：windup 到点拍即出
	_burst_left -= 1
	_burst_wait = _burst_gap()
	if _burst_left <= 0:
		_begin_cool()
	else:
		_phase = "burst"

func _burst_gap() -> int:
	return maxi(int(row.get("burst_interval_ticks", DEFAULT_BURST_INTERVAL)) - 1, 0)


## m2-t7 激光形态发射：EnemyLaser 挂自身（炮台死亡束随体消亡）；晶柱折射源 =
## 场景 refraction_pillars 组（FloorScene 建柱时登记，世界坐标）；bound = 房间
## 可玩内域（combat_bounds，脑层测试空矩形 = 无界）。参数复用行内 bullet_* 键。
func _fire_laser() -> void:
	fired_this_tick = true
	var d := (_player_pos() - brain_pos).normalized()
	if d == Vector2.ZERO:
		d = Vector2.RIGHT
	var pillars: Array[Vector2] = []
	if is_inside_tree():
		for node in get_tree().get_nodes_in_group(EnemyLaser.PILLAR_GROUP):
			var p := node as Node2D
			if p != null and is_instance_valid(p):
				pillars.append(p.global_position)
	var laser := EnemyLaser.new()
	laser.name = "EnemyLaser"
	add_child(laser)
	laser.setup({
		"pos": brain_pos, "dir": d,
		"speed_px": enemy_bullet_speed(EnemyLaser.DEFAULT_SPEED_PX),
		"damage": int(row.get("bullet_dmg", 5)),
		"life_ticks": TimeConst.ticks(float(row.get("bullet_life_seconds", 2.0))),
		"pillars": pillars, "bounds": combat_bounds, "player": player_ref,
		"source_id": String(row.get("id", "")),
		"source_name": String(row.get("name", row.get("id", ""))),
		"attack_name": "晶棱激光",
	})
	AudioMgr.play("shoot_enemy")

func _begin_cool() -> void:
	_phase = "cool"
	_phase_left = _attack_cooldown_ticks(150)

func _fire_fan(fan: int) -> void:
	fired_this_tick = true
	if combat == null:
		return
	var base_dir := (_player_pos() - brain_pos).normalized()
	if base_dir == Vector2.ZERO:
		base_dir = Vector2.RIGHT
	var spread := deg_to_rad(float(row.get("fan_spread_deg", 40.0)))
	for i in fan:
		var ang := -spread / 2.0 + spread * float(i) / float(maxi(fan - 1, 1))
		combat.spawn_projectile({
			"pos": brain_pos, "vel": base_dir.rotated(ang) * enemy_bullet_speed(95.0),
			"damage": int(row.get("bullet_dmg", 4)), "faction": Projectile.Faction.ENEMY,
			"element": Elements.Id.NONE, "pierce": 0, "bounce": 0,
			"life_seconds": float(row.get("bullet_life_seconds", 2.0)),
			"radius": float(row.get("bullet_radius", 4.0)),
			"source_type": "projectile", "source_id": String(row.get("id", "")),
			"source_name": String(row.get("name", row.get("id", ""))), "attack_name": "扇形喷发",
		})
