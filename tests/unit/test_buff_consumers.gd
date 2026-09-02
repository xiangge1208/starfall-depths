class_name TestBuffConsumers
extends GdUnitTestSuite
## m4-c3：增益消费端 ×10 键（buff_manager.gd「消费方待接线」清账）。
## 十键 → 消费端映射（buffs.json 行值）：
##   hunter          dmg_vs_statused_pct 0.2      → CombatSystem 命中结算全局乘区
##   resonance_amp   resonance_radius_pct 0.3
##                   resonance_duration_ticks 60 → CombatSystem 燎原毒火云（Resonance 读数）
##   avenger         vengeance_pct 0.25
##                   vengeance_ticks 180         → Player.take_hit_ctx 开窗 + CombatSystem 读窗
##   element_vision  element_vision 1
##                   telegraph_bonus_ticks 9     → EnemyBase 预警窗延长 + 预警高亮（展示）
##   resonance_vision resonance_vision 1         → EnemyBase 异常状态描边（展示）
##   heart_sense     heart_sense_pct 0.5         → room_combat 房奖励红心掉率 roll
##   anti_poison     anti_poison 1               → player.take_hit_ctx POISON 来伤免疫
## 消费端链路统一走「BuffManager.pick → apply_to_player/apply_to_rig → meta → 消费读点」
## 全通路（与生产同路径），另配直设 meta 的边界/零漂移反例。


# ---- 夹具 ----

func after_test() -> void:
	RunState.start_run("vanguard")   # 复位楼层/种子/聚合（跨套件卫生，m1_integration 同款）


func _root() -> Node2D:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	return root


func _combat(root: Node2D) -> CombatSystem:
	var cs := CombatSystem.new(root, RngSvc.stream(0, "combat"))
	cs.crit_chance = 0.0                       # 乘区与暴击解耦（回响先例同款）
	auto_free(cs)
	root.add_child(cs)
	return cs


func _enemy(root: Node2D, cs: CombatSystem, at: Vector2, hp := 100) -> EnemyBase:
	var e := EnemyBase.new()
	e._test_init({"id": "buff_dummy", "hp": hp, "radius": 6.0})
	e.brain_pos = at
	e.position = at
	root.add_child(e)
	e.add_to_group("enemies")
	cs.register_body(e, e.combat_faction())
	return e


## 激活异常状态（FIRE 单元素不引共鸣）：小怪阈值 2 层 → 两击激活。
func _activate_fire(e: EnemyBase) -> void:
	var now := Engine.get_physics_frames()
	(e.status as StatusComponent).apply_hit(Elements.Id.FIRE, 1, now)
	(e.status as StatusComponent).apply_hit(Elements.Id.FIRE, 1, now)


## 命中结算驱动：弹落在敌心（vel 0），物理帧推进至命中弹退场（test_hero_passives 同款）。
func _fire_at(root: Node2D, cs: CombatSystem, at: Vector2, damage: int) -> void:
	cs.spawn_projectile({
		"pos": at, "vel": Vector2.ZERO, "damage": damage,
		"faction": Projectile.Faction.PLAYER, "element": Elements.Id.NONE,
		"pierce": 0, "bounce": 0, "life_seconds": 1.0, "radius": 3.0,
		"source_type": "projectile", "source_id": "", "source_name": "", "attack_name": "射击",
	})
	for _i in 10:
		await get_tree().physics_frame


func _player_with_rig() -> Array:
	var p: Player = auto_free(Player.new())
	var rig: WeaponRig = auto_free(WeaponRig.new())
	p.weapon_rig = rig
	return [p, rig]


## 受控双流：expect_rng 先算期望值，roll_rng 交被测方——同种子首掷必相同。
func _rigged_rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


class DummyBody extends Node2D:
	var hits: Array = []
	func take_hit(ctx: Dictionary) -> void:
		hits.append(ctx)
	func combat_radius() -> float:
		return 6.0


# ================================================================
# 猎杀者 hunter（dmg_vs_statused_pct 0.2，rig meta）——CombatSystem 全局乘区
# ================================================================

