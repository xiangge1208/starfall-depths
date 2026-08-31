class_name GemQueen
extends BossBase
## 宝石蜂后（A1 Boss，附录 E.2，HP 800）：P0 蜂群扇弹（8 发扇形×3 轮）/ 俯冲（锁定方向直冲）；
## P1（60%）+蜂巢柱（2 根可破坏掩体，登记折射组、吸收敌方弹）+ 环形爆蜂（16 发、每 90° 缺口）；
## P2（30%）+狂暴三连冲（三段俯冲连击，段间再瞄准，末段自晕 1.2s 给玩家输出窗）。
## 招式序列状态机同 VineColossus：_engage 按 phase() 选招表，招式背靠背；前摇 ≥24t（GDD §15）。
## 俯冲/连冲方向在前摇起始拍（连冲为段间末拍）锁定——侧移即落空（预警可读性）。

# ---- 前摇（GDD §15 下限 24t = TimeConst.ticks(0.4)；数值逐字附录 E.2）----
const MIN_WINDUP_TICKS := 24
const FAN_WINDUP_TICKS := 30        # 0.5s
const DIVE_WINDUP_TICKS := 36       # 0.6s
const HIVE_WINDUP_TICKS := 48       # 0.8s
const RING_WINDUP_TICKS := 36       # 0.6s
const RAMPAGE_WINDUP_TICKS := 30    # 0.5s

# ---- 蜂群扇弹（P0）：8 发扇形 ×3 轮（24t 间隔），弹伤 3 弹速 110（行数据）----
const FAN_WAVES := 3
const FAN_PER_WAVE := 8
const FAN_WAVE_GAP_TICKS := 24
const FAN_SPREAD_DEG := 60.0

# ---- 俯冲（P0）：沿锁定方向直冲 30t@220px/s（110px 冲程），接触伤 6 恰一跳 ----
const DIVE_SPEED_PX := 220.0
const DIVE_TICKS := 30
const DIVE_DMG := 6

# ---- 蜂巢柱（P1）：2 根可破坏掩体（hp20 同柱陈设契约），±48px 对称落柱，
#      登记 EnemyLaser 折射组 + 每拍吸收近柱敌方弹（玩家弹不受影响，可拆柱）----
const HIVE_COUNT := 2
const HIVE_OFFSET_PX := 48.0
const HIVE_PILLAR_HP := 20
const PILLAR_ABSORB_RADIUS_PX := EnemyLaser.PILLAR_RADIUS_PX

# ---- 环形爆蜂（P1）：16 发环形，每 90° 象限留 ≥15° 缺口（象限内 18/36/54/72° 均布）----
const RING_COUNT := 16
const RING_PER_QUAD := 4
const RING_GAP_DEG := 18.0

# ---- 狂暴三连冲（P2）：前摇 30t → 三段各 24t 冲程（段间 12t 再瞄准），每段伤 6 恰一跳，
#      末段收尾自晕 1.2s（72t）——晕内 brain 空转（EnemyBase.stun_until 既有语义）----
const RAMPAGE_CHARGES := 3
const RAMPAGE_SEG_TICKS := 24
const RAMPAGE_GAP_TICKS := 12
const RAMPAGE_DMG := 6
const RAMPAGE_STUN_TICKS := 72      # 1.2s（TimeConst.ticks(1.2)）
const RAMPAGE_TOTAL_TICKS := RAMPAGE_WINDUP_TICKS \
	+ RAMPAGE_CHARGES * RAMPAGE_SEG_TICKS + (RAMPAGE_CHARGES - 1) * RAMPAGE_GAP_TICKS   # 126

# ---- 招式序列状态 ----
var _move := ""                     # 当前招式（"" = 选招中）
var _move_start := -1
var _seq_idx := 0                   # 招式表游标（跨阶段延续，入新阶段重置）
var _pillars: Array[HivePillar] = []   # HivePillar（失效/hp0 自动清）
var _fan_facing := 0.0              # 扇弹朝向（前摇起始拍锁定）
var _fan_waves_fired := 0
var _dive_dir := Vector2.RIGHT      # 俯冲/当前冲段方向（前摇起始拍/段间末拍锁定）
var _dive_hit_done := false         # 本次冲段已结算一跳
var _fx: Array[Node] = []           # 招式预警视觉（move 结束即清）


func _test_init(r: Dictionary) -> void:
	super(r)


func setup(r: Dictionary) -> void:
	super(r)


