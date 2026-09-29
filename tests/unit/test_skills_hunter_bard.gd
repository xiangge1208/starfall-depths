class_name TestSkillsHunterBard
extends GdUnitTestSuite
## M5 T7：猎手·隼（弱点洞察 + 猎印）+ 吟游·弦（渐强 + 高潮）（附录 L §3 逐字）。
## - 弱点洞察：同敌第 3 连发必暴（影袭 forced_crit 同口径——暴击率置 1），断连
##   >3s 清零（恰 3s 不断）、触发后 3s 冷却、换敌互不影响；无挂载零漂移；
## - 猎印：标记最近敌 5s 受伤 ×1.25（GDD §7.1 全局乘区向下取整），死亡爆 30/90px
##   AoE，替换摘钩不残留爆裂；强化双印（cap=2 语义以注入短 CD 钉死，数据行不动）；
## - 渐强：连续命中维持 3s 进入攻速 +15%（受击重置；不强吃更高窗）；
## - 高潮：4s 玩家攻速 +30% / 翻滚 CD -12t（meta 通道落账到期摘除）/ 友方实体
##   ally_atk_speed meta 通道（炮台节拍 ÷1.3 实测）；强化到期开 3s 渐强免重置窗。
## 遥测/音频随实现落点覆盖（deadeye_crit/hunter_mark_cast/mark_burst/crescendo_*/
## finale_cast、hunter_mark/bard_finale sfx 键见 test_audio_wiring 全量完备性回归）。

const PLAYER_SCENE := preload("res://core/player/player.tscn")

# ---- 夹具（test_skills_berserk_warlock / test_summons 同款习语） ----

func _player() -> Player:
	var p: Player = auto_free(Player.new())
	p._test_init()
	return p

class RigProbe extends WeaponRig:
	pass

func _rig(p: Player) -> RigProbe:
	var r := RigProbe.new()
	p.add_child(r)
	r._test_init()
	p.weapon_rig = r
	return r

func _hunter(p: Player, data: Dictionary = {}) -> HunterMark:
	var sk := HunterMark.new()
	p.passive_id = "deadeye_insight"                  # HeroApplier 装配口径（被动门控依赖）
	sk.setup(p, data)
	p.add_child(sk)
	return sk

func _bard(p: Player, data: Dictionary = {}) -> BardFinale:
	var sk := BardFinale.new()
	p.passive_id = "crescendo"                        # HeroApplier 装配口径
	sk.setup(p, data)
	p.add_child(sk)
	return sk

func _combat(root: Node2D) -> CombatSystem:
	var cs := CombatSystem.new(root, RngSvc.stream(0, "combat"))
	cs.crit_chance = 0.0                              # 基础暴击 0：必暴只可能来自计数缝
	auto_free(cs)
	root.add_child(cs)
	return cs

## 入树假敌（进 "enemies" 组 + 注册进 combat；hero_passives 先例）。
func _enemy(root: Node2D, cs: CombatSystem, at: Vector2, hp := 100) -> EnemyBase:
	var e := EnemyBase.new()
	e._test_init({"id": "m5t7_dummy", "hp": hp, "radius": 6.0})
	e.brain_pos = at
	e.position = at
	root.add_child(e)
	e.add_to_group("enemies")
	cs.register_body(e, e.combat_faction())
	return e

## 命中结算驱动（staff 弹落敌心 vel 0，物理帧推进至退场）。
func _fire_at(root: Node2D, cs: CombatSystem, at: Vector2, damage: int) -> void:
	cs.spawn_projectile({
		"pos": at, "vel": Vector2.ZERO, "damage": damage,
		"faction": Projectile.Faction.PLAYER, "element": Elements.Id.NONE,
		"pierce": 0, "bounce": 0, "life_seconds": 1.0, "radius": 3.0,
		"source_type": "weapon", "source_id": "lieluren",
		"source_name": "lieluren", "attack_name": "射击",
	})
	for _i in 10:
		await get_tree().physics_frame

