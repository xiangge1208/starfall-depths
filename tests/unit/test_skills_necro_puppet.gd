class_name TestSkillsNecroPuppet
extends GdUnitTestSuite
## M5 T5：死灵·骸（拾骨 + 起傀）（附录 L §3 第 11 行 + 强化行逐字）。
## - 拾骨：击杀积骸能 +1/击杀、上限 10（EventBus.enemy_killed 订阅于 setup）；
## - 起傀：CD 780t/20 蓝 + 耗 4 骸能召 1 只（每 4 具 1 只），在场 ≤2 只；
##   空骸能/骸能不足/满编任一门不过：不烧 CD、不扣蓝、不耗骸能；
## - 傀儡（PuppetSummon，turret 友方实体先例）：12 伤/8s 攻击节奏、60px 内最近敌、
##   12s 存活后消散（"expired"）、hp 归零被击毁（"destroyed"）、不进波次计数
##   （不进 "enemies" 组）；强化版被击毁自爆 24 AoE/48px（消散不引爆）。
## 遥测/音频随实现落点覆盖（bone_harvest/puppet_summon/puppet_burst 事件、
## puppet_summon/puppet_burst sfx 键见 test_audio_wiring 全量完备性回归）。
## 帧注入风格同 test_summons/test_skills_berserk_warlock：tick(frame) 直驱。

const PLAYER_SCENE := preload("res://core/player/player.tscn")
const SKILL_PATH := "res://core/player/skills/necro_puppet.gd"

# ---- 夹具 ----

func _root() -> Node2D:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	return root

func _player(root: Node2D) -> Player:
	var p: Player = auto_free(Player.new())
	p._test_init()
	p.position = Vector2(500, 100)
	p.hp_max = 6                                       # 附录 L §3 面板（6/3/130/80）
	p.hp = 6
	p.shield = 3
	p.energy_max = 130
	p.energy = 130
	root.add_child(p)
	return p

func _combat(root: Node2D) -> CombatSystem:
	var cs := CombatSystem.new(root, RngSvc.stream(0, "combat"))
	cs.crit_chance = 0.0
	auto_free(cs)
	root.add_child(cs)
	return cs

## 入树假敌（进 "enemies" 组并注册进 combat；brain_pos 与 global_position 对齐）。
func _enemy(root: Node2D, cs: CombatSystem, at: Vector2, hp := 100) -> EnemyBase:
	var e := EnemyBase.new()
	e._test_init({"id": "necro_dummy", "hp": hp, "radius": 6.0})
	e.brain_pos = at
	e.position = at
	root.add_child(e)
	e.add_to_group("enemies")
	cs.register_body(e, e.combat_faction())
	return e

## 装好死灵技能的玩家（生产路径同构：setup 数值行注入 + Skill 节点挂玩家）。
func _necro(root: Node2D, cs: CombatSystem, data: Dictionary = {}) -> NecroPuppet:
	var p := _player(root)
	p.combat = cs
	var sk := NecroPuppet.new()
	sk.name = "Skill"                                  # 生产路径：player.tscn 恒挂 "Skill"
	sk.setup(p, data)
	p.add_child(sk)
	return sk

func _necro_on(p: Player, data: Dictionary = {}) -> NecroPuppet:
	var sk := NecroPuppet.new()
	sk.name = "Skill"
	sk.setup(p, data)
	p.add_child(sk)
	return sk

func _first_puppet(root: Node2D) -> PuppetSummon:
	# queue_free 的退场体在空闲帧前仍在组内：按存活口径过滤（同 living_summons 语义）
	for node in root.get_tree().get_nodes_in_group("summons"):
		var s := node as PuppetSummon
		if s != null and not s.is_despawned() and not s.is_queued_for_deletion():
			return s
	return null

func _puppets(root: Node2D) -> Array[PuppetSummon]:
	var out: Array[PuppetSummon] = []
	for node in root.get_tree().get_nodes_in_group("summons"):
		var s := node as PuppetSummon
		if s != null and not s.is_despawned() and not s.is_queued_for_deletion():
			out.append(s)
	return out

func _bone_to(sk: NecroPuppet, n: int) -> void:
	for _i in n:
		EventBus.enemy_killed.emit("necro_dummy")


# ================================================================ 拾骨（骸被动）

func test_bone_harvest_kill_accumulates_and_caps_at_10() -> void:
	var p := _player(_root())
	var sk := _necro_on(p)
	for _i in 12:                                      # 12 击：前 10 积满，后 2 不溢出
		EventBus.enemy_killed.emit("necro_dummy")
	assert_int(sk.bone_count()).is_equal(10)           # 10 具满（附录 L §3）

