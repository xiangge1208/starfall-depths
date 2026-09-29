class_name TestSkillsGunslingerLycanStaranchor
extends GdUnitTestSuite
## M5 T9：火枪手·铳（精炼火药 + 齐射）+ 狼人·牙（嗜血 + 变身）+ 星辰·晷（蓄能 + 星陨）
## （附录 L §3 逐字）。
## - 精炼火药：切枪完成锚点（rig._switch_until）后 2s 首发 ×2（consume-on-read，每锚点
##   恰一次；近战面不消费不放大；再切枪再武装；齐射复制弹不吃不占首发）；
## - 齐射：扇形 6 发复制弹（当前武器单发 ×0.6，确定性扇面无 jitter，skill 归因）；
##   强化 8 发 + 穿透 +1（管线钉死穿透命中第二敌）；近战/手刀态无复制源过门 no-op；
## - 嗜血：近战击杀回 1 HP 每房 ≤2（room_cleared 重置；灾厄禁疗不消耗次数）；
## - 变身：6s 移速 +20%/近战伤 +50%/翻滚 80px 覆写/远程锁定拒发；到期恢复
##   （覆写摘除 + 强化结束回 1 HP，灾厄失效）；
## - 蓄能：同向 1s → 伤害 +30%（滚动窗停写过期；15° 阈内保锚、超阈重置；不强吃更强窗）；
## - 星陨：引导 48t → 预警 30t → 90px 40 伤；强化留 2s 星火地面（1 伤/0.5s + SHOCK
##   积累两次触发——毒池同构）。
## 遥测/音频随实现落点覆盖（volley_cast/shift_*/bloodthirst_heal/charge_up_enter/
## starfall_* 事件、volley/lycan_shift/starfall sfx 键见 test_audio_wiring 完备性回归）。

# ---- 夹具（test_skills_hunter_bard / test_skills_berserk_warlock 同款习语） ----

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

func _gunslinger(p: Player, data: Dictionary = {}) -> GunslingerVolley:
	var sk := GunslingerVolley.new()
	sk.name = "Skill"                            # 生产挂载名（player.tscn 恒名节点）
	p.passive_id = "refined_powder"                   # HeroApplier 装配口径
	sk.setup(p, data)
	p.add_child(sk)
	return sk

func _lycan(p: Player, data: Dictionary = {}) -> LycanShift:
	var sk := LycanShift.new()
	sk.name = "Skill"                            # 生产挂载名（player.tscn 恒名节点）
	p.passive_id = "bloodthirst"                      # HeroApplier 装配口径
	sk.setup(p, data)
	p.add_child(sk)
	return sk

func _staranchor(p: Player, data: Dictionary = {}) -> StaranchorStarfall:
	var sk := StaranchorStarfall.new()
	sk.name = "Skill"                            # 生产挂载名（player.tscn 恒名节点）
	p.passive_id = "charge_up"                        # HeroApplier 装配口径
	sk.setup(p, data)
	p.add_child(sk)
	return sk

func _combat(root: Node2D) -> CombatSystem:
	var cs := CombatSystem.new(root, RngSvc.stream(0, "combat"))
	cs.crit_chance = 0.0                              # 基础暴击 0：数值断言不受暴击干扰
	auto_free(cs)
	root.add_child(cs)
	return cs

## 入树假敌（进 "enemies" 组 + 注册进 combat；hunter/bard 先例）。
func _enemy(root: Node2D, cs: CombatSystem, at: Vector2, hp := 100) -> EnemyBase:
	var e := EnemyBase.new()
	e._test_init({"id": "m5t9_dummy", "hp": hp, "radius": 6.0})
	e.brain_pos = at
	e.position = at
	root.add_child(e)
	e.add_to_group("enemies")
	cs.register_body(e, e.combat_faction())
	return e

## 池内本技能复制弹（source_id 过滤；池可能含其他测试弹）。
func _volley_copies(cs: CombatSystem) -> Array:
	var out: Array = []
	for proj in cs.pool.active:
		if proj.source_id == "gunslinger_volley":
			out.append(proj)
	return out

## 最新入池弹（多次开火断言用；pool.active 为追加序）。
func _last_shot(cs: CombatSystem) -> Projectile:
	return cs.pool.active[cs.pool.active.size() - 1]


# ================================================================ 精炼火药（铳被动）