## 生产口径挂载（player.tscn "Skill" 恒名节点换装——combat 缝 get_node("Skill") 寻址）。
func _mount_as_skill_node(p: Player, data: Dictionary = {}) -> HunterMark:
	var sk := HunterMark.new()
	sk.name = "Skill"
	sk.setup(p, data)
	p.add_child(sk)
	return sk


# ================================================================ 弱点洞察（隼被动）

func test_deadeye_third_hit_flags_force_crit_and_restarts_count() -> void:
	var p := _player()
	var sk := _hunter(p)
	var dummy := _player()                            # 计数键只看 instance_id，占位体即可
	assert_bool(sk.note_player_hit(dummy, 100)).is_false()
	assert_bool(sk.note_player_hit(dummy, 110)).is_false()
	assert_int(sk.deadeye_count(dummy)).is_equal(2)
	assert_bool(sk.note_player_hit(dummy, 120)).is_true()  # 第 3 连发
	assert_int(sk.deadeye_count(dummy)).is_equal(0)        # 触发后归零（进入 3s 冷却）

func test_deadeye_gap_over_3s_resets_count() -> void:
	var p := _player()
	var sk := _hunter(p)
	var dummy := _player()
	assert_bool(sk.note_player_hit(dummy, 100)).is_false()
	assert_bool(sk.note_player_hit(dummy, 200)).is_false()
	assert_bool(sk.note_player_hit(dummy, 390)).is_false()  # 间隔 190 > 180：断连清零重计
	assert_int(sk.deadeye_count(dummy)).is_equal(1)
	assert_bool(sk.note_player_hit(dummy, 400)).is_false()
	assert_bool(sk.note_player_hit(dummy, 410)).is_true()   # 重计后的第 3 发

func test_deadeye_gap_exactly_3s_keeps_chain() -> void:
	# 边界钉死：恰 180t（3s）间隔不算断连（规格「3s 无命中后清零」按 >3s 口径落地）。
	var p := _player()
	var sk := _hunter(p)
	var dummy := _player()
	assert_bool(sk.note_player_hit(dummy, 100)).is_false()
	assert_bool(sk.note_player_hit(dummy, 280)).is_false()  # 间隔恰 180：连击保活
	assert_bool(sk.note_player_hit(dummy, 290)).is_true()

func test_deadeye_per_enemy_counts_independent() -> void:
	var p := _player()
	var sk := _hunter(p)
	var a := _player()
	var b := _player()
	assert_bool(sk.note_player_hit(a, 100)).is_false()
	assert_bool(sk.note_player_hit(b, 100)).is_false()
	assert_bool(sk.note_player_hit(a, 110)).is_false()
	assert_bool(sk.note_player_hit(b, 110)).is_false()
	assert_bool(sk.note_player_hit(a, 120)).is_true()   # A 满 3 发（B 不干扰）
	assert_bool(sk.note_player_hit(b, 120)).is_true()   # B 独立满 3 发
	assert_int(sk.deadeye_count(a)).is_equal(0)
	assert_int(sk.deadeye_count(b)).is_equal(0)

func test_deadeye_trigger_cooldown_3s_no_recount() -> void:
	var p := _player()
	var sk := _hunter(p)
	var dummy := _player()
	assert_bool(sk.note_player_hit(dummy, 100)).is_false()
	assert_bool(sk.note_player_hit(dummy, 110)).is_false()
	assert_bool(sk.note_player_hit(dummy, 120)).is_true()   # 触发：锁定至 300
	for f in [130, 200, 270]:                           # 冷却期命中不计数
		assert_bool(sk.note_player_hit(dummy, f)).is_false()
	assert_int(sk.deadeye_count(dummy)).is_equal(0)
	assert_bool(sk.note_player_hit(dummy, 310)).is_false()  # 锁定已过：last=120 逾 3s 清零 → 从 1 重计
	assert_int(sk.deadeye_count(dummy)).is_equal(1)
	assert_bool(sk.note_player_hit(dummy, 320)).is_false()
	assert_bool(sk.note_player_hit(dummy, 330)).is_true()

