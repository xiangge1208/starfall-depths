class_name TestElementCombatChain
extends GdUnitTestSuite

const BASE_ROW := {"id": "element_dummy", "name": "元素木桩", "hp": 200, "radius": 6.0}

class ActionSpy extends EnemyBase:
	var actions := 0
	func _engage(_frame: int) -> void:
		actions += 1

class SourceSpy extends Node2D:
	var hit := {}
	func take_hit(ctx: Dictionary) -> void:
		hit = ctx
	func combat_radius() -> float:
		return 6.0

func _enemy(root: Node2D, cs: CombatSystem, pos: Vector2, row: Dictionary = BASE_ROW) -> EnemyBase:
	var e: EnemyBase = auto_free(EnemyBase.new())
	e.position = pos
	root.add_child(e)
	e.setup(row.duplicate(true))
	e.combat = cs
	cs.register_body(e, Projectile.Faction.ENEMY)
	return e

func _make_world() -> Dictionary:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	var cs := CombatSystem.new(root, rng)
	root.add_child(cs)
	return {"root": root, "combat": cs}

func _hit(e: EnemyBase, element: int, frame: int, amount := 10, extra := {}) -> void:
	var ctx := {
		"amount": amount, "is_crit": false, "element": element, "from": Vector2.ZERO,
		"frame": frame,
	}
	ctx.merge(extra, true)
	e.take_hit(ctx)

func _activate(e: EnemyBase, element: int, frame: int, amount := 10) -> void:
	for i in e.status.stacks_to_trigger:
		_hit(e, element, frame + i, amount)

func test_real_enemy_elite_and_boss_status_thresholds() -> void:
	var normal: EnemyBase = auto_free(EnemyBase.new())
	normal._test_init(BASE_ROW)
	assert_int(normal.status.stacks_to_trigger).is_equal(2)
	assert_bool(normal.status.is_boss).is_false()

	var elite: EnemyBase = auto_free(EnemyBase.new())
	elite._test_init(BASE_ROW.merged({"elite_affixes": ["swift"]}, true))
	assert_int(elite.status.stacks_to_trigger).is_equal(4)
	assert_bool(elite.status.is_boss).is_false()

	var boss: BossBase = auto_free(BossBase.new())
	boss._test_init(BASE_ROW.merged({"archetype": "boss", "phases": [1.0, 0.5]}, true))
	assert_int(boss.status.stacks_to_trigger).is_equal(4)
	assert_bool(boss.status.is_boss).is_true()

func test_fire_six_ticks_and_poison_five_ticks() -> void:
	var fire: StatusComponent = auto_free(StatusComponent.new())
	fire.setup(2, false)
	fire.apply_hit(Elements.Id.FIRE, 4, 0)
	fire.apply_hit(Elements.Id.FIRE, 4, 1)
	var burn := 0
	for f in range(2, 182):
		burn += fire.tick(f)
	assert_int(burn).is_equal(6)

	var poison: StatusComponent = auto_free(StatusComponent.new())
	poison.setup(2, false)
	poison.apply_hit(Elements.Id.POISON, 4, 0)
	poison.apply_hit(Elements.Id.POISON, 4, 1)
	var dot := 0
	for f in range(2, 302):
		dot += poison.tick(f)
	assert_int(dot).is_equal(5)

func test_ice_freezes_normal_but_boss_only_slows() -> void:
	var normal: StatusComponent = auto_free(StatusComponent.new())
	normal.setup(2, false)
	normal.apply_hit(Elements.Id.ICE, 1, 0)
	normal.apply_hit(Elements.Id.ICE, 1, 1)
	assert_bool(normal.is_frozen(60)).is_true()
	assert_bool(normal.is_frozen(61)).is_false()
	assert_float(normal.action_speed_multiplier(120)).is_equal(0.7)
	assert_float(normal.action_speed_multiplier(121)).is_equal(1.0)

	var boss: StatusComponent = auto_free(StatusComponent.new())
	boss.setup(4, true)
	for i in 4:
		boss.apply_hit(Elements.Id.ICE, 1, i)
	assert_bool(boss.is_frozen(10)).is_false()
	assert_float(boss.action_speed_multiplier(100)).is_equal(0.7)

