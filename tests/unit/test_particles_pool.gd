class_name TestParticlesPool
extends GdUnitTestSuite
## M3 J-C（Juice v2 §2 J3）：池化条带播放器 TDD。
## 契约：启动建满常驻播放单元（Sprite2D + AtlasTexture 帧步进）；play 取用/到期回收/
## 复用同节点（实例数恒 ≤ 池大小，热路径零分配）；同屏预算 200，超预算降级为单帧贴图
##（只显示第 0 帧不做逐帧换图），活跃回落恢复；火花三态选择（暴击/元素/通用）；
## 枪口焰按武器类别 tint；boss_defeated 驱动 J7 白闪 + 碎片环（不在树内零表现）。

const BOSS_ROW := {"id": "boss_jc", "hp": 100, "radius": 14.0}
const BUDGET := 200   # 与 ParticlesPool.BUDGET 同源断言（规格 ≤200）


func before_test() -> void:
	Fx.cancel_hitstop()
	_free_death_flashes()


func after_test() -> void:
	_free_death_flashes()


func _free_death_flashes() -> void:
	# J7 白闪挂在 /root（跨套件持久），用例边界手动回收（正常由 0.25s 真实定时器自毁）
	for child in get_tree().root.get_children():
		if child.name == "BossDeathFlash":
			child.free()


func _pool() -> ParticlesPool:
	# 不入树构建（_build_pool 直调）：无 _process 干扰（用例手动 step）、不挂 node_added
	# 钩子——boss 表现统一由 Fx.particles（autoload 池）承接，避免双订阅双白闪。
	var p: ParticlesPool = auto_free(ParticlesPool.new())
	p._build_pool()
	return p


func _active_unit(pool: ParticlesPool) -> ParticlesPool.Unit:
	for u: ParticlesPool.Unit in pool.units():
		if u.playing:
			return u
	return null


func _unit_by_strip(pool: ParticlesPool, strip: String) -> ParticlesPool.Unit:
	# 多单元同时活跃时按条带定位目标单元（首个活跃 ≠ 最近播放）
	for u: ParticlesPool.Unit in pool.units():
		if u.playing and u.strip == strip:
			return u
	return null


# ---------- 1. 取用 / 回收 / 复用（实例数恒 ≤ 池大小） ----------

func test_play_takes_unit_recycles_after_duration_and_reuses_same_node() -> void:
	var pool := _pool()
	pool.play("spark_hit", Vector2(10, 10))
	assert_int(pool.active_units()).is_equal(1)
	var u := _active_unit(pool)
	assert_bool(u.playing).is_true()
	assert_bool(u.visible).is_true()
	assert_str(u.strip).is_equal("spark_hit")
	assert_vector(u.position).is_equal(Vector2(10, 10))
	pool.step(0.19)                        # 4 帧 × 0.05 = 0.2s：未到期
	assert_int(pool.active_units()).is_equal(1)
	pool.step(0.01)                        # 到期回收
	assert_int(pool.active_units()).is_equal(0)
	assert_bool(u.playing).is_false()
	assert_bool(u.visible).is_false()
	pool.play("kill_shard", Vector2.ZERO)  # 复用同一节点（池不增长）
	assert_int(pool.active_units()).is_equal(1)
	assert_object(_active_unit(pool)).is_same(u)


func test_instance_count_constant_under_storm_zero_allocation_footprint() -> void:
	# 热路径零分配复查（TDD 必测 4）：300 连发 + 回收 ×3，池单元实例 id 集不变
	var pool := _pool()
	var ids_before: Array = []
	for u: ParticlesPool.Unit in pool.units():
		ids_before.append(u.get_instance_id())
	for round_idx in 3:
		for i in 300:
			pool.play("spark_hit", Vector2(i, 0))
		for u: ParticlesPool.Unit in pool.units():
			assert_bool(u.playing).is_true()      # 0.2s 内全部活跃（无中途新建）
		assert_int(pool.get_child_count()).is_equal(ids_before.size())
		pool.step(0.5)                            # 全部到期
		assert_int(pool.active_units()).is_equal(0)
	var ids_after: Array = []
	for u: ParticlesPool.Unit in pool.units():
		ids_after.append(u.get_instance_id())
	assert_array(ids_after).contains_exactly(ids_before)


func test_play_beyond_pool_capacity_drops_silently() -> void:
	var pool := _pool()
	for i in pool.capacity() + 5:
		pool.play("spark_hit", Vector2.ZERO)
	assert_int(pool.active_units()).is_equal(pool.capacity())   # 池硬容量兜底：超额丢弃


func test_unknown_strip_is_fail_closed_no_op() -> void:
	var pool := _pool()
	pool.play("no_such_strip", Vector2.ZERO)
	assert_int(pool.active_units()).is_equal(0)


# ---------- 2. 帧步进与降级（预算 200：超预算单帧，回落恢复） ----------

func test_frame_stepping_advances_through_strip() -> void:
	var pool := _pool()
	pool.play("spark_hit", Vector2.ZERO)          # 4 帧条带
	var u := _active_unit(pool)
	assert_int(u.fidx).is_equal(0)
	pool.step(0.05)
	assert_int(u.fidx).is_equal(1)
	pool.step(0.05)
	assert_int(u.fidx).is_equal(2)
	pool.step(0.05)
	assert_int(u.fidx).is_equal(3)                # 帧号夹取到末帧
	pool.step(0.05)
	assert_bool(u.playing).is_false()             # 0.2s 播毕回收