func test_deadeye_pipeline_forces_crit_on_third_hit() -> void:
	# 全链路：crit_chance=0 基线，第 3 发经 combat 缝置 cc=1 → 5 伤 ×2 暴击。
	var p := _player()
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	cs.register_body(p, Projectile.Faction.PLAYER)
	var e := _enemy(root, cs, Vector2(200, 0), 100)
	_mount_as_skill_node(p)
	await _fire_at(root, cs, Vector2(200, 0), 5)
	await _fire_at(root, cs, Vector2(200, 0), 5)
	assert_int(e.hp).is_equal(90)                       # 前两发 5+5（0% 基线无暴击）
	await _fire_at(root, cs, Vector2(200, 0), 5)
	assert_int(e.hp).is_equal(80)                       # 第 3 发必暴：×2 = 10

func test_deadeye_zero_drift_without_mounted_skill() -> void:
	# 无 Skill 挂载（非隼/纯弹幕环境）：同链路 3 发恒 5 伤（缝 has_method 门控回落）。
	var p := _player()
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	cs.register_body(p, Projectile.Faction.PLAYER)
	var e := _enemy(root, cs, Vector2(200, 0), 100)
	await _fire_at(root, cs, Vector2(200, 0), 5)
	await _fire_at(root, cs, Vector2(200, 0), 5)
	await _fire_at(root, cs, Vector2(200, 0), 5)
	assert_int(e.hp).is_equal(85)


# ================================================================ 猎印（隼主动）

func test_mark_cast_targets_nearest_enemy() -> void:
	var p := _player()
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	p.combat = cs
	p.position = Vector2.ZERO
	var near := _enemy(root, cs, Vector2(100, 0))
	var far := _enemy(root, cs, Vector2(200, 0))
	var sk := _hunter(p)
	assert_bool(sk.cast(100)).is_true()
	assert_bool(sk.is_target_marked(near, 100)).is_true()
	assert_bool(sk.is_target_marked(far, 100)).is_false()

func test_mark_amp_pipeline_floor_min_one() -> void:
	# 7 伤 ×1.25 = 8.75 → 向下取整 8（GDD §7.1 全局乘区收口）；未标记恒 7。
	var p := _player()
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	cs.register_body(p, Projectile.Faction.PLAYER)
	p.combat = cs                                       # 技能选敌/AoE 查询走房间 combat
	p.position = Vector2.ZERO
	var marked := _enemy(root, cs, Vector2(100, 0))
	var plain := _enemy(root, cs, Vector2(-500, 0))
	var sk := _mount_as_skill_node(p)                   # 生产挂载名（combat 缝寻址 "Skill"）
	# 生产帧口径：cast 后管线命中按真实物理帧结算（_fire_at await physics_frame），
	# 标记窗必须同基准——注入 100 会即刻过期（skill 与窗皆帧敏感）。
	assert_bool(sk.cast(Engine.get_physics_frames())).is_true()
	assert_bool(sk.is_target_marked(marked, Engine.get_physics_frames())).is_true()
	await _fire_at(root, cs, Vector2(100, 0), 7)
	assert_int(marked.hp).is_equal(92)                  # 7×1.25 → 8
	await _fire_at(root, cs, Vector2(-500, 0), 7)
	assert_int(plain.hp).is_equal(93)                   # 未标记：7

func test_mark_amp_direct_mult_and_expiry_via_tick() -> void:
	var p := _player()
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	p.combat = cs
	var e := _enemy(root, cs, Vector2(100, 0))
	var sk := _hunter(p)
	assert_bool(sk.cast(1000)).is_true()
	assert_float(sk.hit_damage_mult(e, 1299)).is_equal_approx(1.25, 0.001)  # 窗内（至 1299）
	sk.tick(1299)
	assert_float(sk.hit_damage_mult(e, 1299)).is_equal_approx(1.25, 0.001)
	sk.tick(1300)                                       # 5s（300t）到期
	assert_float(sk.hit_damage_mult(e, 1300)).is_equal_approx(1.0, 0.001)

