class_name TestDestructibleProps
extends GdUnitTestSuite
## M4-C5：可破坏物机制（pillar/crate/bush 静态阻挡 → 可破坏）+ demolition 成就接线。
## 1) DestructibleProp 纯机制（无头）：固定伤害制直扣（ctx.amount 已是 DamageCalc 终值，
##    props 无二次随机乘区）、hp 归零破坏幂等、destroyed 信号恰一次、战斗体注销。
## 2) FloorScene 接线：模板 props → 可破坏体生成（独立小上限，不进弹幕池）+ 进战斗流
##    （HivePillar 同缝 register_body）；玩家弹经 combat 判定流上伤；破坏结算 =
##    阻挡消失（通行性恢复）+ 掉落按行 + Telemetry["prop_destroyed"] +
##    AchievementSystem.notify_prop_destroyed（demolition 全链路）。
## 3) schema fail-closed：pillar/crate/bush hp 必填正整数、drops 白名单/上限。
## 4) 蜂巢柱特例（gem_queen HivePillar）独立实现不回归——既有 test_boss_floor_routing 守护。
## 密闭口径（test_achievement_wiring 同源）：全局 AchievementSystem 换临时隔离档，
## 拆迁办解锁不写真实存档。

const PLAYER_SCENE := preload("res://core/player/player.tscn")
const SAVE_SCRIPT := "res://autoload/save_system.gd"
const SPAN_PX := 416.0
const TPL := "combat_a1_98"        # 测试注入模板（after_test 摘除）

# 门像素位：N(184,8) S(184,216) E(344,120) W(8,120)；刷点 (88,72)/(264,152) 距门均 ≥64px
const C5_ROW := {
	"id": TPL, "size": [22, 14], "doors": ["N", "S", "E", "W"],
	"spawn_points": [[5, 4], [16, 9]],
	"props": [
		{"kind": "pillar", "grid": [4, 7], "hp": 20},
		{"kind": "crate", "grid": [17, 3], "hp": 8, "drops": ["coin"]},
		{"kind": "bush", "grid": [10, 11], "hp": 4},
		{"kind": "crystal_pillar", "grid": [2, 2], "hp": 20},
	],
	"hazards": [],
}


func _room(id: int, type: String, grid: Vector2i, next: Array, tid: String) -> Dictionary:
	return {
		"node": {"id": id, "type": type, "grid": grid, "depth": 0, "next": next},
		"template_id": tid, "world_pos": Vector2(grid) * SPAN_PX,
	}


func _typed_chain(tid: String) -> Dictionary:
	var rooms := {0: _room(0, "start", Vector2i(0, 0), [1], "start_a1"),
		1: _room(1, "combat", Vector2i(1, 0), [], tid)}
	return {"rooms": rooms, "corridors": [{"a": 0, "b": 1, "dir": "E"}],
		"start_room_id": 0, "boss_room_id": -1}


var _fs: FloorScene = null
var _iso_save: Node = null
var _iso_path := "user://test_c5_iso_save.json"


func before_test() -> void:
	GameDB.rooms[TPL] = C5_ROW.duplicate(true)
	# 密闭：全局 AchievementSystem 换临时隔离档（生产同一实例；解锁不落真实档）
	_iso_save = auto_free(load(SAVE_SCRIPT).new())
	_iso_save.save_path = _iso_path
	_iso_save.load_save()
	AchievementSystem.save_system = _iso_save
	AchievementSystem.reset_session()


func after_test() -> void:
	if _fs != null and is_instance_valid(_fs):
		_fs.free()
		_fs = null
	GameDB.rooms.erase(TPL)
	AchievementSystem.save_system = get_node_or_null("/root/SaveSystem")
	AchievementSystem.reset_session()
	DirAccess.remove_absolute(_iso_path)
	DirAccess.remove_absolute(_iso_path + ".tmp")


func _make_scene() -> FloorScene:
	var player: Player = (PLAYER_SCENE as PackedScene).instantiate() as Player
	_fs = FloorScene.new()
	add_child(_fs)
	_fs.setup(_typed_chain(TPL), player)
	return _fs


func _combat_room() -> FloorScene.FloorRoom:
	return _fs.room_node(1)


