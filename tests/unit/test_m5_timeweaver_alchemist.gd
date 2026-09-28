extends GdUnitTestSuite
## M5-T3 时空·隙「时缓域」+ 炼金·汞「投瓶」+ 双被动（时滞/侵蚀）。
## - 域乘区：TimeweaverTimeDilation.domain_scale 纯函数直测（进域/出域/Boss 减半/
##   到期恢复/我方弹强化）；ProjectilePool.spawn 出弹单点消费端到端（敌弹 ×0.6、
##   Boss 来源弹 ×0.8、强化域内我方弹 ×1.2、无钩子零漂移）。
## - 体速乘区取样：ProjectilePool.field_velocity_scale（EnemyBase _physics_process
##   一行消费点的取样缝；体速表达式为手动验证层，测试不经 _physics_process）。
## - 毒池：投瓶落池节拍（1 伤/0.5s、末拍含、追帧 while、过期自净）+ 毒积累走
##   StatusComponent 既有通道 + 强化火/毒/电轮转。
## - 被动：时滞（翻滚 CD -6t，外部累积 meta 通道落账、增益刷新重建不丢失、幂等）；
##   侵蚀（status 系统侧漏斗 ×1.2，与同名增益 (1+Σ)× 叠乘、无钩子零漂移）。
## 静态钩子卫生：after_test 统一清（clear_field + 两钩子置空），跨套件零残留。

const PLAYER_SCENE := preload("res://core/player/player.tscn")

const RADIUS := TimeweaverTimeDilation.FIELD_RADIUS_PX
const DURATION := TimeweaverTimeDilation.FIELD_DURATION_TICKS


func after_test() -> void:
	TimeweaverTimeDilation.clear_field()
	ProjectilePool.velocity_scale_hook = Callable()
	StatusComponent.attacker_stack_scale_hook = Callable()


# ---- 夹具 ----

## 真 CombatSystem（弹侧消费端到端用；暴击无关，确定性归零）。
func _combat(root: Node2D) -> CombatSystem:
	var cs := CombatSystem.new(root, RngSvc.stream(0, "combat"))
	cs.crit_chance = 0.0
	root.add_child(cs)
	return cs


## 装配玩家（player.tscn 实例化——Skill 节点在场景内，HeroApplier.apply 依赖）。
func _player(hero_id: String) -> Player:
	var p: Player = auto_free(PLAYER_SCENE.instantiate() as Player)
	add_child(p)
	HeroApplier.apply(GameDB.get_hero(hero_id), p)
	return p


## 入树假敌（进 enemies 组 + 注册 combat；take_hit 记录后透传 super 走真实结算）。
class HitProbe extends EnemyBase:
	var hits: Array = []

	func _init() -> void:
		_test_init({"id": "m5_t3_dummy", "hp": 100, "radius": 6.0})

	func place(at: Vector2) -> void:
		position = at
		brain_pos = at

	func take_hit(ctx: Dictionary) -> void:
		hits.append(ctx.duplicate(true))
		super.take_hit(ctx)


func _probe(root: Node2D, cs: CombatSystem, at: Vector2) -> HitProbe:
	var e: HitProbe = auto_free(HitProbe.new())
	add_child(e)
	e.place(at)
	e.add_to_group("enemies")
	cs.register_body(e, e.combat_faction())
	return e


## 敌弹 cfg（pos/vel/source_id 可调；其余键同 fire_bullet 全量口径）。
func _bullet_cfg(pos: Vector2, vel: Vector2, faction: int, source_id: String) -> Dictionary:
	return {
		"pos": pos, "vel": vel, "damage": 3, "faction": faction,
		"element": Elements.Id.NONE, "pierce": 0, "bounce": 0,
		"life_seconds": 5.0, "radius": 3.0,
		"source_type": "projectile", "source_id": source_id,
		"source_name": source_id, "attack_name": "弹幕",
	}


# ================================================================ 域乘区纯函数

