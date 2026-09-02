class_name TestBiomeA2
extends GdUnitTestSuite
## M2-T4：A2 生态——暗视野 + 冰面（GDD §10 A2 行）。
## 1) IceZone（纯逻辑，无头）：摩擦选择纯函数 ×0.25 / 区域命中 / tick 帧级进出接缝；
##    敌人无 friction_mult 接缝（冰面只影响玩家）。
## 2) Player 接缝（注入帧）：冰面上 velocity 衰减变慢、离开恢复（MoveMath friction
##    参数被 friction_mult 临时替换）。
## 3) BiomeFx 暗视野：CanvasModulate (0.25,0.25,0.35) + 玩家 PointLight2D（半径 140px、
##    能量 1.2）；剪影下限 modulate 0.4（公平性，按距单调）；光圈跟随玩家。
## 4) FloorScene 挂载：set_biome_a2(true/false) 挂载/卸载 + 冰面补丁常量演示
##    （A2 模板 JSON biome 字段后续卡替换）。

const PLAYER_SCENE := preload("res://core/player/player.tscn")
const SEED := 20260828
const SPAN_PX := 416.0


# ---------------------------------------------------------------- 构建体替身（同 test_floor_scene 习语）

func _room(id: int, type: String, grid: Vector2i, next: Array) -> Dictionary:
	var tid := "combat_a1_01"
	if type == "start":
		tid = "start_a1"
	elif type == "boss":
		tid = "boss_a1"
	return {
		"node": {"id": id, "type": type, "grid": grid, "depth": 0, "next": next},
		"template_id": tid, "world_pos": Vector2(grid) * SPAN_PX,
	}


func _typed_chain(types: Array) -> Dictionary:
	var rooms := {0: _room(0, "start", Vector2i(0, 0), [1])}
	var corridors: Array = []
	for i in types.size():
		var id := i + 1
		var nxt: Array = [] if i == types.size() - 1 else [id + 1]
		rooms[id] = _room(id, String(types[i]), Vector2i(i + 1, 0), nxt)
		corridors.append({"a": id - 1, "b": id, "dir": "E"})
	return {"rooms": rooms, "corridors": corridors, "start_room_id": 0, "boss_room_id": -1}


var _fs: FloorScene = null


func _make_scene(build: Dictionary) -> FloorScene:
	var player: Player = (PLAYER_SCENE as PackedScene).instantiate() as Player
	_fs = FloorScene.new()
	add_child(_fs)
	_fs.setup(build, player)
	return _fs


func _player() -> Player:
	var p: Player = (PLAYER_SCENE as PackedScene).instantiate() as Player
	auto_free(p)
	add_child(p)
	return p


func before_test() -> void:
	for action in ["move_left", "move_right", "move_up", "move_down",
			"touch_move_left", "touch_move_right", "touch_move_up", "touch_move_down"]:
		Input.action_release(action)


func after_test() -> void:
	if _fs != null and is_instance_valid(_fs):
		_fs.free()
		_fs = null


# ---------------------------------------------------------------- IceZone 纯逻辑

func test_effective_friction_on_normal_ground_unchanged() -> void:
	assert_float(IceZone.effective_friction(Player.FRICTION, false)).is_equal(Player.FRICTION)
	assert_float(IceZone.effective_friction(1800.0, false)).is_equal(1800.0)


func test_effective_friction_on_ice_is_quarter() -> void:
	assert_float(IceZone.FRICTION_MULT).is_equal(0.25)
	assert_float(IceZone.effective_friction(Player.FRICTION, true)).is_equal(450.0)
	assert_float(IceZone.effective_friction(1.0, true)).is_equal(0.25)


func test_zone_point_hit_and_miss() -> void:
	var ice := IceZone.new()
	ice.add_zone(Rect2(0, 0, 64, 64))
	assert_bool(ice.in_ice(Vector2(32, 32))).is_true()
	assert_bool(ice.in_ice(Vector2(100, 32))).is_false()
	ice.add_zone(Rect2(200, 0, 32, 32))
	assert_bool(ice.in_ice(Vector2(216, 16))).is_true()


