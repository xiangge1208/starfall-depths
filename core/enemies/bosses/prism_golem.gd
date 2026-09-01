class_name PrismGolem
extends BossBase
## 晶棱魔像（A2 Boss，附录 E.3，HP 1800）：P0 棱镜射线（EnemyLaser 直线激光，命中场内
## 晶柱即 45° 折射——复用 T7 折射组）/ 碎晶抛射（5 发抛物碎晶，落点 3s 晶刺区）；
## P1（60%）+三向扫描（3 束 120° 相隔激光 60°/s 旋转 3s）+ 晶柱再生（拆光后补满 2 根）；
## P2（30%）+瞬移弹幕（瞬移至玩家附近 160px + 环形 20 发，×3 次间隔 72t，分盐流确定）。
## 开战自带 2 根晶柱（可破坏掩体：登记折射组、吸收敌方弹、可藏柱后）。
## 招式序列状态机同 VineColossus；前摇 ≥24t（GDD §15）；数值逐字附录 E.3。

# ---- 前摇（GDD §15 下限 24t；数值逐字附录 E.3）----
const MIN_WINDUP_TICKS := 24
const RAY_WINDUP_TICKS := 36       # 0.6s
const SHARDS_WINDUP_TICKS := 30    # 0.5s
const SWEEP_WINDUP_TICKS := 48     # 0.8s
const REGEN_WINDUP_TICKS := 36     # 0.6s
const BLINK_WINDUP_TICKS := 30     # 0.5s

# ---- 棱镜射线（P0）：直线激光速 150（敌方弹速契约 ≤150 同口径），命中晶柱 45° 折射 ----
const RAY_SPEED_PX := 150.0

# ---- 碎晶抛射（P0）：前摇定 5 落点（玩家位为心 + 72px 十字预警），飞行 36t 落地伤 5，
#      落地生 3s 晶刺区（每 30t 5 伤）；晶刺区存续期占用招式位（同横扫行进语义）----
const SHARD_COUNT := 5
const SHARD_FLIGHT_TICKS := 36
const SHARD_SPREAD_PX := 72.0
const SHARD_DMG := 5
const SPIKE_PERIOD_TICKS := 30     # 0.5s/跳
const SPIKE_DURATION_TICKS := 180  # 3.0s
const SPIKE_RADIUS_PX := 26.0
const SHARDS_TOTAL_TICKS := SHARDS_WINDUP_TICKS + SHARD_FLIGHT_TICKS + SPIKE_DURATION_TICKS

# ---- 三向扫描（P1）：3 束相隔 120°，转速 60°/s = 1°/拍，持续 3s，伤 5 ----
const SWEEP_BEAM_COUNT := 3
const SWEEP_DURATION_TICKS := 180  # 3.0s
const SWEEP_ROTATE_DEG_PER_TICK := 1.0
const SWEEP_RANGE_PX := 280.0
const SWEEP_HIT_RADIUS_PX := 6.0   # 束心命中半径（同激光玩家判定圆口径）
const SWEEP_DMG := 5

# ---- 瞬移弹幕（P2）：前摇 30t → 瞬移（玩家附近 ≤160px）+ 环形 20 发，×3 次间隔 72t ----
const BLINK_RING_TIMES := 3
const BLINK_RING_COUNT := 20
const BLINK_INTERVAL_TICKS := 72   # 1.2s
const BLINK_MIN_DIST_PX := 48.0
const BLINK_MAX_DIST_PX := 160.0
const BLINK_RNG_SALT := "boss_prism_golem_blink"

# ---- 晶柱（开战自带 2 根；hp20 同柱陈设契约；±80px 对称落柱）----
const CRYSTAL_COUNT := 2
const CRYSTAL_OFFSET_PX := 80.0
const CRYSTAL_HP := 20
const CRYSTAL_ABSORB_RADIUS_PX := EnemyLaser.PILLAR_RADIUS_PX

