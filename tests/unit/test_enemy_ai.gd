class_name TestEnemyAI
extends GdUnitTestSuite

## 玩家替身（PlayerProxy 契约：brain_pos + take_hit），受击记录供断言。
class SpyPlayer extends Node2D:
	var hits: Array = []
	var brain_pos := Vector2.ZERO
	func take_hit(ctx: Dictionary) -> void:
		hits.append(ctx)

func test_state_transitions() -> void:
	var e: EnemyBase = auto_free(EnemyFactory.create({"id": "crossbowman", "archetype": "shooter", "hp": 16, "contact_dmg": 3, "speed": 60, "windup_ticks": 30, "cd_ticks": 108}))
	e.on_player_seen(0)
	assert_int(e.state).is_equal(EnemyBase.State.ALERT)
	e.brain_tick(23)
	assert_int(e.state).is_equal(EnemyBase.State.ALERT)     # 0.4s=24 ticks 前摇
	e.brain_tick(24)
	assert_int(e.state).is_equal(EnemyBase.State.ENGAGE)

func test_shooter_cadence() -> void:
	var e: EnemyBase = auto_free(EnemyFactory.create({"id": "crossbowman", "archetype": "shooter", "hp": 16, "contact_dmg": 3, "speed": 60, "windup_ticks": 30, "cd_ticks": 108}))
	e.on_player_seen(0)
	for f in range(1, 25): e.brain_tick(f)
	var shots := 0
	for f in range(25, 300):
		e.brain_tick(f)
		if e.fired_this_tick: shots += 1
	# 0.4s 警觉后首射，随后每 1.8s：约 (300-24)/108 + 1 ≈ 3
	assert_int(shots).is_between(2, 4)

func test_enemy_fire_bullet_consumes_row_radius_and_source() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var combat := CombatSystem.new(root, RngSvc.stream(1, "enemy_radius_test"))
	root.add_child(combat)
	var e: EnemyBase = auto_free(EnemyFactory.create({
		"id": "crossbowman", "name": "弩兵", "archetype": "shooter", "hp": 16,
		"bullet_dmg": 3, "bullet_speed": 110, "bullet_life_seconds": 2.5,
		"bullet_radius": 4.5,
	}))
	e.combat = combat
	e.fire_bullet(Vector2.RIGHT * 100.0, 12)
	assert_int(combat.pool.active.size()).is_equal(1)
	assert_float((combat.pool.active[0] as Projectile).radius).is_equal(4.5)
	var meta: Dictionary = combat._proj_meta[(combat.pool.active[0] as Projectile).get_instance_id()]
	assert_str(String(meta["source_name"])).is_equal("弩兵")
	assert_str(String(meta["attack_name"])).is_equal("弹幕")

func test_suicide_fuse_and_explosion_params() -> void:
	var e: EnemyBase = auto_free(EnemyFactory.create({"id": "kuli_bug", "archetype": "suicide", "hp": 12, "speed": 95, "fuse_ticks": 30, "aoe_radius": 40, "aoe_dmg": 8}))
	e.on_player_seen(0)
	for f in range(1, 25): e.brain_tick(f)
	e.brain_tick(24 + 30)     # ENGAGE 后贴身引信 30 ticks
	assert_bool(e.exploded).is_true()

func test_charger_dash_distance() -> void:
	var e: EnemyBase = auto_free(EnemyFactory.create({"id": "vine_charger", "archetype": "charger", "hp": 18, "contact_dmg": 4, "walk_speed": 45, "dash_speed": 285, "windup_ticks": 30, "dash_ticks": 27, "dash_cooldown_ticks": 90}))
	e.on_player_seen(0)
	for f in range(1, 25):
		e.brain_tick(f)                   # 第 24 帧进入 ENGAGE
	for f in range(25, 55):
		e.brain_tick(f)                   # 前摇 30 ticks（蓄力原地）
	var traveled := 0.0
	var last := e.brain_pos
	for f in range(55, 55 + 27):          # 冲刺 27 ticks = 27×285/60 ≈ 128px（附录 B.2 冲 8 瓦片）
		e.brain_tick(f)
		traveled += last.distance_to(e.brain_pos)
		last = e.brain_pos
	assert_float(traveled).is_equal_approx(128.0, 8.0)

# ---- m0-final fix 回归 ----