## EnemyFactory 直接构造 GemQueen；BossBase._test_init 正常解析阶段。
## 守卫保留给手工构造后遗漏初始化的调试路径（同 VineColossus）。
func _ensure_phases() -> void:
	if _phase_thresholds.is_empty():
		_parse_phases(row)


func _engage(frame: int) -> void:
	_ensure_phases()
	_pillars_block_tick()                   # 掩体挡弹为背景效果：跨招式持续结算
	if _move == "":
		_start_move(_pick_move(), frame)
	_advance_move(frame)


## 阶段招式表（递增：P2 含 P0/P1 全部，狂暴连冲居首——入 P2 立即惩罚压近；
## P1 蜂巢柱/环形爆蜂居前——掩体先落地，先于扇弹建立「可藏柱后」博弈面）。
## 入新阶段游标归零（新招尽快登场）。
func _move_list() -> Array[String]:
	match phase():
		0:
			return ["fan", "dive"]
		1:
			return ["hive", "ring", "fan", "dive"]
		_:
			return ["rampage", "hive", "ring", "fan", "dive"]


func _pick_move() -> String:
	var list := _move_list()
	for _attempt in list.size():
		var m: String = list[_seq_idx % list.size()]
		_seq_idx += 1
		if m == "hive" and _alive_pillars() >= HIVE_COUNT:
			continue                        # 2 根存活期内 hive 不入序列
		return m
	return list[0]


func _on_phase_enter(_phase_idx: int) -> void:
	_seq_idx = 0                            # 换阶段重开序列


func die() -> void:
	_despawn_pillars()
	super()                                 # EnemyBase.die：状态门/死亡爆/信号/退场


# ---- 招式状态机 ----

func _start_move(m: String, frame: int) -> void:
	_move = m
	_move_start = frame
	_fan_waves_fired = 0
	_dive_hit_done = false
	Fx.on_enemy_hit(self, {"telegraph": true})   # 前摇进入拍红闪预警（同 shooter/charger/vine）
	match m:
		"fan":
			_fan_facing = _aim_at_player()   # 朝向前摇起始拍锁定
			_fx_wedge(FAN_SPREAD_DEG)
		"dive":
			_dive_dir = _locked_dir()
			_fx_dash_line(_dive_dir, DIVE_SPEED_PX / TimeConst.FPS * float(DIVE_TICKS))
		"rampage":
			_dive_dir = _locked_dir()        # 首段方向前摇锁定；段间末拍再瞄准
			_fx_dash_line(_dive_dir, DIVE_SPEED_PX / TimeConst.FPS * float(RAMPAGE_SEG_TICKS))
		"ring":
			pass                             # 全向弹幕：红闪已示，无地面预警
		"hive":
			pass                             # 落柱预警由柱体生成时的视觉承载
		_:
			pass


func _advance_move(frame: int) -> void:
	var elapsed := frame - _move_start
	match _move:
		"fan":
			while _fan_waves_fired < FAN_WAVES \
					and elapsed >= FAN_WINDUP_TICKS + _fan_waves_fired * FAN_WAVE_GAP_TICKS:
				_fan_fire_wave()
				_fan_waves_fired += 1
			if _fan_waves_fired >= FAN_WAVES:
				_end_move()
		"dive":
			if elapsed >= DIVE_WINDUP_TICKS and elapsed < DIVE_WINDUP_TICKS + DIVE_TICKS:
				_dash_step(_dive_dir, DIVE_SPEED_PX)
				_dive_hit_check(DIVE_DMG, "俯冲")
			if elapsed >= DIVE_WINDUP_TICKS + DIVE_TICKS:
				_end_move()
		"rampage":
			_rampage_advance(elapsed, frame)
		"ring":
			if elapsed >= RING_WINDUP_TICKS:
				_ring_fire()
				_end_move()
		"hive":
			if elapsed >= HIVE_WINDUP_TICKS:
				_hive_resolve()
				_end_move()
		_:
			pass


func _end_move() -> void:
	_move = ""
	_move_start = -1
	_fx_clear()


