class_name TestHeroPassives
extends GdUnitTestSuite
## m4-c2：英雄被动 ×4 从 data-only 转真实消费端（GDD §6 技能表逐字）。
## - echo（法师）：法杖/激光类武器伤害 +15% —— CombatSystem 命中结算全局乘区
##   （GDD §7.1「全局乘区」口径：base ×1.15 后统一向下取整、最小 1）。
## - blessing（守护者）：每进入新层回满护盾 + 5% 全伤害（单局叠至 4 层）；
##   保守读法（任务卡钉死）：首层开局不叠层，进入第 2 层起每层 +1、第 5 层起封顶 ——
##   消费点 = run_root 层入口钩子 + player.scaled_damage 伤害出口聚合点。
## - spare_parts（工程师）：开局带 1 台便携炮台（存活 12s，DPS 15）+ 每层补 1 台；
##   与主动技共用库存上限 2（GDD 明文；满编顶替最旧 FIFO = summons 既有语义）。
## - shadow_reap（刺客）：近战击杀返还 5 蓝 + 1s 内翻滚无冷却 —— melee 击杀上报 +
##   player.on_melee_kill / roll_ready_at 门控。
## 每被动均带非对应英雄零漂移反例；tests/unit/test_heroes.gd 数据钉不受影响（数据未动）。

const RUN_ROOT_SCENE := "res://core/rooms/run_root.tscn"
const PLAYER_SCENE := preload("res://core/player/player.tscn")

# ---- 夹具 ----

## 密封天赋的 RunRoot（m1_integration._make_root 同款：共享档已购天赋不污染伤害断言）。
## auto_free 注册：RunRoot（含 FloorScene/召唤物）必须逐用例释放——"summons" 组是
## 全局组，不释放会跨用例泄漏并污染零漂移断言。
func _make_root() -> Node2D:
	var root: Node2D = (load(RUN_ROOT_SCENE) as PackedScene).instantiate() as Node2D
	var ts := TalentSystem.new()
	ts.save_system = null
	ts.purchased = []
	root.talents = ts
	auto_free(root)
	return root

func after_test() -> void:
	RunState.start_run("vanguard")   # 复位楼层/种子/聚合（跨套件卫生，m1_integration 同款）

func _combat(root: Node2D) -> CombatSystem:
	var cs := CombatSystem.new(root, RngSvc.stream(0, "combat"))
	cs.crit_chance = 0.0                       # 暴击确定性归零（回响乘区与暴击无关）
	auto_free(cs)
	root.add_child(cs)
	return cs

## 入树假敌（进 "enemies" 组并注册进 combat；brain_pos 与 global_position 对齐）。
func _enemy(root: Node2D, cs: CombatSystem, at: Vector2, hp := 100) -> EnemyBase:
	var e := EnemyBase.new()
	e._test_init({"id": "passive_dummy", "hp": hp, "radius": 6.0})
	e.brain_pos = at
	e.position = at
	root.add_child(e)
	e.add_to_group("enemies")
	cs.register_body(e, e.combat_faction())
	return e

## 命中结算驱动：弹落在敌心（vel 0），物理帧推进至命中弹退场。
func _fire_at(root: Node2D, cs: CombatSystem, at: Vector2, damage: int, source_type: String, source_id: String) -> void:
	cs.spawn_projectile({
		"pos": at, "vel": Vector2.ZERO, "damage": damage,
		"faction": Projectile.Faction.PLAYER, "element": Elements.Id.NONE,
		"pierce": 0, "bounce": 0, "life_seconds": 1.0, "radius": 3.0,
		"source_type": source_type, "source_id": source_id,
		"source_name": source_id, "attack_name": "射击",
	})
	for _i in 10:
		await get_tree().physics_frame

func _living_summons(of_node: Node) -> Array[TurretSummon]:
	var out: Array[TurretSummon] = []
	for node in of_node.get_tree().get_nodes_in_group("summons"):
		var s := node as TurretSummon
		if s != null and not s.is_despawned() and not s.is_queued_for_deletion():
			out.append(s)
	return out


# ================================================================ 回响 echo（法师）

