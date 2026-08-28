class_name StatusComponent
extends Node
## 元素状态与共鸣（GDD §7.3）。纯逻辑：时间全部用注入的物理帧号。
##
## 相对 brief 参考实现的三处修正（verbatim 测试存在硬性矛盾，逐条依据见 task-11-report）：
## 1) extends Node：_trigger 需要调用 get_parent()（纯逻辑测试不在树中 → null，
##    按控制器约定发 null 目标，信号允许）。
## 2) 未达阈值的命中也参与共鸣判定（apply_hit else 分支，候选 = 激活状态 ∪ 已有层数）：
##    test_shatter_resonance_once_with_icd 在 stacks_to_trigger=2 下，火@0+冰@10 各命中
##    1 次即断言淬爆——参考实现“仅阈值触发后才尝试共鸣”不可能通过该测试的断言 1/2。
## 3) 共鸣冷却除按元素对外，另有每目标 2s 总冷却（GDD §7.3 原文“每目标 2s 内部冷却”）：
##    同一测试末段 电@210 不共鸣：燎原(200)只清火/毒，冰的层数在 30 帧仍在，
##    冰+电这对从未共鸣过、按元素对 ICD 拦不住，只能由每目标冷却（200+120=320）拦下。

var stacks_to_trigger := 2
var is_boss := false
var active: Dictionary = {}            # element -> expire_frame
var resonance_event: Dictionary = {}   # {reaction: int, last_damage: int}，读后清空
var _stacks: Dictionary = {}
var _icd_until: Dictionary = {}        # "a_b" -> frame，按元素对独立计（2s = 120 ticks）
var _resonance_cd_until := -1          # 每目标共鸣总冷却（GDD §7.3）
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
	else:
		_try_resonance(element, now)

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
	if now < _resonance_cd_until:
		return
	# 候选快照：激活状态 ∪ 已有积累层数的元素（不在遍历原字典时删键）。
	var candidates := {}
	for k: int in active:
		candidates[k] = true
	for k: int in _stacks:
		if int(_stacks[k]) > 0:
			candidates[k] = true
	for other: int in candidates:
		if other == new_element:
			continue
		var key := "%d_%d" % [mini(other, new_element), maxi(other, new_element)]
		if now < int(_icd_until.get(key, 0)):
			continue
		var reaction := Resonance.resolve(other, new_element)
		if reaction == Resonance.R.NONE:
			continue
		_icd_until[key] = now + TimeConst.ticks(2.0)
		_resonance_cd_until = now + TimeConst.ticks(2.0)
		# 只清参与共鸣的两元素（含其层数/DoT 挂起帧），其余元素不受影响。
		active.erase(other)
		active.erase(new_element)
		_stacks.erase(other)
		_stacks.erase(new_element)
		_dot_next.erase(other)
		_dot_next.erase(new_element)
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
