class_name DungeonBuilder
## M1-T7 地牢装配：DungeonGraph 图 → 逐节点选模板 → 构建体 {"rooms", "corridors",
## "start_room_id", "boss_room_id"} + validate_build（门对齐/模板存在/world_pos/走廊完整性）。
##
## 模板指派规格（task-7-brief）：start→start_a<f>，boss→boss_a<f>；elite→当前使用次数
## 最低的 combat 模板（并列取洗牌序靠前者）；其余类型（combat/shop/treasure/event/
## miniboss）→combat 池按 rng 洗牌循环取用，同模板每层 ≤2 次。模板只提供几何/门，
## 店铺/宝箱等内部陈设由后续任务按房型铺设。
##
## 已证实的系统性数据错配（task-7 报告，1000 种子统计）：A1 模板为固定门集合
## （start_a1={S,E}、boss_a1={N,S}、combat 多为三门），而 DungeonGraph 主路径方向随机
## （起点四向等概率、boss 入向均匀），所需门集合与模板门集合无法恒吻合——按规格
## 「不静默重映射」，validate_build 如实报告 door mismatch，交由数据侧修订。
##
## 运行期解析注记：本脚本须同时在游戏/GdUnit（autoload 在场）与 SceneTree --script
## 无头工具（autoload 不注册，其标识符在编译期即不可解析——GDScript 命名全局仅在
## autoload 实例化时注册）两种上下文工作，故不写 RngSvc/GameDB/RoomTemplate 裸
## 标识符：优先从场景树根取 autoload，--script 模式回退 load() 手动实例化；
## combat 池逻辑与 RoomTemplate.combat_ids 完全一致（单测钉等价性）。

const ROOM_SPAN_TILES := 26   # 房间跨度 = 22 房格 + 4 走廊间隔
const TILE_PX := 16
const ROOM_SPAN_PX := ROOM_SPAN_TILES * TILE_PX   # 416
const SEED_SALT := 777        # 校验种子派生盐：seed_i = stable_hash(i, 777)
const MAX_TEMPLATE_USES := 2  # 同一 combat 模板每层最多使用次数
const DIR_VECS := {"N": Vector2i(0, -1), "S": Vector2i(0, 1), "E": Vector2i(1, 0), "W": Vector2i(-1, 0)}
const DOOR_OPP := {"N": "S", "S": "N", "E": "W", "W": "E"}

static var _fallback_rng_svc: Object = null
static var _fallback_game_db: Object = null


## 校验器种子派生：与 RngSvc.stable_hash(index, 777) 一致（--script 工具经此间接调用）。
static func seed_at(index: int, salt: int = SEED_SALT) -> int:
	return (load("res://autoload/rng_svc.gd") as GDScript).stable_hash(index, salt)


## combat 模板池：与 RoomTemplate.combat_ids(floor_idx) 同约定（combat_a<f>_NN，字典序）。
static func combat_pool(floor_idx: int) -> Array[String]:
	var out: Array[String] = []
	var prefix := "combat_a%d_" % floor_idx
	var rooms: Dictionary = _game_db().rooms
	for id: String in rooms:
		if id.begins_with(prefix):
			out.append(id)
	out.sort()
	return out


## 装配一张地牢：seed 经 RngSvc.setup_run + stream(floor_idx, "dungeon") 派生 rng，
## 禁全局 rand。rooms 键 = 图节点 id（int）。
static func build(seed: int, floor_idx: int = 1) -> Dictionary:
	var rng := _make_rng(seed, floor_idx)
	var graph := DungeonGraph.generate(rng, floor_idx)
	var nodes: Dictionary = graph["nodes"]
	var ids: Array[int] = []
	for id in nodes:
		ids.append(int(id))
	ids.sort()

	# combat 池洗牌一次（Fisher-Yates，续耗图生成后的同一 rng）；循环游标 + 计数去重
	var shuffled := _shuffled(combat_pool(floor_idx), rng)
	var cursor := {"pos": 0}
	var uses := {}
	var rooms := {}
	for id in ids:
		var node: Dictionary = nodes[id]
		var template_id := ""
		match String(node["type"]):
			"start":
				template_id = "start_a%d" % floor_idx
			"boss":
				template_id = "boss_a%d" % floor_idx
			"elite":
				template_id = _pick_lowest_use(shuffled, cursor, uses)
			_:
				template_id = _pick_cycle(shuffled, cursor, uses)
		rooms[id] = {
			"node": node,
			"template_id": template_id,
			"world_pos": Vector2(node["grid"] as Vector2i) * float(ROOM_SPAN_PX),
		}

	# 走廊：每条图边一条，dir = a→b 方向（N/S/E/W，Godot 屏幕系 y 向下为 S）
	var corridors: Array = []
	for id in ids:
		var node: Dictionary = nodes[id]
		var ga: Vector2i = node["grid"]
		for nx in node["next"]:
			var gb: Vector2i = (nodes[int(nx)] as Dictionary)["grid"]
			corridors.append({"a": int(id), "b": int(nx), "dir": _dir_of(gb - ga)})

	return {
		"rooms": rooms,
		"corridors": corridors,
		"start_room_id": int(graph["start_id"]),
		"boss_room_id": int(graph["boss_id"]),
	}


