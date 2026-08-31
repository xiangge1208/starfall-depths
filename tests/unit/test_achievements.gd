class_name TestAchievements
extends GdUnitTestSuite
## M2-T32 成就系统契约测试（22 条 M2 激活 + 2 条试炼 M3 不激活）。
## 判定规格逐条来自数据表附录 K（docs/superpowers/specs/数据表附录-K-成就接线.md）：
## 判定类型白名单 event_once / event_count / state_threshold / composite 各覆盖；
## 蓝晶入账（附录 G.1 原值，M2 合计 4050）/ toast 队列 / 跨局持久化（temp path 模式）。
## SaveSystem 全走临时 user:// 路径注入（同 test_codex_system 模式），不触碰真实档；
## AchievementSystem 用 .new(save) 直构（不入树 → _ready 不连 EventBus，测试间零串扰）；
## 事件经 notify_* API 直驱（与 _ready 的 EventBus 订阅同一路径）。

const AS_PATH := "res://core/meta/achievement_system.gd"
const TOAST_PATH := "res://ui/toast.gd"
const ELITE_ID := "shuangdao_lizardman"      # enemies.json elite_affixes 非空
const NORMAL_ID := "kuli_bug"
const MELEE_ID := "tiejian"                  # weapons.json category=melee
const THROW_ID := "shoulei"                  # weapons.json category=throw
const REMOTE_ID := "laohuoji"                # weapons.json category=pistol

var _save_paths: Array[String] = []
var _run_state_snapshot: Dictionary = {}


func before_test() -> void:
	_run_state_snapshot = {"coins": RunState.coins, "run_time_frames": RunState.run_time_frames}


func after_test() -> void:
	RunState.coins = int(_run_state_snapshot["coins"])
	RunState.run_time_frames = int(_run_state_snapshot["run_time_frames"])
	for path in _save_paths:
		DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(path + ".tmp")
	_save_paths.clear()


# ---- 夹具 ----

func _tmp_path(tag: String) -> String:
	var path := "user://test_achv_%s_%d.json" % [tag, absi(randi())]
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".tmp")
	_save_paths.append(path)
	return path


func _fresh_save(tag: String) -> Variant:
	var s: Variant = auto_free(load("res://autoload/save_system.gd").new())
	s.save_path = _tmp_path(tag)
	s.load_save()
	return s


## 全新 AchievementSystem（save 注入，不入树 → 不连 EventBus；toast 注入 spy）。
func _as(tag: String) -> Variant:
	var cs: Variant = auto_free(load(AS_PATH).new(_fresh_save(tag)))
	cs.toast = _spy_toast()
	return cs


class SpyToast extends Node:
	var shown: Array[String] = []
	func show_toast(text: String, _duration: float = 3.0) -> void:
		shown.append(text)


func _spy_toast() -> SpyToast:
	return auto_free(SpyToast.new())


# ---- 判定器表（附录 K 全表装载） ----

func test_defs_load_24_rows_with_22_active() -> void:
	var cs: Variant = _as("defs")
	var defs: Array = cs.defs()
	assert_int(defs.size()).is_equal(24)
	var active := defs.filter(func(d: Dictionary) -> bool: return bool(d.get("active", false)))
	assert_int(active.size()).is_equal(22)
	var inactive_ids: Array = defs.filter(func(d: Dictionary) -> bool: return not bool(d.get("active", false))) \
		.map(func(d: Dictionary) -> String: return String(d["id"]))
	assert_array(inactive_ids).contains_exactly(["trier", "trial_master"])   # 试炼 2 条 M3