func test_tick_sets_player_friction_mult_on_enter_and_restores_on_leave() -> void:
	var ice := IceZone.new()
	ice.add_zone(Rect2(0, 0, 64, 64))
	var p := _player()
	p.position = Vector2(32, 32)
	ice.tick(p)                                    # 进入：进入替换
	assert_float(p.friction_mult).is_equal(IceZone.FRICTION_MULT)
	p.position = Vector2(500, 500)
	ice.tick(p)                                    # 离开：离开恢复
	assert_float(p.friction_mult).is_equal(1.0)


func test_ice_never_touches_enemies() -> void:
	# 敌人不受冰面影响（GDD §10 A2）：接缝只存在于 Player（friction_mult 字段），
	# IceZone.tick 只写玩家——敌人身上没有任何可被冰面写入的摩擦状态。
	var enemy := EnemyBase.new()
	auto_free(enemy)
	assert_bool("friction_mult" in enemy).is_false()
	var ice := IceZone.new()
	ice.add_zone(Rect2(0, 0, 64, 64))
	enemy.position = Vector2(32, 32)
	assert_bool(ice.in_ice(enemy.global_position)).is_true()   # 区域命中也不产生效果载体


# ---------------------------------------------------------------- Player 接缝（注入帧）

func test_player_friction_mult_defaults_to_one() -> void:
	var p := _player()
	assert_float(p.friction_mult).is_equal(1.0)


func test_player_velocity_decays_slower_on_ice_and_restores_off() -> void:
	var ice := IceZone.new()
	ice.add_zone(Rect2(-32, -32, 64, 64))
	var p := _player()
	p.position = Vector2.ZERO
	# 常规地面：1 帧摩擦 1800/60=30 → 80→50
	p.velocity = Vector2(Player.MOVE_SPEED, 0)
	p._physics_process(0.0)
	assert_float(p.velocity.x).is_equal_approx(50.0, 0.001)
	# 进入冰面（帧级注入）：摩擦 450/60=7.5 → 衰减显著变慢
	p.position = Vector2.ZERO                       # 区域内
	ice.tick(p)
	assert_float(p.friction_mult).is_equal(0.25)
	p.velocity = Vector2(Player.MOVE_SPEED, 0)
	p._physics_process(0.0)
	assert_float(p.velocity.x).is_equal_approx(72.5, 0.001)
	# 离开冰面：恢复常规摩擦
	p.position = Vector2(500, 0)
	ice.tick(p)
	p.velocity = Vector2(Player.MOVE_SPEED, 0)
	p._physics_process(0.0)
	assert_float(p.velocity.x).is_equal_approx(50.0, 0.001)


# ---------------------------------------------------------------- BiomeFx 暗视野

func _fx() -> BiomeFx:
	var fx := BiomeFx.new()
	fx.setup(_player())
	auto_free(fx)
	add_child(fx)          # _ready 建 CanvasModulate + PointLight2D
	return fx


func _canvas_modulate_of(fx: BiomeFx) -> CanvasModulate:
	for child in fx.get_children():
		if child is CanvasModulate:
			return child
	return null


func _light_of(fx: BiomeFx) -> PointLight2D:
	for child in fx.get_children():
		if child is PointLight2D:
			return child
	return null


func test_dark_vision_constants_match_gdd_a2() -> void:
	assert_object(BiomeFx.DARK_COLOR).is_equal(Color(0.25, 0.25, 0.35))
	assert_float(BiomeFx.LIGHT_RADIUS_PX).is_equal(140.0)
	assert_float(BiomeFx.LIGHT_ENERGY).is_equal(1.2)
	assert_float(BiomeFx.SILHOUETTE_FLOOR).is_equal(0.4)


