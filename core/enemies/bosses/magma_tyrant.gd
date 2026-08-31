class_name MagmaTyrant
extends BossBase
## 熔核暴君（A3 Boss，附录 E.5，HP 3200）：P0 岩浆喷发（4 块岩浆区各 5s——复用 T10
## HazardMagma 岩浆区数据：外接方 2r 区几何 + in_magma 含心判定 + 60t DOT 脉冲语义，
## 喷发拍区内爆发 7）+ 火拳（windup 30t 近身扇形 90° 伤 8）；
## P1（60%）+ 火雨（windup 48t，12 红圈落点分 3 波伤 7——直接复用 T10 FireRain 驱动
## 契约：预警倒计时 48t、恰 boom 拍结算、下一拍自除）+ 怒气常驻（HP<60% 起弹幕密度
## ×1.5、移速 +20%）；
## P2（30%）+ 地裂火浪（windup 42t，环形火浪从 Boss 自中心扩散至 300px
## ≥战斗房半对角，伤 8；可被掩体挡——注入 cover_points 世界坐标做线段遮挡判定）。
## 招式序列状态机同 VineColossus/PrismGolem：_engage 按 phase() 选招表，招式背靠背；
## 所有前摇 ≥24t（GDD §15）；红圈/红纹预警齐备（脑层 Polygon2D，测试无树亦安全）。
## 数值逐字附录 E.5。偏差披露：怒气密度倍率在暴君无投射弹的招式面上映射为岩浆喷发
## 区块数 4→6（火雨圈数保持 E.5 定数 12）。区视觉自预警起持续至区过期（5s）再清，
## 避免喷发拍后岩浆区 5s 存续期不可见（fix1：危险可视一致性）。

# ---- 前摇（GDD §15 下限 24t；数值逐字附录 E.5）----
const MIN_WINDUP_TICKS := 24
const ERUPT_WINDUP_TICKS := 36     # 0.6s
const FIST_WINDUP_TICKS := 30      # 0.5s
const RAIN_WINDUP_TICKS := 48      # 0.8s（= HazardMagma.FireRain.WARN_TICKS）
const WAVE_WINDUP_TICKS := 42      # 0.7s

# ---- 岩浆喷发（P0）：4 块岩浆区（怒气 6 块）各持续 5s。区几何/判定/DOT 全复用
#      T10 HazardMagma：外接方 2r（r=24 同 FloorScene._build_magma 缺省岩浆池半径）、
#      in_magma 含心判定、60t 驻留脉冲（2 伤，抗火 meta 减半）。玩家为心 72px 环均布，
#      前摇起始拍锁定；喷发拍站区内爆发 7（E.5「7/跳」）----
const ERUPT_BASE_COUNT := 4
const ERUPT_ZONE_RADIUS_PX := 24.0
const ERUPT_RING_PX := 72.0
const ERUPT_DURATION_TICKS := 300  # 5s
const ERUPT_BURST_DMG := 7

# ---- 火拳（P0）：近身扇形拍，前摇起始拍锁定朝向（同藤蔓巨像拍击，侧移可躲）----
const FIST_RANGE_PX := 70.0
const FIST_ARC_DEG := 90
const FIST_DMG := 8

# ---- 火雨（P1）：12 红圈分 3 波（4/波，波距 24t），落点分盐流逐轮生成夹内域；
#      预警/落点伤/半径/自除全部复用 HazardMagma.FireRain 契约（T19 消费接口）----
const RAIN_WAVES := 3
const RAIN_BASE_PER_WAVE := 4
const RAIN_WAVE_GAP_TICKS := 24
const RAIN_RNG_SALT := "boss_magma_tyrant_rain"

# ---- 地裂火浪（P2）：环形火浪从 Boss 位锚定自中心扩散，2px/拍（120px/s）至 300px
#      （≥ M0 战斗房半对角 257px，自中心覆盖全房）；前沿越过玩家位拍结算 8；
#      掩体遮挡：cover_points 注入世界坐标，掩体心到 Boss→玩家线段 ≤ 掩体半径即挡 ----
const WAVE_DMG := 8
const WAVE_SPEED_PXPS := 120.0
const WAVE_MAX_RADIUS_PX := 300.0
const COVER_RADIUS_PX := EnemyLaser.PILLAR_RADIUS_PX   # 掩体判定圆（同晶柱口径 8px）