func test_defs_ids_unique_schema_and_gem_total_4050() -> void:
	var cs: Variant = _as("schema")
	var ids: Array = cs.defs().map(func(d: Dictionary) -> String: return String(d["id"]))
	var uniq := {}
	for id: String in ids:
		uniq[id] = true
	assert_int(ids.size()).is_equal(uniq.size())   # id 唯一
	var total := 0
	var whitelist: Array[String] = ["event_once", "event_count", "state_threshold", "composite"]
	for d: Dictionary in cs.defs():
		assert_str(String(d.get("name", ""))).is_not_empty()          # 中文成就名（toast 文案）
		assert_int(int(d.get("gems", -1))).is_greater_equal(0)        # 蓝晶奖励
		assert_array(whitelist).contains(String(d.get("type", "")))   # 判定类型白名单
		if bool(d.get("active", false)):
			total += int(d.get("gems", 0))
	assert_int(total).is_equal(4050)   # 附录 K 勘误口径：M2 22 条合计 4050


# ---- event_once：信号到达（参数谓词满足）即解锁 ----

func test_event_once_first_lamp_on_a1_boss_slain() -> void:
	var cs: Variant = _as("lamp")
	assert_bool(cs.is_unlocked("first_lamp")).is_false()
	assert_bool(cs.notify_boss_slain("vine_colossus", 1)).is_true()   # A1 Boss
	assert_bool(cs.is_unlocked("first_lamp")).is_true()
	assert_int(cs.save_system.gems()).is_equal(100)                   # 蓝晶入账
	var fired: Array = []
	cs.achievement_unlocked.connect(func(id: String) -> void: fired.append(id))
	assert_bool(cs.notify_boss_slain("vine_colossus", 1)).is_false()  # 幂等：重复事件不重复解锁
	assert_array(fired).is_empty()


func test_event_once_pred_blocks_wrong_floor() -> void:
	# first_land 谓词 floor_idx == 1：A2 Boss 击杀不解锁；delver 谓词 >= 3：2 层不解锁
	var cs: Variant = _as("predfloor")
	assert_bool(cs.notify_boss_slain("prism_golem", 2)).is_false()
	assert_bool(cs.is_unlocked("first_lamp")).is_false()
	assert_bool(cs.notify_floor_reached(2)).is_false()
	assert_bool(cs.is_unlocked("delver")).is_false()
	assert_bool(cs.notify_floor_reached(3)).is_true()
	assert_int(cs.save_system.gems()).is_equal(150)


func test_event_once_night_watcher_on_victory() -> void:
	# 隔离守夜人：victory 复合判定（拒绝治疗/速通者）同时求值，先破掉另两条
	var cs: Variant = _as("watcher")
	cs.notify_heart_pickup()               # 拒绝治疗：本局拾过红心 → 不解锁
	RunState.run_time_frames = 72000       # 速通者：20min 边界（严格 <）→ 不解锁
	assert_bool(cs.notify_victory()).is_true()
	assert_int(cs.save_system.gems()).is_equal(300)


# ---- event_count：会话计数达阈值 ----

func test_event_count_element_scholar_30_resonances() -> void:
	var cs: Variant = _as("scholar")
	for i in range(29):
		cs.notify_resonance()
	assert_bool(cs.is_unlocked("element_scholar")).is_false()   # 29 次未达
	cs.notify_resonance()
	assert_bool(cs.is_unlocked("element_scholar")).is_true()    # 第 30 次达成
	assert_int(cs.save_system.gems()).is_equal(150)


func test_event_count_demolition_30_props_and_dodge_master_100() -> void:
	var cs: Variant = _as("demolish")
	for i in range(30):
		cs.notify_prop_destroyed()
	assert_bool(cs.is_unlocked("demolition")).is_true()
	assert_int(cs.save_system.gems()).is_equal(50)
	for i in range(99):
		cs.notify_roll_dodge()
	assert_bool(cs.is_unlocked("dodge_master")).is_false()      # 99 次未达
	cs.notify_roll_dodge()
	assert_bool(cs.is_unlocked("dodge_master")).is_true()       # 第 100 次达成
	assert_int(cs.save_system.gems()).is_equal(150)             # 50 + 100


# ---- state_threshold：轮询 SaveSystem 字段达阈值 ----

