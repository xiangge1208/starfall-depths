class_name TestCombatSystem
extends GdUnitTestSuite

class DummyBody extends Node2D:
	var hits: Array = []
	func take_hit(ctx: Dictionary) -> void:
		hits.append(ctx)
	func combat_radius() -> float:
		return 6.0

class FatBody extends Node2D:
	var hits: Array = []
	func take_hit(ctx: Dictionary) -> void:
		hits.append(ctx)
	func combat_radius() -> float:
		return 20.0

func _make_cs() -> CombatSystem:
	# 注：brief 原文 add_child_unchecked 在 gdUnit4 6.2.1 不存在，按既定决议改用 add_child；
	# auto_free 返回 Variant，:= 无法推断类型，需显式类型标注。
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var rng := RngSvc.stream(0, "combat")
	rng.seed = 11
	var cs := CombatSystem.new(root, rng)
	root.add_child(cs)
	return cs

func test_bullet_hits_registered_body() -> void:
	var cs := _make_cs()
	var body: DummyBody = auto_free(DummyBody.new())
	cs.get_parent().add_child(body)
	body.position = Vector2(200, 0)
	cs.register_body(body, Projectile.Faction.PLAYER)
	cs.spawn_projectile({"pos": Vector2(100, 0), "vel": Vector2.RIGHT * 600, "damage": 4, "faction": Projectile.Faction.ENEMY, "element": 0, "pierce": 0, "bounce": 0, "life_seconds": 1.0, "radius": 3.0})
	for _i in 30:
		await get_tree().physics_frame
	assert_int(body.hits.size()).is_equal(1)
	assert_int(body.hits[0]["amount"]).is_equal(4)

func test_same_faction_no_hit_and_pierce() -> void:
	var cs := _make_cs()
	var body: DummyBody = auto_free(DummyBody.new())
	cs.get_parent().add_child(body)
	body.position = Vector2(200, 0)
	cs.register_body(body, Projectile.Faction.ENEMY)
	cs.spawn_projectile({"pos": Vector2(100, 0), "vel": Vector2.RIGHT * 600, "damage": 4, "faction": Projectile.Faction.ENEMY, "element": 0, "pierce": 2, "bounce": 0, "life_seconds": 1.0, "radius": 3.0})
	for _i in 30:
		await get_tree().physics_frame
	assert_int(body.hits.size()).is_equal(0)

func test_player_crit_rolls_at_hit_time() -> void:
	var cs := _make_cs()
	cs.crit_chance = 1.0                      # 必暴
	var body: DummyBody = auto_free(DummyBody.new())
	cs.get_parent().add_child(body)
	body.position = Vector2(200, 0)
	cs.register_body(body, Projectile.Faction.ENEMY)
	cs.spawn_projectile({"pos": Vector2(100, 0), "vel": Vector2.RIGHT * 600, "damage": 4, "faction": Projectile.Faction.PLAYER, "element": 0, "pierce": 0, "bounce": 0, "life_seconds": 1.0, "radius": 3.0})
	for _i in 30:
		await get_tree().physics_frame
	assert_int(body.hits[0]["amount"]).is_equal(8)

func test_enemy_projectile_damage_is_fixed_even_with_player_crit_chance() -> void:
	var cs := _make_cs()
	cs.crit_chance = 1.0
	var body: DummyBody = auto_free(DummyBody.new())
	cs.get_parent().add_child(body)
	body.position = Vector2(200, 0)
	cs.register_body(body, Projectile.Faction.PLAYER)
	cs.spawn_projectile({"pos": Vector2(100, 0), "vel": Vector2.RIGHT * 600, "damage": 4, "faction": Projectile.Faction.ENEMY, "element": 0, "pierce": 0, "bounce": 0, "life_seconds": 1.0, "radius": 3.0})
	for _i in 30:
		await get_tree().physics_frame
	assert_int(body.hits[0]["amount"]).is_equal(4)
	assert_bool(bool(body.hits[0]["is_crit"])).is_false()

# ---- m0-final fix 回归 ----

