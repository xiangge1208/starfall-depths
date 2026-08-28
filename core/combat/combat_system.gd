class_name CombatSystem
extends Node
## 弹幕推进 + 命中结算（GDD §18.2：空间哈希 O(n·k)）。

const BODY_HIT_COOLDOWN_TICKS := 6   # 同一弹对同一体的重复命中抑制（穿透用）

var pool: ProjectilePool
var crit_chance := 0.05
var _hash := SpatialHash.new(32.0)
var _bodies: Dictionary = {}          # instance_id -> {node, faction, radius}
var _max_body_radius := 12.0          # m0-final fix2：查询松弛按已注册体最大半径（单调不缩）
var _rng: RandomNumberGenerator
var _next_id := 1
var _proj_meta: Dictionary = {}       # projectile instance_id -> {hash_id, hit_cd: Dictionary}

func _init(root: Node, combat_rng: RandomNumberGenerator) -> void:
	pool = ProjectilePool.new(root)
	pool.on_evict = _kill               # m0-final fix1：cap 淘汰也走 _kill，哈希/元数据不泄漏
	_rng = combat_rng

func register_body(node: Node2D, faction: int) -> void:
	_max_body_radius = maxf(_max_body_radius, node.combat_radius())   # fix2：候选门按最大体半径
	_bodies[node.get_instance_id()] = {"node": node, "faction": faction, "radius": node.combat_radius(), "hash_id": _next_id}
	_hash.insert(_next_id, node.global_position)
	_next_id += 1

func unregister_body(node: Node2D) -> void:
	var id := node.get_instance_id()
	if _bodies.has(id):
		_hash.remove(_bodies[id]["hash_id"])
		_bodies.erase(id)

func spawn_projectile(cfg: Dictionary) -> void:
	var p := pool.spawn(cfg)
	_proj_meta[p.get_instance_id()] = {"hash_id": _next_id, "hit_cd": {}}
	_hash.insert(_next_id, p.position)
	_next_id += 1

func active_count() -> int:
	return pool.active_count()

## m0-final fix5：调试观测专用（cap 淘汰泄漏回归测试用）——仅元数据计数，别无他物公开。
func debug_meta_count() -> int:
	return _proj_meta.size()

func _physics_process(_delta: float) -> void:
	# 1) 实体位置更新
	for id: int in _bodies:
		var b: Dictionary = _bodies[id]
		_hash.move(b["hash_id"], b["node"].global_position)
	# 2) 弹体推进 + 命中
	for p in pool.active.duplicate():
		if not p.tick():
			_kill(p)
			continue
		var meta: Dictionary = _proj_meta[p.get_instance_id()]
		_hash.move(meta["hash_id"], p.position)
		var hits := _hash.query(p.position, p.radius + _max_body_radius)   # fix2：松弛覆盖最大体半径，防大半径体被静默漏判
		for hid: int in hits:
			var b: Dictionary = _bodies_by_hash(hid)
			if b.is_empty() or b["faction"] == p.faction:
				continue
			var node: Node2D = b["node"]
			if node.global_position.distance_to(p.position) > p.radius + b["radius"]:
				continue
			var cd: Dictionary = meta["hit_cd"]
			if int(cd.get(node.get_instance_id(), -99)) + BODY_HIT_COOLDOWN_TICKS > Engine.get_physics_frames():
				continue
			cd[node.get_instance_id()] = Engine.get_physics_frames()
			var roll := DamageCalc.compute(p.damage, _rng, crit_chance)
			if p.faction == Projectile.Faction.PLAYER and roll["is_crit"]:
				EventBus.player_crit_landed.emit(roll["amount"], p.position)   # m1-t2：玩家弹暴击落地
			node.take_hit({"amount": roll["amount"], "is_crit": roll["is_crit"], "element": p.element, "from": p.position})
			if p.pierce_left > 0:
				p.pierce_left -= 1
			else:
				_kill(p)
				break

func _bodies_by_hash(hid: int) -> Dictionary:
	# M0（≤300 实体）线性反查可接受；若 t13 门禁压测超标，
	# 补 _hash_id -> body_id 反查字典（属性能修复，接口不变）。
	for id: int in _bodies:
		if _bodies[id]["hash_id"] == hid:
			return _bodies[id]
	return {}

func _kill(p: Projectile) -> void:
	_hash.remove(_proj_meta[p.get_instance_id()]["hash_id"])
	_proj_meta.erase(p.get_instance_id())
	pool.despawn(p)

# ---- 近战支持 ----
func projectiles_in_arc(origin: Vector2, facing: float, range_px: float, arc_deg: float, faction: int) -> Array[Projectile]:
	var out: Array[Projectile] = []
	for p in pool.active:
		if p.faction != faction:
			continue
		var to := p.position - origin
		if to.length() > range_px + p.radius:
			continue
		if absf(angle_difference(facing, to.angle())) <= deg_to_rad(arc_deg) / 2.0:
			out.append(p)
	return out

func bodies_in_arc(origin: Vector2, facing: float, range_px: float, arc_deg: float, faction: int) -> Array:
	var out: Array = []
	for id: int in _bodies:
		var b: Dictionary = _bodies[id]
		if b["faction"] != faction:
			continue
		var to: Vector2 = b["node"].global_position - origin
		if to.length() > range_px + b["radius"]:
			continue
		if absf(angle_difference(facing, to.angle())) <= deg_to_rad(arc_deg) / 2.0:
			out.append(b["node"])
	return out

func reflect(p: Projectile, new_damage: int) -> void:
	p.faction = Projectile.Faction.PLAYER
	p.vel = -p.vel
	p.damage = new_damage
	p.life_ticks = TimeConst.ticks(1.0)
	p.modulate = Color(1.0, 1.0, 0.4)

func block(p: Projectile) -> void:
	_kill(p)
