extends EnemyBase
## 亡灵枪手（小 Boss，附录 B.3「与玩家对枪：玩家开火它才开火，弹形复制玩家武器」）：
## 对枪节拍——ENGAGE 后每拍监视战斗池：存在弹龄 ≤1 拍（Projectile._ticks，战斗拍推进）
## 的玩家弹即判定「玩家开火」。触发后 windup 预警（≥24t 契约）才应答 1 发，随后
## cd_ticks 冷却；同一次开火（同一颗弹）只应答一次（_answered 闭锁，冷却结束复位）。
## 弹形复制：玩家 rig 当前武器 damage/bullet_speed（速度夹 ≤150 敌弹上限）；
## 无 rig（替身/脑测）回落行 bullet_dmg/bullet_speed。

const COPY_SPEED_CAP := 150.0
const PLAYER_FIRE_AGE_TICKS := 1

var _phase := "idle"             # idle=待玩家开火 / windup / cool
var _phase_left := 0
var _answered := false           # 玩家最近一次开火是否已应答（冷却结束复位）

func _engage(_frame: int) -> void:
	_kite_walk()
	match _phase:
		"idle":
			if not _answered and _player_fired_recently():
				_phase = "windup"
				_phase_left = _windup_ticks(30)
				Fx.on_enemy_hit(self, {"telegraph": true})
		"windup":
			_phase_left -= 1
			if _phase_left <= 0:
				_answer_fire()
				_phase = "cool"
				_phase_left = maxi(int(row.get("cd_ticks", 90)) - int(row.get("windup_ticks", 30)), 0)
		"cool":
			_phase_left -= 1
			if _phase_left <= 0:
				_phase = "idle"
				_answered = false

## 对枪位走位：贴近至 140~200px 区间外时修正，区间内小幅侧移。
func _kite_walk() -> void:
	var to_player := _player_pos() - brain_pos
	var dist := to_player.length()
	var step := Vector2.ZERO
	if dist < 140.0:
		step = -to_player.normalized()
	elif dist > 200.0:
		step = to_player.normalized()
	else:
		step = to_player.orthogonal().normalized()
	brain_pos += step * (float(row.get("speed", 60)) / TimeConst.FPS)

## 玩家是否「刚刚开火」：池内存在弹龄 ≤1 拍的玩家弹。
func _player_fired_recently() -> bool:
	if combat == null:
		return false
	for p in combat.pool.active:
		if p.faction == Projectile.Faction.PLAYER and p._ticks <= PLAYER_FIRE_AGE_TICKS:
			return true
	return false

## 应答一发（弹形复制玩家武器；无 rig 回落行值）。速度夹敌弹上限 150。
func _answer_fire() -> void:
	fired_this_tick = true
	_answered = true
	if combat == null:
		return
	var dmg := int(row.get("bullet_dmg", 4))
	var speed := enemy_bullet_speed(110.0)
	var rig = player_ref.get("weapon_rig") if player_ref != null else null
	if rig != null:
		var w: Dictionary = rig.current()
		if not w.is_empty():
			dmg = int(w.get("damage", dmg))
			# m3-fix1：bullet_speed_pct 统一口径（复制速已夹 ≤150，因子只对 ≤150 段等比、
			# 封顶不倒扣；脑测回退路径经 enemy_bullet_speed 单次缩放，两路径不叠加）
			speed = TrialMods.enemy_bullet_speed_px(
				minf(float(w.get("bullet_speed", speed)), COPY_SPEED_CAP))
	var dir := (_player_pos() - brain_pos).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	combat.spawn_projectile({
		"pos": brain_pos, "vel": dir * speed,
		"damage": dmg, "faction": Projectile.Faction.ENEMY,
		"element": Elements.Id.NONE, "pierce": 0, "bounce": 0,
		"life_seconds": float(row.get("bullet_life_seconds", 2.5)),
		"radius": float(row.get("bullet_radius", 3.0)),
		"source_type": "projectile", "source_id": String(row.get("id", "")),
		"source_name": String(row.get("name", row.get("id", ""))), "attack_name": "对枪还击",
	})