func test_domain_scale_enemy_inside_outside_and_expiry() -> void:
	var center := Vector2(1000, 1000)
	var until := 1000
	var inside := center + Vector2(60, 0)
	var outside := center + Vector2(RADIUS + 1.0, 0)
	# 域内敌弹/敌速 ×0.6
	assert_float(TimeweaverTimeDilation.domain_scale(center, RADIUS, until, false,
		inside, Projectile.Faction.ENEMY, false, until)).is_equal_approx(0.6, 0.0001)
	# 域外（出域恢复口径②）
	assert_float(TimeweaverTimeDilation.domain_scale(center, RADIUS, until, false,
		outside, Projectile.Faction.ENEMY, false, until)).is_equal_approx(1.0, 0.0001)
	# 窗闭（域出恢复口径①；until 为末帧含）
	assert_float(TimeweaverTimeDilation.domain_scale(center, RADIUS, until, false,
		inside, Projectile.Faction.ENEMY, false, until + 1)).is_equal_approx(1.0, 0.0001)
	# 半径边界（距离 == 半径仍在域内）
	assert_float(TimeweaverTimeDilation.domain_scale(center, RADIUS, until, false,
		center + Vector2(RADIUS, 0), Projectile.Faction.ENEMY, false, until)) \
		.is_equal_approx(0.6, 0.0001)


func test_domain_scale_boss_halved_slow() -> void:
	# Boss 行减速减半：×0.8（弹/体同源同口径）
	var center := Vector2.ZERO
	assert_float(TimeweaverTimeDilation.domain_scale(center, RADIUS, 100, false,
		Vector2(50, 0), Projectile.Faction.ENEMY, true, 100)).is_equal_approx(0.8, 0.0001)


func test_domain_scale_player_bullet_upgraded_and_non_upgraded() -> void:
	var center := Vector2.ZERO
	# 非强化：我方弹恒等（零漂移）
	assert_float(TimeweaverTimeDilation.domain_scale(center, RADIUS, 100, false,
		Vector2(10, 0), Projectile.Faction.PLAYER, false, 100)).is_equal_approx(1.0, 0.0001)
	# 强化：域内我方弹速 +20%；域外不放大
	assert_float(TimeweaverTimeDilation.domain_scale(center, RADIUS, 100, true,
		Vector2(10, 0), Projectile.Faction.PLAYER, false, 100)).is_equal_approx(1.2, 0.0001)
	assert_float(TimeweaverTimeDilation.domain_scale(center, RADIUS, 100, true,
		Vector2(RADIUS + 5.0, 0), Projectile.Faction.PLAYER, false, 100)) \
		.is_equal_approx(1.0, 0.0001)
	# 强化不影响敌方乘区
	assert_float(TimeweaverTimeDilation.domain_scale(center, RADIUS, 100, true,
		Vector2(10, 0), Projectile.Faction.ENEMY, false, 100)).is_equal_approx(0.6, 0.0001)


# ================================================================ 池注入端到端（弹侧消费点）

## 施放时缓域（真实帧口径——池 spawn 取 Engine.get_physics_frames() 采样）。
func _cast_field(p: Player, upgraded: bool, at: Vector2) -> TimeweaverTimeDilation:
	p.global_position = at
	p.facing = Vector2.RIGHT
	var m := p.get_node("Skill") as TimeweaverTimeDilation
	m.upgraded = upgraded
	assert_bool(m.cast(Engine.get_physics_frames())).is_true()
	return m


func test_pool_spawn_slows_enemy_bullet_inside_field() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	var p := _player("timeweaver")
	_cast_field(p, false, Vector2.ZERO)
	var vel := Vector2(100, 0)
	cs.spawn_projectile(_bullet_cfg(Vector2(50, 0), vel, Projectile.Faction.ENEMY, "cave_bat"))
	var proj: Projectile = cs.pool.active[0]
	assert_float(proj.vel.length()).is_equal_approx(60.0, 0.001)     # 100 × 0.6


func test_pool_spawn_boss_source_bullet_halved_slow() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	var p := _player("timeweaver")
	_cast_field(p, false, Vector2.ZERO)
	cs.spawn_projectile(_bullet_cfg(Vector2(40, 0), Vector2(100, 0),
		Projectile.Faction.ENEMY, "gem_queen"))
	var proj: Projectile = cs.pool.active[0]
	assert_float(proj.vel.length()).is_equal_approx(80.0, 0.001)     # 100 × 0.8


func test_pool_spawn_outside_field_untouched() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	var p := _player("timeweaver")
	_cast_field(p, false, Vector2.ZERO)
	cs.spawn_projectile(_bullet_cfg(Vector2(3000, 0), Vector2(100, 0),
		Projectile.Faction.ENEMY, "cave_bat"))
	var proj: Projectile = cs.pool.active[0]
	assert_float(proj.vel.length()).is_equal_approx(100.0, 0.001)    # 域外恒等


