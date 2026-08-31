class_name FrostWidow
extends BossBase
## 寒渊蛛母（A2 Boss，附录 E.4，HP 1800）：P0 冰面铺设（房间 40% 变冰面，复用 T4 IceZone）
## / 蛛网禁锢（3 张落点网，落地 24t 后仍在网心 → 伤 4 + 禁锢 1s；离开落点即网未触发）；
## P1（60%）+ 螺旋弹幕（双臂 180° 相位螺旋持续 4s，弹伤 5 弹速 100）+ 召唤冰蛛×3（cap 3）；
## P2（30%）+ 冰晶牢笼（玩家周围 9 环位落 8 根冰柱留 1 缺口，短命 3s；m2-t36 机制化：
## 柱环 restraint 禁锢——环内玩家越环按缺口弧段判定，缺口可通行）
## + 全屏冰刺阵（8 泳道中 2 条缝隙安全线，其余泳道 5 伤）。
## 招式序列状态机同 VineColossus/GemQueen：_engage 按 phase() 选招表，招式背靠背；
## 所有前摇 ≥24t（GDD §15）；预警视觉红圈（蛛网/牢笼）+ 蓝纹（冰面带/冰刺泳道）齐备。
## 禁锢表现（锚定玩家 brain_pos 于网心 ±6px）沿用 VineColossus 拍击击退的披露口径：
## 脑层直接写 player_ref.brain_pos，真实 PlayerProxy 每帧镜像覆盖——玩家侧卡身表现归
## 表现层接线（本任务报告披露）。冰面数据经 ice_zone 注入接口写入（见 ice_zone 声明）。

# ---- 前摇（GDD §15 下限 24t；数值逐字附录 E.4）----
const MIN_WINDUP_TICKS := 24
const CARPET_WINDUP_TICKS := 30       # 0.5s（E.4 冰面铺设）
const WEBS_WINDUP_TICKS := 36         # 0.6s（E.4 蛛网禁锢）
const SPIRAL_WINDUP_TICKS := 42       # 0.7s（E.4 螺旋弹幕）
const SUMMON_WINDUP_TICKS := 48       # 0.8s（E.4 召唤冰蛛）
const CAGE_WINDUP_TICKS := 54         # 0.9s（E.4 冰晶牢笼；P3 合并行拆两招，冰刺阵共用前摇口径见下）
const SPIKES_WINDUP_TICKS := 36       # 0.6s（E.4 未单列，≥24t 规范内取值，报告披露）

# ---- 冰面铺设（P0）：内域横带 5 分取 2 带 = 恰 40% 面积，一场一次 ----
const CARPET_BANDS := 5
const CARPET_ICE_BANDS := [1, 3]

# ---- 蛛网禁锢（P0）：3 张落点网；落地 24t（0.4s）后仍在网心 18px 内 → 伤 4 + 禁锢 60t ----
const WEB_COUNT := 3
const WEB_TRIGGER_DELAY_TICKS := 24   # 落地后 0.4s 预警窗（红圈），离开落点即打断
const WEB_RADIUS_PX := 18.0
const WEB_SPREAD_PX := 60.0
const WEB_DMG := 4
const RESTRAIN_TICKS := 60            # 1s（TimeConst.ticks(1.0)）
const RESTRAIN_SLACK_PX := 6.0

# ---- 螺旋弹幕（P1）：双臂 180° 相位，持续 4s，每 3t 一轮；转速 45°/s（每轮 2.25°，
#      4s 恰扫满半圆——mod π 无重向，螺旋面连续无缝）----
const SPIRAL_DURATION_TICKS := 240    # 4.0s
const SPIRAL_PERIOD_TICKS := 3
const SPIRAL_ARMS := 2
const SPIRAL_VOLLEYS := SPIRAL_DURATION_TICKS / SPIRAL_PERIOD_TICKS   # 80
const SPIRAL_ROTATE_DEG_PER_TICK := 0.75

# ---- 召唤冰蛛（P1）：ice_spider 行，经 spawn_callback；场上限 3 ----
const SUMMON_ARCHETYPE := "ice_spider"
const SUMMON_COUNT := 3
const SUMMON_CAP := 3
const SUMMON_OFFSET_PX := 48.0