func test_echo_staff_damage_mult_exact_floor_semantics() -> void:
	# 学徒法杖系高伤杖 yunshizhang（伤 20）：20×1.15=23.0 → 向下取整 23（GDD §7.1）。
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	cs.hero_passive_id = "echo"
	var e := _enemy(root, cs, Vector2(200, 0), 100)
	await _fire_at(root, cs, Vector2(200, 0), 20, "weapon", "yunshizhang")
	assert_int(e.hp).is_equal(77)

func test_echo_laser_damage_mult_exact() -> void:
	# 激光 guidaobiaojiqi（伤 8）：8×1.15=9.2 → 9。
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	cs.hero_passive_id = "echo"
	var e := _enemy(root, cs, Vector2(200, 0), 100)
	await _fire_at(root, cs, Vector2(200, 0), 8, "weapon", "guidaobiaojiqi")
	assert_int(e.hp).is_equal(91)

func test_echo_low_base_floor_disclosure_no_gain() -> void:
	# 学徒法杖（伤 3）：3×1.15=3.45 → 向下取整 3（GDD §7.1 取整口径的自然结果，
	# 基伤 <7 时 +15% 不跳变——本测钉死该语义防实现漂移成 round/进位）。
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	cs.hero_passive_id = "echo"
	var e := _enemy(root, cs, Vector2(200, 0), 100)
	await _fire_at(root, cs, Vector2(200, 0), 3, "weapon", "xuetufazhang")
	assert_int(e.hp).is_equal(97)

func test_echo_zero_drift_non_echo_sources_and_heroes() -> void:
	# 非法杖/激光武器（pistol laohuoji 伤 2）、召唤物弹、非法师英雄恒 1.0（零漂移）。
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	cs.hero_passive_id = "echo"
	var e := _enemy(root, cs, Vector2(200, 0), 100)
	await _fire_at(root, cs, Vector2(200, 0), 2, "weapon", "laohuoji")
	assert_int(e.hp).is_equal(98)              # pistol 不在回响类
	var e2 := _enemy(root, cs, Vector2(-200, 0), 100)
	await _fire_at(root, cs, Vector2(-200, 0), 4, "summon", "turret")
	assert_int(e2.hp).is_equal(96)             # 召唤物弹非武器弹
	var cs2 := _combat(root)                   # 非法师英雄：passive 缺省 ""
	var e4 := _enemy(root, cs2, Vector2(200, 0), 100)
	await _fire_at(root, cs2, Vector2(200, 0), 20, "weapon", "yunshizhang")
	assert_int(e4.hp).is_equal(80)
	var cs3 := _combat(root)                   # 骑士：hero_passive_id="defiance"
	cs3.hero_passive_id = "defiance"
	var e5 := _enemy(root, cs3, Vector2(200, 0), 100)
	await _fire_at(root, cs3, Vector2(200, 0), 20, "weapon", "yunshizhang")
	assert_int(e5.hp).is_equal(80)

func test_echo_weapon_category_predicate() -> void:
	# GDD §6「法杖/激光类」= weapons.json category staff/laser（纯函数直测）。
	assert_bool(CombatSystem._is_echo_weapon_category("staff")).is_true()
	assert_bool(CombatSystem._is_echo_weapon_category("laser")).is_true()
	assert_bool(CombatSystem._is_echo_weapon_category("pistol")).is_false()
	assert_bool(CombatSystem._is_echo_weapon_category("bow")).is_false()
	assert_bool(CombatSystem._is_echo_weapon_category("melee")).is_false()
	assert_bool(CombatSystem._is_echo_weapon_category("special")).is_false()
	assert_bool(CombatSystem._is_echo_weapon_category("")).is_false()