# ---- 怒气（P1 常驻）：HP<60% 起弹幕密度 ×1.5（喷发区块数 4→6）、移速 +20% ----
const RAGE_DENSITY_MULT := 1.5
const RAGE_SPEED_MULT := 1.2

# ---- 招式序列状态 ----
var _move := ""                     # 当前招式（"" = 选招中）
var _move_start := -1
var _seq_idx := 0                   # 招式表游标（跨阶段延续，入新阶段重置）
var cover_points: Array = []        # 房间注入掩体世界坐标（可破坏晶柱/岩柱；脑测可注入）

# ---- 岩浆喷发状态（区存储/判定复用 T10 HazardMagma 实例）----
var _magma := HazardMagma.new()
var _erupt_centers: Array[Vector2] = []
var _erupt_untils: Array[int] = []  # 与 _magma.zones 平行：各区到期拍（「各 5s」独立计）
var _zone_fx: Array[Node] = []      # 与 _magma.zones 平行：区视觉（预警矩形自预警起持续至
                                    # 区过期——喷发拍后岩浆区仍有 5s 存续期，不可视即漏披露，
                                    # fix1 起 _end_move 不再提前释放）
var _erupt_standing := 0            # 区内驻留拍（出域暂停不清零——T10 语义）

# ---- 火拳状态 ----
var _fist_facing := 0.0             # 朝向（前摇起始拍锁定）

# ---- 火雨状态（驱动复用 T10 FireRain：倒计时/boom/自除全在组件内）----
var _fire_rain := HazardMagma.FireRain.new()
var _rain_targets: Array[Vector2] = []
var _rain_waves_scheduled := 0
var _rain_rng: RandomNumberGenerator = null
var _rain_fx: Array[Node] = []      # 红圈预警（与 strikes FIFO 对齐，落点自除）

# ---- 地裂火浪状态 ----
var _wave_anchor := Vector2.ZERO    # 扩散心（前摇起始拍锁定 Boss 位）
var _wave_front := 0.0              # 当前前沿半径（px）
var _wave_hit_done := false
var _wave_vis: Node2D = null

var _fx: Array[Node] = []           # 招式预警视觉（move 结束即清）


func _test_init(r: Dictionary) -> void:
	super(r)
	_reset_fire_state()
	_rain_rng = RngSvc.stream(RunState.floor_idx, RAIN_RNG_SALT)


func setup(r: Dictionary) -> void:
	super(r)
	_reset_fire_state()
	_rain_rng = RunState.stream(RAIN_RNG_SALT)


## EnemyFactory 直接构造 MagmaTyrant；BossBase._test_init 正常解析阶段。
## 守卫保留给手工构造后遗漏初始化的调试路径（同 VineColossus）。
func _ensure_phases() -> void:
	if _phase_thresholds.is_empty():
		_parse_phases(row)


func _reset_fire_state() -> void:
	_magma = HazardMagma.new()
	_erupt_centers = []
	_erupt_untils = []
	_fx_free(_zone_fx)
	_erupt_standing = 0
	_fire_rain = HazardMagma.FireRain.new()
	_rain_targets = []
	_rain_waves_scheduled = 0
	_wave_front = 0.0
	_wave_hit_done = false


## 怒气常驻门：HP<60%（阶段 1）起生效，只进不退（BossBase 阶段语义保证）。
func rage_active() -> bool:
	return phase() >= 1


## 怒气弹幕密度倍率：E.5「弹幕密度 ×1.5」在暴君招式面上的映射点——岩浆喷发区块数
## （火雨圈数保持 E.5 定数 12，见类头偏差披露）。
func _density_count(base: int) -> int:
	return ceili(base * RAGE_DENSITY_MULT) if rage_active() else base


func _engage(frame: int) -> void:
	_ensure_phases()
	_pursue_step()                          # 追走（怒气 +20% 移速）为常驻行为
	_erupt_tick(frame)                      # 岩浆区为背景效果：跨招式持续结算
	_rain_tick()                            # 火雨红圈为背景效果：跨招式持续结算
	if _move == "":
		_start_move(_pick_move(), frame)
	_advance_move(frame)


