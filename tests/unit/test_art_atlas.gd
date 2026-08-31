class_name TestArtAtlas
extends GdUnitTestSuite
## m2-t37 全图集合并契约（GDD §18.3「draw call ≤150（全图集）」前提落地）：
## 1) 图集产物存在且规格合法（单页、幂次边长 ≤1024、条目含 padding 不重叠）；
## 2) **像素恒等**：每个条目的图集区域逐像素等于源 PNG（源参数表 → 产物一致性）；
## 3) 区域钉值：至少一枚精灵的 源图 → 图集区域 映射被字面量钉死（防再打包漂移）；
## 4) 运行时接线：ArtLookup.tex 命中条目返回共享同页的 AtlasTexture（批处理前提：
##    所有世界精灵同一底层纹理），尺寸/过滤语义不变；
## 5) 排除与回落：tiles/（region+repeat 平铺）与 *_sheet.png（hframes/vframes 帧表）
##    不入图集；图集缺失/停用时 fail-closed 回落逐文件纹理。
## 生成器：tools/gen_art_atlas.py（只增不删、确定性装箱；gen_placeholder_art main()
## 末尾串联，prune 前——失败即中止，绝不带陈旧图集清理）。

const MANIFEST_PATH := "res://art/generated/atlas/atlas.json"
const PAGE_RELPATH := "res://art/generated/atlas/"
const SRC_BASE := "res://art/generated/"

# 区域钉值（确定性 shelf 装箱产物，tools/gen_art_atlas.py 同输入逐字节同输出；
# 再打包若漂移即失败——保护 atlas 区域映射不悄悄变更。值取自 2026-08-31 首版图集）
const PIN_KULI_BUG := "enemies/kuli_bug.png"
const PIN_KULI_BUG_RECT := Rect2i(2, 74, 16, 16)
const PIN_BULLET_ENEMY := "projectiles/bullet_enemy.png"
const PIN_BULLET_ENEMY_RECT := Rect2i(350, 274, 8, 8)

var manifest: Dictionary = {}


func before_test() -> void:
	ArtAtlas.reset_for_tests()
	ArtAtlas.set_enabled(true)
	manifest = _load_manifest()


func after_test() -> void:
	ArtAtlas.reset_for_tests()
	ArtAtlas.set_enabled(true)


func _load_manifest() -> Dictionary:
	assert_bool(FileAccess.file_exists(MANIFEST_PATH)).is_true()
	var txt := FileAccess.get_file_as_string(MANIFEST_PATH)
	var parsed: Variant = JSON.parse_string(txt)
	assert_object(parsed).is_not_null()
	return parsed as Dictionary


func _entries() -> Dictionary:
	return manifest.get("entries", {}) as Dictionary


func _page_image() -> Image:
	var page := String(manifest.get("page", ""))
	assert_bool(page.is_empty()).is_false()
	var tex := load(PAGE_RELPATH + page) as Texture2D
	assert_object(tex).is_not_null()
	return tex.get_image()


func _src_image(rel: String) -> Image:
	var tex := load(SRC_BASE + rel) as Texture2D
	assert_object(tex).is_not_null()
	return tex.get_image()


# ------------------------------------------------ 1) 产物规格

func test_manifest_spec_and_page_exist() -> void:
	var w := int(manifest.get("size", [0, 0])[0])
	var h := int(manifest.get("size", [0, 0])[1])
	assert_bool(w > 0 and h > 0).is_true()
	assert_bool(_pow2(w) and _pow2(h)).is_true()
	assert_int(maxi(w, h)).is_less_equal(1024)   # 2GB 内存机型 VRAM 预算（fail-closed 线）
	assert_int(int(manifest.get("padding", 0))).is_greater_equal(1)
	assert_bool(FileAccess.file_exists(PAGE_RELPATH + String(manifest.get("page", "")))).is_true()


func _pow2(v: int) -> bool:
	return v > 0 and (v & (v - 1)) == 0


func test_entries_non_empty_and_shapes_integer() -> void:
	var entries := _entries()
	assert_int(entries.size()).is_greater(100)   # 世界精灵主力（敌人 48+弹 10+拾取 4+英雄 6…）
	for rel: String in entries:
		var rect: Array = entries[rel]
		assert_int(rect.size()).is_equal(4)
		for v: Variant in rect:
			assert_float(float(v)).is_equal(float(int(v)))   # 整数像素（无半像素采样）


