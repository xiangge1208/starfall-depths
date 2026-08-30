extends EnemyBase
## 重装（附录 B 原型「重装」）：缓慢逼近玩家，正面扇区（朝向 ±90°）减伤
## front_block_pct（硬壳龟 0.8 / 黑曜卫 0.8 / 磁石傀儡·冻土巨蟹 0.6 / 老树守卫 0.5）；
## 背面/侧面全伤（「侧面可击」）。带弹行（老树守卫 弹4）每 cd_ticks 蓄力 windup 后
## 释放根部弹环（volley_count 均布）。
## 面向 = 逼近方向（每拍刷新）；受击方向取 ctx["from"]（来弹位）。

const DEFAULT_VOLLEY_COUNT := 8
const RING_SPEED_DEFAULT := 95.0

var _facing := Vector2.RIGHT
var _phase := "idle"
var _phase_left := 0

func _engage(frame: int) -> void:
	var to_player := _player_pos() - brain_pos
	if to_player.length_squared() > 0.0001:
		_facing = to_player.normalized()
		brain_pos += _facing * (float(row.get("speed", 30)) / TimeConst.FPS)
	if int(row.get("bullet_dmg", 0)) <= 0:
		return                                   # 纯贴近型重装（硬壳龟等）无弹环
	match _phase:
		"idle":
			_phase = "windup"
			_phase_left = _windup_ticks(30)
			Fx.on_enemy_hit(self, {"telegraph": true})
		"windup":
			_phase_left -= 1
			if _phase_left <= 0:
				_fire_root_ring(frame)
				_phase = "cool"
				_phase_left = maxi(int(row.get("cd_ticks", 180)) - int(row.get("windup_ticks", 30)), 0)
		"cool":
			_phase_left -= 1
			if _phase_left <= 0:
				_phase = "windup"
				_phase_left = _windup_ticks(30)
				Fx.on_enemy_hit(self, {"telegraph": true})

## 根部弹环（B.2 A1 老树守卫「根部弹环」）：以自身为中心 volley_count 发均布环弹。
func _fire_root_ring(_frame: int) -> void:
	fired_this_tick = true
	if combat == null:
		return
	var count := int(row.get("volley_count", DEFAULT_VOLLEY_COUNT))
	for i in count:
		var dir := Vector2.from_angle(TAU * float(i) / float(count))
		combat.spawn_projectile({
			"pos": brain_pos, "vel": dir * float(row.get("bullet_speed", RING_SPEED_DEFAULT)),
			"damage": int(row.get("bullet_dmg", 4)), "faction": Projectile.Faction.ENEMY,
			"element": Elements.Id.NONE, "pierce": 0, "bounce": 0,
			"life_seconds": float(row.get("bullet_life_seconds", 2.5)),
			"radius": float(row.get("bullet_radius", 4.0)),
			"source_type": "projectile", "source_id": String(row.get("id", "")),
			"source_name": String(row.get("name", row.get("id", ""))), "attack_name": "根部弹环",
		})

## 正面减伤：来弹方向与面向同侧（点积 > 0）时按 front_block_pct 削减；其余全伤。
func take_hit(ctx: Dictionary) -> void:
	if state == State.DEAD:
		return
	var block := _effective_block_pct(int(ctx.get("frame", Engine.get_physics_frames())))
	if block > 0.0:
		var from: Vector2 = ctx.get("from", brain_pos)
		var incoming := from - brain_pos
		if incoming.length_squared() > 0.0001 and _facing.dot(incoming.normalized()) > 0.0:
			var reduced := ctx.duplicate()
			# round 而非 floor：0.8 减伤在浮点下 10×0.2=1.999…，floor 会多砍 1
			reduced["amount"] = int(round(float(int(ctx.get("amount", 0))) * (1.0 - block)))
			super(reduced)
			return
	super(ctx)

## 生效正面减伤比例（子类覆写钩子：石盾武僧破势窗内归零）。
func _effective_block_pct(_frame: int) -> float:
	return float(row.get("front_block_pct", 0.0))
