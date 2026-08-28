class_name DungeonGraph
## 地牢图生成 + 结构校验（m1-t1，纯逻辑：rng 注入，无场景树/autoload 依赖）。
## 布局规格（GDD §9.1）：主路径先行——start(0,0) 沿随机方向链走至 boss，
## boss 深度 = 主路径长（7~9）；miniboss 固定主路径倒数第二节点；shop 主路径中段
## （2 ≤ depth ≤ boss-2）；elite 挂主路径深段（depth ≥ max(2, boss-4)）；其余节点为
## combat 支线链（从主路径出度<2 的节点侧向生长），treasure/event 挂 combat 叶子。
## 网格 4 邻接：每条边曼哈顿距离 == 1，节点 grid 全局不重叠；出度 ≤ 2（GDD 分支因子）。
## 注：brief/GDD 头行“12 节点”与其显式类型计数（合计 13）矛盾，按类型计数实现 13 节点。
## 确定性：相同 rng seed 必产出逐字段相同的图；整体重掷续耗 rng 无妨（floor_idx 预留分层差异）。

const TYPES := ["start", "combat", "elite", "shop", "treasure", "event", "miniboss", "boss"]

const TOTAL_NODES := 13      # start1+combat6+elite1+shop1+treasure1+event1+miniboss1+boss1
const MAIN_DEPTH_MIN := 7    # boss 深度 = 主路径长，规格取 7~9
const MAIN_DEPTH_MAX := 9
const MAX_ATTEMPTS := 256    # 局部围死/挂载失败时整体重掷的上限（失败概率趋零，仅作保险）

const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


## 生成一张地牢图：{"nodes": id→{id:int,type:String,grid:Vector2i,depth:int,next:Array[int]},
## "start_id": int, "boss_id": int}。rng 由调用方注入（RngSvc.stream 派生）。
@warning_ignore("unused_parameter")
static func generate(rng: RandomNumberGenerator, floor_idx: int = 1) -> Dictionary:
	for _attempt in MAX_ATTEMPTS:
		var g := _attempt_generate(rng)
		if not g.is_empty():
			return g
	push_error("DungeonGraph.generate: %d 次尝试全部失败（理论不可达）" % MAX_ATTEMPTS)
	return {"nodes": {}, "start_id": -1, "boss_id": -1}


