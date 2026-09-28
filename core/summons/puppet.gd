class_name PuppetSummon
extends SummonBase
## 死灵·骸「起傀」骸骨傀儡召唤体（M5-T5，附录 L §3 第 11 行 + 强化行）。
## 复用 turret.gd 友方部署实体完整先例（SummonBase 骨架：spawn→存活期→消散；
## 「summons」组、玩家阵营战斗体、不进波次计数——同炮台，T7 吟游光环以组联动）。
## - 存活 12s（LIFETIME_TICKS，附录 L §3「12s 存活后消散」）；
## - 攻击节奏 8s 一击（ATTACK_INTERVAL_TICKS）、伤 12（ATTACK_DAMAGE，附录 L §3
##   「12 伤/8s」字面：单次重击 12 伤、间隔 8s——同炮台「DPS=伤×频」拆解习语）。
##   存活 720t 与间隔 480t 两规格数字直推：每只傀儡存活期恰落 1 击（部署 +8s 拍，
##   第二拍 +16s 已越 12s 存活线）——规格原样实现，节奏数值供强化/Balance Bot 调参；
## - 索敌 = 60px 内最近敌人（ATTACK_RANGE_PX，复用 AutoAim.pick_target 全向锥，
##   brain_pos 权威——同炮台习语）；命中为近身直击（bodies_in_radius 取最近
##   1 体 take_hit，同炮台导弹直击通路，不走弹池）；
## - 部署后驻留（同炮台先例，无寻路——「召唤扛伤」定位：以驻留体承接敌弹）；
## - 强化（行键 upgraded，附录 L 强化行「傀儡死亡自爆 24 AoE」）：被敌方击毁
##   （despawn reason="destroyed"，即 hp 归零路径）时以爆心 24 伤 AoE 直击范围内
##   敌方体；存活期自然消散（"expired"）与其它退场（"replaced" 等）不引爆——
##   「死亡」严格取击毁语义（消散≠死亡，头注钉死）。
## 无附录出处的实现议定值（Balance Bot 校准点，同 SHOT_SPEED 先例披露）：
## ATTACK_RANGE_PX 60px（life_tide 60px AoE 议定先例）、行 hp 10（照炮台
## TURRET_HP=10 生命先例定值，附录 L 未给）、爆心半径 48px（炮台导弹
## MISSILE_AOE_PX=48 议定先例）、体半径 7.0（炮台同款）。

const LIFETIME_TICKS := 720           # 12s（附录 L §3「12s 存活后消散」）
const ATTACK_INTERVAL_TICKS := 480    # 8s 攻击节奏（附录 L §3「/8s」）
const ATTACK_DAMAGE := 12             # 附录 L §3「12 伤」
const ATTACK_RANGE_PX := 60.0         # 议定：近身打击距离
const PUPPET_HP := 10                 # 议定：照炮台生命先例（附录 L 未给，校准点）
const PUPPET_RADIUS := 7.0            # 议定：战斗体半径（同炮台）
const BURST_DAMAGE := 24              # 强化：死亡自爆 24 AoE（附录 L 强化行逐字）
const BURST_RADIUS_PX := 48.0         # 议定：自爆爆心半径（炮台导弹同款）

var upgraded := false
var _next_attack_at := -1

## 部署行（技能侧装配入口）：数值集中本类常量（同 TurretSummon.default_row 习语）。
static func default_row(is_upgraded: bool = false) -> Dictionary:
	return {
		"id": "puppet", "hp": PUPPET_HP, "lifetime_ticks": LIFETIME_TICKS,
		"radius": PUPPET_RADIUS, "upgraded": is_upgraded,
	}

func setup(r: Dictionary) -> void:
	super.setup(r)
	upgraded = bool(r.get("upgraded", false))

