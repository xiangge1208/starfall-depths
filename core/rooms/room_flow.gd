class_name RoomFlow
extends RefCounted
## 房间波次状态机（可无头测试）。RoomCombat 场景层消费它的事件。
##
## 语义按 brief 测试对齐（brief 注：pending_spawns 语义=还需刷的数量，实现者按测试语义对齐）：
## pending_spawns = 当前波总怪数（刷怪在波开始即由场景层完成，pending 即"本波还需击杀数"；
## 波开始时为满员，全灭后进下一波回满）。notify_killed 由场景层经 EventBus.enemy_killed 桥接。

var locked := false
var cleared := false
var rewards := {}
var _waves: Array = []
var _wave := -1
var _alive: Array[String] = []

func setup(cfg: Dictionary) -> void:
	_waves = cfg.get("waves", [])
	rewards = {
		"coins": int(cfg.get("coins", 30)),
		"energy_orbs": int(cfg.get("energy_orbs", 4)),
		"hearts": int(cfg.get("hearts", 0)),
	}

func on_entered(_frame: int) -> void:
	locked = true
	_advance_wave()

func pending_spawns() -> int:
	return 0 if _wave < 0 or _wave >= _waves.size() else (_waves[_wave] as Array).size()

func current_wave_ids() -> Array:
	return [] if _wave < 0 or _wave >= _waves.size() else _waves[_wave]

## 当前波索引（-1 = 未进入；≥ waves.size() = 已清房）。HUD/遥测展示用。
func wave_index() -> int:
	return _wave

func notify_killed(id: String, _frame: int) -> void:
	if cleared:
		return
	_alive.erase(id)                      # 按 id 精确移除（brief 原文 pop_back 的超集正确形态）
	if _alive.is_empty():
		_advance_wave()

func _advance_wave() -> void:
	_wave += 1
	_alive.clear()
	if _wave >= _waves.size():
		locked = false
		cleared = true
		return
	_alive.assign((current_wave_ids() as Array).map(func(s): return String(s)))
