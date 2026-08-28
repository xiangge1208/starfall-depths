extends Node
## 数据库：加载 res://data/*.json（m0-t2 起有真实数据）。当前为可运行空壳。
var weapons: Dictionary = {}

func get_weapon(id: String) -> Dictionary:
	return weapons.get(id, {})