func test_state_threshold_full_roster_6_heroes() -> void:
	var cs: Variant = _as("roster")
	for hero: String in ["blademaster", "gunner", "mage", "guardian", "assassin"]:
		cs.save_system.unlock_hero(hero)   # + vanguard 默认 = 6
	assert_bool(cs.is_unlocked("full_roster")).is_false()   # 存档变了也要 recheck 才判
	assert_array(cs.recheck()).contains("full_roster")
	assert_int(cs.save_system.gems()).is_equal(400)


func test_state_threshold_talents_12_and_24() -> void:
	var cs: Variant = _as("talent")
	var all_talents: Array = cs.save_system.data.keys()
	var talents: Array[String] = []
	for i in range(1, 25):
		talents.append("t%d" % i)
	for i in range(12):
		cs.save_system.record_talent_purchase(talents[i])
	assert_array(cs.recheck()).contains("gifted")
	assert_array(cs.recheck()).not_contains("overflowing")
	assert_int(cs.save_system.gems()).is_equal(150)
	for i in range(12, 24):
		cs.save_system.record_talent_purchase(talents[i])
	assert_array(cs.recheck()).contains("overflowing")
	assert_int(cs.save_system.gems()).is_equal(650)
	assert_int(cs.save_system.purchased_talents().size()).is_equal(24)
	assert_bool(all_talents.has("gems"))   # 存档键健全性（防误写 data）


func test_state_threshold_collector_50_grand_115() -> void:
	# codex_seen 键缺席（T25 v2 前）：回落 unlocked_weapons 口径（其子集，保守低估）
	var cs: Variant = _as("collector")
	var names: Array = GameDB.weapons_all.keys()
	for i in range(50):
		cs.save_system.unlock_weapon(String(names[i]))
	assert_array(cs.recheck()).contains("collector")
	assert_array(cs.recheck()).not_contains("grand_collector")
	assert_int(cs.save_system.gems()).is_equal(150)
	for i in range(50, 115):
		cs.save_system.unlock_weapon(String(names[i]))
	assert_array(cs.recheck()).contains("grand_collector")
	assert_int(cs.save_system.gems()).is_equal(650)


func test_state_threshold_collector_prefers_codex_seen_when_present() -> void:
	# T25 v2 落地形态：codex_seen 键在场即为权威（K.4：默认池获取 ∪ 任务解锁），
	# 不再回落 unlocked_weapons——空表计 0，解锁 115 把任务武器也不点亮藏品家
	var cs: Variant = _as("seen")
	cs.save_system.data["codex_seen"] = [] as Array[String]
	var names: Array = GameDB.weapons_all.keys()
	for i in range(115):
		cs.save_system.unlock_weapon(String(names[i]))
	assert_array(cs.recheck()).not_contains("collector")
	assert_int(cs.save_system.gems()).is_equal(0)
	cs.save_system.data["codex_seen"] = (names.slice(0, 50) as Array).map(
		func(n: Variant) -> String: return String(n))
	assert_array(cs.recheck()).contains("collector")       # 恰 50 见过
	assert_array(cs.recheck()).not_contains("grand_collector")
	assert_int(cs.save_system.gems()).is_equal(150)


func test_state_threshold_missing_counters_key_is_placeholder_zero() -> void:
	# 裁定⑨：T25 v2 counters 缺席键按占位 0 处理——熔铸匠/挑战者不误解锁
	var cs: Variant = _as("placeholder")
	assert_bool(cs.save_system.data.has("counters")).is_false()
	assert_array(cs.recheck()).not_contains("forge_smith")
	assert_array(cs.recheck()).not_contains("challenger")
	# 计数器出现（T25 v2 落地后口径）：crafts_total=10 → 熔铸匠解锁
	cs.save_system.data["counters"] = {"crafts_total": 10, "challenge_rooms_total": 2}
	assert_array(cs.recheck()).contains("forge_smith")
	assert_array(cs.recheck()).not_contains("challenger")
	assert_int(cs.save_system.gems()).is_equal(100)


# ---- composite：多条件与 ----

