class_name BalanceBotDecisions
extends RefCounted
## Balance Bot 决策纯逻辑（m2 计划 Task 27 / H-1，卡号 m2-t28）。
##
## 无场景依赖的确定性决策函数集：机器人每拍把世界观测注入（位置/房界/
## 敌弹/敌人/hazard 域/玩家面板/三选一名录），换取行为决策。全部随机性以
## 「采样值」显式入参（roll_sample / panic_sample / wander_sign），同输入必同
## 输出——tests/unit/test_balance_bot_decisions.gd 钉死契约，10 局回归因此可复现。
##
## 本文件常量是「bot 手感」（只影响 bot 行为，不影响游戏规则/数值）；游戏数值
## 一律留在生产侧（tools/balance_bot.gd 只经生产接口操作，见其头注释披露）。

# ---------------- 走位（避弹 / 避 hazard / 近敌拉开 / 距离带） ----------------
const DODGE_RADIUS_PX := 132.0       # 敌弹感知半径（ proactive：弹速 ~200px/s 下留 ≥0.6s 反应窗）
const DODGE_WEIGHT := 2.0            # 弹幕斥力缩放（线性衰减权重）
const DODGE_APPROACH_DOT := 0.2      # 弹速与「弹→我」向量的点积阈值（≥ 视为在远离）
const JUKE_WEIGHT := 0.7             # 威胁下切向游走分量（有威胁不站桩——横向 juke 拉弹道）
const MELEE_GAP_PX := 80.0           # 近敌拉开距离
const MELEE_RETREAT_W := 1.6         # 近敌退避主分量
const MELEE_TANGENT_W := 0.9         # 切向绕走分量（纯背退会被墙/追兵夹死）
const RANGED_BAND_MIN_PX := 72.0     # 理想距离带下沿（无弹幕威胁时维持）
const RANGED_BAND_MAX_PX := 132.0    # 理想距离带上沿
const ORBIT_WEIGHT := 0.9            # 带内环绕分量（站桩 = 追踪者白给；持续横移拉扯）
const HAZARD_AVOID_PX := 24.0        # hazard 域（地刺/岩浆/间歇泉）排斥起距
const HAZARD_WEIGHT := 1.2           # hazard 斥力权重（固定值——不像弹幕随距离衰减：
                                     # 踩域伤害是确定的，规避意志不因远近打折）

# ---------------- 自爆虫引信（armed bomber；观测侧只传自爆型敌人） ----------------
const BOMBER_FLEE_MARGIN_PX := 16.0  # 爆炸域外扩余量（走位逃离触发域 = radius + margin）
const BOMBER_FLEE_WEIGHT := 2.4      # 爆炸域斥力（固定强权重——到点必炸，不随距离打折）
const BOMBER_ROLL_MARGIN_PX := 8.0   # 翻滚触发：炸圈边缘再外扩 8px（bomber_d = 距离-半径）
const BOMBER_KEEPAWAY_MARGIN_PX := 84.0  # 未点燃保距域外扩（半径40+16+84=140px 外即开火
                                         # 优先——玩家移速 80 低于自爆虫 95，跑不掉只能早杀）
const BOMBER_KEEPAWAY_WEIGHT := 1.6  # 未点燃保距斥力（压过距离带趋近 1.0——忌贴脸引信）
const BOMBER_ROLL_PROB := 0.9        # 爆炸临身翻滚概率（到点必炸的确定 AoE，近满概率）
const WALL_AVOID_PX := 20.0          # 软避墙带（贴墙风筝即挨打）
const WALL_AVOID_W := 0.8            # 软避墙分量（弱于出界强拉回，压过微弱漂移）

# ---------------- 翻滚（概率触发，受玩家翻滚 CD 自然限频） ----------------
const ROLL_RADIUS_PX := 28.0         # 贴弹触发半径（省 CD——翻滚优先留给确定性大伤：
                                     # 自爆 AoE / 冲锋；普通弹多数靠走位已能甩掉）
const ROLL_PROB := 0.5               # 贴弹拍翻滚概率
const PANIC_ROLL_PX := 34.0          # 近战贴脸 panic 半径
const PANIC_ROLL_PROB := 0.4         # 近战 panic 翻滚概率

