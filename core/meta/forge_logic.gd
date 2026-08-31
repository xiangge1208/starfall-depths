class_name ForgeLogic
extends RefCounted
## 熔铸纯逻辑（m2-t25）：配方命中 / 通用升级 / 费用，全 static 无副作用（同 ShopLogic 习语）。
##
## 规则锚点（GDD §8.3 + 数据表附录 D）：
## - 固定配方：data/fusions.json 15 行 {a,b,result}（a/b 无序等价，附录 D 拼音 id 对齐 weapons 表）；
## - 产物继承（附录 D 尾部，裁定⑯）：配方产物的 energy_cost = 两材料较高者，
##   element = B 材料的元素（B = 配方表 b 键那把，与入参顺序无关）。只改返回的副本，
##   绝不回写 GameDB 表行；材料行缺字段时回落 0 / "none"。
## - 通用升级：同稀有度任意两把 → +1 稀有度的随机武器，每局限 2 次（计数在 RunState.forge_upgrades，
##   上限本表 UPGRADE_LIMIT_PER_RUN）；候选排除两把材料本体与 ★熔铸限定
##   （附录 A：★只能由配方产出，不入普通掉落池，故也不入通用升级桶）。
##   ★集合权威源 = data/unlock_tasks.json 的 forge_only:true（裁定⑭，见 fusion_only()）；
## - 费用：两把中较高稀有度的基准价（附录 H 锚点中值，同 ShopLogic.BASE_PRICES）×1.5，四舍五入到 5。
##   （披露：GDD §8.3「40~80 金」为早期区间口径，本卡按控制器规格固定公式落地。）
##
## 池接缝：pool 为权威武器表（Dictionary id -> row，row 至少含 rarity，建议含 name）。
## 传入什么就只在什么里选取/校验——未解锁（locked）武器不入池即天然不可作材料也不可作产物。

const FUSIONS_PATH := "res://data/fusions.json"
## ★熔铸限定的权威数据源（m2-t20 数据卡，T3 定稿 49 条）：unlock_tasks.json 的
## forge_only:true 条目。不经 GameDB 装载（同 CodexSystem._load_tasks 的 FileAccess 直读习语）。
const UNLOCK_TASKS_PATH := "res://data/unlock_tasks.json"
const UPGRADE_LIMIT_PER_RUN := 2     # 通用升级每局限 2 次（GDD §8.3）
const COST_MULT := 1.5               # 较高稀有度基准 ×1.5
const ROUND_TO := 5                  # 取整到 5（同 ShopLogic）
const RARITIES: Array[String] = ["common", "uncommon", "rare", "epic", "legend"]
## 附录 H 锚点中值：直接别名 ShopLogic.BASE_PRICES（编译期常量引用，无 autoload 依赖），
## 双表永不同漂移。
const BASE_PRICES := ShopLogic.BASE_PRICES
## ★熔铸限定 4 把（附录 A）：不入通用升级候选。
## 【兜底，非真相源】权威源是 data/unlock_tasks.json 的 forge_only 条目（见 fusion_only()）：
## 该表可读时一律走数据，本常量仅在数据缺失/不可解析/零命中时生效。二者由
## test_fusion_only_matches_unlock_tasks_forge_only_data 双向钉死，改数据不改常量会立刻 RED。
const FUSION_ONLY: Array[String] = ["leishenzhichui", "zhanjiandao", "xingyunpao", "yamiehexin"]
## 兜底随机源用的熔铸盐（Minor-3）：正式局由 floor_scene 注入 rng，此路径不可达。
## static 上下文不能裸引用 autoload 常量（Object.get 读不到脚本 const，实测返回 null），
## 故留字面量并抽常量，由 test_forge_fallback_salt_matches_run_state_constant 钉死
## 与 RunState.SALT_FORGE 一致——改一处忘另一处立刻 RED。
const SALT_FORGE := "forge"

