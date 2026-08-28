class_name TestProjectilePool
extends GdUnitTestSuite

func test_spawn_reuses_instances() -> void:
	var root: Node = auto_free(Node.new())
	var pool := ProjectilePool.new(root)
	var a := pool.spawn({"pos": Vector2.ZERO, "vel": Vector2.RIGHT * 100, "damage": 2, "faction": 0, "element": 0, "pierce": 0, "bounce": 0, "life_seconds": 1.0, "radius": 3.0})
	pool.despawn(a)
	var b := pool.spawn({"pos": Vector2.ZERO, "vel": Vector2.RIGHT * 100, "damage": 2, "faction": 0, "element": 0, "pierce": 0, "bounce": 0, "life_seconds": 1.0, "radius": 3.0})
	assert_that(a).is_same(b)

func test_lifetime_expiry() -> void:
	var root: Node = auto_free(Node.new())
	var pool := ProjectilePool.new(root)
	var p := pool.spawn({"pos": Vector2.ZERO, "vel": Vector2.ZERO, "damage": 1, "faction": 0, "element": 0, "pierce": 0, "bounce": 0, "life_seconds": 0.05, "radius": 3.0})
	var alive := true
	for _i in 10:                # 0.05s = 3 ticks
		alive = p.tick()
	assert_bool(alive).is_false()

func test_cap_enforced() -> void:
	var root: Node = auto_free(Node.new())
	var pool := ProjectilePool.new(root)
	var first := pool.spawn({"pos": Vector2.ZERO, "vel": Vector2.ZERO, "damage": 1, "faction": 1, "element": 0, "pierce": 0, "bounce": 0, "life_seconds": 9.0, "radius": 3.0})
	for _i in 600:
		pool.spawn({"pos": Vector2.ZERO, "vel": Vector2.ZERO, "damage": 1, "faction": 1, "element": 0, "pierce": 0, "bounce": 0, "life_seconds": 9.0, "radius": 3.0})
	assert_int(pool.active_count()).is_equal(500)
	# 公平性淘汰：最旧的非追踪弹被淘汰（GDD §7.5）——队首不再是 first
	# （victim 节点被池回收复用，故其实例仍在 active 中，但已作为新弹位于队尾）
	assert_bool(pool.active[0] == first).is_false()
