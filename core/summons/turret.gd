class_name TurretSummon
extends SummonBase
## 工程师·铆「自动炮台」召唤体（M2-T8 计划卡 + GDD §6 技能表）。
## - 存活 12s（LIFETIME_TICKS，计划卡/GDD §6「存活 12s」）；
## - 索敌 = 240px 内最近敌人（RANGE_PX，计划卡契约；复用 AutoAim.pick_target，
##   锥角 360° 即全向，敌人位置以 brain_pos 为权威——同坚守被动/敌方 AI 习语）；
## - 射速 2/s（FIRE_INTERVAL_TICKS）、伤 4（SHOT_DAMAGE）——玩家阵营弹经房间
##   CombatSystem 结算（可暴击/可触发元素，与武器弹同通路，不另起 RNG）；
## - 升级版（heroes 行 upgraded）：每 3s 追加一发导弹（12 AoE，GDD §6 强化列，
##   落点为当前索敌目标，范围内敌方体直击结算）。
## 无附录出处的实现议定值（T28 Balance Bot 校准点）：SHOT_SPEED_PX/SHOT_LIFE_SECONDS/
## MISSILE_AOE_PX/行 hp；其余数值均出自计划卡或 GDD §6。
## m4-c2 备件（工程师被动，GDD §6「开局带 1 台便携炮台（存活 12s，DPS 15）」）：
## 备件炮台经 spare_parts_row() 行注入——存活/耐久/索敌与主动技炮台同一框架，
## 差异仅射速/单发伤：DPS 15 = 5 伤 × 3/s（GDD 仅给 DPS，拆分议定同 SHOT_SPEED 先例，
## T28 校准点）。行键 shot_damage/fire_interval_ticks 缺省回落主动技常量（零漂移）。

const LIFETIME_TICKS := 720           # 12s（计划卡/GDD §6）
const RANGE_PX := 240.0               # 索敌半径（计划卡契约）
const FIRE_INTERVAL_TICKS := 30       # 2/s（计划卡）
const SHOT_DAMAGE := 4                # 计划卡（伤 4）
const SHOT_SPEED_PX := 180.0          # 议定：介于敌弹基准 110 与玩家弹 300 之间
const SHOT_LIFE_SECONDS := 1.5        # 议定：覆盖 240px 索敌半径（240/180 ≈ 1.33s）
const MISSILE_INTERVAL_TICKS := 180   # 每 3s（GDD §6 强化）
const MISSILE_DAMAGE := 12            # GDD §6 强化（12 AoE）
const MISSILE_AOE_PX := 48.0          # 议定：导弹爆心半径
const TURRET_HP := 10                 # 议定：便携炮台耐久（无出处，框架字段）
const TURRET_RADIUS := 7.0            # 议定：战斗体半径（视觉同尺寸）
const SPARE_PARTS_SHOT_DAMAGE := 5            # m4-c2 备件：5 伤
const SPARE_PARTS_FIRE_INTERVAL_TICKS := 20   # m4-c2 备件：3/s → DPS 15（GDD §6）

var upgraded := false
var shot_damage := SHOT_DAMAGE              # m4-c2：行键 shot_damage 可覆写（缺省主动技 4）
var fire_interval_ticks := FIRE_INTERVAL_TICKS  # m4-c2：行键 fire_interval_ticks 可覆写
var _next_shot_at := -1
var _next_missile_at := -1

## 部署行（技能侧装配入口）：数值集中本类常量，heroes 行只携带 upgraded/cap。
static func default_row(is_upgraded: bool = false) -> Dictionary:
	return {
		"id": "turret", "hp": TURRET_HP, "lifetime_ticks": LIFETIME_TICKS,
		"radius": TURRET_RADIUS, "upgraded": is_upgraded,
	}

## m4-c2 备件炮台部署行（run_root 层入口被动补台用）：存活 12s、DPS 15（GDD §6）。
static func spare_parts_row() -> Dictionary:
	return {
		"id": "turret", "hp": TURRET_HP, "lifetime_ticks": LIFETIME_TICKS,
		"radius": TURRET_RADIUS, "upgraded": false,
		"shot_damage": SPARE_PARTS_SHOT_DAMAGE,
		"fire_interval_ticks": SPARE_PARTS_FIRE_INTERVAL_TICKS,
	}

