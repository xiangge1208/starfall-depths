class_name TestArtLookup
extends GdUnitTestSuite
## m1-t28 美术接线查询表测试：id → art/generated 纹理路径映射（纯静态）。
## 核心契约：表驱动路径必须真实存在（缺图 = 空串回落色块，绝不给 load 塞坏路径）。

# ---------- 敌人映射（RoomCombat/FloorScene._dress_enemy 消费） ----------

func test_sprite_for_enemy_known_m1_rows() -> void:
	assert_str(ArtLookup.sprite_for_enemy({"id": "kuli_bug"})) \
		.is_equal("res://art/generated/enemies/kuli_bug.png")
	assert_str(ArtLookup.sprite_for_enemy({"id": "cave_bat"})) \
		.is_equal("res://art/generated/enemies/cave_bat.png")
	assert_str(ArtLookup.sprite_for_enemy({"id": "crossbowman"})) \
		.is_equal("res://art/generated/enemies/crossbowman.png")
	assert_str(ArtLookup.sprite_for_enemy({"id": "vine_charger"})) \
		.is_equal("res://art/generated/enemies/vine_charger.png")
	assert_str(ArtLookup.sprite_for_enemy({"id": "mushroom_spore"})) \
		.is_equal("res://art/generated/enemies/mushroom_spore.png")
	assert_str(ArtLookup.sprite_for_enemy({"id": "vine_colossus"})) \
		.is_equal("res://art/generated/enemies/vine_colossus.png")

func test_sprite_for_enemy_unknown_id_returns_empty() -> void:
	assert_str(ArtLookup.sprite_for_enemy({})).is_empty()
	assert_str(ArtLookup.sprite_for_enemy({"id": "dummy"})).is_empty()
	assert_str(ArtLookup.sprite_for_enemy({"id": "no_such_enemy"})).is_empty()

func test_sprite_for_enemy_guest_placeholder_falls_back_by_kind() -> void:
	# T12 占位嘉宾行（vine_charger 覆盖行，id=波次标记）：按 guest_kind 取变体图
	assert_str(ArtLookup.sprite_for_enemy({"id": "elite_charger", "guest_kind": "elite"})) \
		.is_equal("res://art/generated/enemies/vine_charger_elite.png")
	assert_str(ArtLookup.sprite_for_enemy({"id": "miniboss_charger", "guest_kind": "miniboss"})) \
		.is_equal("res://art/generated/enemies/vine_charger_miniboss.png")

func test_sprite_for_enemy_real_guest_id_wins_over_kind() -> void:
	# m1-t27 真实嘉宾：行 id 已是真实数据行（双刀蜥人带 elite 标记）→ id 图优先
	assert_str(ArtLookup.sprite_for_enemy({"id": "shuangdao_lizardman", "guest_kind": "elite"})) \
		.is_equal("res://art/generated/enemies/shuangdao_lizardman.png")
	assert_str(ArtLookup.sprite_for_enemy({"id": "zibao_wangchong", "guest_kind": "miniboss"})) \
		.is_equal("res://art/generated/enemies/zibao_wangchong.png")

func test_all_enemy_texture_entries_exist_on_disk() -> void:
	# 表驱动承诺：列出的路径一定有文件（防表腐坏给 load 塞坏路径）
	for id: String in ArtLookup.ENEMY_TEXTURES:
		var path: String = ArtLookup.BASE + String(ArtLookup.ENEMY_TEXTURES[id])
		assert_bool(FileAccess.file_exists(path)).is_true()

func test_data_enemy_rows_all_have_textures() -> void:
	# M1 名录（data/enemies.json）全量有图：缺图行才会触发色块回落告警
	for id: String in ["kuli_bug", "cave_bat", "crossbowman", "vine_charger",
			"mushroom_spore", "shuangdao_lizardman", "zibao_wangchong", "vine_colossus"]:
		assert_bool(ArtLookup.enemy_texture_path(id).is_empty()).is_false()

# ---------- 英雄映射（HeroApplier meta "hero" 接缝消费） ----------

