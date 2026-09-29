class_name TestSkillsMonkCleric
extends GdUnitTestSuite
## M5 T8：武僧·岳（行云 + 震山）+ 圣职·烛（圣佑 + 圣环）（附录 L §3 逐字）。
## - 行云：近战命中积「势」（≤5 层封顶），每层近战伤 +8%（melee.gd 单点读数缝——
##   meta 通道 1+0.08×层，非武僧缺省零漂移；无衰减条款）；
## - 震山：耗尽全部势 → 90px 环形 AoE（每层 8 伤固定值 + 击退 8px）；0 层合法 no-op
##   过门；强化满「势」反弹窗 ×2（7t→14t = 0.12→0.24s；窗口开启拍定格——挥击第 1 拍
##   命中补满即本挥击生效，开启后中途耗势不缩窗）；
## - 圣佑：护盾破碎拍（EventBus.shield_broken 同源信号）→ 1.5s（90t）无敌，每房 1 次
##   （combat 实例键更替 = 换房重置预算——FloorScene._wire_room_combat 每房重注入契约）；
## - 圣环：3s 静止环（110px）：环内受伤 -25%（复用 m5-t6 incoming_dr 通用窗，×0.75
##   向下取整 min 1；离环 ≤2t 过期）+ 触敌 2 伤/0.5s（30t 节拍，末拍含共 6 拍）；
##   强化结束回 1 HP（heal 单一收口——灾厄禁疗静默、已死不回、上限 clamp）。
## 遥测/音频随实现落点覆盖（flow_full/quake_cast/aegis_trigger/sanctuary_cast/
## sanctuary_heal、monk_quake/cleric_sanctuary sfx 键见 test_audio_wiring 全量完备性回归）。

# ---- 夹具（test_skills_hunter_bard / test_melee_parry 同款习语） ----

func _player() -> Player:
	var p: Player = auto_free(Player.new())
	p._test_init()
	return p

func _monk(p: Player, data: Dictionary = {}) -> MonkQuake:
	var sk := MonkQuake.new()
	sk.name = "Skill"                                 # 生产挂载名（melee 上报缝寻址）
	p.passive_id = "flow_stance"                      # HeroApplier 装配口径（被动门控依赖）
	sk.setup(p, data)
	p.add_child(sk)
	return sk

func _cleric(p: Player, data: Dictionary = {}) -> ClericSanctuary:
	var sk := ClericSanctuary.new()
	sk.name = "Skill"
	p.passive_id = "aegis_blessing"                   # HeroApplier 装配口径
	sk.setup(p, data)
	p.add_child(sk)
	return sk

func _combat(root: Node2D) -> CombatSystem:
	var cs := CombatSystem.new(root, RngSvc.stream(0, "combat"))
	cs.crit_chance = 0.0
	auto_free(cs)
	root.add_child(cs)
	return cs

## 入树假敌（进 "enemies" 组 + 注册进 combat；hunter 夹具同款）。
func _enemy(root: Node2D, cs: CombatSystem, at: Vector2, hp := 100) -> EnemyBase:
	var e := EnemyBase.new()
	e._test_init({"id": "m5t8_dummy", "hp": hp, "radius": 6.0})
	e.brain_pos = at
	e.position = at
	root.add_child(e)
	e.add_to_group("enemies")
	cs.register_body(e, e.combat_faction())
	return e

class CsProbe extends CombatSystem:
	# test_melee_parry 同款：脚本化弹幕/命中体 + 记录（PREDELETE 释放池根防孤儿）。
	var reflected: Array = []
	var blocked: Array = []
	var scripted_projectiles: Array[Projectile] = []
	var scripted_body: Node2D
	var _pool_root: Node2D

	func _init() -> void:
		_pool_root = Node2D.new()
		super(_pool_root, null)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE and _pool_root != null:
			_pool_root.free()
			_pool_root = null

	func projectiles_in_arc(_origin: Vector2, _facing: float, _range_px: float, _arc_deg: float, _faction: int) -> Array[Projectile]:
		return scripted_projectiles

	func bodies_in_arc(_origin: Vector2, _facing: float, _range_px: float, _arc_deg: float, _faction: int) -> Array:
		return [scripted_body] if scripted_body != null else []

	func reflect(p: Projectile, dmg: int) -> void:
		reflected.append([p, dmg])

	func block(p: Projectile) -> void:
		blocked.append(p)