func test_pool_spawn_upgraded_player_bullet_boost() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	var p := _player("timeweaver")
	_cast_field(p, true, Vector2.ZERO)
	cs.spawn_projectile(_bullet_cfg(Vector2(30, 0), Vector2(100, 0),
		Projectile.Faction.PLAYER, "bingzhuizhang"))
	var proj: Projectile = cs.pool.active[0]
	assert_float(proj.vel.length()).is_equal_approx(120.0, 0.001)    # 100 × 1.2
	# 敌方乘区不受强化影响
	cs.spawn_projectile(_bullet_cfg(Vector2(30, 0), Vector2(100, 0),
		Projectile.Faction.ENEMY, "cave_bat"))
	assert_float((cs.pool.active[1] as Projectile).vel.length()).is_equal_approx(60.0, 0.001)


func test_pool_spawn_zero_drift_without_hook() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	ProjectilePool.velocity_scale_hook = Callable()   # 无时空英雄装配
	cs.spawn_projectile(_bullet_cfg(Vector2(50, 0), Vector2(100, 0),
		Projectile.Faction.ENEMY, "gem_queen"))
	assert_float((cs.pool.active[0] as Projectile).vel.length()).is_equal_approx(100.0, 0.001)


func test_source_is_boss_by_game_db_row() -> void:
	assert_bool(ProjectilePool.source_is_boss("gem_queen")).is_true()
	assert_bool(ProjectilePool.source_is_boss("vine_colossus")).is_true()
	assert_bool(ProjectilePool.source_is_boss("kuli_bug")).is_false()
	assert_bool(ProjectilePool.source_is_boss("no_such_id")).is_false()


# ================================================================ 体速乘区取样缝

func test_field_velocity_scale_body_channel() -> void:
	var p := _player("timeweaver")
	_cast_field(p, false, Vector2.ZERO)
	var now := Engine.get_physics_frames()
	assert_float(ProjectilePool.field_velocity_scale(Vector2(50, 0),
		Projectile.Faction.ENEMY, false, now)).is_equal_approx(0.6, 0.0001)
	assert_float(ProjectilePool.field_velocity_scale(Vector2(50, 0),
		Projectile.Faction.ENEMY, true, now)).is_equal_approx(0.8, 0.0001)
	assert_float(ProjectilePool.field_velocity_scale(Vector2(5000, 0),
		Projectile.Faction.ENEMY, false, now)).is_equal_approx(1.0, 0.0001)


func test_field_state_lifecycle_via_skill() -> void:
	var p := _player("timeweaver")
	var now := Engine.get_physics_frames()
	_cast_field(p, false, Vector2.ZERO)
	var m := p.get_node("Skill") as TimeweaverTimeDilation
	assert_bool(TimeweaverTimeDilation.field_active(now)).is_true()
	assert_bool(TimeweaverTimeDilation.field_active(now + DURATION)).is_true()   # 末帧含
	assert_bool(TimeweaverTimeDilation.field_active(now + DURATION + 1)).is_false()
	assert_int(m.cooldown_remaining(now + 1)).is_equal(720 - 1)   # 数据行 CD 覆写生效


# ================================================================ 时滞被动（翻滚 CD -0.1s）

func test_time_lag_roll_cd_reduction_applied() -> void:
	var p := _player("timeweaver")
	assert_int(p.roll_cd_reduction_ticks).is_equal(6)                       # 0.1s = 6t
	assert_int(p.effective_roll_cd_ticks()).is_equal(42 - 6)                # 0.7s → 0.6s


func test_time_lag_idempotent_on_reapply() -> void:
	var p := _player("timeweaver")
	HeroApplier.apply(GameDB.get_hero("timeweaver"), p)                     # 重复装配
	assert_int(p.roll_cd_reduction_ticks).is_equal(6)                       # 不叠加
	HeroApplier.apply(GameDB.get_hero("timeweaver"), p)
	assert_int(p.roll_cd_reduction_ticks).is_equal(6)


