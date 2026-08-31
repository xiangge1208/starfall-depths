class_name TestCodexSystem
extends GdUnitTestSuite
## M2-T20 图鉴 + 解锁任务引擎契约测试。
## 数据源 data/unlock_tasks.json（T3 定稿 49 条，test_unlock_data 已锁 schema）；
## 本卡消费：progress 六类条件判定（注入计数）/ check_unlocks 解锁持久化（SaveSystem.
## unlocked_weapons）/ 掉落池过滤（locked 未解锁不入池、解锁非★入池、★恒不入池）/
## 图鉴 UI 数据驱动断言（115 格：已解锁亮名称、未解锁 ??? + 中文条件）。
## SaveSystem 全走临时 user:// 路径注入（同 test_save/test_talent_system 模式），
## 不触碰真实 user://save.json；CodexSystem 用 .new(save) 直构（不入树 → _ready
## 不连 EventBus，测试间零串扰）。GameDB.weapons 全局池被 grant 污染后逐用例还原。


# ---- 夹具 ----

const TASKS_PATH := "res://data/unlock_tasks.json"
const CODEX_SCENE := "res://ui/codex.tscn"

var _save_paths: Array[String] = []
var _pool_snapshot: Array = []


func before_test() -> void:
	_pool_snapshot = GameDB.weapons.keys()
	# 抹平真实档（user://save.json）已解锁武器经 autoload 启动回池造成的基线漂移：
	# 本套件统一从「49 把全锁」基线出发，after_test 按快照原样还原（含真实档授权）。
	for id: String in GameDB.weapons.keys():
		if bool((GameDB.weapons[id] as Dictionary).get("locked", false)):
			GameDB.weapons.erase(id)


func after_test() -> void:
	# 还原被 grant_to_pool 扩池的全局 GameDB.weapons（其他用例看到基线池）
	for id: String in GameDB.weapons.keys():
		if not _pool_snapshot.has(id):
			GameDB.weapons.erase(id)
	for path in _save_paths:
		DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(path + ".tmp")
	_save_paths.clear()


func _tmp_path(tag: String) -> String:
	var path := "user://test_codex_%s_%d.json" % [tag, absi(randi())]
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".tmp")
	_save_paths.append(path)
	return path


## 全新 CodexSystem（save 注入，不入树 → 不连 EventBus 不读全局档）。
## 无 class_name（autoload 命名规则同 GameDB/SaveSystem）→ load 脚本直构（同 _fresh_save 手法）。
func _cs(tag: String) -> Variant:
	return auto_free(load("res://core/meta/codex_system.gd").new(_cs_with_save(tag)))


func _cs_with_save(tag: String) -> Variant:
	var s: Variant = auto_free(load("res://autoload/save_system.gd").new())
	s.save_path = _tmp_path(tag)
	s.load_save()
	return s


# ---- 任务表装载 ----

func test_tasks_loaded_all_49() -> void:
	var cs: Variant = _cs("load")
	assert_int(cs.tasks.size()).is_equal(49)


func test_tasks_goal_param_restored_to_int() -> void:
	# JSON 数字为 float：装载时必须整值还原（进度比较与 UI 文案都依赖 int）
	var cs: Variant = _cs("int")
	assert_int(typeof(cs.tasks["yahuozhe"]["goal"])).is_equal(TYPE_INT)
	assert_int(typeof(cs.tasks["guanri"]["param"])).is_equal(TYPE_INT)
	assert_int(int(cs.tasks["guanri"]["param"])).is_equal(2)


# ---- progress：六类条件（注入计数） ----

