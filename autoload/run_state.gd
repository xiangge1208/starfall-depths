extends Node
## 全局局状态（m1-t15）：单局的种子激活、楼层推进、蓝晶结算与局内聚合字段。
## 命名规则同既有 autoload（无 class_name，按 autoload 名 "RunState" 引用）。
##
## 分盐契约：所有逻辑随机经 RunState.stream(盐) 派生（= RngSvc.stream(floor_idx, salt)），
## floor_idx 变化即隐式重置各盐流（派生链含楼层）。盐常量：
##   SALT_PROJECTILE("proj_crit") 弹幕命中/暴击掷签（CombatSystem 结算流）
##   SALT_RIG("rig")              武器射击散布（rig/melee 注入流）
##   SALT_DUNGEON("dungeon")      地牢装配
## M2-T1 设施独立盐（M1 终审 ③：原先黑商/雕像/饮料机/层间/事件五处共享
## 掉落盐同种子重派生，首抽相互关联；各自分盐后互不关联）：
##   SALT_SHOP("shop")            商店（进货/黑商，含店内神秘混合掷签）
##   SALT_SHRINE("shrine")        星髓像随机附魔
##   SALT_DRINK("drink")          饮料机神秘混合
##   SALT_INTER_FLOOR("inter_floor") 层间三选一增益
##   SALT_EVENT("event")          楼层事件/房间抽取（宝箱、事件选项等）
##   SALT_FORGE("forge")          熔铸台通用升级随机产物（m2-t25）
##   SALT_ELITE("elite")          精英房词缀楼层递进掷签（m2-audit，§12.3）
##   SALT_TRIAL("trial")          每日试炼因子抽取（M3-R-A；抽取流种子精确复刻
##                                派生链于 run_seed=trial_seed、floor_idx=0，
##                                等价性由 test_trial_system 钉死）
##
## 调用时序契约：**RunState.start_run() 必须先于本局任何地牢构建 / 战斗发生**。
## T7 的 DungeonBuilder.build(seed, floor_idx) 仍是纯函数（rng 内部自派生，签名不变）：
## 其当前种子路径为 RngSvc.setup_run(seed)+stream(floor_idx,"dungeon")，会覆写 RngSvc.run_seed；
## 局流程任务（T23）接入时应以 RunState.run_seed 作为 build 的 seed 入参、且构建后不得再
## 依赖此前缓存的流，或统一改走 RunState.stream(SALT_DUNGEON)——本任务不改 T7 签名。

const SALT_PROJECTILE := "proj_crit"
const SALT_RIG := "rig"
const SALT_DUNGEON := "dungeon"
const SALT_SHOP := "shop"                  # M2-T1 设施独立盐（原五处共享掉落盐已删）
const SALT_SHRINE := "shrine"
const SALT_DRINK := "drink"
const SALT_INTER_FLOOR := "inter_floor"
const SALT_EVENT := "event"
const SALT_FORGE := "forge"                # m2-t25 熔铸台（通用升级掷签独立盐）
const SALT_ELITE := "elite"                # m2-audit 精英房词缀递进（A1 无/A2 一/A3 二）
const SALT_TRIAL := "trial"                # M3-R-A 每日试炼因子抽取（trial_seed 派生链盐）
const FLOOR_GEMS := [60, 120, 200]   # GDD §14.1 每层通过蓝晶结算
## m2-t31 击杀蓝晶档位（GDD §14 允许口径）：精英 +5 / 小 Boss +20 / Boss +50；
## Boss 首杀再 +300（SaveSystem.boss_first_kills 无该 boss 记录时，击杀即标记入档
## 防死亡重试/跨局重刷）。键 = 敌行 guest_kind（A1 嘉宾三档，见 FloorScene.GUEST_SPECS）；
## 真实 Boss 行只有 boss_script 无 guest_kind——死亡路由按同款口径等价归 boss 档。
const KILL_GEMS := {"elite": 5, "miniboss": 20, "boss": 50}
const BOSS_FIRST_KILL_GEMS := 300
const WEAPON_SLOTS := 2              # 双武器位（同 WeaponRig.slots 契约）

var run_seed: int = 0                # 0 = 未开局（各盐流退化为种子 0 的确定序列）
var floor_idx: int = 0
var hero_id: String = ""
var coins: int = 0
var gems: int = 0                    # 本局待结算蓝晶；局外持久余额只存在 SaveSystem
var buffs: Array[String] = []
var weapons: Array[String] = []      # 双槽武器 id（空槽 ""），record_weapon 聚合用
var selected_slot: int = 0           # T15 权威字段：当前武器槽
## 兼容旧 HUD/测试的历史字段名；读写都代理到 selected_slot，避免双份状态漂移。
var current_slot: int:
	get:
		return selected_slot
	set(value):
		selected_slot = value
var kills: int = 0
var rooms_cleared: int = 0
var run_time_frames: int = 0         # 物理帧计（60/s）
var pending_investment: int = 0      # 乞丐事件接缝（T19 规格）
var beggar_paid_floor: int = 0       # 乞丐付款层号（T19 declare-only；0 = 未付；返还消费归 T20 跨层）
var star_spring_used: bool = false   # 星髓泉每局一次守卫（T19 declare-only；start_run 重置在整合任务接线）
var forge_upgrades: int = 0          # 本局熔铸通用升级已用次数（m2-t25；上限 ForgeLogic.UPGRADE_LIMIT_PER_RUN）
var last_chosen_hero: String = ""    # 与 HeroSelect.last_chosen 静态暂存同口径（T11 接缝）
## M3-R-A 试炼因子修改器（单点注入）：全系统消费侧只读本字段（键 = trials.json mods
## 白名单），禁止散读 data/trials.json。普通局恒空 {}；试炼局由 start_trial_run
## 注入当日两因子 mods 的合并（键互不相交，见 TrialSystem.pick_mods）。
var mods: Dictionary = {}
var is_trial_run: bool = false       # M3-R-A 本局是否每日试炼局（种子 = 当日 trial_seed）