func _prop_by_kind(room: FloorScene.FloorRoom, kind: String) -> DestructibleProp:
	for p: DestructibleProp in room.destructibles:
		if p.kind == kind:
			return p
	return null


func _await_until(check: Callable, max_frames: int = 60) -> void:
	for _i in max_frames:
		if check.call():
			return
		await get_tree().physics_frame


# ---------------------------------------------------------------- 纯机制（无头）

func test_fixed_damage_no_random_component() -> void:
	# 固定伤害制：ctx.amount 直扣（伤害随机性已在 DamageCalc/暴击缝收口，props 无二次乘区）
	var prop: DestructibleProp = auto_free(DestructibleProp.new())
	add_child(prop)
	prop.setup("pillar", 20, [] as Array[String], true,
		Rect2(Vector2(-8, -8), Vector2(16, 16)), null)
	prop.take_hit({"amount": 7})
	assert_int(prop.hp).is_equal(13)
	prop.take_hit({"amount": 7})
	assert_int(prop.hp).is_equal(6)
	prop.take_hit({"amount": 6})
	assert_int(prop.hp).is_equal(0)


func test_destroy_signal_once_and_post_destroy_hits_ignored() -> void:
	var prop: DestructibleProp = auto_free(DestructibleProp.new())
	add_child(prop)
	prop.setup("crate", 8, [] as Array[String], true,
		Rect2(Vector2(-8, -8), Vector2(16, 16)), null)
	var count := [0]
	prop.destroyed.connect(func(_p: DestructibleProp) -> void: count[0] += 1)
	prop.take_hit({"amount": 99})
	assert_int(prop.hp).is_equal(0)
	assert_int(count[0]).is_equal(1)
	prop.take_hit({"amount": 99})          # 已破坏：再击无副作用
	assert_int(count[0]).is_equal(1)
	assert_int(prop.hp).is_equal(0)


func test_destroy_unregisters_combat_body() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var rng := RngSvc.stream(0, "combat")
	rng.seed = 11
	var cs := CombatSystem.new(root, rng)
	root.add_child(cs)
	var prop: DestructibleProp = auto_free(DestructibleProp.new())
	root.add_child(prop)
	prop.position = Vector2(200, 100)
	prop.setup("pillar", 20, [] as Array[String], true,
		Rect2(Vector2(-8, -8), Vector2(16, 16)), null)
	prop.attach_combat(cs)
	var found: Array = cs.bodies_in_radius(prop.position, 32.0, Projectile.Faction.ENEMY)
	assert_bool(found.has(prop)).is_true()
	prop.take_hit({"amount": 99})
	var after: Array = cs.bodies_in_radius(prop.position, 32.0, Projectile.Faction.ENEMY)
	assert_bool(after.has(prop)).is_false()     # 退场即注销（哈希不泄漏，HivePillar 同契约）


func test_per_room_cap_and_independent_of_projectile_pool() -> void:
	# 独立池小上限：bounded 截断 + 可破坏物不是弹（弹池计数恒 0）
	var rows: Array = []
	for i in 40:
		rows.append({"kind": "crate", "grid": [1 + (i % 20), 1 + int(i / 20.0)], "hp": 8})
	assert_int(DestructibleProp.bounded(rows, DestructibleProp.PER_ROOM_CAP).size()) \
		.is_equal(DestructibleProp.PER_ROOM_CAP)
	assert_int(DestructibleProp.bounded(rows, 4).size()).is_equal(4)
	assert_int(DestructibleProp.bounded(rows, DestructibleProp.PER_ROOM_CAP).size()) \
		.is_less(rows.size())


# ---------------------------------------------------------------- FloorScene 接线

func test_floor_builds_destructibles_and_wires_combat() -> void:
	var fs := _make_scene()
	var room := _combat_room()
	assert_int(room.destructibles.size()).is_equal(3)   # pillar/crate/bush（crystal_pillar 除外）
	for kind: String in ["pillar", "crate", "bush"]:
		var p := _prop_by_kind(room, kind)
		assert_object(p).is_not_null()
	var pillar := _prop_by_kind(room, "pillar")
	var near: Array = room.combat.bodies_in_radius(pillar.global_position, 24.0,
		Projectile.Faction.ENEMY)
	assert_bool(near.has(pillar)).is_true()             # 已进 combat 判定流
	assert_int(room.combat.active_count()).is_equal(0)  # 不进弹幕池（独立池）