func test_progress_all_condition_types_with_injected_counters() -> void:
	var cs: Variant = _cs("types")
	cs.counters["kills_total"] = 299          # yahuozhe kill_x 300
	cs.counters["resonances_total"] = 120     # dianque resonate_x 120
	cs.counters["crafts_total"] = 6           # leishenzhichui craft_x 6
	cs.counters["purchases_total"] = 24       # fenshenxinhaotan buy_x 25
	cs.counters["gems_earned_total"] = 1000   # wurenjimujian collect_gems_x 1000
	cs.counters["floor_clears"] = {2: 1}      # guanri clear_floor_x(A2) ×2
	assert_dict(cs.progress("yahuozhe")).is_equal({"cur": 299, "goal": 300})
	assert_dict(cs.progress("dianque")).is_equal({"cur": 120, "goal": 120})
	assert_dict(cs.progress("leishenzhichui")).is_equal({"cur": 6, "goal": 6})
	assert_dict(cs.progress("fenshenxinhaotan")).is_equal({"cur": 24, "goal": 25})
	assert_dict(cs.progress("wurenjimujian")).is_equal({"cur": 1000, "goal": 1000})
	assert_dict(cs.progress("guanri")).is_equal({"cur": 1, "goal": 2})


func test_progress_unknown_task_returns_zeroed() -> void:
	var cs: Variant = _cs("unknown")
	assert_dict(cs.progress("no_such_weapon")).is_equal({"cur": 0, "goal": 0})


func test_progress_floor_clear_buckets_by_param_floor() -> void:
	# clear_floor_x 按层号分桶：clears[2]=3 只喂 param=2 的任务，不喂 param=3（caijue）
	var cs: Variant = _cs("bucket")
	cs.counters["floor_clears"] = {2: 3}
	assert_int(int(cs.progress("guanri")["cur"])).is_equal(3)
	assert_int(int(cs.progress("caijue")["cur"])).is_equal(0)


# ---- check_unlocks：解锁 + 持久化 ----

func test_check_unlocks_unlocks_and_persists_and_emits() -> void:
	var cs: Variant = _cs("unlock")
	var save: Variant = cs.save_system
	cs.counters["kills_total"] = 300
	var fired: Array = []
	cs.weapon_unlocked.connect(func(id: String) -> void: fired.append(id))
	var newly: Array[String] = cs.check_unlocks()
	assert_array(newly).contains("yahuozhe")
	assert_array(fired).contains("yahuozhe")
	assert_array(save.unlocked_weapons()).contains("yahuozhe")
	# 条件未达的不得误解锁
	assert_array(save.unlocked_weapons()).not_contains("yingwan")


func test_check_unlocks_idempotent_second_call_empty() -> void:
	var cs: Variant = _cs("idem")
	cs.counters["kills_total"] = 300
	assert_array(cs.check_unlocks()).is_not_empty()
	assert_array(cs.check_unlocks()).is_empty()


func test_unlock_survives_save_reload_roundtrip() -> void:
	var path := _tmp_path("roundtrip")
	var s1: Variant = auto_free(load("res://autoload/save_system.gd").new())
	s1.save_path = path
	s1.load_save()
	assert_bool(s1.unlock_weapon("yahuozhe")).is_true()
	var s2: Variant = auto_free(load("res://autoload/save_system.gd").new())
	s2.save_path = path
	s2.load_save()
	assert_array(s2.unlocked_weapons()).contains_exactly(["yahuozhe"])


func test_unlock_weapon_idempotent() -> void:
	var s: Variant = _cs_with_save("idemsave")
	assert_bool(s.unlock_weapon("yahuozhe")).is_true()
	assert_bool(s.unlock_weapon("yahuozhe")).is_false()   # 幂等：重复入库拒绝
	assert_int(s.unlocked_weapons().size()).is_equal(1)


# ---- 掉落池过滤 ----

func test_drop_pool_excludes_locked_by_default() -> void:
	# 基线：非 locked 全在池；locked（yahuozhe）不入池
	assert_bool(GameDB.drop_pool().has("baoliejian")) \
		.override_failure_message("non-locked weapon missing from pool").is_true()
	assert_bool(GameDB.drop_pool().has("yahuozhe")) \
		.override_failure_message("locked weapon leaked into pool").is_false()
	assert_int(GameDB.drop_pool().size()).is_equal(66)   # 115 − 49 locked


func test_unlocked_non_forge_enters_drop_pool() -> void:
	var cs: Variant = _cs("poolin")
	cs.counters["kills_total"] = 300
	cs.check_unlocks()
	assert_bool(GameDB.drop_pool().has("yahuozhe")) \
		.override_failure_message("unlocked weapon must re-enter drop pool").is_true()


