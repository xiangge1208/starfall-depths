class_name TestSkillsMageGuardian
extends GdUnitTestSuite
## M2-T11 B-2：法师·烬「奥术新星」+ 守护者·萄「生命潮汐」（GDD §6 技能表两行）
## + StatusComponent.apply_freeze 冻结接缝 + heroes.json mage/guardian 行。
## 数值出处：GDD §6（法师：CD 10s 耗蓝 20、120px 冰霜新星 24 伤 + 冻结 1.2s 精英减半、
## 强化 = 半径 +40% 且冻结 2s；守护者：CD 14s 耗蓝 30、立即回 2 HP + 3s 法阵 0.5 HP/s、
## 强化 = 法阵内额外 -20% 受伤）。整数 HP 口径：0.5 HP/s 经累加器满 1 落地（3s 共 1 HP）。
## 帧注入风格同 test_skills/test_summons：cast/tick(frame) 直驱，不经 _physics_process。

const NOVA_PATH := "res://core/player/skills/arcane_nova.gd"
const TIDE_PATH := "res://core/player/skills/life_tide.gd"

# ---- 夹具 ----

func _root() -> Node2D:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	return root

func _player(root: Node2D, at := Vector2(500, 100)) -> Player:
	var p: Player = auto_free(Player.new())
	p._test_init()
	p.position = at
	root.add_child(p)
	return p

## 入树假敌（"enemies" 组，brain_pos/global_position 对齐；同坚守/炮台习语）。
func _enemy(root: Node2D, at: Vector2, row_extra: Dictionary = {}) -> EnemyBase:
	var row := {"id": "nova_dummy", "hp": 30, "radius": 6.0}
	row.merge(row_extra, true)   # overwrite：row_extra 的 id/hp 等覆盖基础行
	var e := EnemyBase.new()
	e._test_init(row)
	e.brain_pos = at
	e.position = at
	root.add_child(e)
	e.add_to_group("enemies")
	return e

func _nova(p: Player, data: Dictionary = {}) -> SkillBase:
	var sk: SkillBase = auto_free(load(NOVA_PATH).new())
	sk.name = "Skill"
	sk.setup(p, data)
	p.add_child(sk)
	return sk

func _tide(p: Player, data: Dictionary = {}) -> SkillBase:
	var sk: SkillBase = auto_free(load(TIDE_PATH).new())
	sk.name = "Skill"
	sk.setup(p, data)
	p.add_child(sk)
	return sk

# ---- StatusComponent.apply_freeze 接缝（冻结语义并列消费方） ----

func test_apply_freeze_sets_window_for_normal_enemy() -> void:
	var s: StatusComponent = auto_free(StatusComponent.new())
	s.setup(2, false)
	s.apply_freeze(72, 100)                       # 1.2s（GDD §6 奥术新星）
	assert_bool(s.is_frozen(100)).is_true()
	assert_bool(s.is_frozen(171)).is_true()       # 100 + 72 - 1
	assert_bool(s.is_frozen(172)).is_false()      # 窗外恢复行动

func test_apply_freeze_boss_immune_reuses_is_frozen_semantics() -> void:
	var s: StatusComponent = auto_free(StatusComponent.new())
	s.setup(4, true)                              # Boss（status_component 冻结语义：Boss 免疫）
	s.apply_freeze(72, 100)
	assert_bool(s.is_frozen(100)).is_false()
	assert_bool(s.is_frozen(171)).is_false()

func test_apply_freeze_takes_max_never_shortens() -> void:
	var s: StatusComponent = auto_free(StatusComponent.new())
	s.setup(2, false)
	s.apply_freeze(100, 0)
	s.apply_freeze(50, 10)                        # 更短的续冻不得缩短既有窗（同 apply_iframes 习语）
	assert_bool(s.is_frozen(99)).is_true()
	assert_bool(s.is_frozen(100)).is_false()
	s.apply_freeze(80, 25)                        # 更长者正常延展（25 + 80 = 105）
	assert_bool(s.is_frozen(100)).is_true()
	assert_bool(s.is_frozen(104)).is_true()
	assert_bool(s.is_frozen(105)).is_false()     # 窗为半开 [now, now+ticks)

# ---- 奥术新星：命中 / 半径 / 冻结 ----

