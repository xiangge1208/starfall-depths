class_name TestM5BossWeapons
extends GdUnitTestSuite
## M5-B 六 Boss 专属橙武器契约测试（115→121）。
## ① 六行 schema/加载合法（legend + locked + boss_exclusive + source_tag）
## ② DPS 橙带内（纸面 damage×rate×projectiles ∈ 22~27，GDD §8.1 上下文）
## ③ boss 行 boss_drop ↔ 武器行一一映射（双向存在）
## ④ boss_exclusive 不进 ShopLogic 池（_bucket 直测 + 生产池直测 + grant_to_pool 兜底）
## ⑤ SaveSystem.has_boss_first_kill 只读语义（不标记/不落盘）
## ⑥ FloorScene 掉落分支：首杀必掉（零随机消费）/ 复杀 _loot_rng 掷签（注入确定性对拍）
## ⑦ 素材 tripwire：六武器图标 + 手持在盘（weapon_icon_path 约定寻址）
## ⑧ 图鉴来源标注：codex 已解锁格 cond_text = source_tag（缺省回落类别，既有通道复用）

const BOSS_WIDS: Array[String] = ["tengmanjiaobian", "fenghoulengci", "jinglenguanchuan",
	"shuangzhurensi", "ronghepenliu", "shuangziyunxing"]
const BOSS_IDS: Array[String] = ["vine_colossus", "gem_queen", "prism_golem",
	"frost_widow", "magma_tyrant", "starfall_prophet"]
const DPS_LO := 22.0   # m5-b 卡：橙档纸面 DPS 带（GDD §8.1 橙 ×2.7 白板）
const DPS_HI := 27.0
const SEED := 20260928

var _save_paths: Array[String] = []
var _pool_snapshot: Array = []
var _fs: FloorScene = null


func before_test() -> void:
	# 抹平真实档（user://save.json）已解锁武器经 autoload 启动回池造成的基线漂移
	# （test_codex_system 同款手法）：统一从「55 把全锁」基线出发，after_test 按快照还原。
	_pool_snapshot = GameDB.weapons.keys()
	for id: String in GameDB.weapons.keys():
		if bool((GameDB.weapons[id] as Dictionary).get("locked", false)):
			GameDB.weapons.erase(id)


func after_test() -> void:
	for id: String in GameDB.weapons.keys():
		if not _pool_snapshot.has(id):
			GameDB.weapons.erase(id)          # 还原被 grant_to_pool 扩池的全局池
	if _fs != null and is_instance_valid(_fs):
		_fs.free()                            # EventBus 桥接断连（test_floor_scene 习语）
		_fs = null
	for path in _save_paths:
		DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(path + ".tmp")
	_save_paths.clear()


func _tmp_save(tag: String) -> Variant:
	var path := "user://test_m5b_%s_%d.json" % [tag, absi(randi())]
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".tmp")
	_save_paths.append(path)
	var s: Variant = auto_free(load("res://autoload/save_system.gd").new())
	s.save_path = path
	s.load_save()
	return s


# ---------------------------------------------------------------- ① 行 schema/加载

func test_six_boss_weapon_rows_load_legal() -> void:
	for wid in BOSS_WIDS:
		var row: Dictionary = GameDB.weapons_all.get(wid, {})
		assert_bool(row.is_empty()).override_failure_message(
			"weapons_all 缺行 %s（GameDB fail-closed 应已挡坏行）" % wid).is_false()
		if row.is_empty():
			continue
		assert_str(String(row["id"])).is_equal(wid)
		assert_str(String(row["rarity"])).is_equal("legend")
		assert_bool(bool(row["locked"])).is_true()           # 不进 GameDB.weapons 池
		assert_bool(bool(row["boss_exclusive"])).is_true()   # _bucket 双保险标记
		assert_str(String(row["source_tag"])).is_equal("Boss 掉落")
		assert_str(String(row["name"])).is_not_empty()
		assert_int(int(row["damage"])).is_greater(0)
		assert_float(float(row["rate"])).is_greater(0.0)
		assert_bool(int(row["damage"]) > 0 and float(row["rate"]) > 0.0).is_true()
		assert_array(["none", "fire", "ice", "poison", "shock"]).contains(String(row["element"]))