func test_time_lag_survives_buff_manager_rebuild() -> void:
	# 口径：贡献落外部累积 meta；BuffManager 重建（var = drink meta 全量还原）不丢失，
	# 且饮料后续拾取（meta 累加）不重复计数。
	var p := _player("timeweaver")
	p.set_meta("drink_roll_cd_reduction_ticks",
		int(p.get_meta("drink_roll_cd_reduction_ticks", 0)) + 3)            # 饮料 +3t
	p.roll_cd_reduction_ticks += 3
	assert_int(p.roll_cd_reduction_ticks).is_equal(9)
	# BuffManager.apply_to_player 重建口径（181 行）：var = drink meta
	p.roll_cd_reduction_ticks = int(p.get_meta("drink_roll_cd_reduction_ticks", 0))
	assert_int(p.roll_cd_reduction_ticks).is_equal(9)                       # 6 + 3 完整保留
	assert_int(p.effective_roll_cd_ticks()).is_equal(42 - 9)


func test_time_lag_zero_drift_other_heroes() -> void:
	var p := _player("guardian")
	assert_int(p.roll_cd_reduction_ticks).is_equal(0)
	assert_int(p.effective_roll_cd_ticks()).is_equal(42)
	var q := _player("alchemist")
	assert_int(q.roll_cd_reduction_ticks).is_equal(0)                       # 炼金无时滞


# ================================================================ 侵蚀被动（元素积累 ×1.2）

func test_erosion_hook_scales_hit_context_stack_gain() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	var vial := AlchemistVial.new()
	auto_free(vial)
	StatusComponent.attacker_stack_scale_hook = Callable(vial, "_erosion_stack_scale")
	var e := _probe(root, cs, Vector2(100, 0))
	# 无增益 ctx：1 层 → ×1.2 小数进度
	e.status.apply_hit_context({"element": Elements.Id.POISON}, 5, 100)
	assert_float(float(e.status._stacks.get(Elements.Id.POISON, 0.0))).is_equal_approx(1.2, 0.0001)


func test_erosion_multiplicative_with_same_name_buff() -> void:
	# 叠乘口径：(1 + Σ增益) × 1.2 —— ctx.status_rate_mult=1.25（状态侵蚀 buff 通道值）
	# → 1.25 × 1.2 = 1.5（非 1 + 0.25 + 0.2 加法合流 = 1.45）
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	var vial := AlchemistVial.new()
	auto_free(vial)
	StatusComponent.attacker_stack_scale_hook = Callable(vial, "_erosion_stack_scale")
	var e := _probe(root, cs, Vector2(100, 0))
	e.status.apply_hit_context({"element": Elements.Id.POISON, "status_rate_mult": 1.25}, 5, 100)
	assert_float(float(e.status._stacks.get(Elements.Id.POISON, 0.0))).is_equal_approx(1.5, 0.0001)


func test_erosion_triggers_status_with_remainder() -> void:
	# 阈值跨触发保留余数（apply_hit_scaled 既有语义）：1.2+1.2=2.4 → 触发后余 0.4
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	var vial := AlchemistVial.new()
	auto_free(vial)
	StatusComponent.attacker_stack_scale_hook = Callable(vial, "_erosion_stack_scale")
	var e := _probe(root, cs, Vector2(100, 0))
	e.status.apply_hit_context({"element": Elements.Id.POISON}, 5, 100)
	e.status.apply_hit_context({"element": Elements.Id.POISON}, 5, 100)
	assert_bool(e.status.active.has(Elements.Id.POISON)).is_true()          # 中毒激活
	assert_float(float(e.status._stacks.get(Elements.Id.POISON, 0.0))).is_equal_approx(0.4, 0.001)


func test_erosion_zero_drift_without_hook() -> void:
	StatusComponent.attacker_stack_scale_hook = Callable()
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	var e := _probe(root, cs, Vector2(100, 0))
	e.status.apply_hit_context({"element": Elements.Id.POISON}, 5, 100)
	assert_float(float(e.status._stacks.get(Elements.Id.POISON, 0.0))).is_equal_approx(1.0, 0.0001)


# ================================================================ 投瓶毒池

## 装配炼金并施放投瓶（真实帧口径；cs 给出时按生产注入习语 wired p.combat）。
func _cast_vial(p: Player, upgraded: bool, cs: CombatSystem = null) -> AlchemistVial:
	if cs != null:
		p.combat = cs
	p.facing = Vector2.RIGHT
	var m := p.get_node("Skill") as AlchemistVial
	m.upgraded = upgraded
	assert_bool(m.cast(Engine.get_physics_frames())).is_true()
	return m