func test_bone_harvest_null_player_no_accumulate() -> void:
	var sk: NecroPuppet = auto_free(NecroPuppet.new()) # 无绑定装配：击杀零积累
	sk.setup(null, {"id": "necro"})
	EventBus.enemy_killed.emit("necro_dummy")
	assert_int(sk.bone_count()).is_equal(0)

func test_harvest_accumulates_only_for_own_skill_state() -> void:
	# 骸能是技能实例状态（非玩家蓝量）：积累不进 energy。
	var root := _root()
	var sk := _necro(root, _combat(root))
	_bone_to(sk, 5)
	assert_int(sk.bone_count()).is_equal(5)
	assert_int(sk.player.energy).is_equal(130)         # 蓝量不受击杀积累影响


# ================================================================ 起傀（骸主动）

func test_data_row_numbers_flow_through_setup() -> void:
	var h := GameDB.get_hero("necro")
	assert_str(h["skill_script"]).is_equal(SKILL_PATH)
	assert_str(h["passive_id"]).is_equal("bone_harvest")
	var sk: NecroPuppet = auto_free(NecroPuppet.new())
	sk.setup(null, {"id": "necro", "cooldown_ticks": int(h["skill_cd"]),
		"energy_cost": int(h["skill_energy"])})
	assert_int(sk.cooldown_ticks).is_equal(780)        # CD 13s（附录 L §3）
	assert_int(sk.energy_cost).is_equal(20)            # 20 蓝

func test_null_player_placeholder_smoke_unchanged() -> void:
	# test_heroes 占位冒烟同口径：无绑定装配下 cast 过框架门为 true（骸能门直通零漂移）。
	var sk: NecroPuppet = auto_free(NecroPuppet.new())
	sk.setup(null, {"id": "necro", "cooldown_ticks": 780, "energy_cost": 20})
	assert_bool(sk.cast(0)).is_true()
	assert_int(sk.cooldown_remaining(1)).is_equal(779)

func test_empty_bone_gate_blocks_without_burning_cd_or_energy() -> void:
	var root := _root()
	var cs := _combat(root)
	var sk := _necro(root, cs)
	assert_int(sk.bone_count()).is_equal(0)
	assert_bool(sk.can_cast(100)).is_false()           # 空骸能：不可发动
	assert_bool(sk.cast(100)).is_false()
	assert_int(sk.player.energy).is_equal(130)         # 不扣蓝
	assert_int(sk.cooldown_remaining(100)).is_equal(0) # 不烧 CD
	assert_int(sk.bone_count()).is_equal(0)

func test_insufficient_bone_gate_blocks_below_four() -> void:
	var root := _root()
	var sk := _necro(root, _combat(root))
	_bone_to(sk, 3)                                    # 3 具 < 4：不够一只
	assert_bool(sk.can_cast(100)).is_false()
	assert_bool(sk.cast(100)).is_false()
	assert_int(sk.bone_count()).is_equal(3)

func test_cast_spends_4_bone_20_energy_and_deploys_puppet() -> void:
	var root := _root()
	var cs := _combat(root)
	var p := _player(root)
	p.combat = cs
	var sk := _necro_on(p)
	_bone_to(sk, 4)
	assert_bool(sk.cast(100)).is_true()
	assert_int(sk.bone_count()).is_equal(0)            # 耗 4 骸能
	assert_int(p.energy).is_equal(110)                 # 扣 20 蓝
	var puppet := _first_puppet(root)
	assert_object(puppet).is_not_null()
	assert_bool(puppet.is_in_group("summons")).is_true()
	assert_bool(puppet.is_in_group("enemies")).is_false()   # 不进波次计数
	assert_vector(puppet.global_position).is_equal_approx(p.global_position,
		Vector2(0.001, 0.001))                         # 落在玩家脚下
	assert_object(puppet.combat).is_same(cs)           # 挂房间 combat 引用（契约）
	assert_object(puppet.player).is_same(p)            # 玩家引用注入（契约）
	assert_int(puppet.hp).is_equal(10)                 # 议定耐久（炮台生命先例）
	assert_int(puppet.hp_max).is_equal(10)
	assert_bool(puppet.upgraded).is_false()            # 非强化：死亡不自爆
	# 已登记为玩家阵营战斗体（敌方可攻击可击杀）
	var found := false
	for body in cs.bodies_in_radius(puppet.global_position, 200.0, Projectile.Faction.PLAYER):
		if body == puppet:
			found = true
	assert_bool(found).is_true()
	assert_int(sk.cooldown_remaining(100)).is_equal(780)   # CD 13s 自成功拍起算
	assert_bool(sk.cast(101)).is_false()               # CD 门（骸能已尽同样拒）

