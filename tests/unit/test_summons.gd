class_name TestSummons
extends GdUnitTestSuite
## M2-T8 B-1：召唤物框架（SummonBase）+ 工程师「自动炮台」。
## 数值出处：计划卡 Task 8（12s 存活 / 索敌 240px / 射速 2/s / 伤 4 / 上限 2 /
## 升级版每 3s 导弹 12 AoE）+ GDD §6 工程师行（hp7/盾5/蓝120/速78/铆钉枪）。
## 帧注入风格同 test_skills：tick(frame) 直驱，不经 _physics_process。

const SKILL_PATH := "res://core/player/skills/turret.gd"

# ---- 夹具 ----

func _root() -> Node2D:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	return root

func _player(root: Node2D) -> Player:
	var p: Player = auto_free(Player.new())
	p._test_init()
	p.position = Vector2(500, 100)
	root.add_child(p)
	return p

func _combat(root: Node2D) -> CombatSystem:
	var cs := CombatSystem.new(root, RngSvc.stream(0, "combat"))
	auto_free(cs)
	root.add_child(cs)
	return cs

## 入树假敌（进 "enemies" 组并注册进 combat；brain_pos 与 global_position 对齐）。
func _enemy(root: Node2D, cs: CombatSystem, at: Vector2, hp := 30) -> EnemyBase:
	var e := EnemyBase.new()
	e._test_init({"id": "turret_dummy", "hp": hp, "radius": 6.0})
	e.brain_pos = at
	e.position = at
	root.add_child(e)
	e.add_to_group("enemies")
	cs.register_body(e, e.combat_faction())
	return e

## 装好工程师技能的玩家（生产路径：meta "hero" 行注入召唤上限，同 HeroApplier 时序）。
func _engineer(root: Node2D, cs: CombatSystem, upgraded := false) -> Player:
	var p := _player(root)
	p.combat = cs
	p.set_meta("hero", GameDB.get_hero("engineer"))
	var skill: EngineerTurret = auto_free(EngineerTurret.new())
	skill.name = "Skill"                        # 生产路径：player.tscn 恒挂 "Skill" 节点换装
	skill.setup(p, {"upgraded": upgraded})
	p.add_child(skill)
	return p

func _first_summon(root: Node2D) -> TurretSummon:
	# queue_free 的退场体在空闲帧前仍在组内：按存活口径过滤（同 living_summons 语义）
	for node in root.get_tree().get_nodes_in_group("summons"):
		var s := node as TurretSummon
		if s != null and not s.is_despawned() and not s.is_queued_for_deletion():
			return s
	return null

# ---- 数据行（heroes.json 工程师行 + summon_cap 附加键） ----

func test_engineer_row_values() -> void:
	assert_bool(GameDB.load_ok).is_true()
	var h := GameDB.get_hero("engineer")
	assert_str(h.get("name", "")).is_equal("工程师·铆")
	assert_int(h.get("hp", -1)).is_equal(7)
	assert_int(h.get("shield", -1)).is_equal(5)
	assert_int(h.get("energy", -1)).is_equal(120)
	assert_float(h.get("speed", -1.0)).is_equal_approx(78.0, 0.001)
	assert_float(h.get("crit_chance", -1.0)).is_equal_approx(0.05, 0.0001)
	var sw: Array = h.get("start_weapons", [])
	assert_int(sw.size()).is_equal(1)
	assert_str(String(sw[0])).is_equal("maodingqiang")
	assert_str(h.get("skill_script", "")).is_equal(SKILL_PATH)
	assert_int(h.get("skill_cd", -1)).is_equal(720)             # CD 12s（GDD §6）
	assert_int(h.get("skill_energy", -2)).is_equal(0)
	assert_str(h.get("passive_id", "")).is_equal("spare_parts")
	assert_bool(h.get("has_defiance", true)).is_false()
	assert_str(h.get("skill_name", "")).is_equal("自动炮台")
	assert_bool(h.get("skill_desc", "").is_empty()).is_false()
	assert_bool(h.get("upgraded", true)).is_false()
	assert_int(h.get("summon_cap", -1)).is_equal(2)             # 召唤物库存上限（计划卡）

# ---- 部署（技能施放 → 召唤物落地 + 接线） ----

