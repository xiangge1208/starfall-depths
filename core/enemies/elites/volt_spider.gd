extends "res://core/enemies/archetypes/summoner.gd"
## 电磁蛛（小 Boss，附录 B.3「电弧链场，杀死小蛛可断链」）：
## 继承召唤（转换拍召 summon_count 只冰蛛、每 summon_interval_ticks 补召、
## 存活 ≤ summon_cap），叠加电弧链——周期 windup 预警后放出一发 SHOCK 电弧弹；
## 链需小蛛导电：_prune_tracked 后存活数为 0 则不放（断链），冷却后下窗再试。
## 「杀死小蛛可断链」= 清小蛛即可关掉它的远程输出，逼玩家做目标取舍。

var _chain_phase := "idle"
var _chain_left := 0

func _engage(frame: int) -> void:
	super(frame)   # 召唤节拍 + 走位（summoner）
	if state == State.DEAD:
		return
	match _chain_phase:
		"idle":
			_chain_phase = "windup"
			_chain_left = _windup_ticks(30)
			Fx.on_enemy_hit(self, {"telegraph": true})
		"windup":
			_chain_left -= 1
			if _chain_left <= 0:
				_prune_tracked()   # 先清已灭小蛛（引用悬置不计存活）
				if not _summoned.is_empty():
					_zap_at_player()
				_chain_phase = "cool"
				_chain_left = maxi(int(row.get("chain_cd_ticks", 150)) \
					- int(row.get("windup_ticks", 30)), 0)
		"cool":
			_chain_left -= 1
			if _chain_left <= 0:
				_chain_phase = "windup"
				_chain_left = _windup_ticks(30)
				Fx.on_enemy_hit(self, {"telegraph": true})

## 电弧弹（SHOCK）：命中玩家侧由元素状态机把感电/麻痹接进来；小蛛全灭时本函数不可达。
func _zap_at_player() -> void:
	fired_this_tick = true
	if combat == null:
		return
	var dir := (_player_pos() - brain_pos).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	combat.spawn_projectile({
		"pos": brain_pos, "vel": dir * enemy_bullet_speed(110.0),
		"damage": int(row.get("bullet_dmg", 5)), "faction": Projectile.Faction.ENEMY,
		"element": Elements.Id.SHOCK, "pierce": 0, "bounce": 0,
		"life_seconds": float(row.get("bullet_life_seconds", 2.0)),
		"radius": float(row.get("bullet_radius", 3.0)),
		"source_type": "projectile", "source_id": String(row.get("id", "")),
		"source_name": String(row.get("name", row.get("id", ""))), "attack_name": "电弧链",
	})