class DummyBody extends Node2D:
	var hits: Array = []
	func take_hit(ctx: Dictionary) -> void:
		hits.append(ctx)
	func combat_radius() -> float:
		return 6.0

## 近战管线夹具（test_melee_parry 习语）：武僧初始武器长枪（9 伤/220px/30°）。
func _melee(p: Player, probe: CsProbe) -> Melee:
	var m := Melee.new()
	p.add_child(m)
	m._test_init()
	m.rig = auto_free(WeaponRig.new())
	m.rig.slots = [GameDB.get_weapon("changqiang"), {}]
	m.combat = probe
	return m


# ================================================================ 行云（岳被动）

func test_flow_stacks_accumulate_and_cap_at_five() -> void:
	var p := _player()
	var sk := _monk(p)
	for _i in 7:
		sk.note_melee_hit()                           # 超额命中：≤5 封顶
	assert_int(sk.momentum).is_equal(5)
	assert_bool(sk.momentum_full()).is_true()
	assert_float(float(p.get_meta(MonkQuake.META_MOMENTUM_MULT, 0.0))) \
		.is_equal_approx(1.4, 0.001)                  # 1 + 0.08×5

func test_flow_mult_per_stack_values() -> void:
	var p := _player()
	var sk := _monk(p)
	assert_float(float(p.get_meta(MonkQuake.META_MOMENTUM_MULT, 0.0))) \
		.is_equal_approx(1.0, 0.001)                  # 装配基线（0 层）
	for i in range(1, 6):
		sk.note_melee_hit()
		assert_float(float(p.get_meta(MonkQuake.META_MOMENTUM_MULT, 0.0))) \
			.is_equal_approx(1.0 + 0.08 * float(i), 0.001)

func test_flow_gate_non_flow_stance_passive_noop() -> void:
	var p := _player()
	var sk := _monk(p)
	p.passive_id = "crescendo"                        # 非武僧口径：门控拦
	sk.note_melee_hit()
	sk.note_melee_hit()
	assert_int(sk.momentum).is_equal(0)
	assert_float(float(p.get_meta(MonkQuake.META_MOMENTUM_MULT, 1.0))) \
		.is_equal_approx(1.0, 0.001)                  # 装配基线未被推进

func test_flow_pipeline_hit_builds_stack() -> void:
	# 全链路：真实 Melee 直击路径 → "Skill" 上报缝 → 积层（真实帧无关——直驱 _physics_process）。
	var p := _player()
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var probe: CsProbe = auto_free(CsProbe.new())
	probe.scripted_body = auto_free(DummyBody.new())
	var m := _melee(p, probe)
	var sk := _monk(p)
	assert_bool(m.try_attack(0)).is_true()
	m._physics_process(1.0 / TimeConst.FPS)           # tick1：直击 + 上报
	assert_int(sk.momentum).is_equal(1)
	assert_float(float(p.get_meta(MonkQuake.META_MOMENTUM_MULT, 0.0))) \
		.is_equal_approx(1.08, 0.001)
	var hit: Dictionary = (probe.scripted_body as DummyBody).hits[0]
	assert_int(hit["amount"]).is_equal(9)             # 起手 0 层：基线 9（自身命中不 retro 加成）

func test_flow_pipeline_damage_mult_five_stacks() -> void:
	# 5 层乘区端到端：长枪 9 × 1.4 = 12.6 → round 13（乘在玩家出口之后、暴击掷签之前）。
	var p := _player()
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var probe: CsProbe = auto_free(CsProbe.new())
	probe.scripted_body = auto_free(DummyBody.new())
	var m := _melee(p, probe)
	var sk := _monk(p)
	for _i in 5:
		sk.note_melee_hit()
	assert_bool(m.try_attack(0)).is_true()
	m._physics_process(1.0 / TimeConst.FPS)
	var hit: Dictionary = (probe.scripted_body as DummyBody).hits[0]
	assert_int(hit["amount"]).is_equal(13)
	assert_int(sk.momentum).is_equal(5)               # 本挥击自身命中：封顶不再涨