func test_ice_slow_reduces_real_enemy_action_frequency() -> void:
	var e: ActionSpy = auto_free(ActionSpy.new())
	e._test_init(BASE_ROW)
	e.state = EnemyBase.State.ENGAGE
	_activate(e, Elements.Id.ICE, 0)
	for f in range(10, 110):
		e.brain_tick(f)
	# 前 51 拍仍在 1s 冻结窗，余下 49 拍按 70% 行动频率推进。
	assert_int(e.actions).is_between(34, 35)

func test_shock_stuns_self_and_jumps_nearest_enemy_for_eight() -> void:
	var world := _make_world()
	var root: Node2D = world["root"]
	var cs: CombatSystem = world["combat"]
	var trigger := _enemy(root, cs, Vector2.ZERO)
	var near := _enemy(root, cs, Vector2(50, 0))
	var far := _enemy(root, cs, Vector2(70, 0))
	_activate(trigger, Elements.Id.SHOCK, 100)
	assert_int(trigger.stun_until).is_equal(125)
	assert_int(near.hp).is_equal(192)
	assert_int(far.hp).is_equal(200)

func test_shatter_is_90px_and_one_point_five_last_hit() -> void:
	var world := _make_world()
	var root: Node2D = world["root"]
	var cs: CombatSystem = world["combat"]
	var trigger := _enemy(root, cs, Vector2.ZERO)
	var inside := _enemy(root, cs, Vector2(80, 0))
	var outside := _enemy(root, cs, Vector2(100, 0))
	_activate(trigger, Elements.Id.FIRE, 0, 10)
	_activate(trigger, Elements.Id.ICE, 10, 10)
	assert_int(inside.hp).is_equal(185)
	assert_int(outside.hp).is_equal(200)
	assert_int(trigger.hp).is_equal(160) # 四次直击，不吃自身淬爆 AoE

func test_blaze_cloud_survives_trigger_and_ticks_three_times_in_100px() -> void:
	var world := _make_world()
	var root: Node2D = world["root"]
	var cs: CombatSystem = world["combat"]
	var trigger := _enemy(root, cs, Vector2.ZERO)
	var inside := _enemy(root, cs, Vector2(90, 0))
	var outside := _enemy(root, cs, Vector2(120, 0))
	_activate(trigger, Elements.Id.FIRE, 0)
	_activate(trigger, Elements.Id.POISON, 10)
	trigger.die()
	cs.tick_environment(71)
	cs.tick_environment(131)
	cs.tick_environment(191)
	assert_int(inside.hp).is_equal(188)
	assert_int(outside.hp).is_equal(200)

func test_superconduct_amplifies_followup_and_expires() -> void:
	var e: EnemyBase = auto_free(EnemyBase.new())
	e._test_init(BASE_ROW)
	_activate(e, Elements.Id.ICE, 0, 10)
	_activate(e, Elements.Id.SHOCK, 10, 10)
	var after_trigger := e.hp
	_hit(e, Elements.Id.NONE, 20, 10)
	assert_int(e.hp).is_equal(after_trigger - 14)
	_hit(e, Elements.Id.NONE, 252, 10)
	assert_int(e.hp).is_equal(after_trigger - 24)

func test_boss_superconduct_bonus_is_twenty_percent() -> void:
	var boss: BossBase = auto_free(BossBase.new())
	boss._test_init(BASE_ROW.merged({"archetype": "boss"}, true))
	_activate(boss, Elements.Id.ICE, 0, 10)
	_activate(boss, Elements.Id.SHOCK, 10, 10)
	var after_trigger := boss.hp
	boss._take_hit_at({"amount": 10, "is_crit": false, "element": Elements.Id.NONE, "from": Vector2.ZERO}, 20)
	assert_int(boss.hp).is_equal(after_trigger - 12)