# 缓存 + 「已尝试装载」哨兵（M-1）：哨兵而非 is_empty()，否则缺文件/空表会每次调用
# 重读一遍并刷一条 error；reset_caches() 供测试重置。
static var _recipes_cache: Array = []
static var _recipes_loaded := false
static var _forge_only_data: Array[String] = []
static var _forge_only_loaded := false
static var _fallback_weapons_all: Dictionary = {}


# ---------------------------------------------------------------- 配方表

## 配方表（data/fusions.json）：首次读取后缓存；行规范化为 {a,b,result}（String），
## 畸形行跳过并告警（fail-soft，缺文件/空表 = 只有通用升级可用）。
static func recipes() -> Array:
	if not _recipes_loaded:
		_recipes_loaded = true
		_recipes_cache = _load_recipes()
	return _recipes_cache


## 测试/热重载缝：清空配方表与★集合缓存及其哨兵，下次访问重新读文件。
static func reset_caches() -> void:
	_recipes_cache = []
	_recipes_loaded = false
	_forge_only_data = []
	_forge_only_loaded = false


## 数据侧★集合（权威源，不做兜底）；装载一次后缓存，缺文件/坏 JSON 返回空数组。
static func forge_only_from_data() -> Array[String]:
	if not _forge_only_loaded:
		_forge_only_loaded = true
		_forge_only_data = _read_forge_only_ids()
	return _forge_only_data


## ★熔铸限定集合：优先取 unlock_tasks.json 的 forge_only 条目，数据不可用时回落常量。
static func fusion_only() -> Array[String]:
	var from_data := forge_only_from_data()
	return from_data if not from_data.is_empty() else FUSION_ONLY.duplicate()


## 查配方：a/b 无序等价，命中返回产物 id，否则 ""。
static func find_recipe(a: String, b: String) -> String:
	return String(find_recipe_row(a, b).get("result", ""))


## 查配方（含材料归属）：返回 {result, mat_a, mat_b}；mat_a/mat_b 是**配方表 a/b 键**
## 对应的那两把（与调用方的入参顺序无关，供附录 D 产物继承判定「B 材料」用）。
static func find_recipe_row(a: String, b: String) -> Dictionary:
	for r: Variant in recipes():
		var row: Dictionary = r
		if String(row["a"]) == a and String(row["b"]) == b:
			return {"result": String(row["result"]), "mat_a": a, "mat_b": b}
		if String(row["a"]) == b and String(row["b"]) == a:
			return {"result": String(row["result"]), "mat_a": b, "mat_b": a}
	return {}


## 稀有度 +1；顶稀有度（legend）返回 ""。
static func next_rarity(rarity: String) -> String:
	var i := RARITIES.find(rarity)
	if i < 0 or i + 1 >= RARITIES.size():
		return ""
	return RARITIES[i + 1]


# ---------------------------------------------------------------- 熔铸

## 预览（不掷签、不消耗 rng）：配方命中给确切产物（含继承后的 energy_cost/element）；
## 同稀有度给升级目标稀有度；其余（空 id/同名/不在池/稀有度不同/顶稀有/桶空）→ {"kind": "none"}。
static func preview(a: String, b: String, pool: Dictionary) -> Dictionary:
	var kind := _classify(a, b, pool)
	if kind == "recipe":
		return _recipe_result(a, b, pool)
	if kind == "upgrade":
		return {"kind": "upgrade",
			"target_rarity": next_rarity(String((pool[a] as Dictionary).get("rarity", "")))}
	return {"kind": "none"}


## 熔铸：命中配方 → 产物（rng 不消费）；未命中但同稀有度 → +1 稀有度随机未拥有武器
## （rng 注入优先；缺省沿 RunState 分盐流，--script 无树时退化 a|b 散列种子保确定性）；
## 其余返回空字典。产物 = {"kind", "id", "name", "rarity"}，
## 配方产物另附 {"energy_cost", "element"}（附录 D 继承后的局内实例值，裁定⑯）。
static func fuse(a: String, b: String, pool: Dictionary,
		rng: RandomNumberGenerator = null) -> Dictionary:
	var kind := _classify(a, b, pool)
	if kind == "recipe":
		return _recipe_result(a, b, pool)
	if kind != "upgrade":
		return {}
	var target := next_rarity(String((pool[a] as Dictionary).get("rarity", "")))
	var candidates := _candidates(pool, target, a, b)
	if candidates.is_empty():
		return {}
	if rng == null:
		rng = _default_rng(a, b)
	var picked := candidates[rng.randi_range(0, candidates.size() - 1)]
	var prow: Dictionary = pool.get(picked, {})
	return {"kind": "upgrade", "id": picked,
		"name": String(prow.get("name", picked)), "rarity": target}