func test_setup_mounts_canvas_modulate_and_player_light() -> void:
	var fx := _fx()
	var cm := _canvas_modulate_of(fx)
	assert_object(cm).is_not_null()
	if cm != null:
		assert_object(cm.color).is_equal(Color(0.25, 0.25, 0.35))
	var light := _light_of(fx)
	assert_object(light).is_not_null()
	if light != null:
		# energy 经引擎属性按 float32 往返（1.2 → 1.20000004…），逐位相等必假相等。
		assert_float(light.energy).is_equal_approx(1.2, 0.0001)
		# 有效光半径 = 纹理半宽 × texture_scale ≈ 140px
		var radius: float = light.texture.get_size().x * 0.5 * light.texture_scale
		assert_float(radius).is_equal_approx(140.0, 0.5)
		# 二次衰减 (1-d)^2：半半径处强度 ≈ 0.25（分段线性锚点）
		var gt := light.texture as GradientTexture2D
		if gt != null and gt.gradient != null:
			assert_float(gt.gradient.sample(0.5).a).is_equal_approx(0.25, 0.01)


func test_silhouette_modulate_monotonic_to_floor() -> void:
	assert_float(BiomeFx.silhouette_modulate(0.0)).is_equal(1.0)
	assert_float(BiomeFx.silhouette_modulate(BiomeFx.LIGHT_RADIUS_PX)).is_equal(0.4)
	assert_float(BiomeFx.silhouette_modulate(1000.0)).is_equal(0.4)   # 光圈外下限（剪影可辨）
	var prev := 1.1
	for d in [0, 35, 70, 105, 140, 280, 1000]:
		var m: float = BiomeFx.silhouette_modulate(float(d))
		assert_bool(m <= prev).is_true()
		prev = m


func test_process_dims_far_enemies_and_restore_resets() -> void:
	var fx := _fx()
	var player: Player = fx.player
	var near: EnemyBase = auto_free(EnemyBase.new())
	near.position = player.global_position + Vector2(20, 0)
	near.add_to_group("enemies")
	add_child(near)
	var far: EnemyBase = auto_free(EnemyBase.new())
	far.position = player.global_position + Vector2(600, 0)
	far.add_to_group("enemies")
	add_child(far)
	fx._process(0.0)
	# 近敌按剪影曲线取值（20px → ≈0.914），仍显著亮于圈外下限 0.4。
	assert_float(near.modulate.r).is_equal_approx(BiomeFx.silhouette_modulate(20.0), 0.001)
	assert_float(near.modulate.r).is_greater(BiomeFx.SILHOUETTE_FLOOR)
	assert_object(far.modulate).is_equal(Color(BiomeFx.SILHOUETTE_FLOOR,
		BiomeFx.SILHOUETTE_FLOOR, BiomeFx.SILHOUETTE_FLOOR))
	fx.restore_enemies()
	assert_object(near.modulate).is_equal(Color.WHITE)
	assert_object(far.modulate).is_equal(Color.WHITE)


func test_light_follows_player_every_frame() -> void:
	var fx := _fx()
	var light := _light_of(fx)
	assert_object(light).is_not_null()
	if light == null:
		return
	fx.player.global_position = Vector2(123, 45)
	fx._process(0.0)
	assert_vector(light.global_position).is_equal_approx(Vector2(123, 45), Vector2(0.01, 0.01))


func test_process_without_player_is_safe_noop() -> void:
	var fx := BiomeFx.new()          # 未 setup：无玩家引用
	auto_free(fx)
	add_child(fx)
	assert_object(fx.player).is_null()
	fx._process(0.0)                 # 不得报错


# ---------------------------------------------------------------- FloorScene 挂载

func test_set_biome_a2_mounts_fx_and_ice_zones() -> void:
	var fs := _make_scene(_typed_chain(["combat"]))
	assert_bool(fs.biome_a2).is_false()
	assert_object(fs.biome_fx).is_null()
	fs.set_biome_a2(true)
	assert_bool(fs.biome_a2).is_true()
	assert_object(fs.biome_fx).is_not_null()
	assert_object(fs.biome_fx.player).is_same(fs.player_node())
	assert_object(_canvas_modulate_of(fs.biome_fx)).is_not_null()
	assert_object(_light_of(fs.biome_fx)).is_not_null()
	# 冰面补丁：每房一块（常量演示，A2 模板 biome 字段后续卡驱动）
	assert_object(fs.biome_ice).is_not_null()
	if fs.biome_ice != null:
		assert_int(fs.biome_ice.zones.size()).is_equal(fs.room_count())
	# set_biome_a2(true) 幂等：不重复挂载
	var zone_count: int = fs.biome_ice.zones.size()
	fs.set_biome_a2(true)
	assert_int(fs.biome_ice.zones.size()).is_equal(zone_count)


