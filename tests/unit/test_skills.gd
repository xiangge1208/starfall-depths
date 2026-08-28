class_name TestSkills
extends GdUnitTestSuite
## M1 t2：技能框架 + 骑士「狂潮」双持 + 被动「坚守」+ 暴击事件（GDD §6）。
## M1 t5：游侠「影袭」瞬步/无敌窗/必暴/弹速 + 被动「鹰眼」返蓝。

const PLAYER_SCENE := preload("res://core/player/player.tscn")

class RigProbe extends WeaponRig:
	var spawned: Array = []
	func _spawn(cfg: Dictionary) -> void:
		spawned.append(cfg)

class DummyBody extends Node2D:
	var hits: Array = []
	func take_hit(ctx: Dictionary) -> void:
		hits.append(ctx)
	func combat_radius() -> float:
		return 6.0

# ---- 装配 ----

# 注：auto_free 返回 Variant，:= 无法推断类型（同 test_weapon_rig.gd 既定决议），需显式类型标注。
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

func _rampage(p: Player, data: Dictionary = {}) -> VanguardRampage:
	var sk := VanguardRampage.new()
	sk.setup(p, data)
	p.add_child(sk)
	return sk

## 入树假敌（进 "enemies" 组，坚守 AoE 按 M0 同款分组寻敌）
func _enemy(root: Node2D, at: Vector2) -> EnemyBase:
	var e := EnemyBase.new()
	e._test_init({"id": "defiance_dummy", "hp": 10, "radius": 6.0})
	e.brain_pos = at
	root.add_child(e)
	e.add_to_group("enemies")
	return e

# ---- 技能框架契约 ----

func test_cast_grants_dual_wield_for_480_ticks() -> void:
	var p := _player()
	_rig(p)
	var sk := _rampage(p)
	assert_bool(sk.cast(100)).is_true()
	assert_int(p.weapon_rig.dual_wield_until).is_equal(100 + 480)   # 8s = 480t（GDD §6）

func test_can_cast_gated_by_energy_and_cooldown() -> void:
	var p := _player()
	var sk := _rampage(p, {"energy_cost": 30})
	p.energy = 29
	assert_bool(sk.can_cast(100)).is_false()             # 耗蓝门
	p.energy = 100
	assert_bool(sk.can_cast(100)).is_true()
	assert_bool(sk.cast(100)).is_true()
	assert_int(p.energy).is_equal(70)                    # 施放扣蓝
	assert_bool(sk.can_cast(100 + 839)).is_false()       # CD 门（蓝回满也不放）
	p.add_energy(30)
	assert_bool(sk.can_cast(100 + 839)).is_false()
	assert_bool(sk.cast(100 + 839)).is_false()           # CD 期间 cast false
	assert_bool(sk.cast(100 + 840)).is_true()            # CD 结束恢复

func test_cooldown_remaining_bounds() -> void:
	var p := _player()
	var sk := _rampage(p)
	assert_int(sk.cooldown_remaining(500)).is_equal(0)   # 未施放
	assert_bool(sk.cast(500)).is_true()
	assert_int(sk.cooldown_remaining(500)).is_equal(840)
	assert_int(sk.cooldown_remaining(500 + 839)).is_equal(1)
	assert_int(sk.cooldown_remaining(500 + 840)).is_equal(0)

# ---- 狂潮：升级减伤（受伤 ×0.7 向下取整 min 1，字段由技能写在 player 上） ----

func test_upgraded_sets_damage_reduction_window() -> void:
	var p := _player()
	_rig(p)
	var sk := _rampage(p, {"upgraded": true})
	assert_bool(sk.cast(100)).is_true()
	assert_int(p.weapon_rig.dual_wield_until).is_equal(580)
	assert_int(p.rampage_active_until).is_equal(580)     # 字段由技能写在 player 上
	p.shield = 0
	p.take_hit_ctx({"amount": 10}, 300)                  # 窗内：10 → floor(7.0) = 7
	assert_int(p.hp).is_equal(8 - 7)

func test_damage_reduction_floors_at_one() -> void:
	var p := _player()
	p.rampage_active_until = 500
	p.shield = 0
	p.take_hit_ctx({"amount": 1}, 100)                   # floor(0.7)=0 → min 1
	assert_int(p.hp).is_equal(7)

