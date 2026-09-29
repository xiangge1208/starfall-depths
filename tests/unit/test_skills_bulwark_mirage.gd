class_name TestSkillsBulwarkMirage
extends GdUnitTestSuite
## M5 T6：铁卫·锚（固守 + 架设）+ 影卫·蜃（调虎 + 留影）（附录 L §3 逐字）。
## - 固守：静止 1.5s（90t）获受伤 -25%（移动即失效，停写 ≤2 拍自然过期）；
## - 架设：CD 12s/0蓝，面前 26px 钢盾（HP 30，挡双方弹幕——本体 ENEMY 阵营接我方弹
##   + catcher PLAYER 阵营接敌方弹，同一 HP 池）；强化碎裂迸 3 碎片各 10 伤；
## - 调虎：诱饵存活期敌 AI 优先攻诱饵（EnemyBase.target_override 仇恨缝；退场回落）；
## - 留影：CD 10s/10蓝，4s 诱饵（3 HP），消失/被击毁 60px 内 15 伤烟爆；
##   强化再按技能键手动引爆（不烧 CD 不耗蓝，CD 自首次施放起算）。
## 遥测/音频随实现落点覆盖（steel_shield/decoy_leave/decoy_burst 键见 test_audio_wiring
## 全量完备性回归）。

# ---- 夹具 ----

func _root() -> Node2D:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	return root

func _player(root: Node2D) -> Player:
	var p: Player = auto_free(Player.new())
	p._test_init()
	root.add_child(p)
	return p

func _combat(root: Node2D) -> CombatSystem:
	var cs := CombatSystem.new(root, RngSvc.stream(0, "combat"))
	cs.crit_chance = 0.0
	auto_free(cs)
	root.add_child(cs)
	return cs

func _bulwark(p: Player, data: Dictionary = {}) -> BulwarkShield:
	var sk := BulwarkShield.new()
	p.passive_id = "entrench"                          # HeroApplier 装配口径（被动门控依赖）
	sk.setup(p, data)
	p.add_child(sk)
	return sk

func _mirage(p: Player, data: Dictionary = {}) -> MirageDecoy:
	var sk := MirageDecoy.new()
	p.passive_id = "decoy_master"                      # HeroApplier 装配口径
	sk.setup(p, data)
	p.add_child(sk)
	return sk

## 回响同款入树假敌（进 "enemies" 组 + 注册 ENEMY 阵营战斗体）。
func _enemy(root: Node2D, cs: CombatSystem, at: Vector2, hp := 100) -> EnemyBase:
	var e := EnemyBase.new()
	e._test_init({"id": "m5t6_dummy", "hp": hp, "radius": 6.0})
	e.brain_pos = at
	e.position = at
	root.add_child(e)
	e.add_to_group("enemies")
	cs.register_body(e, e.combat_faction())
	return e

## 弹落点直驱（m5-t4 _fire_at 同款：vel 0 落点即命中，物理帧推进至退场）。
func _fire_at(cs: CombatSystem, at: Vector2, damage: int, faction: int) -> void:
	cs.spawn_projectile({
		"pos": at, "vel": Vector2.ZERO, "damage": damage,
		"faction": faction, "element": Elements.Id.NONE,
		"pierce": 0, "bounce": 0, "life_seconds": 1.0, "radius": 3.0,
		"source_type": "weapon", "source_id": "cilishoutao",
		"source_name": "cilishoutao", "attack_name": "射击",
	})
	for _i in 10:
		await get_tree().physics_frame


# ================================================================ 架设（锚主动）

func test_shield_cast_places_steel_shield_ahead_of_facing() -> void:
	var root := _root()
	var p := _player(root)
	var cs := _combat(root)
	p.combat = cs
	var sk := _bulwark(p)
	assert_bool(sk.cast(100)).is_true()                # 0 蓝：默认 100 蓝恒可放
	assert_bool(sk.shield_alive()).is_true()
	assert_int(sk.shield.hp).is_equal(30)              # 附录 L §3 逐字
	assert_vector(sk.shield.global_position).is_equal_approx(Vector2(26, 0), Vector2(0.01, 0.01))
	# 双判定体注册：本体 ENEMY 阵营 + catcher PLAYER 阵营（挡双方弹幕通道）。
	assert_bool(cs.bodies_in_radius(Vector2(26, 0), 1.0,
		Projectile.Faction.ENEMY).has(sk.shield)).is_true()
	assert_bool(cs.bodies_in_radius(Vector2(26, 0), 1.0,
		Projectile.Faction.PLAYER).has(sk.shield.catcher)).is_true()