func test_composite_deadeye_crit_ratio_over_35pct_needs_50_shots() -> void:
	# K.3 判定式 crits/shots > 0.35 且 shots >= 50（shots = 每次命中计 1，含暴击本尊）
	var cs: Variant = _as("deadeye")
	for i in range(32):
		cs.notify_enemy_damaged(4, false)
	for i in range(17):
		cs.notify_enemy_damaged(6, true)
	assert_bool(cs.is_unlocked("deadeye")).is_false()     # 49 发 17 暴击：发数不足且 34.7% 未达
	cs.notify_enemy_damaged(6, true)
	assert_bool(cs.is_unlocked("deadeye")).is_true()      # 50 发 18 暴击 = 36% > 35%
	assert_int(cs.save_system.gems()).is_equal(100)


func test_composite_deadeye_35pct_boundary_is_strict() -> void:
	# 恰 50 发 17 暴击 = 34%（交叉乘 1700 vs 1750）：严格大于，不解锁
	var cs: Variant = _as("deadeye3")
	for i in range(33):
		cs.notify_enemy_damaged(4, false)
	for i in range(17):
		cs.notify_enemy_damaged(6, true)
	assert_int(int(cs.session["shots"])).is_equal(50)
	assert_int(int(cs.session["crits"])).is_equal(17)
	assert_bool(cs.is_unlocked("deadeye")).is_false()


func test_composite_deadeye_ratio_alone_insufficient() -> void:
	# 高暴击率但射击数不足（>=50 条件独立成立）
	var cs: Variant = _as("deadeye2")
	for i in range(10):
		cs.notify_enemy_damaged(6, true)
	assert_bool(cs.is_unlocked("deadeye")).is_false()


func test_composite_slum_king_floor1_clear_zero_deaths() -> void:
	var cs: Variant = _as("slum")
	RunState.coins = 0                     # 隔离：财神同 floor_cleared 触发
	assert_bool(cs.notify_floor_cleared(1)).is_true()
	assert_int(cs.save_system.gems()).is_equal(100)
	var cs2: Variant = _as("slum2")
	RunState.coins = 0
	cs2.notify_player_hit(4, false)        # 受击不破（口径=death 非 hurt）
	assert_bool(cs2.notify_floor_cleared(1)).is_true()
	var cs3: Variant = _as("slum3")
	RunState.coins = 0
	cs3.notify_player_hit(99, true)        # 死亡一次 → 破
	assert_bool(cs3.notify_floor_cleared(1)).is_false()


func test_composite_moneybags_500_coins_on_floor1_clear() -> void:
	var cs: Variant = _as("money")
	cs.notify_player_hit(99, true)        # 隔离：破贫民窟之王（同 floor_cleared 触发）
	RunState.coins = 400
	assert_bool(cs.notify_floor_cleared(1)).is_false()
	RunState.coins = 501
	assert_bool(cs.notify_floor_cleared(1)).is_true()   # >500 严格大于
	assert_int(cs.save_system.gems()).is_equal(100)


func test_composite_speedrunner_victory_under_20min() -> void:
	# 隔离口径：拾红心破拒绝治疗；守夜人随首次 victory 必然解锁（K.3 到达即 true），
	# 计入 gems 断言；速通者边界 72000 = 20min 整（严格 <）
	var cs: Variant = _as("speed")
	cs.notify_heart_pickup()
	RunState.run_time_frames = 72000
	cs.notify_victory()
	assert_bool(cs.is_unlocked("speedrunner")).is_false()
	assert_int(cs.save_system.gems()).is_equal(300)     # 仅守夜人
	RunState.run_time_frames = 71999
	assert_bool(cs.notify_victory()).is_true()          # 第二次 victory 只剩速通者可解
	assert_bool(cs.is_unlocked("speedrunner")).is_true()
	assert_int(cs.save_system.gems()).is_equal(450)