func test_non_upgraded_has_no_reduction() -> void:
	var q := _player()
	_rig(q)
	var sk := _rampage(q)                                # 非 upgraded
	assert_bool(sk.cast(100)).is_true()
	assert_int(q.rampage_active_until).is_equal(-1)      # 非升级不写减伤窗
	q.shield = 0
	q.take_hit_ctx({"amount": 10}, 100)
	assert_int(q.hp).is_equal(0)                         # 8 - 10 → 0，无减伤

# ---- 双持齐射（RigProbe 覆写 _spawn 捕获） ----

func _inject_cost_gun() -> void:
	GameDB.weapons["testgun_cost5"] = {"id": "testgun_cost5", "name": "tc5", "category": "pistol",
		"rarity": "common", "damage": 3, "rate": 10.0, "energy_cost": 5, "bullet_speed": 300,
		"spread_deg": 0.0, "projectiles": 1, "pierce": 0, "bounce": 0, "element": "none",
		"is_melee": false, "range": 0, "arc_deg": 0.0}

func test_dual_wield_spawns_both_slots_and_waives_energy() -> void:
	_inject_cost_gun()
	var p := _player()
	p.energy = 3                                         # 主手蓝耗 5：常态必被空蓝拦截
	var r := _rig(p)
	r.equip("testgun_cost5")                             # 槽 0
	r.equip("maodingqiang")                              # 槽 1
	r.dual_wield_until = 100
	assert_bool(r.try_fire(Vector2.RIGHT, 50)).is_true()
	assert_int(p.energy).is_equal(3)                     # 双武器免蓝
	assert_int(r.spawned.size()).is_equal(2)             # 主 + 副各一次 _spawn
	var main: Dictionary = r.spawned[0]
	var alt: Dictionary = r.spawned[1]
	assert_float(main["pos"].x).is_equal_approx(8.0, 0.001)    # 主手右舷枪口（_muzzle=(8,0)）
	assert_float(alt["pos"].x).is_equal_approx(-8.0, 0.001)    # 副手镜像枪口
	assert_int(alt["damage"]).is_equal(2)                      # 副手按自身武器数值（铆钉枪 2 伤）

func test_dual_wield_cost_waive_only_during_window() -> void:
	_inject_cost_gun()
	var p := _player()
	p.energy = 3
	var r := _rig(p)
	r.equip("testgun_cost5")
	assert_bool(r.try_fire(Vector2.RIGHT, 50)).is_false()      # 窗外：5 > 3 → 空蓝禁射
	r.dual_wield_until = 100
	assert_bool(r.try_fire(Vector2.RIGHT, 50)).is_true()       # 窗内免蓝
	assert_int(p.energy).is_equal(3)

func test_dual_wield_skips_empty_or_melee_alt() -> void:
	_inject_cost_gun()
	var p := _player()
	p.energy = 3
	var r := _rig(p)
	r.equip("testgun_cost5")                             # 副手空
	r.dual_wield_until = 100
	assert_bool(r.try_fire(Vector2.RIGHT, 50)).is_true()
	assert_int(r.spawned.size()).is_equal(1)             # 副手空 → 跳过
	assert_int(p.energy).is_equal(3)                     # 主手仍免蓝
	var q := _player()
	q.energy = 3
	var r2 := _rig(q)
	r2.equip("testgun_cost5")
	r2.equip("tiejian")                                  # 副手近战 → 跳过
	r2.dual_wield_until = 100
	assert_bool(r2.try_fire(Vector2.RIGHT, 50)).is_true()
	assert_int(r2.spawned.size()).is_equal(1)

# ---- 盾破事件 + 被动「坚守」 ----

func test_shield_broken_emitted_only_on_break() -> void:
	var p := _player()
	var events: Array = []
	var cb := func() -> void: events.append(1)
	EventBus.shield_broken.connect(cb)
	p.take_hit_ctx({"amount": 2}, 100)                   # 盾 4→2：未破
	p.take_hit_ctx({"amount": 2}, 200)                   # 盾 2→0：破（跳过无敌帧）
	EventBus.shield_broken.disconnect(cb)
	assert_int(p.shield).is_equal(0)
	assert_int(events.size()).is_equal(1)                # 恰在破碎拍广播一次