func test_powder_first_shot_doubled_one_frame_window_then_consumed() -> void:
	# 生产路径：真实帧切枪（switch_slot）→ 切枪锁 15t 过后首发 ×2（弹 12 伤 + 出口
	# 读数 ×2）→ 1 拍窗自灭；同锚点第二发不再放大（记账每锚点恰一次）。
	var p := _player()
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	var rig := _rig(p)
	rig.combat = cs
	p.combat = cs
	rig.equip("maodingqiang")                         # 槽 0：副武器（伤害 3）
	rig.equip("zuolunzhengwu")                        # 槽 1：主武器（伤害 6）——切枪后为当前
	var sk := _gunslinger(p)
	var f0 := Engine.get_physics_frames()
	rig.switch_slot(f0)                               # 切枪帧 f0 → 完成锚点 f0+15
	for _i in 16:
		await get_tree().physics_frame                # 切枪锁 15t 过后
	var f1 := Engine.get_physics_frames()
	assert_bool(rig.try_fire(Vector2.RIGHT, f1)).is_true()
	assert_int(cs.pool.active.size()).is_equal(1)
	assert_int(cs.pool.active[0].damage).is_equal(12)  # 首发 6×2
	assert_int(p.powder_dmg_mult_until).is_equal(f1 + 1)   # 一次性窗（开火拍 +1）
	assert_int(p.scaled_damage(10)).is_equal(20)       # 同拍出口读数 ×2
	for _i in 2:
		await get_tree().physics_frame
	assert_int(p.scaled_damage(10)).is_equal(10)       # 窗 1 拍自灭：无残留
	rig._next_fire_frame = 0                          # 越过射速门（测试直驱）
	assert_bool(rig.try_fire(Vector2.RIGHT, Engine.get_physics_frames())).is_true()
	assert_int(_last_shot(cs).damage).is_equal(6)      # 同锚点第二发：无 ×2

func test_powder_window_is_2s_from_switch_completion() -> void:
	# 窗口锚定「切枪动作完成帧」（_switch_until = 切枪帧 + 15）：窗内首发放大、>2s 窗闭；
	# 恰 2s 边界以注入帧纯查询钉死（伤害路径真实帧与锚点解耦，避免边界拍竞争）。
	var p := _player()
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	var rig := _rig(p)
	rig.combat = cs
	rig.equip("zuolunzhengwu")
	var sk := _gunslinger(p)
	while Engine.get_physics_frames() < 200:          # 推进过 2s 窗口径（帧基线，避免负锚点）
		await get_tree().physics_frame
	var f := Engine.get_physics_frames()
	rig._switch_until = f - 60                        # 完成于 1s 前：窗内
	assert_bool(rig.try_fire(Vector2.RIGHT, f)).is_true()
	assert_int(cs.pool.active[0].damage).is_equal(12)  # 首发 6×2
	rig._next_fire_frame = 0
	rig._switch_until = f - 121                       # 完成于 121t 前：窗外（> 2s）
	for _i in 2:
		await get_tree().physics_frame                # 上一发的 1 拍窗先自灭（同拍会残留 ×2）
	assert_bool(rig.try_fire(Vector2.RIGHT, Engine.get_physics_frames())).is_true()
	assert_int(_last_shot(cs).damage).is_equal(6)      # 无 ×2
	rig._switch_until = 5000                          # 边界查询（注入帧确定）
	assert_bool(sk.powder_window_active(5000)).is_true()      # 完成拍即窗开
	assert_bool(sk.powder_window_active(5119)).is_true()      # 完成后 1.98s 仍在
	assert_bool(sk.powder_window_active(5120)).is_false()     # 恰完成 +2s：窗闭（严格 <）
	assert_bool(sk.powder_window_active(4999)).is_false()     # 切枪动作未完成：不开窗

func test_powder_rearms_on_next_switch() -> void:
	var p := _player()
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	var rig := _rig(p)
	rig.combat = cs
	rig.equip("zuolunzhengwu")
	rig.equip("maodingqiang")
	_gunslinger(p)
	var f := Engine.get_physics_frames()
	rig._switch_until = f - 10                        # 锚点 A（刚完成）
	assert_bool(rig.try_fire(Vector2.RIGHT, f)).is_true()
	assert_int(cs.pool.active[0].damage).is_equal(12)
	rig._next_fire_frame = 0
	var f2 := Engine.get_physics_frames()
	rig._switch_until = f2                            # 锚点 B：再切枪再武装
	assert_bool(rig.try_fire(Vector2.RIGHT, f2)).is_true()
	assert_int(_last_shot(cs).damage).is_equal(12)

func test_powder_no_switch_or_unmounted_zero_drift() -> void:
	# 未切过枪（锚点 0）/ 未挂载技能节点（无 weapon_fired 缝写窗）：出口恒等。
	var p := _player()
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	var rig := _rig(p)
	rig.combat = cs
	rig.equip("zuolunzhengwu")
	rig.equip("maodingqiang")
	assert_int(p.scaled_damage(10)).is_equal(10)      # 无窗（字段缺省）
	var f := Engine.get_physics_frames()
	rig._switch_until = f - 10                        # 有锚点但无技能节点写窗
	assert_bool(rig.try_fire(Vector2.RIGHT, f)).is_true()
	assert_int(cs.pool.active[0].damage).is_equal(6)   # 无 ×2（被动随技能装配）

