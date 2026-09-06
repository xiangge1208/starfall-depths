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
##
## m4p-bal-b：武装自爆虫优先瞄准（aim_priority_index——先杀后走）+ 爆炸域逃离
## 去对消（bomber_flee_vector——径向只取最近一只 + 切向机动，多虫夹击不再定身）
## + 翻滚触发余量 8→20。
##
## m4p-bal-c（探针定向迭代卡 C，捕获例归因见提交 body）：
##   ① 大体积距离带——enemies 观测通道加 combat_radius（enemy_radii 平行数组），
##     近敌拉开缺口与距离带沿随半径线性外扩（probe 3493：电磁蛛 speed 80 = 玩家
##     移速，80px 拉开带贴墙收尾 → 接触冲撞死；miniboss 半径 7×1.25、Boss 16）。
##   ② Boss 预告观测——拍击扇形（windup 30t 内可走位躲出）走独立斥力通道
##     boss_zone_repulsion；藤蔓横扫条带几何 456×238 全覆盖 M0 战斗房内域
##     320×192（probe 几何归因：走位无出口侧，条带必中）→ 不进走位通道，改走
##     确定性翻滚通道（boss_band_impact_ticks 当拍锚点+方向外推 → roll_decision
##     命中前 ≤9 拍逆行进向翻滚，i-frame 13t 覆盖穿越窗——同武装自爆虫口径）。
##   ③ 红心目标黏滞 sticky_heart_id（probe 3472-a1 实拍：已清 elite 房双红心分居
##     柱面两侧，逐拍重选使 seek 滑移符号逐拍翻转 → 柱东面 5.5px 极限环）——
##     锁定最近红心 HEART_STICKY_TICKS 拍再评估。

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
const BOMBER_FLEE_TANGENT_W := 1.0   # 逃离切向机动分量（m4p-bal-b 去对消：径向只取最近
                                     # 一只后叠加其左垂直切向——符号随 wander_sign，径向
                                     # 被墙/第二虫顶死时仍保持横移机动）
const BOMBER_ROLL_MARGIN_PX := 20.0  # 翻滚触发：炸圈边缘再外扩 20px（bomber_d = 距离-半径；
                                     # m4p-bal-b 8→20——引信 0.5s 内虫闭近 ~47px，8px 触发
                                     # 几乎必吃爆炸；20px 给翻滚 56px 位移+无敌帧留余量）
const BOMBER_PRIORITY_PX := 240.0    # 优先瞄准距离（m4p-bal-b：武装虫 ≤240px 锁定瞄准——
                                     # 玩家移速 80 低于自爆虫 95 跑不掉只能早杀，
                                     # 见 BOMBER_KEEPAWAY_MARGIN_PX 注释）
const MINION_PRIORITY_PX := 160.0    # m4p-bal-d 二级优先瞄准距离：Boss 在场时会开火小怪
                                     # （蘑菇孢子手等）≤160px 锁定——Boss 战马拉松里减速
                                     # 孢子扇的持续 DPS/减速叠加比 Boss 本体伤更致命，
                                     # 先清炮手再打 Boss（超距回落默认最近）。
const BOMBER_KEEPAWAY_MARGIN_PX := 84.0  # 未点燃保距域外扩（半径40+16+84=140px 外即开火
                                         # 优先——玩家移速 80 低于自爆虫 95，跑不掉只能早杀）
const BOMBER_KEEPAWAY_WEIGHT := 1.6  # 未点燃保距斥力（压过距离带趋近 1.0——忌贴脸引信）
const BOMBER_ROLL_PROB := 0.9        # 爆炸临身翻滚概率（到点必炸的确定 AoE，近满概率）
const WALL_AVOID_PX := 20.0          # 软避墙带（贴墙风筝即挨打）
const WALL_AVOID_W := 0.8            # 软避墙分量（弱于出界强拉回，压过微弱漂移）

# ---------------- m4-b3② shooter 接近带（弩兵等风筝型；m3-fix2 §2.1.3 残差主因） ----------------
const SHOOTER_APPROACH_W := 1.2      # 威胁下向超带 shooter 的趋近主分量（1.2 压过单弹
                                     # 斥力中段的 -0.64 与反向 juke 的 -0.7：8 向量化后
                                     # 趋近轴仍被按下，净距离收敛；近距弹斥力 2.0 级
                                     # 仍优先——躲避优先级不变）