func test_vial_pool_tick_damage_and_accumulation() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	var p := _player("alchemist")
	p.global_position = Vector2.ZERO
	var m := _cast_vial(p, false, cs)
	var pool_center := Vector2(AlchemistVial.THROW_RANGE_PX, 0)
	assert_float(m._pool_center.distance_to(pool_center)).is_equal_approx(0.0, 0.001)
	var e := _probe(root, cs, pool_center)
	var f := Engine.get_physics_frames()
	m.tick(f + 1)                                        # 非节拍帧：无结算
	assert_int(e.hits.size()).is_equal(0)
	m.tick(f + AlchemistVial.POOL_TICK_INTERVAL_TICKS)   # 0.5s 节拍
	assert_int(e.hits.size()).is_equal(1)
	assert_int(int(e.hits[0]["amount"])).is_equal(1)
	assert_int(int(e.hits[0]["element"])).is_equal(Elements.Id.POISON)
	assert_str(String(e.hits[0]["source_id"])).is_equal("alchemist_vial")
	assert_bool(bool(e.hits[0]["player_damage"])).is_true()
	# 毒积累走 status 既有通道（侵蚀钩子同漏斗 ×1.2）
	assert_float(float(e.status._stacks.get(Elements.Id.POISON, 0.0))).is_equal_approx(1.2, 0.0001)


func test_vial_pool_full_window_six_ticks_then_expires() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	var p := _player("alchemist")
	p.global_position = Vector2.ZERO
	var m := _cast_vial(p, false, cs)
	var e := _probe(root, cs, m._pool_center)
	var f0 := Engine.get_physics_frames()
	for i in range(1, AlchemistVial.POOL_DURATION_TICKS + 8):   # 3s + 余量
		m.tick(f0 + i)
	assert_int(e.hits.size()).is_equal(6)                # 1 伤/0.5s × 3s（末拍含）
	# 池过期后再推进不再结算
	m.tick(f0 + AlchemistVial.POOL_DURATION_TICKS + 100)
	assert_int(e.hits.size()).is_equal(6)
	assert_bool(m.pool_active(f0 + AlchemistVial.POOL_DURATION_TICKS)).is_true()
	assert_bool(m.pool_active(f0 + AlchemistVial.POOL_DURATION_TICKS + 1)).is_false()


func test_vial_pool_radius_filter() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	var p := _player("alchemist")
	p.global_position = Vector2.ZERO
	var m := _cast_vial(p, false, cs)
	var inside := _probe(root, cs, m._pool_center + Vector2(40, 0))
	# bodies_in_radius 按体半径松弛（range + body.radius=6 → 界 66px）：域外探针放 80px
	var outside := _probe(root, cs, m._pool_center + Vector2(80, 0))
	m.tick(Engine.get_physics_frames() + AlchemistVial.POOL_TICK_INTERVAL_TICKS)
	assert_int(inside.hits.size()).is_equal(1)
	assert_int(outside.hits.size()).is_equal(0)


func test_vial_pool_triggers_poison_status() -> void:
	# 池 2 跳积累（×1.2 侵蚀 = 2.4）跨过阈值 2 → 中毒激活（走既有触发语义）
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	var p := _player("alchemist")
	p.global_position = Vector2.ZERO
	var m := _cast_vial(p, false, cs)
	var e := _probe(root, cs, m._pool_center)
	var f0 := Engine.get_physics_frames()
	m.tick(f0 + AlchemistVial.POOL_TICK_INTERVAL_TICKS)
	m.tick(f0 + AlchemistVial.POOL_TICK_INTERVAL_TICKS * 2)
	assert_bool(e.status.active.has(Elements.Id.POISON)).is_true()


func test_vial_zero_energy_casts_via_framework_gate() -> void:
	# 0 蓝耗：空蓝也可施放（框架耗蓝门直通）；CD 门照常
	var p := _player("alchemist")
	p.energy = 0
	p.facing = Vector2.RIGHT
	var m := p.get_node("Skill") as AlchemistVial
	assert_bool(m.cast(1000)).is_true()
	assert_int(m.cooldown_remaining(1001)).is_equal(479)
	assert_bool(m.cast(1001)).is_false()                 # CD 内拒绝