## 生产换装路径（HeroApplier.set_script + 数据/hero meta 注入）端到端。
func test_hero_applier_mounts_engineer_skill_and_cast_deploys() -> void:
	var root := _root()
	var cs := _combat(root)
	var p: Player = auto_free(preload("res://core/player/player.tscn").instantiate())
	p.position = Vector2(500, 100)
	root.add_child(p)
	p.combat = cs
	HeroApplier.apply(GameDB.get_hero("engineer"), p)
	var skill: Node = p.get_node("Skill")
	assert_str((skill.get_script() as Script).resource_path).is_equal(SKILL_PATH)
	assert_int(skill.get("cooldown_ticks")).is_equal(720)       # skill_cd 经数据行注入
	assert_int(skill.get("energy_cost")).is_equal(0)
	assert_int(int(skill.call("summon_cap"))).is_equal(2)       # 上限经 hero meta 行注入
	assert_bool(skill.cast(100)).is_true()
	assert_object(_first_summon(root)).is_not_null()

func test_cast_deploys_turret_at_player_with_wiring() -> void:
	var root := _root()
	var cs := _combat(root)
	var p := _engineer(root, cs)
	var skill: EngineerTurret = p.get_node("Skill") as EngineerTurret
	assert_bool(skill.cast(100)).is_true()
	var turret := _first_summon(root)
	assert_object(turret).is_not_null()
	assert_bool(turret.is_in_group("summons")).is_true()
	assert_vector(turret.global_position).is_equal_approx(p.global_position,
		Vector2(0.001, 0.001))                                   # 落在玩家脚下
	assert_object(turret.combat).is_same(cs)                    # 挂房间 combat 引用（契约）
	assert_object(turret.player).is_same(p)                     # 玩家引用注入（契约）
	assert_int(turret.hp).is_equal(turret.hp_max)
	assert_int(turret.hp_max).is_greater(0)
	# 已登记为玩家阵营战斗体（敌弹可命中炮台）
	var found := false
	for body in cs.bodies_in_radius(turret.global_position, 200.0, Projectile.Faction.PLAYER):
		if body == turret:
			found = true
	assert_bool(found).is_true()
	assert_int(skill.cooldown_remaining(100)).is_equal(720)     # CD 12s
	assert_bool(skill.cast(101)).is_false()                     # CD 门

# ---- 索敌 + 开火（注入帧） ----

func test_turret_fires_at_nearest_enemy_within_240px() -> void:
	var root := _root()
	var cs := _combat(root)
	var p := _engineer(root, cs)
	(p.get_node("Skill") as EngineerTurret).cast(100)
	var turret := _first_summon(root)
	var near := _enemy(root, cs, turret.global_position + Vector2(100, 0))
	var far_in_range := _enemy(root, cs, turret.global_position + Vector2(200, 0))
	turret.tick(100 + 30)                                       # 射速 2/s：部署后 30t 首射
	assert_int(cs.pool.active.size()).is_equal(1)
	var shot: Projectile = cs.pool.active[0]
	assert_int(shot.damage).is_equal(4)                         # 伤 4（计划卡）
	assert_int(shot.faction).is_equal(Projectile.Faction.PLAYER)
	var dir: Vector2 = (shot.vel as Vector2).normalized()
	assert_float(dir.dot((near.brain_pos - turret.global_position).normalized())) \
		.is_equal_approx(1.0, 0.01)                             # 朝最近敌人（100px < 200px）
	far_in_range.take_hit({"amount": 0})                        # 引用保活（未被打中）

func test_turret_no_target_beyond_240px_no_shot() -> void:
	var root := _root()
	var cs := _combat(root)
	var p := _engineer(root, cs)
	(p.get_node("Skill") as EngineerTurret).cast(100)
	var turret := _first_summon(root)
	_enemy(root, cs, turret.global_position + Vector2(400, 0))  # 索敌外
	for f in 4:
		turret.tick(100 + 30 * (f + 1))
	assert_int(cs.pool.active.size()).is_equal(0)               # 越界敌不打

func test_turret_fire_cadence_two_per_second() -> void:
	var root := _root()
	var cs := _combat(root)
	var p := _engineer(root, cs)
	(p.get_node("Skill") as EngineerTurret).cast(100)
	var turret := _first_summon(root)
	_enemy(root, cs, turret.global_position + Vector2(80, 0))
	turret.tick(130)
	assert_int(cs.pool.active.size()).is_equal(1)               # 30t：第 1 发
	turret.tick(159)
	assert_int(cs.pool.active.size()).is_equal(1)               # 29t 间隔：未到节拍
	turret.tick(160)
	assert_int(cs.pool.active.size()).is_equal(2)               # 30t：第 2 发（2/s）

# ---- 超时自毁 / 击毁 ----