func test_floor_tick_applies_ice_to_player_by_position() -> void:
	var fs := _make_scene(_typed_chain(["combat"]))
	fs.set_biome_a2(true)
	var p := fs.player_node()
	# 玩家出生在 start 房中心 → 冰面补丁中心：一帧后 friction_mult = 0.25
	fs._physics_process(0.0)
	assert_float(p.friction_mult).is_equal(0.25)
	# 移出补丁（仍在房内）：恢复 1.0
	p.global_position = fs.room_rect(0).get_center() + Vector2(140, 0)
	fs._physics_process(0.0)
	assert_float(p.friction_mult).is_equal(1.0)


func test_set_biome_a2_disable_unmounts_and_restores() -> void:
	var fs := _make_scene(_typed_chain(["combat"]))
	fs.set_biome_a2(true)
	fs._physics_process(0.0)
	assert_float(fs.player_node().friction_mult).is_equal(0.25)
	fs.set_biome_a2(false)
	assert_bool(fs.biome_a2).is_false()
	assert_object(fs.biome_fx).is_null()
	assert_object(fs.biome_ice).is_null()
	assert_float(fs.player_node().friction_mult).is_equal(1.0)
	# 再关一次：幂等 no-op
	fs.set_biome_a2(false)
	assert_float(fs.player_node().friction_mult).is_equal(1.0)


## Major-1 回归（楼层销毁路径）：run_root 换层直接 queue_free 旧 FloorScene，
## 不经 set_biome_a2(false)；层间 PROCESS_MODE_DISABLED 已冻结 tick——站冰面
## 换层不得把 0.25 泄漏到下一层。玩家先挂测试树（镜像 RunRoot 持有），free 层
## 后存活，BiomeFx._exit_tree 须复位其摩擦。
func test_floor_free_without_disable_restores_player_friction() -> void:
	var player: Player = (PLAYER_SCENE as PackedScene).instantiate() as Player
	auto_free(player)
	add_child(player)                    # 先入树 → setup 不收养，层销毁后玩家存活
	var fs := FloorScene.new()
	_fs = fs                             # 断言中途失败时由 after_test 兜底回收
	add_child(fs)
	fs.setup(_typed_chain(["combat"]), player)
	fs.set_biome_a2(true)
	fs._physics_process(0.0)             # 玩家站 start 房冰面补丁中心
	assert_float(player.friction_mult).is_equal(0.25)
	fs.free()                            # 直接销毁（不走 set_biome_a2(false)）
	assert_float(player.friction_mult).is_equal(1.0)


# ---------------------------------------------------------------- m2-t37 光圈批处理（lit-mask 收口）
## §18.3 F2 draw call 超标根因（m2-t37 实测归因，见 task-37 报告）：光圈默认
## cull_mask=1 使画布上全部条目（弹幕/伤害数字/FX 粒子…）参与逐项光照重渲，
## 批处理沿 lit/unlit 状态翻转碎裂 → O(穿越次数) 增量（40 敌满压下 ~+33~+45）。
## 修复：光圈收口到专属位 LIT_ITEM_MASK=2——只有 opt-in 的世界条目（静态地形面/
## 陈设 + 敌人剪影 + 玩家外观）被照亮；高计数瞬态条目（弹幕/伤害数字/粒子）不再
## 参与。实测 opt-in 配置回到无光圈基线（~110-119 vs 全亮 ~150+，探针证据见报告）。

