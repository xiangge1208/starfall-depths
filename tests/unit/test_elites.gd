class_name TestElites
extends GdUnitTestSuite

## m1-t12：精英词缀 + 小 Boss×2 + 原型映射改造。
## 帧参数全部注入（同 test_enemy_ai 约定），不经真实时钟。

const ARCHETYPE_BASE := "res://core/enemies/archetypes/"
const ELITE_BASE := "res://core/enemies/elites/"

## 玩家替身（PlayerProxy 契约：brain_pos + take_hit），受击记录供断言。
class SpyPlayer extends Node2D:
	var hits: Array = []
	var brain_pos := Vector2.ZERO
	func take_hit(ctx: Dictionary) -> void:
		hits.append(ctx)

## 战斗替身：只记录 spawn_projectile 调用（计数弹幕大师 volley）。
class SpyCombat extends CombatSystem:
	var spawned: Array = []
	func spawn_projectile(cfg: Dictionary) -> void:
		spawned.append(cfg)

## 召唤物替身：可写 hp（分裂断言用）、无 state（视为存活）。
class StubMinion extends Node2D:
	var hp := 0

# ---- 原型映射改造（重构回归：对外契约不变） ----

func test_archetype_map_mounts_preloaded_scripts() -> void:
	for arch in ["charger", "shooter", "orbiter", "suicide", "dummy"]:
		var e: EnemyBase = auto_free(EnemyBase.new())
		e._test_init({"id": "t", "archetype": arch, "hp": 10})
		var s := e.get_script() as Script
		assert_str(s.resource_path).is_equal(ARCHETYPE_BASE + arch + ".gd")
		assert_bool(e.row == e.get("row")).is_true()       # 行/成员经 Object.set 落到新实例
		assert_int(e.hp).is_equal(10)
		assert_int(e.hp_max).is_equal(10)

func test_unknown_archetype_stays_on_base_and_warns() -> void:
	var e: EnemyBase = auto_free(EnemyBase.new())
	e._test_init({"id": "t", "archetype": "nope", "hp": 10})
	var s := e.get_script() as Script
	assert_str(s.resource_path).is_equal("res://core/enemies/enemy_base.gd")

func test_boss_subclass_is_not_remounted() -> void:
	var b: BossBase = auto_free(BossBase.new())
	b._test_init({"id": "boss_test", "hp": 800, "radius": 14.0, "phases": [1.0, 0.6]})
	var s := b.get_script() as Script
	assert_str(s.resource_path).is_equal("res://core/enemies/boss_base.gd")   # 二次换装守卫保持
	assert_int(b.hp).is_equal(800)

# ---- 词缀数值（TDD：迅捷/坚甲断言） ----

func test_swift_multiplies_all_row_speed_keys() -> void:
	var e: EnemyBase = auto_free(EnemyBase.new())
	var row := {"id": "t", "archetype": "charger", "hp": 10, "speed": 100, "walk_speed": 40, "dash_speed": 200.0}
	e._test_init(row)
	EliteAffix.apply(e, "swift")
	assert_float(float(e.row["speed"])).is_equal_approx(130.0, 0.001)
	assert_float(float(e.row["walk_speed"])).is_equal_approx(52.0, 0.001)
	assert_float(float(e.row["dash_speed"])).is_equal_approx(260.0, 0.001)
	assert_bool(row == e.row).is_false()   # 与传入行解耦（不污染共享表）

func test_armored_triples_hp_and_max() -> void:
	var e: EnemyBase = auto_free(EnemyBase.new())
	e._test_init({"id": "t", "archetype": "dummy", "hp": 20})
	EliteAffix.apply(e, "armored")
	assert_int(e.hp).is_equal(60)
	assert_int(e.hp_max).is_equal(60)