func test_shield_no_combat_silent_noop() -> void:
	# 裸测/无房：cast 过框架门但不产生实体（占位语义）。
	var root := _root()
	var p := _player(root)
	var sk := _bulwark(p)
	assert_bool(sk.cast(100)).is_true()
	assert_bool(sk.shield_alive()).is_false()

func test_shield_blocks_player_side_bullet() -> void:
	# 我方弹打盾：盾扣 HP、弹碎，盾后敌不受伤（挡己方火力=规格逐字）。
	var root := _root()
	var p := _player(root)
	var cs := _combat(root)
	p.combat = cs
	var e := _enemy(root, cs, Vector2(60, 0), 100)
	var sk := _bulwark(p)
	assert_bool(sk.cast(100)).is_true()
	await _fire_at(cs, Vector2(26, 0), 5, Projectile.Faction.PLAYER)
	assert_int(sk.shield.hp).is_equal(25)
	assert_int(e.hp).is_equal(100)
	assert_int(cs.active_count()).is_equal(0)          # 弹在盾上碎裂（pierce 0）

func test_shield_blocks_enemy_side_bullet_protects_player() -> void:
	# 敌方弹打 catcher：同一 HP 池扣减，弹碎不再飞向玩家。
	var root := _root()
	var p := _player(root)
	var cs := _combat(root)
	p.combat = cs
	cs.register_body(p, Projectile.Faction.PLAYER)
	var sk := _bulwark(p)
	assert_bool(sk.cast(100)).is_true()
	await _fire_at(cs, Vector2(26, 0), 5, Projectile.Faction.ENEMY)
	assert_int(sk.shield.hp).is_equal(25)
	assert_int(p.hp).is_equal(8)                       # 玩家毫发无伤
	assert_int(cs.active_count()).is_equal(0)

func test_shield_destroyable_unregister_and_idempotent() -> void:
	var root := _root()
	var p := _player(root)
	var cs := _combat(root)
	p.combat = cs
	var sk := _bulwark(p)
	assert_bool(sk.cast(100)).is_true()
	var shield: Node2D = sk.shield
	shield.take_hit({"amount": 999})                   # C-5 固定伤害制直扣
	assert_bool(sk.shield_alive()).is_false()
	# 双判定体注销（哈希不泄漏）：再查询为空；已碎再击零副作用（幂等门）。
	assert_int(cs.bodies_in_radius(Vector2(26, 0), 20.0, Projectile.Faction.ENEMY).size()).is_equal(0)
	shield.take_hit({"amount": 5})
	assert_bool(sk.shield_alive()).is_false()

func test_shield_replacement_destroys_old() -> void:
	var root := _root()
	var p := _player(root)
	var cs := _combat(root)
	p.combat = cs
	var sk := _bulwark(p)
	assert_bool(sk.cast(100)).is_true()
	sk.shield.take_hit({"amount": 10})                 # 旧盾 20 HP
	assert_bool(sk.cast(100 + 720)).is_true()          # CD 过后重放
	assert_bool(sk.shield_alive()).is_true()
	assert_int(sk.shield.hp).is_equal(30)              # 新盾满血（替换即碎裂语义）

func test_upgraded_shatter_spawns_3_shards_10_dmg() -> void:
	var root := _root()
	var p := _player(root)
	var cs := _combat(root)
	p.combat = cs
	var sk := _bulwark(p, {"upgraded": true})
	assert_bool(sk.cast(100)).is_true()
	sk.shield.take_hit({"amount": 999})
	assert_bool(sk.shield_alive()).is_false()
	assert_int(cs.active_count()).is_equal(3)          # 碎裂迸 3 碎片
	var dirs := [Vector2.RIGHT, Vector2.from_angle(TAU / 3.0), Vector2.from_angle(2.0 * TAU / 3.0)]
	for i in 3:
		var shard: Projectile = cs.pool.active[i]
		assert_int(shard.damage).is_equal(10)          # 各 10 伤
		assert_int(shard.faction).is_equal(Projectile.Faction.PLAYER)   # 玩家弹结算通道
		assert_vector(shard.vel).is_equal_approx(dirs[i] * 180.0, Vector2(0.01, 0.01)) # 120° 均布确定性

