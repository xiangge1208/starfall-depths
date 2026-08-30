class_name TestEnemyAI
extends GdUnitTestSuite

## 玩家替身（PlayerProxy 契约：brain_pos + take_hit），受击记录供断言。
class SpyPlayer extends Node2D:
	var hits: Array = []
	var brain_pos := Vector2.ZERO
	func take_hit(ctx: Dictionary) -> void:
		hits.append(ctx)

func test_state_transitions() -> void:
	var e: EnemyBase = auto_free(EnemyFactory.create({"id": "crossbowman", "archetype": "shooter", "hp": 16, "contact_dmg": 3, "speed": 60, "windup_ticks": 30, "cd_ticks": 108}))
	e.on_player_seen(0)
	assert_int(e.state).is_equal(EnemyBase.State.ALERT)
	e.brain_tick(23)
	assert_int(e.state).is_equal(EnemyBase.State.ALERT)     # 0.4s=24 ticks 前摇
	e.brain_tick(24)
	assert_int(e.state).is_equal(EnemyBase.State.ENGAGE)

func test_shooter_cadence() -> void:
	var e: EnemyBase = auto_free(EnemyFactory.create({"id": "crossbowman", "archetype": "shooter", "hp": 16, "contact_dmg": 3, "speed": 60, "windup_ticks": 30, "cd_ticks": 108}))
	e.on_player_seen(0)
	for f in range(1, 25): e.brain_tick(f)
	var shots := 0
	for f in range(25, 300):
		e.brain_tick(f)
		if e.fired_this_tick: shots += 1
	# 0.4s 警觉后首射，随后每 1.8s：约 (300-24)/108 + 1 ≈ 3
	assert_int(shots).is_between(2, 4)

func test_enemy_fire_bullet_consumes_row_radius_and_source() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var combat := CombatSystem.new(root, RngSvc.stream(1, "enemy_radius_test"))
	root.add_child(combat)
	var e: EnemyBase = auto_free(EnemyFactory.create({
		"id": "crossbowman", "name": "弩兵", "archetype": "shooter", "hp": 16,
		"bullet_dmg": 3, "bullet_speed": 110, "bullet_life_seconds": 2.5,
		"bullet_radius": 4.5,
	}))
	e.combat = combat
	e.fire_bullet(Vector2.RIGHT * 100.0, 12)
	assert_int(combat.pool.active.size()).is_equal(1)
	assert_float((combat.pool.active[0] as Projectile).radius).is_equal(4.5)
	var meta: Dictionary = combat._proj_meta[(combat.pool.active[0] as Projectile).get_instance_id()]
	assert_str(String(meta["source_name"])).is_equal("弩兵")
	assert_str(String(meta["attack_name"])).is_equal("弹幕")

func test_suicide_fuse_and_explosion_params() -> void:
	var e: EnemyBase = auto_free(EnemyFactory.create({"id": "kuli_bug", "archetype": "suicide", "hp": 12, "speed": 95, "fuse_ticks": 30, "aoe_radius": 40, "aoe_dmg": 8}))
	e.on_player_seen(0)
	for f in range(1, 25): e.brain_tick(f)
	e.brain_tick(24 + 30)     # ENGAGE 后贴身引信 30 ticks
	assert_bool(e.exploded).is_true()

func test_charger_dash_distance() -> void:
	var e: EnemyBase = auto_free(EnemyFactory.create({"id": "vine_charger", "archetype": "charger", "hp": 18, "contact_dmg": 4, "walk_speed": 45, "dash_speed": 285, "windup_ticks": 30, "dash_ticks": 27, "dash_cooldown_ticks": 90}))
	e.on_player_seen(0)
	for f in range(1, 25):
		e.brain_tick(f)                   # 第 24 帧进入 ENGAGE
	for f in range(25, 55):
		e.brain_tick(f)                   # 前摇 30 ticks（蓄力原地）
	var traveled := 0.0
	var last := e.brain_pos
	for f in range(55, 55 + 27):          # 冲刺 27 ticks = 27×285/60 ≈ 128px（附录 B.2 冲 8 瓦片）
		e.brain_tick(f)
		traveled += last.distance_to(e.brain_pos)
		last = e.brain_pos
	assert_float(traveled).is_equal_approx(128.0, 8.0)

# ---- m0-final fix 回归 ----

