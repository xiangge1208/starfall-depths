class_name TestDungeonGraph
extends GdUnitTestSuite
## m1-t1：DungeonGraph 地牢图生成（纯逻辑）结构契约测试。
## 断言清单来源：task-1-brief（generate 形状/类型计数/结构规则/确定性/validate）。
## 注：brief 头行“12 节点”与其显式类型计数 start1/combat6/elite1/shop1/treasure1/
## event1/miniboss1/boss1（合计 13）矛盾，GDD §9.1 同样如此；两处冲突时以更具体、
## 可算术验证的类型计数为准 → 全图 13 节点（已在上报 concerns 注明，待设计侧确认）。

const SEED_A := 20260828
const SEEDS := [20260828, 7, 1234, 99, 555]  # 结构规则多子取样，防单一种子侥幸


func _rng(seed: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	return r


func _graphs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in SEEDS:
		out.append(DungeonGraph.generate(_rng(int(s)), 1))
	return out


func _count_types(g: Dictionary) -> Dictionary:
	var counts := {}
	var nodes: Dictionary = g["nodes"]
	for id in nodes:
		var n: Dictionary = nodes[id]
		var t := String(n["type"])
		counts[t] = int(counts.get(t, 0)) + 1
	return counts


func _first_of_type(g: Dictionary, type: String) -> int:
	var nodes: Dictionary = g["nodes"]
	for id in nodes:
		var n: Dictionary = nodes[id]
		if String(n["type"]) == type:
			return int(id)
	return -1


## 枚举 start→boss 全部最短路径（边数 == boss.depth，且逐边 depth+1），返回途经节点集合。
func _on_shortest_path_nodes(g: Dictionary) -> Dictionary:
	var nodes: Dictionary = g["nodes"]
	var boss_id := int(g["boss_id"])
	var target := int((nodes[boss_id] as Dictionary)["depth"])
	var result := {}
	_walk_shortest(nodes, int(g["start_id"]), boss_id, target, 0, {}, result)
	return result


func _walk_shortest(nodes: Dictionary, cur: int, boss_id: int, target: int, steps: int, path: Dictionary, result: Dictionary) -> void:
	if path.has(cur) or steps > target:
		return
	path[cur] = true
	if cur == boss_id and steps == target:
		for k in path:
			result[k] = true
	else:
		var nd: Dictionary = nodes[cur]
		var nexts: Array = nd["next"]
		for nx in nexts:
			var nxt := int(nx)
			if nodes.has(nxt):
				var nn: Dictionary = nodes[nxt]
				if int(nn["depth"]) == steps + 1:
					_walk_shortest(nodes, nxt, boss_id, target, steps + 1, path, result)
	path.erase(cur)


func _copy(g: Dictionary) -> Dictionary:
	var out := {"start_id": int(g["start_id"]), "boss_id": int(g["boss_id"]), "nodes": {}}
	var src: Dictionary = g["nodes"]
	for id in src:
		var n: Dictionary = src[id]
		var nexts: Array = n["next"]
		var nn: Array[int] = []
		for nx in nexts:
			nn.append(int(nx))
		out["nodes"][int(id)] = {
			"id": int(n["id"]), "type": String(n["type"]),
			"grid": n["grid"], "depth": int(n["depth"]), "next": nn,
		}
	return out


# ---------------------------------------------------------------- 契约常量

func test_types_constant_contract() -> void:
	assert_array(DungeonGraph.TYPES).is_equal(
		["start", "combat", "elite", "shop", "treasure", "event", "miniboss", "boss"])


# ---------------------------------------------------------------- generate 形状

func test_generate_node_count_and_type_counts() -> void:
	var g := DungeonGraph.generate(_rng(SEED_A), 1)
	var nodes: Dictionary = g["nodes"]
	# 13 = start1+combat6+elite1+shop1+treasure1+event1+miniboss1+boss1（见文件头注）
	assert_int(nodes.size()).is_equal(13)
	var counts := _count_types(g)
	assert_int(int(counts.get("start", 0))).is_equal(1)
	assert_int(int(counts.get("combat", 0))).is_equal(6)
	assert_int(int(counts.get("elite", 0))).is_equal(1)
	assert_int(int(counts.get("shop", 0))).is_equal(1)
	assert_int(int(counts.get("treasure", 0))).is_equal(1)
	assert_int(int(counts.get("event", 0))).is_equal(1)
	assert_int(int(counts.get("miniboss", 0))).is_equal(1)
	assert_int(int(counts.get("boss", 0))).is_equal(1)


func test_generate_start_unique_at_origin() -> void:
	for g in _graphs():
		var nodes: Dictionary = g["nodes"]
		var start_count := 0
		for id in nodes:
			var n: Dictionary = nodes[id]
			if String(n["type"]) == "start":
				start_count += 1
				var grid: Vector2i = n["grid"]
				assert_bool(grid == Vector2i.ZERO).is_true()
		assert_int(start_count).is_equal(1)
		var start: Dictionary = nodes[int(g["start_id"])]
		assert_bool(String(start["type"]) == "start").is_true()


func test_generate_boss_unique_and_unique_max_depth() -> void:
	for g in _graphs():
		var nodes: Dictionary = g["nodes"]
		var boss_count := 0
		var max_depth := -1
		var max_count := 0
		for id in nodes:
			var nd: Dictionary = nodes[id]
			if String(nd["type"]) == "boss":
				boss_count += 1
			if int(nd["depth"]) > max_depth:
				max_depth = int(nd["depth"])
				max_count = 1
			elif int(nd["depth"]) == max_depth:
				max_count += 1
		assert_int(boss_count).is_equal(1)
		var boss: Dictionary = nodes[int(g["boss_id"])]
		assert_bool(String(boss["type"]) == "boss").is_true()
		assert_int(max_depth).is_between(7, 9)  # boss 深度 = 主路径长，取 7~9
		assert_int(max_count).is_equal(1)       # boss 为全图唯一 depth 最大者
		assert_int(int(boss["depth"])).is_equal(max_depth)


func test_boss_depth_distribution_covers_7_to_9() -> void:
	# 生成规格：boss 深度 = 主路径长，取 7~9。种子扫描钉住全分布——防实现退化令
	# 某档深度不可达（fix1：步骤 4 循环内重算叶表，曾令深度 9 的尝试必失败重掷）。
	var seen := {}
	for base in SEEDS:
		for i in 200:
			var r := _rng(int(base) * 100003 + i)
			var g := DungeonGraph.generate(r, (i % 3) + 1)
			var boss: Dictionary = (g["nodes"] as Dictionary)[int(g["boss_id"])]
			seen[int(boss["depth"])] = true
	assert_bool(seen.has(7)).is_true()
	assert_bool(seen.has(8)).is_true()
	assert_bool(seen.has(9)).is_true()


func test_node_payload_contract() -> void:
	# Task 7 消费契约：id→{id:int,type:String,grid:Vector2i,depth:int,next:Array[int]}
	var g := DungeonGraph.generate(_rng(SEED_A), 1)
	var nodes: Dictionary = g["nodes"]
	for id in nodes:
		var n: Dictionary = nodes[id]
		assert_bool(n.has("id") and n.has("type") and n.has("grid") and n.has("depth") and n.has("next")).is_true()
		assert_int(int(n["id"])).is_equal(int(id))
		assert_bool(n["grid"] is Vector2i).is_true()
		assert_bool(n["type"] is String).is_true()
		assert_bool(n["depth"] is int).is_true()
		assert_bool(n["next"] is Array).is_true()
		var nexts: Array = n["next"]
		for nx in nexts:
			assert_bool(nx is int).is_true()
			assert_bool(nodes.has(nx)).is_true()


func test_generate_accepts_floor_idx_and_default() -> void:
	var g1 := DungeonGraph.generate(_rng(SEED_A))
	var g3 := DungeonGraph.generate(_rng(SEED_A), 3)
	assert_array(DungeonGraph.validate(g1)).is_empty()
	assert_array(DungeonGraph.validate(g3)).is_empty()
	assert_int((g3["nodes"] as Dictionary).size()).is_equal(13)


# ---------------------------------------------------------------- 结构规则

func test_all_nodes_reachable_from_start() -> void:
	for g in _graphs():
		var nodes: Dictionary = g["nodes"]
		var start_id := int(g["start_id"])
		var seen := {start_id: true}
		var queue: Array[int] = [start_id]
		while not queue.is_empty():
			var cur: int = queue.pop_front()
			var nd: Dictionary = nodes[cur]
			var nexts: Array = nd["next"]
			for nx in nexts:
				var nxt := int(nx)
				if not seen.has(nxt):
					seen[nxt] = true
					queue.append(nxt)
		assert_int(seen.size()).is_equal(nodes.size())


func test_acyclic_walk_next_never_revisits() -> void:
	for g in _graphs():
		var nodes: Dictionary = g["nodes"]
		var cycle_found := false
		for id in nodes:
			var walked := {}
			var cur := int(id)
			while nodes.has(cur) and not walked.has(cur):
				walked[cur] = true
				var nd: Dictionary = nodes[cur]
				var nexts: Array = nd["next"]
				if nexts.is_empty():
					break
				cur = int(nexts[0])
			if walked.has(cur):
				var nd2: Dictionary = nodes[cur]
				if not (nd2["next"] as Array).is_empty():
					cycle_found = true
		assert_bool(cycle_found).is_false()


func test_edges_manhattan_one_and_grids_unique() -> void:
	for g in _graphs():
		var nodes: Dictionary = g["nodes"]
		var grids := {}
		for id in nodes:
			var nd: Dictionary = nodes[id]
			var grid: Vector2i = nd["grid"]
			grids[grid] = true  # 重叠即冲突（Dictionary 键唯一）
			var nexts: Array = nd["next"]
			for nx in nexts:
				var nn: Dictionary = nodes[int(nx)]
				var other: Vector2i = nn["grid"]
				var md := absi(grid.x - other.x) + absi(grid.y - other.y)
				assert_int(md).is_equal(1)
		assert_int(grids.size()).is_equal(nodes.size())


func test_depth_equals_distance_from_start() -> void:
	for g in _graphs():
		var nodes: Dictionary = g["nodes"]
		var start_id := int(g["start_id"])
		var dist := {start_id: 0}
		var queue: Array[int] = [start_id]
		while not queue.is_empty():
			var cur: int = queue.pop_front()
			var nd: Dictionary = nodes[cur]
			var nexts: Array = nd["next"]
			for nx in nexts:
				var nxt := int(nx)
				if not dist.has(nxt):
					dist[nxt] = int(dist[cur]) + 1
					queue.append(nxt)
		for id in nodes:
			assert_int(int(nodes[id]["depth"])).is_equal(int(dist[int(id)]))


func test_miniboss_on_main_path_depth_boss_minus_one() -> void:
	for g in _graphs():
		var nodes: Dictionary = g["nodes"]
		var boss: Dictionary = nodes[int(g["boss_id"])]
		var on_path := _on_shortest_path_nodes(g)
		var mb_id := _first_of_type(g, "miniboss")
		assert_int(mb_id).is_not_equal(-1)
		var mb: Dictionary = nodes[mb_id]
		assert_bool(on_path.has(mb_id)).is_true()
		assert_int(int(mb["depth"])).is_equal(int(boss["depth"]) - 1)


func test_shop_on_main_path_mid_segment() -> void:
	for g in _graphs():
		var nodes: Dictionary = g["nodes"]
		var boss: Dictionary = nodes[int(g["boss_id"])]
		var on_path := _on_shortest_path_nodes(g)
		var shop_id := _first_of_type(g, "shop")
		assert_int(shop_id).is_not_equal(-1)
		assert_bool(on_path.has(shop_id)).is_true()
		assert_int(int(nodes[shop_id]["depth"])).is_between(2, int(boss["depth"]) - 2)


func test_elite_on_main_path_deep_segment() -> void:
	# 生成规格：depth ≥ max(2, boss深度-4) 的主路径节点挂 elite
	for g in _graphs():
		var nodes: Dictionary = g["nodes"]
		var boss: Dictionary = nodes[int(g["boss_id"])]
		var on_path := _on_shortest_path_nodes(g)
		var elite_id := _first_of_type(g, "elite")
		assert_int(elite_id).is_not_equal(-1)
		assert_bool(on_path.has(elite_id)).is_true()
		assert_int(int(nodes[elite_id]["depth"])).is_greater_equal(maxi(2, int(boss["depth"]) - 4))


func test_treasure_and_event_are_side_leaves() -> void:
	# treasure/event：非主路径叶子（next 为空，且不在任何 start→boss 最短路径上）
	for g in _graphs():
		var nodes: Dictionary = g["nodes"]
		var on_path := _on_shortest_path_nodes(g)
		for t in ["treasure", "event"]:
			var nid := _first_of_type(g, String(t))
			assert_int(nid).is_not_equal(-1)
			var n: Dictionary = nodes[nid]
			assert_bool((n["next"] as Array).is_empty()).is_true()
			assert_bool(on_path.has(nid)).is_false()


# ---------------------------------------------------------------- 确定性

func test_deterministic_same_seed_field_by_field() -> void:
	var a := DungeonGraph.generate(_rng(SEED_A), 1)
	var b := DungeonGraph.generate(_rng(SEED_A), 1)
	assert_int(int(a["start_id"])).is_equal(int(b["start_id"]))
	assert_int(int(a["boss_id"])).is_equal(int(b["boss_id"]))
	var an: Dictionary = a["nodes"]
	var bn: Dictionary = b["nodes"]
	assert_int(an.size()).is_equal(bn.size())
	for id in an:
		assert_bool(bn.has(id)).is_true()
		var x: Dictionary = an[id]
		var y: Dictionary = bn[id]
		assert_int(int(x["id"])).is_equal(int(y["id"]))
		assert_bool(String(x["type"]) == String(y["type"])).is_true()
		assert_bool(Vector2i(x["grid"]) == Vector2i(y["grid"])).is_true()
		assert_int(int(x["depth"])).is_equal(int(y["depth"]))
		var xn: Array = x["next"]
		var yn: Array = y["next"]
		assert_int(xn.size()).is_equal(yn.size())
		for i in xn.size():
			assert_int(int(xn[i])).is_equal(int(yn[i]))


# ---------------------------------------------------------------- validate

func test_validate_generated_graph_passes() -> void:
	for g in _graphs():
		var errs := DungeonGraph.validate(g)
		assert_array(errs).is_empty()


func test_validate_rejects_broken_graphs() -> void:
	var base := DungeonGraph.generate(_rng(SEED_A), 1)

	# (a) 邻接破坏：把某节点搬到远处（曼哈顿 != 1）
	var a := _copy(base)
	var moved_id := int(base["boss_id"])
	var an: Dictionary = a["nodes"]
	(an[moved_id] as Dictionary)["grid"] = Vector2i(99, 99)
	assert_array(DungeonGraph.validate(a)).is_not_empty()

	# (b) 断连：摘掉指向某节点的所有边 → 不可达
	var disc := _copy(base)
	var victim := _first_of_type(base, "treasure")
	var dn: Dictionary = disc["nodes"]
	for id in dn:
		var nd: Dictionary = dn[id]
		var nexts: Array = nd["next"]
		nexts.erase(victim)
	assert_array(DungeonGraph.validate(disc)).is_not_empty()

	# (c) 环：给某条边 a→b 补反向 b→a
	var cyc := _copy(base)
	var cn: Dictionary = cyc["nodes"]
	var start_next: Array = (cn[int(base["start_id"])] as Dictionary)["next"]
	var child := int(start_next[0])
	(cn[child] as Dictionary)["next"].append(int(base["start_id"]))
	assert_array(DungeonGraph.validate(cyc)).is_not_empty()

	# (d) start 不在 (0,0)
	var org := _copy(base)
	var on: Dictionary = org["nodes"]
	(on[int(base["start_id"])] as Dictionary)["grid"] = Vector2i(5, 5)
	assert_array(DungeonGraph.validate(org)).is_not_empty()

	# (e) depth 失真：某节点 depth 与 start 距离不符
	var dep := _copy(base)
	var dnn: Dictionary = dep["nodes"]
	var some_id := _first_of_type(base, "shop")
	(dnn[some_id] as Dictionary)["depth"] = int((dnn[some_id] as Dictionary)["depth"]) + 5
	assert_array(DungeonGraph.validate(dep)).is_not_empty()


func test_validate_tolerates_garbage_input() -> void:
	assert_array(DungeonGraph.validate({})).is_not_empty()
	assert_array(DungeonGraph.validate({"nodes": {}, "start_id": 0, "boss_id": 1})).is_not_empty()
