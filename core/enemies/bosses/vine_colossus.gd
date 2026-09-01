class_name VineColossus
extends BossBase
## 藤蔓巨像（A1 Boss，附录 E.1）：P0 巨掌拍击/种子弹环交替；P1 增藤蔓横扫+召唤蘑菇；
## P2 增毒雨（3 个持续移动的安全区绿圈）。招式序列状态机：_engage 按 phase() 选招表，招式间背靠背。
## 所有前摇 ≥24t（GDD §15）；地面效果红纹预警、安全区绿圈（GDD §7.5）。
## 横扫以施法拍 brain_pos 为锚；毒雨安全区优先使用房间注入的 combat_bounds，
## 经 RunState/RngSvc 分盐流逐轮生成，同 seed+楼层+Boss 实例序列可复现。

# ---- 前摇（GDD §15 下限 24t = TimeConst.ticks(0.4)）----
const MIN_WINDUP_TICKS := 24
const SLAP_WINDUP_TICKS := 30       # 0.5s
const RING_WINDUP_TICKS := 36       # 0.6s
const SWEEP_WINDUP_TICKS := 42      # 0.7s
const SUMMON_WINDUP_TICKS := 48     # 0.8s
const RAIN_WINDUP_TICKS := 60       # 1.0s

# ---- 拍击（P0）----
const SLAP_RANGE_PX := 70.0
const SLAP_ARC_DEG := 90.0
const SLAP_DMG := 5
const SLAP_KNOCKBACK_PX := 8.0

# ---- 种子弹环（P0）：附录 E.1「环形 12 发×2 轮」= 12+12 两波（24t 间隔）全环 24 发，
# 第二轮错半步 15°（(i*2+wave)/24 均布几何，两轮各 30° 步进错 15°）----
const RING_WAVES := 2
const RING_PER_WAVE := 12
const RING_WAVE_GAP_TICKS := 24     # 0.4s

# ---- 藤蔓横扫（P1）：全宽地面条带 36t 横穿，左右交替 ----
const SWEEP_TRAVEL_TICKS := 36
const SWEEP_DMG := 5
const SWEEP_WIDTH_PX := 456.0       # M0 战斗房内域宽
const SWEEP_HEIGHT_PX := 238.0      # M0 战斗房内域高（条带纵程）
const SWEEP_THICKNESS_PX := 24.0

# ---- 召唤蘑菇（P1）：真实蘑菇孢子手，场上限 2，每 240t 补 ----
const SUMMON_ARCHETYPE := "mushroom_spore"
const SUMMON_CAP := 2
const SUMMON_PERIOD_TICKS := 240    # 4.0s
const SUMMON_OFFSET_PX := 48.0

# ---- 毒雨（P2）：前摇 60t 后全场 360t，每 30t 4 伤（附录 E.1）；3 个 r48 安全区 ----
const RAIN_DURATION_TICKS := 360    # 6.0s
const RAIN_PERIOD_TICKS := 30       # 0.5s
const RAIN_DMG := 4
const SAFE_RADIUS_PX := 48.0
const SAFE_COUNT := 3
const SAFE_GAP_PX := 12.0
const SAFE_MIN_SEPARATION_PX := SAFE_RADIUS_PX * 2.0 + SAFE_GAP_PX
const SAFE_MOVE_RADIUS_PX := 16.0
const SAFE_MOVE_PERIOD_TICKS := 180   # 3.0s/圈；单次 6s 毒雨完整移动两圈
const RAIN_RNG_SALT := "boss_vine_colossus_safe_zones"

## 房间注入：spawn_callback.call("mushroom_spore", pos, {}) 须返回真实刷出节点，
## 并由房间递归注入同 callback、CombatSystem、player_ref 与非波次计数标记。
## 成员声明位于 EnemyBase（m1-t12）；此处不重复声明（parse 冲突）。