func test_light_cull_mask_is_dedicated_bit_not_default() -> void:
	# 专属位 2（默认可见位 1 不再有光圈参与）：弹幕/伤害数字/FX 走默认位 → 零逐项重渲
	assert_int(BiomeFx.LIT_ITEM_MASK).is_equal(2)
	assert_int(BiomeFx.LIT_ITEM_MASK).is_not_equal(1)
	var fx := _fx()
	var light := _light_of(fx)
	assert_object(light).is_not_null()
	if light != null:
		assert_int(light.range_item_cull_mask).is_equal(BiomeFx.LIT_ITEM_MASK)


func test_dressed_enemy_sprite_opts_into_lit_mask() -> void:
	# 敌人剪影仍被光圈真实照亮（opt-in）：dress_enemy_sprite 产出的精灵在专属位上
	var e := EnemyBase.new()
	auto_free(e)
	add_child(e)
	assert_bool(ArtLookup.dress_enemy_sprite(e, {"id": "kuli_bug", "radius": 6.0})).is_true()
	var spr := e.get_node("Sprite") as Sprite2D
	assert_object(spr).is_not_null()
	if spr != null:
		assert_int(spr.light_mask).is_equal(BiomeFx.LIT_ITEM_MASK)


func test_world_tile_and_prop_sprites_opt_into_lit_mask() -> void:
	# 静态世界面（平铺地板/墙 + 单图陈设/门/危险地块）opt-in——lit-tiles 配置
	# 实测零增量（回无光圈基线）；走 ArtLookup 工厂统一落位
	var tiled := ArtLookup.make_tiled(ArtLookup.tile_path("floor_cave"), Rect2(0, 0, 64, 64))
	auto_free(tiled)
	assert_object(tiled).is_not_null()
	if tiled != null:
		assert_int(tiled.light_mask).is_equal(BiomeFx.LIT_ITEM_MASK)
	var prop := ArtLookup.make_sprite(ArtLookup.tile_path("prop_crate"))
	auto_free(prop)
	assert_object(prop).is_not_null()
	if prop != null:
		assert_int(prop.light_mask).is_equal(BiomeFx.LIT_ITEM_MASK)


func test_setup_opts_player_sprite_into_lit_mask() -> void:
	# 玩家外观同样 opt-in（光圈中心玩家亮度与既往行为一致）；缺 Sprite 节点静默跳过
	var p := _player()
	assert_int(p.get_node("Sprite").light_mask).is_equal(1)   # 场景默认位
	var fx := BiomeFx.new()
	auto_free(fx)
	fx.setup(p)
	assert_int(p.get_node("Sprite").light_mask).is_equal(BiomeFx.LIT_ITEM_MASK)


# ---------------------------------------------------------------- fix1（评审 Important-1）：弹幕可读性折叠
## T37 首轮把弹幕留在默认位（不参与光圈重渲）——评审指出飞行敌弹是 A2 图的主要
## 威胁刺激，失去光圈增亮是玩家可见的最大保真损失。实测两条路（探针口径）：
##   - 弹幕进光照参与集：diag +3.7 但探针 F2 100.4 → ~148（+47，预算下不可接受）；
##   - self_modulate 折叠（本落点）：逐项 modulate 写入零批处理成本（首轮矩阵
##     f2_nomod 实证），近似既往光圈加亮曲线。
## 预警纹（地面红纹等）计数小、走真实光照参与集（见下组测试）。