## 阶段招式表（递增：P2 含 P1/P0 全部；新招居首——入阶段尽快登场）。
func _move_list() -> Array[String]:
	match phase():
		0:
			return ["erupt", "fist"]
		1:
			return ["rain", "erupt", "fist"]
		_:
			return ["wave", "rain", "erupt", "fist"]


func _pick_move() -> String:
	var list := _move_list()
	var m: String = list[_seq_idx % list.size()]
	_seq_idx += 1
	return m


func _on_phase_enter(_phase_idx: int) -> void:
	_seq_idx = 0                            # 换阶段重开序列


func die() -> void:
	_magma.zones.clear()                    # 岩浆区随 Boss 退场清空
	_erupt_untils.clear()
	_fx_free(_zone_fx)
	_fx_free(_fx)
	_fx_free(_rain_fx)
	super()                                 # EnemyBase.die：状态门/死亡爆/信号/退场


# ---- 招式状态机 ----

func _start_move(m: String, frame: int) -> void:
	_move = m
	_move_start = frame
	_wave_hit_done = false
	_rain_waves_scheduled = 0
	Fx.on_enemy_hit(self, {"telegraph": true})   # 前摇进入拍红闪预警（同 shooter/charger/vine）
	match m:
		"erupt":
			_erupt_centers = _generate_erupt_centers()
			for c in _erupt_centers:        # 红纹预警：落点区外接方（2r 见方，同 T10 区几何）；
				# 视觉入 _zone_fx——预警矩形保留至岩浆区过期（fix1：喷发拍后区仍存续 5s）
				_zone_fx.append(_fx_rect(c, Vector2(_erupt_zone_side_px(), _erupt_zone_side_px()),
					Color(1.0, 0.25, 0.2, 0.3)))
		"fist":
			_fist_facing = (_player_pos() - brain_pos).angle()   # 朝向前摇起始拍锁定
			_fx_wedge(FIST_RANGE_PX, float(FIST_ARC_DEG), Color(1.0, 0.25, 0.2, 0.35))
		"rain":
			_rain_targets = []              # 各波落点随排程拍生成（预警红圈同拍出现）
		"wave":
			_wave_anchor = brain_pos        # 扩散心 = 前摇起始拍 Boss 位
			_wave_front = 0.0
			_wave_vis = _fx_wave_ring()
		_:
			pass


## 喷发区外接方边长（2r，T10 岩浆池几何）。
func _erupt_zone_side_px() -> float:
	return ERUPT_ZONE_RADIUS_PX * 2.0


func _advance_move(frame: int) -> void:
	var elapsed := frame - _move_start
	match _move:
		"erupt":
			if elapsed >= ERUPT_WINDUP_TICKS:
				_erupt_resolve(frame)
				_end_move()
		"fist":
			if elapsed >= FIST_WINDUP_TICKS:
				_fist_resolve()
				_end_move()
		"rain":
			while _rain_waves_scheduled < RAIN_WAVES \
					and elapsed >= _rain_waves_scheduled * RAIN_WAVE_GAP_TICKS:
				_rain_schedule_wave()
			if _rain_waves_scheduled >= RAIN_WAVES:
				_end_move()                 # 红圈为背景效果：排程完即释放招式位
		"wave":
			var t := elapsed - WAVE_WINDUP_TICKS
			if t >= 0:
				_wave_front = minf(float(t) * (WAVE_SPEED_PXPS / TimeConst.FPS),
					WAVE_MAX_RADIUS_PX)
				_sync_wave_vis()
				_wave_hit_check()
			if _wave_front >= WAVE_MAX_RADIUS_PX:
				_end_move()
		_:
			pass


func _end_move() -> void:
	_move = ""
	_move_start = -1
	_wave_vis = null
	_fx_clear()


# ---- 岩浆喷发 ----

## 前摇起始拍以玩家位为心生成 n 块区心（72px 环均布，夹进房内域），无随机（可预读）。
func _generate_erupt_centers() -> Array[Vector2]:
	var n := _density_count(ERUPT_BASE_COUNT)
	var centers: Array[Vector2] = []
	var base := _player_pos()
	for i in range(n):
		var pos := base + Vector2.from_angle(TAU * float(i) / float(n)) * ERUPT_RING_PX
		centers.append(_clamp_to_bounds(pos, ERUPT_ZONE_RADIUS_PX))
	return centers


