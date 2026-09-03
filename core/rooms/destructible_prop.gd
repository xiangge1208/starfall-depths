class_name DestructibleProp
extends StaticBody2D
## 可破坏陈设（m4-c5）：pillar/crate/bush 从静态阻挡升级为可破坏（task-33 §2.4
## demolition BLOCKED 的机制缺口收口）。
##
## 伤害入口 = CombatSystem 判定流既有缝（gem_queen HivePillar 先例同形，独立实现不共用）：
## attach_combat → register_body(self, Faction.ENEMY) → 玩家弹/近战/召唤物/玩家侧 AoE
## 经 `_projectile_hit_candidates`/`bodies_in_arc`/`bodies_in_radius` 命中本体的
## take_hit。**固定伤害制**：ctx.amount 已是 DamageCalc 结算终值（暴击 = 全游戏唯一
## 随机乘区），本体直扣、无二次随机乘区。
##
## 破坏结算（FloorScene._on_prop_destroyed 经 destroyed 信号承接）：战斗体注销 +
## 阻挡消失（StaticBody2D 整体 queue_free，`_room_solid_rects` 读活子节点 → 通行性
## 即时恢复）+ 掉落按行（drops 数据键）+ 遥测 `prop_destroyed` +
## AchievementSystem.notify_prop_destroyed（demolition 接线）。
##
## 预算：**独立池小上限**（PER_ROOM_CAP，防滥用）——本体不是弹，不进 ProjectilePool/
## 弹幕可视化预算；破坏表现走 fx/ 既有 ParticlesPool 预算（kill_shard），不新增 draw 大户。

signal destroyed(prop: DestructibleProp)

const COMBAT_RADIUS_PX := 8.0    # 16px 格内切圆判定（EnemyLaser.PILLAR_RADIUS_PX 同口径）
const PER_ROOM_CAP := 32         # 每房可破坏体上限（独立池防滥用；模板实测最大 14）

var kind := "pillar"
var max_hp := 1
var hp := 1
var drops: Array[String] = []    # 破坏掉落（Pickup kind 白名单，按行配置；空 = 无掉落）
var blocking := true             # true = 物理阻挡（pillar/crate 静态期语义）；bush 仅视觉
var combat: CombatSystem = null
var _done := false               # 破坏幂等门（destroyed 恰一次）


## 独立池上限纯函数：超出 cap 的陈设行截断（fail-soft，构建侧 push_warning 留痕）。
static func bounded(rows: Array, cap: int) -> Array:
	if rows.size() <= cap:
		return rows
	return rows.slice(0, cap)


## 装配：rect = 阻挡/落位矩形（房内局部坐标）；vis 由构建侧提供（贴图/缺图回落
## 已在 FloorScene._prop_visual 收口），null 允许（纯逻辑测试）。
func setup(p_kind: String, hp_value: int, p_drops: Array[String], p_blocking: bool,
		rect: Rect2, vis: Node2D) -> void:
	kind = p_kind
	max_hp = maxi(hp_value, 1)
	hp = max_hp
	drops = p_drops
	blocking = p_blocking
	position = rect.get_center()
	if blocking:
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		cs.shape = shape
		add_child(cs)
	if vis != null:
		vis.position = Vector2.ZERO
		add_child(vis)


## 进战斗流（CombatSystem 建制后由 FloorScene 接线；战斗房才有 combat——
## start 等非战斗房 props 保持纯静态陈设）。重复接线安全（换房重接语义备用）。
func attach_combat(system: CombatSystem) -> void:
	if combat == system:
		return
	if combat != null:
		combat.unregister_body(self)
	combat = system
	if combat != null:
		combat.register_body(self, Projectile.Faction.ENEMY)   # HivePillar 同缝：玩家侧伤害可及


## CombatSystem 战斗体半径契约（同 EnemyBase.combat_radius 口径）。
func combat_radius() -> float:
	return COMBAT_RADIUS_PX


## 伤害入口（固定伤害制）：amount 直扣，归零即破坏。已破坏再击零副作用（幂等）。
func take_hit(ctx: Dictionary) -> void:
	if _done:
		return
	hp = maxi(hp - absi(int(ctx.get("amount", 0))), 0)
	if hp == 0:
		destroy()


## 破坏：战斗体注销（哈希不泄漏）→ destroyed 信号（FloorScene 承接掉落/遥测/成就）→
## 整体退场（阻挡随节点消失，通行性恢复）。
func destroy() -> void:
	if _done:
		return
	_done = true
	hp = 0
	AudioMgr.play_once("destroy")   # m4p-w2a：陈设破碎拍（幂等门内恰一次；同帧多体限一声）
	if combat != null:
		combat.unregister_body(self)
		combat = null
	destroyed.emit(self)
	queue_free()