func test_unknown_affix_is_ignored() -> void:
	var e: EnemyBase = auto_free(EnemyBase.new())
	e._test_init({"id": "t", "archetype": "dummy", "hp": 20})
	EliteAffix.apply(e, "bogus")
	assert_int(e.hp).is_equal(20)
	assert_bool(bool(e.get("split_on_death"))).is_false()

func test_affix_table_has_six_entries() -> void:
	assert_int(EliteAffix.AFFIXES.size()).is_equal(6)

# ---- 分裂（die 后 2 子体，hp 减半，经 spawn_callback 接缝） ----

func test_splitter_spawns_two_half_hp_children_at_death() -> void:
	var e: EnemyBase = auto_free(EnemyBase.new())
	e._test_init({"id": "vine_charger", "archetype": "charger", "hp": 20, "radius": 6.0, "windup_ticks": 30, "dash_ticks": 27, "dash_speed": 285, "dash_cooldown_ticks": 90})
	var calls: Array = []
	e.set("spawn_callback", func(row_id: String, pos: Vector2) -> Node:
		var m := StubMinion.new()
		calls.append({"row_id": row_id, "pos": pos, "minion": m})
		return m)
	EliteAffix.apply(e, "splitter")
	assert_bool(e.split_on_death).is_true()
	e.take_hit({"amount": 99, "is_crit": false, "element": Elements.Id.NONE, "from": Vector2.ZERO})
	assert_int(e.state).is_equal(EnemyBase.State.DEAD)
	assert_int(calls.size()).is_equal(2)
	for i in 2:
		assert_str(String(calls[i]["row_id"])).is_equal("vine_charger")   # 原型同 row
		assert_float((calls[i]["pos"] as Vector2).distance_to(e.brain_pos)).is_equal_approx(6.0, 0.001)
		assert_int((calls[i]["minion"] as StubMinion).hp).is_equal(10)    # hp ×0.5
		(calls[i]["minion"] as StubMinion).free()                         # 替身自清（非 auto_free 通路）

func test_splitter_without_callback_dies_cleanly() -> void:
	var e: EnemyBase = auto_free(EnemyBase.new())
	e._test_init({"id": "vine_charger", "archetype": "charger", "hp": 20, "windup_ticks": 30, "dash_ticks": 27, "dash_speed": 285, "dash_cooldown_ticks": 90})
	e.set("split_on_death", true)          # 接缝未注入：静默跳过
	e.take_hit({"amount": 99, "is_crit": false, "element": Elements.Id.NONE, "from": Vector2.ZERO})
	assert_int(e.state).is_equal(EnemyBase.State.DEAD)

# ---- 虹吸（接触伤害命中自回等量 hp，≤ hp_max） ----

func test_leech_heals_on_contact_hit() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var e: EnemyBase = auto_free(EnemyBase.new())
	e.position = Vector2.ZERO
	root.add_child(e)
	e.setup({"id": "t", "archetype": "dummy", "hp": 30, "contact_dmg": 3, "radius": 6.0})
	e.set("hp", 10)                        # 先扣到 10/30
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2.ZERO           # 与敌同点 → 接触命中
	e.set("player_ref", spy)
	EliteAffix.apply(e, "leech")
	assert_bool(e.leech).is_true()
	for _i in 3:
		await get_tree().physics_frame
	assert_int(spy.hits.size()).is_between(1, 3)
	assert_int(e.hp).is_equal(mini(10 + 3 * spy.hits.size(), e.hp_max))   # 自回等量、封顶 hp_max
	for h in spy.hits:
		assert_int(h["amount"]).is_equal(3)

func test_no_leech_keeps_hp() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var e: EnemyBase = auto_free(EnemyBase.new())
	e.position = Vector2.ZERO
	root.add_child(e)
	e.setup({"id": "t", "archetype": "dummy", "hp": 30, "contact_dmg": 3, "radius": 6.0})
	e.set("hp", 10)
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2.ZERO
	e.set("player_ref", spy)
	for _i in 3:
		await get_tree().physics_frame
	assert_int(spy.hits.size()).is_between(1, 3)
	assert_int(e.hp).is_equal(10)          # 无虹吸：不掉不回