func test_powder_melee_face_gate_direct() -> void:
	# 出口面门控：近战面（当前武器近战/空槽手刀）不吃首发窗——「首发」是枪击语义。
	var p := _player()
	var rig := _rig(p)
	_gunslinger(p)
	p.powder_dmg_mult = 2.0
	p.powder_dmg_mult_until = 9999999
	rig.equip("zuolunzhengwu")
	assert_int(p.scaled_damage(10)).is_equal(20)       # 远程面：×2
	rig.clear_slot(0)
	assert_int(p.scaled_damage(10)).is_equal(10)       # 空槽（手刀态）= 近战面
	rig.equip("duyaduanren")
	assert_int(p.scaled_damage(10)).is_equal(10)       # 近战武器：近战面

func test_powder_volley_does_not_eat_or_consume_first_shot() -> void:
	# 齐射复制弹不吃首发 ×2 也不消费首发记账（齐射不走 weapon_fired，记账不动）——
	# 「首发」留给窗内下一发常规枪击。
	var p := _player()
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	var rig := _rig(p)
	rig.combat = cs
	p.combat = cs
	rig.equip("maodingqiang")                         # 槽 0：副武器（伤害 3）
	rig.equip("zuolunzhengwu")                        # 槽 1：主武器（伤害 6）——切枪后为当前
	var sk := _gunslinger(p)
	var f0 := Engine.get_physics_frames()
	rig.switch_slot(f0)
	for _i in 16:
		await get_tree().physics_frame
	assert_bool(sk.powder_window_active(Engine.get_physics_frames())).is_true()
	assert_bool(sk.cast(Engine.get_physics_frames())).is_true()   # 窗内齐射
	assert_array(_volley_copies(cs)).has_size(6)
	assert_int(_volley_copies(cs)[0].damage).is_equal(4)   # 6×0.6=3.6→round 4（无 ×2）
	assert_float(p.powder_dmg_mult).is_equal_approx(1.0, 0.001)   # 记账未动
	rig._next_fire_frame = 0
	assert_bool(rig.try_fire(Vector2.RIGHT, Engine.get_physics_frames())).is_true()
	assert_int(_last_shot(cs).damage).is_equal(12)     # 下一发常规枪击仍是首发 ×2


# ================================================================ 齐射（铳主动）

func test_volley_fires_6_deterministic_fan_copies() -> void:
	var p := _player()
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	var rig := _rig(p)
	rig.combat = cs
	p.combat = cs
	rig.equip("zuolunzhengwu")
	var sk := _gunslinger(p)
	p.facing = Vector2.RIGHT
	assert_bool(sk.cast(100)).is_true()
	var copies := _volley_copies(cs)
	assert_array(copies).has_size(6)                  # 附录 L §3：扇形 6 发
	# 确定性扇面 30°：±15/±9/±3（无 jitter；偶数发不含正中向，武器散弹展开同构）。
	var expected := [-15.0, -9.0, -3.0, 3.0, 9.0, 15.0]
	var angles: Array = []
	for proj in copies:
		angles.append(rad_to_deg(proj.vel.angle()))
	angles.sort()
	for i in expected.size():
		assert_float(angles[i]).is_equal_approx(expected[i], 0.0001)
	for proj in copies:
		assert_int(proj.damage).is_equal(4)           # 6（单发终伤）×0.6 → round 4
		assert_int(proj.pierce_left).is_equal(0)      # 基础无穿透
		assert_str(proj.source_type).is_equal("skill")
		assert_str(proj.source_id).is_equal("gunslinger_volley")
	assert_int(p.energy).is_equal(85)                 # 15 蓝（heroes 行 skill_energy）
	assert_int(sk.cooldown_remaining(101)).is_equal(659)

func test_volley_upgraded_8_shots_and_pierce_plus_one() -> void:
	var p := _player()
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	var rig := _rig(p)
	rig.combat = cs
	p.combat = cs
	rig.equip("zuolunzhengwu")
	var sk := _gunslinger(p, {"upgraded": true})      # 强化行「齐射 8 发且穿透 +1」
	p.facing = Vector2.RIGHT
	assert_bool(sk.cast(100)).is_true()
	var copies := _volley_copies(cs)
	assert_array(copies).has_size(8)
	for proj in copies:
		assert_int(proj.pierce_left).is_equal(1)      # 行值 0 + 1