# ---- 招式序列状态 ----
var _move := ""                     # 当前招式（"" = 选招中）
var _move_start := -1
var _seq_idx := 0                   # 招式表游标（跨阶段延续，入新阶段重置）
var _crystals: Array[Crystal] = []  # Crystal（失效/hp0 自动清）
var _ray_dir := Vector2.RIGHT       # 射线方向（前摇起始拍锁定）
var _shard_targets: Array[Vector2] = []
var _shards_landed := false               # 落地旗标（跳拍安全结算）
var _spike_zones: Array[Dictionary] = []   # {center, next, until}（背景结算：晶刺区跳）
var _sweep_base_angle := 0.0        # 扫描起始角（前摇起始拍锁定，rad）
var _sweep_angles: Array[float] = []       # 当前 3 束朝向（rad）
var _sweep_rotated_deg := 0.0
var _sweep_beams_hit: Array[bool] = []
var _blink_rings_fired := 0
var _blink_positions: Array[Vector2] = []  # 确定性断言面（同 seed 逐点一致）
var _blink_rng: RandomNumberGenerator = null
var _fx: Array[Node] = []           # 招式预警视觉（move 结束即清）
var _sweep_fx: Array[Node] = []     # 扫描束视觉（随束旋转，move 结束即清）


func _test_init(r: Dictionary) -> void:
	super(r)
	_blink_rng = RngSvc.stream(RunState.floor_idx, BLINK_RNG_SALT)


func setup(r: Dictionary) -> void:
	super(r)
	_blink_rng = RunState.stream(BLINK_RNG_SALT)


## EnemyFactory 直接构造 PrismGolem；BossBase._test_init 正常解析阶段。
## 守卫保留给手工构造后遗漏初始化的调试路径（同 VineColossus）。
func _ensure_phases() -> void:
	if _phase_thresholds.is_empty():
		_parse_phases(row)


## 进入 ENGAGE 转换拍：开战自带 2 根晶柱（附录 E.3「可藏柱后」阵地面）。
func _on_engage_start(_frame: int) -> void:
	_spawn_crystals()


func _engage(frame: int) -> void:
	_ensure_phases()
	_crystals_block_tick()                  # 晶柱挡弹为背景效果：跨招式持续结算
	_spike_tick(frame)                      # 晶刺区跳为背景效果：跨招式持续结算
	if _move == "":
		_start_move(_pick_move(), frame)
	_advance_move(frame)


## 阶段招式表（递增；regen 仅在晶柱残缺时登场——附录 E.3「补满晶柱」）。
func _move_list() -> Array[String]:
	var list: Array[String] = ["ray", "shards"]
	if phase() >= 1:
		list.append("sweep")
		if _alive_crystals() < CRYSTAL_COUNT:
			list.append("regen")
	if phase() >= 2:
		list.append("blink")
	return list


func _pick_move() -> String:
	var list := _move_list()
	var m: String = list[_seq_idx % list.size()]
	_seq_idx += 1
	return m


func _on_phase_enter(_phase_idx: int) -> void:
	_seq_idx = 0                            # 换阶段重开序列


func die() -> void:
	_despawn_crystals()
	super()                                 # EnemyBase.die：状态门/死亡爆/信号/退场


# ---- 招式状态机 ----

func _start_move(m: String, frame: int) -> void:
	_move = m
	_move_start = frame
	_blink_rings_fired = 0
	_shards_landed = false
	Fx.on_enemy_hit(self, {"telegraph": true})   # 前摇进入拍红闪预警（同 shooter/charger/vine）
	match m:
		"ray":
			_ray_dir = _locked_dir()         # 方向前摇起始拍锁定
			_fx_beam_line(_ray_dir, 200.0)
		"shards":
			_shard_targets = _generate_shard_targets()
			for t in _shard_targets:
				_fx_circle(t, SPIKE_RADIUS_PX)
		"sweep":
			_sweep_base_angle = _aim_at_player()   # 起始角即瞄准角（前摇起始拍锁定）
			_sweep_angles.clear()
			_sweep_rotated_deg = 0.0
			_sweep_beams_hit.clear()
		"regen":
			pass                             # 补柱预警由柱体生成时的视觉承载
		"blink":
			pass                             # 瞬移无地面预警（红闪已示）
		_:
			pass


