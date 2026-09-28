class_name TestMFollower
extends GdUnitTestSuite
## m5-f 招募跟随（局内临时同伴）契约测试。
## 1) 佣兵事件（第 5 选）：招募扣款 50 金经 summon_follower 接缝；接缝未注入/
##    余额不足 fail-closed 零副作用；文案含价签
## 2) 至多 1 名=替换语义：deploy 二连，旧体 despawn("replaced")、存活恒 1
## 3) 跟随：60~90px 距离带保持（远则贴近、带内停步）
## 4) 索敌开火：240px 内最近敌人、cd_ticks 节拍、弹幕 faction=PLAYER 可断言
## 5) 90s 时限消散（帧注入直驱，勿用墙钟）；玩家死亡消散（fatal 信号）
## 6) 无敌简化：take_hit 恒 no-op；组纪律：不进 enemies/summons 组
## 7) 战斗体注册 PLAYER 阵营（己方 AoE 可见、敌方阵营查询不可见）

const ALLY_SCENE := "res://core/enemies/follow_ally.gd"


# ---------------------------------------------------------------- 夹具

func _root() -> Node2D:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	return root


func _combat(root: Node2D) -> CombatSystem:
	var cs := CombatSystem.new(root, RngSvc.stream(0, "combat"))
	auto_free(cs)
	root.add_child(cs)
	return cs


## 入树假敌（进 "enemies" 组并注册进 combat；brain_pos 与 global_position 对齐，
## 同 test_summons._enemy 习语）。
func _enemy(root: Node2D, cs: CombatSystem, at: Vector2, hp := 30) -> EnemyBase:
	var e := EnemyBase.new()
	e._test_init({"id": "follower_dummy", "hp": hp, "radius": 6.0})
	e.brain_pos = at
	e.position = at
	root.add_child(e)
	e.add_to_group("enemies")
	cs.register_body(e, e.combat_faction())
	return e


func _living_allies() -> Array[FollowAlly]:
	var out: Array[FollowAlly] = []
	if get_tree() == null:
		return out
	for node in get_tree().get_nodes_in_group(FollowAlly.GROUP):
		var a := node as FollowAlly
		if a != null and not a.is_despawned() and not a.is_queued_for_deletion():
			out.append(a)
	return out


# ================================================================ 1) 佣兵事件

func test_mercenary_in_event_pool_with_title_and_cost_text() -> void:
	assert_array(EventRoom.EVENT_IDS).contains("mercenary")
	assert_int(EventRoom.EVENT_IDS.size()).is_equal(5)
	assert_str(String(EventRoom.EVENT_TITLES["mercenary"])).is_equal("佣兵")
	assert_int(EventRoom.MERCENARY_COST).is_equal(50)


func test_mercenary_accept_spends_50_and_calls_summon_seam() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var player: Node2D = auto_free(Node2D.new())
	root.add_child(player)
	var room: EventRoom = auto_free(EventRoom.new())
	root.add_child(room)
	room.setup(player, _rng(7))
	var hires: Array[int] = []                  # lambda 按值捕获：引用容器计数
	room.summon_follower = func() -> void:
		hires.append(1)
	assert_bool(room.open_event("mercenary")).is_true()
	RunState.coins = 80
	room.accept()
	assert_int(RunState.coins).is_equal(30)      # 80 − 50 扣款
	assert_int(hires.size()).is_equal(1)         # 召唤缝恰一次
	assert_bool(room.ui_visible()).is_false()    # 面板关闭


func test_mercenary_insufficient_funds_is_zero_side_effect() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var player: Node2D = auto_free(Node2D.new())
	root.add_child(player)
	var room: EventRoom = auto_free(EventRoom.new())
	root.add_child(room)
	room.setup(player, _rng(7))
	var hires: Array[int] = []                  # lambda 按值捕获：引用容器计数
	room.summon_follower = func() -> void:
		hires.append(1)
	assert_bool(room.open_event("mercenary")).is_true()
	RunState.coins = 30
	room.accept()
	assert_int(RunState.coins).is_equal(30)      # 不扣款
	assert_int(hires.size()).is_equal(0)         # 不召唤
	assert_bool(room.ui_visible()).is_false()    # 关面板（乞丐同款零副作用惯例）


func test_mercenary_without_seam_is_fail_closed_before_spend() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var player: Node2D = auto_free(Node2D.new())
	root.add_child(player)
	var room: EventRoom = auto_free(EventRoom.new())
	root.add_child(room)
	room.setup(player, _rng(7))                  # 不注入 summon_follower
	assert_bool(room.open_event("mercenary")).is_true()
	RunState.coins = 200
	room.accept()
	assert_int(RunState.coins).is_equal(200)     # 未接线不扣款
	assert_str(room.desc_text()).contains("50")  # 文案带价签


