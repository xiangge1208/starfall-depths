class_name StarfallProphet
extends BossBase
## 星陨先知（A3 隐藏 Boss，附录 E.6，HP 3200）：P1 元素轮回（火环/冰针/毒云/电链
## 四轮各 24t，轮回序跨施法延续）+ 星陨（3 颗追踪星体坠落——ENEMY 弹被近战反弹
## 窗 combat.reflect 翻面后即停追踪、可击回 Boss，教玩家「反打」）；P2（60%）
## 单元素领域（重施切换元素、8s 内存续招式弹/直击带领域元素——「领域内敌我伤害
## 转化」的 Boss 侧口径）+ 共鸣斩（对已有异常玩家强制附加第二状态：
## StatusComponent.force_resonance 按状态契约结算，共鸣伤害载荷经
## resonance_event.last_damage（=斩击伤 8）由状态消费方结算——本招为单一伤害
## 实例（伤 8=附录 E.6 共鸣斩伤值；fix 评审 I-1：真实 Player 受击无敌帧下同拍
## 无可被吞的第二击，测试替身与生产契约一致））；P3（30%）星河（滚筒
## 弹幕墙 ×3 波横向推进，每波 12 行含 2×2 行缺口=安全通道（缺口行向内收一行：
## g1∈[1,4]/g2∈[7,10]，fix 评审 M-4——贴边缺口自由窗过窄）；期间召唤 2 星髓聚合体）。
## 隐藏门接线在 FloorScene（A3 携带任意共鸣击杀小 Boss → 开门入场）。
## 招式序列状态机同 VineColossus/GemQueen；前摇 ≥24t（GDD §15）；数值逐字附录 E.6。

# ---- 前摇（GDD §15 下限 24t；数值逐字附录 E.6）----
const MIN_WINDUP_TICKS := 24
const CYCLE_WINDUP_TICKS := 36       # 0.6s
const STARFALL_WINDUP_TICKS := 48    # 0.8s
const FIELD_WINDUP_TICKS := 60       # 1.0s
const SLASH_WINDUP_TICKS := 30       # 0.5s
const GALAXY_WINDUP_TICKS := 72      # 1.2s

# ---- 元素轮回（P1）：每轮一种元素弹幕（火环/冰针/毒云/电链）×4 轮（24t 间隔）；
#      轮回游标跨施法延续（火→冰→毒→电→火…）----
const CYCLE_ROUNDS := 4
const CYCLE_WAVE_GAP_TICKS := 24
const CYCLE_ELEMENTS: Array[int] = [Elements.Id.FIRE, Elements.Id.ICE,
	Elements.Id.POISON, Elements.Id.SHOCK]
const FIRE_RING_COUNT := 12          # 火环：12 发全环均布
const ICE_NEEDLE_COUNT := 5          # 冰针：5 发扇形（±30°）锁定玩家
const ICE_FAN_DEG := 60.0
const POISON_ORB_COUNT := 4          # 毒云：4 发慢速大弹（云团口径）
const POISON_FAN_DEG := 60.0
const POISON_SPEED_PX := 60.0
const POISON_RADIUS_PX := 8.0
const POISON_LIFE_SECONDS := 3.5
const SHOCK_CHAIN_COUNT := 4         # 电链：4 发快索（±12° 窄扇，弹速契约 ≤150）
const SHOCK_FAN_DEG := 24.0
const SHOCK_SPEED_PX := 150.0

# ---- 星陨（P1）：3 颗追踪星体（伤 7 r6）；ENEMY 面翻 PLAYER 即出追踪集（可近战反弹）----
const STAR_COUNT := 3
const STAR_DMG := 7
const STAR_RADIUS_PX := 6.0
const STAR_LIFE_SECONDS := 4.0
const STAR_SPREAD_DEG := 50.0        # 落星初始朝向扇（±25°）
const STAR_TURN_RAD_PER_TICK := 0.035   # ≈2°/拍 追踪转向率