func test_cast_upgraded_flows_into_puppet_row() -> void:
	var root := _root()
	var sk := _necro(root, _combat(root), {"upgraded": true})
	_bone_to(sk, 4)
	assert_bool(sk.cast(100)).is_true()
	assert_bool(_first_puppet(root).upgraded).is_true()

func test_bone_currency_two_puppets_from_full_ten_across_cd() -> void:
	# 满骸能 10 = 两次施放（4+4），CD 780t 错峰：首只 720t 存活期尽先消散。
	var root := _root()
	var cs := _combat(root)
	var sk := _necro(root, cs)
	_bone_to(sk, 10)
	assert_bool(sk.cast(100)).is_true()                # 耗 4：余 6
	assert_int(sk.bone_count()).is_equal(6)
	var first := _first_puppet(root)
	assert_bool(sk.cast(200)).is_false()               # CD 门（骸能足也不行）
	first.tick(100 + 720)                              # 首只存活期尽消散（无头直驱生产物理拍）
	assert_bool(first.is_queued_for_deletion()).is_true()
	assert_bool(sk.cast(880)).is_true()                # 780t 后：再耗 4：余 2
	assert_int(sk.bone_count()).is_equal(2)
	assert_int(_puppets(root).size()).is_equal(1)      # 场上仅新傀儡
	assert_bool(sk.cast(1000)).is_false()              # 余 2 骸 < 4：拒

func test_puppet_cap_two_on_field_blocks_cast_without_cost() -> void:
	# 在场 ≥2 拒召不顶替（议定：骸能稀缺资源，满编门为规格字面守卫；CD 780t > 存活
	# 720t 自然施放不可达满编，门为双保险）。直驱 _deploy 造满编（不经骸能扣减）。
	var root := _root()
	var cs := _combat(root)
	var sk := _necro(root, cs)
	_bone_to(sk, 10)
	sk._deploy(100)
	sk._deploy(100)
	assert_int(_puppets(root).size()).is_equal(2)      # 满编 2 只
	assert_bool(sk.can_cast(100)).is_false()
	assert_bool(sk.cast(100)).is_false()
	assert_int(sk.bone_count()).is_equal(10)           # 满编拒召不耗骸能
	assert_int(sk.player.energy).is_equal(130)         # 不扣蓝
	assert_int(sk.cooldown_remaining(100)).is_equal(0) # 不烧 CD
	var leaving := _first_puppet(root)
	leaving.despawn("replaced")                        # 退 1 只 → 门开（骸能足即过）
	assert_int(_puppets(root).size()).is_equal(1)
	assert_bool(sk.can_cast(100)).is_true()            # 骸能 10 ≥ 4、在场 1 < 2
	leaving.queue_free()


# ================================================================ 傀儡实体（PuppetSummon）

func test_puppet_expires_after_720_ticks() -> void:
	var root := _root()
	var sk := _necro(root, _combat(root))
	_bone_to(sk, 4)
	assert_bool(sk.cast(100)).is_true()
	var puppet := _first_puppet(root)
	var reasons: Array = []
	puppet.despawned.connect(func(reason: String) -> void: reasons.append(reason))
	puppet.tick(100 + 719)
	assert_bool(puppet.is_queued_for_deletion()).is_false()   # 12s 内存活
	puppet.tick(100 + 720)
	assert_bool(puppet.is_queued_for_deletion()).is_true()    # 存活期尽 → 消散
	assert_array(reasons).contains_exactly(["expired"])

func test_puppet_slams_nearest_enemy_12_every_8s() -> void:
	var root := _root()
	var cs := _combat(root)
	var sk := _necro(root, cs)
	_bone_to(sk, 4)
	assert_bool(sk.cast(100)).is_true()
	var puppet := _first_puppet(root)
	var near := _enemy(root, cs, puppet.global_position + Vector2(40, 0), 100)
	var far := _enemy(root, cs, puppet.global_position + Vector2(50, 0), 100)
	puppet.tick(100 + 479)
	assert_int(near.hp).is_equal(100)                  # 8s 节拍未到：不击
	puppet.tick(100 + 480)
	assert_int(near.hp).is_equal(88)                   # 12 伤（附录 L §3）
	assert_int(far.hp).is_equal(100)                   # 只打最近 1 体
	puppet.tick(100 + 719)
	assert_int(near.hp).is_equal(88)                   # 下一节拍 1060t > 存活 820t：
	assert_int(far.hp).is_equal(100)                   # 每只存活期恰 1 击（规格双数字直推，头注披露）
	puppet.tick(100 + 720)
	assert_bool(puppet.is_queued_for_deletion()).is_true()   # 存活期尽 → 消散

