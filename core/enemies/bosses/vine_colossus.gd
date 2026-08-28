class_name VineColossus
extends BossBase
## 藤蔓巨像（A1 Boss，附录 E.1）：P0 巨掌拍击/种子弹环交替；P1 增藤蔓横扫+召唤蘑菇；
## P2 增毒雨（3 安全区绿圈）。招式序列状态机：_engage 按 phase() 选招表，招式间背靠背。
## 所有前摇 ≥24t（GDD §15）；地面效果红纹预警、安全区绿圈（GDD §7.5）。
## 脑层无房间锚（披露）：横扫/毒雨以施法拍 brain_pos 为锚、取 M0 战斗房内域尺寸（456×238）；
## 安全区取锚 ± 固定偏移 [(-160,0),(0,0),(160,0)]（确定性，替代「每轮随机」——见 task-13 报告）。

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

# ---- 召唤蘑菇（P1）：蘑菇孢子手暂以 shooter 原型替身（披露），场上限 2，每 240t 补 ----
const SUMMON_ARCHETYPE := "shooter"
const SUMMON_CAP := 2
const SUMMON_PERIOD_TICKS := 240    # 4.0s
const SUMMON_OFFSET_PX := 48.0

# ---- 毒雨（P2）：前摇 60t 后全场 360t，每 30t 1 伤；3 个 r48 安全区 ----
const RAIN_DURATION_TICKS := 360    # 6.0s
const RAIN_PERIOD_TICKS := 30       # 0.5s
const RAIN_DMG := 1
const SAFE_RADIUS_PX := 48.0
const SAFE_OFFSETS: Array[Vector2] = [Vector2(-160, 0), Vector2.ZERO, Vector2(160, 0)]

## 房间注入：spawn_callback.call("shooter", pos) 须返回刷出节点（供上限追踪；返回 null 则止于本次）。
## 未注入（Callable 无效）→ 召唤招不入序列。生产接线归房间/流程层（见 task-13 报告）。
var spawn_callback := Callable()

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
var _fx: Array[Node] = []           # 招式预警视觉（move 结束即清）
var _rain_fx: Array[Node] = []      # 毒雨视觉（雨停即清，跨招式存活）

## set_script 换装 hazard 自愈：EnemyBase._test_init 按 boss_script 换装后，
## BossBase._test_init 内 _parse_phases 的成员写入落在被弃实例（m0-t12 同款丢失）。
## 生产路径（RoomCombat: EnemyBase.new()+setup(row)）首次 _engage 时在此补析血线。
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
			_rain_circles.clear()
			for off in SAFE_OFFSETS:
				_rain_circles.append(brain_pos + off)
			_fx_rect(brain_pos, Vector2(SWEEP_WIDTH_PX, SWEEP_HEIGHT_PX), Color(1.0, 0.25, 0.2, 0.15))
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
	_hit_player(SLAP_DMG, {"knockback": SLAP_KNOCKBACK_PX})
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
			"pos": brain_pos, "vel": Vector2.from_angle(a) * float(row.get("bullet_speed", 110)),
			"damage": int(row.get("bullet_dmg", 3)), "faction": Projectile.Faction.ENEMY,
			"element": Elements.Id.NONE, "pierce": 0, "bounce": 0,
			"life_seconds": float(row.get("bullet_life_seconds", 2.5)), "radius": 3.0,
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
		_hit_player(SWEEP_DMG, {})

# ---- 召唤蘑菇 ----

func _alive_minions() -> int:
	_minions = _minions.filter(func(m): return is_instance_valid(m) and m.get("state") != EnemyBase.State.DEAD)
	return _minions.size()

func _summon_resolve() -> void:
	if not spawn_callback.is_valid():
		return
	while _alive_minions() < SUMMON_CAP:
		var m: Variant = spawn_callback.call(SUMMON_ARCHETYPE,
			brain_pos + Vector2(SUMMON_OFFSET_PX * _summon_side, 0.0))
		_summon_side = -_summon_side
		if m == null:
			break                           # 回调未返回实例：无法追踪上限，止于本次
		_minions.append(m)

# ---- 毒雨 ----

func _rain_tick(frame: int) -> void:
	if _rain_until < 0:
		return
	if frame > _rain_until:
		_rain_until = -1
		_rain_next = -1
		_rain_circles.clear()
		_fx_free(_rain_fx)
		return
	if frame >= _rain_next:
		_rain_next += RAIN_PERIOD_TICKS
		var pp := _player_pos()
		for c in _rain_circles:
			if pp.distance_to(c) <= SAFE_RADIUS_PX:
				return                      # 安全区内免伤（含圈界 ≤ r48）
		_hit_player(RAIN_DMG, {"element": Elements.Id.POISON})

# ---- 玩家结算 ----

func _hit_player(dmg: int, extra: Dictionary) -> void:
	if player_ref == null or not player_ref.has_method("take_hit"):
		return
	var ctx := {"amount": dmg, "is_crit": false, "element": Elements.Id.NONE, "from": brain_pos}
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