# ---- 冰晶牢笼（P2）：玩家位为心 r64 环，9 环位落 8 根冰柱留 1 缺口（80° 豁口），
#      短命 3s；落柱点位压玩家 → 伤 6 恰一跳。m2-t36（T16 移交机制化）：柱环为
#      restraint 禁锢几何——环内玩家越环时按缺口弧段判定（缺口可通行，其余弧段夹回环缘）----
const CAGE_SLOTS := 9
const CAGE_PILLAR_COUNT := 8
const CAGE_RING_RADIUS_PX := 64.0
const CAGE_PILLAR_RADIUS_PX := 12.0
const CAGE_PILLAR_LIFE_TICKS := 180   # 3s
const CAGE_DMG := 6
const CAGE_SLOT_ARC_DEG := 40.0       # 环位弧宽（360°/9 环位）
const CAGE_GAP_ARC_DEG := CAGE_SLOT_ARC_DEG * 2.0   # 缺口豁口 = 邻柱间距（2 环位）
const CAGE_RNG_SALT := "boss_frost_widow_cage_gap"

# ---- 全屏冰刺阵（P2）：内域纵切 8 泳道，2 条缝隙安全线（分盐流确定），其余 5 伤 ----
const SPIKE_LANE_COUNT := 8
const SPIKE_GAP_LANES := 2
const SPIKE_DMG := 5
const SPIKE_RNG_SALT := "boss_frost_widow_spike_gaps"

const DEFAULT_FIELD_PX := Vector2(456.0, 238.0)   # 无 bounds 脑测兜底（同 VineColossus 条带口径）

# ---- 招式序列状态 ----
var _move := ""                     # 当前招式（"" = 选招中）
var _move_start := -1
var _seq_idx := 0                   # 招式表游标（跨阶段延续，入新阶段重置）
var _ice_laid := false              # 冰面一场一次
## 冰面数据注入接口：生产由房间注入 FloorScene.biome_ice（玩家摩擦接缝由其帧驱动），
## 未注入（脑测/独立运行）时懒建自有实例——IceZone.add_zone 原样复用，ice_floor.gd 零改动。
var ice_zone: IceZone = null
var _web_targets: Array[Vector2] = []
var _webs_armed := false            # 落地旗标（跳拍安全结算）
var _webs_checked := false
var _restraints: Array[Dictionary] = []   # {center, until}（背景结算：跨招式锚定）
var _spiral_volleys := 0
var _spiral_base := 0.0             # 螺旋起始角（前摇起始拍锁定）
var _minions: Array = []            # spawn_callback 返回的活体（失效/死亡自动清）
var _cage_center := Vector2.ZERO    # 牢笼环心（前摇起始拍锁定玩家位）
var _cage_gap_slot := 0
var _cage_landed := false
var _cage_hit_done := false
var _cage_confine := false          # m2-t36：禁锢激活（落地拍玩家在环内才激活，防预警期越环者回拉）
var _cage_pillars: Array[CagePillar] = []
var _spike_lanes: Array[Rect2] = []
var _spike_gap_indices: Array[int] = []
var _spikes_fired := false
var _cage_rng: RandomNumberGenerator = null
var _spike_rng: RandomNumberGenerator = null
var _fx: Array[Node] = []           # 招式预警视觉（move 结束即清）


func _test_init(r: Dictionary) -> void:
	super(r)
	_cage_rng = RngSvc.stream(RunState.floor_idx, CAGE_RNG_SALT)
	_spike_rng = RngSvc.stream(RunState.floor_idx, SPIKE_RNG_SALT)


func setup(r: Dictionary) -> void:
	super(r)
	_cage_rng = RunState.stream(CAGE_RNG_SALT)
	_spike_rng = RunState.stream(SPIKE_RNG_SALT)


## EnemyFactory 直接构造 FrostWidow；BossBase._test_init 正常解析阶段。
## 守卫保留给手工构造后遗漏初始化的调试路径（同 VineColossus/GemQueen）。
func _ensure_phases() -> void:
	if _phase_thresholds.is_empty():
		_parse_phases(row)


func _engage(frame: int) -> void:
	_ensure_phases()
	_restrain_tick(frame)                   # 蛛网禁锢为背景效果：跨招式持续锚定
	_cage_expire_tick(frame)                # 冰晶牢笼短命清场为背景效果
	_cage_confine_tick()                    # m2-t36：牢笼禁锢为背景效果（T16 移交机制化）
	if _move == "":
		_start_move(_pick_move(), frame)
	_advance_move(frame)