func test_forge_only_unlocked_still_excluded_from_drop_pool() -> void:
	# ★熔铸限定（J.6）：达成解锁条件后进图鉴，但仍不入普通掉落池
	var cs: Variant = _cs("forge")
	cs.counters["crafts_total"] = 8   # xingyunpao craft_x 8（forge_only）
	var newly: Array[String] = cs.check_unlocks()
	assert_array(newly).contains("xingyunpao")
	assert_array(cs.save_system.unlocked_weapons()).contains("xingyunpao")
	assert_bool(GameDB.drop_pool().has("xingyunpao")) \
		.override_failure_message("forge_only weapon must never enter drop pool").is_false()


func test_grant_to_pool_unknown_and_duplicate_safe() -> void:
	GameDB.grant_to_pool("yahuozhe")
	assert_bool(GameDB.drop_pool().has("yahuozhe")).is_true()
	GameDB.grant_to_pool("yahuozhe")                       # 重复 grant 幂等
	GameDB.grant_to_pool("no_such_id")                     # 未知 id 防御性忽略
	assert_int(GameDB.drop_pool().size()).is_equal(67)


# ---- 事件计数 API ----

func test_count_events_increment_counters() -> void:
	var cs: Variant = _cs("events")
	cs.count_kill("kuli_bug")
	cs.count_kill("cave_bat")
	cs.count_resonate()
	cs.count_craft()
	cs.count_buy()
	cs.count_gems(60)
	assert_int(int(cs.counters["kills_total"])).is_equal(2)
	assert_int(int(cs.counters["resonances_total"])).is_equal(1)
	assert_int(int(cs.counters["crafts_total"])).is_equal(1)
	assert_int(int(cs.counters["purchases_total"])).is_equal(1)
	assert_int(int(cs.counters["gems_earned_total"])).is_equal(60)


func test_on_floor_entered_counts_clear_and_gems() -> void:
	# 过第 N 层 = 进入 N+1 层：enter(2) 记 clears[1] +60 蓝；enter(3) 记 clears[2] +120
	var cs: Variant = _cs("floor")
	cs.on_floor_entered(1)   # 开局进入 1 层：不产生任何计数
	assert_dict(cs.snapshot_counters()["floor_clears"]).is_empty()
	cs.on_floor_entered(2)
	cs.on_floor_entered(3)
	var c: Dictionary = cs.counters
	assert_int(int(c["floor_clears"][1])).is_equal(1)
	assert_int(int(c["floor_clears"][2])).is_equal(1)
	assert_int(int(c["gems_earned_total"])).is_equal(180)   # 60 + 120
	assert_int(int(cs.progress("guanri")["cur"])).is_equal(1)


func test_on_floor_entered_triggers_check_unlocks() -> void:
	# guanri：通过第 2 层 2 次 → enter(3) 两次即解锁（1 行挂点自动结算）；
	# 第一次 enter(3) 只达成 clears[2]=1 → 坠星大剑（A2 ×1）先解锁，guanri 未达
	var cs: Variant = _cs("hook")
	cs.on_floor_entered(3)
	assert_array(cs.save_system.unlocked_weapons()).contains("zhuixingdajian")
	assert_array(cs.save_system.unlocked_weapons()).not_contains("guanri")
	cs.on_floor_entered(3)
	assert_array(cs.save_system.unlocked_weapons()).contains("guanri")


# ---- 图鉴 UI（数据驱动断言） ----

func test_codex_scene_builds_115_cells() -> void:
	var ui: Control = auto_free((load(CODEX_SCENE) as PackedScene).instantiate())
	ui.codex_system = _cs("ui115")
	add_child(ui)
	assert_int(ui.cell_count()).is_equal(115)


