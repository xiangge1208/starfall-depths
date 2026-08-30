class_name TestEnemyLaser
extends GdUnitTestSuite
## M2-T7：敌方直线激光束 + 晶柱 45° 折射（GDD §10 A2「晶柱折射敌方激光」）。
## 1) reflect_direction 纯数学：镜面轴 45°（y=x）下轴向入射偏转 90°（右→下 等
##    四象限案例 = 「入射 45° 案例」：入射向与镜面轴恰成 45°）；沿法线入射原路
##    折返；沿轴掠射方向不变；任意轴保持单位长度；零向量安全。
## 2) EnemyLaser 生命周期（帧注入 tick，无树直驱）：命中晶柱 → 45° 反射再飞
##    （refracts_left 1→0）；已折射后再次触柱 → 吸收终结（防无限往复）；
##    距柱超判定半径不折射；命中玩家结算 take_hit 后消亡；出房内域/寿命尽终结。
## 3) 岩晶炮台激光形态（rock_crystal_turret 行键 laser=true）：windup 后发
##    EnemyLaser（非普通弹），参数取行内 bullet_*。

const EPS := Vector2(0.001, 0.001)
const DIAG := 0.7071067811865476   # √2/2


class SpyTarget extends Node2D:
	var brain_pos := Vector2.ZERO
	var hits: Array[int] = []

	func take_hit(ctx: Dictionary) -> void:
		hits.append(int(ctx.get("amount", 0)))


func _laser(over: Dictionary = {}) -> EnemyLaser:
	var cfg := {
		"pos": Vector2.ZERO, "dir": Vector2.RIGHT,
		"speed_px": 240.0, "damage": 5, "life_ticks": 300,
		"pillars": [], "bounds": Rect2(-2000, -2000, 4000, 4000),
	}
	cfg.merge(over, true)
	var l := EnemyLaser.new()
	auto_free(l)
	l.setup(cfg)
	return l


# ---------------------------------------------------------------- 折射数学（45° 案例）

func test_reflect_direction_45_mirror_axis_cases() -> void:
	# 镜面轴 45°（方向 u=(√2/2, √2/2)）：入射向与轴成 45° → 反射向与轴成 45°
	# （偏转恰 90°）。轴向弹道四象限逐一钉死。
	assert_vector(EnemyLaser.reflect_direction(Vector2.RIGHT)).is_equal_approx(Vector2.DOWN, EPS)
	assert_vector(EnemyLaser.reflect_direction(Vector2.LEFT)).is_equal_approx(Vector2.UP, EPS)
	assert_vector(EnemyLaser.reflect_direction(Vector2.UP)).is_equal_approx(Vector2.LEFT, EPS)
	assert_vector(EnemyLaser.reflect_direction(Vector2.DOWN)).is_equal_approx(Vector2.RIGHT, EPS)


func test_reflect_direction_normal_incidence_returns_along_path() -> void:
	# 沿镜面法线入射（45° 方向弹道垂直于 45° 镜面）→ 原路折返
	var incident := Vector2(DIAG, -DIAG)
	assert_vector(EnemyLaser.reflect_direction(incident)).is_equal_approx(-incident, EPS)


func test_reflect_direction_grazing_along_axis_unchanged() -> void:
	# 沿镜面轴掠射 → 方向不变（数学边界，仍消耗折射次数）
	var along := Vector2(DIAG, DIAG)
	assert_vector(EnemyLaser.reflect_direction(along)).is_equal_approx(along, EPS)


func test_reflect_direction_other_axis_and_unit_length() -> void:
	# 0° 轴（x 轴镜面）：上下镜像翻转
	assert_vector(EnemyLaser.reflect_direction(Vector2(DIAG, DIAG), 0.0)) \
		.is_equal_approx(Vector2(DIAG, -DIAG), EPS)
	# 任意轴、任意入射：反射向保持单位长度
	for deg in [0.0, 30.0, 45.0, 90.0, 135.0]:
		var u := Vector2.from_angle(deg_to_rad(deg))
		var r := EnemyLaser.reflect_direction(u.rotated(0.7))
		assert_float(r.length()).is_equal_approx(1.0, 0.001)
	# 非单位入射先归一；零向量安全
	assert_vector(EnemyLaser.reflect_direction(Vector2(5, 0))).is_equal_approx(Vector2.DOWN, EPS)
	assert_vector(EnemyLaser.reflect_direction(Vector2.ZERO)).is_equal_approx(Vector2.ZERO, EPS)