## 占位视觉（骸骨色块 + 双臂骨条，同炮台/RoomCombat 回落习语；纯表现层无玩法数值）。
func _ready() -> void:
	var base := Polygon2D.new()
	base.name = "Visual"
	base.polygon = PackedVector2Array([
		Vector2(-5, -6), Vector2(5, -6), Vector2(5, 6), Vector2(-5, 6),
	])
	base.color = Color(0.88, 0.86, 0.78)     # 骨白
	add_child(base)
	var arm := Polygon2D.new()
	arm.polygon = PackedVector2Array([Vector2(-8, -1), Vector2(8, -1), Vector2(8, 1), Vector2(-8, 1)])
	arm.color = Color(0.55, 0.52, 0.45)      # 暗骨臂
	add_child(arm)

func _on_deploy(frame: int) -> void:
	_next_attack_at = frame + ATTACK_INTERVAL_TICKS

## 节拍驱动：非节拍帧零开销直接返回（组扫描只在 8s 节拍上发生，热路径零分配）。
func _tick_ai(frame: int) -> void:
	if frame < _next_attack_at:
		return
	_next_attack_at = frame + ATTACK_INTERVAL_TICKS   # 节拍恒推进（无目标空挥，同炮台口径）
	var target := _acquire_target()
	if target != null:
		_slam(target, frame)

## 索敌：60px 内最近存活敌人（复用 AutoAim.pick_target 全向锥；无目标返回 null）。
func _acquire_target() -> EnemyBase:
	if not is_inside_tree():
		return null
	var candidates: Array[Vector2] = []
	var enemies: Array[EnemyBase] = []
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as EnemyBase
		if e == null or e.state == EnemyBase.State.DEAD:
			continue
		if e.brain_pos.distance_to(global_position) > ATTACK_RANGE_PX:
			continue
		enemies.append(e)
		candidates.append(e.brain_pos)
	if candidates.is_empty():
		return null
	var idx := AutoAim.pick_target(global_position, 0.0, candidates, 360.0)
	return enemies[idx] if idx >= 0 else null

## 近身重击：单目标直击（同炮台导弹直击结算通路，可触发元素/归因玩家侧）。
func _slam(target: EnemyBase, frame: int) -> void:
	target.take_hit({
		"amount": ATTACK_DAMAGE, "is_crit": false, "element": Elements.Id.NONE,
		"from": global_position, "frame": frame, "source_type": "summon",
		"source_id": id, "source_name": "骸骨傀儡", "attack_name": "傀儡重击",
		"player_damage": true,
	})

## 统一退场覆写：强化版被击毁（"destroyed"）先自爆再走基类注销/遥测/回收
## （爆心结算要求 combat 引用仍有效，故在 super.despawn 之前）。
func despawn(reason: String) -> void:
	if upgraded and reason == "destroyed":
		_self_destruct()
	super.despawn(reason)

## 死亡自爆：以自身为爆心 24 伤 AoE 直击范围内敌方体（同炮台导弹 bodies_in_radius
## 习语；已死者跳过防同拍重复结算）。多傀儡同帧同拍限一声（AudioMgr.play_once）。
func _self_destruct() -> void:
	if combat == null or not is_instance_valid(combat):
		return
	var at := global_position
	var frame := Engine.get_physics_frames()
	var hits := 0
	for body in combat.bodies_in_radius(at, BURST_RADIUS_PX, Projectile.Faction.ENEMY):
		if body.get("state") == EnemyBase.State.DEAD:
			continue
		hits += 1
		body.take_hit({
			"amount": BURST_DAMAGE, "is_crit": false, "element": Elements.Id.NONE,
			"from": at, "frame": frame, "source_type": "summon", "source_id": id,
			"source_name": "骸骨傀儡", "attack_name": "骸爆", "player_damage": true,
		})
	AudioMgr.play_once("puppet_burst")   # m5-t5：自爆拍（同拍多爆限一声）
	Telemetry.log_row(["puppet_burst", frame, BURST_DAMAGE, hits])