# ---- 单元素领域（P2）：重施切换元素并重锚窗口；领域元素序 火→冰→毒→电 轮转 ----
const FIELD_DURATION_TICKS := 480    # 8s
const FIELD_ORDER: Array[int] = [Elements.Id.FIRE, Elements.Id.ICE,
	Elements.Id.POISON, Elements.Id.SHOCK]

# ---- 共鸣斩（P2）：近身扇形 90°/70px 伤 8（单一伤害实例，附录 E.6）；
#      对已有异常玩家强制附加第二状态（StatusComponent.force_resonance——共鸣伤害
#      载荷经 resonance_event.last_damage 结算，不另发第二击：评审 I-1 契约修复）----
const SLASH_RANGE_PX := 70.0
const SLASH_ARC_DEG := 90.0
const SLASH_DMG := 8

# ---- 星河（P3）：滚筒弹幕墙 ×3 波（48t 间隔）横向推进，方向交替；每波 12 行
#      其中 2 缺口×2 行（缺口罩间=安全通道，前/后半区各一）；期间召唤 2 星髓聚合体 ----
const GALAXY_WAVES := 3
const GALAXY_WAVE_GAP_TICKS := 48
const GALAXY_ROWS := 12
const GALAXY_ROW_GAP_PX := 20.0
const GALAXY_GAP_COUNT := 2
const GALAXY_GAP_ROWS := 2
const GALAXY_LIFE_SECONDS := 5.0     # 全屏横穿（456px @100px/s ≈ 4.6s）
const GALAXY_SUMMON_ARCHETYPE := "starmarrow_blob"
const GALAXY_SUMMON_COUNT := 2
const GALAXY_SUMMON_OFFSET_PX := 48.0
const GALAXY_RNG_SALT := "boss_starfall_prophet_galaxy"

# ---- 招式序列状态 ----
var _move := ""                      # 当前招式（"" = 选招中）
var _move_start := -1
var _seq_idx := 0                    # 招式表游标（跨阶段延续，入新阶段重置）
var _cycle_round := 0                # 轮回游标（跨施法延续，不随施法重置）
var _cycle_rounds_fired := 0         # 本轮施法已发轮数（招式位内状态，_start_move 重置）
var _field_element := Elements.Id.NONE   # 当前领域元素（NONE = 无领域）
var _field_until := -1
var _field_round := 0                # 领域元素序游标（跨施法延续）
var _slash_facing := 0.0             # 共鸣斩朝向（前摇起始拍锁定）
var _galaxy_waves_fired := 0
var _galaxy_base_dir := 1            # 施法首波方向（+1 左→右先行）
var _galaxy_waves: Array = []        # 逐波记录面 [{"dir": int, "ys": Array[float]}]
var _galaxy_rng: RandomNumberGenerator = null
var _stars_active := false           # 星陨追踪粘性门控（施法置位/池内无星清零——评审 M-1）
var _fx: Array[Node] = []            # 招式预警视觉（move 结束即清）


func _test_init(r: Dictionary) -> void:
	super(r)
	_galaxy_rng = RngSvc.stream(RunState.floor_idx, GALAXY_RNG_SALT)


func setup(r: Dictionary) -> void:
	super(r)
	_galaxy_rng = RunState.stream(GALAXY_RNG_SALT)


## EnemyFactory 直接构造 StarfallProphet；BossBase._test_init 正常解析阶段。
## 守卫保留给手工构造后遗漏初始化的调试路径（同 VineColossus）。
func _ensure_phases() -> void:
	if _phase_thresholds.is_empty():
		_parse_phases(row)


func _engage(frame: int) -> void:
	_ensure_phases()
	_field_tick(frame)                      # 领域为背景状态：跨招式存续/到期
	_stars_home_tick()                      # 星陨追踪为背景效果：跨招式持续转向
	if _move == "":
		_start_move(_pick_move(), frame)
	_advance_move(frame)


## 阶段招式表（递增，附录 E.6）：P1 轮回/星陨；P2 +领域/共鸣斩；P3 +星河。
func _move_list() -> Array[String]:
	match phase():
		0:
			return ["cycle", "starfall"]
		1:
			return ["field", "slash", "cycle", "starfall"]
		_:
			return ["galaxy", "field", "slash", "cycle", "starfall"]


