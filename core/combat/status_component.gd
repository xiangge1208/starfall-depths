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
var _stacks: Dictionary = {}         # element -> float progress（状态积累倍率可产生小数进度）
var _dot_next: Dictionary = {}         # element -> next dot frame
var last_damage := 0
var _superconduct_until := -1
var _superconduct_bonus := 0.0
enum Effect { NONE, SHOCK }
var effect_event: Dictionary = {}
var _ice_slow_until := -1
var _freeze_until := -1

func setup(stacks := 2, boss := false) -> void:
	stacks_to_trigger = stacks
	is_boss = boss
	active.clear()
	resonance_event.clear()
	effect_event.clear()
	_stacks.clear()
	_dot_next.clear()
	resonance_icd_until = -1
	_superconduct_until = -1
	_superconduct_bonus = 0.0
	_ice_slow_until = -1
	_freeze_until = -1
	last_damage = 0

func apply_hit(element: int, damage: int, now: int) -> void:
	apply_hit_scaled(element, damage, now, 1.0)

## 状态积累倍率：一次命中默认推进 1 层；状态侵蚀/饮料可推进 >1 的小数进度。
## 若一次命中跨过多个阈值，只触发一次状态并保留余数，避免同拍重复共鸣事件被覆盖。
func apply_hit_scaled(element: int, damage: int, now: int, stack_gain: float) -> void:
	if element == Elements.Id.NONE:
		return
	last_damage = damage
	_stacks[element] = float(_stacks.get(element, 0.0)) + maxf(stack_gain, 0.0)
	if float(_stacks[element]) >= float(stacks_to_trigger):
		_stacks[element] = float(_stacks[element]) - float(stacks_to_trigger)
		_trigger(element, now)

## 统一的远程/近战命中元素契约：一次伤害可同时携带武器主元素和一条 Buff proc。
## 伤害只在 EnemyBase/BossBase 结算一次；这里仅分别推进状态积累。
func apply_hit_context(ctx: Dictionary, damage: int, now: int) -> void:
	if damage <= 0:
		return
	var stack_gain := float(ctx.get("status_rate_mult", 1.0))
	var primary := int(ctx.get("element", Elements.Id.NONE))
	var proc := int(ctx.get("proc_element", Elements.Id.NONE))
	apply_hit_scaled(primary, damage, now, stack_gain)
	if proc != Elements.Id.NONE:
		apply_hit_scaled(proc, damage, now, stack_gain)
	if bool(ctx.get("force_resonance", false)):
		force_resonance(proc if proc != Elements.Id.NONE else primary, damage, now)

func _trigger(element: int, now: int) -> void:
	match element:
		Elements.Id.FIRE:
			active[element] = now + TimeConst.ticks(3.0)
			_dot_next[element] = now + TimeConst.ticks(0.5)
		Elements.Id.ICE:
			active[element] = now + TimeConst.ticks(2.0)
			_ice_slow_until = now + TimeConst.ticks(2.0)
			if not is_boss:
				_freeze_until = now + TimeConst.ticks(1.0)
		Elements.Id.POISON:
			active[element] = now + TimeConst.ticks(5.0)
			_dot_next[element] = now + TimeConst.ticks(1.0)
		Elements.Id.SHOCK:
			active[element] = now + TimeConst.ticks(0.4)
			effect_event = {"effect": Effect.SHOCK, "until": now + TimeConst.ticks(0.4)}
	# 纯逻辑测试无宿主：get_parent() 为 null 时按约定发 null 目标（信号允许）。
	EventBus.status_applied.emit(get_parent(), element)
	_try_resonance(element, now)

func _try_resonance(new_element: int, now: int) -> void:
	if not active.has(new_element):
		return
	if now < resonance_icd_until:
		return
	for other: int in Resonance.ELEMENT_ORDER:
		if not active.has(other):
			continue
		if other == new_element:
			continue
		var reaction := Resonance.resolve(other, new_element)
		if reaction == Resonance.R.NONE:
			continue
		resonance_icd_until = now + TimeConst.ticks(2.0)
		_clear_active_element(other)
		_clear_active_element(new_element)
		resonance_event = {"reaction": reaction, "last_damage": last_damage}
		return

## 暴击强制共鸣：目标至少已有一个已激活异常且未处于 ICD 时，立即以确定性搭档结算。
## preferred_element 优先作为第二元素；若不兼容则按 Resonance.ELEMENT_ORDER 选第一个兼容搭档。
func force_resonance(preferred_element: int, damage: int, now: int) -> bool:
	if now < resonance_icd_until or active.is_empty():
		return false
	last_damage = damage
	# 若目标真实持有两种可共鸣状态，先结算真实组合；命中元素只在缺少第二状态时用于合成。
	for first: int in Resonance.ELEMENT_ORDER:
		if not active.has(first):
			continue
		for second: int in Resonance.ELEMENT_ORDER:
			if second == first or not active.has(second):
				continue
			var actual_reaction := Resonance.resolve(first, second)
			if actual_reaction == Resonance.R.NONE:
				continue
			_resolve_forced(first, second, actual_reaction, now)
			return true
	for first: int in Resonance.ELEMENT_ORDER:
		if not active.has(first):
			continue
		var second := Resonance.compatible_partner(first, preferred_element)
		if second == Elements.Id.NONE:
			continue
		var reaction := Resonance.resolve(first, second)
		if reaction == Resonance.R.NONE:
			continue
		_resolve_forced(first, second, reaction, now)
		return true
	return false

func _resolve_forced(first: int, second: int, reaction: int, now: int) -> void:
	resonance_icd_until = now + TimeConst.ticks(2.0)
	_clear_active_element(first)
	_clear_active_element(second)       # 合成搭档不存在时清理是安全空操作
	resonance_event = {"reaction": reaction, "last_damage": last_damage, "forced": true}

func _clear_active_element(element: int) -> void:
	active.erase(element)
	_dot_next.erase(element)
	if element == Elements.Id.ICE:
		_ice_slow_until = -1
		_freeze_until = -1

func tick(now: int) -> int:
	var dmg := 0
	for element: int in active.keys():
		# 先结算 DoT 再判过期：3s 燃烧的第 6 跳（0.5,1.0,...,3.0s）必须落地
		if element == Elements.Id.FIRE or element == Elements.Id.POISON:
			while now >= int(_dot_next.get(element, 0)) and int(_dot_next[element]) <= int(active[element]):
				dmg += 1
				var interval := TimeConst.ticks(0.5) if element == Elements.Id.FIRE else TimeConst.ticks(1.0)
				_dot_next[element] = int(_dot_next[element]) + interval
		if now >= int(active[element]):
			active.erase(element)
	if _superconduct_until > 0 and now >= _superconduct_until:
		_superconduct_until = -1
	return dmg

func apply_superconduct(bonus: float, duration_ticks: int, now: int) -> void:
	_superconduct_bonus = bonus
	_superconduct_until = now + duration_ticks

func damage_multiplier(now: int = -1) -> float:
	if _superconduct_until <= 0:
		return 1.0
	if now >= 0 and now >= _superconduct_until:
		return 1.0
	return 1.0 + _superconduct_bonus

func is_frozen(now: int) -> bool:
	return not is_boss and now < _freeze_until

func action_speed_multiplier(now: int) -> float:
	return 0.7 if now < _ice_slow_until else 1.0

func consume_effect_event() -> Dictionary:
	var out := effect_event
	effect_event = {}
	return out
