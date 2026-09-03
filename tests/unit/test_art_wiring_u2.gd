class_name TestArtWiringU2
extends GdUnitTestSuite
## m4p-u2 可玩性收口 u2 卡：把「图在盘、代码零引用」走查探针改写为正式回归——
## 1) Boss 贴图：A2 池三只（gem_queen/prism_golem/frost_widow）+ 静态 Boss 行全部
##    有图且装配成功（无色块 fallback）；
## 2) Boss 血条：boss_bar_frame/fill 接线 HUD，boss_target 存活态显隐 + hp/hp_max 同步，
##    FloorScene 进 Boss 房注册 / Boss 死亡清除；
## 3) 设施贴图：商店（商人/黑市款）/熔铸台/饮料机/神像/事件装置/层间出口水晶/
##    喷泉两态/地刺/间歇喷口/残骸贴花 —— 房间/实体内 Sprite 存在且贴图非空；
## 4) HUD 图标系：红心格/盾条/蓝条/金币 icon_*.png TextureRect 接线 +
##    vignette_lowhp.png 低血红晕（色块仅缺图回落）。

const SPAN_PX := 416.0


# ---------------------------------------------------------------- 构建替身（同 test_floor_scene 习语）

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
		var grid := Vector2i(i + 1, 0)
		var nxt: Array = [] if i == types.size() - 1 else [id + 1]
		rooms[id] = _room(id, String(types[i]), grid, nxt)
		corridors.append({"a": id - 1, "b": id, "dir": "E"})
	return {"rooms": rooms, "corridors": corridors, "start_room_id": 0, "boss_room_id": -1}


var _fs: FloorScene = null


func _make_scene(build: Dictionary) -> FloorScene:
	var player: Player = (load("res://core/player/player.tscn") as PackedScene).instantiate() as Player
	_fs = FloorScene.new()
	add_child(_fs)
	_fs.setup(build, player)
	return _fs


func after_test() -> void:
	if _fs != null and is_instance_valid(_fs):
		_fs.free()
		_fs = null


func _find_enemy(room: FloorScene.FloorRoom, id: String) -> EnemyBase:
	for e in room.enemies:
		if is_instance_valid(e) and String(e.row.get("id", "")) == id \
				and e.state != EnemyBase.State.DEAD:
			return e
	return null


# ---------------------------------------------------------------- 1) Boss 贴图

func test_a2_boss_pool_all_have_sprites_no_color_block_fallback() -> void:
	# 走查探针 no-art=2 收口：A2 池三只全部表命中 + 盘上有图 + 装配成功
	for id: String in ["gem_queen", "prism_golem", "frost_widow"]:
		var row := GameDB.get_enemy(id)
		assert_bool(row.is_empty()).is_false()
		var path := ArtLookup.sprite_for_enemy(row)
		assert_str(path).is_not_empty()
		assert_bool(FileAccess.file_exists(path)).is_true()
		var host: Node2D = auto_free(Node2D.new())
		assert_bool(ArtLookup.dress_enemy_sprite(host, row)).is_true()
		var spr := host.get_node_or_null("Sprite") as Sprite2D
		assert_object(spr).is_not_null()
		assert_object(spr.texture).is_not_null()


func test_static_boss_rows_have_textures_on_disk() -> void:
	# A1/A3 静态 Boss + 隐藏 Boss 同契约（ENEMY_TEXTURES 全表存在性另由
	# test_art_lookup 钉死，此处钉 Boss 行无遗漏）
	for id: String in ["vine_colossus", "magma_tyrant", "starfall_prophet"]:
		var path := ArtLookup.enemy_texture_path(id)
		assert_str(path).is_not_empty()
		assert_bool(FileAccess.file_exists(path)).is_true()


# ---------------------------------------------------------------- 2) Boss 血条

func test_hud_boss_bar_wired_and_syncs_alive_boss() -> void:
	var hud: HUD = auto_free(HUD.new())
	hud.player = auto_free(Player.new())
	add_child(hud)
	# 贴图接线：frame + fill 非空
	assert_object(hud._boss_bar.texture_under).is_not_null()
	assert_str((hud._boss_bar.texture_under as Texture2D).resource_path) \
		.contains("boss_bar_frame")
	assert_object(hud._boss_bar.texture_progress).is_not_null()
	assert_str((hud._boss_bar.texture_progress as Texture2D).resource_path) \
		.contains("boss_bar_fill")
	# 缺省（无 boss_target）恒隐藏——非 Boss 房不占 HUD
	assert_bool(hud._boss_bar.visible).is_false()
	# 存活 Boss：亮条 + max=hp_max、value=hp（EnemyBase 公开字段查询缝）
	var boss: BossBase = auto_free(BossBase.new())
	boss._test_init({"id": "prism_golem", "hp": 1000, "archetype": "boss",
		"phases": [1.0, 0.6, 0.3]})
	hud.boss_target = boss
	hud._apply_boss_bar()
	assert_bool(hud._boss_bar.visible).is_true()
	assert_int(int(hud._boss_bar.max_value)).is_equal(1000)
	assert_int(int(hud._boss_bar.value)).is_equal(1000)
	boss.hp = 400
	hud._apply_boss_bar()
	assert_int(int(hud._boss_bar.value)).is_equal(400)
	# 死亡/清除：条隐藏
	boss.state = EnemyBase.State.DEAD
	hud._apply_boss_bar()
	assert_bool(hud._boss_bar.visible).is_false()
	hud.boss_target = null
	hud._apply_boss_bar()
	assert_bool(hud._boss_bar.visible).is_false()