## fix4（附录 B.1「死亡即刻爆」）：苦力虫受击致死同样引爆——40px 内替身恰好吃 1×8。
func test_kuli_death_by_damage_explodes_on_player_within_aoe() -> void:
	var e: EnemyBase = auto_free(EnemyFactory.create({"id": "kuli_bug", "archetype": "suicide", "hp": 12, "speed": 95, "fuse_ticks": 30, "aoe_radius": 40, "aoe_dmg": 8}))
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2.ZERO             # 与 e.brain_pos 同点（40px 内）
	e.player_ref = spy
	e.take_hit({"amount": 99, "is_crit": false, "element": Elements.Id.NONE, "from": Vector2.ZERO})
	assert_int(e.state).is_equal(EnemyBase.State.DEAD)
	assert_int(spy.hits.size()).is_equal(1)
	assert_int(spy.hits[0]["amount"]).is_equal(8)
	assert_bool(spy.hits[0]["is_crit"]).is_false()
	assert_int(int(spy.hits[0]["element"])).is_equal(Elements.Id.NONE)

## fix4：40px 外受击致死——爆而不中。
func test_kuli_death_by_damage_beyond_aoe_no_hit() -> void:
	var e: EnemyBase = auto_free(EnemyFactory.create({"id": "kuli_bug", "archetype": "suicide", "hp": 12, "speed": 95, "fuse_ticks": 30, "aoe_radius": 40, "aoe_dmg": 8}))
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(50, 0)           # 50px > aoe_radius 40
	e.set("player_ref", spy)
	e.take_hit({"amount": 99, "is_crit": false, "element": Elements.Id.NONE, "from": Vector2.ZERO})
	assert_int(e.state).is_equal(EnemyBase.State.DEAD)
	assert_int(spy.hits.size()).is_equal(0)

## fix4 去重：引信致死（exploded=true → die()）恰好一次爆炸，不再双重结算。
func test_kuli_fuse_death_explodes_exactly_once() -> void:
	var e: EnemyBase = auto_free(EnemyFactory.create({"id": "kuli_bug", "archetype": "suicide", "hp": 12, "speed": 95, "fuse_ticks": 30, "aoe_radius": 40, "aoe_dmg": 8}))
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2.ZERO             # 贴身（0 < 14px）：转换拍即点燃
	e.set("player_ref", spy)
	e.on_player_seen(0)
	for f in range(1, 25): e.brain_tick(f)
	e.brain_tick(24 + 30)                    # 引信 30 ticks 到点
	assert_bool(e.exploded).is_true()
	assert_int(spy.hits.size()).is_equal(1)  # 单一爆炸源：引信不再单独结算
	assert_int(spy.hits[0]["amount"]).is_equal(8)

## fix3：SHATTER AoE 不含触发体自身、跳过本拍已死体；范围内他体吃 1.5× 触发伤。
## 走真实 tick 通路：真实树物理帧驱动 EnemyBase._physics_process 消费 resonance_event。
func test_shatter_aoe_excludes_self_and_dead() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var rng := RngSvc.stream(0, "combat")
	var cs := CombatSystem.new(root, rng)
	root.add_child(cs)
	var trig: EnemyBase = auto_free(EnemyBase.new())
	trig.position = Vector2(100, 100)
	root.add_child(trig)
	trig.setup({"id": "trigger", "hp": 100, "radius": 6.0})
	trig.combat = cs
	cs.register_body(trig, trig.combat_faction())
	var other: EnemyBase = auto_free(EnemyBase.new())
	other.position = Vector2(130, 100)       # 30px，90px AoE 内
	root.add_child(other)
	other.setup({"id": "victim", "hp": 100, "radius": 6.0})
	other.combat = cs
	cs.register_body(other, other.combat_faction())
	var corpse: EnemyBase = auto_free(EnemyBase.new())
	corpse.position = Vector2(160, 100)      # 60px，AoE 内但已死
	root.add_child(corpse)
	corpse.setup({"id": "corpse", "hp": 100, "radius": 6.0})
	cs.register_body(corpse, corpse.combat_faction())
	corpse.state = EnemyBase.State.DEAD      # 模拟同拍先死（快照内已 DEAD）
	# 火+冰 → SHATTER（帧号按 StatusComponent 阈值/ICD 注入，不依赖真实时钟）
	var f0 := Engine.get_physics_frames()
	var st: StatusComponent = trig.status
	st.apply_hit(Elements.Id.FIRE, 8, f0)
	st.apply_hit(Elements.Id.FIRE, 8, f0 + 10)     # 燃烧激活
	st.apply_hit(Elements.Id.ICE, 8, f0 + 20)
	st.apply_hit(Elements.Id.ICE, 8, f0 + 30)      # 火+冰 → 淬爆事件置位
	for _i in 5:
		await get_tree().physics_frame       # 敌 tick 消费 resonance_event → _shatter_aoe
	assert_int(other.hp).is_equal(100 - 12)  # 1.5×8=12 落在他体
	assert_int(trig.hp).is_equal(100)        # 触发体自身不免（燃烧 DoT 未到跳点，无掉血）
	assert_int(corpse.hp).is_equal(100)      # 已死体跳过

