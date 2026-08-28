class_name FloorFlow
extends RefCounted
## 楼层流程状态机（M1-T10 纯逻辑层，无头可测）。FloorScene 场景层消费其判定并驱动
## 门闸/战斗/陈设；本类不触碰场景树/物理/autoload。
##
## 规则（task-10 规格）：
## - start 房开局即「已清 + 当前」；玩家只能站在已清房（或被锁的战斗房）内。
## - 进入未清战斗系房（combat/elite/miniboss/boss）即锁房：is_locked=true 期间全楼层
##   门封死（含来路），战斗流程由场景层跑波次，直至 notify_room_cleared。
## - 房清 → 到相邻房的门开。门开条件（doors_open_between，走廊闸实体镜像此判定）：
##   相邻 且 非锁定期 且 (a 已清 或 b 已清)；boss 走廊另需 miniboss 已清
##   （boss_door_unlocked）且 boss 的邻接侧已清（adjacent-cleared-path）。
## - treasure/shop/event 进门即清（无战斗）并发 room_event（guest UI 数据占位，
##   C 线后续接入）；elite/miniboss/boss 经战斗占位流程清，room_event 同拍发出
##   （T12/T12 后集成卡经此缝接嘉宾）。
## - notify_room_cleared 幂等（房序去重）；adjacent/next_rooms 输出去重且升序稳定。

## 客房事件（treasure/shop/event 的 guest UI 位 + elite/miniboss/boss 的嘉宾集成缝）。
signal room_event(room_type: String, room_id: int)

const INSTANT_CLEAR_TYPES := ["treasure", "shop", "event"]
const COMBAT_TYPES := ["combat", "elite", "miniboss", "boss"]
const GUEST_EVENT_TYPES := ["treasure", "shop", "event", "elite", "miniboss", "boss"]

var current_room := -1
var cleared: Array[int] = []

var _adj: Dictionary = {}      # int id -> Array[int]（去重升序）
var _types: Dictionary = {}    # int id -> String
var _start_id := -1
var _boss_id := -1
var _miniboss_id := -1


## 消费 DungeonBuilder.build 构建体（rooms/corridors/start_room_id/boss_room_id）。
## 走廊为物理邻接权威（无向化）；rooms 键容错 JSON 字符串键（转 int）。
func setup(build: Dictionary) -> void:
	_adj.clear()
	_types.clear()
	cleared.clear()
	_start_id = -1
	_boss_id = -1
	_miniboss_id = -1
	current_room = -1
	var rooms: Dictionary = build.get("rooms", {})
	for id in rooms:
		var i := int(id)
		_types[i] = String((rooms[id] as Dictionary).get("node", {}).get("type", "combat"))
		if not _adj.has(i):
			_adj[i] = []
	for c in build.get("corridors", []):
		var corridor: Dictionary = c
		var a := int(corridor["a"])
		var b := int(corridor["b"])
		_link(a, b)
		_link(b, a)
	_start_id = int(build.get("start_room_id", -1))
	_boss_id = int(build.get("boss_room_id", -1))
	for id in _types:
		if String(_types[id]) == "miniboss":
			_miniboss_id = int(id)
			break
	if _start_id >= 0 and _types.has(_start_id):
		current_room = _start_id
		cleared.append(_start_id)             # 开局：start 已清 + 当前


## 房间进入：合法（相邻 + 门开）返回 true 并推进状态；否则 false 原地不动。
## 未清战斗系房进入后保持未清（=锁）；instant 房当场清并记入 cleared。
func enter_room(id: int) -> bool:
	var target := int(id)
	if target == current_room:
		return true                            # 已在房内：幂等
	if not doors_open_between(current_room, target):
		return false
	current_room = target
	var type := room_type(target)
	if INSTANT_CLEAR_TYPES.has(type) and not cleared.has(target):
		cleared.append(target)
	if GUEST_EVENT_TYPES.has(type):
		room_event.emit(type, target)
	return true


## 房清通知（幂等：重复通知不产生重复房序）。
func notify_room_cleared(id: int) -> void:
	var target := int(id)
	if _types.has(target) and not cleared.has(target):
		cleared.append(target)


## boss 门规则（GDD §9.1 主路径）：miniboss 房已清即解锁；
## 图中无 miniboss（退化构建体）时视作无门禁。
func boss_door_unlocked() -> bool:
	return _miniboss_id < 0 or cleared.has(_miniboss_id)


## 走廊闸判定（无向）：相邻 + 非锁定期 + 至少一侧已清；boss 走廊另需
## miniboss 已清且 boss 邻接侧已清。锁定期（战斗中）全楼封门。
func doors_open_between(a: int, b: int) -> bool:
	if not adjacent(a).has(b):
		return false
	if is_locked():
		return false                           # 战斗中：全楼封门（含来路）
	if a == _boss_id or b == _boss_id:
		if not boss_door_unlocked():
			return false
		var other := b if a == _boss_id else a
		if not cleared.has(other):
			return false                       # adjacent-cleared-path
	return cleared.has(a) or cleared.has(b)


## 当前房的可达邻房（相邻 + 门开），去重升序。
func next_rooms() -> Array[int]:
	var out: Array[int] = []
	for n in adjacent(current_room):
		if doors_open_between(current_room, n):
			out.append(n)
	out.sort()
	return out


## 无向邻房（去重升序）；未知房返回空。
func adjacent(id: int) -> Array[int]:
	var out: Array[int] = []
	if _adj.has(int(id)):
		out.assign(_adj[int(id)])
	return out


## 战斗锁定期：当前房未清（进未清战斗系房后、notify 前）。锁定期全楼封门。
func is_locked() -> bool:
	return current_room >= 0 and not cleared.has(current_room)


func room_type(id: int) -> String:
	return String(_types.get(int(id), ""))


func is_cleared(id: int) -> bool:
	return cleared.has(int(id))


func start_room() -> int:
	return _start_id


func boss_room() -> int:
	return _boss_id


func miniboss_room() -> int:
	return _miniboss_id


func _link(a: int, b: int) -> void:
	if not _adj.has(a):
		_adj[a] = []
	var list: Array[int] = []
	list.assign(_adj[a])
	if not list.has(b):
		list.append(b)
		list.sort()
	_adj[a] = list