func test_electrolysis_stuns_self_and_at_most_three_neighbours() -> void:
	var world := _make_world()
	var root: Node2D = world["root"]
	var cs: CombatSystem = world["combat"]
	var trigger := _enemy(root, cs, Vector2.ZERO)
	var neighbours: Array[EnemyBase] = []
	for x in [20.0, 40.0, 60.0, 80.0]:
		neighbours.append(_enemy(root, cs, Vector2(x, 0)))
	var outside := _enemy(root, cs, Vector2(120, 0))
	_activate(trigger, Elements.Id.POISON, 100)
	_activate(trigger, Elements.Id.SHOCK, 110)
	assert_int(trigger.stun_until).is_equal(159)
	for i in 3:
		assert_int(neighbours[i].stun_until).is_equal(159)
	assert_int(neighbours[3].stun_until).is_equal(-1)
	assert_int(outside.stun_until).is_equal(-1)

func test_resonance_icd_is_unified_per_target() -> void:
	var s: StatusComponent = auto_free(StatusComponent.new())
	s.setup(2, false)
	s.apply_hit(Elements.Id.FIRE, 8, 0)
	s.apply_hit(Elements.Id.FIRE, 8, 1)
	s.apply_hit(Elements.Id.ICE, 8, 2)
	s.apply_hit(Elements.Id.ICE, 8, 3)
	assert_int(s.resonance_event["reaction"]).is_equal(Resonance.R.SHATTER)
	s.resonance_event = {}
	s.apply_hit(Elements.Id.POISON, 8, 10)
	s.apply_hit(Elements.Id.POISON, 8, 11)
	s.apply_hit(Elements.Id.SHOCK, 8, 12)
	s.apply_hit(Elements.Id.SHOCK, 8, 13)
	assert_dict(s.resonance_event).is_empty()

func test_status_rate_multiplier_changes_real_stack_progress() -> void:
	var e: EnemyBase = auto_free(EnemyBase.new())
	e._test_init(BASE_ROW)
	_hit(e, Elements.Id.FIRE, 0, 1, {"status_rate_mult": 1.25})
	assert_dict(e.status.active).is_empty()
	_hit(e, Elements.Id.FIRE, 1, 1, {"status_rate_mult": 1.25})
	assert_bool(e.status.active.has(Elements.Id.FIRE)).is_true()
	e.status.active.clear()
	_hit(e, Elements.Id.FIRE, 2, 1, {"status_rate_mult": 1.0})
	assert_dict(e.status.active).is_empty() # 首轮余 0.5 + 本轮 1.0 = 1.5，尚未达 2

func test_projectile_crit_forces_resonance_and_preserves_source_context() -> void:
	var world := _make_world()
	var root: Node2D = world["root"]
	var cs: CombatSystem = world["combat"]
	cs.set_physics_process(false)
	cs.crit_chance = 1.0
	var e := _enemy(root, cs, Vector2.ZERO)
	e.set_physics_process(false)
	# 预激活火状态，但把其配对命中伤害设为 0，避免夹具伤害干扰弹丸断言。
	e.status.apply_hit(Elements.Id.FIRE, 0, 0)
	e.status.apply_hit(Elements.Id.FIRE, 0, 1)
	cs.spawn_projectile({
		# Projectile.tick() 先移动一拍；由 -1px 向右飞确保推进后仍与目标重叠。
		"pos": Vector2(-1, 0), "vel": Vector2(60, 0), "damage": 4,
		"faction": Projectile.Faction.PLAYER, "element": Elements.Id.ICE,
		"pierce": 0, "bounce": 0, "life_seconds": 1.0, "radius": 40.0,
		"crit_detonate_pct": 1.0, "source_type": "projectile", "source_id": "weapon_x",
		"source_name": "测试枪", "attack_name": "测试射击",
	})
	cs._physics_process(1.0 / TimeConst.FPS)
	assert_int(e.hp).is_equal(192) # 4 点必暴（默认 x2）
	assert_int(e.status.resonance_icd_until).is_greater(Engine.get_physics_frames())
	assert_dict(e.status.active).is_empty()