func test_base_shield_no_shards_on_destroy() -> void:
	var root := _root()
	var p := _player(root)
	var cs := _combat(root)
	p.combat = cs
	var sk := _bulwark(p)                              # 非强化：无碎片
	assert_bool(sk.cast(100)).is_true()
	sk.shield.take_hit({"amount": 999})
	assert_int(cs.active_count()).is_equal(0)


# ================================================================ 固守（锚被动）

func test_entrench_opens_dr_window_after_90_stationary_ticks() -> void:
	var root := _root()
	var p := _player(root)
	var sk := _bulwark(p)
	for f in range(100, 190):                          # 静止 90t（1.5s）
		sk.tick(f)
	assert_bool(sk.entrenched()).is_true()
	assert_float(p.incoming_dr_pct).is_equal_approx(0.25, 0.001)
	assert_int(p.incoming_dr_until).is_equal(189 + 2)  # 滚动续窗前瞻 2t
	# 受伤 -25%：10 × 0.75 = 7.5 → 向下取整 7（狂潮/潮汐同口径 min 1）。
	p.shield = 0
	p.take_hit_ctx({"amount": 10}, 190)
	assert_int(p.hp).is_equal(1)

func test_entrench_movement_resets_and_window_expires() -> void:
	var root := _root()
	var p := _player(root)
	var sk := _bulwark(p)
	for f in range(100, 190):
		sk.tick(f)
	assert_bool(sk.entrenched()).is_true()
	p.position += Vector2(5, 0)                        # 位移（含翻滚/击退任何变化）即清零
	sk.tick(191)
	assert_bool(sk.entrenched()).is_false()
	# 停写 ≤2 拍自然过期：last write until=191，193 拍起全额结算。
	p.shield = 0
	p.take_hit_ctx({"amount": 4}, 193)
	assert_int(p.hp).is_equal(4)                       # 无减伤：全额 4

func test_entrench_stationary_resumes_after_move() -> void:
	var root := _root()
	var p := _player(root)
	var sk := _bulwark(p)
	for f in range(100, 150):
		sk.tick(f)
	p.position += Vector2(3, 0)                        # 移动拍清零
	sk.tick(150)
	assert_bool(sk.entrenched()).is_false()
	for f in range(151, 241):                          # 重新站满 90t
		sk.tick(f)
	assert_bool(sk.entrenched()).is_true()

func test_entrench_gate_non_entrench_passive_noop() -> void:
	# 被动门控：非固守英雄 tick 零写入（T8 圣环复用同窗前零漂移）。
	var root := _root()
	var p := _player(root)
	var sk := _bulwark(p)
	p.passive_id = "defiance"
	for f in range(100, 300):
		sk.tick(f)
	assert_bool(sk.entrenched()).is_false()
	assert_int(p.incoming_dr_until).is_equal(-1)


# ================================================================ 留影（蜃主动）

func test_decoy_cast_registers_player_faction_body() -> void:
	var root := _root()
	var p := _player(root)
	var cs := _combat(root)
	p.combat = cs
	var sk := _mirage(p)
	assert_bool(sk.cast(100)).is_true()
	assert_int(p.energy).is_equal(90)                  # 10 蓝
	assert_bool(sk.decoy_alive()).is_true()
	assert_int(sk.decoy.hp).is_equal(3)                # 附录 L §3 逐字
	assert_bool(cs.bodies_in_radius(Vector2.ZERO, 1.0,
		Projectile.Faction.PLAYER).has(sk.decoy)).is_true()

func test_decoy_expiry_bursts_15_in_60px() -> void:
	var root := _root()
	var p := _player(root)
	var cs := _combat(root)
	p.combat = cs
	var near := _enemy(root, cs, Vector2(50, 0), 100)  # 60px 内
	var far := _enemy(root, cs, Vector2(110, 0), 100)  # 60px 外
	var sk := _mirage(p)
	assert_bool(sk.cast(100)).is_true()
	sk.decoy.tick(100 + 240)                           # 4s 到期（SummonBase 计时）
	assert_bool(sk.decoy_alive()).is_false()
	assert_int(near.hp).is_equal(85)                   # 烟爆 15 伤
	assert_int(far.hp).is_equal(100)                   # 半径外不波及

