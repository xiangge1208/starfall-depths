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
	assert_str(ArtLookup.projectile_texture_path(true, Elements.Id.FIRE)) \
		.is_equal("res://art/generated/projectiles/elem_fire.png")
	assert_str(ArtLookup.projectile_texture_path(false, Elements.Id.ICE)) \
		.is_equal("res://art/generated/projectiles/elem_ice.png")
	assert_str(ArtLookup.projectile_texture_path(false, Elements.Id.POISON)) \
		.is_equal("res://art/generated/projectiles/elem_poison.png")
	assert_str(ArtLookup.projectile_texture_path(true, Elements.Id.SHOCK)) \
		.is_equal("res://art/generated/projectiles/elem_shock.png")

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