# ---------------- 商店（买药） ----------------
const SHOP_HEAL_GAP := 2             # 缺 ≥2 HP 才买红心（红心回 2，缺 1 买则溢出）

# ---------------- 三选一（buff 贪心评分） ----------------
const RARITY_SCORE := {"common": 1.0, "uncommon": 2.0, "rare": 3.0, "epic": 4.0, "legend": 5.0}
const HEAL_WEIGHT_HURT := 3.0        # 缺血 ≥2 时 hp_max 生存权重（压过 rare 输出键）
const HEAL_WEIGHT_FULL := 0.8        # 满血时 hp_max 权重（近乎溢出，仍略优先于同级白板）
const SHIELD_WEIGHT := 1.0
const OFFENSE_WEIGHT := 0.5
const PHOENIX_WEIGHT := 1.2
const OFFENSE_EFFECT_KEYS := ["atk_speed_pct", "extra_projectiles", "crit_pct",
	"crit_dmg_pct", "dmg_flat", "bullet_speed_pct"]


## 战斗走位方向（返回未归一化的「意图向量」，调用方 8 向量化后经 Input 注入）。
## bullets: [{pos: Vector2, vel: Vector2}]；enemies: [Vector2]（brain_pos）；
## hazard_zones: [Rect2]（世界坐标判定域）；bounds: 已收缩的可玩内域；
## bombers: [{pos: Vector2, radius: float, armed: bool}]（自爆型敌人；armed=引信
## 已点燃——未点燃走温和保距，点燃走强逃，缺省 armed=true）。
## 优先级：出界强拉回 > 弹幕斥力 > 爆炸域斥力 > hazard 斥力 > 近敌拉开 > 距离带维持
## > 软避墙（贴墙带内向分量）。
static func combat_move_dir(pos: Vector2, bounds: Rect2,
		bullets: Array, enemies: Array, hazard_zones: Array,
		wander_sign: float, bombers: Array = []) -> Vector2:
	var dir := Vector2.ZERO

	# 1) 弹幕斥力：只躲正在逼近的弹（距离越近权重越大，线性衰减）+ 切向 juke。
	var has_threat := false
	var juke_perp := Vector2.ZERO
	var nearest_threat_d := INF
	for b in bullets:
		var to: Vector2 = b["pos"] - pos
		var d := to.length()
		if d > DODGE_RADIUS_PX or d < 1.0:
			continue
		var vel: Vector2 = b["vel"]
		if vel.length() > 1.0 \
				and to.normalized().dot(vel.normalized()) >= DODGE_APPROACH_DOT:
			continue                      # 弹在远离/擦肩：不追着躲
		has_threat = true
		dir -= to.normalized() * ((1.0 - d / DODGE_RADIUS_PX) * DODGE_WEIGHT)
		if d < nearest_threat_d:          # 最近逼近弹的左垂直 → 横向 juke 拉弹道
			nearest_threat_d = d
			juke_perp = Vector2(-to.y, to.x) / d
	if has_threat and juke_perp != Vector2.ZERO:
		dir += juke_perp * (JUKE_WEIGHT * wander_sign)

	# 2) 自爆虫：引信已点燃 → 爆炸域+余量固定强权重的逃离；
	#    未点燃 → 保距域温和斥力（不主动贴近引信范围即可）。
	for b in bombers:
		var away_b: Vector2 = pos - (b["pos"] as Vector2)
		var radius := float(b.get("radius", 40.0))
		var db := away_b.length()
		if bool(b.get("armed", true)):
			if db < radius + BOMBER_FLEE_MARGIN_PX and db > 0.1:
				dir += away_b.normalized() * BOMBER_FLEE_WEIGHT
		else:
			if db < radius + BOMBER_FLEE_MARGIN_PX + BOMBER_KEEPAWAY_MARGIN_PX \
					and db > 0.1:
				dir += away_b.normalized() * BOMBER_KEEPAWAY_WEIGHT

	# 2) hazard 域斥力（地刺/岩浆/间歇泉/藤蔓）：域最近点方向的固定权重。
	for zone: Rect2 in hazard_zones:
		var closest := Vector2(
			clampf(pos.x, zone.position.x, zone.end.x),
			clampf(pos.y, zone.position.y, zone.end.y))
		var away := pos - closest
		var dz := away.length()
		if dz < 1.0:
			away = pos - zone.get_center()          # 域内：从域心推出
			dz = maxf(away.length(), 1.0)
		if dz < HAZARD_AVOID_PX:
			dir += away.normalized() * HAZARD_WEIGHT

	# 3) 敌人相对位：近敌拉开（退避+切向）；带内环绕走位；带外趋近/拉开。
	if not enemies.is_empty():
		var nearest_d := INF
		var nearest := Vector2.ZERO
		for e: Vector2 in enemies:
			var de: float = e.distance_to(pos)
			if de < nearest_d:
				nearest_d = de
				nearest = e
		var away_e := (pos - nearest) / maxf(nearest_d, 1.0)
		if nearest_d < MELEE_GAP_PX:
			var tangent := Vector2(-away_e.y, away_e.x)   # 显式左垂直（不依赖 orthogonal 方向约定）
			dir += away_e * MELEE_RETREAT_W + tangent * (MELEE_TANGENT_W * wander_sign)
		elif not has_threat:
			var orbit := Vector2(-away_e.y, away_e.x) * (ORBIT_WEIGHT * wander_sign)
			if nearest_d < RANGED_BAND_MIN_PX:
				dir += away_e
			elif nearest_d > RANGED_BAND_MAX_PX:
				dir -= away_e
			dir += orbit                     # 带内/带外调整都叠加环绕（永不停步）

	# 4) 软避墙：贴墙带内先离墙（风筝被逼到墙角 = 挨打面最大化；硬拉回见 5）。
	if pos.x - bounds.position.x < WALL_AVOID_PX:
		dir.x += WALL_AVOID_W
	elif bounds.end.x - pos.x < WALL_AVOID_PX:
		dir.x -= WALL_AVOID_W
	if pos.y - bounds.position.y < WALL_AVOID_PX:
		dir.y += WALL_AVOID_W
	elif bounds.end.y - pos.y < WALL_AVOID_PX:
		dir.y -= WALL_AVOID_W

	# 5) 出界拉回（近墙时该轴强制至少 1.0，压过其它分量——卡墙即挨打）。
	if pos.x < bounds.position.x:
		dir.x = maxf(dir.x, 1.0)
	elif pos.x > bounds.end.x:
		dir.x = minf(dir.x, -1.0)
	if pos.y < bounds.position.y:
		dir.y = maxf(dir.y, 1.0)
	elif pos.y > bounds.end.y:
		dir.y = minf(dir.y, -1.0)
	return dir