func test_hero_texture_path_six_heroes() -> void:
	for hero_id: String in ["vanguard", "ranger", "assassin", "engineer", "guardian", "mage"]:
		assert_str(ArtLookup.hero_texture_path(hero_id)) \
			.is_equal("res://art/generated/characters/hero_%s.png" % hero_id)
		assert_bool(FileAccess.file_exists(ArtLookup.hero_texture_path(hero_id))).is_true()

func test_hero_texture_path_unknown_returns_empty() -> void:
	assert_str(ArtLookup.hero_texture_path("no_such_hero")).is_empty()

# ---------- 弹丸映射（表现层弹幕镜像消费） ----------

func test_projectile_texture_by_faction() -> void:
	assert_str(ArtLookup.projectile_texture_path(true, Elements.Id.NONE)) \
		.is_equal("res://art/generated/projectiles/bullet_player.png")
	assert_str(ArtLookup.projectile_texture_path(false, Elements.Id.NONE)) \
		.is_equal("res://art/generated/projectiles/bullet_enemy.png")

func test_projectile_texture_element_overrides_faction() -> void:
	# m2-t27 元素弹阵营分化：玩家保持基础图，敌方走 _enemy 暗边框变体
	assert_str(ArtLookup.projectile_texture_path(true, Elements.Id.FIRE)) \
		.is_equal("res://art/generated/projectiles/elem_fire.png")
	assert_str(ArtLookup.projectile_texture_path(true, Elements.Id.SHOCK)) \
		.is_equal("res://art/generated/projectiles/elem_shock.png")
	assert_str(ArtLookup.projectile_texture_path(false, Elements.Id.FIRE)) \
		.is_equal("res://art/generated/projectiles/elem_fire_enemy.png")
	assert_str(ArtLookup.projectile_texture_path(false, Elements.Id.ICE)) \
		.is_equal("res://art/generated/projectiles/elem_ice_enemy.png")
	assert_str(ArtLookup.projectile_texture_path(false, Elements.Id.POISON)) \
		.is_equal("res://art/generated/projectiles/elem_poison_enemy.png")
	assert_str(ArtLookup.projectile_texture_path(false, Elements.Id.SHOCK)) \
		.is_equal("res://art/generated/projectiles/elem_shock_enemy.png")

func test_enemy_element_variant_files_exist_on_disk() -> void:
	# 表驱动承诺：敌方元素弹变体 4 张必须真实存在（缺图 = tex() 回落 null 触发告警）
	for name: String in ["elem_fire_enemy", "elem_ice_enemy", "elem_poison_enemy", "elem_shock_enemy"]:
		assert_bool(FileAccess.file_exists("res://art/generated/projectiles/%s.png" % name)).is_true()

func test_enemy_element_bullet_memo_distinct_and_stable() -> void:
	# 缓存命中不变式保持（M2-T1 契约）：敌方 FIRE 与玩家 FIRE 不同纹理实例，
	# 同参重复查询零新增 miss（热路径零分配契约不变）。
	ArtLookup.bullet_texture(Projectile.Faction.ENEMY, Elements.Id.FIRE)   # 预热
	ArtLookup.bullet_texture(Projectile.Faction.PLAYER, Elements.Id.FIRE)  # 预热（对照键）
	var warm: int = ArtLookup._path_cache_size
	var enemy_fire := ArtLookup.bullet_texture(Projectile.Faction.ENEMY, Elements.Id.FIRE)
	var player_fire := ArtLookup.bullet_texture(Projectile.Faction.PLAYER, Elements.Id.FIRE)
	assert_object(enemy_fire).is_not_null()
	assert_bool(enemy_fire == player_fire).is_false()     # 阵营分化 → 不同贴图实例
	for _i in 100:
		ArtLookup.bullet_texture(Projectile.Faction.ENEMY, Elements.Id.FIRE)
	assert_int(ArtLookup._path_cache_size).is_equal(warm) # 零新增 miss