func test_nova_hits_and_freezes_enemies_within_120px() -> void:
	var root := _root()
	var p := _player(root)
	var sk := _nova(p)
	var inside := _enemy(root, Vector2(620, 100))      # 120px：边界内（含）
	var edge_out := _enemy(root, Vector2(621.5, 100))  # 121.5px：外
	assert_bool(sk.cast(100)).is_true()
	assert_int(inside.hp).is_equal(30 - 24)            # 24 固定伤（GDD §6）
	assert_int(edge_out.hp).is_equal(30)               # 半径外不受伤
	assert_int(p.energy).is_equal(100 - 20)            # 耗蓝 20
	var st := inside.status as StatusComponent
	assert_bool(st.is_frozen(100 + 71)).is_true()      # 冻结 1.2s = 72t
	assert_bool(st.is_frozen(100 + 72)).is_false()
	assert_bool((edge_out.status as StatusComponent).is_frozen(100 + 71)).is_false()

func test_nova_elite_freeze_halved() -> void:
	var root := _root()
	var p := _player(root)
	var sk := _nova(p)
	var elite := _enemy(root, Vector2(560, 100), {"id": "nova_elite", "elite_affixes": ["swift"]})
	assert_bool(sk.cast(100)).is_true()
	assert_int(elite.hp).is_equal(30 - 24)             # 伤害不减免（精英只减半冻结）
	var st := elite.status as StatusComponent
	assert_bool(st.is_frozen(100 + 35)).is_true()      # 1.2s × 0.5 = 36t（GDD §6 精英减半）
	assert_bool(st.is_frozen(100 + 36)).is_false()

func test_nova_boss_takes_damage_but_not_frozen() -> void:
	var root := _root()
	var p := _player(root)
	var sk := _nova(p)
	var boss := _enemy(root, Vector2(540, 100), {"id": "nova_boss", "hp": 100, "archetype": "boss"})
	assert_bool(sk.cast(100)).is_true()
	assert_int(boss.hp).is_equal(100 - 24)             # 伤害照常
	assert_bool((boss.status as StatusComponent).is_frozen(100)).is_false()   # 复用冻结语义：Boss 免疫

func test_nova_carries_ice_element_status_progress() -> void:
	var root := _root()
	var p := _player(root)
	var sk := _nova(p)
	var e := _enemy(root, Vector2(560, 100))
	assert_bool(sk.cast(100)).is_true()
	# 冰霜新星命中携带 ICE 元素（+1 层）：再补 1 层即触发冰缓（阈值 2 层）
	(e.status as StatusComponent).apply_hit(Elements.Id.ICE, 1, 200)
	assert_float((e.status as StatusComponent).action_speed_multiplier(210)).is_equal(0.7)

func test_nova_cooldown_600_and_energy_gate() -> void:
	var root := _root()
	var p := _player(root)
	var sk := _nova(p)
	p.energy = 19
	assert_bool(sk.can_cast(100)).is_false()           # 蓝耗门（20）
	p.energy = 100
	assert_bool(sk.cast(100)).is_true()
	assert_int(sk.cooldown_remaining(100)).is_equal(600)   # CD 10s（GDD §6）
	p.energy = 100                                     # 回满蓝仍被 CD 门拦
	assert_bool(sk.can_cast(100 + 599)).is_false()
	assert_bool(sk.cast(100 + 599)).is_false()
	assert_bool(sk.cast(100 + 600)).is_true()

func test_nova_upgraded_radius_168_and_freeze_120() -> void:
	var root := _root()
	var p := _player(root)
	var sk := _nova(p, {"upgraded": true})
	var mid := _enemy(root, Vector2(650, 100))         # 150px：仅升级版（120×1.4=168）内
	var out := _enemy(root, Vector2(670, 100))         # 170px：仍外
	assert_bool(sk.cast(100)).is_true()
	assert_int(mid.hp).is_equal(30 - 24)
	assert_int(out.hp).is_equal(30)
	var st := mid.status as StatusComponent
	assert_bool(st.is_frozen(100 + 119)).is_true()     # 升级冻结 2s = 120t（GDD §6 强化列）
	assert_bool(st.is_frozen(100 + 120)).is_false()

# ---- 生命潮汐：即时治疗 + 法阵周期/总量 ----

func test_tide_instant_heal_2_on_cast() -> void:
	var root := _root()
	var p := _player(root)
	var sk := _tide(p)
	p.hp = 4
	assert_bool(sk.cast(100)).is_true()
	assert_int(p.hp).is_equal(4 + 2)                   # 立即回 2 HP（GDD §6）
	assert_int(p.energy).is_equal(100 - 30)            # 耗蓝 30

