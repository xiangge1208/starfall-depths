class_name TestSkillsBerserkWarlock
extends GdUnitTestSuite
## M5 T4：狂战士·烈（血怒 + 破釜）+ 术士·蚀（虹吸 + 献祭）（附录 L §3 逐字）。
## - 血怒：HP<50%（恰 50% 不激活）攻速 +25%（tick 续写 atk_speed_boost 共享窗）+
##   受到伤害 +1（take_hit_ctx 入口读点，乘区收口后固定加算）；
## - 破釜：耗 2 HP（pay_hp 绕盾直扣）5s 伤害 +40%/移速 +15%；强化 8s + 击杀返还
##   1 HP（≤2 次/施放）；
## - 虹吸：击杀吸 2 蓝（add_energy clamp）；
## - 献祭：耗 2 HP 得 40 蓝（clamp），4s 法杖/激光伤 +20%（combat 回响同款口径）；
##   强化附加 6s 全伤害 +10%（scaled_damage 祝福同通道）；
## - 禁自杀守卫：HP≤2 双技能均不可发动（can_cast 门控 + pay_hp 兜底），CD 不烧。
## 遥测/音频随实现落点覆盖（bloodbath_cast/sacrifice_cast/kill_* 事件、bloodbath/
## sacrifice sfx 键见 test_audio_wiring 全量完备性回归）。

const PLAYER_SCENE := preload("res://core/player/player.tscn")

class RigProbe extends WeaponRig:
	pass

# ---- 夹具 ----

func _player() -> Player:
	var p: Player = auto_free(Player.new())
	p._test_init()
	return p

func _rig(p: Player) -> RigProbe:
	var r := RigProbe.new()
	p.add_child(r)
	r._test_init()
	p.weapon_rig = r
	return r

func _berserk(p: Player, data: Dictionary = {}) -> BerserkBloodbath:
	var sk := BerserkBloodbath.new()
	p.passive_id = "bloodrage"                            # HeroApplier 装配口径（被动门控依赖）
	sk.setup(p, data)
	p.add_child(sk)
	return sk

func _warlock(p: Player, data: Dictionary = {}) -> WarlockSacrifice:
	var sk := WarlockSacrifice.new()
	p.passive_id = "siphon"                               # HeroApplier 装配口径
	p.hp_max = 5                                          # 附录 L §3 面板（5/4/140/80）
	p.hp = 5
	p.energy_max = 140
	sk.setup(p, data)
	p.add_child(sk)
	return sk

## 回响同款入树假敌（hero_passives 先例：进 "enemies" 组 + 注册进 combat）。
func _enemy(root: Node2D, cs: CombatSystem, at: Vector2, hp := 100) -> EnemyBase:
	var e := EnemyBase.new()
	e._test_init({"id": "m5t4_dummy", "hp": hp, "radius": 6.0})
	e.brain_pos = at
	e.position = at
	root.add_child(e)
	e.add_to_group("enemies")
	cs.register_body(e, e.combat_faction())
	return e

func _combat(root: Node2D) -> CombatSystem:
	var cs := CombatSystem.new(root, RngSvc.stream(0, "combat"))
	cs.crit_chance = 0.0
	auto_free(cs)
	root.add_child(cs)
	return cs

## 命中结算驱动（hero_passives._fire_at 同款：staff 弹落敌心 vel 0，物理帧推进至退场）。
func _fire_at(root: Node2D, cs: CombatSystem, at: Vector2, damage: int) -> void:
	cs.spawn_projectile({
		"pos": at, "vel": Vector2.ZERO, "damage": damage,
		"faction": Projectile.Faction.PLAYER, "element": Elements.Id.NONE,
		"pierce": 0, "bounce": 0, "life_seconds": 1.0, "radius": 3.0,
		"source_type": "weapon", "source_id": "huoqiuzhang",
		"source_name": "huoqiuzhang", "attack_name": "射击",
	})
	for _i in 10:
		await get_tree().physics_frame


# ================================================================ 破釜（烈）