# ---------------- m4p-bal-c① 大体积距离带（probe 3493 归因修法） ----------------
const BIG_BODY_GAP_SCALE_PX := 2.0   # 缺口/带沿的半径缩放系数 k：effective = 基准 +
                                     # combat_radius*k（miniboss 8.75 → 缺口 97.5、
                                     # Boss 16 → 缺口 112；小怪 5~6 → 90~92 轻微外扩）。

# ---------------- m4p-bal-c② Boss 预告域（拍击扇形斥力 + 横扫条带翻滚） ----------------
const BOSS_ZONE_WEIGHT := 1.6        # 拍击扇形域斥力权重（确定性 5 伤大伤，压过距离带
                                     # 趋近 1.0 / 环绕 0.9；hazard 同级量级）
const BOSS_BAND_ROLL_AHEAD_TICKS := 9.0  # 条带命中前 ≤9 拍触发翻滚：i-frame 13t 覆盖
                                         # 穿越窗（逆行进向滚，合拢 12.7+4.3=17px/t，
                                         # 触发距 ~126px → 穿越落第 7 拍，余量充足）
const BOSS_BAND_ROLL_GUARD_TICKS := 64.0 # 条带临身守卫窗（9 阈值 + 翻滚 CD 42 + i-frame
                                         # 13）：窗内抑制贴弹/近战 panic 翻滚——翻滚 CD
                                         # 被 3 伤可躲弹烧掉后，必中 5 伤条带无 CD 可用
                                         #（verify-3483 死例归因：角点 47 弹连滚烧 CD）
const BOSS_BAND_ROLL_PROB := 0.9     # 条带必中（几何全覆盖）→ 近满概率（同 BOMBER_ROLL_PROB）

# ---------------- m4p-bal-c③ 红心目标黏滞（probe 3472-a1 双心抖动极限环修法） ----------------
const HEART_STICKY_TICKS := 90       # 红心目标锁定窗（1.5s）：柱端绕行 ~0.6s 内意图
                                     # 恒定，滑移方向不再被逐拍撤销；窗满再评估。