## 结构校验：空数组 = 通过。覆盖 brief 结构规则全集：可达/无环/曼哈顿邻接/grid 唯一/
## depth==start 距离/boss 唯一最深/单例房型计数/miniboss·shop·elite 主路径位次/
## treasure·event 非主路径叶子/start 位于 (0,0)。combat 数量不在校验内（唯一伸缩项）。
static func validate(graph: Dictionary) -> Array[String]:
	var errs: Array[String] = []
	if not (graph.has("nodes") and graph.has("start_id") and graph.has("boss_id")):
		errs.append("missing root keys nodes/start_id/boss_id")
		return errs
	var nodes: Dictionary = graph["nodes"]
	if nodes.is_empty():
		errs.append("nodes is empty")
		return errs
	var start_id := int(graph["start_id"])
	var boss_id := int(graph["boss_id"])
	if not nodes.has(start_id):
		errs.append("start_id %d not in nodes" % start_id)
	if not nodes.has(boss_id):
		errs.append("boss_id %d not in nodes" % boss_id)

	# 单遍：字段完整 / id 一致 / 类型合法 / grid 唯一 / 单例房型计数
	var complete := {}      # 字段齐全的节点 id → node（缺字段的已报错，后续遍历跳过）
	var grids := {}
	var counts := {}
	for id in nodes:
		var n: Dictionary = nodes[id]
		if not (n.has("id") and n.has("type") and n.has("grid") and n.has("depth") and n.has("next")):
			errs.append("node %s missing fields" % str(id))
			continue
		complete[int(id)] = true
		if int(n["id"]) != int(id):
			errs.append("node %s id mismatch (%s)" % [str(id), str(n["id"])])
		var t := String(n["type"])
		if not TYPES.has(t):
			errs.append("node %s unknown type %s" % [str(id), t])
		counts[t] = int(counts.get(t, 0)) + 1
		var grid: Vector2i = n["grid"]
		if grids.has(grid):
			errs.append("grid %s overlap at node %s" % [str(grid), str(id)])
		grids[grid] = true
	for t in ["start", "boss", "miniboss", "shop", "treasure", "event", "elite"]:
		if int(counts.get(String(t), 0)) != 1:
			errs.append("type %s count %d != 1" % [String(t), int(counts.get(String(t), 0))])
	if complete.has(start_id):
		var sg: Vector2i = (nodes[start_id] as Dictionary)["grid"]
		if sg != Vector2i.ZERO:
			errs.append("start grid %s != (0,0)" % str(sg))

	# 边：悬挂引用 + 曼哈顿距离 == 1
	for id in complete:
		var n: Dictionary = nodes[id]
		var grid: Vector2i = n["grid"]
		var nexts: Array = n["next"]
		for nx in nexts:
			var nxt := int(nx)
			if not nodes.has(nxt):
				errs.append("edge %d->%d dangling" % [int(id), nxt])
				continue
			var un: Dictionary = nodes[nxt]
			if not un.has("grid"):
				continue  # 缺字段已单独报错
			var other: Vector2i = un["grid"]
			if absi(grid.x - other.x) + absi(grid.y - other.y) != 1:
				errs.append("edge %d->%d manhattan != 1" % [int(id), nxt])

	# BFS：从 start 可达 + depth == start 距离
	if complete.has(start_id):
		var dist := {start_id: 0}
		var queue: Array[int] = [start_id]
		while not queue.is_empty():
			var cur: int = queue.pop_front()
			var nexts: Array = (nodes[cur] as Dictionary)["next"]
			for nx in nexts:
				var nxt := int(nx)
				if complete.has(nxt) and not dist.has(nxt):
					dist[nxt] = int(dist[cur]) + 1
					queue.append(nxt)
		for id in nodes:
			if not dist.has(int(id)):
				errs.append("node %d unreachable from start" % int(id))
			elif complete.has(int(id)) and int((nodes[id] as Dictionary)["depth"]) != int(dist[int(id)]):
				errs.append("node %d depth != distance from start" % int(id))

	# 无环：沿 next 的 DFS 三色标记
	var state := {}
	var cyclic := false
	for id in complete:
		if _dfs_cycle(nodes, int(id), state):
			cyclic = true
			break
	if cyclic:
		errs.append("graph contains a cycle along next")

	# 位次规则（前置检查全净才做，避免半残图误报/崩溃）
	if errs.is_empty():
		var bd := int((nodes[boss_id] as Dictionary)["depth"])
		for id in complete:
			if int(id) != boss_id and int((nodes[id] as Dictionary)["depth"]) >= bd:
				errs.append("node %d depth >= boss depth %d" % [int(id), bd])
		# 反向 BFS：到 boss 的最小跳数；主路径成员 ⇔ depth + 跳数 == boss.depth
		var rev := {}
		for id in complete:
			var nexts: Array = (nodes[id] as Dictionary)["next"]
			for nx in nexts:
				var nxt := int(nx)
				if not rev.has(nxt):
					rev[nxt] = []
				(rev[nxt] as Array).append(int(id))
		var rbfs := {boss_id: 0}
		var rq: Array[int] = [boss_id]
		while not rq.is_empty():
			var cur: int = rq.pop_front()
			var ups: Array = rev.get(cur, [])
			for ux in ups:
				var up := int(ux)
				if not rbfs.has(up):
					rbfs[up] = int(rbfs[cur]) + 1
					rq.append(up)
		for id in complete:
			var n: Dictionary = nodes[id]
			var t := String(n["type"])
			var depth := int(n["depth"])
			var on_main := rbfs.has(int(id)) and depth + int(rbfs[int(id)]) == bd
			var nexts: Array = n["next"]
			match t:
				"miniboss":
					if not on_main:
						errs.append("miniboss %d not on start->boss shortest path" % int(id))
					if depth != bd - 1:
						errs.append("miniboss %d depth != boss.depth-1" % int(id))
				"shop":
					if not on_main:
						errs.append("shop %d not on main path" % int(id))
					if depth < 2 or depth > bd - 2:
						errs.append("shop %d depth out of [2, boss.depth-2]" % int(id))
				"elite":
					if not on_main:
						errs.append("elite %d not on main path" % int(id))
					if depth < maxi(2, bd - 4):
						errs.append("elite %d depth < max(2, boss.depth-4)" % int(id))
				"treasure", "event":
					if not nexts.is_empty():
						errs.append("%s %d is not a leaf" % [t, int(id)])
					if on_main:
						errs.append("%s %d sits on main path" % [t, int(id)])
	return errs


# ---------------------------------------------------------------- 生成内部