func test_degrade_beyond_budget_locks_single_frame_and_recovers() -> void:
	var pool := _pool()
	for i in BUDGET:                              # 填满预算：200 活跃
		pool.play("spark_hit", Vector2.ZERO)
	assert_int(pool.active_units()).is_equal(BUDGET)
	assert_bool(pool.is_degraded()).is_false()
	pool.step(0.01)                               # 全员仍活跃
	pool.play("kill_shard", Vector2.ZERO)         # 第 201 请求：超预算 → 降级
	assert_bool(pool.is_degraded()).is_true()
	var u := _unit_by_strip(pool, "kill_shard")
	assert_object(u).is_not_null()
	assert_bool(u.degraded).is_true()
	pool.step(0.06)
	pool.step(0.06)
	assert_int(u.fidx).is_equal(0)                # 降级：只显示第 0 帧不逐帧换图
	pool.step(0.5)                                # 全部到期 → 活跃回落
	assert_int(pool.active_units()).is_equal(0)
	pool.step(0.01)                               # 回落后恢复帧动画
	assert_bool(pool.is_degraded()).is_false()
	pool.play("spark_hit", Vector2.ZERO)
	var v := _active_unit(pool)
	assert_bool(v.degraded).is_false()
	pool.step(0.05)
	assert_int(v.fidx).is_equal(1)                # 恢复：正常逐帧


# ---------- 3. 火花三态 / 枪口焰 tint / 碎片环 ----------

func test_spark_selection_crit_element_generic() -> void:
	var pool := _pool()
	pool.play_spark(Vector2.ZERO, true, Elements.Id.NONE)   # 暴击优先：金色 + 1.3×
	var u := _active_unit(pool)
	assert_str(u.strip).is_equal("spark_crit")
	assert_vector(u.scale).is_equal(Vector2(1.3, 1.3))
	assert_that(u.modulate).is_equal(Color(1.0, 0.85, 0.2))
	pool.step(1.0)
	pool.play_spark(Vector2.ZERO, false, Elements.Id.FIRE)  # 武器原生元素 → 元素条带
	assert_str(_active_unit(pool).strip).is_equal("spark_fire")
	pool.step(1.0)
	pool.play_spark(Vector2.ZERO, false, Elements.Id.SHOCK)
	assert_str(_active_unit(pool).strip).is_equal("spark_shock")
	pool.step(1.0)
	pool.play_spark(Vector2.ZERO, false, Elements.Id.NONE)  # 无元素 → 通用
	assert_str(_active_unit(pool).strip).is_equal("spark_hit")


func test_muzzle_tint_by_weapon_category_and_rotation() -> void:
	var pool := _pool()
	pool.play_muzzle(Vector2(4, 4), PI, "shotgun")
	var u := _active_unit(pool)
	assert_str(u.strip).is_equal("muzzle_v2")
	assert_float(u.rotation).is_equal_approx(PI, 0.0001)
	assert_that(u.modulate).is_not_equal(Color.WHITE)       # 霰弹组预设色（非白）
	pool.step(1.0)
	pool.play_muzzle(Vector2.ZERO, 0.0, "laser")
	assert_that(_active_unit(pool).modulate).is_not_equal(Color.WHITE)
	pool.step(1.0)
	pool.play_muzzle(Vector2.ZERO, 0.0, "pistol")            # 三组外的类别 → 不 tint
	assert_that(_active_unit(pool).modulate).is_equal(Color.WHITE)


func test_kill_shard_ring_plays_six_frame_strip() -> void:
	var pool := _pool()
	pool.play_kill_shard(Vector2(20, 20))
	var u := _active_unit(pool)
	assert_str(u.strip).is_equal("kill_shard")
	assert_int(u.frames).is_equal(6)
	pool.step(0.28)                              # 6 × 0.05 = 0.3s：步进避开浮点精确边界
	assert_bool(u.playing).is_true()
	pool.step(0.05)
	assert_bool(u.playing).is_false()


# ---------- 4. 必跟①：boss_defeated → J7 白闪 + 碎片环（在树内恰一次；不在树内零表现） ----------

func test_boss_defeated_in_tree_spawns_flash_and_shard_exactly_once() -> void:
	var flashes_before := _death_flash_count()
	var active_before := Fx.particles.active_units()
	var boss: BossBase = auto_free(BossBase.new())
	boss._test_init(BOSS_ROW)
	add_child(boss)                               # 在树内：表现触发
	boss.die()
	assert_int(_death_flash_count()).is_equal(flashes_before + 1)   # 全屏白闪恰一层
	assert_int(Fx.particles.active_units()).is_equal(active_before + 1)
	assert_object(_unit_by_strip(Fx.particles, "kill_shard")).is_not_null()
	boss.die()                                    # 状态门：死亡态重复调用不再发信号
	assert_int(_death_flash_count()).is_equal(flashes_before + 1)   # 仍恰一次
	assert_int(Fx.particles.active_units()).is_equal(active_before + 1)


func test_boss_defeated_out_of_tree_is_pure_signal_no_visuals() -> void:
	# 脑测 Boss 不在树内：不崩、零表现（is_inside_tree 守卫）
	var flashes_before := _death_flash_count()
	var active_before := Fx.particles.active_units()
	var boss: BossBase = auto_free(BossBase.new())
	boss._test_init(BOSS_ROW)
	boss.die()
	assert_int(_death_flash_count()).is_equal(flashes_before)
	assert_int(Fx.particles.active_units()).is_equal(active_before)


func _death_flash_count() -> int:
	var n := 0
	for child in get_tree().root.get_children():
		if child.name == "BossDeathFlash":
			n += 1
	return n