func test_decoy_destroyed_by_enemy_bullet_bursts() -> void:
	# 全链路：敌方弹击毁诱饵（3 HP）→ 烟爆结算（诱饵挡弹护玩家）。
	var root := _root()
	var p := _player(root)
	var cs := _combat(root)
	p.combat = cs
	cs.register_body(p, Projectile.Faction.PLAYER)
	var near := _enemy(root, cs, Vector2(130, 0), 100) # 距爆点 (80,0) 50px
	var sk := _mirage(p)
	# 含 await 的用例必须以真实引擎帧锚定存活计时：SummonBase._physics_process 自驱
	# 读 Engine.get_physics_frames()，注入小帧会在整跑大帧号下「施放即过期」。
	var f := Engine.get_physics_frames()
	assert_bool(sk.cast(f)).is_true()
	sk.decoy.position = Vector2(80, 0)                 # 诱饵前置于玩家与敌之间
	sk.decoy.brain_pos = Vector2(80, 0)
	await get_tree().physics_frame                     # 哈希随拍对齐（f+1 < f+240 存活）
	await _fire_at(cs, Vector2(80, 0), 2, Projectile.Faction.ENEMY)
	assert_int(sk.decoy.hp).is_equal(1)
	await _fire_at(cs, Vector2(80, 0), 2, Projectile.Faction.ENEMY)
	assert_bool(sk.decoy_alive()).is_false()           # 3 HP 耗尽 → 消失烟爆
	assert_int(near.hp).is_equal(85)
	assert_int(p.hp).is_equal(8)                       # 敌方弹被诱饵拦下

func test_decoy_our_side_projectile_no_friendly_fire() -> void:
	# 我方弹不误伤诱饵（同阵营不结算，FollowAlly 同缝）。
	var root := _root()
	var p := _player(root)
	var cs := _combat(root)
	p.combat = cs
	var sk := _mirage(p)
	var f := Engine.get_physics_frames()               # 含 await：真实帧锚定（同上披露）
	assert_bool(sk.cast(f)).is_true()
	sk.decoy.position = Vector2(80, 0)
	sk.decoy.brain_pos = Vector2(80, 0)
	await get_tree().physics_frame
	await _fire_at(cs, Vector2(80, 0), 5, Projectile.Faction.PLAYER)
	assert_int(sk.decoy.hp).is_equal(3)
	assert_bool(sk.decoy_alive()).is_true()


# ================================================================ 调虎（蜃被动）

func test_decoy_master_aggro_override_and_fallback_on_despawn() -> void:
	var root := _root()
	var p := _player(root)
	var cs := _combat(root)
	p.combat = cs
	var e := _enemy(root, cs, Vector2(100, 0), 100)
	var sk := _mirage(p)
	assert_bool(sk.cast(100)).is_true()
	sk.tick(101)                                       # 施放拍 + 每拍维护注入
	assert_bool(e.get("target_override") == sk.decoy).is_true()
	assert_vector(e._player_pos()).is_equal_approx(Vector2.ZERO, Vector2(0.01, 0.01))   # 仇恨读点改读诱饵
	var late := _enemy(root, cs, Vector2(150, 0), 100) # 施放后新刷的敌人
	sk.tick(102)
	assert_bool(late.get("target_override") == sk.decoy).is_true()
	sk.decoy.tick(100 + 240)                           # 退场（烟爆同拍）清除
	assert_bool(e.get("target_override") == null).is_true()
	assert_bool(late.get("target_override") == null).is_true()
	e.brain_pos = Vector2(100, 0)
	assert_vector(e._player_pos()).is_equal_approx(Vector2(100, 0), Vector2(0.01, 0.01))  # 回落玩家

func test_aggro_seam_falls_back_on_invalid_or_dead_override() -> void:
	# EnemyBase.target_override 仇恨缝自证回落：释放（is_instance_valid）/亡故（is_alive）。
	var e: EnemyBase = auto_free(EnemyFactory.create(
		{"id": "crossbowman", "archetype": "shooter", "hp": 16, "speed": 60}))
	var spy: Node2D = auto_free(SpyBody.new())
	spy.brain_pos = Vector2(300, 0)
	e.player_ref = spy
	assert_vector(e._player_pos()).is_equal_approx(Vector2(300, 0), Vector2(0.01, 0.01))
	var decoy: Node2D = auto_free(StubDecoy.new())
	decoy.brain_pos = Vector2(40, 0)
	e.target_override = decoy
	assert_vector(e._player_pos()).is_equal_approx(Vector2(40, 0), Vector2(0.01, 0.01))
	decoy.alive = false                                # 自报亡故 → 回落
	assert_vector(e._player_pos()).is_equal_approx(Vector2(300, 0), Vector2(0.01, 0.01))
	decoy.alive = true
	e.target_override = decoy
	decoy.free()                                       # 覆写体释放 → 回落（is_instance_valid）
	assert_vector(e._player_pos()).is_equal_approx(Vector2(300, 0), Vector2(0.01, 0.01))
	e.target_override = null
	assert_vector(e._player_pos()).is_equal_approx(Vector2(300, 0), Vector2(0.01, 0.01))