## 翻滚决策。ctx 键（全部显式注入，无隐藏随机）：
##   roll_ready      生产 roll_ready_at(f) 守卫值
##   bullet_d / bullet_away    最近敌弹距离与远离方向（无弹 d=INF）
##   bomber_d / bomber_away    最近已点燃自爆虫「距离-爆炸半径」（负=炸圈内）与远离方向
##   charge_perp     冲锋怪前摇侧闪方向（Vector2.ZERO = 无读到的冲锋）
##   melee_d / melee_away      最近近战敌距离与远离方向
##   roll_sample / panic_sample / side_sample   本拍随机采样（调用方 rng 掷出）
## 优先级：贴弹 > 爆炸临身 > 冲锋临身 > 近战贴脸 panic。返回 {do: bool, dir: Vector2}。
static func roll_decision(ctx: Dictionary) -> Dictionary:
	if not bool(ctx.get("roll_ready", false)):
		return {"do": false, "dir": Vector2.ZERO}
	var roll_sample := float(ctx.get("roll_sample", 0.0))
	var side_sign := 1.0 if float(ctx.get("side_sample", 0.5)) < 0.5 else -1.0
	var bullet_d := float(ctx.get("bullet_d", INF))
	if bullet_d < ROLL_RADIUS_PX and roll_sample < ROLL_PROB:
		return {"do": true, "dir": (ctx.get("bullet_away") as Vector2).normalized()}
	var bomber_d := float(ctx.get("bomber_d", INF))
	if bomber_d < BOMBER_ROLL_MARGIN_PX and roll_sample < BOMBER_ROLL_PROB:
		return {"do": true, "dir": (ctx.get("bomber_away") as Vector2).normalized()}
	var charge_perp: Vector2 = ctx.get("charge_perp", Vector2.ZERO)
	if charge_perp != Vector2.ZERO and roll_sample < ROLL_PROB:
		return {"do": true, "dir": charge_perp.normalized() * side_sign}
	var melee_d := float(ctx.get("melee_d", INF))
	if melee_d < PANIC_ROLL_PX \
			and float(ctx.get("panic_sample", 1.0)) < PANIC_ROLL_PROB:
		return {"do": true, "dir": (ctx.get("melee_away") as Vector2).normalized()}
	return {"do": false, "dir": Vector2.ZERO}