# ================================================================ 2) 至多 1 名=替换

func test_deploy_twice_replaces_old_follower() -> void:
	var root := _root()
	var player: Node2D = auto_free(Node2D.new())
	root.add_child(player)
	var cs := _combat(root)
	var first := FollowAlly.deploy(root, player, cs, 0)
	assert_object(first).is_not_null()
	var reasons: Array[String] = []
	first.despawned.connect(func(reason: String) -> void: reasons.append(reason))
	var second := FollowAlly.deploy(root, player, cs, 10)
	assert_object(second).is_not_null()
	assert_bool(second == first).is_false()
	assert_int(reasons.size()).is_equal(1)
	assert_str(reasons[0]).is_equal("replaced")  # 替换语义披露
	assert_bool(first.is_despawned()).is_true()
	assert_bool(first.is_queued_for_deletion()).is_true()
	assert_array(_living_allies()).has_size(1)   # 场上恒至多 1 名


func test_deploy_without_host_or_player_fails_closed() -> void:
	assert_object(FollowAlly.deploy(null, null, null, 0)).is_null()
	var root := _root()
	assert_object(FollowAlly.deploy(root, null, null, 0)).is_null()
	assert_array(_living_allies()).is_empty()


# ================================================================ 3) 跟随

func test_follower_walks_into_band_and_stops() -> void:
	var root := _root()
	var player: Node2D = auto_free(Node2D.new())
	player.position = Vector2.ZERO
	root.add_child(player)
	var ally := FollowAlly.deploy(root, player, null, 0)
	ally.brain_pos = Vector2(180, 0)             # 90px 带外（> MAX）
	var last_dist := ally.brain_pos.distance_to(player.global_position)
	for frame in range(1, 121):                  # 2s @ speed 60 → 恰好走完 90px 差
		ally.tick(frame)
		var dist := ally.brain_pos.distance_to(player.global_position)
		assert_bool(dist <= last_dist + 0.0001).is_true()   # 单调贴近
		last_dist = dist
	assert_float(last_dist).is_equal_approx(FollowAlly.FOLLOW_MAX_PX, 0.5)
	for frame in range(121, 200):                # 带内停步（不越过下沿反复振荡）
		ally.tick(frame)
	assert_float(ally.brain_pos.distance_to(
		player.global_position)).is_equal_approx(FollowAlly.FOLLOW_MAX_PX, 0.5)


# ================================================================ 4) 索敌开火

func test_follower_fires_player_faction_bullets_on_row_cadence() -> void:
	var root := _root()
	var player: Node2D = auto_free(Node2D.new())
	player.position = Vector2.ZERO
	root.add_child(player)
	var cs := _combat(root)
	var ally := FollowAlly.deploy(root, player, cs, 0)
	ally.brain_pos = Vector2(90, 0)              # 带内停步
	var foe := _enemy(root, cs, Vector2(210, 0))  # 距 120 ≤ 240 索敌半径
	var cadence := int(ally.row["cd_ticks"])
	for frame in range(1, cadence):              # 部署拍起整周期：首拍不开火
		ally.tick(frame)
		assert_int(cs.active_count()).is_equal(0)
	ally.tick(cadence)
	assert_int(cs.active_count()).is_equal(1)
	var p: Projectile = cs.pool.active[0]
	assert_int(p.faction).is_equal(Projectile.Faction.PLAYER)   # 阵营断言（核心契约）
	assert_int(p.damage).is_equal(3)             # crossbowman 行 bullet_dmg
	assert_float(p.vel.normalized().dot(Vector2.RIGHT)).is_equal_approx(1.0, 0.001)   # 朝 +x 轴向
	for frame in range(cadence + 1, cadence * 2):
		ally.tick(frame)
	ally.tick(cadence * 2)
	assert_int(cs.active_count()).is_equal(2)    # 第二拍整周期再发（节拍=行 cd_ticks）


func test_follower_holds_fire_without_target_in_range() -> void:
	var root := _root()
	var player: Node2D = auto_free(Node2D.new())
	player.position = Vector2.ZERO
	root.add_child(player)
	var cs := _combat(root)
	var ally := FollowAlly.deploy(root, player, cs, 0)
	_enemy(root, cs, Vector2(600, 0))            # 距 600 > 240：索敌圈外
	for frame in range(1, int(ally.row["cd_ticks"]) * 3 + 1):
		ally.tick(frame)
	assert_int(cs.active_count()).is_equal(0)    # 无目标不开火


