extends EnemyBase
## 腐沼巨蟾（小 Boss，附录 B.3「吞弹（吸收玩家弹幕存伤害）后吐还弹幕」）：
## 相位循环 wait（wait_ticks，游走）→ swallow（swallow_ticks，张口吞弹：玩家远程弹
## 被吞不落血、伤害入 _stored；近战/元素状态照常结算）→ windup（30t 预警）→
## spit（吐还 spit_count 发扇面，单发伤 = 存伤均分，无存伤回落行 bullet_dmg）→
## cool（cd_ticks）→ 循环。吞弹判定 = ctx.source_type == "weapon"（玩家枪弹契约）。

const SPIT_SPREAD_DEG := 50.0

var _phase := "idle"
var _phase_left := 0
var _stored := 0            # 吞弹存伤（吐还清零）

func _engage(_frame: int) -> void:
	match _phase:
		"idle":
			_phase = "wait"
			_phase_left = int(row.get("wait_ticks", 60))
		"wait":
			_walk_to_player()
			_phase_left -= 1
			if _phase_left <= 0:
				_phase = "swallow"
				_phase_left = int(row.get("swallow_ticks", 120))
				Fx.on_enemy_hit(self, {"telegraph": true})   # 张口预警
		"swallow":
			_phase_left -= 1   # 张口定身（挪步停住，靶子换打法）
			if _phase_left <= 0:
				_phase = "windup"
				_phase_left = _windup_ticks(30)
				Fx.on_enemy_hit(self, {"telegraph": true})
		"windup":
			_phase_left -= 1
			if _phase_left <= 0:
				_spit_back()
				_phase = "cool"
				_phase_left = maxi(int(row.get("cd_ticks", 90)) - int(row.get("windup_ticks", 30)), 0)
		"cool":
			_walk_to_player()
			_phase_left -= 1
			if _phase_left <= 0:
				_phase = "idle"

func _walk_to_player() -> void:
	var to_player := _player_pos() - brain_pos
	if to_player.length_squared() > 0.0001:
		brain_pos += to_player.normalized() * (float(row.get("speed", 50)) / TimeConst.FPS)

## 吞弹：swallow 相内玩家远程弹（source_type=="weapon"）整发入腹——不落血、不走
## 受击管线（无暴击/状态/遥测，弹被吃掉）；其余伤害源（近战/状态/环境）照常结算。
func take_hit(ctx: Dictionary) -> void:
	if state != State.DEAD and _phase == "swallow" \
			and String(ctx.get("source_type", "")) == "weapon":
		_stored += maxi(int(ctx.get("amount", 0)), 0)
		return
	super(ctx)

## 吐还：spit_count 发扇面；单发伤 = round(存伤/发数)（至少 1），无存伤用行 bullet_dmg。
func _spit_back() -> void:
	fired_this_tick = true
	if combat == null:
		_stored = 0
		return
	var count := int(row.get("spit_count", 5))
	var per := int(round(float(_stored) / float(count))) if _stored > 0 \
		else int(row.get("bullet_dmg", 4))
	per = maxi(per, 1)
	var base_dir := (_player_pos() - brain_pos).normalized()
	if base_dir == Vector2.ZERO:
		base_dir = Vector2.RIGHT
	var spread := deg_to_rad(SPIT_SPREAD_DEG)
	for i in count:
		var ang := -spread / 2.0 + spread * float(i) / float(maxi(count - 1, 1))
		combat.spawn_projectile({
			"pos": brain_pos, "vel": base_dir.rotated(ang) * float(row.get("bullet_speed", 110.0)),
			"damage": per, "faction": Projectile.Faction.ENEMY,
			"element": Elements.Id.NONE, "pierce": 0, "bounce": 0,
			"life_seconds": float(row.get("bullet_life_seconds", 2.5)),
			"radius": float(row.get("bullet_radius", 4.0)),
			"source_type": "projectile", "source_id": String(row.get("id", "")),
			"source_name": String(row.get("name", row.get("id", ""))), "attack_name": "吐还弹幕",
		})
	_stored = 0