# ---- 狂暴（50% 血阈值 + windup ×0.7） ----

func test_berserk_threshold_strict_below_half() -> void:
	var e: EnemyBase = auto_free(EnemyBase.new())
	e._test_init({"id": "t", "archetype": "charger", "hp": 100})
	e.set("hp", 51)
	assert_bool(e.berserk_active()).is_false()   # 51%：未激活
	e.set("hp", 50)
	assert_bool(e.berserk_active()).is_false()   # 恰 50%：未激活（严格 <）
	e.set("hp", 49)
	assert_bool(e.berserk_active()).is_true()    # 49%：激活

func test_berserk_scales_windup_in_charger_and_shooter() -> void:
	var c: EnemyBase = auto_free(EnemyBase.new())
	c._test_init({"id": "t", "archetype": "charger", "hp": 18, "windup_ticks": 30, "dash_ticks": 27, "dash_speed": 285, "dash_cooldown_ticks": 90})
	assert_int(c._windup_ticks(30)).is_equal(30)     # 满血：不变
	c.set("hp", 8)                                    # 8×2=16 < 18 → 狂暴
	assert_int(c._windup_ticks(30)).is_equal(21)      # ×0.7
	var s: EnemyBase = auto_free(EnemyBase.new())
	s._test_init({"id": "t", "archetype": "shooter", "hp": 16, "windup_ticks": 30, "cd_ticks": 108, "speed": 60})
	s.set("hp", 7)                                    # 7×2=14 < 16 → 狂暴
	assert_int(s._windup_ticks(30)).is_equal(21)
	# charger 行为层：ENGAGE 首拍进入蓄力即取缩短后的窗口
	c.set("hp", 18)
	c.on_player_seen(0)
	for f in range(1, 26): c.brain_tick(f)
	assert_int(int(c.get("_phase_left"))).is_equal(30)

# ---- 弹幕大师（shooter volley = 1 + barrage_extra） ----

func test_barrage_extra_expands_shooter_volley() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var rng := RngSvc.stream(0, "combat")
	var cs := SpyCombat.new(root, rng)
	root.add_child(cs)
	var e: EnemyBase = auto_free(EnemyBase.new())
	e.position = Vector2.ZERO
	root.add_child(e)
	e.setup({"id": "t", "archetype": "shooter", "hp": 16, "speed": 60, "windup_ticks": 30, "cd_ticks": 108})
	e.combat = cs
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(170, 0)       # 游走区间内
	e.set("player_ref", spy)
	e.on_player_seen(0)
	for f in range(1, 25): e.brain_tick(f)
	for f in range(25, 120):
		e.brain_tick(f)
		if e.fired_this_tick:
			break
	assert_int(cs.spawned.size()).is_equal(1)   # 基线：单发
	# 弹幕大师 ×2 → 3 发对称扇形
	var cs2 := SpyCombat.new(root, rng)
	root.add_child(cs2)
	var e2: EnemyBase = auto_free(EnemyBase.new())
	e2.position = Vector2.ZERO
	root.add_child(e2)
	e2.setup({"id": "t", "archetype": "shooter", "hp": 16, "speed": 60, "windup_ticks": 30, "cd_ticks": 108})
	e2.combat = cs2
	e2.set("player_ref", spy)
	e2.set("barrage_extra", 2)
	e2.on_player_seen(0)
	for f in range(1, 25): e2.brain_tick(f)
	var fired := false
	for f in range(25, 120):
		e2.brain_tick(f)
		if e2.fired_this_tick:
			fired = true
			break
	assert_bool(fired).is_true()
	assert_int(cs2.spawned.size()).is_equal(3)  # 1 + 2

# ---- 双刀蜥人（三连冲锋：dash → 36t → dash → 60t → 36t 大前摇 → dash） ----