func test_defiance_blast_hits_stuns_knocks_nearby_only() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var p: Player = auto_free(Player.new())
	p._test_init()
	p.has_defiance = true
	p.position = Vector2(500, 100)
	root.add_child(p)                                    # 入树 → _ready 连接 shield_broken
	var near := _enemy(root, Vector2(540, 100))          # 40px：内
	var edge := _enemy(root, Vector2(560, 100))          # 60px：边界内（含）
	var far := _enemy(root, Vector2(600, 100))           # 100px：外
	p.take_hit_ctx({"amount": 4}, 100)                   # 盾 4→0 → 坚守触发
	assert_int(near.hp).is_equal(9)                      # 1 伤
	assert_float(near.brain_pos.x).is_equal_approx(548.0, 0.001)   # 击退 8px 远离玩家
	assert_bool(near.stun_until > 0).is_true()
	var st: int = near.stun_until
	near.state = EnemyBase.State.ALERT                   # 眩晕内 brain 空转（不推进状态机）
	near._seen_frame = 0
	near.brain_tick(st - 1)
	assert_int(near.state).is_equal(EnemyBase.State.ALERT)
	near.brain_tick(st)                                  # 眩晕结束即恢复行动
	assert_int(near.state).is_equal(EnemyBase.State.ENGAGE)
	assert_int(edge.hp).is_equal(9)                      # 60px 边界含
	assert_int(far.hp).is_equal(10)                      # 60px 外无效
	assert_int(far.stun_until).is_equal(-1)
	assert_float(far.brain_pos.x).is_equal_approx(600.0, 0.001)

func test_defiance_off_no_blast_but_event_still_emits() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var p: Player = auto_free(Player.new())
	p._test_init()                                       # has_defiance 默认 false（角色数据注入，t11）
	p.position = Vector2(500, 100)
	root.add_child(p)
	var near := _enemy(root, Vector2(540, 100))
	var events: Array = []
	var cb := func() -> void: events.append(1)
	EventBus.shield_broken.connect(cb)
	p.take_hit_ctx({"amount": 4}, 100)
	EventBus.shield_broken.disconnect(cb)
	assert_int(events.size()).is_equal(1)                # 盾破事件无条件广播
	assert_int(near.hp).is_equal(10)                     # 无坚守 → 不炸
	assert_int(near.stun_until).is_equal(-1)

# ---- 暴击事件（玩家弹暴击落地） ----

func _make_cs(root: Node2D, crit_chance: float) -> CombatSystem:
	var rng := RngSvc.stream(0, "combat")
	var cs := CombatSystem.new(root, rng)
	root.add_child(cs)
	cs.crit_chance = crit_chance
	return cs

func _shoot_player_bullet(cs: CombatSystem, body: DummyBody, root: Node2D, events: Array, cb: Callable) -> void:
	root.add_child(body)
	body.position = Vector2(200, 0)
	cs.register_body(body, Projectile.Faction.ENEMY)
	EventBus.player_crit_landed.connect(cb)
	cs.spawn_projectile({"pos": Vector2(100, 0), "vel": Vector2.RIGHT * 600, "damage": 4,
		"faction": Projectile.Faction.PLAYER, "element": 0, "pierce": 0, "bounce": 0,
		"life_seconds": 1.0, "radius": 3.0})
	for _i in 30:
		await get_tree().physics_frame
	EventBus.player_crit_landed.disconnect(cb)

func test_player_bullet_crit_emits_player_crit_landed() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _make_cs(root, 1.0)                        # 必暴
	var body: DummyBody = auto_free(DummyBody.new())
	var events: Array = []
	var cb := func(amount: int, at: Vector2) -> void: events.append([amount, at])
	await _shoot_player_bullet(cs, body, root, events, cb)
	assert_int(body.hits.size()).is_equal(1)
	assert_int(body.hits[0]["amount"]).is_equal(8)       # 暴击 2×
	assert_bool(body.hits[0]["is_crit"]).is_true()
	assert_int(events.size()).is_equal(1)                # 玩家阵营弹暴击 → 落地事件
	assert_int(events[0][0]).is_equal(8)