func test_flow_pipeline_zero_drift_without_monk_skill() -> void:
	# 无 Skill 挂载（非武僧/纯近战环境）：伤害恒基线、meta 不落。
	var p := _player()
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var probe: CsProbe = auto_free(CsProbe.new())
	probe.scripted_body = auto_free(DummyBody.new())
	var m := _melee(p, probe)
	assert_bool(m.try_attack(0)).is_true()
	m._physics_process(1.0 / TimeConst.FPS)
	var hit: Dictionary = (probe.scripted_body as DummyBody).hits[0]
	assert_int(hit["amount"]).is_equal(9)
	assert_bool(p.has_meta(MonkQuake.META_MOMENTUM_MULT)).is_false()
	assert_bool(p.has_meta(MonkQuake.META_PARRY_EXTRA)).is_false()


# ================================================================ 震山（岳主动）

func test_quake_deals_8_per_stack_and_consumes_all() -> void:
	var p := _player()
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	p.combat = cs
	p.position = Vector2.ZERO
	var a := _enemy(root, cs, Vector2(50, 0), 100)
	var b := _enemy(root, cs, Vector2(-40, 30), 100)
	var sk := _monk(p)
	for _i in 3:
		sk.note_melee_hit()
	assert_bool(sk.cast(100)).is_true()
	assert_int(a.hp).is_equal(76)                     # 3 层 × 8 = 24
	assert_int(b.hp).is_equal(76)
	assert_int(sk.momentum).is_equal(0)               # 耗尽
	assert_float(float(p.get_meta(MonkQuake.META_MOMENTUM_MULT, 1.0))) \
		.is_equal_approx(1.0, 0.001)                  # meta 回基线
	assert_int(int(p.get_meta(MonkQuake.META_PARRY_EXTRA, 0))).is_equal(0)

func test_quake_radius_90px_and_knockback_8px() -> void:
	var p := _player()
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	p.combat = cs
	p.position = Vector2.ZERO
	var inside := _enemy(root, cs, Vector2(80, 0), 100)    # ≤90px
	var outside := _enemy(root, cs, Vector2(100, 0), 100)  # >90px
	var sk := _monk(p)
	sk.note_melee_hit()
	assert_bool(sk.cast(100)).is_true()
	assert_int(inside.hp).is_equal(92)                # 1 层 × 8
	assert_vector(inside.brain_pos).is_equal(Vector2(88, 0))   # 击退 8px（背向玩家）
	assert_int(outside.hp).is_equal(100)              # 半径外不波及
	assert_vector(outside.brain_pos).is_equal(Vector2(100, 0))

func test_quake_zero_stacks_noop_but_cast_gates() -> void:
	# 0 层合法 no-op（框架过门语义，CD 照走——hunter 无目标同惯例）。
	var p := _player()
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	p.combat = cs
	p.position = Vector2.ZERO
	var a := _enemy(root, cs, Vector2(50, 0), 100)
	var sk := _monk(p)
	assert_bool(sk.cast(100)).is_true()
	assert_int(a.hp).is_equal(100)
	assert_int(sk.cooldown_remaining(101)).is_equal(539)

func test_quake_dead_enemy_skipped() -> void:
	var p := _player()
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	p.combat = cs
	p.position = Vector2.ZERO
	var dead := _enemy(root, cs, Vector2(30, 0), 1)
	var alive := _enemy(root, cs, Vector2(60, 0), 100)
	dead.take_hit({"amount": 100, "is_crit": false, "from": Vector2.ZERO})   # 先致死
	assert_bool(dead.state == EnemyBase.State.DEAD).is_true()
	var sk := _monk(p)
	sk.note_melee_hit()
	assert_bool(sk.cast(100)).is_true()
	assert_int(alive.hp).is_equal(92)                 # 活体照常结算
	assert_bool(dead.state == EnemyBase.State.DEAD).is_true()