## 阶段招式表（递增；新招居前——入新阶段尽快登场）。入新阶段游标归零。
func _move_list() -> Array[String]:
	match phase():
		0:
			return ["carpet", "webs"]
		1:
			return ["spiral", "summon", "carpet", "webs"]
		_:
			return ["cage", "spikes", "spiral", "summon", "carpet", "webs"]


func _pick_move() -> String:
	var list := _move_list()
	for _attempt in list.size():
		var m: String = list[_seq_idx % list.size()]
		_seq_idx += 1
		if m == "carpet" and _ice_laid:
			continue                        # 冰面已铺：一场一次
		if m == "summon" and _alive_minions() >= SUMMON_CAP:
			continue                        # 3 只存活期内召唤不入序列
		return m
	return list[0]


func _on_phase_enter(_phase_idx: int) -> void:
	_seq_idx = 0                            # 换阶段重开序列


func die() -> void:
	_despawn_cage_pillars()
	_cage_confine = false                   # m2-t36：Boss 退场禁锢即解除
	super()                                 # EnemyBase.die：状态门/死亡爆/信号/退场


# ---- 招式状态机 ----

func _start_move(m: String, frame: int) -> void:
	_move = m
	_move_start = frame
	_webs_armed = false
	_webs_checked = false
	_spiral_volleys = 0
	_cage_landed = false
	_cage_hit_done = false
	_spikes_fired = false
	Fx.on_enemy_hit(self, {"telegraph": true})   # 前摇进入拍红闪预警（同 shooter/charger/vine）
	match m:
		"carpet":
			var bands := _carpet_bands()
			for band in bands:
				_fx_rect(band.get_center(), band.size, Color(0.4, 0.75, 1.0, 0.18))   # 蓝纹
		"webs":
			_web_targets = _generate_web_targets()
			for t in _web_targets:
				_fx_circle(t, WEB_RADIUS_PX)   # 预警红圈
		"spiral":
			_spiral_base = _aim_at_player()    # 起始角即瞄准角（前摇起始拍锁定）
		"cage":
			_cage_center = _player_pos()       # 环心锁定玩家位
			_cage_gap_slot = _cage_rng.randi_range(0, CAGE_SLOTS - 1)
			_fx_circle(_cage_center, CAGE_RING_RADIUS_PX + CAGE_PILLAR_RADIUS_PX)   # 预警红圈
		"spikes":
			_spike_lanes.clear()
			_spike_gap_indices.clear()
			var bounds := _field_bounds()
			var lane_w := bounds.size.x / float(SPIKE_LANE_COUNT)
			for i in SPIKE_LANE_COUNT:
				var lane := Rect2(bounds.position.x + lane_w * float(i), bounds.position.y,
					lane_w, bounds.size.y)
				_spike_lanes.append(lane)
			var first := _spike_rng.randi_range(0, SPIKE_LANE_COUNT - 1)
			var second := _spike_rng.randi_range(0, SPIKE_LANE_COUNT - 1)
			while second == first:
				second = _spike_rng.randi_range(0, SPIKE_LANE_COUNT - 1)
			_spike_gap_indices = [first, second]
			for i in SPIKE_LANE_COUNT:
				if _spike_gap_indices.has(i):
					continue
				_fx_rect(_spike_lanes[i].get_center(), _spike_lanes[i].size,
					Color(0.4, 0.75, 1.0, 0.22))   # 蓝纹泳道预警
		_:
			pass                               # summon 无地面预警（红闪已示）