func test_player_bullet_no_crit_no_event() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _make_cs(root, 0.0)                        # 必不暴
	var body: DummyBody = auto_free(DummyBody.new())
	var events: Array = []
	var cb := func(amount: int, at: Vector2) -> void: events.append([amount, at])
	await _shoot_player_bullet(cs, body, root, events, cb)
	assert_int(body.hits.size()).is_equal(1)
	assert_int(body.hits[0]["amount"]).is_equal(4)
	assert_int(events.size()).is_equal(0)

# ---- 游侠「影袭」+ 被动「鹰眼」 ----

## 鹰眼掷签探针：本地 RandomNumberGenerator.randf() 为原生方法不可覆写，
## 仿 RigProbe 以子类覆写 _hawk_proc 注入 100%/0% 桩（实 rng 流由 hawk_rng 承载）。
class HawkProbe extends RangerShadowstep:
	var procs := true
	func _hawk_proc() -> bool:
		return procs

func _shadowstep(p: Player, data: Dictionary = {}) -> RangerShadowstep:
	var sk := RangerShadowstep.new()
	sk.setup(p, data)
	p.add_child(sk)
	return sk

func _hawk(p: Player, procs: bool) -> HawkProbe:
	var sk := HawkProbe.new()
	sk.procs = procs
	sk.setup(p, {})
	p.add_child(sk)
	return sk

func test_shadowstep_dashes_140px_along_facing() -> void:
	var p := _player()
	_rig(p)
	var sk := _shadowstep(p)
	p.facing = Vector2.RIGHT
	p.position = Vector2(100, 50)
	assert_bool(sk.cast(100)).is_true()
	assert_float(p.position.x).is_equal_approx(240.0, 0.001)   # 沿 facing 单帧 +140px
	assert_float(p.position.y).is_equal_approx(50.0, 0.001)
	p.facing = Vector2(0.0, -1.0)                              # 归一化方向（影袭瞬步沿 facing）
	assert_bool(sk.cast(100 + 540)).is_true()                  # CD 后再次施放
	assert_float(p.position.y).is_equal_approx(50.0 - 140.0, 0.001)

func test_shadowstep_iframes_15_ticks() -> void:
	var p := _player()
	_rig(p)
	var sk := _shadowstep(p)
	assert_bool(sk.cast(100)).is_true()
	assert_bool(p.is_invincible_at(100 + 14)).is_true()        # 15t 无敌窗（0.25s）
	assert_bool(p.is_invincible_at(100 + 15)).is_false()       # 窗外恢复可受击

func test_shadowstep_upgraded_iframes_36_ticks() -> void:
	var p := _player()
	_rig(p)
	var sk := _shadowstep(p, {"upgraded": true})
	assert_bool(sk.cast(100)).is_true()
	assert_bool(p.is_invincible_at(100 + 35)).is_true()        # 升级版 36t（0.6s）
	assert_bool(p.is_invincible_at(100 + 36)).is_false()

func test_apply_iframes_keeps_longest_window() -> void:
	var p := _player()
	p.apply_iframes(48, 100)                                   # 受伤窗至 148
	p.apply_iframes(15, 120)                                   # 影袭接缝：不缩短既有窗
	assert_bool(p.is_invincible_at(147)).is_true()
	assert_bool(p.is_invincible_at(148)).is_false()

func test_shadowstep_sets_boost_windows_240_ticks() -> void:
	var p := _player()
	var r := _rig(p)
	var cs := CombatSystem.new(auto_free(Node2D.new()), RngSvc.stream(0, "combat"))
	auto_free(cs)
	p.combat = cs                                           # 房间注入同款（room_combat.gd 接线）
	var sk := _shadowstep(p)
	assert_bool(sk.cast(100)).is_true()
	assert_int(r.crit_boost_until).is_equal(340)               # 必暴状态窗 4s（HUD/查询镜像）
	assert_int(r.speed_boost_until).is_equal(340)              # 弹速 ×1.2 窗 4s
	assert_int(cs.forced_crit_until).is_equal(340)             # 功能侧：命中结算必暴窗

