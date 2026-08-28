class_name Resonance
## 共鸣表（GDD §7.3）：火+冰=淬爆 / 火+毒=燎原 / 冰+电=超导 / 毒+电=电解
enum R { NONE, SHATTER, BLAZE, SUPERCONDUCT, ELECTROLYSIS }
const TABLE := {"1_2": R.SHATTER, "1_3": R.BLAZE, "2_4": R.SUPERCONDUCT, "3_4": R.ELECTROLYSIS}

static func resolve(a: int, b: int) -> int:
	if a == b or a == Elements.Id.NONE or b == Elements.Id.NONE:
		return R.NONE
	return TABLE.get("%d_%d" % [mini(a, b), maxi(a, b)], R.NONE)
