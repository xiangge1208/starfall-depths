class_name TestCombatSystem
extends GdUnitTestSuite

class DummyBody extends Node2D:
	var hits: Array = []
	func take_hit(ctx: Dictionary) -> void:
		hits.append(ctx)
	func combat_radius() -> float:
		return 6.0

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