func test_mark_death_burst_30_in_90px() -> void:
	var p := _player()
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	p.combat = cs
	var marked := _enemy(root, cs, Vector2.ZERO, 100)
	var victim := _enemy(root, cs, Vector2(60, 0), 100)     # 90px 内
	var far := _enemy(root, cs, Vector2(200, 0), 100)       # 90px 外
	var sk := _hunter(p)
	assert_bool(sk.cast(100)).is_true()
	marked.take_hit({"amount": 1000, "is_crit": false, "from": Vector2.ZERO})   # 致死 → die()
	assert_int(marked.hp).is_equal(0)
	assert_bool(marked.state == EnemyBase.State.DEAD).is_true()
	assert_int(victim.hp).is_equal(70)                  # 死亡爆 30
	assert_int(far.hp).is_equal(100)                    # 半径外不波及
	assert_array(sk._marks).is_empty()                  # 即时摘标

func test_mark_base_single_slot_replaces() -> void:
	# 基础版 cap=1：重施替换（append+trim 摘最旧）。CD 注入 100t 仅为让两次施放
	# 在标记 5s 窗内发生——数据行 600t 不动（约束 13），槽位语义由此钉死。
	var p := _player()
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	p.combat = cs
	var a := _enemy(root, cs, Vector2(100, 0))
	var b := _enemy(root, cs, Vector2(140, 0))
	var sk := _hunter(p, {"cooldown_ticks": 100})
	assert_bool(sk.cast(100)).is_true()
	assert_bool(sk.is_target_marked(a, 150)).is_true()
	assert_bool(sk.cast(200)).is_true()
	assert_bool(sk.is_target_marked(b, 250)).is_true()   # 换标最近者 B
	assert_bool(sk.is_target_marked(a, 250)).is_false()  # A 被替换摘标

func test_mark_upgraded_two_marks_coexist() -> void:
	var p := _player()
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	p.combat = cs
	var a := _enemy(root, cs, Vector2(100, 0))
	var b := _enemy(root, cs, Vector2(140, 0))
	var sk := _hunter(p, {"cooldown_ticks": 100, "upgraded": true})   # 强化行「可同时存在 2 个」
	assert_bool(sk.cast(100)).is_true()
	assert_bool(sk.cast(200)).is_true()                  # 「最近未标记者」→ B
	assert_bool(sk.is_target_marked(a, 250)).is_true()   # 双印并存
	assert_bool(sk.is_target_marked(b, 250)).is_true()

func test_mark_replaced_enemy_does_not_burst() -> void:
	# 替换摘钩：被摘标的 A 死亡不得再触发爆裂（died 连接随摘标断开）。
	var p := _player()
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	p.combat = cs
	var a := _enemy(root, cs, Vector2(100, 0), 100)
	var bystander := _enemy(root, cs, Vector2(160, 0), 100)
	var sk := _hunter(p, {"cooldown_ticks": 100})
	assert_bool(sk.cast(100)).is_true()                  # 标 A
	assert_bool(sk.cast(200)).is_true()                  # 换标 B（远处，无需实体精确性——b 不在场也回落最近）
	a.take_hit({"amount": 1000, "is_crit": false, "from": Vector2(100, 0)})
	assert_int(bystander.hp).is_equal(100)               # A 已摘标：无爆裂

func test_hunter_data_row_numbers_flow_through_setup() -> void:
	# heroes.json：hunter 600t/10 蓝（数值照抄不调参）。
	var p := _player()
	var sk := _hunter(p, {"cooldown_ticks": int(GameDB.get_hero("hunter")["skill_cd"]),
		"energy_cost": int(GameDB.get_hero("hunter")["skill_energy"])})
	assert_int(sk.cooldown_ticks).is_equal(600)
	assert_int(sk.energy_cost).is_equal(10)

