class_name CombatSystem
extends Node
## 弹幕推进 + 命中结算（GDD §18.2：空间哈希 O(n·k)）。

const BODY_HIT_COOLDOWN_TICKS := 6   # 同一弹对同一体的重复命中抑制（穿透用）
const ENEMY_BULLET_CAP := 400        # m1-t18 GDD §7.5：敌方场上弹上限（总池 MAX_PROJECTILES 500 不变）

var pool: ProjectilePool
var crit_chance := 0.05
var crit_multiplier := 2.0         # 玩家暴击倍率（Buff/楼层接线写入）
var status_rate_mult := 1.0        # 玩家元素状态积累倍率
var forced_crit_until := -1        # m1-t5 影袭：frame < 此值时玩家弹命中必暴（技能经 player.combat 写入）
var _hash := SpatialHash.new(32.0)
var _bodies: Dictionary = {}          # instance_id -> {node, faction, radius}
var _max_body_radius := 12.0          # m0-final fix2：查询松弛按已注册体最大半径（单调不缩）
var _rng: RandomNumberGenerator
var _next_id := 1
var _proj_meta: Dictionary = {}       # projectile instance_id -> {hash_id, hit_cd, source/强制共鸣元数据}
var _blaze_clouds: Array[Dictionary] = []

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
	# m1-t18 GDD §7.5：敌方弹达 400 时先淘汰最旧敌方弹（公平性 victim，同池 cap 习语），
	# 再生成；玩家弹不受此门。O(n) 清点在发射节奏（低频）可接受（t18 决议披露）。
	if int(cfg.get("faction", Projectile.Faction.PLAYER)) == Projectile.Faction.ENEMY \
			and _enemy_alive_count() >= ENEMY_BULLET_CAP:
		_kill(_oldest_enemy())
	var p := pool.spawn(cfg)
	_proj_meta[p.get_instance_id()] = {
		"hash_id": _next_id, "hit_cd": {},
		"source_type": String(cfg.get("source_type", "projectile")),
		"source_id": String(cfg.get("source_id", "")),
		"source_name": String(cfg.get("source_name", "")),
		"attack_name": String(cfg.get("attack_name", "弹幕")),
	}
	_hash.insert(_next_id, p.position)
	_next_id += 1

## 敌方弹存活数（spawn 拍 O(n) 清点）。
func _enemy_alive_count() -> int:
	var n := 0
	for p in pool.active:
		if p.faction == Projectile.Faction.ENEMY:
			n += 1
	return n

## 最旧敌方弹（公平性 victim）；调用前提是清点 ≥400（恒有敌方弹，回退分支不可达）。
func _oldest_enemy() -> Projectile:
	for p in pool.active:
		if p.faction == Projectile.Faction.ENEMY:
			return p
	return pool.active[0]

func active_count() -> int:
	return pool.active_count()

## m0-final fix5：调试观测专用（cap 淘汰泄漏回归测试用）——仅元数据计数，别无他物公开。
func debug_meta_count() -> int:
	return _proj_meta.size()

func _physics_process(_delta: float) -> void:
	var frame := Engine.get_physics_frames()
	_tick_blaze_clouds(frame)
	# 1) 实体位置更新
	for id: int in _bodies:
		var b: Dictionary = _bodies[id]
		_hash.move(b["hash_id"], b["node"].global_position)
	# 2) 弹体推进 + 命中
	for p in pool.active.duplicate():
		var meta: Dictionary = _proj_meta[p.get_instance_id()]
		if not p.tick():
			_kill(p)
			continue
		_hash.move(meta["hash_id"], p.position)
		var hits := _projectile_hit_candidates(p)
		for b: Dictionary in hits:
			var node: Node2D = b["node"]
			var cd: Dictionary = meta["hit_cd"]
			if int(cd.get(node.get_instance_id(), -99)) + BODY_HIT_COOLDOWN_TICKS > frame:
				continue
			cd[node.get_instance_id()] = frame
			var player_shot: bool = p.faction == Projectile.Faction.PLAYER
			var cc := crit_chance if player_shot else 0.0
			if player_shot and Engine.get_physics_frames() < forced_crit_until:
				cc = 1.0                        # m1-t5 影袭：玩家弹必暴窗（帧口径同上物理帧）
			var roll: Dictionary = DamageCalc.compute(p.damage, _rng, cc,
				crit_multiplier if player_shot else 2.0)
			if p.faction == Projectile.Faction.PLAYER and roll["is_crit"]:
				EventBus.player_crit_landed.emit(roll["amount"], p.position)   # m1-t2：玩家弹暴击落地
			# 附录 C 的附魔在「有效命中」才掷签；没有附魔时 helper 不消费 RNG。
			# 多弹按 pool.active 生成顺序、穿透目标按距离/注册序消费，保证同 seed 复现。
			var proc_element := Elements.Id.NONE
			if player_shot:
				proc_element = ElementProc.roll_element(p.enchant_element,
					p.enchant_proc_chance, _rng)
			var force_resonance: bool = player_shot and bool(roll["is_crit"]) \
				and ElementProc.roll_chance(p.crit_detonate_pct, _rng)
			node.take_hit({
				"amount": roll["amount"], "is_crit": roll["is_crit"], "element": p.element,
				"proc_element": proc_element,
				"from": p.position, "frame": frame, "force_resonance": force_resonance,
				"status_rate_mult": status_rate_mult if player_shot else 1.0,
				"source_type": meta.get("source_type", "projectile"),
				"source_id": meta.get("source_id", ""), "source_name": meta.get("source_name", ""),
				"attack_name": meta.get("attack_name", "弹幕"),
				"player_damage": player_shot,
				"slow_pct": p.slow_pct, "slow_ticks": p.slow_ticks,
			})
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