# ---------- 层生物群系套件映射（m2-t27 I-3：A2/A3 瓦片接线验证） ----------

func test_biome_set_floor1_cave_kit() -> void:
	# 第 1 层 = cave/garden 套（biome_set 取主体 cave；start 庭院 garden 特例留在 floor_scene）
	var set1 := ArtLookup.biome_set(1)
	assert_str(String(set1["floor"])).is_equal("res://art/generated/tiles/floor_cave.png")
	assert_str(String(set1["wall"])).is_equal("res://art/generated/tiles/wall_cave.png")
	assert_str(String(set1["door"])).is_equal("res://art/generated/tiles/door_closed.png")

func test_biome_set_floor2_crystal_kit() -> void:
	var set2 := ArtLookup.biome_set(2)
	assert_str(String(set2["floor"])).is_equal("res://art/generated/tiles/floor_crystal.png")
	assert_str(String(set2["wall"])).is_equal("res://art/generated/tiles/wall_crystal.png")
	assert_str(String(set2["door"])).is_equal("res://art/generated/tiles/door_closed.png")

func test_biome_set_floor3_magma_kit() -> void:
	var set3 := ArtLookup.biome_set(3)
	assert_str(String(set3["floor"])).is_equal("res://art/generated/tiles/floor_magma.png")
	assert_str(String(set3["wall"])).is_equal("res://art/generated/tiles/wall_magma.png")
	assert_str(String(set3["door"])).is_equal("res://art/generated/tiles/door_closed.png")

func test_biome_set_all_paths_exist_for_three_floors() -> void:
	# 映射完备性契约：1/2/3 层套件（地板/墙/门）每条路径都真实存在（防表腐坏塞坏路径）
	for floor_idx: int in [1, 2, 3]:
		var kit := ArtLookup.biome_set(floor_idx)
		assert_int(kit.size()).is_equal(3)
		for key: String in ["floor", "wall", "door"]:
			var path := String(kit[key])
			assert_bool(path.is_empty()).is_false()
			assert_bool(FileAccess.file_exists(path)).is_true()

func test_biome_set_unknown_floor_returns_empty() -> void:
	assert_int(ArtLookup.biome_set(0).size()).is_equal(0)
	assert_int(ArtLookup.biome_set(-1).size()).is_equal(0)
	assert_int(ArtLookup.biome_set(4).size()).is_equal(0)

func test_corridor_tiles_for_crystal_magma_kits_exist() -> void:
	# 套件走廊瓦片（走廊不随层变色时仍统一 corridor_floor；crystal/magma 变体已在表内可寻址）
	assert_str(ArtLookup.tile_path("corridor_crystal")) \
		.is_equal("res://art/generated/tiles/corridor_crystal.png")
	assert_str(ArtLookup.tile_path("corridor_magma")) \
		.is_equal("res://art/generated/tiles/corridor_magma.png")
	assert_bool(FileAccess.file_exists(ArtLookup.tile_path("corridor_crystal"))).is_true()
	assert_bool(FileAccess.file_exists(ArtLookup.tile_path("corridor_magma"))).is_true()

# ---------- 弹丸热路径备忘（M2-T1：bullet_texture 静态字典缓存） ----------

func test_bullet_texture_memoizes_repeat_calls() -> void:
	# 热路径契约（floor_scene/room_combat _sync_bullet_visuals 逐帧逐弹查询）：
	# 同 (faction, element) 二次起必须命中静态缓存——miss 计数不得再增长。
	var faction := Projectile.Faction.PLAYER
	ArtLookup.bullet_texture(faction, Elements.Id.FIRE)   # 预热：消除跨套件静态状态影响
	var misses_before: int = ArtLookup._path_cache_size
	var first := ArtLookup.bullet_texture(faction, Elements.Id.FIRE)
	assert_object(first).is_not_null()
	for _i in 500:                                        # 热路径写实连发：零新增 miss
		ArtLookup.bullet_texture(faction, Elements.Id.FIRE)
	assert_int(ArtLookup._path_cache_size).is_equal(misses_before)
	var repeat := ArtLookup.bullet_texture(faction, Elements.Id.FIRE)
	assert_bool(repeat == first).is_true()                # 同一纹理实例（零重载）