## 单次尝试；失败（局部围死/挂载失败）返回 {}，由 generate 用同一 rng 重掷。
static func _attempt_generate(rng: RandomNumberGenerator) -> Dictionary:
	var main_depth := rng.randi_range(MAIN_DEPTH_MIN, MAIN_DEPTH_MAX)

	# 1) 主路径网格链：start(0,0) 随机方向走 main_depth 步
	var occupied := {Vector2i.ZERO: true}
	var path: Array[Vector2i] = [Vector2i.ZERO]
	for _i in main_depth:
		var dirs := _free_dirs(occupied, path[path.size() - 1])
		if dirs.is_empty():
			return {}
		var cell: Vector2i = dirs[rng.randi_range(0, dirs.size() - 1)]
		occupied[cell] = true
		path.append(cell)

	# 2) 主路径房型：start/miniboss(d-1)/boss(d) + shop 中段 + elite 深段，其余 combat
	var shop_depth := rng.randi_range(2, main_depth - 2)
	var elite_pool: Array[int] = []
	for d in range(maxi(2, main_depth - 4), main_depth - 1):
		if d != shop_depth:
			elite_pool.append(d)
	if elite_pool.is_empty():
		return {}
	var elite_depth: int = elite_pool[rng.randi_range(0, elite_pool.size() - 1)]
	var nodes := {}
	for d in main_depth + 1:
		var t := "combat"
		if d == 0:
			t = "start"
		elif d == main_depth:
			t = "boss"
		elif d == main_depth - 1:
			t = "miniboss"
		elif d == shop_depth:
			t = "shop"
		elif d == elite_depth:
			t = "elite"
		nodes[d] = _node(d, t, path[d], d)
		if d > 0:  # 主路径链边：depth d-1 → d
			var mnext: Array = (nodes[d - 1] as Dictionary)["next"]
			mnext.append(d)

	# 3) combat 支线链：从主路径出度<2 且非 boss/miniboss 的节点侧向生长。
	#    支线深度上限 boss-2 → treasure/event（+1）仍浅于 boss，保证 boss 唯一最深。
	var side_combat := TOTAL_NODES - (main_depth + 1) - 2
	var next_id := main_depth + 1
	var placed := 0
	var dead_anchors := {}
	while placed < side_combat:
		var anchors: Array[int] = []
		for aid in main_depth - 1:  # 0..main_depth-2（排除 boss 与 miniboss）
			if dead_anchors.has(aid):
				continue
			var an: Dictionary = nodes[aid]
			if (an["next"] as Array).size() >= 2:
				continue
			anchors.append(aid)
		if anchors.is_empty():
			return {}
		var anchor: int = anchors[rng.randi_range(0, anchors.size() - 1)]
		var anchor_depth := int(nodes[anchor]["depth"])
		var budget := mini(side_combat - placed, (main_depth - 2) - anchor_depth)
		if budget <= 0:
			dead_anchors[anchor] = true
			continue
		var parent := anchor
		var cur: Vector2i = nodes[anchor]["grid"]
		var cdepth := anchor_depth
		var grew := false
		for _j in budget:
			var dirs := _free_dirs(occupied, cur)
			if dirs.is_empty():
				break
			var cell: Vector2i = dirs[rng.randi_range(0, dirs.size() - 1)]
			occupied[cell] = true
			cdepth += 1
			var pnext: Array = (nodes[parent] as Dictionary)["next"]
			pnext.append(next_id)
			nodes[next_id] = _node(next_id, "combat", cell, cdepth)
			parent = next_id
			cur = cell
			next_id += 1
			placed += 1
			grew = true
		if not grew:
			dead_anchors[anchor] = true

	# 4) treasure/event 挂 combat 叶子（允许同叶异枝：boss 深度 9 时支线 combat 仅 1 节点）
	for kind in ["treasure", "event"]:
		var leaves: Array[int] = []
		for id in nodes:
			var nd: Dictionary = nodes[id]
			if String(nd["type"]) == "combat" and (nd["next"] as Array).is_empty():
				leaves.append(int(id))
		if leaves.is_empty():
			return {}
		var leaf: int = leaves[rng.randi_range(0, leaves.size() - 1)]
		var leaf_grid: Vector2i = nodes[leaf]["grid"]
		var dirs := _free_dirs(occupied, leaf_grid)
		if dirs.is_empty():
			return {}
		var cell: Vector2i = dirs[rng.randi_range(0, dirs.size() - 1)]
		occupied[cell] = true
		var lnext: Array = (nodes[leaf] as Dictionary)["next"]
		lnext.append(next_id)
		nodes[next_id] = _node(next_id, String(kind), cell, int((nodes[leaf] as Dictionary)["depth"]) + 1)
		next_id += 1
	return {"nodes": nodes, "start_id": 0, "boss_id": main_depth}


static func _node(id: int, type: String, grid: Vector2i, depth: int) -> Dictionary:
	var next: Array[int] = []
	return {"id": id, "type": type, "grid": grid, "depth": depth, "next": next}


static func _free_dirs(occupied: Dictionary, cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in DIRS:
		var dv: Vector2i = d
		if not occupied.has(cell + dv):
			out.append(cell + dv)
	return out


## 三色 DFS：state 2=在栈 1=完成；沿 next 回边即有环。
static func _dfs_cycle(nodes: Dictionary, cur: int, state: Dictionary) -> bool:
	var s := int(state.get(cur, 0))
	if s == 1:
		return false
	if s == 2:
		return true
	state[cur] = 2
	var n: Dictionary = nodes[cur]
	if n.has("next"):
		var nexts: Array = n["next"]
		for nx in nexts:
			var nxt := int(nx)
			if nodes.has(nxt) and _dfs_cycle(nodes, nxt, state):
				state[cur] = 1
				return true
	state[cur] = 1
	return false