func test_hunter_null_player_placeholder_smoke_unchanged() -> void:
	# test_heroes 通用冒烟同口径：无绑定装配下 cast 过框架门为 true。
	var sk: HunterMark = auto_free(HunterMark.new())
	sk.setup(null, {"id": "hunter", "cooldown_ticks": 600, "energy_cost": 10})
	assert_bool(sk.cast(0)).is_true()


# ================================================================ 渐强（弦被动）

func test_crescendo_enters_after_3s_sustained_hits() -> void:
	var p := _player()
	var sk := _bard(p)
	assert_bool(sk.note_player_hit(null, 100)).is_false()
	assert_bool(sk.note_player_hit(null, 190)).is_false()
	assert_bool(sk.crescendo_active()).is_false()        # 维持 170t：未满
	assert_bool(sk.note_player_hit(null, 280)).is_false()  # 280-100=180：满 3s 进入
	assert_bool(sk.crescendo_active()).is_true()
	sk.tick(280)                                         # 激活拍续写共享窗（frame+1 滚动）
	assert_float(p.atk_speed_boost_pct).is_equal_approx(0.15, 0.001)
	assert_int(p.atk_speed_boost_until).is_equal(281)
	_rig(p)                                              # 裸玩家无 rig（player.tscn 子节点）——端到端攻速断言需注入
	var w := {"id": "liannu", "rate": 2.0, "is_melee": false}
	assert_float(p.weapon_rig.effective_attack_rate(w, p, 280)).is_equal_approx(2.3, 0.001)

func test_crescendo_chain_break_after_gap_over_3s() -> void:
	var p := _player()
	var sk := _bard(p)
	assert_bool(sk.note_player_hit(null, 100)).is_false()
	assert_bool(sk.note_player_hit(null, 200)).is_false()
	assert_bool(sk.note_player_hit(null, 400)).is_false()  # 间隔 200 > 180：断连重计
	assert_bool(sk.crescendo_active()).is_false()
	assert_bool(sk.note_player_hit(null, 570)).is_false()  # 570-400=170：未满
	assert_bool(sk.crescendo_active()).is_false()
	assert_bool(sk.note_player_hit(null, 580)).is_false()  # 580-400=180：进入
	assert_bool(sk.crescendo_active()).is_true()

func test_crescendo_gap_exactly_3s_keeps_chain() -> void:
	var p := _player()
	var sk := _bard(p)
	assert_bool(sk.note_player_hit(null, 100)).is_false()
	assert_bool(sk.note_player_hit(null, 280)).is_false()  # 恰 180t：连击保活且即满 3s
	assert_bool(sk.crescendo_active()).is_true()

func test_crescendo_reset_on_player_damaged() -> void:
	var p := _player()
	var sk := _bard(p)
	assert_bool(sk.note_player_hit(null, 100)).is_false()
	assert_bool(sk.note_player_hit(null, 280)).is_false()
	assert_bool(sk.crescendo_active()).is_true()
	p.shield = 0
	p.take_hit_ctx({"amount": 1}, 290)                   # 受击 → EventBus.player_damaged
	assert_bool(sk.crescendo_active()).is_false()        # 重置：清状态清连击
	sk.tick(291)
	assert_float(p.atk_speed_boost_pct).is_equal_approx(0.0, 0.001)   # 停写（旧 1 拍窗已过）
	assert_bool(sk.note_player_hit(null, 300)).is_false()
	assert_bool(sk.crescendo_active()).is_false()        # 需重新维持 3s
	assert_bool(sk.note_player_hit(null, 480)).is_false()
	assert_bool(sk.crescendo_active()).is_true()