func test_volley_pipeline_two_center_shots_hit_at_range() -> void:
	# ±3° 中心双发在 150px 处落点偏移 7.4px ≤ 9（体 6+弹 3）命中；±9°/±15° 偏移超阈不中。
	var p := _player()
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	cs.register_body(p, Projectile.Faction.PLAYER)
	p.combat = cs
	p.position = Vector2.ZERO
	p.facing = Vector2.RIGHT
	var target := _enemy(root, cs, Vector2(150, 0), 100)
	var flank := _enemy(root, cs, Vector2(-400, 0), 100)   # 扇面外对照
	var rig := _rig(p)
	rig.combat = cs
	rig.equip("zuolunzhengwu")
	var sk := _gunslinger(p)
	assert_bool(sk.cast(Engine.get_physics_frames())).is_true()
	for _i in 40:
		await get_tree().physics_frame
	assert_int(target.hp).is_equal(92)                # 2 发 × 4（复制弹 ×0.6）
	assert_int(flank.hp).is_equal(100)

func test_volley_upgraded_pierce_pipeline_hits_second_enemy() -> void:
	# 穿透 +1 管线：中心双发穿过首敌继续命中次敌；基础版（无穿透）次敌不受波及。
	var p := _player()
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	cs.register_body(p, Projectile.Faction.PLAYER)
	p.combat = cs
	p.position = Vector2.ZERO
	p.facing = Vector2.RIGHT
	var first := _enemy(root, cs, Vector2(150, 0), 100)
	var second := _enemy(root, cs, Vector2(165, 0), 100)
	var rig := _rig(p)
	rig.combat = cs
	rig.equip("zuolunzhengwu")
	var sk := _gunslinger(p, {"upgraded": true})
	assert_bool(sk.cast(Engine.get_physics_frames())).is_true()
	for _i in 45:
		await get_tree().physics_frame
	assert_int(first.hp).is_equal(92)
	assert_int(second.hp).is_equal(92)                # 穿透后同弹继续命中

func test_volley_base_no_pierce_second_enemy_untouched() -> void:
	var p := _player()
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	cs.register_body(p, Projectile.Faction.PLAYER)
	p.combat = cs
	p.position = Vector2.ZERO
	p.facing = Vector2.RIGHT
	var first := _enemy(root, cs, Vector2(150, 0), 100)
	var second := _enemy(root, cs, Vector2(165, 0), 100)
	var rig := _rig(p)
	rig.combat = cs
	rig.equip("zuolunzhengwu")
	var sk := _gunslinger(p)
	assert_bool(sk.cast(Engine.get_physics_frames())).is_true()
	for _i in 45:
		await get_tree().physics_frame
	assert_int(first.hp).is_equal(92)
	assert_int(second.hp).is_equal(100)               # 无穿透：次敌不受波及

func test_volley_melee_or_empty_current_passes_gate_noop() -> void:
	# 手刀/近战态无复制源：框架过门（CD/蓝不退——hunter 空目标先例），零弹。
	var p := _player()
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	var rig := _rig(p)
	rig.combat = cs
	p.combat = cs
	var sk := _gunslinger(p)
	assert_bool(sk.cast(100)).is_true()               # 空槽（手刀态）
	assert_array(_volley_copies(cs)).is_empty()
	assert_int(p.energy).is_equal(85)                 # 框架过门已扣蓝
	rig.equip("duyaduanren")                          # 近战武器当前槽
	assert_bool(sk.cast(100 + 660)).is_true()
	assert_array(_volley_copies(cs)).is_empty()

func test_gunslinger_data_row_numbers_flow_through_setup() -> void:
	# heroes.json：gunslinger 660t/15 蓝（数值照抄不调参）。
	var p := _player()
	var sk := _gunslinger(p, {"cooldown_ticks": int(GameDB.get_hero("gunslinger")["skill_cd"]),
		"energy_cost": int(GameDB.get_hero("gunslinger")["skill_energy"])})
	assert_int(sk.cooldown_ticks).is_equal(660)
	assert_int(sk.energy_cost).is_equal(15)

func test_gunslinger_null_player_placeholder_smoke_unchanged() -> void:
	var sk: GunslingerVolley = auto_free(GunslingerVolley.new())
	sk.setup(null, {"id": "gunslinger", "cooldown_ticks": 660, "energy_cost": 15})
	assert_bool(sk.cast(0)).is_true()


# ================================================================ 嗜血（牙被动）

func test_bloodthirst_melee_kill_heals_1_max_2_per_room() -> void:
	var p := _player()
	var sk := _lycan(p)
	p.hp = 3
	sk.on_melee_kill_report(100)
	assert_int(p.hp).is_equal(4)                      # 近战击杀回 1 HP
	assert_int(sk.bloodthirst_heals_left()).is_equal(1)
	sk.on_melee_kill_report(110)
	assert_int(p.hp).is_equal(5)
	assert_int(sk.bloodthirst_heals_left()).is_equal(0)
	sk.on_melee_kill_report(120)
	assert_int(p.hp).is_equal(5)                      # 每房 ≤2：第 3 击不回
	assert_int(sk.bloodthirst_heals_left()).is_equal(0)