func test_zero_crit_detonate_does_not_force_and_force_respects_icd() -> void:
	var e: EnemyBase = auto_free(EnemyBase.new())
	e._test_init(BASE_ROW)
	_activate(e, Elements.Id.FIRE, 0, 1)
	_hit(e, Elements.Id.ICE, 10, 2, {"force_resonance": false})
	assert_bool(e.status.active.has(Elements.Id.FIRE)).is_true()
	_hit(e, Elements.Id.ICE, 11, 2, {"force_resonance": true})
	assert_int(e.status.resonance_icd_until).is_equal(131)
	e.status.resonance_event = {}
	_activate(e, Elements.Id.POISON, 20, 1)
	_hit(e, Elements.Id.SHOCK, 30, 2, {"force_resonance": true})
	assert_dict(e.status.resonance_event).is_empty()

func test_combat_system_player_crit_multiplier_is_consumed() -> void:
	var world := _make_world()
	var root: Node2D = world["root"]
	var cs: CombatSystem = world["combat"]
	cs.set_physics_process(false)
	cs.crit_chance = 1.0
	cs.crit_multiplier = 2.5
	var e := _enemy(root, cs, Vector2.ZERO)
	e.set_physics_process(false)
	cs.spawn_projectile({
		"pos": Vector2.ZERO, "vel": Vector2.ZERO, "damage": 4,
		"faction": Projectile.Faction.PLAYER, "element": Elements.Id.NONE,
		"pierce": 0, "bounce": 0, "life_seconds": 1.0, "radius": 40.0,
	})
	cs._physics_process(1.0 / TimeConst.FPS)
	assert_int(e.hp).is_equal(190)

func test_combat_system_preserves_projectile_source_context() -> void:
	var world := _make_world()
	var root: Node2D = world["root"]
	var cs: CombatSystem = world["combat"]
	cs.set_physics_process(false)
	cs.crit_chance = 0.0
	var target: SourceSpy = auto_free(SourceSpy.new())
	root.add_child(target)
	cs.register_body(target, Projectile.Faction.ENEMY)
	cs.spawn_projectile({
		"pos": Vector2(-1, 0), "vel": Vector2(60, 0), "damage": 4,
		"faction": Projectile.Faction.PLAYER, "element": Elements.Id.NONE,
		"pierce": 0, "bounce": 0, "life_seconds": 1.0, "radius": 3.0,
		"source_type": "projectile", "source_id": "weapon_x",
		"source_name": "测试枪", "attack_name": "测试射击",
	})
	cs._physics_process(1.0 / TimeConst.FPS)
	assert_str(target.hit.get("source_type", "")).is_equal("projectile")
	assert_str(target.hit.get("source_id", "")).is_equal("weapon_x")
	assert_str(target.hit.get("source_name", "")).is_equal("测试枪")
	assert_str(target.hit.get("attack_name", "")).is_equal("测试射击")

func test_element_proc_strict_threshold_and_noop_rng_contract() -> void:
	assert_bool(ElementProc.succeeds(0.199999, 0.2)).is_true()
	assert_bool(ElementProc.succeeds(0.2, 0.2)).is_false()
	assert_bool(ElementProc.succeeds(0.149999, 0.15)).is_true()
	assert_bool(ElementProc.succeeds(0.15, 0.15)).is_false()
	var rng := RandomNumberGenerator.new(); rng.seed = 101
	var state_before := rng.state
	assert_int(ElementProc.roll_element(Elements.Id.NONE, 0.2, rng)).is_equal(Elements.Id.NONE)
	assert_int(ElementProc.roll_element(Elements.Id.FIRE, 0.0, rng)).is_equal(Elements.Id.NONE)
	assert_int(rng.state).is_equal(state_before)

func test_status_context_preserves_native_and_adds_successful_proc() -> void:
	var s: StatusComponent = auto_free(StatusComponent.new())
	s.setup(2, false)
	# ICE + FIRE 会触发淬爆并清空两种 active；此处选择不共鸣的 POISON，
	# 单独锁定“原生元素与成功附魔 proc 分别推进积累”的契约。
	var ctx := {"element": Elements.Id.ICE, "proc_element": Elements.Id.POISON,
		"status_rate_mult": 1.0}
	s.apply_hit_context(ctx, 4, 10)
	s.apply_hit_context(ctx, 4, 11)
	assert_bool(s.active.has(Elements.Id.ICE)).is_true()
	assert_bool(s.active.has(Elements.Id.POISON)).is_true()

