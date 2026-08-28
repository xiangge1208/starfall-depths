extends Node
## 全局局状态（m1-t15）：单局的种子激活、楼层推进、蓝晶结算与局内聚合字段。
## 命名规则同既有 autoload（无 class_name，按 autoload 名 "RunState" 引用）。
##
## 分盐契约：所有逻辑随机经 RunState.stream(盐) 派生（= RngSvc.stream(floor_idx, salt)），
## floor_idx 变化即隐式重置各盐流（派生链含楼层）。盐常量：
##   SALT_PROJECTILE("proj_crit") 弹幕命中/暴击掷签（CombatSystem 结算流）
##   SALT_RIG("rig")              武器射击散布（rig/melee 注入流）
##   SALT_LOOT("loot")            掉落/奖励
##   SALT_DUNGEON("dungeon")      地牢装配
##
## 调用时序契约：**RunState.start_run() 必须先于本局任何地牢构建 / 战斗发生**。
## T7 的 DungeonBuilder.build(seed, floor_idx) 仍是纯函数（rng 内部自派生，签名不变）：
## 其当前种子路径为 RngSvc.setup_run(seed)+stream(floor_idx,"dungeon")，会覆写 RngSvc.run_seed；
## 局流程任务（T23）接入时应以 RunState.run_seed 作为 build 的 seed 入参、且构建后不得再
## 依赖此前缓存的流，或统一改走 RunState.stream(SALT_DUNGEON)——本任务不改 T7 签名。

const SALT_PROJECTILE := "proj_crit"
const SALT_RIG := "rig"
const SALT_LOOT := "loot"
const SALT_DUNGEON := "dungeon"
const FLOOR_GEMS := [60, 120, 200]   # GDD §14.1 每层通过蓝晶结算
const WEAPON_SLOTS := 2              # 双武器位（同 WeaponRig.slots 契约）

var run_seed: int = 0                # 0 = 未开局（各盐流退化为种子 0 的确定序列）
var floor_idx: int = 0
var hero_id: String = ""
var coins: int = 0
var gems: int = 0                    # 蓝晶为 meta 货币（T17），start_run 不重置
var buffs: Array[String] = []
var weapons: Array[String] = []      # 双槽武器 id（空槽 ""），record_weapon 聚合用
var current_slot: int = 0
var kills: int = 0
var rooms_cleared: int = 0
var run_time_frames: int = 0         # 物理帧计（60/s）
var pending_investment: int = 0      # 乞丐事件接缝（T19 规格）
var beggar_paid_floor: int = 0       # 乞丐付款层号（T19 declare-only；0 = 未付；返还消费归 T20 跨层）
var star_spring_used: bool = false   # 星髓泉每局一次守卫（T19 declare-only；start_run 重置在整合任务接线）
var last_chosen_hero: String = ""    # 与 HeroSelect.last_chosen 静态暂存同口径（T11 接缝）

func start_run(hero: String) -> void:
	# GDD §9.1「玩家点击时刻」：开局种子允许非确定源——**全代码库仅此处**可用
	# 墙钟/全局随机（RngSvc 头注释的全局 randi 禁令在此豁免）。
	run_seed = hash(Time.get_ticks_usec()) ^ randi()
	RngSvc.setup_run(run_seed)
	floor_idx = 1
	hero_id = hero
	last_chosen_hero = hero              # 与 HeroSelect.last_chosen 静态暂存同口径（T11 接缝收编）
	coins = 0
	buffs.clear()
	weapons = []
	weapons.resize(WEAPON_SLOTS)
	current_slot = 0
	kills = 0
	rooms_cleared = 0
	run_time_frames = 0
	pending_investment = 0

## 选角钩子（T11 守卫契约：HeroSelect 探测 /root/RunState 后调用）= start_run 的别名：
## 选角即开局——玩家点击选卡时刻就是 GDD §9.1 的种子激活时刻，故此处直接全程启动；
## T23 场景路由只需读 RunState.run_seed / hero_id，无需再补调 start_run。
func select_hero(id: String) -> void:
	start_run(id)

## 楼层推进：floor_idx+1 并按 GDD §14.1 结算蓝晶（过第 N 层在进入 N+1 层时给
## FLOOR_GEMS[min(N-1,2)]：1→2 给 60，2→3 给 120，其后封顶 200）。
## floor_idx 变化即隐式重置各盐流（stream 派生链含楼层）。
func next_floor() -> int:
	floor_idx += 1
	gems += FLOOR_GEMS[clampi(floor_idx - 2, 0, FLOOR_GEMS.size() - 1)]
	return floor_idx

## 分盐流：等价 RngSvc.stream(floor_idx, salt)（一致性由 test_run_state 钉死）。
func stream(salt: String) -> RandomNumberGenerator:
	return RngSvc.stream(floor_idx, salt)

func add_kill() -> void:
	kills += 1

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