func test_monk_data_row_numbers_flow_through_setup() -> void:
	# heroes.json：monk 540t/0 蓝（数值照抄不调参）。
	var p := _player()
	var sk := _monk(p, {"cooldown_ticks": int(GameDB.get_hero("monk")["skill_cd"]),
		"energy_cost": int(GameDB.get_hero("monk")["skill_energy"])})
	assert_int(sk.cooldown_ticks).is_equal(540)
	assert_int(sk.energy_cost).is_equal(0)

func test_monk_null_player_placeholder_smoke_unchanged() -> void:
	# test_heroes 通用冒烟同口径：无绑定装配下 cast 过框架门为 true。
	var sk: MonkQuake = auto_free(MonkQuake.new())
	sk.setup(null, {"id": "monk", "cooldown_ticks": 540, "energy_cost": 0})
	assert_bool(sk.cast(0)).is_true()
	assert_int(sk.momentum).is_equal(0)


# ================================================================ 反弹窗 ×2（岳强化）

func test_parry_window_doubles_at_full_momentum_upgraded() -> void:
	var p := _player()
	var probe: CsProbe = auto_free(CsProbe.new())
	probe.scripted_projectiles = [auto_free(Projectile.new())]
	var m := _melee(p, probe)
	var sk := _monk(p, {"upgraded": true})
	for _i in 5:
		sk.note_melee_hit()
	assert_int(int(p.get_meta(MonkQuake.META_PARRY_EXTRA, 0))).is_equal(7)
	assert_bool(m.try_attack(0)).is_true()
	for _i in 16:
		m._physics_process(1.0 / TimeConst.FPS)       # 直驱 16 拍（扩展窗全程）
	assert_int(probe.reflected.size()).is_equal(14)   # 3..16t = 14t ≈ 0.24s（×2）
	assert_int(probe.blocked.size()).is_equal(2)      # 1..2t 不变
	assert_bool(m.is_parry_tick(16)).is_true()
	assert_bool(m.is_parry_tick(17)).is_false()

func test_parry_window_full_not_upgraded_stays_baseline() -> void:
	# 满势但未强化：meta 0 → 基线 3..9t（7t），9 拍后挥击结束无额外反弹。
	var p := _player()
	var probe: CsProbe = auto_free(CsProbe.new())
	probe.scripted_projectiles = [auto_free(Projectile.new())]
	var m := _melee(p, probe)
	var sk := _monk(p)                                # 未强化
	for _i in 5:
		sk.note_melee_hit()
	assert_int(int(p.get_meta(MonkQuake.META_PARRY_EXTRA, 0))).is_equal(0)
	assert_bool(m.try_attack(0)).is_true()
	for _i in 16:
		m._physics_process(1.0 / TimeConst.FPS)
	assert_int(probe.reflected.size()).is_equal(7)
	assert_int(probe.blocked.size()).is_equal(2)

func test_parry_window_upgraded_not_full_stays_baseline() -> void:
	# 强化但未满势（3 层，无直击体——窗口开启拍势仍 <5）：meta 0 → 基线 7t。
	var p := _player()
	var probe: CsProbe = auto_free(CsProbe.new())
	probe.scripted_projectiles = [auto_free(Projectile.new())]
	var m := _melee(p, probe)
	var sk := _monk(p, {"upgraded": true})
	for _i in 3:
		sk.note_melee_hit()
	assert_bool(m.try_attack(0)).is_true()
	for _i in 16:
		m._physics_process(1.0 / TimeConst.FPS)
	assert_int(sk.momentum).is_equal(3)
	assert_int(int(p.get_meta(MonkQuake.META_PARRY_EXTRA, 0))).is_equal(0)
	assert_int(probe.reflected.size()).is_equal(7)
	assert_int(probe.blocked.size()).is_equal(2)

