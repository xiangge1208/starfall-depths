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
	assert_int(s.data["version"]).is_equal(1)
	assert_int(s.data["gems"]).is_equal(0)
	assert_array(s.data["unlocked_heroes"]).is_equal(["vanguard"])
	assert_dict(s.data["achievements"]).is_empty()
	assert_float(s.data["settings"]["screen_shake"]).is_equal(1.0)
	assert_bool(s.data["settings"]["damage_numbers"]).is_true()
	assert_bool(s.data["settings"]["colorblind_shapes"]).is_false()
	assert_bool(s.data["settings"]["auto_aim"]).is_true()
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
	assert_int(fresh.data["version"]).is_equal(1)
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
	assert_bool(s.get_setting("auto_aim", true)).is_false()
	var fresh: Variant = _fresh(path)
	assert_bool(fresh.get_setting("auto_aim", true)).is_false()
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
	assert_int(spy.data["version"]).is_equal(1)   # 迁移后盖当前版本戳
	assert_int(spy.gems()).is_equal(7)
	_wipe(path)


func test_no_migration_for_current_version() -> void:
	var path := _tmp_path("nomigrate")
	_wipe(path)
	_write_json(path, '{"version": 1, "gems": 5}')
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
	assert_int(spy.data["version"]).is_equal(1)
	_wipe(path)