func test_six_rows_all_legend_counts_115_to_121() -> void:
	assert_int(GameDB.weapons_all.size()).is_equal(121)   # 115 + 6（校准测试同口径钉值）
	assert_int(GameDB.drop_pool().size()).is_equal(66)    # 121 − 55 locked（池零扩容）


func test_dps_paper_band_22_to_27() -> void:
	for wid in BOSS_WIDS:
		var row: Dictionary = GameDB.weapons_all[wid]
		var dps := float(row["damage"]) * float(row["rate"]) * float(row["projectiles"])
		assert_bool(dps >= DPS_LO and dps <= DPS_HI) \
			.override_failure_message(
				"%s 纸面 DPS %f 越橙带 [%f, %f]" % [wid, dps, DPS_LO, DPS_HI]).is_true()


# ---------------------------------------------------------------- ③ boss_drop 双向映射

func test_boss_rows_drop_pointers_bidirectional() -> void:
	for bid in BOSS_IDS:
		var row: Dictionary = GameDB.get_enemy(bid)
		assert_bool(row.is_empty()).override_failure_message("enemies 缺 Boss 行 " + bid).is_false()
		var wid := String(row.get("boss_drop", ""))
		assert_array(BOSS_WIDS).override_failure_message(
			"%s.boss_drop='%s' 不在六武清单" % [bid, wid]).contains(wid)
		assert_bool(GameDB.get_weapon(wid).is_empty()).override_failure_message(
			"boss_drop 指向不存在武器行 " + wid).is_false()
	# 每把武器恰被一个 Boss 行引用（无重复掉落源/无孤儿行）
	for wid in BOSS_WIDS:
		var refs := 0
		for bid: String in GameDB.enemies:
			if String((GameDB.enemies[bid] as Dictionary).get("boss_drop", "")) == wid:
				refs += 1
		assert_int(refs).override_failure_message("武器 %s 被 %d 个 Boss 引用" % [wid, refs]) \
			.is_equal(1)


# ---------------------------------------------------------------- ④ 池过滤

func test_bucket_direct_skips_boss_exclusive() -> void:
	# 直测：合成表内 boss_exclusive 行恒被跳过（exclude 之外仍跳）
	var table := {
		"fake_boss": {"rarity": "legend", "boss_exclusive": true},
		"fake_normal": {"rarity": "legend"},
	}
	var out: Array[String] = ShopLogic._bucket(table, "legend", [])
	assert_array(out).contains_exactly(["fake_normal"])
	var out2: Array[String] = ShopLogic._bucket(table, "legend", ["fake_normal"])
	assert_array(out2).is_empty()   # 只剩 boss 行时桶枯（回退链消费方自行处理）


func test_production_pool_never_offers_boss_weapons() -> void:
	# GameDB.drop_pool（locked 全滤）+ ShopLogic 生产池大量 roll 双路径零泄露
	var pool := GameDB.drop_pool()
	for wid in BOSS_WIDS:
		assert_array(pool).override_failure_message("池泄露专属橙 " + wid).not_contains(wid)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for i in 300:
		var exclude: Array[String] = []
		var wid := ShopLogic.roll_weapon_id(rng, 3, exclude, "combat")
		assert_array(BOSS_WIDS).override_failure_message(
			"roll 第 %d 次泄露专属橙 %s" % [i, wid]).not_contains(wid)
	var black := ShopLogic.roll_black_weapon_id(rng, [])
	assert_array(BOSS_WIDS).override_failure_message("黑商泄露专属橙 " + black).not_contains(black)


func test_bucket_double_guard_even_after_grant_to_pool() -> void:
	# 兜底路径：行被 grant_to_pool（图鉴解锁回池）后 _bucket 仍跳过 boss_exclusive
	GameDB.grant_to_pool("tengmanjiaobian")
	assert_bool(GameDB.weapons.has("tengmanjiaobian")).is_true()   # 前置：行确已回池
	var pool: Array[String] = ShopLogic._bucket(GameDB.weapons, "legend", [])
	assert_array(pool).override_failure_message(
		"grant 回池后 _bucket 仍须跳过 boss_exclusive 行").not_contains("tengmanjiaobian")