func _pick_move() -> String:
	var list := _move_list()
	var m: String = list[_seq_idx % list.size()]
	_seq_idx += 1
	return m


func _on_phase_enter(_phase_idx: int) -> void:
	_seq_idx = 0                            # 换阶段重开序列


# ---- 招式状态机 ----

func _start_move(m: String, frame: int) -> void:
	_move = m
	_move_start = frame
	_galaxy_waves_fired = 0
	_cycle_rounds_fired = 0
	_galaxy_waves.clear()
	Fx.on_enemy_hit(self, {"telegraph": true})   # 前摇进入拍红闪预警（同 shooter/vine）
	match m:
		"slash":
			_slash_facing = (_player_pos() - brain_pos).angle()   # 朝向前摇起始拍锁定
			_fx_wedge(SLASH_RANGE_PX, SLASH_ARC_DEG, Color(1.0, 0.25, 0.2, 0.35))
		"field":
			var el := FIELD_ORDER[_field_round % FIELD_ORDER.size()]
			_fx_ring(Color(0.5, 0.75, 1.0, 0.3) if el == Elements.Id.ICE
				else Color(1.0, 0.4, 0.2, 0.3) if el == Elements.Id.FIRE
				else Color(0.4, 0.9, 0.35, 0.3) if el == Elements.Id.POISON
				else Color(1.0, 0.9, 0.3, 0.3))
		"cycle":
			pass                             # 轮回逐轮弹幕：红闪已示
		"starfall":
			pass                             # 落星预警由星体本体承载
		"galaxy":
			pass                             # 滚筒墙预警由墙体弹幕承载（整拍红闪已示）
		_:
			pass


func _advance_move(frame: int) -> void:
	var elapsed := frame - _move_start
	match _move:
		"cycle":
			while _cycle_rounds_fired < CYCLE_ROUNDS and elapsed \
					>= CYCLE_WINDUP_TICKS + _cycle_rounds_fired * CYCLE_WAVE_GAP_TICKS:
				_cycle_fire_round(frame)
				_cycle_rounds_fired += 1
			if _cycle_rounds_fired >= CYCLE_ROUNDS:
				_end_move()
		"starfall":
			if elapsed >= STARFALL_WINDUP_TICKS:
				_starfall_resolve()
				_end_move()
		"field":
			if elapsed >= FIELD_WINDUP_TICKS:
				_field_resolve(frame)
				_end_move()
		"slash":
			if elapsed >= SLASH_WINDUP_TICKS:
				_slash_resolve(frame)
				_end_move()
		"galaxy":
			while _galaxy_waves_fired < GALAXY_WAVES and elapsed \
					>= GALAXY_WINDUP_TICKS + _galaxy_waves_fired * GALAXY_WAVE_GAP_TICKS:
				_galaxy_fire_wave(_galaxy_waves_fired, frame)
				_galaxy_waves_fired += 1
			if _galaxy_waves_fired >= GALAXY_WAVES:
				_end_move()
		_:
			pass


func _end_move() -> void:
	_move = ""
	_move_start = -1
	_fx_clear()


# ---- 元素轮回 ----

