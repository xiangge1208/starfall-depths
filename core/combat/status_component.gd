class_name StatusComponent
extends Node
## 元素状态与共鸣（GDD §7.3）。纯逻辑：时间全部用注入的物理帧号。
##
## 共鸣判定（GDD-strict，fix round 1 按控制器裁决）：
## - 只有已达阈值触发的激活状态参与共鸣：新触发的元素状态 + 场上已有激活状态；
##   未达阈值的层数不触发状态、也不参与共鸣（保护阈值机制：小怪 2 层 / 精英·Boss 4 层）。
## - ICD 为每目标单一 2s 冷却（GDD「每目标 2s 内部冷却」），非按元素对。
## - 共鸣清除参与共鸣的两元素激活状态，并置 resonance_event（读后由消费方清空）。

var stacks_to_trigger := 2
var is_boss := false
var active: Dictionary = {}            # element -> expire_frame
var resonance_event: Dictionary = {}   # {reaction: int, last_damage: int}，读后清空
var resonance_icd_until := -1          # 每目标共鸣 ICD（GDD §7.3：2s = 120 ticks）
var _stacks: Dictionary = {}
var _dot_next: Dictionary = {}         # element -> next dot frame
var last_damage := 0
var _superconduct_until := -1
var _superconduct_bonus := 0.0

func setup(stacks := 2, boss := false) -> void:
	stacks_to_trigger = stacks
	is_boss = boss

func apply_hit(element: int, damage: int, now: int) -> void:
	if element == Elements.Id.NONE:
		return
	last_damage = damage
	_stacks[element] = int(_stacks.get(element, 0)) + 1
	if _stacks[element] >= stacks_to_trigger:
		_stacks[element] = 0
		_trigger(element, now)

func _trigger(element: int, now: int) -> void:
	match element:
		Elements.Id.FIRE:
			active[element] = now + TimeConst.ticks(3.0)
			_dot_next[element] = now + TimeConst.ticks(0.5)
		Elements.Id.ICE:
			active[element] = now + TimeConst.ticks(2.0)
		Elements.Id.POISON:
			active[element] = now + TimeConst.ticks(5.0)
			_dot_next[element] = now + TimeConst.ticks(1.0)
		Elements.Id.SHOCK:
			active[element] = now + TimeConst.ticks(2.0)
	# 纯逻辑测试无宿主：get_parent() 为 null 时按约定发 null 目标（信号允许）。
	EventBus.status_applied.emit(get_parent(), element)
	_try_resonance(element, now)

func _try_resonance(new_element: int, now: int) -> void:
	if not active.has(new_element):
		return
	if now < resonance_icd_until:
		return
	for other: int in active.keys():
		if other == new_element:
			continue
		var reaction := Resonance.resolve(other, new_element)
		if reaction == Resonance.R.NONE:
			continue
		resonance_icd_until = now + TimeConst.ticks(2.0)
		active.erase(other)
		active.erase(new_element)
		resonance_event = {"reaction": reaction, "last_damage": last_damage}
		return

func tick(now: int) -> int:
	var dmg := 0
	for element: int in active.keys():
		# 先结算 DoT 再判过期：3s 燃烧的第 6 跳（0.5,1.0,...,3.0s）必须落地
		if element == Elements.Id.FIRE or element == Elements.Id.POISON:
			if now >= int(_dot_next.get(element, 0)):
				dmg += 1
				var interval := TimeConst.ticks(0.5) if element == Elements.Id.FIRE else TimeConst.ticks(1.0)
				_dot_next[element] = now + interval
		if now >= int(active[element]):
			active.erase(element)
	if _superconduct_until > 0 and now >= _superconduct_until:
		_superconduct_until = -1
	return dmg

func apply_superconduct(bonus: float, duration_ticks: int, now: int) -> void:
	_superconduct_bonus = bonus
	_superconduct_until = now + duration_ticks

func damage_multiplier() -> float:
	return 1.0 + (_superconduct_bonus if _superconduct_until > 0 else 0.0)