func _advance_move(frame: int) -> void:
	var elapsed := frame - _move_start
	match _move:
		"carpet":
			if elapsed >= CARPET_WINDUP_TICKS:
				_carpet_resolve()
				_end_move()
		"webs":
			# 落地/触发拍用旗标而非 ==：冰缓/冻结跳拍时仍能结算（>= 首个未跳过拍）
			if elapsed >= WEBS_WINDUP_TICKS and not _webs_armed:
				_webs_armed = true
			if _webs_armed and not _webs_checked \
					and elapsed >= WEBS_WINDUP_TICKS + WEB_TRIGGER_DELAY_TICKS:
				_webs_checked = true
				_webs_trigger(frame)
				_end_move()
		"spiral":
			while _spiral_volleys < SPIRAL_VOLLEYS \
					and elapsed >= SPIRAL_WINDUP_TICKS + _spiral_volleys * SPIRAL_PERIOD_TICKS:
				_spiral_fire(_spiral_volleys)
				_spiral_volleys += 1
			if _spiral_volleys >= SPIRAL_VOLLEYS:
				_end_move()
		"summon":
			if elapsed >= SUMMON_WINDUP_TICKS:
				_summon_resolve()
				_end_move()
		"cage":
			if elapsed >= CAGE_WINDUP_TICKS and not _cage_landed:
				_cage_landed = true
				_cage_land(frame)
				_end_move()                    # 柱体短命清场走背景 _cage_expire_tick
		"spikes":
			if elapsed >= SPIKES_WINDUP_TICKS and not _spikes_fired:
				_spikes_fired = true
				_spikes_trigger()
				_end_move()
		_:
			pass


func _end_move() -> void:
	_move = ""
	_move_start = -1
	_fx_clear()


# ---- 冰面铺设 ----

func _carpet_bands() -> Array[Rect2]:
	var bounds := _field_bounds()
	var band_h := bounds.size.y / float(CARPET_BANDS)
	var bands: Array[Rect2] = []
	for idx_v in CARPET_ICE_BANDS:
		var idx := int(idx_v)
		bands.append(Rect2(bounds.position + Vector2(0.0, band_h * float(idx)),
			Vector2(bounds.size.x, band_h)))
	return bands


func _ensure_ice_zone() -> IceZone:
	if ice_zone == null:
		ice_zone = IceZone.new()
	return ice_zone


## 房间 40% 铺冰：横带 5 分取 2 带（恰 40% 面积）写入注入的 IceZone（T4 复用）。
func _carpet_resolve() -> void:
	var zone := _ensure_ice_zone()
	for band in _carpet_bands():
		zone.add_zone(band)
	_ice_laid = true


# ---- 蛛网禁锢 ----

## 招式起始拍定 3 落点（玩家位为心 + ±60px 横向侧翼），夹进房内域（红圈预警全程）。
func _generate_web_targets() -> Array[Vector2]:
	var center := _player_pos()
	var targets: Array[Vector2] = [center]
	targets.append(_clamp_to_bounds(center + Vector2(WEB_SPREAD_PX, 0.0)))
	targets.append(_clamp_to_bounds(center - Vector2(WEB_SPREAD_PX, 0.0)))
	return targets


## 落地 24t 后逐网结算：玩家仍在网心 18px 内 → 伤 4 + 禁锢 1s（锚定网心）；
## 已离开落点 → 网未触发（可打断）。
func _webs_trigger(frame: int) -> void:
	var pp := _player_pos()
	for t in _web_targets:
		if pp.distance_to(t) <= WEB_RADIUS_PX:
			_hit_player(WEB_DMG, {"attack_name": "蛛网禁锢"})
			_restraints.append({"center": t, "until": frame + RESTRAIN_TICKS})


## 禁锢背景结算：窗内把玩家 brain_pos 锚回网心 ±6px（脑层位移披露口径，见类头注释），
## 过期（1s）即清。
func _restrain_tick(frame: int) -> void:
	for i in range(_restraints.size() - 1, -1, -1):
		if frame > int(_restraints[i]["until"]):
			_restraints.remove_at(i)
	if player_ref == null or _restraints.is_empty():
		return
	for r in _restraints:
		var center: Vector2 = r["center"]
		player_ref.brain_pos = center \
			+ (player_ref.brain_pos - center).limit_length(RESTRAIN_SLACK_PX)


# ---- 螺旋弹幕 ----

## 一轮双臂（180° 相位）齐射：起始角前摇锁定，逐轮旋进 2.25°，弹伤/弹速取行数据。
func _spiral_fire(volley: int) -> void:
	fired_this_tick = true
	if combat == null:
		return
	var speed := float(row.get("bullet_speed", 100))
	var base := _spiral_base \
		+ deg_to_rad(SPIRAL_ROTATE_DEG_PER_TICK * float(SPIRAL_PERIOD_TICKS * volley))
	for arm in SPIRAL_ARMS:
		combat.spawn_projectile({
			"pos": brain_pos, "vel": Vector2.from_angle(base + PI * float(arm)) * speed,
			"damage": int(row.get("bullet_dmg", 5)), "faction": Projectile.Faction.ENEMY,
			"element": Elements.Id.NONE, "pierce": 0, "bounce": 0,
			"life_seconds": float(row.get("bullet_life_seconds", 2.0)),
			"radius": float(row.get("bullet_radius", 4.0)),
			"source_type": "projectile", "source_id": String(row.get("id", "")),
			"source_name": String(row.get("name", row.get("id", ""))), "attack_name": "螺旋弹幕",
		})


