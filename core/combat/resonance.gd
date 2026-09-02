class_name Resonance
## 共鸣表（GDD §7.3）：火+冰=淬爆 / 火+毒=燎原 / 冰+电=超导 / 毒+电=电解
enum R { NONE, SHATTER, BLAZE, SUPERCONDUCT, ELECTROLYSIS }
const TABLE := {"1_2": R.SHATTER, "1_3": R.BLAZE, "2_4": R.SUPERCONDUCT, "3_4": R.ELECTROLYSIS}
const ELEMENT_ORDER: Array[int] = [Elements.Id.FIRE, Elements.Id.ICE, Elements.Id.POISON, Elements.Id.SHOCK]

static func resolve(a: int, b: int) -> int:
	if a == b or a == Elements.Id.NONE or b == Elements.Id.NONE:
		return R.NONE
	return TABLE.get("%d_%d" % [mini(a, b), maxi(a, b)], R.NONE)

## 为强制共鸣选择稳定搭档：优先命中元素，其次按元素固定顺序。
static func compatible_partner(element: int, preferred: int = Elements.Id.NONE) -> int:
	if resolve(element, preferred) != R.NONE:
		return preferred
	for candidate: int in ELEMENT_ORDER:
		if resolve(element, candidate) != R.NONE:
			return candidate
	return Elements.Id.NONE


## m4-c3 resonance_amp 消费端读数（buff_resonance_radius_pct / resonance_duration_ticks，
## WeaponRig buff_* meta 绝对值，CombatSystem 共鸣结算路径读取）：共鸣 AoE 半径按
## (1+pct) 缩放、持续加算 ticks（行值 60 = +1s）。负值/零 clamp 恒等回落基线
## （无增益/非法值零漂移）。static 纯函数直测。
static func radius_px(base_px: float, radius_pct: float) -> float:
	return base_px * (1.0 + maxf(radius_pct, 0.0))


static func duration_ticks(base_ticks: int, bonus_ticks: int) -> int:
	return base_ticks + maxi(bonus_ticks, 0)
