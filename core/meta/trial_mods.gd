class_name TrialMods
extends RefCounted
## 试炼 mods 消费端单点（M3-fix1 / 规格 docs/superpowers/specs/2026-08-30-m3-trial-mode-spec.md §7）：
## data/trials.json mods 白名单 10 键逐一提供唯一读取函数；各系统只经本类消费
## RunState.mods（R-A 单点注入通道），禁止散读 trials.json（分工条款）。
##
## 零漂移契约：普通局 RunState.mods 恒 {}（start_run 复位）→ 本类全部函数返回恒等值，
## 非试炼局行为与现状逐字节一致（tests/unit/test_trial_mods.gd 逐键钉死）。
##
## 键 → 消费系统对照（每键一处系统消费端）：
##   enemy_speed_pct        EnemyBase._physics_process（表现层体速缩放，覆盖走/冲全原型）
##   enemy_attack_speed_pct EnemyBase._windup_ticks / _attack_cooldown_ticks（蓄力+冷却÷倍率）
##   bullet_speed_pct       EnemyBase.enemy_bullet_speed（敌方出弹速度，GDD §7.5 ≤150 封顶，
##                          慢弹等比提速快弹封顶；windup 预警时间不减免）
##   drop_melee_only        ShopLogic.roll_weapon_id / FloorScene._roll_weapon（掉落池过滤近战）
##   energy_cost_mult       WeaponRig.try_fire（开火蓝耗 ceil(蓝耗×倍率)）
##   shop_discount_pct      Shop._haggled_price（商店售价漏斗：武器/道具/饮料）
##   no_hearts              Shop（货架不出红心）+ FloorScene._spawn_pickup（红心掉落位→等值金币）
##   vision_scale           FloorScene._apply_trial_vision（BiomeFx 暗视野，整层；与 A2 叠加取更暗者）
##   elite_bonus_pct        TrialMods.elite_bonus_wave_ids（精英房波次精英数 ×(1+pct%)）
##                          + TrialMods.altar_elite_surge（m4-c4：战斗房祭坛交互分支切精英）
##   force_element          WeaponRig.element_hit_profile（本层一切元素附魔统一转为层元素）

const ENEMY_BULLET_SPEED_CAP_PX := 150.0   # GDD §7.5：敌方弹速上限（bullet_haste 封顶口径）
## no_hearts 红心掉落位等值金币（等值口径：商店红心 25 金币回复 2 HP → 每 HP 12.5，
## 保守向下取整 12；只替换战斗掉落位，商店/事件/饮料机治疗源不受本键影响）
const HEART_DROP_COIN_EQUIV := 12
## force_element 每层元素池（规格 §3 边界：每层从火/冰/毒/电按层种子随机定 1）
const FORCE_ELEMENT_POOL: Array[int] = [
	Elements.Id.FIRE, Elements.Id.ICE, Elements.Id.POISON, Elements.Id.SHOCK,
]

static func _mods() -> Dictionary:
	return RunState.mods

static func _pct(key: String) -> float:
	return float(_mods().get(key, 0.0)) / 100.0

# ---- 1) enemy_speed_pct（敌人提速·移速） ----
## 体速倍率（1.0 = 无因子零漂移）。消费端：EnemyBase._physics_process 速度式乘本值
## ——brain_pos 权威差值速度整体缩放，走行/冲刺/绕行全原型一致生效。
static func enemy_speed_scale() -> float:
	return 1.0 + _pct("enemy_speed_pct")

# ---- 2) enemy_attack_speed_pct（敌人提速·攻速） ----
## 攻速倍率。消费端：EnemyBase._windup_ticks / _attack_cooldown_ticks 把拍数 ÷ 本值
## （攻速 ×1.2 ⇔ 蓄力/冷却拍数 ÷1.2）；狂暴（×0.7）与倍率相乘叠加。
static func enemy_attack_speed_scale() -> float:
	return 1.0 + _pct("enemy_attack_speed_pct")

# ---- 3) bullet_speed_pct（弹速风暴） ----
## 敌方出弹速度：慢弹等比提速、快弹封顶 150px/s（GDD §7.5）；无因子恒等返回（含
## 数据行 >150 的防御：上限只封顶不加成后的值，不倒扣存量快弹）。
## 预警时间不减免：windup 拍数只受 enemy_attack_speed_pct 影响，与本键无关。
static func enemy_bullet_speed_px(base_px: float) -> float:
	var scaled := base_px * (1.0 + _pct("bullet_speed_pct"))
	return maxf(base_px, minf(scaled, ENEMY_BULLET_SPEED_CAP_PX))