func test_composite_no_heal_victory_without_heart_pickup() -> void:
	# 同上隔离：速通者钉边界外；守夜人计入 gems
	var cs: Variant = _as("noheal")
	RunState.run_time_frames = 72000
	cs.notify_heart_pickup()
	cs.notify_victory()
	assert_bool(cs.is_unlocked("no_heal")).is_false()   # 拾过红心 → 破
	assert_int(cs.save_system.gems()).is_equal(300)     # 仅守夜人
	var cs2: Variant = _as("noheal2")
	RunState.run_time_frames = 72000
	assert_bool(cs2.notify_victory()).is_true()
	assert_bool(cs2.is_unlocked("no_heal")).is_true()
	assert_int(cs2.save_system.gems()).is_equal(500)    # 守夜人 300 + 拒绝治疗 200


func test_composite_nightmare_dawn_a3_boss_zero_deaths() -> void:
	var cs: Variant = _as("dawn")
	cs.notify_player_hit(99, true)
	assert_bool(cs.notify_boss_slain("prophet", 3)).is_false()
	var cs2: Variant = _as("dawn2")
	assert_bool(cs2.notify_boss_slain("prophet", 3)).is_true()
	assert_int(cs2.save_system.gems()).is_equal(300)


func test_composite_bare_hands_melee_only_floor_window() -> void:
	# 隔离口径：A1 通过点同时求值贫民窟之王/财神——死亡一次破前者，金币钉 0 破后者
	var cs: Variant = _as("bare")
	cs.notify_player_hit(99, true)
	RunState.coins = 0
	cs.notify_weapon_used(MELEE_ID)
	assert_bool(cs.notify_floor_cleared(1)).is_true()   # 本层仅近战挥击
	assert_int(cs.save_system.gems()).is_equal(200)
	var cs2: Variant = _as("bare2")
	cs2.notify_player_hit(99, true)
	RunState.coins = 0
	cs2.notify_weapon_used(REMOTE_ID)                   # 远程开火 → 破
	cs2.notify_weapon_used(MELEE_ID)
	assert_bool(cs2.notify_floor_cleared(1)).is_false()
	var cs3: Variant = _as("bare3")
	cs3.notify_weapon_used(MELEE_ID)
	cs3.notify_floor_reached(2)                         # 新层窗口重置
	cs3.notify_weapon_used(REMOTE_ID)
	assert_bool(cs3.notify_floor_cleared(2)).is_false() # A2 无同触发邻居（pred 层号隔离）


func test_composite_nitpicker_throw_weapon_a1_boss_kill() -> void:
	# 隔离口径：A1 boss_slain 同时求值初次点灯——受测实例预解锁 first_lamp 排除干扰
	var cs: Variant = _as("nitpick")
	cs.save_system.unlock_achievement("first_lamp")   # 预解锁：隔离初次点灯
	assert_bool(cs.notify_boss_slain("vine_colossus", 1, REMOTE_ID)).is_false()   # 非投掷
	var cs2: Variant = _as("nitpick2")
	assert_bool(cs2.notify_boss_slain("vine_colossus", 2, THROW_ID)).is_false()   # 非 A1
	var cs3: Variant = _as("nitpick3")
	cs3.save_system.unlock_achievement("first_lamp")   # 预解锁：隔离初次点灯
	assert_bool(cs3.notify_boss_slain("vine_colossus", 1, THROW_ID)).is_true()
	assert_int(cs3.save_system.gems()).is_equal(100)
	var cs4: Variant = _as("nitpick4")
	cs4.save_system.unlock_achievement("first_lamp")
	assert_bool(cs4.notify_boss_slain("vine_colossus", 1)).is_false()   # 未知武器 id（占位 ""）不误解锁