# ---------------- m4-b3③ 实体斥力场（柱/箱/墙；3271-a3 Seek 楔死柱面实证修法） ----------------
const SOLID_AVOID_PX := 14.0         # 实体面外斥力带宽（玩家 r=6 + 8px 缓冲）
const SOLID_WEIGHT := 1.4            # 垂直离面分量（带宽内线性衰减）
const SOLID_SLIDE_W := 0.7           # 切向滑移分量（纯径向斥力与 Seek 对顶时合力为零
                                     # 仍楔死——滑移保证沿面绕行，符号随 wander_sign 确定）

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
## 已点燃——未点燃走温和保距，点燃走强逃，缺省 armed=true）；
## shooters: [Vector2]（m4-b3② 风筝型射击敌人 brain_pos，弩兵等；威胁下超带趋近）；
## solids: [Rect2]（m4-b3③ 房内实体矩形，世界坐标——柱/箱/墙，同
## FloorScene._room_solid_rects 契约）；
## enemy_radii: [float]（m4p-bal-c① 平行数组，enemies[i] 的 combat_radius；缺项/空
## 数组按 0 处理 = 既有行为零漂移）；
## boss_zones: [Dictionary]（m4p-bal-c② Boss 预告域，现契约 kind="wedge" 拍击扇形，
## 见 boss_zone_repulsion）。
## 优先级：出界强拉回 > 弹幕斥力 > 爆炸域斥力 > hazard 斥力 > 实体斥力场
## > 近敌拉开（半径缩放缺口）> Boss 预告域斥力 > 距离带维持（威胁下超带 shooter 趋近）
## > 软避墙（贴墙带内向分量）。
static func combat_move_dir(pos: Vector2, bounds: Rect2,
		bullets: Array, enemies: Array, hazard_zones: Array,
		wander_sign: float, bombers: Array = [], shooters: Array = [],
		solids: Array = [], enemy_radii: Array = [], boss_zones: Array = []) -> Vector2:
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

	# 2) 自爆虫：引信已点燃 → 爆炸域逃离（m4p-bal-b 去对消：径向只取最近一只
	#    + 切向机动——旧口径对全部武装虫 away 求和，两虫对夹时 ≈0 定身挨炸）；
	#    未点燃 → 保距域温和斥力（求和维持——温和斥力无对消危害）。
	dir += bomber_flee_vector(pos, bombers, wander_sign)
	for b in bombers:
		if bool(b.get("armed", true)):
			continue
		var away_b: Vector2 = pos - (b["pos"] as Vector2)
		var radius := float(b.get("radius", 40.0))
		var db := away_b.length()
		if db < radius + BOMBER_FLEE_MARGIN_PX + BOMBER_KEEPAWAY_MARGIN_PX \
				and db > 0.1:
			dir += away_b.normalized() * BOMBER_KEEPAWAY_WEIGHT

	# 3) hazard 域斥力（地刺/岩浆/间歇泉/藤蔓）：域最近点方向的固定权重。
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

	# 4) m4-b3③ 实体斥力场：带宽内线性离面斥力 + 最近面切向滑移（Seek/走位顶死
	#    柱面时「径向斥力与寻的分量对顶 → 合力为零」的楔死被滑移打破，沿面绕行）。
	#    滑移以「本步之前的意图向量」定向（帮助绕行而非对顶）。
	dir += _solid_repulsion(pos, solids, dir, wander_sign)

	# 5) 敌人相对位：近敌拉开（半径缩放缺口：退避+切向）；带内环绕走位；带外趋近/拉开。
	#    m4p-bal-c① 缺口与带沿随最近敌 combat_radius 线性外扩（BIG_BODY_GAP_SCALE_PX）：
	#    miniboss 半径 7×1.25=8.75、Boss 16（小怪 5~6）——接触冲撞收尾速度随体积上升，
	#    按小怪标定的 80px 缺口 / 72~132 带对大体积失效（probe 3493：电磁蛛 speed 80
	#    = 玩家移速，缺口外恒距逼近贴墙收尾接触死）。半径观测缺项按 0 = 既有行为。
	if not enemies.is_empty():
		var nearest_d := INF
		var nearest := Vector2.ZERO
		var nearest_radius := 0.0
		for i in enemies.size():
			var e: Vector2 = enemies[i]
			var de: float = e.distance_to(pos)
			if de < nearest_d:
				nearest_d = de
				nearest = e
				nearest_radius = float(enemy_radii[i]) if i < enemy_radii.size() else 0.0
		var away_e := (pos - nearest) / maxf(nearest_d, 1.0)
		var gap := MELEE_GAP_PX + nearest_radius * BIG_BODY_GAP_SCALE_PX
		var band_min := RANGED_BAND_MIN_PX + nearest_radius * BIG_BODY_GAP_SCALE_PX
		var band_max := RANGED_BAND_MAX_PX + nearest_radius * BIG_BODY_GAP_SCALE_PX
		if nearest_d < gap:
			var tangent := Vector2(-away_e.y, away_e.x)   # 显式左垂直（不依赖 orthogonal 方向约定）
			dir += away_e * MELEE_RETREAT_W + tangent * (MELEE_TANGENT_W * wander_sign)
		elif not has_threat:
			var orbit := Vector2(-away_e.y, away_e.x) * (ORBIT_WEIGHT * wander_sign)
			if nearest_d < band_min:
				dir += away_e
			elif nearest_d > band_max:
				dir -= away_e
			dir += orbit                     # 带内/带外调整都叠加环绕（永不停步）

	# 5.4) m4p-bal-c② Boss 预告域斥力（拍击扇形：windup 30t 内可走位躲出 70px/90°
	#      扇形；横扫条带为全房覆盖几何不进本通道——规避走翻滚通道，见决策层头注②）。
	dir += boss_zone_repulsion(pos, boss_zones)

	# 5.5) m4-b3② shooter 接近带：威胁下上面整段距离带逻辑被跳过（has_threat 分支），
	#      弩兵等风筝原型把 bot 拖入 150~200px 恒距（fix2 §2.1.3 实证）。超带最近
	#      shooter 给恒定趋近主分量——近距弹斥力（2.0 级）仍优先，中远距净趋近；
	#      距离 ≤ 带上沿即停（不推入对方风筝保距域内应）。
	if has_threat and not shooters.is_empty():
		var ns_d := INF
		var ns_v := Vector2.ZERO
		for s: Vector2 in shooters:
			var d: float = s.distance_to(pos)
			if d < ns_d:
				ns_d = d
				ns_v = s - pos
		if ns_d > RANGED_BAND_MAX_PX and ns_d > 1.0:
			dir += ns_v / ns_d * SHOOTER_APPROACH_W

	# 6) 软避墙：贴墙带内先离墙（风筝被逼到墙角 = 挨打面最大化；硬拉回见 7）。
	if pos.x - bounds.position.x < WALL_AVOID_PX:
		dir.x += WALL_AVOID_W
	elif bounds.end.x - pos.x < WALL_AVOID_PX:
		dir.x -= WALL_AVOID_W
	if pos.y - bounds.position.y < WALL_AVOID_PX:
		dir.y += WALL_AVOID_W
	elif bounds.end.y - pos.y < WALL_AVOID_PX:
		dir.y -= WALL_AVOID_W

	# 7) 出界拉回（近墙时该轴强制至少 1.0，压过其它分量——卡墙即挨打）。
	if pos.x < bounds.position.x:
		dir.x = maxf(dir.x, 1.0)
	elif pos.x > bounds.end.x:
		dir.x = minf(dir.x, -1.0)
	if pos.y < bounds.position.y:
		dir.y = maxf(dir.y, 1.0)
	elif pos.y > bounds.end.y:
		dir.y = minf(dir.y, -1.0)
	return dir