func _advance_move(frame: int) -> void:
	var elapsed := frame - _move_start
	match _move:
		"ray":
			if elapsed >= RAY_WINDUP_TICKS:
				_ray_fire()
				_end_move()
		"shards":
			# 落地拍用旗标而非 ==：冰缓/冻结跳拍时仍能结算（>= 首个未跳过拍）
			if elapsed >= SHARDS_WINDUP_TICKS + SHARD_FLIGHT_TICKS and not _shards_landed:
				_shards_landed = true
				_shards_land(frame)
			if elapsed >= SHARDS_TOTAL_TICKS:
				_end_move()                  # 晶刺区（3s）随招式位收尾到期
		"sweep":
			var t := elapsed - SWEEP_WINDUP_TICKS
			if t >= 0:
				if _sweep_angles.is_empty():
					_sweep_activate()        # 激活拍：起始角正对者即结算一跳
				else:
					_sweep_rotate()          # 60°/s = 1°/拍
			if elapsed >= SWEEP_WINDUP_TICKS + SWEEP_DURATION_TICKS:
				_end_move()
		"regen":
			if elapsed >= REGEN_WINDUP_TICKS:
				_spawn_crystals()
				_end_move()
		"blink":
			while _blink_rings_fired < BLINK_RING_TIMES \
					and elapsed >= BLINK_WINDUP_TICKS + _blink_rings_fired * BLINK_INTERVAL_TICKS:
				_blink_step()
				_blink_rings_fired += 1
			if _blink_rings_fired >= BLINK_RING_TIMES:
				_end_move()
		_:
			pass


func _end_move() -> void:
	_move = ""
	_move_start = -1
	_fx_clear()


# ---- 棱镜射线 ----

## 前摇 36t 发 EnemyLaser（复用 T7）：注入自有晶柱折射源与房内域；
## 激光生命在组件内自驱（树内 _physics_process / 测试直呼 tick）。
func _ray_fire() -> void:
	fired_this_tick = true
	var laser := EnemyLaser.new()
	laser.setup({
		"pos": brain_pos, "dir": _ray_dir,
		"damage": int(row.get("bullet_dmg", 5)),
		"speed_px": RAY_SPEED_PX,
		"life_ticks": EnemyLaser.DEFAULT_LIFE_TICKS,
		"bounds": combat_bounds,
		"pillars": _alive_crystal_positions(),
		"player": player_ref,
		"source_id": String(row.get("id", "")),
		"source_name": String(row.get("name", row.get("id", ""))),
		"attack_name": "棱镜射线",
	})
	add_child(laser)


# ---- 碎晶抛射 ----

## 招式起始拍定 5 落点（玩家位为心 + 72px 十字），红圈预警前摇 + 飞行全程。
## 出界侧目标优先翻转到对侧（保持 72px 落点距离，不因夹边贴到玩家脸上），末端仍夹进内域。
func _generate_shard_targets() -> Array[Vector2]:
	var center := _player_pos()
	var targets: Array[Vector2] = [center]
	for i in range(1, SHARD_COUNT):
		var off := Vector2.from_angle(deg_to_rad(90.0 * float(i))) * SHARD_SPREAD_PX
		var pos := center + off
		if combat_bounds.has_area() and not combat_bounds.grow(-4.0).has_point(pos) \
				and combat_bounds.grow(-4.0).has_point(center - off):
			pos = center - off
		targets.append(_clamp_to_bounds(pos))
	return targets