func setup(r: Dictionary) -> void:
	super.setup(r)
	upgraded = bool(r.get("upgraded", false))
	shot_damage = maxi(1, int(r.get("shot_damage", SHOT_DAMAGE)))
	fire_interval_ticks = maxi(1, int(r.get("fire_interval_ticks", FIRE_INTERVAL_TICKS)))

## 占位视觉（色块 + 炮管，同 RoomCombat 敌人回落习语；正式贴图归 M2-T17/T21 美术卡）。
## 纯表现层，不含玩法数值。
func _ready() -> void:
	var base := Polygon2D.new()
	base.name = "Visual"
	base.polygon = PackedVector2Array([
		Vector2(-5, -5), Vector2(5, -5), Vector2(5, 5), Vector2(-5, 5),
	])
	base.color = Color(0.85, 0.62, 0.25)     # 工程师橙棕
	add_child(base)
	var barrel := Polygon2D.new()
	barrel.polygon = PackedVector2Array([Vector2(0, -1.5), Vector2(8, 0), Vector2(0, 1.5)])
	barrel.color = Color(0.42, 0.42, 0.48)
	add_child(barrel)

func _on_deploy(frame: int) -> void:
	_next_shot_at = frame + fire_interval_ticks
	_next_missile_at = frame + MISSILE_INTERVAL_TICKS

## 节拍驱动：非节拍帧零开销直接返回（组扫描只在 2/s + 3s 节拍上发生，热路径零分配）。
func _tick_ai(frame: int) -> void:
	var shot_due := frame >= _next_shot_at
	var missile_due := upgraded and frame >= _next_missile_at
	if not shot_due and not missile_due:
		return
	var target := _acquire_target()
	if shot_due:
		_next_shot_at = frame + fire_interval_ticks
		if target != null:
			_fire_shot(target)
	if missile_due:
		_next_missile_at = frame + MISSILE_INTERVAL_TICKS
		if target != null:
			_fire_missile(target, frame)

## 索敌：240px 内最近存活敌人（复用 AutoAim.pick_target 全向锥；无目标返回 null）。
func _acquire_target() -> EnemyBase:
	if not is_inside_tree():
		return null
	var candidates: Array[Vector2] = []
	var enemies: Array[EnemyBase] = []
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as EnemyBase
		if e == null or e.state == EnemyBase.State.DEAD:
			continue
		if e.brain_pos.distance_to(global_position) > RANGE_PX:
			continue
		enemies.append(e)
		candidates.append(e.brain_pos)
	if candidates.is_empty():
		return null
	var idx := AutoAim.pick_target(global_position, 0.0, candidates, 360.0)
	return enemies[idx] if idx >= 0 else null

## 直射弹：玩家阵营经房间 CombatSystem（命中/暴击/元素结算与武器弹同通路）。
func _fire_shot(target: EnemyBase) -> void:
	if combat == null or not is_instance_valid(combat):
		return
	var dir := (target.brain_pos - global_position).normalized()
	AudioMgr.play_once("turret_shot")   # m4p-w2a：炮台开火拍（多台同帧限一声）
	combat.spawn_projectile({
		"pos": global_position, "vel": dir * SHOT_SPEED_PX, "damage": shot_damage,
		"faction": Projectile.Faction.PLAYER, "element": Elements.Id.NONE,
		"pierce": 0, "bounce": 0, "life_seconds": SHOT_LIFE_SECONDS,
		"radius": 3.0, "source_type": "summon", "source_id": id,
		"source_name": "自动炮台", "attack_name": "炮台弹",
	})

## 升级版导弹：以当前目标为爆心的 AoE 直击（同元素跳电/毒火云的 bodies_in_radius 习语）。
func _fire_missile(target: EnemyBase, frame: int) -> void:
	if combat == null or not is_instance_valid(combat):
		return
	var at := target.brain_pos
	AudioMgr.play_once("missile")       # m4p-w2a：升级导弹发射拍（多台同帧限一声）
	for body in combat.bodies_in_radius(at, MISSILE_AOE_PX, Projectile.Faction.ENEMY):
		if body.get("state") == EnemyBase.State.DEAD:
			continue
		body.take_hit({
			"amount": MISSILE_DAMAGE, "is_crit": false, "element": Elements.Id.NONE,
			"from": at, "frame": frame, "source_type": "summon", "source_id": id,
			"source_name": "自动炮台", "attack_name": "追击导弹", "player_damage": true,
		})