# ---- M2-T9：敌人 40 全录 + 契约复查 + 新原型行为抽样（附录 B.1/B.2/B.3） ----
# 帧约定（同上文）：ALERT 24 拍转 ENGAGE，首个 _engage 拍 = 25；
# windup 30 的状态机原型首发拍 = 25 + 30 = 55（M2_FIRST_ATTACK_TICK）。
# 写法约束（gdUnit 6.2.1 源解析器）：测试体内不自调用带参助手（会被解析器吞掉
# 其后全部函数，M2 节内联展开）；失败上下文用 join 字符串指纹承载。

const M2_FIRST_ATTACK_TICK := 55         # 25 + windup 30
const M2_TELEGRAPH_MIN_TICKS := 24       # 0.4s 预警下限（设计 §12：弹幕生成前必须预警）
const M2_BULLET_SPEED_CAP := 150         # 敌弹速度上限 150 px/s（设计 §12）

## 名录以 ArtLookup.ENEMY_TEXTURES 预置的附录 B id 为准（m1-t28 已全量登记）。
const M2_COMMON_IDS := ["kuli_bug", "cave_bat", "crossbowman", "mud_slime"]
const M2_A1_IDS := ["vine_charger", "mushroom_spore", "hardshell_turtle", "wing_lizard",
	"thorn_turret", "spore_flower", "stone_boar", "ruin_archer", "moss_slime",
	"glowbug_swarm", "old_tree_guard", "seed_pitcher"]
const M2_A2_IDS := ["crystal_bat", "ice_mage", "magnet_golem", "ghost_jelly", "frost_crab",
	"crystal_rat", "rock_crystal_turret", "crystal_summoner", "prism_ranger", "ice_spider",
	"echo_lurker", "crystal_dragon"]
const M2_A3_IDS := ["lava_hound", "ash_shooter", "firerain_priest", "magma_slime",
	"obsidian_guard", "sulfur_moth", "lava_turret", "ember_summoner", "scorch_stomper",
	"flame_lich", "magma_wyvern", "starmarrow_blob"]
const M2_MINIBOSS_IDS := ["shuangdao_lizardman", "zibao_wangchong", "undead_gunner",
	"stone_shield_monk", "volt_spider", "marsh_toad"]

## 附录 B.1/B.2 逐行 [hp, 触, 弹] 三元组（数值唯一出处；A2 弹=基准+2、A3 弹=基准+4）。
const M2_ROSTER_TRIPLES := {
	"kuli_bug": [12, 0, 0], "cave_bat": [10, 3, 0], "crossbowman": [16, 3, 3],
	"mud_slime": [20, 4, 0],
	"vine_charger": [18, 4, 0], "mushroom_spore": [20, 3, 3],
	"hardshell_turtle": [45, 5, 0], "wing_lizard": [14, 3, 2],
	"thorn_turret": [30, 0, 4], "spore_flower": [26, 3, 0],
	"stone_boar": [28, 6, 0], "ruin_archer": [18, 3, 3],
	"moss_slime": [22, 4, 0], "glowbug_swarm": [8, 0, 0],
	"old_tree_guard": [40, 5, 4], "seed_pitcher": [20, 3, 3],
	"crystal_bat": [24, 5, 5], "ice_mage": [44, 4, 5],
	"magnet_golem": [90, 6, 0], "ghost_jelly": [30, 5, 5],
	"frost_crab": [100, 7, 0], "crystal_rat": [18, 4, 0],
	"rock_crystal_turret": [66, 0, 6], "crystal_summoner": [57, 4, 0],
	"prism_ranger": [40, 4, 5], "ice_spider": [26, 4, 0],
	"echo_lurker": [48, 5, 5], "crystal_dragon": [88, 8, 0],
	"lava_hound": [87, 9, 0], "ash_shooter": [79, 6, 7],
	"firerain_priest": [97, 6, 7], "magma_slime": [145, 8, 0],
	"obsidian_guard": [220, 10, 0], "sulfur_moth": [29, 6, 0],
	"lava_turret": [145, 0, 8], "ember_summoner": [116, 6, 0],
	"scorch_stomper": [194, 11, 0], "flame_lich": [106, 6, 7],
	"magma_wyvern": [87, 8, 7], "starmarrow_blob": [242, 7, 7],
}