func test_bloodthirst_room_clear_resets_quota() -> void:
	var p := _player()
	var sk := _lycan(p)
	p.hp = 2
	sk.on_melee_kill_report(100)
	sk.on_melee_kill_report(110)
	assert_int(sk.bloodthirst_heals_left()).is_equal(0)
	EventBus.room_cleared.emit("room_a")              # 房清：配额重置（「每房」口径）
	assert_int(sk.bloodthirst_heals_left()).is_equal(2)
	p.hp = 2
	sk.on_melee_kill_report(200)
	assert_int(p.hp).is_equal(3)                      # 新房可再回

func test_bloodthirst_calamity_blocked_does_not_consume_quota() -> void:
	# 治疗单一收口：灾厄禁疗 heal() 失效且不消耗次数（berserk 击杀返还先例）。
	var p := _player()
	var sk := _lycan(p)
	p.hp = 3
	p.set_meta(Player.CALAMITY_HEAL_DISABLED_META, 1)
	sk.on_melee_kill_report(100)
	assert_int(p.hp).is_equal(3)
	assert_int(sk.bloodthirst_heals_left()).is_equal(2)

func test_bloodthirst_forwarded_via_player_melee_kill_seam() -> void:
	# m4-c2 掠影同缝管线：passive_id=bloodthirst → player.on_melee_kill 转发技能节点。
	var p := _player()
	var sk := _lycan(p)
	p.hp = 3
	p.on_melee_kill(100)                              # melee.gd 上报路径（生产单一入口）
	assert_int(p.hp).is_equal(4)
	p.passive_id = "shadow_reap"                      # 掠影路径回归：不误触发嗜血
	p.hp = 3
	p.on_melee_kill(110)
	assert_int(p.hp).is_equal(3)
	p.passive_id = "defiance"                         # 非狼人零漂移
	p.on_melee_kill(120)
	assert_int(p.hp).is_equal(3)

func test_bloodthirst_no_skill_node_noop() -> void:
	# 未挂载 Skill 节点（脑层/装配前）：上报静默 no-op。
	var p := _player()
	p.passive_id = "bloodthirst"
	p.hp = 3
	p.on_melee_kill(100)
	assert_int(p.hp).is_equal(3)


# ================================================================ 变身（牙主动）

func test_shift_opens_wolf_windows_and_roll_override() -> void:
	var p := _player()
	_rig(p)
	var sk := _lycan(p)
	assert_bool(sk.cast(100)).is_true()               # 0 蓝：energy 不动
	assert_int(p.energy).is_equal(100)
	assert_float(p.move_speed_boost_pct).is_equal_approx(0.20, 0.001)
	assert_int(p.move_speed_boost_until).is_equal(460)     # 6s
	assert_float(p.melee_dmg_bonus_pct).is_equal_approx(0.50, 0.001)
	assert_int(p.melee_dmg_bonus_until).is_equal(460)
	assert_float(p.roll_dist_override_px).is_equal_approx(80.0, 0.001)
	assert_int(p.ranged_lock_until).is_equal(460)
	assert_bool(sk.shift_active(459)).is_true()
	assert_bool(sk.shift_active(460)).is_false()

func test_shift_move_speed_and_melee_damage_effective() -> void:
	var p := _player()
	var rig := _rig(p)
	rig.equip("duyaduanren")                          # 近战当前槽（melee_face）
	var sk := _lycan(p)
	assert_bool(sk.cast(100)).is_true()
	assert_float(p.effective_move_speed(150)).is_equal_approx(96.0, 0.001)   # 80×1.2
	assert_int(p.scaled_damage(10, 150)).is_equal(15)  # 近战面 10×1.5
	rig.equip("zuolunzhengwu")                        # 填副槽后切到远程槽（ranged_face）
	rig.switch_slot(151)
	assert_int(p.scaled_damage(10, 152)).is_equal(10)  # 远程面不吃近战加成（且已被锁定）
	sk.tick(460)                                      # 到期
	assert_float(p.effective_move_speed(461)).is_equal_approx(80.0, 0.001)
	assert_int(p.scaled_damage(10, 461)).is_equal(10)

func test_shift_expiry_restores_roll_override() -> void:
	var p := _player()
	_rig(p)
	var sk := _lycan(p)
	assert_bool(sk.cast(100)).is_true()
	sk.tick(459)                                      # 窗内：不动账
	assert_float(p.roll_dist_override_px).is_equal_approx(80.0, 0.001)
	sk.tick(460)                                      # 到期收尾
	assert_float(p.roll_dist_override_px).is_equal_approx(-1.0, 0.001)
	assert_bool(sk.shift_active(460)).is_false()