func test_shadowstep_cooldown_540_zero_energy_cost() -> void:
	var p := _player()
	_rig(p)
	p.energy = 10
	var sk := _shadowstep(p)
	assert_bool(sk.cast(100)).is_true()
	assert_int(p.energy).is_equal(10)                          # 0 耗蓝
	assert_int(sk.cooldown_remaining(100)).is_equal(540)
	assert_bool(sk.cast(100 + 539)).is_false()                 # CD 门（9s）
	assert_bool(sk.cast(100 + 540)).is_true()

func test_speed_boost_multiplies_bullet_velocity_in_window() -> void:
	_inject_cost_gun()
	var p := _player()
	var r := _rig(p)
	r.equip("testgun_cost5")
	assert_bool(r.try_fire(Vector2.RIGHT, 50)).is_true()
	assert_float((r.spawned[0]["vel"] as Vector2).x).is_equal_approx(300.0, 0.001)   # 窗外原速
	r.speed_boost_until = 100
	assert_bool(r.try_fire(Vector2.RIGHT, 60)).is_true()       # rate 门后下一拍
	assert_float((r.spawned[1]["vel"] as Vector2).x).is_equal_approx(360.0, 0.001)   # 窗内 ×1.2

func test_forced_crit_overrides_hit_roll() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _make_cs(root, 0.0)                              # 场上掷签必不暴
	cs.forced_crit_until = 999999                              # 影袭必暴窗（覆盖物理帧口径）
	var body: DummyBody = auto_free(DummyBody.new())
	var events: Array = []
	var cb := func(amount: int, at: Vector2) -> void: events.append([amount, at])
	await _shoot_player_bullet(cs, body, root, events, cb)
	assert_int(body.hits[0]["amount"]).is_equal(8)             # 强制暴击 2×
	assert_bool(body.hits[0]["is_crit"]).is_true()
	assert_int(events.size()).is_equal(1)                      # player_crit_landed 照常广播（鹰眼源）

func test_forced_crit_expired_uses_field_chance() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _make_cs(root, 0.0)
	cs.forced_crit_until = 0                                   # 窗已过 → 回落 crit_chance 字段
	var body: DummyBody = auto_free(DummyBody.new())
	var events: Array = []
	var cb := func(amount: int, at: Vector2) -> void: events.append([amount, at])
	await _shoot_player_bullet(cs, body, root, events, cb)
	assert_int(body.hits[0]["amount"]).is_equal(4)             # 无暴击
	assert_bool(body.hits[0]["is_crit"]).is_false()
	assert_int(events.size()).is_equal(0)

func test_hawk_eye_returns_one_energy_per_crit_when_proc() -> void:
	var p := _player()
	p.energy = 50
	_hawk(p, true)                                             # 100% 桩
	EventBus.player_crit_landed.emit(8, Vector2.ZERO)
	EventBus.player_crit_landed.emit(8, Vector2.ZERO)          # 两次暴击 → 两次返蓝
	assert_int(p.energy).is_equal(52)                          # 每次 +1

func test_hawk_eye_no_return_when_proc_fails() -> void:
	var p := _player()
	p.energy = 50
	_hawk(p, false)                                            # 0% 桩
	EventBus.player_crit_landed.emit(8, Vector2.ZERO)
	assert_int(p.energy).is_equal(50)

func test_hawk_eye_proc_threshold_uses_half() -> void:
	var p := _player()
	var sk := _shadowstep(p)
	assert_bool(sk._hawk_should_return_energy(0.49)).is_true()
	assert_bool(sk._hawk_should_return_energy(0.5)).is_false() # < 0.5 才返蓝
	sk.hawk_rng = RngSvc.stream(0, "hawk")                     # 实装流注入（T11 装配同款派生）
	var expected: float = RngSvc.stream(0, "hawk").randf()     # 同派生流首掷（确定性 twin）
	assert_float(sk._next_hawk_roll()).is_equal(expected)      # 掷签经注入流

# ---- 场景挂载契约 ----

func test_player_scene_mounts_skill_node() -> void:
	var inst: Node = PLAYER_SCENE.instantiate()
	auto_free(inst)
	var skill: Node = inst.get_node_or_null("Skill")
	assert_object(skill).is_not_null()                   # 恰一个 Skill 子节点，脚本待角色数据注入
	if skill != null:
		var script: Script = skill.get_script()
		assert_str(script.resource_path).is_equal("res://core/player/skills/skill_base.gd")