func test_echo_passive_flows_via_player_combat_injection() -> void:
	# player.combat 注入（floor_scene._wire_room_combat 生产路径）回写 echo 读点。
	var p: Player = auto_free(Player.new())
	p._test_init()
	p.passive_id = "echo"
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	assert_str(cs.hero_passive_id).is_empty()   # 注入前缺省
	p.combat = cs
	assert_str(cs.hero_passive_id).is_equal("echo")
	p.combat = null                              # 摘除不回写、不报错
	assert_str(cs.hero_passive_id).is_equal("echo")
	# HeroApplier 装配序兜底：combat 先注入、装配后（training_room 序）仍回填。
	# （用 player.tscn：apply 会换装 Skill 节点，裸 Player.new() 无该子节点。）
	var cs2 := _combat(root)
	var p2: Player = PLAYER_SCENE.instantiate()
	auto_free(p2)
	add_child(p2)
	p2.combat = cs2
	HeroApplier.apply(GameDB.get_hero("mage"), p2)
	assert_str(p2.passive_id).is_equal("echo")
	assert_str(cs2.hero_passive_id).is_equal("echo")


# ================================================================ 祝福 blessing（守护者）

func test_blessing_floor_entry_stack_matrix_cap_and_shield_refill() -> void:
	# 叠层矩阵：首层不叠；2/3/4/5/6 层 → 1/2/3/4/4（4 层帽）；每次入口回满护盾。
	var root := _make_root()
	add_child(root)
	var p: Player = auto_free(Player.new())
	p._test_init()
	p.passive_id = "blessing"
	p.shield_max = 6                            # GDD §6 守护者盾 6
	root.player = p
	root._apply_floor_entry_passives(1, 100)    # 首层开局：不叠层（保守读法钉死）
	assert_int(p.blessing_stacks).is_equal(0)
	p.shield = 2
	root._apply_floor_entry_passives(2, 100)
	assert_int(p.blessing_stacks).is_equal(1)
	assert_int(p.shield).is_equal(6)            # 回满护盾
	p.shield = 0
	root._apply_floor_entry_passives(3, 100)
	assert_int(p.blessing_stacks).is_equal(2)
	assert_int(p.shield).is_equal(6)
	root._apply_floor_entry_passives(4, 100)
	assert_int(p.blessing_stacks).is_equal(3)
	root._apply_floor_entry_passives(5, 100)
	assert_int(p.blessing_stacks).is_equal(4)   # 至多 4 层
	root._apply_floor_entry_passives(6, 100)
	assert_int(p.blessing_stacks).is_equal(4)   # 第 5 层起封顶不外溢
	assert_int(p.shield).is_equal(6)

func test_blessing_damage_exit_remote_per_stack() -> void:
	# 伤害出口聚合点（远程）：base 20 每层 +5% → 21/22/23/24（round 口径沿袭天赋先例）。
	var p: Player = auto_free(Player.new())
	p._test_init()
	p.passive_id = "blessing"
	assert_int(p.scaled_damage(20)).is_equal(20)   # 0 层 = 原伤
	p.blessing_stacks = 1
	assert_int(p.scaled_damage(20)).is_equal(21)
	p.blessing_stacks = 2
	assert_int(p.scaled_damage(20)).is_equal(22)
	p.blessing_stacks = 3
	assert_int(p.scaled_damage(20)).is_equal(23)
	p.blessing_stacks = 4
	assert_int(p.scaled_damage(20)).is_equal(24)   # +20% 封顶

func test_blessing_damage_exit_reaches_projectile_and_melee() -> void:
	# 远程：WeaponRig 探针捕获落弹伤害（yunshizhang 伤 20，4 层 → 24）。
	# 近战：真挥击路径（双匕伤 4，4 层 → round(4.8)=5）。
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var p: Player = auto_free(Player.new())
	p._test_init()
	p.passive_id = "blessing"
	p.blessing_stacks = 4
	root.add_child(p)
	var rig := RigProbe.new()
	p.add_child(rig)
	rig._test_init()
	rig.equip("yunshizhang")
	assert_bool(rig.try_fire(Vector2.RIGHT, 0)).is_true()
	assert_int(rig.spawned.size()).is_equal(1)
	assert_int(int(rig.spawned[0]["damage"])).is_equal(24)
	# 近战真路径
	var cs := _combat(root)
	var e := _enemy(root, cs, Vector2(20, 0), 100)
	var m: Melee = auto_free(Melee.new())
	p.add_child(m)
	m._test_init()
	m.rig = auto_free(WeaponRig.new())
	m.rig.slots = [GameDB.get_weapon("shuangbi"), {}]
	m.combat = cs
	assert_bool(m.try_attack(0)).is_true()
	m._physics_process(1.0 / TimeConst.FPS)
	assert_int(e.hp).is_equal(95)               # 100 - round(4×1.2)=5