func test_parry_window_extends_when_swing_hit_fills_momentum() -> void:
	# 第 1 拍命中补满势 → 第 3 拍窗口开启可见满势 meta → 本挥击即 ×2（实时生效口径）。
	var p := _player()
	var probe: CsProbe = auto_free(CsProbe.new())
	probe.scripted_projectiles = [auto_free(Projectile.new())]
	probe.scripted_body = auto_free(DummyBody.new())  # 直击体：喂层
	var m := _melee(p, probe)
	var sk := _monk(p, {"upgraded": true})
	for _i in 4:
		sk.note_melee_hit()
	assert_bool(m.try_attack(0)).is_true()
	for _i in 16:
		m._physics_process(1.0 / TimeConst.FPS)
	assert_int(sk.momentum).is_equal(5)               # 第 1 拍命中补满
	assert_int(probe.reflected.size()).is_equal(14)   # 本挥击窗口已 ×2
	assert_int(probe.blocked.size()).is_equal(2)

func test_parry_window_frozen_after_mid_swing_quake() -> void:
	# 窗口开启（满势）后第 4 拍施放震山耗势：不缩窗（开启拍已定格）。
	var p := _player()
	var probe: CsProbe = auto_free(CsProbe.new())
	probe.scripted_projectiles = [auto_free(Projectile.new())]
	var m := _melee(p, probe)
	var sk := _monk(p, {"upgraded": true})
	for _i in 5:
		sk.note_melee_hit()
	assert_bool(m.try_attack(0)).is_true()
	for _i in 3:
		m._physics_process(1.0 / TimeConst.FPS)       # tick3：窗口开启并定格 ×2
	assert_int(probe.reflected.size()).is_equal(1)
	assert_bool(sk.cast(Engine.get_physics_frames())).is_true()   # 震山：势清零
	assert_int(int(p.get_meta(MonkQuake.META_PARRY_EXTRA, 0))).is_equal(0)
	for _i in 13:
		m._physics_process(1.0 / TimeConst.FPS)       # tick4..16
	assert_int(probe.reflected.size()).is_equal(14)   # 定格：不缩窗


# ================================================================ 圣佑（烛被动）

func test_aegis_iframes_on_shield_break() -> void:
	var p := _player()
	var sk := _cleric(p)
	var f := Engine.get_physics_frames()
	p.shield = 2
	p.take_hit_ctx({"amount": 5, "source_type": "projectile"}, f)   # 盾 2→0 破碎
	assert_bool(sk._aegis_used).is_true()
	assert_bool(p.is_invincible_at(f)).is_true()
	assert_bool(p.is_invincible_at(f + 48)).is_true()  # 逾受击无敌帧（0.8s）仍在圣佑窗
	assert_bool(p.is_invincible_at(f + 89)).is_true()  # 1.5s = 90t（末拍含）
	assert_bool(p.is_invincible_at(f + 90)).is_false()

func test_aegis_once_per_room_guard() -> void:
	var p := _player()
	var sk := _cleric(p)
	var f0 := Engine.get_physics_frames()
	p.shield = 2
	p.take_hit_ctx({"amount": 5}, f0)                 # 破 1：触发
	assert_bool(sk._aegis_used).is_true()
	for _i in 100:
		await get_tree().physics_frame                # 真实帧推进跨过首窗（90t）
	var f1 := Engine.get_physics_frames()
	p.shield = 2
	p.take_hit_ctx({"amount": 5}, f1)                 # 破 2（同房）：每房守卫拦
	assert_bool(sk._aegis_used).is_true()
	assert_bool(p.is_invincible_at(f1 + 89)).is_false()   # 无新圣佑窗（受击窗仅 f1..f1+47）
	var root2: Node2D = auto_free(Node2D.new())
	add_child(root2)
	p.combat = _combat(root2)                         # 换房：combat 实例更替
	for _i in 60:
		await get_tree().physics_frame                # 跨过破 2 的受击无敌帧
	var f2 := Engine.get_physics_frames()
	p.shield = 2
	p.take_hit_ctx({"amount": 5}, f2)                 # 破 3（新房）：预算重置 → 触发
	assert_bool(sk._aegis_used).is_true()
	assert_bool(p.is_invincible_at(f2 + 89)).is_true()
	assert_bool(p.is_invincible_at(f2 + 90)).is_false()