func test_aggro_not_applied_without_passive_or_decoy() -> void:
	# 门控：非调虎被动不写 override；诱饵退场后 tick 零开销直返。
	var root := _root()
	var p := _player(root)
	var cs := _combat(root)
	p.combat = cs
	var e := _enemy(root, cs, Vector2(100, 0), 100)
	var sk := _mirage(p)
	p.passive_id = "defiance"
	assert_bool(sk.cast(100)).is_true()
	sk.tick(101)
	assert_bool(e.get("target_override") == null).is_true()


# ================================================================ 强化手动引爆

func test_upgraded_manual_detonate_no_cd_no_energy() -> void:
	var root := _root()
	var p := _player(root)
	var cs := _combat(root)
	p.combat = cs
	var near := _enemy(root, cs, Vector2(50, 0), 100)
	var sk := _mirage(p, {"upgraded": true})
	assert_bool(sk.cast(100)).is_true()
	assert_int(p.energy).is_equal(90)
	assert_int(sk.cooldown_remaining(100)).is_equal(600)
	assert_bool(sk.cast(150)).is_true()                # 再按技能键 = 引爆
	assert_bool(sk.decoy_alive()).is_false()
	assert_int(p.energy).is_equal(90)                  # 不耗蓝
	assert_int(sk.cooldown_remaining(150)).is_equal(550)   # 不烧 CD（自首施放起算）
	assert_int(near.hp).is_equal(85)                   # 提前烟爆照常结算

func test_base_recast_blocked_while_cd() -> void:
	# 非强化：诱饵存活期再按 = 普通施放门（CD 内拒绝）。
	var root := _root()
	var p := _player(root)
	var cs := _combat(root)
	p.combat = cs
	var sk := _mirage(p)
	assert_bool(sk.cast(100)).is_true()
	assert_bool(sk.cast(150)).is_false()
	assert_bool(sk.decoy_alive()).is_true()


# ================================================================ 框架契约

func test_data_row_numbers_flow_through_setup() -> void:
	# heroes.json：bulwark 720t/0 蓝、mirage 600t/10 蓝（数值照抄不调参）。
	var pb := _root()
	var pw := _root()
	var sb := _bulwark(_player(pb), {"cooldown_ticks": int(GameDB.get_hero("bulwark")["skill_cd"]),
		"energy_cost": int(GameDB.get_hero("bulwark")["skill_energy"])})
	assert_int(sb.cooldown_ticks).is_equal(720)
	assert_int(sb.energy_cost).is_equal(0)
	var sw := _mirage(_player(pw), {"cooldown_ticks": int(GameDB.get_hero("mirage")["skill_cd"]),
		"energy_cost": int(GameDB.get_hero("mirage")["skill_energy"])})
	assert_int(sw.cooldown_ticks).is_equal(600)
	assert_int(sw.energy_cost).is_equal(10)

func test_null_player_placeholder_smoke_unchanged() -> void:
	# test_heroes 通用冒烟同口径：无绑定装配下 cast 过框架门为 true（零漂移）。
	var sb: BulwarkShield = auto_free(BulwarkShield.new())
	sb.setup(null, {"id": "bulwark", "cooldown_ticks": 720, "energy_cost": 0})
	assert_bool(sb.cast(0)).is_true()
	var sw: MirageDecoy = auto_free(MirageDecoy.new())
	sw.setup(null, {"id": "mirage", "cooldown_ticks": 600, "energy_cost": 10})
	assert_bool(sw.cast(0)).is_true()


# ---- 测试替身 ----

## 玩家替身（PlayerProxy 契约：brain_pos + take_hit）。
class SpyBody extends Node2D:
	var brain_pos := Vector2.ZERO
	func take_hit(_ctx: Dictionary) -> void:
		pass

## 仇恨缝自证替身（is_alive() duck 契约）。
class StubDecoy extends Node2D:
	var brain_pos := Vector2.ZERO
	var alive := true
	func is_alive() -> bool:
		return alive