## 当前轮的元素弹幕（轮回序 火→冰→毒→电，跨施法延续）。
func _cycle_fire_round(frame: int) -> void:
	fired_this_tick = true
	if combat == null:
		return
	var element: int = CYCLE_ELEMENTS[_cycle_round % CYCLE_ELEMENTS.size()]
	_cycle_round += 1
	var speed := enemy_bullet_speed(100)
	var dmg := int(row.get("bullet_dmg", 6))
	var aim := _aim_at_player()
	var field_el := _spawn_element()   # 领域存续：轮回弹伤害同转化为领域元素（附录 E.6 P2）
	var count := 0
	var attack := ""
	match element:
		Elements.Id.FIRE:
			count = FIRE_RING_COUNT
			attack = "火环"
		Elements.Id.ICE:
			count = ICE_NEEDLE_COUNT
			attack = "冰针"
		Elements.Id.POISON:
			count = POISON_ORB_COUNT
			attack = "毒云"
		_:
			count = SHOCK_CHAIN_COUNT
			attack = "电链"
	for i in range(count):
		var off := 0.0
		var vel_speed := speed
		var radius := float(row.get("bullet_radius", 4.0))
		var life := float(row.get("bullet_life_seconds", 2.5))
		match element:
			Elements.Id.FIRE:
				off = 0.0
				vel_speed = speed
			Elements.Id.ICE:
				off = deg_to_rad(ICE_FAN_DEG) * (float(i) / float(count - 1) - 0.5)
			Elements.Id.POISON:
				off = deg_to_rad(POISON_FAN_DEG) * (float(i) / float(count - 1) - 0.5)
				vel_speed = POISON_SPEED_PX
				radius = POISON_RADIUS_PX
				life = POISON_LIFE_SECONDS
			_:
				off = deg_to_rad(SHOCK_FAN_DEG) * (float(i) / float(count - 1) - 0.5)
				vel_speed = SHOCK_SPEED_PX
		var dir := TAU * float(i) / float(count) if element == Elements.Id.FIRE else aim + off
		combat.spawn_projectile({
			"pos": brain_pos, "vel": Vector2.from_angle(dir) * vel_speed,
			"damage": dmg, "faction": Projectile.Faction.ENEMY,
			"element": field_el if field_el != Elements.Id.NONE else element,
			"pierce": 0, "bounce": 0,
			"life_seconds": life, "radius": radius,
			"source_type": "projectile", "source_id": String(row.get("id", "")),
			"source_name": String(row.get("name", row.get("id", ""))), "attack_name": attack,
		})


# ---- 星陨 ----

## 3 颗追踪星体（伤 7 r6）：ENEMY 弹入场，此后每拍 _stars_home_tick 向玩家转向；
## 近战反弹窗 combat.reflect 翻 PLAYER 面即出追踪集（可击回 Boss——教玩家反打）。
func _starfall_resolve() -> void:
	fired_this_tick = true
	if combat == null:
		return
	_stars_active = true              # 追踪粘性置位（池内无星自动清零——评审 M-1）
	var speed := enemy_bullet_speed(100)
	var aim := _aim_at_player()
	for i in range(STAR_COUNT):
		var a := aim + deg_to_rad(STAR_SPREAD_DEG) * (float(i) / float(STAR_COUNT - 1) - 0.5)
		combat.spawn_projectile({
			"pos": brain_pos, "vel": Vector2.from_angle(a) * speed,
			"damage": STAR_DMG, "faction": Projectile.Faction.ENEMY,
			"element": _spawn_element(), "pierce": 0, "bounce": 0,
			"life_seconds": STAR_LIFE_SECONDS, "radius": STAR_RADIUS_PX,
			"source_type": "projectile", "source_id": String(row.get("id", "")),
			"source_name": String(row.get("name", row.get("id", ""))), "attack_name": "星陨",
		})


## 存活追踪星体（ENEMY 面 + 星陨标记——反弹后翻面自动出集）。
## fix 评审 M-1：扫描以 _stars_active 粘性门控——星陨施法置位、扫描未见星清零；
## 无星拍零分配零池扫描（热路径守恒，同 magma_tyrant 背景结算手法）。
func _live_stars() -> Array:
	if combat == null or not _stars_active:
		return []
	var out: Array = []
	for p in combat.pool.active:
		if p.faction == Projectile.Faction.ENEMY and p.attack_name == "星陨":
			out.append(p)
	if out.is_empty():
		_stars_active = false
	return out


## 追踪转向：星体速度向玩家方向收拢，每拍至多 STAR_TURN_RAD_PER_TICK（≈2°）。
func _stars_home_tick() -> void:
	if combat == null or player_ref == null:
		return
	for p in _live_stars():
		var proj := p as Projectile
		var to: Vector2 = _player_pos() - proj.position
		if to.length() < 0.01 or proj.vel.length() < 0.01:
			continue
		var diff := angle_difference(proj.vel.angle(), (to.normalized() * proj.vel.length()).angle())
		proj.vel = proj.vel.rotated(clampf(diff, -STAR_TURN_RAD_PER_TICK, STAR_TURN_RAD_PER_TICK))