func test_bullet_texture_distinct_args_cached_separately() -> void:
	# 不同键各自恰好 miss 一次：阵营底图/元素弹互不串味，重复查询全命中。
	ArtLookup.bullet_texture(Projectile.Faction.PLAYER, Elements.Id.NONE)
	ArtLookup.bullet_texture(Projectile.Faction.ENEMY, Elements.Id.NONE)
	ArtLookup.bullet_texture(Projectile.Faction.PLAYER, Elements.Id.FIRE)
	var warm: int = ArtLookup._path_cache_size
	var player_none := ArtLookup.bullet_texture(Projectile.Faction.PLAYER, Elements.Id.NONE)
	var enemy_none := ArtLookup.bullet_texture(Projectile.Faction.ENEMY, Elements.Id.NONE)
	var fire := ArtLookup.bullet_texture(Projectile.Faction.PLAYER, Elements.Id.FIRE)
	assert_bool(player_none == enemy_none).is_false()     # 阵营底图不同贴图
	assert_bool(fire == player_none).is_false()           # 元素弹 ≠ 阵营底图
	for _i in 10:
		ArtLookup.bullet_texture(Projectile.Faction.ENEMY, Elements.Id.NONE)
	assert_int(ArtLookup._path_cache_size).is_equal(warm)

# ---------- 拾取映射 ----------

func test_pickup_texture_paths_exist() -> void:
	for kind: String in ["coin", "energy", "heart"]:
		assert_bool(FileAccess.file_exists(ArtLookup.pickup_texture_path(kind))).is_true()
	assert_str(ArtLookup.pickup_texture_path("no_such_kind")).is_empty()

# ---------- 地块/门/陈设映射 ----------

func test_all_tile_entries_exist_on_disk() -> void:
	for tile_name: String in ArtLookup.TILES:
		var path: String = ArtLookup.BASE + String(ArtLookup.TILES[tile_name])
		assert_bool(FileAccess.file_exists(path)).is_true()
	assert_str(ArtLookup.tile_path("no_such_tile")).is_empty()

func test_weapon_icon_paths_exist_for_rack_roster() -> void:
	# 训练房武器架 6 把 + 全名录抽查：icon 按 id 约定寻址，缺图由 make_sprite null 兜底
	for wid: String in ["laohuoji", "maodingqiang", "duangong", "xuetufazhang", "tiejian", "shuangbi"]:
		assert_bool(FileAccess.file_exists(ArtLookup.weapon_icon_path(wid))).is_true()
	assert_str(ArtLookup.weapon_icon_path("")).is_empty()

# ---------- 节点工厂 ----------

func test_make_sprite_nearest_filter() -> void:
	var spr := ArtLookup.make_sprite(ArtLookup.hero_texture_path("vanguard"))
	assert_bool(spr is Sprite2D).is_true()
	assert_object(spr.texture).is_not_null()
	assert_int(spr.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)
	spr.free()

func test_make_tiled_covers_rect_with_repeat() -> void:
	var rect := Rect2(16, 16, 456, 238)
	var spr := ArtLookup.make_tiled(ArtLookup.BASE + "tiles/floor_cave.png", rect)
	assert_bool(spr.centered).is_false()
	assert_bool(spr.region_enabled).is_true()
	assert_int(spr.texture_repeat).is_equal(CanvasItem.TEXTURE_REPEAT_ENABLED)
	assert_vector(spr.region_rect.size).is_equal(rect.size)
	assert_vector(spr.position).is_equal(rect.position)
	assert_int(spr.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)
	spr.free()

func test_make_sprite_missing_path_returns_null() -> void:
	# 坏路径不炸：返回 null 由调用方回落（表已由测试守护，此为兜底契约）
	assert_object(ArtLookup.make_sprite("res://art/generated/nope.png")).is_null()