func test_blessing_floor_entry_via_run_root_real_flow() -> void:
	# 真流程：guardian 开局（首层不叠）→ 门进第 2 层（真建 A2 楼层）→ 叠 1 层 + 回盾。
	RunState.start_run("guardian")
	var root := _make_root()
	add_child(root)
	root._begin()
	var p: Player = root.player
	assert_str(p.passive_id).is_equal("blessing")
	assert_int(p.blessing_stacks).is_equal(0)   # 首层不叠
	p.shield = 1                                # 模拟首层掉盾
	root._on_next_floor_requested(2)
	assert_int(p.blessing_stacks).is_equal(1)
	assert_int(p.shield).is_equal(p.shield_max)
	assert_int(root.floor_scene.floor_idx).is_equal(2)

func test_blessing_repeat_entry_same_floor_no_double_stack() -> void:
	# 「每进入新层」按层号去重：同层重复触发（层间重入/根节点复用）不重复叠层；
	# 护盾回满幂等、重复入口仍执行（run_root._floor_entry_max 去重语义钉死）。
	var root := _make_root()
	add_child(root)
	var p: Player = auto_free(Player.new())
	p._test_init()
	p.passive_id = "blessing"
	p.shield_max = 6
	root.player = p
	root._apply_floor_entry_passives(2, 100)
	assert_int(p.blessing_stacks).is_equal(1)
	p.shield = 3
	root._apply_floor_entry_passives(2, 150)    # 同层重复入口：不叠层
	assert_int(p.blessing_stacks).is_equal(1)
	assert_int(p.shield).is_equal(6)            # 但回盾仍幂等生效
	root._apply_floor_entry_passives(1, 200)    # 层号回退（≤已触发最大层）：不叠层
	assert_int(p.blessing_stacks).is_equal(1)
	root._apply_floor_entry_passives(3, 250)    # 真新层恢复叠层
	assert_int(p.blessing_stacks).is_equal(2)

func test_blessing_zero_drift_non_guardian() -> void:
	# 非守护者：层入口钩子恒等（不叠层不动盾），伤害出口无叠层乘区。
	var root := _make_root()
	add_child(root)
	var p: Player = auto_free(Player.new())
	p._test_init()
	p.passive_id = "defiance"
	p.shield_max = 4
	p.shield = 1
	root.player = p
	root._apply_floor_entry_passives(3, 100)
	assert_int(p.blessing_stacks).is_equal(0)
	assert_int(p.shield).is_equal(1)            # 盾不被回满
	assert_int(p.scaled_damage(20)).is_equal(20)


# ================================================================ 备件 spare_parts（工程师）

func test_spare_parts_row_dps_15_lifetime_12s() -> void:
	# GDD §6：存活 12s、DPS 15 —— 5 伤 × 3/s（20t）拆分议定；整期名义总伤 = 180。
	var row := TurretSummon.spare_parts_row()
	assert_int(int(row.get("lifetime_ticks", -1))).is_equal(720)
	assert_int(int(row.get("shot_damage", -1))).is_equal(5)
	assert_int(int(row.get("fire_interval_ticks", -1))).is_equal(20)
	assert_int(int(row.get("shot_damage", -1)) * (int(TimeConst.FPS) / int(row.get("fire_interval_ticks", 1)))).is_equal(15)
	assert_int(int(row.get("shot_damage", -1)) * (int(row.get("lifetime_ticks", 0)) / int(row.get("fire_interval_ticks", 1)))).is_equal(180)

