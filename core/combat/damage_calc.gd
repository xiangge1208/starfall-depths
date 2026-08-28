class_name DamageCalc
## 固定伤害 + 暴击唯一随机（GDD §7.1）

static func compute(base: int, rng: RandomNumberGenerator, crit_chance: float, crit_mult: float = 2.0, global_mult: float = 1.0) -> Dictionary:
	var is_crit := rng.randf() < crit_chance
	var amount := int(floor(float(base) * global_mult * (crit_mult if is_crit else 1.0)))
	return {"amount": maxi(1, amount), "is_crit": is_crit}