func test_hunter_full_chain_bonus_damage_vs_statused_target() -> void:
	# 全通路：pick hunter → rig meta → 命中异常状态敌 20×1.2=24（GDD §7.1 向下取整）。
	var root := _root()
	var cs := _combat(root)
	var pair := _player_with_rig()
	var p: Player = pair[0]
	cs.player_body = p                        # rig 5 键读点玩家（生产=register_body 捕获）
	var bm := BuffManager.new()
	bm.pick("hunter")
	bm.apply_to_player(p)
	bm.apply_to_rig(p.weapon_rig)
	var e := _enemy(root, cs, Vector2(200, 0), 100)
	_activate_fire(e)
	await _fire_at(root, cs, Vector2(200, 0), 20)
	assert_int(e.hp).is_equal(76)

func test_hunter_no_bonus_below_threshold_stacks_or_clean_target() -> void:
	# 未达阈值层数（GDD「处于异常状态」= 已激活态）与无状态目标均零漂移。
	var root := _root()
	var cs := _combat(root)
	var pair := _player_with_rig()
	var p: Player = pair[0]
	cs.player_body = p
	var bm := BuffManager.new()
	bm.pick("hunter")
	bm.apply_to_player(p)
	bm.apply_to_rig(p.weapon_rig)
	var stacked_only := _enemy(root, cs, Vector2(200, 0), 100)
	(stacked_only.status as StatusComponent).apply_hit(Elements.Id.FIRE, 1,
		Engine.get_physics_frames())          # 1 层 < 2 阈值：active 空
	await _fire_at(root, cs, Vector2(200, 0), 20)
	assert_int(stacked_only.hp).is_equal(80)
	var clean := _enemy(root, cs, Vector2(-200, 0), 100)
	await _fire_at(root, cs, Vector2(-200, 0), 20)
	assert_int(clean.hp).is_equal(80)

func test_hunter_mult_boundary_and_target_predicate() -> void:
	# 乘区与异常判定直测：statused→×1.2；clean/无玩家→1.0。
	var root := _root()
	var cs := _combat(root)
	var pair := _player_with_rig()
	var p: Player = pair[0]
	var rig: WeaponRig = pair[1]
	rig.set_meta("buff_dmg_vs_statused_pct", 0.2)
	cs.player_body = p
	var e := _enemy(root, cs, Vector2(200, 0), 100)
	assert_bool(CombatSystem._target_statused(e)).is_false()
	_activate_fire(e)
	assert_bool(CombatSystem._target_statused(e)).is_true()
	var frame := Engine.get_physics_frames()
	assert_float(cs._player_global_mult(true, {}, e, frame)).is_equal_approx(1.2, 0.0001)
	assert_float(cs._player_global_mult(true, {}, null, frame)).is_equal_approx(1.0, 0.0001)
	cs.player_body = null
	assert_float(cs._player_global_mult(true, {}, e, frame)).is_equal_approx(1.0, 0.0001)

func test_player_body_capture_via_register_and_unregister() -> void:
	# 生产读点捕获缝：register_body 首个 Player 阵营体即玩家；注销清位（跨房不滞留）。
	var root := _root()
	var cs := _combat(root)
	var p: Player = auto_free(Player.new())
	p.position = Vector2(10000, 10000)        # 远离弹径，不参与命中
	cs.register_body(p, Projectile.Faction.PLAYER)
	assert_object(cs.player_body).is_same(p)
	cs.unregister_body(p)
	assert_bool(cs.player_body == null).is_true()

# ================================================================
# 复仇者 avenger（vengeance_pct 0.25 / vengeance_ticks 180，rig meta）
# ——Player.take_hit_ctx 开窗 + CombatSystem 读窗乘区
# ================================================================

func test_avenger_full_chain_window_opens_on_hit_and_boosts_damage() -> void:
	# 受击开窗（3s=180t）→ 窗内命中 20×1.25=25；受击本体掉血 3 不受增益影响。
	var root := _root()
	var cs := _combat(root)
	var pair := _player_with_rig()
	var p: Player = pair[0]
	cs.player_body = p
	var bm := BuffManager.new()
	bm.pick("avenger")
	bm.apply_to_player(p)
	bm.apply_to_rig(p.weapon_rig)
	var frame := Engine.get_physics_frames()
	p.take_hit_ctx({"amount": 3, "source_type": "contact"}, frame)
	assert_int(p.hp).is_equal(p.hp_max)                   # 护盾 4 先吸满 3（hp 不动）
	assert_int(p.shield).is_equal(p.shield_max - 3)
	assert_int(p.vengeance_until).is_equal(frame + 180)
	var e := _enemy(root, cs, Vector2(200, 0), 100)
	await _fire_at(root, cs, Vector2(200, 0), 20)
	assert_int(e.hp).is_equal(75)