func test_spare_parts_initial_deploy_on_begin() -> void:
	# 开局带 1 台（_begin 层入口钩子），行 = spare_parts_row。
	RunState.start_run("engineer")
	var root := _make_root()
	add_child(root)
	root._begin()
	var p: Player = root.player
	assert_str(p.passive_id).is_equal("spare_parts")
	var living := _living_summons(root)
	assert_int(living.size()).is_equal(1)
	assert_int(int(living[0].row.get("shot_damage", -1))).is_equal(5)
	assert_int(int(living[0].row.get("fire_interval_ticks", -1))).is_equal(20)
	assert_int(int(living[0].row.get("lifetime_ticks", -1))).is_equal(720)
	# 主动技与被动共用库存上限（heroes.summon_cap=2 → HeroApplier meta 接缝读出）。
	var skill := p.get_node("Skill") as EngineerTurret
	assert_object(skill).is_not_null()
	assert_int(skill.summon_cap()).is_equal(2)

func test_spare_parts_refill_shares_cap_and_replaces_oldest() -> void:
	# 每层补 1 台 + 共帽 2：满编时补台顶替最旧（FIFO，summons 既有语义），总数恒 ≤ 2。
	RunState.start_run("engineer")
	var root := _make_root()
	add_child(root)
	root._begin()
	var p: Player = root.player
	var initial := _living_summons(root)[0]
	var skill := p.get_node("Skill") as EngineerTurret
	# 主动技补到满编 2 台（默认行 伤 4）
	assert_bool(skill.cast(Engine.get_physics_frames())).is_true()
	assert_int(_living_summons(root).size()).is_equal(2)
	# 层入口补台：满编 → 开局备件台（最旧）退场，新备件台（伤 5）落地
	root._apply_floor_entry_passives(2, Engine.get_physics_frames() + 50)
	assert_bool(initial.is_despawned()).is_true()
	var living := _living_summons(root)
	assert_int(living.size()).is_equal(2)
	var spare := false
	for s in living:
		if int(s.row.get("shot_damage", -1)) == 5:
			spare = true
	assert_bool(spare).is_true()                # 新补的备件台在场
	# 连续再补一层：仍 2 台（帽不外溢）
	root._apply_floor_entry_passives(3, Engine.get_physics_frames() + 100)
	assert_int(_living_summons(root).size()).is_equal(2)

func test_spare_parts_repeat_entry_same_floor_no_redeploy() -> void:
	# 「每进入新一层补 1 台」按层号去重：同层重复入口不重复补台（不顶替/不超帽）。
	RunState.start_run("engineer")
	var root := _make_root()
	add_child(root)
	root._begin()
	var skill := root.player.get_node("Skill") as EngineerTurret
	root._apply_floor_entry_passives(2, Engine.get_physics_frames() + 50)
	var count := _living_summons(root).size()
	assert_int(count).is_equal(2)               # 开局 1 + 补 1（帽 2）
	root._apply_floor_entry_passives(2, Engine.get_physics_frames() + 100)
	assert_int(_living_summons(root).size()).is_equal(count)   # 重复入口：数量不变
	skill.cast(Engine.get_physics_frames() + 120)              # 主动技仍可在帽内部署
	assert_int(_living_summons(root).size()).is_equal(2)

func test_spare_parts_zero_drift_non_engineer() -> void:
	# 非工程师：开局/层入口钩子不产生任何召唤物。
	RunState.start_run("vanguard")
	var root := _make_root()
	add_child(root)
	root._begin()
	assert_str(root.player.passive_id).is_equal("defiance")
	assert_int(_living_summons(root).size()).is_equal(0)
	root._apply_floor_entry_passives(2, 100)
	assert_int(_living_summons(root).size()).is_equal(0)
	# 裸玩家（无 Skill 节点）挂 spare_parts 被动：钩子静默跳过不崩。
	var bare_root := _make_root()
	add_child(bare_root)
	var bare: Player = auto_free(Player.new())
	bare._test_init()
	bare.passive_id = "spare_parts"
	bare_root.player = bare
	bare_root._apply_floor_entry_passives(2, 100)   # 无 Skill → no-op
	assert_int(_living_summons(bare_root).size()).is_equal(0)


# ================================================================ 掠影 shadow_reap（刺客）