func test_floor_props_hold_data_hp_and_drops() -> void:
	var fs := _make_scene()
	var room := _combat_room()
	assert_int(_prop_by_kind(room, "pillar").max_hp).is_equal(20)
	assert_int(_prop_by_kind(room, "crate").max_hp).is_equal(8)
	assert_int(_prop_by_kind(room, "bush").max_hp).is_equal(4)
	var crate := _prop_by_kind(room, "crate")
	assert_array(crate.drops).is_equal(["coin"])        # 掉落按行配置
	assert_array(_prop_by_kind(room, "pillar").drops).is_empty()
	# bush 不做物理阻挡（静态期既有语义），pillar/crate 阻挡
	assert_bool(_prop_by_kind(room, "bush").blocking).is_false()
	assert_bool(_prop_by_kind(room, "pillar").blocking).is_true()


func test_player_bullet_damages_prop_through_combat_flow() -> void:
	var fs := _make_scene()
	var room := _combat_room()
	var pillar := _prop_by_kind(room, "pillar")
	var start := pillar.global_position + Vector2(40, 0)
	room.combat.spawn_projectile({
		"pos": start, "vel": Vector2(-100, 0), "damage": 5,
		"faction": Projectile.Faction.PLAYER, "element": Elements.Id.NONE,
		"pierce": 0, "bounce": 0, "life_seconds": 2.0, "radius": 3.0,
	})
	await _await_until(func() -> bool: return pillar.hp < 20)
	# 固定伤害制：5（平伤）或 10（暴击），无其他散布
	assert_bool(pillar.hp == 15 or pillar.hp == 10).is_true()
	await _await_until(func() -> bool: return room.combat.active_count() == 0)
	assert_int(room.combat.active_count()).is_equal(0)  # 无穿透弹命中即耗（阻挡生效）


func test_destroy_removes_blocking_and_restores_passability() -> void:
	var fs := _make_scene()
	var room := _combat_room()
	var crate := _prop_by_kind(room, "crate")
	var center := crate.global_position
	var before := fs._room_solid_rects(room)
	var hit := false
	for r: Rect2 in before:
		if r.has_point(center):
			hit = true
	assert_bool(hit).is_true()                          # 静态期：实体阻挡
	crate.take_hit({"amount": 99})
	for _i in 3:
		await get_tree().physics_frame                  # queue_free 落帧
	assert_bool(is_instance_valid(crate)).is_false()
	var after := fs._room_solid_rects(room)
	for r: Rect2 in after:
		assert_bool(r.has_point(center)).is_false()     # 阻挡消失
	var spot := FloorScene.find_safe_placement(center, after, 6.0, fs._room_interior(room))
	assert_vector(spot).is_equal_approx(center, Vector2(0.01, 0.01))   # 通行性恢复


func test_crate_drop_spawns_coin_pickup_pillar_spawns_none() -> void:
	var fs := _make_scene()
	var room := _combat_room()
	var pickups := room.get_children().filter(func(c: Node) -> bool: return c is Pickup)
	assert_int(pickups.size()).is_equal(0)
	_prop_by_kind(room, "crate").take_hit({"amount": 99})
	pickups = room.get_children().filter(func(c: Node) -> bool: return c is Pickup)
	assert_int(pickups.size()).is_equal(1)
	assert_str((pickups[0] as Pickup).kind).is_equal("coin")
	_prop_by_kind(room, "pillar").take_hit({"amount": 99})   # 无掉落行
	pickups = room.get_children().filter(func(c: Node) -> bool: return c is Pickup)
	assert_int(pickups.size()).is_equal(1)


func test_prop_destroyed_telemetry_row() -> void:
	var fs := _make_scene()
	var room := _combat_room()
	Telemetry.flush()   # 先把前序用例的缓冲行落盘，取基线计数（telemetry.csv 跨运行持久）
	var before := _count_prop_rows(FileAccess.get_file_as_string("user://telemetry.csv"))
	_prop_by_kind(room, "bush").take_hit({"amount": 99})
	Telemetry.flush()
	var text := FileAccess.get_file_as_string("user://telemetry.csv")
	assert_bool(text.contains("prop_destroyed")).is_true()
	# 本用例破坏恰 1 个（增量断言：前序用例/历史运行的行不参与）
	assert_int(_count_prop_rows(text)).is_equal(before + 1)