## 喷发拍：区入 T10 HazardMagma（各 5s 独立到期）+ 站区内玩家爆发 7（恰一跳；
## 区内判定同 T10 in_magma 口径 = 区外接方矩形 has_point，非 r 圆——角落一致，fix1）。
func _erupt_resolve(frame: int) -> void:
	var side := _erupt_zone_side_px()
	var new_zones: Array[Rect2] = []
	for c in _erupt_centers:
		var rect := Rect2(c - Vector2(side, side) / 2.0, Vector2(side, side))
		_magma.add_zone(rect)
		new_zones.append(rect)
		_erupt_untils.append(frame + ERUPT_DURATION_TICKS)
	var pp := _player_pos()
	for rect in new_zones:
		if rect.has_point(pp):
			_hit_player(ERUPT_BURST_DMG, {"element": Elements.Id.FIRE, "attack_name": "岩浆喷发"})
			break                            # 喷发拍恰一跳（多区重叠不叠伤）


## 岩浆区背景结算：过期区自清（区视觉同步释放——预警矩形持续至区过期，fix1）；
## 站区内驻留满 HazardMagma.PULSE_TICKS 出一跳（伤害/抗火减半均取 T10 pulse_damage
## 纯函数；出域暂停驻留拍不清零）。
func _erupt_tick(frame: int) -> void:
	if _magma.zones.is_empty():
		return
	for i in range(_magma.zones.size() - 1, -1, -1):
		if frame > _erupt_untils[i]:
			_magma.zones.remove_at(i)
			_erupt_untils.remove_at(i)
			if i < _zone_fx.size() and is_instance_valid(_zone_fx[i]):
				_zone_fx[i].queue_free()
			_zone_fx.remove_at(i)
	if _magma.zones.is_empty():
		return
	if not _magma.in_magma(_player_pos()):
		return
	_erupt_standing += 1
	if _erupt_standing >= HazardMagma.PULSE_TICKS:
		_erupt_standing = 0
		_hit_player(HazardMagma.pulse_damage(_anti_fire()),
			{"element": Elements.Id.FIRE, "attack_name": "岩浆区"})


## 玩家抗火 meta 读取（T12 buff_anti_fire 0/1；与 HazardMagma.has_anti_fire 同键）。
func _anti_fire() -> bool:
	return player_ref != null and is_instance_valid(player_ref) \
		and int(player_ref.get_meta(HazardMagma.ANTI_FIRE_META, 0)) != 0


# ---- 火拳 ----

func _fist_resolve() -> void:
	var to := _player_pos() - brain_pos
	if to.length() > FIST_RANGE_PX:
		return
	if absf(angle_difference(_fist_facing, to.angle())) > deg_to_rad(FIST_ARC_DEG) / 2.0:
		return
	_hit_player(FIST_DMG, {"attack_name": "火拳"})


# ---- 火雨 ----

## 排程一波红圈（怒气后仍为 4/波——E.5 定数 12）：落点分盐流夹内域，
## 经 HazardMagma.FireRain.schedule 进入 48t 预警倒计时，红圈预警同拍出现。
func _rain_schedule_wave() -> void:
	var legal := combat_bounds.grow(-8.0) if combat_bounds.has_area() \
		else Rect2(brain_pos - Vector2(200, 100), Vector2(400, 200))
	for _i in range(RAIN_BASE_PER_WAVE):
		var pos := Vector2(
			_rain_rng.randf_range(legal.position.x, legal.end.x),
			_rain_rng.randf_range(legal.position.y, legal.end.y))
		_rain_targets.append(pos)
		_fire_rain.schedule(pos)
		_rain_fx.append(_fx_red_circle(pos, HazardMagma.FireRain.RADIUS_PX))
	_rain_waves_scheduled += 1


## 火雨背景结算：组件倒计时推进 + 恰 boom 拍对玩家结算（伤/半径在 FireRain 契约内）；
## 红圈预警与 strikes FIFO 对齐，落点下一拍随 strike 自除。
func _rain_tick() -> void:
	if _fire_rain.strike_count() == 0:
		return
	_fire_rain.tick()
	var dmg := _fire_rain.striking_at(_player_pos())
	if dmg > 0:
		_hit_player(dmg, {"element": Elements.Id.FIRE, "attack_name": "火雨"})
	while _rain_fx.size() > _fire_rain.strike_count():
		var vis: Node = _rain_fx.pop_front()
		if is_instance_valid(vis):
			vis.queue_free()