func test_floor_scene_registers_and_clears_boss_target() -> void:
	# 进 Boss 房：真实 Boss 嘉宾（BossBase 子类）注册即上条；死亡即摘条
	var fs := _make_scene(_typed_chain(["boss"]))
	assert_object(fs.hud).is_not_null()
	assert_object(fs.hud.boss_target).is_null()
	assert_bool(fs.enter_room(1)).is_true()
	var boss := _find_enemy(fs.room_node(1), "vine_colossus")
	assert_object(boss).is_not_null()
	assert_object(fs.hud.boss_target).is_same(boss)
	boss.take_hit({"amount": 9999, "is_crit": false, "element": 0,
		"from": boss.global_position})
	assert_object(fs.hud.boss_target).is_null()


# ---------------------------------------------------------------- 3) 设施贴图

func test_shop_and_event_facility_sprites_in_rooms() -> void:
	var fs := _make_scene(_typed_chain(["shop", "event"]))
	# shop 房：商人世界形象（普通/黑市款按 black 旗；两款都属 shopkeeper 贴图）
	assert_bool(fs.enter_room(1)).is_true()
	var shop: Shop = null
	for c in fs.room_node(1).get_children():
		if c is Shop:
			shop = c
	assert_object(shop).is_not_null()
	var keeper := shop.get_node_or_null("Sprite") as Sprite2D
	assert_object(keeper).is_not_null()
	assert_object(keeper.texture).is_not_null()
	assert_str(keeper.texture.resource_path).contains("shopkeeper")
	# event 房：事件设施贴图按掷中事件挂对应 NPC/装置图（event_* 家族）
	assert_bool(fs.enter_room(2)).is_true()
	var ev_sprite := fs.room_node(2).get_node_or_null("Sprite") as Sprite2D
	assert_object(ev_sprite).is_not_null()
	assert_object(ev_sprite.texture).is_not_null()
	assert_str(ev_sprite.texture.resource_path).contains("art/generated/tiles/event_")


func test_event_art_name_mapping_covers_all_events() -> void:
	var fs := _make_scene(_typed_chain(["event"]))
	assert_str(fs._event_art_name("mystery_merchant")).is_equal("event_merchant")
	assert_str(fs._event_art_name("beggar")).is_equal("event_beggar")
	assert_str(fs._event_art_name("star_spring")).is_equal("event_spring")
	assert_str(fs._event_art_name("graffiti")).is_equal("event_graffiti")
	assert_str(fs._event_art_name("")).is_equal("event_device")
	assert_str(fs._event_art_name("no_such")).is_equal("event_device")


func test_shrine_drink_forge_sprites_mounted() -> void:
	# 神像四属性贴图 + 未知 kind 不挂图（fail-closed 同 setup 契约）
	for kind: String in Shrine.KINDS:
		var shrine: Shrine = auto_free(Shrine.new().setup(kind))
		var spr := shrine.get_node_or_null("Sprite") as Sprite2D
		assert_object(spr).is_not_null()
		assert_str(spr.texture.resource_path).contains("shrine_%s" % kind)
	# 饮料机（世界实体）
	var drink: DrinkMachine = auto_free(DrinkMachine.new())
	add_child(drink)
	var dspr := drink.get_node_or_null("Sprite") as Sprite2D
	assert_object(dspr).is_not_null()
	assert_str(dspr.texture.resource_path).contains("drink_machine")
	# 熔铸台（场景实例）
	var forge: Forge = (load("res://ui/forge.tscn") as PackedScene).instantiate() as Forge
	auto_free(forge)
	add_child(forge)
	var fspr := forge.get_node_or_null("Sprite") as Sprite2D
	assert_object(fspr).is_not_null()
	assert_str(fspr.texture.resource_path).contains("fusion_forge")