func test_shift_roll_distance_80px_dash() -> void:
	# 翻滚 80px 突进：形态距离档覆写（速度同步放大、tick 数不变——start_roll 语义）。
	var p := _player()
	_rig(p)
	var sk := _lycan(p)
	assert_bool(sk.cast(100)).is_true()
	p.start_roll(Vector2.RIGHT, 150)
	assert_float(p._roll_vel.length()).is_equal_approx(80.0 * 60.0 / 13.0, 0.01)
	p._roll_left = 0                                  # 结束翻滚（直驱状态机）
	p._roll_cd_until = -999
	sk.tick(460)                                      # 摘覆写
	p.start_roll(Vector2.RIGHT, 500)
	assert_float(p._roll_vel.length()).is_equal_approx(56.0 * 60.0 / 13.0, 0.01)  # 基线恢复

func test_shift_ranged_lock_rejects_fire_at_entry() -> void:
	# 远程锁定：开火入口读点拒发——不耗蓝、不进冷却；窗闭（严格 <）恢复开火。
	var p := _player()
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	var rig := _rig(p)
	rig.combat = cs
	rig.equip("zuolunzhengwu")
	var sk := _lycan(p)
	assert_bool(sk.cast(100)).is_true()
	assert_bool(rig.try_fire(Vector2.RIGHT, 200)).is_false()   # 锁定窗内拒发
	assert_int(p.energy).is_equal(100)                # 不耗蓝
	assert_int(cs.active_count()).is_equal(0)         # 不进冷却不发声（拒发即 no-op）
	sk.tick(460)                                      # 到期收尾
	assert_bool(rig.try_fire(Vector2.RIGHT, 460)).is_true()
	assert_int(cs.active_count()).is_equal(1)         # 恢复开火
	assert_int(p.energy).is_equal(99)

func test_shift_upgraded_10s_and_end_heal() -> void:
	var p := _player()
	_rig(p)
	var sk := _lycan(p, {"upgraded": true})           # 强化行「持续 10s 且结束回 1 HP」
	assert_bool(sk.cast(100)).is_true()
	assert_int(p.move_speed_boost_until).is_equal(700)
	assert_bool(sk.shift_active(699)).is_true()
	p.hp = 3
	sk.tick(700)                                      # 结束回 1 HP
	assert_int(p.hp).is_equal(4)
	assert_float(p.roll_dist_override_px).is_equal_approx(-1.0, 0.001)

func test_shift_base_no_end_heal() -> void:
	var p := _player()
	_rig(p)
	var sk := _lycan(p)
	assert_bool(sk.cast(100)).is_true()
	p.hp = 3
	sk.tick(460)
	assert_int(p.hp).is_equal(3)                      # 基础版无结束治疗

func test_shift_upgraded_end_heal_calamity_blocked() -> void:
	var p := _player()
	_rig(p)
	var sk := _lycan(p, {"upgraded": true})
	assert_bool(sk.cast(100)).is_true()
	p.hp = 3
	p.set_meta(Player.CALAMITY_HEAL_DISABLED_META, 1)
	sk.tick(700)
	assert_int(p.hp).is_equal(3)                      # 灾厄禁疗：结束治疗失效

func test_lycan_data_row_numbers_flow_through_setup() -> void:
	# heroes.json：lycan 840t/0 蓝（数值照抄不调参）。
	var p := _player()
	var sk := _lycan(p, {"cooldown_ticks": int(GameDB.get_hero("lycan")["skill_cd"]),
		"energy_cost": int(GameDB.get_hero("lycan")["skill_energy"])})
	assert_int(sk.cooldown_ticks).is_equal(840)
	assert_int(sk.energy_cost).is_equal(0)

func test_lycan_null_player_placeholder_smoke_unchanged() -> void:
	var sk: LycanShift = auto_free(LycanShift.new())
	sk.setup(null, {"id": "lycan", "cooldown_ticks": 840, "energy_cost": 0})
	assert_bool(sk.cast(0)).is_true()


# ================================================================ 蓄能（晷被动）

func test_charge_up_enters_after_1s_same_direction() -> void:
	var p := _player()
	_rig(p)
	var sk := _staranchor(p)
	p.facing = Vector2.RIGHT
	for i in 59:
		sk.tick(i)                                    # 59 拍同向：未满 1s
	assert_bool(sk.charge_active()).is_false()
	assert_int(sk.charge_acc()).is_equal(59)
	sk.tick(59)                                       # 第 60 拍同向：进入蓄能
	assert_bool(sk.charge_active()).is_true()
	assert_float(p.skill_dmg_bonus_pct).is_equal_approx(0.30, 0.001)
	assert_int(p.skill_dmg_bonus_until).is_equal(60)  # frame+1 滚动窗
	assert_int(p.scaled_damage(10, 59)).is_equal(13)  # ×1.3

func test_charge_up_window_stops_after_tick_stops() -> void:
	var p := _player()
	_rig(p)
	var sk := _staranchor(p)
	p.facing = Vector2.RIGHT
	for i in 60:
		sk.tick(i)
	assert_int(p.scaled_damage(10, 59)).is_equal(13)
	assert_int(p.scaled_damage(10, 61)).is_equal(10)  # 停写 1 拍后自然过期（无残留）