## 武装自爆虫爆炸域逃离向量（m4p-bal-b 去对消；combat_move_dir 第 2 段武装分支）。
## 径向分量只取「已进入爆炸域（radius + BOMBER_FLEE_MARGIN_PX）的最近一只武装虫」
## 的远离方向（固定权重 BOMBER_FLEE_WEIGHT 不变）——旧口径对全部武装虫的 away
## 求和，两虫等距对夹时求和 ≈0 定身挨炸；叠加最近虫的左垂直切向分量
## （BOMBER_FLEE_TANGENT_W，符号随 wander_sign）保持机动不被径向锁死。
## 未点燃 keepaway 温和斥力维持求和（无对消危害），仍在 combat_move_dir 原段处理。
## bombers 契约同 combat_move_dir（{pos: Vector2, radius: float, armed: bool}；
## 缺省 armed=true）。无武装虫进爆炸域 → 零向量（不产生任何分量）。
static func bomber_flee_vector(pos: Vector2, bombers: Array, wander_sign: float) -> Vector2:
	var best_d := INF
	var best_away := Vector2.ZERO
	for b in bombers:
		if not bool(b.get("armed", true)):
			continue
		var away: Vector2 = pos - (b["pos"] as Vector2)
		var db := away.length()
		if db >= float(b.get("radius", 40.0)) + BOMBER_FLEE_MARGIN_PX or db < 0.1:
			continue
		if db < best_d:
			best_d = db
			best_away = away
	if best_d == INF:
		return Vector2.ZERO
	var radial := best_away / maxf(best_d, 0.1)
	var tangent := Vector2(-radial.y, radial.x)   # 显式左垂直（与近敌拉开切向同约定）
	return radial * BOMBER_FLEE_WEIGHT + tangent * (BOMBER_FLEE_TANGENT_W * wander_sign)


## Boss 预告域斥力（m4p-bal-c②；combat_move_dir 第 5.4 段）。zones 元素契约：
## {kind: "wedge", apex: Vector2, facing: float(弧度), range_px: float,
##  half_angle: float(弧度)}——藤蔓巨像 P0 巨掌拍击（SLAP_RANGE 70 / 90° 扇形 /
## windup 30t，bot 侧经 BossBase 节点 get("_move")/get("_slap_facing") 只读观测）。
## 玩家在扇形域内（距离 ≤ range_px 且与 facing 夹角 ≤ half_angle）→ 从 apex 径向
## 推出（固定权重 BOSS_ZONE_WEIGHT）；域外/未知 kind → 零分量。前摇结束拍后 bot
## 不再注入（扇形已结算，规避无意义）。藤蔓横扫条带不进本通道：条带 456×238
## 全覆盖 M0 战斗房内域 320×192（probe 几何归因），走位无出口侧——规避走确定性
## 翻滚通道（boss_band_impact_ticks → roll_decision）。
static func boss_zone_repulsion(pos: Vector2, zones: Array) -> Vector2:
	var out := Vector2.ZERO
	for z in zones:
		if String(z.get("kind", "")) != "wedge":
			continue
		var apex: Vector2 = z["apex"]
		var facing := float(z.get("facing", 0.0))
		var to := pos - apex
		var d := to.length()
		if d < 1.0:
			to = Vector2.from_angle(facing + PI)    # 与 apex 重合：沿背向推出
			d = 1.0
		if d > float(z.get("range_px", 70.0)):
			continue
		if absf(angle_difference(facing, to.angle())) > float(z.get("half_angle", PI * 0.25)):
			continue
		out += to / d * BOSS_ZONE_WEIGHT
	return out