func test_bullet_aid_monotonic_falloff_matches_aura_curve() -> void:
	assert_object(BiomeFx.bullet_aid(0.0, BiomeFx.LIGHT_RADIUS_PX)) \
		.is_equal(Color(1.0 + BiomeFx.LIGHT_ENERGY, 1.0 + BiomeFx.LIGHT_ENERGY,
			1.0 + BiomeFx.LIGHT_ENERGY))                       # 光圈中心最大增亮
	# 单调衰减；光圈边与圈外 = WHITE（无增亮，不低于原亮度）
	var prev := 2.3
	for d in [0, 35, 70, 105, 139, 140, 200, 1000]:
		var c := BiomeFx.bullet_aid(float(d), BiomeFx.LIGHT_RADIUS_PX)
		assert_float(c.r).is_less_equal(prev)
		prev = c.r
	assert_object(BiomeFx.bullet_aid(BiomeFx.LIGHT_RADIUS_PX, BiomeFx.LIGHT_RADIUS_PX)) \
		.is_equal(Color.WHITE)
	assert_object(BiomeFx.bullet_aid(1000.0, BiomeFx.LIGHT_RADIUS_PX)).is_equal(Color.WHITE)
	assert_object(BiomeFx.bullet_aid(10.0, 0.0)).is_equal(Color.WHITE)   # 无光圈口径


func test_aura_gradient_matches_texture_anchor() -> void:
	# 复刻 _aura_texture 渐变锚点：中心 1.0 / 半半径 0.25 / 边缘 0.0
	assert_float(BiomeFx.aura_gradient(0.0)).is_equal(1.0)
	assert_float(BiomeFx.aura_gradient(0.25)).is_equal(0.625)
	assert_float(BiomeFx.aura_gradient(0.5)).is_equal(0.25)
	assert_float(BiomeFx.aura_gradient(1.0)).is_equal(0.0)


func test_floor_bullet_visuals_get_aura_brightness_aid() -> void:
	# 表现层弹幕镜像（floor_scene 共享池）：A2 下光圈内弹幕 self_modulate > 1，
	# 无暗视野组件时复位 WHITE（池化跨层安全）；光照参与集保持默认位（零重渲）。
	var fs := _make_scene(_typed_chain(["combat"]))
	fs.set_biome_a2(true)
	fs.enter_room(1)
	var room := fs.room_node(1)
	fs.player.global_position = fs.room_rect(1).get_center()   # 玩家与弹同点（光圈中心）
	room.combat.spawn_projectile({
		"pos": fs.player.position, "vel": Vector2(60, 0), "damage": 0,
		"faction": Projectile.Faction.ENEMY, "radius": 3.0, "life_seconds": 5.0,
	})
	fs._sync_bullet_visuals()
	assert_int(fs._bullet_sprites.size()).is_greater(0)
	if fs._bullet_sprites.size() > 0:
		var vis := fs._bullet_sprites[0]
		assert_int(vis.light_mask).is_equal(1)             # 不参与光照重渲（零 draw 成本）
		assert_float(vis.self_modulate.r).is_greater(1.0)  # 光圈内增亮生效
	# 卸载暗视野：下一次同步复位 WHITE（池化不泄漏）
	fs.set_biome_a2(false)
	fs._sync_bullet_visuals()
	if fs._bullet_sprites.size() > 0:
		assert_object(fs._bullet_sprites[0].self_modulate).is_equal(Color.WHITE)


# ---------------------------------------------------------------- m4-k3（K-3 披露收口）：伤害数字/FX 粒子增亮折叠
## T37 报告 §四.2 披露：伤害数字/FX 粒子留在默认位 1，不再被光圈照亮。K-3 以
## bullet_aid 同形 self_modulate 折叠收口（弹幕先例：逐项 modulate 写入零批处理
## 成本，f2_nomod 实证；真实光照参与集 +47 draw 已被否决）。状态源/半径/强度全走
## BiomeFx 既有口径（light_radius_px 含 _vision_factor 缩径），不建第二套。
## 表现侧折叠：零判定影响；随 bullet_aid 先例不发遥测（先查无既有事件口径）。