func test_bloodbath_cast_costs_2_hp_and_opens_300t_windows() -> void:
	var p := _player()
	_rig(p)
	var sk := _berserk(p)
	assert_bool(sk.cast(100)).is_true()
	assert_int(p.hp).is_equal(6)                          # 耗 2 HP（绕盾直扣）
	assert_float(p.skill_dmg_bonus_pct).is_equal_approx(0.40, 0.001)
	assert_int(p.skill_dmg_bonus_until).is_equal(100 + 300)   # 5s
	assert_float(p.move_speed_boost_pct).is_equal_approx(0.15, 0.001)
	assert_int(p.move_speed_boost_until).is_equal(100 + 300)
	assert_int(p.scaled_damage(10, 100)).is_equal(14)     # ×1.4
	assert_int(p.scaled_damage(10, 100 + 300)).is_equal(10)   # 恰到期不含（严格 <）

func test_bloodbath_upgraded_last_480t() -> void:
	var p := _player()
	var sk := _berserk(p, {"upgraded": true})
	assert_bool(sk.cast(100)).is_true()
	assert_int(p.skill_dmg_bonus_until).is_equal(100 + 480)   # 强化 8s
	assert_int(p.move_speed_boost_until).is_equal(100 + 480)

func test_bloodbath_suicide_guard_hp_le_2_blocked() -> void:
	var p := _player()
	var sk := _berserk(p)
	p.hp = 2
	assert_bool(sk.can_cast(100)).is_false()              # HP≤2 不可发动
	assert_bool(sk.cast(100)).is_false()
	assert_int(p.hp).is_equal(2)                          # 未扣血
	p.hp = 3
	assert_bool(sk.cast(100)).is_true()                   # 守卫未烧 CD：同拍可放
	assert_int(p.hp).is_equal(1)                          # 支付后恒 ≥1（禁自杀）
	assert_int(sk.cooldown_remaining(100)).is_equal(sk.cooldown_ticks)   # CD 自成功拍起算

func test_bloodbath_pay_hp_bypasses_shield() -> void:
	# 「耗 2 HP」是资源价不是受击：护盾不代付（take_hit 口径会把 3 盾先扣光）。
	var p := _player()
	var sk := _berserk(p)
	p.shield = 3
	assert_bool(sk.cast(100)).is_true()
	assert_int(p.shield).is_equal(3)
	assert_int(p.hp).is_equal(6)

func test_bloodbath_kill_refund_upgraded_max_2_per_cast() -> void:
	var p := _player()
	var sk := _berserk(p, {"upgraded": true})
	var f := Engine.get_physics_frames()
	assert_bool(sk.cast(f)).is_true()
	p.hp = 1                                              # 先扣血再压血线（守卫在施放拍判定）
	EventBus.enemy_killed.emit("dummy")
	assert_int(p.hp).is_equal(2)                          # 返还 1 HP
	EventBus.enemy_killed.emit("dummy")
	assert_int(p.hp).is_equal(3)
	EventBus.enemy_killed.emit("dummy")
	assert_int(p.hp).is_equal(3)                          # ≤2 次：第 3 击不返还

func test_bloodbath_kill_refund_base_and_expired_window_noop() -> void:
	var p := _player()
	var sk := _berserk(p)                                 # 非强化：无返还
	var f := Engine.get_physics_frames()
	assert_bool(sk.cast(f)).is_true()
	p.hp = 1
	EventBus.enemy_killed.emit("dummy")
	assert_int(p.hp).is_equal(1)
	var sk2 := _berserk(p, {"upgraded": true})
	p.hp = 6                                              # 恢复血线过守卫（守卫只在施放拍判定）
	assert_bool(sk2.cast(f)).is_true()                    # 同拍重放（无玩家 CD 冲突，实例独立）
	p.hp = 1                                              # 施放后才压血线
	sk2._refund_until = f - 1                             # 窗过期（直驱注入帧口径）
	EventBus.enemy_killed.emit("dummy")
	assert_int(p.hp).is_equal(1)