func test_vial_upgraded_element_rotation_fire_poison_shock() -> void:
	# 强化「随机元素（火/毒/电轮转）」：确定性轮转 火→毒→电，非升级恒毒
	var p := _player("alchemist")
	var m := p.get_node("Skill") as AlchemistVial
	m.upgraded = true
	p.facing = Vector2.RIGHT
	var f := Engine.get_physics_frames()
	assert_bool(m.cast(f)).is_true()
	assert_int(m._pool_element).is_equal(Elements.Id.FIRE)
	assert_bool(m.cast(f + 480)).is_true()               # CD 480t 后重投
	assert_int(m._pool_element).is_equal(Elements.Id.POISON)
	assert_bool(m.cast(f + 960)).is_true()
	assert_int(m._pool_element).is_equal(Elements.Id.SHOCK)
	assert_bool(m.cast(f + 1440)).is_true()
	assert_int(m._pool_element).is_equal(Elements.Id.FIRE)   # 回到火（轮转闭合）
	# 非升级恒毒
	m.upgraded = false
	assert_bool(m.cast(f + 1920)).is_true()
	assert_int(m._pool_element).is_equal(Elements.Id.POISON)


func test_vial_upgraded_pool_carries_rotated_element() -> void:
	# 火池节拍按 FIRE 积累（触发/共鸣全走既有状态语义）
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	var p := _player("alchemist")
	p.global_position = Vector2.ZERO
	var m := _cast_vial(p, true, cs)                      # 首投 = 火
	assert_int(m._pool_element).is_equal(Elements.Id.FIRE)
	var e := _probe(root, cs, m._pool_center)
	m.tick(Engine.get_physics_frames() + AlchemistVial.POOL_TICK_INTERVAL_TICKS)
	assert_int(int(e.hits[0]["element"])).is_equal(Elements.Id.FIRE)
	assert_float(float(e.status._stacks.get(Elements.Id.FIRE, 0.0))).is_equal_approx(1.2, 0.0001)
	assert_float(float(e.status._stacks.get(Elements.Id.POISON, 0.0))).is_equal_approx(0.0, 0.0001)


func test_vial_zero_facing_falls_back_to_right() -> void:
	var p := _player("alchemist")
	p.global_position = Vector2(50, 50)
	p.facing = Vector2.ZERO
	var m := _cast_vial(p, false)
	assert_float(m._pool_center.distance_to(Vector2(50 + AlchemistVial.THROW_RANGE_PX, 50))) \
		.is_equal_approx(0.0, 0.001)


# ================================================================ 遥测

func test_telemetry_rows_emitted_on_cast() -> void:
	# 先清缓冲（flush 落盘）消除长会话缓冲态歧义，再断言两行在缓冲内
	Telemetry.flush()
	var p := _player("timeweaver")
	_cast_field(p, false, Vector2.ZERO)
	var p2 := _player("alchemist")
	p2.global_position = Vector2.ZERO
	_cast_vial(p2, false)
	var rows: Array = Telemetry._buf
	var found := {"time_dilation_cast": false, "vial_throw": false}
	for r: String in rows:
		if r.begins_with("time_dilation_cast,"):
			found["time_dilation_cast"] = true
		if r.begins_with("vial_throw,"):
			found["vial_throw"] = true
	assert_bool(found["time_dilation_cast"]).is_true()
	assert_bool(found["vial_throw"]).is_true()


# ================================================================ 数据行/装配契约

func test_hero_rows_pin_appendix_l_values() -> void:
	# 约束 13：CD/耗蓝/被动 id 照抄附录 L §3（数据行不动，装配数值钉死）
	var tw := GameDB.get_hero("timeweaver")
	assert_int(int(tw["skill_cd"])).is_equal(720)
	assert_int(int(tw["skill_energy"])).is_equal(25)
	assert_str(String(tw["passive_id"])).is_equal("time_lag")
	var al := GameDB.get_hero("alchemist")
	assert_int(int(al["skill_cd"])).is_equal(480)
	assert_int(int(al["skill_energy"])).is_equal(0)
	assert_str(String(al["passive_id"])).is_equal("erosion")


func test_placeholder_contract_setup_null_player_cast_still_works() -> void:
	# T1 冒烟契约不回归：setup(null) + cast(0) 过框架门（无玩家绑定生效体早退）
	for path: String in ["res://core/player/skills/timeweaver_time_dilation.gd",
			"res://core/player/skills/alchemist_vial.gd"]:
		var sk: SkillBase = auto_free(load(path).new())
		sk.setup(null, {"id": "x", "cooldown_ticks": 720, "energy_cost": 25,
			"upgraded": false})
		assert_bool(sk.cast(0)).is_true()