# ---- 单元素领域 ----

## 领域内存续招式弹/直击的元素口径（Boss 侧「敌我伤害转化」）。
func _spawn_element() -> int:
	return _field_element


## 领域到期清空（重施在 _field_resolve 覆写 = 切换）。
func _field_tick(frame: int) -> void:
	if _field_element != Elements.Id.NONE and frame >= _field_until:
		_field_element = Elements.Id.NONE
		_field_until = -1


func _field_resolve(frame: int) -> void:
	_field_element = FIELD_ORDER[_field_round % FIELD_ORDER.size()]
	_field_round += 1
	_field_until = frame + FIELD_DURATION_TICKS


# ---- 共鸣斩 ----

## 玩家已有异常元素：鸭子接缝 StatusComponent.active 优先（真实玩家侧状态持有者），
## 否则领域存续期玩家被视为携带领域元素（领域=制造异常的来源）。无则 NONE。
func _player_anomaly_element() -> int:
	var st: Node = player_ref.get("status") if player_ref != null else null
	if st != null and not (st as StatusComponent).active.is_empty():
		for element: int in Resonance.ELEMENT_ORDER:
			if (st as StatusComponent).active.has(element):
				return element
	if _field_element != Elements.Id.NONE:
		return _field_element
	return Elements.Id.NONE


## 本击（伤 8 单一伤害实例，扇内）+ 对已有异常玩家强制附加第二状态：
## StatusComponent.force_resonance（状态契约结算：清两元素激活表 + resonance_event
## 落 reaction/last_damage/forced，共鸣伤害载荷由状态消费方按 last_damage 结算）。
## fix 评审 I-1：不再同拍发第二击——真实 Player 受击无敌帧会吞掉同拍二击，
## 单一伤害实例使测试替身与生产契约一致。
func _slash_resolve(frame: int) -> void:
	var to := _player_pos() - brain_pos
	if to.length() > SLASH_RANGE_PX:
		return
	if absf(angle_difference(_slash_facing, to.angle())) > deg_to_rad(SLASH_ARC_DEG) / 2.0:
		return
	_hit_player(SLASH_DMG, {"element": _spawn_element(), "attack_name": "共鸣斩"})
	var anomaly := _player_anomaly_element()
	if anomaly == Elements.Id.NONE:
		return
	var partner := Resonance.compatible_partner(anomaly)
	if partner == Elements.Id.NONE:
		return
	var st: Node = player_ref.get("status") if player_ref != null else null
	if st != null:
		(st as StatusComponent).force_resonance(partner, SLASH_DMG, frame)


# ---- 星河 ----