# ---------------------------------------------------------------- 激光束生命周期

func test_laser_refracts_off_pillar_at_45() -> void:
	var l := _laser({"pillars": [Vector2(40, 0)]})   # 4px/tick，10 拍到柱
	for i in 10:
		l.tick()
	assert_bool(l.alive()).is_true()
	assert_vector(l.dir).is_equal_approx(Vector2.DOWN, EPS)   # 右 → 下（45° 镜面）
	assert_int(l.refracts_left).is_equal(0)
	assert_float(l.laser_pos.x).is_equal_approx(40.0, 0.01)   # 从柱面弹出
	assert_bool(l.laser_pos.y >= EnemyLaser.PILLAR_RADIUS_PX).is_true()
	for i in 20:                                     # 折射段沿新方向继续飞
		l.tick()
	assert_float(l.laser_pos.x).is_equal_approx(40.0, 0.01)
	assert_float(l.laser_pos.y).is_greater(80.0)
	assert_bool(l.alive()).is_true()


func test_laser_second_pillar_hit_absorbed_no_infinite() -> void:
	var l := _laser({"pillars": [Vector2(40, 0), Vector2(40, 100)]})
	var frames := 0
	while l.alive() and frames < 200:
		l.tick()
		frames += 1
	assert_bool(l.alive()).is_false()                # 第二柱吸收（最多 1 次折射）
	assert_int(frames).is_less(200)


func test_laser_passes_by_pillar_out_of_radius() -> void:
	var l := _laser({"pillars": [Vector2(40, 13)]})  # 路径 y=0 距柱 13 > 8+3
	for i in 30:
		l.tick()
	assert_bool(l.alive()).is_true()
	assert_vector(l.dir).is_equal_approx(Vector2.RIGHT, EPS)
	assert_int(l.refracts_left).is_equal(1)


func test_laser_hits_player_once_and_dies() -> void:
	var spy: SpyTarget = auto_free(SpyTarget.new())
	spy.brain_pos = Vector2(20, 0)
	var l := _laser({"player": spy})
	for i in 10:
		l.tick()
	assert_int(spy.hits.size()).is_equal(1)
	assert_int(spy.hits[0]).is_equal(5)
	assert_bool(l.alive()).is_false()


func test_laser_expires_on_leaving_bounds() -> void:
	var l := _laser({"bounds": Rect2(0, -50, 20, 100)})
	var frames := 0
	while l.alive() and frames < 50:
		l.tick()
		frames += 1
	assert_bool(l.alive()).is_false()                # 撞墙（出房内域）消失
	assert_int(frames).is_less(50)


func test_laser_expires_on_life_end() -> void:
	var l := _laser({"life_ticks": 3})
	for i in 3:
		l.tick()
	assert_bool(l.alive()).is_false()


func test_laser_setup_normalizes_direction() -> void:
	var l := _laser({"dir": Vector2(5, 0)})
	assert_float(l.dir.length()).is_equal_approx(1.0, 0.001)
	assert_vector(l.dir).is_equal_approx(Vector2.RIGHT, EPS)


# ---------------------------------------------------------------- 岩晶炮台激光形态

func test_rock_crystal_turret_fires_enemy_laser() -> void:
	var e: EnemyBase = auto_free(EnemyFactory.create(GameDB.enemies["rock_crystal_turret"]))
	assert_object(e).is_not_null()
	assert_bool(bool(GameDB.enemies["rock_crystal_turret"].get("laser", false))).is_true()
	var spy: SpyTarget = auto_free(SpyTarget.new())
	spy.brain_pos = Vector2(100, 0)                  # 正东 → 激光向右
	e.set("player_ref", spy)
	e.on_player_seen(0)
	var fired := false
	for f in range(1, 120):                          # ALERT24 + windup36 → ~61 拍发射
		e.brain_tick(f)
		var laser := e.get_node_or_null("EnemyLaser") as EnemyLaser
		if laser != null:
			fired = true
			assert_vector(laser.dir).is_equal_approx(Vector2.RIGHT, EPS)
			assert_int(laser.damage).is_equal(6)     # 行 bullet_dmg
			assert_float(laser.speed_px).is_equal(150.0)   # 行 bullet_speed
			break
	assert_bool(fired).is_true()
