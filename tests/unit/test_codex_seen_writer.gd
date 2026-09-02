class_name TestCodexSeenWriter
extends GdUnitTestSuite
## m4-c3：codex_seen 写入方（K.3/K.5 collector/grand_collector 权威源落键）。
## 写入集 = 默认池首取 ∪ 掉落/商店/熔铸（四路共同 choke = WeaponRig.equip）
## ∪ 任务解锁（CodexSystem.check_unlocks 直写）。覆盖：
##   - SaveSystem.record_codex_seen / codex_seen 持久化键（幂等 + 落盘 + 读回）
##   - CodexSystem.mark_weapon_seen（幂等 + weapon_seen 信号 + 遥测 + 防御性忽略）
##   - check_unlocks 任务解锁侧同入见集
##   - WeaponRig.equip 获取点收口
##   - AchievementSystem weapon_seen → recheck 订阅 + collector(50)/grand_collector(115)
##     经见集自动点亮（unlocked_weapons 恒空 → 证明走的是权威口径而非回落）。
## SaveSystem 全走临时 user:// 路径（test_codex_system 同款），零真实档残留。

const SAVE_SCRIPT := "res://autoload/save_system.gd"
const CODEX_SCRIPT := "res://core/meta/codex_system.gd"

var _save_paths: Array[String] = []
var _pool_snapshot: Array = []
var _codex_save_restore: Node = null
var _achv_save_restore: Node = null
var _counters_snapshot: Dictionary = {}


func before_test() -> void:
	_pool_snapshot = GameDB.weapons.keys()


func after_test() -> void:
	for id: String in GameDB.weapons.keys():
		if not _pool_snapshot.has(id):
			GameDB.weapons.erase(id)          # 还原被 grant_to_pool 扩池的全局表
	if _codex_save_restore != null:
		CodexSystem.save_system = _codex_save_restore
		_codex_save_restore = null
	if _counters_snapshot != null:
		CodexSystem.counters = _counters_snapshot   # 深快照还原（活计数器防搭车）
		_counters_snapshot = {}
	if _achv_save_restore != null:
		AchievementSystem.save_system = _achv_save_restore
		AchievementSystem.reset_session()
		_achv_save_restore = null
	for path in _save_paths:
		DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(path + ".tmp")
	_save_paths.clear()


func _tmp_path(tag: String) -> String:
	var path := "user://test_codex_seen_%s_%d.json" % [tag, absi(randi())]
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".tmp")
	_save_paths.append(path)
	return path


func _fresh_save(tag: String) -> Node:
	var s: Node = auto_free(load(SAVE_SCRIPT).new())
	s.save_path = _tmp_path(tag)
	s.load_save()
	return s


## 全新 CodexSystem（save 注入，不入树 → _ready 不跑不连 EventBus，测试间零串扰）。
func _codex(save: Node) -> Node:
	return auto_free(load(CODEX_SCRIPT).new(save))


## 全局 autoload 换临时隔离档（test_achievement_wiring 密闭口径同款），after_test 还原。
## 两 autoload 共用同一隔离档——生产拓扑即同一 SaveSystem 单例（权威源不可割裂）；
## CodexSystem 活计数器深快照后归零（recheck 轮询 counter:* 防既有累计搭车解锁）。
func _isolate_autoloads() -> void:
	_codex_save_restore = CodexSystem.save_system
	_achv_save_restore = AchievementSystem.save_system
	_counters_snapshot = CodexSystem.counters.duplicate(true)
	var iso: Node = _fresh_save("codex_seen_iso")
	CodexSystem.save_system = iso
	AchievementSystem.save_system = iso
	for key: String in CodexSystem.COUNTER_KEYS:
		CodexSystem.counters[key] = 0
	CodexSystem.counters["floor_clears"] = {}


# ---- SaveSystem 持久化键 ----

func test_record_codex_seen_idempotent_and_persists() -> void:
	var s := _fresh_save("record")
	assert_bool(s.data.has("codex_seen")).is_false()      # legacy 骨架缺键（回落契约半边）
	assert_bool(s.record_codex_seen("laohuoji")).is_true()
	assert_bool(s.record_codex_seen("laohuoji")).is_false()   # 已见过：false 不重写盘
	s.record_codex_seen("dianque")
	assert_array(s.codex_seen()).contains("laohuoji", "dianque")
	# 落盘读回：新实例同路径 load_save → 见集还原（_merge_saved 同口径合并）。
	var s2: Node = load(SAVE_SCRIPT).new()
	s2.save_path = s.save_path
	s2.load_save()
	assert_array(s2.codex_seen()).contains("laohuoji", "dianque")
	s2.free()

func test_codex_seen_reader_filters_dirty_elements() -> void:
	var s := _fresh_save("dirty")
	s.data["codex_seen"] = [1, "laohuoji", null, "dianque"]
	assert_array(s.codex_seen()).contains("laohuoji", "dianque")   # 非法元素静默丢弃
	assert_int(s.codex_seen().size()).is_equal(2)