func test_inter_floor_fountain_two_states_and_exit_crystal() -> void:
	var inter: InterFloor = auto_free(InterFloor.new())
	# 场景玩家（带 WeaponRig）：_wire_player 需 rig 接缝（裸 Player 会打引擎缺节点告警）
	var player: Player = (load("res://core/player/player.tscn") as PackedScene).instantiate() as Player
	auto_free(player)
	inter.setup(player, BuffManager.new(), 1)
	# 出口水晶：层间下一层门贴 exit_crystal.png
	var door := inter.get_node_or_null("NextFloorDoor") as Interactable
	assert_object(door).is_not_null()
	var dspr := door.get_node_or_null("Sprite") as Sprite2D
	assert_object(dspr).is_not_null()
	assert_str(dspr.texture.resource_path).contains("exit_crystal")
	# 喷泉两态：满水 fountain_full → 饮用后 fountain_used
	var fountain := inter.get_node_or_null("Fountain") as Interactable
	assert_object(fountain).is_not_null()
	var fspr := fountain.get_node_or_null("Sprite") as Sprite2D
	assert_object(fspr).is_not_null()
	assert_str(fspr.texture.resource_path).contains("fountain_full")
	# 推进 BUFF→FOUNTAIN（同 inter_floor_flow 契约）后交互
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	inter.flow.open_with_offerings(rng)
	assert_bool(inter.flow.choose_buff(inter.flow.offered[0])).is_true()
	inter._on_fountain_interact(player)
	assert_bool(inter.flow.fountain_used).is_true()
	assert_str(fspr.texture.resource_path).contains("fountain_used")


func test_hazard_tiles_use_sprites() -> void:
	# 地刺/间歇喷口：视觉从色块升格为 hazard_*.png（相位语义不变）
	var fs := _make_scene(_typed_chain(["combat"]))
	var room: FloorScene.FloorRoom = fs.room_node(1)
	fs._build_spikes(room, [1, 1], room.position + Vector2(64, 64))
	var spike_vis := fs._spikes_vis[fs._spikes_vis.size() - 1] as Sprite2D
	assert_object(spike_vis).is_not_null()
	assert_str(spike_vis.texture.resource_path).contains("hazard_spikes")
	fs._build_geyser(room, [2, 2], room.position + Vector2(96, 96))
	var geyser_vis := fs._geyser_vis[fs._geyser_vis.size() - 1] as Sprite2D
	assert_object(geyser_vis).is_not_null()
	assert_str(geyser_vis.texture.resource_path).contains("hazard_vent")


func test_prop_destruction_leaves_debris_sprite() -> void:
	var fs := _make_scene(_typed_chain(["combat"]))
	var room: FloorScene.FloorRoom = fs.room_node(1)
	var prop: DestructibleProp = auto_free(DestructibleProp.new())
	prop.setup("crate", 1, [] as Array[String], false,
		Rect2(room.position + Vector2(48, 48), Vector2(16, 16)), null)
	fs._on_prop_destroyed(prop, room)
	var debris := room.get_node_or_null("PropDebris") as Sprite2D
	assert_object(debris).is_not_null()
	assert_object(debris.texture).is_not_null()
	assert_str(debris.texture.resource_path).contains("prop_debris")


# ---------------------------------------------------------------- 4) HUD 图标系

func test_hud_icons_wired_texture_rects_replacing_color_blocks() -> void:
	var hud: HUD = auto_free(HUD.new())
	var p: Player = auto_free(Player.new())       # hp_max=8 → 8 红心格
	hud.player = p
	add_child(hud)                                # _ready 建全部图标节点
	var snap := HUD.hud_snapshot(p, hud.run, 0)
	hud._apply_top_left(snap)
	# 红心格贴图化（缺图回落路径才走 ColorRect）
	assert_bool(hud._hearts_textured).is_true()
	assert_int(hud._hearts.get_child_count()).is_equal(p.hp_max)
	assert_object(hud._hearts.get_child(0) as TextureRect).is_not_null()
	# 全 HUD 收集 TextureRect 贴图：四枚图标系 + 低血红晕全部在位
	var paths := {}
	for node in hud.find_children("*", "TextureRect", true, false):
		var t: Texture2D = (node as TextureRect).texture
		if t != null:
			paths[t.resource_path] = true
	for icon: String in ["icon_heart_full", "icon_shield", "icon_energy", "icon_coin"]:
		assert_bool(paths.has(ArtLookup.ui_texture_path(icon))).is_true()
	var vg := hud._vignette as TextureRect
	assert_object(vg).is_not_null()
	assert_str(vg.texture.resource_path).contains("vignette_lowhp")
	# 满血 → 红晕隐藏；低血（hp≤2）→ 红晕显示（口径不变，仅载体换贴图）
	hud._process(0.0)
	assert_bool(hud._vignette.visible).is_false()
	p.hp = 2
	hud._process(0.0)
	assert_bool(hud._vignette.visible).is_true()


# ---------------------------------------------------------------- 表契约（表驱动路径必须真实存在）

func test_facility_texture_table_all_exist_on_disk() -> void:
	for name: String in ArtLookup.FACILITY_TEXTURES:
		var path := ArtLookup.facility_texture_path(name)
		assert_str(path).is_not_empty()
		assert_bool(FileAccess.file_exists(path)).is_true()
	assert_str(ArtLookup.facility_texture_path("no_such_facility")).is_empty()


func test_ui_texture_table_all_exist_on_disk() -> void:
	for name: String in ArtLookup.UI_TEXTURES:
		var path := ArtLookup.ui_texture_path(name)
		assert_str(path).is_not_empty()
		assert_bool(FileAccess.file_exists(path)).is_true()
	assert_str(ArtLookup.ui_texture_path("no_such_ui")).is_empty()
