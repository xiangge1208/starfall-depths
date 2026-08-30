class_name TestHeroWalkAnim
extends GdUnitTestSuite
## m2-t17 英雄行走帧表完整性 + 玩家四向动画切换测试。
## 契约（tools/gen_placeholder_art.py --hero-sheets 与 core/player/player.gd）：
## - 每英雄 characters/hero_<id>_sheet.png = 64x64，4 行(下/上/左/右) × 4 列(idle+walk×3)；
## - MANIFEST.md 逐行登记（生成器单一出口，比对防表腐坏）；
## - 帧序 = 方向行*4 + 列；idle=0，行走循环 1..3（8t/帧）；静止保留上一方向行；
## - Sprite 节点保留名 "Sprite"（Fx 受击白闪按名寻址，沿用不变）。

const SHEET_FMT := "res://art/generated/characters/hero_%s_sheet.png"
const MANIFEST_PATH := "res://art/generated/MANIFEST.md"
const SHEET_PX := 64
const FULL_ROSTER := ["vanguard", "ranger", "engineer", "mage", "assassin", "guardian"]

# ---------- 帧表完整性（数据驱动 + 美术名录并集） ----------

func test_walk_sheets_exist_for_all_data_heroes() -> void:
	# data/heroes.json 现有全部行必须有帧表（新英雄入表 → 重跑生成器即覆盖）
	var txt := FileAccess.get_file_as_string("res://data/heroes.json")
	var parsed: Variant = JSON.parse_string(txt)
	assert_object(parsed).is_not_null()
	var heroes: Dictionary = parsed
	assert_int(heroes.size()).is_greater_equal(3)
	for hid: String in heroes:
		assert_bool(FileAccess.file_exists(SHEET_FMT % hid)).is_true()

func test_walk_sheets_full_six_roster_64px() -> void:
	# 全六英雄（含 T11 mage / T13 assassin+guardian 未落数据行的名录兜底）
	for hid: String in FULL_ROSTER:
		var t := ArtLookup.tex(SHEET_FMT % hid)
		assert_object(t).is_not_null()
		assert_vector(t.get_size()).is_equal(Vector2(SHEET_PX, SHEET_PX))

func test_manifest_lists_all_walk_sheets() -> void:
	# MANIFEST 比对：每张帧表一行、尺寸列 64x64、用途列点名四向帧表
	var manifest := FileAccess.get_file_as_string(MANIFEST_PATH)
	assert_bool(manifest.is_empty()).is_false()
	for hid: String in FULL_ROSTER:
		var row := "| `characters/hero_%s_sheet.png` | 64x64 |" % hid
		assert_bool(manifest.contains(row)).is_true()
		assert_bool(manifest.contains("英雄") and manifest.contains("四向行走帧表")).is_true()

# ---------- 方向/帧序纯函数（Player.anim_*） ----------

func test_anim_dir_index_cardinals() -> void:
	assert_int(Player.anim_dir_index(Vector2.RIGHT)).is_equal(Player.ANIM_DIR_RIGHT)
	assert_int(Player.anim_dir_index(Vector2.LEFT)).is_equal(Player.ANIM_DIR_LEFT)
	assert_int(Player.anim_dir_index(Vector2.DOWN)).is_equal(Player.ANIM_DIR_DOWN)
	assert_int(Player.anim_dir_index(Vector2.UP)).is_equal(Player.ANIM_DIR_UP)

func test_anim_dir_index_diagonals_horizontal_wins() -> void:
	assert_int(Player.anim_dir_index(Vector2.ONE)).is_equal(Player.ANIM_DIR_RIGHT)
	assert_int(Player.anim_dir_index(Vector2(-1, 1))).is_equal(Player.ANIM_DIR_LEFT)
	assert_int(Player.anim_dir_index(Vector2(1, -1))).is_equal(Player.ANIM_DIR_RIGHT)
	assert_int(Player.anim_dir_index(Vector2(-0.1, 0.9))).is_equal(Player.ANIM_DIR_DOWN)
	assert_int(Player.anim_dir_index(Vector2(0.1, -0.9))).is_equal(Player.ANIM_DIR_UP)

func test_anim_walk_col_three_frame_cycle() -> void:
	# 8t/帧：f∈[0,8)→列1, [8,16)→列2, [16,24)→列3, [24,32)→列1（循环）
	assert_int(Player.anim_walk_col(0)).is_equal(1)
	assert_int(Player.anim_walk_col(7)).is_equal(1)
	assert_int(Player.anim_walk_col(8)).is_equal(2)
	assert_int(Player.anim_walk_col(15)).is_equal(2)
	assert_int(Player.anim_walk_col(16)).is_equal(3)
	assert_int(Player.anim_walk_col(23)).is_equal(3)
	assert_int(Player.anim_walk_col(24)).is_equal(1)