const COMBO_ROW := {"id": "shuangdao_lizardman", "archetype": "combo_charger", "hp": 180,
	"windup_ticks": 30, "dash_ticks": 20, "dash_speed": 300.0, "dash_cooldown_ticks": 120}

func test_combo_charger_mounts_elite_script() -> void:
	var e: EnemyBase = auto_free(EnemyBase.new())
	e._test_init(COMBO_ROW)
	var s := e.get_script() as Script
	assert_str(s.resource_path).is_equal(ELITE_BASE + "combo_charger.gd")

## 逐拍分类位移：蓄力/停顿窗零位移，三段冲锋窗各 20t×5px=100px（参数取行 walk/dash 字段）。
func test_combo_charger_three_dash_pattern() -> void:
	var e: EnemyBase = auto_free(EnemyBase.new())
	e._test_init(COMBO_ROW)
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = e.brain_pos + Vector2(200, 0)
	e.set("player_ref", spy)
	e.on_player_seen(0)
	var moved: Dictionary = {}             # frame -> 该拍位移
	var last := e.brain_pos
	for f in range(1, 370):
		e.brain_tick(f)
		moved[f] = last.distance_to(e.brain_pos)
		last = e.brain_pos
	# 静止窗：首蓄力 25..55（31 拍）、36t 停顿 76..111、60t 停顿 132..191、
	# 36t 大前摇 192..227、三段后冷却 248..367
	for win in [[25, 55], [76, 111], [132, 191], [192, 227], [248, 367]]:
		for f in range(int(win[0]), int(win[1]) + 1):
			assert_float(moved[f]).is_equal(0.0)
	# 三段冲锋窗各 20 拍、每拍 5px（300/60）、总计 100px
	for win in [[56, 75], [112, 131], [228, 247]]:
		var traveled := 0.0
		for f in range(int(win[0]), int(win[1]) + 1):
			assert_float(moved[f]).is_equal_approx(5.0, 0.001)
			traveled += moved[f]
		assert_float(traveled).is_equal_approx(100.0, 0.1)

## 第三段大前摇进入拍重新锁定方向（B.3 最大输出窗语义：可走位躲第三段）。
func test_combo_charger_reaims_on_big_windup() -> void:
	var e: EnemyBase = auto_free(EnemyBase.new())
	e._test_init(COMBO_ROW)
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = e.brain_pos + Vector2(200, 0)
	e.set("player_ref", spy)
	e.on_player_seen(0)
	for f in range(1, 190): e.brain_tick(f)
	spy.brain_pos = e.brain_pos + Vector2(0, -200)   # 二段停顿末改位
	for f in range(190, 228): e.brain_tick(f)        # 191 拍进大前摇：重锁方向
	var before := e.brain_pos
	for f in range(228, 248): e.brain_tick(f)        # 第三段冲刺
	var step := (e.brain_pos - before) / 20.0
	assert_float(step.y).is_equal_approx(-5.0, 0.001)   # 向新方向 -y 冲刺
	assert_float(step.x).is_equal_approx(0.0, 0.001)

# ---- 自爆王虫（召唤环：转换拍首环 + 每 300t + 存活 ≤4） ----

var _summon_calls: Array = []
var _summon_made: Array = []

func _record_summon(row_id: String, pos: Vector2) -> Node:
	var m := StubMinion.new()
	_summon_calls.append({"row_id": row_id, "pos": pos, "minion": m})
	_summon_made.append(m)
	return m

func _reset_summon_recording() -> void:
	_summon_calls = []
	_summon_made = []