## 逐波滚筒墙：12 行纵向均布（内域纵向居中），前/后半区各 1 缺口×2 行（分盐流确定）；
## 横向纯推进，方向交替（+1/-1/+1）。首波起同时召唤 2 星髓聚合体。
func _galaxy_fire_wave(wave: int, _frame: int) -> void:
	fired_this_tick = true
	if wave == 0:
		_galaxy_summon()
	if combat == null:
		return
	if _galaxy_rng == null:           # 懒初始化护栏（同 vine_colossus/magma_tyrant，评审 M-3）
		_galaxy_rng = RngSvc.stream(RunState.floor_idx, GALAXY_RNG_SALT)
	var wave_dir := _galaxy_base_dir if wave % 2 == 0 else -_galaxy_base_dir
	var speed := enemy_bullet_speed(100)
	var dmg := int(row.get("bullet_dmg", 6))
	var bounds := combat_bounds if combat_bounds.has_area() \
		else Rect2(brain_pos - Vector2(240, 120), Vector2(480, 240))
	var x0 := bounds.position.x - 8.0 if wave_dir > 0 else bounds.end.x + 8.0
	var center_y := bounds.get_center().y
	# 前/后半区各一缺口（缺口行向内收一行，评审 M-4：贴边缺口自由窗过窄）——
	# 首缺口 ⊆ [1,4]、次缺口 ⊆ [7,10]，两缺口不重叠且不贴墙带
	var g1 := _galaxy_rng.randi_range(1, GALAXY_ROWS / 2 - GALAXY_GAP_ROWS)
	var g2 := _galaxy_rng.randi_range(GALAXY_ROWS / 2 + 1, GALAXY_ROWS - GALAXY_GAP_ROWS)
	var ys: Array = []
	for r in range(GALAXY_ROWS):
		var in_gap := (r >= g1 and r < g1 + GALAXY_GAP_ROWS) \
			or (r >= g2 and r < g2 + GALAXY_GAP_ROWS)
		if in_gap:
			continue
		var y := center_y + (float(r) - float(GALAXY_ROWS - 1) / 2.0) * GALAXY_ROW_GAP_PX
		ys.append(y)
		combat.spawn_projectile({
			"pos": Vector2(x0, y), "vel": Vector2(wave_dir * speed, 0.0),
			"damage": dmg, "faction": Projectile.Faction.ENEMY,
			"element": _spawn_element(), "pierce": 0, "bounce": 0,
			"life_seconds": GALAXY_LIFE_SECONDS,
			"radius": float(row.get("bullet_radius", 4.0)),
			"source_type": "projectile", "source_id": String(row.get("id", "")),
			"source_name": String(row.get("name", row.get("id", ""))), "attack_name": "星河",
		})
	_galaxy_waves.append({"dir": wave_dir, "ys": ys})


## 星河期间召唤 2 星髓聚合体（附录 E.6；同 VineColossus 召唤缝：行数据驱动落位）。
func _galaxy_summon() -> void:
	if not spawn_callback.is_valid():
		return
	for i in range(GALAXY_SUMMON_COUNT):
		var side := 1.0 if i % 2 == 0 else -1.0
		spawn_callback.call(GALAXY_SUMMON_ARCHETYPE,
			brain_pos + Vector2(GALAXY_SUMMON_OFFSET_PX * side, 0.0), {})


# ---- 共用 helpers ----

func _aim_at_player() -> float:
	return (_player_pos() - brain_pos).angle()


# ---- 玩家结算（同 VineColossus）----

func _hit_player(dmg: int, extra: Dictionary) -> void:
	if player_ref == null or not player_ref.has_method("take_hit"):
		return
	var ctx := {
		"amount": dmg, "is_crit": false, "element": Elements.Id.NONE, "from": brain_pos,
		"source_type": "boss", "source_id": String(row.get("id", "starfall_prophet")),
		"source_name": String(row.get("name", "星陨先知")), "attack_name": "攻击",
	}
	ctx.merge(extra, true)
	player_ref.take_hit(ctx)


# ---- 预警视觉（脑层挂子节点，测试无树亦安全；同 VineColossus 手法）----

func _fx_wedge(radius: float, arc_deg: float, color: Color) -> Node2D:
	var pts := PackedVector2Array([Vector2.ZERO])
	var n := 12
	for i in range(n + 1):
		var a := _slash_facing + deg_to_rad(arc_deg) * (float(i) / float(n) - 0.5)
		pts.append(Vector2.from_angle(a) * radius)
	var vis := Polygon2D.new()
	vis.polygon = pts
	vis.color = color
	vis.z_index = 15
	add_child(vis)
	_fx.append(vis)
	return vis


## 领域圈预警（Boss 为心 r96 圆，色随领域元素）。
func _fx_ring(color: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(24):
		pts.append(Vector2.from_angle(TAU * float(i) / 24.0) * 96.0)
	var vis := Polygon2D.new()
	vis.polygon = pts
	vis.color = color
	vis.z_index = 15
	add_child(vis)
	_fx.append(vis)


func _fx_clear() -> void:
	for node in _fx:
		if is_instance_valid(node):
			node.queue_free()
	_fx.clear()