func test_turret_expires_after_720_ticks() -> void:
	var root := _root()
	var cs := _combat(root)
	var p := _engineer(root, cs)
	(p.get_node("Skill") as EngineerTurret).cast(100)
	var turret := _first_summon(root)
	var reasons: Array = []
	turret.despawned.connect(func(reason: String) -> void: reasons.append(reason))
	turret.tick(100 + 719)
	assert_bool(turret.is_queued_for_deletion()).is_false()      # 12s 内存活
	turret.tick(100 + 720)
	assert_bool(turret.is_queued_for_deletion()).is_true()       # 超时 → queue_free
	assert_array(reasons).contains_exactly(["expired"])
	# 退场即注销战斗体
	var found := false
	for body in cs.bodies_in_radius(turret.global_position, 200.0, Projectile.Faction.PLAYER):
		if body == turret:
			found = true
	assert_bool(found).is_false()

func test_turret_destroyed_when_hp_depleted() -> void:
	var root := _root()
	var cs := _combat(root)
	var p := _engineer(root, cs)
	(p.get_node("Skill") as EngineerTurret).cast(100)
	var turret := _first_summon(root)
	var reasons: Array = []
	turret.despawned.connect(func(reason: String) -> void: reasons.append(reason))
	turret.take_hit({"amount": turret.hp})                       # 敌弹击毁
	assert_bool(turret.is_queued_for_deletion()).is_true()
	assert_array(reasons).contains_exactly(["destroyed"])

func test_summon_base_lifetime_from_row_override() -> void:
	var root := _root()
	var s: SummonBase = auto_free(SummonBase.new())
	root.add_child(s)
	s.setup({"id": "probe", "hp": 3, "lifetime_ticks": 10})
	s.begin(1000)
	assert_int(s.hp_max).is_equal(3)
	s.tick(1009)
	assert_bool(s.is_queued_for_deletion()).is_false()
	s.tick(1010)
	assert_bool(s.is_queued_for_deletion()).is_true()

# ---- 库存上限 2（先进先出顶替） ----

func test_summon_cap_two_replaces_oldest() -> void:
	var root := _root()
	var cs := _combat(root)
	var p := _engineer(root, cs)
	var skill: EngineerTurret = p.get_node("Skill") as EngineerTurret
	skill.cast(0)
	var first := _first_summon(root)
	var first_reasons: Array = []
	first.despawned.connect(func(reason: String) -> void: first_reasons.append(reason))
	skill.cast(720)                                              # CD 12s 后第二台
	assert_int(skill.living_summons().size()).is_equal(2)
	skill.cast(1440)                                             # 第三台：上限 2 → 顶替最旧
	assert_int(skill.living_summons().size()).is_equal(2)
	assert_array(first_reasons).contains_exactly(["replaced"])
	assert_bool(first.is_queued_for_deletion()).is_true()
	assert_bool(_first_summon(root) != first).is_true()

# ---- 升级版：每 3s 追加导弹（12 AoE） ----

func test_upgraded_turret_missile_aoe_every_180_ticks() -> void:
	var root := _root()
	var cs := _combat(root)
	var p := _engineer(root, cs, true)
	(p.get_node("Skill") as EngineerTurret).cast(100)
	var turret := _first_summon(root)
	assert_bool(turret.upgraded).is_true()
	var a := _enemy(root, cs, turret.global_position + Vector2(100, 0), 30)   # 导弹落点（最近）
	var b := _enemy(root, cs, turret.global_position + Vector2(130, 0), 30)   # 距 a 30px：AoE 内
	var c := _enemy(root, cs, turret.global_position + Vector2(230, 0), 30)   # 距 a 130px：AoE 外
	turret.tick(100 + 179)
	assert_int(a.hp).is_equal(30)                                # 未到 3s 节拍
	turret.tick(100 + 180)
	assert_int(a.hp).is_equal(18)                                # 12 AoE（GDD §6 强化）
	assert_int(b.hp).is_equal(18)
	assert_int(c.hp).is_equal(30)                                # AoE 外不伤

func test_plain_turret_never_fires_missile() -> void:
	var root := _root()
	var cs := _combat(root)
	var p := _engineer(root, cs, false)
	(p.get_node("Skill") as EngineerTurret).cast(100)
	var turret := _first_summon(root)
	assert_bool(turret.upgraded).is_false()
	var a := _enemy(root, cs, turret.global_position + Vector2(100, 0), 30)
	for i in 6:
		turret.tick(100 + 30 * (i + 1))                          # 推进 180t（跨导弹节拍）
	assert_int(a.hp).is_equal(30)                                # 无导弹：直射弹走 combat（未命中前 hp 不动）
	assert_int(cs.pool.active.size()).is_greater(0)              # 常规炮弹照常
