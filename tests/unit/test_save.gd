class_name TestSave
extends GdUnitTestSuite
## m1-t17 存档桩 SaveSystem：meta 进度（蓝晶/角色解锁/成就/设置）的持久化。
## 全部用例走临时 user:// 路径注入（save_path 可覆写）+ 全新实例，
## 不触碰真实 user://save.json 与 /root/SaveSystem 的持久化 API（只读冒烟除外）。


## 迁移钩子间谍：记录 _migrate 是否被调及 from_version 实参。
class SpySaver extends "res://autoload/save_system.gd":
	var migrate_call_count := 0
	var migrate_called_from := -1

	func _migrate(migrated: Dictionary, from_version: int) -> Dictionary:
		migrate_call_count += 1
		migrate_called_from = from_version
		return migrated


func _tmp_path(tag: String) -> String:
	# 随机后缀：即便上次运行残留文件也不会污染本用例
	return "user://test_save_%s_%d.json" % [tag, absi(randi())]


func _wipe(path: String) -> void:
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".tmp")


func _fresh(path: String) -> Variant:
	# 全新实例（不在树内，_ready 不触发，显式 load_save），同 test_game_db 既定模式
	var s: Variant = auto_free(load("res://autoload/save_system.gd").new())
	s.save_path = path
	s.load_save()
	return s