## 总数 40 = B.1 通用 4 + B.2 每生态 12×3；id 集逐一在表。
func test_m2_roster_counts_40_regular_enemies() -> void:
	var missing := []
	var total := 0
	for group in [M2_COMMON_IDS, M2_A1_IDS, M2_A2_IDS, M2_A3_IDS]:
		for id in group:
			if not GameDB.enemies.has(String(id)):
				missing.append(String(id))
			else:
				total += 1
	assert_str(", ".join(PackedStringArray(missing))).is_equal("")
	assert_int(total).is_equal(40)

## B.3 小 Boss 池 6：M1 已有 2 + 本卡 4；数值口径同既有行（hp 180 / 体型 1.25 /
## 固定 2 词缀 / 掉落 weapon,hearts2；A2 400 / A3 870 为楼层侧缩放，不落多行）。
func test_m2_miniboss_pool_six_rows() -> void:
	var missing := []
	var bad := []
	for id in M2_MINIBOSS_IDS:
		if not GameDB.enemies.has(String(id)):
			missing.append(String(id))
			continue
		var row: Dictionary = GameDB.enemies[String(id)]
		var ok := int(row["hp"]) == 180 and absf(float(row["body_scale"]) - 1.25) < 0.001 \
			and (row["elite_affixes"] as Array).size() == 2 \
			and String(row["drops"]) == "weapon,hearts2"
		if not ok:
			bad.append(String(id))
	assert_str(", ".join(PackedStringArray(missing))).is_equal("")
	assert_str(", ".join(PackedStringArray(bad))).is_equal("")

## 契约复查（46 行逐行）：弹速 ≤150；开火者/冲锋者 windup ≥24t；自爆引信 ≥24t。
func test_m2_contract_bullet_speed_cap_and_telegraph() -> void:
	var fast := []
	var hasty := []
	var short_fuse := []
	var checked := 0
	for group in [M2_COMMON_IDS, M2_A1_IDS, M2_A2_IDS, M2_A3_IDS, M2_MINIBOSS_IDS]:
		for id in group:
			if not GameDB.enemies.has(String(id)):
				continue
			var row: Dictionary = GameDB.enemies[String(id)]
			checked += 1
			var sid := String(row["id"])
			var speed := int(row.get("bullet_speed", 0))
			var windup := int(row.get("windup_ticks", 0))
			var dash := int(row.get("dash_speed", 0))
			var fuse := int(row.get("fuse_ticks", 0))
			if speed > M2_BULLET_SPEED_CAP:
				fast.append(sid)
			if (speed > 0 or dash > 0) and windup < M2_TELEGRAPH_MIN_TICKS:
				hasty.append(sid)
			if fuse > 0 and fuse < M2_TELEGRAPH_MIN_TICKS:
				short_fuse.append(sid)
	assert_int(checked).is_equal(46)
	assert_str(", ".join(PackedStringArray(fast))).is_equal("")
	assert_str(", ".join(PackedStringArray(hasty))).is_equal("")
	assert_str(", ".join(PackedStringArray(short_fuse))).is_equal("")

## 逐字转录校验：40 行 hp/接触伤/弹伤三元组 = 附录 B.1/B.2 表值（指纹含 id 便于定位）。
func test_m2_appendix_values_verbatim_triples() -> void:
	var bad := []
	var checked := 0
	for group in [M2_COMMON_IDS, M2_A1_IDS, M2_A2_IDS, M2_A3_IDS]:
		for id in group:
			if not GameDB.enemies.has(String(id)):
				continue
			var row: Dictionary = GameDB.enemies[String(id)]
			checked += 1
			var sid := String(row["id"])
			if not M2_ROSTER_TRIPLES.has(sid):
				bad.append(sid + ":not-in-table")
				continue
			var want: Array = M2_ROSTER_TRIPLES[sid]
			var got := "%s=%d/%d/%d" % [sid, int(row["hp"]),
				int(row.get("contact_dmg", 0)), int(row.get("bullet_dmg", 0))]
			var exp := "%s=%d/%d/%d" % [sid, int(want[0]), int(want[1]), int(want[2])]
			if got != exp:
				bad.append("%s got=%s want=%s" % [sid, got, exp])
	assert_int(checked).is_equal(40)
	assert_str(", ".join(PackedStringArray(bad))).is_equal("")