func test_bloodbath_recast_rearms_refund_counter() -> void:
	var p := _player()
	var sk := _berserk(p, {"upgraded": true})
	var f := Engine.get_physics_frames()
	assert_bool(sk.cast(f)).is_true()
	p.hp = 1
	EventBus.enemy_killed.emit("dummy")
	EventBus.enemy_killed.emit("dummy")
	assert_int(p.hp).is_equal(3)
	p.hp = 3
	assert_bool(sk.cast(f + sk.cooldown_ticks)).is_true()   # CD 过后重放（hp=3 过守卫）
	assert_int(sk._refund_left).is_equal(2)                 # 每次施放重置 ≤2


# ================================================================ 血怒（烈被动）

func test_bloodrage_threshold_strict_below_half_flip() -> void:
	var p := _player()
	_berserk(p)
	p.hp_max = 8
	p.hp = 4                                              # 恰 50%：不激活（严格 <）
	assert_bool(p.bloodrage_enraged()).is_false()
	p.hp = 3                                              # 37.5%：激活
	assert_bool(p.bloodrage_enraged()).is_true()
	p.heal(8)                                             # 回满：退出
	assert_bool(p.bloodrage_enraged()).is_false()

func test_bloodrage_atk_speed_window_write_and_expiry() -> void:
	var p := _player()
	_rig(p)
	var sk := _berserk(p)
	p.hp_max = 8
	p.hp = 3
	sk.tick(100)                                          # 激活：续写共享窗（frame+1 滚动）
	assert_float(p.atk_speed_boost_pct).is_equal_approx(0.25, 0.001)
	assert_int(p.atk_speed_boost_until).is_equal(101)
	var w := {"id": "jiaoju", "rate": 2.0, "is_melee": false}
	assert_float(p.weapon_rig.effective_attack_rate(w, p, 100)).is_equal_approx(2.5, 0.001)
	p.heal(8)                                             # 回满：停写，旧窗 1 拍内自然过期
	sk.tick(105)
	assert_float(p.weapon_rig.effective_attack_rate(w, p, 105)).is_equal_approx(2.0, 0.001)

func test_bloodrage_inactive_tick_does_not_clobber_shrine_window() -> void:
	var p := _player()
	var sk := _berserk(p)
	p.hp_max = 8
	p.hp = 8                                              # 非激活
	p.atk_speed_boost_pct = 0.30                          # 模拟战神像在窗
	p.atk_speed_boost_until = 9999
	sk.tick(100)                                          # 未激活拍零写入
	assert_float(p.atk_speed_boost_pct).is_equal_approx(0.30, 0.001)
	assert_int(p.atk_speed_boost_until).is_equal(9999)

func test_bloodrage_incoming_damage_plus_one_flat() -> void:
	var p := _player()
	_berserk(p)
	p.hp_max = 8
	p.shield = 0
	p.hp = 3                                              # 激活
	p.take_hit_ctx({"amount": 1}, 100)
	assert_int(p.hp).is_equal(1)                          # 1 +1 = 2 伤
	p.hp = 4                                              # 恰 50%：不激活
	p.take_hit_ctx({"amount": 1}, 200)
	assert_int(p.hp).is_equal(3)                          # 1 伤（无 +1）
	var p2 := _player()                                   # 非血怒英雄零漂移
	_berserk(p2)
	p2.passive_id = "defiance"
	p2.shield = 0
	p2.hp = 3
	p2.take_hit_ctx({"amount": 1}, 100)
	assert_int(p2.hp).is_equal(2)

func test_bloodrage_plus_one_after_multiplicative_dr() -> void:
	# 「固定」语义：+1 加算收口在乘区（狂潮 -30%）之后——10×0.7=7 → 8。
	# hp_max 24/hp 10：激活且留 2 HP 非致死（避免致死路径旁支）。
	var p := _player()
	_berserk(p)
	p.hp_max = 24
	p.shield = 0
	p.hp = 10
	p.rampage_active_until = 999
	p.take_hit_ctx({"amount": 10}, 100)
	assert_int(p.hp).is_equal(2)


# ================================================================ 献祭（蚀）