func test_status_context_proc_failure_keeps_native_element_only() -> void:
	var s: StatusComponent = auto_free(StatusComponent.new())
	s.setup(2, false)
	var ctx := {"element": Elements.Id.ICE, "proc_element": Elements.Id.NONE}
	s.apply_hit_context(ctx, 4, 10)
	s.apply_hit_context(ctx, 4, 11)
	assert_bool(s.active.has(Elements.Id.ICE)).is_true()
	assert_int(s.active.size()).is_equal(1)

func test_projectile_hit_proc_rng_order_is_distance_then_registration() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var rng := RandomNumberGenerator.new(); rng.seed = 20260829
	# 用同 seed twin 计算两目标各自的第二掷（每目标先暴击、再附魔），
	# 再取两值中点确保结果不同；断言哪一个结果落到近者，验证消费顺序。
	var twin := RandomNumberGenerator.new(); twin.seed = 20260829
	twin.randf(); var near_proc_roll := twin.randf()
	twin.randf(); var far_proc_roll := twin.randf()
	assert_bool(is_equal_approx(near_proc_roll, far_proc_roll)).is_false()
	var chance := (near_proc_roll + far_proc_roll) * 0.5
	var cs := CombatSystem.new(root, rng)
	root.add_child(cs)
	cs.set_physics_process(false)
	cs.crit_chance = 0.0
	var far := SourceSpy.new(); far.position = Vector2(8, 0); root.add_child(far)
	var near := SourceSpy.new(); near.position = Vector2(2, 0); root.add_child(near)
	# 故意先注册远者，证明距离排序压过 Dictionary/注册顺序。
	cs.register_body(far, Projectile.Faction.ENEMY)
	cs.register_body(near, Projectile.Faction.ENEMY)
	cs.spawn_projectile({"pos": Vector2.ZERO, "vel": Vector2.ZERO, "damage": 1,
		"faction": Projectile.Faction.PLAYER, "element": Elements.Id.ICE,
		"enchant_element": Elements.Id.FIRE, "enchant_proc_chance": chance,
		"pierce": 1, "life_seconds": 1.0, "radius": 10.0})
	cs._physics_process(1.0 / TimeConst.FPS)
	assert_int(near.hit["element"]).is_equal(Elements.Id.ICE)
	assert_int(near.hit["proc_element"]).is_equal(Elements.Id.FIRE \
		if near_proc_roll < chance else Elements.Id.NONE)
	assert_int(far.hit["element"]).is_equal(Elements.Id.ICE)
	assert_int(far.hit["proc_element"]).is_equal(Elements.Id.FIRE \
		if far_proc_roll < chance else Elements.Id.NONE)

func test_projectile_without_buff_consumes_only_crit_rng() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var rng := RandomNumberGenerator.new(); rng.seed = 303
	var twin := RandomNumberGenerator.new(); twin.seed = 303; twin.randf()
	var cs := CombatSystem.new(root, rng); root.add_child(cs); cs.set_physics_process(false)
	cs.crit_chance = 0.0
	var target := SourceSpy.new(); root.add_child(target)
	cs.register_body(target, Projectile.Faction.ENEMY)
	cs.spawn_projectile({"pos": Vector2.ZERO, "vel": Vector2.ZERO, "damage": 1,
		"faction": Projectile.Faction.PLAYER, "element": Elements.Id.ICE,
		"pierce": 0, "life_seconds": 1.0, "radius": 3.0})
	cs._physics_process(1.0 / TimeConst.FPS)
	assert_int(rng.state).is_equal(twin.state)
	assert_int(target.hit["element"]).is_equal(Elements.Id.ICE)
	assert_int(target.hit["proc_element"]).is_equal(Elements.Id.NONE)