## 构建体校验：空数组 = 通过。覆盖：根键齐全/房间字段完整/模板存在于 GameDB.rooms/
## world_pos == grid×416/start·boss 房 id 与类型/走廊端点·朝向·边集完备/门对齐
## （dir="N" 的走廊要求 a 有 N 门且 b 有 S 门，其余方向镜像）。不静默修复任何错配。
static func validate_build(build: Dictionary) -> Array[String]:
	var errs: Array[String] = []
	for key: String in ["rooms", "corridors", "start_room_id", "boss_room_id"]:
		if not build.has(key):
			errs.append("missing root key: %s" % key)
	if not errs.is_empty():
		return errs
	var rooms: Dictionary = build["rooms"]
	var rooms_db: Dictionary = _game_db().rooms

	# 房间：字段完整 / 模板存在 / id 一致 / world_pos 一致
	for id in rooms:
		var room: Dictionary = rooms[id]
		if not (room.has("node") and room.has("template_id") and room.has("world_pos")):
			errs.append("room %s: missing fields" % str(id))
			continue
		var tid := String(room["template_id"])
		if tid.is_empty() or not rooms_db.has(tid):
			errs.append("room %s: template_id %s not in GameDB.rooms" % [str(id), tid])
		var node: Dictionary = room["node"]
		if not node.has("grid"):
			errs.append("room %s: node missing grid" % str(id))
			continue
		if node.has("id") and int(node["id"]) != int(id):
			errs.append("room %s: node id mismatch (%s)" % [str(id), str(node["id"])])
		var grid: Vector2i = node["grid"]
		var want: Vector2 = Vector2(grid) * float(ROOM_SPAN_PX)
		if Vector2(room["world_pos"]) != want:
			errs.append("room %s: world_pos %s != grid*%d (%s)" \
				% [str(id), str(room["world_pos"]), ROOM_SPAN_PX, str(want)])

	# start/boss 房 id 有效且类型正确
	var role_ids := {"start_room_id": "start", "boss_room_id": "boss"}
	for key: String in role_ids:
		var rid := int(build[key])
		if not rooms.has(rid):
			errs.append("%s %d not in rooms" % [key, rid])
		elif String((rooms[rid] as Dictionary).get("node", {}).get("type", "")) != String(role_ids[key]):
			errs.append("room %d is not a %s room" % [rid, String(role_ids[key])])

	# 走廊：端点存在 / dir 合法且与网格位移一致 / 恰好覆盖全部图边 / 门对齐
	var expected_edges := {}
	var edge_total := 0
	for id in rooms:
		var nexts: Array = (rooms[id] as Dictionary).get("node", {}).get("next", [])
		edge_total += nexts.size()
		for nx in nexts:
			expected_edges["%d->%d" % [int(id), int(nx)]] = true
	var corridors: Array = build["corridors"]
	if corridors.size() != edge_total:
		errs.append("corridors: size %d != graph edge count %d" % [corridors.size(), edge_total])
	for c in corridors:
		var corridor: Dictionary = c
		if not (corridor.has("a") and corridor.has("b") and corridor.has("dir")):
			errs.append("corridor: missing fields")
			continue
		var a := int(corridor["a"])
		var b := int(corridor["b"])
		var dir := String(corridor["dir"])
		if not rooms.has(a) or not rooms.has(b):
			errs.append("corridor %d->%d: dangling endpoint" % [a, b])
			continue
		if not DIR_VECS.has(dir):
			errs.append("corridor %d->%d: bad dir %s" % [a, b, dir])
			continue
		var ga: Vector2i = (rooms[a] as Dictionary)["node"]["grid"]
		var gb: Vector2i = (rooms[b] as Dictionary)["node"]["grid"]
		if gb - ga != DIR_VECS[dir]:
			errs.append("corridor %d->%d: dir %s != grid delta %s" % [a, b, dir, str(gb - ga)])
		var edge_key := "%d->%d" % [a, b]
		if not expected_edges.has(edge_key):
			errs.append("corridor %s: not a graph edge" % edge_key)
		else:
			expected_edges.erase(edge_key)  # 剩余者即缺失边
		# 门对齐：a 需 dir 门，b 需对侧门
		if not _doors_of(rooms_db, (rooms[a] as Dictionary)["template_id"]).has(dir):
			errs.append("door mismatch: room %d(%s) lacks %s for corridor %d->%d" \
				% [a, str((rooms[a] as Dictionary)["template_id"]), dir, a, b])
		var opp := String(DOOR_OPP.get(dir, ""))
		if not _doors_of(rooms_db, (rooms[b] as Dictionary)["template_id"]).has(opp):
			errs.append("door mismatch: room %d(%s) lacks %s for corridor %d->%d" \
				% [b, str((rooms[b] as Dictionary)["template_id"]), opp, a, b])
	for edge_key in expected_edges:
		errs.append("corridors: missing graph edge %s" % edge_key)
	return errs