func test_crescendo_tick_does_not_clobber_stronger_window() -> void:
	# 高潮/战神像更强窗存活时不自我降档；窗过期后恢复续写（血怒「未激活拍零写入」对偶）。
	var p := _player()
	var sk := _bard(p)
	assert_bool(sk.note_player_hit(null, 0)).is_false()
	assert_bool(sk.note_player_hit(null, 180)).is_false()
	assert_bool(sk.crescendo_active()).is_true()
	p.atk_speed_boost_pct = 0.30                         # 模拟高潮窗存活
	p.atk_speed_boost_until = 9999
	sk.tick(200)
	assert_float(p.atk_speed_boost_pct).is_equal_approx(0.30, 0.001)
	p.atk_speed_boost_until = 199                        # 窗闭
	sk.tick(200)
	assert_float(p.atk_speed_boost_pct).is_equal_approx(0.15, 0.001)
	assert_int(p.atk_speed_boost_until).is_equal(201)

func test_crescendo_hit_never_forces_crit() -> void:
	# 同一 note_player_hit 缝：弦恒 false（必暴是隼专属语义）。
	var p := _player()
	var sk := _bard(p)
	assert_bool(sk.note_player_hit(null, 100)).is_false()
	assert_bool(sk.note_player_hit(null, 110)).is_false()
	assert_bool(sk.note_player_hit(null, 120)).is_false()


# ================================================================ 高潮（弦主动）

func test_finale_opens_windows_and_roll_cd_reduction() -> void:
	var p := _player()
	var sk := _bard(p)
	assert_bool(sk.cast(100)).is_true()
	assert_float(p.atk_speed_boost_pct).is_equal_approx(0.30, 0.001)
	assert_int(p.atk_speed_boost_until).is_equal(100 + 240)           # 4s
	assert_float(float(p.get_meta("ally_atk_speed_pct", 0.0))).is_equal_approx(0.30, 0.001)
	assert_int(int(p.get_meta("ally_atk_speed_until", -1))).is_equal(340)
	assert_int(p.roll_cd_reduction_ticks).is_equal(12)                # 翻滚 CD -0.2s
	assert_int(int(p.get_meta("drink_roll_cd_reduction_ticks", 0))).is_equal(12)
	assert_int(p.effective_roll_cd_ticks()).is_equal(30)              # 42-12
	assert_bool(sk.finale_active(339)).is_true()
	assert_bool(sk.finale_active(340)).is_false()

func test_finale_expiry_rolls_back_roll_cd_and_meta() -> void:
	var p := _player()
	var sk := _bard(p)
	assert_bool(sk.cast(100)).is_true()
	sk.tick(339)                                         # 窗内：不动账
	assert_int(p.roll_cd_reduction_ticks).is_equal(12)
	sk.tick(340)                                         # 到期收尾
	assert_int(p.roll_cd_reduction_ticks).is_equal(0)    # 现值回退
	assert_int(int(p.get_meta("drink_roll_cd_reduction_ticks", 0))).is_equal(0)   # 通道落账回退
	assert_int(p.effective_roll_cd_ticks()).is_equal(42)
	assert_bool(sk.finale_active(340)).is_false()

func test_finale_upgraded_grace_opens_on_expiry() -> void:
	var p := _player()
	var sk := _bard(p, {"upgraded": true})
	assert_bool(sk.cast(100)).is_true()
	sk.tick(340)                                         # 到期：开 3s 渐强免重置窗
	assert_int(sk._grace_until).is_equal(340 + 180)      # 强化行「结束后 3s 渐强不重置」
	sk._grace_until = Engine.get_physics_frames() + 100  # 免重置窗内存活化（真实帧口径）
	assert_bool(sk.note_player_hit(null, 0)).is_false()
	assert_bool(sk.note_player_hit(null, 180)).is_false()
	assert_bool(sk.crescendo_active()).is_true()
	p.shield = 0
	p.take_hit_ctx({"amount": 1}, 200)                   # 受击：窗内不重置
	assert_bool(sk.crescendo_active()).is_true()
	sk._grace_until = -1                                 # 窗外：恢复受击重置
	p.take_hit_ctx({"amount": 1}, 300)
	assert_bool(sk.crescendo_active()).is_false()