func test_anim_frame_index_idle_uses_last_dir_row() -> void:
	# 静止=列0 且保留上一方向行（不回默认朝向）
	assert_int(Player.anim_frame_index(Vector2.ZERO, Player.ANIM_DIR_LEFT, 0)) \
		.is_equal(Player.ANIM_DIR_LEFT * 4)
	assert_int(Player.anim_frame_index(Vector2.ZERO, Player.ANIM_DIR_UP, 999)) \
		.is_equal(Player.ANIM_DIR_UP * 4)

func test_anim_frame_index_moving_combines_row_and_cycle() -> void:
	assert_int(Player.anim_frame_index(Vector2.RIGHT, 0, 0)).is_equal(Player.ANIM_DIR_RIGHT * 4 + 1)
	assert_int(Player.anim_frame_index(Vector2.RIGHT, 0, 16)).is_equal(Player.ANIM_DIR_RIGHT * 4 + 3)
	assert_int(Player.anim_frame_index(Vector2.DOWN, 3, 8)).is_equal(Player.ANIM_DIR_DOWN * 4 + 2)
	assert_int(Player.anim_frame_index(Vector2.UP, 3, 0)).is_equal(Player.ANIM_DIR_UP * 4 + 1)

# ---------- 场景接线（player.tscn Sprite 帧表化 + 白闪节点名契约） ----------

func _player_in_tree() -> Player:
	# 注：auto_free 返回 Variant（同 test_player_state.gd 决议），需显式类型标注
	var p: Player = auto_free(load("res://core/player/player.tscn").instantiate() as Player)
	add_child(p)                                         # 入树（_ready 装配 Sprite 帧表）
	return p

func test_player_scene_sprite_wired_as_sheet_grid() -> void:
	# tscn 烘焙：Sprite(Sprite2D) + 帧表纹理 + 4x4 网格（缺省 vanguard 表）
	var p := _player_in_tree()
	var spr := p.get_node_or_null("Sprite") as Sprite2D
	assert_object(spr).is_not_null()                     # Fx 白闪按名寻址契约
	assert_int(spr.hframes).is_equal(4)
	assert_int(spr.vframes).is_equal(4)
	assert_int(spr.frame).is_equal(0)
	assert_vector(spr.texture.get_size()).is_equal(Vector2(SHEET_PX, SHEET_PX))

func test_walk_anim_switches_frames_by_move_direction() -> void:
	var p := _player_in_tree()
	p.set_meta("hero", {"id": "ranger"})
	p._load_anim_sheet()                                 # meta 换装后重解析帧表
	var spr := p.get_node_or_null("Sprite") as Sprite2D
	assert_bool(spr.texture == ArtLookup.tex(SHEET_FMT % "ranger")).is_true()
	p._update_walk_anim(Vector2.RIGHT, 0)
	assert_int(spr.frame).is_equal(Player.ANIM_DIR_RIGHT * 4 + 1)
	p._update_walk_anim(Vector2.DOWN, 8)
	assert_int(spr.frame).is_equal(Player.ANIM_DIR_DOWN * 4 + 2)
	p._update_walk_anim(Vector2.ZERO, 9)                 # 松手：保留朝下行回 idle 列
	assert_int(spr.frame).is_equal(Player.ANIM_DIR_DOWN * 4)
	p._update_walk_anim(Vector2.LEFT, 16)
	assert_int(spr.frame).is_equal(Player.ANIM_DIR_LEFT * 4 + 3)

func test_walk_anim_redresses_after_sprite_reapply() -> void:
	# 进房重装路径：ArtLookup.apply_player_sprite 写回站立像 → 下一动画帧懒复位帧表
	var p := _player_in_tree()
	p.set_meta("hero", {"id": "ranger"})
	ArtLookup.apply_player_sprite(p)
	var spr := p.get_node_or_null("Sprite") as Sprite2D
	assert_bool(spr.texture == ArtLookup.tex(SHEET_FMT % "ranger")).is_false()  # 站立像已写入
	p._update_walk_anim(Vector2.UP, 0)
	assert_int(spr.frame).is_equal(Player.ANIM_DIR_UP * 4 + 1)
	assert_bool(spr.texture == ArtLookup.tex(SHEET_FMT % "ranger")).is_true()   # 已复位为帧表

func test_missing_sheet_falls_back_to_single_frame() -> void:
	# 无帧表英雄回落：重解析发现缺表 → hframes/vframes 复位 1（站立像整图显示
	# 而非 4x4 裁切），且帧驱动停用（后续 _update_walk_anim 不再写 frame）。
	var p := _player_in_tree()
	p.set_meta("hero", {"id": "no_such_hero"})
	p._load_anim_sheet()
	var spr := p.get_node_or_null("Sprite") as Sprite2D
	assert_int(spr.hframes).is_equal(1)
	assert_int(spr.vframes).is_equal(1)
	assert_int(spr.frame).is_equal(0)
	p._update_walk_anim(Vector2.RIGHT, 16)
	assert_int(spr.frame).is_equal(0)