func start_run(hero: String) -> void:
	# GDD §9.1「玩家点击时刻」：开局种子允许非确定源——**全代码库仅此处**可用
	# 墙钟/全局随机（RngSvc 头注释的全局 randi 禁令在此豁免）。
	run_seed = hash(Time.get_ticks_usec() ^ randi())
	RngSvc.setup_run(run_seed)
	floor_idx = 1
	hero_id = hero
	last_chosen_hero = hero              # 与 HeroSelect.last_chosen 静态暂存同口径（T11 接缝收编）
	coins = 0
	gems = 0
	buffs.clear()
	weapons = []
	weapons.resize(WEAPON_SLOTS)
	selected_slot = 0
	kills = 0
	rooms_cleared = 0
	run_time_frames = 0
	pending_investment = 0
	beggar_paid_floor = 0
	star_spring_used = false
	forge_upgrades = 0
	mods = {}                            # M3-R-A 试炼 mods 不残留到普通局
	is_trial_run = false

## 每日试炼开局（M3-R-A）：先 start_run（复位全字段 + 消费其复位逻辑）→ 覆写种子为
## 当日 trial_seed 并重新激活 RngSvc → is_trial_run + mods 单点注入（当日两因子 mods
## 按 id 升序合并，TrialSystem.pick_mods）。种子不含角色 id：同日所有人同布局（§2）。
## date_str 由调用方经 TrialSystem.today_date() 取得——全代码库唯一墙钟豁免点
## （试炼入口读系统日期，元游戏调度）；种子写入后一切随机走 RngSvc 种子链。
func start_trial_run(hero: String, date_str: String) -> void:
	start_run(hero)
	var trial := TrialSystem.new()
	run_seed = trial.daily_seed(date_str)
	RngSvc.setup_run(run_seed)
	is_trial_run = true
	mods = trial.pick_mods(date_str)

## 选角钩子（T11 守卫契约：HeroSelect 探测 /root/RunState 后调用）= start_run 的别名：
## 选角即开局——玩家点击选卡时刻就是 GDD §9.1 的种子激活时刻，故此处直接全程启动；
## T23 场景路由只需读 RunState.run_seed / hero_id，无需再补调 start_run。
func select_hero(id: String) -> void:
	start_run(id)

## 楼层推进：floor_idx+1 并按 GDD §14.1 结算蓝晶（过第 N 层在进入 N+1 层时给
## FLOOR_GEMS[min(N-1,2)]：1→2 给 60，2→3 给 120，其后封顶 200）。
## floor_idx 变化即隐式重置各盐流（stream 派生链含楼层）。
## 蓝晶统一入池累积（过层 + 击杀），死亡减半 / 胜利全额时才经 SaveSystem 入档
## （m2-t31 口径：GDD §14「死亡也保留 50%」作用于本局全部待结算蓝晶）。
func next_floor() -> int:
	floor_idx += 1
	gems += FLOOR_GEMS[clampi(floor_idx - 2, 0, FLOOR_GEMS.size() - 1)]
	return floor_idx

## 死亡结算一次性消费：本局待结算蓝晶按 50% 向下取整入账，随后立即归零。
## 把防重放在 RunState 而非单个 DeathSummary 节点，重复面板/重复确认均只能领取一次。
func settle_death_gems() -> int:
	var awarded := int(floor(gems / 2.0))
	gems = 0
	return awarded

## 分盐流：等价 RngSvc.stream(floor_idx, salt)（一致性由 test_run_state 钉死）。
func stream(salt: String) -> RandomNumberGenerator:
	return RngSvc.stream(floor_idx, salt)

func add_kill() -> void:
	kills += 1

## m2-t31 击杀蓝晶便捷入池（FloorScene 死亡路由单点调用）：直接 gems += n，
## 不走层结算；入档时机统一在终局结算（死亡减半 / 胜利全额，GDD §14）。
func add_gems(n: int) -> void:
	gems += n

## m2-t31 击杀蓝晶档位结算：guest_kind ∈ elite/miniboss/boss 按 KILL_GEMS 档位入池；
## boss 再查首杀——SaveSystem.boss_first_kills 无该 boss（按数据行 id，空 id 不标记）
## 记录时 +300 入池并立即标记入档。返回本次实际入池额（无档位/杂兵 = 0）。
func settle_kill_gems(guest_kind: String, row_id: String) -> int:
	var amount := int(KILL_GEMS.get(guest_kind, 0))
	if guest_kind == "boss" and not row_id.is_empty() \
			and SaveSystem.record_boss_first_kill(row_id):
		amount += BOSS_FIRST_KILL_GEMS
	if amount > 0:
		add_gems(amount)
	return amount

func add_room_cleared() -> void:
	rooms_cleared += 1

func add_coins(n: int) -> void:
	coins += n

## 消费金币：不足整额拒绝（false，余额不动）；足额扣减并返回 true。
func spend_coins(n: int) -> bool:
	if coins < n:
		return false
	coins -= n
	return true

func add_buff(id: String) -> void:
	buffs.append(id)

## 局内武器聚合（按槽位记录 id，与 WeaponRig 双槽对齐）；越界槽忽略。
func record_weapon(slot: int, id: String) -> void:
	if slot < 0 or slot >= weapons.size():
		return
	weapons[slot] = id

func _physics_process(_delta: float) -> void:
	_tick_run_time()

## 局时累计：每物理帧 +1（_physics_process 唯一调用路径；测试可直接驱动）。
func _tick_run_time() -> void:
	run_time_frames += 1