func test_sacrifice_pays_2_hp_gains_40_energy_clamped() -> void:
	var p := _player()
	var sk := _warlock(p)
	p.hp = 5
	p.energy = 100
	assert_bool(sk.cast(100)).is_true()
	assert_int(p.hp).is_equal(3)
	assert_int(p.energy).is_equal(140)
	assert_int(p.sacrifice_weapon_until).is_equal(100 + 240)  # 4s
	assert_bool(sk.cast(100 + sk.cooldown_ticks)).is_true()
	assert_int(p.energy).is_equal(140)                    # clamp：不溢出上限
	assert_int(p.hp).is_equal(1)

func test_sacrifice_suicide_guard_hp_le_2_blocked() -> void:
	var p := _player()
	var sk := _warlock(p)
	p.hp = 2
	p.energy = 10
	assert_bool(sk.can_cast(100)).is_false()
	assert_bool(sk.cast(100)).is_false()
	assert_int(p.hp).is_equal(2)
	assert_int(p.energy).is_equal(10)
	p.hp = 3
	assert_bool(sk.cast(100)).is_true()                   # 守卫未烧 CD
	assert_int(p.hp).is_equal(1)
	assert_int(p.energy).is_equal(50)

func test_sacrifice_weapon_mult_staff_only_and_expiry() -> void:
	var p := _player()
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	cs.register_body(p, Projectile.Faction.PLAYER)        # player_body 捕获（register_body 习语）
	p.sacrifice_weapon_until = -1                         # 未施放：恒 1.0
	var staff := {"source_type": "weapon", "source_id": "huoqiuzhang"}
	var bow := {"source_type": "weapon", "source_id": "liannu"}
	assert_float(cs._player_global_mult(true, staff, null, 100)).is_equal_approx(1.0, 0.001)
	var sk := _warlock(p)
	assert_bool(sk.cast(200)).is_true()
	assert_float(cs._player_global_mult(true, staff, null, 200)).is_equal_approx(1.2, 0.001)
	assert_float(cs._player_global_mult(true, staff, null, 200 + 240)).is_equal_approx(1.0, 0.001)  # 恰到期不含
	assert_float(cs._player_global_mult(true, bow, null, 200)).is_equal_approx(1.0, 0.001)   # 非法杖/激光
	assert_float(cs._player_global_mult(true, {"source_type": "summon", "source_id": "turret"}, null, 200)).is_equal_approx(1.0, 0.001)
	assert_float(cs._player_global_mult(false, staff, null, 200)).is_equal_approx(1.0, 0.001)  # 敌方弹

func test_sacrifice_weapon_mult_stacks_with_echo_passive() -> void:
	# 与回响（m4-c2）叠乘：1.15×1.2=1.38（两乘区独立通道）。
	var p := _player()
	p.passive_id = "echo"
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	cs.hero_passive_id = "echo"
	cs.register_body(p, Projectile.Faction.PLAYER)
	var sk := _warlock(p)
	assert_bool(sk.cast(200)).is_true()
	var staff := {"source_type": "weapon", "source_id": "huoqiuzhang"}
	assert_float(cs._player_global_mult(true, staff, null, 200)).is_equal_approx(1.38, 0.001)

func test_sacrifice_weapon_window_full_pipeline_hit() -> void:
	# 全链路：staff 弹命中结算过 _player_global_mult（7 伤 ×1.2=8.4 → 向下取整 8）。
	var p := _player()
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	cs.register_body(p, Projectile.Faction.PLAYER)
	var e := _enemy(root, cs, Vector2(200, 0), 100)
	p.sacrifice_weapon_until = Engine.get_physics_frames() + 100
	await _fire_at(root, cs, Vector2(200, 0), 7)
	assert_int(e.hp).is_equal(92)

func test_sacrifice_upgraded_adds_360t_all_damage_window() -> void:
	var p := _player()
	var sk := _warlock(p, {"upgraded": true})
	assert_bool(sk.cast(100)).is_true()
	assert_float(p.skill_dmg_bonus_pct).is_equal_approx(0.10, 0.001)
	assert_int(p.skill_dmg_bonus_until).is_equal(100 + 360)   # 6s
	assert_int(p.scaled_damage(10, 100)).is_equal(11)     # ×1.10
	assert_int(p.scaled_damage(10, 100 + 360)).is_equal(10)   # 恰到期不含
	assert_int(p.sacrifice_weapon_until).is_equal(100 + 240)  # 基础窗照开（附加语义）