func test_tide_circle_heals_one_per_second_accumulated() -> void:
	var root := _root()
	var p := _player(root)
	var sk := _tide(p)
	p.hp = 1                                           # 立即回 2 → 3；法阵再按累加器落地
	assert_bool(sk.cast(100)).is_true()
	assert_int(p.hp).is_equal(3)
	sk.tick(100 + 60)                                  # 第 1 秒：acc 0.5，不足 1 不落地
	assert_int(p.hp).is_equal(3)
	sk.tick(100 + 120)                                 # 第 2 秒：acc 满 1 → 治疗 1
	assert_int(p.hp).is_equal(4)
	sk.tick(100 + 180)                                 # 第 3 秒（法阵末拍含）：acc 0.5 不落地
	assert_int(p.hp).is_equal(4)                       # 法阵总治疗 = 1（0.5/s × 3s = 1.5 向下取整）
	sk.tick(100 + 240)                                 # 法阵已结束：不再治疗
	assert_int(p.hp).is_equal(4)

func test_tide_circle_requires_player_inside() -> void:
	var root := _root()
	var p := _player(root)
	var sk := _tide(p)
	p.hp = 1
	assert_bool(sk.cast(100)).is_true()                # 法阵锚定施放位置（500,100）
	p.hp = 3
	p.position = Vector2(700, 100)                     # 离开法阵（200px > 60px 半径）
	sk.tick(100 + 60)
	sk.tick(100 + 120)
	sk.tick(100 + 180)
	assert_int(p.hp).is_equal(3)                       # 阵外不治疗

func test_tide_upgraded_reduces_damage_only_in_circle() -> void:
	var root := _root()
	var p := _player(root)
	var sk := _tide(p, {"upgraded": true})
	p.shield = 0
	assert_bool(sk.cast(100)).is_true()                # 玩家在法阵中心
	sk.tick(150)
	p.take_hit_ctx({"amount": 5}, 150)                 # 阵内：floor(5×0.8)=4（-20%）
	assert_int(p.hp).is_equal(8 - 4)
	p.position = Vector2(700, 100)                     # 离开法阵
	sk.tick(300)                                       # 法阵已结束：减伤窗不再续期
	p.take_hit_ctx({"amount": 2}, 301)                 # 阵外：全额 2
	assert_int(p.hp).is_equal(8 - 4 - 2)

func test_tide_cooldown_840_and_energy_gate() -> void:
	var root := _root()
	var p := _player(root)
	var sk := _tide(p)
	p.energy = 29
	assert_bool(sk.can_cast(100)).is_false()           # 蓝耗门（30）
	p.energy = 100
	assert_bool(sk.cast(100)).is_true()
	assert_int(sk.cooldown_remaining(100)).is_equal(840)   # CD 14s（GDD §6）
	p.energy = 100
	assert_bool(sk.cast(100 + 839)).is_false()
	assert_bool(sk.cast(100 + 840)).is_true()

# ---- heroes.json mage/guardian 行（GDD §6 面板表 + engineer 行模式推导字段） ----

func test_five_heroes_loaded() -> void:
	assert_bool(GameDB.load_ok).is_true()
	assert_dict(GameDB.heroes).contains_keys("vanguard", "ranger", "engineer", "mage", "guardian")
	assert_int(GameDB.heroes.size()).is_equal(5)       # M2-T11：+mage/+guardian

func test_mage_row_values() -> void:
	var h := GameDB.get_hero("mage")
	assert_str(h.get("name", "")).is_equal("法师·烬")
	assert_int(h.get("hp", -1)).is_equal(5)            # GDD §6 面板表
	assert_int(h.get("shield", -1)).is_equal(5)
	assert_int(h.get("energy", -1)).is_equal(160)
	assert_float(h.get("speed", -1.0)).is_equal_approx(80.0, 0.001)
	assert_float(h.get("crit_chance", -1.0)).is_equal_approx(0.05, 0.0001)   # §7.1 基础 5%（被动无暴击加成）
	var sw: Array = h.get("start_weapons", [])
	assert_int(sw.size()).is_equal(1)
	assert_str(String(sw[0])).is_equal("xuetufazhang")  # 学徒法杖（GDD §6）
	assert_str(h.get("skill_script", "")).is_equal(NOVA_PATH)
	assert_int(h.get("skill_cd", -1)).is_equal(600)    # CD 10s
	assert_int(h.get("skill_energy", -2)).is_equal(20) # 耗蓝 20
	assert_str(h.get("passive_id", "")).is_equal("echo")
	assert_bool(h.get("has_defiance", true)).is_false()
	assert_str(h.get("skill_name", "")).is_equal("奥术新星")
	assert_bool(h.get("skill_desc", "").is_empty()).is_false()
	assert_bool(h.get("upgraded", true)).is_false()