# ---- 招式序列状态 ----
var _move := ""                     # 当前招式（"" = 选招中）
var _move_start := -1
var _seq_idx := 0                   # 招式表游标（跨阶段延续，入新阶段重置）
var _slap_facing := 0.0             # 拍击朝向（前摇起始拍锁定）
var _ring_waves_fired := 0
var _sweep_dir := 1                 # +1 左→右 / -1 右→左（交替）
var _sweep_anchor := Vector2.ZERO   # 行进起点（x0, 锚 y）
var _sweep_x1_px := 0.0             # 行进终点 x（x0→x1 线性）
var _sweep_hit_done := false
var _sweep_travel_started := false
var _sweep_vis: Node2D = null
var _summon_next := -1              # 首个 P1+ engage 拍锚定 +240
var _summon_side := 1.0             # 召唤落点左右交替
var _minions: Array = []            # spawn_callback 返回的活体（失效/死亡自动清）
var _rain_until := -1
var _rain_next := -1
var _rain_circles: Array[Vector2] = []
var _rain_anchors: Array[Vector2] = []
var _rain_rng: RandomNumberGenerator = null
var _rain_round := 0
var _rain_started_at := -1
var _rain_motion_phase := 0.0
var _rain_motion_dir := 1.0
var _fx: Array[Node] = []           # 招式预警视觉（move 结束即清）
var _rain_fx: Array[Node] = []      # 毒雨视觉（雨停即清，跨招式存活）


func _test_init(r: Dictionary) -> void:
	super(r)
	_rain_rng = RngSvc.stream(RunState.floor_idx, RAIN_RNG_SALT)
	_rain_round = 0


func setup(r: Dictionary) -> void:
	super(r)
	_rain_rng = RunState.stream(RAIN_RNG_SALT)
	_rain_round = 0

## EnemyFactory 会直接构造 VineColossus；BossBase._test_init 正常解析阶段。
## 此守卫保留给手工构造后遗漏初始化的调试路径，不再承担脚本换装自愈。
func _ensure_phases() -> void:
	if _phase_thresholds.is_empty():
		_parse_phases(row)

func _engage(frame: int) -> void:
	_ensure_phases()
	_rain_tick(frame)                       # 毒雨为背景效果：跨招式持续结算
	if _summon_next < 0 and phase() >= 1:
		_summon_next = frame + SUMMON_PERIOD_TICKS
	if _move == "":
		if phase() >= 1 and _summon_next > 0 and frame >= _summon_next \
				and spawn_callback.is_valid() and _alive_minions() < SUMMON_CAP:
			_start_move("summon", frame)
		else:
			_start_move(_pick_move(frame), frame)
	_advance_move(frame)

## 阶段招式表（递增：P2 含 P1/P0 全部）。入新阶段游标归零（新招尽快登场）。
func _move_list() -> Array[String]:
	match phase():
		0:
			return ["slap", "ring"]
		1:
			return ["slap", "ring", "sweep"]
		_:
			return ["slap", "ring", "sweep", "rain"]

func _pick_move(frame: int) -> String:
	var list := _move_list()
	for _attempt in list.size():
		var m: String = list[_seq_idx % list.size()]
		_seq_idx += 1
		if m == "rain" and frame < _rain_until:
			continue                        # 毒雨存续期不叠加
		return m
	return list[0]

func _on_phase_enter(_phase_idx: int) -> void:
	_seq_idx = 0                            # 换阶段重开序列

# ---- 招式状态机 ----

func _start_move(m: String, frame: int) -> void:
	_move = m
	_move_start = frame
	_ring_waves_fired = 0
	_sweep_hit_done = false
	_sweep_travel_started = false
	Fx.on_enemy_hit(self, {"telegraph": true})   # 前摇进入拍红闪预警（同 shooter/charger）
	match m:
		"slap":
			_slap_facing = (_player_pos() - brain_pos).angle()   # 朝向前摇起始拍锁定
			_fx_wedge(SLAP_RANGE_PX, SLAP_ARC_DEG, Color(1.0, 0.25, 0.2, 0.35))
		"sweep":
			var half_w := SWEEP_WIDTH_PX / 2.0
			var x0 := brain_pos.x - half_w if _sweep_dir > 0 else brain_pos.x + half_w
			var x1 := brain_pos.x + half_w if _sweep_dir > 0 else brain_pos.x - half_w
			_sweep_anchor = Vector2(x0, brain_pos.y)
			_sweep_x1_px = x1
			_fx_rect(brain_pos, Vector2(SWEEP_WIDTH_PX, SWEEP_HEIGHT_PX), Color(1.0, 0.25, 0.2, 0.2))
		"rain":
			_generate_safe_zones()
			var rain_rect := _rain_bounds()
			_fx_rect(rain_rect.get_center(), rain_rect.size, Color(1.0, 0.25, 0.2, 0.15))
			for c in _rain_circles:
				_rain_fx_circle(c)
		_:
			pass                            # ring / summon 无地面预警（红闪已示）

