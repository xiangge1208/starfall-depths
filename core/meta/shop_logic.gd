class_name ShopLogic
extends RefCounted
## 商店纯逻辑（m1-t14）：定价 / 货架 roll / 回收价，全 static 无副作用。
## 数值锚点：数据表附录 H（商店价格系数 ×1.0/×1.6/×2.56）+ 控制器基准表
## {common:20, uncommon:42, rare:85, epic:155, legend:260}（附录 H 锚点中值）；
## 稀有度权重：设计文档 §8.2 掉落权重表按层取行（A1 70/25/5/0/0、A2 45/35/16/4/0、
## A3 25/33/25/13/4）。同名武器不重复（exclude 由调用方累积传入）。
## 注意：M1 现役 data/weapons.json 仅 6 把全 common——高稀有度桶在真实数据下
## 统一经「向下回退」落到 common（预期行为，数据补齐后自动生效）。

const RARITIES: Array[String] = ["common", "uncommon", "rare", "epic", "legend"]
const BASE_PRICES := {"common": 20, "uncommon": 42, "rare": 85, "epic": 155, "legend": 260}
const FLOOR_MULT: Array[float] = [1.0, 1.6, 2.56]   # 附录 H：A1/A2/A3
const BLACK_MULT := 1.8
const RECYCLE_RATIO := 0.3                          # §8.2：回收 = 30% 价格
const ROUND_TO := 5
const RECYCLE_MIN := 5
# §8.2 逐层稀有度权重（白/绿/蓝/紫/橙 → common/uncommon/rare/epic/legend），每行合计 100
const RARITY_WEIGHTS := {
	1: {"common": 70, "uncommon": 25, "rare": 5, "epic": 0, "legend": 0},
	2: {"common": 45, "uncommon": 35, "rare": 16, "epic": 4, "legend": 0},
	3: {"common": 25, "uncommon": 33, "rare": 25, "epic": 13, "legend": 4},
}
# 高→低（桶空向下回退序）
const RARITY_FALLBACK: Array[String] = ["legend", "epic", "rare", "uncommon", "common"]
const ITEM_KINDS: Array[String] = ["heart", "energy"]
const DRINK_PLACEHOLDER := "mystery_drink"          # T16 接真实饮料前的数据占位

static var _fallback_weapons: Dictionary = {}


## 售价：基准表 × floor 系数 ×（黑市 ×1.8），取整到 5。
## 未知稀有度按 common 基准防御性计价（不崩溃）。
static func price(rarity: String, floor_idx: int, black: bool) -> int:
	var base := int(BASE_PRICES.get(rarity, BASE_PRICES["common"]))
	return _round5(float(base) * _floor_mult(floor_idx) * (BLACK_MULT if black else 1.0))


## 回收价：基准 × 0.3 × floor 系数，取整到 5，下限 5。
static func recycle_price(rarity: String, floor_idx: int) -> int:
	var base := int(BASE_PRICES.get(rarity, BASE_PRICES["common"]))
	return maxi(RECYCLE_MIN, _round5(float(base) * RECYCLE_RATIO * _floor_mult(floor_idx)))


## 按层权重 roll 一把武器 id：先掷稀有度（§8.2 当层行），桶内按 id 字典序均匀取；
## 桶空（数据缺失或被 exclude）→ 沿 RARITY_FALLBACK 向下回退；全空返回 ""（池枯哨兵）。
static func roll_weapon_id(rng: RandomNumberGenerator, floor_idx: int,
		exclude: Array[String]) -> String:
	var weapons := _weapons()
	var rolled := _roll_rarity(rng, floor_idx)
	var start := RARITY_FALLBACK.find(rolled)
	if start < 0:
		start = RARITY_FALLBACK.size() - 1
	for i in range(start, RARITY_FALLBACK.size()):
		var pool := _bucket(weapons, RARITY_FALLBACK[i], exclude)
		if not pool.is_empty():
			return pool[rng.randi_range(0, pool.size() - 1)]
	return ""


## 货架：3 武器（层内不重复，exclude 累积排除；池枯提前截断）+ 2 道具 + 1 饮料占位。
## 附带 "floor_idx" 元数据键供 UI 定价（ShopLogic 生成时已知层号，UI 免再传）。
static func roll_stock(rng: RandomNumberGenerator, floor_idx: int,
		exclude: Array[String]) -> Dictionary:
	var seen: Array[String] = exclude.duplicate()
	var ids: Array[String] = []
	for i in 3:
		var id := roll_weapon_id(rng, floor_idx, seen)
		if id.is_empty():
			break
		ids.append(id)
		seen.append(id)
	var items: Array[Dictionary] = [{"kind": "heart"}, {"kind": "energy"}]
	return {
		"floor_idx": clampi(floor_idx, 1, 3),
		"weapons": ids,
		"items": items,
		"drink": DRINK_PLACEHOLDER,
	}


# ---------------------------------------------------------------- 内部

static func _floor_mult(floor_idx: int) -> float:
	return FLOOR_MULT[clampi(floor_idx - 1, 0, 2)]


static func _round5(x: float) -> int:
	return int(round(x / float(ROUND_TO))) * ROUND_TO


## 掷稀有度：当层权重行 1..100 落区间（行合计恒 100）。
static func _roll_rarity(rng: RandomNumberGenerator, floor_idx: int) -> String:
	var weights: Dictionary = RARITY_WEIGHTS.get(clampi(floor_idx, 1, 3),
		RARITY_WEIGHTS[1])
	var roll := rng.randi_range(1, 100)
	var acc := 0
	for rarity: String in RARITIES:
		acc += int(weights.get(rarity, 0))
		if roll <= acc:
			return rarity
	return "common"


## 稀有度桶：表内该稀有度、未被 exclude 的 id 集（字典序，保证确定性）。
static func _bucket(weapons: Dictionary, rarity: String, exclude: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for id: String in weapons:
		if String(weapons[id].get("rarity", "")) == rarity and not exclude.has(id):
			out.append(id)
	out.sort()
	return out


## weapons 表解析：游戏内取 autoload；--script 模式回退手动加载（同一加载器路径，
## 同 DungeonBuilder._game_db 模式——static 上下文不裸引用 autoload）。
static func _weapons() -> Dictionary:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var found: Node = (loop as SceneTree).root.get_node_or_null("GameDB")
		if found != null:
			return found.weapons
	if _fallback_weapons.is_empty():
		var script: GDScript = load("res://autoload/game_db.gd")
		var db: Object = script.new()
		_fallback_weapons = db._load_table(script.TABLES["weapons"],
			script.WEAPON_SCHEMA, script.WEAPON_OPTIONAL)
	return _fallback_weapons