func test_avenger_window_boundary_and_refresh_on_rehit() -> void:
	# 窗界 frame==until 不生效（frame < until 严格）；再次受击按最新帧顺延。
	var root := _root()
	var cs := _combat(root)
	var pair := _player_with_rig()
	var p: Player = pair[0]
	var rig: WeaponRig = pair[1]
	rig.set_meta("buff_vengeance_pct", 0.25)
	rig.set_meta("buff_vengeance_ticks", 180)
	cs.player_body = p
	var frame := Engine.get_physics_frames()
	assert_float(cs._player_global_mult(true, {}, null, frame)).is_equal_approx(1.0, 0.0001)
	p.vengeance_until = frame + 180
	assert_float(cs._player_global_mult(true, {}, null, frame + 179)).is_equal_approx(1.25, 0.0001)
	assert_float(cs._player_global_mult(true, {}, null, frame + 180)).is_equal_approx(1.0, 0.0001)
	p.take_hit_ctx({"amount": 1, "source_type": "contact"}, frame + 100)
	assert_int(p.vengeance_until).is_equal(frame + 280)   # 顺延 = 新受击帧 + 180

func test_avenger_no_window_without_buff_and_telemetry() -> void:
	# 无增益（rig meta 缺省 0）零漂移：不开窗不写 vengeance 遥测；有增益时每次受击
	# 恰一行 vengeance_trigger（hurt 行为 take_hit_ctx 既有口径，另行 +1）；
	# pct ≤ 0 不开窗不记遥测（meta 残留 0 值 pct 的防御半边）。
	# 受击帧拉开 ≥48t（受击无敌帧基线）避免后续受击被无敌帧拦成 no-op。
	var root := _root()
	var cs := _combat(root)
	var pair := _player_with_rig()
	var p: Player = pair[0]
	var rig: WeaponRig = pair[1]
	cs.player_body = p
	var frame := Engine.get_physics_frames()
	var vt_rows := func() -> int:
		var n := 0
		for r: String in Telemetry._buf:
			if r.begins_with("vengeance_trigger"):
				n += 1
		return n
	var vt_baseline := int(vt_rows.call())    # 基线（同套件先行用例可能已写入）
	p.take_hit_ctx({"amount": 1, "source_type": "contact"}, frame)
	assert_int(p.vengeance_until).is_equal(-1)
	assert_int(int(vt_rows.call())).is_equal(vt_baseline)
	rig.set_meta("buff_vengeance_pct", 0.25)
	rig.set_meta("buff_vengeance_ticks", 180)
	p.take_hit_ctx({"amount": 1, "source_type": "contact"}, frame + 100)
	assert_int(p.vengeance_until).is_equal(frame + 280)
	assert_int(int(vt_rows.call())).is_equal(vt_baseline + 1)
	rig.set_meta("buff_vengeance_pct", 0.0)
	p.take_hit_ctx({"amount": 1, "source_type": "contact"}, frame + 200)
	assert_int(p.vengeance_until).is_equal(frame + 280)   # pct=0 受击不改写窗
	assert_int(int(vt_rows.call())).is_equal(vt_baseline + 1)

# ================================================================
# 共鸣增幅 resonance_amp（resonance_radius_pct 0.3 / resonance_duration_ticks 60）
# ——燎原毒火云半径 ×(1+pct)、持续 +ticks（Resonance 静态读数）
# ================================================================

func test_resonance_helpers_scale_clamp_and_no_buff_identity() -> void:
	# 纯函数：放大、负值 clamp 恒等；时长加算、负值 clamp 恒等。
	assert_float(Resonance.radius_px(100.0, 0.3)).is_equal_approx(130.0, 0.0001)
	assert_float(Resonance.radius_px(100.0, 0.0)).is_equal_approx(100.0, 0.0001)
	assert_float(Resonance.radius_px(100.0, -0.5)).is_equal_approx(100.0, 0.0001)
	assert_int(Resonance.duration_ticks(180, 60)).is_equal(240)
	assert_int(Resonance.duration_ticks(180, 0)).is_equal(180)
	assert_int(Resonance.duration_ticks(180, -9)).is_equal(180)

