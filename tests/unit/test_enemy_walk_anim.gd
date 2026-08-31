class_name TestEnemyWalkAnim
extends GdUnitTestSuite
## m2-t21 敌人 2 帧动画：帧表完整性 + RoomCombat 帧切换测试。
## 契约（tools/gen_placeholder_art_m2.gen_enemy_sheets_m2 与 core/rooms/room_combat.gd）：
## - data/enemies.json 常规行（无 elite_affixes 且 archetype != boss）= 40 种，
##   每种 art/generated/enemies/<id>_sheet.png = 2 列(idle|walk) × 1 行（32x16，帧 16x16）；
## - MANIFEST.md 逐行登记（生成器单一出口，比对防表腐坏——同 T17 模式）；
## - Sprite hframes=2 vframes=1；idle=列0；移动中 (物理帧/8) % 2 两帧交替（同玩家节拍）；
## - 缺表敌种（精英/小Boss/Boss/嘉宾）保留单帧外观回落，不回归色块。

const SHEET_FMT := "res://art/generated/enemies/%s_sheet.png"
const SINGLE_FMT := "res://art/generated/enemies/%s.png"
const MANIFEST_PATH := "res://art/generated/MANIFEST.md"
const REGULAR_COUNT := 40
const FRAME_PX := 16

# ---------- 常规敌 roster（数据驱动口径） ----------

func _regular_enemy_ids() -> Array[String]:
	var txt := FileAccess.get_file_as_string("res://data/enemies.json")
	var parsed: Variant = JSON.parse_string(txt)
	assert_object(parsed).is_not_null()
	var out: Array[String] = []
	for eid: String in parsed:
		var row: Dictionary = parsed[eid]
		if row.has("elite_affixes") or String(row.get("archetype", "")) == "boss":
			continue
		out.append(eid)
	return out

func test_regular_roster_is_forty() -> void:
	# 附录 B 常规敌 40 种口径守护：剔除 2 精英 + 4 小Boss（elite_affixes）+ 1 Boss
	var ids := _regular_enemy_ids()
	assert_int(ids.size()).is_equal(REGULAR_COUNT)

# ---------- 帧表完整性（存在性 + 几何 + MANIFEST 比对） ----------

func test_sheets_exist_for_all_regular_enemies() -> void:
	for eid: String in _regular_enemy_ids():
		assert_bool(FileAccess.file_exists(SHEET_FMT % eid)) \
			.override_failure_message("缺少敌人帧表: " + (SHEET_FMT % eid)).is_true()

func test_sheets_two_column_geometry() -> void:
	# 每张帧表 = 2 列 × 1 行、帧尺寸 16x16（与单帧图同规格；hframes=2 消费契约）
	for eid: String in _regular_enemy_ids():
		var t := ArtLookup.tex(SHEET_FMT % eid)
		assert_object(t).is_not_null()
		assert_vector(t.get_size()).is_equal(Vector2(FRAME_PX * 2, FRAME_PX))

func test_elite_miniboss_boss_have_no_sheet() -> void:
	# 排除口径：精英/小Boss（elite_affixes 行）与 Boss 不出帧表——回落单帧外观
	for eid: String in ["shuangdao_lizardman", "zibao_wangchong", "stone_shield_monk",
			"undead_gunner", "volt_spider", "marsh_toad", "vine_colossus"]:
		assert_bool(FileAccess.file_exists(SHEET_FMT % eid)).is_false()

func test_manifest_lists_all_enemy_sheets() -> void:
	var manifest := FileAccess.get_file_as_string(MANIFEST_PATH)
	assert_bool(manifest.is_empty()).is_false()
	for eid: String in _regular_enemy_ids():
		var row := "| `enemies/%s_sheet.png` | 32x16 |" % eid
		assert_bool(manifest.contains(row)) \
			.override_failure_message("MANIFEST 缺帧表行: " + row).is_true()

# ---------- 帧序纯函数（RoomCombat.enemy_anim_frame） ----------

func test_anim_frame_idle_is_column_zero() -> void:
	for f: int in [0, 7, 8, 99]:
		assert_int(RoomCombat.enemy_anim_frame(false, f)).is_equal(0)

func test_anim_frame_moving_alternates_at_8t() -> void:
	# 8t/帧两帧交替：f∈[0,8)→列0, [8,16)→列1, [16,24)→列0, [24,32)→列1（循环）
	assert_int(RoomCombat.enemy_anim_frame(true, 0)).is_equal(0)
	assert_int(RoomCombat.enemy_anim_frame(true, 7)).is_equal(0)
	assert_int(RoomCombat.enemy_anim_frame(true, 8)).is_equal(1)
	assert_int(RoomCombat.enemy_anim_frame(true, 15)).is_equal(1)
	assert_int(RoomCombat.enemy_anim_frame(true, 16)).is_equal(0)
	assert_int(RoomCombat.enemy_anim_frame(true, 24)).is_equal(1)

# ---------- 场景接线（_dress_enemy 换装帧表网格 + 拍驱动） ----------

func _room() -> RoomCombat:
	return auto_free(RoomCombat.new())