## 落地拍：圆内玩家结算碎晶伤，并登记晶刺区（落地 +30t 起每 30t 一跳，共 3s）。
func _shards_land(frame: int) -> void:
	for t in _shard_targets:
		if player_ref != null and _player_pos().distance_to(t) <= SPIKE_RADIUS_PX:
			_hit_player(SHARD_DMG, {"attack_name": "碎晶抛射"})
		_spike_zones.append({
			"center": t,
			"next": frame + SPIKE_PERIOD_TICKS,
			"until": frame + SPIKE_DURATION_TICKS,
		})


## 晶刺区背景结算：区内存续期每 30t 对区内玩家跳 5 伤，过期（3s）即清。
func _spike_tick(frame: int) -> void:
	if _spike_zones.is_empty():
		return
	for zone in _spike_zones:
		while frame >= int(zone["next"]) and int(zone["next"]) <= int(zone["until"]):
			if player_ref != null and _player_pos().distance_to(zone["center"]) <= SPIKE_RADIUS_PX:
				_hit_player(SHARD_DMG, {"attack_name": "晶刺区"})
			zone["next"] = int(zone["next"]) + SPIKE_PERIOD_TICKS
	for i in range(_spike_zones.size() - 1, -1, -1):
		if frame > int(_spike_zones[i]["until"]):
			_spike_zones.remove_at(i)


# ---- 三向扫描 ----

## 激活拍：3 束相隔 120°（起始角即瞄准角），正对玩家者结算一跳；此后每拍旋转 1°。
func _sweep_activate() -> void:
	_sweep_angles.clear()
	_sweep_beams_hit.clear()
	for k in range(SWEEP_BEAM_COUNT):
		_sweep_angles.append(_sweep_base_angle + deg_to_rad(120.0 * float(k)))
		_sweep_beams_hit.append(false)
	for k in range(SWEEP_BEAM_COUNT):
		_sweep_fx.append(_fx_beam_rotor(_sweep_angles[k]))
	_sweep_hit_check()


func _sweep_rotate() -> void:
	_sweep_rotated_deg += SWEEP_ROTATE_DEG_PER_TICK
	for k in range(SWEEP_BEAM_COUNT):
		_sweep_angles[k] = _sweep_base_angle + deg_to_rad(_sweep_rotated_deg + 120.0 * float(k))
	for i in mini(_sweep_fx.size(), _sweep_angles.size()):
		if is_instance_valid(_sweep_fx[i]):
			_sweep_fx[i].rotation = _sweep_angles[i]
	_sweep_hit_check()


## 束命中：每束每次扫描至多一跳（束心距 ≤6px、射程内），命中后本束标记完成。
func _sweep_hit_check() -> void:
	if player_ref == null or not player_ref.has_method("take_hit"):
		return
	var to := _player_pos() - brain_pos
	var dist := to.length()
	if dist < 0.01 or dist > SWEEP_RANGE_PX:
		return
	for k in range(SWEEP_BEAM_COUNT):
		if _sweep_beams_hit[k]:
			continue
		var off_axis := absf(angle_difference(_sweep_angles[k], to.angle())) * dist
		if off_axis <= SWEEP_HIT_RADIUS_PX:
			_sweep_beams_hit[k] = true
			_hit_player(SWEEP_DMG, {"attack_name": "三向扫描"})


# ---- 晶柱再生 / 晶柱阵面 ----

func _spawn_crystals() -> void:
	_prune_crystals()
	for i in range(CRYSTAL_COUNT - _crystals.size()):
		var side := 1.0 if (i % 2 == 0) else -1.0
		var pos := _clamp_to_bounds(brain_pos + Vector2(CRYSTAL_OFFSET_PX * side, 0.0))
		var crystal := Crystal.new()
		crystal.setup(pos, CRYSTAL_HP, combat)   # m2-t36：可破坏战斗体接线（T14 移交）
		add_child(crystal)
		_crystals.append(crystal)


func _alive_crystals() -> int:
	_prune_crystals()
	return _crystals.size()