# ---- 4) drop_melee_only（近战洗礼） ----
## 武器掉落池过滤 category == "melee"（含宝箱/精英/嘉宾掉落；熔铸材料流不变）。
static func drop_melee_only() -> bool:
	return bool(_mods().get("drop_melee_only", false))

# ---- 5) energy_cost_mult（蓝量重税） ----
## 玩家武器开火蓝耗：ceil(蓝耗 × 倍率)（0 耗武器 ×1.5 仍为 0——规格「向上取整」字面
## 语义）。技能蓝耗不受影响（规格 §3：所有武器蓝耗）。
static func player_energy_cost(base_cost: int) -> int:
	var mult := float(_mods().get("energy_cost_mult", 1.0))
	if mult == 1.0:
		return base_cost
	return int(ceil(float(base_cost) * mult))

# ---- 6) shop_discount_pct（黑心集市·半价） ----
## 商店售价折让比例（0 = 无折扣恒等）。消费端：Shop._haggled_price 统一漏斗。
static func shop_discount_pct() -> float:
	return _pct("shop_discount_pct")

## 试炼折让后售价（武器/道具/饮料统一经 Shop._haggled_price 漏斗调用）：整到 5、
## 下限 5（沿 ShopLogic 议价同口径）。无因子恒等返回原值（零漂移）。
static func shop_price(price_value: int) -> int:
	var pct := _pct("shop_discount_pct")
	if price_value <= 0 or pct <= 0.0:
		return price_value
	return maxi(ShopLogic.RECYCLE_MIN, ShopLogic.round5(float(price_value) * (1.0 - pct)))

# ---- 7) no_hearts（黑心集市·禁红心） ----
## true：商店不出现治疗类商品 + 红心掉落位替换为 HEART_DROP_COIN_EQUIV 等值金币。
static func no_hearts() -> bool:
	return bool(_mods().get("no_hearts", false))

# ---- 8) vision_scale（管中窥豹） ----
## 视野缩放系数（<1 生效；1.0 = 无因子零漂移）。消费端：FloorScene._apply_trial_vision。
static func vision_scale() -> float:
	return float(_mods().get("vision_scale", 1.0))

# ---- 9) elite_bonus_pct（精英潮） ----
## 精英标记波次体的追加体数：pct=100 → 每个精英标记体追加 1 体（×2 同模板双精英）。
## 「哪个 id 是精英标记」归消费端（FloorScene._spawn_wave 持有 GUEST_SPECS，避免
## meta→rooms 反向依赖）；追加体与原体同 wave_id，RoomFlow 按出现次数天然计数。
## 无因子 → 0（消费端零改动）。
static func elite_extra_copies() -> int:
	var pct := _pct("elite_bonus_pct")
	if pct <= 0.0:
		return 0
	return int(round(pct))

## elite_surge 祭坛分支读点（m4-c4）：elite_bonus_pct 因子激活（>0）时，战斗房增益
## 祭坛的交互分支改为「追加 1 精英」（消费端 = Altar.interact）。与 elite_extra_copies
## 同 mods 键单点（trials.json 因子 elite_surge → mods 键 elite_bonus_pct），
## 普通局/无因子恒 false（零漂移）。
static func altar_elite_surge() -> bool:
	return _pct("elite_bonus_pct") > 0.0

# ---- 10) force_element（元素独尊） ----
## 本层强制元素（Elements.Id；NONE = 无因子/非 random 值域）。层元素由
## run_seed+floor_idx 确定性派生（RngSvc.stable_hash，同种子同层恒同元素）。
## 消费端：WeaponRig.element_hit_profile——本层玩家一切元素附魔（武器自带/增益/
## 星髓像）统一转为该元素（proc_chance 语义保留，仅元素身份被统一）。
static func floor_force_element(floor_idx: int) -> int:
	if String(_mods().get("force_element", "")) != "random":
		return Elements.Id.NONE
	var h := RngSvc.stable_hash(RngSvc._salt_hash("force_element"),
		RngSvc._salt_hash("%d|%d" % [RunState.run_seed, floor_idx]))
	return FORCE_ELEMENT_POOL[int(absi(h)) % FORCE_ELEMENT_POOL.size()]