func _write_json(path: String, content: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(content)
	f = null


func test_autoload_registered_after_runstate() -> void:
	# 只读冒烟：注册在 RunState 之后（project.godot 顺序契约）
	var save_system: Node = get_tree().root.get_node_or_null("SaveSystem")
	assert_that(save_system).is_not_null()
	assert_int(get_tree().root.get_children().find(save_system)) \
		.is_greater(get_tree().root.get_children().find(get_tree().root.get_node("RunState")))
	assert_int(SaveSystem.gems()).is_greater_equal(0)   # API 可调（只读）


func test_missing_file_gives_defaults() -> void:
	var path := _tmp_path("missing")
	_wipe(path)
	var s: Variant = _fresh(path)
	assert_int(s.gems()).is_equal(0)
	assert_array(s.data["unlocked_heroes"]).is_equal(["vanguard"])
	assert_dict(s.data["achievements"]).is_empty()
	_wipe(path)


func test_defaults_shape() -> void:
	var path := _tmp_path("shape")
	_wipe(path)
	var s: Variant = _fresh(path)
	assert_int(s.data["version"]).is_equal(2)   # m2-t32 起 v2：成就字段版本化（K.5）
	assert_int(s.data["gems"]).is_equal(0)
	assert_array(s.data["unlocked_heroes"]).is_equal(["vanguard"])
	assert_dict(s.data["achievements"]).is_empty()
	assert_float(s.data["settings"]["screen_shake"]).is_equal(1.0)
	assert_bool(s.data["settings"]["damage_numbers"]).is_true()
	assert_bool(s.data["settings"]["colorblind_shapes"]).is_false()
	assert_bool(s.data["settings"]["auto_aim"]).is_true()
	assert_bool(s.data["settings"]["touch_controls"]).is_false()
	_wipe(path)


func test_corrupted_json_falls_back_to_defaults() -> void:
	# fail-SOFT：损坏档 push_error + 默认档，绝不让玩家存档阻断启动
	var path := _tmp_path("corrupt")
	_wipe(path)
	_write_json(path, '{"gems": 999, oops')
	var s: Variant = _fresh(path)
	assert_int(s.gems()).is_equal(0)
	assert_array(s.data["unlocked_heroes"]).is_equal(["vanguard"])
	_wipe(path)


func test_non_dict_json_falls_back_to_defaults() -> void:
	var path := _tmp_path("nondict")
	_wipe(path)
	_write_json(path, '[1, 2, 3]')
	var s: Variant = _fresh(path)
	assert_int(s.gems()).is_equal(0)
	assert_dict(s.data["achievements"]).is_empty()
	_wipe(path)


func test_wrong_typed_keys_backfill_defaults() -> void:
	# 可解析但键类型错：逐键回落默认（同样 fail-SOFT），不崩溃不半档
	var path := _tmp_path("badtypes")
	_wipe(path)
	_write_json(path, '{"version": 1, "gems": "many", "unlocked_heroes": 3, "settings": "off"}')
	var s: Variant = _fresh(path)
	assert_int(s.gems()).is_equal(0)
	assert_array(s.data["unlocked_heroes"]).is_equal(["vanguard"])
	assert_bool(s.data["settings"]["auto_aim"]).is_true()
	_wipe(path)


func test_roundtrip_persists_all_fields() -> void:
	var path := _tmp_path("roundtrip")
	_wipe(path)
	var s: Variant = _fresh(path)
	s.add_gems(42)
	s.unlock_hero("ranger")
	s.data["achievements"]["first_kill"] = true
	s.set_setting("screen_shake", 0.5)
	s.set_setting("damage_numbers", false)
	# 全新实例从盘上重读 → 逐字段一致
	var fresh: Variant = _fresh(path)
	assert_int(fresh.gems()).is_equal(42)
	assert_array(fresh.data["unlocked_heroes"]).is_equal(["vanguard", "ranger"])
	assert_bool(fresh.data["achievements"].get("first_kill", false)).is_true()
	assert_float(fresh.get_setting("screen_shake", 9.9)).is_equal(0.5)
	assert_bool(fresh.get_setting("damage_numbers", true)).is_false()
	assert_int(fresh.data["version"]).is_equal(2)   # m2-t32 起 v2
	_wipe(path)


func test_add_gems_persists() -> void:
	var path := _tmp_path("gems")
	_wipe(path)
	var s: Variant = _fresh(path)
	s.add_gems(30)
	assert_int(s.gems()).is_equal(30)
	s.add_gems(12)
	assert_int(s.gems()).is_equal(42)
	var fresh: Variant = _fresh(path)
	assert_int(fresh.gems()).is_equal(42)
	_wipe(path)


func test_unlock_hero_appends_and_persists() -> void:
	var path := _tmp_path("unlock")
	_wipe(path)
	var s: Variant = _fresh(path)
	assert_bool(s.unlock_hero("ranger")).is_true()
	var fresh: Variant = _fresh(path)
	assert_array(fresh.data["unlocked_heroes"]).is_equal(["vanguard", "ranger"])
	_wipe(path)


func test_unlock_hero_idempotent() -> void:
	var path := _tmp_path("unlock_dup")
	_wipe(path)
	var s: Variant = _fresh(path)
	assert_bool(s.unlock_hero("ranger")).is_true()
	assert_bool(s.unlock_hero("ranger")).is_false()   # 幂等：重复解锁拒绝且不重复入库
	assert_array(s.data["unlocked_heroes"]).is_equal(["vanguard", "ranger"])
	_wipe(path)


func test_settings_roundtrip() -> void:
	var path := _tmp_path("settings")
	_wipe(path)
	var s: Variant = _fresh(path)
	s.set_setting("auto_aim", false)
	s.set_setting("touch_controls", true)
	assert_bool(s.get_setting("auto_aim", true)).is_false()
	assert_bool(s.get_setting("touch_controls", false)).is_true()
	var fresh: Variant = _fresh(path)
	assert_bool(fresh.get_setting("auto_aim", true)).is_false()
	assert_bool(fresh.get_setting("touch_controls", false)).is_true()
	# 未写入的键取默认
	assert_str(fresh.get_setting("not_a_key", "fallback")).is_equal("fallback")
	_wipe(path)


func test_migration_stub_called_with_from_version() -> void:
	var path := _tmp_path("migrate")
	_wipe(path)
	_write_json(path, '{"version": 0, "gems": 7}')
	var spy := SpySaver.new()
	auto_free(spy)
	spy.save_path = path
	spy.load_save()
	assert_int(spy.migrate_call_count).is_equal(1)
	assert_int(spy.migrate_called_from).is_equal(0)
	assert_int(spy.data["version"]).is_equal(2)   # 迁移后盖当前版本戳（m2-t32 起 v2）
	assert_int(spy.gems()).is_equal(7)
	_wipe(path)


func test_no_migration_for_current_version() -> void:
	# m2-t31 起 SAVE_VERSION=2：当前版本档不再迁移（v1 档迁移见 v2 用例组）
	var path := _tmp_path("nomigrate")
	_wipe(path)
	_write_json(path, '{"version": 2, "gems": 5}')   # m2-t32 起当前版本=2（v1 会走迁移）
	var spy := SpySaver.new()
	auto_free(spy)
	spy.save_path = path
	spy.load_save()
	assert_int(spy.migrate_call_count).is_equal(0)
	assert_int(spy.gems()).is_equal(5)
	_wipe(path)


func test_missing_version_migrates_from_zero() -> void:
	var path := _tmp_path("nover")
	_wipe(path)
	_write_json(path, '{"gems": 3}')
	var spy := SpySaver.new()
	auto_free(spy)
	spy.save_path = path
	spy.load_save()
	assert_int(spy.migrate_call_count).is_equal(1)
	assert_int(spy.migrate_called_from).is_equal(0)
	assert_int(spy.gems()).is_equal(3)
	assert_int(spy.data["version"]).is_equal(2)
	_wipe(path)


# ================================================================ m2-t31 Boss 首杀名录

func test_boss_first_kills_default_empty() -> void:
	# additive 键位：旧档缺失由 _merge_saved 回落默认空表（同 purchased_talents 口径）。
	var path := _tmp_path("bosskills_default")
	_wipe(path)
	var s: Variant = _fresh(path)
	assert_array(s.boss_first_kills()).is_empty()
	_wipe(path)


func test_record_boss_first_kill_appends_persists_idempotent() -> void:
	var path := _tmp_path("bosskills_record")
	_wipe(path)
	var s: Variant = _fresh(path)
	assert_bool(s.record_boss_first_kill("vine_colossus")).is_true()
	assert_array(s.boss_first_kills()).is_equal(["vine_colossus"])
	assert_bool(s.record_boss_first_kill("vine_colossus")).is_false()   # 幂等：不重复入库
	assert_array(s.boss_first_kills()).is_equal(["vine_colossus"])
	assert_bool(s.record_boss_first_kill("frost_widow")).is_true()
	# 全新实例从盘上重读 → 名录完整（跨局防首杀重刷）。
	var fresh: Variant = _fresh(path)
	assert_array(fresh.boss_first_kills()).is_equal(["vine_colossus", "frost_widow"])
	_wipe(path)


func test_boss_first_kills_merge_filters_dirty_elements() -> void:
	# 档内非数组/脏元素防御性过滤（同 unlocked_weapons 口径），非法元素静默丢弃。
	var path := _tmp_path("bosskills_merge")
	_wipe(path)
	_write_json(path, '{"version": 1, "boss_first_kills": ["vine_colossus", 3, "frost_widow"]}')
	var s: Variant = _fresh(path)
	assert_array(s.boss_first_kills()).is_equal(["vine_colossus", "frost_widow"])
	_wipe(path)


func test_boss_first_kills_wrong_typed_key_backfills_default() -> void:
	var path := _tmp_path("bosskills_badtype")
	_wipe(path)
	_write_json(path, '{"version": 1, "boss_first_kills": "vine_colossus"}')
	var s: Variant = _fresh(path)
	assert_array(s.boss_first_kills()).is_empty()   # 类型错回落空表（fail-SOFT）
	_wipe(path)


# ================================================================ m2-t31 migration v2

func test_v1_save_migrates_to_v2_preserving_all_fields() -> void:
	# v1→v2 迁移：旧档 gems/unlocked_heroes/purchased_talents/unlocked_weapons/
	# achievements/settings/boss_first_kills 全保留；unlock_tasks 进度默认空；版本戳盖 2。
	var path := _tmp_path("v2_migrate")
	_wipe(path)
	_write_json(path, '{"version": 1, "gems": 77, "unlocked_heroes": ["vanguard", "ranger"], '
		+ '"purchased_talents": ["vit_a"], "unlocked_weapons": ["yaohuozhe"], '
		+ '"achievements": {"first_blood": true}, "boss_first_kills": ["vine_colossus"], '
		+ '"settings": {"screen_shake": 0.5, "damage_numbers": false}}')
	var s: Variant = _fresh(path)
	assert_int(s.data["version"]).is_equal(2)
	assert_int(s.gems()).is_equal(77)
	assert_array(s.data["unlocked_heroes"]).is_equal(["vanguard", "ranger"])
	assert_array(s.purchased_talents()).is_equal(["vit_a"])
	assert_array(s.unlocked_weapons()).is_equal(["yaohuozhe"])
	assert_dict(s.data["achievements"]).is_equal({"first_blood": true})
	assert_array(s.boss_first_kills()).is_equal(["vine_colossus"])
	assert_float(float(s.get_setting("screen_shake", 9.9))).is_equal(0.5)
	assert_bool(bool(s.get_setting("damage_numbers", true))).is_false()
	assert_dict(s.unlock_tasks()).is_empty()      # 新字段默认空（空进度）
	_wipe(path)


func test_migration_v2_idempotent_double_load() -> void:
	# 迁移幂等：v1 档载入迁移 → 正常写入 → 全新实例二次载入（已是 v2）不重复
	# 迁移、数组不翻倍、字段不丢。
	var path := _tmp_path("v2_idempotent")
	_wipe(path)
	_write_json(path, '{"version": 1, "gems": 12, "unlocked_heroes": ["vanguard", "ranger"], '
		+ '"purchased_talents": ["t1"], "boss_first_kills": ["frost_widow"]}')
	var first: Variant = _fresh(path)
	assert_int(first.data["version"]).is_equal(2)
	first.add_gems(3)                              # 迁移后正常写入（15）
	first.record_talent_purchase("t2")
	var second: Variant = _fresh(path)             # 二次载入：from_version=2 不再迁移
	assert_int(second.data["version"]).is_equal(2)
	assert_int(second.gems()).is_equal(15)
	assert_array(second.data["unlocked_heroes"]).is_equal(["vanguard", "ranger"])
	assert_array(second.purchased_talents()).is_equal(["t1", "t2"])
	assert_array(second.boss_first_kills()).is_equal(["frost_widow"])
	_wipe(path)


func test_migration_v2_no_replay_for_v2_save() -> void:
	# v2 档直接载入：_migrate 不被调（幂等的第二半：不重复走迁移分支）。
	var path := _tmp_path("v2_nomigrate")
	_wipe(path)
	_write_json(path, '{"version": 2, "gems": 9, "unlock_tasks": {"kills_total": 4}}')
	var spy := SpySaver.new()
	auto_free(spy)
	spy.save_path = path
	spy.load_save()
	assert_int(spy.migrate_call_count).is_equal(0)
	assert_int(spy.gems()).is_equal(9)
	assert_int(int(spy.unlock_tasks().get("kills_total", 0))).is_equal(4)
	_wipe(path)


func test_unlock_tasks_progress_roundtrip() -> void:
	# unlock_tasks 进度（CodexSystem.counters 快照）往返：floor_clears 的 JSON 字符串键
	# 归一化回 int（CodexSystem._cur_of 按整型层号查桶，字符串键会静默丢进度）。
	var path := _tmp_path("v2_tasks")
	_wipe(path)
	var s: Variant = _fresh(path)
	s.record_unlock_tasks({
		"kills_total": 42, "resonances_total": 3, "crafts_total": 1,
		"purchases_total": 2, "gems_earned_total": 300,
		"floor_clears": {1: 4, 2: 1},
	})
	var fresh: Variant = _fresh(path)             # 盘上 JSON：floor_clears 键已变字符串
	assert_int(int(fresh.unlock_tasks().get("kills_total", 0))).is_equal(42)
	assert_int(int(fresh.unlock_tasks().get("gems_earned_total", 0))).is_equal(300)
	var clears: Dictionary = fresh.unlock_tasks().get("floor_clears", {})
	assert_int(int(clears.get(1, 0))).is_equal(4)  # 键归一化回 int
	assert_int(int(clears.get(2, 0))).is_equal(1)
	_wipe(path)


func test_unlock_tasks_dirty_save_filtered() -> void:
	# fail-SOFT：标量计数器非数字 / floor_clears 非字典 → 该键回落默认（0 / 空桶）。
	var path := _tmp_path("v2_tasks_dirty")
	_wipe(path)
	_write_json(path, '{"version": 1, "unlock_tasks": {"kills_total": "many", '
		+ '"floor_clears": "notdict", "gems_earned_total": 7}}')
	var s: Variant = _fresh(path)
	assert_int(int(s.unlock_tasks().get("kills_total", 0))).is_equal(0)
	assert_dict(s.unlock_tasks().get("floor_clears", {})).is_empty()
	assert_int(int(s.unlock_tasks().get("gems_earned_total", 0))).is_equal(7)
	_wipe(path)