func _alive_crystal_positions() -> Array:
	_prune_crystals()
	var out: Array = []
	for c in _crystals:
		out.append(c.pos_world)
	return out


func _prune_crystals() -> void:
	for i in range(_crystals.size() - 1, -1, -1):
		var c := _crystals[i]
		if not is_instance_valid(c) or c.hp <= 0:
			_crystals.remove_at(i)


## 晶柱挡弹（背景结算）：吸收近柱敌方弹（玩家弹不受影响——晶柱对玩家是可拆掩体）。
func _crystals_block_tick() -> void:
	if combat == null or _crystals.is_empty():
		return
	_prune_crystals()
	for c in _crystals:
		for proj in combat.pool.active.duplicate():
			if proj.faction != Projectile.Faction.ENEMY:
				continue
			if c.pos_world.distance_to(proj.position) <= CRYSTAL_ABSORB_RADIUS_PX + proj.radius:
				combat.block(proj)


func _despawn_crystals() -> void:
	for c in _crystals:
		if is_instance_valid(c):
			c.despawn()
	_crystals.clear()


# ---- 瞬移弹幕 ----

## 瞬移（玩家附近 ≤160px、夹进房内域）+ 环形 20 发；分盐流确定（同 seed 逐点一致）。
func _blink_step() -> void:
	var a := _blink_rng.randf_range(0.0, TAU)
	var r := _blink_rng.randf_range(BLINK_MIN_DIST_PX, BLINK_MAX_DIST_PX)
	var offset := Vector2.from_angle(a) * r
	# 记录夹边前的原始瞬移向量（分盐流确定断言面；实际落点 = 玩家位 + 向量再夹进内域）
	_blink_positions.append(offset)
	brain_pos = _clamp_to_bounds(_player_pos() + offset, 9.0)
	_blink_ring_fire()


func _blink_ring_fire() -> void:
	fired_this_tick = true
	if combat == null:
		return
	var speed := enemy_bullet_speed(100)
	for i in range(BLINK_RING_COUNT):
		var a := TAU * float(i) / float(BLINK_RING_COUNT)
		combat.spawn_projectile({
			"pos": brain_pos, "vel": Vector2.from_angle(a) * speed,
			"damage": int(row.get("bullet_dmg", 5)), "faction": Projectile.Faction.ENEMY,
			"element": Elements.Id.NONE, "pierce": 0, "bounce": 0,
			"life_seconds": float(row.get("bullet_life_seconds", 2.0)),
			"radius": float(row.get("bullet_radius", 4.0)),
			"source_type": "projectile", "source_id": String(row.get("id", "")),
			"source_name": String(row.get("name", row.get("id", ""))), "attack_name": "瞬移弹幕",
		})


# ---- 共用 helpers ----

func _aim_at_player() -> float:
	return (_player_pos() - brain_pos).angle()


## 锁定方向：前摇期间不跟踪。零向量安全退化向 +x。
func _locked_dir() -> Vector2:
	var to := _player_pos() - brain_pos
	return to.normalized() if to.length() > 0.01 else Vector2.RIGHT


func _clamp_to_bounds(pos: Vector2, inset := 4.0) -> Vector2:
	if combat_bounds.has_area():
		var legal := combat_bounds.grow(-inset)
		return pos.clamp(legal.position, legal.end)
	return pos


# ---- 玩家结算（同 VineColossus）----

func _hit_player(dmg: int, extra: Dictionary) -> void:
	if player_ref == null or not player_ref.has_method("take_hit"):
		return
	var ctx := {
		"amount": dmg, "is_crit": false, "element": Elements.Id.NONE, "from": brain_pos,
		"source_type": "boss", "source_id": String(row.get("id", "prism_golem")),
		"source_name": String(row.get("name", "晶棱魔像")), "attack_name": "攻击",
	}
	ctx.merge(extra, true)
	player_ref.take_hit(ctx)


# ---- 预警视觉（脑层挂子节点，测试无树亦安全；同 VineColossus 手法）----