func test_composite_flawless_elite_no_hurt_in_room_window() -> void:
	var cs: Variant = _as("flawless")
	assert_bool(cs.notify_enemy_killed(ELITE_ID)).is_true()   # 窗口零受击
	assert_int(cs.save_system.gems()).is_equal(50)
	var cs2: Variant = _as("flawless2")
	cs2.notify_enemy_killed(NORMAL_ID)                        # 非精英不解锁
	assert_bool(cs2.is_unlocked("flawless_elite")).is_false()
	var cs3: Variant = _as("flawless3")
	cs3.notify_player_hit(4, false)                           # 本房受击 → 破
	assert_bool(cs3.notify_enemy_killed(ELITE_ID)).is_false()
	cs3.notify_room_cleared()                                 # 房间窗口重置（下一房）
	assert_bool(cs3.notify_enemy_killed(ELITE_ID)).is_true()


# ---- 蓝晶入账 / 信号 / toast ----

func test_unlock_emits_signal_toast_and_gems_once() -> void:
	# 隔离口径：拾红心破拒绝治疗、20min 边界破速通者——victory 只解守夜人
	var cs: Variant = _as("emit")
	cs.notify_heart_pickup()
	RunState.run_time_frames = 72000
	var fired: Array = []
	cs.achievement_unlocked.connect(func(id: String) -> void: fired.append(id))
	cs.notify_boss_slain("vine_colossus", 1)
	cs.notify_victory()   # 守夜人（300）
	cs.notify_boss_slain("vine_colossus", 1)   # 重复事件幂等
	assert_array(fired).contains_exactly(["first_lamp", "night_watcher"])
	assert_int(cs.save_system.gems()).is_equal(400)   # 100 + 300，无重复入账
	var spy: SpyToast = cs.toast
	assert_array(spy.shown).contains("成就解锁：初次点灯 +100 蓝晶")
	assert_array(spy.shown).contains("成就解锁：守夜人 +300 蓝晶")
	assert_int(spy.shown.size()).is_equal(2)


func test_state_threshold_path_also_emits_and_rewards() -> void:
	var cs: Variant = _as("stateemit")
	cs.save_system.record_talent_purchase("t1")
	for i in range(11):
		cs.save_system.record_talent_purchase("t%d" % (i + 2))
	var fired: Array = []
	cs.achievement_unlocked.connect(func(id: String) -> void: fired.append(id))
	assert_array(cs.recheck()).contains("gifted")
	assert_array(fired).contains("gifted")
	assert_int(cs.save_system.gems()).is_equal(150)
	var spy: SpyToast = cs.toast
	assert_array(spy.shown).contains("成就解锁：天赋异禀 +150 蓝晶")


# ---- 跨局持久化（temp path 模式） ----

func test_unlock_persists_across_save_reload() -> void:
	var path := _tmp_path("roundtrip")
	var s1: Variant = auto_free(load("res://autoload/save_system.gd").new())
	s1.save_path = path
	s1.load_save()
	assert_bool(s1.unlock_achievement("first_lamp")).is_true()
	s1.add_gems(100)
	var s2: Variant = auto_free(load("res://autoload/save_system.gd").new())
	s2.save_path = path
	s2.load_save()
	assert_array(s2.unlocked_achievements()).contains("first_lamp")
	assert_int(s2.gems()).is_equal(100)
	assert_bool(s2.unlock_achievement("first_lamp")).is_false()   # 幂等：已解锁拒绝
	assert_int(s2.gems()).is_equal(100)                           # 不重复入账


func test_save_v2_migration_keeps_v1_achievements_key() -> void:
	# v1 档（无 achievements 键/旧格式）载入 → v2 迁移归一 id→true，版本戳=2
	var path := _tmp_path("migrate")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "gems": 7, "achievements": {"delver": true}}))
	f = null
	var s: Variant = auto_free(load("res://autoload/save_system.gd").new())
	s.save_path = path
	s.load_save()
	assert_int(int(s.data["version"])).is_equal(2)
	assert_array(s.unlocked_achievements()).contains("delver")
	assert_int(s.gems()).is_equal(7)