func test_aegis_gate_non_cleric_passive_noop() -> void:
	var p := _player()
	var sk := _cleric(p)
	p.passive_id = "crescendo"                        # 非圣职口径：门控拦
	p.shield = 2
	var f := Engine.get_physics_frames()
	p.take_hit_ctx({"amount": 5}, f)
	assert_bool(sk._aegis_used).is_false()
	assert_bool(p.is_invincible_at(f + 48)).is_false()   # 无 1.5s 圣佑窗

func test_aegis_no_trigger_when_shield_survives() -> void:
	var p := _player()
	var sk := _cleric(p)
	p.shield = 5
	var f := Engine.get_physics_frames()
	p.take_hit_ctx({"amount": 3}, f)                  # 盾 5→2：未破碎
	assert_bool(sk._aegis_used).is_false()
	assert_bool(p.is_invincible_at(f + 48)).is_false()

func test_aegis_revisiting_same_room_does_not_reset_budget() -> void:
	# 重访已进房（同 CombatSystem 实例回注）：键不变 → 预算不重置（严格于首入口径）。
	var p := _player()
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	p.combat = cs
	var sk := _cleric(p)
	p.shield = 2
	p.take_hit_ctx({"amount": 5}, Engine.get_physics_frames())
	assert_bool(sk._aegis_used).is_true()
	p.combat = cs                                     # 同实例重注（模拟重访）
	p.shield = 2
	p.take_hit_ctx({"amount": 5},
		Engine.get_physics_frames() + 200)            # 注入未来帧逾窗：走守卫
	assert_bool(sk._aegis_used).is_true()


# ================================================================ 圣环（烛主动）

func test_sanctuary_ring_window_and_dr_write() -> void:
	var p := _player()
	var sk := _cleric(p)
	p.position = Vector2.ZERO
	assert_bool(sk.cast(100)).is_true()
	assert_bool(sk.ring_active(100)).is_true()
	assert_bool(sk.ring_active(280)).is_true()        # 末拍含（180t）
	assert_bool(sk.ring_active(281)).is_false()
	sk.tick(100)                                      # 环内：续写减伤窗（+2 前瞻）
	assert_float(p.incoming_dr_pct).is_equal_approx(0.25, 0.001)
	assert_int(p.incoming_dr_until).is_equal(102)

func test_sanctuary_dr_pipeline_floor_and_min_one() -> void:
	# 环内受击管线（复用 m5-t6 通用窗收口）：10 伤 ×0.75 → 向下取整 7；1 伤 ×0.75 →
	# floor 0 → clamp 1（与狂潮/潮汐同 min 1 口径——经共享窗生效不产生 0/负伤）。
	var p := _player()
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	p.combat = cs
	p.position = Vector2.ZERO
	var sk := _cleric(p)
	p.shield = 0                                      # 排除默认护盾吸收（净 HP 口径）
	sk.cast(100)
	sk.tick(100)
	p.take_hit_ctx({"amount": 10}, 101)               # 环内受击：8 - 7
	assert_int(p.hp).is_equal(1)
	sk.tick(150)                                      # 环内续写（窗至 152）
	p.take_hit_ctx({"amount": 1}, 151)                # 逾受击无敌帧（101+48=149）
	assert_int(p.hp).is_equal(0)                      # 8 - 7 - 1（min 1 收口）

func test_sanctuary_dr_expires_after_leaving_ring() -> void:
	# 环锚定施放点（不随人走）；离环停写 ≤2t 过期 → 全额来伤。
	var p := _player()
	var sk := _cleric(p)
	p.position = Vector2.ZERO
	p.shield = 0                                      # 排除默认护盾吸收（净 HP 口径）
	sk.cast(100)
	sk.tick(100)                                      # 末次续写（窗至 102）
	p.position = Vector2(200, 0)
	sk.tick(150)
	sk.tick(200)                                      # 离环：不续写
	p.take_hit_ctx({"amount": 10}, 300)
	assert_int(p.hp).is_equal(0)                      # 8 - 10（无 -25%）