# ---------------------------------------------------------------- 内部：模板选取

## combat/shop/treasure/event/miniboss：洗牌序循环取用，跳过已达上限者。
static func _pick_cycle(shuffled: Array[String], cursor: Dictionary, uses: Dictionary) -> String:
	var n := shuffled.size()
	for _i in n:
		var cand := shuffled[int(cursor["pos"]) % n]
		cursor["pos"] = int(cursor["pos"]) + 1
		if int(uses.get(cand, 0)) < MAX_TEMPLATE_USES:
			uses[cand] = int(uses.get(cand, 0)) + 1
			return cand
	return ""


## elite：当前使用次数最低的 combat 模板（<上限；并列取洗牌序靠前者）。
static func _pick_lowest_use(shuffled: Array[String], cursor: Dictionary, uses: Dictionary) -> String:
	var best := ""
	var best_count := MAX_TEMPLATE_USES
	for cand in shuffled:
		var count := int(uses.get(cand, 0))
		if count < best_count:
			best = cand
			best_count = count
	if not best.is_empty():
		uses[best] = int(uses.get(best, 0)) + 1
	return best


static func _shuffled(pool: Array[String], rng: RandomNumberGenerator) -> Array[String]:
	var out: Array[String] = pool.duplicate()
	for i in range(out.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: String = out[i]
		out[i] = out[j]
		out[j] = tmp
	return out


static func _dir_of(delta: Vector2i) -> String:
	for dir: String in DIR_VECS:
		if DIR_VECS[dir] == delta:
			return dir
	return "N"  # 不可达：图边曼哈顿距离恒 1


static func _doors_of(rooms_db: Dictionary, template_id: Variant) -> Array:
	if typeof(template_id) == TYPE_STRING and rooms_db.has(template_id):
		var doors: Variant = (rooms_db[template_id] as Dictionary).get("doors", [])
		if typeof(doors) == TYPE_ARRAY:
			return doors
	return []


# ---------------------------------------------------------------- 内部：服务解析

## rng = RngSvc.setup_run(seed) + RngSvc.stream(floor_idx, "dungeon")（规格派生链）。
## 游戏内取真 autoload；--script 无头模式回退同脚本实例（派生数学完全一致）。
static func _make_rng(seed: int, floor_idx: int) -> RandomNumberGenerator:
	var svc := _rng_svc()
	svc.setup_run(seed)
	return svc.stream(floor_idx, "dungeon")


## --script 工具退出前释放回退实例（避免 ObjectDB 泄漏告警；游戏/测试上下文为空操作）。
static func cleanup_fallbacks() -> void:
	if _fallback_rng_svc != null:
		_fallback_rng_svc.free()
		_fallback_rng_svc = null
	if _fallback_game_db != null:
		_fallback_game_db.free()
		_fallback_game_db = null


static func _rng_svc() -> Object:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var found: Node = (loop as SceneTree).root.get_node_or_null("RngSvc")
		if found != null:
			return found
	if _fallback_rng_svc == null:
		_fallback_rng_svc = (load("res://autoload/rng_svc.gd") as GDScript).new()
	return _fallback_rng_svc


## GameDB 解析：游戏内取 autoload（rooms 已 fail-closed 加载）；--script 模式回退
## 手动实例化并仅加载 rooms 表（同一加载器/校验路径，坏数据同样不入库）。
static func _game_db() -> Object:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var found: Node = (loop as SceneTree).root.get_node_or_null("GameDB")
		if found != null:
			return found
	if _fallback_game_db == null:
		var script: GDScript = load("res://autoload/game_db.gd")
		var db: Object = script.new()
		db.rooms = db._load_table(script.TABLES["rooms"], script.ROOM_SCHEMA,
			script.ROOM_OPTIONAL, Callable(db, "validate_room_row"))
		_fallback_game_db = db
	return _fallback_game_db