## fix4（附录 B.1「死亡即刻爆」）：苦力虫受击致死同样引爆——40px 内替身恰好吃 1×8。
func test_kuli_death_by_damage_explodes_on_player_within_aoe() -> void:
	var e: EnemyBase = auto_free(EnemyFactory.create({"id": "kuli_bug", "archetype": "suicide", "hp": 12, "speed": 95, "fuse_ticks": 30, "aoe_radius": 40, "aoe_dmg": 8}))
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2.ZERO             # 与 e.brain_pos 同点（40px 内）
	e.player_ref = spy
	e.take_hit({"amount": 99, "is_crit": false, "element": Elements.Id.NONE, "from": Vector2.ZERO})
	assert_int(e.state).is_equal(EnemyBase.State.DEAD)
	assert_int(spy.hits.size()).is_equal(1)
	assert_int(spy.hits[0]["amount"]).is_equal(8)
	assert_bool(spy.hits[0]["is_crit"]).is_false()
	assert_int(int(spy.hits[0]["element"])).is_equal(Elements.Id.NONE)

## fix4：40px 外受击致死——爆而不中。
func test_kuli_death_by_damage_beyond_aoe_no_hit() -> void:
	var e: EnemyBase = auto_free(EnemyFactory.create({"id": "kuli_bug", "archetype": "suicide", "hp": 12, "speed": 95, "fuse_ticks": 30, "aoe_radius": 40, "aoe_dmg": 8}))
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(50, 0)           # 50px > aoe_radius 40
	e.set("player_ref", spy)
	e.take_hit({"amount": 99, "is_crit": false, "element": Elements.Id.NONE, "from": Vector2.ZERO})
	assert_int(e.state).is_equal(EnemyBase.State.DEAD)
	assert_int(spy.hits.size()).is_equal(0)

## fix4 去重：引信致死（exploded=true → die()）恰好一次爆炸，不再双重结算。
func test_kuli_fuse_death_explodes_exactly_once() -> void:
	var e: EnemyBase = auto_free(EnemyFactory.create({"id": "kuli_bug", "archetype": "suicide", "hp": 12, "speed": 95, "fuse_ticks": 30, "aoe_radius": 40, "aoe_dmg": 8}))
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2.ZERO             # 贴身（0 < 14px）：转换拍即点燃
	e.set("player_ref", spy)
	e.on_player_seen(0)
	for f in range(1, 25): e.brain_tick(f)
	e.brain_tick(24 + 30)                    # 引信 30 ticks 到点
	assert_bool(e.exploded).is_true()
	assert_int(spy.hits.size()).is_equal(1)  # 单一爆炸源：引信不再单独结算
	assert_int(spy.hits[0]["amount"]).is_equal(8)

## fix3：SHATTER AoE 不含触发体自身、跳过本拍已死体；范围内他体吃 1.5× 触发伤。
## 走真实 tick 通路：真实树物理帧驱动 EnemyBase._physics_process 消费 resonance_event。
func test_shatter_aoe_excludes_self_and_dead() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var rng := RngSvc.stream(0, "combat")
	var cs := CombatSystem.new(root, rng)
	root.add_child(cs)
	var trig: EnemyBase = auto_free(EnemyBase.new())
	trig.position = Vector2(100, 100)
	root.add_child(trig)
	trig.setup({"id": "trigger", "hp": 100, "radius": 6.0})
	trig.combat = cs
	cs.register_body(trig, trig.combat_faction())
	var other: EnemyBase = auto_free(EnemyBase.new())
	other.position = Vector2(130, 100)       # 30px，90px AoE 内
	root.add_child(other)
	other.setup({"id": "victim", "hp": 100, "radius": 6.0})
	other.combat = cs
	cs.register_body(other, other.combat_faction())
	var corpse: EnemyBase = auto_free(EnemyBase.new())
	corpse.position = Vector2(160, 100)      # 60px，AoE 内但已死
	root.add_child(corpse)
	corpse.setup({"id": "corpse", "hp": 100, "radius": 6.0})
	cs.register_body(corpse, corpse.combat_faction())
	corpse.state = EnemyBase.State.DEAD      # 模拟同拍先死（快照内已 DEAD）
	# 火+冰 → SHATTER（帧号按 StatusComponent 阈值/ICD 注入，不依赖真实时钟）
	var f0 := Engine.get_physics_frames()
	var st: StatusComponent = trig.status
	st.apply_hit(Elements.Id.FIRE, 8, f0)
	st.apply_hit(Elements.Id.FIRE, 8, f0 + 10)     # 燃烧激活
	st.apply_hit(Elements.Id.ICE, 8, f0 + 20)
	st.apply_hit(Elements.Id.ICE, 8, f0 + 30)      # 火+冰 → 淬爆事件置位
	for _i in 5:
		await get_tree().physics_frame       # 敌 tick 消费 resonance_event → _shatter_aoe
	assert_int(other.hp).is_equal(100 - 12)  # 1.5×8=12 落在他体
	assert_int(trig.hp).is_equal(100)        # 触发体自身不免（燃烧 DoT 未到跳点，无掉血）
	assert_int(corpse.hp).is_equal(100)      # 已死体跳过