## 工厂映射完备：46 行（40 常规 + 6 小 Boss）都能经 preload 映射构造（fail-closed 不触发）。
func test_m2_all_roster_rows_construct_via_factory() -> void:
	var bad := []
	for group in [M2_COMMON_IDS, M2_A1_IDS, M2_A2_IDS, M2_A3_IDS, M2_MINIBOSS_IDS]:
		for id in group:
			var row: Dictionary = GameDB.enemies.get(String(id), {})
			if row.is_empty():
				bad.append(String(id) + ":missing")
				continue
			var e := EnemyFactory.create(row)
			if e == null:
				bad.append(String(id) + ":no-archetype")
			else:
				e.free()   # create() 未入树：直接 free（非 auto_free 通路）
	assert_str(", ".join(PackedStringArray(bad))).is_equal("")

# ---- 新原型行为抽样（注入帧；SpyPlayer 同上文，M2SpyCombat 同 test_elites 约定） ----

class M2SpyCombat extends CombatSystem:
	var spawned: Array = []
	func spawn_projectile(cfg: Dictionary) -> void:
		spawned.append(cfg)

var _m2_spawn_calls: Array = []

func _m2_record_spawn(row_id: String, pos: Vector2, row_override: Dictionary = {}) -> Node:
	var m := Node2D.new()
	_m2_spawn_calls.append({"row_id": row_id, "pos": pos, "row": row_override, "minion": m})
	return m

func _m2_free_minions() -> void:
	for c in _m2_spawn_calls:
		var m: Node2D = c["minion"]
		if is_instance_valid(m):
			m.free()
	_m2_spawn_calls = []

## 分裂（B.1 泥浆史莱姆）：死亡经 spawn_callback 出 2 子体，hp=split_child_hp(6)，
## 子体行 split_generations=0（不再链式分裂）。
func test_m2_splitter_mud_slime_death_split() -> void:
	_m2_spawn_calls = []
	var e: EnemyBase = auto_free(EnemyFactory.create(GameDB.enemies["mud_slime"]))
	assert_object(e).is_not_null()
	e.set("spawn_callback", Callable(self, "_m2_record_spawn"))
	e.take_hit({"amount": 99, "is_crit": false, "element": Elements.Id.NONE, "from": Vector2.ZERO})
	assert_int(e.state).is_equal(EnemyBase.State.DEAD)
	assert_int(_m2_spawn_calls.size()).is_equal(2)
	var bad := []
	for c in _m2_spawn_calls:
		var child_row: Dictionary = c["row"]
		var ok := String(c["row_id"]) == "mud_slime" and int(child_row["hp"]) == 6 \
			and int(child_row.get("split_generations", 0)) == 0
		if not ok:
			bad.append(str(c["row_id"]))
	assert_str(", ".join(PackedStringArray(bad))).is_equal("")
	_m2_free_minions()

## 重装（B.2 硬壳龟）：正面减伤 80%（45 血吃正面 10 伤只掉 2），背面全伤。
func test_m2_heavy_hardshell_turtle_frontal_block() -> void:
	var e: EnemyBase = auto_free(EnemyFactory.create(GameDB.enemies["hardshell_turtle"]))
	assert_object(e).is_not_null()
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(100, 0)      # 朝 +x 走 → 面向 +x
	e.set("player_ref", spy)
	e.on_player_seen(0)
	for f in range(1, 26):
		e.brain_tick(f)                   # 24 转 ENGAGE，25 拍确立面向
	assert_int(e.hp).is_equal(45)
	e.take_hit({"amount": 10, "is_crit": false, "element": Elements.Id.NONE,
		"from": Vector2(200, 0)})        # 正面来弹：10×(1-0.8)=2
	assert_int(e.hp).is_equal(43)
	e.take_hit({"amount": 10, "is_crit": false, "element": Elements.Id.NONE,
		"from": Vector2(-100, 0)})       # 背面：全伤
	assert_int(e.hp).is_equal(33)

## 炮台（B.2 荆棘炮台）：固定不动，windup 30 后 3 连发（首发 55、间隔 6t）。
func test_m2_turret_thorn_turret_burst() -> void:
	var e: EnemyBase = auto_free(EnemyFactory.create(GameDB.enemies["thorn_turret"]))
	assert_object(e).is_not_null()
	var origin := e.brain_pos
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(100, 0)
	e.set("player_ref", spy)
	e.on_player_seen(0)
	var fire_ticks: Array[int] = []
	for f in range(1, 200):
		e.brain_tick(f)
		if e.fired_this_tick:
			fire_ticks.append(f)
	assert_int(fire_ticks.size()).is_equal(3)            # 一轮 3 连发（200t 内单轮）
	var gaps_ok := true
	for i in range(1, fire_ticks.size()):
		gaps_ok = gaps_ok and fire_ticks[i] - fire_ticks[i - 1] == 6
	assert_bool(gaps_ok).is_true()
	assert_int(fire_ticks[0]).is_equal(M2_FIRST_ATTACK_TICK)
	var drift := origin.distance_to(e.brain_pos)
	assert_float(drift).is_less(0.01)                    # 固定不动