func test_multiple_projectiles_consume_proc_rng_in_spawn_order() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var rng := RandomNumberGenerator.new(); rng.seed = 20260829
	# 每颗弹先掷暴击、再掷附魔；用同 seed 的两个 proc 掷签中点确保结果相反，
	# 从而可直接观察 pool.active 的生成顺序是否就是 RNG 消费顺序。
	var twin := RandomNumberGenerator.new(); twin.seed = 20260829
	twin.randf(); var first_proc_roll := twin.randf()
	twin.randf(); var second_proc_roll := twin.randf()
	assert_bool(is_equal_approx(first_proc_roll, second_proc_roll)).is_false()
	var chance := (first_proc_roll + second_proc_roll) * 0.5
	var cs := CombatSystem.new(root, rng); root.add_child(cs); cs.set_physics_process(false)
	cs.crit_chance = 0.0
	var first := SourceSpy.new(); first.position = Vector2.ZERO; root.add_child(first)
	var second := SourceSpy.new(); second.position = Vector2(40, 0); root.add_child(second)
	cs.register_body(second, Projectile.Faction.ENEMY) # 故意反向注册，排除注册序干扰
	cs.register_body(first, Projectile.Faction.ENEMY)
	cs.spawn_projectile({"pos": Vector2.ZERO, "vel": Vector2.ZERO, "damage": 1,
		"faction": Projectile.Faction.PLAYER, "element": Elements.Id.ICE,
		"enchant_element": Elements.Id.FIRE, "enchant_proc_chance": chance,
		"pierce": 0, "life_seconds": 1.0, "radius": 3.0})
	cs.spawn_projectile({"pos": Vector2(40, 0), "vel": Vector2.ZERO, "damage": 1,
		"faction": Projectile.Faction.PLAYER, "element": Elements.Id.ICE,
		"enchant_element": Elements.Id.FIRE, "enchant_proc_chance": chance,
		"pierce": 0, "life_seconds": 1.0, "radius": 3.0})
	cs._physics_process(1.0 / TimeConst.FPS)
	assert_int(first.hit["proc_element"]).is_equal(Elements.Id.FIRE \
		if first_proc_roll < chance else Elements.Id.NONE)
	assert_int(second.hit["proc_element"]).is_equal(Elements.Id.FIRE \
		if second_proc_roll < chance else Elements.Id.NONE)

func test_temporary_enchant_real_hit_skips_permanent_proc_rng() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var rng := RandomNumberGenerator.new(); rng.seed = 404
	var twin := RandomNumberGenerator.new(); twin.seed = 404; twin.randf() # 仅暴击掷签
	var cs := CombatSystem.new(root, rng); root.add_child(cs); cs.set_physics_process(false)
	cs.crit_chance = 0.0
	var player := Player.new()
	player._test_init()
	var rig := WeaponRig.new()
	player.add_child(rig)
	rig._test_init()
	root.add_child(player)
	rig.combat = cs
	rig.slots = [{
		"id": "temp_element_test", "name": "临时附魔测试枪", "is_melee": false,
		"damage": 1, "rate": 1.0, "energy_cost": 0, "bullet_speed": 0.0,
		"spread_deg": 0.0, "projectiles": 1, "pierce": 0, "bounce": 0,
		"element": "ice", "bullet_life": 1.0, "bullet_radius": 3.0, "muzzle": 0.0,
	}, {}]
	rig.enchant_element = Elements.Id.FIRE
	rig.enchant_proc_chance = 1.0
	rig.temporary_enchant_element = Elements.Id.SHOCK
	rig.temporary_enchant_until = 100
	var target := SourceSpy.new(); root.add_child(target)
	cs.register_body(target, Projectile.Faction.ENEMY)
	assert_bool(rig.try_fire(Vector2.RIGHT, 0)).is_true()
	cs._physics_process(1.0 / TimeConst.FPS)
	assert_int(target.hit["element"]).is_equal(Elements.Id.SHOCK)
	assert_int(target.hit["proc_element"]).is_equal(Elements.Id.NONE)
	assert_int(rng.state).is_equal(twin.state)

func test_same_seed_reproduces_element_proc_sequence() -> void:
	var a := RandomNumberGenerator.new(); a.seed = 20260829
	var b := RandomNumberGenerator.new(); b.seed = 20260829
	var seq_a: Array[int] = []
	var seq_b: Array[int] = []
	for i in 40:
		seq_a.append(ElementProc.roll_element(Elements.Id.SHOCK, 0.15, a))
		seq_b.append(ElementProc.roll_element(Elements.Id.SHOCK, 0.15, b))
	assert_array(seq_a).is_equal(seq_b)