func test_shadow_reap_kill_grants_5_energy_and_roll_free_window() -> void:
	var p: Player = auto_free(Player.new())
	p._test_init()
	p.passive_id = "shadow_reap"
	p.energy = 40
	# 长翻滚 CD（模拟刚翻滚），击杀开窗
	p._roll_cd_until = 2000
	p.on_melee_kill(1000)
	assert_int(p.energy).is_equal(45)           # 返还 5 蓝
	assert_bool(p.roll_ready_at(1059)).is_true()    # 窗内（1000+60=1060 末帧开）无视 CD
	assert_bool(p.roll_ready_at(1060)).is_false()   # 窗闭即恢复 CD 门控
	# 再次击杀：窗口顺延（按最新击杀计）
	p.on_melee_kill(1040)
	assert_int(p.energy).is_equal(50)
	assert_bool(p.roll_ready_at(1099)).is_true()
	assert_bool(p.roll_ready_at(1100)).is_false()

func test_shadow_reap_window_end_to_end_via_melee_kill() -> void:
	# 真近战挥击击杀路径（双匕伤 4 > hp 1 必杀）→ 上报 Player → 返蓝 + 免冷却窗生效。
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	var p: Player = auto_free(Player.new())
	p._test_init()
	p.passive_id = "shadow_reap"
	p.energy = 40
	root.add_child(p)
	var m: Melee = auto_free(Melee.new())
	p.add_child(m)
	m._test_init()
	m.rig = auto_free(WeaponRig.new())
	m.rig.slots = [GameDB.get_weapon("shuangbi"), {}]
	m.combat = cs
	var e := _enemy(root, cs, Vector2(20, 0), 1)
	assert_bool(m.try_attack(0)).is_true()
	m._physics_process(1.0 / TimeConst.FPS)
	assert_bool(e.state == EnemyBase.State.DEAD).is_true()
	assert_int(p.energy).is_equal(45)
	var window_until := p._reap_roll_free_until
	assert_int(window_until).is_greater(0)
	# 窗内免 CD：把 CD 抬到窗外之后，窗内帧仍可翻滚
	p._roll_cd_until = window_until + 10
	assert_bool(p.roll_ready_at(window_until - 1)).is_true()
	assert_bool(p.roll_ready_at(window_until)).is_false()

func test_shadow_reap_surviving_hit_no_credit() -> void:
	# 未击杀（敌存活）不上报：无返蓝、无窗。
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	var p: Player = auto_free(Player.new())
	p._test_init()
	p.passive_id = "shadow_reap"
	p.energy = 40
	root.add_child(p)
	var m: Melee = auto_free(Melee.new())
	p.add_child(m)
	m._test_init()
	m.rig = auto_free(WeaponRig.new())
	m.rig.slots = [GameDB.get_weapon("shuangbi"), {}]
	m.combat = cs
	var e := _enemy(root, cs, Vector2(20, 0), 100)
	assert_bool(m.try_attack(0)).is_true()
	m._physics_process(1.0 / TimeConst.FPS)
	assert_bool(e.state == EnemyBase.State.DEAD).is_false()
	assert_int(p.energy).is_equal(40)
	assert_int(p._reap_roll_free_until).is_equal(-999)

func test_shadow_reap_zero_drift_non_assassin() -> void:
	# 非刺客：击杀上报为恒等 no-op（不返蓝、不开窗、翻滚 CD 照常门控）。
	var p: Player = auto_free(Player.new())
	p._test_init()
	p.passive_id = "defiance"
	p.energy = 40
	p._roll_cd_until = 2000
	p.on_melee_kill(1000)
	assert_int(p.energy).is_equal(40)
	assert_bool(p.roll_ready_at(1000)).is_false()   # CD 照常拦截
	# 无被动 id（裸玩家）同理
	var q: Player = auto_free(Player.new())
	q._test_init()
	q.energy = 40
	q.on_melee_kill(1000)
	assert_int(q.energy).is_equal(40)


# ---- 探针（文件尾聚合；同 test_weapon_rig.RigProbe 先例） ----

class RigProbe extends WeaponRig:
	var spawned: Array = []
	func _spawn(cfg: Dictionary) -> void:
		spawned.append(cfg)