func test_dress_enemy_applies_sheet_grid() -> void:
	# 常规敌换装：hframes=2/vframes=1、缩放按帧尺寸重算（radius 5 → 10/16）
	var room := _room()
	var e: EnemyBase = auto_free(EnemyBase.new())
	room._dress_enemy(e, {"id": "kuli_bug", "radius": 5.0})
	var spr := e.get_node_or_null("Sprite") as Sprite2D
	assert_object(spr).is_not_null()                     # Fx 白闪按名寻址契约
	assert_int(spr.hframes).is_equal(2)
	assert_int(spr.vframes).is_equal(1)
	assert_int(spr.frame).is_equal(0)
	assert_bool(spr.texture == ArtLookup.tex(SHEET_FMT % "kuli_bug")).is_true()
	assert_vector(spr.scale).is_equal(Vector2(0.625, 0.625))

func test_dress_enemy_without_sheet_keeps_single_frame() -> void:
	# 缺表回落：Boss（无帧表）保持单帧整图外观，不套 2 列网格
	var room := _room()
	var e: EnemyBase = auto_free(EnemyBase.new())
	room._dress_enemy(e, {"id": "vine_colossus", "radius": 12.0})
	var spr := e.get_node_or_null("Sprite") as Sprite2D
	assert_object(spr).is_not_null()
	assert_int(spr.hframes).is_equal(1)
	assert_int(spr.vframes).is_equal(1)
	assert_bool(spr.texture == ArtLookup.tex(SINGLE_FMT % "vine_colossus")).is_true()

func test_tick_anim_switches_by_movement() -> void:
	# 静止=idle 列0；移动=按物理帧交替；停步即回 idle（零分配拍驱动）
	var room := _room()
	var e: EnemyBase = auto_free(EnemyBase.new())
	room._dress_enemy(e, {"id": "kuli_bug", "radius": 5.0})
	var spr := e.get_node_or_null("Sprite") as Sprite2D
	room._tick_enemy_anim(e, 0)                       # 装配位==当前位 → 静止
	assert_int(spr.frame).is_equal(0)
	e.brain_pos = Vector2(100.0, 0.0)
	room._tick_enemy_anim(e, 8)                       # 位移 100px 且 f=8 → walk 列
	assert_int(spr.frame).is_equal(1)
	room._tick_enemy_anim(e, 16)                      # 原地不动 → idle（覆盖帧号）
	assert_int(spr.frame).is_equal(0)
	e.brain_pos = Vector2(96.0, 0.0)
	room._tick_enemy_anim(e, 17)                      # 移动中 f∈[16,24) → 列0
	assert_int(spr.frame).is_equal(0)
	e.brain_pos = Vector2(80.0, 0.0)
	room._tick_enemy_anim(e, 24)                      # 移动中 f∈[24,32) → 列1
	assert_int(spr.frame).is_equal(1)

func test_tick_anim_ignores_micro_jitter() -> void:
	# 位移² ≤ 0.25（贴墙抖动回弹量级）视为静止，不误播 walk
	var room := _room()
	var e: EnemyBase = auto_free(EnemyBase.new())
	room._dress_enemy(e, {"id": "kuli_bug", "radius": 5.0})
	var spr := e.get_node_or_null("Sprite") as Sprite2D
	e.brain_pos = Vector2(0.4, 0.0)
	room._tick_enemy_anim(e, 8)                       # 位移² 0.16 < 0.25 → idle
	assert_int(spr.frame).is_equal(0)

func test_death_clears_anim_tracking() -> void:
	# 实例 id 可复用：敌亡必须清动画跟踪（防 Sprite 引用悬挂/错体）；
	# 清理先于 _enemies 注册守卫——未注册（召唤/拆除中）敌种死亡同样不留脏。
	var room := _room()
	var e: EnemyBase = auto_free(EnemyBase.new())
	room._dress_enemy(e, {"id": "kuli_bug", "radius": 5.0})
	assert_bool(room._anim_sprites.has(e.get_instance_id())).is_true()
	room._on_enemy_died(e)                            # 未注册 → 早退但先清动画跟踪
	assert_bool(room._anim_sprites.has(e.get_instance_id())).is_false()
	assert_bool(room._anim_prev.has(e.get_instance_id())).is_false()

# ---------- T17 Minor① 顺手修复守护（apply_player_sprite 清帧表切片） ----------

func test_apply_player_sprite_clears_sheet_grid() -> void:
	# 写回站立像必须复位 hframes/vframes/frame——否则 4x4 帧表切片残留
	# 在 16x16 站立像上只显示 1/16 区域（m2-t21 修复，防回归）
	var p: Player = auto_free(load("res://core/player/player.tscn").instantiate() as Player)
	add_child(p)
	var spr := p.get_node_or_null("Sprite") as Sprite2D
	spr.hframes = 4
	spr.vframes = 4
	spr.frame = 5
	ArtLookup.apply_player_sprite(p)
	assert_int(spr.hframes).is_equal(1)
	assert_int(spr.vframes).is_equal(1)
	assert_int(spr.frame).is_equal(0)
	assert_bool(spr.texture == ArtLookup.tex("res://art/generated/characters/hero_vanguard.png")).is_true()