func test_regions_within_page_and_disjoint_with_padding() -> void:
	var w := int(manifest.get("size", [0, 0])[0])
	var h := int(manifest.get("size", [0, 0])[1])
	var pad := int(manifest.get("padding", 0))
	# 占据栅格（含 padding 外扩）：任何一格被两个条目占据 = 重叠/贴边渗色风险
	var grid := PackedByteArray()
	grid.resize(w * h)
	for rel: String in _entries():
		var r: Array = _entries()[rel]
		var x0: int = int(r[0]) - pad
		var y0: int = int(r[1]) - pad
		var x1: int = int(r[0]) + int(r[2]) + pad
		var y1: int = int(r[1]) + int(r[3]) + pad
		assert_bool(x0 >= 0 and y0 >= 0 and x1 <= w and y1 <= h).is_true()
		for y in range(y0, y1):
			for x in range(x0, x1):
				var idx := y * w + x
				assert_int(grid[idx]).is_equal(0)   # 与既有占据冲突（rel=%s）% rel
				grid[idx] = 1


# ------------------------------------------------ 2) 像素恒等（源 → 图集区域）

func test_pixel_identity_all_entries() -> void:
	# 可见像素（alpha>0）逐位恒等 = 渲染恒等契约。alpha==0 处 RGB 为不可见数据，
	# 导入器 fix_alpha_border 会重写其邻域色（抗黑边），不参与比对也不影响表现。
	var page := _page_image()
	var checked := 0
	for rel: String in _entries():
		var r: Array = _entries()[rel]
		var src := _src_image(rel)
		assert_int(src.get_width()).is_equal(int(r[2]))
		assert_int(src.get_height()).is_equal(int(r[3]))
		for y in src.get_height():
			for x in src.get_width():
				var ps := src.get_pixel(x, y)
				if ps.a <= 0.0:
					continue                    # 全透明像素不可见（fix_alpha_border 域）
				var pa := page.get_pixel(int(r[0]) + x, int(r[1]) + y)
				if not ps.is_equal_approx(pa):
					fail("像素不恒等 %s (%d,%d) src=%s atlas=%s" % [rel, x, y, ps, pa])
					return
		checked += 1
	assert_int(checked).is_greater(100)


# ------------------------------------------------ 3) 区域钉值

func test_pinned_region_mapping_survives_repack() -> void:
	var entries := _entries()
	assert_bool(entries.has(PIN_KULI_BUG)).is_true()
	assert_bool(entries.has(PIN_BULLET_ENEMY)).is_true()
	var kuli: Array = entries[PIN_KULI_BUG]
	assert_int(Vector2i(kuli[0], kuli[1]).x).is_equal(PIN_KULI_BUG_RECT.position.x)
	assert_int(Vector2i(kuli[0], kuli[1]).y).is_equal(PIN_KULI_BUG_RECT.position.y)
	assert_int(int(kuli[2])).is_equal(PIN_KULI_BUG_RECT.size.x)
	assert_int(int(kuli[3])).is_equal(PIN_KULI_BUG_RECT.size.y)
	var bullet: Array = entries[PIN_BULLET_ENEMY]
	assert_int(int(bullet[0])).is_equal(PIN_BULLET_ENEMY_RECT.position.x)
	assert_int(int(bullet[1])).is_equal(PIN_BULLET_ENEMY_RECT.position.y)
	assert_int(int(bullet[2])).is_equal(PIN_BULLET_ENEMY_RECT.size.x)
	assert_int(int(bullet[3])).is_equal(PIN_BULLET_ENEMY_RECT.size.y)