func test_zibao_summon_ring_cadence_and_cap() -> void:
	_reset_summon_recording()
	var e: EnemyBase = auto_free(EnemyBase.new())
	e._test_init({"id": "zibao_wangchong", "archetype": "zibao_wangchong", "hp": 180, "speed": 0, "fuse_ticks": 30, "aoe_radius": 72, "aoe_dmg": 16, "delayed_death_ticks": 60})
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(100, 0)       # >14px：引信不燃，王虫原地（speed 0）
	e.set("player_ref", spy)
	e.set("spawn_callback", Callable(self, "_record_summon"))
	var s := e.get_script() as Script
	assert_str(s.resource_path).is_equal(ELITE_BASE + "zibao_wangchong.gd")
	e.on_player_seen(0)
	for f in range(1, 25): e.brain_tick(f)
	assert_int(_summon_calls.size()).is_equal(4)          # 转换拍即召一环 4 只
	for c in _summon_calls:
		assert_str(String(c["row_id"])).is_equal("kuli_bug")
		assert_float((c["pos"] as Vector2).distance_to(e.brain_pos)).is_equal_approx(40.0, 0.001)
	for f in range(25, 324): e.brain_tick(f)              # 300t 未到
	assert_int(_summon_calls.size()).is_equal(4)
	e.brain_tick(324)                                     # 转换拍后恰 300t：满员不补
	assert_int(_summon_calls.size()).is_equal(4)
	_summon_made[0].free()                                 # 死 2 只 → 下窗补召 2
	_summon_made[1].free()
	for f in range(325, 624): e.brain_tick(f)
	assert_int(_summon_calls.size()).is_equal(4)
	e.brain_tick(624)
	assert_int(_summon_calls.size()).is_equal(6)          # 夹到上限 ≤4 存活
	for m in _summon_made:
		if is_instance_valid(m):
			m.free()                                       # 替身自清

func test_zibao_without_callback_ticks_cleanly() -> void:
	_reset_summon_recording()
	var e: EnemyBase = auto_free(EnemyBase.new())
	e._test_init({"id": "zibao_wangchong", "archetype": "zibao_wangchong", "hp": 180, "speed": 0, "fuse_ticks": 30, "aoe_radius": 72, "aoe_dmg": 16, "delayed_death_ticks": 60})
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(100, 0)
	e.set("player_ref", spy)
	e.on_player_seen(0)
	for f in range(1, 330): e.brain_tick(f)               # 接缝未注入：节拍照走，不炸不崩
	assert_int(e.state).is_not_equal(EnemyBase.State.DEAD)

# ---- 延迟大爆（die() 延迟分支 → DelayedBlast 60t 后按 M0 爆炸语义结算） ----

const ZIBAO_BLAST_ROW := {"id": "zibao_wangchong", "archetype": "zibao_wangchong", "hp": 180,
	"speed": 0, "fuse_ticks": 30, "aoe_radius": 72, "aoe_dmg": 16, "delayed_death_ticks": 60}

func test_zibao_death_spawns_delayed_blast_detonating_at_60t() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var rng := RngSvc.stream(0, "combat")
	var cs := CombatSystem.new(root, rng)
	root.add_child(cs)
	var e: EnemyBase = auto_free(EnemyBase.new())
	e.position = Vector2.ZERO
	root.add_child(e)
	e.setup(ZIBAO_BLAST_ROW)
	e.combat = cs
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2.ZERO             # 爆点 72px 内
	e.set("player_ref", spy)
	e.take_hit({"amount": 999, "is_crit": false, "element": Elements.Id.NONE, "from": Vector2.ZERO})
	assert_int(e.state).is_equal(EnemyBase.State.DEAD)
	assert_int(spy.hits.size()).is_equal(0)  # 延迟分支：不即刻爆
	var blast: DelayedBlast = null
	for child in cs.get_children():
		blast = child as DelayedBlast
	assert_object(blast).is_not_null()
	for _i in 59:
		blast.tick()
	assert_int(spy.hits.size()).is_equal(0)  # 60t 未到：不结算
	blast.tick()
	assert_int(spy.hits.size()).is_equal(1)  # 恰 60t：aoe_dmg 经 take_hit（无敌帧节流归玩家侧）
	assert_int(spy.hits[0]["amount"]).is_equal(16)
	assert_bool(bool(spy.hits[0]["is_crit"])).is_false()