## 商店买红心决策：未售罄 + 缺 ≥2 HP（红心回 2，缺 1 买则溢出）+ 买得起。
## price 为红心价（Shop.ITEM_PRICES.heart = 25）；扣款走生产 RunState.spend_coins。
static func buy_heart(hp: int, hp_max: int, coins: int, price: int, sold: bool) -> bool:
	if sold:
		return false
	if hp > hp_max - SHOP_HEAL_GAP:
		return false
	return coins >= price


## 三选一贪心：生存（缺血时 hp_max/复活）> 稀有度 > 输出键。
## rows: id -> {rarity: String, effects: Dictionary}（GameDB.get_buff 行）。
## 平分取先出现者（确定性；未知效果键退化为纯稀有度排序）。
static func greedy_pick(offered: Array, rows: Dictionary, hp_missing: int) -> String:
	var best := ""
	var best_score := -INF
	for id in offered:
		var row: Dictionary = rows.get(String(id), {})
		var effects: Dictionary = row.get("effects", {})
		var score := float(RARITY_SCORE.get(String(row.get("rarity", "common")), 1.0))
		if effects.has("hp_max"):
			score += HEAL_WEIGHT_HURT if hp_missing >= 2 else HEAL_WEIGHT_FULL
		if effects.has("shield_max"):
			score += SHIELD_WEIGHT
		if effects.has("phoenix_flag"):
			score += PHOENIX_WEIGHT
		for k in OFFENSE_EFFECT_KEYS:
			if effects.has(k):
				score += OFFENSE_WEIGHT
				break
		if score > best_score:
			best_score = score
			best = String(id)
	return best


# ---------------- 校准点① helper：炮台周期/DPS（turret.gd 循环语义的镜像） ----------------

## 炮台稳态循环口径（core/enemies/archetypes/turret.gd 逐帧语义）：
##   idle → windup(windup_ticks) → 齐射（fan/laser 一次性；连发 = burst_count 发，
##   间隔 burst_interval_ticks-1 拍）→ cool(cd_ticks - windup_ticks) → windup …
## 故稳态周期 = cd_ticks + 连发尾拍；首发延迟 = windup_ticks。
## 返回 {cycle_ticks, shots_per_cycle, first_shot_ticks, sustained_dps}。
## （DPS 口径 = 每周期弹丸总伤 ×60 / 周期拍数；实际命中率取决于玩家走位。）
static func turret_cycle_dps(row: Dictionary) -> Dictionary:
	var cd := maxi(int(row.get("cd_ticks", 150)), int(row.get("windup_ticks", 30)))
	var windup := int(row.get("windup_ticks", 30))
	var fan := int(row.get("fan_count", 0))
	var shots: int
	var volley_ticks := 0
	if fan > 1:
		shots = fan                                   # 扇形齐射：一次性，不占周期
	else:
		shots = maxi(int(row.get("burst_count", 1)), 1)
		var gap := maxi(int(row.get("burst_interval_ticks", 6)) - 1, 0)
		volley_ticks = (shots - 1) * gap              # 首发在 windup 到点拍即出
	var cycle := cd + volley_ticks
	var dmg := int(row.get("bullet_dmg", 4))
	var dps := float(shots * dmg) * 60.0 / float(cycle)
	return {
		"cycle_ticks": cycle,
		"shots_per_cycle": shots,
		"first_shot_ticks": windup,
		"sustained_dps": snappedf(dps, 0.01),
	}