func test_puppet_targets_nearest_within_60px_only() -> void:
	var root := _root()
	var cs := _combat(root)
	var sk := _necro(root, cs)
	_bone_to(sk, 4)
	assert_bool(sk.cast(100)).is_true()
	var puppet := _first_puppet(root)
	var outside := _enemy(root, cs, puppet.global_position + Vector2(100, 0), 100)
	var near := _enemy(root, cs, puppet.global_position + Vector2(30, 0), 100)
	var mid := _enemy(root, cs, puppet.global_position + Vector2(50, 0), 100)
	puppet.tick(100 + 480)
	assert_int(near.hp).is_equal(88)                   # 最近敌（30px < 50px）
	assert_int(mid.hp).is_equal(100)
	assert_int(outside.hp).is_equal(100)               # 100px 越界敌不打

func test_puppet_destroyed_when_hp_depleted_and_unregistered() -> void:
	var root := _root()
	var cs := _combat(root)
	var sk := _necro(root, cs)
	_bone_to(sk, 4)
	assert_bool(sk.cast(100)).is_true()
	var puppet := _first_puppet(root)
	var reasons: Array = []
	puppet.despawned.connect(func(reason: String) -> void: reasons.append(reason))
	puppet.take_hit({"amount": 10})                    # 敌弹击毁（hp 10 归零）
	assert_bool(puppet.is_queued_for_deletion()).is_true()
	assert_array(reasons).contains_exactly(["destroyed"])
	var found := false
	for body in cs.bodies_in_radius(puppet.global_position, 200.0, Projectile.Faction.PLAYER):
		if body == puppet:
			found = true
	assert_bool(found).is_false()                      # 退场即注销战斗体


# ================================================================ 强化：死亡自爆 24 AoE

func test_upgraded_puppet_self_destructs_24_aoe_on_destroyed() -> void:
	var root := _root()
	var cs := _combat(root)
	var sk := _necro(root, cs, {"upgraded": true})
	_bone_to(sk, 4)
	assert_bool(sk.cast(100)).is_true()
	var puppet := _first_puppet(root)
	var in_radius := _enemy(root, cs, puppet.global_position + Vector2(30, 0), 100)
	var out_radius := _enemy(root, cs, puppet.global_position + Vector2(80, 0), 100)
	puppet.take_hit({"amount": 10})                    # 被击毁 → 自爆
	assert_bool(puppet.is_queued_for_deletion()).is_true()
	assert_int(in_radius.hp).is_equal(76)              # 24 AoE（附录 L 强化行）
	assert_int(out_radius.hp).is_equal(100)            # 48px 爆心外不波及

func test_base_puppet_death_no_burst() -> void:
	var root := _root()
	var cs := _combat(root)
	var sk := _necro(root, cs)                         # 非强化
	_bone_to(sk, 4)
	assert_bool(sk.cast(100)).is_true()
	var puppet := _first_puppet(root)
	var near := _enemy(root, cs, puppet.global_position + Vector2(30, 0), 100)
	puppet.take_hit({"amount": 10})
	assert_bool(puppet.is_queued_for_deletion()).is_true()
	assert_int(near.hp).is_equal(100)                  # 基础版死亡无自爆

func test_upgraded_puppet_expiry_no_burst() -> void:
	# 「死亡自爆」严格取击毁语义：存活期尽消散（expired）不引爆（消散≠死亡）。
	var root := _root()
	var cs := _combat(root)
	var sk := _necro(root, cs, {"upgraded": true})
	_bone_to(sk, 4)
	assert_bool(sk.cast(100)).is_true()
	var puppet := _first_puppet(root)
	var near := _enemy(root, cs, puppet.global_position + Vector2(30, 0), 100)
	puppet.tick(100 + 720)                             # 自然消散
	assert_bool(puppet.is_queued_for_deletion()).is_true()
	assert_int(near.hp).is_equal(100)                  # 消散不自爆


# ================================================================ 生产订阅路径

func test_harvest_and_cast_via_eventbus_in_tree() -> void:
	# 生产链路端到端：入树玩家 + 真实数据行装配 → EventBus 广播积骸 → 施放召傀。
	var root := _root()
	var cs := _combat(root)
	var p: Player = PLAYER_SCENE.instantiate() as Player
	p.position = Vector2(500, 100)
	root.add_child(p)
	p.combat = cs
	p.energy_max = 130
	p.energy = 130
	var h := GameDB.get_hero("necro")
	var sk := _necro_on(p, {"id": "necro", "cooldown_ticks": int(h["skill_cd"]),
		"energy_cost": int(h["skill_energy"])})
	for _i in 4:
		EventBus.enemy_killed.emit("necro_dummy")      # 生产击杀广播 → 拾骨
	assert_int(sk.bone_count()).is_equal(4)
	assert_bool(sk.cast(Engine.get_physics_frames())).is_true()
	assert_int(p.energy).is_equal(110)
	assert_object(_first_puppet(root)).is_not_null()