func _advance_move(frame: int) -> void:
	var elapsed := frame - _move_start
	match _move:
		"slap":
			if elapsed >= SLAP_WINDUP_TICKS:
				_slap_resolve()
				_end_move()
		"ring":
			while _ring_waves_fired < RING_WAVES \
					and elapsed >= RING_WINDUP_TICKS + _ring_waves_fired * RING_WAVE_GAP_TICKS:
				_ring_fire_wave(_ring_waves_fired)
				_ring_waves_fired += 1
			if _ring_waves_fired >= RING_WAVES:
				_end_move()
		"sweep":
			var t := elapsed - SWEEP_WINDUP_TICKS
			if t >= 0 and not _sweep_travel_started:
				_sweep_travel_started = true
				_sweep_dir = -_sweep_dir        # 行进开始拍换向（下次反向）
				_sweep_vis = _fx_rect(_sweep_anchor, Vector2(SWEEP_THICKNESS_PX, SWEEP_HEIGHT_PX), Color(0.3, 0.75, 0.3, 0.6))
			if t >= 0:
				var progress := minf(float(t) / float(SWEEP_TRAVEL_TICKS), 1.0)
				var center_x := lerpf(_sweep_anchor.x, _sweep_x1_px, progress)
				if _sweep_vis != null:
					_sweep_vis.position = Vector2(center_x, _sweep_anchor.y) - brain_pos
				_sweep_tick(center_x)
			if elapsed >= SWEEP_WINDUP_TICKS + SWEEP_TRAVEL_TICKS:
				_end_move()
		"summon":
			if elapsed >= SUMMON_WINDUP_TICKS:
				_summon_resolve()
				_summon_next = frame + SUMMON_PERIOD_TICKS
				_end_move()
		"rain":
			if elapsed >= RAIN_WINDUP_TICKS:
				_rain_until = frame + RAIN_DURATION_TICKS
				_rain_next = frame + RAIN_PERIOD_TICKS
				_rain_started_at = frame
				_update_safe_zone_motion(0)
				_end_move()                     # 雨为背景效果：招式位即释放

func _end_move() -> void:
	_move = ""
	_move_start = -1
	_sweep_vis = null
	_fx_clear()

# ---- 拍击 ----

func _slap_resolve() -> void:
	var to := _player_pos() - brain_pos
	if to.length() > SLAP_RANGE_PX:
		return
	if absf(angle_difference(_slap_facing, to.angle())) > deg_to_rad(SLAP_ARC_DEG) / 2.0:
		return
	_hit_player(SLAP_DMG, {"knockback": SLAP_KNOCKBACK_PX, "attack_name": "巨掌拍击"})
	# 击退：Player.take_hit 无击退通路（M0），直接位移 player_ref.brain_pos（同坚守反向用法）；
	# 真实 PlayerProxy 每帧镜像覆盖此位移——击退表现归表现层接线（task-13 报告披露）。
	if player_ref != null and to.length() > 0.01:
		player_ref.brain_pos += to.normalized() * SLAP_KNOCKBACK_PX

# ---- 种子弹环 ----