func test_follower_targets_nearest_enemy() -> void:
	var root := _root()
	var player: Node2D = auto_free(Node2D.new())
	player.position = Vector2.ZERO
	root.add_child(player)
	var cs := _combat(root)
	var ally := FollowAlly.deploy(root, player, cs, 0)
	ally.brain_pos = Vector2(0, 0)
	_enemy(root, cs, Vector2(-240, 0))           # 远敌在左（索敌半径内沿）
	var near := _enemy(root, cs, Vector2(60, 0))  # 近敌在右
	assert_object(near).is_not_null()
	var cadence := int(ally.row["cd_ticks"])
	for frame in range(1, cadence + 1):          # 开火节拍逐拍推进（tick 非快进语义）
		ally.tick(frame)
	var p: Projectile = cs.pool.active[0]
	# 弹幕朝向 240px 内最近者（右），而非更远者（左）——AutoAim 全向就近契约
	assert_float(p.vel.normalized().dot(Vector2.RIGHT)).is_equal_approx(1.0, 0.001)   # 朝 +x 轴向


# ================================================================ 5) 时限/死亡消散

func test_follower_expires_after_90s_by_injected_frames() -> void:
	var root := _root()
	var player: Node2D = auto_free(Node2D.new())
	root.add_child(player)
	var ally := FollowAlly.deploy(root, player, null, 0)
	var reasons: Array[String] = []
	ally.despawned.connect(func(reason: String) -> void: reasons.append(reason))
	assert_int(FollowAlly.LIFETIME_TICKS).is_equal(5400)        # 90s × 60fps
	ally.tick(FollowAlly.LIFETIME_TICKS - 1)
	assert_bool(ally.is_despawned()).is_false()  # 限期内存活
	ally.tick(FollowAlly.LIFETIME_TICKS)
	assert_bool(ally.is_despawned()).is_true()
	var expected: Array[String] = ["expired"]
	assert_array(reasons).is_equal(expected)
	assert_bool(ally.is_queued_for_deletion()).is_true()


func test_follower_despawns_on_player_fatal_damage_only() -> void:
	var root := _root()
	var player: Node2D = auto_free(Node2D.new())
	root.add_child(player)
	var ally := FollowAlly.deploy(root, player, null, 0)
	var reasons: Array[String] = []
	ally.despawned.connect(func(reason: String) -> void: reasons.append(reason))
	EventBus.player_damaged.emit(3, false)       # 非致命：随从留存
	assert_bool(ally.is_despawned()).is_false()
	assert_array(reasons).is_empty()
	EventBus.player_damaged.emit(10, true)       # 玩家死亡：随从消散
	assert_bool(ally.is_despawned()).is_true()
	var expected: Array[String] = ["player_dead"]
	assert_array(reasons).is_equal(expected)


# ================================================================ 6) 无敌简化 + 组纪律

func test_follower_is_invincible_by_disclosed_simplification() -> void:
	var root := _root()
	var player: Node2D = auto_free(Node2D.new())
	root.add_child(player)
	var cs := _combat(root)
	var ally := FollowAlly.deploy(root, player, cs, 0)
	ally.take_hit({"amount": 99, "is_crit": false, "element": Elements.Id.NONE,
		"from": Vector2.ZERO, "source_type": "projectile"})   # 敌方弹命中路径
	assert_bool(ally.is_despawned()).is_false()  # ★ take_hit no-op（头注双重披露）


func test_follower_group_discipline() -> void:
	var root := _root()
	var player: Node2D = auto_free(Node2D.new())
	root.add_child(player)
	var ally := FollowAlly.deploy(root, player, null, 0)
	assert_bool(ally.is_in_group(FollowAlly.GROUP)).is_true()
	assert_bool(ally.is_in_group("enemies")).is_false()   # 绝不被己方索敌当敌人
	assert_bool(ally.is_in_group("summons")).is_false()   # 不污染炮台库存计数


# ================================================================ 7) PLAYER 阵营注册

func test_follower_registered_as_player_faction_body() -> void:
	var root := _root()
	var player: Node2D = auto_free(Node2D.new())
	player.position = Vector2(500, 0)
	root.add_child(player)
	var cs := _combat(root)
	var ally := FollowAlly.deploy(root, player, cs, 0)
	# 己方（PLAYER 阵营）范围查询可见=注册为 PLAYER；敌方查询不可见=不在敌方阵营
	var as_player := cs.bodies_in_radius(ally.global_position, 12.0,
		Projectile.Faction.PLAYER)
	assert_array(as_player).has_size(1)
	assert_bool(as_player[0] == ally).is_true()
	assert_array(cs.bodies_in_radius(ally.global_position, 12.0,
		Projectile.Faction.ENEMY)).is_empty()


# ---------------------------------------------------------------- 工具

func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng
