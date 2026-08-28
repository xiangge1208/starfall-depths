class_name ShieldSpirit
extends Node2D
## 护盾精灵（m1-t16 精灵像）：作为 Player 子节点挂在固定偏移（-24px）随玩家移动，
## 每物理拍经注入的房间 CombatSystem 查 12px 内敌方弹并拦截 1 发，3 次耗尽自灭。
## 接缝（全部 duck-typed，便于 headless 单测替身）：
## - combat: 房间 CombatSystem（可选；缺省只跟随不拦截）。
##   查询走 combat.pool.active（与 CombatSystem/ProjectilePool 现有结构对齐）；
##   拦截优先 combat.block(p)（T18 接缝，现尚不存在）——
##   落地前退化为 life_ticks=0（下拍 CombatSystem._kill 正常回收）+ on_despawn 隐身。
## - 同一发弹经 _blocked_ids 去重，拦截失败/无 block 也不会重复扣次数。

signal exhausted

const FOLLOW_OFFSET := Vector2(0, -24)   # 24px 偏移（玩家头顶）
const BLOCK_RADIUS := 12.0

var player: Node2D = null
var combat = null                        # duck-typed CombatSystem（可选）
var charges := 3
var _blocked_ids: Dictionary = {}        # instance_id -> true（去重防线）

## 链式装配：挂到玩家（调用方 add_child），可注入 combat 与次数。
func setup(p: Node2D, combat_ = null, charges_ := 3) -> ShieldSpirit:
	player = p
	combat = combat_
	charges = charges_
	position = FOLLOW_OFFSET
	return self

func _physics_process(_delta: float) -> void:
	guard_tick()

## 拦截一拍：命中敌方弹 → 拦截 + 扣次数（0 耗尽自灭）；返回是否发生拦截。
func guard_tick() -> bool:
	if charges <= 0 or combat == null or player == null:
		return false
	var target := _find_blockable()
	if target == null:
		return false
	_block(target)
	charges -= 1
	if charges <= 0:
		exhausted.emit()
		queue_free()                     # 3 发拦完消失
	return true

## 射程内最近的可拦截敌方弹（faction==ENEMY 且未被本精灵拦过）。
func _find_blockable() -> Node2D:
	var pool_obj: Variant = combat.get("pool")
	if pool_obj == null:
		return null
	var active: Array = pool_obj.get("active")
	var best: Node2D = null
	var best_d := INF
	for p: Variant in active:
		if p == null or not is_instance_valid(p):
			continue
		var faction: Variant = p.get("faction")
		if faction == null or int(faction) != Projectile.Faction.ENEMY:
			continue
		if _blocked_ids.has(p.get_instance_id()):
			continue
		var node := p as Node2D
		if node == null:
			continue
		var radius_v: Variant = p.get("radius")
		var radius := float(radius_v) if radius_v != null else 0.0
		var d := node.global_position.distance_to(global_position)
		if d <= BLOCK_RADIUS + radius and d < best_d:
			best_d = d
			best = node
	return best

## 拦截落地：优先 combat.block（正式接缝）；缺省退化 life_ticks=0 + on_despawn。
func _block(p: Node2D) -> void:
	_blocked_ids[p.get_instance_id()] = true
	if combat != null and combat.has_method("block"):
		combat.block(p)
	else:
		p.set("life_ticks", 0)           # 下拍 CombatSystem 推进时 _kill 正常回收
		if p.has_method("on_despawn"):
			p.call("on_despawn")         # 立即隐身（视觉拦截反馈）