func test_light_aid_at_matches_bullet_aid_curve_and_falls_back() -> void:
	# 只读查询（m4-k3）：无暗视野组件（F1/F3/训练房/测试树常态）→ WHITE 零漂移
	assert_object(BiomeFx.light_aid_at(Vector2.ZERO)).is_equal(Color.WHITE)
	var fs := _make_scene(_typed_chain(["combat"]))
	fs.set_biome_a2(true)
	fs.enter_room(1)
	fs.player.global_position = fs.room_rect(1).get_center()
	var center := fs.player.global_position
	var radius: float = fs.biome_fx.light_radius_px
	# 光圈内逐点与 bullet_aid 曲线逐值一致（同 aura_gradient / LIGHT_ENERGY / 缩径口径）
	assert_object(BiomeFx.light_aid_at(center)).is_equal(BiomeFx.bullet_aid(0.0, radius))
	assert_object(BiomeFx.light_aid_at(center + Vector2(radius * 0.5, 0.0))) \
		.is_equal(BiomeFx.bullet_aid(radius * 0.5, radius))
	# 圈外零漂移：WHITE（增亮不低于原亮度、不产生圈外亮度差）
	assert_object(BiomeFx.light_aid_at(center + Vector2(radius + 10.0, 0.0))) \
		.is_equal(Color.WHITE)
	# 光圈消失回落：unmount 走 queue_free（延迟一帧），组件消亡（_exit_tree）后查询回落
	fs.set_biome_a2(false)
	assert_object(BiomeFx.light_aid_at(center)).is_not_equal(Color.WHITE)  # 消亡前一帧仍在（unmount 语义）
	await get_tree().process_frame
	assert_object(BiomeFx.light_aid_at(center)).is_equal(Color.WHITE)


func test_damage_numbers_get_aura_brightness_aid_and_fall_back() -> void:
	var settings_before: Dictionary = (SaveSystem.data.get("settings", {}) as Dictionary) \
		.duplicate(true)
	SaveSystem.data["settings"] = settings_before.duplicate(true)
	SaveSystem.data["settings"]["damage_numbers"] = true
	var fs := _make_scene(_typed_chain(["combat"]))
	fs.set_biome_a2(true)
	fs.enter_room(1)
	fs.player.global_position = fs.room_rect(1).get_center()
	var center := fs.player.global_position
	var radius: float = fs.biome_fx.light_radius_px
	# J4 视野裁剪缝：注入大矩形（无头/相机位不确定，与裁剪测试同缝，与本案无关）
	Fx.visible_world_rect_provider = func() -> Rect2:
		return Rect2(-100000.0, -100000.0, 200000.0, 200000.0)
	var in_label := Fx.spawn_damage_number(center, 12, false)
	assert_object(in_label).is_not_null()
	if in_label != null:
		assert_int(in_label.light_mask).is_equal(1)              # 不进光照参与集（折叠前提）
		assert_float(in_label.self_modulate.r).is_greater(1.0)   # 光圈内增亮（spawn 即生效）
	# 圈外零漂移：WHITE
	var out_label := Fx.spawn_damage_number(center + Vector2(radius + 40.0, 0.0), 7, false)
	assert_object(out_label).is_not_null()
	if out_label != null:
		assert_object(out_label.self_modulate).is_equal(Color.WHITE)
	# 逐帧刷新跟随：玩家移到原圈外点 → 原圈内数字回落、原圈外数字增亮（表现跟随光圈）
	fs.player.global_position = center + Vector2(radius + 40.0, 0.0)
	Fx._refresh_damage_number_aid()
	if in_label != null:
		assert_object(in_label.self_modulate).is_equal(Color.WHITE)
	if out_label != null:
		assert_float(out_label.self_modulate.r).is_greater(1.0)
	# 光圈消失回落：卸载（queue_free 延迟一帧）→ 刷新复位 WHITE（池化/跨层不泄漏）
	fs.set_biome_a2(false)
	await get_tree().process_frame
	Fx._refresh_damage_number_aid()
	if in_label != null:
		assert_object(in_label.self_modulate).is_equal(Color.WHITE)
	Fx.visible_world_rect_provider = Callable()
	SaveSystem.data["settings"] = settings_before
	if in_label != null:
		in_label.queue_free()
	if out_label != null:
		out_label.queue_free()