# ---- CodexSystem.mark_weapon_seen ----

func test_mark_weapon_seen_emits_once_logs_once_idempotent() -> void:
	var codex := _codex(_fresh_save("mark"))
	var seen_ids: Array[String] = []
	codex.weapon_seen.connect(func(id: String) -> void: seen_ids.append(id))
	var buf_before := Telemetry._buf.size()
	codex.mark_weapon_seen("laohuoji")
	assert_array(seen_ids).contains("laohuoji")
	assert_int(Telemetry._buf.size()).is_equal(buf_before + 1)
	assert_str(String(Telemetry._buf[Telemetry._buf.size() - 1])).starts_with("codex_seen")
	codex.mark_weapon_seen("laohuoji")                    # 已见过：不重发不重记
	assert_int(seen_ids.size()).is_equal(1)
	assert_int(Telemetry._buf.size()).is_equal(buf_before + 1)
	codex.mark_weapon_seen("dianque")
	assert_int(seen_ids.size()).is_equal(2)
	assert_array(codex.save_system.codex_seen()).contains("laohuoji", "dianque")

func test_mark_weapon_seen_defensive_noop_without_save_or_empty_id() -> void:
	var codex := _codex(null)                             # 直构未注入 save → no-op
	codex.mark_weapon_seen("laohuoji")                    # 不抛错不动作
	var codex2 := _codex(_fresh_save("empty_id"))
	codex2.mark_weapon_seen("")
	assert_int(codex2.save_system.codex_seen().size()).is_equal(0)

# ---- 任务解锁侧（check_unlocks 直写） ----

func test_check_unlocks_records_task_unlock_into_seen_set() -> void:
	var codex := _codex(_fresh_save("task"))
	codex.counters["kills_total"] = 300                   # yahuozhe kill_x goal 300
	var newly: Array[String] = codex.check_unlocks()
	assert_array(newly).contains("yahuozhe")
	assert_array(codex.save_system.codex_seen()).contains("yahuozhe")
	assert_array(codex.save_system.unlocked_weapons()).contains("yahuozhe")

# ---- 获取点收口（WeaponRig.equip = 掉落/商店/熔铸/首取共同 choke） ----

func test_weapon_rig_equip_records_seen_via_global_codex() -> void:
	_isolate_autoloads()
	var rig: WeaponRig = auto_free(WeaponRig.new())
	rig.equip("laohuoji")
	var iso: Node = CodexSystem.save_system
	assert_array(iso.codex_seen()).contains("laohuoji")
	rig.equip("laohuoji")                                 # 幂等：不重复入库
	assert_int(iso.codex_seen().size()).is_equal(1)
	rig.equip("dianque")
	assert_array(iso.codex_seen()).contains("laohuoji", "dianque")

# ---- 成就权威口径切换（collector 50 / grand_collector 115 经见集点亮） ----

func test_weapon_seen_subscription_lights_collector_then_grand_collector() -> void:
	# 端到端（生产实例）：global CodexSystem.mark_weapon_seen → weapon_seen →
	# global AchievementSystem.recheck → 见集 50 点亮 collector、115 点亮 grand_collector。
	# 全程零 unlock_weapon（unlocked_weapons 恒空）→ 点亮只能来自 codex_seen 权威口径。
	_isolate_autoloads()
	var names: Array = GameDB.weapons_all.keys()
	for i in range(49):
		CodexSystem.mark_weapon_seen(String(names[i]))
	assert_bool(AchievementSystem.is_unlocked("collector")).is_false()
	assert_int(AchievementSystem.save_system.gems()).is_equal(0)
	for i in range(49, 50):
		CodexSystem.mark_weapon_seen(String(names[i]))
	assert_bool(AchievementSystem.is_unlocked("collector")).is_true()      # 恰 50 见过
	assert_bool(AchievementSystem.is_unlocked("grand_collector")).is_false()
	assert_int(AchievementSystem.save_system.gems()).is_equal(150)
	for i in range(50, 115):
		CodexSystem.mark_weapon_seen(String(names[i]))
	assert_bool(AchievementSystem.is_unlocked("grand_collector")).is_true()
	assert_int(AchievementSystem.save_system.gems()).is_equal(650)         # 150 + 500
	assert_int(CodexSystem.save_system.codex_seen().size()).is_equal(115)

func test_collector_stays_locked_below_threshold_via_seen_set() -> void:
	# 权威口径不达标侧：见集 49 + unlocked_weapons 115 把全解锁 → collector 仍不亮
	# （键在场即权威，回落口径不参与——与 test_achievements 既有空表用例互补）。
	_isolate_autoloads()
	var names: Array = GameDB.weapons_all.keys()
	for i in range(115):
		AchievementSystem.save_system.unlock_weapon(String(names[i]))   # 回落口径满分
	for i in range(49):
		CodexSystem.mark_weapon_seen(String(names[i]))
	assert_bool(AchievementSystem.is_unlocked("collector")).is_false()
	assert_int(AchievementSystem.save_system.gems()).is_equal(0)