## 狂暴连冲拍序：前摇 [0,30) → 段 k 移动 [30+36k, 54+36k) → 段间 12t（末拍 off=35 再瞄准）；
## 第 3 段收尾拍（elapsed 126）自晕 72t、招式位清空（晕内 brain 空转）。
func _rampage_advance(elapsed: int, frame: int) -> void:
	if elapsed >= RAMPAGE_TOTAL_TICKS:
		_end_move()
		stun_until = maxi(stun_until, frame + RAMPAGE_STUN_TICKS)   # 末段撞墙自晕 1.2s
		return
	var t := elapsed - RAMPAGE_WINDUP_TICKS
	if t < 0:
		return                              # 前摇中
	var cycle := RAMPAGE_SEG_TICKS + RAMPAGE_GAP_TICKS
	var seg_idx := t / cycle
	var phase_off := t % cycle
	if phase_off < RAMPAGE_SEG_TICKS:
		_dash_step(_dive_dir, DIVE_SPEED_PX)
		_dive_hit_check(RAMPAGE_DMG, "狂暴连冲")
	elif phase_off == RAMPAGE_SEG_TICKS + RAMPAGE_GAP_TICKS - 1 \
			and seg_idx + 1 < RAMPAGE_CHARGES:
		_dive_hit_done = false              # 新段重新允许恰一跳
		_dive_dir = _locked_dir()           # 段间末拍再瞄准（下拍段首即冲）


# ---- 蜂群扇弹 ----

func _fan_fire_wave() -> void:
	fired_this_tick = true
	if combat == null:
		return
	var speed := float(row.get("bullet_speed", 110))
	for i in range(FAN_PER_WAVE):
		var off := deg_to_rad(FAN_SPREAD_DEG) * (float(i) / float(FAN_PER_WAVE - 1) - 0.5)
		combat.spawn_projectile({
			"pos": brain_pos, "vel": Vector2.from_angle(_fan_facing + off) * speed,
			"damage": int(row.get("bullet_dmg", 3)), "faction": Projectile.Faction.ENEMY,
			"element": Elements.Id.NONE, "pierce": 0, "bounce": 0,
			"life_seconds": float(row.get("bullet_life_seconds", 2.5)),
			"radius": float(row.get("bullet_radius", 3.0)),
			"source_type": "projectile", "source_id": String(row.get("id", "")),
			"source_name": String(row.get("name", row.get("id", ""))), "attack_name": "蜂群扇弹",
		})


# ---- 环形爆蜂 ----

func _ring_fire() -> void:
	fired_this_tick = true
	if combat == null:
		return
	var speed := float(row.get("bullet_speed", 110))
	for q in range(4):
		for k in range(RING_PER_QUAD):
			# 象限内 18°/36°/54°/72° 均布：距 90° 缺口心最近 18°（≥15° 缺口约束）
			var a := deg_to_rad(90.0 * float(q) + RING_GAP_DEG * (float(k) + 1.0))
			combat.spawn_projectile({
				"pos": brain_pos, "vel": Vector2.from_angle(a) * speed,
				"damage": int(row.get("bullet_dmg", 3)), "faction": Projectile.Faction.ENEMY,
				"element": Elements.Id.NONE, "pierce": 0, "bounce": 0,
				"life_seconds": float(row.get("bullet_life_seconds", 2.5)),
				"radius": float(row.get("bullet_radius", 3.0)),
				"source_type": "projectile", "source_id": String(row.get("id", "")),
				"source_name": String(row.get("name", row.get("id", ""))), "attack_name": "环形爆蜂",
			})


# ---- 蜂巢柱 ----

func _hive_resolve() -> void:
	_prune_pillars()
	for i in range(HIVE_COUNT - _pillars.size()):
		var side := 1.0 if (i % 2 == 0) else -1.0
		var pos := _clamp_to_bounds(brain_pos + Vector2(HIVE_OFFSET_PX * side, 0.0))
		var pillar := HivePillar.new()
		pillar.setup(pos, HIVE_PILLAR_HP)
		add_child(pillar)
		_pillars.append(pillar)


func _alive_pillars() -> int:
	_prune_pillars()
	return _pillars.size()


func _prune_pillars() -> void:
	for i in range(_pillars.size() - 1, -1, -1):
		var p := _pillars[i]
		if not is_instance_valid(p) or p.hp <= 0:
			_pillars.remove_at(i)


## 掩体挡弹（背景结算）：吸收近柱敌方弹（玩家弹不受影响——掩体对玩家是可拆掩体，
## 对 Boss 弹幕是障碍，敌我博弈核心）。复用 CombatSystem.block 统一退场路径。
func _pillars_block_tick() -> void:
	if combat == null or _pillars.is_empty():
		return
	_prune_pillars()
	for p in _pillars:
		for proj in combat.pool.active.duplicate():
			if proj.faction != Projectile.Faction.ENEMY:
				continue
			if p.pos_world.distance_to(proj.position) <= PILLAR_ABSORB_RADIUS_PX + proj.radius:
				combat.block(proj)


func _despawn_pillars() -> void:
	for p in _pillars:
		if is_instance_valid(p):
			p.despawn()
	_pillars.clear()