func test_charge_up_turn_within_threshold_keeps_chain() -> void:
	# 阈内微调（10°/恰 15°）不算转向：锚点不变累计继续。
	var p := _player()
	_rig(p)
	var sk := _staranchor(p)
	p.facing = Vector2.RIGHT
	for i in 30:
		sk.tick(i)
	p.facing = Vector2.RIGHT.rotated(deg_to_rad(10.0))
	sk.tick(30)
	assert_int(sk.charge_acc()).is_equal(31)
	p.facing = Vector2.RIGHT.rotated(deg_to_rad(15.0))  # 恰阈值：不重置（≤ 阈口径）
	sk.tick(31)
	assert_int(sk.charge_acc()).is_equal(32)
	for i in range(32, 60):
		sk.tick(i)
	assert_bool(sk.charge_active()).is_true()          # 共 60 拍同向（跨两次阈内调整）

func test_charge_up_turn_beyond_threshold_resets() -> void:
	var p := _player()
	_rig(p)
	var sk := _staranchor(p)
	p.facing = Vector2.RIGHT
	for i in 59:
		sk.tick(i)
	assert_bool(sk.charge_active()).is_false()
	p.facing = Vector2.RIGHT.rotated(deg_to_rad(20.0))  # 超阈转向：重置
	sk.tick(59)
	assert_int(sk.charge_acc()).is_equal(1)             # 锚改写 + 重计（本拍即第 1 拍）
	for i in range(60, 119):
		sk.tick(i)
	assert_bool(sk.charge_active()).is_true()           # 新方向满 60 拍再进入
	assert_float(p.skill_dmg_bonus_pct).is_equal_approx(0.30, 0.001)

func test_charge_up_does_not_clobber_stronger_window() -> void:
	# 更强窗（如破釜 0.40）存活不自我降档；窗闭后恢复续写（渐强先例）。
	var p := _player()
	_rig(p)
	var sk := _staranchor(p)
	p.facing = Vector2.RIGHT
	for i in 60:
		sk.tick(i)
	assert_bool(sk.charge_active()).is_true()
	p.skill_dmg_bonus_pct = 0.40
	p.skill_dmg_bonus_until = 9999
	sk.tick(200)
	assert_float(p.skill_dmg_bonus_pct).is_equal_approx(0.40, 0.001)
	p.skill_dmg_bonus_until = 199                       # 窗闭
	sk.tick(200)
	assert_float(p.skill_dmg_bonus_pct).is_equal_approx(0.30, 0.001)
	assert_int(p.skill_dmg_bonus_until).is_equal(201)


# ================================================================ 星陨（晷主动）

func test_starfall_chain_timing_warning_then_impact() -> void:
	# 引导 48t → 预警 30t → 落点结算：链长 78t，前 77 拍不掉血（§7.5 预警拍独立）。
	var p := _player()
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	cs.register_body(p, Projectile.Faction.PLAYER)
	p.combat = cs
	p.position = Vector2.ZERO
	p.facing = Vector2.RIGHT
	var target := _enemy(root, cs, Vector2(200, 0), 100)
	var sk := _staranchor(p)
	assert_bool(sk.cast(1000)).is_true()
	assert_int(p.energy).is_equal(75)                   # 25 蓝（heroes 行 skill_energy）
	assert_bool(sk.starfall_pending()).is_true()
	sk.tick(1047)                                       # 引导期内：无预警圈无结算
	assert_bool(sk.starfall_pending()).is_true()
	assert_int(target.hp).is_equal(100)
	sk.tick(1077)                                       # 预警期满前 1 拍：仍未结算
	assert_int(target.hp).is_equal(100)
	sk.tick(1078)                                       # 落点拍：40 伤
	assert_int(target.hp).is_equal(60)
	assert_bool(sk.starfall_pending()).is_false()

func test_starfall_lands_at_crosshair_range_radius_90() -> void:
	# 落点 = 施放拍 pos + facing × 200px；90px AoE（+体半径松弛）边界内外分野。
	var p := _player()
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	cs.register_body(p, Projectile.Faction.PLAYER)
	p.combat = cs
	p.position = Vector2.ZERO
	p.facing = Vector2.RIGHT
	var inside := _enemy(root, cs, Vector2(200, 0), 100)   # 落点正中
	var edge := _enemy(root, cs, Vector2(120, 0), 100)     # 距落点 80px：90px 内
	var outside := _enemy(root, cs, Vector2(100, 0), 100)  # 距落点 100px：90px 外
	var sk := _staranchor(p)
	assert_bool(sk.cast(1000)).is_true()
	sk.tick(1078)
	assert_int(inside.hp).is_equal(60)                  # 40 伤
	assert_int(edge.hp).is_equal(60)
	assert_int(outside.hp).is_equal(100)