func test_codex_cell_states_unlocked_vs_locked() -> void:
	var cs: Variant = _cs("uicell")
	cs.counters["kills_total"] = 300
	cs.check_unlocks()   # yahuozhe 解锁
	var ui: Control = auto_free((load(CODEX_SCENE) as PackedScene).instantiate())
	ui.codex_system = cs
	add_child(ui)
	var got: Dictionary = ui.cell_info("yahuozhe")
	assert_bool(bool(got["unlocked"])).is_true()
	assert_str(String(got["name_text"])).is_equal("哑火者")   # 已解锁亮真名
	var locked: Dictionary = ui.cell_info("yingwan")
	assert_bool(bool(locked["unlocked"])).is_false()
	assert_str(String(locked["name_text"])).is_equal("???")   # 未解锁灰 + ???
	assert_str(String(locked["cond_text"])).contains("累计击杀 400 名敌人")
	assert_str(String(locked["cond_text"])).contains("0/400")   # 中文条件 + 进度


func test_codex_summary_counts_unlocked() -> void:
	var cs: Variant = _cs("uisum")
	cs.counters["kills_total"] = 300
	cs.check_unlocks()
	var ui: Control = auto_free((load(CODEX_SCENE) as PackedScene).instantiate())
	ui.codex_system = cs
	add_child(ui)
	assert_str(ui.summary_text()).contains("1 / 115")


# ================================================================ m2-t31 计数器持久化（存档 v2 对接）

func test_counters_restore_from_save_on_construct() -> void:
	# J.2 跨局累计：档内 unlock_tasks 进度在构造时恢复（含 floor_clears 层号分桶）。
	var save: Variant = _cs_with_save("restore")
	save.record_unlock_tasks({
		"kills_total": 42, "gems_earned_total": 300,
		"floor_clears": {1: 4, 2: 1},
	})
	var cs: Variant = auto_free(load("res://core/meta/codex_system.gd").new(save))
	assert_int(int(cs.counters["kills_total"])).is_equal(42)
	assert_int(int(cs.counters["gems_earned_total"])).is_equal(300)
	var clears: Dictionary = cs.counters["floor_clears"]
	assert_int(int(clears.get(1, 0))).is_equal(4)
	assert_int(int(clears.get(2, 0))).is_equal(1)


func test_persist_counters_writes_snapshot_to_save() -> void:
	# persist_counters：内存计数器快照整体覆写入档（SaveSystem.record_unlock_tasks）。
	var cs: Variant = _cs("persist")
	for _i in 7:
		cs.count_kill("kuli_bug")
	cs.persist_counters()
	var saved: Dictionary = cs.save_system.unlock_tasks()
	assert_int(int(saved["kills_total"])).is_equal(7)


func test_on_floor_entered_persists_counters_and_restores_cumulative() -> void:
	# 层进入 = 计数结算点（与 check_unlocks 合一）：写档后全新实例读回继续累计。
	var cs: Variant = _cs("floorpersist")
	for _i in 3:
		cs.count_kill("kuli_bug")
	cs.on_floor_entered(2)
	assert_int(int(cs.save_system.unlock_tasks()["kills_total"])).is_equal(3)
	var cs2: Variant = auto_free(load("res://core/meta/codex_system.gd").new(cs.save_system))
	cs2.count_kill("kuli_bug")     # 恢复 3 后继续累计 → 4
	assert_int(int(cs2.counters["kills_total"])).is_equal(4)


func test_check_unlocks_piggybacks_counter_persist() -> void:
	# 解锁达成时计数器快照随解锁写盘搭车（解锁本身已写盘，无额外热路径 IO）。
	# zhuixingdajian = clear_floor_x param 2 goal 1（通过第 2 层 ×1）。
	var cs: Variant = _cs("unlockpersist")
	assert_bool(cs.save_system.unlocked_weapons().has("zhuixingdajian")).is_false()
	cs.on_floor_entered(3)         # 进入第 3 层 = 通过第 2 层 ×1 → 解锁达成
	assert_bool(cs.save_system.unlocked_weapons().has("zhuixingdajian")).is_true()
	var saved: Dictionary = cs.save_system.unlock_tasks()
	assert_int(int(saved["floor_clears"].get(2, 0))).is_equal(1)