# ---------------------------------------------------------------- ⑤ 首杀只读查询

func test_has_boss_first_kill_readonly_semantics() -> void:
	var s: Variant = _tmp_save("readonly")
	assert_bool(s.has_boss_first_kill("vine_colossus")).is_false()   # 空档 → 未标记
	assert_bool(s.has_boss_first_kill("")).is_false()                # 脏键防御
	assert_bool(s.has_boss_first_kill("no_such_boss")).is_false()
	assert_bool(s.record_boss_first_kill("vine_colossus")).is_true()   # 标记入库
	var snapshot := FileAccess.get_file_as_string(s.save_path)
	assert_bool(s.has_boss_first_kill("vine_colossus")).is_true()
	assert_str(FileAccess.get_file_as_string(s.save_path)).is_equal(snapshot) \
		.override_failure_message("has_boss_first_kill 不得写盘（只读语义）")
	# 只读查询不得补标记：读后再 record 必须仍是「新记录」true（幂等口径未被破坏）
	assert_bool(s.record_boss_first_kill("vine_colossus")).is_false()   # 已标记 → false
	var s2: Variant = _tmp_save("readonly2")
	assert_bool(s2.has_boss_first_kill("magma_tyrant")).is_false()
	assert_bool(s2.record_boss_first_kill("magma_tyrant")).is_true()   # 读过（false）未污染


# ---------------------------------------------------------------- ⑥ 掉落分支

func _drop_scene() -> FloorScene:
	var rooms := {
		0: {"node": {"id": 0, "type": "start", "grid": Vector2i(0, 0), "depth": 0,
			"next": [1]}, "template_id": "start_a1", "world_pos": Vector2.ZERO},
		1: {"node": {"id": 1, "type": "combat", "grid": Vector2i(1, 0), "depth": 0,
			"next": []}, "template_id": "combat_a1_01", "world_pos": Vector2(416, 0)},
	}
	var build := {"rooms": rooms, "corridors": [{"a": 0, "b": 1, "dir": "E"}],
		"start_room_id": 0, "boss_room_id": -1}
	var player: Player = (load("res://core/player/player.tscn") as PackedScene).instantiate() as Player
	_fs = FloorScene.new()
	add_child(_fs)
	_fs.setup(build, player)
	return _fs


func _loot_stations(room: FloorScene.FloorRoom, wid := "") -> Array:
	var out: Array = []
	for c in room.get_children():
		if c is FloorScene.FixtureInteractable and c.has_meta("weapon_id") \
				and (wid.is_empty() or String(c.get_meta("weapon_id")) == wid):
			out.append(c)
	return out


func test_boss_drop_first_kill_always_drops_without_consuming_rng() -> void:
	var fs := _drop_scene()
	var room: FloorScene.FloorRoom = fs.room_node(1)
	var row: Dictionary = GameDB.get_enemy("vine_colossus").duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	fs._loot_rng = rng
	var state := rng.state
	fs._spawn_drops_now(room, row, Vector2.ZERO, true)   # 首杀：必掉
	assert_int(_loot_stations(room, "tengmanjiaobian").size()).is_equal(1)
	assert_int(rng.state).override_failure_message(
		"首杀必掉路径不得消费 _loot_rng（短路 or 保随机序列可复现）").is_equal(state)


func test_boss_drop_repeat_kill_rolls_injected_loot_rng() -> void:
	var fs := _drop_scene()
	var room: FloorScene.FloorRoom = fs.room_node(1)
	var row: Dictionary = GameDB.get_enemy("vine_colossus").duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	fs._loot_rng = rng
	for i in 40:
		fs._spawn_drops_now(room, row, Vector2.ZERO, false)   # 复杀：掷签
	var dropped := _loot_stations(room, "tengmanjiaobian").size()
	# 对拍：同 seed 参考 rng 逐次 randf() < 0.25 的次数必须严格一致（注入确定性）
	var ref := RandomNumberGenerator.new()
	ref.seed = SEED
	var expected := 0
	for i in 40:
		if ref.randf() < FloorScene.BOSS_DROP_REPEAT_CHANCE:
			expected += 1
	assert_int(dropped).override_failure_message(
		"复杀掉落 %d ≠ 同 seed 参考掷签 %d（_loot_rng 消费契约破坏）" % [dropped, expected]) \
		.is_equal(expected)
	# 掷签不为 0（seed 落在两分支之间的健全性自检，防全拒路径假绿）
	assert_bool(dropped > 0 and dropped < 40).is_true()