# ---- 俯冲 / 连冲共用 ----

## 直冲一步（220px/s = DIVE_SPEED_PX/60 px/拍）并夹进房内域。
func _dash_step(dir: Vector2, speed_px: float) -> void:
	brain_pos = _clamp_to_bounds(brain_pos + dir.normalized() * (speed_px / TimeConst.FPS))


## 冲线命中：圆接触（战斗半径 + 6px 同接触冲撞口径）每段恰一跳。
func _dive_hit_check(dmg: int, attack: String) -> void:
	if _dive_hit_done:
		return
	if player_ref == null or not player_ref.has_method("take_hit"):
		return
	if _player_pos().distance_to(brain_pos) > combat_radius() + 6.0:
		return
	_dive_hit_done = true
	_hit_player(dmg, {"attack_name": attack})


func _aim_at_player() -> float:
	return (_player_pos() - brain_pos).angle()


## 锁定方向：前摇期间不跟踪（侧移即落空）。零向量安全退化向 +x。
func _locked_dir() -> Vector2:
	var to := _player_pos() - brain_pos
	return to.normalized() if to.length() > 0.01 else Vector2.RIGHT


func _clamp_to_bounds(pos: Vector2) -> Vector2:
	if combat_bounds.has_area():
		var legal := combat_bounds.grow(-4.0)
		return pos.clamp(legal.position, legal.end)
	return pos


# ---- 玩家结算（同 VineColossus）----

func _hit_player(dmg: int, extra: Dictionary) -> void:
	if player_ref == null or not player_ref.has_method("take_hit"):
		return
	var ctx := {
		"amount": dmg, "is_crit": false, "element": Elements.Id.NONE, "from": brain_pos,
		"source_type": "boss", "source_id": String(row.get("id", "gem_queen")),
		"source_name": String(row.get("name", "宝石蜂后")), "attack_name": "攻击",
	}
	ctx.merge(extra, true)
	player_ref.take_hit(ctx)


# ---- 预警视觉（脑层挂子节点，测试无树亦安全；同 VineColossus 手法）----

func _fx_wedge(arc_deg: float) -> void:
	var pts := PackedVector2Array([Vector2.ZERO])
	var radius := 110.0
	var n := 12
	for i in range(n + 1):
		var a := _fan_facing + deg_to_rad(arc_deg) * (float(i) / float(n) - 0.5)
		pts.append(Vector2.from_angle(a) * radius)
	var vis := Polygon2D.new()
	vis.polygon = pts
	vis.color = Color(1.0, 0.25, 0.2, 0.35)
	vis.z_index = 15
	add_child(vis)
	_fx.append(vis)


func _fx_dash_line(dir: Vector2, length_px: float) -> void:
	var vis := Polygon2D.new()
	var w := 10.0
	var d := dir.normalized()
	var n := d.orthogonal()
	vis.polygon = PackedVector2Array([
		Vector2.ZERO + n * w, d * length_px + n * w, d * length_px - n * w, Vector2.ZERO - n * w,
	])
	vis.color = Color(1.0, 0.25, 0.2, 0.25)
	vis.z_index = 15
	add_child(vis)
	_fx.append(vis)


func _fx_clear() -> void:
	for node in _fx:
		if is_instance_valid(node):
			node.queue_free()
	_fx.clear()


## 蜂巢掩体柱（脑层轻量实体）：登记 EnemyLaser 折射组（与 FloorScene 晶柱同组同语义），
## hp 归零即失效退场；Boss 死亡随行清场。
class HivePillar extends Node2D:
	var pos_world := Vector2.ZERO
	var hp := 0

	func setup(p: Vector2, hp_value: int) -> void:
		pos_world = p
		hp = hp_value
		position = p
		add_to_group(EnemyLaser.PILLAR_GROUP)
		var vis := Polygon2D.new()
		var pts := PackedVector2Array()
		for i in range(6):
			pts.append(Vector2.from_angle(TAU * float(i) / 6.0) * EnemyLaser.PILLAR_RADIUS_PX)
		vis.polygon = pts
		vis.color = Color(0.95, 0.75, 0.2, 0.9)
		vis.z_index = 12
		add_child(vis)

	func take_hit(ctx: Dictionary) -> void:
		if hp <= 0:
			return
		hp = maxi(hp - int(ctx["amount"]), 0)
		if hp == 0:
			despawn()

	func despawn() -> void:
		hp = 0
		if is_inside_tree():
			remove_from_group(EnemyLaser.PILLAR_GROUP)
		queue_free()