func test_resonance_amp_full_chain_boosts_blaze_cloud_radius_and_duration() -> void:
	# 燎原毒火云（基线 100px/3s）：增益后 130px/240t——110px 处敌体增益内被波及、
	# 增益半径外不受影响；200s 时间轴上 1200 < until(1240) 仍在结算、基线 180t 早已散。
	var root := _root()
	var cs := _combat(root)
	var pair := _player_with_rig()
	var p: Player = pair[0]
	cs.player_body = p
	var bm := BuffManager.new()
	bm.pick("resonance_amp")
	bm.apply_to_player(p)
	bm.apply_to_rig(p.weapon_rig)
	var in_ring: DummyBody = auto_free(DummyBody.new())
	in_ring.position = Vector2(110, 0)        # 100px 基线外、130px 增益内
	root.add_child(in_ring)
	cs.register_body(in_ring, Projectile.Faction.ENEMY)
	var far: DummyBody = auto_free(DummyBody.new())
	far.position = Vector2(200, 0)            # 130px 增益半径外（+体半径 6 仍不中）
	root.add_child(far)
	cs.register_body(far, Projectile.Faction.ENEMY)
	cs.spawn_blaze_cloud(Vector2.ZERO, 1000)
	cs.tick_environment(1100)
	assert_int(in_ring.hits.size()).is_equal(1)
	assert_int(far.hits.size()).is_equal(0)
	cs.tick_environment(1200)                 # 1200 < until(1240)：基线云此刻已散、增益云仍结算
	assert_int(in_ring.hits.size()).is_equal(3)
	cs.tick_environment(1300)                 # ≥ until(1240)：末拍后散
	assert_int(in_ring.hits.size()).is_equal(4)
	cs.tick_environment(1400)
	assert_int(in_ring.hits.size()).is_equal(4)

func test_blaze_cloud_baseline_untouched_without_buff() -> void:
	# 无增益零漂移：110px 处不中（基线 100px+体半径 6）；基线时长 180t 到点即散。
	var root := _root()
	var cs := _combat(root)
	var ring: DummyBody = auto_free(DummyBody.new())
	ring.position = Vector2(110, 0)
	root.add_child(ring)
	cs.register_body(ring, Projectile.Faction.ENEMY)
	cs.spawn_blaze_cloud(Vector2.ZERO, 1000)
	cs.tick_environment(1100)
	assert_int(ring.hits.size()).is_equal(0)
	var near: DummyBody = auto_free(DummyBody.new())
	near.position = Vector2(450, 0)           # 第二朵云中心 (500,0) 半径内
	root.add_child(near)
	cs.register_body(near, Projectile.Faction.ENEMY)
	cs.spawn_blaze_cloud(Vector2(500, 0), 2000)
	cs.tick_environment(2100)
	assert_int(near.hits.size()).is_equal(1)
	cs.tick_environment(2240)                 # until(2180)：2060/2120/2180 三拍
	assert_int(near.hits.size()).is_equal(3)
	cs.tick_environment(2400)                 # 已散
	assert_int(near.hits.size()).is_equal(3)

# ================================================================
# 元素视界 element_vision（flag 1 + telegraph_bonus_ticks 9）——敌侧预警展示层
# ================================================================

func test_element_vision_full_chain_extends_windup_and_marks_telegraph() -> void:
	# 弹幕预警窗 +9t（30→39，狂暴/试炼缩放后加算）；预警进入拍叠自绘高亮窗（纯表现）。
	var root := _root()
	var cs := _combat(root)
	var pair := _player_with_rig()
	var p: Player = pair[0]
	var bm := BuffManager.new()
	bm.pick("element_vision")
	bm.apply_to_player(p)
	bm.apply_to_rig(p.weapon_rig)
	var e := _enemy(root, cs, Vector2(200, 0), 100)
	e.player_ref = p
	assert_int(e._windup_ticks(30)).is_equal(39)
	var frame := Engine.get_physics_frames()
	e.telegraph_fx()
	assert_int(e._vision_mark_until).is_equal(frame + 21)   # VISION_MARK_TICKS=21（0.35s）
	e.telegraph_fx()                          # 窗内不重置
	assert_int(e._vision_mark_until).is_equal(frame + 21)
	e.update_vision_outlines(frame + 21)      # 过期拍清位
	assert_int(e._vision_mark_until).is_equal(-1)

