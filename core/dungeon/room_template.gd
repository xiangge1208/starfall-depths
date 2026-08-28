class_name RoomTemplate
extends RefCounted
## A1 房间模板只读访问器：数据全部在 GameDB.rooms（autoload 启动时加载并经
## ROOM_SCHEMA + validate_room_row 双重校验，坏行 fail-closed 不会入库）。

## 按 id 取模板行；不存在返回空 Dictionary。
## 注：命名用 get_room 而非 get——Godot 4.7 将遮蔽原生 Object.get 的方法
## （NATIVE_METHOD_OVERRIDE）按错误处理，static func get 无法编译。
static func get_room(id: String) -> Dictionary:
	return GameDB.rooms.get(id, {})

## 指定层的战斗房模板 id 列表（按命名约定 combat_a<floor_idx>_NN，字典序稳定）。
static func combat_ids(floor_idx: int = 1) -> Array[String]:
	var out: Array[String] = []
	var prefix := "combat_a%d_" % floor_idx
	for id: String in GameDB.rooms:
		if id.begins_with(prefix):
			out.append(id)
	out.sort()
	return out