func _fx_beam_line(dir: Vector2, length_px: float) -> void:
	var vis := _beam_poly(length_px)
	vis.rotation = dir.angle()
	add_child(vis)
	_fx.append(vis)


## 扫描束：锚在 boss 位（显示镜像减 brain_pos），绕锚旋转。
func _fx_beam_rotor(angle_rad: float) -> Polygon2D:
	var vis := _beam_poly(SWEEP_RANGE_PX)
	vis.rotation = angle_rad
	add_child(vis)
	return vis


func _beam_poly(length_px: float) -> Polygon2D:
	var vis := Polygon2D.new()
	var w := 3.0
	vis.polygon = PackedVector2Array([
		Vector2(0, -w), Vector2(length_px, -w), Vector2(length_px, w), Vector2(0, w),
	])
	vis.color = Color(1.0, 0.25, 0.2, 0.3)
	vis.z_index = 15
	return vis


func _fx_circle(center: Vector2, radius: float) -> void:
	var pts := PackedVector2Array()
	for i in range(20):
		pts.append(Vector2.from_angle(TAU * float(i) / 20.0) * radius)
	var vis := Polygon2D.new()
	vis.polygon = pts
	vis.color = Color(1.0, 0.25, 0.2, 0.3)
	vis.z_index = 15
	vis.position = center - brain_pos
	add_child(vis)
	_fx.append(vis)


func _fx_clear() -> void:
	for node in _fx:
		if is_instance_valid(node):
			node.queue_free()
	_fx.clear()
	for node in _sweep_fx:
		if is_instance_valid(node):
			node.queue_free()
	_sweep_fx.clear()


## 晶柱（脑层轻量实体）：顶层挂载（top_level——出生坐标即世界坐标，魔像瞬移/位移不
## 拖动晶柱；修 T14 移交的空间错位）；登记 EnemyLaser 折射组（与 FloorScene 晶柱同组
## 同语义）+ CombatSystem 战斗体（register_body/combat_radius——玩家弹/近战可拆柱，
## 拆柱→regen 补柱博弈环闭环）；hp 归零即失效退场并注销战斗体；Boss 死亡随行清场。
class Crystal extends Node2D:
	var pos_world := Vector2.ZERO
	var hp := 0
	var combat: CombatSystem = null

	func setup(p: Vector2, hp_value: int, combat_system: CombatSystem = null) -> void:
		pos_world = p
		hp = hp_value
		top_level = true                # m2-t36：出生位 = 世界坐标（不受 Boss 变换拖动）
		position = p
		combat = combat_system
		if combat != null:
			combat.register_body(self, Projectile.Faction.ENEMY)   # m2-t36：玩家弹可拆柱
		add_to_group(EnemyLaser.PILLAR_GROUP)
		var vis := Polygon2D.new()
		var pts := PackedVector2Array()
		for i in range(4):
			var a := TAU * float(i) / 4.0 + TAU / 8.0
			pts.append(Vector2.from_angle(a) * EnemyLaser.PILLAR_RADIUS_PX)
		vis.polygon = pts
		vis.color = Color(0.55, 0.85, 0.95, 0.9)
		vis.z_index = 12
		add_child(vis)

	## m2-t36：CombatSystem 战斗体半径契约（同 EnemyBase.combat_radius 口径）。
	func combat_radius() -> float:
		return EnemyLaser.PILLAR_RADIUS_PX

	func take_hit(ctx: Dictionary) -> void:
		if hp <= 0:
			return
		hp = maxi(hp - int(ctx["amount"]), 0)
		if hp == 0:
			despawn()

	func despawn() -> void:
		hp = 0
		if combat != null:
			combat.unregister_body(self)   # m2-t36：退场即注销战斗体（哈希不泄漏）
			combat = null
		if is_inside_tree():
			remove_from_group(EnemyLaser.PILLAR_GROUP)
		queue_free()