func test_particles_get_aura_brightness_aid_and_fall_back() -> void:
	var fs := _make_scene(_typed_chain(["combat"]))
	fs.set_biome_a2(true)
	fs.enter_room(1)
	fs.player.global_position = fs.room_rect(1).get_center()
	var center := fs.player.global_position
	var radius: float = fs.biome_fx.light_radius_px
	Fx.particles.play("spark_hit", center)
	var u: ParticlesPool.Unit = null
	for cand: ParticlesPool.Unit in Fx.particles.units():
		if cand.playing:
			u = cand
			break
	assert_object(u).is_not_null()
	if u != null:
		assert_int(u.light_mask).is_equal(1)                     # 不进光照参与集（折叠前提）
		assert_float(u.self_modulate.r).is_greater(1.0)          # 光圈内增亮（play 首帧写入）
	# 圈外零漂移：WHITE
	Fx.particles.play("spark_hit", center + Vector2(radius + 40.0, 0.0))
	var v: ParticlesPool.Unit = null
	for cand: ParticlesPool.Unit in Fx.particles.units():
		if cand.playing and cand != u:
			v = cand
			break
	assert_object(v).is_not_null()
	if v != null:
		assert_object(v.self_modulate).is_equal(Color.WHITE)
	# 逐帧刷新跟随：玩家移到原圈外点 → 原圈内单元回落、原圈外单元增亮
	fs.player.global_position = center + Vector2(radius + 40.0, 0.0)
	Fx.particles.step(1.0 / 60.0)
	if u != null:
		assert_object(u.self_modulate).is_equal(Color.WHITE)
	if v != null:
		assert_float(v.self_modulate.r).is_greater(1.0)
	# 光圈消失回落：卸载（queue_free 延迟一帧）→ step 复位 WHITE（池化不泄漏）
	fs.set_biome_a2(false)
	await get_tree().process_frame
	Fx.particles.step(1.0 / 60.0)
	if u != null:
		assert_object(u.self_modulate).is_equal(Color.WHITE)
	if v != null:
		assert_object(v.self_modulate).is_equal(Color.WHITE)
	Fx.particles.step(1.0)   # 回收清理：不向后续用例/套件泄漏活跃单元


func test_hazard_telegraph_visuals_opt_into_lit_mask() -> void:
	# 地面预警纹（地刺瓦片/滚石预警道/间歇泉瓦片）创建即 opt-in——伤害预告刺激
	# 在暗视野下保持 T37 前亮度；火雨红圈同口径（schedule_fire_rain 楼层级）。
	var fs := _make_scene(_typed_chain(["combat"]))
	var room := fs.room_node(1)
	fs._build_spikes(room, [3, 3], fs.room_rect(1).position + Vector2(64, 64))
	fs._build_rock(room, {"side": "W"}, fs.room_rect(1).position + Vector2(96, 64))
	fs._build_geyser(room, [2, 2], fs.room_rect(1).position + Vector2(128, 64))
	assert_int(fs._spikes_vis.size()).is_greater(0)
	if fs._spikes_vis.size() > 0:
		assert_int(fs._spikes_vis[0].light_mask).is_equal(BiomeFx.LIT_ITEM_MASK)
	assert_int(fs._rock_line_vis.size()).is_greater(0)
	if fs._rock_line_vis.size() > 0:
		assert_int(fs._rock_line_vis[0].light_mask).is_equal(BiomeFx.LIT_ITEM_MASK)
	assert_int(fs._rock_vis.size()).is_greater(0)
	if fs._rock_vis.size() > 0:
		assert_int(fs._rock_vis[0].light_mask).is_equal(BiomeFx.LIT_ITEM_MASK)
	assert_int(fs._geyser_vis.size()).is_greater(0)
	if fs._geyser_vis.size() > 0:
		assert_int(fs._geyser_vis[0].light_mask).is_equal(BiomeFx.LIT_ITEM_MASK)
	fs.schedule_fire_rain(fs.room_rect(1).get_center())
	assert_int(fs._fire_rain_vis.size()).is_greater(0)
	if fs._fire_rain_vis.size() > 0:
		assert_int(fs._fire_rain_vis[0].light_mask).is_equal(BiomeFx.LIT_ITEM_MASK)