## 召唤（B.2 孢子召唤花）：转换拍召 1 苦力虫，此后每 240t，存活上限 3。
func test_m2_summoner_spore_flower_cadence_and_cap() -> void:
	_m2_spawn_calls = []
	var e: EnemyBase = auto_free(EnemyFactory.create(GameDB.enemies["spore_flower"]))
	assert_object(e).is_not_null()
	e.set("spawn_callback", Callable(self, "_m2_record_spawn"))
	e.on_player_seen(0)
	for f in range(1, 25):
		e.brain_tick(f)
	assert_int(_m2_spawn_calls.size()).is_equal(1)       # 转换拍即召第 1 只
	assert_str(String(_m2_spawn_calls[0]["row_id"])).is_equal("kuli_bug")
	for f in range(25, 264):
		e.brain_tick(f)
	assert_int(_m2_spawn_calls.size()).is_equal(1)       # 240t 未到不补
	e.brain_tick(264)
	assert_int(_m2_spawn_calls.size()).is_equal(2)
	for f in range(265, 745):
		e.brain_tick(f)                                  # 504 窗补到 3；744 窗满员封顶
	assert_int(_m2_spawn_calls.size()).is_equal(3)
	for f in range(745, 900):
		e.brain_tick(f)
	assert_int(_m2_spawn_calls.size()).is_equal(3)       # 上限 3，不再补
	_m2_free_minions()

## 弹幕（B.2 冰晶法师）：windup 30 后一圈 8 发冰缓环弹（45° 均布，slow 0.3/60t）。
func test_m2_barrage_ice_mage_ring_volley() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs: CombatSystem = auto_free(M2SpyCombat.new(root, RngSvc.stream(1, "m2_barrage")))
	var e: EnemyBase = auto_free(EnemyFactory.create(GameDB.enemies["ice_mage"]))
	assert_object(e).is_not_null()
	e.set("combat", cs)
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(100, 0)
	e.set("player_ref", spy)
	e.on_player_seen(0)
	for f in range(1, M2_FIRST_ATTACK_TICK):
		e.brain_tick(f)
	assert_int((cs as M2SpyCombat).spawned.size()).is_equal(0)   # 预警期零弹
	e.brain_tick(M2_FIRST_ATTACK_TICK)
	assert_int((cs as M2SpyCombat).spawned.size()).is_equal(8)
	var angles := []
	var bad := []
	for c in (cs as M2SpyCombat).spawned:
		var cfg: Dictionary = c
		var speed := Vector2(cfg["vel"]).length()
		if int(cfg["damage"]) != 5 or absf(float(cfg["slow_pct"]) - 0.3) > 0.001 \
				or absf(speed - 95.0) > 0.5:
			bad.append(str(cfg["damage"]))
		angles.append(Vector2.RIGHT.angle_to(cfg["vel"]))
	assert_str(", ".join(PackedStringArray(bad))).is_equal("")
	angles.sort()
	var spacing_ok := true
	for i in range(1, angles.size()):
		spacing_ok = spacing_ok and absf(angles[i] - angles[i - 1] - TAU / 8.0) < 0.01
	assert_bool(spacing_ok).is_true()

## 游走（B.2 飞行翼蜥）：绕行体带弹（弹 2）时周期开火——windup 30 预警后单发。
func test_m2_orbiter_wing_lizard_fires_with_telegraph() -> void:
	var e: EnemyBase = auto_free(EnemyFactory.create(GameDB.enemies["wing_lizard"]))
	assert_object(e).is_not_null()
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(100, 0)
	e.set("player_ref", spy)
	e.on_player_seen(0)
	var fire_ticks: Array[int] = []
	for f in range(1, 120):
		e.brain_tick(f)
		if e.fired_this_tick:
			fire_ticks.append(f)
	assert_int(fire_ticks.size()).is_greater_equal(1)
	assert_int(fire_ticks[0]).is_greater_equal(M2_FIRST_ATTACK_TICK)  # 预警期满才出弹

## 冲锋（B.2 晶背龙蜥）：冲撞结束自晕 60t（1s 输出窗）。
func test_m2_charger_crystal_dragon_self_stun_after_dash() -> void:
	var e: EnemyBase = auto_free(EnemyFactory.create(GameDB.enemies["crystal_dragon"]))
	assert_object(e).is_not_null()
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(100, 0)
	e.set("player_ref", spy)
	e.on_player_seen(0)
	var dash_end_frame := -1
	for f in range(1, 130):
		e.brain_tick(f)
		if e.stun_until > f:                            # windup30+dash30 后出现自晕
			dash_end_frame = f
			break
	var expected_end := 25 + 30 + 30
	assert_int(dash_end_frame).is_equal(expected_end)
	var stun_len := e.stun_until - dash_end_frame
	assert_int(stun_len).is_equal(60)

## 射手（B.3 灰烬射手 3 连发点射）：windup 后 3 发（首发 55、间隔 8t）。
func test_m2_shooter_ash_shooter_triple_burst() -> void:
	var e: EnemyBase = auto_free(EnemyFactory.create(GameDB.enemies["ash_shooter"]))
	assert_object(e).is_not_null()
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(100, 0)
	e.set("player_ref", spy)
	e.on_player_seen(0)
	var fire_ticks: Array[int] = []
	for f in range(1, 100):
		e.brain_tick(f)
		if e.fired_this_tick:
			fire_ticks.append(f)
	assert_int(fire_ticks.size()).is_equal(3)
	var gaps_ok := true
	for i in range(1, fire_ticks.size()):
		gaps_ok = gaps_ok and fire_ticks[i] - fire_ticks[i - 1] == 8
	assert_bool(gaps_ok).is_true()

# ---- B.3 小 Boss ×4 行为抽样 ----

## 石盾武僧：正面格挡一切（正面 10 伤 → 0 落血）；正面近战 → 破势（自晕输出窗），
## 破势窗内正面武器伤全额落地。
func test_m2_stone_shield_monk_blocks_front_melee_breaks_guard() -> void:
	var e: EnemyBase = auto_free(EnemyFactory.create(GameDB.enemies["stone_shield_monk"]))
	assert_object(e).is_not_null()
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(100, 0)      # 面向 +x
	e.set("player_ref", spy)
	e.on_player_seen(0)
	for f in range(1, 26):
		e.brain_tick(f)
	var hp0 := int(e.hp)                 # 词缀行 hp 为 180×坚甲倍率，取运行时值
	e.take_hit({"amount": 10, "is_crit": false, "element": Elements.Id.NONE,
		"from": Vector2(200, 0), "source_type": "weapon"})
	assert_int(e.hp).is_equal(hp0)       # 正面全格挡
	e.take_hit({"amount": 10, "is_crit": false, "element": Elements.Id.NONE,
		"from": Vector2(200, 0), "source_type": "melee"})
	assert_int(e.hp).is_equal(hp0)       # 破势一击本身不落血
	assert_int(e.stun_until).is_greater(25)              # 破势自晕（输出窗）
	e.take_hit({"amount": 10, "is_crit": false, "element": Elements.Id.NONE,
		"from": Vector2(200, 0), "source_type": "weapon"})
	assert_int(e.hp).is_equal(hp0 - 10)  # 破势窗内正面全伤

## 亡灵枪手（对枪）：玩家不开火它绝不开火；玩家出弹后应答（≥30t 预警，行弹形 4 伤/110 速）。
func test_m2_undead_gunner_duel_answers_player_fire() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := CombatSystem.new(root, RngSvc.stream(1, "m2_gunner"))
	root.add_child(cs)
	var e: EnemyBase = auto_free(EnemyFactory.create(GameDB.enemies["undead_gunner"]))
	assert_object(e).is_not_null()
	e.set("combat", cs)
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(100, 0)
	e.set("player_ref", spy)
	e.on_player_seen(0)
	var idle_bullets := 0
	for f in range(1, 120):
		e.brain_tick(f)
		for p in cs.pool.active:
			if p.faction == Projectile.Faction.ENEMY:
				idle_bullets += 1
	assert_int(idle_bullets).is_equal(0)                 # 玩家未开火 → 零弹
	cs.spawn_projectile({"pos": Vector2.ZERO, "vel": Vector2(200, 0), "damage": 3,
		"faction": Projectile.Faction.PLAYER, "element": Elements.Id.NONE,
		"pierce": 0, "bounce": 0, "life_seconds": 2.0, "radius": 3.0})
	var answered_at := -1
	for f in range(120, 200):
		e.brain_tick(f)
		var enemy_bullets := 0
		for p in cs.pool.active:
			if p.faction == Projectile.Faction.ENEMY:
				enemy_bullets += 1
		if enemy_bullets > 0:
			answered_at = f
			break
	var earliest := 120 + 30
	assert_int(answered_at).is_greater_equal(earliest)    # 应答也要 ≥30t 预警
	assert_int(answered_at).is_less(165)
	var bolt: Projectile = null
	for p in cs.pool.active:
		if p.faction == Projectile.Faction.ENEMY:
			bolt = p
	assert_object(bolt).is_not_null()
	assert_int(bolt.damage).is_equal(4)                  # 行弹形（替身无 rig → 行值）
	var bolt_speed := bolt.vel.length()
	assert_float(bolt_speed).is_equal_approx(110.0, 0.5)