func _ring_fire_wave(wave: int) -> void:
	fired_this_tick = true
	if combat == null:
		return
	var total := RING_PER_WAVE * RING_WAVES          # 全环 24 发均布，两波各错半步（15°）
	for i in range(RING_PER_WAVE):
		var a := deg_to_rad(360.0) * (float(i * 2 + wave) / float(total))
		combat.spawn_projectile({
			"pos": brain_pos, "vel": Vector2.from_angle(a) * enemy_bullet_speed(110),
			"damage": int(row.get("bullet_dmg", 3)), "faction": Projectile.Faction.ENEMY,
			"element": Elements.Id.NONE, "pierce": 0, "bounce": 0,
			"life_seconds": float(row.get("bullet_life_seconds", 2.5)),
			"radius": float(row.get("bullet_radius", 3.0)),
			"source_type": "projectile", "source_id": String(row.get("id", "")),
			"source_name": String(row.get("name", row.get("id", ""))), "attack_name": "种子弹环",
		})

# ---- 藤蔓横扫 ----

func _sweep_tick(center_x: float) -> void:
	if _sweep_hit_done:
		return
	var pp := _player_pos()
	if absf(pp.y - _sweep_anchor.y) > SWEEP_HEIGHT_PX / 2.0:
		return
	if absf(pp.x - center_x) <= SWEEP_THICKNESS_PX / 2.0:
		_sweep_hit_done = true
		_hit_player(SWEEP_DMG, {"attack_name": "藤蔓横扫"})

# ---- 召唤蘑菇 ----

func _alive_minions() -> int:
	_minions = _minions.filter(func(m): return is_instance_valid(m) and m.get("state") != EnemyBase.State.DEAD)
	return _minions.size()

func _summon_resolve() -> void:
	if not spawn_callback.is_valid():
		return
	while _alive_minions() < SUMMON_CAP:
		var m: Variant = spawn_callback.call(SUMMON_ARCHETYPE,
			brain_pos + Vector2(SUMMON_OFFSET_PX * _summon_side, 0.0), {})
		_summon_side = -_summon_side
		if m == null:
			break                           # 回调未返回实例：无法追踪上限，止于本次
		_minions.append(m)

# ---- 毒雨 ----

func _rain_bounds() -> Rect2:
	if combat_bounds.size.x >= SAFE_RADIUS_PX * 2.0 and combat_bounds.size.y >= SAFE_RADIUS_PX * 2.0:
		return combat_bounds
	return Rect2(brain_pos - Vector2(SWEEP_WIDTH_PX, SWEEP_HEIGHT_PX) / 2.0,
		Vector2(SWEEP_WIDTH_PX, SWEEP_HEIGHT_PX))


## 三个安全圆的锚点全部落在预留 16px 移动余量的合法内域，且圆心距离至少
## 108px（2r+12px）。固定候选网格使用随机起点+与 21 互质步长遍历，既保证
## 同 seed 可复现，也避免拒绝采样极端退化。
func _generate_safe_zones() -> void:
	if _rain_rng == null:
		_rain_rng = RngSvc.stream(RunState.floor_idx, RAIN_RNG_SALT)
	_rain_round += 1
	_rain_circles.clear()
	_rain_anchors.clear()
	var bounds := _rain_bounds()
	var safe_margin := SAFE_RADIUS_PX + SAFE_MOVE_RADIUS_PX
	var legal := Rect2(bounds.position + Vector2.ONE * safe_margin,
		bounds.size - Vector2.ONE * safe_margin * 2.0)
	var candidates: Array[Vector2] = []
	const COLS := 7
	const ROWS := 3
	for y in ROWS:
		for x in COLS:
			candidates.append(Vector2(
				lerpf(legal.position.x, legal.end.x, float(x) / float(COLS - 1)),
				lerpf(legal.position.y, legal.end.y, float(y) / float(ROWS - 1))))
	var start := _rain_rng.randi_range(0, candidates.size() - 1)
	var step_options := [5, 11, 13, 17, 19]
	var step: int = step_options[_rain_rng.randi_range(0, step_options.size() - 1)]
	for i in candidates.size():
		var candidate := candidates[(start + i * step) % candidates.size()]
		var clear := true
		for placed in _rain_anchors:
			if candidate.distance_to(placed) < SAFE_MIN_SEPARATION_PX:
				clear = false
				break
		if clear:
			_rain_anchors.append(candidate)
			if _rain_anchors.size() == SAFE_COUNT:
				break
	assert(_rain_anchors.size() == SAFE_COUNT,
		"VineColossus: room too small for three non-overlapping poison-rain safe zones")
	_rain_motion_phase = _rain_rng.randf_range(0.0, TAU)
	_rain_motion_dir = -1.0 if _rain_rng.randi_range(0, 1) == 0 else 1.0
	_rain_started_at = -1
	_update_safe_zone_motion(0)