func test_starfall_upgraded_leaves_ember_ground_with_shock_buildup() -> void:
	# 强化行「星陨留 2s 星火地面（电积累）」：落点后每 0.5s 1 伤 + SHOCK 积累
	# （毒池同构——2 层触发感电激活态，第二次共鸣挂点）。
	var p := _player()
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	cs.register_body(p, Projectile.Faction.PLAYER)
	p.combat = cs
	p.position = Vector2.ZERO
	p.facing = Vector2.RIGHT
	var target := _enemy(root, cs, Vector2(200, 0), 100)
	var sk := _staranchor(p, {"upgraded": true})
	assert_bool(sk.cast(1000)).is_true()
	sk.tick(1078)                                       # 落点：40 伤 + 铺星火
	assert_int(target.hp).is_equal(60)
	assert_bool(sk.ember_active(1088)).is_true()
	sk.tick(1108)                                       # 星火 tick 1（落点+0.5s）：1 伤 + SHOCK 1 层
	assert_int(target.hp).is_equal(59)
	assert_bool(target.status.active.has(Elements.Id.SHOCK)).is_false()   # 未达阈值
	sk.tick(1138)                                       # tick 2：1 伤 + SHOCK 触发
	assert_int(target.hp).is_equal(58)
	assert_bool(target.status.active.has(Elements.Id.SHOCK)).is_true()
	sk.tick(1168)                                       # tick 3
	assert_int(target.hp).is_equal(57)
	sk.tick(1198)                                       # tick 4（末拍含，2s 满）
	assert_int(target.hp).is_equal(56)
	assert_bool(sk.ember_active(1199)).is_false()       # 2s 到期自净
	sk.tick(1228)                                       # 地面外拍：不再掉血
	assert_int(target.hp).is_equal(56)

func test_starfall_ember_only_hits_ground_radius() -> void:
	# 星火地面半径同星陨 90px：地面外敌不吃积累。
	var p := _player()
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	cs.register_body(p, Projectile.Faction.PLAYER)
	p.combat = cs
	p.position = Vector2.ZERO
	p.facing = Vector2.RIGHT
	var near := _enemy(root, cs, Vector2(200, 0), 100)
	var far := _enemy(root, cs, Vector2(60, 0), 100)    # 距落点 140px：地面外
	var sk := _staranchor(p, {"upgraded": true})
	assert_bool(sk.cast(1000)).is_true()
	sk.tick(1078)
	sk.tick(1108)
	assert_int(near.hp).is_equal(59)
	assert_int(far.hp).is_equal(100)

func test_starfall_base_no_ember_ground() -> void:
	var p := _player()
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	cs.register_body(p, Projectile.Faction.PLAYER)
	p.combat = cs
	p.position = Vector2.ZERO
	p.facing = Vector2.RIGHT
	var target := _enemy(root, cs, Vector2(200, 0), 100)
	var sk := _staranchor(p)
	assert_bool(sk.cast(1000)).is_true()
	sk.tick(1078)
	sk.tick(1088)
	assert_int(target.hp).is_equal(60)                  # 只有落点 40 伤，无星火
	assert_bool(sk.ember_active(1088)).is_false()

func test_starfall_charge_does_not_amplify_impact_damage() -> void:
	# 星陨 40 伤为规格定值（不走玩家伤害出口）：蓄能激活不放大星陨本体（头注披露）。
	var p := _player()
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	cs.register_body(p, Projectile.Faction.PLAYER)
	p.combat = cs
	p.position = Vector2.ZERO
	p.facing = Vector2.RIGHT
	var target := _enemy(root, cs, Vector2(200, 0), 100)
	var sk := _staranchor(p)
	for i in 60:                                        # 预先蓄能满
		sk.tick(i)
	assert_bool(sk.charge_active()).is_true()
	assert_bool(sk.cast(1000)).is_true()
	sk.tick(1078)
	assert_int(target.hp).is_equal(60)                  # 恒 40 伤

func test_staranchor_data_row_numbers_flow_through_setup() -> void:
	# heroes.json：staranchor 780t/25 蓝（数值照抄不调参）。
	var p := _player()
	var sk := _staranchor(p, {"cooldown_ticks": int(GameDB.get_hero("staranchor")["skill_cd"]),
		"energy_cost": int(GameDB.get_hero("staranchor")["skill_energy"])})
	assert_int(sk.cooldown_ticks).is_equal(780)
	assert_int(sk.energy_cost).is_equal(25)

func test_staranchor_null_player_placeholder_smoke_unchanged() -> void:
	var sk: StaranchorStarfall = auto_free(StaranchorStarfall.new())
	sk.setup(null, {"id": "staranchor", "cooldown_ticks": 780, "energy_cost": 25})
	assert_bool(sk.cast(0)).is_true()