## 电磁蛛：电弧链需小蛛存活——转换拍召 2 只冰蛛；链窗放出 SHOCK 电弧弹；
## 小蛛全灭后链断（到补召窗前零放电）；补召窗（300t）重新召满后链恢复。
func test_m2_volt_spider_chain_broken_without_spiderlings() -> void:
	_m2_spawn_calls = []
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs: CombatSystem = auto_free(M2SpyCombat.new(root, RngSvc.stream(1, "m2_volt")))
	var e: EnemyBase = auto_free(EnemyFactory.create(GameDB.enemies["volt_spider"]))
	assert_object(e).is_not_null()
	e.set("combat", cs)
	e.set("spawn_callback", Callable(self, "_m2_record_spawn"))
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(100, 0)
	e.set("player_ref", spy)
	e.on_player_seen(0)
	for f in range(1, 25):
		e.brain_tick(f)
	assert_int(_m2_spawn_calls.size()).is_equal(2)       # 转换拍召 2 只小蛛
	var ids_ok := true
	for c in _m2_spawn_calls:
		ids_ok = ids_ok and String(c["row_id"]) == "ice_spider"
	assert_bool(ids_ok).is_true()
	for f in range(25, 214):
		e.brain_tick(f)
	assert_int((cs as M2SpyCombat).spawned.size()).is_greater_equal(1)   # 小蛛存活 → 链在场
	assert_int(int((cs as M2SpyCombat).spawned[0]["element"])).is_equal(Elements.Id.SHOCK)
	(cs as M2SpyCombat).spawned.clear()
	_m2_free_minions()                                   # 小蛛全灭 → 断链
	for f in range(214, 324):
		e.brain_tick(f)
	assert_int((cs as M2SpyCombat).spawned.size()).is_equal(0)           # 断链后零放电
	for f in range(324, 574):
		e.brain_tick(f)                                  # 324 补召窗重召 2 只
	assert_int(_m2_spawn_calls.size()).is_equal(2)       # 补召记录在案
	assert_int((cs as M2SpyCombat).spawned.size()).is_greater_equal(1)   # 补召后链恢复
	_m2_free_minions()

## 腐沼巨蟾：吞弹相（60t 起算、持续 120t）内玩家弹被吞（不落血、存伤 20）；
## 吐还相 5 发均分（各 4 伤）；近战不受吞弹相保护。
func test_m2_marsh_toad_swallows_bullets_and_spits_back() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs: CombatSystem = auto_free(M2SpyCombat.new(root, RngSvc.stream(1, "m2_toad")))
	var e: EnemyBase = auto_free(EnemyFactory.create(GameDB.enemies["marsh_toad"]))
	assert_object(e).is_not_null()
	e.set("combat", cs)
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(100, 0)
	e.set("player_ref", spy)
	e.on_player_seen(0)
	for f in range(1, 86):
		e.brain_tick(f)                                  # 25 起 wait 60 → 85 进吞弹相
	var hp0 := int(e.hp)
	e.take_hit({"amount": 20, "is_crit": false, "element": Elements.Id.NONE,
		"from": Vector2(200, 0), "source_type": "weapon"})
	assert_int(e.hp).is_equal(hp0)       # 吞弹：不落血
	e.take_hit({"amount": 5, "is_crit": false, "element": Elements.Id.NONE,
		"from": Vector2(200, 0), "source_type": "melee"})
	assert_int(e.hp).is_equal(hp0 - 5)   # 近战不吃吞弹相
	for f in range(86, 237):
		e.brain_tick(f)                                  # 吞弹 120 + 吐还预警 30 → 235
	assert_int((cs as M2SpyCombat).spawned.size()).is_equal(5)           # 吐还 5 发
	var bad := []
	for c in (cs as M2SpyCombat).spawned:
		var cfg: Dictionary = c
		if int(cfg["damage"]) != 4:
			bad.append(str(cfg["damage"]))
	assert_str(", ".join(PackedStringArray(bad))).is_equal("")           # 20 存伤均分