## 三圈共享同一圆周位移：整个毒雨期间逐帧连续移动，同时严格保持彼此间距；
## 锚点预留 SAFE_MOVE_RADIUS_PX，故任意相位下完整 r48 圆均不会越出战斗内域。
func _update_safe_zone_motion(elapsed_ticks: int) -> void:
	if _rain_anchors.is_empty():
		return
	var theta := _rain_motion_phase + _rain_motion_dir * TAU \
		* float(maxi(elapsed_ticks, 0)) / float(SAFE_MOVE_PERIOD_TICKS)
	var offset := Vector2.from_angle(theta) * SAFE_MOVE_RADIUS_PX
	_rain_circles.clear()
	for anchor in _rain_anchors:
		_rain_circles.append(anchor + offset)
	_sync_rain_fx()


func _sync_rain_fx() -> void:
	for i in mini(_rain_fx.size(), _rain_circles.size()):
		var vis := _rain_fx[i]
		if is_instance_valid(vis):
			vis.position = _rain_circles[i] - brain_pos

func _rain_tick(frame: int) -> void:
	if _rain_until < 0:
		return
	if frame > _rain_until:
		_rain_until = -1
		_rain_next = -1
		_rain_started_at = -1
		_rain_circles.clear()
		_rain_anchors.clear()
		_fx_free(_rain_fx)
		return
	_update_safe_zone_motion(frame - _rain_started_at)
	if frame >= _rain_next:
		_rain_next += RAIN_PERIOD_TICKS
		var pp := _player_pos()
		for c in _rain_circles:
			if pp.distance_to(c) <= SAFE_RADIUS_PX:
				return                      # 安全区内免伤（含圈界 ≤ r48）
		_hit_player(RAIN_DMG, {"element": Elements.Id.POISON, "attack_name": "毒雨"})

# ---- 玩家结算 ----

func _hit_player(dmg: int, extra: Dictionary) -> void:
	if player_ref == null or not player_ref.has_method("take_hit"):
		return
	var ctx := {
		"amount": dmg, "is_crit": false, "element": Elements.Id.NONE, "from": brain_pos,
		"source_type": "boss", "source_id": String(row.get("id", "vine_colossus")),
		"source_name": String(row.get("name", "藤蔓巨像")), "attack_name": "攻击",
	}
	ctx.merge(extra, true)
	player_ref.take_hit(ctx)

# ---- 预警/效果视觉（脑层挂子节点，测试无树亦安全；玩家可读性归 GDD §7.5）----

func _fx_rect(center: Vector2, size: Vector2, color: Color) -> Node2D:
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
	return vis

func _fx_wedge(radius: float, arc_deg: float, color: Color) -> void:
	var pts := PackedVector2Array([Vector2.ZERO])
	var n := 12
	for i in range(n + 1):
		var a := _slap_facing + deg_to_rad(arc_deg) * (float(i) / float(n) - 0.5)
		pts.append(Vector2.from_angle(a) * radius)
	var vis := Polygon2D.new()
	vis.polygon = pts
	vis.color = color
	vis.z_index = 15
	add_child(vis)
	_fx.append(vis)

func _rain_fx_circle(center: Vector2) -> void:
	var pts := PackedVector2Array()
	for i in range(24):
		pts.append(Vector2.from_angle(TAU * float(i) / 24.0) * SAFE_RADIUS_PX)
	var vis := Polygon2D.new()
	vis.polygon = pts
	vis.color = Color(0.3, 0.9, 0.35, 0.4)      # 绿圈安全区
	vis.z_index = 15
	vis.position = center - brain_pos
	add_child(vis)
	_rain_fx.append(vis)

func _fx_clear() -> void:
	_fx_free(_fx)

func _fx_free(list: Array[Node]) -> void:
	for node in list:
		if is_instance_valid(node):
			node.queue_free()
	list.clear()
