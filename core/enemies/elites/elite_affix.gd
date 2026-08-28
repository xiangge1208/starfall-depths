class_name EliteAffix
extends RefCounted
## 精英词缀（设计 §12.3：A2 起 1 词缀、A3 可 2；小 Boss 固定 2 词缀）。
## apply(elite, affix_id) 把词缀落到敌人本体/行数据；行内 elite_affixes 由 EnemyBase.setup
## 末尾统一应用。全部数值常量集中于此，便于 TDD 数值断言与后续调参。

const AFFIXES := ["swift", "armored", "splitter", "leech", "barrage", "berserk"]

const SWIFT_SPEED_MULT := 1.3    # 迅捷：速度 ×1.3（行内全部速度键）
const ARMORED_HP_MULT := 3       # 坚甲：hp 与 hp_max ×3（+200% HP）

## 词缀应用入口。enemy 可能已换装原型脚本——成员读写一律经 Object.get/set，
## 落到当前脚本实例（同 EnemyBase.setup 的换装后约定）。
static func apply(enemy: EnemyBase, affix_id: String) -> void:
	match affix_id:
		"swift":
			_apply_swift(enemy)
		"armored":
			enemy.set("hp", int(enemy.get("hp")) * ARMORED_HP_MULT)
			enemy.set("hp_max", int(enemy.get("hp_max")) * ARMORED_HP_MULT)
		"splitter":
			enemy.set("split_on_death", true)
		"leech":
			enemy.set("leech", true)
		"barrage":
			enemy.set("barrage_extra", int(enemy.get("barrage_extra")) + 1)
		"berserk":
			enemy.set("has_berserk", true)   # 门控标记：仅带词缀者在 <50% 血时 berserk_active()（fix1）
		_:
			push_warning("EliteAffix: unknown affix '%s'" % affix_id)

## 迅捷：行内存在的速度键全部 ×1.3（speed / walk_speed / dash_speed）。
## row 可能与 GameDB 缓存共享（房间直接传表行）——先拷贝再改，不污染全局表。
static func _apply_swift(enemy: EnemyBase) -> void:
	var r: Dictionary = (enemy.get("row") as Dictionary).duplicate()
	for key in ["speed", "walk_speed", "dash_speed"]:
		var v: Variant = r.get(key)
		if v != null and (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT):
			r[key] = float(v) * SWIFT_SPEED_MULT
	enemy.set("row", r)