## 费用：两把中较高稀有度基准价 ×1.5，四舍五入到 5；未知稀有度防御性按 common 基准。
static func fuse_cost(rarity_a: String, rarity_b: String) -> int:
	var ia := RARITIES.find(rarity_a)
	var ib := RARITIES.find(rarity_b)
	if ia < 0:
		ia = 0
	if ib < 0:
		ib = 0
	var base := int(BASE_PRICES[RARITIES[maxi(ia, ib)]])
	return _round5(float(base) * COST_MULT)


# ---------------------------------------------------------------- 内部

## 配方产物结果（preview/fuse 共用，两处口径同源）。
## 附录 D 尾部的产物继承（裁定⑯）由 _inherit_stats 在返回前覆写。
static func _recipe_result(a: String, b: String, pool: Dictionary) -> Dictionary:
	var hit := find_recipe_row(a, b)
	var pid := String(hit.get("result", ""))
	var row := _product_row(pid, pool)
	var out := {"kind": "recipe", "id": pid,
		"name": String(row.get("name", pid)), "rarity": String(row.get("rarity", ""))}
	_inherit_stats(out, hit, pool)
	return out


## 附录 D 尾部的产物继承（裁定⑯，GDD 明文规则）：
##   energy_cost = 两材料较高者；element = B 材料的元素（B = 配方表 b 键那把，
##   与调用方入参顺序无关——熔铸对投入顺序无感）。
## 只写返回副本，绝不回写 GameDB 表行（继承属局内实例属性）。
## 材料行缺字段时按常规回落：蓝耗 0、元素 "none"。
static func _inherit_stats(out: Dictionary, hit: Dictionary, pool: Dictionary) -> void:
	var mat_a := String(hit.get("mat_a", ""))
	var mat_b := String(hit.get("mat_b", ""))
	if mat_a.is_empty() or mat_b.is_empty():
		return
	var row_a := (pool.get(mat_a, {}) as Dictionary)
	var row_b := (pool.get(mat_b, {}) as Dictionary)
	out["energy_cost"] = maxi(int(row_a.get("energy_cost", 0)), int(row_b.get("energy_cost", 0)))
	out["element"] = String(row_b.get("element", "none"))


## 共同前置分类：空 id / 同名武器 / 任一不在池 → "none"；
## 配方命中 → "recipe"；同稀有度、可 +1 且 +1 桶在池内有候选 → "upgrade"；其余 → "none"。
## （桶空一致性：preview 与 fuse 同源判定——当前数据期紫/橙全 locked 不入掉落池，
## 蓝→紫桶空即不可升级，UI 不会出现「可预览、熔铸却失败」的付费陷阱。）
static func _classify(a: String, b: String, pool: Dictionary) -> String:
	if a.is_empty() or b.is_empty() or a == b:
		return "none"
	if not pool.has(a) or not pool.has(b):
		return "none"
	if not find_recipe(a, b).is_empty():
		return "recipe"
	var ra := String((pool[a] as Dictionary).get("rarity", ""))
	var rb := String((pool[b] as Dictionary).get("rarity", ""))
	if ra != rb or next_rarity(ra).is_empty():
		return "none"
	if _candidates(pool, next_rarity(ra), a, b).is_empty():
		return "none"
	return "upgrade"