# ---- 召唤冰蛛 ----

func _alive_minions() -> int:
	_minions = _minions.filter(func(m): return is_instance_valid(m) and m.get("state") != EnemyBase.State.DEAD)
	return _minions.size()


## 3 只冰蛛（ice_spider 行）绕 Boss 均布落位；经 spawn_callback 生成并计入 cap。
func _summon_resolve() -> void:
	if not spawn_callback.is_valid():
		return
	var i := 0
	while _alive_minions() < SUMMON_CAP and i < SUMMON_COUNT:
		var pos := _clamp_to_bounds(
			brain_pos + Vector2.from_angle(TAU * float(i) / float(SUMMON_COUNT)) * SUMMON_OFFSET_PX)
		var m: Variant = spawn_callback.call(SUMMON_ARCHETYPE, pos, {})
		if m == null:
			break                           # 回调未返回实例：无法追踪上限，止于本次
		_minions.append(m)
		i += 1


# ---- 冰晶牢笼 ----

## 9 环位落 8 根冰柱留 1 缺口（缺口位经分盐流确定）；落柱点位压玩家 → 伤 6 恰一跳。
## m2-t36（T16 移交机制化）：落地拍玩家在环内才激活禁锢（预警期越环者不回拉）。
func _cage_land(frame: int) -> void:
	var until := frame + CAGE_PILLAR_LIFE_TICKS
	for slot in CAGE_SLOTS:
		if slot == _cage_gap_slot:
			continue
		var pos := _clamp_to_bounds(_cage_center
			+ Vector2.from_angle(TAU * float(slot) / float(CAGE_SLOTS)) * CAGE_RING_RADIUS_PX)
		var pillar := CagePillar.new()
		pillar.setup(pos, until, CAGE_PILLAR_RADIUS_PX)
		add_child(pillar)
		_cage_pillars.append(pillar)
		if not _cage_hit_done and _player_pos().distance_to(pos) <= CAGE_PILLAR_RADIUS_PX:
			_cage_hit_done = true
			_hit_player(CAGE_DMG, {"attack_name": "冰晶牢笼"})
	_cage_confine = _player_pos().distance_to(_cage_center) <= CAGE_RING_RADIUS_PX


## 冰晶牢笼禁锢（m2-t36，T16 移交机制化；restraint 同蛛网禁锢口径）：环内玩家越环时
## 按缺口弧段判定——缺口弧段内放行并解除禁锢（合法逃脱），其余弧段夹回环缘（脑层
## 位移披露口径，见类头注释）；柱体到期清场/Boss 死亡后自由。
func _cage_confine_tick() -> void:
	if not _cage_confine or _cage_pillars.is_empty() or player_ref == null:
		return
	var to: Vector2 = _player_pos() - _cage_center
	var dist := to.length()
	if dist <= CAGE_RING_RADIUS_PX or dist <= 0.01:
		return                                  # 环内：未越环
	var gap_ang := TAU * float(_cage_gap_slot) / float(CAGE_SLOTS)
	if absf(angle_difference(to.angle(), gap_ang)) <= deg_to_rad(CAGE_GAP_ARC_DEG) / 2.0:
		_cage_confine = false                   # 缺口弧段越环 = 合法逃脱，禁锢解除
		return
	player_ref.brain_pos = _cage_center + to.normalized() * CAGE_RING_RADIUS_PX


## 冰柱短命（3s）清场为背景结算：到期即退场；失效体自动出列。
func _cage_expire_tick(frame: int) -> void:
	for i in range(_cage_pillars.size() - 1, -1, -1):
		var p := _cage_pillars[i]
		if not is_instance_valid(p) or p.expired(frame):
			if is_instance_valid(p):
				p.despawn()
			_cage_pillars.remove_at(i)