func test_reset_session_clears_session_counters_not_unlocks() -> void:
	var cs: Variant = _as("reset")
	cs.notify_resonance()
	cs.notify_enemy_damaged(4, true)
	cs.notify_player_hit(4, true)
	cs.notify_heart_pickup()
	cs.notify_boss_slain("vine_colossus", 1)   # first_lamp 解锁（持久）
	cs.reset_session()
	assert_int(int(cs.session["resonances"])).is_equal(0)
	assert_int(int(cs.session["shots"])).is_equal(0)
	assert_int(int(cs.session["crits"])).is_equal(0)
	assert_int(int(cs.session["deaths"])).is_equal(0)
	assert_int(int(cs.session["heart_pickups"])).is_equal(0)
	assert_bool(cs.is_unlocked("first_lamp")).is_true()   # 解锁不随会话复位
	assert_int(cs.save_system.gems()).is_equal(100)


func test_trial_achievements_not_unlockable_in_m2() -> void:
	# 试炼 2 条 M3：判定器不接线，强行判定也拒绝入档
	var cs: Variant = _as("trial")
	assert_bool(cs.is_active("trier")).is_false()
	assert_bool(cs.is_active("trial_master")).is_false()
	assert_bool(cs._unlock("trier")).is_false()
	assert_bool(cs._unlock("trial_master")).is_false()
	assert_array(cs.save_system.unlocked_achievements()).is_empty()
	assert_int(cs.save_system.gems()).is_equal(0)


func test_notify_recheck_does_not_unlock_unknown_or_locked_defs() -> void:
	var cs: Variant = _as("unknown")
	assert_bool(cs._unlock("no_such_achievement")).is_false()
	assert_array(cs.recheck()).is_empty()   # 全新档：无 state_threshold 达成
	assert_int(cs.save_system.gems()).is_equal(0)


# ---- _ready 订阅冒烟（入树实例 → EventBus 真信号路径） ----

func test_ready_subscribes_event_bus_resonance() -> void:
	var cs: Variant = auto_free(load(AS_PATH).new(_fresh_save("wire")))
	cs.toast = _spy_toast()
	add_child(cs)   # _ready 连 EventBus
	EventBus.resonance_triggered.emit(0, Vector2.ZERO, {})
	assert_int(int(cs.session["resonances"])).is_equal(1)


# ---- toast 队列（右下角，3s 淡出，最多同屏 3 条） ----

func _toast() -> Variant:
	var t: Variant = auto_free(load(TOAST_PATH).new())
	t.lifetime = 60.0   # 冻结过期，专测队列策略
	add_child(t)
	return t


func test_toast_queue_caps_at_3_evicts_oldest() -> void:
	var t: Variant = _toast()
	for i in range(5):
		t.show_toast("测试%d" % i)
	var texts: Array = t.visible_texts()
	assert_int(texts.size()).is_equal(3)
	assert_array(texts).contains_exactly(["测试2", "测试3", "测试4"])   # 最老两条被挤掉


func test_toast_expire_after_lifetime() -> void:
	var t: Variant = auto_free(load(TOAST_PATH).new())
	t.lifetime = 0.1
	add_child(t)
	t.show_toast("稍候淡出")
	assert_int(t.visible_texts().size()).is_equal(1)
	await get_tree().create_timer(0.6).timeout
	assert_int(t.visible_texts().size()).is_equal(0)   # 3s 口径的缩短注入版：过期即淡出清位


func test_toast_scene_instantiates_script_layer() -> void:
	# 计划卡交付面 ui/toast.gd(+tscn)：场景实例 = 挂 toast.gd 的 CanvasLayer，
	# 与 autoload 生产路径（TOAST_SCENE）同一资源
	var packed: Variant = load("res://ui/toast.tscn")
	assert_object(packed).is_not_null()
	assert_bool(packed is PackedScene).is_true()
	var t: Variant = auto_free(packed.instantiate())
	assert_bool(t is CanvasLayer).is_true()
	t.lifetime = 60.0
	add_child(t)
	t.show_toast("场景装配路径")
	assert_array(t.visible_texts()).contains("场景装配路径")