func test_element_vision_zero_drift_without_buff() -> void:
	# 无增益：预警窗原值、telegraph_fx 不建高亮窗（Fx 红闪通道行为等价保留）。
	var root := _root()
	var cs := _combat(root)
	var e := _enemy(root, cs, Vector2(200, 0), 100)
	assert_int(e._windup_ticks(30)).is_equal(30)
	e.telegraph_fx()
	assert_int(e._vision_mark_until).is_equal(-1)

func test_telegraph_bonus_ticks_flat_after_berserk_scaling() -> void:
	# +flat 语义钉死：狂暴缩放（×0.7）之后再加算——缺省 40 狂暴 28 + 9 = 37。
	var root := _root()
	var cs := _combat(root)
	var pair := _player_with_rig()
	var p: Player = pair[0]
	p.set_meta("buff_telegraph_bonus_ticks", 9)
	var e := _enemy(root, cs, Vector2(200, 0), 100)
	e.player_ref = p
	e.has_berserk = true                      # hp=1 < 50%：狂暴激活（仅词缀敌可真）
	e.hp = 1
	assert_int(e._windup_ticks(40)).is_equal(37)

# ================================================================
# 共鸣视界 resonance_vision（flag 1）——异常状态敌高亮描边（展示，零判定影响）
# ================================================================

func test_resonance_vision_outlines_statused_enemy_and_tracks_changes() -> void:
	var root := _root()
	var cs := _combat(root)
	var pair := _player_with_rig()
	var p: Player = pair[0]
	p.set_meta("buff_resonance_vision", 1)
	var e := _enemy(root, cs, Vector2(200, 0), 100)
	e.player_ref = p
	var frame := Engine.get_physics_frames()
	e.update_vision_outlines(frame)           # 未异常：不描边
	assert_bool(e._status_outline).is_false()
	_activate_fire(e)
	e.update_vision_outlines(frame + 1)
	assert_bool(e._status_outline).is_true()
	assert_int(e._status_outline_element).is_equal(Elements.Id.FIRE)
	(e.status as StatusComponent).active.clear()   # 状态过期 → 摘除描边
	e.update_vision_outlines(frame + 2)
	assert_bool(e._status_outline).is_false()

func test_resonance_vision_zero_drift_without_buff() -> void:
	# 无增益：异常状态敌不描边（判定链路亦不读该状态位）。
	var root := _root()
	var cs := _combat(root)
	var e := _enemy(root, cs, Vector2(200, 0), 100)
	_activate_fire(e)
	e.update_vision_outlines(Engine.get_physics_frames())
	assert_bool(e._status_outline).is_false()

# ================================================================
# 红心感应 heart_sense（heart_sense_pct 0.5，player meta）——房奖励掉率 roll
# ================================================================

func _room_with_player() -> RoomCombat:
	var room := RoomCombat.new()
	room.spawn_player = true
	auto_free(room)
	add_child(room)
	return room


func _heart_count(room: RoomCombat) -> int:
	var n := 0
	for child in room.get_children():
		var pk := child as Pickup
		if pk != null and pk.kind == "heart":
			n += 1
	return n


func test_heart_sense_full_chain_roll_spawns_bonus_heart_on_win() -> void:
	# 全通路：pick heart_sense → player meta → 房奖励 roll；受控盐流钉中奖分支恰掉 1 心。
	var room := _room_with_player()
	var bm := BuffManager.new()
	bm.pick("heart_sense")
	bm.apply_to_player(room.player)
	assert_float(float(room.player.get_meta("buff_heart_sense_pct", 0.0))) \
		.is_equal_approx(0.5, 0.0001)
	var first: float = _rigged_rng(7).randf()          # 期望流（与 roll 流同种子同首掷）
	room._heart_rng = _rigged_rng(7)
	room._heart_sense_bonus()
	assert_int(_heart_count(room)).is_equal(1 if first < 0.5 else 0)
	assert_int(room.coins_collected()).is_equal(0)

func test_heart_sense_pct_clamped_to_unit_range() -> void:
	# pct clamp [0,1]：1.5 → 必中（randf()∈[0,1) 恒 < 1.0）。
	var room := _room_with_player()
	room.player.set_meta("buff_heart_sense_pct", 1.5)
	room._heart_rng = _rigged_rng(7)
	room._heart_sense_bonus()
	assert_int(_heart_count(room)).is_equal(1)