## 统计 prop_destroyed 行数（事件名在列首，查既有清单不撞名——约束 12）。
func _count_prop_rows(text: String) -> int:
	var n := 0
	for line: String in text.split("\n"):
		if line.begins_with("prop_destroyed,"):
			n += 1
	return n


func test_destruction_notifies_achievement_and_unlocks_demolition() -> void:
	var fs := _make_scene()
	var room := _combat_room()
	assert_int(int(AchievementSystem.session.get("props", -1))).is_equal(0)
	_prop_by_kind(room, "pillar").take_hit({"amount": 99})
	assert_int(int(AchievementSystem.session.get("props", -1))).is_equal(1)   # 接线 1 行生效
	assert_bool(AchievementSystem.is_unlocked("demolition")).is_false()
	AchievementSystem.session["props"] = 29                   # 预置 29（引擎阈值 30 由引擎测试钉）
	_prop_by_kind(room, "crate").take_hit({"amount": 99})
	assert_bool(AchievementSystem.is_unlocked("demolition")).is_true()   # 24/24 全激活口径
	assert_int(_iso_save.gems()).is_equal(50)                 # 附录 G.1 蓝晶原值


# ---------------------------------------------------------------- schema fail-closed

func _valid_row(id: String) -> Dictionary:
	return {
		"id": id, "size": [22, 14], "doors": ["N", "S"],
		"spawn_points": [[5, 4], [16, 9]],
		"props": [{"kind": "pillar", "grid": [10, 7], "hp": 20}],
		"hazards": [],
	}


func test_schema_requires_positive_hp_on_destructible_kinds() -> void:
	var row := _valid_row("hp_missing")
	(row["props"][0] as Dictionary).erase("hp")
	assert_int(GameDB.validate_room_row(row).size()).is_greater(0)
	var zero := _valid_row("hp_zero")
	zero["props"][0]["hp"] = 0
	assert_int(GameDB.validate_room_row(zero).size()).is_greater(0)
	var str_hp := _valid_row("hp_str")
	str_hp["props"][0]["hp"] = "20"
	assert_int(GameDB.validate_room_row(str_hp).size()).is_greater(0)
	assert_array(GameDB.validate_room_row(_valid_row("hp_ok"))).is_empty()


func test_schema_validates_drops_whitelist_and_cap() -> void:
	var ok := _valid_row("drops_ok")
	ok["props"][0]["drops"] = ["coin"]
	assert_array(GameDB.validate_room_row(ok)).is_empty()
	var bad_kind := _valid_row("drops_bad")
	bad_kind["props"][0]["drops"] = ["gem"]              # gem 不入小额掉落白名单
	assert_int(GameDB.validate_room_row(bad_kind).size()).is_greater(0)
	var not_array := _valid_row("drops_type")
	not_array["props"][0]["drops"] = "coin"
	assert_int(GameDB.validate_room_row(not_array).size()).is_greater(0)
	var over_cap := _valid_row("drops_cap")
	over_cap["props"][0]["drops"] = ["coin", "coin", "coin", "coin", "coin"]
	assert_int(GameDB.validate_room_row(over_cap).size()).is_greater(0)


func test_data_all_destructible_props_carry_hp_and_crate_drops() -> void:
	# 全表数据契约：pillar 20/crate 8/bush 4（既有 EXPECTED_PROP_HP 同源）；
	# crate 行带 ["coin"] 小额掉落，pillar/bush/crystal_pillar 无掉落键
	for id: String in GameDB.rooms:
		for p: Dictionary in GameDB.rooms[id]["props"]:
			if p["kind"] in ["pillar", "crate", "bush"]:
				assert_int(p["hp"]).is_greater(0)
			if p["kind"] == "crate":
				assert_array(p["drops"]).is_equal(["coin"])
			else:
				assert_bool(p.has("drops")).is_false()
