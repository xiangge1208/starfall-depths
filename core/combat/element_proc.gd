class_name ElementProc
## 命中型元素 Buff 的唯一掷签契约。
##
## - 调用方只在已经确认一次有效命中后调用 roll_element；
## - 没有附魔或概率为 0 时绝不消费 RNG；
## - 边界严格为 roll < chance（roll == chance 不触发）；
## - RNG 必须由房间装配注入（RunState 分盐流），本类不创建随机源。

static func succeeds(roll: float, chance: float) -> bool:
	return chance > 0.0 and roll < chance


static func roll_element(element: int, chance: float, rng: RandomNumberGenerator) -> int:
	if element == Elements.Id.NONE or chance <= 0.0 or rng == null:
		return Elements.Id.NONE
	return element if succeeds(rng.randf(), chance) else Elements.Id.NONE


static func roll_chance(chance: float, rng: RandomNumberGenerator) -> bool:
	if chance <= 0.0 or rng == null:
		return false
	return succeeds(rng.randf(), chance)