## 藤蔓横扫条带命中时序（m4p-bal-c②；节奏常量镜像 core/enemies/bosses/
## vine_colossus.gd SWEEP_WINDUP_TICKS=42 / SWEEP_TRAVEL_TICKS=36 /
## SWEEP_THICKNESS_PX=24——bot 侧经 BossBase 节点只读 _move/_move_start/
## _sweep_anchor/_sweep_x1_px 生产字段，锚点+方向外推当拍与未来条带位）。
## elapsed_ticks: _move 起始拍差；x0 = _sweep_anchor.x（行进起点）、x1 =
## _sweep_x1_px（行进终点）；windup 段条带静止于 x0，travel 段线性推进。
## 返回条带前缘到达 player_x（半厚 half_thickness 内）的剩余拍数；INF = 本回合
## 不会命中（玩家在行进起点后方 / 条带已越过 / 行进结束未及）。
static func boss_band_impact_ticks(elapsed_ticks: float, player_x: float, x0: float,
		x1: float, windup_ticks: int, travel_ticks: int, half_thickness: float) -> float:
	var span := x1 - x0
	if absf(span) < 0.01 or travel_ticks <= 0:
		return INF
	var dir_sign := signf(span)
	var speed := absf(span) / float(travel_ticks)     # 456px/36t = 12.7px/t（远超玩家滚速）
	var elapsed := maxf(elapsed_ticks, 0.0)
	if elapsed < float(windup_ticks):
		var dist0 := (player_x - x0) * dir_sign
		if dist0 < -half_thickness:
			return INF                        # 玩家在行进起点后方：条带出发即远离
		return float(windup_ticks) - elapsed \
			+ maxf(dist0 - half_thickness, 0.0) / speed
	var progress := minf((elapsed - float(windup_ticks)) / float(travel_ticks), 1.0)
	var center := lerpf(x0, x1, progress)
	var dist := (player_x - center) * dir_sign
	if dist < -half_thickness:
		return INF                            # 条带已越过玩家（单回合单次命中已结算）
	if progress >= 1.0 and dist > half_thickness:
		return INF                            # 行进结束仍未及玩家
	return maxf(dist - half_thickness, 0.0) / speed


## 红心目标黏滞（m4p-bal-c③；probe 3472-a1 双红心意图抖动极限环修法）。
## 形态：已清房双心分居柱面两侧，最近心随玩家滑动在距离曲线交点两侧翻转 →
## seek_with_solids 的滑移符号（signf(切向·intent)）逐拍翻转 → 绕柱方向承诺被
## 逐拍撤销 → 柱面东沿极限环（捕获实拍：pp y∈[954,959.5] 9 唯一位，160s 零拾取）。
## 修法：prev_id 在 HEART_STICKY_TICKS 窗内且候选仍存在 → 维持（意图/滑移方向
## 恒定，绕柱端点 ~0.6s 内收敛）；窗满或失效 → 最近心重锁（严格 <，同距取先
## 出现者，确定性）。candidates: [{id: int, pos: Vector2}]；返回 id（无候选 -1）。
static func sticky_heart_id(prev_id: int, prev_frame: int, candidates: Array,
		pos: Vector2, frame: int, lock_ticks: int) -> int:
	var best_id := -1
	var best_d := INF
	var prev_alive := false
	for c in candidates:
		var id := int(c.get("id", -1))
		var d: float = (c["pos"] as Vector2).distance_to(pos)
		if id == prev_id:
			prev_alive = true
		if d < best_d:
			best_d = d
			best_id = id
	if prev_alive and prev_frame >= 0 and frame - prev_frame < lock_ticks:
		return prev_id
	return best_id