func test_finale_base_no_grace_after_expiry() -> void:
	var p := _player()
	var sk := _bard(p)
	assert_bool(sk.cast(100)).is_true()
	sk.tick(340)
	assert_int(sk._grace_until).is_equal(-1)             # 非强化：无免重置窗

func test_finale_ally_channel_scales_turret_fire_interval() -> void:
	# 友方实体通道端到端：meta 窗内炮台开火节拍 30t → 23t（30 ÷ 1.3 = 23.08 → round 23）；
	# 对照炮台（无 meta/无 player 注入）恒等 30t。两套独立 combat 隔离弹池计数。
	var aura_root: Node2D = auto_free(Node2D.new())
	add_child(aura_root)
	var aura_cs := _combat(aura_root)
	var p := _player()
	p.combat = aura_cs
	aura_root.add_child(p)
	_enemy(aura_root, aura_cs, Vector2(100, 50))
	var bard_sk := _bard(p)
	assert_bool(bard_sk.cast(1000)).is_true()
	var turret := TurretSummon.new()
	aura_root.add_child(turret)
	turret.combat = aura_cs                              # deploy 方注入习语
	turret.player = p                                    # SummonBase 召唤主注入
	turret.begin(1000)
	turret.tick(1030)                                    # 首发节拍 1000+30
	assert_int(aura_cs.active_count()).is_equal(1)
	turret.tick(1052)                                    # 窗内下一发 1030+23=1053：未到
	assert_int(aura_cs.active_count()).is_equal(1)
	turret.tick(1053)
	assert_int(aura_cs.active_count()).is_equal(2)       # 光环节拍生效（30t → 23t）
	var plain_root: Node2D = auto_free(Node2D.new())
	add_child(plain_root)
	var plain_cs := _combat(plain_root)
	_enemy(plain_root, plain_cs, Vector2(100, 50))
	var turret_plain := TurretSummon.new()               # 对照：无窗恒等 30t
	plain_root.add_child(turret_plain)
	turret_plain.combat = plain_cs
	turret_plain.begin(1000)
	turret_plain.tick(1030)
	assert_int(plain_cs.active_count()).is_equal(1)
	turret_plain.tick(1059)                              # 1030+30=1060：未到
	assert_int(plain_cs.active_count()).is_equal(1)
	turret_plain.tick(1060)
	assert_int(plain_cs.active_count()).is_equal(2)      # 基线 30t 节拍不受影响

func test_ally_fire_interval_math_and_fallbacks() -> void:
	var p := _player()
	var sk := _bard(p)
	assert_bool(sk.cast(100)).is_true()
	var probe: SummonBase = auto_free(SummonBase.new())           # 入树外探针：auto_free 防孤儿
	probe.player = p
	assert_int(probe.ally_fire_interval(30, 200)).is_equal(23)   # 30 ÷ 1.3 → 23
	assert_int(probe.ally_fire_interval(30, 340)).is_equal(30)   # frame >= until：恒等
	var bare: SummonBase = auto_free(SummonBase.new())            # 无 player/无 meta：恒等
	assert_int(bare.ally_fire_interval(30, 200)).is_equal(30)
	assert_int(bare.ally_fire_interval(1, 200)).is_equal(1)      # 退化间隔不下除

func test_bard_data_row_numbers_flow_through_setup() -> void:
	# heroes.json：bard 720t/0 蓝（数值照抄不调参）。
	var p := _player()
	var sk := _bard(p, {"cooldown_ticks": int(GameDB.get_hero("bard")["skill_cd"]),
		"energy_cost": int(GameDB.get_hero("bard")["skill_energy"])})
	assert_int(sk.cooldown_ticks).is_equal(720)
	assert_int(sk.energy_cost).is_equal(0)

func test_bard_null_player_placeholder_smoke_unchanged() -> void:
	var sk: BardFinale = auto_free(BardFinale.new())
	sk.setup(null, {"id": "bard", "cooldown_ticks": 720, "energy_cost": 0})
	assert_bool(sk.cast(0)).is_true()