## fix1：cap 淘汰须走 on_evict(=CombatSystem._kill)——哈希条目与 _proj_meta 不泄漏。
## m1-t18：饱和弹改玩家阵营——敌方弹现受 400 上限门（由 test_enemy_bullet_cap_400 专测），
## 本回归须继续压满 500 总池上限的淘汰路径（玩家弹无阵营门，直抵池 cap）。
func test_cap_eviction_cleans_hash_meta() -> void:
	var cs := _make_cs()
	var body: DummyBody = auto_free(DummyBody.new())
	cs.get_parent().add_child(body)
	body.position = Vector2(5000, 0)          # 远离弹堆：饱和期不被命中
	cs.register_body(body, Projectile.Faction.PLAYER)
	for _i in 600:                            # 上限 500 → 100 次淘汰
		cs.spawn_projectile({"pos": Vector2.ZERO, "vel": Vector2.ZERO, "damage": 1, "faction": Projectile.Faction.PLAYER, "element": 0, "pierce": 0, "bounce": 0, "life_seconds": 9.0, "radius": 3.0})
	assert_int(cs.active_count()).is_equal(500)
	assert_int(cs.debug_meta_count()).is_equal(cs.active_count())   # fix5：无幽灵元数据
	# 哈希无陈旧条目（不外泄 API，经反射清点）：meta 键按实例 id 复用即自愈，
	# 真正无界泄漏在 _hash（_next_id 每弹自增）——修复前 600 弹后 hash=600 ≠ 500。
	# 场上另有 1 个注册体，故哈希条目 = 500 弹 + 1 体。
	var hash_pos: Dictionary = cs._hash.get("_pos")
	assert_int(hash_pos.size()).is_equal(cs.active_count() + 1)
	# 哈希未被幽灵条目污染：饱和后新弹仍命中注册体
	cs.spawn_projectile({"pos": Vector2(4700, 0), "vel": Vector2.RIGHT * 600, "damage": 4, "faction": Projectile.Faction.ENEMY, "element": 0, "pierce": 0, "bounce": 0, "life_seconds": 1.0, "radius": 3.0})
	for _i in 40:
		await get_tree().physics_frame
	assert_int(body.hits.size()).is_equal(1)
	assert_int(body.hits[0]["amount"]).is_equal(4)

## fix2：大半径体（20px）在 p.radius+_max_body_radius 松弛内须被候选、精确判定命中
## （旧 slack 3+12=15 静默漏判：离弹道 18px > 15 但 ≤ 3+20）。
func test_large_radius_body_hit_within_widened_slack() -> void:
	var cs := _make_cs()
	var body: FatBody = auto_free(FatBody.new())
	cs.get_parent().add_child(body)
	body.position = Vector2(200, 18)          # 最近接近距 18px：> 旧门 15，≤ 新门 23
	cs.register_body(body, Projectile.Faction.PLAYER)
	cs.spawn_projectile({"pos": Vector2(100, 0), "vel": Vector2.RIGHT * 600, "damage": 4, "faction": Projectile.Faction.ENEMY, "element": 0, "pierce": 0, "bounce": 0, "life_seconds": 1.0, "radius": 3.0})
	for _i in 30:
		await get_tree().physics_frame
	assert_int(body.hits.size()).is_equal(1)

# ---- m1-t18 ----

func _enemy_alive(cs: CombatSystem) -> int:
	var n := 0
	for p in cs.pool.active:
		if p.faction == Projectile.Faction.ENEMY:
			n += 1
	return n

## GDD §7.5：敌方场上弹 ≤400；第 401 发让最旧敌方弹淘汰让位（公平性 victim，同池 cap 习语）。
## 总池 500 上限不变；玩家弹不因敌方 cap 让位。
func test_enemy_bullet_cap_400_recycles_oldest() -> void:
	var cs := _make_cs()
	var enemy_cfg := {"pos": Vector2.ZERO, "vel": Vector2.ZERO, "damage": 1, "faction": Projectile.Faction.ENEMY, "element": 0, "pierce": 0, "bounce": 0, "life_seconds": 9.0, "radius": 3.0}
	cs.spawn_projectile(enemy_cfg)
	var first: Projectile = cs.pool.active[0]
	for _i in 400:                            # 累计 401 发敌方弹
		cs.spawn_projectile(enemy_cfg)
	assert_int(_enemy_alive(cs)).is_equal(400)
	assert_int(cs.active_count()).is_equal(400)
	assert_bool(cs.pool.active[0] == first).is_false()   # 最旧已让位（实例复用至队尾）
	assert_int(cs.debug_meta_count()).is_equal(cs.active_count())   # 淘汰不泄漏元数据
	# 玩家弹不受敌方 cap 淘汰
	cs.spawn_projectile({"pos": Vector2.ZERO, "vel": Vector2.ZERO, "damage": 1, "faction": Projectile.Faction.PLAYER, "element": 0, "pierce": 0, "bounce": 0, "life_seconds": 9.0, "radius": 3.0})
	var player_p: Projectile = cs.pool.active[cs.pool.active.size() - 1]
	assert_int(cs.active_count()).is_equal(401)
	cs.spawn_projectile(enemy_cfg)            # 再发敌方弹：让位的是最旧敌方弹
	assert_bool(cs.pool.active.has(player_p)).is_true()
	assert_int(_enemy_alive(cs)).is_equal(400)