## 优先瞄准下标（m4p-bal-b 先杀后走；_nudge_aim_if_unlocked 瞄准层接线）。
## 一级：存在「武装（引信已点燃，armed 标志）且距离 ≤ BOMBER_PRIORITY_PX」的
## 自爆虫时返回最近一只的下标——玩家移速 80 低于自爆虫 95 跑不掉只能早杀。
## 二级（m4p-bal-d）：无武装虫但「Boss 型敌人在场（boss_flags 有 true）且存在
## 距离 ≤ MINION_PRIORITY_PX 的会开火小怪（minion_flags，如 Boss 房蘑菇孢子手）」
## 时返回最近小怪的下标——bot 旧口径瞄准「最近」（Boss 房内往往是 Boss 本体），
## 减速孢子扇小怪在旁白嫖。两者皆不满足 → -1（调用方走默认最近目标）。
## 多只满足取最近（严格 <，同距取先出现者，确定性）。
## 平行数组契约：bomber_flags/bomber_ds（及可选 boss_flags/minion_flags）与
## enemy_poses 按下标一一对应（bot 侧在同一构建循环里追加，不会错位）；
## bomber_ds 缺项时回落 pos×enemy_poses 几何距离（纯函数容错，不炸）——
## 该数组实为「到每敌距离」平行数组，二级优先复用同一距离源。
## 缺省 boss_flags/minion_flags = 空（既有 4 参调用行为逐字节不变：二级永不触发）。
static func aim_priority_index(pos: Vector2, enemy_poses: Array, bomber_flags: Array,
		bomber_ds: Array, boss_flags: Array = [], minion_flags: Array = []) -> int:
	var best := -1
	var best_d := INF
	for i in mini(enemy_poses.size(), bomber_flags.size()):
		if not bool(bomber_flags[i]):
			continue
		var d := float(bomber_ds[i]) if i < bomber_ds.size() \
				else (enemy_poses[i] as Vector2).distance_to(pos)
		if d > BOMBER_PRIORITY_PX:
			continue
		if d < best_d:
			best_d = d
			best = i
	if best >= 0:
		return best
	var n := mini(mini(enemy_poses.size(), boss_flags.size()), minion_flags.size())
	var has_boss := false
	for i in n:
		if bool(boss_flags[i]):
			has_boss = true
			break
	if not has_boss:
		return -1
	best = -1
	best_d = INF
	for i in n:
		if not bool(minion_flags[i]):
			continue
		var d2 := float(bomber_ds[i]) if i < bomber_ds.size() \
				else (enemy_poses[i] as Vector2).distance_to(pos)
		if d2 > MINION_PRIORITY_PX:
			continue
		if d2 < best_d:
			best_d = d2
			best = i
	return best


## m4-b3③ 实体斥力场内部：rep = 全部带内实体的线性衰减离面分量之和；
## slide = 仅最近实体的切向滑移（方向与 intent 同侧——帮助绕行而非对顶；
## intent 切向投影为 0 时回落 wander_sign）。滑移只取最近面：多面滑移按
## intent 各自对齐后仍会互拍抵消（probe-3230-a2 实证：两枚错切向箱面的
## 对齐滑移相加后垂直分量净剩 0.245 < 8 向 0.35 阈值 → 玩家单轴按压顶死
## 箱面）；单滑移的切向轴分量结构性 ≥ SOLID_SLIDE_W（|b+0.7σ| ≥ 0.7）。
static func _solid_field(pos: Vector2, solids: Array, intent: Vector2,
		wander_sign: float) -> Dictionary:
	var rep := Vector2.ZERO
	var slide := Vector2.ZERO
	var slide_d := INF
	for r: Rect2 in solids:
		var closest := Vector2(
			clampf(pos.x, r.position.x, r.end.x),
			clampf(pos.y, r.position.y, r.end.y))
		var away := pos - closest
		var d := away.length()
		if d >= SOLID_AVOID_PX:
			continue
		if d < 1.0:
			away = pos - r.get_center()
			d = maxf(away.length(), 1.0)
		var n := away / d
		rep += n * (SOLID_WEIGHT * (1.0 - d / SOLID_AVOID_PX))
		if d < slide_d:
			slide_d = d
			var t := Vector2(-n.y, n.x)
			var s := signf(t.dot(intent))
			if s == 0.0:
				s = wander_sign
			slide = t * (SOLID_SLIDE_W * s)
	return {"rep": rep, "slide": slide}


