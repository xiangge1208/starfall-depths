class_name DungeonBuilder
## M1-T7 地牢装配：DungeonGraph 图 → 逐节点选模板 → 构建体 {"rooms", "corridors",
## "start_room_id", "boss_room_id"} + validate_build（门对齐/模板存在/world_pos/走廊完整性）。
##
## 模板指派规格（task-7-brief）：start→start_a<f>，boss→boss_a<f>；elite→当前使用次数
## 最低的 combat 模板（并列取洗牌序靠前者）；其余类型（combat/shop/treasure/event/
## miniboss）→combat 池按 rng 洗牌循环取用，同模板每层 ≤2 次。模板只提供几何/门，
## 店铺/宝箱等内部陈设由后续任务按房型铺设。
##
## 已证实的系统性数据错配（round 0 报告）：A1 固定模板门集合与 DungeonGraph 随机方向
## 的需门无法恒吻合（start_a1={S,E} 仅覆盖 437/1000 种子、boss_a1={N,S} 仅 500/1000）。
## 控制器裁定（fix round 1，混合 fit-aware）落地：
## 1) 数据修订：start_a1/boss_a1 门补全为 ["N","S","E","W"]——未用门为封闭门框几何，
##    房间只对实际使用的门上锁/解锁（M0 行为）；combat 模板保留原作门集合（布局多样性）。
## 2) 装配器 fit-aware：combat/elite/shop/treasure/event/miniboss 仅在门集合覆盖该节点
##    需门方向（邻接出边方向 + 入边对侧方向）的模板中取使用次数最少者（并列取洗牌序
##    靠前），去重 ≤2 仍生效；start/boss 固定模板由此恒覆盖。
## 3) 无合格模板时响亮失败：validate_build 报「room + 需门方向」（规格上不可达，
##    1000 种子扫描验证覆盖）。
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

	# combat 池洗牌一次（Fisher-Yates，续耗图生成后的同一 rng）；门覆盖感知 + 计数去重
	var shuffled := _shuffled(combat_pool(floor_idx), rng)
	var rooms_db: Dictionary = _game_db().rooms
	var req_map := _required_dir_map(nodes)
	var uses := {}
	var rooms := {}
	# 最受限先配：需门方向多者优先（同数按 id 升序）——防稀缺的全向/贴合模板被
	# 低约束节点按「最少使用」抢占，令后配的高约束节点无合格模板（seed 244 实证）。
	# 输出 rooms 键序随分配序，确定性不受影响（同种子同序）。
	var order: Array[int] = ids.duplicate()
	order.sort_custom(func(a: int, b: int) -> bool:
		var ra := (req_map[a] as Array).size()
		var rb := (req_map[b] as Array).size()
		if ra != rb:
			return ra > rb
		return a < b)
	for id in order:
		var node: Dictionary = nodes[id]
		var template_id := ""
		match String(node["type"]):
			"start":
				template_id = "start_a%d" % floor_idx
			"boss":
				template_id = "boss_a%d" % floor_idx
			_:
				# combat/elite/shop/treasure/event/miniboss：fit-aware 最少使用
				template_id = _pick_fit(shuffled, req_map[int(id)], uses, rooms_db)
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
	for edge_key in expected_edges:
		errs.append("corridors: missing graph edge %s" % edge_key)

	# 门对齐（响亮失败）：每房模板门必须覆盖其邻接需门方向集合（出边方向 + 入边
	# 对侧方向，规范序 N/S/E/W）；start/boss 固定模板同样受检。错误携带节点与需门
	# 方向（裁定 fix round 1 第 3 条）；规格上不可达，1000 种子扫描验证。
	var vnodes := {}
	for id in rooms:
		vnodes[int(id)] = (rooms[id] as Dictionary).get("node", {})
	var vreq := _required_dir_map(vnodes)
	for id in rooms:
		var room: Dictionary = rooms[id]
		var required: Array[String] = vreq.get(int(id), [])
		if required.is_empty():
			continue
		var doors := _doors_of(rooms_db, room["template_id"])
		var missing: Array[String] = []
		for d in required:
			if not doors.has(d):
				missing.append(d)
		if not missing.is_empty():
			errs.append("door mismatch: room %d(%s) lacks dirs [%s] (required [%s])" \
				% [int(id), str(room["template_id"]),
				", ".join(PackedStringArray(missing)), ", ".join(PackedStringArray(required))])
	return errs


# ---------------------------------------------------------------- 内部：模板选取

## 门覆盖感知选取（裁定 fix round 1）：仅在门集合覆盖节点需门方向的模板中取
## 使用次数最少者（并列取洗牌序靠前者，rng 序）；去重 ≤2 仍生效。无合格者返回 ""
## （validate_build 以「room + 需门方向」响亮报告；规格上不可达）。
static func _pick_fit(shuffled: Array[String], required: Array[String], uses: Dictionary,
		rooms_db: Dictionary) -> String:
	var best := ""
	var best_count := MAX_TEMPLATE_USES
	for cand in shuffled:
		var count := int(uses.get(cand, 0))
		if count >= best_count:
			continue
		if not _covers(rooms_db, cand, required):
			continue
		best = cand
		best_count = count
	if not best.is_empty():
		uses[best] = best_count + 1
	return best


static func _covers(rooms_db: Dictionary, template_id: String, required: Array[String]) -> bool:
	var doors := _doors_of(rooms_db, template_id)
	for d in required:
		if not doors.has(d):
			return false
	return true


## 每节点需门方向集合：出边方向 ∪ 入边对侧方向（树中入度 ≤1、出度 ≤2，故 ≤3 向），
## 按规范序 N/S/E/W 输出（校验消息稳定）。nodes 形如 {id → {grid, next}}。
static func _required_dir_map(nodes: Dictionary) -> Dictionary:
	var raw := {}
	for id in nodes:
		raw[int(id)] = {}
	for id in nodes:
		var nd: Dictionary = nodes[id]
		if not (nd.has("grid") and nd.has("next")):
			continue
		var grid: Vector2i = nd["grid"]
		var nexts: Array = nd["next"]
		for nx in nexts:
			var nxt := int(nx)
			if not nodes.has(nxt):
				continue
			var dir := _dir_of((nodes[nxt]["grid"] as Vector2i) - grid)
			(raw[int(id)] as Dictionary)[dir] = true
			(raw[nxt] as Dictionary)[String(DOOR_OPP[dir])] = true
	var out := {}
	for id in raw:
		var arr: Array[String] = []
		for d: String in ["N", "S", "E", "W"]:
			if (raw[id] as Dictionary).has(d):
				arr.append(d)
		out[int(id)] = arr
	return out


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