func _despawn_cage_pillars() -> void:
	for p in _cage_pillars:
		if is_instance_valid(p):
			p.despawn()
	_cage_pillars.clear()


# ---- 全屏冰刺阵 ----

## 全屏泳道中非缝隙泳道结算 5 伤（恰一跳）；缝隙安全线（2 条）免伤。
func _spikes_trigger() -> void:
	if player_ref == null or not player_ref.has_method("take_hit"):
		return
	var pp := _player_pos()
	for i in _spike_lanes.size():
		if _spike_gap_indices.has(i):
			continue
		if _spike_lanes[i].has_point(pp):
			_hit_player(SPIKE_DMG, {"attack_name": "冰刺阵"})
			return


# ---- 共用 helpers ----

func _aim_at_player() -> float:
	return (_player_pos() - brain_pos).angle()


func _clamp_to_bounds(pos: Vector2, inset := 4.0) -> Vector2:
	if combat_bounds.has_area():
		var legal := combat_bounds.grow(-inset)
		return pos.clamp(legal.position, legal.end)
	return pos


## 招式场地内域：房间注入 combat_bounds 优先，空矩形脑测兜底默认 M0 战斗房内域。
func _field_bounds() -> Rect2:
	if combat_bounds.has_area():
		return combat_bounds
	return Rect2(brain_pos - DEFAULT_FIELD_PX / 2.0, DEFAULT_FIELD_PX)


# ---- 玩家结算（同 VineColossus/GemQueen）----

func _hit_player(dmg: int, extra: Dictionary) -> void:
	if player_ref == null or not player_ref.has_method("take_hit"):
		return
	var ctx := {
		"amount": dmg, "is_crit": false, "element": Elements.Id.NONE, "from": brain_pos,
		"source_type": "boss", "source_id": String(row.get("id", "frost_widow")),
		"source_name": String(row.get("name", "寒渊蛛母")), "attack_name": "攻击",
	}
	ctx.merge(extra, true)
	player_ref.take_hit(ctx)


# ---- 预警视觉（脑层挂子节点，测试无树亦安全；同 VineColossus 手法）----

func _fx_circle(center: Vector2, radius: float) -> void:
	var pts := PackedVector2Array()
	for i in range(20):
		pts.append(Vector2.from_angle(TAU * float(i) / 20.0) * radius)
	var vis := Polygon2D.new()
	vis.polygon = pts
	vis.color = Color(1.0, 0.25, 0.2, 0.3)   # 预警红圈
	vis.z_index = 15
	vis.position = center - brain_pos
	add_child(vis)
	_fx.append(vis)


func _fx_rect(center: Vector2, size: Vector2, color: Color) -> void:
	var vis := Polygon2D.new()
	var h := size / 2.0
	vis.polygon = PackedVector2Array([
		Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y),
	])
	vis.color = color
	vis.z_index = 15
	vis.position = center - brain_pos
	add_child(vis)
	_fx.append(vis)


func _fx_clear() -> void:
	for node in _fx:
		if is_instance_valid(node):
			node.queue_free()
	_fx.clear()


## 冰晶牢笼柱（脑层轻量实体）：顶层挂载（top_level——环位锚定世界坐标，Boss 位移不
## 拖动柱环，m2-t36 同 HivePillar/Crystal 接线口径）；短命 3s 到期退场；Boss 死亡随行清场。
class CagePillar extends Node2D:
	var pos_world := Vector2.ZERO
	var until := -1
	var radius_px := 12.0
	var alive := true

	func setup(p: Vector2, until_frame: int, pillar_radius: float) -> void:
		pos_world = p
		until = until_frame
		radius_px = pillar_radius
		top_level = true               # m2-t36：出生位 = 世界坐标（不受 Boss 变换拖动）
		position = p
		var vis := Polygon2D.new()
		var pts := PackedVector2Array()
		for i in range(6):
			pts.append(Vector2.from_angle(TAU * float(i) / 6.0) * radius_px)
		vis.polygon = pts
		vis.color = Color(0.55, 0.85, 0.95, 0.9)   # 冰蓝（同 PrismGolem 晶柱口径）
		vis.z_index = 12
		add_child(vis)

	func expired(frame: int) -> bool:
		return frame > until

	func despawn() -> void:
		alive = false
		queue_free()