func test_boss_drop_sync_fallback_via_spawn_guest_drops() -> void:
	# _spawn_guest_drops 全链（defer 拒绝 → 同步照旧）：首杀参数穿透到 boss_drop 分支
	var fs := _drop_scene()
	var room: FloorScene.FloorRoom = fs.room_node(1)
	var row: Dictionary = GameDB.get_enemy("magma_tyrant").duplicate()   # boss_script 行
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	fs._loot_rng = rng
	fs._spawn_guest_drops(room, row, Vector2.ZERO, true)
	assert_int(_loot_stations(room, "ronghepenliu").size()).is_equal(1)


func test_no_drop_when_row_lacks_drops_and_boss_drop() -> void:
	var fs := _drop_scene()
	var room: FloorScene.FloorRoom = fs.room_node(1)
	var row := {"id": "cave_bat", "name": "穴蝠"}   # 两键皆空 → 恒静默
	fs._spawn_drops_now(room, row, Vector2.ZERO, true)
	assert_int(_loot_stations(room).size()).is_equal(0)


# ---------------------------------------------------------------- ⑦ 素材 tripwire

func test_boss_weapon_art_on_disk() -> void:
	for wid in BOSS_WIDS:
		assert_bool(FileAccess.file_exists(ArtLookup.weapon_icon_path(wid))) \
			.override_failure_message("缺图鉴图标 " + ArtLookup.weapon_icon_path(wid)).is_true()
		assert_bool(FileAccess.file_exists("res://art/generated/weapons/%s.png" % wid)) \
			.override_failure_message("缺手持精灵 " + wid).is_true()


# ---------------------------------------------------------------- ⑧ 图鉴来源标注

## 全解锁替身（鸭子类型：ui 侧只调 codex_system.is_unlocked；属性钉 Node 类型 →
## 替身必须 extends Node）——绕开 _ready 的 /root/CodexSystem 探测（真实 autoload
## 挂真档 → Boss 武器恒未解锁渲染）。
class AllUnlockedStub extends Node:
	func is_unlocked(_weapon_id: String) -> bool:
		return true


func test_codex_unlocked_cell_shows_source_tag() -> void:
	# 既有通道最小接线：已解锁格 cond_text 显示 source_tag；无标注行回落类别（零漂移）
	var ui: Control = auto_free((load("res://ui/codex.tscn") as PackedScene).instantiate())
	var stub: Node = auto_free(AllUnlockedStub.new())
	ui.codex_system = stub   # 注入须在 add_child 前（_ready 探测短路）
	add_child(ui)
	assert_str(String(ui.cell_info("tengmanjiaobian")["cond_text"])).is_equal("Boss 掉落")
	assert_str(String(ui.cell_info("shuangziyunxing")["cond_text"])).is_equal("Boss 掉落")
	assert_str(String(ui.cell_info("duangong")["cond_text"])).is_equal("bow")   # 未标注行不变


func test_codex_unlock_on_first_pickup_seen() -> void:
	# 无任务 Boss 专属橙：拾取见集（codex_seen，equip 收口写入）即图鉴解锁；
	# 未拾取恒「???」。非标注行（yahuozhe）语义不变（见集不触发解锁）。
	var s: Variant = _tmp_save("seenunlock")
	var cs: Variant = auto_free(load("res://core/meta/codex_system.gd").new(s))
	assert_bool(cs.is_unlocked("tengmanjiaobian")).is_false()
	s.record_codex_seen("tengmanjiaobian")
	assert_bool(cs.is_unlocked("tengmanjiaobian")).is_true()
	assert_bool(cs.is_unlocked("yahuozhe")).is_false()
	# 解锁态仅图鉴展示：不入掉落池（grant_to_pool 只由任务行 check_unlocks 调用）
	assert_bool(GameDB.drop_pool().has("tengmanjiaobian")).is_false()