## m1-t18：EnemyBase.take_hit 启用 EventBus.enemy_damaged（原死信号）——扣血后、死亡判定前。
func test_enemy_damaged_emitted_on_take_hit() -> void:
	var e: EnemyBase = auto_free(EnemyBase.new())
	e._test_init({"id": "t18_dummy", "hp": 10, "radius": 6.0})
	var seen: Array = []
	var cb := func(amount: int, is_crit: bool) -> void:
		seen.append([amount, is_crit])
	EventBus.enemy_damaged.connect(cb)
	e.take_hit({"amount": 4, "is_crit": true, "element": 0, "from": Vector2.ZERO})
	EventBus.enemy_damaged.disconnect(cb)
	assert_int(seen.size()).is_equal(1)
	assert_int(seen[0][0]).is_equal(4)
	assert_bool(seen[0][1]).is_true()
	assert_int(e.hp).is_equal(6)              # 信号在扣血之后
	assert_int(e.state).is_equal(EnemyBase.State.IDLE)   # 且在死亡判定之前（未致死）

func test_enemy_damaged_emitted_before_death_check() -> void:
	var e: EnemyBase = auto_free(EnemyBase.new())
	e._test_init({"id": "t18_dummy2", "hp": 4, "radius": 6.0})
	var seen: Array = []
	var cb := func(amount: int, _is_crit: bool) -> void:
		seen.append(amount)
	EventBus.enemy_damaged.connect(cb)
	e.take_hit({"amount": 4, "is_crit": false, "element": 0, "from": Vector2.ZERO})
	EventBus.enemy_damaged.disconnect(cb)
	assert_int(seen.size()).is_equal(1)       # 致死当拍仍先广播再走 die()
	assert_int(e.state).is_equal(EnemyBase.State.DEAD)

func test_enemy_damage_events_use_actual_not_overkill_or_negative() -> void:
	var e: EnemyBase = auto_free(EnemyBase.new())
	e._test_init({"id": "actual_dummy", "hp": 4, "radius": 6.0})
	var enemy_seen: Array[int] = []
	var player_seen: Array[int] = []
	var enemy_cb := func(amount: int, _is_crit: bool) -> void: enemy_seen.append(amount)
	var player_cb := func(amount: int, _frame: int) -> void: player_seen.append(amount)
	EventBus.enemy_damaged.connect(enemy_cb)
	EventBus.player_damage_resolved.connect(player_cb)
	e.take_hit({"amount": 999, "is_crit": false, "element": Elements.Id.NONE,
		"from": Vector2.ZERO, "frame": 10, "player_damage": true})
	EventBus.enemy_damaged.disconnect(enemy_cb)
	EventBus.player_damage_resolved.disconnect(player_cb)
	assert_int(enemy_seen[0]).is_equal(4)
	assert_int(player_seen[0]).is_equal(4)

func test_zero_damage_emits_zero_and_does_not_apply_status() -> void:
	var e: EnemyBase = auto_free(EnemyBase.new())
	e._test_init({"id": "zero_dummy", "hp": 4, "radius": 6.0})
	var seen: Array[int] = []
	var cb := func(amount: int, _is_crit: bool) -> void: seen.append(amount)
	EventBus.enemy_damaged.connect(cb)
	e.take_hit({"amount": 0, "is_crit": false, "element": Elements.Id.FIRE,
		"proc_element": Elements.Id.ICE, "from": Vector2.ZERO, "frame": 10})
	EventBus.enemy_damaged.disconnect(cb)
	assert_int(seen[0]).is_equal(0)
	assert_int(e.hp).is_equal(4)
	assert_dict(e.status.active).is_empty()