## 升级候选：目标稀有度桶（字典序确定性），排除两把材料与★熔铸限定。
static func _candidates(pool: Dictionary, rarity: String,
		exclude_a: String, exclude_b: String) -> Array[String]:
	var out: Array[String] = []
	var stars := fusion_only()
	for id: String in pool:
		if id == exclude_a or id == exclude_b or stars.has(id):
			continue
		if String((pool[id] as Dictionary).get("rarity", "")) != rarity:
			continue
		out.append(id)
	out.sort()
	return out


## 缺省随机源：正式局走 RunState 分盐流（forge 盐）；无 SceneTree（--script/纯解析）
## 时退化确定性种子（RngSvc 全局 randi 禁令：绝不裸随机）。
## 不裸引用 autoload（同 ShopLogic._weapons 习语）：按名寻址 + has_method 门，
## 保 --script 模式编译干净；盐字面量同 RunState.SALT_FORGE("forge")。
static func _default_rng(a: String, b: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var found: Node = (loop as SceneTree).root.get_node_or_null("RunState")
		if found != null and found.has_method("stream"):
			return found.call("stream", SALT_FORGE)
	rng.seed = hash("%s|%s" % [a, b])
	return rng


static func _round5(x: float) -> int:
	return int(round(x / float(ROUND_TO))) * ROUND_TO


## 产物行（副本，永不回写）：pool 优先；缺则回落全量表——locked 产物不在掉落池时
## 取展示名，避免 name 退化成拼音 id（M-2）。
static func _product_row(pid: String, pool: Dictionary) -> Dictionary:
	var row: Variant = pool.get(pid, {})
	if typeof(row) != TYPE_DICTIONARY or (row as Dictionary).is_empty():
		row = _weapons_all().get(pid, {})
	if typeof(row) != TYPE_DICTIONARY:
		return {}
	return (row as Dictionary).duplicate()


## 全量武器表（含 locked）：游戏内取 autoload；--script 模式回退手动加载
## （同 ShopLogic._weapons 习语——static 上下文不裸引用 autoload）。
static func _weapons_all() -> Dictionary:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var found: Node = (loop as SceneTree).root.get_node_or_null("GameDB")
		if found != null:
			return found.weapons_all
	if _fallback_weapons_all.is_empty():
		var script: GDScript = load("res://autoload/game_db.gd")
		var db: Object = script.new()
		_fallback_weapons_all = db._load_table(script.TABLES["weapons"],
			script.WEAPON_SCHEMA, script.WEAPON_OPTIONAL)
	return _fallback_weapons_all


## 读 unlock_tasks.json 的 forge_only:true 条目（字典序）；任何失败返回空数组
## （调用方据此回落 FUSION_ONLY）。同 CodexSystem._load_tasks 的 fail-soft 口径。
static func _read_forge_only_ids() -> Array[String]:
	var out: Array[String] = []
	if not FileAccess.file_exists(UNLOCK_TASKS_PATH):
		push_error("ForgeLogic: missing %s" % UNLOCK_TASKS_PATH)
		return out
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(UNLOCK_TASKS_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("ForgeLogic: %s is not an object" % UNLOCK_TASKS_PATH)
		return out
	for id: String in parsed:
		if typeof(parsed[id]) != TYPE_DICTIONARY:
			continue
		if bool((parsed[id] as Dictionary).get("forge_only", false)):
			out.append(id)
	out.sort()
	return out


static func _load_recipes() -> Array:
	var txt := FileAccess.get_file_as_string(FUSIONS_PATH)
	if txt.is_empty():
		push_error("ForgeLogic: cannot read %s" % FUSIONS_PATH)
		return []
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_ARRAY:
		push_error("ForgeLogic: %s is not an array" % FUSIONS_PATH)
		return []
	var out: Array = []
	for r: Variant in parsed:
		if typeof(r) != TYPE_DICTIONARY:
			push_warning("ForgeLogic: skip non-object recipe row")
			continue
		var row: Dictionary = r
		if not (row.has("a") and row.has("b") and row.has("result")):
			push_warning("ForgeLogic: skip recipe row missing a/b/result")
			continue
		out.append({"a": String(row["a"]), "b": String(row["b"]), "result": String(row["result"])})
	return out
