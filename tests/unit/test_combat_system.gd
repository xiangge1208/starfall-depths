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

func test_crit_rolls_at_hit_time() -> void:
	var cs := _make_cs()
	cs.crit_chance = 1.0                      # 必暴
	var body: DummyBody = auto_free(DummyBody.new())
	cs.get_parent().add_child(body)
	body.position = Vector2(200, 0)
	cs.register_body(body, Projectile.Faction.PLAYER)
	# 注：brief 原文此处弹体阵营为 PLAYER，与同阵营不互击契约（test_same_faction_no_hit_and_pierce）
	# 矛盾导致永不命中；按 test_bullet_hits_registered_body 同型改为 ENEMY，唯一变量即 crit_chance=1.0。
	cs.spawn_projectile({"pos": Vector2(100, 0), "vel": Vector2.RIGHT * 600, "damage": 4, "faction": Projectile.Faction.ENEMY, "element": 0, "pierce": 0, "bounce": 0, "life_seconds": 1.0, "radius": 3.0})
	for _i in 30:
		await get_tree().physics_frame
	assert_int(body.hits[0]["amount"]).is_equal(8)

# ---- m0-final fix 回归 ----

## fix1：cap 淘汰须走 on_evict(=CombatSystem._kill)——哈希条目与 _proj_meta 不泄漏。
func test_cap_eviction_cleans_hash_meta() -> void:
	var cs := _make_cs()
	var body: DummyBody = auto_free(DummyBody.new())
	cs.get_parent().add_child(body)
	body.position = Vector2(5000, 0)          # 远离弹堆：饱和期不被命中
	cs.register_body(body, Projectile.Faction.PLAYER)
	for _i in 600:                            # 上限 500 → 100 次淘汰
		cs.spawn_projectile({"pos": Vector2.ZERO, "vel": Vector2.ZERO, "damage": 1, "faction": Projectile.Faction.ENEMY, "element": 0, "pierce": 0, "bounce": 0, "life_seconds": 9.0, "radius": 3.0})
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