func test_manifest_covers_runtime_world_tables() -> void:
	# 运行时世界精灵表（ArtLookup）必须全量入图集（新精灵落盘即被生成器扫入，
	# 表新增而图集缺行 = 契约破坏）
	var entries := _entries()
	for id: String in ArtLookup.ENEMY_TEXTURES:
		assert_bool(entries.has(String(ArtLookup.ENEMY_TEXTURES[id]))).is_true()
	for hid: String in ArtLookup.HERO_TEXTURES:
		assert_bool(entries.has(String(ArtLookup.HERO_TEXTURES[hid]))).is_true()
	for kind: String in ArtLookup.PICKUP_TEXTURES:
		assert_bool(entries.has(String(ArtLookup.PICKUP_TEXTURES[kind]))).is_true()
	assert_bool(entries.has("projectiles/bullet_player.png")).is_true()
	assert_bool(entries.has("projectiles/bullet_enemy.png")).is_true()
	assert_bool(entries.has("projectiles/elem_fire.png")).is_true()
	assert_bool(entries.has("projectiles/elem_fire_enemy.png")).is_true()


# ------------------------------------------------ 4) 运行时接线（批处理前提）

func test_tex_returns_atlas_texture_on_shared_page() -> void:
	var t := ArtLookup.tex("res://art/generated/enemies/kuli_bug.png")
	assert_object(t).is_not_null()
	assert_bool(t is AtlasTexture).is_true()
	if t is AtlasTexture:
		var at := t as AtlasTexture
		assert_object(at.atlas).is_same(ArtAtlas.page_texture())   # 同一页纹理实例
		var r := at.region
		assert_int(int(r.position.x)).is_equal(int((_entries()[PIN_KULI_BUG] as Array)[0]))
		assert_int(int(r.position.y)).is_equal(int((_entries()[PIN_KULI_BUG] as Array)[1]))
	assert_vector(t.get_size()).is_equal(Vector2(16, 16))          # 语义尺寸不变


func test_world_sprites_all_share_one_page_texture() -> void:
	# 批处理前提：敌人/弹/拾取/英雄 纹理实例各异（区域不同），底层页纹理同一张
	var kuli := ArtLookup.tex("res://art/generated/enemies/kuli_bug.png")
	var bat := ArtLookup.tex("res://art/generated/enemies/cave_bat.png")
	var bullet := ArtLookup.tex("res://art/generated/projectiles/bullet_enemy.png")
	var coin := ArtLookup.tex("res://art/generated/pickups/coin.png")
	var hero := ArtLookup.tex("res://art/generated/characters/hero_vanguard.png")
	for t: Texture2D in [bat, bullet, coin, hero]:
		assert_object((t as AtlasTexture).atlas).is_same((kuli as AtlasTexture).atlas)
	# 弹热路径备忘同样落在共享页上
	var be := ArtLookup.bullet_texture(Projectile.Faction.ENEMY, Elements.Id.NONE)
	var pe := ArtLookup.bullet_texture(Projectile.Faction.PLAYER, Elements.Id.NONE)
	assert_bool(be == pe).is_false()                               # 实例各异（M2-T1 契约）
	assert_object((be as AtlasTexture).atlas).is_same((kuli as AtlasTexture).atlas)


# ------------------------------------------------ 5) 排除与 fail-closed 回落

func test_tiles_and_sheets_excluded_from_atlas() -> void:
	# tiles/：make_tiled 依赖 texture_repeat（AtlasTexture 不支持平铺）→ 必须逐文件纹理
	var floor_tex := ArtLookup.tex(ArtLookup.tile_path("floor_cave"))
	assert_bool(floor_tex is AtlasTexture).is_false()
	assert_object(floor_tex).is_not_null()
	# *_sheet.png：hframes/vframes 帧表寻址依赖独立整图 → 必须逐文件纹理
	var sheet := ArtLookup.tex("res://art/generated/characters/hero_vanguard_sheet.png")
	assert_bool(sheet is AtlasTexture).is_false()
	assert_object(sheet).is_not_null()


func test_disabled_falls_back_to_per_file_texture() -> void:
	ArtAtlas.set_enabled(false)
	var t := ArtLookup.tex("res://art/generated/enemies/kuli_bug.png")
	assert_object(t).is_not_null()
	assert_bool(t is AtlasTexture).is_false()     # fail-closed：原逐文件路径原样可用
	ArtAtlas.set_enabled(true)
	ArtAtlas.reset_for_tests()
	var t2 := ArtLookup.tex("res://art/generated/enemies/kuli_bug.png")
	assert_bool(t2 is AtlasTexture).is_true()