func test_heart_sense_lazy_salt_stream_independent() -> void:
	# 未预置流时经 RunState.stream("heart_sense") 独立盐惰性建（kill_energy 先例），
	# 且流被缓存（fresh-per-call 会退化成恒同掷签——实现注释钉死的契约）。
	var room := _room_with_player()
	room.player.set_meta("buff_heart_sense_pct", 0.5)
	assert_object(room._heart_rng).is_null()
	room._heart_sense_bonus()
	assert_object(room._heart_rng).is_not_null()
	var cached := room._heart_rng
	room._heart_sense_bonus()
	assert_object(room._heart_rng).is_same(cached)

func test_heart_sense_zero_drift_without_buff_no_roll_no_stream() -> void:
	# 无增益：不掷签、不建流、不掉心（m0_loop_smoke 35 pickups 断言不回归的半边）。
	var room := _room_with_player()
	room._heart_sense_bonus()
	assert_int(_heart_count(room)).is_equal(0)
	assert_object(room._heart_rng).is_null()
	room.player.set_meta("buff_heart_sense_pct", 0.0)
	room._heart_sense_bonus()
	assert_int(_heart_count(room)).is_equal(0)
	assert_object(room._heart_rng).is_null()

# ================================================================
# 抗毒 anti_poison（flag 1，player meta）——POISON 归因来伤免疫（仿 anti_ice 先例）
# ================================================================

func test_anti_poison_full_chain_poison_damage_is_full_noop() -> void:
	# 免疫=完整 no-op：不掉血不进护盾结算、不开受击无敌帧、不发受击结算信号。
	var room := _room_with_player()
	var p := room.player
	var bm := BuffManager.new()
	bm.pick("anti_poison")
	bm.apply_to_player(p)
	assert_int(int(p.get_meta("buff_anti_poison", 0))).is_equal(1)
	var frame := Engine.get_physics_frames()
	var resolved_spy: Array = []
	var spy := func(amount: int, fatal: bool, ctx: Dictionary) -> void:
		resolved_spy.append(ctx)
	EventBus.player_hit_resolved.connect(spy)
	p.take_hit_ctx({"amount": 5, "element": Elements.Id.POISON, "source_type": "projectile"}, frame)
	EventBus.player_hit_resolved.disconnect(spy)
	assert_int(p.hp).is_equal(p.hp_max)
	assert_bool(p.is_invincible_at(frame + 1)).is_false()
	assert_array(resolved_spy).is_empty()

func test_anti_poison_does_not_block_other_elements_or_unbuffed_poison() -> void:
	# 非 POISON 归因来伤照常；无增益时 POISON 照常（免疫仅覆盖毒向量）。
	# 默认护盾 4：5 点来伤 → 护盾清空 + hp -1（吸收后余量）。
	var p: Player = auto_free(Player.new())
	p.set_meta("buff_anti_poison", 1)
	p.take_hit_ctx({"amount": 5, "element": Elements.Id.FIRE, "source_type": "projectile"},
		Engine.get_physics_frames())
	assert_int(p.hp).is_equal(p.hp_max - 1)
	assert_int(p.shield).is_equal(0)
	var p2: Player = auto_free(Player.new())
	p2.take_hit_ctx({"amount": 5, "element": Elements.Id.POISON, "source_type": "projectile"},
		Engine.get_physics_frames())
	assert_int(p2.hp).is_equal(p2.hp_max - 1)
	assert_int(p2.shield).is_equal(0)

# ================================================================
# 展示键零判定影响收口（约束：表现判定分离）
# ================================================================

func test_vision_flags_are_display_only_zero_judgment_drift() -> void:
	# 三展示键齐挂：伤害结算与无增益完全一致（高亮/描边/预警窗不进判定；
	# 敌侧展示读点经 _player_buff_meta 消费 meta，不影响本击数值）。
	var root := _root()
	var cs := _combat(root)
	var pair := _player_with_rig()
	var p: Player = pair[0]
	p.set_meta("buff_element_vision", 1)
	p.set_meta("buff_resonance_vision", 1)
	var e := _enemy(root, cs, Vector2(200, 0), 100)
	await _fire_at(root, cs, Vector2(200, 0), 20)
	assert_int(e.hp).is_equal(80)             # 无任何乘区介入
	assert_bool(CombatSystem._target_statused(e)).is_false()