static func _solid_repulsion(pos: Vector2, solids: Array, intent: Vector2,
		wander_sign: float) -> Vector2:
	var f := _solid_field(pos, solids, intent, wander_sign)
	return (f["rep"] as Vector2) + (f["slide"] as Vector2)


## m4-b3③ 寻的向量过实体斥力场（已清房拾取/走位寻的共用；combat_move_dir 内嵌
## 同一场）。seek 允许任意模长（调用方可直传「目标−自身」距离向量），非空 solids
## 时归一为 O(1) 意图向量再加斥力——斥力/滑移分量是 O(1) 量级，未归一的大模长
## seek 会把它们淹没（3230 复跑实证：47px seek 吞掉 ±0.7 滑移 → 8 向量化垂直
## 分量低于 0.35 阈值 → 依旧顶死柱面）。solids 空 / seek 零向量 = 原样直通。
## 死区兜底：合成向量双轴都落入 8 向 0.35 阈值时（径向污染吃掉滑移轴的极端
## 几何），整体退到「最近面滑移方向」——切向轴 ≥0.7 保底运动。
static func seek_with_solids(seek: Vector2, pos: Vector2, solids: Array,
		wander_sign: float) -> Vector2:
	if solids.is_empty() or seek == Vector2.ZERO:
		return seek
	var intent := seek.normalized()
	var f := _solid_field(pos, solids, intent, wander_sign)
	var out := intent + (f["rep"] as Vector2) + (f["slide"] as Vector2)
	if absf(out.x) < 0.35 and absf(out.y) < 0.35:
		out = f["slide"] as Vector2
	return out


## m4-b3① 观测差分速度（bot lead 预判的入参）：帧窗 <2 拍拒收（逐拍抖动噪声）、
## >30 拍拒收（陈旧锚点）——均按「静止目标」处理（lead 退化为直瞄）。
## 返回 px/s。
static func velocity_from_track(prev: Vector2, prev_frame: int, cur: Vector2,
		cur_frame: int) -> Vector2:
	var dt := cur_frame - prev_frame
	if dt < 2 or dt > 30:
		return Vector2.ZERO
	return (cur - prev) * (60.0 / float(dt))


## 翻滚决策。ctx 键（全部显式注入，无隐藏随机）：
##   roll_ready      生产 roll_ready_at(f) 守卫值
##   boss_band_ticks / boss_band_dir  m4p-bal-c②：横扫条带命中剩余拍（INF=不命中）
##                                    与行进方向单位向量（Vector2.ZERO=未观测）
##   bullet_d / bullet_away    最近敌弹距离与远离方向（无弹 d=INF）
##   bomber_d / bomber_away    最近已点燃自爆虫「距离-爆炸半径」（负=炸圈内）与远离方向
##   charge_perp     冲锋怪前摇侧闪方向（Vector2.ZERO = 无读到的冲锋）
##   melee_d / melee_away      最近近战敌距离与远离方向
##   roll_sample / panic_sample / side_sample   本拍随机采样（调用方 rng 掷出）
## 优先级：横扫条带（必中确定性大伤）> 贴弹 > 爆炸临身 > 冲锋临身 > 近战贴脸 panic。
## 条带翻滚方向 = 逆行进向（条带 12.7px/t 快于翻滚 4.3px/t，顺向滚 i-frame 13t 内
## 会被追上；迎面穿越让合拢 17px/t 在触发距 ~126px 下第 ~7 拍过身，i-frame 覆盖）。
## 返回 {do: bool, dir: Vector2}。
static func roll_decision(ctx: Dictionary) -> Dictionary:
	if not bool(ctx.get("roll_ready", false)):
		return {"do": false, "dir": Vector2.ZERO}
	var roll_sample := float(ctx.get("roll_sample", 0.0))
	var side_sign := 1.0 if float(ctx.get("side_sample", 0.5)) < 0.5 else -1.0
	var band_ticks := float(ctx.get("boss_band_ticks", INF))
	var band_dir: Vector2 = ctx.get("boss_band_dir", Vector2.ZERO)
	if band_ticks <= BOSS_BAND_ROLL_AHEAD_TICKS and band_dir != Vector2.ZERO \
			and roll_sample < BOSS_BAND_ROLL_PROB:
		return {"do": true, "dir": -band_dir.normalized()}
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