## 弹体同拍可能覆盖多个目标。显式排序后再消费暴击/proc RNG，避免 Dictionary
## 迭代次序让穿透结果在同 seed 下漂移：近者优先，同距按注册 hash id。
func _projectile_hit_candidates(p: Projectile) -> Array[Dictionary]:
	var ranked: Array[Dictionary] = []
	for hid: int in _hash.query(p.position, p.radius + _max_body_radius):
		var b := _bodies_by_hash(hid)
		if b.is_empty() or int(b["faction"]) == p.faction:
			continue
		var node: Node2D = b["node"]
		var distance := node.global_position.distance_to(p.position)
		if distance > p.radius + float(b["radius"]):
			continue
		ranked.append({"node": node, "faction": b["faction"], "radius": b["radius"],
			"hash_id": b["hash_id"], "distance": distance})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a["distance"]), float(b["distance"])):
			return float(a["distance"]) < float(b["distance"])
		return int(a["hash_id"]) < int(b["hash_id"])
	)
	return ranked

func _kill(p: Projectile) -> void:
	if not _proj_meta.has(p.get_instance_id()):
		return
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
	var ranked: Array[Dictionary] = []
	for id: int in _bodies:
		var b: Dictionary = _bodies[id]
		if b["faction"] != faction:
			continue
		var to: Vector2 = b["node"].global_position - origin
		if to.length() > range_px + b["radius"]:
			continue
		if absf(angle_difference(facing, to.angle())) <= deg_to_rad(arc_deg) / 2.0:
			ranked.append({"node": b["node"], "distance": to.length(), "hash_id": b["hash_id"]})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a["distance"]), float(b["distance"])):
			return float(a["distance"]) < float(b["distance"])
		return int(a["hash_id"]) < int(b["hash_id"])
	)
	var out: Array = []
	for item: Dictionary in ranked:
		out.append(item["node"])
	return out

## 确定性的全向范围查询：距离优先，同距按 instance id；元素跳电/电解/毒火云共享。
func bodies_in_radius(origin: Vector2, range_px: float, faction: int, exclude: Node = null, limit: int = -1) -> Array:
	var ranked: Array[Dictionary] = []
	for id: int in _bodies:
		var b: Dictionary = _bodies[id]
		var node: Node2D = b["node"]
		if b["faction"] != faction or node == exclude or not is_instance_valid(node):
			continue
		var distance := node.global_position.distance_to(origin)
		if distance > range_px + float(b["radius"]):
			continue
		ranked.append({"node": node, "distance": distance, "id": node.get_instance_id()})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a["distance"]), float(b["distance"])):
			return float(a["distance"]) < float(b["distance"])
		return int(a["id"]) < int(b["id"])
	)
	var out: Array = []
	for item in ranked:
		out.append(item["node"])
		if limit > 0 and out.size() >= limit:
			break
	return out

## 燎原毒火云独立于触发目标存活：3 秒，每秒对 100px 内全部敌人造成 4 点。
func spawn_blaze_cloud(center: Vector2, now: int) -> void:
	_blaze_clouds.append({
		"center": center, "until": now + TimeConst.ticks(3.0),
		"next_tick": now + TimeConst.ticks(1.0),
	})

func tick_environment(now: int) -> void:
	_tick_blaze_clouds(now)

func _tick_blaze_clouds(now: int) -> void:
	for cloud in _blaze_clouds.duplicate():
		while now >= int(cloud["next_tick"]) and int(cloud["next_tick"]) <= int(cloud["until"]):
			for body in bodies_in_radius(cloud["center"], 100.0, Projectile.Faction.ENEMY):
				if body.get("state") == EnemyBase.State.DEAD:
					continue
				body.take_hit({
					"amount": 4, "is_crit": false, "element": Elements.Id.NONE, "from": cloud["center"],
					"source_type": "status", "source_id": "blaze", "source_name": "燎原",
					"attack_name": "毒火云",
					"player_damage": true,
				})
			cloud["next_tick"] = int(cloud["next_tick"]) + TimeConst.ticks(1.0)
		if now >= int(cloud["until"]):
			_blaze_clouds.erase(cloud)

func reflect(p: Projectile, new_damage: int) -> void:
	p.faction = Projectile.Faction.PLAYER
	p.vel = -p.vel
	p.damage = new_damage
	p.life_ticks = TimeConst.ticks(1.0)
	p.modulate = Color(1.0, 1.0, 0.4)

func block(p: Projectile) -> void:
	_kill(p)
