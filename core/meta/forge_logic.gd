class_name ForgeLogic
extends RefCounted
## 熔铸纯逻辑（m2-t25）：配方命中 / 通用升级 / 费用，全 static 无副作用（同 ShopLogic 习语）。
##
## 规则锚点（GDD §8.3 + 数据表附录 D）：
## - 固定配方：data/fusions.json 15 行 {a,b,result}（a/b 无序等价，附录 D 拼音 id 对齐 weapons 表）；
## - 通用升级：同稀有度任意两把 → +1 稀有度的随机武器，每局限 2 次（计数在 RunState.forge_upgrades，
##   上限本表 UPGRADE_LIMIT_PER_RUN）；候选排除两把材料本体与 4 把★熔铸限定
##   （附录 A：★只能由配方产出，不入普通掉落池，故也不入通用升级桶）；
## - 费用：两把中较高稀有度的基准价（附录 H 锚点中值，同 ShopLogic.BASE_PRICES）×1.5，四舍五入到 5。
##   （披露：GDD §8.3「40~80 金」为早期区间口径，本卡按控制器规格固定公式落地。）
##
## 池接缝：pool 为权威武器表（Dictionary id -> row，row 至少含 rarity，建议含 name）。
## 传入什么就只在什么里选取/校验——未解锁（locked）武器不入池即天然不可作材料也不可作产物。

const FUSIONS_PATH := "res://data/fusions.json"
const UPGRADE_LIMIT_PER_RUN := 2     # 通用升级每局限 2 次（GDD §8.3）
const COST_MULT := 1.5               # 较高稀有度基准 ×1.5
const ROUND_TO := 5                  # 取整到 5（同 ShopLogic）
const RARITIES: Array[String] = ["common", "uncommon", "rare", "epic", "legend"]
## 附录 H 锚点中值：直接别名 ShopLogic.BASE_PRICES（编译期常量引用，无 autoload 依赖），
## 双表永不同漂移。
const BASE_PRICES := ShopLogic.BASE_PRICES
## ★熔铸限定 4 把（附录 A）：不入通用升级候选。
const FUSION_ONLY: Array[String] = ["leishenzhichui", "zhanjiandao", "xingyunpao", "yamiehexin"]

static var _recipes_cache: Array = []


# ---------------------------------------------------------------- 配方表

## 配方表（data/fusions.json）：首次读取后缓存；行规范化为 {a,b,result}（String），
## 畸形行跳过并告警（fail-soft，缺文件/空表 = 只有通用升级可用）。
static func recipes() -> Array:
	if _recipes_cache.is_empty():
		_recipes_cache = _load_recipes()
	return _recipes_cache


## 查配方：a/b 无序等价，命中返回产物 id，否则 ""。
static func find_recipe(a: String, b: String) -> String:
	for r: Variant in recipes():
		var row: Dictionary = r
		if (String(row["a"]) == a and String(row["b"]) == b) \
				or (String(row["a"]) == b and String(row["b"]) == a):
			return String(row["result"])
	return ""


## 稀有度 +1；顶稀有度（legend）返回 ""。
static func next_rarity(rarity: String) -> String:
	var i := RARITIES.find(rarity)
	if i < 0 or i + 1 >= RARITIES.size():
		return ""
	return RARITIES[i + 1]


# ---------------------------------------------------------------- 熔铸

## 预览（不掷签、不消耗 rng）：配方命中给确切产物；同稀有度给升级目标稀有度；
## 其余（空 id/同名/不在池/稀有度不同/顶稀有/桶空）→ {"kind": "none"}。
static func preview(a: String, b: String, pool: Dictionary) -> Dictionary:
	var kind := _classify(a, b, pool)
	if kind == "recipe":
		var pid := find_recipe(a, b)
		var row: Dictionary = pool.get(pid, {})
		return {"kind": "recipe", "id": pid,
			"name": String(row.get("name", pid)), "rarity": String(row.get("rarity", ""))}
	if kind == "upgrade":
		return {"kind": "upgrade",
			"target_rarity": next_rarity(String((pool[a] as Dictionary).get("rarity", "")))}
	return {"kind": "none"}


## 熔铸：命中配方 → 产物（rng 不消费）；未命中但同稀有度 → +1 稀有度随机未拥有武器
## （rng 注入优先；缺省沿 RunState 分盐流，--script 无树时退化 a|b 散列种子保确定性）；
## 其余返回空字典。产物 = {"kind", "id", "name", "rarity"}。
static func fuse(a: String, b: String, pool: Dictionary,
		rng: RandomNumberGenerator = null) -> Dictionary:
	var kind := _classify(a, b, pool)
	if kind == "recipe":
		var pid := find_recipe(a, b)
		var row: Dictionary = pool.get(pid, {})
		return {"kind": "recipe", "id": pid,
			"name": String(row.get("name", pid)), "rarity": String(row.get("rarity", ""))}
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
	for id: String in pool:
		if id == exclude_a or id == exclude_b or FUSION_ONLY.has(id):
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
			return found.call("stream", "forge")
	rng.seed = hash("%s|%s" % [a, b])
	return rng


static func _round5(x: float) -> int:
	return int(round(x / float(ROUND_TO))) * ROUND_TO


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