# ---------------- m4p-bal-d 武器升级拾取（房清安全态巡视掉落台） ----------------
# 探针归因（两轮门禁 70/70 Boss 房团灭）：bot 只捡红心从不拾武器掉落，全程初始
# 手枪 DPS 12 打 800 HP 藤蔓巨像，而 GDD §15 Boss 数值按「到 Boss 时 DPS ~22」校准
# ——2 倍 DPS 缺口下 90~150s 机制马拉松必死。修法：房清后巡视 LootStation，
# 地面武器严格优于当前较弱槽才拾（空槽必拾），走生产交互缝换装。

const WEAPON_TIE_EPS := 0.001        # DPS 平手判定容差（浮点卫生；「平手不换」契约）


## 地面武器 DPS 口径（m4p-bal-d）：damage × rate，近战同口径（melee.gd try_attack
## 语义：挥击频率由 rate 驱动、单次伤害 = damage，与远程同标尺；range/arc 覆盖差
## 不折算——确定性优先，多弹丸散布/命中率差异同样不折算，披露见提交 body）。
## 行缺键 / damage=0 特殊武器（护盾发生器等）→ 0（永不触发严格优于，保守不换）。
static func ground_weapon_dps(row: Dictionary) -> float:
	var dmg_v: Variant = row.get("damage")
	var rate_v: Variant = row.get("rate")
	var dmg := float(dmg_v) if dmg_v != null else 0.0
	var rate := float(rate_v) if rate_v != null else 0.0
	return dmg * rate


## 当前武器最弱槽下标（m4p-bal-d 预切槽入参）：空槽（{}）视为 -INF DPS（必被选为
## 最弱——生产 equip 填第一个空槽时它就是落点）；平手取先出现者（低下标，确定性）。
## 空数组 → -1。
static func weakest_slot_index(current_weapons: Array) -> int:
	var best := -1
	var best_dps := INF
	for i in current_weapons.size():
		var w: Variant = current_weapons[i]
		var dps := -INF if not (w is Dictionary) or (w as Dictionary).is_empty() \
				else ground_weapon_dps(w)
		if dps < best_dps:
			best_dps = dps
			best = i
	return best


## 武器拾取升级决策（m4p-bal-d；纯函数，同输入必同输出）。
## current_weapons: WeaponRig.slots 形态（GameDB 武器行字典数组；{} = 空槽）。
## 地面武器 DPS（ground_weapon_dps 口径）严格优于当前槽中最弱者 → true（拾取）；
## 平手不换（确定性）；存在空槽或无武器 → true（必拾——生产 equip 填第一个空槽，
## 不顶替任何现有武器）；地面行空（未知 id）→ false（保守不换）。
static func weapon_upgrade_pickup(current_weapons: Array, ground_weapon: Dictionary) -> bool:
	if ground_weapon.is_empty():
		return false
	if current_weapons.is_empty():
		return true
	for w_v: Variant in current_weapons:
		if not (w_v is Dictionary) or (w_v as Dictionary).is_empty():
			return true            # 空槽必拾
	var ground := ground_weapon_dps(ground_weapon)
	var weakest := INF
	for w_v: Variant in current_weapons:
		if w_v is Dictionary and not (w_v as Dictionary).is_empty():
			weakest = minf(weakest, ground_weapon_dps(w_v))
	return ground > weakest + WEAPON_TIE_EPS


## 武器掉落台挑选（m4p-bal-d）：candidates [{id: int, pos: Vector2, row: Dictionary}]，
## 依次过 weapon_upgrade_pickup 过滤，取「地面 DPS 最高」者；DPS 平手（容差内）取
## 最近、再平手取先出现者（确定性）。无合格候选 → -1。
static func weapon_loot_index(candidates: Array, current_weapons: Array,
		pos: Vector2) -> int:
	var best := -1
	var best_dps := -INF
	var best_d := INF
	for i in candidates.size():
		var c: Dictionary = candidates[i]
		var row: Dictionary = c.get("row", {})
		if not weapon_upgrade_pickup(current_weapons, row):
			continue
		var dps := ground_weapon_dps(row)
		var d: float = (c.get("pos", pos) as Vector2).distance_to(pos)
		if dps > best_dps + WEAPON_TIE_EPS \
				or (dps > best_dps - WEAPON_TIE_EPS and d < best_d):
			best_dps = dps
			best_d = d
			best = i
	return best


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
