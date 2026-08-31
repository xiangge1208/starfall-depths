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