func test_unknown_path_still_null_without_crash() -> void:
	assert_object(ArtLookup.tex("")).is_null()
	assert_object(ArtLookup.tex("res://art/generated/enemies/no_such.png")).is_null()


# ------------------------------------------------ 5b) 畸形/越界行负缓存（评审 Minor-5）

func test_malformed_rows_negative_cached_at_load() -> void:
	# 归一化直接注入（跳过文件 I/O）：错误元数的行被拒并记入负缓存，好行不受牵连
	var data := {
		"page": "atlas_page.png", "size": [64, 64],
		"entries": {
			"good/a.png": [2, 2, 8, 8],
			"bad_arity.png": [2, 2, 8],
			"bad_float.png": [2.5, 2, 8, 8],
		},
	}
	assert_bool(ArtAtlas._apply_manifest(data)).is_true()
	assert_int(ArtAtlas._manifest.size()).is_equal(1)
	assert_bool(ArtAtlas._invalid.has("bad_arity.png")).is_true()
	assert_bool(ArtAtlas._invalid.has("bad_float.png")).is_true()
	assert_bool(ArtAtlas._invalid.has("good/a.png")).is_false()


func test_out_of_bounds_row_rejected_before_allocation_and_negative_cached() -> void:
	# 先判界后建对象（Minor-5）：越界行 texture_for 恒 null，负缓存生效——
	# 热路径重复查询不再告警/不再重建（_regions 备忘不含该行）
	var data := {
		"page": "atlas_page.png", "size": [64, 64],
		"entries": {"enemies/oob.png": [60, 60, 16, 16]},
	}
	ArtAtlas._apply_manifest(data)
	ArtAtlas._loaded = true             # 跳过文件重载，专测越界判定路径
	var t := ArtAtlas.texture_for("res://art/generated/enemies/oob.png")
	assert_object(t).is_null()
	assert_bool(ArtAtlas._invalid.has("enemies/oob.png")).is_true()
	assert_bool(ArtAtlas._regions.has("enemies/oob.png")).is_false()
	# 二次查询走负缓存（零重复告警语义：仍 null，行为稳定）
	assert_object(ArtAtlas.texture_for("res://art/generated/enemies/oob.png")).is_null()


# ------------------------------------------------ 6) 生成器幂等（additive 契约）

func test_atlas_generator_idempotent_and_additive() -> void:
	# 重定向输出到临时目录跑两轮：两轮 atlas.json 逐字节一致（确定性装箱），
	# 且源目录零改动（只增不删由生成器只写 atlas/ 子目录保证）。
	var exe := _python_exe()
	assert_str(exe).is_not_empty()
	var root := ProjectSettings.globalize_path("res://art/generated")
	var out := ProjectSettings.globalize_path("user://atlas_idem_test")
	DirAccess.remove_absolute(out)
	DirAccess.make_dir_recursive_absolute(out)
	var args: PackedStringArray = [
		ProjectSettings.globalize_path("res://tools/gen_art_atlas.py"),
		"--root", root, "--out", out,
	]
	var code := OS.execute(exe, args, [], true)
	assert_int(code).is_equal(0)
	var json1 := FileAccess.get_file_as_string(out + "/atlas.json")
	DirAccess.remove_absolute(out + "/atlas.json")
	var code2 := OS.execute(exe, args, [], true)
	assert_int(code2).is_equal(0)
	var json2 := FileAccess.get_file_as_string(out + "/atlas.json")
	assert_str(json2).is_equal(json1)
	DirAccess.remove_absolute(out)


func _python_exe() -> String:
	# m2-t37 fix（评审 Minor-4）：环境变量 ART_ATLAS_PYTHON 优先（指向含 Pillow 的
	# 解释器，机器相关路径不入库），回落 PATH 上的 python / py。
	var override := OS.get_environment("ART_ATLAS_PYTHON")
	if not override.is_empty() and FileAccess.file_exists(override) \
			and OS.execute(override, ["--version"], [], true) == 0:
		return override
	for exe: String in ["python", "py"]:
		var out: Array = []
		if OS.execute(exe, ["--version"], out, true) == 0:
			return exe
	return ""