func test_sacrifice_base_no_all_damage_window() -> void:
	var p := _player()
	var sk := _warlock(p)
	assert_bool(sk.cast(100)).is_true()
	assert_float(p.skill_dmg_bonus_pct).is_equal_approx(0.0, 0.001)
	assert_int(p.skill_dmg_bonus_until).is_equal(-1)      # 非强化不开全伤害窗
	assert_int(p.scaled_damage(10, 100)).is_equal(10)


# ================================================================ 虹吸（蚀被动）

func test_siphon_kill_grants_2_energy_clamped() -> void:
	var p := _player()
	p.passive_id = "siphon"
	p.energy_max = 140                                    # 蚀面板蓝上限（5/4/140/80）
	p.energy = 10
	p._on_enemy_killed("dummy")
	assert_int(p.energy).is_equal(12)
	p.energy = 139
	p._on_enemy_killed("dummy")
	assert_int(p.energy).is_equal(140)                    # clamp：不溢出上限

func test_siphon_zero_drift_non_siphon_passives() -> void:
	var p := _player()
	p.passive_id = "defiance"
	p.energy = 10
	p._on_enemy_killed("dummy")
	assert_int(p.energy).is_equal(10)
	var p2 := _player()
	p2.energy = 10
	p2._on_enemy_killed("dummy")
	assert_int(p2.energy).is_equal(10)

func test_siphon_via_eventbus_in_tree() -> void:
	# 生产订阅路径：入树玩家 _ready 挂 EventBus.enemy_killed → 广播驱动吸蓝。
	var p: Player = PLAYER_SCENE.instantiate() as Player
	auto_free(p)
	add_child(p)
	p.passive_id = "siphon"
	p.energy = 10
	EventBus.enemy_killed.emit("dummy")
	assert_int(p.energy).is_equal(12)


# ================================================================ 框架契约

func test_data_row_numbers_flow_through_setup() -> void:
	# heroes.json：berserk 720t/0 蓝、warlock 600t/0 蓝（数值照抄不调参）。
	var pb := _player()
	var sb := _berserk(pb, {"cooldown_ticks": int(GameDB.get_hero("berserk")["skill_cd"]),
		"energy_cost": int(GameDB.get_hero("berserk")["skill_energy"])})
	assert_int(sb.cooldown_ticks).is_equal(720)
	assert_int(sb.energy_cost).is_equal(0)
	var pw := _player()
	var sw := _warlock(pw, {"cooldown_ticks": int(GameDB.get_hero("warlock")["skill_cd"]),
		"energy_cost": int(GameDB.get_hero("warlock")["skill_energy"])})
	assert_int(sw.cooldown_ticks).is_equal(600)
	assert_int(sw.energy_cost).is_equal(0)

func test_null_player_placeholder_smoke_unchanged() -> void:
	# test_heroes 通用冒烟同口径：无绑定装配下 cast 过框架门为 true（守卫直通零漂移）。
	var sb: BerserkBloodbath = auto_free(BerserkBloodbath.new())
	sb.setup(null, {"id": "berserk", "cooldown_ticks": 720, "energy_cost": 0})
	assert_bool(sb.cast(0)).is_true()
	var sw: WarlockSacrifice = auto_free(WarlockSacrifice.new())
	sw.setup(null, {"id": "warlock", "cooldown_ticks": 600, "energy_cost": 0})
	assert_bool(sw.cast(0)).is_true()

func test_pay_hp_refuses_when_hp_le_cost() -> void:
	var p := _player()
	p.hp = 2
	assert_bool(p.pay_hp(2)).is_false()
	assert_int(p.hp).is_equal(2)
	p.hp = 3
	assert_bool(p.pay_hp(2)).is_true()
	assert_int(p.hp).is_equal(1)