func test_sanctuary_enemy_beats_2_per_half_second() -> void:
	var p := _player()
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	p.combat = cs
	p.position = Vector2.ZERO
	var inside := _enemy(root, cs, Vector2(50, 0), 100)
	var outside := _enemy(root, cs, Vector2(200, 0), 100)
	var sk := _cleric(p)
	assert_bool(sk.cast(100)).is_true()               # until 280；节拍 130..280（6 拍）
	sk.tick(129)
	assert_int(inside.hp).is_equal(100)               # 未到首拍
	sk.tick(130)
	assert_int(inside.hp).is_equal(98)                # 首拍 2 伤
	sk.tick(131)
	assert_int(inside.hp).is_equal(98)                # 非节拍拍空转
	sk.tick(280)
	assert_int(inside.hp).is_equal(88)                # 6 拍 × 2 = 12
	sk.tick(281)                                      # 末拍后：到期收尾
	assert_int(inside.hp).is_equal(88)
	assert_int(outside.hp).is_equal(100)              # 环外不波及
	assert_bool(sk.ring_active(281)).is_false()

func test_sanctuary_tick_without_combat_advances_beats() -> void:
	# 脑层/纯逻辑环境（combat null）：节拍推进、结算跳过、到期收尾正常。
	var p := _player()
	var sk := _cleric(p)
	p.position = Vector2.ZERO
	assert_bool(sk.cast(100)).is_true()
	sk.tick(280)
	sk.tick(281)
	assert_bool(sk.ring_active(281)).is_false()

func test_sanctuary_upgraded_heals_1_on_expiry() -> void:
	var p := _player()
	var sk := _cleric(p, {"upgraded": true})
	p.hp = 4
	sk.cast(100)
	sk.tick(281)                                      # 末拍后首个 tick：到期收尾回血
	assert_int(p.hp).is_equal(5)
	assert_int(sk._ring_until).is_equal(-1)
	sk.tick(300)                                      # 收尾幂等：不再回
	assert_int(p.hp).is_equal(5)

func test_sanctuary_base_no_heal_on_expiry() -> void:
	var p := _player()
	var sk := _cleric(p)
	p.hp = 4
	sk.cast(100)
	sk.tick(281)
	assert_int(p.hp).is_equal(4)                      # 非强化：无结束回血

func test_sanctuary_upgraded_heal_blocked_by_calamity() -> void:
	# 灾厄「治疗无效」（heal 单一收口拦截）：回血静默失效。
	var p := _player()
	var sk := _cleric(p, {"upgraded": true})
	p.set_meta(Player.CALAMITY_HEAL_DISABLED_META, 1)
	p.hp = 4
	sk.cast(100)
	sk.tick(281)
	assert_int(p.hp).is_equal(4)

func test_sanctuary_upgraded_heal_skips_dead() -> void:
	var p := _player()
	var sk := _cleric(p, {"upgraded": true})
	p.hp = 0                                          # 已死：不做无复活语义的起死回生
	sk.cast(100)
	sk.tick(281)
	assert_int(p.hp).is_equal(0)

func test_sanctuary_upgraded_heal_clamps_at_max() -> void:
	var p := _player()
	var sk := _cleric(p, {"upgraded": true})
	p.hp = p.hp_max                                   # 满血：heal mini clamp 不越顶
	sk.cast(100)
	sk.tick(281)
	assert_int(p.hp).is_equal(p.hp_max)

func test_cleric_data_row_numbers_flow_through_setup() -> void:
	# heroes.json：cleric 720t/15 蓝（数值照抄不调参）。
	var p := _player()
	var sk := _cleric(p, {"cooldown_ticks": int(GameDB.get_hero("cleric")["skill_cd"]),
		"energy_cost": int(GameDB.get_hero("cleric")["skill_energy"])})
	assert_int(sk.cooldown_ticks).is_equal(720)
	assert_int(sk.energy_cost).is_equal(15)

func test_cleric_null_player_placeholder_smoke_unchanged() -> void:
	var sk: ClericSanctuary = auto_free(ClericSanctuary.new())
	sk.setup(null, {"id": "cleric", "cooldown_ticks": 720, "energy_cost": 15})
	assert_bool(sk.cast(0)).is_true()
	assert_bool(sk.ring_active(1)).is_false()         # 无绑定装配：_activate no-op 无环