func test_delayed_blast_beyond_radius_no_hit() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var rng := RngSvc.stream(0, "combat")
	var cs := CombatSystem.new(root, rng)
	root.add_child(cs)
	var e: EnemyBase = auto_free(EnemyBase.new())
	e.position = Vector2(100, 0)             # 爆点在 (100,0)
	root.add_child(e)
	e.setup(ZIBAO_BLAST_ROW)
	e.combat = cs
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2.ZERO             # 距爆点 100 > 72
	e.set("player_ref", spy)
	e.take_hit({"amount": 999, "is_crit": false, "element": Elements.Id.NONE, "from": Vector2(100, 0)})
	var blast: DelayedBlast = null
	for child in cs.get_children():
		blast = child as DelayedBlast
	assert_object(blast).is_not_null()
	for _i in 60:
		blast.tick()
	assert_int(spy.hits.size()).is_equal(0)  # 爆而不中

# ---- 体型 1.25（战斗半径 ×1.25 + 视觉缩放） ----

func test_body_scale_scales_combat_radius_and_visual() -> void:
	var e: EnemyBase = auto_free(EnemyBase.new())
	e._test_init({"id": "t", "archetype": "dummy", "hp": 10, "radius": 6.0, "body_scale": 1.25})
	assert_float(e.combat_radius()).is_equal_approx(7.5, 0.001)
	var e2: EnemyBase = auto_free(EnemyBase.new())
	e2.setup({"id": "t", "archetype": "dummy", "hp": 10, "radius": 6.0, "body_scale": 1.25})
	assert_vector(e2.scale).is_equal_approx(Vector2(1.25, 1.25), Vector2(0.001, 0.001))
	var e3: EnemyBase = auto_free(EnemyBase.new())
	e3.setup({"id": "t", "archetype": "dummy", "hp": 10, "radius": 6.0})
	assert_float(e3.combat_radius()).is_equal_approx(6.0, 0.001)   # 无 body_scale：原行为
	assert_vector(e3.scale).is_equal_approx(Vector2.ONE, Vector2(0.001, 0.001))

# ---- 行驱动词缀（setup 末尾应用；小 Boss 数据契约） ----

func test_row_elite_affixes_applied_at_setup_end() -> void:
	var e: EnemyBase = auto_free(EnemyBase.new())
	e.setup({"id": "t", "archetype": "shooter", "hp": 180, "speed": 100, "windup_ticks": 30, "cd_ticks": 108,
		"elite_affixes": ["armored", "swift"]})
	assert_int(e.hp).is_equal(540)           # 坚甲：180×3
	assert_int(e.hp_max).is_equal(540)
	assert_float(float(e.row["speed"])).is_equal_approx(130.0, 0.001)   # 迅捷：100×1.3

func test_miniboss_rows_data_contract() -> void:
	# data/enemies.json 小 Boss 行（附录 B.3，HP 180）：掉落与体型为 T10/房间的数据契约
	var table: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/enemies.json"))
	var lizard: Dictionary = table["shuangdao_lizardman"]
	assert_int(int(lizard["hp"])).is_equal(180)
	assert_str(String(lizard["drops"])).is_equal("weapon,hearts2")
	assert_float(float(lizard["body_scale"])).is_equal_approx(1.25, 0.001)
	assert_int(lizard["elite_affixes"].size()).is_equal(2)
	var zibao: Dictionary = table["zibao_wangchong"]
	assert_int(int(zibao["hp"])).is_equal(180)
	assert_int(int(zibao["delayed_death_ticks"])).is_equal(60)
	assert_str(String(zibao["drops"])).is_equal("weapon,hearts2")
	assert_float(float(zibao["body_scale"])).is_equal_approx(1.25, 0.001)
	assert_int(zibao["elite_affixes"].size()).is_equal(2)