# ---- 地裂火浪 ----

## 前沿越过玩家位拍结算 8（恰一跳）；掩体挡线（Boss→玩家线段过掩体判定圆）则免伤。
func _wave_hit_check() -> void:
	if _wave_hit_done:
		return
	var pp := _player_pos()
	if _wave_anchor.distance_to(pp) > _wave_front:
		return                          # 火浪前沿尚未到达
	_wave_hit_done = true
	if _cover_blocked(_wave_anchor, pp):
		return
	_hit_player(WAVE_DMG, {"attack_name": "地裂火浪"})


## 掩体遮挡判定：任一掩体心到 Boss→玩家线段距离 ≤ 掩体判定圆即挡。
func _cover_blocked(from: Vector2, to: Vector2) -> bool:
	for c in cover_points:
		if _segment_distance(Vector2(c), from, to) <= COVER_RADIUS_PX:
			return true
	return false


## 点到线段距离（夹参投影；零长线段退化为点距）。
static func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := 0.0 if ab.length_squared() < 0.0001 \
		else clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


# ---- 追走（怒气移速 +20% 的载体）----

## 常驻缓慢逼近玩家（行 speed px/s；怒气 ×1.2），夹进房内域；贴身（接触口径）即停。
func _pursue_step() -> void:
	var to := _player_pos() - brain_pos
	if to.length() <= combat_radius() + 6.0:
		return
	var mult := RAGE_SPEED_MULT if rage_active() else 1.0
	brain_pos = _clamp_to_bounds(
		brain_pos + to.normalized() * (float(row.get("speed", 24)) * mult / TimeConst.FPS))


## 夹进房内域（同 PrismGolem）。
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
		"source_type": "boss", "source_id": String(row.get("id", "magma_tyrant")),
		"source_name": String(row.get("name", "熔核暴君")), "attack_name": "攻击",
	}
	ctx.merge(extra, true)
	player_ref.take_hit(ctx)


# ---- 预警/效果视觉（脑层挂子节点，测试无树亦安全；玩家可读性归 GDD §7.5）----

func _fx_rect(center: Vector2, size: Vector2, color: Color) -> Polygon2D:
	var half := size / 2.0
	var vis := Polygon2D.new()
	vis.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y),
	])
	vis.color = color
	vis.z_index = 15
	vis.position = center - brain_pos
	add_child(vis)
	return vis


func _fx_wedge(radius: float, arc_deg: float, color: Color) -> void:
	var pts := PackedVector2Array([Vector2.ZERO])
	var n := 12
	for i in range(n + 1):
		var a := _fist_facing + deg_to_rad(arc_deg) * (float(i) / float(n) - 0.5)
		pts.append(Vector2.from_angle(a) * radius)
	var vis := Polygon2D.new()
	vis.polygon = pts
	vis.color = color
	vis.z_index = 15
	add_child(vis)
	_fx.append(vis)


func _fx_red_circle(center: Vector2, radius: float) -> Polygon2D:
	var vis := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in range(24):
		pts.append(Vector2.from_angle(TAU * float(i) / 24.0) * radius)
	vis.polygon = pts
	vis.color = Color(1.0, 0.25, 0.2, 0.3)      # 红圈落点预警
	vis.z_index = 15
	vis.position = center - brain_pos
	add_child(vis)
	return vis


## 扩散红环：满径多边形 + 缩放承载前沿半径（move 结束随 _fx 清）。
func _fx_wave_ring() -> Polygon2D:
	var vis := _fx_red_circle(_wave_anchor, WAVE_MAX_RADIUS_PX)
	vis.scale = Vector2.ZERO
	_fx.append(vis)
	return vis


func _sync_wave_vis() -> void:
	if _wave_vis != null and is_instance_valid(_wave_vis):
		_wave_vis.scale = Vector2.ONE * (_wave_front / WAVE_MAX_RADIUS_PX)


func _fx_clear() -> void:
	_fx_free(_fx)


func _fx_free(list: Array[Node]) -> void:
	for node in list:
		if is_instance_valid(node):
			node.queue_free()
	list.clear()