func test_guardian_row_values() -> void:
	var h := GameDB.get_hero("guardian")
	assert_str(h.get("name", "")).is_equal("守护者·萄")
	assert_int(h.get("hp", -1)).is_equal(7)            # GDD §6 面板表
	assert_int(h.get("shield", -1)).is_equal(6)
	assert_int(h.get("energy", -1)).is_equal(130)
	assert_float(h.get("speed", -1.0)).is_equal_approx(80.0, 0.001)
	assert_float(h.get("crit_chance", -1.0)).is_equal_approx(0.05, 0.0001)
	var sw: Array = h.get("start_weapons", [])
	assert_int(sw.size()).is_equal(1)
	assert_str(String(sw[0])).is_equal("xinghuizhang")  # 星辉杖（GDD §6；弱化版无独立武器行）
	assert_str(h.get("skill_script", "")).is_equal(TIDE_PATH)
	assert_int(h.get("skill_cd", -1)).is_equal(840)    # CD 14s
	assert_int(h.get("skill_energy", -2)).is_equal(30) # 耗蓝 30
	assert_str(h.get("passive_id", "")).is_equal("blessing")
	assert_bool(h.get("has_defiance", true)).is_false()
	assert_str(h.get("skill_name", "")).is_equal("生命潮汐")
	assert_bool(h.get("skill_desc", "").is_empty()).is_false()
	assert_bool(h.get("upgraded", true)).is_false()

## GDD §6 守护者初始武器星辉杖为紫/橙（M2-T6 默认图鉴 locked）：初始武器是授予而非
## 掉落——get_weapon 可解析（equip 通路），但掉落池（GameDB.weapons）不得混入 locked 行。
func test_locked_epic_start_weapon_resolves_but_stays_out_of_drop_pool() -> void:
	var row: Dictionary = GameDB.weapons_all.get("xinghuizhang", {})
	assert_bool(row.is_empty()).is_false()
	assert_bool(bool(row.get("locked", false))).is_true()           # 紫橙默认锁定（M2-T6）
	assert_bool(GameDB.weapons.has("xinghuizhang")).is_false()      # 掉落池口径不变
	assert_bool(GameDB.get_weapon("xinghuizhang").is_empty()).is_false()   # 授予型引用可解析

# ---- HeroApplier 生产换装端到端（同 T8 engineer 先例） ----

func _applied_player(root: Node2D, hero_id: String) -> Player:
	var p: Player = auto_free(preload("res://core/player/player.tscn").instantiate())
	p.position = Vector2(500, 100)
	root.add_child(p)
	HeroApplier.apply(GameDB.get_hero(hero_id), p)
	return p

func test_hero_applier_mounts_mage_nova_and_cast_works() -> void:
	var root := _root()
	var p := _applied_player(root, "mage")
	var skill: Node = p.get_node("Skill")
	assert_str((skill.get_script() as Script).resource_path).is_equal(NOVA_PATH)
	assert_int(skill.get("cooldown_ticks")).is_equal(600)
	assert_int(skill.get("energy_cost")).is_equal(20)
	var e := _enemy(root, Vector2(560, 100))
	assert_int(p.energy).is_equal(160)                 # 装配即满蓝（法师 160）
	assert_bool(skill.cast(100)).is_true()
	assert_int(e.hp).is_equal(30 - 24)
	assert_int(p.energy).is_equal(160 - 20)

func test_hero_applier_mounts_guardian_tide_and_cast_works() -> void:
	var root := _root()
	var p := _applied_player(root, "guardian")
	var skill: Node = p.get_node("Skill")
	assert_str((skill.get_script() as Script).resource_path).is_equal(TIDE_PATH)
	assert_int(skill.get("cooldown_ticks")).is_equal(840)
	assert_int(skill.get("energy_cost")).is_equal(30)
	assert_str(String(p.weapon_rig.slots[0].get("id", ""))).is_equal("xinghuizhang")   # 初始武器经授予通路装备
	p.hp = 3
	assert_bool(skill.cast(100)).is_true()
	assert_int(p.hp).is_equal(3 + 2)                   # 立即回 2 HP
	assert_int(p.energy).is_equal(130 - 30)
